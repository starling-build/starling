// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import WaylandServerBridge
import Foundation
#if os(Linux)
import DmaBufBridge
import FlutterEmbedderBridge
import Glibc
import Dispatch
#endif

// MARK: - Thread-Safe Queue

/// Thread-safe mutable box for sharing state across threads.
private final class AtomicBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
    init(_ value: T) { self._value = value }

    /// Atomic read-modify-write — appends must use this, not get+set
    /// (two lock acquisitions lose updates against a concurrent drain).
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&_value)
    }

    /// Atomically take the current value, leaving `empty` behind.
    func take(_ empty: T) -> T {
        lock.lock(); defer { lock.unlock() }
        let v = _value
        _value = empty
        return v
    }
}

// MARK: - Event / Command Enums

/// Events produced on the platform thread (C callbacks), consumed on the UI thread.
private enum WaylandEvent: @unchecked Sendable {
    case newToplevel(surfaceId: UInt32, clientId: UInt64)
    case surfaceCommit(surfaceId: UInt32, fd: Int32, width: Int, height: Int,
                       stride: Int, fourcc: UInt32, modifier: UInt64,
                       firstCommit: Bool, bufferScale: Int,
                       viewportWidth: Int, viewportHeight: Int)
    /// wl_shm commit. `pixels` is a tightly-packed copy owned by this event —
    /// whoever consumes it must deallocate.
    case shmSurfaceCommit(surfaceId: UInt32, pixels: UnsafeMutableRawPointer,
                          width: Int, height: Int, format: UInt32,
                          firstCommit: Bool, bufferScale: Int,
                          viewportWidth: Int, viewportHeight: Int)
    case toplevelDestroy(surfaceId: UInt32)
    /// A client connection closed. The last moment its clientId means
    /// anything — see WaylandIntegration.onClientDestroyed.
    case clientDestroy(clientId: UInt64)
    case titleChanged(surfaceId: UInt32, title: String)
    case appIdChanged(surfaceId: UInt32, appId: String)
    case newPopup(surfaceId: UInt32, parentSurfaceId: UInt32,
                  x: Int, y: Int, width: Int, height: Int)
    case popupDestroy(surfaceId: UInt32)
    case windowGeometry(surfaceId: UInt32, x: Int, y: Int, width: Int, height: Int)
    case fullscreenRequest(surfaceId: UInt32)
    case unfullscreenRequest(surfaceId: UInt32)
    case cursorShape(shape: UInt32)
    case moveRequest(surfaceId: UInt32)
    case interactiveResizeRequest(surfaceId: UInt32, edges: UInt32)
    /// zwp_text_input_v3 state on the focused surface (cursor rect is
    /// surface-local logical coords).
    case textInputState(surfaceId: UInt32, enabled: Bool,
                        x: Int32, y: Int32, w: Int32, h: Int32)
}

/// Commands produced on the UI thread, executed on the platform thread.
private enum WaylandCommand: @unchecked Sendable {
    case configureToplevel(surfaceId: UInt32, width: Int32, height: Int32)
    case closeToplevel(surfaceId: UInt32)
    case flushClients
    case updateScale(scale: Int32, fractional120: UInt32)
    case setOutputs(outputs: [WaylandOutputDesc])
    case setSurfaceOutputs(surfaceId: UInt32, mask: UInt32, paceMask: UInt32)
    case setSurfaceThrottle(surfaceId: UInt32, intervalMs: UInt32)
    case textInputCommit(text: String)
    case textInputPreedit(text: String, cursor: Int32)
}

// MARK: - WaylandIntegration

/// The only two `wl_shm` formats the compositor advertises (see
/// `wayland_shm.c`). Both are B,G,R,{A,X} in memory on a little-endian host,
/// so ARGB is the only one carrying alpha worth honouring.
private let kShmFormatARGB8888: UInt32 = 0
private let kShmFormatXRGB8888: UInt32 = 1

/// Bridges the Wayland compositor server to DesktopShellApp's window system.
///
/// Thread model:
/// - **Platform thread** (epoll): `wayland_server_dispatch()`, C callbacks queue
///   events into `pendingEvents`, configure commands are executed here.
/// - **UI thread** (onBeginFrame → FrameCallbackScheduler): `tick()` drains
///   queued events and calls DesktopShell callbacks (setState, etc.).
/// - Input forwarding (pointer/keyboard/scroll) uses the C-level deferred pipe
///   and is safe from any thread.
class WaylandIntegration {
    private var server: OpaquePointer?  // WaylandServer*
    let engine: OpaquePointer
    let textureRegistry: LinuxTextureRegistry

    // ─── Surface tracking (UI thread only) ──────────────────────────────

    private var surfaceTextures: [UInt32: Int64] = [:]   // surfaceId → textureId
    private var surfaceWindows: [UInt32: String] = [:]    // surfaceId → windowId
    private var surfaceAppIds: [UInt32: String] = [:]     // surfaceId → xdg app_id
    private var surfacePids: [UInt32: pid_t] = [:]        // surfaceId → client pid
    private var surfaceSizes: [UInt32: (Int, Int)] = [:]  // surfaceId → (width, height) in buffer pixels
    private var surfaceBufferScales: [UInt32: Int] = [:]  // surfaceId → buffer_scale from client
    /// surfaceId → wp_viewporter destination size, when the client set one
    private var surfaceViewportSizes: [UInt32: (Int, Int)] = [:]
    private var surfaceGeometry: [UInt32: (x: Int, y: Int, width: Int, height: Int)] = [:]
    private var lastEmittedGeometry: [UInt32: (x: Int, y: Int, w: Int, h: Int, bufW: Int, bufH: Int)] = [:]
    private var popupSurfaceIds: Set<UInt32> = []
    private var outputScale: Int = 1
    private var shellDpi: Double = 1.0
    private var fractionalScale: Double = 1.0

    // Resize throttling (UI thread only)
    private var lastResizeTime: [UInt32: UInt64] = [:]
    private var pendingResize: [UInt32: (width: Int, height: Int)] = [:]
    private let resizeIntervalNs: UInt64 = 33_000_000  // 33ms (~30fps)

    // ─── Thread-safe queues ─────────────────────────────────────────────

    /// Events from platform thread → UI thread.
    private let pendingEvents = AtomicBox<[WaylandEvent]>([])

    /// Commands from UI thread → platform thread.
    private let pendingCommands = AtomicBox<[WaylandCommand]>([])

    /// Wakeup pipe: UI thread writes to trigger epoll → platform drains commands.
    private(set) var wakeupReadFd: Int32 = -1
    private var wakeupWriteFd: Int32 = -1

    /// When true, dispatch is driven by epoll (DRM mode). When false, tick()
    /// dispatches directly (GLFW mode).
    private var _epollDriven = false

    /// Set by handle* methods on platform thread, cleared by dispatchEvents.
    private var _needsFrame = false

    // ─── Callbacks (set by DesktopShell, called from tick on UI thread) ──

    var onNewWindow: ((_ surfaceId: UInt32, _ textureId: Int, _ title: String, _ clientId: UInt64) -> String)?
    var onWindowDestroyed: ((_ windowId: String) -> Void)?
    /// A client connection went away, so its clientId is now free for reuse
    /// by an unrelated client. Anything the shell keyed on it — agent window
    /// ownership, most of all — must be dropped here, or the next client to
    /// land on the same address inherits it.
    var onClientDestroyed: ((_ clientId: UInt64) -> Void)?
    var onTitleChanged: ((_ windowId: String, _ title: String) -> Void)?
    /// The client's own name for itself (`xdg_toplevel.set_app_id`). This is
    /// how a window is tied back to an installed app — it matches the
    /// `StartupWMClass` in the app's `.desktop` entry, which is what
    /// `app-install` records into the app registry. Nothing else identifies a
    /// window reliably: titles follow the open document.
    var onAppIdChanged: ((_ windowId: String, _ appId: String) -> Void)?
    var onWindowBufferResized: ((_ windowId: String, _ logicalWidth: Int, _ logicalHeight: Int) -> Void)?
    var onPopupBufferResized: ((_ popupId: String, _ logicalWidth: Int, _ logicalHeight: Int, _ geoX: Int, _ geoY: Int) -> Void)?
    var onNewPopup: ((_ surfaceId: UInt32, _ textureId: Int, _ parentSurfaceId: UInt32, _ x: Int, _ y: Int, _ width: Int, _ height: Int) -> String)?
    var onPopupDestroyed: ((_ popupId: String) -> Void)?
    var onWindowGeometryChanged: ((_ windowId: String, _ x: Int, _ y: Int, _ width: Int, _ height: Int, _ bufferLogicalWidth: Int, _ bufferLogicalHeight: Int) -> Void)?
    var onFullscreenRequest: ((_ windowId: String) -> Void)?
    var onUnfullscreenRequest: ((_ windowId: String) -> Void)?
    /// Client-initiated interactive move/resize (xdg_toplevel.move/resize).
    var onMoveRequest: ((_ windowId: String) -> Void)?
    /// Focused Wayland client's text-input state: enabled + cursor rect
    /// (surface-local logical coords). Drives IME routing + panel anchor.
    var onTextInputState: ((_ windowId: String, _ enabled: Bool,
                            _ x: Double, _ y: Double,
                            _ w: Double, _ h: Double) -> Void)?

    /// IME delivery to the focused client's enabled text input (queued to
    /// the server's event-loop thread).
    func sendTextInputCommit(_ text: String) {
        enqueueCommand(.textInputCommit(text: text))
        enqueueCommand(.flushClients)
    }

    func sendTextInputPreedit(_ text: String, cursor: Int32) {
        enqueueCommand(.textInputPreedit(text: text, cursor: cursor))
        enqueueCommand(.flushClients)
    }
    var onInteractiveResizeRequest: ((_ windowId: String, _ edges: UInt32) -> Void)?

    // ─── Init / Lifecycle ───────────────────────────────────────────────

    init(engine: OpaquePointer, textureRegistry: LinuxTextureRegistry) {
        self.engine = engine
        self.textureRegistry = textureRegistry
    }

    deinit {
        stop()
    }

    /// Mark as epoll-driven (DRM mode). Call after registering Wayland fd with epoll.
    func setEpollDriven() {
        _epollDriven = true
    }

    /// Update scale factors at runtime (e.g. from Settings app DPI change).
    func updateScale(_ scale: Int, shellDpi: Double, fractionalScale: Double) {
        outputScale = max(scale, 1)
        self.shellDpi = max(shellDpi, 1.0)
        self.fractionalScale = fractionalScale
        enqueueCommand(.updateScale(scale: Int32(outputScale),
                                     fractional120: UInt32(fractionalScale * 120.0)))
    }

    /// Start the Wayland server. Call after engine is running.
    /// `refreshMhz`: the display's real refresh rate (wl_output.mode +
    /// wp_presentation refresh period); 0 falls back to 60 Hz.
    func start(screenWidth: Int, screenHeight: Int, scale: Int = 1, shellDpi: Double = 1.0,
               refreshMhz: Int = 0) {
        outputScale = max(scale, 1)
        self.shellDpi = max(shellDpi, 1.0)
        self.fractionalScale = max(shellDpi, 1.0)
        var config = WaylandServerConfig()
        config.display_width = Int32(screenWidth)
        config.display_height = Int32(screenHeight)
        config.refresh_mhz = refreshMhz > 0 ? Int32(refreshMhz) : 60000
        config.scale = Int32(scale)

        server = wayland_server_create(&config)
        guard let server = server else { return }

        // The shell usually runs as root (DRM master) while clients run as
        // the login user. AppArmor's wayland interface rule is
        // owner-qualified (`owner /run/user/*/wayland-* rw`), so a
        // root-owned socket is unreachable from confined user apps (snap
        // browsers) even though its mode bits allow it. Hand the socket to
        // the runtime dir's owner so user-session clients can connect.
        if getuid() == 0, let name = socketName {
            let xdg = LoginUser.runtimeDir
            var st = stat()
            if stat(xdg, &st) == 0, st.st_uid != 0 {
                _ = chown(xdg + "/" + name, st.st_uid, st.st_gid)
            }
        }

        wayland_server_update_scale(server, Int32(outputScale), UInt32(fractionalScale * 120.0))

        // Create wakeup pipe for UI→platform command delivery
        var pipeFds: [Int32] = [0, 0]
        if pipe(&pipeFds) == 0 {
            wakeupReadFd = pipeFds[0]
            wakeupWriteFd = pipeFds[1]
            let fl0 = fcntl(wakeupReadFd, F_GETFL, 0)
            fcntl(wakeupReadFd, F_SETFL, fl0 | O_NONBLOCK)
            let fl1 = fcntl(wakeupWriteFd, F_GETFL, 0)
            fcntl(wakeupWriteFd, F_SETFL, fl1 | O_NONBLOCK)
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        wayland_server_on_new_toplevel(server, { (ctx, surfaceId, clientId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleNewToplevel(surfaceId, clientId: clientId)
        }, ctx)

        wayland_server_on_surface_commit(server, { (ctx, surfaceId, fd, w, h, stride, fourcc, modifier, firstCommit, bufferScale) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleSurfaceCommit(surfaceId, fd: fd, width: Int(w), height: Int(h),
                                     stride: Int(stride), fourcc: UInt32(fourcc),
                                     modifier: modifier, firstCommit: firstCommit != 0,
                                     bufferScale: Int(bufferScale))
        }, ctx)

        // Software clients (wl_shm). Without this the compositor's SHM branch
        // finds a NULL callback and silently drops every frame, so the client
        // attaches, damages, commits and gets its buffers released — while the
        // window composites as nothing at all.
        wayland_server_on_shm_surface_commit(server, { (ctx, surfaceId, pixels, w, h, stride, format, firstCommit, bufferScale) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            guard let pixels = pixels else { return }
            this.handleShmSurfaceCommit(surfaceId, pixels: pixels,
                                        width: Int(w), height: Int(h), stride: Int(stride),
                                        format: format, firstCommit: firstCommit != 0,
                                        bufferScale: Int(bufferScale))
        }, ctx)

        wayland_server_on_toplevel_destroy(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleToplevelDestroy(surfaceId)
        }, ctx)

        wayland_server_on_client_destroy(server, { (ctx, clientId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleClientDestroy(clientId)
        }, ctx)

        wayland_server_on_text_input_state(server, { (ctx, surfaceId, enabled, x, y, w, h) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleTextInputState(surfaceId, enabled: enabled != 0,
                                      x: x, y: y, w: w, h: h)
        }, ctx)

        wayland_server_on_title_changed(server, { (ctx, surfaceId, title) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            guard let title = title else { return }
            this.handleTitleChanged(surfaceId, title: String(cString: title))
        }, ctx)

        // Declared in wayland_server.h and fired by wayland_xdg_shell.c since
        // the compositor was written — but never registered here, so every
        // window's app_id was thrown away and the dock had to guess from
        // titles. Same failure shape as the wl_shm commit callback: complete C
        // plumbing, no Swift setter, silent.
        wayland_server_on_app_id_changed(server, { (ctx, surfaceId, appId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            guard let appId = appId else { return }
            this.handleAppIdChanged(surfaceId, appId: String(cString: appId))
        }, ctx)

        wayland_server_on_new_popup(server, { (ctx, surfaceId, parentSurfaceId, x, y, w, h) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleNewPopup(surfaceId, parentSurfaceId: parentSurfaceId,
                                 x: Int(x), y: Int(y), width: Int(w), height: Int(h))
        }, ctx)

        wayland_server_on_popup_destroy(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handlePopupDestroy(surfaceId)
        }, ctx)

        wayland_server_on_window_geometry(server, { (ctx, surfaceId, x, y, w, h) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleWindowGeometry(surfaceId, x: Int(x), y: Int(y),
                                       width: Int(w), height: Int(h))
        }, ctx)

        wayland_server_on_fullscreen_request(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleFullscreenRequest(surfaceId)
        }, ctx)

        wayland_server_on_unfullscreen_request(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleUnfullscreenRequest(surfaceId)
        }, ctx)

        wayland_server_on_cursor_shape(server, { (ctx, shape) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.handleCursorShape(shape)
        }, ctx)

        wayland_server_on_move_request(server, { (ctx, surfaceId) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.moveRequest(surfaceId: surfaceId))
        }, ctx)

        wayland_server_on_interactive_resize_request(server, { (ctx, surfaceId, edges) in
            let this = Unmanaged<WaylandIntegration>.fromOpaque(ctx!).takeUnretainedValue()
            this.queueEvent(.interactiveResizeRequest(surfaceId: surfaceId, edges: edges))
        }, ctx)
    }

    /// Queue an event from a platform-thread C callback for UI-thread tick().
    private func queueEvent(_ event: WaylandEvent) {
        pendingEvents.withLock { $0.append(event) }
        _needsFrame = true
    }

    func stop() {
        if let server = server {
            wayland_server_destroy(server)
            self.server = nil
        }
        if wakeupReadFd >= 0 { Glibc.close(wakeupReadFd); wakeupReadFd = -1 }
        if wakeupWriteFd >= 0 { Glibc.close(wakeupWriteFd); wakeupWriteFd = -1 }
    }

    var serverFd: Int {
        guard let server = server else { return -1 }
        return Int(wayland_server_get_fd(server))
    }

    var socketName: String? {
        guard let server = server else { return nil }
        return String(cString: wayland_server_get_socket_name(server))
    }

    /// True while any client holds a zwp_idle_inhibitor_v1 — Chrome or
    /// Firefox playing video, a slideshow, a player. The shell's screensaver
    /// idle timer treats this as ongoing activity, so a film watched without
    /// touching the mouse doesn't get covered up.
    var idleInhibited: Bool {
        guard let server = server else { return false }
        return wayland_server_idle_inhibited(server) > 0
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Platform Thread: Dispatch + Command Execution
    // ═══════════════════════════════════════════════════════════════════════

    /// Called from DRM epoll when the Wayland fd is readable.
    /// Dispatches protocol events (C callbacks queue into pendingEvents).
    func dispatchEvents() {
        guard let server = server else { return }
        _needsFrame = false
        executePendingCommands()
        wayland_server_dispatch(server)
        if _needsFrame {
            FlutterEngineScheduleFrame(engine)
        }
    }

    /// Called from the DRM per-output present callback (platform thread —
    /// the same thread that dispatches the Wayland event loop) when a page
    /// flip lands on `outputId`. Drives the frame callbacks + presentation
    /// feedback of the clients ON that output off its real vsync — a client
    /// on the 30Hz panel is paced at 30, one on the 90Hz panel at 90.
    func handlePresent(flipTimeNs: UInt64, refreshNs: UInt32, outputId: Int) {
        guard let server = server else { return }
        wayland_server_on_present(server, flipTimeNs, refreshNs,
                                  1 << outputBit(forId: outputId))
    }

    /// Called from DRM epoll when the wakeup pipe is readable.
    /// Drains command queue from the UI thread.
    func drainWakeupPipe() {
        // Consume wakeup bytes
        if wakeupReadFd >= 0 {
            var buf = [UInt8](repeating: 0, count: 64)
            while Glibc.read(wakeupReadFd, &buf, buf.count) > 0 {}
        }
        executePendingCommands()
    }

    /// Execute queued commands on the platform thread.
    private func executePendingCommands() {
        let commands = pendingCommands.take([])
        guard !commands.isEmpty else { return }
        guard let server = server else { return }
        for cmd in commands {
            switch cmd {
            case .configureToplevel(let surfaceId, let w, let h):
                wayland_server_configure_toplevel(server, surfaceId, w, h)
            case .closeToplevel(let surfaceId):
                wayland_server_close_toplevel(server, surfaceId)
            case .flushClients:
                wayland_server_flush_clients(server)
            case .updateScale(let scale, let fractional120):
                wayland_server_update_scale(server, scale, fractional120)
            case .setOutputs(var outputs):
                wayland_server_set_outputs(server, &outputs,
                                           Int32(outputs.count))
            case .setSurfaceOutputs(let surfaceId, let mask, let paceMask):
                wayland_server_surface_set_outputs(server, surfaceId, mask,
                                                   paceMask)
            case .setSurfaceThrottle(let surfaceId, let intervalMs):
                wayland_server_set_surface_throttle(server, surfaceId, intervalMs)
            case .textInputCommit(let text):
                _ = wayland_server_text_input_commit_string(server, text)
            case .textInputPreedit(let text, let cursor):
                _ = wayland_server_text_input_preedit(server, text, cursor)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - UI Thread: Event Processing
    // ═══════════════════════════════════════════════════════════════════════

    /// Every client frame, by texture id — the agent broker's await_settled
    /// is the consumer. Its own frame bookkeeping only ever saw first-party
    /// DMA-BUF children, so for a Wayland window "has the app caught up yet"
    /// had nothing to measure.
    var onSurfaceFrame: ((Int64) -> Void)?

    /// Called from FrameCallbackScheduler on the UI thread.
    /// Drains queued events from the platform thread and processes them.
    func tick() {
        // In GLFW mode (no epoll), dispatch + execute commands here.
        if !_epollDriven, let server = server {
            executePendingCommands()
            wayland_server_dispatch(server)
        }

        let events = pendingEvents.take([])
        guard !events.isEmpty else { return }

        for event in events {
            switch event {
            case .newToplevel(let surfaceId, let clientId):
                processNewToplevel(surfaceId, clientId: clientId)
            case .surfaceCommit(let surfaceId, let fd, let width, let height,
                                let stride, let fourcc, let modifier,
                                let firstCommit, let bufferScale,
                                let vpW, let vpH):
                processSurfaceCommit(surfaceId, fd: fd, width: width, height: height,
                                     stride: stride, fourcc: fourcc, modifier: modifier,
                                     firstCommit: firstCommit, bufferScale: bufferScale,
                                     viewportWidth: vpW, viewportHeight: vpH)
            case .shmSurfaceCommit(let surfaceId, let pixels, let width, let height,
                                   let format, let firstCommit, let bufferScale,
                                   let vpW, let vpH):
                processShmSurfaceCommit(surfaceId, pixels: pixels,
                                        width: width, height: height, format: format,
                                        firstCommit: firstCommit, bufferScale: bufferScale,
                                        viewportWidth: vpW, viewportHeight: vpH)
            case .toplevelDestroy(let surfaceId):
                processToplevelDestroy(surfaceId)
            case .clientDestroy(let clientId):
                onClientDestroyed?(clientId)
            case .titleChanged(let surfaceId, let title):
                processTitleChanged(surfaceId, title: title)
            case .appIdChanged(let surfaceId, let appId):
                processAppIdChanged(surfaceId, appId: appId)
            case .newPopup(let surfaceId, let parentSurfaceId, let x, let y, let w, let h):
                processNewPopup(surfaceId, parentSurfaceId: parentSurfaceId,
                                x: x, y: y, width: w, height: h)
            case .popupDestroy(let surfaceId):
                processPopupDestroy(surfaceId)
            case .windowGeometry(let surfaceId, let x, let y, let w, let h):
                surfaceGeometry[surfaceId] = (x, y, w, h)
            case .fullscreenRequest(let surfaceId):
                processFullscreenRequest(surfaceId)
            case .unfullscreenRequest(let surfaceId):
                processUnfullscreenRequest(surfaceId)
            case .cursorShape(let shape):
                processCursorShape(shape)
            case .moveRequest(let surfaceId):
                if let windowId = surfaceWindows[surfaceId] {
                    onMoveRequest?(windowId)
                }
            case .interactiveResizeRequest(let surfaceId, let edges):
                if let windowId = surfaceWindows[surfaceId] {
                    onInteractiveResizeRequest?(windowId, edges)
                }
            case .textInputState(let surfaceId, let enabled,
                                 let x, let y, let w, let h):
                if let windowId = surfaceWindows[surfaceId] {
                    onTextInputState?(windowId, enabled,
                                      Double(x), Double(y),
                                      Double(w), Double(h))
                }
            }
        }
    }

    /// Map wp_cursor_shape_device_v1 shapes onto the DRM hardware cursor's
    /// available bitmaps. Anything without a matching bitmap falls back to
    /// the default arrow (the shell's own hover handlers restore shapes when
    /// the pointer returns to shell chrome).
    private func processCursorShape(_ shape: UInt32) {
        let mapped: CursorShape
        switch shape {
        case 9, 10:               // text, vertical_text
            mapped = .text
        case 4, 16, 17:           // pointer (hand), grab, grabbing
            mapped = .pointer
        case 19, 22, 27, 31:      // n_resize, s_resize, ns_resize, row_resize
            mapped = .resizeNS
        case 18, 25, 26, 30:      // e_resize, w_resize, ew_resize, col_resize
            mapped = .resizeEW
        case 20, 24, 28:          // ne_resize, sw_resize, nesw_resize
            mapped = .resizeNESW
        case 21, 23, 29:          // nw_resize, se_resize, nwse_resize
            mapped = .resizeNWSE
        default:
            mapped = .default
        }
        DesktopCursor.setShape(mapped)
    }

    // ─── Event Processors (UI thread) ───────────────────────────────────

    private func processNewToplevel(_ surfaceId: UInt32, clientId: UInt64) {
        let textureId = textureRegistry.registerTexture(engine: engine)
        textureRegistry.markAsWaylandSurface(id: textureId)
        surfaceTextures[surfaceId] = textureId

        // Peer pid, captured here while the surface is certainly alive. The
        // dock's Quit needs it to escalate past a client that ignores
        // xdg_toplevel.close, and looking it up later races the client's own
        // teardown — by the time a user picks Quit the surface may be gone.
        if let server = server {
            let pid = wayland_server_surface_pid(server, surfaceId)
            if pid > 0 { surfacePids[surfaceId] = pid }
        }
        if let windowId = onNewWindow?(surfaceId, Int(textureId), "Wayland App", clientId) {
            surfaceWindows[surfaceId] = windowId
            // An app_id that arrived before the window existed.
            if let appId = surfaceAppIds[surfaceId] {
                onAppIdChanged?(windowId, appId)
            }
        }
    }

    /// Size/scale bookkeeping plus the resize and geometry notifications that
    /// every commit owes the shell, shared by the dma-buf and wl_shm paths.
    /// Returns the buffer dimensions capped to the viewport content area.
    @discardableResult
    private func applyCommitGeometry(_ surfaceId: UInt32, width: Int, height: Int,
                                     bufferScale: Int,
                                     viewportWidth vpW: Int,
                                     viewportHeight vpH: Int) -> (Int, Int) {
        let prevSize = surfaceSizes[surfaceId]
        let prevScale = surfaceBufferScales[surfaceId]
        surfaceSizes[surfaceId] = (width, height)
        surfaceBufferScales[surfaceId] = bufferScale
        // The size the client believes its surface IS, which is not the size
        // of the buffer it drew: a client using wp_viewporter (every Chromium
        // at a fractional scale) attaches a buffer 1.5x its surface and lets
        // the viewport scale it down. Pointer coordinates are surface-local,
        // so this — not the buffer — is what they are measured in.
        if vpW > 0 && vpH > 0 {
            surfaceViewportSizes[surfaceId] = (vpW, vpH)
        } else {
            surfaceViewportSizes.removeValue(forKey: surfaceId)
        }

        let scale = max(bufferScale, 1)
        let effectiveScale = max(Double(scale), shellDpi)
        let hasViewport = vpW > 0 && vpH > 0

        // Notify shell of size changes
        let sizeChanged = prevSize.map { $0.0 != width || $0.1 != height } ?? true
        let scaleChanged = prevScale.map { $0 != bufferScale } ?? true
        if sizeChanged || scaleChanged {
            if let windowId = surfaceWindows[surfaceId] {
                let isPopup = popupSurfaceIds.contains(surfaceId)
                if isPopup {
                    let logicalW = Int(Double(width) / effectiveScale)
                    let logicalH = Int(Double(height) / effectiveScale)
                    let geo = surfaceGeometry[surfaceId]
                    onPopupBufferResized?(windowId, logicalW, logicalH,
                                          Int(Double(geo?.x ?? 0) * fractionalScale / shellDpi),
                                          Int(Double(geo?.y ?? 0) * fractionalScale / shellDpi))
                } else if hasViewport {
                    onWindowBufferResized?(windowId, vpW, vpH)
                } else if let geo = surfaceGeometry[surfaceId] {
                    onWindowBufferResized?(windowId,
                                           Int(Double(geo.width) * fractionalScale / shellDpi),
                                           Int(Double(geo.height) * fractionalScale / shellDpi))
                } else {
                    onWindowBufferResized?(windowId,
                                           Int(Double(width) / effectiveScale),
                                           Int(Double(height) / effectiveScale))
                }
            }
        }

        // Emit geometry callback for toplevels
        if !popupSurfaceIds.contains(surfaceId),
           let windowId = surfaceWindows[surfaceId] {
            let bufLogW: Int
            let bufLogH: Int
            if hasViewport {
                bufLogW = vpW
                bufLogH = vpH
            } else {
                bufLogW = Int(Double(width) / effectiveScale)
                bufLogH = Int(Double(height) / effectiveScale)
            }
            let geo = surfaceGeometry[surfaceId]
            let gx = Int(Double(geo?.x ?? 0) * fractionalScale / shellDpi)
            let gy = Int(Double(geo?.y ?? 0) * fractionalScale / shellDpi)
            let gw = Int(Double(geo?.width ?? vpW) * fractionalScale / shellDpi)
            let gh = Int(Double(geo?.height ?? vpH) * fractionalScale / shellDpi)
            let cur = (gx, gy, gw, gh, bufLogW, bufLogH)
            let prev = lastEmittedGeometry[surfaceId]
            if prev == nil || prev!.x != cur.0 || prev!.y != cur.1
                || prev!.w != cur.2 || prev!.h != cur.3
                || prev!.bufW != cur.4 || prev!.bufH != cur.5 {
                lastEmittedGeometry[surfaceId] = (cur.0, cur.1, cur.2, cur.3, cur.4, cur.5)
                onWindowGeometryChanged?(windowId, gx, gy, gw, gh, bufLogW, bufLogH)
            }
        }

        // Cap import dimensions to viewport content area
        var importW = width
        var importH = height
        if hasViewport {
            let contentPixelW = Int(Double(vpW) * fractionalScale)
            let contentPixelH = Int(Double(vpH) * fractionalScale)
            if contentPixelW < width { importW = contentPixelW }
            if contentPixelH < height { importH = contentPixelH }
        }
        return (importW, importH)
    }

    /// Flush a throttled resize once the interval has elapsed.
    private func flushPendingResize(_ surfaceId: UInt32) {
        if let pending = pendingResize[surfaceId] {
            let now = DispatchTime.now().uptimeNanoseconds
            let last = lastResizeTime[surfaceId] ?? 0
            if now - last >= resizeIntervalNs {
                pendingResize.removeValue(forKey: surfaceId)
                lastResizeTime[surfaceId] = now
                enqueueCommand(.configureToplevel(surfaceId: surfaceId,
                                                   width: Int32(pending.width),
                                                   height: Int32(pending.height)))
                enqueueCommand(.flushClients)
            }
        }
    }

    private func processSurfaceCommit(_ surfaceId: UInt32, fd: Int32, width: Int, height: Int,
                                       stride: Int, fourcc: UInt32, modifier: UInt64,
                                       firstCommit: Bool, bufferScale: Int,
                                       viewportWidth vpW: Int, viewportHeight vpH: Int) {
        guard let textureId = surfaceTextures[surfaceId] else {
            // Surface already gone — we own the dup'd fd, don't leak it.
            if fd >= 0 { Glibc.close(fd) }
            return
        }

        // Read before applyCommitGeometry — it overwrites surfaceSizes.
        let prevSize = surfaceSizes[surfaceId]
        let (importW, importH) = applyCommitGeometry(surfaceId, width: width, height: height,
                                                     bufferScale: bufferScale,
                                                     viewportWidth: vpW, viewportHeight: vpH)

        // Import DMA-BUF. ownsFd: the fd is our dup (made at commit time on
        // the platform thread) — the registry closes it when it's replaced
        // or the texture is dropped.
        if firstCommit || prevSize == nil {
            textureRegistry.importDmaBuf(
                engine: engine, id: textureId,
                fd: fd, width: importW, height: importH,
                stride: stride, fourcc: fourcc,
                modifier: modifier, ownsFd: true
            )
        } else {
            textureRegistry.reimportDmaBuf(
                engine: engine, id: textureId,
                fd: fd, width: importW, height: importH,
                stride: stride, fourcc: fourcc,
                modifier: modifier, ownsFd: true
            )
        }

        flushPendingResize(surfaceId)
        FrameCallbackScheduler.shared.noteTextureUpdate(textureId)
        onSurfaceFrame?(Int64(textureId))
    }

    /// wl_shm commit. `pixels` is this event's tightly-packed copy and is
    /// deallocated here on every path.
    private func processShmSurfaceCommit(_ surfaceId: UInt32,
                                          pixels: UnsafeMutableRawPointer,
                                          width: Int, height: Int, format: UInt32,
                                          firstCommit: Bool, bufferScale: Int,
                                          viewportWidth vpW: Int, viewportHeight vpH: Int) {
        defer { pixels.deallocate() }
        guard let textureId = surfaceTextures[surfaceId] else { return }

        // wl_shm ARGB/XRGB8888 is B,G,R,A in memory; the CPU texture path
        // uploads GL_RGBA. Swizzle in place — this runs on the UI thread, which
        // is also where popup membership is known.
        //
        // Alpha is forced opaque for toplevels. Clients routinely leave it at
        // zero on window surfaces, which composites the window away entirely —
        // the same trap the dma-buf path sidesteps by importing with an opaque
        // fourcc, and that the X server's shadow blit handles the same way.
        // Popups keep their alpha: they need it for shadows and rounded corners.
        let isPopup = popupSurfaceIds.contains(surfaceId)
        let hasAlpha = format == kShmFormatARGB8888
        let keepAlpha = isPopup && hasAlpha
        let px = pixels.assumingMemoryBound(to: UInt8.self)
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let b = px[i]
            px[i] = px[i + 2]
            px[i + 2] = b
            if !keepAlpha { px[i + 3] = 0xFF }
        }

        applyCommitGeometry(surfaceId, width: width, height: height,
                            bufferScale: bufferScale,
                            viewportWidth: vpW, viewportHeight: vpH)

        textureRegistry.updatePixelData(engine: engine, id: textureId,
                                        data: pixels, width: width, height: height)

        flushPendingResize(surfaceId)
        FrameCallbackScheduler.shared.noteTextureUpdate(textureId)
        onSurfaceFrame?(Int64(textureId))
    }

    private func processToplevelDestroy(_ surfaceId: UInt32) {
        lastResizeTime.removeValue(forKey: surfaceId)
        pendingResize.removeValue(forKey: surfaceId)

        if let windowId = surfaceWindows.removeValue(forKey: surfaceId) {
            onWindowDestroyed?(windowId)
        }
        if let textureId = surfaceTextures.removeValue(forKey: surfaceId) {
            textureRegistry.unregisterTexture(engine: engine, id: textureId)
        }

        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceAppIds.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)
        surfaceGeometry.removeValue(forKey: surfaceId)
        lastEmittedGeometry.removeValue(forKey: surfaceId)
        surfaceOutputsMaskCache.removeValue(forKey: surfaceId)
    }

    private func processTitleChanged(_ surfaceId: UInt32, title: String) {
        if let windowId = surfaceWindows[surfaceId] {
            onTitleChanged?(windowId, title)
        }
    }

    /// Clients may set their app_id before the surface has a window (the
    /// toplevel is created, app_id set, and only the first commit maps it), so
    /// remember it and replay when the window appears — otherwise the one
    /// authoritative identity signal is dropped for exactly the clients that
    /// are quickest off the mark.
    private func processAppIdChanged(_ surfaceId: UInt32, appId: String) {
        surfaceAppIds[surfaceId] = appId
        if let windowId = surfaceWindows[surfaceId] {
            onAppIdChanged?(windowId, appId)
        }
    }

    private func processNewPopup(_ surfaceId: UInt32, parentSurfaceId: UInt32,
                                  x: Int, y: Int, width: Int, height: Int) {
        if let oldTextureId = surfaceTextures[surfaceId] {
            textureRegistry.unregisterTexture(engine: engine, id: oldTextureId)
        }
        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)

        let textureId = textureRegistry.registerTexture(engine: engine)
        textureRegistry.markAsWaylandSurface(id: textureId)
        textureRegistry.markAsPopupSurface(id: textureId)
        surfaceTextures[surfaceId] = textureId

        popupSurfaceIds.insert(surfaceId)
        if let popupId = onNewPopup?(surfaceId, Int(textureId), parentSurfaceId, x, y, width, height) {
            surfaceWindows[surfaceId] = popupId
        }
    }

    private func processPopupDestroy(_ surfaceId: UInt32) {
        popupSurfaceIds.remove(surfaceId)

        if let popupId = surfaceWindows.removeValue(forKey: surfaceId) {
            onPopupDestroyed?(popupId)
        }
        if let textureId = surfaceTextures.removeValue(forKey: surfaceId) {
            textureRegistry.unregisterTexture(engine: engine, id: textureId)
        }

        surfaceSizes.removeValue(forKey: surfaceId)
        surfaceBufferScales.removeValue(forKey: surfaceId)
    }

    private func processFullscreenRequest(_ surfaceId: UInt32) {
        guard let windowId = surfaceWindows[surfaceId] else { return }
        onFullscreenRequest?(windowId)
    }

    private func processUnfullscreenRequest(_ surfaceId: UInt32) {
        guard let windowId = surfaceWindows[surfaceId] else { return }
        onUnfullscreenRequest?(windowId)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - C Callback Handlers (platform thread — just queue events)
    // ═══════════════════════════════════════════════════════════════════════

    private func handleNewToplevel(_ surfaceId: UInt32, clientId: UInt64) {
        pendingEvents.withLock { $0.append(.newToplevel(surfaceId: surfaceId, clientId: clientId)) }
        _needsFrame = true
    }

    private func handleCursorShape(_ shape: UInt32) {
        pendingEvents.withLock { $0.append(.cursorShape(shape: shape)) }
        _needsFrame = true
    }

    private func handleSurfaceCommit(_ surfaceId: UInt32, fd: Int32, width: Int, height: Int,
                                      stride: Int, fourcc: UInt32, modifier: UInt64,
                                      firstCommit: Bool, bufferScale: Int) {
        // Read viewport destination on platform thread (safe — inside dispatch)
        var vpW: Int32 = 0
        var vpH: Int32 = 0
        let hasViewport = server != nil && wayland_server_get_viewport_destination(server, surfaceId, &vpW, &vpH) != 0

        // Dup the DMA-BUF fd NOW, while the wl_buffer is guaranteed alive (we
        // are inside the commit dispatch on the event-loop thread). The C side
        // closes its fd whenever the client destroys the buffer — which can
        // happen before the UI thread processes this event. The dup is owned
        // by the texture registry (ownsFd) from import onward.
        let ownedFd = fd >= 0 ? dup(fd) : Int32(-1)

        pendingEvents.withLock { $0.append(.surfaceCommit(
            surfaceId: surfaceId, fd: ownedFd, width: width, height: height,
            stride: stride, fourcc: fourcc, modifier: modifier,
            firstCommit: firstCommit, bufferScale: bufferScale,
            viewportWidth: hasViewport ? Int(vpW) : 0,
            viewportHeight: hasViewport ? Int(vpH) : 0
        )) }
        _needsFrame = true
    }

    private func handleShmSurfaceCommit(_ surfaceId: UInt32, pixels: UnsafeRawPointer,
                                         width: Int, height: Int, stride: Int,
                                         format: UInt32, firstCommit: Bool,
                                         bufferScale: Int) {
        guard width > 0, height > 0, stride >= width * 4 else { return }

        var vpW: Int32 = 0
        var vpH: Int32 = 0
        let hasViewport = server != nil && wayland_server_get_viewport_destination(server, surfaceId, &vpW, &vpH) != 0

        // The pool mapping is only guaranteed for the duration of this callback
        // (the client may destroy the pool the moment we return), so the pixels
        // have to be copied out here on the event-loop thread. Rows are packed
        // to width*4 on the way so the texture upload needs no stride handling.
        let rowBytes = width * 4
        let copy = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height,
                                                    alignment: MemoryLayout<UInt32>.alignment)
        if stride == rowBytes {
            copy.copyMemory(from: pixels, byteCount: rowBytes * height)
        } else {
            for row in 0..<height {
                (copy + row * rowBytes).copyMemory(from: pixels + row * stride,
                                                   byteCount: rowBytes)
            }
        }

        pendingEvents.withLock { $0.append(.shmSurfaceCommit(
            surfaceId: surfaceId, pixels: copy, width: width, height: height,
            format: format, firstCommit: firstCommit, bufferScale: bufferScale,
            viewportWidth: hasViewport ? Int(vpW) : 0,
            viewportHeight: hasViewport ? Int(vpH) : 0
        )) }
        _needsFrame = true
    }

    private func handleTextInputState(_ surfaceId: UInt32, enabled: Bool,
                                       x: Int32, y: Int32, w: Int32, h: Int32) {
        var events = pendingEvents.value
        events.append(.textInputState(surfaceId: surfaceId, enabled: enabled,
                                      x: x, y: y, w: w, h: h))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleClientDestroy(_ clientId: UInt64) {
        var events = pendingEvents.value
        events.append(.clientDestroy(clientId: clientId))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleToplevelDestroy(_ surfaceId: UInt32) {
        var events = pendingEvents.value
        events.append(.toplevelDestroy(surfaceId: surfaceId))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleTitleChanged(_ surfaceId: UInt32, title: String) {
        var events = pendingEvents.value
        events.append(.titleChanged(surfaceId: surfaceId, title: title))
        pendingEvents.value = events
    }

    private func handleAppIdChanged(_ surfaceId: UInt32, appId: String) {
        var events = pendingEvents.value
        events.append(.appIdChanged(surfaceId: surfaceId, appId: appId))
        pendingEvents.value = events
    }

    private func handleNewPopup(_ surfaceId: UInt32, parentSurfaceId: UInt32,
                                 x: Int, y: Int, width: Int, height: Int) {
        var events = pendingEvents.value
        events.append(.newPopup(surfaceId: surfaceId, parentSurfaceId: parentSurfaceId,
                                 x: x, y: y, width: width, height: height))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handlePopupDestroy(_ surfaceId: UInt32) {
        var events = pendingEvents.value
        events.append(.popupDestroy(surfaceId: surfaceId))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleWindowGeometry(_ surfaceId: UInt32, x: Int, y: Int,
                                        width: Int, height: Int) {
        var events = pendingEvents.value
        events.append(.windowGeometry(surfaceId: surfaceId, x: x, y: y,
                                       width: width, height: height))
        pendingEvents.value = events
    }

    private func handleFullscreenRequest(_ surfaceId: UInt32) {
        var events = pendingEvents.value
        events.append(.fullscreenRequest(surfaceId: surfaceId))
        pendingEvents.value = events
        _needsFrame = true
    }

    private func handleUnfullscreenRequest(_ surfaceId: UInt32) {
        var events = pendingEvents.value
        events.append(.unfullscreenRequest(surfaceId: surfaceId))
        pendingEvents.value = events
        _needsFrame = true
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Command Enqueuing (UI thread → platform thread)
    // ═══════════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Multi-output (UI thread)
    // ═══════════════════════════════════════════════════════════════════════

    /// Output-array bit index per DisplayOutput.id (primary is always bit 0,
    /// matching the server's fresh-map default).
    /// Output id → wl_output bit. Written on the main thread (setOutputs),
    /// read on the PLATFORM thread (handlePresent maps the flipping engine
    /// output to its bit) — hence the lock; a torn Dictionary read is a
    /// crash, not just a stale answer.
    private var outputBitForId: [Int: Int] = [:]
    private let outputBitLock = NSLock()
    /// mask in the low 32 bits, pace mask in the high — one cache entry
    /// covers both, so a pace change with an unchanged intersection (a
    /// window sliding along the seam) still gets sent.
    private var surfaceOutputsMaskCache: [UInt32: UInt64] = [:]

    /// Advertise the virtual-desktop arrangement: one wl_output global per
    /// display, geometry in global logical coordinates.
    func setOutputs(_ outputs: [DisplayOutput]) {
        let ordered = outputs.filter { $0.isPrimary } +
                      outputs.filter { !$0.isPrimary }
        outputBitLock.lock()
        outputBitForId = Dictionary(
            uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        outputBitLock.unlock()
        let descs = ordered.map { o -> WaylandOutputDesc in
            var desc = WaylandOutputDesc()
            desc.logical_x = Int32(o.originX.rounded())
            desc.logical_y = Int32(o.originY.rounded())
            desc.physical_w = Int32(o.physicalWidth)
            desc.physical_h = Int32(o.physicalHeight)
            desc.scale = Int32(max(1, Int(o.scale)))
            desc.refresh_mhz = Int32(o.refreshMhz)
            withUnsafeMutableBytes(of: &desc.name) { buf in
                let bytes = Array(o.name.utf8.prefix(buf.count - 1))
                for (i, b) in bytes.enumerated() { buf[i] = b }
                buf[bytes.count] = 0
            }
            return desc
        }
        enqueueCommand(.setOutputs(outputs: descs))
    }

    /// Update which outputs a window's surface intersects; the server diffs
    /// and sends wl_surface.enter/leave. `paceOutputId` is the output the
    /// window mostly sits on — the one whose flips drive the client's frame
    /// callbacks. No-op for non-Wayland windows.
    func updateSurfaceOutputs(windowId: String, intersectingIds: [Int],
                              paceOutputId: Int? = nil) {
        outputBitLock.lock()
        let bits = outputBitForId
        outputBitLock.unlock()
        guard !bits.isEmpty,
              let surfaceId = surfaceWindows.first(
                  where: { $0.value == windowId })?.key
        else { return }
        var mask: UInt32 = 0
        for id in intersectingIds {
            if let bit = bits[id] {
                mask |= 1 << UInt32(bit)
            }
        }
        var paceMask: UInt32 = 0
        if let paceId = paceOutputId, let bit = bits[paceId] {
            paceMask = 1 << UInt32(bit)
        }
        let combined = UInt64(mask) | (UInt64(paceMask) << 32)
        if surfaceOutputsMaskCache[surfaceId] == combined { return }
        surfaceOutputsMaskCache[surfaceId] = combined
        enqueueCommand(.setSurfaceOutputs(surfaceId: surfaceId, mask: mask,
                                          paceMask: paceMask))
    }

    /// The wl_output bit for an engine output id, or bit 0 (the primary)
    /// when the id is unknown — single-output desktops never call
    /// setOutputs, and their one panel IS the primary. Platform-thread safe.
    func outputBit(forId id: Int) -> UInt32 {
        outputBitLock.lock()
        defer { outputBitLock.unlock() }
        return UInt32(outputBitForId[id] ?? 0)
    }

    private func enqueueCommand(_ cmd: WaylandCommand) {
        pendingCommands.withLock { $0.append(cmd) }
        // Wake the epoll loop to drain commands promptly. Writing before the
        // loop starts (or before setEpollDriven) is fine — the byte sits in
        // the pipe and fires as soon as the loop begins polling, which is
        // what lets startup commands (e.g. setOutputs) execute deterministically.
        if wakeupWriteFd >= 0 {
            var byte: UInt8 = 1
            _ = Glibc.write(wakeupWriteFd, &byte, 1)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Input Forwarding (safe from any thread — uses C deferred pipe)
    // ═══════════════════════════════════════════════════════════════════════

    /// Queries which DRM modifiers the compositor's EGL can import for the
    /// formats our texture path supports, and advertises exactly that list
    /// via linux-dmabuf (v3 modifier events + v4 feedback table). Clients
    /// bringing their own Mesa then negotiate layouts both sides explicitly
    /// support — no reliance on implicit-modifier guessing across Mesa
    /// versions.
    func advertiseDmaBufFormats(eglDisplay: UnsafeMutableRawPointer?) {
        guard let server = server, let eglDisplay = eglDisplay else { return }
        let DRM_FORMAT_MOD_INVALID: UInt64 = 0x00FF_FFFF_FFFF_FFFF
        // ARGB8888, XRGB8888, ABGR8888, XBGR8888 — the import path's formats.
        let fourccs: [UInt32] = [0x3432_5241, 0x3432_5258, 0x3432_4241, 0x3432_4258]

        // Tiled modifiers are opt-in for now: zink's
        // eglQueryDmaBufModifiersEXT reports the AMD tiled layouts as
        // importable, but eglCreateImageKHR then fails with BAD_ALLOC
        // (and DCC layouts additionally need multi-plane import we don't
        // have). Until that gap closes, advertise EGL-verified LINEAR plus
        // the implicit modifier — correctness first, tiling perf later.
        let allowTiled = ProcessInfo.processInfo.environment["STARLING_DMABUF_TILED"] == "1"
        let DRM_FORMAT_MOD_LINEAR: UInt64 = 0

        // Modifiers a previous session PROVED unimportable (the query lies;
        // the import is ground truth — e.g. radeonsi's GFX11 64K_R_X layout
        // fails zink's plane-layout translation). Skipped up front so
        // clients never waste a first frame on them.
        let demoted = Self.loadDemotedModifiers()

        var formats: [UInt32] = []
        var modifiers: [UInt64] = []
        var queried = [UInt64](repeating: 0, count: 64)
        for fourcc in fourccs {
            let n = dmabuf_query_modifiers(eglDisplay, fourcc, &queried, 64)
            for i in 0 ..< Int(n) {
                let modifier = queried[i]
                if !allowTiled && modifier != DRM_FORMAT_MOD_LINEAR {
                    continue
                }
                // Skip AMD DCC modifiers even in tiled mode: DCC buffers
                // carry extra metadata planes and our import path is
                // single-plane only (vendor 0x02 in bits 56-63, DCC bit 13).
                if (modifier >> 56) == 0x02 && (modifier >> 13) & 1 == 1 {
                    continue
                }
                if demoted.contains(modifier) {
                    continue
                }
                formats.append(fourcc)
                modifiers.append(modifier)
            }
            // Keep implicit-modifier support: producer and consumer share the
            // same kernel driver, which resolves the layout.
            formats.append(fourcc)
            modifiers.append(DRM_FORMAT_MOD_INVALID)
        }
        guard !formats.isEmpty else { return }
        wayland_server_set_dmabuf_formats(server, formats, modifiers,
                                          Int32(formats.count))
        if !demoted.isEmpty {
            print("[WaylandIntegration] skipping \(demoted.count) demoted dma-buf modifier(s) from a previous session")
        }
        print("[WaylandIntegration] advertising \(formats.count) dma-buf format+modifier pairs from EGL")

        // Runtime self-correction: when the raster thread's EGLImage import
        // rejects a buffer, demote its modifier live (feedback re-send makes
        // v4 clients re-allocate) and persist it for the next session.
        LinuxTextureRegistry.onDmaBufImportFailure = { [weak self] fourcc, modifier in
            guard let self, let server = self.server else { return }
            if Self.persistDemotedModifier(modifier) {
                print("[WaylandIntegration] dma-buf import failed (fourcc=0x\(String(fourcc, radix: 16)) modifier=0x\(String(modifier, radix: 16))) — demoting")
            }
            wayland_server_demote_dmabuf_modifier(server, fourcc, modifier)
        }
    }

    /// Demoted-modifier persistence: one hex modifier per line. Lives in
    /// TMPDIR so it survives shell restarts on the dev box (and resets per
    /// boot on the image, where /tmp is tmpfs) — a stale entry only costs
    /// tiling perf, never correctness.
    private static let demotedModifiersPath =
        (ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp") + "/starling-dmabuf-demoted"
    private static let demotedLock = NSLock()
    // nonisolated(unsafe): guarded by demotedLock.
    nonisolated(unsafe) private static var demotedPersisted: Set<UInt64>?

    private static func loadDemotedModifiers() -> Set<UInt64> {
        demotedLock.lock()
        defer { demotedLock.unlock() }
        if let cached = demotedPersisted { return cached }
        var set = Set<UInt64>()
        if let text = try? String(contentsOfFile: demotedModifiersPath, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                if let v = UInt64(line.trimmingCharacters(in: .whitespaces), radix: 16) {
                    set.insert(v)
                }
            }
        }
        demotedPersisted = set
        return set
    }

    /// Returns true when the modifier is newly demoted (first failure).
    private static func persistDemotedModifier(_ modifier: UInt64) -> Bool {
        demotedLock.lock()
        defer { demotedLock.unlock() }
        var set = demotedPersisted ?? Set<UInt64>()
        guard !set.contains(modifier) else { return false }
        set.insert(modifier)
        demotedPersisted = set
        let text = set.map { String($0, radix: 16) }.joined(separator: "\n") + "\n"
        try? text.write(toFile: demotedModifiersPath, atomically: true, encoding: .utf8)
        return true
    }

    private var pointerFocusSurface: UInt32 = 0
    private var keyboardFocusSurface: UInt32 = 0

    /// xkb modifier masks for the default us(pc105) keymap the seat sends.
    private var modsDepressed: UInt32 = 0
    private var modsLocked: UInt32 = 0

    /// Maps a modifier keysym to its bit in the default keymap
    /// (Shift=0, Lock=1, Control=2, Mod1/Alt=3, Mod2/Num=4, Mod4/Super=6,
    /// Mod5/AltGr=7).
    private static func modifierBit(forKeysym keysym: Int64) -> UInt32? {
        switch keysym {
        case 0xFFE1, 0xFFE2: return 1 << 0  // Shift_L / Shift_R
        case 0xFFE3, 0xFFE4: return 1 << 2  // Control_L / Control_R
        case 0xFFE9, 0xFFEA: return 1 << 3  // Alt_L / Alt_R
        case 0xFFEB, 0xFFEC: return 1 << 6  // Super_L / Super_R
        case 0xFE03: return 1 << 7          // ISO_Level3_Shift (AltGr)
        default: return nil
        }
    }

    /// Sync wl_keyboard focus (enter/leave + modifiers) to the
    /// pointer-focused surface without sending a key. Needed while the IME
    /// swallows every key: text-input enter rides keyboard enter, and the
    /// lazy enter inside sendKeyEvent would otherwise never fire.
    func ensureKeyboardFocus() {
        guard let server = server else { return }
        let surfaceId = pointerFocusSurface
        guard surfaceId != 0, keyboardFocusSurface != surfaceId else { return }
        if keyboardFocusSurface != 0 {
            wayland_server_keyboard_leave(server, keyboardFocusSurface)
        }
        wayland_server_keyboard_enter(server, surfaceId)
        keyboardFocusSurface = surfaceId
        wayland_server_keyboard_modifiers(server, surfaceId,
                                          modsDepressed, 0, modsLocked, 0)
    }

    /// Deliver a key to a Wayland client. `targetSurface` is the focused
    /// WINDOW's surface — keyboard focus follows window focus, not the pointer.
    /// Passing 0 falls back to the pointer-focus surface (legacy callers).
    ///
    /// This distinction is load-bearing: when a window is focused without the
    /// pointer over it — a new toplevel mapped on top (Zoom's SSO opening
    /// Chrome), or click-to-focus followed by the cursor moving away — the
    /// pointer-focus surface is 0, and keying off it dropped every keystroke.
    func sendKeyEvent(physical: Int64, logical: Int64, isDown: Bool,
                      targetSurface: UInt32 = 0) {
        guard let server = server else { return }
        let surfaceId = targetSurface != 0 ? targetSurface : pointerFocusSurface
        guard surfaceId != 0 else { return }

        if keyboardFocusSurface != surfaceId {
            if keyboardFocusSurface != 0 {
                wayland_server_keyboard_leave(server, keyboardFocusSurface)
            }
            wayland_server_keyboard_enter(server, surfaceId)
            keyboardFocusSurface = surfaceId
            // The spec requires a modifiers event after enter so the client
            // starts from the compositor's current state.
            wayland_server_keyboard_modifiers(server, surfaceId,
                                              modsDepressed, 0, modsLocked, 0)
        }

        // Track modifier state from the keysym and inform the client BEFORE
        // the key event: clients interpret keys through the xkb state driven
        // by wl_keyboard.modifiers, so without this Shift/Ctrl never apply.
        var modsChanged = false
        if let bit = WaylandIntegration.modifierBit(forKeysym: logical) {
            if isDown && modsDepressed & bit == 0 {
                modsDepressed |= bit
                modsChanged = true
            } else if !isDown && modsDepressed & bit != 0 {
                modsDepressed &= ~bit
                modsChanged = true
            }
        } else if isDown && (logical == 0xFFE5 || logical == 0xFF7F) {
            // Caps_Lock / Num_Lock toggle their locked bits on press.
            let bit: UInt32 = logical == 0xFFE5 ? (1 << 1) : (1 << 4)
            modsLocked ^= bit
            modsChanged = true
        }
        if modsChanged {
            wayland_server_keyboard_modifiers(server, surfaceId,
                                              modsDepressed, 0, modsLocked, 0)
        }

        let evdevKey = WaylandIntegration.hidToEvdev(UInt64(bitPattern: physical))
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        wayland_server_keyboard_key(server, surfaceId, timeMs, evdevKey,
                                     isDown ? 1 : 0)
    }

    /// USB HID usage (page 0x07) -> evdev key code. The exact inverse of the
    /// engine's FlDrmInput::EvdevToHID (fl_drm_input.cc) — keep in sync.
    /// Not private: the X11 key path (DesktopShell.routeKey) reuses this so the
    /// HID→evdev mapping has ONE source of truth across both display servers.
    /// HID → evdev for Wayland clients. The table lives in HidEvdev, which
    /// derives this direction and its inverse from one list of pairs — see
    /// there for why they must not be separate switches.
    static func hidToEvdev(_ hid: UInt64) -> UInt32 {
        return HidEvdev.evdev(fromHid: hid)
    }

    func sendScrollEvent(surfaceId: UInt32, x: Double, y: Double,
                          scrollDeltaX: Double, scrollDeltaY: Double) {
        guard let server = server else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        wayland_server_pointer_axis(server, surfaceId, timeMs,
                                     scrollDeltaX, scrollDeltaY)
    }

    func sendPointerEvent(surfaceId: UInt32, phase: Int32, x: Double, y: Double, buttons: Int64) {
        guard let server = server else { return }

        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)

        let (sx, sy) = toSurfaceSpace(surfaceId, x, y)
        if pointerFocusSurface != surfaceId {
            if pointerFocusSurface != 0 {
                wayland_server_pointer_leave(server, pointerFocusSurface)
            }
            wayland_server_pointer_enter(server, surfaceId, sx, sy)
            pointerFocusSurface = surfaceId
        }

        switch phase {
        case 2: // down
            wayland_server_pointer_button(server, surfaceId, timeMs, 0x110, 1)
        case 1: // up
            wayland_server_pointer_button(server, surfaceId, timeMs, 0x110, 0)
        case 3, 6: // move, hover
            wayland_server_pointer_motion(server, surfaceId, timeMs, sx, sy)
        default:
            break
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Quit
    // ═══════════════════════════════════════════════════════════════════════

    /// Ask the client owning `surfaceId` to close itself (xdg_toplevel.close).
    func requestClose(surfaceId: UInt32) {
        guard server != nil else { return }
        enqueueCommand(.closeToplevel(surfaceId: surfaceId))
    }

    /// pid behind a surface, captured when its toplevel appeared. nil if the
    /// surface never had one (or the compositor could not read credentials).
    func clientPid(surfaceId: UInt32) -> pid_t? {
        return surfacePids[surfaceId]
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Resize / Configure (UI thread → enqueue commands)
    // ═══════════════════════════════════════════════════════════════════════

    func isResizing(surfaceId: UInt32) -> Bool {
        guard let t = lastResizeTime[surfaceId] else { return false }
        return DispatchTime.now().uptimeNanoseconds - t < resizeIntervalNs * 3
    }

    /// What we last asked each surface to be, in the coordinate space the
    /// shell's own pointer coordinates are in.
    ///
    /// A client does not have to comply, and two common cases mean it does
    /// not: it can enforce a minimum window size, and one that applies its
    /// own device-scale factor renders a buffer bigger than the size it was
    /// configured with. The shell draws whatever arrives STRETCHED into the
    /// box it meant — so the picture looks right while every pointer
    /// coordinate is wrong by that stretch. See `toSurfaceSpace`.
    private var configuredSize: [UInt32: (w: Double, h: Double)] = [:]

    /// Map a point in the box the shell DRAWS a surface into onto the
    /// surface's own coordinate space.
    ///
    /// Claude Desktop in a workspace column is the case that found this: it
    /// refuses to be narrower than 948px and renders at 1.5x, so a 460x1383
    /// pane held a 948x2075 surface. Clicks were delivered — the compositor
    /// logged the button reaching the client's pointer — at coordinates a
    /// third of the way to where the user had aimed, so they hit nothing and
    /// the window looked dead to the mouse while typing and scrolling worked
    /// fine. Nothing about that reads as a coordinate bug, which is why it is
    /// worth doing here, once, for every window kind rather than per caller.
    /// The size of a surface in its OWN units — what surface-local pointer
    /// coordinates are measured in.
    ///
    /// Three spellings of "how big is this window" meet here and only one is
    /// the right answer. The buffer is what the client drew (2304 px wide for
    /// Chrome at 1.5x). `buffer_scale` covers the integer-scale clients. A
    /// viewport covers the rest, and it is the common case on this desktop:
    /// every Chromium at a fractional scale attaches an oversized buffer and
    /// asks wp_viewporter to scale it down, leaving buffer_scale at 1. Read
    /// the buffer and you conclude the surface is half again as big as the
    /// client thinks it is — which sends every pointer event 1.5x too far
    /// down and to the right, into whatever is there instead.
    private func surfaceLocalSize(_ surfaceId: UInt32) -> (Double, Double)? {
        if let vp = surfaceViewportSizes[surfaceId], vp.0 > 0, vp.1 > 0 {
            return (Double(vp.0), Double(vp.1))
        }
        guard let buf = surfaceSizes[surfaceId], buf.0 > 0, buf.1 > 0 else { return nil }
        let bs = Double(max(surfaceBufferScales[surfaceId] ?? 1, 1))
        return (Double(buf.0) / bs, Double(buf.1) / bs)
    }

    private func toSurfaceSpace(_ surfaceId: UInt32,
                                _ x: Double, _ y: Double) -> (Double, Double) {
        let d = shellDpi / fractionalScale
        guard let want = configuredSize[surfaceId], want.w > 1, want.h > 1,
              let got = surfaceLocalSize(surfaceId), got.0 > 1, got.1 > 1 else {
            return (x * d, y * d)
        }
        return (x * got.0 / want.w, y * got.1 / want.h)
    }

    func sendResize(surfaceId: UInt32, width: Int, height: Int) {
        guard server != nil else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if let last = lastResizeTime[surfaceId], now - last < resizeIntervalNs {
            pendingResize[surfaceId] = (width, height)
            return
        }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = now
        let sw = Int32(Double(width) * shellDpi / fractionalScale)
        let sh = Int32(Double(height) * shellDpi / fractionalScale)
        configuredSize[surfaceId] = (Double(width), Double(height))
        enqueueCommand(.configureToplevel(surfaceId: surfaceId, width: sw, height: sh))
        enqueueCommand(.flushClients)
    }

    func sendFullscreenResize(surfaceId: UInt32, width: Int, height: Int) {
        guard server != nil else { return }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = DispatchTime.now().uptimeNanoseconds
        let sw = Int32(Double(width) * shellDpi / fractionalScale)
        let sh = Int32(Double(height) * shellDpi / fractionalScale)
        configuredSize[surfaceId] = (Double(width), Double(height))
        enqueueCommand(.configureToplevel(surfaceId: surfaceId, width: sw, height: sh))
        enqueueCommand(.flushClients)
    }

    func sendExitFullscreen(surfaceId: UInt32, width: Int, height: Int) {
        guard server != nil else { return }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = DispatchTime.now().uptimeNanoseconds
        let sw = Int32(Double(width) * shellDpi / fractionalScale)
        let sh = Int32(Double(height) * shellDpi / fractionalScale)
        configuredSize[surfaceId] = (Double(width), Double(height))
        enqueueCommand(.configureToplevel(surfaceId: surfaceId, width: sw, height: sh))
        enqueueCommand(.flushClients)
    }

    func sendResizeForced(surfaceId: UInt32, width: Int, height: Int) {
        guard server != nil else { return }
        pendingResize.removeValue(forKey: surfaceId)
        lastResizeTime[surfaceId] = DispatchTime.now().uptimeNanoseconds
        let sw = Int32(Double(width) * shellDpi / fractionalScale)
        let sh = Int32(Double(height) * shellDpi / fractionalScale)
        configuredSize[surfaceId] = (Double(width), Double(height))
        enqueueCommand(.configureToplevel(surfaceId: surfaceId, width: sw, height: sh))
        enqueueCommand(.flushClients)
    }

    func sendPointerEnter(surfaceId: UInt32, x: Double, y: Double) {
        guard let server = server else { return }
        let (sx, sy) = toSurfaceSpace(surfaceId, x, y)
        wayland_server_pointer_enter(server, surfaceId, sx, sy)
    }

    func sendPointerLeave(surfaceId: UInt32) {
        guard let server = server else { return }
        wayland_server_pointer_leave(server, surfaceId)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Lookup Helpers
    // ═══════════════════════════════════════════════════════════════════════

    func surfaceId(forWindowId windowId: String) -> UInt32? {
        return surfaceWindows.first(where: { $0.value == windowId })?.key
    }

    /// Throttle a surface's frame callbacks (Murmuration: tile-only agent
    /// windows idle at ~5fps). 0 restores full rate. Safe from any thread.
    func setSurfaceThrottle(surfaceId: UInt32, intervalMs: UInt32) {
        enqueueCommand(.setSurfaceThrottle(surfaceId: surfaceId, intervalMs: intervalMs))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Agent Input (Murmuration)
    //
    // Broker-injected input into agent-owned Wayland windows. A dedicated
    // second wl_seat exists compositor-side (seat-agent), but Chromium's
    // Ozone layer is single-seat and takes no input from it (verified:
    // zero DOM events) — so agent input is delivered on seat 0 with
    // EXPLICIT per-event surface targeting and its own focus trackers.
    // Delivery is per-client, so the human (in one client) and the agent
    // (in another) never disturb each other; only concurrent human+agent
    // use of the SAME client's windows can interleave. Seat-aware clients
    // can move to the agent seat later without compositor changes.
    // ═══════════════════════════════════════════════════════════════════════

    // NOTE: the agent's pointer and keyboard focus are NOT tracked separately
    // any more, and must not be. There is one wl_seat, so the client has ONE
    // idea of where the pointer is — two caches of it drift the moment the
    // other side moves, and the stale one then stops re-asserting the enter
    // it thinks it already sent. What that looked like: the agent clicked
    // Chrome fine until the human's pointer crossed onto another window,
    // which sent Chrome a leave; from then on every agent click was accepted,
    // audited "ok", delivered as motion+button — and dropped by the client,
    // because from its seat the pointer was somewhere else entirely. Nothing
    // logged a refusal, and moving the real pointer back over the window
    // "fixed" it, which is what made it look like the agent had gone blind.
    // Both paths now share `pointerFocusSurface` / `keyboardFocusSurface`, so
    // whichever side moves last re-asserts the enter, and the other side
    // re-asserts it on its next event.

    /// The agent's own xkb modifier state, kept apart from the human's for
    /// the same reason the focus trackers are: the person holding Shift must
    /// not shift what an agent types in another window, and vice versa.
    private var agentModsDepressed: UInt32 = 0
    private var agentModsLocked: UInt32 = 0

    /// Modifier bit for a HID usage, in the default us(pc105) keymap the seat
    /// sends. The human path derives this from the KEYSYM; the agent contract
    /// carries only a HID usage, so the same table is expressed over usages.
    /// (Shift=0, Lock=1, Control=2, Mod1/Alt=3, Mod2/Num=4, Mod4/Super=6.)
    private static func agentModifierBit(forHid hid: UInt64) -> UInt32? {
        switch hid {
        case 0xE1, 0xE5: return 1 << 0  // Left/Right Shift
        case 0xE0, 0xE4: return 1 << 2  // Left/Right Control
        case 0xE2, 0xE6: return 1 << 3  // Left/Right Alt
        case 0xE3, 0xE7: return 1 << 6  // Left/Right GUI (Super)
        default: return nil
        }
    }

    /// Buttons, as evdev codes — the C layer passes them through verbatim.
    static let agentButtonLeft: UInt32 = 0x110
    static let agentButtonRight: UInt32 = 0x111
    static let agentButtonMiddle: UInt32 = 0x112

    /// Same phase contract as sendPointerEvent (2=down 1=up 3=move 6=hover),
    /// same coordinate scaling, but with independent focus tracking. A
    /// motion always precedes a button so the click lands at (x, y) even
    /// without preceding hovers.
    func agentPointerEvent(surfaceId: UInt32, phase: Int32, x: Double, y: Double,
                           button: UInt32 = WaylandIntegration.agentButtonLeft) {
        guard let server = server else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        // Same stretch, same correction — an agent aims at the coordinate
        // space `capture` reported, which is the box the shell draws into.
        let (sx, sy) = toSurfaceSpace(surfaceId, x, y)
        if pointerFocusSurface != surfaceId {
            // Leave the surface we were on first. Without this a client that
            // has been left keeps believing the pointer is inside it — it
            // holds its hover state, and its idea of where the pointer sits
            // is whatever it last heard, forever.
            if pointerFocusSurface != 0 {
                wayland_server_pointer_leave(server, pointerFocusSurface)
            }
            wayland_server_pointer_enter(server, surfaceId, sx, sy)
            pointerFocusSurface = surfaceId
            // Keyboard enter rides POINTER enter, not the first keystroke.
            // CLAUDE.md's trap, paid for again here: a client that receives
            // wl_keyboard.enter AFTER a click has already moved its internal
            // focus treats the enter as freshly gaining focus and resets to
            // its default target. Concretely — click Chrome's address bar,
            // then send Ctrl+A, and the selection lands in the PAGE, because
            // the enter arrived between the two and put focus back on the web
            // contents. Establishing keyboard focus with the pointer makes
            // the click the last word on where the caret is.
            agentEnsureKeyboardFocus(surfaceId)
        }
        switch phase {
        case 2:
            wayland_server_pointer_motion(server, surfaceId, timeMs, sx, sy)
            wayland_server_pointer_button(server, surfaceId, timeMs, button, 1)
        case 1:
            wayland_server_pointer_button(server, surfaceId, timeMs, button, 0)
        case 3, 6:
            wayland_server_pointer_motion(server, surfaceId, timeMs, sx, sy)
        default:
            break
        }
    }

    /// Move the agent's wl_keyboard focus to `surfaceId` if it is not there
    /// already. Called from pointer enter as well as from the key path — see
    /// agentPointerEvent for why the pointer must not be the second one.
    private func agentEnsureKeyboardFocus(_ surfaceId: UInt32) {
        guard let server = server, keyboardFocusSurface != surfaceId else { return }
        if keyboardFocusSurface != 0 {
            wayland_server_keyboard_leave(server, keyboardFocusSurface)
        }
        wayland_server_keyboard_enter(server, surfaceId)
        keyboardFocusSurface = surfaceId
        // The spec requires a modifiers event after enter so the client
        // starts from the compositor's current state.
        wayland_server_keyboard_modifiers(server, surfaceId,
                                          agentModsDepressed, 0,
                                          agentModsLocked, 0)
    }

    /// Agent key; `physical` is a HID usage (the broker's key contract),
    /// converted with the same table as the human path.
    func agentKeyEvent(surfaceId: UInt32, physical: Int64, isDown: Bool) {
        guard let server = server else { return }
        agentEnsureKeyboardFocus(surfaceId)
        let hid = UInt64(bitPattern: physical)
        // Clients interpret keys through the xkb state that wl_keyboard
        // .modifiers drives, so a chord sent without this arrives UNMODIFIED
        // — Ctrl+C as a bare `c`, into whatever has the caret. The human path
        // has always done this; the agent path never did, which is why
        // holding a modifier through `keydown` needs it now.
        var modsChanged = false
        if let bit = WaylandIntegration.agentModifierBit(forHid: hid) {
            if isDown && agentModsDepressed & bit == 0 {
                agentModsDepressed |= bit
                modsChanged = true
            } else if !isDown && agentModsDepressed & bit != 0 {
                agentModsDepressed &= ~bit
                modsChanged = true
            }
        } else if isDown && (hid == 0x39 || hid == 0x53) {
            // Caps Lock / Num Lock toggle their locked bits on press.
            agentModsLocked ^= (hid == 0x39 ? (1 << 1) : (1 << 4))
            modsChanged = true
        }
        if modsChanged {
            wayland_server_keyboard_modifiers(server, surfaceId,
                                              agentModsDepressed, 0,
                                              agentModsLocked, 0)
        }
        let evdevKey = WaylandIntegration.hidToEvdev(hid)
        guard evdevKey != 0 else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        wayland_server_keyboard_key(server, surfaceId, timeMs,
                                    evdevKey, isDown ? 1 : 0)
    }

    /// Release everything the agent is holding on `surfaceId` — modifiers
    /// included. A window closing (or an agent disconnecting) mid-chord would
    /// otherwise leave the client convinced Ctrl is still down.
    func agentReleaseAll(surfaceId: UInt32) {
        guard let server = server else { return }
        guard agentModsDepressed != 0 || agentModsLocked != 0 else { return }
        agentModsDepressed = 0
        wayland_server_keyboard_modifiers(server, surfaceId, 0, 0,
                                          agentModsLocked, 0)
    }

    /// Agent scroll (deltas in the same units as sendScrollEvent).
    func agentScrollEvent(surfaceId: UInt32, deltaX: Double, deltaY: Double) {
        guard let server = server else { return }
        let timeMs = UInt32(DispatchTime.now().uptimeNanoseconds / 1_000_000)
        wayland_server_pointer_axis(server, surfaceId, timeMs, deltaX, deltaY)
    }

    func windowId(forSurfaceId surfaceId: UInt32) -> String? {
        return surfaceWindows[surfaceId]
    }

}
