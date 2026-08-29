// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import X11Server
#if os(Linux)
import FlutterEmbedderBridge
import FlutterDRMBridge
import Glibc
import Dispatch
import Foundation
#endif

/// Bridges the X11 server to DesktopShellApp's window system.
/// Similar to WaylandIntegration but for X11 clients.
class X11Integration {
    private var server: OpaquePointer?  // X11Server*
    /// Public access for timerfd registration.
    var serverPointer: OpaquePointer? { server }

    /// Whether any X client is connected.
    ///
    /// The shell's frame pump watches for a GetImage screen capture starting,
    /// and a capture needs a client. With nobody connected -- the normal state
    /// of a Wayland-only desktop -- the pump can skip that check and the
    /// wakeup that would carry it.
    var hasClients: Bool {
        guard let server else { return false }
        return x11_server_client_count(server) > 0
    }
    private let engine: OpaquePointer
    private let textureRegistry: LinuxTextureRegistry

    // Surface tracking
    private var windowTextures: [UInt32: Int64] = [:]   // x11_window_id → textureId
    private var windowIds: [UInt32: String] = [:]        // x11_window_id → shell windowId
    private var popupIds: [UInt32: String] = [:]         // x11_window_id → shell popupId
    private var lastPointerWindowId: UInt32 = 0          // track enter/leave

    // Callbacks set by DesktopShell
    var onNewWindow: ((_ windowId: UInt32, _ textureId: Int, _ title: String,
                        _ x: Int, _ y: Int, _ width: Int, _ height: Int) -> String)?
    var onWindowDestroyed: ((_ windowId: String) -> Void)?
    /// An override-redirect toplevel (menu / dropdown / tooltip) was mapped.
    /// x/y are root-relative physical px; the shell anchors it to parentWindowId.
    var onNewPopup: ((_ windowId: UInt32, _ textureId: Int, _ parentWindowId: UInt32,
                       _ x: Int, _ y: Int, _ width: Int, _ height: Int) -> String)?
    var onPopupDestroyed: ((_ popupId: String) -> Void)?
    /// A popup's presented buffer changed size (menus map small, then grow).
    var onPopupBufferResized: ((_ popupId: String, _ physWidth: Int, _ physHeight: Int) -> Void)?
    var onTitleChanged: ((_ windowId: String, _ title: String) -> Void)?
    var onBufferPresented: ((_ windowId: String) -> Void)?
    /// Called when a client's buffer size changes (physical width/height).
    var onWindowBufferResized: ((_ windowId: String, _ physWidth: Int, _ physHeight: Int) -> Void)?

    init(engine: OpaquePointer, textureRegistry: LinuxTextureRegistry) {
        self.engine = engine
        self.textureRegistry = textureRegistry
    }

    deinit {
        stop()
    }

    /// DRM view for adding fds to epoll
    private var drmView: OpaquePointer?
    /// Wakeup pipe — written to trigger dispatch via epoll
    private var wakeupReadFd: Int32 = -1
    private var wakeupWriteFd: Int32 = -1
    /// Self-signal counter — limits busy-looping during init
    private var wakeupCounter: Int = 0

    /// Client pid per X11 window, from the connection's peer credentials.
    private var windowPids: [UInt32: pid_t] = [:]

    /// Last imported DMA-BUF dimensions per texture — avoids costly
    /// reimportDmaBuf when frame dimensions haven't changed.
    private var lastImportedSize: [Int64: (width: Int, height: Int)] = [:]

    // Resize throttling: minimum interval between ConfigureNotify events.
    // X11 server also has sync_waiting (33ms fallback), but Swift-side throttle
    // ensures we don't flood Chrome even when sync_waiting clears quickly.
    private var lastResizeTime: [UInt32: UInt64] = [:]
    private var pendingResize: [UInt32: (width: Int, height: Int)] = [:]
    private let resizeIntervalNs: UInt64 = 33_000_000  // 33ms (~30fps) — matching Wayland (DRI3Open dup→open fix may prevent crash)

    /// Start the X11 server on the given display number.
    func start(displayNum: Int, screenWidth: Int, screenHeight: Int, drmView: OpaquePointer? = nil) {
        self.drmView = drmView
        var config = X11ServerConfig()
        config.display_width = Int32(screenWidth)
        config.display_height = Int32(screenHeight)
        config.depth = 24
        config.userdata = Unmanaged.passUnretained(self).toOpaque()

        config.on_window_mapped = { (userdata, windowId, x, y, w, h) in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            this.handleWindowMapped(windowId, x: Int(x), y: Int(y),
                                     width: Int(w), height: Int(h))
        }

        config.on_popup_mapped = { (userdata, windowId, parentId, x, y, w, h) in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            this.handlePopupMapped(windowId, parentId: parentId,
                                    x: Int(x), y: Int(y), width: Int(w), height: Int(h))
        }

        config.on_popup_unmapped = { (userdata, windowId) in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            this.handlePopupUnmapped(windowId)
        }

        config.on_window_destroyed = { (userdata, windowId) in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            this.handleWindowDestroyed(windowId)
        }

        config.on_window_unmapped = { (userdata, windowId) in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            this.handleWindowDestroyed(windowId)
        }

        config.on_present_buffer = { (userdata, windowId, fd, w, h, stride, fourcc) in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            this.handlePresentBuffer(windowId, fd: fd, width: Int(w), height: Int(h),
                                      stride: Int(stride), fourcc: fourcc)
        }

        config.on_present_image = { (userdata, windowId, pixels, w, h) in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            guard let pixels = pixels else { return }
            this.handlePresentImage(windowId, pixels: pixels,
                                     width: Int(w), height: Int(h))
        }

        config.on_title_changed = { (userdata, windowId, title) in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            guard let title = title else { return }
            this.handleTitleChanged(windowId, title: String(cString: title))
        }

        // GetImage / screen capture (Zoom screen share): arm the compositor's
        // capture mirror and copy the requested rect out as X ZPixmap BGRX.
        config.capture_screen = { (userdata, x, y, w, h, dst, dstLen) -> Int32 in
            let this = Unmanaged<X11Integration>.fromOpaque(userdata!).takeUnretainedValue()
            guard let view = this.drmView, let dst = dst else { return 0 }
            fl_drm_view_arm_capture(view)
            return Int32(fl_drm_view_read_capture(x, y, w, h, dst, dstLen))
        }

        server = x11_server_create(Int32(displayNum), &config)
        if let server = server {
            /* Create a wakeup eventfd for client data notification.
             * When a new client connects, we write to this eventfd.
             * The eventfd is registered with DRM epoll (uses 1 slot, not per-client).
             * When it fires, dispatch() polls ALL client fds. */
            if let view = drmView {
                var pipeFds: [Int32] = [0, 0]
                if pipe(&pipeFds) == 0 {
                    wakeupReadFd = pipeFds[0]
                    wakeupWriteFd = pipeFds[1]
                    // Make both non-blocking
                    let fl0 = fcntl(wakeupReadFd, F_GETFL, 0)
                    fcntl(wakeupReadFd, F_SETFL, fl0 | O_NONBLOCK)
                    let fl1 = fcntl(wakeupWriteFd, F_GETFL, 0)
                    fcntl(wakeupWriteFd, F_SETFL, fl1 | O_NONBLOCK)
                    // Register READ end with DRM epoll (1 slot, not per-client)
                    fl_drm_view_add_external_fd(view, wakeupReadFd, { _ in
                        guard let x = x11Integration, let server = x.server else { return }
                        // Drain the pipe
                        var buf = [UInt8](repeating: 0, count: 64)
                        while read(x.wakeupReadFd, &buf, 64) > 0 {}
                        x.dispatchEvents()
                        // Re-signal for more dispatch but limit to prevent
                        // starving the engine's timerfd (vsync).
                        x.wakeupCounter += 1
                        if x11_server_has_clients(server) != 0 && x.wakeupCounter < 500 {
                            x.scheduleWakeup()
                        }
                    }, nil)
                }
            }

            // Register vblank timer with epoll — triggers shm_fences so Chrome's
            // GPU process doesn't deadlock waiting for buffer completion.
            // Without this, the last PresentPixmap's fence is never triggered.
            // NOT armed here. The timer is armed by the server itself when a
            // client connects and disarmed when the last one leaves -- armed
            // from startup it woke the shell 62.5 times a second forever, on a
            // desktop where nothing ever connects. The fd is still registered
            // with epoll below; an unarmed timerfd simply never fires.
            let vblankFd = x11_server_get_vblank_timer_fd(server)
            if vblankFd >= 0, let view = drmView {
                fl_drm_view_add_external_fd(view, vblankFd, { _ in
                    guard let x = x11Integration, let s = x.server else { return }
                    // Dispatch incoming client data BEFORE sending vblank events.
                    // Chrome sends requests between frames (e.g. GetSelectionOwner)
                    // and blocks in xcb_wait_for_reply until we process them.
                    // Without this, the xcb reader thread deadlocks and Present
                    // events are never delivered to Chrome's WSI swapchain thread.
                    x11_server_dispatch(s)
                    x11_server_vblank_tick(s)
                    // Also process any texture marks from dispatched PresentPixmaps
                    if x.flushPendingTextureMarks() {
                        PlatformDispatcher.instance.scheduleFrame()
                    }
                }, nil)
            }

            // When a new client connects, signal the wakeup pipe and reset counter
            x11_server_set_client_connect_callback(server, { (clientFd, userData) in
                guard let x = x11Integration else { return }
                x.wakeupCounter = 0  // Reset — allow more dispatch cycles
                if x.wakeupWriteFd >= 0 {
                    var byte: UInt8 = 1
                    _ = write(x.wakeupWriteFd, &byte, 1)
                }
            }, nil)
        }
    }

    /// Stop the X11 server.
    func stop() {
        if let server = server {
            x11_server_destroy(server)
            self.server = nil
        }
    }

    /// Get the listening socket fd for epoll.
    var serverFd: Int {
        guard let server = server else { return -1 }
        return Int(x11_server_get_fd(server))
    }

    /// Whether the connected-client count changed since last asked, and if so
    /// tell the shell.
    ///
    /// The frame pump only polls for a screen capture starting while an X
    /// client is connected -- nothing announces a GetImage. A connect is
    /// therefore what arms that poll, and a disconnect is what stops it; both
    /// become visible to Swift here, because dispatch is what accepts and
    /// reaps connections.
    private var _lastClientCount: Int32 = 0
    private func _noteClientCount() {
        guard let server else { return }
        let n = x11_server_client_count(server)
        guard n != _lastClientCount else { return }
        _lastClientCount = n
        onClientCountChanged?()
    }

    /// Set by the shell.
    var onClientCountChanged: (() -> Void)?

    /// Dispatch pending X11 events.
    func dispatchEvents() {
        guard let server = server else { return }
        x11_server_dispatch(server)
        _noteClientCount()
        if flushPendingTextureMarks() {
            // Also schedule via PlatformDispatcher to ensure the engine
            // processes the frame even when called from an epoll callback
            PlatformDispatcher.instance.scheduleFrame()
        }
    }

    /// Schedule a delayed wakeup to re-dispatch after clients have time to send data.
    func scheduleWakeup() {
        if wakeupWriteFd >= 0 {
            var byte: UInt8 = 1
            _ = write(wakeupWriteFd, &byte, 1)
        }
    }

    /// Dispatch + schedule frame (called from listen socket epoll only).
    func dispatchAndScheduleFrame() {
        guard let server = server else { return }
        x11_server_dispatch(server)
        _noteClientCount()
        FlutterEngineScheduleFrame(engine)
    }

    /// Called from FrameCallbackScheduler — dispatch + schedule next frame
    /// if X11 clients are connected.
    func onFrameBegin() {
        guard let server = server else { return }
        x11_server_dispatch(server)
    }

    // MARK: - Event Handlers

    private func handleWindowMapped(_ windowId: UInt32, x: Int, y: Int,
                                     width: Int, height: Int) {
        let textureId = textureRegistry.registerTexture(engine: engine)
        windowTextures[windowId] = textureId

        // Peer pid, captured while the client is certainly still connected.
        // The dock's Quit needs it to escalate past a client that ignores
        // WM_DELETE_WINDOW; reading it at Quit time races the client's own
        // teardown. Zoom is the case that matters — one X connection fronting
        // an eleven-process tree that survives losing its window.
        if let server = server {
            let pid = x11_server_window_pid(server, windowId)
            if pid > 0 { windowPids[windowId] = pid }
        }

        if let shellWindowId = onNewWindow?(windowId, Int(textureId), "X11 App",
                                             x, y, width, height) {
            windowIds[windowId] = shellWindowId
        } else {
            // print("[X11Integration] WARNING: onNewWindow callback not set!")
        }
    }

    /// Override-redirect toplevel: a menu, dropdown or tooltip. It gets a
    /// texture like any other window (the present paths key off windowTextures,
    /// so PutImage/DRI3 content lands without any extra plumbing) but the shell
    /// draws it undecorated, anchored to its parent toplevel.
    private func handlePopupMapped(_ windowId: UInt32, parentId: UInt32,
                                    x: Int, y: Int, width: Int, height: Int) {
        guard windowTextures[windowId] == nil else { return }
        let textureId = textureRegistry.registerTexture(engine: engine)
        windowTextures[windowId] = textureId
        if let popupId = onNewPopup?(windowId, Int(textureId), parentId,
                                      x, y, width, height) {
            popupIds[windowId] = popupId
        }
    }

    private func handlePopupUnmapped(_ windowId: UInt32) {
        if let popupId = popupIds.removeValue(forKey: windowId) {
            onPopupDestroyed?(popupId)
        }
        if let textureId = windowTextures.removeValue(forKey: windowId) {
            textureRegistry.unregisterTexture(engine: engine, id: textureId)
        }
    }

    /// Shell window id for an X11 window — lets the popup renderer resolve the
    /// toplevel a menu is anchored to, the same way it does for Wayland.
    func shellWindowId(forX11Window windowId: UInt32) -> String? {
        return windowIds[windowId]
    }

    private func handleWindowDestroyed(_ windowId: UInt32) {
        windowPids.removeValue(forKey: windowId)
        // print("[X11Integration] Window destroyed: 0x\(String(windowId, radix: 16))")

        if let shellWindowId = windowIds.removeValue(forKey: windowId) {
            onWindowDestroyed?(shellWindowId)
        }
        if let textureId = windowTextures.removeValue(forKey: windowId) {
            textureRegistry.unregisterTexture(engine: engine, id: textureId)
        }
    }

    /// Texture IDs that received new DMA-BUF content and need MarkExternalTexture.
    private var pendingTextureMarks: [Int64] = []

    /// Software present: a raster client (Qt, GTK, xclock) pushed CPU pixels
    /// with PutImage / ShmPutImage instead of handing us a DRI3 dma-buf.
    /// The pixels are only valid for this call, so upload synchronously.
    private func handlePresentImage(_ windowId: UInt32,
                                     pixels: UnsafePointer<UInt8>,
                                     width: Int, height: Int) {
        guard let textureId = windowTextures[windowId], width > 0, height > 0 else { return }

        textureRegistry.updatePixelData(
            engine: engine, id: textureId,
            data: UnsafeRawPointer(pixels), width: width, height: height
        )

        // Same bookkeeping the dma-buf path does, minus the EGLImage import:
        // keep frames scheduled and let the shell size the window to content.
        pendingTextureMarks.append(textureId)
        FrameCallbackScheduler.shared.noteTextureUpdate(textureId)

        let lastSize = lastImportedSize[textureId]
        if lastSize == nil || lastSize!.width != width || lastSize!.height != height {
            lastImportedSize[textureId] = (width, height)
            if let shellWindowId = windowIds[windowId] {
                onWindowBufferResized?(shellWindowId, width, height)
            } else if let popupId = popupIds[windowId] {
                onPopupBufferResized?(popupId, width, height)
            }
        }
        if let shellWindowId = windowIds[windowId] {
            onBufferPresented?(shellWindowId)
        }
    }

    private func handlePresentBuffer(_ windowId: UInt32, fd: Int32,
                                      width: Int, height: Int,
                                      stride: Int, fourcc: UInt32) {
        guard let textureId = windowTextures[windowId] else { return }

        // Check if dimensions changed — only then destroy old EGLImage.
        // reimportDmaBuf is expensive (destroy + recreate EGLImage).
        // For same-size frames, importDmaBuf just updates the fd and rebinds.
        let lastSize = lastImportedSize[textureId]
        if lastSize == nil || lastSize!.width != width || lastSize!.height != height {
            lastImportedSize[textureId] = (width, height)
            textureRegistry.reimportDmaBuf(
                engine: engine, id: textureId,
                fd: fd, width: width, height: height,
                stride: stride, fourcc: fourcc
            )
        } else {
            textureRegistry.importDmaBuf(
                engine: engine, id: textureId,
                fd: fd, width: width, height: height,
                stride: stride, fourcc: fourcc
            )
        }

        // Flush pending resize if throttle interval elapsed
        if let pending = pendingResize[windowId], let server = server {
            let now = DispatchTime.now().uptimeNanoseconds
            let last = lastResizeTime[windowId] ?? 0
            if now - last >= resizeIntervalNs {
                pendingResize.removeValue(forKey: windowId)
                lastResizeTime[windowId] = now
                x11_server_configure_window(server, windowId,
                                             Int32(pending.width), Int32(pending.height))
            }
        }

        // Queue texture for marking after dispatch returns to the epoll loop.
        pendingTextureMarks.append(textureId)

        // Tell FrameCallbackScheduler to keep scheduling frames
        // (same mechanism Wayland uses for continuous rendering)
        FrameCallbackScheduler.shared.noteTextureUpdate(textureId)

        if let shellWindowId = windowIds[windowId] {
            // Notify shell of buffer dimensions so window rect matches texture
            if lastSize == nil || lastSize?.width != width || lastSize?.height != height {
                onWindowBufferResized?(shellWindowId, width, height)
            }
            onBufferPresented?(shellWindowId)
        } else if let popupId = popupIds[windowId],
                  lastSize == nil || lastSize?.width != width || lastSize?.height != height {
            // Menus are routinely mapped at a placeholder size and resized
            // before their first frame — Zoom's maps 496x32 and then presents
            // 496x400. Without this the popup is drawn as a sliver of itself.
            onPopupBufferResized?(popupId, width, height)
        }
    }

    /// Call after dispatch to mark textures that received new DMA-BUF content.
    /// Returns true if any textures were marked (caller should schedule a frame).
    @discardableResult
    func flushPendingTextureMarks() -> Bool {
        let hadMarks = !pendingTextureMarks.isEmpty
        for id in pendingTextureMarks {
            FlutterEngineMarkExternalTextureFrameAvailable(engine, id)
        }
        if hadMarks {
            FlutterEngineScheduleFrame(engine)
        }
        pendingTextureMarks.removeAll()
        return hadMarks
    }

    private func handleTitleChanged(_ windowId: UInt32, title: String) {
        if let shellWindowId = windowIds[windowId] {
            onTitleChanged?(shellWindowId, title)
        }
    }

    // MARK: - Input Forwarding

    /// Forward a pointer event to the X11 client.
    /// phase: 1=up, 2=down, 3=move, 6=hover (matches DesktopWindow convention)
    func sendPointerEvent(windowId: UInt32, phase: Int32, x: Double, y: Double, buttons: Int64) {
        guard let server = server else { return }

        // Auto-focus and send EnterNotify on pointer entry
        x11_server_set_focus(server, windowId)
        if lastPointerWindowId != windowId {
            if lastPointerWindowId != 0 {
                x11_server_leave_notify(server, lastPointerWindowId, Int32(x), Int32(y))
            }
            x11_server_enter_notify(server, windowId, Int32(x), Int32(y))
            lastPointerWindowId = windowId
        }

        switch phase {
        case 2: // down
            x11_server_pointer_button(server, 1, 1, Int32(x), Int32(y))  // BTN_LEFT
        case 1: // up
            x11_server_pointer_button(server, 1, 0, Int32(x), Int32(y))
        case 3: // move (dragging)
            x11_server_pointer_motion(server, Int32(x), Int32(y))
        case 6: // hover
            x11_server_pointer_motion(server, Int32(x), Int32(y))
        default:
            break
        }
    }

    /// Ask the client owning `windowId` to close (WM_DELETE_WINDOW).
    func requestClose(windowId: UInt32) {
        guard let server = server else { return }
        x11_server_close_window(server, windowId)
    }

    /// pid behind an X11 window, captured when it was mapped.
    func clientPid(windowId: UInt32) -> pid_t? {
        return windowPids[windowId]
    }

    /// Send a resize to the X11 window.
    /// Throttled at 33ms (~30fps) + pending buffer for final size delivery.
    func sendResize(windowId: UInt32, width: Int, height: Int) {
        guard let server = server else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if let last = lastResizeTime[windowId], now - last < resizeIntervalNs {
            pendingResize[windowId] = (width, height)
            return
        }
        pendingResize.removeValue(forKey: windowId)
        lastResizeTime[windowId] = now
        x11_server_configure_window(server, windowId, Int32(width), Int32(height))
    }

    /// True when a resize was recently sent for a given shell window ID.
    /// Used by DesktopShell to suppress onWindowBufferResized during active drag.
    func isResizing(shellWindowId: String) -> Bool {
        // Reverse-lookup: shell windowId → X11 windowId
        guard let x11Id = windowIds.first(where: { $0.value == shellWindowId })?.key else {
            return false
        }
        guard let t = lastResizeTime[x11Id] else { return false }
        return DispatchTime.now().uptimeNanoseconds - t < resizeIntervalNs * 3
    }

    /// Send a key event to the focused X11 window.
    func sendKeyEvent(keycode: UInt32, pressed: Bool) {
        guard let server = server else { return }
        x11_server_key_event(server, keycode, pressed ? 1 : 0)
    }

    /// Set focus to a specific X11 window.
    func setFocus(windowId: UInt32) {
        guard let server = server else { return }
        x11_server_set_focus(server, windowId)
    }

    /// Release the current buffer for a window so the client can reuse it.
    func releaseBuffer(windowId: UInt32) {
        guard let server = server else { return }
        x11_server_release_buffer(server, windowId)
    }

    /// Test resize: resize the first X11 window to a new size.
    func testResize(width: Int, height: Int) {
        guard let server = server else { return }
        guard let firstWindowId = windowTextures.keys.first else {
            return
        }
        x11_server_configure_window(server, firstWindowId, Int32(width), Int32(height))
    }
}
