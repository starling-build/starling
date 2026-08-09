// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import DmaBufBridge
import Flutter
import FlutterDRMBridge
import FlutterSwiftBridge
import Foundation
import Glibc
import StarlingRecord

/// Stage B of the NVIDIA-view plan (docs/plans/nv-view.md): runs one
/// per-screen shell as a child process — rendering on its own GPU through
/// GpuDmaBufRenderer's swapchain — and feeds its frames to an externally
/// sourced engine output (fl_drm_view_push_external_frame) instead of a
/// composited window texture. Same socket protocol as
/// LinuxProcessAppManager's launches; deliberately separate from it
/// because nothing here is a window: no texture, no chrome, no dock
/// presence. Input forwarding and the recording tap are the next stages.
final class ExternalScreenShell: @unchecked Sendable {
    private let view: OpaquePointer
    private let outputId: UInt32
    private let logicalWidth: Int32
    private let logicalHeight: Int32
    private let scale: Double
    private let device: String
    private var process: Process?
    private let fdLock = NSLock()
    private var clientFd: Int32 = -1
    /// NVENC session recording THIS screen: frames are the child's own
    /// NVIDIA-resident buffers, encoded on the same GPU — recording never
    /// crosses GPUs. Guarded by recLock; encode runs on the reader thread.
    private let recLock = NSLock()
    private var recorder: NvencEncoder?

    /// Window relay (nv-view.md Stage B "windows on the NV screen"): desktop
    /// windows overlapping this output stream to the child over a second
    /// socket as DmaBufWindowStreamMsg. winLock guards the registry AND
    /// serializes socket writes — callers are the UI thread (placement sync)
    /// and every process app's reader thread (frames).
    private let winLock = NSLock()
    private var winStreamFd: Int32 = -1
    private var relayed: [Int64: RelayedWindow] = [:]   // texId → window
    private var windowKeys: [String: Int32] = [:]       // shell win id → key
    private var nextWindowKey: Int32 = 1

    private struct RelayedWindow {
        var key: Int32
        var id: String        // the shell's window id, for focus/raise
        var x: Float, y: Float, w: Float, h: Float   // CONTENT rect
        var z: Int32
        var focused: Bool
        var fullscreen: Bool  // content covers the rect; no bar to hit
        var title: String
    }

    /// Title-bar drag in flight on the external screen (input thread,
    /// winLock): the shell moves the window; the child just repaints it
    /// at each PLACE.
    private var barDragWinId: String? = nil
    private var barDragLast: (x: Double, y: Double) = (0, 0)

    private enum HitZone: Equatable {
        case content    // inside the app's buffer — forward input
        case bar        // the drawn title bar — drag to move
        case close      // red
        case minimize   // yellow
        case maximize   // green
        case resize(ResizeEdge)  // 6px inside the window bounds
    }

    /// Resize drag in flight (input thread, winLock) — the widget's handle
    /// lifecycle: targetRect snapshot at start, per-event deltas through
    /// resizeWindow, final client configure on release.
    private var resizeDragWinId: String? = nil
    private var resizeDragEdge: ResizeEdge = .bottom

    /// Double-click detection on the drawn title bar (input thread,
    /// winLock): time and window of the last bar down.
    private var barLastDownTime: Double = 0
    private var barLastDownWinId: String = ""

    /// Input targeting for relayed windows (engine input thread, winLock):
    /// the app whose window the current drag started in (pointer capture,
    /// window-widget semantics), and the one that took the last click —
    /// routeKey sends keys there while this screen holds keyboard focus.
    private var pointerTargetTexId: Int64 = -1
    private var keyTargetTexId: Int64 = -1

    /// The app that should receive keys typed at this screen, or nil for
    /// the screen shell's own desktop. UI thread (routeKey).
    var keyboardTargetTexId: Int64? {
        winLock.lock()
        defer { winLock.unlock() }
        return keyTargetTexId >= 0 ? keyTargetTexId : nil
    }

    /// Topmost relayed window containing the point — content area or the
    /// child-drawn chrome above it — with the zone hit. winLock held.
    /// Traffic-light geometry mirrors WindowTitleBar: 12px circles from
    /// x=14, vertically centered in the 38px bar; only close is live here.
    private func hitTestLocked(_ lx: Double, _ ly: Double)
        -> (texId: Int64, win: RelayedWindow, zone: HitZone)? {
        var best: (texId: Int64, win: RelayedWindow, zone: HitZone)? = nil
        for (texId, win) in relayed {
            let inX = lx >= Double(win.x) && lx < Double(win.x + win.w)
            guard inX else { continue }
            let barTop = Double(win.y) - DesktopTheme.kTitleBarHeight
            let inContent = ly >= Double(win.y) && ly < Double(win.y + win.h)
            let inBar = !win.fullscreen && ly >= barTop && ly < Double(win.y)
            guard inContent || inBar else { continue }
            if best == nil || win.z > best!.win.z {
                var zone: HitZone = inContent ? .content : .bar
                // Resize bands first — the widget's handles layer over the
                // chrome too. 6px inside the full bounds, 16px corners.
                if !win.fullscreen {
                    let top = barTop, bottom = Double(win.y + win.h)
                    let left = Double(win.x), right = Double(win.x + win.w)
                    let nearL = lx < left + 6, nearR = lx >= right - 6
                    let nearT = ly < top + 6, nearB = ly >= bottom - 6
                    let cornL = lx < left + 16, cornR = lx >= right - 16
                    let cornT = ly < top + 16, cornB = ly >= bottom - 16
                    if (nearT || nearB) && (cornL || cornR) {
                        zone = .resize(nearT ? (cornL ? .topLeft : .topRight)
                                             : (cornL ? .bottomLeft : .bottomRight))
                    } else if (nearL || nearR) && (cornT || cornB) {
                        zone = .resize(cornT ? (nearL ? .topLeft : .topRight)
                                             : (nearL ? .bottomLeft : .bottomRight))
                    } else if nearT {
                        zone = .resize(.top)
                    } else if nearB {
                        zone = .resize(.bottom)
                    } else if nearL {
                        zone = .resize(.left)
                    } else if nearR {
                        zone = .resize(.right)
                    }
                }
                if case .resize = zone {
                    best = (texId, win, zone)
                    continue
                }
                if inBar {
                    // Circle centers 20/40/60 from the window's left edge
                    // (WindowTitleBar's 14px inset, 12px lights, 8px gaps).
                    let cy = barTop + DesktopTheme.kTitleBarHeight / 2
                    let lights: [(Double, HitZone)] = [
                        (20, .close), (40, .minimize), (60, .maximize),
                    ]
                    for (off, lightZone) in lights {
                        let dx = lx - (Double(win.x) + off), dy = ly - cy
                        if dx * dx + dy * dy <= 81 {  // 9px grab radius
                            zone = lightZone
                            break
                        }
                    }
                }
                best = (texId, win, zone)
            }
        }
        return best
    }

    /// DRM_FORMAT_MOD_LINEAR — every relayable buffer is linear by protocol
    /// (single-bo apps allocate GBM_BO_USE_LINEAR, swapchain front buffers
    /// detile to modifier 0), and the child's zink EGL wants the explicit
    /// modifier rather than an implicit-layout guess.
    private static let modLinear: UInt64 = 0

    init(view: OpaquePointer, outputId: Int, logicalWidth: Int,
         logicalHeight: Int, scale: Double, device: String) {
        self.view = view
        self.outputId = UInt32(outputId)
        self.logicalWidth = Int32(logicalWidth)
        self.logicalHeight = Int32(logicalHeight)
        self.scale = scale
        self.device = device
    }

    func start() {
        Thread.detachNewThread { [self] in run() }
    }

    private func log(_ msg: String) {
        FileHandle.standardError.write(Data(
            "[ScreenShell out=\(outputId)] \(msg)\n".utf8))
    }

    private func run() {
        let sockPath = "/tmp/starling-screen-shell-\(getpid())-\(outputId).sock"
        unlink(sockPath)
        let listenFd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard listenFd >= 0 else {
            log("socket() failed: \(String(cString: strerror(errno)))")
            return
        }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                sockPath.withCString { _ = strncpy(buf, $0, 107) }
            }
        }
        let bound = withUnsafePointer(to: &addr) { ap in
            ap.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Glibc.bind(listenFd, $0, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(listenFd, 1) == 0 else {
            log("bind/listen failed: \(String(cString: strerror(errno)))")
            Glibc.close(listenFd)
            return
        }

        // Window stream: a second socket for relaying desktop windows.
        let winSockPath = "/tmp/starling-screen-shell-\(getpid())-\(outputId)-win.sock"
        unlink(winSockPath)
        var winListenFd: Int32 = -1
        let wfd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        if wfd >= 0 {
            var waddr = sockaddr_un()
            waddr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &waddr.sun_path) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                    winSockPath.withCString { _ = strncpy(buf, $0, 107) }
                }
            }
            let wbound = withUnsafePointer(to: &waddr) { ap in
                ap.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Glibc.bind(wfd, $0, UInt32(MemoryLayout<sockaddr_un>.size))
                }
            }
            if wbound == 0, listen(wfd, 1) == 0 {
                winListenFd = wfd
            } else {
                Glibc.close(wfd)
            }
        }

        let env0 = ProcessInfo.processInfo.environment
        let exe = (env0["FLUTTER_APPS_DIR"] ?? ".") + "/ScreenShellApp"
        var env = env0
        env["FLUTTER_DMABUF_SOCKET"] = sockPath
        if winListenFd >= 0 {
            env["FLUTTER_WINDOW_STREAM_SOCKET"] = winSockPath
        }
        if env["STARLING_TEXT_DEBUG"] != nil {
            env["STARLING_TEXT_DEBUG"] = "2"  // verbose in the child only
        }
        env["STARLING_APP_DRM_DEVICE"] = device
        env["FLUTTER_DRM_DPI"] = String(scale)
        // Same scrub as LinuxProcessAppManager's children: the shell's own
        // GL selection must not leak into the child (zink cannot re-import
        // its own linear dma-buf).
        for k in ["MESA_LOADER_DRIVER_OVERRIDE", "GBM_BACKENDS_PATH",
                  "VK_ICD_FILENAMES", "LD_LIBRARY_PATH"] {
            env.removeValue(forKey: k)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.environment = env
        do {
            try p.run()
        } catch {
            log("spawn \(exe) failed: \(error)")
            Glibc.close(listenFd)
            return
        }
        process = p
        log("spawned \(exe) (pid \(p.processIdentifier)) on \(device)")

        // The child connects the window stream only after its engine runs —
        // accept it off this thread, which the frame loop below needs.
        if winListenFd >= 0 {
            Thread.detachNewThread { [self, winListenFd] in
                let fd = accept(winListenFd, nil, nil)
                Glibc.close(winListenFd)
                unlink(winSockPath)
                guard fd >= 0 else { return }
                winLock.lock()
                winStreamFd = fd
                winLock.unlock()
                log("window stream connected")
                // Deliver the windows already on this output: sync runs on
                // every shell state change, but a freshly idle shell may not
                // change for a while — poke one through the main queue.
                DispatchQueue.main.async { _shellState?.setState {} }
            }
        }

        let clientFd = accept(listenFd, nil, nil)
        Glibc.close(listenFd)
        guard clientFd >= 0 else {
            log("accept failed: \(String(cString: strerror(errno)))")
            return
        }
        fdLock.lock()
        self.clientFd = clientFd
        fdLock.unlock()

        var cfg = DmaBufConfigure(width: logicalWidth, height: logicalHeight,
                                  type: DMABUF_CONFIGURE, _reserved: 0)
        _ = withUnsafePointer(to: &cfg) {
            send(clientFd, $0, MemoryLayout<DmaBufConfigure>.size, 0)
        }

        // Every fd-carrying message is a swapchain front buffer; push it to
        // the external output (which dups) and close ours. Frame signals
        // ('F') carry no information the push didn't already.
        var buf = [UInt8](repeating: 0, count: 128)
        var frames = 0
        while true {
            var fd: Int32 = -1
            let n = dmabuf_recv_with_fd(clientFd, &buf, buf.count, &fd)
            if n <= 0 {
                log("child socket reader exiting: recv=\(n) errno=\(errno)")
                break
            }
            if fd >= 0 && n >= MemoryLayout<DmaBufMeta>.size {
                var meta = DmaBufMeta(width: 0, height: 0, stride: 0, fourcc: 0)
                memcpy(&meta, &buf, MemoryLayout<DmaBufMeta>.size)
                _ = fl_drm_view_push_external_frame(
                    view, outputId, fd, UInt32(meta.stride), 0,
                    meta.fourcc, 0)
                recLock.lock()
                if let enc = recorder {
                    var ts = timespec()
                    clock_gettime(CLOCK_MONOTONIC, &ts)
                    let us = UInt64(ts.tv_sec) * 1_000_000
                        + UInt64(ts.tv_nsec) / 1_000
                    if !enc.encode(fd: fd, stride: UInt32(meta.stride),
                                   offset: 0, fourcc: meta.fourcc,
                                   modifier: 0, timestampUs: us) {
                        log("nvenc encode failed: \(enc.errorOutput)")
                        enc.abort()
                        recorder = nil
                    }
                }
                recLock.unlock()
                Glibc.close(fd)
                frames += 1
                if frames == 1 {
                    log("first frame (\(meta.width)x\(meta.height) " +
                        "fourcc=0x\(String(meta.fourcc, radix: 16)))")
                }
            }
        }
        fdLock.lock()
        self.clientFd = -1
        fdLock.unlock()
        Glibc.close(clientFd)
    }

    /// Start an NVENC recording of this screen; returns the file path.
    func startRecording() -> String? {
        recLock.lock()
        defer { recLock.unlock() }
        if let live = recorder { return live.outputURL.path }
        let physW = Int((Double(logicalWidth) * scale).rounded())
        let physH = Int((Double(logicalHeight) * scale).rounded())
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"
        let dir = RecordingPaths.videosDir(home: home)
        let url = RecordingPaths.outputURL(in: dir, now: Date(),
                                           label: "NVIDIA Screen")
        guard let enc = NvencEncoder(inWidth: physW, inHeight: physH,
                                     width: max(2, physW & ~1),
                                     height: max(2, physH & ~1),
                                     fps: 30, outputURL: url) else {
            log("NvencEncoder open failed")
            return nil
        }
        recorder = enc
        log("recording -> \(url.path)")
        return url.path
    }

    /// Finish the recording; returns the completed file path.
    func stopRecording() -> String? {
        recLock.lock()
        defer { recLock.unlock() }
        guard let enc = recorder else { return nil }
        recorder = nil
        if enc.finish() {
            log("recording finished")
            return enc.outputURL.path
        }
        log("recording finish failed: \(enc.errorOutput)")
        enc.abort()
        return nil
    }

    /// Engine input thread: pointer/scroll landing on this output.
    /// Coordinates arrive output-local physical; the child expects logical.
    func sendInput(phase: Int32, x: Double, y: Double, buttons: Int64,
                   scrollDx: Double, scrollDy: Double) {
        fdLock.lock()
        let fd = clientFd
        fdLock.unlock()
        guard fd >= 0 else { return }
        let lx = x / scale
        let ly = y / scale
        if ProcessInfo.processInfo.environment["STARLING_SWAPCHAIN_DEBUG"] == "1",
           phase == 1 || phase == 2 {
            log("fwd phase=\(phase) phys=(\(x),\(y)) /\(scale) -> (\(lx),\(ly))")
        }

        // Windows composited on this screen get their input back — the
        // shell stays the window manager; the child only draws them. A
        // drag belongs to the window it started in (pointer capture, the
        // window widget's semantics), and the last click decides where
        // routeKey sends keys while this screen holds the keyboard.
        //
        // A title-bar drag in flight consumes everything: the shell moves
        // the window (main-queue hop, the hotplug path's cross-thread
        // setState precedent) and the new rect returns to the child as a
        // PLACE on the next sync.
        winLock.lock()
        if let dragId = barDragWinId {
            if phase == 1, buttons == 0 {
                barDragWinId = nil
                winLock.unlock()
                return
            }
            let dx = lx - barDragLast.x
            let dy = ly - barDragLast.y
            barDragLast = (lx, ly)
            winLock.unlock()
            if dx != 0 || dy != 0 {
                DispatchQueue.main.async {
                    _shellState?.setState {
                        _shellState?.windowManager.moveWindowByDelta(
                            dragId, delta: Offset(dx, dy))
                    }
                }
            }
            return
        }
        if let dragId = resizeDragWinId {
            let edge = resizeDragEdge
            if phase == 1, buttons == 0 {
                resizeDragWinId = nil
                winLock.unlock()
                // Release: reconfigure the client from the rect the drag
                // landed on — the widget handles' onResizeDragEnd contract.
                DispatchQueue.main.async {
                    guard let wm = _shellState?.windowManager,
                          let win = wm.windows.first(where: { $0.id == dragId }),
                          let target = win.targetRect else { return }
                    let contentW = target.width
                    let contentH = target.height - DesktopTheme.kTitleBarHeight
                    if contentW > 0 && contentH > 0 {
                        win.onResizeComplete?(contentW, contentH)
                    }
                }
                return
            }
            let dx = lx - barDragLast.x
            let dy = ly - barDragLast.y
            barDragLast = (lx, ly)
            winLock.unlock()
            if dx != 0 || dy != 0 {
                DispatchQueue.main.async {
                    _shellState?.setState {
                        _shellState?.windowManager.resizeWindow(
                            dragId, edge: edge, delta: Offset(dx, dy))
                    }
                }
            }
            return
        }
        var target: (texId: Int64, win: RelayedWindow)? = nil
        var chrome: (texId: Int64, win: RelayedWindow, zone: HitZone)? = nil
        if pointerTargetTexId >= 0 {
            if let win = relayed[pointerTargetTexId] {
                target = (pointerTargetTexId, win)
            }
        } else if let hit = hitTestLocked(lx, ly) {
            if hit.zone == .content {
                target = (hit.texId, hit.win)
            } else {
                chrome = hit
            }
        }
        if phase == 2 {  // kDown claims capture and the key target
            pointerTargetTexId = target?.texId ?? -1
            // The key target follows any click on the window, chrome
            // included; a desktop click clears it.
            keyTargetTexId = target?.texId ?? chrome?.texId ?? -1
            if let c = chrome, case .resize(let edge) = c.zone {
                resizeDragWinId = c.win.id
                resizeDragEdge = edge
                barDragLast = (lx, ly)
                let winId = c.win.id
                DispatchQueue.main.async {
                    // Snapshot for delta accumulation, the handles'
                    // onResizeDragStart contract.
                    guard let wm = _shellState?.windowManager,
                          let win = wm.windows.first(where: { $0.id == winId })
                    else { return }
                    win.targetRect = win.rect
                }
            }
            if let c = chrome, c.zone == .bar {
                // Second bar down on the same window within the threshold is
                // a double-click: maximize-toggle, no drag (the widget's
                // kDoubleTapThreshold and behavior).
                var ts = timespec()
                clock_gettime(CLOCK_MONOTONIC, &ts)
                let now = Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
                if now - barLastDownTime < 0.4, barLastDownWinId == c.win.id {
                    barLastDownTime = 0
                    let winId = c.win.id
                    DispatchQueue.main.async {
                        _shellState?.requestWindowTitleBarDoubleTap(winId)
                    }
                } else {
                    barLastDownTime = now
                    barLastDownWinId = c.win.id
                    barDragWinId = c.win.id
                    barDragLast = (lx, ly)
                }
            }
        }
        if phase == 1, buttons == 0 {  // last button up releases capture
            pointerTargetTexId = -1
        }
        winLock.unlock()
        if phase == 2, let winId = (target?.win ?? chrome?.win)?.id {
            // Focus and raise, as any click on a window does. Hopped to the
            // main queue: this is the engine input thread, and the GCD main
            // queue drains on the shell's own loop (the hotplug path makes
            // the same cross-thread setState). The z bump flows back to the
            // child as a PLACE on the next sync.
            DispatchQueue.main.async {
                _shellState?.setState {
                    _shellState?.windowManager.bringToFront(winId)
                }
            }
        }
        if phase == 2, let c = chrome,
           c.zone == .close || c.zone == .minimize || c.zone == .maximize {
            let winId = c.win.id
            let zone = c.zone
            DispatchQueue.main.async {
                switch zone {
                case .close: _shellState?.requestWindowClose(winId)
                case .minimize: _shellState?.requestWindowMinimize(winId)
                case .maximize: _shellState?.requestWindowMaximize(winId)
                default: break
                }
            }
            return
        }
        if chrome != nil { return }  // chrome swallows what it doesn't use
        if let (texId, win) = target {
            let wx = lx - Double(win.x)
            let wy = ly - Double(win.y)
            if scrollDx != 0 || scrollDy != 0 {
                linuxProcessAppManager?.sendScrollEventRelay(
                    texId: texId, x: wx, y: wy, dx: scrollDx, dy: scrollDy)
            } else {
                linuxProcessAppManager?.sendPointerEventRelay(
                    texId: texId, phase: phase, x: wx, y: wy, buttons: buttons)
            }
            return
        }

        var event: DmaBufInputEvent
        if scrollDx != 0 || scrollDy != 0 {
            let bits = UInt64(Float(scrollDx).bitPattern)
                | (UInt64(Float(scrollDy).bitPattern) << 32)
            event = DmaBufInputEvent(x: lx, y: ly,
                                     buttons: Int64(bitPattern: bits),
                                     type: Int32(DMABUF_INPUT_SCROLL),
                                     phase: 0)
        } else {
            event = DmaBufInputEvent(x: lx, y: ly, buttons: buttons,
                                     type: Int32(DMABUF_INPUT_POINTER),
                                     phase: phase)
        }
        _ = withUnsafePointer(to: &event) {
            send(fd, $0, MemoryLayout<DmaBufInputEvent>.size, Int32(MSG_NOSIGNAL))
        }
    }

    // MARK: - Window relay

    /// Reconcile the set of process-app windows overlapping this output.
    /// UI thread, on every shell state change (the SecondaryOutputScreen
    /// cadence). Placement is output-local logical; z is bottom-most first.
    /// A window ENTERING the output gets its app's latest buffer as an
    /// immediate FRAME — an idle app sends no frames, and a window that
    /// only appears on its next repaint reads as "drag lost it".
    func syncWindows(
        _ entries: [(id: String, texId: Int64, x: Double, y: Double,
                     w: Double, h: Double, z: Int, title: String,
                     focused: Bool, fullscreen: Bool)]) {
        winLock.lock()
        guard winStreamFd >= 0 else {
            winLock.unlock()
            return
        }
        var seen = Set<Int64>()
        var frames: [(texId: Int64, msg: DmaBufWindowStreamMsg)] = []
        for e in entries {
            seen.insert(e.texId)
            let key: Int32
            if let k = windowKeys[e.id] {
                key = k
            } else {
                key = nextWindowKey
                nextWindowKey += 1
                windowKeys[e.id] = key
            }
            let win = RelayedWindow(
                key: key, id: e.id, x: Float(e.x), y: Float(e.y),
                w: Float(e.w), h: Float(e.h), z: Int32(e.z),
                focused: e.focused, fullscreen: e.fullscreen, title: e.title)
            if let old = relayed[e.texId] {
                if old.x != win.x || old.y != win.y || old.w != win.w
                    || old.h != win.h || old.z != win.z
                    || old.focused != win.focused
                    || old.fullscreen != win.fullscreen {
                    relayed[e.texId] = win
                    sendLocked(makeMsg(kind: DMABUF_WINSTREAM_PLACE, win), fd: -1)
                }
                if old.title != win.title {
                    relayed[e.texId] = win
                    sendTitleLocked(key, win.title)
                }
            } else {
                relayed[e.texId] = win
                sendTitleLocked(key, win.title)
                frames.append((e.texId, makeMsg(kind: DMABUF_WINSTREAM_FRAME, win)))
            }
        }
        for (texId, win) in relayed where !seen.contains(texId) {
            sendLocked(makeMsg(kind: DMABUF_WINSTREAM_REMOVE, win), fd: -1)
            relayed.removeValue(forKey: texId)
        }
        winLock.unlock()
        // The buffer dup takes the process manager's lock — outside ours.
        for (texId, var msg) in frames {
            guard let buf = linuxProcessAppManager?.dupLatestBuffer(texId)
            else { continue }
            msg.buf_w = buf.w
            msg.buf_h = buf.h
            msg.stride = buf.stride
            msg.fourcc = buf.fourcc
            msg.modifier = Self.modLinear
            winLock.lock()
            sendLocked(msg, fd: buf.fd)
            winLock.unlock()
            Glibc.close(buf.fd)
        }
    }

    /// A new buffer for an app's window (its reader thread; fd is borrowed —
    /// sent inline, never kept). No-op unless the window is on this output.
    func relayFrame(texId: Int64, fd: Int32, w: Int32, h: Int32,
                    stride: Int32, fourcc: UInt32) {
        winLock.lock()
        defer { winLock.unlock() }
        guard winStreamFd >= 0, let win = relayed[texId] else { return }
        var msg = makeMsg(kind: DMABUF_WINSTREAM_FRAME, win)
        msg.buf_w = w
        msg.buf_h = h
        msg.stride = stride
        msg.fourcc = fourcc
        msg.modifier = Self.modLinear
        sendLocked(msg, fd: fd)
    }

    /// An app repainted its single buffer in place (frame signal).
    func relayDamage(texId: Int64) {
        winLock.lock()
        defer { winLock.unlock() }
        guard winStreamFd >= 0, let win = relayed[texId] else { return }
        sendLocked(makeMsg(kind: DMABUF_WINSTREAM_DAMAGE, win), fd: -1)
    }

    private func makeMsg(kind: Int32, _ win: RelayedWindow) -> DmaBufWindowStreamMsg {
        var msg = DmaBufWindowStreamMsg()
        msg.kind = kind
        msg.window = win.key
        msg.x = win.x
        msg.y = win.y
        msg.w = win.w
        msg.h = win.h
        msg.z = win.z
        msg.flags = (win.focused ? UInt32(DMABUF_WINFLAG_FOCUSED) : 0)
            | (win.fullscreen ? UInt32(DMABUF_WINFLAG_FULLSCREEN) : 0)
        msg.modifier = Self.modLinear
        return msg
    }

    /// winLock must be held. The title travels 8 UTF-8 bytes per message
    /// (the DMABUF_DISPLAY_NAME pattern); chunk 0 starts a fresh title, so
    /// an empty title is one zero-length chunk.
    private func sendTitleLocked(_ key: Int32, _ title: String) {
        let bytes = Array(title.utf8.prefix(256))
        var idx: Int32 = 0
        var off = 0
        repeat {
            var chunk: UInt64 = 0
            var i = 0
            while i < 8 && off + i < bytes.count {
                chunk |= UInt64(bytes[off + i]) << (8 * i)
                i += 1
            }
            var msg = DmaBufWindowStreamMsg()
            msg.kind = Int32(DMABUF_WINSTREAM_TITLE)
            msg.window = key
            msg.z = idx
            msg.buf_w = Int32(bytes.count)
            msg.modifier = chunk
            sendLocked(msg, fd: -1)
            idx += 1
            off += 8
        } while off < bytes.count
    }

    /// winLock must be held. fd >= 0 rides along via SCM_RIGHTS.
    private func sendLocked(_ msg: DmaBufWindowStreamMsg, fd: Int32) {
        var m = msg
        if fd >= 0 {
            _ = withUnsafePointer(to: &m) {
                dmabuf_send_fd(winStreamFd, fd, $0,
                               MemoryLayout<DmaBufWindowStreamMsg>.size)
            }
        } else {
            _ = withUnsafePointer(to: &m) {
                send(winStreamFd, $0, MemoryLayout<DmaBufWindowStreamMsg>.size,
                     Int32(MSG_NOSIGNAL))
            }
        }
    }

    /// Keyboard input while this screen holds output-level key focus (see
    /// externalScreenKeyFocus). Same encoding as LinuxProcessAppManager's
    /// key forwarding: x/y carry KeyData's physical HID code and logical
    /// keysym, buttons the Unicode scalar (0 = none), phase 0/1/2 for
    /// down/up/repeat. The child routes it through FlutterEngineSendKeyEvent,
    /// so it takes the same keydata path as native input.
    func sendKey(physical: Int64, logical: Int64, character: UInt32,
                 phase: Int32) {
        fdLock.lock()
        let fd = clientFd
        fdLock.unlock()
        guard fd >= 0 else { return }
        var event = DmaBufInputEvent(x: Double(physical), y: Double(logical),
                                     buttons: Int64(character),
                                     type: Int32(DMABUF_INPUT_KEY),
                                     phase: phase)
        _ = withUnsafePointer(to: &event) {
            send(fd, $0, MemoryLayout<DmaBufInputEvent>.size, Int32(MSG_NOSIGNAL))
        }
    }
}
