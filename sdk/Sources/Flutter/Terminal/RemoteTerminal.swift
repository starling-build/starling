// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The client half of the remote terminal (docs/plans/remote-terminal.md):
// a transport that drives a HEADLESS TerminalSession from a session living
// on another machine.
//
// Nothing above this knows the difference. TerminalView renders the same
// grid, sends the same keys and resizes the same way; what changes is where
// the bytes come from — `starling-termd` over an ssh exec channel instead of
// a local PTY. Because the wire format is the pty byte stream, the emulator
// here is the only one in the system: there is no second one on the server
// to disagree with it.
//
//     let session = TerminalSession()
//     let remote = RemoteTerminal(session: session, host: "prod-1")
//     remote.start()
//     TerminalView(session: session)

// macOS is here as well as the two shipping platforms: the transport is a
// child with two pipes (TermdLink.swift) and Darwin has one. A Mac terminal
// that cannot reach a remote session would be the odd one out, and it is the
// machine this is developed on.
import Foundation

public final class RemoteTerminal: @unchecked Sendable {

    /// What the link is doing, for chrome that wants to say so.
    public enum Link: Sendable, Equatable {
        case connecting
        case live(session: UInt32)
        /// The link dropped and is being rebuilt; the session on the far end
        /// is untouched and keeps running.
        case reconnecting(attempt: Int)
        case closed(String?)
    }

    public let session: TerminalSession
    public private(set) var link: Link = .connecting
    /// Fires on an internal thread whenever `link` changes.
    public var onLink: ((Link) -> Void)?

    /// The far-side session id, once known. Kept across reconnects — it is
    /// what makes the next attach resume the same shell.
    public private(set) var remoteId: UInt32?

    /// The session's name, if one was asked for — the handle that survives
    /// what the id does not. A daemon restarted between reconnects renumbers
    /// from 1, so the stale id misses (or, worse, hits someone else's
    /// session); the name still finds the right shell, or makes it.
    public var sessionName: String? { name }
    private let name: String?

    /// When an ATTACH is refused because the session is gone, open a fresh one
    /// rather than reporting the end.
    ///
    /// Off by default, and that default is the desktop's: a pane the user
    /// opened onto session 12 IS session 12, and quietly handing them a
    /// different shell under the same rectangle is worse than saying it ended.
    /// A workspace pane is the exception — its ids come out of a stored
    /// arrangement that outlives the daemon that issued them, and restoring
    /// the arrangement is the entire promise (see TerminalWorkspace.swift).
    public var reopenIfSessionGone = false

    /// Cap the backlog an ATTACH replays, in bytes. 0 (the default) means
    /// everything the far side still holds, which is what rebuilds a
    /// session's scrollback and is worth the wait for ONE session.
    ///
    /// A workspace is the case that isn't: six panes attaching at once, each
    /// entitled to 8 MB, is minutes of blank screen on a slow link when what
    /// the person wants is to see where they were. See
    /// TerminalWorkspace.swift, which sets it.
    public var maxReplayBytes: UInt32 = 0

    /// Consulted at the moment an OPEN is sent, and preferred over the fixed
    /// `command` this was built with. Called on the transport's thread.
    ///
    /// A pane that outlives the session it was attached to is reopened from
    /// here (see `reopenIfSessionGone`), and what it should run depends on
    /// where that pane had got to — which nothing knows when the pane is
    /// built. Anything reading app state from it must take its own lock.
    public var commandForOpen: (() -> String?)?

    /// The ssh destination this transport talks to, for a caller that wants
    /// to rebuild it (a reconnect button) without remembering it.
    public var hostName: String { host }
    private let host: String
    private let sshPath: String
    private let serverPath: String
    private let command: String?
    private var cols: Int = 80
    private var rows: Int = 24

    /// Byte offset consumed so far: what a reattach resumes from, and what
    /// ACK reports. The only piece of state a reconnect actually needs.
    private var consumed: UInt64 = 0

    private var child: TermdTransport?
    /// How this session reaches its daemon — see `TermdDialer`.
    private let dial: TermdDialer
    private let lock = NSLock()
    private var stopped = false
    /// An ATTACH is outstanding — which is what makes an ERROR answering it
    /// distinguishable from one answering anything else.
    private var attaching = false
    private var attempt = 0
    private var lastPong = Date()

    public init(session: TerminalSession,
                host: String,
                name: String? = nil,
                attach: UInt32? = nil,
                command: String? = nil,
                sshPath: String? = nil,
                serverPath: String? = nil,
                dial: TermdDialer? = nil) {
        self.session = session
        self.host = host
        self.name = (name?.isEmpty ?? true) ? nil : name
        self.remoteId = attach
        self.command = command
        #if os(Linux) || os(macOS) || os(Windows)
        let paths = TermdPaths(ssh: sshPath, server: serverPath)
        self.sshPath = paths.ssh
        self.serverPath = paths.server
        self.dial = dial ?? termdChildDialer(sshPath: paths.ssh,
                                             serverPath: paths.server)
        #else
        self.sshPath = sshPath ?? ""
        self.serverPath = serverPath ?? "starling-termd"
        self.dial = dial ?? { _ in nil }
        #endif

        // Keys and query responses go up the wire; the grid stays here.
        session.onOutput = { [weak self] text in
            self?.send(.input, Array(text.utf8))
        }
        session.onResize = { [weak self] c, r in
            guard let self = self else { return }
            self.lock.lock()
            self.cols = c
            self.rows = r
            self.lock.unlock()
            var payload = [UInt8]()
            payload.append(contentsOf: RemoteTerminal.u16(UInt16(clamping: c)))
            payload.append(contentsOf: RemoteTerminal.u16(UInt16(clamping: r)))
            self.send(.resize, payload)
        }
    }

    // MARK: - Lifecycle

    public func start() {
        lock.lock()
        stopped = false
        lock.unlock()
        Thread { [weak self] in self?.runLoop() }.start()
    }

    /// Drops the link. The session on the far end keeps running — that is the
    /// point of the design; use `LIST`/`--list` there to find it again.
    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        killChild()
        setLink(.closed(nil))
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
            lock.unlock()
            if stopping { return }

            attempt += 1
            // The far end is fine; only the pipe to it is gone. Say so in the
            // terminal itself rather than leaving a frozen screen.
            note("\r\n\u{1B}[38;5;244m[link lost — reconnecting…]\u{1B}[0m\r\n")
            setLink(.reconnecting(attempt: attempt))
            Thread.sleep(forTimeInterval: TermdDialPacer.backoff(attempt: attempt))
        }
    }

    /// `ssh host starling-termd --stdio`, or the daemon directly when the
    /// host is local — the same protocol either way, which is what makes a
    /// local persistent session and a remote one the same feature.
    private func spawn() -> Bool {
        // Wait for this host's turn. Every pane of a workspace dials the same
        // machine the instant a tunnel drops, and unpaced that is N handshakes
        // in one millisecond — see TermdDialPacer, which the child dialer
        // waits on for us.
        lock.lock()
        let done = stopped
        lock.unlock()
        // Waiting for a slot takes real time, and stop() can land inside it.
        if done { return false }
        guard let link = dial(host) else { return false }
        lock.lock()
        child = link
        lock.unlock()

        // HELLO, then either attach to the session we already know or open one.
        var hello = RemoteTerminal.u16(UInt16(RemoteTerminal.protocolVersion))
        hello.append(contentsOf: Array("starling".utf8))
        send(.hello, hello)
        lock.lock()
        let (c, r, id) = (cols, rows, remoteId)
        let from = consumed
        lock.unlock()
        if let id = id {
            lock.lock(); attaching = true; lock.unlock()
            var p = RemoteTerminal.u32(id)
            p.append(contentsOf: RemoteTerminal.u64(from))
            p.append(contentsOf: RemoteTerminal.u16(UInt16(clamping: c)))
            p.append(contentsOf: RemoteTerminal.u16(UInt16(clamping: r)))
            // Only on the FIRST attach. A reconnect resumes from a real
            // offset and asking for a cap there would silently discard what
            // was missed while the link was down.
            if maxReplayBytes > 0 && from == 0 {
                p.append(contentsOf: RemoteTerminal.u32(maxReplayBytes))
            }
            send(.attach, p)
        } else {
            sendOpen()
        }
        return true
    }

    /// Length-prefixed name, then the command. Named OPENs are
    /// attach-or-create server-side, so this is both "start iOS dev" and "get
    /// me back into iOS dev" — including after a daemon restart, when there is
    /// no id left to attach by.
    private func sendOpen() {
        lock.lock()
        let (c, r, fixed) = (cols, rows, command)
        let ask = commandForOpen
        lock.unlock()
        // Asked for NOW, not remembered from construction. The case this
        // exists for — the session behind a pane vanished and one is being
        // opened in its place — happens long after the pane was built, and
        // what it should run (the directory that pane is in) is only known at
        // that moment. Holding the string instead means reopening a pane with
        // whatever was true when it was first created, which for a pane that
        // was created empty is nothing at all.
        let cmd = ask?() ?? fixed
        let n = Array((name ?? "").utf8.prefix(RemoteTerminal.maxNameBytes))
        var p = RemoteTerminal.u16(UInt16(clamping: c))
        p.append(contentsOf: RemoteTerminal.u16(UInt16(clamping: r)))
        p.append(contentsOf: RemoteTerminal.u16(UInt16(n.count)))
        p.append(contentsOf: n)
        if let cmd = cmd { p.append(contentsOf: Array(cmd.utf8)) }
        send(.open, p)
    }

    private func pump() {
        var buf = [UInt8](repeating: 0, count: 65536)
        var acc = [UInt8]()
        var lastAck: UInt64 = 0
        var lastPing = Date()
        lastPong = Date()

        while true {
            lock.lock()
            let link = child
            let done = stopped
            lock.unlock()
            guard !done, let link = link else { return }

            let n = link.read(into: &buf, timeoutMs: 500)
            if n < 0 { return }
            if n > 0 {
                acc.append(contentsOf: buf[0..<n])
                if !drain(&acc) { return }
            }

            // ACK what has been consumed, so the far end knows how far back it
            // must keep for us; and a heartbeat, because a half-open TCP link
            // will otherwise sit there looking healthy forever.
            lock.lock()
            let have = consumed
            lock.unlock()
            if have != lastAck {
                send(.ack, RemoteTerminal.u64(have))
                lastAck = have
            }
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
            let len = Int(RemoteTerminal.readU32(acc, off + 4))
            if len > 1 << 21 { return false }
            if acc.count - off - 8 < len { break }
            let body = Array(acc[(off + 8)..<(off + 8 + len)])
            off += 8 + len

            switch type {
            case Frame.helloOk.rawValue:
                break
            case Frame.attached.rawValue:
                guard body.count >= 12 else { break }
                let id = RemoteTerminal.readU32(body, 0)
                let from = RemoteTerminal.readU64(body, 4)
                lock.lock()
                attaching = false
                remoteId = id
                // The server says where it will actually resume. If the ring
                // could not reach back far enough, that is a gap — take its
                // word for it rather than mis-numbering everything after.
                if from != consumed { consumed = from }
                lock.unlock()
                setLink(.live(session: id))
            case Frame.data.rawValue:
                guard body.count >= 8 else { break }
                let seq = RemoteTerminal.readU64(body, 0)
                let bytes = Array(body[8...])
                lock.lock()
                let expected = consumed
                lock.unlock()
                if seq > expected {
                    // The ring rolled while we were away: the screen will be
                    // rebuilt from here, and only history older than the ring
                    // is gone. Say so once rather than pretending.
                    note("\r\n\u{1B}[38;5;244m[\(seq - expected) bytes of history dropped]\u{1B}[0m\r\n")
                }
                session.feed(bytes)
                lock.lock()
                consumed = seq + UInt64(bytes.count)
                lock.unlock()
            case Frame.exit.rawValue:
                note("\r\n\u{1B}[38;5;244m[remote session ended]\u{1B}[0m\r\n")
                lock.lock(); stopped = true; lock.unlock()
                setLink(.closed(nil))
                return false
            case Frame.pong.rawValue:
                lastPong = Date()
            case Frame.ping.rawValue:
                send(.pong, body)
            case Frame.error.rawValue:
                let code = body.count >= 2 ? RemoteTerminal.readU16(body, 0) : 0
                let msg = body.count > 2
                    ? String(decoding: body[2...], as: UTF8.self) : "error"
                lock.lock()
                let wasAttaching = attaching
                attaching = false
                let reopen = reopenIfSessionGone
                lock.unlock()
                // TERMD_ERR_NO_SESSION on an ATTACH: the id we held is gone —
                // a reboot, a restarted daemon renumbering from 1, an idle
                // one that finally exited. A pane that belongs to a workspace
                // asks for a fresh session instead of dying, because the
                // arrangement is what was promised to survive and a dead
                // rectangle in the middle of it keeps none of that promise.
                if wasAttaching && code == 1 && reopen {
                    note("\r\n\u{1B}[38;5;244m[the session this pane held is gone — starting a new one]\u{1B}[0m\r\n")
                    lock.lock()
                    remoteId = nil
                    consumed = 0
                    lock.unlock()
                    sendOpen()
                    break
                }
                note("\r\n\u{1B}[38;5;203m[termd: \(msg)]\u{1B}[0m\r\n")
                // A protocol-level refusal will not fix itself by retrying.
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

    private typealias Frame = TermdFrame
    static let protocolVersion = TermdWire.version
    static let maxNameBytes = TermdWire.maxNameBytes

    private func send(_ type: Frame, _ payload: [UInt8]) {
        lock.lock()
        let link = child
        lock.unlock()
        link?.write(TermdWire.frame(type, payload))
    }

    /// A line of our own in the user's terminal. It goes through the emulator
    /// like any other output, so it scrolls and clears with the rest.
    private func note(_ text: String) {
        session.feed(Array(text.utf8))
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

    // One implementation of the scalars, in TermdLink.swift, so a workspace
    // link and a session link cannot come to disagree about endianness.
    private static func u16(_ v: UInt16) -> [UInt8] { TermdWire.u16(v) }
    private static func u32(_ v: UInt32) -> [UInt8] { TermdWire.u32(v) }
    private static func u64(_ v: UInt64) -> [UInt8] { TermdWire.u64(v) }
    private static func readU16(_ b: [UInt8], _ off: Int) -> UInt16 {
        TermdWire.readU16(b, off)
    }
    private static func readU32(_ b: [UInt8], _ off: Int) -> UInt32 {
        TermdWire.readU32(b, off)
    }
    private static func readU64(_ b: [UInt8], _ off: Int) -> UInt64 {
        TermdWire.readU64(b, off)
    }
}
