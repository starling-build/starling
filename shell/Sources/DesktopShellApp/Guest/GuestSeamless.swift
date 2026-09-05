// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import Flutter
import FlutterSwiftBridge
import StarlingRegistry

/// One Starling window per guest app window — M2, Phase 3
/// (`docs/plans/guest-seamless.md`).
///
/// The guest's scanout is still ONE texture, the one `GuestSession` imports
/// for the console. Seamless mode does not capture anything per window: each
/// guest top-level becomes a `WindowInfo` whose `textureCrop` is that
/// window's rectangle of the shared texture, and the painter clips the rest.
/// Zero extra copies, and the guest's own stacking shows through wherever two
/// of its windows overlap — the known v1 limit.
///
/// The guest half is the helper on `org.starling.agent.0`, reached through
/// `GuestBridge`. It sends the manageable top-levels, topmost first, whenever
/// anything about them changes; this reconciles that list against the
/// windows it has already made. Focus goes both ways — ours raises the
/// guest's (`activate`), the guest's foreground raises ours — with the same
/// echo guard the clipboard uses, because either direction re-entering the
/// other is a loop.
///
/// Everything here is platform-thread state — the framework's thread, not
/// the main queue (`onPlatformThread`) — and the bridge delivers there.
final class GuestSeamless {

    private unowned let session: GuestSession
    private let bridge: GuestBridge

    /// Raised on the main thread when seamless mode cannot run — no channel,
    /// no helper answering, or the channel closed. The session falls back
    /// to the console on it, so a guest with no helper is still reachable.
    var onUnavailable: ((String) -> Void)?
    /// The helper answered: launches can go. Main thread.
    var onReady: (() -> Void)?
    /// A window of a guest APP (one with a record of its own) appeared;
    /// carries the record id. The launch arm's dock bounce ends on it.
    var onAppWindow: ((String) -> Void)?
    private(set) var isReady = false

    /// Guest processes an agent's launch created, by pid, and until when a
    /// new window of theirs is the agent's — see the reconcile.
    private var agentByPid: [Int: (agent: String, until: Date)] = [:]

    private struct Entry {
        let hwnd: Int64
        let windowId: String
        /// The guest's visible frame, in guest pixels.
        var frame: (x: Int, y: Int, w: Int, h: Int)
        var title: String
        var minimized: Bool
        /// Identity, kept for `refreshOwnership`.
        var aumid: String
        var exe: String
        /// The guest process the window belongs to (0 when unknown).
        let pid: Int
        /// A size we asked the guest for and have not seen answered. While it
        /// stands, the guest's echoes of the OLD size are not applied to our
        /// rect — or the drag would snap back once per event until the guest
        /// caught up.
        var requested: (w: Int, h: Int)?
        var requestedAt: Date?
    }

    private var byHwnd: [Int64: Entry] = [:]
    private var lastFg: Int64 = 0
    /// Set while a reconcile is applying the guest's state to ours, so the
    /// focus and minimise callbacks it triggers — including the raise of the
    /// guest's own foreground window — are not echoed back to the guest.
    private var applying = false
    private var stopped = false
    private var readyDeadline: DispatchWorkItem?
    private var resizeDebounce: [Int64: DispatchWorkItem] = [:]
    /// Foreground windows the helper cannot show us (UIPI: elevated, or the
    /// guest's own UI), each noticed once — and only once they have STAYED
    /// foreground: a launching app is foreground for a tick before it is
    /// listable (Calculator, every time), and that is not a UAC prompt.
    private var noticedForeign: Set<Int64> = []
    private var foreignCheck: DispatchWorkItem?

    init(session: GuestSession) {
        self.session = session
        self.bridge = GuestBridge(domain: session.domain)
    }

    // MARK: - Lifecycle

    func start() {
        bridge.onReady = { [weak self] helper in
            guard let self, !self.stopped else { return }
            self.readyDeadline?.cancel()
            self.readyDeadline = nil
            FileHandle.standardError.write(Data(
                "[seamless] \(self.session.domain): helper \(helper)\n".utf8))
            // Events first, then a list: a window that appears between the
            // two arrives as an event, and one that appears before the
            // observe is in the list. Either order is safe because
            // reconcile is idempotent; this one is the shorter wait.
            // Phase 6: the guest's scaling follows ours, so a guest window
            // is the logical size a native one would be — not physically
            // 1:1 and small at 1.5x. Live in Windows, no sign-out; the
            // windows re-lay out and the observer reports the new frames.
            let percent = Int((currentShellDpi * 100).rounded())
            self.bridge.send(op: "set_scale", args: ["percent": percent]) { reply in
                FileHandle.standardError.write(Data(
                    "[seamless] guest scale asked \(percent)% -> \(jsonInt(reply["percent"]) ?? -1)% (ok=\(jsonBool(reply["ok"])))\n".utf8))
            }
            // The nearly empty session (Phase 5): hide the guest's taskbar and
            // desktop icons — each guest window is composited on its own onto
            // the Starling desktop, so the Windows shell should not be there —
            // and reclaim the taskbar strip so a maximised app fills the
            // output. Shown again when we leave seamless (stop()).
            self.bridge.send(op: "furniture", args: ["hide": 1]) { reply in
                FileHandle.standardError.write(Data(
                    "[seamless] furniture hidden (tray_visible=\(jsonBool(reply["tray_visible"])))\n".utf8))
            }
            self.bridge.send(op: "observe", args: ["interval": 100])
            self.bridge.send(op: "list_windows") { [weak self] reply in
                self?.reconcile(reply)
            }
            // The guest's own catalog, as registry records (Phase 5). Asked
            // once per attach: it walks every installed app with an icon
            // each, which is a second or two inside the guest.
            self.bridge.send(op: "apps") { [weak self] reply in
                guard let self, !self.stopped,
                      let apps = reply["apps"] as? [[String: Any]] else { return }
                let color = AppRegistry.shared.app(id: self.session.appId)?.color ?? 0x2E6FCC
                let n = GuestAppRecords.update(domain: self.session.domain, apps: apps,
                                               color: color)
                FileHandle.standardError.write(Data(
                    "[seamless] \(self.session.domain): \(n) app records\n".utf8))
                self.refreshOwnership()
            }
            self.isReady = true
            self.onReady?()
        }
        bridge.onEvent = { [weak self] ev in
            guard let self, !self.stopped else { return }
            switch ev["event"] as? String {
            case "windows":
                self.reconcile(ev)
            case "helper-up":
                // The helper (re)started after we connected: our first hello
                // went nowhere. Ask again now rather than on the retry tick.
                self.bridge.hello()
            default:
                break
            }
        }
        bridge.onClosed = { [weak self] in
            guard let self, !self.stopped else { return }
            self.unavailable("the helper's channel closed")
        }
        guard bridge.open() else {
            unavailable("the domain has no \(GuestBridge.channelName) channel, or nothing is listening on it")
            return
        }
        // A channel with no helper behind it accepts the connection and says
        // nothing. Bounded, so "seamless is on and nothing appears" becomes a
        // notice and the console instead of a blank desktop.
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, !self.bridge.isReady else { return }
            self.unavailable("no Starling helper answered inside Windows (docs/WINDOWS-VM.md, \"Apps as windows\")")
        }
        readyDeadline = deadline
        onPlatformThread(after: 15, execute: deadline)
    }

    /// Drops every window and the channel. The session and its texture stay.
    func stop() {
        guard !stopped else { return }
        stopped = true
        readyDeadline?.cancel()
        readyDeadline = nil
        foreignCheck?.cancel()
        foreignCheck = nil
        for work in resizeDebounce.values { work.cancel() }
        resizeDebounce.removeAll()
        bridge.onReady = nil
        bridge.onEvent = nil
        bridge.onClosed = nil
        isReady = false
        let ids = byHwnd.values.map(\.windowId)
        byHwnd.removeAll()
        if !ids.isEmpty, let shell = _shellState {
            shell.setState {
                for id in ids {
                    if let win = shell.windowManager.windows.first(where: { $0.id == id }) {
                        // Ours is going away; the guest's stays.
                        win.onWindowClose = nil
                        win.onMinimizedChanged = nil
                    }
                    shell.windowManager.closeWindow(id)
                }
            }
        }
        // Give the guest its shell back before we drop the channel. Best
        // effort: if the helper has already died the write is a no-op and the
        // taskbar returns on the next attach or an explorer restart.
        bridge.send(op: "furniture", args: ["hide": 0])
        bridge.close()
    }

    private func unavailable(_ detail: String) {
        FileHandle.standardError.write(Data(
            "[seamless] \(session.domain): \(detail)\n".utf8))
        stop()
        onUnavailable?(detail)
    }

    // MARK: - Queries

    func owns(_ windowId: String) -> Bool {
        byHwnd.values.contains { $0.windowId == windowId }
    }

    var windowCount: Int { byHwnd.count }

    /// What this mode is showing, for the broker's `guest_state`: one entry
    /// per guest window, so a test can assert on titles and ids without
    /// reading pixels.
    func snapshot() -> [[String: Any]] {
        let wm = _shellState?.windowManager
        return byHwnd.values.sorted { $0.windowId < $1.windowId }.map { e in
            var d: [String: Any] = [
                "hwnd": e.hwnd, "window": e.windowId, "title": e.title,
                "minimized": e.minimized,
                "frame": ["x": e.frame.x, "y": e.frame.y,
                          "w": e.frame.w, "h": e.frame.h],
            ]
            // OUR rect, logical, so a test can aim at the title bar or an
            // edge of the window the desktop actually drew.
            if let win = wm?.windows.first(where: { $0.id == e.windowId }) {
                d["rect"] = ["x": win.rect.left, "y": win.rect.top,
                             "w": win.rect.width, "h": win.rect.height]
                d["focused"] = wm?.focusedWindowId == e.windowId
                d["owner"] = win.ownerAgentId ?? ""
            }
            return d
        }
    }

    /// UIA tree / action through the helper — the broker's `semantic_tree`
    /// and `perform_action` for a guest window (M3 Phase 3). `extra` carries
    /// node/action/value for perform_action. `completion` runs on the
    /// platform thread with the helper's reply (already in the broker's shape:
    /// `{ok, nodes}` / `{ok}`).
    func semantics(op: String, windowId: String, extra: [String: Any],
                   completion: @escaping ([String: Any]) -> Void) {
        guard !stopped, let e = byHwnd.values.first(where: { $0.windowId == windowId }) else {
            completion(["ok": false, "error": "no such guest window"])
            return
        }
        var args = extra
        args["hwnd"] = e.hwnd
        bridge.send(op: op, args: args) { reply in completion(reply) }
    }

    /// PrintWindow one window through the helper — the broker's `capture` op
    /// for a guest window (M3 Phase 2). Occlusion-proof and safe on a
    /// background window: it reads pixels, it touches no input, so unlike the
    /// input ops it needs no activate and no lease. `completion` runs on the
    /// platform thread with the helper's raw reply (or a synthesised failure).
    func capture(windowId: String, maxSide: Int,
                 completion: @escaping ([String: Any]) -> Void) {
        guard !stopped, let e = byHwnd.values.first(where: { $0.windowId == windowId }) else {
            completion(["ok": false, "error": "no such guest window"])
            return
        }
        bridge.send(op: "capture", args: ["hwnd": e.hwnd, "max_side": maxSide]) { reply in
            completion(reply)
        }
    }

    /// Raise `windowId`'s guest window before an agent's input. Completes
    /// at once when the guest's foreground already is it (as the last list
    /// reported), else on the helper's reply — and with its verdict, because
    /// input after a refused activate lands in whatever IS the foreground.
    /// `lastFg` follows a successful reply, not the request: the reconcile's
    /// echo of the change raises nothing for an agent's window anyway.
    func activate(windowId: String, completion: @escaping (Bool) -> Void) {
        guard !stopped, let e = byHwnd.values.first(where: { $0.windowId == windowId }) else {
            completion(false)
            return
        }
        if lastFg == e.hwnd { completion(true); return }
        let hwnd = e.hwnd
        bridge.send(op: "activate", args: ["hwnd": hwnd]) { [weak self] reply in
            let ok = jsonBool(reply["ok"])
            if ok { self?.lastFg = hwnd }
            FileHandle.standardError.write(Data(
                "[seamless] activate \(e.title.prefix(30)) hwnd \(hwnd) for an agent -> ok=\(ok)\n".utf8))
            completion(ok)
        }
    }

    // MARK: - The guest's list -> our windows

    /// Guest pixels -> logical, per axis. The scanout is asked to be the
    /// output's physical size, so this is 1/dpi once the guest has answered;
    /// until then (and for ever if it refuses) it is whatever ratio makes the
    /// crop land at the right size — the same reasoning as M1's pointer
    /// mapping through the content rect rather than the dpi.
    private func ratios() -> (x: Double, y: Double, guestW: Int, guestH: Int)? {
        guard let size = session.guestSize, size.w > 0, size.h > 0 else { return nil }
        let dpi = currentShellDpi
        let physW = PlatformDispatcher.instance.implicitView?.physicalSize.width ?? Double(size.w)
        let physH = PlatformDispatcher.instance.implicitView?.physicalSize.height ?? Double(size.h)
        return (physW / dpi / Double(size.w), physH / dpi / Double(size.h), size.w, size.h)
    }

    private func reconcile(_ obj: [String: Any]) {
        guard !stopped, let shell = _shellState,
              let list = obj["windows"] as? [[String: Any]] else { return }
        guard let r = ratios() else {
            // No scanout yet: the list is not wrong, it is early. It will be
            // re-sent on the next change, and scanoutChanged() asks for one.
            return
        }
        let fg = jsonInt(obj["fg"]) ?? 0
        let titleBar = DesktopTheme.kTitleBarHeight
        let topInset = DesktopTheme.kStatusBarHeight
        var seen = Set<Int64>()

        applying = true
        defer { applying = false }
        shell.setState {
            // Bottom-most first, so a fresh set of windows is stacked the way
            // the guest stacks them (each addWindow lands on top).
            for w in list.reversed() {
                guard let hwnd = jsonInt(w["hwnd"]), hwnd != 0 else { continue }
                let title = w["title"] as? String ?? ""
                var x = Int(jsonInt(w["x"]) ?? 0)
                var y = Int(jsonInt(w["y"]) ?? 0)
                var wd = Int(jsonInt(w["w"]) ?? 0)
                var ht = Int(jsonInt(w["h"]) ?? 0)
                let minimized = jsonBool(w["min"])
                // Clamp to the scanout: the texture has no pixels outside
                // it, and a crop that reaches past the edge would stretch
                // what there is over the gap.
                let x1 = min(x + wd, r.guestW), y1 = min(y + ht, r.guestH)
                x = max(0, x); y = max(0, y)
                wd = x1 - x; ht = y1 - y
                guard wd > 0, ht > 0 else { continue }
                seen.insert(hwnd)

                let crop = Rect.fromLTWH(Double(x) / Double(r.guestW),
                                         Double(y) / Double(r.guestH),
                                         Double(wd) / Double(r.guestW),
                                         Double(ht) / Double(r.guestH))
                let logW = Double(wd) * r.x
                let logH = Double(ht) * r.y

                if var e = byHwnd[hwnd] {
                    guard let win = shell.windowManager.windows.first(where: { $0.id == e.windowId }) else {
                        byHwnd.removeValue(forKey: hwnd)
                        continue
                    }
                    if e.title != title {
                        e.title = title
                        win.title = title
                    }
                    if win.textureCrop != crop { win.textureCrop = crop }
                    let frameChanged = e.frame.x != x || e.frame.y != y
                        || e.frame.w != wd || e.frame.h != ht
                    if let req = e.requested {
                        // Answered (exactly, or as near as the app's minimum
                        // size allows) — or stale: a guest that ignores a
                        // resize for a second is not going to honour it.
                        let stale = e.requestedAt.map { Date().timeIntervalSince($0) > 1.0 } ?? true
                        if (req.w == wd && req.h == ht) || stale || frameChanged {
                            e.requested = nil
                            e.requestedAt = nil
                        }
                    }
                    if frameChanged {
                        e.frame = (x, y, wd, ht)
                        if e.requested == nil {
                            // Follow the guest: it is the one drawing.
                            win.rect = Rect.fromLTWH(win.rect.left, win.rect.top,
                                                     logW, logH + titleBar)
                            win.targetRect = nil
                        }
                    }
                    if e.minimized != minimized {
                        e.minimized = minimized
                        if minimized {
                            shell.windowManager.minimizeWindow(e.windowId)
                        } else if win.isMinimized {
                            shell.windowManager.restoreWindow(e.windowId)
                        }
                    }
                    byHwnd[hwnd] = e
                } else {
                    // Mirror the guest's placement, kept under the menu bar.
                    // Position is cosmetic — the crop does not depend on
                    // where our window sits — but a window that opens where
                    // the guest put it is what a person expects.
                    let left = Double(x) * r.x
                    let top = max(topInset, Double(y) * r.y - titleBar)
                    let rect = Rect.fromLTWH(left, top, logW, logH + titleBar)
                    // An agent's launch claims the next window of its record
                    // (M3): owned windows have no desktop presence, exactly
                    // as a first-party child launched by an agent.
                    let owner = GuestAppRecords.recordId(
                        domain: session.domain,
                        aumid: w["aumid"] as? String ?? "",
                        exe: w["exe"] as? String ?? "")
                    // Ownership follows the PROCESS for the rest of the
                    // launch's ten seconds (M3): Notepad restores every
                    // window of its last session in one burst and Chrome
                    // opens several, and those are the launch's windows as
                    // much as the first. Bounded, because a single-instance
                    // app is one process for everyone: a person launching
                    // Notepad a minute later gets a window in the agent's
                    // process, and that window must stay theirs (an agent's
                    // own later windows landing on the desktop is the lesser
                    // wrong: visible, not lost). And a launch that lands in
                    // a process the human already had pairs its one window
                    // only.
                    let pid = Int(jsonInt(w["pid"]) ?? 0)
                    var pairing: GuestSession.AgentPairing? = nil
                    var agent: String? = nil
                    if pid != 0, let known = agentByPid[pid], known.until > Date() {
                        agent = known.agent
                    }
                    if agent == nil, let owner,
                       let p = session.takeAgentPairing(forRecord: owner) {
                        pairing = p
                        agent = p.agentId
                        if pid != 0, !byHwnd.values.contains(where: { $0.pid == pid }) {
                            agentByPid[pid] = (p.agentId, p.deadline)
                        }
                    }
                    let id = shell.windowManager.addWindow(
                        title: title,
                        appId: "guest-\(session.domain)-\(hwnd)",
                        rect: rect,
                        textureId: session.textureId.map { Int($0) },
                        onWindowClose: { [weak self] in self?.closeRequested(hwnd) },
                        onPointerEvent: { [weak self] phase, px, py, buttons in
                            self?.forwardPointer(hwnd: hwnd, phase: phase,
                                                 x: px, y: py, buttons: buttons)
                        },
                        onContentResize: { [weak self] cw, ch in
                            self?.requestResize(hwnd: hwnd, logicalW: cw, logicalH: ch,
                                                immediate: false)
                        },
                        onResizeComplete: { [weak self] cw, ch in
                            self?.requestResize(hwnd: hwnd, logicalW: cw, logicalH: ch,
                                                immediate: true)
                        },
                        onScrollEvent: { [weak self] _, _, dx, dy in
                            self?.session.forwardScroll(dx: dx, dy: dy)
                        },
                        flipTextureY: session.flipY,
                        ownerAgentId: agent,
                        appBuilder: { _ in SizedBox(expand: ()) }
                    )
                    if let win = shell.windowManager.windows.first(where: { $0.id == id }) {
                        // The app's own record when the guest listed one
                        // (Phase 5) — by AppUserModelID or executable, never
                        // the title — else the VM's, where it would have
                        // been anyway.
                        win.wmClass = owner ?? session.appId
                        if let owner, agent == nil { onAppWindow?(owner) }
                        win.textureCrop = crop
                        win.onPointerHoverCursor = { [weak session] in session?.assertCursor() }
                        win.onMinimizedChanged = { [weak self] m in
                            self?.minimizeRequested(hwnd, minimized: m)
                        }
                        if minimized, agent == nil { shell.windowManager.minimizeWindow(id) }
                    }
                    if let agent {
                        FileHandle.standardError.write(Data(
                            "[seamless] \(title.prefix(40)) is \(agent)'s\(pairing == nil ? " (same process)" : "")\n".utf8))
                    }
                    pairing?.onWindow(id)
                    byHwnd[hwnd] = Entry(hwnd: hwnd, windowId: id, frame: (x, y, wd, ht),
                                         title: title, minimized: minimized,
                                         aumid: w["aumid"] as? String ?? "",
                                         exe: w["exe"] as? String ?? "",
                                         pid: pid,
                                         requested: nil, requestedAt: nil)
                    FileHandle.standardError.write(Data(
                        "[seamless] + \(title.prefix(40)) (\(wd)x\(ht) at \(x),\(y)) hwnd \(hwnd)\n".utf8))
                }
            }

            // Gone from the guest: destroyed, hidden, or cloaked. Ours goes
            // without asking the guest to close anything — it already has.
            for (hwnd, e) in byHwnd where !seen.contains(hwnd) {
                if let win = shell.windowManager.windows.first(where: { $0.id == e.windowId }) {
                    win.onWindowClose = nil
                    win.onMinimizedChanged = nil
                }
                shell.windowManager.closeWindow(e.windowId)
                byHwnd.removeValue(forKey: hwnd)
                // Pids are reused; forget a process once its last window went.
                if e.pid != 0, !byHwnd.values.contains(where: { $0.pid == e.pid }) {
                    agentByPid.removeValue(forKey: e.pid)
                }
                FileHandle.standardError.write(Data(
                    "[seamless] - \(e.title.prefix(40)) hwnd \(hwnd)\n".utf8))
            }

            // The guest's foreground is our focus, once per change. A change
            // we caused (activate) comes back with lastFg already equal.
            if fg != lastFg {
                lastFg = fg
                if let e = byHwnd[fg] {
                    // An agent's window has no desktop presence to raise;
                    // the guest's foreground moving to it is the agent's
                    // activate, not the person's focus.
                    let agents = shell.windowManager.windows.first(where: { $0.id == e.windowId })?.ownerAgentId != nil
                    if !agents, shell.windowManager.focusedWindowId != e.windowId {
                        if let win = shell.windowManager.windows.first(where: { $0.id == e.windowId }),
                           win.isMinimized {
                            shell.windowManager.restoreWindow(e.windowId)
                        } else {
                            shell.windowManager.bringToFront(e.windowId)
                        }
                    }
                } else if fg != 0, !noticedForeign.contains(fg),
                          let what = obj["fgTitle"] as? String, !what.isEmpty {
                    // The guest is showing something we cannot: an elevated
                    // window, a UAC prompt, its own Start menu. Say so — a
                    // guest waiting on a click we are not showing looks hung.
                    // After a moment, not now: a window that becomes
                    // listable on the next poll was only launching. And
                    // only when it has a title: none means furniture or a
                    // transient the helper could not even name.
                    foreignCheck?.cancel()
                    let check = DispatchWorkItem { [weak self] in
                        guard let self, !self.stopped, self.lastFg == fg,
                              self.byHwnd[fg] == nil,
                              !self.noticedForeign.contains(fg) else { return }
                        self.noticedForeign.insert(fg)
                        FileHandle.standardError.write(Data(
                            "[seamless] the guest's foreground window is not one we show: \"\(what)\" hwnd \(fg)\n".utf8))
                        if !what.isEmpty {
                            self.session.onNotice?("Windows is showing \"\(what)\"",
                                                   "It cannot be shown as a window here. Use \"Show Windows Desktop\" from the dock menu to reach it.")
                        }
                    }
                    foreignCheck = check
                    onPlatformThread(after: 1.5, execute: check)
                }
            }
        }
    }

    /// Records arrived after windows did: give every window the owner it
    /// would have had. Called once per `apps` reply, so it re-reads the
    /// identity the reconcile keeps in `Entry` — which is why it keeps it.
    private func refreshOwnership() {
        guard let shell = _shellState else { return }
        var changed = false
        for e in byHwnd.values {
            guard let win = shell.windowManager.windows.first(where: { $0.id == e.windowId }) else { continue }
            let owner = GuestAppRecords.recordId(domain: session.domain,
                                                 aumid: e.aumid, exe: e.exe)
            let wmClass = owner ?? session.appId
            if win.wmClass != wmClass {
                win.wmClass = wmClass
                changed = true
                // A launch whose window arrived before its record did ends
                // its dock bounce here, not never.
                if let owner { onAppWindow?(owner) }
            }
        }
        if changed { shell.setState {} }
    }

    /// The scanout changed size or orientation: every crop is relative to
    /// it, so every crop moves. Asks the helper for a fresh list too, because
    /// a guest that just changed resolution has usually re-laid its windows.
    func scanoutChanged() {
        guard !stopped, let shell = _shellState, let r = ratios() else { return }
        shell.setState {
            for e in byHwnd.values {
                guard let win = shell.windowManager.windows.first(where: { $0.id == e.windowId }) else { continue }
                let crop = Rect.fromLTWH(Double(e.frame.x) / Double(r.guestW),
                                         Double(e.frame.y) / Double(r.guestH),
                                         Double(e.frame.w) / Double(r.guestW),
                                         Double(e.frame.h) / Double(r.guestH))
                win.textureCrop = crop
                win.flipTextureY = session.flipY
            }
        }
        if bridge.isReady {
            bridge.send(op: "list_windows") { [weak self] reply in self?.reconcile(reply) }
        }
    }

    // MARK: - Ours -> the guest

    /// Our focus landed on one of these windows — by the person, since a
    /// reconcile's own raises arrive with `applying` set.
    func focused(_ windowId: String) {
        guard !stopped, !applying else { return }
        guard let e = byHwnd.values.first(where: { $0.windowId == windowId }) else { return }
        lastFg = e.hwnd
        bridge.send(op: "activate", args: ["hwnd": e.hwnd])
    }

    private func closeRequested(_ hwnd: Int64) {
        // The X button: ask, the way the guest's own X would — the app may
        // prompt or refuse, in which case the window comes back on the next
        // list. Ours is being torn down by the caller.
        byHwnd.removeValue(forKey: hwnd)
        resizeDebounce.removeValue(forKey: hwnd)?.cancel()
        guard !stopped else { return }
        bridge.send(op: "close", args: ["hwnd": hwnd])
    }

    private func minimizeRequested(_ hwnd: Int64, minimized: Bool) {
        guard !stopped, !applying, var e = byHwnd[hwnd] else { return }
        e.minimized = minimized
        byHwnd[hwnd] = e
        bridge.send(op: minimized ? "minimize" : "restore", args: ["hwnd": hwnd])
    }

    private func requestResize(hwnd: Int64, logicalW: Double, logicalH: Double,
                               immediate: Bool) {
        guard !stopped, let r = ratios(), byHwnd[hwnd] != nil else { return }
        resizeDebounce[hwnd]?.cancel()
        let w = max(120, Int((logicalW / r.x).rounded()))
        let h = max(80, Int((logicalH / r.y).rounded()))
        let send = { [weak self] in
            guard let self, !self.stopped, var e = self.byHwnd[hwnd] else { return }
            e.requested = (w, h)
            e.requestedAt = Date()
            self.byHwnd[hwnd] = e
            self.bridge.send(op: "move", args: [
                "hwnd": hwnd, "x": e.frame.x, "y": e.frame.y, "w": w, "h": h,
            ])
        }
        if immediate {
            send()
        } else {
            // A drag is a hundred resize events, and each move re-lays the
            // guest's window; M1's debounce, per window.
            let work = DispatchWorkItem(block: send)
            resizeDebounce[hwnd] = work
            onPlatformThread(after: 0.15, execute: work)
        }
    }

    /// Window-local logical coordinates -> guest pixels: the window's frame
    /// origin plus the position scaled by frame-over-content, which is 1:1 by
    /// construction except in the interval between a resize and the guest's
    /// answer — exactly M1's content-rect rule, per window.
    private func forwardPointer(hwnd: Int64, phase: Int32, x: Double, y: Double,
                                buttons: Int64) {
        guard !stopped, let e = byHwnd[hwnd], let shell = _shellState,
              let win = shell.windowManager.windows.first(where: { $0.id == e.windowId })
        else { return }
        let contentW = win.rect.width
        let contentH = win.rect.height - DesktopTheme.kTitleBarHeight
        guard contentW > 1, contentH > 1 else { return }
        let gx = Double(e.frame.x) + x * Double(e.frame.w) / contentW
        let gy = Double(e.frame.y) + y * Double(e.frame.h) / contentH
        session.forwardPointerGuest(phase: phase, gx: gx, gy: gy, buttons: buttons)
    }

    /// Something the test tier and the dock menu can act on: open a program
    /// inside the guest. The helper resolves the path; a Store app is its
    /// `shell:AppsFolder\…` name.
    func launch(_ target: String, args: String = "") {
        guard !stopped, bridge.isReady else {
            FileHandle.standardError.write(Data(
                "[seamless] launch \(target) dropped: helper not ready\n".utf8))
            return
        }
        bridge.send(op: "launch", args: ["path": target, "args": args]) { reply in
            FileHandle.standardError.write(Data(
                "[seamless] launch \(target) \(args) -> ok=\(reply["ok"] as? Bool ?? false)\n".utf8))
        }
    }
}

/// JSON numbers as swift-corelibs-foundation hands them back: Int, Double or
/// NSNumber depending on the platform and the value. Bools are NSNumber on
/// some Foundations too, which is why `jsonBool` is not `as? Bool`.
private func jsonInt(_ v: Any?) -> Int64? {
    if let i = v as? Int { return Int64(i) }
    if let i = v as? Int64 { return i }
    if let d = v as? Double { return Int64(d) }
    if let n = v as? NSNumber { return n.int64Value }
    return nil
}

private func jsonBool(_ v: Any?) -> Bool {
    if let b = v as? Bool { return b }
    if let n = v as? NSNumber { return n.boolValue }
    return false
}
#endif
