// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import FlutterEmbedderBridge
import RdpServer
import Flutter
import FlutterSwiftBridge
import SwiftRuntime

// The RDP connection as the display: `DesktopShellApp --rdp`.
//
// No DRM, no seat, no libinput — the acceptance test from docs/WSL.md is that
// this starts with /dev/dri absent, which is what makes the desktop run in
// WSL, a container, or a cloud VM. The engine renders through a surfaceless
// EGL context into an FBO; `present` reads that back and hands it to the RDP
// encoder; the client's pointer drives the engine directly.
//
// Rendering is GL rather than the software renderer on purpose: it costs one
// C file and keeps the entire existing compositor stack — external textures,
// the SHM upload path, the shaders — working exactly as it does on DRM.
// Which GPU (if any) is behind it is Mesa's business; in WSL that is llvmpipe
// unless GALLIUM_DRIVER=d3d12 is set. See docs/plans/rdp-wsl.md.

/// Live for the process; the engine's C callbacks reach these without a
/// user_data round trip, and there is exactly one display-mode session.
nonisolated(unsafe) var rdpEgl: OpaquePointer? = nil
nonisolated(unsafe) var rdpDisplayService: RdpDisplayService? = nil
nonisolated(unsafe) private var rdpPointer: RdpPointer? = nil
nonisolated(unsafe) private var rdpKeyboard: RdpKeyboard? = nil
nonisolated(unsafe) private var rdpEngine: OpaquePointer? = nil

/// Size a client negotiated but the raster thread has not applied yet. The
/// FBO can only be resized where the context is current, so the change is
/// parked here and picked up by make_current.
nonisolated(unsafe) private var rdpPendingSize: (w: UInt32, h: UInt32)? = nil
private let rdpSizeLock = NSLock()

func runRdpDisplay() -> Never {
    let env = ProcessInfo.processInfo.environment

    // Fallback geometry until a client says otherwise. The desktop runs with
    // nobody connected — a client attaching renegotiates, as plugging in a
    // monitor would.
    var width: UInt32 = 1920
    var height: UInt32 = 1080
    if let spec = env["STARLING_RDP_SIZE"], !spec.isEmpty {
        let parts = spec.lowercased().split(separator: "x")
        if parts.count == 2, let w = UInt32(parts[0]), let h = UInt32(parts[1]),
           w >= 320, h >= 240 {
            width = w
            height = h
        } else {
            FileHandle.standardError.write(Data(
                "[RdpDisplay] ignoring malformed STARLING_RDP_SIZE=\"\(spec)\"\n".utf8))
        }
    }
    // No EDID exists to derive from, and an RDP client reports nothing
    // trustworthy about physical size — so scale is policy, never derived.
    let scale = env["STARLING_RDP_SCALE"].flatMap { Double($0) } ?? 1.0
    currentShellDpi = scale

    guard let egl = rdp_egl_create(width, height) else {
        FileHandle.standardError.write(Data(
            "[RdpDisplay] surfaceless EGL unavailable — cannot start\n".utf8))
        exit(1)
    }
    rdpEgl = egl

    let service = RdpDisplayService()
    rdpDisplayService = service
    let pointer = RdpPointer()
    rdpPointer = pointer
    let keyboard = RdpKeyboard()
    rdpKeyboard = keyboard

    guard service.start(defaultWidth: width, defaultHeight: height) else {
        FileHandle.standardError.write(Data(
            "[RdpDisplay] listener failed — cannot start\n".utf8))
        exit(1)
    }

    displayLayout = DisplayLayout.build(
        physicalWidth: Int(width), physicalHeight: Int(height),
        scale: scale, refreshMhz: 60000, name: "rdp")

    runApp(
        MacosApp(
            themeMode: .dark,
            home: DesktopShell(),
            title: "Desktop Shell"
        )
    )
    var callbacks = createRuntimeCallbacks()

    var rendererConfig = FlutterRendererConfig()
    rendererConfig.type = kOpenGL
    rendererConfig.open_gl.struct_size =
        MemoryLayout<FlutterOpenGLRendererConfig>.size
    rendererConfig.open_gl.make_current = { _ in
        guard let e = rdpEgl else { return false }
        if rdp_egl_make_current(e) == 0 { return false }
        // Apply a pending client resize here: this is the one place the
        // context is guaranteed current, which an FBO resize requires.
        rdpSizeLock.lock()
        let pending = rdpPendingSize
        rdpPendingSize = nil
        rdpSizeLock.unlock()
        if let p = pending {
            if rdp_egl_resize(e, p.w, p.h) == 0 {
                FileHandle.standardError.write(Data(
                    "[RdpDisplay] resize to \(p.w)x\(p.h) failed\n".utf8))
            }
        }
        return true
    }
    rendererConfig.open_gl.clear_current = { _ in
        guard let e = rdpEgl else { return false }
        return rdp_egl_clear_current(e) != 0
    }
    rendererConfig.open_gl.make_resource_current = { _ in
        guard let e = rdpEgl else { return false }
        return rdp_egl_make_resource_current(e) != 0
    }
    rendererConfig.open_gl.fbo_callback = { _ in
        guard let e = rdpEgl else { return 0 }
        return rdp_egl_fbo(e)
    }
    // The FBO can change under us when a client reconnects at another size,
    // so the engine must ask again after every present.
    rendererConfig.open_gl.fbo_reset_after_present = true
    rendererConfig.open_gl.gl_proc_resolver = { _, name in
        guard let name else { return nil }
        return rdp_egl_get_proc_address(name)
    }
    rendererConfig.open_gl.present = { _ in
        guard let e = rdpEgl, let svc = rdpDisplayService else { return false }
        // Raster thread. Skip the readback entirely when nobody is attached
        // or the rate cap has not elapsed — the pixels would only be thrown
        // away, and this thread is the desktop's pipeline.
        guard svc.wantsFrame(), var slot = svc.acquireBuffer() else {
            return true
        }
        let ok = slot.buf.withUnsafeMutableBufferPointer { p -> Bool in
            rdp_egl_read_frame(e, p.baseAddress, p.count) != 0
        }
        if ok { svc.submit(slot.buf) }
        return true
    }

    var args = FlutterProjectArgs()
    args.struct_size = MemoryLayout<FlutterProjectArgs>.size
    let engineOutDir = env["FLUTTER_ENGINE_OUT"]
        ?? "../engine/src/out/host_debug"
    let assetsPath = strdup("\(engineOutDir)/flutter_assets")!
    let icuPath = strdup("\(engineOutDir)/icudtl.dat")!
    args.assets_path = UnsafePointer(assetsPath)
    args.icu_data_path = UnsafePointer(icuPath)

    let argv0 = strdup("DesktopShellApp")!
    let argv1 = strdup("--enable-impeller=false")!
    let argvBuf = UnsafeMutableBufferPointer<UnsafePointer<CChar>?>
        .allocate(capacity: 3)
    argvBuf[0] = UnsafePointer(argv0)
    argvBuf[1] = UnsafePointer(argv1)
    argvBuf[2] = nil
    args.command_line_argc = 2
    args.command_line_argv = UnsafePointer(argvBuf.baseAddress!)

    var engine: OpaquePointer? = nil
    let initResult = withUnsafeMutablePointer(to: &callbacks) { cbPtr in
        FlutterEngineInitializeSwift(
            Int(FLUTTER_ENGINE_VERSION), &rendererConfig, &args, nil,
            UnsafeRawPointer(cbPtr), &engine)
    }
    guard initResult == kSuccess, let engine = engine else {
        fatalError("[RdpDisplay] FlutterEngineInitializeSwift failed")
    }
    guard FlutterEngineRunInitializedSwift(engine) == kSuccess else {
        fatalError("[RdpDisplay] FlutterEngineRunInitializedSwift failed")
    }
    rdpEngine = engine
    pointer.attach(engine: engine)
    keyboard.attach(engine: engine)

    sendRdpMetrics(engine: engine, width: width, height: height, scale: scale)

    // A client connecting is this mode's hotplug event: adopt its size, then
    // force a composite so it sees the desktop immediately rather than after
    // the next thing that happens to change.
    service.onSizeNegotiated = { w, h in
        rdpSizeLock.lock()
        rdpPendingSize = (w, h)
        rdpSizeLock.unlock()
        displayLayout = DisplayLayout.build(
            physicalWidth: Int(w), physicalHeight: Int(h),
            scale: scale, refreshMhz: 60000, name: "rdp")
        sendRdpMetrics(engine: engine, width: w, height: h, scale: scale)
        Flutter._forceNextComposite = true
        PlatformDispatcher.instance.scheduleFrame()
    }
    service.onPointer = { x, y, buttons, wdx, wdy in
        rdpPointer?.handle(x: x, y: y, buttons: buttons,
                           wheelDX: wdx, wheelDY: wdy)
    }
    service.onKey = { scancode, extended, down in
        rdpKeyboard?.handle(scancode: scancode, extended: extended, down: down)
    }
    service.onKeySync = { flags in
        rdpKeyboard?.sync(toggleFlags: flags)
    }
    service.onClientGone = {
        // Release both devices: a client that disappears mid-drag or
        // mid-chord must not leave a button or a modifier stuck down.
        rdpPointer?.reset()
        rdpKeyboard?.releaseAll()
    }

    PlatformDispatcher.instance.scheduleFrame()
    Foundation.RunLoop.main.run()
    exit(0)
}

private func sendRdpMetrics(engine: OpaquePointer, width: UInt32,
                            height: UInt32, scale: Double) {
    var metrics = FlutterWindowMetricsEvent()
    metrics.struct_size = MemoryLayout<FlutterWindowMetricsEvent>.size
    metrics.width = Int(width)
    metrics.height = Int(height)
    metrics.pixel_ratio = scale
    metrics.view_id = 0
    FlutterEngineSendWindowMetricsEvent(engine, &metrics)
}
#endif
