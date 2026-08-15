// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The starling-termd protocol, with no transport in it.
//
// RemoteTerminal speaks this same protocol, but it OWNS its transport — it
// forks `ssh` and pumps pipes on a thread, which is the right shape on a
// desktop and an impossible one on iOS, where there is no fork and the ssh
// client is an in-process library with its own event loop. What iOS needs is
// the part of RemoteTerminal that is not a transport: framing, the
// attach/open handshake, byte offsets, ACK, the keepalive — as a machine that
// is FED bytes and EMITS frames, indifferent to what carries them.
//
// That is this type. `receive(_:)` takes whatever the transport read;
// `sendFrame` hands back encoded frames to write; everything between is the
// protocol. The session wiring is in here too — INPUT from `onOutput`,
// RESIZE from `onResize`, DATA into `feed` — because that mapping is protocol
// behaviour, identical for every transport, and leaving it to each caller is
// how two transports drift.
//
// One deliberate divergence from RemoteTerminal, for the phone: a client
// whose ATTACH is refused (the stored session is gone) OPENs a fresh one
// instead of dying, and an EXIT does the same. A desktop pane belongs to one
// session and should say so when it ends; a phone reconnecting after a week
// should always land in a shell.
//
// Offsets and reattach: `consumed` is the byte offset this client has fed to
// its emulator. A reconnect ATTACHes at that offset and the server replays
// only what was missed; a fresh launch attaches at zero and the server
// replays from the oldest byte its ring still holds, which rebuilds the
// screen and the scrollback both. ATTACHED carries the offset the server
// will ACTUALLY start from — the ring may not reach back far enough — and
// `consumed` is corrected to it, so a gap is visible once rather than
// mis-numbering everything after.

import Foundation

public final class TermdClient: @unchecked Sendable {

    /// The far side of the link, as the client learns it.
    public enum State: Sendable, Equatable {
        case attaching
        case live(session: UInt32)
        /// EXIT or a protocol error: nothing on the far side belongs to this
        /// client any more. The string is a human-readable reason, nil for a
        /// clean exit that was announced in the terminal itself.
        case ended(String?)
    }

    public let session: TerminalSession
    /// Encoded frames for the transport to write, in order. Set before
    /// `begin`; called on whatever thread `receive`/`begin` run on.
    public var sendFrame: (([UInt8]) -> Void)?
    /// Fires when the server confirms an attach — the moment the link is
    /// real. The id is what a later connection re-attaches to.
    public var onLive: ((UInt32) -> Void)?
    /// Fires once when the session is over (EXIT after `openFreshOnExit` was
    /// disabled, or a protocol error). Reconnecting is pointless after this.
    public var onEnded: ((String?) -> Void)?

    /// The far-side session id, once known — the reattach handle.
    public private(set) var remoteId: UInt32?
    /// The session's name, if this client asked for one. A durable handle in
    /// a way the id is not: ids are gone when the daemon restarts, whereas
    /// "iOS dev" is what the person typed and can type again. Sent with every
    /// OPEN, which the server treats as attach-or-create.
    public let name: String?
    /// Byte offset fed to the emulator so far: what a reconnect resumes from.
    public private(set) var consumed: UInt64 = 0
    /// True once HELLO_OK has arrived — the proof that what answered was
    /// starling-termd and not a shell printing "command not found". The
    /// transport's fallback decision reads this.
    public private(set) var sawServer = false

    /// When the attached session's shell exits, open a fresh one rather than
    /// reporting the end. On by default: see the header.
    public var openFreshOnExit = true

    private var acc = [UInt8]()
    private var cols = 80
    private var rows = 24
    private var command: String?
    private var attaching = false
    private var lastAck: UInt64 = 0
    private var lastPong = Date()
    private let lock = NSLock()

    public init(session: TerminalSession,
                name: String? = nil,
                attach: UInt32? = nil,
                from: UInt64 = 0) {
        self.session = session
        self.name = (name?.isEmpty ?? true) ? nil : name
        self.remoteId = attach
        self.consumed = from
    }

    // MARK: - Driving

    /// HELLO, then ATTACH to the known session or OPEN a new one. Also takes
    /// over the session's output and resize hooks — keys become INPUT frames,
    /// resizes become RESIZE frames — so call it when this client owns the
    /// link, and re-call it on a reconnected transport.
    public func begin(cols: Int, rows: Int, command: String? = nil) {
        lock.lock()
        self.cols = cols
        self.rows = rows
        self.command = command
        self.acc.removeAll()
        self.sawServer = false
        self.lastPong = Date()
        let id = remoteId
        let from = consumed
        lock.unlock()

        session.onOutput = { [weak self] text in
            self?.send(.input, Array(text.utf8))
        }
        session.onResize = { [weak self] c, r in
            guard let self = self else { return }
            self.lock.lock()
            self.cols = c
            self.rows = r
            self.lock.unlock()
            var p = Self.u16(UInt16(clamping: c))
            p.append(contentsOf: Self.u16(UInt16(clamping: r)))
            self.send(.resize, p)
        }

        var hello = Self.u16(UInt16(Self.protocolVersion))
        hello.append(contentsOf: Array("starling".utf8))
        send(.hello, hello)
        if let id = id {
            lock.lock(); attaching = true; lock.unlock()
            var p = Self.u32(id)
            p.append(contentsOf: Self.u64(from))
            p.append(contentsOf: Self.u16(UInt16(clamping: cols)))
            p.append(contentsOf: Self.u16(UInt16(clamping: rows)))
            send(.attach, p)
        } else {
            open()
        }
    }

    /// Bytes from the transport, any framing, any quantity. Feeds the
    /// emulator, answers the protocol, ACKs what advanced.
    public func receive(_ bytes: [UInt8]) {
        lock.lock()
        acc.append(contentsOf: bytes)
        lock.unlock()
        drain()

        lock.lock()
        let have = consumed
        let acked = lastAck
        lock.unlock()
        if have != acked {
            send(.ack, Self.u64(have))
            lock.lock(); lastAck = have; lock.unlock()
        }
    }

    /// The transport's keepalive tick: sends PING, and answers whether the
    /// far side has been silent long enough to declare the link dead — a
    /// half-open TCP connection looks healthy forever without this.
    public func keepalive(timeout: TimeInterval = 30) -> Bool {
        send(.ping, [])
        lock.lock()
        let silent = Date().timeIntervalSince(lastPong) > timeout
        lock.unlock()
        return !silent
    }

    // MARK: - Frames

    private func drain() {
        while true {
            lock.lock()
            guard acc.count >= 8 else { lock.unlock(); return }
            let type = acc[0]
            let len = Int(Self.readU32(acc, 4))
            guard len <= 1 << 21 else {
                lock.unlock()
                end("bad frame from server")
                return
            }
            guard acc.count - 8 >= len else { lock.unlock(); return }
            let body = Array(acc[8..<(8 + len)])
            acc.removeFirst(8 + len)
            lock.unlock()

            switch type {
            case Frame.helloOk.rawValue:
                lock.lock(); sawServer = true; lock.unlock()

            case Frame.attached.rawValue:
                guard body.count >= 12 else { break }
                let id = Self.readU32(body, 0)
                let from = Self.readU64(body, 4)
                lock.lock()
                attaching = false
                remoteId = id
                // The server says where it will actually resume; take its
                // word rather than mis-numbering everything after.
                if from != consumed { consumed = from }
                lastAck = consumed
                lock.unlock()
                onLive?(id)

            case Frame.data.rawValue:
                guard body.count >= 8 else { break }
                let seq = Self.readU64(body, 0)
                let bytes = Array(body[8...])
                lock.lock()
                let expected = consumed
                lock.unlock()
                if seq > expected {
                    // The ring rolled while this client was away. The screen
                    // rebuilds from here; say so once rather than pretending.
                    note("\r\n\u{1B}[38;5;244m[\(seq - expected) bytes of history dropped]\u{1B}[0m\r\n")
                }
                session.feed(bytes)
                lock.lock()
                consumed = seq + UInt64(bytes.count)
                lock.unlock()

            case Frame.exit.rawValue:
                lock.lock()
                let reopen = openFreshOnExit
                remoteId = nil
                consumed = 0
                lastAck = 0
                lock.unlock()
                if reopen {
                    note("\r\n\u{1B}[38;5;244m[remote session ended — starting a new one]\u{1B}[0m\r\n")
                    open()
                } else {
                    note("\r\n\u{1B}[38;5;244m[remote session ended]\u{1B}[0m\r\n")
                    onEnded?(nil)
                }

            case Frame.error.rawValue:
                let code = body.count >= 2 ? Self.readU16(body, 0) : 0
                lock.lock()
                let wasAttaching = attaching
                attaching = false
                lock.unlock()
                if wasAttaching && code == 1 {  // TERMD_ERR_NO_SESSION
                    // The stored session is gone — a reboot, a --kill, an
                    // idle daemon that finally exited. Not an error worth a
                    // red line on a phone: open a fresh shell.
                    lock.lock()
                    remoteId = nil
                    consumed = 0
                    lastAck = 0
                    lock.unlock()
                    open()
                } else {
                    let msg = body.count > 2
                        ? String(decoding: body[2...], as: UTF8.self) : "error"
                    end(msg)
                }

            case Frame.ping.rawValue:
                send(.pong, body)

            case Frame.pong.rawValue:
                lock.lock(); lastPong = Date(); lock.unlock()

            default:
                break
            }
        }
    }

    private func open() {
        lock.lock()
        let (c, r, cmd) = (cols, rows, command)
        lock.unlock()
        // cols, rows, then the name length-prefixed so the command after it
        // needs no escaping. A named OPEN is attach-or-create on the server:
        // this is also how a reconnect finds its session again when the id it
        // held is gone (a restarted daemon renumbers from 1).
        let n = Array((name ?? "").utf8.prefix(Self.maxNameBytes))
        var p = Self.u16(UInt16(clamping: c))
        p.append(contentsOf: Self.u16(UInt16(clamping: r)))
        p.append(contentsOf: Self.u16(UInt16(n.count)))
        p.append(contentsOf: n)
        if let cmd = cmd { p.append(contentsOf: Array(cmd.utf8)) }
        send(.open, p)
    }

    private func end(_ message: String) {
        note("\r\n\u{1B}[38;5;203m[termd: \(message)]\u{1B}[0m\r\n")
        onEnded?(message)
    }

    /// A line of our own in the user's terminal, through the emulator like
    /// any other output, so it scrolls and clears with the rest.
    private func note(_ text: String) {
        session.feed(Array(text.utf8))
    }

    // MARK: - Encoding

    private enum Frame: UInt8 {
        case hello = 1, helloOk = 2, list = 3, listReply = 4, open = 5
        case attach = 6, attached = 7, data = 8, input = 9, resize = 10
        case ack = 11, exit = 12, detach = 13, error = 14, ping = 15, pong = 16
    }
    // 2 added session names (termd/protocol.h). The daemon refuses a version
    // it does not speak, so an old server answers ERROR rather than
    // misreading a named OPEN as a command.
    static let protocolVersion = 2
    /// termd/protocol.h's TERMD_MAX_NAME, less the NUL the daemon adds.
    static let maxNameBytes = 63

    private func send(_ type: Frame, _ payload: [UInt8]) {
        var frame = [UInt8]([type.rawValue, 0, 0, 0])
        frame.append(contentsOf: Self.u32(UInt32(payload.count)))
        frame.append(contentsOf: payload)
        sendFrame?(frame)
    }

    private static func u16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    private static func u32(_ v: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((v >> (8 * $0)) & 0xff) }
    }
    private static func u64(_ v: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xff) }
    }
    private static func readU16(_ b: [UInt8], _ off: Int) -> UInt16 {
        UInt16(b[off]) | (UInt16(b[off + 1]) << 8)
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
