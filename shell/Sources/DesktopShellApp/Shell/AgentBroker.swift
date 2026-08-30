// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Flutter
import FlutterDRMBridge
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
//   input    — inject on the agent's own delivery path: a Wayland client's
//              surface targeted explicitly, a DMA-BUF child over its own
//              socket. The human's pointer and keyboard are never touched.
//   pixels   — capture of the window's OWN texture through the compositor's
//              resolver (clean, unoccluded, content-local; no full-screen
//              screenshots, and a covered window captures the same as a bare
//              one). A first-party child's linear DMA-BUF is the fallback.
//   settled  — await_settled v0: per-window frame-quiet + shell animations
//
// Threading: accept/read run on background GCD queues; every handler is
// marshalled onto the main queue (the codebase @Sendable-coercion idiom).
// Replies are serialized per connection on its write queue.

/// One client connection: fd + registered agent + serialized writer.
private final class BrokerConn: @unchecked Sendable {
    let fd: Int32
    var agentId: String? = nil
    /// The connecting process, from the kernel's own peer credentials — the
    /// same read that authenticates the uid. Kept because it is the only
    /// honest link back to the APP that spawned this client: an MCP server is
    /// a child of the desktop app that launched it, so walking up from here
    /// finds the window to pair the agent's workspace with.
    var peerPid: pid_t = 0
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

    /// Where this agent last put the pointer in each window (main thread,
    /// content-local logical px). There is no other honest answer to
    /// `cursor_position`: the hardware cursor belongs to the human, and
    /// reporting THAT to an agent would both leak where the person is
    /// pointing and be wrong about the agent's own last move.
    private var lastPointerPos: [String: (x: Double, y: Double)] = [:]

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

    /// Apps an agent may launch (design: scope.launch) — computed from the
    /// registry, never listed here. There WAS a table, holding four of the
    /// catalog's two dozen apps, and an agent that can only open Settings is
    /// a demo rather than computer use. The rule the rest of the shell
    /// follows applies to the broker too: the record is the one description
    /// of an app, and a second list is how the two drift.
    ///
    /// Only what an agent can actually be given exclusive ownership of: an
    /// installed first-party or host app. See the `launch` handler for why
    /// x11 and android records are refused.
    private static func launchScope() -> [String] {
        AppRegistry.shared.apps
            .filter { $0.installed && ($0.kind == .firstParty || $0.kind == .host) }
            .map(\.id)
            .sorted()
    }

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
                let conn = BrokerConn(fd: clientFd)
                conn.peerPid = Self.peerPid(clientFd)
                self.serveConnection(conn)
            }
        }
    }

    /// The connecting process id, or 0 when the kernel will not say.
    private static func peerPid(_ fd: Int32) -> pid_t {
        var cred = ucred()
        var len = socklen_t(MemoryLayout<ucred>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0
        else { return 0 }
        return pid_t(cred.pid)
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
                           "scope": ["launch": Self.launchScope(),
                                     "windows": "owned"]])
                audit(existing.id, op, true, "reattach \(name)")
                return
            }

            let n = shell.windowManager.agents.count + 1
            let agent = AgentInfo(id: "agent-\(n)", name: "\(name) (socket)")
            agent.clientPid = conn.peerPid
            // If a workspace's driver spawned this client, that workspace
            // claims it and everything it opens lands beside the app driving
            // it. Done at hello, before any window exists, so the very first
            // one is already in the right place.
            shell._bindAgentToWorkspace(agentId: agent.id, pid: conn.peerPid)
            agent.isExternal = true
            shell.setState { shell.windowManager.agents.append(agent) }
            conn.agentId = agent.id
            agentLastOpMs[agent.id] = nowMs
            conn.send(["id": id, "ok": true, "proto": 1, "agent": agent.id,
                       "token": agent.token,
                       "scope": ["launch": Self.launchScope(),
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
                 // How it is installed and launched. Reported because the
                 // launch scope is derived from it — a test that wants to
                 // check the scope against the registry would otherwise have
                 // to re-parse catalog.d itself, which is a second reader of
                 // the same file and drifts the way the deleted table did.
                 "kind": app.kind.rawValue,
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

        // Screensaver state. Unscoped and read-only, like dock_rects: it
        // reports what is already on screen. The functional tier asserts on
        // this rather than on pixels — a screensaver IS a full-screen visual
        // change, and a screenshot check for one would re-bless itself into
        // meaninglessness the first time the shader is tuned.
        if op == "screensaver" {
            conn.send(["id": id, "ok": true,
                       "active": shell._screensaverActive,
                       "idle_seconds": shell._screensaverIdleSeconds,
                       "inhibited": shell._screensaverInhibited])
            return
        }

        // Everything else requires a registered agent.
        guard let agentId = conn.agentId else { return fail("hello first") }
        agentLastOpMs[agentId] = nowMs
        let wm = shell.windowManager

        /// Why the last `ownedWindow()` came back nil. Read by the callers
        /// through `failOwned()`, so "you never had it" and "the human has it
        /// right now" are not the same sentence — an agent told "no such
        /// owned window" about a window it opened a second ago has no way to
        /// tell a revocation from a crash, and will retry forever.
        var ownedWindowError = "no such owned window"

        /// Ownership chokepoint: resolve a "win" argument to a window this
        /// agent owns and the human has not taken — anything else is
        /// invisible.
        func ownedWindow() -> WindowInfo? {
            ownedWindowError = "no such owned window"
            guard let winId = req["win"] as? String,
                  let win = wm.windows.first(where: { $0.id == winId }),
                  win.ownerAgentId == agentId else { return nil }
            // Take-over. This is deliberately INSIDE the ownership chokepoint
            // rather than beside it: every op that resolves a window is
            // covered by construction, including the ones that only read, and
            // a new op cannot forget to check. Reads are covered because a
            // window the human grabbed to type into is precisely the one that
            // must not be screenshotted.
            if win.humanHoldsControl {
                ownedWindowError = "the human has taken control of this "
                    + "window; it returns when they press Esc"
                return nil
            }
            return win
        }

        /// The refusal for a `win` argument that did not resolve.
        func failOwned() { fail(ownedWindowError) }

        // Take-over is BACK, in `ownedWindow()` above. It was lost with the
        // AI Space (3776fd6) — the flag lived in that UI — and for a while
        // nothing was regressed, because agent windows were drawn nowhere and
        // there was no surface to take over from. Agent windows now appear in
        // the workspace rail, so the guard had to return with them: touching
        // one takes it until Esc, and while it holds every op that acts on
        // the window or reads it is refused.
        switch op {
        case "list_windows":
            let wins = wm.windows(ownedBy: agentId).map { w -> [String: Any] in
                // `held` is reported even though every other op refuses the
                // window while it is set: an agent that can see the window
                // still exists, and that a person is holding it, can say so
                // and wait. One that only ever gets a refusal cannot tell
                // that from the window having died, and will retry forever.
                ["win": w.id, "app": w.appId, "title": w.title,
                 "content": [w.rect.width, w.rect.height - DesktopTheme.kTitleBarHeight],
                 "focused": wm.focusedWindowId == w.id,
                 "held": w.humanHoldsControl]
            }
            conn.send(["id": id, "ok": true, "windows": wins])
            audit(agentId, op, true, "\(wins.count) windows")

        case "launch":
            guard let app = req["app"] as? String else { return fail("launch needs app") }
            guard let rec = AppRegistry.shared.app(id: app) else {
                return fail("unknown app (scope: \(Self.launchScope().joined(separator: ",")))")
            }
            guard rec.installed else { return fail("\(app) is not installed") }
            switch rec.kind {
            case .host:
                // A third-party Wayland client out of the app runtime: the
                // arriving toplevel is claimed for this agent. The claim is a
                // single global slot, so two launches in flight would hand
                // the second agent the first one's window — refuse rather
                // than race. (Only reachable now that the whole registry is
                // launchable; with three first-party apps it never was.)
                if shell._pendingAgentWayland != nil {
                    return fail("another host-app launch is still claiming a window")
                }
                let replied = ReplyOnce()
                let started = shell._launchAgentHostApp(
                    agentId: agentId, recipe: rec.exec,
                    arg: req["url"] as? String,
                    discreteGpu: rec.discreteGpu,
                    onWindow: { [weak self] winId in
                        guard replied.claim() else { return }
                        conn.send(["id": id, "ok": true, "win": winId])
                        self?.audit(agentId, op, true, "\(app) -> \(winId)")
                    })
                guard started else { return fail("\(app) launch unavailable") }
                let bail: () -> Void = { [weak self] in
                    guard replied.claim() else { return }
                    // Drop the claim on the next arriving toplevel. Left set,
                    // it is still armed when the human opens a browser later,
                    // and their window becomes the agent's.
                    shell._pendingAgentWayland = nil
                    conn.send(["id": id, "ok": false,
                               "error": "\(app) launch timed out"])
                    self?.audit(agentId, op, false, "\(app) timeout")
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .seconds(25),
                    execute: unsafeBitCast(bail, to: (@Sendable () -> Void).self))
                return

            case .firstParty:
                launchSeq += 1
                let appId = "\(agentId):\(app)#\(launchSeq)"
                let replied = ReplyOnce()
                // Launch at the pane size this window will be given, not the
                // record's `Window=` rect: _agentStageContentSize is what
                // actually lays out, and a child launched larger draws an
                // overflow marker on its first frame. It also means the
                // `content` size we report back is the one the agent gets.
                let isTerminal = app == "terminal"
                let pane = isTerminal ? shell._agentChatContentSize()
                                      : shell._agentStageContentSize()
                shell._launchAgentChildApp(
                    agentId: agentId, execName: rec.exec, appId: appId,
                    title: rec.name,
                    rect: Rect.fromLTWH(0, 0, pane.width,
                                        pane.height + DesktopTheme.kTitleBarHeight),
                    isTerminal: isTerminal,
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

            case .x11, .android:
                // Neither fits the one-client-one-window claim this model is
                // built on, so ownership could not be established even if the
                // launch worked. WeChat is a whole rootful Xwayland screen in
                // a single window; Waydroid renders EVERY Android app into
                // one window whose title follows whichever is in front — an
                // agent handed either would be addressing the human's apps
                // too. Refusing is the scope boundary doing its job.
                return fail("\(app) cannot be agent-owned (\(rec.kind.rawValue) apps "
                            + "share one window across the whole session)")
            }

        case "inject":
            guard let win = ownedWindow() else { return failOwned() }
            guard let ev = req["ev"] as? [String: Any],
                  let type = ev["type"] as? String else { return fail("bad ev") }
            lastInjectMs[win.id] = nowMs
            let winId = win.id
            // Wayland windows take the AGENT SEAT (independent focus stream
            // — the human's pointer/keyboard are never disturbed); DMA-BUF
            // children keep their per-window sockets. EVERY action below goes
            // through one of those two, never the shared seat: an action that
            // reached for the human's pointer would silently reintroduce the
            // cursor-fighting this whole design exists to avoid.
            let agentSurf: UInt32? = win.appId.hasPrefix("wayland-")
                ? waylandIntegration?.surfaceId(forWindowId: win.id) : nil

            /// The button in both vocabularies at once: an evdev code for
            /// Wayland (the C layer passes it through verbatim) and Flutter's
            /// mask for DMA-BUF children. `rclick`/`mclick` name it; the
            /// down/up/drag forms take `ev.button`.
            func buttonCodes(_ name: String?) -> (evdev: UInt32, flutter: Int64) {
                switch name {
                case "right": return (WaylandIntegration.agentButtonRight, 2)
                case "middle": return (WaylandIntegration.agentButtonMiddle, 4)
                default: return (WaylandIntegration.agentButtonLeft, 1)
                }
            }

            /// One pointer event, routed by window kind. Phases match
            /// sendPointerEvent (2=down 1=up 3=move 6=hover). Re-resolves the
            /// window each time so a deferred half of a gesture cannot touch
            /// a window that has closed under it.
            func point(_ phase: Int32, _ x: Double, _ y: Double,
                       _ b: (evdev: UInt32, flutter: Int64)) {
                if let surf = agentSurf {
                    waylandIntegration?.agentPointerEvent(
                        surfaceId: surf, phase: phase, x: x, y: y, button: b.evdev)
                } else {
                    // Flutter's mask is the state DURING the event: the button
                    // is held on down and move, and gone on up.
                    let mask: Int64 = (phase == 1 || phase == 6) ? 0 : b.flutter
                    wm.windows.first(where: { $0.id == winId })?
                        .onPointerEvent?(phase, x, y, mask)
                }
                self.lastPointerPos[winId] = (x, y)
                self.lastInjectMs[winId] = self.nowMs
            }

            /// Main-queue delay. Gestures are built out of real gaps rather
            /// than gestures: `onDoubleTap` cannot be used on the DRM embedder
            /// (Foundation.Timer never fires there — CLAUDE.md), so a double
            /// click is genuinely two clicks with a plausible interval, which
            /// is also what a client's own double-click detection expects.
            func after(_ ms: Int, _ body: @escaping () -> Void) {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(ms),
                    execute: unsafeBitCast(body, to: (@Sendable () -> Void).self))
            }

            func done(_ what: String) {
                conn.send(["id": id, "ok": true])
                self.audit(agentId, op, true, "\(what) -> \(winId)")
            }

            switch type {
            case "click", "rclick", "mclick":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]) else { return fail("bad coords") }
                let b = buttonCodes(type == "rclick" ? "right"
                                    : type == "mclick" ? "middle"
                                    : (ev["button"] as? String))
                point(2, x, y, b)
                after(60) { [weak self] in
                    guard self != nil else { return }
                    point(1, x, y, b)
                    done("\(type) \(Int(x)),\(Int(y))")
                }

            case "dblclick":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]) else { return fail("bad coords") }
                let b = buttonCodes(ev["button"] as? String)
                // 140ms between the two presses: inside every double-click
                // threshold worth the name (400ms and up), far enough apart
                // that a client sees two distinct presses rather than one
                // bounced button.
                point(2, x, y, b)
                after(60) { point(1, x, y, b) }
                after(140) { point(2, x, y, b) }
                after(200) { [weak self] in
                    guard self != nil else { return }
                    point(1, x, y, b)
                    done("dblclick \(Int(x)),\(Int(y))")
                }

            case "tripleclick":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]) else { return fail("bad coords") }
                let b = buttonCodes(ev["button"] as? String)
                point(2, x, y, b)
                for (i, t) in [60, 140, 200, 280].enumerated() {
                    after(t) { point(i % 2 == 0 ? 1 : 2, x, y, b) }
                }
                after(340) { [weak self] in
                    guard self != nil else { return }
                    point(1, x, y, b)
                    done("tripleclick \(Int(x)),\(Int(y))")
                }

            case "down":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]) else { return fail("bad coords") }
                let b = buttonCodes(ev["button"] as? String)
                point(2, x, y, b)
                done("down \(Int(x)),\(Int(y))")

            case "up":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]) else { return fail("bad coords") }
                let b = buttonCodes(ev["button"] as? String)
                point(1, x, y, b)
                done("up \(Int(x)),\(Int(y))")

            case "drag":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]),
                      let x2 = dbl(ev["x2"]), let y2 = dbl(ev["y2"]) else {
                    return fail("drag needs x,y,x2,y2")
                }
                let b = buttonCodes(ev["button"] as? String)
                // Glide, don't teleport. A single jump from press to release
                // is not a drag to anything that reads motion — text
                // selection, a slider, a window's own move handler all follow
                // the path, and several stop tracking if they never see one.
                let steps = 12
                point(2, x, y, b)
                for i in 1...steps {
                    let t = Double(i) / Double(steps)
                    after(i * 16) {
                        point(3, x + (x2 - x) * t, y + (y2 - y) * t, b)
                    }
                }
                after(steps * 16 + 40) { [weak self] in
                    guard self != nil else { return }
                    point(1, x2, y2, b)
                    done("drag \(Int(x)),\(Int(y))->\(Int(x2)),\(Int(y2))")
                }

            case "hover", "move":
                guard let x = dbl(ev["x"]), let y = dbl(ev["y"]) else { return fail("bad coords") }
                if let surf = agentSurf {
                    waylandIntegration?.agentPointerEvent(
                        surfaceId: surf, phase: type == "hover" ? 6 : 3, x: x, y: y)
                } else {
                    win.onPointerEvent?(type == "hover" ? 6 : 3, x, y,
                                        Int64(dbl(ev["buttons"]) ?? 0))
                }
                lastPointerPos[winId] = (x, y)
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
                lastPointerPos[winId] = (x, y)
                conn.send(["id": id, "ok": true])
                audit(agentId, op, true, "scroll -> \(win.id)")

            case "key", "keydown", "keyup":
                guard let physical = int64(ev["physical"]) else { return fail("bad key") }
                // keydown/keyup are the halves `hold_key` and chords need:
                // press Ctrl, press C, release C, release Ctrl. The agent's
                // modifier state is tracked on its own seat state, so a
                // modifier held here shifts the agent's keys and nobody
                // else's.
                let down = type != "keyup"
                let up = type != "keydown"
                if let surf = agentSurf {
                    if down {
                        waylandIntegration?.agentKeyEvent(
                            surfaceId: surf, physical: physical, isDown: true)
                    }
                    if up {
                        waylandIntegration?.agentKeyEvent(
                            surfaceId: surf, physical: physical, isDown: false)
                    }
                    conn.send(["id": id, "ok": true])
                    audit(agentId, op, true, "\(type) \(physical) (agent seat) -> \(win.id)")
                    return
                }
                guard let texId = win.textureId, let mgr = linuxProcessAppManager else {
                    return fail("bad key")
                }
                let logical = int64(ev["logical"]) ?? physical
                let character = UInt32(int64(ev["character"]) ?? 0)
                if down {
                    mgr.sendKeyEvent(textureId: Int64(texId), physical: physical,
                                     logical: logical, character: character, phase: 0)
                }
                if up {
                    mgr.sendKeyEvent(textureId: Int64(texId), physical: physical,
                                     logical: logical, character: 0, phase: 1)
                }
                conn.send(["id": id, "ok": true])
                audit(agentId, op, true, "\(type) \(physical) -> \(win.id)")

            case "text":
                guard let text = ev["text"] as? String else { return fail("bad text") }
                if let surf = agentSurf {
                    // A Wayland client learns what was typed ONLY by running
                    // keys through its own xkb state — there is no "insert
                    // this string" request. This branch used to be missing
                    // entirely: `text` fell through to the DMA-BUF path,
                    // which no-ops for a Wayland window and answered ok:true,
                    // so typing into Chrome reported success and did nothing.
                    var unsupported: [String] = []
                    for scalar in text.unicodeScalars {
                        guard let k = HidEvdev.asciiKey(scalar) else {
                            unsupported.append(String(scalar))
                            continue
                        }
                        if k.shift {
                            waylandIntegration?.agentKeyEvent(
                                surfaceId: surf, physical: 0xE1, isDown: true)
                        }
                        waylandIntegration?.agentKeyEvent(
                            surfaceId: surf, physical: Int64(k.hid), isDown: true)
                        waylandIntegration?.agentKeyEvent(
                            surfaceId: surf, physical: Int64(k.hid), isDown: false)
                        if k.shift {
                            waylandIntegration?.agentKeyEvent(
                                surfaceId: surf, physical: 0xE1, isDown: false)
                        }
                    }
                    if !unsupported.isEmpty {
                        // Partial typing reported as success is the failure
                        // mode this branch exists to end. Say what was
                        // dropped; a keyboard cannot express it.
                        conn.send(["id": id, "ok": false,
                                   "error": "typed the ASCII part; no key produces "
                                            + unsupported.joined()])
                        audit(agentId, op, false, "text: unmapped \(unsupported.count)")
                        return
                    }
                    conn.send(["id": id, "ok": true])
                    audit(agentId, op, true, "text(\(text.count)) (agent seat) -> \(win.id)")
                    return
                }
                guard let texId = win.textureId, let mgr = linuxProcessAppManager else {
                    return fail("bad text")
                }
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

        case "cursor_position":
            // Where the AGENT's pointer is, not the human's. Content-local
            // logical px, the same space `inject` takes and `capture`
            // declares. Never moved by this agent means never moved: an
            // invented (0,0) reads as "the pointer is in the corner", which
            // is a different and wrong claim.
            guard let win = ownedWindow() else { return failOwned() }
            if let p = lastPointerPos[win.id] {
                conn.send(["id": id, "ok": true, "x": p.x, "y": p.y])
            } else {
                conn.send(["id": id, "ok": true, "x": NSNull(), "y": NSNull()])
            }

        case "wait":
            // A pause the audit log can see. The client could sleep on its
            // own, but then the one record of what an agent did has a hole in
            // it exactly where it waited — and `wait` is an action in the
            // tool contract, not a client-side convenience.
            let ms = max(0, min(int64(req["ms"]) ?? 500, 10_000))
            let reply: () -> Void = { [weak self] in
                conn.send(["id": id, "ok": true, "waited_ms": ms])
                self?.audit(agentId, op, true, "\(ms)ms")
            }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Int(ms)),
                execute: unsafeBitCast(reply, to: (@Sendable () -> Void).self))

        case "capture":
            guard let win = ownedWindow() else { return failOwned() }
            guard let texId = win.textureId else {
                return fail("window has no capturable buffer")
            }
            let winId = win.id
            // Buffers are physical pixels; agents address windows in logical
            // (content-local) coordinates — declare the mapping.
            let contentW = win.rect.width
            let contentH = win.rect.height - DesktopTheme.kTitleBarHeight
            let flipY = win.flipTextureY
            // What the GPU path renders into. The window's own physical size
            // by default, optionally capped on the long edge: computer-use
            // models want ~1280px images from panels three times that, and
            // the engine's blit is a scaling one, so downscaling HERE costs
            // nothing and saves base64'ing pixels nobody wants. The aspect
            // is the CONTENT's, not the texture's — a stretch is exactly
            // what keeps image px → content-logical a single linear factor.
            let dpi = currentShellDpi
            var outW = max(1, Int((contentW * dpi).rounded()))
            var outH = max(1, Int((contentH * dpi).rounded()))
            if let cap = int64(req["max_px"]), cap > 0, max(outW, outH) > Int(cap) {
                let f = Double(cap) / Double(max(outW, outH))
                outW = max(1, Int((Double(outW) * f).rounded()))
                outH = max(1, Int((Double(outH) * f).rounded()))
            }
            let dmaInfo = linuxProcessAppManager?.dmaBufInfo(textureId: Int64(texId))
            // Off the main thread: the engine path blocks on the raster
            // thread (which the platform thread services — calling it from
            // main is how you deadlock it), and base64 of a few MB is not
            // main-thread work either. The @Sendable coercion is the
            // codebase idiom (main-owned values).
            let job: () -> Void = { [weak self] in
                guard let self else { return }

                // 1. The GPU path: the window's own texture, resolved the way
                //    compositing resolves it. Works for EVERY window kind —
                //    Wayland clients included, which is the whole point: their
                //    buffers are tiled, so the mmap below hands back swizzled
                //    garbage for them rather than failing. It is also immune
                //    to the empty-read seen on virtualised GPUs, where the
                //    compositor imports the buffer as a texture and never maps
                //    it.
                if let view = drmViewHandle {
                    var rgba = [UInt8](repeating: 0, count: outW * outH * 4)
                    let rc: Int32 = rgba.withUnsafeMutableBufferPointer { buf in
                        fl_drm_view_capture_texture_once(
                            view, Int64(texId), flipY ? 1 : 0,
                            Int32(outW), Int32(outH),
                            buf.baseAddress, Int32(buf.count))
                    }
                    if rc == 0 {
                        conn.send(["id": id, "ok": true,
                                   "w": outW, "h": outH,
                                   "stride": outW * 4,
                                   // AB24 is R,G,B,A in memory — what
                                   // glReadPixels(GL_RGBA) produces, and what
                                   // clients already decode without a swap.
                                   "fourcc": "AB24",
                                   "format": "rgba",
                                   "row_order": "top-down",
                                   "content": [contentW, contentH],
                                   "scale": contentW > 0 ? Double(outW) / contentW : 1.0,
                                   "source": "texture",
                                   "data": Data(rgba).base64EncodedString()])
                        self.audit(conn.agentId, "capture", true,
                                   "\(winId) \(outW)x\(outH) texture")
                        return
                    }
                    // Fall through to the mmap path, but remember why: a
                    // silent fallback is how "the GPU capture is broken"
                    // stays invisible behind a path that happens to work for
                    // first-party windows only.
                    FileHandle.standardError.write(Data(
                        ("[AgentBroker] capture_texture_once(\(winId)) failed "
                         + "rc=\(rc) — falling back to the DMA-BUF mmap\n").utf8))
                }

                // 2. Fallback: mmap the child's linear DMA-BUF. First-party
                //    children only (Wayland surfaces never enter that table),
                //    and only while the engine path is unavailable. The fd
                //    stays valid for the window's lifetime.
                guard let info = dmaInfo else {
                    conn.send(["id": id, "ok": false,
                               "error": "window has no capturable buffer"])
                    self.audit(conn.agentId, "capture", false, "\(winId) no buffer")
                    return
                }
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
                           "scale": contentW > 0 ? Double(info.width) / contentW : 1.0,
                           "source": "dmabuf",
                           "data": data.base64EncodedString()])
                self.audit(conn.agentId, "capture", true,
                           "\(winId) \(info.width)x\(info.height) dmabuf")
            }
            DispatchQueue.global(qos: .userInitiated).async(
                execute: unsafeBitCast(job, to: (@Sendable () -> Void).self))

        case "await_settled":
            guard let win = ownedWindow() else { return failOwned() }
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
            guard let win = ownedWindow() else { return failOwned() }
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
            guard let win = ownedWindow() else { return failOwned() }
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
