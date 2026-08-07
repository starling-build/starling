// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import Foundation
import Glibc
import StarlingRegistry

// MARK: - Agent Broker (Murmuration P1)
//
// One broker lives in the shell — the only process that sees every window,
// texture and socket — listening on $XDG_RUNTIME_DIR/starling-agent.sock.
// JSON-lines, versioned hello; every request carries `id`, every effectful
// call is answered and audited. Scope is default-deny: an agent addresses
// ONLY windows it owns (launched through the broker with its token); the
// human's windows and other agents' windows are not listed, not injectable,
// not capturable.
//
// Layers (design doc §4):
//   observe  — list_windows over WindowManagerState (owned scope)
//   input    — inject over the child's DMA-BUF socket (zero seat interference)
//   pixels   — capture by mmap of the child's linear DMA-BUF (clean,
//              unoccluded, content-local; no full-screen screenshots)
//   settled  — await_settled v0: per-window frame-quiet + shell animations
//
// Threading: accept/read run on background GCD queues; every handler is
// marshalled onto the main queue (the codebase @Sendable-coercion idiom).
// Replies are serialized per connection on its write queue.

/// One client connection: fd + registered agent + serialized writer.
private final class BrokerConn: @unchecked Sendable {
    let fd: Int32
    var agentId: String? = nil
    private let writeQ = DispatchQueue(label: "starling.agent.conn.write")
    private var closed = false

    init(fd: Int32) { self.fd = fd }

    /// Serialize + enqueue one JSON-lines reply. Safe from any thread; all
    /// fd writes (and the close) are ordered on writeQ so a queued reply
    /// can never hit a reused fd.
    func send(_ obj: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(obj),
              let json = try? JSONSerialization.data(withJSONObject: obj) else { return }
        let data = json + Data([0x0A])
        writeQ.async { [self] in
            guard !closed else { return }
            data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                var off = 0
                while off < buf.count {
                    let n = write(fd, buf.baseAddress! + off, buf.count - off)
                    if n <= 0 { break }
                    off += n
                }
            }
        }
    }

    /// Flush queued replies, then close. Called once by the reader loop.
    func markClosed() {
        writeQ.async { [self] in
            guard !closed else { return }
            closed = true
            close(fd)
        }
    }
}

final class AgentBroker: @unchecked Sendable {
    private weak var shell: _DesktopShellState?
    private var listenFd: Int32 = -1
    private(set) var socketPath = ""
    private var auditDir = ""
    private var launchSeq = 0

    /// Last child frame arrival per texture id, ms. Written from the
    /// platform thread (tick), read from main — lock-guarded.
    private var lastFrameMs: [Int64: Int64] = [:]
    private let frameLock = NSLock()

    /// Last injection per window (main thread). await_settled measures
    /// quiet from max(lastFrame, lastInject): a settle issued right after a
    /// click must wait for that click's repaint, not match pre-click quiet.
    private var lastInjectMs: [String: Int64] = [:]

    /// Last broker op per agent (main thread) — the fleet UI derives its
    /// working/idle status from this plus frame recency.
    private(set) var agentLastOpMs: [String: Int64] = [:]

    /// Connections subscribed to app status (main thread). Deliberately NOT
    /// agents: this is the shell publishing which apps are installed and
    /// live, so its own apps do not have to work it out separately and
    /// drift. See the `subscribe_apps` handler for why it is outside the
    /// agent scope model.
    private var appSubscribers: [ObjectIdentifier: BrokerConn] = [:]
    /// Polls liveness while anyone is subscribed — a process exiting without
    /// closing a window raises no event of its own. Nothing ticks when the
    /// App Store is closed.
    private var appTick: DispatchSourceTimer?

    var now: Int64 { nowMs }

    func lastFrame(forTexture tex: Int64) -> Int64? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return lastFrameMs[tex]
    }

    private var nowMs: Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    /// Apps an agent may launch (design: scope.launch). Rects follow the
    /// dock launch table; position is irrelevant for agent windows.
    /// Apps an agent may launch. No sizes here on purpose: the window is
    /// given a nominal size at launch, so the size in this
    /// table could only ever disagree with the one that gets applied.
    private static let launchable: [String: (exec: String, title: String)] = [
        "files": ("FileExplorerApp", "Files"),
        "settings": ("SettingsApp", "Settings"),
        "terminal": ("TerminalApp", "Terminal"),
    ]

    // MARK: Lifecycle

    func start(shell: _DesktopShellState) {
        self.shell = shell
        let dir = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] ?? "/tmp"
        socketPath = dir + "/starling-agent.sock"
        auditDir = dir + "/starling-agents"
        try? FileManager.default.createDirectory(
            atPath: auditDir, withIntermediateDirectories: true)

        unlink(socketPath)
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                socketPath.withCString { src in strncpy(buf, src, 107) }
            }
        }
        let bound = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            return
        }
        // This socket drives the session: `launch` starts processes and
        // `inject` types into them, so reaching it IS code execution as the
        // login user. It is owner-only, and every accepted peer is checked
        // against that owner below — filesystem mode alone is not the gate.
        //
        // Dev mode runs the shell as root while agents connect as the user,
        // so hand the socket to the login user rather than widening the mode
        // (0666 here was how any local uid, and every app that gets
        // XDG_RUNTIME_DIR bind-mounted in, could drive the whole session).
        chmod(socketPath, 0o600)
        if getuid() == 0 { _ = chown(socketPath, LoginUser.uid, gid_t(bitPattern: -1)) }
        listenFd = fd

        // Frame-quiet raw material for await_settled.
        linuxProcessAppManager?.onChildFrame = { [weak self] texId in
            guard let self else { return }
            self.frameLock.lock()
            self.lastFrameMs[texId] = self.nowMs
            self.frameLock.unlock()
        }

        FileHandle.standardError.write(Data(
            "[AgentBroker] listening on \(socketPath)\n".utf8))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let self, self.listenFd >= 0 {
                let clientFd = accept(self.listenFd, nil, nil)
                guard clientFd >= 0 else { break }
                // Authenticate the peer by uid before it can say anything.
                // The kernel supplies this; it cannot be forged by the
                // client, which is why it — not the socket mode — is the
                // security boundary.
                guard Self.peerIsSessionOwner(clientFd) else {
                    close(clientFd)
                    continue
                }
                self.serveConnection(BrokerConn(fd: clientFd))
            }
        }
    }

    /// True when the connected peer runs as the session's own user (or root,
    /// which could take the session anyway). Rejects every other local uid.
    private static func peerIsSessionOwner(_ fd: Int32) -> Bool {
        var cred = ucred()
        var len = socklen_t(MemoryLayout<ucred>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0 else {
            // No credentials means we cannot prove who this is — fail closed.
            FileHandle.standardError.write(Data(
                "[AgentBroker] rejected a peer with no credentials\n".utf8))
            return false
        }
        let owner = LoginUser.uid
        if cred.uid == owner || cred.uid == 0 { return true }
        FileHandle.standardError.write(Data(
            "[AgentBroker] rejected connection from uid \(cred.uid) (session owner is \(owner))\n".utf8))
        return false
    }

    private func serveConnection(_ conn: BrokerConn) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var pending = Data()
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(conn.fd, &buf, buf.count)
                if n <= 0 { break }
                pending.append(contentsOf: buf[0..<n])
                while let nl = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[pending.startIndex..<nl])
                    pending = Data(pending[pending.index(after: nl)...])
                    if !line.isEmpty { self?.handleLine(line, conn) }
                }
            }
            conn.markClosed()
            // Drop any app-status subscription this connection held, and stop
            // the tick once the last subscriber goes.
            let cleanup: () -> Void = { [weak self] in
                guard let self else { return }
                self.appSubscribers.removeValue(forKey: ObjectIdentifier(conn))
                self.stopAppTickIfIdle()
            }
            DispatchQueue.main.async(
                execute: unsafeBitCast(cleanup, to: (@Sendable () -> Void).self))
        }
    }

    // MARK: App status publishing

    /// Push a liveness change to every subscriber. Called by the shell when
    /// its `appLiveness` actually changed, so this is edge-triggered.
    func pushAppStatus(_ liveness: [String: _DesktopShellState.AppLiveness]) {
        guard !appSubscribers.isEmpty else { return }
        let payload = Self.appStatusPayload(liveness)
        for conn in appSubscribers.values { conn.send(payload) }
    }

    static func appStatusPayload(
        _ liveness: [String: _DesktopShellState.AppLiveness]
    ) -> [String: Any] {
        var apps: [String: Any] = [:]
        for (id, live) in liveness {
            apps[id] = ["window": live.window, "process": live.process]
        }
        return ["event": "app_status", "apps": apps]
    }

    private func startAppTickIfNeeded() {
        guard appTick == nil, !appSubscribers.isEmpty else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.shell?._refreshAppLiveness()
        }
        appTick = timer
        timer.resume()
    }

    private func stopAppTickIfIdle() {
        guard appSubscribers.isEmpty else { return }
        appTick?.cancel()
        appTick = nil
    }

    /// Parse on the reader thread, handle on main (handlers touch shell state).
    private func handleLine(_ line: Data, _ conn: BrokerConn) {
        guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let op = obj["op"] as? String else {
            conn.send(["ok": false, "error": "bad json-lines request"])
            return
        }
        let work: () -> Void = { [weak self] in self?.dispatch(op, obj, conn) }
        DispatchQueue.main.async(
            execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    // MARK: Dispatch (main thread)

    private func dispatch(_ op: String, _ req: [String: Any], _ conn: BrokerConn) {
        let id = req["id"] ?? NSNull()
        func fail(_ msg: String) {
            conn.send(["id": id, "ok": false, "error": msg])
            audit(conn.agentId, op, false, msg)
        }
        guard let shell else { return fail("shell gone") }

        if op == "hello" {
            let name = (req["name"] as? String) ?? "external"

            // Re-attach. Windows are owned per agent, so a client that runs as
            // a series of short-lived processes — one per command — needs to
            // come back as the SAME agent or it cannot address the window it
            // just launched. Requires the token issued at registration.
            if let want = req["agent"] as? String, let token = req["token"] as? String,
               let existing = shell.windowManager.agents.first(where: { $0.id == want }) {
                guard existing.token == token else {
                    audit(want, op, false, "bad token")
                    return fail("bad token for \(want)")
                }
                conn.agentId = existing.id
                agentLastOpMs[existing.id] = nowMs
                conn.send(["id": id, "ok": true, "proto": 1, "agent": existing.id,
                           "token": existing.token, "reattached": true,
                           "scope": ["launch": (Array(Self.launchable.keys) + ["chrome"]).sorted(),
                                     "windows": "owned"]])
                audit(existing.id, op, true, "reattach \(name)")
                return
            }

            let n = shell.windowManager.agents.count + 1
            let agent = AgentInfo(id: "agent-\(n)", name: "\(name) (socket)")
            agent.isExternal = true
            shell.setState { shell.windowManager.agents.append(agent) }
            conn.agentId = agent.id
            agentLastOpMs[agent.id] = nowMs
            conn.send(["id": id, "ok": true, "proto": 1, "agent": agent.id,
                       "token": agent.token,
                       "scope": ["launch": (Array(Self.launchable.keys) + ["chrome"]).sorted(),
                                 "windows": "owned"]])
            audit(agent.id, op, true, name)
            return
        }

        // Subscribe to app status. Deliberately outside the agent scope
        // model, and the only op that is: this does not address, inject into
        // or capture anything — it reports which catalog apps are installed
        // and live, which is strictly less than the dock already shows on
        // screen. It exists so the shell can be the one place that maintains
        // app status, instead of every app deriving it again (the App Store
        // needs it to refuse removing a running app).
        if op == "subscribe_apps" {
            appSubscribers[ObjectIdentifier(conn)] = conn
            shell._refreshAppLiveness()
            var reply = Self.appStatusPayload(shell.appLiveness)
            reply["id"] = id
            reply["ok"] = true
            reply["proto"] = 1
            conn.send(reply)
            startAppTickIfNeeded()
            return
        }

        // The registry as the shell sees it: what the launcher would show and
        // what the dock would pin. Unscoped and read-only like the two below.
        // Exists so a functional test can assert on the launcher's contents
        // without screenshotting and diffing pixels, which for a compositor
        // rots faster than it catches anything.
        if op == "list_apps" {
            shell._refreshAppLiveness()
            let live = shell.appLiveness
            let apps = AppRegistry.shared.apps.map { app -> [String: Any] in
                ["app": app.id,
                 "name": app.name,
                 "installed": app.installed,
                 "dock": app.dockOrder ?? -1,
                 "window": live[app.id]?.window ?? false,
                 "process": live[app.id]?.process ?? false]
            }
            conn.send(["id": id, "ok": true, "apps": apps])
            return
        }

        // What the Launchpad is showing right now: whether it is open, the
        // live search string, and the app ids surviving that filter.
        //
        // Exists to make the search bar assertable. "Typing does nothing" is
        // the kind of report that cannot be chased by reading code — the key
        // path looks correct end to end — and a screenshot only says the pill
        // did not change, not why. With this, a test types and then asks: a
        // `query` that moved with an unchanged `filtered` is a filtering bug,
        // and a `query` that never moved is a key-delivery one.
        if op == "launcher_state" {
            conn.send(["id": id, "ok": true,
                       "open": shell._launcherOpen,
                       "query": shell._launcherQuery,
                       "filtered": shell._launcherFilteredApps().map { $0.appId }])
            return
        }

        // The WiFi picture the status-bar popup is drawing right now, so a
        // test can assert what the panel shows without reading pixels — and,
        // by comparing it against `nmcli`, that the panel is showing the
        // system's actual state rather than its own stale copy.
        if op == "wifi_state" {
            let snap = shell.networkService.snapshot
            let icon = shell.statusItemCenter(.wifi)
            let content = shell.statusPopupContent(.wifi)
            conn.send(["id": id, "ok": true,
                       "icon": ["x": icon.x, "y": icon.y],
                       "content": ["left": content.left, "width": content.width,
                                   "top": content.top, "center_x": content.centerX],
                       // Where each listed network's row actually is, so a
                       // caller clicks what the shell drew instead of
                       // reproducing its layout (see statusPopupContent).
                       "rows": shell._wifiRowCenters.map {
                           ["ssid": $0.ssid, "y": $0.y] as [String: Any]
                       },
                       "wired": snap.wired.map {
                           ["device": $0.device, "connected": $0.connected,
                            "carrier": $0.carrier, "ip": $0.ipAddress,
                            "connection": $0.connectionName,
                            "speed": $0.speed, "mac": $0.mac] as [String: Any]
                       } ?? [:],
                       "available": snap.available,
                       "enabled": snap.wifiEnabled,
                       "active": snap.active?.ssid ?? "",
                       "ip": snap.active?.ipAddress ?? "",
                       "networks": snap.networks.map { $0.ssid },
                       "saved": Array(snap.savedNames),
                       "popup_open": shell.activeStatusBarPopup == .wifi,
                       "password_prompt": shell._wifiPasswordSSID ?? "",
                       "connecting": shell._wifiConnecting ?? "",
                       "error": shell._wifiError ?? ""])
            return
        }

        // The battery picture the status bar is drawing right now — present,
        // percent, state, and where the icon is — so the functional tier can
        // drive it against the kernel's test_power module without reading
        // pixels. An absent battery reports present=false and no icon: the
        // icon does not exist on screen, and a center for it would be a lie.
        if op == "battery_state" {
            let snap = shell.batteryService.snapshot
            var reply: [String: Any] = [
                "id": id, "ok": true,
                "present": snap.present,
                "percent": snap.percent,
                "state": snap.state.label,
                "ac_online": snap.acOnline,
                "popup_open": shell.activeStatusBarPopup == .battery,
            ]
            if snap.present {
                let icon = shell.statusItemCenter(.battery)
                reply["icon"] = ["x": icon.x, "y": icon.y]
            }
            conn.send(reply)
            return
        }

        // The notification center's state — the collected events, the bell's
        // position and unseen tint, whether its popup is open — so the
        // functional tier posts over the real bus and asserts what the bell
        // collects without reading pixels.
        if op == "notification_state" {
            let icon = shell.statusItemCenter(.notifications)
            conn.send(["id": id, "ok": true,
                       "icon": ["x": icon.x, "y": icon.y],
                       "popup_open": shell.activeStatusBarPopup == .notifications,
                       "unseen": shell._notificationsUnseen,
                       "notifications": shell._notifications.map {
                           ["id": Int($0.id), "app": $0.appName,
                            "summary": $0.summary,
                            "urgency": $0.urgency] as [String: Any]
                       }])
            return
        }

        // Screen recording as the shell sees it — the state machine, the
        // elapsed clock, and where the stop indicator is — so a test can
        // start a recording from the tile, watch it become real, and stop
        // it, all without reading pixels.
        if op == "recording_state" {
            let rec = recordingService
            let stateName: String
            switch rec?.state {
            case .starting:  stateName = "starting"
            case .recording: stateName = "recording"
            case .stopping:  stateName = "stopping"
            default:         stateName = "idle"
            }
            let indicator = shell.recordingIndicatorCenter()
            conn.send(["id": id, "ok": true,
                       "available": rec?.available ?? false,
                       "state": stateName,
                       "recording": rec?.isRecording ?? false,
                       "elapsed_s": rec?.elapsedSeconds ?? 0,
                       "indicator": ["x": indicator.x, "y": indicator.y],
                       "last_file": rec?.lastSavedPath ?? "",
                       // The session's own claim about what it captures —
                       // tests compare the file against THIS, not against a
                       // re-derivation of the downscale policy.
                       "capture_w": rec?.captureWidth ?? 0,
                       "capture_h": rec?.captureHeight ?? 0,
                       "hardware": rec?.usingHardware ?? false,
                       "zero_copy": rec?.zeroCopy ?? false,
                       "window": rec?.windowLabel ?? "",
                       // Record-App picker cards, when the picker is open —
                       // a test clicks one of these to choose the window.
                       "picker": shell.recordPickerTargets().map {
                           ["title": $0.title, "x": $0.x, "y": $0.y]
                       }])
            return
        }

        // The control center as drawn right now — the icon, whether it is
        // open, each quick tile's center in declaration order, and the
        // levels behind the sliders — so a test taps what the shell laid
        // out instead of reproducing its arithmetic.
        if op == "control_center_state" {
            let icon = shell.statusItemCenter(.controlCenter)
            let tileIds = ["wifi", "dark", "tiling", "mute", "record",
                           "recordapp"]
            var tiles: [[String: Any]] = []
            for (i, tid) in tileIds.enumerated() {
                let c = shell.controlCenterTileCenter(i)
                tiles.append(["id": tid, "x": c.x, "y": c.y])
            }
            let net = shell.networkService.snapshot
            conn.send(["id": id, "ok": true,
                       "icon": ["x": icon.x, "y": icon.y],
                       "open": shell.activeStatusBarPopup == .controlCenter,
                       "tiles": tiles,
                       "wifi_available": net.available,
                       "wifi_enabled": net.wifiEnabled,
                       "dark": shellTheme.isDark,
                       "tiling": shell.windowManager.tilingEnabled,
                       "audio_available": shell._ccAudio.available,
                       "volume": shell._ccAudio.volume,
                       "muted": shell._ccAudio.muted,
                       "backlight_present": shell._ccBacklight.present,
                       "brightness": shell._ccBacklight.percent])
            return
        }

        // The screen as the shell sees it. Tooling that synthesises absolute
        // pointer events needs the PHYSICAL size to set up its device and the
        // DPI to convert; guessing either puts every click somewhere else.
        // shell-drive.py used to default to 3840x2160, which was right on the
        // machine it was written on and wrong in the 5120x2160 test VM — every
        // click landed at roughly two thirds of the intended position.
        if op == "screen" {
            let dpi = currentShellDpi
            conn.send(["id": id, "ok": true,
                       "logical": [shell.screenWidth, shell.screenHeight],
                       "physical": [shell.screenWidth * dpi,
                                    shell.screenHeight * dpi],
                       "dpi": dpi])
            return
        }

        // Live dock geometry, for tooling that needs to click a dock icon.
        // Unscoped for the same reason as subscribe_apps: read-only, and it
        // reports only where things already are on screen.
        if op == "dock_rects" {
            let slots = shell.dockSlots().map {
                ["app": $0.app, "x": $0.x, "y": $0.y, "size": $0.size] as [String: Any]
            }
            conn.send(["id": id, "ok": true, "slots": slots])
            return
        }

        // Everything else requires a registered agent.
        guard let agentId = conn.agentId else { return fail("hello first") }
        agentLastOpMs[agentId] = nowMs
        let wm = shell.windowManager

        /// Ownership chokepoint: resolve a "win" argument to a window this
        /// agent owns — anything else is invisible.
        func ownedWindow() -> WindowInfo? {
            guard let winId = req["win"] as? String,
                  let win = wm.windows.first(where: { $0.id == winId }),
                  win.ownerAgentId == agentId else { return nil }
            return win
        }

        /// Take-over: the human has the controls of this window until Esc.
        ///
        /// Every op that acts on a window OR reads its contents refuses while
        /// this holds — a hand-off that still let the agent act semantically,
        /// or screenshot what the human is typing, would be a hint rather than
        /// a boundary. It was checked only in `inject` before, which by then
        /// was the one path an agent driving a web page did not use.
        ///
        switch op {
        case "list_windows":
            let wins = wm.windows(ownedBy: agentId).map { w -> [String: Any] in
                ["win": w.id, "app": w.appId, "title": w.title,
                 "content": [w.rect.width, w.rect.height - DesktopTheme.kTitleBarHeight],
                 "focused": wm.focusedWindowId == w.id]
            }
            conn.send(["id": id, "ok": true, "windows": wins])
            audit(agentId, op, true, "\(wins.count) windows")

        case "launch":
            guard let app = req["app"] as? String else { return fail("launch needs app") }
            if app == "chrome" {
                // Wayland client from the app runtime — the arriving
                // toplevel is claimed for this agent (P4 seed; input rides
                // the shared seat until the agent wl_seat lands).
                let replied = ReplyOnce()
                let started = shell._launchAgentChrome(
                    agentId: agentId,
                    url: req["url"] as? String,
                    onWindow: { [weak self] winId in
                        guard replied.claim() else { return }
                        conn.send(["id": id, "ok": true, "win": winId])
                        self?.audit(agentId, op, true, "chrome -> \(winId)")
                    })
                guard started else { return fail("chrome launch unavailable") }
                let bail: () -> Void = { [weak self] in
                    guard replied.claim() else { return }
                    // Drop the claim on the next arriving toplevel. Left set,
                    // it is still armed when the human opens a browser later,
                    // and their window becomes the agent's.
                    shell._pendingAgentWayland = nil
                    conn.send(["id": id, "ok": false, "error": "chrome launch timed out"])
                    self?.audit(agentId, op, false, "chrome timeout")
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .seconds(25),
                    execute: unsafeBitCast(bail, to: (@Sendable () -> Void).self))
                return
            }
            guard let spec = Self.launchable[app] else {
                return fail("unknown app (scope: chrome,\(Self.launchable.keys.sorted().joined(separator: ",")))")
            }
            launchSeq += 1
            let appId = "\(agentId):\(app)#\(launchSeq)"
            let replied = ReplyOnce()
            // Launch at the pane size this window will be given, not the
            // table's nominal size: _agentStageContentSize is what actually
            // lays out, and a child launched larger draws an overflow marker
            // on its first frame. It also means the `content` size we report
            // back is the one the agent will really get.
            let pane = app == "terminal" ? shell._agentChatContentSize()
                                         : shell._agentStageContentSize()
            shell._launchAgentChildApp(
                agentId: agentId, execName: spec.exec, appId: appId,
                title: spec.title,
                rect: Rect.fromLTWH(0, 0, pane.width,
                                    pane.height + DesktopTheme.kTitleBarHeight),
                isTerminal: app == "terminal",
                onWindow: { [weak self] winId in
                    guard replied.claim() else { return }
                    conn.send(["id": id, "ok": true, "win": winId,
                               "content": [pane.width, pane.height]])
                    self?.audit(agentId, op, true, "\(app) -> \(winId)")
                })
            // Child never produced a window (missing binary, crash-on-start).
            let bail: () -> Void = { [weak self] in
                guard replied.claim() else { return }
                conn.send(["id": id, "ok": false, "error": "launch timed out"])
                self?.audit(agentId, op, false, "\(app) timeout")
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .seconds(15),
                execute: unsafeBitCast(bail, to: (@Sendable () -> Void).self))

        case "inject":
            guard let win = ownedWindow() else { return fail("no such owned window") }
            guard let ev = req["ev"] as? [String: Any],
                  let type = ev["type"] as? String else { return fail("bad ev") }
            lastInjectMs[win.id] = nowMs
            // Wayland windows take the AGENT SEAT (independent focus stream
            // — the human's pointer/keyboard are never disturbed); DMA-BUF
            // children keep their per-window sockets.
            let agentSurf: UInt32? = win.appId.hasPrefix("wayland-")
                ? waylandIntegration?.surfaceId(forWindowId: win.id) : nil
            switch type {
            case "click":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]) else { return fail("bad coords") }
                if let surf = agentSurf {
                    waylandIntegration?.agentPointerEvent(surfaceId: surf, phase: 2, x: x, y: y)
                } else {
                    win.onPointerEvent?(2, x, y, 1)
                }
                let winId = win.id
                let up: () -> Void = { [weak self, weak wm] in
                    guard let self else { return }
                    if let surf = agentSurf {
                        waylandIntegration?.agentPointerEvent(surfaceId: surf, phase: 1, x: x, y: y)
                    } else {
                        wm?.windows.first(where: { $0.id == winId })?.onPointerEvent?(1, x, y, 0)
                    }
                    self.lastInjectMs[winId] = self.nowMs
                    conn.send(["id": id, "ok": true])
                    self.audit(agentId, op, true, "click \(Int(x)),\(Int(y)) -> \(winId)")
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(60),
                    execute: unsafeBitCast(up, to: (@Sendable () -> Void).self))
            case "hover", "move":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]) else { return fail("bad coords") }
                if let surf = agentSurf {
                    waylandIntegration?.agentPointerEvent(
                        surfaceId: surf, phase: type == "hover" ? 6 : 3, x: x, y: y)
                } else {
                    win.onPointerEvent?(type == "hover" ? 6 : 3, x, y,
                                        Int64(dbl(ev["buttons"]) ?? 0))
                }
                conn.send(["id": id, "ok": true])
            case "scroll":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]),
                      let dx = dbl(ev["dx"]), let dy = dbl(ev["dy"]) else { return fail("bad coords") }
                if let surf = agentSurf {
                    waylandIntegration?.agentPointerEvent(surfaceId: surf, phase: 6, x: x, y: y)
                    waylandIntegration?.agentScrollEvent(surfaceId: surf, deltaX: dx, deltaY: dy)
                } else {
                    win.onScrollEvent?(x, y, dx, dy)
                }
                conn.send(["id": id, "ok": true])
                audit(agentId, op, true, "scroll -> \(win.id)")
            case "key":
                guard let physical = int64(ev["physical"]) else { return fail("bad key") }
                if let surf = agentSurf {
                    waylandIntegration?.agentKeyEvent(surfaceId: surf, physical: physical, isDown: true)
                    waylandIntegration?.agentKeyEvent(surfaceId: surf, physical: physical, isDown: false)
                    conn.send(["id": id, "ok": true])
                    audit(agentId, op, true, "key \(physical) (agent seat) -> \(win.id)")
                    return
                }
                guard let texId = win.textureId, let mgr = linuxProcessAppManager else {
                    return fail("bad key")
                }
                let logical = int64(ev["logical"]) ?? physical
                let character = UInt32(int64(ev["character"]) ?? 0)
                mgr.sendKeyEvent(textureId: Int64(texId), physical: physical,
                                 logical: logical, character: character, phase: 0)
                mgr.sendKeyEvent(textureId: Int64(texId), physical: physical,
                                 logical: logical, character: 0, phase: 1)
                conn.send(["id": id, "ok": true])
                audit(agentId, op, true, "key \(physical) -> \(win.id)")
            case "text":
                guard let texId = win.textureId, let mgr = linuxProcessAppManager,
                      let text = ev["text"] as? String else { return fail("bad text") }
                for scalar in text.unicodeScalars {
                    mgr.sendKeyEvent(textureId: Int64(texId), physical: 0,
                                     logical: Int64(scalar.value),
                                     character: scalar.value, phase: 0)
                    mgr.sendKeyEvent(textureId: Int64(texId), physical: 0,
                                     logical: Int64(scalar.value),
                                     character: 0, phase: 1)
                }
                conn.send(["id": id, "ok": true])
                audit(agentId, op, true, "text(\(text.count)) -> \(win.id)")
            default:
                fail("unknown ev.type \(type)")
            }

        case "capture":
            guard let win = ownedWindow() else { return fail("no such owned window") }
            guard let texId = win.textureId,
                  let info = linuxProcessAppManager?.dmaBufInfo(textureId: Int64(texId)) else {
                return fail("window has no capturable buffer")
            }
            let winId = win.id
            // Buffers are physical pixels; agents address windows in logical
            // (content-local) coordinates — declare the mapping.
            let contentW = win.rect.width
            let contentH = win.rect.height - DesktopTheme.kTitleBarHeight
            let scale = contentW > 0 ? Double(info.width) / contentW : 1.0
            let flipY = win.flipTextureY
            // mmap + base64 off the main thread; the fd stays valid for the
            // window's lifetime (owned by LinuxProcessAppManager). The
            // @Sendable coercion is the codebase idiom (main-owned values).
            let job: () -> Void = { [weak self] in
                guard let self else { return }
                let size = info.stride * info.height
                // Best-effort CPU-read coherency bracket (DMA_BUF_IOCTL_SYNC).
                var flags: UInt64 = 1 | 0  // SYNC_START | SYNC_READ
                _ = ioctl(info.fd, 0x40086200, &flags)
                guard let base = mmap(nil, size, PROT_READ, MAP_SHARED, info.fd, 0),
                      base != MAP_FAILED else {
                    conn.send(["id": id, "ok": false, "error": "mmap failed"])
                    return
                }
                let data = Data(bytes: base, count: size)
                munmap(base, size)
                flags = 1 | 4  // SYNC_END | SYNC_READ
                _ = ioctl(info.fd, 0x40086200, &flags)
                conn.send(["id": id, "ok": true,
                           "w": info.width, "h": info.height,
                           "stride": info.stride,
                           "fourcc": fourccString(info.fourcc),
                           // First-party children render GL bottom-left
                           // origin; Wayland buffers are top-down (they get
                           // flipTextureY at composite time instead).
                           "row_order": flipY ? "top-down" : "bottom-up",
                           "content": [contentW, contentH],
                           "scale": scale,
                           "data": data.base64EncodedString()])
                self.audit(conn.agentId, "capture", true,
                           "\(winId) \(info.width)x\(info.height)")
            }
            DispatchQueue.global(qos: .userInitiated).async(
                execute: unsafeBitCast(job, to: (@Sendable () -> Void).self))

        case "await_settled":
            guard let win = ownedWindow() else { return fail("no such owned window") }
            guard let texId = win.textureId else { return fail("window has no buffer") }
            let timeout = int64(req["timeout_ms"]) ?? 2000
            let quiet = int64(req["quiet_ms"]) ?? 150
            let start = nowMs
            let tex = Int64(texId)
            let winId = win.id
            func poll() {
                guard let shell = self.shell else { return }
                self.frameLock.lock()
                let lastFrame = self.lastFrameMs[tex]
                self.frameLock.unlock()
                // Quiet is measured from the LATEST activity — a frame or an
                // injection. A settle issued right after inject waits for the
                // repaint that injection causes (or quiet_ms if none comes).
                var last = lastFrame
                if let inj = self.lastInjectMs[winId] {
                    last = max(last ?? inj, inj)
                }
                let quietFor = last.map { self.nowMs - $0 } ?? Int64.max
                if quietFor >= quiet && shell._shellQuiescent {
                    conn.send(["id": id, "ok": true,
                               "settled_in_ms": self.nowMs - start])
                    self.audit(conn.agentId, "await_settled", true,
                               "\(win.id) in \(self.nowMs - start)ms")
                } else if self.nowMs - start >= timeout {
                    conn.send(["id": id, "ok": false, "error": "timeout",
                               "waited_ms": self.nowMs - start])
                    self.audit(conn.agentId, "await_settled", false, "\(win.id) timeout")
                } else {
                    let again: () -> Void = { poll() }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + .milliseconds(40),
                        execute: unsafeBitCast(again, to: (@Sendable () -> Void).self))
                }
            }
            poll()

        case "cdp_endpoint":
            // Murmuration P4: web apps are driven through the Chrome
            // DevTools Protocol, not pixels. Agent-launched Chrome runs
            // with a per-agent profile + DevTools port; this returns the
            // endpoint (same ownership chokepoint — the window must be
            // an owned Wayland toplevel).
            guard let win = ownedWindow() else { return fail("no such owned window") }
            guard win.appId.hasPrefix("wayland-") else {
                return fail("not a Wayland client window")
            }
            // Where the profile went is app-run's decision, not ours: it
            // differs between the sandboxed image (the app home bound at
            // /home/user) and a host install (the login user's own home).
            // Reconstructing it here is what made this op answer "still
            // starting" forever on every Ubuntu machine — the path it
            // rebuilt was one only the sandbox ever has. Read the pointer
            // app-run leaves instead, and keep the old path as a fallback
            // for a Chrome started by an older launcher.
            let runtimeDir = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] ?? "/tmp"
            let homes = ProcessInfo.processInfo.environment["STARLING_APP_HOMES"]
                ?? "/var/lib/starling-apps/homes"
            var profileDir = homes + "/chrome/.config/chrome-cdp-\(agentId)"
            if let pointer = try? String(
                contentsOfFile: runtimeDir + "/chrome-cdp-\(agentId).path", encoding: .utf8) {
                let line = pointer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { profileDir = line }
            }
            let portFile = profileDir + "/DevToolsActivePort"
            guard let contents = try? String(contentsOfFile: portFile, encoding: .utf8) else {
                return fail("no CDP endpoint (launched without CDP, or Chrome still starting)")
            }
            let lines = contents.split(separator: "\n").map(String.init)
            guard lines.count >= 2, let port = Int(lines[0]) else {
                return fail("malformed DevToolsActivePort")
            }
            conn.send(["id": id, "ok": true, "port": port,
                       "browser_ws": "ws://127.0.0.1:\(port)\(lines[1])",
                       "targets_url": "http://127.0.0.1:\(port)/json/list"])
            audit(agentId, op, true, "\(win.id) port \(port)")

        case "semantic_tree", "perform_action":
            // Murmuration P3: proxy to the child's semantics endpoint. The
            // agent addresses labels and node ids — no coordinates, no
            // pixels; the same ownership chokepoint applies.
            guard let win = ownedWindow() else { return fail("no such owned window") }
            guard let endpoint = win.agentEndpointPath else {
                return fail("window has no semantics endpoint")
            }
            var payload: [String: Any] = ["id": id, "op": op]
            if op == "perform_action" {
                guard let node = req["node"] as? Int,
                      let action = req["action"] as? String else {
                    return fail("perform_action needs node + action")
                }
                payload["node"] = node
                payload["action"] = action
                // Semantic actions repaint like injections do — a settle
                // right after must wait for that repaint (same rule as
                // inject).
                lastInjectMs[win.id] = nowMs
            }
            let winId = win.id
            let job: () -> Void = { [weak self] in
                let resp = Self.roundTrip(endpoint, payload)
                conn.send(resp ?? ["id": id, "ok": false,
                                   "error": "semantics endpoint unreachable"])
                self?.audit(agentId, op, resp?["ok"] as? Bool ?? false, winId)
            }
            DispatchQueue.global(qos: .userInitiated).async(
                execute: unsafeBitCast(job, to: (@Sendable () -> Void).self))

        default:
            fail("unknown op \(op)")
        }
    }

    /// One blocking JSON-lines request/response against a child's semantics
    /// endpoint (3s receive timeout). Background threads only.
    private static func roundTrip(_ path: String, _ payload: [String: Any]) -> [String: Any]? {
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 3, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: 108) { buf in
                path.withCString { src in strncpy(buf, src, 107) }
            }
        }
        let connected = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, UInt32(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }
        let out = json + Data([0x0A])
        let wrote = out.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Bool in
            var off = 0
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
        guard wrote else { return nil }
        var pending = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while !pending.contains(0x0A) {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { return nil }
            pending.append(contentsOf: buf[0..<n])
        }
        guard let nl = pending.firstIndex(of: 0x0A) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(pending[..<nl]))) as? [String: Any]
    }

    // MARK: Audit

    /// Append one line to the agent's audit log. Every effectful call lands
    /// here — the chokepoint is what makes scoping enforceable.
    private func audit(_ agentId: String?, _ op: String, _ ok: Bool, _ detail: String) {
        let path = auditDir + "/\(agentId ?? "anonymous").audit.jsonl"
        let entry: [String: Any] = [
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "op": op, "ok": ok, "detail": detail,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: entry) else { return }
        var line = json
        line.append(0x0A)
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        line.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            _ = write(fd, buf.baseAddress, buf.count)
        }
        close(fd)
    }
}

// MARK: - Small helpers

/// One-shot latch so launch answers exactly once (window or timeout).
private final class ReplyOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

private func dbl(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

private func int64(_ v: Any?) -> Int64? {
    if let i = v as? Int { return Int64(i) }
    if let d = v as? Double { return Int64(d) }
    if let n = v as? NSNumber { return n.int64Value }
    return nil
}

private func fourccString(_ f: UInt32) -> String {
    let bytes = [UInt8(f & 0xFF), UInt8((f >> 8) & 0xFF),
                 UInt8((f >> 16) & 0xFF), UInt8((f >> 24) & 0xFF)]
    return String(bytes: bytes, encoding: .ascii) ?? String(f)
}
#endif
