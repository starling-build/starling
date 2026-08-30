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

/// Dispatch sources standing in for the DRM loop's epoll registrations.
/// Held here because a released source stops firing.
nonisolated(unsafe) private var rdpWaylandSource: DispatchSourceRead? = nil
nonisolated(unsafe) private var rdpWakeupSource: DispatchSourceRead? = nil

func runRdpDisplay() -> Never {
    let env = ProcessInfo.processInfo.environment

    // The style and appearance the user picked, before anything is built.
    //
    // These used to be restored in `runDRM` only, so display mode always came
    // up macOS-and-default no matter what the user had chosen — and display
    // mode is the WHOLE product wherever there is no DRM device, which is to
    // say every WSL box. Style first: it decides which dark/light pair the
    // appearance then resolves against.
    _DesktopShellState.loadPersistedStyle()
    _DesktopShellState.loadPersistedAppearance()

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

    // The texture registry resolves GL entry points through our context
    // rather than the DRM view's. Created before the engine because the
    // renderer config's external-texture callback reaches it.
    let textureRegistry = LinuxTextureRegistry()
    textureRegistry.glProcAddressResolver = { name in
        return rdp_egl_get_proc_address(name)
    }
    drmTextureRegistry = textureRegistry

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
    // Client windows composite through here, exactly as they do on DRM —
    // the registry's GL paths are unchanged, they just run on a surfaceless
    // context. This callback is why display mode is worth building on GL:
    // under the software renderer the embedder resolves no external
    // textures at all and every client window paints nothing.
    rendererConfig.open_gl.gl_external_texture_frame_callback = {
        _, textureId, width, height, textureOut in
        guard let registry = drmTextureRegistry, let out = textureOut else {
            return false
        }
        return registry.populateTexture(id: textureId, width: Int(width),
                                        height: Int(height), textureOut: out)
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
        // A push to the client is this mode's page flip, and Wayland clients
        // are paced off it exactly as they are off a real one on DRM —
        // otherwise frame callbacks never fire and every client stalls after
        // its first buffer. Marshalled to main, where the Wayland event loop
        // lives here (the DRM path calls it on its platform thread, which is
        // the same thread as its event loop, for the same reason).
        let now = UInt64(DispatchTime.now().uptimeNanoseconds)
        DispatchQueue.main.async {
            waylandIntegration?.handlePresent(flipTimeNs: now,
                                              refreshNs: 16_666_667,
                                              outputId: 0)
        }
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
    // A present the rate cap swallowed re-asks for a frame through here —
    // see wantsFrame. Wired only now, engine in hand, so a cap hit during
    // startup simply drops (nothing to catch up TO before first paint).
    //
    // ScheduleFrame alone is NOT enough: the Adapter skips compositing when
    // no widget is dirty, so the scheduled frame builds, finds nothing to
    // do, and never reaches raster or present — measured as exactly this
    // sequence after a maximise: the old-content frame pushed, the
    // new-content frame capped, the catch-up firing, and then silence.
    // Force the composite the same way the screenshot path does.
    service.scheduleCatchUp = {
        Flutter._forceNextComposite = true
        if let e = rdpEngine { FlutterEngineScheduleFrame(e) }
    }
    pointer.attach(engine: engine)
    keyboard.attach(engine: engine)

    // ─── Compositor services ─────────────────────────────────────────────
    // Everything below needs a running engine, not a DRM view. X11 is
    // deliberately absent (Wayland only, per CLAUDE.md), and so is the
    // dma-buf advertisement: without /dev/dri nothing can export one, and
    // not offering linux-dmabuf is what makes clients pick wl_shm by
    // themselves instead of failing.
    let externalApps = LinuxExternalAppManager(engine: engine,
                                               textureRegistry: textureRegistry)
    linuxExternalAppManager = externalApps
    let processApps = LinuxProcessAppManager(engine: engine,
                                             textureRegistry: textureRegistry)
    FrameCallbackScheduler.shared.register(processApps) { [weak processApps] in
        processApps?.tick()
    }
    linuxProcessAppManager = processApps
    processApps.onThemeChangeRequested = { dark in
        _shellState?._setAppearance(dark: dark)
    }
    processApps.onLayoutChangeRequested = { tiling in
        _shellState?._setTiling(tiling)
    }
    processApps.onWallpaperChangeRequested = { preset in
        _shellState?._setWallpaper(preset)
    }

    let wayland = WaylandIntegration(engine: engine,
                                     textureRegistry: textureRegistry)
    wayland.start(screenWidth: Int(width), screenHeight: Int(height),
                  scale: max(1, Int(scale)), shellDpi: scale,
                  refreshMhz: 60000)
    // The compositor's C side records its event-loop thread on first dispatch
    // and warns about every call from anywhere else. On DRM that invariant
    // holds for free: the engine's GCD integration drains the main queue ON
    // the platform thread, so main queue, epoll loop and Wayland dispatch are
    // all one thread. Display mode has no such integration — the scheduler
    // fires on the engine's UI thread — so the hop is explicit here, and
    // every server call funnels through the main queue with the fd sources.
    FrameCallbackScheduler.shared.register(wayland) {
        // Reaches the integration through the global rather than capturing
        // it, so nothing is sent across the queue boundary.
        DispatchQueue.main.async { waylandIntegration?.tick() }
    }
    waylandIntegration = wayland
    _onWaylandIntegrationReady?()

    // The DRM path hangs these fds off the engine's epoll loop. Here the
    // main queue IS the platform thread, so they become dispatch sources —
    // same single-threaded delivery, no epoll to register with.
    if wayland.serverFd >= 0 {
        let src = DispatchSource.makeReadSource(fileDescriptor: Int32(wayland.serverFd),
                                                queue: .main)
        src.setEventHandler { waylandIntegration?.dispatchEvents() }
        src.resume()
        rdpWaylandSource = src
    }
    if wayland.wakeupReadFd >= 0 {
        let src = DispatchSource.makeReadSource(
            fileDescriptor: Int32(wayland.wakeupReadFd), queue: .main)
        src.setEventHandler { waylandIntegration?.drainWakeupPipe() }
        src.resume()
        rdpWakeupSource = src
    }

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
