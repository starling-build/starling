// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The client half of a workspace (docs/plans/remote-workspace.md): a
// connection that carries no session at all.
//
// RemoteTerminal is one pane — one ATTACH, one byte stream. A workspace is
// the arrangement those panes are in, and the daemon stores it as a blob it
// never parses. Reading and writing that blob is what this type does, over a
// link of its own:
//
//     workspace "dev"                         client
//       ├── session 12  ──bytes──►  RemoteTerminal ┐
//       ├── session 13  ──bytes──►  RemoteTerminal ├─►  panes, drawn here
//       └── session 14  ──bytes──►  RemoteTerminal ┘
//       layout blob     ◄──────────  RemoteWorkspace   (this file)
//
// Why a separate connection rather than a field on a pane's: WS_* frames are
// connection-level, so any of the pane links could carry them — and then the
// workspace's identity would live inside whichever pane happened to connect
// first, and would go away with it. A workspace outlives every pane in it
// (that is the entire point), so it gets a link that outlives them too.
//
// The link is idle almost always. It answers PING, writes a blob when the
// layout moves, and otherwise sits there — which is also what makes it the
// right place to notice that the far end is gone.

#if os(Linux) || os(macOS) || os(Windows)

import Foundation

public final class RemoteWorkspace: @unchecked Sendable {

    /// What the control link is doing. A workspace whose link is down still
    /// draws — the panes have their own links — so this is chrome, not a
    /// gate: what it costs is that layout changes are not being recorded.
    public enum Link: Sendable, Equatable {
        case connecting
        case live(workspace: UInt32)
        case reconnecting(attempt: Int)
        case closed(String?)
    }

    /// The workspace's name — the durable handle, exactly as a session's name
    /// is. Ids are gone when the daemon restarts; "dev" is what the person
    /// typed and can type again.
    public let name: String
    public var hostName: String { host }

    public private(set) var link: Link = .connecting
    /// The far-side workspace id, once WS_CREATE has answered.
    public private(set) var workspaceId: UInt32?

    /// True when the daemon runs a session's command through a POSIX shell —
    /// which is what says whether a client may compose one. Known from
    /// HELLO_OK, so it is settled long before `onRestore` fires and a caller
    /// reading it there is never guessing. False for a daemon too old to say,
    /// which is the safe answer: it means "send no command you invented".
    public var serverUsesPosixShell: Bool {
        lock.lock(); defer { lock.unlock() }
        return caps.contains(.posixShell)
    }
    private var caps: TermdCaps = []

    /// Where the daemon last said a session's shell is.
    ///
    /// Polled, and only when the far side advertised that it can answer. This
    /// is the fallback under the client's own OSC 7 reading, and the one that
    /// works for shells that emit nothing — which on macOS is every zsh that
    /// is not talking to Apple Terminal.
    public func cwd(for session: UInt32) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cwds[session]
    }
    private var cwds: [UInt32: String] = [:]
    private var lastCwdPoll = Date.distantPast

    /// How often the daemon is asked. A `cd` is a human-speed event and the
    /// answer is only ever needed when a pane is being rebuilt, so this is a
    /// handful of tiny frames a minute, not a watch.
    private static let cwdPollInterval: TimeInterval = 5

    /// Fires on the link's thread once the workspace is resolved AND its
    /// stored blob has been read back — everything the client needs to
    /// rebuild the arrangement, in one callback so a caller cannot act on
    /// half of it. The blob is empty for a workspace that has never been
    /// written to, which is how a caller tells "restore this" from "this is
    /// new, lay it out however you like".
    public var onRestore: (([UInt8]) -> Void)?
    /// Fires on the link's thread whenever `link` changes.
    public var onLink: ((Link) -> Void)?

    /// Another client rearranged this workspace. Fires on the link's thread,
    /// with the arrangement it stored.
    ///
    /// The daemon sends WS_META unasked to every other connection watching a
    /// workspace, so this is how a second machine finds out that a pane was
    /// split on the first. A client that ignores it is not broken — it will
    /// simply keep drawing what it had, and overwrite the other's tree on its
    /// next change, which is exactly what this exists to stop.
    public var onLayoutChanged: (([UInt8]) -> Void)?

    private let host: String
    private let sshPath: String
    private let serverPath: String

    /// The layout as the client last drew it, and whether the daemon has been
    /// told. Held rather than sent: a seam drag is a hundred layout changes a
    /// second and the daemon needs the last one, not all of them.
    private var pending: [UInt8]?
    private var lastSent: [UInt8]?
    private var pendingAt = Date.distantPast
    /// Sessions to join, queued until the workspace has an id — a pane's
    /// ATTACHED can easily land before the control link's WS_INFO.
    private var pendingAdds: [UInt32] = []
    private var added = Set<UInt32>()

    private var child: ChildLink?
    private let lock = NSLock()
    private var stopped = false
    private var attempt = 0
    private var lastPong = Date()
    private var restored = false
    /// True from a re-established connection until its WS_META lands — which
    /// is what separates "the daemon is telling me what it had while I was
    /// away" from "another client just changed this". The first is answered by
    /// re-asserting our arrangement, the second by adopting theirs.
    private var reconnecting = false

    /// How long a layout change is held before it is written. Long enough
    /// that a drag is one write rather than a hundred, short enough that
    /// closing the window right after a split still records it.
    private static let debounce: TimeInterval = 0.4

    public init(name: String,
                host: String,
                sshPath: String? = nil,
                serverPath: String? = nil) {
        self.name = name
        self.host = host
        let paths = TermdPaths(ssh: sshPath, server: serverPath)
        self.sshPath = paths.ssh
        self.serverPath = paths.server
    }

    // MARK: - Lifecycle

    public func start() {
        lock.lock()
        stopped = false
        lock.unlock()
        Thread { [weak self] in self?.runLoop() }.start()
    }

    /// Drops the link. The workspace on the far end is untouched — its
    /// sessions keep running and its blob keeps saying how they were
    /// arranged, which is what the next attach reads.
    ///
    /// A pending layout write is flushed first, synchronously: the common way
    /// to leave a workspace is to close the window, and a split made two
    /// seconds earlier must not be the one thing that did not survive it.
    public func stop() {
        flush()
        lock.lock()
        stopped = true
        lock.unlock()
        killChild()
        setLink(.closed(nil))
    }

    // MARK: - What a caller does with a workspace

    /// Record the arrangement. Debounced — see `pending`.
    public func setLayout(_ blob: [UInt8]) {
        guard blob.count <= TermdWire.maxBlobBytes else { return }
        lock.lock()
        if blob != lastSent {
            pending = blob
            pendingAt = Date()
        }
        lock.unlock()
    }

    /// Join a session to the workspace. Idempotent here as well as in the
    /// daemon, because every pane calls it on every reconnect.
    public func add(session: UInt32) {
        guard session != 0 else { return }
        lock.lock()
        let known = added.contains(session)
        if !known { pendingAdds.append(session) }
        let id = workspaceId
        lock.unlock()
        if !known, id != nil { drainAdds() }
    }

    /// Write a pending layout now and wait briefly for the daemon's
    /// acknowledgement. Called on `stop`, and worth calling before anything
    /// else that ends the process.
    public func flush() {
        lock.lock()
        let blob = pending
        let id = workspaceId
        lock.unlock()
        guard let blob = blob, let id = id else { return }
        sendSetMeta(id, blob)
        lock.lock()
        pending = nil
        lastSent = blob
        lock.unlock()
        // The write is a frame on a pipe; giving the reader thread a moment
        // to see WS_INFO is the difference between "queued" and "landed".
        Thread.sleep(forTimeInterval: 0.05)
    }

    // MARK: - The connect / read / reconnect loop

    private func runLoop() {
        while true {
            lock.lock()
            let done = stopped
            lock.unlock()
            if done { return }

            setLink(attempt == 0 ? .connecting : .reconnecting(attempt: attempt))
            if spawn() {
                attempt = 0
                pump()                    // returns when the link dies
            }
            killChild()

            lock.lock()
            let stopping = stopped
            // The id came from a daemon that may since have restarted and
            // renumbered; WS_CREATE by name on the next connection is what
            // finds the workspace again, so the id must not be trusted across
            // the gap. Everything already added is re-added for the same
            // reason.
            workspaceId = nil
            added.removeAll()
            lock.unlock()
            if stopping { return }

            attempt += 1
            setLink(.reconnecting(attempt: attempt))
            Thread.sleep(forTimeInterval: min(8.0, pow(2.0, Double(min(attempt, 3))) * 0.25))
        }
    }

    private func spawn() -> Bool {
        let argv = termdArgv(host: host, sshPath: sshPath, serverPath: serverPath)
        guard let link = ChildLink.spawn(argv) else { return false }
        lock.lock()
        child = link
        // Every connection after the first is a reconnect, and the WS_META it
        // asks for means something different from an unasked one.
        reconnecting = restored
        lock.unlock()

        var hello = TermdWire.u16(UInt16(TermdWire.version))
        hello.append(contentsOf: Array("starling".utf8))
        send(.hello, hello)
        // Idempotent by name: this both creates the workspace and finds it
        // again, so a first launch and a reattach are the same frame.
        let n = Array(name.utf8.prefix(TermdWire.maxNameBytes))
        var p = TermdWire.u16(UInt16(n.count))
        p.append(contentsOf: n)
        send(.wsCreate, p)
        return true
    }

    private func pump() {
        var buf = [UInt8](repeating: 0, count: 8192)
        var acc = [UInt8]()
        var lastPing = Date()
        lastPong = Date()

        while true {
            lock.lock()
            let link = child
            let done = stopped
            lock.unlock()
            guard !done, let link = link else { return }

            let n = link.read(into: &buf, timeoutMs: 200)
            if n < 0 { return }
            if n > 0 {
                acc.append(contentsOf: buf[0..<n])
                if !drain(&acc) { return }
            }

            // The debounce lands here rather than on a timer: this thread
            // wakes at least every 200 ms anyway, and a timer would be one
            // more thing to cancel on the way out.
            lock.lock()
            let due = pending != nil
                && Date().timeIntervalSince(pendingAt) >= Self.debounce
            let blob = due ? pending : nil
            let id = workspaceId
            if due, id != nil {
                lastSent = pending
                pending = nil
            }
            lock.unlock()
            if let blob = blob, let id = id { sendSetMeta(id, blob) }

            pollCwds()

            if Date().timeIntervalSince(lastPing) > 10 {
                send(.ping, [])
                lastPing = Date()
            }
            if Date().timeIntervalSince(lastPong) > 30 { return }
        }
    }

    /// Consumes whole frames from `acc`. Returns false if the link must die.
    private func drain(_ acc: inout [UInt8]) -> Bool {
        var off = 0
        while acc.count - off >= 8 {
            let type = acc[off]
            let len = Int(TermdWire.readU32(acc, off + 4))
            if len > 1 << 21 { return false }
            if acc.count - off - 8 < len { break }
            let body = Array(acc[(off + 8)..<(off + 8 + len)])
            off += 8 + len

            switch type {
            case TermdFrame.helloOk.rawValue:
                // A daemon that predates the caps byte sends four; assume
                // nothing of one that says nothing.
                lock.lock()
                caps = TermdCaps(rawValue: body.count >= 5 ? body[4] : 0)
                lock.unlock()

            case TermdFrame.wsInfo.rawValue:
                guard body.count >= 6 else { break }
                let id = TermdWire.readU32(body, 0)
                lock.lock()
                let first = workspaceId == nil
                workspaceId = id
                lock.unlock()
                if first {
                    setLink(.live(workspace: id))
                    // Ask for the blob only on the connection that learned
                    // the id. WS_INFO is also the reply to every WRITE, and
                    // reading back what we just wrote would be a loop.
                    send(.wsGetMeta, TermdWire.u32(id))
                    drainAdds()
                }

            case TermdFrame.wsMeta.rawValue:
                guard body.count >= 4 else { break }
                let id = TermdWire.readU32(body, 0)
                let blob = Array(body[4...])
                lock.lock()
                let firstRestore = !restored
                restored = true
                var rewrite: [UInt8]?
                var adopt: [UInt8]?
                if firstRestore {
                    // What the daemon holds IS what this client will draw, so
                    // it must not be written straight back.
                    if !blob.isEmpty { lastSent = blob }
                } else if reconnecting {
                    // A reconnect, onto a daemon that may hold an older
                    // arrangement than the one on screen — a split made while
                    // the link was down. Here the client is the authority.
                    if let mine = lastSent, mine != blob { rewrite = mine }
                } else if lastSent != blob {
                    // Unasked, on a live link: another client rearranged the
                    // workspace. Here the OTHER end is the authority, and
                    // `lastSent` moves with it — otherwise this client would
                    // write its own tree back on its next change and the two
                    // would flap forever.
                    lastSent = blob
                    adopt = blob
                }
                reconnecting = false
                lock.unlock()
                if firstRestore { onRestore?(blob) }
                if let rewrite = rewrite { sendSetMeta(id, rewrite) }
                if let adopt = adopt { onLayoutChanged?(adopt) }

            case TermdFrame.sessionCwdReply.rawValue:
                guard body.count >= 4 else { break }
                let id = TermdWire.readU32(body, 0)
                let path = String(decoding: body[4...], as: UTF8.self)
                lock.lock()
                // An empty answer means the daemon looked and could not say —
                // a shell that has exited, a platform that cannot. Keeping the
                // last known directory beats forgetting where a pane was.
                if path.hasPrefix("/") { cwds[id] = path }
                lock.unlock()

            case TermdFrame.ping.rawValue:
                send(.pong, body)
            case TermdFrame.pong.rawValue:
                lastPong = Date()

            case TermdFrame.error.rawValue:
                let code = body.count >= 2 ? TermdWire.readU16(body, 0) : 0
                let msg = body.count > 2
                    ? String(decoding: body[2...], as: UTF8.self) : "error"
                // TERMD_ERR_NO_SESSION: a WS_ADD for a session that has since
                // exited. Ordinary — a pane can die between its ATTACHED and
                // this frame — and nothing about the workspace is wrong, so
                // the link stays up. Everything else (no such workspace, a
                // daemon that is full, one too old to know what a workspace
                // is) will not fix itself by retrying.
                if code == 1 { break }
                lock.lock(); stopped = true; lock.unlock()
                setLink(.closed(msg))
                return false

            default:
                break
            }
        }
        if off > 0 { acc.removeFirst(off) }
        return true
    }

    // MARK: - Plumbing

    /// Ask the daemon where each of this workspace's sessions is.
    ///
    /// Only when it said it can answer: an unknown frame comes back as an
    /// ERROR, and the control link treats those as fatal for good reason.
    private func pollCwds() {
        lock.lock()
        guard caps.contains(.sessionCwd),
              Date().timeIntervalSince(lastCwdPoll) >= Self.cwdPollInterval
        else { lock.unlock(); return }
        lastCwdPoll = Date()
        let sessions = added
        lock.unlock()
        for session in sessions { send(.sessionCwd, TermdWire.u32(session)) }
    }

    private func drainAdds() {
        lock.lock()
        guard let id = workspaceId else { lock.unlock(); return }
        let sessions = pendingAdds
        pendingAdds.removeAll()
        for s in sessions { added.insert(s) }
        // A session that just joined has never been asked where it is; don't
        // make its first answer wait out the poll interval.
        if !sessions.isEmpty { lastCwdPoll = .distantPast }
        lock.unlock()
        for session in sessions {
            var p = TermdWire.u32(id)
            p.append(contentsOf: TermdWire.u32(session))
            send(.wsAdd, p)
        }
    }

    private func sendSetMeta(_ id: UInt32, _ blob: [UInt8]) {
        var p = TermdWire.u32(id)
        p.append(contentsOf: blob)
        send(.wsSetMeta, p)
    }

    private func send(_ type: TermdFrame, _ payload: [UInt8]) {
        lock.lock()
        let link = child
        lock.unlock()
        link?.write(TermdWire.frame(type, payload))
    }

    private func setLink(_ new: Link) {
        lock.lock()
        let changed = link != new
        link = new
        lock.unlock()
        if changed { onLink?(new) }
    }

    private func killChild() {
        lock.lock()
        let link = child
        child = nil
        lock.unlock()
        link?.close()
    }
}

#endif  // os(Linux) || os(macOS) || os(Windows)
