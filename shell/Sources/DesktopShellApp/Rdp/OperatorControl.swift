// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import Glibc
import Flutter
import FlutterEmbedderBridge
import RdpServer
import FlutterSwiftBridge
import SwiftRuntime

// The operator socket: how an agent (or a script) drives a HEADLESS desktop
// (`DesktopShellApp --rdp`) with no RDP client, no uinput and no root.
// Design and the security argument: docs/plans/headless-desktop.md.
//
// This is deliberately NOT the Agent Broker. The broker is window-scoped
// (an agent sees only windows it launched). This socket controls the WHOLE
// desktop — input into any window, a screenshot of everything — which is the
// right power for the one operator of a private headless desktop and the
// wrong one to hand to a sandboxed agent. So it is locked to the session's
// own user three ways:
//
//   1. a unix socket under $XDG_RUNTIME_DIR (per-user, 0700), never TCP;
//   2. the socket file itself is mode 0600;
//   3. SO_PEERCRED on every accept: a peer whose uid is not ours is dropped
//      before a byte is read.
//
// Protocol: JSON lines, one request per line, one reply per request:
//   -> {"id":1,"op":"shot","path":"/tmp/a.png"}
//   <- {"id":1,"ok":true,"path":"/tmp/a.png","w":1920,"h":1080,"ms":41.2}
// Coordinates are LOGICAL pixels (physical / scale), like shell-drive.py.
//
// Ops: hello, screen, shot, windows, launch, move, click, dblclick, down, up,
// drag, scroll, key, keydown, keyup, type, stats, quit.

nonisolated(unsafe) var operatorControl: OperatorControl? = nil

/// One captured frame, top-down RGBA.
struct OperatorFrame {
    var w: UInt32
    var h: UInt32
    var rgba: [UInt8]
}

/// Shared between the engine's raster thread (present callback) and the
/// operator socket's handlers on main. Everything here is lock-guarded.
final class OperatorControl: @unchecked Sendable {

    // MARK: frame capture + stats (raster thread side)

    private let lock = NSLock()
    private var waiters: [(OperatorFrame?) -> Void] = []
    private var presentNs: [UInt64] = []
    private var readbackMs: [Double] = []
    private var statsSince = DispatchTime.now().uptimeNanoseconds
    private var cpuAtReset = OperatorControl.processCpuSeconds()

    /// Raster thread, every present: record the timestamp for fps stats.
    func notePresent() {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        presentNs.append(now)
        if presentNs.count > 20000 { presentNs.removeFirst(10000) }
        lock.unlock()
    }

    /// Raster thread: is anyone waiting on a screenshot?
    var captureWanted: Bool {
        lock.lock(); defer { lock.unlock() }
        return !waiters.isEmpty
    }

    /// Raster thread, called from present with the context current.
    func serviceCapture(egl e: OpaquePointer) {
        var w: UInt32 = 0, h: UInt32 = 0
        rdp_egl_size(e, &w, &h)
        guard w > 0, h > 0 else { return }
        var buf = [UInt8](repeating: 0, count: Int(w) * Int(h) * 4)
        let t0 = DispatchTime.now().uptimeNanoseconds
        let ok = buf.withUnsafeMutableBufferPointer {
            rdp_egl_read_frame(e, $0.baseAddress, $0.count) != 0
        }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        lock.lock()
        let ws = waiters
        waiters.removeAll()
        if ok { readbackMs.append(ms) }
        lock.unlock()
        let frame = ok ? OperatorFrame(w: w, h: h, rgba: buf) : nil
        for cb in ws { cb(frame) }
    }

    /// Main: ask for the next presented frame. Calls |done| with nil on
    /// timeout. The engine only presents when something changed, so this
    /// forces one composite — same trick the size-negotiation path uses.
    func requestFrame(timeout: Double = 5, done: @escaping (OperatorFrame?) -> Void) {
        let once = OnceFlag()
        let finish: (OperatorFrame?) -> Void = { f in
            if once.claim() { done(f) }
        }
        lock.lock()
        waiters.append(finish)
        lock.unlock()
        Flutter._forceNextComposite = true
        PlatformDispatcher.instance.scheduleFrame()
        onMain(after: timeout) { finish(nil) }
    }

    // MARK: stats

    func resetStats() {
        lock.lock()
        presentNs.removeAll()
        readbackMs.removeAll()
        statsSince = DispatchTime.now().uptimeNanoseconds
        cpuAtReset = OperatorControl.processCpuSeconds()
        lock.unlock()
    }

    func statsReply() -> [String: Any] {
        lock.lock()
        let times = presentNs
        let rb = readbackMs
        let since = statsSince
        let cpu0 = cpuAtReset
        lock.unlock()
        let now = DispatchTime.now().uptimeNanoseconds
        let wall = Double(now - since) / 1e9
        var out: [String: Any] = [
            "wall_s": wall,
            "presents": times.count,
            "fps": wall > 0 ? Double(times.count) / wall : 0,
            "cpu_s": OperatorControl.processCpuSeconds() - cpu0,
        ]
        if times.count > 2 {
            var iv: [Double] = []
            for i in 1..<times.count {
                iv.append(Double(times[i] - times[i - 1]) / 1e6)
            }
            iv.sort()
            func pct(_ p: Double) -> Double { iv[min(iv.count - 1, Int(Double(iv.count) * p))] }
            // Typed locals: inline in a [String: Any] literal, `iv.last ?? 0`
            // was inferred as the autoclosure itself and serialised as a
            // function, which the JSON writer rejects.
            let p50: Double = pct(0.5), p95: Double = pct(0.95), p99: Double = pct(0.99)
            let mx: Double = iv[iv.count - 1]
            out["interval_ms"] = ["p50": p50, "p95": p95, "p99": p99, "max": mx] as [String: Double]
        }
        if !rb.isEmpty {
            let s = rb.sorted()
            let rp50: Double = s[s.count / 2], rmax: Double = s[s.count - 1]
            out["readback_ms"] = ["n": Double(s.count), "p50": rp50, "max": rmax] as [String: Double]
        }
        return out
    }

    /// User+system CPU seconds this process has used, all threads.
    static func processCpuSeconds() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
    }

    // MARK: socket server

    private var listenFd: Int32 = -1
    private(set) var path = ""

    func start() {
        let env = ProcessInfo.processInfo.environment
        let dir = env["XDG_RUNTIME_DIR"] ?? "/tmp"
        path = env["STARLING_OPERATOR_SOCK"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(dir)/starling-operator.sock"

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else {
            warn("socket path too long: \(path)")
            return
        }
        unlink(path)
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
        guard fd >= 0 else { warn("socket(): errno \(errno)"); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            _ = path.withCString { strncpy(raw.baseAddress!.assumingMemoryBound(to: CChar.self), $0, maxLen - 1) }
        }
        // The file is created with the umask applied; 0177 → 0600 from the
        // first instant, so there is no window where another user could
        // connect. The explicit chmod is belt and braces.
        let old = umask(0o177)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(old)
        guard rc == 0 else { warn("bind \(path): errno \(errno)"); close(fd); return }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { warn("listen: errno \(errno)"); close(fd); return }
        listenFd = fd
        warn("listening on \(path) (uid \(getuid()) only)")

        let thread = Thread { [self] in
            while true {
                let c = accept4(listenFd, nil, nil, Int32(SOCK_CLOEXEC.rawValue))
                if c < 0 { if errno == EINTR { continue }; break }
                // SO_PEERCRED: the kernel's word on who is on the other end.
                var cred = ucred()
                var len = socklen_t(MemoryLayout<ucred>.size)
                let ok = getsockopt(c, SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0
                guard ok, cred.uid == getuid() else {
                    warn("rejected connection from uid \(ok ? Int(cred.uid) : -1)")
                    close(c)
                    continue
                }
                let conn = Thread { [self] in serve(fd: c) }
                conn.stackSize = 1 << 20
                conn.start()
            }
        }
        thread.stackSize = 1 << 20
        thread.start()
    }

    private func serve(fd: Int32) {
        defer { removeSubscriber(fd: fd); close(fd) }
        let writeLock = NSLock()
        let reply: ([String: Any]) -> Void = { obj in
            // A reply that cannot be serialised (NaN, a non-JSON type) must
            // still be answered, or the client waits forever on a socket
            // that looks healthy.
            var obj = obj
            if !JSONSerialization.isValidJSONObject(obj) {
                FileHandle.standardError.write(Data("[Operator] unserialisable reply: \(obj)\n".utf8))
                obj = ["id": obj["id"] ?? NSNull(), "ok": false, "error": "internal: unserialisable reply"]
            }
            guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
            let line = d + Data([0x0A])
            writeLock.lock()
            line.withUnsafeBytes { b in
                var off = 0
                while off < b.count {
                    let n = write(fd, b.baseAddress! + off, b.count - off)
                    if n <= 0 { break }
                    off += n
                }
            }
            writeLock.unlock()
        }
        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return }
            pending.append(contentsOf: chunk[0..<n])
            if pending.count > 1 << 22 { return }   // 4 MiB line: not a client
            while let nl = pending.firstIndex(of: 0x0A) {
                let lineData = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else {
                    reply(["ok": false, "error": "bad json"])
                    continue
                }
                let id = obj["id"] ?? NSNull()
                if let op = obj["op"] as? String, op == "subscribe" || op == "unsubscribe" {
                    if op == "subscribe" {
                        // Acknowledge only once the baseline snapshot exists, so
                        // anything that happens after the reply is reported.
                        subLock.lock(); subscribers[fd] = reply; subLock.unlock()
                        let ack = reply
                        onMain { self.startWatching(); ack(["id": id, "ok": true]) }
                    } else {
                        removeSubscriber(fd: fd)
                        reply(["id": id, "ok": true])
                    }
                    continue
                }
                onMain {
                    self.handle(obj) { r in
                        var r = r
                        r["id"] = id
                        reply(r)
                    }
                }
            }
        }
    }

    // MARK: ops (main queue)

    /// Runs wl-copy / wl-paste against the shell's Wayland socket. Off the
    /// main queue: wl-paste blocks until the owner answers.
    static func runClipboard(set: Bool, text: String, socket: String) -> [String: Any] {
        let p = Process()
        var env = ProcessInfo.processInfo.environment
        env["WAYLAND_DISPLAY"] = socket
        p.environment = env
        let bins = ["/usr/bin/wl-copy", "/usr/bin/wl-paste"]
        let path = set ? bins[0] : bins[1]
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return ["ok": false, "error": "wl-clipboard not installed (apt install wl-clipboard)"]
        }
        p.executableURL = URL(fileURLWithPath: path)
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        if set {
            p.arguments = []
            p.standardInput = inPipe
            // wl-copy stays alive to serve the selection; do not wait for it.
            p.standardOutput = FileHandle.nullDevice
        } else {
            p.arguments = ["--no-newline"]
            p.standardInput = FileHandle.nullDevice
        }
        do { try p.run() } catch { return ["ok": false, "error": "spawn failed: \(error)"] }
        if set {
            inPipe.fileHandleForWriting.write(Data(text.utf8))
            try? inPipe.fileHandleForWriting.close()
            Thread.sleep(forTimeInterval: 0.3)   // let it claim the selection
            return ["ok": true]
        }
        let deadline = Date().addingTimeInterval(5)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if p.isRunning { kill(p.processIdentifier, SIGTERM); return ["ok": false, "error": "clipboard read timed out"] }
        if p.terminationStatus != 0 { return ["ok": true, "text": "", "empty": true] }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return ["ok": true, "text": String(decoding: data, as: UTF8.self)]
    }

    // MARK: events (window opened / closed / focused / minimised / retitled)

    private let subLock = NSLock()
    private var subscribers: [Int32: ([String: Any]) -> Void] = [:]
    private var watching = false
    private var hooked = false
    private var lastWins: [String: [String: Any]] = [:]
    private var lastFocus: String?

    private func addSubscriber(fd: Int32, push: @escaping ([String: Any]) -> Void) {
        subLock.lock(); subscribers[fd] = push; subLock.unlock()
        onMain { self.startWatching() }
    }

    private func removeSubscriber(fd: Int32) {
        subLock.lock(); subscribers[fd] = nil; subLock.unlock()
    }

    /// Main queue. Diffs the window list every 150 ms, only while someone is
    /// subscribed — an unwatched desktop pays nothing.
    private func startWatching() {
        guard !watching, let shell = _shellState else { return }
        watching = true
        warn("watch: start")
        let wm = shell.windowManager
        lastWins = Dictionary(uniqueKeysWithValues: wm.windows.map { ($0.id, snapshot($0)) })
        lastFocus = wm.focusedWindowId
        if !hooked {
            // Opens and closes are reported the moment the window manager
            // announces them; the poll below only has to catch title and
            // focus changes. (A window that lives <150 ms is otherwise
            // invisible to a poll.)
            hooked = true
            wm.windowsObserver = { [weak self] in self?.diffNow() }
        }
        tickWatch()
    }

    /// Main queue: report what changed since the last look, to everyone listening.
    private func diffNow() {
        subLock.lock(); let subs = Array(subscribers.values); subLock.unlock()
        guard !subs.isEmpty, let shell = _shellState else { return }
        emitDiff(shell.windowManager, subs)
    }

    private func snapshot(_ w: WindowInfo) -> [String: Any] {
        ["win": w.id, "app": w.appId, "title": w.title, "minimized": w.isMinimized,
         "rect": [w.rect.left, w.rect.top, w.rect.width, w.rect.height]]
    }

    private func tickWatch() {
        subLock.lock(); let subs = Array(subscribers.values); subLock.unlock()
        guard !subs.isEmpty, let shell = _shellState else { warn("watch: stop"); watching = false; return }
        emitDiff(shell.windowManager, subs)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in tickWatch() }
    }

    private func emitDiff(_ wm: WindowManagerState, _ subs: [([String: Any]) -> Void]) {
        var now: [String: [String: Any]] = [:]
        for w in wm.windows { now[w.id] = snapshot(w) }
        var events: [[String: Any]] = []
        for (id, cur) in now {
            guard let old = lastWins[id] else {
                events.append(["event": "window_opened"].merging(cur) { a, _ in a }); continue
            }
            if (old["title"] as? String) != (cur["title"] as? String) {
                events.append(["event": "window_title"].merging(cur) { a, _ in a })
            }
            if (old["minimized"] as? Bool) != (cur["minimized"] as? Bool) {
                events.append(["event": (cur["minimized"] as? Bool) == true ? "window_minimized" : "window_restored"]
                    .merging(cur) { a, _ in a })
            }
        }
        for (id, old) in lastWins where now[id] == nil {
            events.append(["event": "window_closed"].merging(old) { a, _ in a })
        }
        if wm.focusedWindowId != lastFocus {
            lastFocus = wm.focusedWindowId
            if let f = lastFocus, let cur = now[f] {
                events.append(["event": "window_focused"].merging(cur) { a, _ in a })
            }
        }
        lastWins = now
        for e in events { for push in subs { push(e) } }
    }

    private func pickWindow(_ req: [String: Any], _ wm: WindowManagerState, requireSelector: Bool = false) -> WindowInfo? {
        if let id = req["win"] as? String { return wm.windows.first { $0.id == id } }
        if let app = req["app"] as? String { return wm.windows.first { $0.appId == app } }
        if let t = req["title_contains"] as? String { return wm.windows.first { $0.title.contains(t) } }
        if requireSelector { return nil }
        return wm.windows.first { $0.id == wm.focusedWindowId }
    }

    private func scale() -> Double { currentShellDpi > 0 ? currentShellDpi : 1.0 }

    private func handle(_ req: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
        let op = req["op"] as? String ?? ""
        func fail(_ m: String) { done(["ok": false, "error": m]) }
        func num(_ k: String) -> Double? {
            if let d = req[k] as? Double { return d }
            if let i = req[k] as? Int { return Double(i) }
            return nil
        }
        func xy() -> (Double, Double)? {
            guard let x = num("x"), let y = num("y") else { return nil }
            return (x * scale(), y * scale())
        }
        let buttonMask: Int64 = {
            switch req["button"] as? String ?? "left" {
            case "right": return 2
            case "middle": return 4
            default: return 1
            }
        }()
        let ptr = rdpPointer

        switch op {
        case "hello":
            done(["ok": true, "version": 1, "uid": Int(getuid()), "pid": Int(getpid()),
                  "mode": "headless-rdp-display"])

        case "screen":
            var w: UInt32 = 0, h: UInt32 = 0
            if let e = rdpEgl { rdp_egl_size(e, &w, &h) }
            done(["ok": true, "physical": [Int(w), Int(h)], "scale": scale(),
                  "logical": [Double(w) / scale(), Double(h) / scale()],
                  "renderer": e_renderer()])

        case "shot":
            let t0 = DispatchTime.now().uptimeNanoseconds
            requestFrame { frame in
                guard let f = frame else { return fail("no frame within timeout") }
                let tR = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                // Encode off the main queue: deflate of 4K takes real time.
                let wantPath = req["path"] as? String
                let inline = req["inline"] as? Bool == true || wantPath == nil
                let work: () -> Void = {
                    guard let png = PngEncoder.encode(rgba: f.rgba, width: Int(f.w), height: Int(f.h)) else {
                        return done(["ok": false, "error": "png encode failed"])
                    }
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
                    var out: [String: Any] = ["ok": true, "w": Int(f.w), "h": Int(f.h),
                                              "ms": ms, "frame_ms": tR, "bytes": png.count]
                    if let p = wantPath, !p.isEmpty {
                        guard (try? png.write(to: URL(fileURLWithPath: p))) != nil else {
                            return done(["ok": false, "error": "cannot write \(p)"])
                        }
                        out["path"] = p
                    }
                    if inline { out["png_b64"] = png.base64EncodedString() }
                    done(out)
                }
                DispatchQueue.global().async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
            }

        case "windows":
            guard let shell = _shellState else { return fail("shell not ready") }
            let wm = shell.windowManager
            let list = wm.windows.map { w -> [String: Any] in
                ["win": w.id, "app": w.appId, "class": w.wmClass ?? "", "title": w.title,
                 "rect": [w.rect.left, w.rect.top, w.rect.width, w.rect.height],
                 "z": w.zIndex, "focused": wm.focusedWindowId == w.id,
                 "minimized": w.isMinimized, "maximized": w.isMaximized]
            }
            done(["ok": true, "windows": list])

        case "focus", "close", "minimize", "maximize", "unmaximize", "winmove", "resize":
            // Window management. Pick the window by "win" (id from `windows`),
            // else by "app" (first match), else the focused one. Geometry is
            // LOGICAL px, the same unit `windows` reports.
            guard let shell = _shellState else { return fail("shell not ready") }
            let wm = shell.windowManager
            guard let w = self.pickWindow(req, wm) else { return fail("no such window") }
            let id = w.id
            let (sw, sh): (Double, Double) = {
                var pw: UInt32 = 0, ph: UInt32 = 0
                if let e = rdpEgl { rdp_egl_size(e, &pw, &ph) }
                return (Double(pw) / scale(), Double(ph) / scale())
            }()
            switch op {
            case "focus": wm.restoreWindow(id)
            case "close": wm.closeWindow(id)
            case "minimize": wm.minimizeWindow(id)
            case "maximize": if !w.isMaximized { wm.maximizeWindow(id, screenWidth: sw, screenHeight: sh) }
            case "unmaximize": if w.isMaximized { wm.maximizeWindow(id, screenWidth: sw, screenHeight: sh) }
            case "winmove":
                guard let x = num("x"), let y = num("y") else { return fail("winmove needs x,y") }
                wm.moveWindow(id, to: Offset(x, y))
            default:
                guard let nw = num("w"), let nh = num("h") else { return fail("resize needs w,h") }
                let cur = w.targetRect ?? w.rect
                wm.resizeWindow(id, edge: .bottomRight, delta: Offset(nw - cur.width, nh - cur.height))
            }
            PlatformDispatcher.instance.scheduleFrame()
            done(["ok": true, "win": id])

        case "wait_window":
            // {"app"|"title_contains"|"win", "state":"open"|"gone", "timeout":S}
            guard let shell = _shellState else { return fail("shell not ready") }
            let wantGone = (req["state"] as? String) == "gone"
            let deadline = Date().addingTimeInterval(num("timeout") ?? 15)
            nonisolated(unsafe) let reqU = req
            nonisolated(unsafe) let shellU = shell
            nonisolated(unsafe) let doneU = done
            let pollBox = PollBox()
            pollBox.fn = {
                let hit = self.pickWindow(reqU, shellU.windowManager, requireSelector: true)
                if (hit != nil) != wantGone {
                    return doneU(["ok": true, "win": hit?.id ?? ""])
                }
                if Date() > deadline { return doneU(["ok": false, "error": "timeout waiting for window"]) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pollBox.fn?() }
            }
            pollBox.fn?()

        case "clipboard_set", "clipboard_get":
            // The desktop clipboard, through the compositor's own data-control
            // support: wl-copy / wl-paste are ordinary clients of OUR socket,
            // so this is exactly what Chrome or a first-party app would see.
            guard let sock = waylandIntegration?.socketName, !sock.isEmpty else {
                return fail("wayland server not ready")
            }
            let text = req["text"] as? String
            if op == "clipboard_set" && text == nil { return fail("clipboard_set needs text") }
            nonisolated(unsafe) let doneU = done
            let isSet = op == "clipboard_set"
            DispatchQueue.global().async {
                let r = OperatorControl.runClipboard(set: isSet, text: text ?? "", socket: sock)
                DispatchQueue.main.async { doneU(r) }
            }

        case "launch":
            guard let app = req["app"] as? String, let shell = _shellState else {
                return fail("launch needs app")
            }
            shell._launchOrFocusApp(app)
            done(["ok": true])

        case "move":
            guard let (x, y) = xy(), let ptr else { return fail("move needs x,y") }
            ptr.handle(x: x, y: y, buttons: 0, wheelDX: 0, wheelDY: 0)
            done(["ok": true])

        case "down", "up":
            guard let (x, y) = xy(), let ptr else { return fail("needs x,y") }
            ptr.handle(x: x, y: y, buttons: op == "down" ? buttonMask : 0, wheelDX: 0, wheelDY: 0)
            done(["ok": true])

        case "click", "dblclick":
            guard let (x, y) = xy(), let ptr else { return fail("click needs x,y") }
            let reps = op == "dblclick" ? 2 : 1
            var steps: [(Double, () -> Void)] = [(0.0, { ptr.handle(x: x, y: y, buttons: 0, wheelDX: 0, wheelDY: 0) })]
            for _ in 0..<reps {
                steps.append((0.04, { ptr.handle(x: x, y: y, buttons: buttonMask, wheelDX: 0, wheelDY: 0) }))
                steps.append((0.04, { ptr.handle(x: x, y: y, buttons: 0, wheelDX: 0, wheelDY: 0) }))
            }
            sequence(steps) { done(["ok": true]) }

        case "drag":
            guard let x1 = num("x1"), let y1 = num("y1"), let x2 = num("x2"), let y2 = num("y2"),
                  let ptr else { return fail("drag needs x1,y1,x2,y2") }
            let s = scale()
            let n = 12
            var steps: [(Double, () -> Void)] = [
                (0.0, { ptr.handle(x: x1 * s, y: y1 * s, buttons: 0, wheelDX: 0, wheelDY: 0) }),
                (0.05, { ptr.handle(x: x1 * s, y: y1 * s, buttons: buttonMask, wheelDX: 0, wheelDY: 0) }),
            ]
            for i in 1...n {
                let t = Double(i) / Double(n)
                let x = (x1 + (x2 - x1) * t) * s, y = (y1 + (y2 - y1) * t) * s
                steps.append((0.016, { ptr.handle(x: x, y: y, buttons: buttonMask, wheelDX: 0, wheelDY: 0) }))
            }
            steps.append((0.05, { ptr.handle(x: x2 * s, y: y2 * s, buttons: 0, wheelDX: 0, wheelDY: 0) }))
            sequence(steps) { done(["ok": true]) }

        case "scroll":
            guard let (x, y) = xy(), let ptr else { return fail("scroll needs x,y") }
            let dx = (num("dx") ?? 0), dy = (num("dy") ?? 0)
            ptr.handle(x: x, y: y, buttons: 0, wheelDX: dx, wheelDY: dy)
            done(["ok": true])

        case "key", "keydown", "keyup":
            guard let combo = req["key"] as? String, let kbd = rdpKeyboard else {
                return fail("key needs key")
            }
            let parts = combo.lowercased().split(separator: "+").map(String.init)
            let codes = parts.compactMap { KeyTable.code(for: $0) }
            guard codes.count == parts.count, !codes.isEmpty else { return fail("unknown key in \(combo)") }
            var steps: [(Double, () -> Void)] = []
            if op != "keyup" {
                for c in codes { steps.append((0.01, { kbd.handle(scancode: c.sc, extended: c.ext, down: true) })) }
            }
            if op == "key" { steps.append((0.03, {})) }
            if op != "keydown" {
                for c in codes.reversed() { steps.append((0.01, { kbd.handle(scancode: c.sc, extended: c.ext, down: false) })) }
            }
            sequence(steps) { done(["ok": true]) }

        case "type":
            guard let text = req["text"] as? String, let kbd = rdpKeyboard else { return fail("type needs text") }
            var steps: [(Double, () -> Void)] = []
            for ch in text {
                guard let (code, shift) = KeyTable.code(forCharacter: ch) else {
                    return fail("cannot type \(ch.debugDescription) (US ASCII only)")
                }
                if shift { steps.append((0.004, { kbd.handle(scancode: 0x2A, extended: false, down: true) })) }
                steps.append((0.006, { kbd.handle(scancode: code.sc, extended: code.ext, down: true) }))
                steps.append((0.006, { kbd.handle(scancode: code.sc, extended: code.ext, down: false) }))
                if shift { steps.append((0.004, { kbd.handle(scancode: 0x2A, extended: false, down: false) })) }
            }
            sequence(steps) { done(["ok": true, "typed": text.count]) }

        case "stats":
            if req["reset"] as? Bool == true { resetStats() }
            var s = statsReply()
            s["ok"] = true
            done(s)

        case "quit":
            done(["ok": true])
            onMain(after: 0.1) { exit(0) }

        default:
            fail("unknown op \(op)")
        }
    }

    private func e_renderer() -> String {
        // GL_RENDERER is captured at startup by RdpDisplayMode (logged); the
        // egl helper only returns it with the context current, so report
        // what the process logged via env, set by runRdpDisplay.
        return ProcessInfo.processInfo.environment["STARLING_GL_RENDERER"] ?? ""
    }

    /// Run |steps| in order, each after its own delay, on the main queue.
    private func sequence(_ steps: [(Double, () -> Void)], done: @escaping () -> Void) {
        func run(_ i: Int) {
            if i >= steps.count { return done() }
            let (delay, f) = steps[i]
            onMain(after: delay) { f(); run(i + 1) }
        }
        run(0)
    }

    private func warn(_ m: String) {
        FileHandle.standardError.write(Data("[Operator] \(m)\n".utf8))
    }
}

// MARK: helpers

private final class OnceFlag: @unchecked Sendable {
    private let l = NSLock()
    private var taken = false
    func claim() -> Bool {
        l.lock(); defer { l.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}

/// The codebase's main-queue idiom: the closures here capture non-Sendable
/// state on purpose (everything touched is main-queue only).
private func onMain(_ f: @escaping () -> Void) {
    DispatchQueue.main.async(execute: unsafeBitCast(f, to: (@Sendable () -> Void).self))
}
private func onMain(after s: Double, _ f: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + s,
                                  execute: unsafeBitCast(f, to: (@Sendable () -> Void).self))
}

// MARK: keys (RDP set-1 scancodes — what RdpKeyboard takes)

enum KeyTable {
    struct Code { var sc: UInt32; var ext: Bool }

    static func code(for name: String) -> Code? {
        if let c = named[name] { return c }
        if name.count == 1, let ch = name.first, let (c, shift) = code(forCharacter: ch), !shift { return c }
        return nil
    }

    static func code(forCharacter ch: Character) -> (Code, Bool)? {
        if ch == " " { return (Code(sc: 0x39, ext: false), false) }
        if ch == "\n" { return (Code(sc: 0x1C, ext: false), false) }
        if ch == "\t" { return (Code(sc: 0x0F, ext: false), false) }
        let s = String(ch)
        if let sc = plain[s] { return (Code(sc: sc, ext: false), false) }
        if let lower = shifted[s], let sc = plain[lower] { return (Code(sc: sc, ext: false), true) }
        if ch.isUppercase, ch.isASCII, let sc = plain[s.lowercased()] { return (Code(sc: sc, ext: false), true) }
        return nil
    }

    private static let plain: [String: UInt32] = [
        "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10, "0": 11,
        "-": 12, "=": 13, "q": 16, "w": 17, "e": 18, "r": 19, "t": 20, "y": 21, "u": 22,
        "i": 23, "o": 24, "p": 25, "[": 26, "]": 27, "a": 30, "s": 31, "d": 32, "f": 33,
        "g": 34, "h": 35, "j": 36, "k": 37, "l": 38, ";": 39, "'": 40, "`": 41, "\\": 43,
        "z": 44, "x": 45, "c": 46, "v": 47, "b": 48, "n": 49, "m": 50, ",": 51, ".": 52, "/": 53,
    ]
    private static let shifted: [String: String] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
        "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", ":": ";", "\"": "'",
        "~": "`", "|": "\\", "<": ",", ">": ".", "?": "/",
    ]
    private static let named: [String: Code] = {
        var m: [String: Code] = [
            "esc": Code(sc: 1, ext: false), "escape": Code(sc: 1, ext: false),
            "backspace": Code(sc: 0x0E, ext: false), "tab": Code(sc: 0x0F, ext: false),
            "enter": Code(sc: 0x1C, ext: false), "return": Code(sc: 0x1C, ext: false),
            "ctrl": Code(sc: 0x1D, ext: false), "shift": Code(sc: 0x2A, ext: false),
            "alt": Code(sc: 0x38, ext: false), "space": Code(sc: 0x39, ext: false),
            "capslock": Code(sc: 0x3A, ext: false),
            "meta": Code(sc: 0x5B, ext: true), "super": Code(sc: 0x5B, ext: true),
            "home": Code(sc: 0x47, ext: true), "up": Code(sc: 0x48, ext: true),
            "pageup": Code(sc: 0x49, ext: true), "left": Code(sc: 0x4B, ext: true),
            "right": Code(sc: 0x4D, ext: true), "end": Code(sc: 0x4F, ext: true),
            "down": Code(sc: 0x50, ext: true), "pagedown": Code(sc: 0x51, ext: true),
            "insert": Code(sc: 0x52, ext: true), "delete": Code(sc: 0x53, ext: true),
            "f11": Code(sc: 0x57, ext: false), "f12": Code(sc: 0x58, ext: false),
        ]
        for i in 1...10 { m["f\(i)"] = Code(sc: UInt32(0x3A + i), ext: false) }
        return m
    }()
}

// MARK: PNG (zlib resolved at runtime — the package links no zlib)

enum PngEncoder {
    private typealias Compress2 = @convention(c) (
        UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt>?,
        UnsafePointer<UInt8>?, UInt, Int32) -> Int32
    private typealias CompressBound = @convention(c) (UInt) -> UInt

    private static let compress2: Compress2? = {
        guard let h = dlopen("libz.so.1", RTLD_NOW), let s = dlsym(h, "compress2") else { return nil }
        return unsafeBitCast(s, to: Compress2.self)
    }()
    private static let bound: CompressBound? = {
        guard let h = dlopen("libz.so.1", RTLD_NOW), let s = dlsym(h, "compressBound") else { return nil }
        return unsafeBitCast(s, to: CompressBound.self)
    }()

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private static func crc(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
    private static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }
        out += be(UInt32(body.count))
        let tb = Array(type.utf8) + body
        out += tb
        out += be(crc(tb))
        return out
    }

    /// RGBA8 → PNG (colour type 6, filter 0 on every row — fast; llvmpipe
    /// desktops are mostly flat colour, which deflate handles well anyway).
    static func encode(rgba: [UInt8], width: Int, height: Int) -> Data? {
        guard let compress2, let bound, rgba.count == width * height * 4 else { return nil }
        // Prepend the filter byte to each row.
        var raw = [UInt8](repeating: 0, count: (width * 4 + 1) * height)
        raw.withUnsafeMutableBufferPointer { dst in
            rgba.withUnsafeBufferPointer { src in
                for y in 0..<height {
                    dst[y * (width * 4 + 1)] = 0
                    memcpy(dst.baseAddress! + y * (width * 4 + 1) + 1,
                           src.baseAddress! + y * width * 4, width * 4)
                }
            }
        }
        var outLen = bound(UInt(raw.count))
        var z = [UInt8](repeating: 0, count: Int(outLen))
        let level: Int32 = 1   // speed over size: this is an agent's screenshot
        let rc = z.withUnsafeMutableBufferPointer { zp in
            raw.withUnsafeBufferPointer { rp in
                compress2(zp.baseAddress, &outLen, rp.baseAddress, UInt(rp.count), level)
            }
        }
        guard rc == 0 else { return nil }
        z.removeLast(z.count - Int(outLen))
        func be(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", be(width) + be(height) + [8, 6, 0, 0, 0])
        png += chunk("IDAT", z)
        png += chunk("IEND", [])
        return Data(png)
    }
}
#endif

/// Holds a self-rescheduling main-queue closure; only ever touched on main.
private final class PollBox: @unchecked Sendable { var fn: (() -> Void)? }
