// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import Flutter
import FlutterSwiftBridge
import GuestDisplay
import WaylandServerBridge
import Glibc

/// One VM console on the desktop — Phase 4 of docs/plans/guest-display.md.
///
/// A guest window is a texture-backed `WindowInfo` and nothing more. The
/// scanout is a dma-buf the texture registry imports, input goes back out as
/// scancodes and absolute pointer positions, and everything the desktop does
/// with windows — dock, spaces, Mission Control, resize, focus — comes free
/// because none of it knows what a texture holds.
///
/// Threading: `GuestDisplay` calls back on its own bus thread. Every callback
/// that touches shell state hops to the PLATFORM thread (`onPlatformThread`
/// — the framework's thread, which is not the main queue); the frame ack is
/// drained from the compositor's present callback on that same thread. The
/// CLIPBOARD is the exception and stays on the main queue: its provider is
/// a Wayland client of this shell's own compositor, and the compositor runs
/// on the platform thread — a client connecting from there waits on itself.
/// That deadlock was measured, not reasoned about: the first build that
/// hopped everything to the platform thread hung on the guest's connect,
/// with the scanouts posted behind it and never run. `@unchecked`
/// because that split is the design and the compiler cannot see it: everything
/// but the ack queue is main-thread state, and the ack queue carries its own
/// lock precisely so it does not have to be.
final class GuestSession: @unchecked Sendable {

    let domain: String
    /// The registry record's id, e.g. "windows". Becomes the window's
    /// wmClass, which is how `_appOwning` resolves the dock icon and menu.
    let appId: String
    let appName: String

    /// Raised on the main thread when the connection cannot be made or is
    /// lost. The detail is libvirt's or sd-bus's own message.
    var onFailure: ((String) -> Void)?
    /// Raised on the main thread the first time a window exists.
    var onWindowOpened: ((String) -> Void)?
    /// Raised when the session has torn itself down and should be forgotten.
    var onClosed: (() -> Void)?
    /// Something the person should hear about, as a desktop notification:
    /// (summary, body). Set by the launch arm; seamless mode uses it for
    /// "the helper is not running" and "the guest is showing a window we
    /// cannot".
    var onNotice: ((String, String) -> Void)?

    /// How the guest is presented — the whole desktop in one window, or one
    /// window per guest app (`GuestSeamless`). Mutually exclusive by decision
    /// (`docs/plans/guest-seamless.md`): two windows showing the same pixels
    /// is the confusion that avoids.
    enum Mode { case console, seamless }
    private(set) var mode: Mode = .console
    /// The mode to enter once the display is connected. Set before `open()`.
    var preferredMode: Mode = .console
    private var seamless: GuestSeamless?
    /// Work that needs the helper — launching an app inside the guest —
    /// queued until seamless mode has its helper, dropped if it never does.
    private var whenReady: [(GuestSession) -> Void] = []
    /// A guest app's window appeared, by record id (Phase 5).
    var onAppWindow: ((String) -> Void)?

    // MARK: - Agents (M3, docs/plans/guest-agents.md)

    /// A launch an agent asked for, waiting for its window. Ownership pairs
    /// by IDENTITY inside a bounded window, never by pid: a packaged app's
    /// launch pid is a broker's, and Chrome is many processes.
    struct AgentPairing {
        let agentId: String
        let recordId: String
        let deadline: Date
        let onWindow: (String) -> Void
    }
    private var agentPairings: [AgentPairing] = []

    /// The next window whose record is `record` belongs to `agent`, if it
    /// arrives inside ten seconds.
    func expectAgentWindow(record: String, agent: String,
                           onWindow: @escaping (String) -> Void) {
        agentPairings.append(AgentPairing(agentId: agent, recordId: record,
                                          deadline: Date().addingTimeInterval(10),
                                          onWindow: onWindow))
    }

    /// Consume the pairing for a record, if one is live.
    func takeAgentPairing(forRecord record: String) -> AgentPairing? {
        let now = Date()
        agentPairings.removeAll { $0.deadline < now }
        guard let i = agentPairings.firstIndex(where: { $0.recordId == record }) else { return nil }
        return agentPairings.remove(at: i)
    }

    func cancelAgentPairing(record: String, agent: String) {
        agentPairings.removeAll { $0.recordId == record && $0.agentId == agent }
    }

    /// The seat lease. A Windows session has one input queue and one
    /// foreground window, so while the person has a window of this guest
    /// focused, an agent's pointer or keys would land in their hands.
    var humanIsUsing: Bool {
        guard let wm = _shellState?.windowManager, let f = wm.focusedWindowId,
              let win = wm.windows.first(where: { $0.id == f }) else { return false }
        return win.ownerAgentId == nil && owns(f)
    }

    /// Raise a window in the guest before an agent's input, because that
    /// input goes wherever the guest's foreground is. Completes at once when
    /// it already is.
    func activateForAgent(windowId: String, completion: @escaping (Bool) -> Void) {
        guard let sm = seamless else { completion(false); return }
        sm.activate(windowId: windowId, completion: completion)
    }

    private var gd: OpaquePointer?
    private(set) var textureId: Int64?
    private(set) var windowId: String?
    private var closed = false

    /// The scanout's own pixel size — guest pixels, which are also physical
    /// pixels, because the guest renders at content size times our dpi.
    private(set) var guestSize: (w: Int, h: Int)?
    private(set) var flipY = false

    /// Damage tokens waiting for a present. Written on the bus thread, drained
    /// on the platform thread, so it carries its own lock rather than riding
    /// the main queue — an ack that waits for the main thread is an ack that
    /// arrives after the frame it was pacing.
    private let ackLock = NSLock()
    private var pendingTokens: [UInt64] = []
    /// One main-thread hop per burst of damage, not one per rect.
    private var markScheduled = false

    private var heldKeys: Set<UInt32> = []

    private var cursorBGRA: [UInt8] = []
    private var cursorW = 0, cursorH = 0, cursorHotX = 0, cursorHotY = 0
    private var cursorVisible = true
    /// Bumped on every cursor change; the hover hook re-asserts only when it
    /// differs from what the plane last got, so hovering does not re-upload a
    /// GBM buffer per pointer event.
    private var cursorGen: UInt64 = 0
    /// Whether the guest has ever sent a bitmap. Separate from `cursorGen`,
    /// which counts every reason the plane might need re-asserting.
    private var sawCursorDefine = false
    private var cursorGenOnPlane: UInt64 = .max

    /// Our own data-control client, so the guest's clipboard and the
    /// desktop's are the same clipboard. The shell is a CLIENT of its own
    /// compositor here, on the bridge's private thread and connection —
    /// docs/plans/clipboard.md is explicit that the shell must not broker a
    /// pull-based clipboard itself.
    private var clip: WaylandClipboardProvider?

    private var resizeDebounce: DispatchWorkItem?
    private var requestedSize: (w: Int, h: Int)?
    private var requestedAt: Date?

    /// Buttons the guest currently believes are down, as a Flutter mask.
    private var buttonMask: Int64 = 0
    private var scrollAccumX = 0.0
    private var scrollAccumY = 0.0
    /// One libinput scroll unit is 20 Flutter pixels (fl_drm_input.cc's
    /// HandlePointerAxis), so that is one wheel notch to the guest.
    private static let kScrollNotch = 20.0

    init(domain: String, appId: String, appName: String) {
        self.domain = domain
        self.appId = appId
        self.appName = appName
    }

    // MARK: - Lifecycle

    /// Opens the display. Returns at once; failure arrives through
    /// `onFailure`. Call on the main thread.
    func open() {
        var cb = GuestDisplayCallbacks()
        cb.ctx = Unmanaged.passUnretained(self).toOpaque()
        cb.on_state = { ctx, state, detail in
            guard let ctx else { return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            let text = detail.map { String(cString: $0) }
            onPlatformThread { me.handleState(Int(state), text) }
        }
        cb.on_scanout = { ctx, fd, w, h, stride, offset, fourcc, modifier, y0Top in
            guard let ctx else { if fd >= 0 { Glibc.close(fd) }; return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            FileHandle.standardError.write(Data(
                "[guest] scanout \(w)x\(h) fd \(fd) received on the bus thread\n".utf8))
            onPlatformThread {
                me.handleScanout(fd: fd, width: Int(w), height: Int(h),
                                 stride: Int(stride), offset: Int(offset),
                                 fourcc: fourcc, modifier: modifier,
                                 y0Top: y0Top != 0)
            }
        }
        cb.on_update = { ctx, token, _, _, _, _ in
            guard let ctx else { return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            me.handleUpdate(token: token)
        }
        cb.on_disable = { ctx in
            guard let ctx else { return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            onPlatformThread { me.handleDisable() }
        }
        cb.on_cursor_define = { ctx, w, h, hx, hy, bgra, len in
            guard let ctx, let bgra, len > 0 else { return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            let bytes = [UInt8](UnsafeBufferPointer(start: bgra, count: len))
            onPlatformThread {
                me.handleCursorDefine(bytes, w: Int(w), h: Int(h),
                                      hotX: Int(hx), hotY: Int(hy))
            }
        }
        cb.on_mouse_set = { ctx, _, _, visible in
            guard let ctx else { return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            onPlatformThread { me.handleMouseSet(visible: visible != 0) }
        }
        cb.on_clipboard_request = { ctx, token, mime in
            guard let ctx else { return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            let m = mime.map { String(cString: $0) } ?? "text/plain;charset=utf-8"
            // Main queue, not the platform thread: see the clipboard note above.
            DispatchQueue.main.async { me.handleClipboardRequest(token: token, mime: m) }
        }
        cb.on_clipboard_grab = { ctx, mimes, n in
            guard let ctx else { return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            // The guest copied something. Pull it and make it the desktop's
            // selection. Only ever arrives from a QEMU carrying patches/0003.
            var wanted: String? = nil
            if let mimes {
                for i in 0..<Int(n) {
                    guard let m = mimes[i] else { continue }
                    let s = String(cString: m)
                    if s.hasPrefix("text/") || s == "UTF8_STRING" {
                        wanted = s
                        break
                    }
                }
            }
            guard let mime = wanted else { return }
            FileHandle.standardError.write(Data(
                "[guest] the guest copied \(mime); pulling it\n".utf8))
            me.pullFromGuest(mime: mime)
        }
        cb.on_clipboard_release = { _ in }
        cb.on_clipboard_data = { ctx, mime, data, len in
            guard let ctx, let data, len > 0 else { return }
            let me = Unmanaged<GuestSession>.fromOpaque(ctx).takeUnretainedValue()
            let text = String(decoding: UnsafeRawBufferPointer(start: data,
                                                              count: len),
                              as: UTF8.self)
            let deliver: () -> Void = { me.handleClipboardData(text) }
            DispatchQueue.main.async(
                execute: unsafeBitCast(deliver, to: (@Sendable () -> Void).self))
        }

        gd = domain.withCString { guest_display_open($0, &cb) }
        if gd == nil {
            onFailure?("could not start the guest display thread")
        }
    }

    /// Detaches from the domain and drops the window. The VM keeps running —
    /// closing the console is not shutting Windows down, and reopening is
    /// instant. "Shut Down Windows" is an explicit dock-menu item.
    func close() {
        guard !closed else { return }
        closed = true
        resizeDebounce?.cancel()
        seamless?.stop()
        seamless = nil
        // The provider lives on the main queue (clipboard note above).
        DispatchQueue.main.async { [self] in
            clip?.onSelectionChanged = nil
            clip = nil
        }
        if let gd {
            guest_display_close(gd)
            self.gd = nil
        }
        if let id = textureId, let wl = waylandIntegration {
            drmTextureRegistry?.unregisterTexture(engine: wl.engine, id: id)
        }
        textureId = nil
        if let winId = windowId {
            windowId = nil
            _shellState?.setState {
                _shellState?.windowManager.closeWindow(winId)
            }
        }
        onClosed?()
    }

    // MARK: - Connection state

    private func handleState(_ state: Int, _ detail: String?) {
        guard !closed else { return }
        switch state {
        case Int(GUEST_DISPLAY_FAILED):
            onFailure?(detail ?? "the guest display could not be opened")
            close()
        case Int(GUEST_DISPLAY_CONNECTED):
            startClipboard()
            if preferredMode == .seamless { setMode(.seamless) }
        case Int(GUEST_DISPLAY_DISCONNECTED):
            // No reconnect in M1: one control client per domain, and the
            // window without a connection behind it is a lie.
            onFailure?(detail ?? "the guest display disconnected")
            close()
        default:
            break
        }
    }

    private func handleDisable() {
        // The console went away (guest reset, display off). The window stays,
        // showing the last frame, until a scanout comes back — a reboot is not
        // a reason to throw the user's window away.
    }

    // MARK: - Clipboard

    /// Host -> guest. We announce (`Grab`) whenever the desktop's selection
    /// changes to something textual; the guest pulls (`Request`) when someone
    /// actually pastes, and we answer with the selection as it is THEN — which
    /// is the whole reason this is announce-then-pull and not a copy.
    private func startClipboard() {
        guard !closed else { return }
        guest_display_clipboard_enable(gd)
        // Connecting to the compositor is a round trip the compositor has to
        // answer, and this runs on the compositor's own thread: hop to the
        // main queue first (clipboard note above), and keep `clip` there.
        DispatchQueue.main.async { [self] in
            guard clip == nil, !closed else { return }
            guard let socket = waylandIntegration?.socketName,
                  let provider = WaylandClipboardProvider(display: socket) else {
                FileHandle.standardError.write(Data(
                    "[guest] no data-control clipboard to bridge\n".utf8))
                return
            }
            clip = provider
            attachClipboard(provider)
        }
    }

    private func attachClipboard(_ provider: WaylandClipboardProvider) {
        provider.onSelectionChanged = { [weak self] hasText, mine in
            // `mine` is the loop guard: answering the guest makes US the
            // owner, and announcing that back to the guest would be an
            // announcement per paste, for ever.
            guard hasText, !mine else { return }
            // The bridge fires on its own thread and this closure is not
            // Sendable; the same cast the SDK's clipboard completion uses
            // (Clipboard.swift's deliverOnMain) carries it to the UI thread.
            let announce: () -> Void = {
                guard let self, !self.closed, let gd = self.gd else { return }
                var mime = strdup("text/plain;charset=utf-8")
                withUnsafeMutablePointer(to: &mime) { p in
                    p.withMemoryRebound(to: Optional<UnsafePointer<CChar>>.self,
                                        capacity: 1) { mimes in
                        guest_display_clipboard_grab(gd, mimes, 1)
                    }
                }
                free(mime)
            }
            DispatchQueue.main.async(
                execute: unsafeBitCast(announce, to: (@Sendable () -> Void).self))
        }
    }

    /// Bus thread — the command is queued, so this is safe from a callback.
    private func pullFromGuest(mime: String) {
        guard let gd else { return }
        mime.withCString { guest_display_clipboard_pull(gd, $0) }
    }

    /// The guest's selection, on its way to becoming the desktop's. Setting it
    /// makes US the owner, so the next `onSelectionChanged` arrives with
    /// `mine` true and announces nothing back — which is what stops this from
    /// being a copy that bounces between the two clipboards for ever.
    private func handleClipboardData(_ text: String) {
        guard !closed, let clip, !text.isEmpty else { return }
        FileHandle.standardError.write(Data(
            "[guest] the guest's clipboard is now the desktop's (\(text.utf8.count) bytes)\n".utf8))
        clip.setText(text)
    }

    private func handleClipboardRequest(token: UInt64, mime: String) {
        FileHandle.standardError.write(Data(
            "[guest] the guest is pasting; wants \(mime)\n".utf8))
        guard !closed, let gd, let clip else {
            // Answer with nothing rather than leave the guest's paste hanging
            // on a 25 s D-Bus timeout.
            if let gd { guest_display_clipboard_reply(gd, token, mime, nil, 0) }
            return
        }
        clip.getText { text in
            guard let text, !text.isEmpty else {
                guest_display_clipboard_reply(gd, token, mime, nil, 0)
                return
            }
            let bytes = Array(text.utf8)
            FileHandle.standardError.write(Data(
                "[guest] answering the paste with \(bytes.count) bytes\n".utf8))
            bytes.withUnsafeBufferPointer { buf in
                guest_display_clipboard_reply(gd, token, mime, buf.baseAddress,
                                              buf.count)
            }
        }
    }

    // MARK: - Frames

    private func handleScanout(fd: Int32, width: Int, height: Int, stride: Int,
                               offset: Int, fourcc: UInt32, modifier: UInt64,
                               y0Top: Bool) {
        guard !closed, let wl = waylandIntegration,
              let registry = drmTextureRegistry else {
            FileHandle.standardError.write(Data(
                "[guest] scanout dropped: closed=\(closed) wayland=\(waylandIntegration != nil) registry=\(drmTextureRegistry != nil)\n".utf8))
            Glibc.close(fd)
            return
        }
        // The import hardcodes plane 0 at offset 0 (dmabuf_helpers.c). Every
        // scanout the spike saw was offset 0; importing one that is not would
        // show the guest's desktop shifted by a scanline or two with nothing
        // to say why, so refuse it out loud instead.
        guard offset == 0 else {
            FileHandle.standardError.write(Data(
                "[guest] scanout at offset \(offset) — the dma-buf import only handles 0; frame dropped\n"
                    .utf8))
            Glibc.close(fd)
            return
        }
        // A modifier we never advertised must not reach the driver: an
        // eglCreateImageKHR on a foreign tiled layout can allocate-then-fail
        // and abort the shell under memory pressure. The guest's buffers are
        // INVALID, which always passes; this is for the day one is not.
        guard wayland_server_dmabuf_modifier_importable(fourcc, modifier) != 0 else {
            FileHandle.standardError.write(Data(
                "[guest] scanout modifier 0x\(String(modifier, radix: 16)) is not importable; frame dropped\n"
                    .utf8))
            Glibc.close(fd)
            return
        }

        let sizeChanged = guestSize.map { $0.w != width || $0.h != height } ?? true
        if textureId == nil {
            textureId = registry.registerTexture(engine: wl.engine)
        }
        guard let texId = textureId else { Glibc.close(fd); return }

        // ALWAYS reimport. A scanout means "here is a different buffer", and
        // only reimport sets needsReimport — the plain import path rebinds the
        // EGLImage it already has and ignores the new fd entirely. That is not
        // hypothetical: QEMU answers a resize with its placeholder XB24 buffer
        // and then the guest's real AB24 one AT THE SAME SIZE, so keying the
        // choice on dimensions dropped the real buffer and left the window
        // showing the blank placeholder. It looked exactly like the guest had
        // stopped painting. Damage on the SAME buffer is the other case, and
        // that goes through noteDmaBufContentChanged, not here — so this
        // costs one EGLImage per mode change, and the registry's per-buffer
        // cache makes even that a lookup when the buffer comes back.
        registry.reimportDmaBuf(engine: wl.engine, id: texId, fd: fd,
                                width: width, height: height,
                                stride: stride, fourcc: fourcc,
                                modifier: modifier, ownsFd: true)
        guestSize = (width, height)

        // Two inversions, both of which have to be right or Windows is upside
        // down. QEMU's `y0_top` means the OPPOSITE of what it reads like:
        // FALSE is the ordinary top-down layout (row 0 = top — blob scanouts
        // and QEMU's own placeholder), TRUE marks a GL-rendered texture whose
        // row 0 is the bottom. And `flipTextureY` is the widget-layer flip
        // this shell applies to a TOP-DOWN buffer, which is why every X11
        // window sets it. A bottom-up buffer is already what GL sampling
        // expects, so the two cancel: flip when y0_top is false, not when it
        // is true. Measured against a real guest — the first run had it the
        // other way and put the taskbar at the top of the window.
        //
        // Per SCANOUT, not per window: the placeholder says one thing and the
        // guest's real buffer another, and both are re-sent on every resize.
        flipY = !y0Top
        if mode == .seamless {
            // No console window; every guest window's crop is relative to
            // this scanout, and the first one cannot be made before it.
            seamless?.scanoutChanged()
        } else if let winId = windowId,
           let win = _shellState?.windowManager.windows.first(where: { $0.id == winId }) {
            if win.flipTextureY != flipY {
                _shellState?.setState { win.flipTextureY = self.flipY }
            }
            if sizeChanged { noteGuestResized(width: width, height: height) }
        } else {
            openWindow(width: width, height: height)
        }
        FrameCallbackScheduler.shared.noteTextureUpdate(texId)
        // The scanout is the first frame: without it on record, a settle
        // asked before the first damage update saw a texture that had never
        // drawn and answered at once (measured on a fresh session: 0 ms).
        _shellState?._agentBroker?.noteFrame(textureId: Int64(texId))
    }

    // MARK: - Mode

    /// True for the console window and for every seamless window — the
    /// question the key router and the focus hook ask.
    func owns(_ id: String) -> Bool {
        windowId == id || seamless?.owns(id) == true
    }

    /// Switch between the console and one-window-per-app. Either way the
    /// display, the texture and the clipboard stay; only the windows change.
    func setMode(_ new: Mode) {
        guard !closed, new != mode else { return }
        switch new {
        case .seamless:
            if let winId = windowId, let shell = _shellState {
                windowId = nil
                shell.setState {
                    if let win = shell.windowManager.windows.first(where: { $0.id == winId }) {
                        // Closing the console must not detach the session.
                        win.onWindowClose = nil
                    }
                    shell.windowManager.closeWindow(winId)
                }
            }
            mode = .seamless
            let sm = GuestSeamless(session: self)
            sm.onUnavailable = { [weak self] detail in
                guard let self, !self.closed else { return }
                self.onNotice?("Windows apps cannot be shown as windows", detail)
                self.whenReady.removeAll()
                self.seamless = nil
                self.setMode(.console)
            }
            sm.onReady = { [weak self] in
                guard let self else { return }
                let queued = self.whenReady
                self.whenReady.removeAll()
                for work in queued { work(self) }
            }
            sm.onAppWindow = { [weak self] id in self?.onAppWindow?(id) }
            seamless = sm
            sm.start()
            // The guest's desktop becomes the output: every window it can
            // open is then somewhere on our screen. Phase 6 in the plan.
            let dpi = currentShellDpi
            if let phys = PlatformDispatcher.instance.implicitView?.physicalSize {
                requestResize(logicalW: phys.width / dpi, logicalH: phys.height / dpi,
                              immediate: true)
            }
        case .console:
            seamless?.stop()
            seamless = nil
            mode = .console
            if windowId == nil, let size = guestSize {
                openWindow(width: size.w, height: size.h)
            }
        }
    }

    /// Our focus landed on a window of this session's.
    func focused(_ id: String) {
        seamless?.focused(id)
    }

    /// Open a program inside the guest, through the helper. Seamless only.
    func launchInGuest(_ target: String, args: String = "") {
        seamless?.launch(target, args: args)
    }

    /// Run `work` once the helper answers — now, if it already has. Nothing
    /// runs if seamless mode falls back to the console instead.
    func whenSeamlessReady(_ work: @escaping (GuestSession) -> Void) {
        if mode == .seamless, seamless?.isReady == true {
            work(self)
        } else {
            whenReady.append(work)
        }
    }

    /// For the broker's `guest_state`.
    func stateSnapshot() -> [String: Any] {
        ["domain": domain, "app": appId,
         "mode": mode == .seamless ? "seamless" : "console",
         "scanout": guestSize.map { ["w": $0.w, "h": $0.h] } ?? [:],
         "console": windowId ?? "",
         "humanUsing": humanIsUsing,
         "pairings": agentPairings.map { ["agent": $0.agentId, "record": $0.recordId] },
         "windows": seamless?.snapshot() ?? []]
    }

    /// Damage. Bus thread — queue the ack for the next present and ask for a
    /// composite; the rect itself is dropped, because the compositor repaints
    /// whole surfaces and nothing downstream consumes rects.
    private func handleUpdate(token: UInt64) {
        ackLock.lock()
        if token != 0 { pendingTokens.append(token) }
        let needsHop = !markScheduled
        markScheduled = true
        ackLock.unlock()
        guard needsHop else { return }
        onPlatformThread { [weak self] in
            guard let self else { return }
            self.ackLock.lock()
            self.markScheduled = false
            self.ackLock.unlock()
            guard !self.closed, let texId = self.textureId,
                  let wl = waylandIntegration else { return }
            drmTextureRegistry?.noteDmaBufContentChanged(engine: wl.engine,
                                                         id: texId)
            FrameCallbackScheduler.shared.noteTextureUpdate(texId)
            // await_settled's raw material (M3): a guest window settles when
            // the guest's SCREEN goes quiet, since one scanout carries every
            // window of it. Without this the op had no frame to wait for and
            // answered at once, and an agent's text typed straight after
            // `launch` reached Notepad before it had an edit control to
            // take it — lost, with ok:true.
            _shellState?._agentBroker?.noteFrame(textureId: Int64(texId))
        }
    }

    /// Called from the compositor's present callback (platform thread). QEMU
    /// blocks the guest's display pipeline on this reply, so acking on present
    /// paces the guest to our refresh exactly as a monitor would.
    func ackPresentedFrames() {
        ackLock.lock()
        let tokens = pendingTokens
        pendingTokens.removeAll(keepingCapacity: true)
        ackLock.unlock()
        guard let gd else { return }
        for t in tokens { guest_display_ack_frame(gd, t) }
    }

    // MARK: - The window

    private func openWindow(width: Int, height: Int) {
        guard let shell = _shellState else { return }
        let dpi = currentShellDpi
        let screenW = (PlatformDispatcher.instance.implicitView?.physicalSize.width ?? 3840.0) / dpi
        let screenH = (PlatformDispatcher.instance.implicitView?.physicalSize.height ?? 2160.0) / dpi
        // The USABLE area, not the panel: the window manager clamps to this
        // anyway (`_outputFillRect`), and a guest sized to the whole panel is
        // then clamped, follows the clamp, and comes back a few pixels shorter
        // every time it is reopened.
        let topInset = DesktopTheme.kStatusBarHeight
        let availH = screenH - topInset - shellMetrics.bottomInset

        var logW = Double(width) / dpi
        var logH = Double(height) / dpi + DesktopTheme.kTitleBarHeight
        let capped = logW > screenW || logH > availH
        logW = min(logW, screenW)
        logH = min(logH, availH)
        let rect = Rect.fromLTWH(max(0, (screenW - logW) / 2),
                                 topInset + max(0, (availH - logH) / 2),
                                 logW, logH)

        var newId: String = ""
        shell.setState {
            newId = shell.windowManager.addWindow(
                title: self.appName,
                appId: "guest-\(self.domain)",
                rect: rect,
                textureId: self.textureId.map { Int($0) },
                onWindowClose: { [weak self] in self?.close() },
                onPointerEvent: { [weak self] phase, x, y, buttons in
                    self?.forwardPointer(phase: phase, x: x, y: y,
                                         buttons: buttons)
                },
                onContentResize: { [weak self] w, h in
                    self?.requestResize(logicalW: w, logicalH: h, immediate: false)
                },
                onResizeComplete: { [weak self] w, h in
                    self?.requestResize(logicalW: w, logicalH: h, immediate: true)
                },
                onScrollEvent: { [weak self] _, _, dx, dy in
                    self?.forwardScroll(dx: dx, dy: dy)
                },
                flipTextureY: self.flipY,
                appBuilder: { _ in SizedBox(expand: ()) }
            )
            if let win = shell.windowManager.windows.first(where: { $0.id == newId }) {
                // The dock icon, running dot and menu resolve through
                // `_appOwning`, which matches wmClass second. Without this the
                // window is nobody's and the dock shows a stranger.
                win.wmClass = self.appId
                win.onPointerHoverCursor = { [weak self] in self?.assertCursor() }
            }
        }
        windowId = newId

        // The window was capped to the screen — ask the guest to render at
        // what we can actually show, rather than scaling its desktop down.
        if capped {
            requestResize(logicalW: logW, logicalH: logH - DesktopTheme.kTitleBarHeight,
                          immediate: true)
        }
        onWindowOpened?(newId)
    }

    /// A scanout arrived at a size we did not ask for, or the guest ignored
    /// what we did ask for. Either way the window follows the guest: a texture
    /// stretched to a shape the guest is not drawing is worse than a window
    /// that resizes itself once.
    private func noteGuestResized(width: Int, height: Int) {
        guard let shell = _shellState, let winId = windowId,
              let win = shell.windowManager.windows.first(where: { $0.id == winId })
        else { return }
        if let want = requestedSize, want.w == width, want.h == height {
            requestedSize = nil
            requestedAt = nil
            return
        }
        // Only snap back when we were waiting on a resize that never came;
        // an unsolicited change (the guest's own display settings) is the
        // guest's business and the window should simply follow it.
        let dpi = currentShellDpi
        let logW = Double(width) / dpi
        let logH = Double(height) / dpi + DesktopTheme.kTitleBarHeight
        shell.setState {
            win.rect = Rect.fromLTWH(win.rect.left, win.rect.top, logW, logH)
            win.targetRect = nil
        }
        requestedSize = nil
        requestedAt = nil
    }

    private func requestResize(logicalW: Double, logicalH: Double,
                               immediate: Bool) {
        guard !closed, let gd else { return }
        let dpi = currentShellDpi
        let w = UInt32(max(320.0, (logicalW * dpi).rounded()))
        let h = UInt32(max(240.0, (logicalH * dpi).rounded()))
        resizeDebounce?.cancel()
        let send = { [weak self] in
            guard let self, let gd = self.gd else { return }
            self.requestedSize = (Int(w), Int(h))
            self.requestedAt = Date()
            // One line per settled resize, not per drag event. It is the only
            // way to tell "the guest ignored us" from "we never asked" — the
            // two look identical from the outside, and the first drag-resize
            // that appeared not to work was the second.
            FileHandle.standardError.write(Data(
                "[guest] ask for \(w)x\(h)\n".utf8))
            guest_display_set_ui_size(gd, w, h)
        }
        if immediate {
            send()
        } else {
            // A drag is a hundred resize events; the guest answers each one
            // with a mode change that takes tens of milliseconds.
            let work = DispatchWorkItem(block: send)
            resizeDebounce = work
            onPlatformThread(after: 0.15, execute: work)
        }
        _ = gd
    }

    // MARK: - Input

    private func forwardPointer(phase: Int32, x: Double, y: Double,
                                buttons: Int64) {
        guard !closed, let gd, let size = guestSize else { return }
        // Map through the CONTENT RECT, not the dpi. The two agree only while
        // the guest's buffer is exactly the window's content size times the
        // scale — which is false for the whole interval between asking for a
        // resize and the guest answering, and false for ever if the guest
        // refuses the mode. Multiplying by dpi in that state sends clicks to
        // the wrong place inside Windows, and the window looks unresponsive
        // rather than mis-aimed. TextureWidget stretches the old scanout to
        // fill the content area, so this ratio is exactly what the human sees.
        var scaleX = currentShellDpi
        var scaleY = currentShellDpi
        if let winId = windowId,
           let win = _shellState?.windowManager.windows.first(where: { $0.id == winId }) {
            let contentW = win.rect.width
            let contentH = win.rect.height - DesktopTheme.kTitleBarHeight
            if contentW > 1, contentH > 1 {
                scaleX = Double(size.w) / contentW
                scaleY = Double(size.h) / contentH
            }
        }
        forwardPointerGuest(phase: phase, gx: x * scaleX, gy: y * scaleY,
                            buttons: buttons)
    }

    /// A pointer event already in guest pixels — the console maps through
    /// its content rect, a seamless window through its crop's frame.
    func forwardPointerGuest(phase: Int32, gx: Double, gy: Double, buttons: Int64) {
        guard !closed, let gd, let size = guestSize else { return }
        let px = UInt32(max(0, min(Double(size.w - 1), gx.rounded())))
        let py = UInt32(max(0, min(Double(size.h - 1), gy.rounded())))
        guest_display_mouse_abs(gd, px, py)

        // Flutter's mask -> QEMU's button numbers: 0 left, 1 middle, 2 right.
        // A release arrives with buttons == 0, so the transition set is what
        // says which button it was — tracking all three, not just the left
        // one the Wayland path's hard-coded BTN_LEFT assumes.
        let mask: Int64 = (phase == 1) ? 0 : buttons
        let pairs: [(Int64, UInt32)] = [(1, 0), (4, 1), (2, 2)]
        for (bit, qemuButton) in pairs {
            let wasDown = (buttonMask & bit) != 0
            let isDown = (mask & bit) != 0
            if wasDown != isDown {
                guest_display_mouse_button(gd, qemuButton, isDown ? 1 : 0)
            }
        }
        buttonMask = mask
    }

    func forwardScroll(dx: Double, dy: Double) {
        guard !closed, let gd else { return }
        scrollAccumX += dx
        scrollAccumY += dy
        // Wheel up is 3, wheel down is 4, and a notch is a press and a
        // release of it.
        while abs(scrollAccumY) >= Self.kScrollNotch {
            let up = scrollAccumY < 0
            scrollAccumY -= (up ? -Self.kScrollNotch : Self.kScrollNotch)
            let button: UInt32 = up ? 3 : 4
            guest_display_mouse_button(gd, button, 1)
            guest_display_mouse_button(gd, button, 0)
        }
        // Horizontal wheel is 7/8 in QEMU's enum, but virtio's tablet does
        // not carry it; drop the accumulation rather than send nothing
        // repeatedly.
        if abs(scrollAccumX) >= Self.kScrollNotch { scrollAccumX = 0 }
    }

    /// A key for the guest, as a HID usage. Returns false when the usage has
    /// no XT scancode, so the caller can log it once and move on.
    @discardableResult
    func sendKey(hid: UInt64, down: Bool) -> Bool {
        guard !closed, let gd, let qnum = HidQnum.qnum(forHid: hid) else {
            return false
        }
        if down { heldKeys.insert(qnum) } else { heldKeys.remove(qnum) }
        guest_display_key(gd, qnum, down ? 1 : 0)
        return true
    }

    /// Focus left the window. Anything still held has to come up, or Windows
    /// spends the rest of the session believing Ctrl is down.
    func releaseHeldKeys() {
        guard let gd else { heldKeys.removeAll(); return }
        for qnum in heldKeys { guest_display_key(gd, qnum, 0) }
        heldKeys.removeAll()
    }

    /// Ctrl+Alt+Del, which no chord can carry — the shell would eat it, and
    /// on a real machine the firmware does.
    func sendSecureAttention() {
        guard !closed, let gd else { return }
        for qnum in [UInt32(0x1D), UInt32(0x38), UInt32(0xD3)] {
            guest_display_key(gd, qnum, 1)
        }
        for qnum in [UInt32(0xD3), UInt32(0x38), UInt32(0x1D)] {
            guest_display_key(gd, qnum, 0)
        }
    }

    // MARK: - Cursor

    private func handleCursorDefine(_ bgra: [UInt8], w: Int, h: Int,
                                    hotX: Int, hotY: Int) {
        guard !closed, bgra.count >= w * h * 4 else { return }
        if !sawCursorDefine {
            sawCursorDefine = true
            // Once, so "the guest window has no pointer" can be told apart
            // from "the guest never sent one" — which is what HWCursor=0 in
            // the guest looks like, and it looks like our bug.
            //
            // Keyed on its OWN flag, not on `cursorGen == 0`: MouseSet bumps
            // the generation too and always arrives first, so the original
            // condition could never once be true. That cost an afternoon of
            // believing the guest sent no cursor at all, while a standalone
            // client on the same domain was receiving them fine.
            FileHandle.standardError.write(Data(
                "[guest] first cursor \(w)x\(h) hot \(hotX),\(hotY)\n".utf8))
        }
        cursorBGRA = bgra
        cursorW = w
        cursorH = h
        cursorHotX = hotX
        cursorHotY = hotY
        cursorGen &+= 1
        if pointerIsOverGuest { assertCursor(force: true) }
    }

    private func handleMouseSet(visible: Bool) {
        guard !closed, visible != cursorVisible else { return }
        FileHandle.standardError.write(Data(
            "[guest] pointer visible -> \(visible)\n".utf8))
        cursorVisible = visible
        cursorGen &+= 1
        if pointerIsOverGuest { assertCursor(force: true) }
    }

    /// True while this window is the one the pointer is hovering — the hover
    /// hook is the only thing that sets it, and any other window's hover
    /// resets the plane to an arrow on its own.
    private var pointerIsOverGuest = false

    /// Re-assert the guest's cursor on the plane. Called from the hover hook,
    /// which fires per pointer event, so it de-duplicates on the generation:
    /// uploading a GBM buffer per motion event would be absurd.
    func assertCursor(force: Bool = false) {
        pointerIsOverGuest = true
        guard force || cursorGenOnPlane != cursorGen else { return }
        cursorGenOnPlane = cursorGen
        if !cursorVisible || cursorW == 0 || cursorH == 0 {
            // The guest says it has no pointer — either it has not drawn one
            // yet (the state at connect, so this is the FIRST hover every
            // time) or it deliberately hid it. On a real machine that means
            // no pointer at all; in a window it would mean the human loses
            // theirs somewhere inside a rectangle, with nothing to aim with
            // and no way back except leaving the window blind. So fall back
            // to the desktop's own arrow, which is what every other window
            // shows anyway.
            DesktopCursor.setShape(.default)
        } else {
            DesktopCursor.setImage(cursorBGRA, width: cursorW, height: cursorH,
                                   hotX: cursorHotX, hotY: cursorHotY)
        }
    }

    /// The pointer left. Nothing to do on the plane — whatever it moved onto
    /// sets its own shape, and the wallpaper/title bar/dock all reset to the
    /// arrow — but the next entry must re-upload.
    func pointerLeft() {
        pointerIsOverGuest = false
        cursorGenOnPlane = .max
    }
}

/// Every open guest console, by domain. One place so the present callback has
/// something to ask, and so a second launch of the same domain focuses the
/// window it already has instead of taking its own display away.
enum GuestSessions {
    nonisolated(unsafe) private(set) static var byDomain: [String: GuestSession] = [:]

    static func session(forDomain domain: String) -> GuestSession? {
        byDomain[domain]
    }

    static func session(forWindow windowId: String) -> GuestSession? {
        byDomain.values.first { $0.owns(windowId) }
    }

    static func add(_ session: GuestSession) {
        byDomain[session.domain] = session
    }

    static func remove(domain: String) {
        byDomain.removeValue(forKey: domain)
    }

    /// Platform thread, from the output present callback. The lock inside each
    /// session is the only synchronisation this needs — `byDomain` is written
    /// on the main thread at open and close, which are rare enough that a
    /// torn read here would be a bug worth hearing about rather than a race
    /// worth locking for on every flip.
    static func handlePresent() {
        guard !byDomain.isEmpty else { return }
        for session in byDomain.values { session.ackPresentedFrames() }
    }

    /// Focus moved. Every session that does not own the focused window
    /// releases what it holds; the one that does mirrors the focus into the
    /// guest (seamless mode raises the matching guest window).
    static func focusChanged(to windowId: String?) {
        for session in byDomain.values {
            if let windowId, session.owns(windowId) {
                session.focused(windowId)
            } else {
                session.releaseHeldKeys()
                session.pointerLeft()
            }
        }
    }
}
#endif
