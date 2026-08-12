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

#if os(Linux)
import Foundation
import Glibc

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

    private var child: pid_t = -1
    private var toChild: Int32 = -1
    private var fromChild: Int32 = -1
    private let lock = NSLock()
    private var stopped = false
    private var attempt = 0
    private var lastPong = Date()

    public init(session: TerminalSession,
                host: String,
                attach: UInt32? = nil,
                command: String? = nil,
                sshPath: String = "ssh",
                serverPath: String = "starling-termd") {
        self.session = session
        self.host = host
        self.remoteId = attach
        self.command = command
        self.sshPath = sshPath
        self.serverPath = serverPath

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
            let backoff = min(8.0, pow(2.0, Double(min(attempt, 3))) * 0.25)
            Thread.sleep(forTimeInterval: backoff)
        }
    }

    /// `ssh host starling-termd --stdio`, or the daemon directly when the
    /// host is local — the same protocol either way, which is what makes a
    /// local persistent session and a remote one the same feature.
    private func spawn() -> Bool {
        var inPipe: [Int32] = [-1, -1]
        var outPipe: [Int32] = [-1, -1]
        guard pipe(&inPipe) == 0, pipe(&outPipe) == 0 else { return false }

        var argv: [String]
        if host.isEmpty || host == "local" || host == "localhost" {
            argv = [serverPath, "--stdio"]
        } else {
            // -T: no tty on the ssh channel. The stream must be the session's
            // bytes and nothing else — a pty in the middle would mangle them.
            argv = [sshPath, "-T", "-o", "BatchMode=yes",
                    "-o", "ServerAliveInterval=15", host, serverPath, "--stdio"]
        }

        let pid = fork()
        if pid < 0 { return false }
        if pid == 0 {
            dup2(inPipe[0], 0)
            dup2(outPipe[1], 1)
            close(inPipe[0]); close(inPipe[1])
            close(outPipe[0]); close(outPipe[1])
            var cargs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
            cargs.append(nil)
            if let program = cargs[0] { execvp(program, &cargs) }
            _exit(127)
        }
        close(inPipe[0])
        close(outPipe[1])
        lock.lock()
        child = pid
        toChild = inPipe[1]
        fromChild = outPipe[0]
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
            var p = RemoteTerminal.u32(id)
            p.append(contentsOf: RemoteTerminal.u64(from))
            p.append(contentsOf: RemoteTerminal.u16(UInt16(clamping: c)))
            p.append(contentsOf: RemoteTerminal.u16(UInt16(clamping: r)))
            send(.attach, p)
        } else {
            var p = RemoteTerminal.u16(UInt16(clamping: c))
            p.append(contentsOf: RemoteTerminal.u16(UInt16(clamping: r)))
            if let command = command { p.append(contentsOf: Array(command.utf8)) }
            send(.open, p)
        }
        return true
    }

    private func pump() {
        var buf = [UInt8](repeating: 0, count: 65536)
        var acc = [UInt8]()
        var lastAck: UInt64 = 0
        var lastPing = Date()
        lastPong = Date()

        while true {
            lock.lock()
            let fd = fromChild
            let done = stopped
            lock.unlock()
            if done || fd < 0 { return }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, 500)
            if ready < 0 && errno != EINTR { return }

            if ready > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                let n = read(fd, &buf, buf.count)
                if n <= 0 { return }
                acc.append(contentsOf: buf[0..<n])
                if !drain(&acc) { return }
            }
            if ready > 0 && (pfd.revents & Int16(POLLHUP | POLLERR)) != 0 { return }

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
                let msg = body.count > 2
                    ? String(decoding: body[2...], as: UTF8.self) : "error"
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

    private enum Frame: UInt8 {
        case hello = 1, helloOk = 2, list = 3, listReply = 4, open = 5
        case attach = 6, attached = 7, data = 8, input = 9, resize = 10
        case ack = 11, exit = 12, detach = 13, error = 14, ping = 15, pong = 16
    }
    static let protocolVersion = 1

    private func send(_ type: Frame, _ payload: [UInt8]) {
        lock.lock()
        let fd = toChild
        lock.unlock()
        guard fd >= 0 else { return }
        var frame = [UInt8]([type.rawValue, 0, 0, 0])
        frame.append(contentsOf: RemoteTerminal.u32(UInt32(payload.count)))
        frame.append(contentsOf: payload)
        var off = 0
        frame.withUnsafeBufferPointer { buf in
            while off < buf.count {
                let n = write(fd, buf.baseAddress! + off, buf.count - off)
                if n > 0 { off += n; continue }
                if errno == EINTR { continue }
                break
            }
        }
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
        let (pid, a, b) = (child, toChild, fromChild)
        child = -1
        toChild = -1
        fromChild = -1
        lock.unlock()
        if a >= 0 { close(a) }
        if b >= 0 { close(b) }
        if pid > 0 {
            kill(pid, SIGTERM)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
        }
    }

    private static func u16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    private static func u32(_ v: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((v >> (8 * $0)) & 0xff) }
    }
    private static func u64(_ v: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xff) }
    }
    private static func readU32(_ b: [UInt8], _ off: Int) -> UInt32 {
        UInt32(b[off]) | (UInt32(b[off + 1]) << 8)
            | (UInt32(b[off + 2]) << 16) | (UInt32(b[off + 3]) << 24)
    }
    private static func readU64(_ b: [UInt8], _ off: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(b[off + i]) << (8 * UInt64(i)) }
        return v
    }
}
#endif  // os(Linux)
