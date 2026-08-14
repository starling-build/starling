// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// An ssh session driving a HEADLESS TerminalSession: the transport the iOS
// app exists for.
//
// It is the same arrangement as RemoteTerminal — the emulator lives here and
// the shell lives on the far machine — but against a stock sshd rather than
// starling-termd, so there is nothing to install on the machine being reached.
// What crosses the wire is the pty byte stream, which is what ssh carries
// anyway, so the emulator here remains the only one involved.
//
// This is an in-process ssh client (SwiftNIO SSH) rather than a spawned `ssh`
// because iOS has neither fork nor exec: a child process is not merely
// awkward there, it is impossible. That is also why the rest of the app can
// keep using RemoteTerminal's spawned-child transport on the desktop without
// either of them being wrong.
//
//     let session = TerminalSession()
//     let ssh = SSHTerminal(session: session)
//     ssh.connect(host: "mac-mini.local", port: 22, user: "me", password: pw)
//     TerminalView(session: session)

#if os(iOS)
import Flutter
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Trust on first use, the way `ssh` itself behaves on a host it has not seen
/// — with the difference that iOS has no known_hosts file, so the record is
/// UserDefaults, keyed by host and port.
///
/// The alternative that keeps coming up is to accept every key. That is not a
/// weaker version of this, it is a different thing: it means the connection
/// can be silently intercepted by anything on the path, and the password
/// typed into this app goes to whatever answered. Pinning on first sight
/// costs nothing and turns the second connection into a real check.
///
/// A mismatch is reported, not tolerated. Rekeying a machine is a real event
/// and `forget(host:port:)` is how the user says so.
private final class TrustOnFirstUse: NIOSSHClientServerAuthenticationDelegate {
    private let key: String

    /// The pin is versioned because the first implementation stored something
    /// that could never match — see `validateHostKey`. Bumping the key name
    /// discards those values rather than reporting every machine as rekeyed.
    private static let prefix = "starling.ssh.hostkey.v2."

    init(host: String, port: Int) {
        self.key = "\(TrustOnFirstUse.prefix)\(host):\(port)"
    }

    static func forget(host: String, port: Int) {
        UserDefaults.standard.removeObject(forKey: "\(prefix)\(host):\(port)")
    }

    func validateHostKey(hostKey: NIOSSHPublicKey,
                         validationCompletePromise: EventLoopPromise<Void>) {
        // The key's own bytes, in OpenSSH's "algorithm-id base64-blob" form —
        // the same text a known_hosts line carries, so a pin can be compared
        // with one by eye.
        //
        // What this must NOT be is Swift's `Hasher`, which is what it was.
        // `Hasher` is seeded randomly PER PROCESS, so hashing the same key
        // twice in two launches gives two different values: the first
        // connection to a machine pinned a number that the second could never
        // reproduce, and every connection after the first failed as a changed
        // host key. It looked like the app breaking overnight rather than a
        // hash being unstable, because the first run of a fresh install always
        // worked.
        let fingerprint = String(openSSHPublicKey: hostKey)

        let defaults = UserDefaults.standard
        guard let known = defaults.string(forKey: key) else {
            defaults.set(fingerprint, forKey: key)
            validationCompletePromise.succeed(())
            return
        }
        if known == fingerprint {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(SSHTerminal.Failure.hostKeyChanged)
        }
    }
}

/// Remembers the last error the connection saw, so a handshake that fails can
/// say why.
///
/// Everything before the session channel exists — the version exchange, key
/// exchange, host-key validation, authentication — happens on the parent
/// channel, and NIOSSH reports those failures by firing an error down that
/// pipeline and closing. `SessionChannelHandler` is on the CHILD channel and
/// is never added when the handshake fails, so without this the error had
/// nowhere to land: the connection simply closed and the app sat on
/// "connecting…" for ever, with no message and no way to retry.
private final class ErrorCapture: ChannelInboundHandler {
    typealias InboundIn = Any

    private let lock = NSLock()
    private var _error: Error?

    var error: Error? {
        lock.lock(); defer { lock.unlock() }
        return _error
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        lock.lock()
        if _error == nil { _error = error }
        lock.unlock()
        context.fireErrorCaught(error)
    }
}

/// Pumps one ssh exec channel into and out of a TermdClient: the transport
/// half of the persistent-session arrangement, with the protocol half in the
/// sdk (`TermdClient`, which explains the split).
///
/// No pty is requested, deliberately. The stream must be termd's frames and
/// nothing else — a pty in the middle would translate newlines, echo input
/// and mangle every byte over 0x7f. That is also why stderr is routed to the
/// screen as text rather than into the client: the far side's `sh -lc` and
/// termd itself both report their troubles there ("command not found",
/// "could not start the daemon"), and those lines are for the person.
private final class TermdChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let client: TermdClient
    private let command: String
    private let onReady: () -> Void
    private let onClose: (String?) -> Void

    init(client: TermdClient, command: String,
         onReady: @escaping () -> Void,
         onClose: @escaping (String?) -> Void) {
        self.client = client
        self.command = command
        self.onReady = onReady
        self.onClose = onClose
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let exec = SSHChannelRequestEvent.ExecRequest(
            command: command, wantReply: true)
        context.triggerUserOutboundEvent(exec).whenComplete { [weak self] result in
            switch result {
            case .failure(let error):
                self?.onClose("exec refused: \(error)")
            case .success:
                self?.onReady()
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        let bytes = Array(buffer.readableBytesView)
        if case .stdErr = channelData.type {
            client.session.feed(Array("\u{1B}[38;5;244m".utf8))
            client.session.feed(bytes)
            client.session.feed(Array("\u{1B}[0m".utf8))
        } else {
            client.receive(bytes)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let status = event as? SSHChannelRequestEvent.ExitStatus {
            // 127 is "starling-termd: command not found" from the login
            // shell — the fallback trigger, reported by exit status because
            // by then there is no other channel left to say it on.
            onClose(status.exitStatus == 0
                    ? nil : "termd bridge exited with status \(status.exitStatus)")
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose(nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        onClose("\(error)")
        context.close(promise: nil)
    }
}

/// Pumps one ssh session channel into and out of a TerminalSession.
private final class SessionChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let session: TerminalSession
    private let onReady: () -> Void
    private let onClose: (String?) -> Void
    private var reportedReady = false

    init(session: TerminalSession,
         onReady: @escaping () -> Void,
         onClose: @escaping (String?) -> Void) {
        self.session = session
        self.onReady = onReady
        self.onClose = onClose
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // The PTY has to be requested before the shell, and both before any
        // byte moves: a shell started with no pty gets no job control, no
        // line editing and no TERM, which reads as "the prompt is missing"
        // rather than "the request was in the wrong order".
        let (cols, rows) = (session.emulator.cols, session.emulator.rows)
        let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:]))
        context.triggerUserOutboundEvent(pty).whenComplete { [weak self] result in
            switch result {
            case .failure(let error):
                self?.onClose("pty request refused: \(error)")
            case .success:
                context.triggerUserOutboundEvent(
                    SSHChannelRequestEvent.ShellRequest(wantReply: true)
                ).whenComplete { shell in
                    switch shell {
                    case .failure(let error):
                        self?.onClose("shell request refused: \(error)")
                    case .success:
                        self?.markReady()
                    }
                }
            }
        }
    }

    private func markReady() {
        guard !reportedReady else { return }
        reportedReady = true
        onReady()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        // stdout and stderr both belong on the screen, undivided — that is
        // what a pty does on the far side anyway, and a terminal that dropped
        // stderr would hide exactly the output worth reading.
        session.feed(Array(buffer.readableBytesView))
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let status = event as? SSHChannelRequestEvent.ExitStatus {
            onClose(status.exitStatus == 0
                    ? nil : "the shell exited with status \(status.exitStatus)")
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        onClose(nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        onClose("\(error)")
        context.close(promise: nil)
    }
}

public final class SSHTerminal: @unchecked Sendable {

    public enum Failure: Error {
        case hostKeyChanged
        /// The connection closed before the shell was running and the pipeline
        /// recorded no error of its own.
        case closedDuringHandshake
    }

    /// What the connection is doing, for chrome that wants to say so.
    public enum Link: Sendable, Equatable {
        case idle
        case connecting
        case live
        case failed(String)
    }

    public let session: TerminalSession
    public private(set) var link: Link = .idle
    /// Fires on an internal thread whenever `link` changes.
    public var onLink: ((Link) -> Void)?

    private let group: MultiThreadedEventLoopGroup
    private var connection: Channel?
    private var channel: Channel?
    private var _reachedLive = false
    private var _reported = false
    private let lock = NSLock()

    // ── the persistent-session state ────────────────────────────────────
    /// The protocol engine, created on the first termd connection and kept
    /// across reconnects — it holds the session id and the byte offset, which
    /// are exactly what a resume needs.
    private var termd: TermdClient?
    /// Credentials, kept in memory for the lifetime of this object so a
    /// dropped link can be rebuilt without asking again. Never persisted:
    /// the app's rule is that a password is typed per connection, and a
    /// reconnect is the same connection from the user's point of view.
    private var creds: (host: String, port: Int, user: String, password: String)?
    /// False once termd proved absent on this host — the plain-shell
    /// fallback, which cannot resume and therefore must not auto-reconnect.
    private var termdMode = true
    private var reconnectAttempt = 0
    private var userStopped = false
    private var keepalive: RepeatedTask?

    /// Where the far side's session id is remembered between app launches,
    /// so a relaunch walks back into the same shell.
    private var sessionKey: String? {
        guard let c = creds else { return nil }
        return "starling.termd.session.\(c.user)@\(c.host):\(c.port)"
    }

    public init(session: TerminalSession) {
        self.session = session
        // One thread: this drives a single interactive session, and its
        // traffic is a person typing.
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    /// Forget a machine's pinned host key, for the case where it really was
    /// rekeyed. The next connection pins whatever it is offered.
    public static func forgetHostKey(host: String, port: Int) {
        TrustOnFirstUse.forget(host: host, port: port)
    }

    public func connect(host: String, port: Int, user: String, password: String) {
        // Both latches are per-attempt. Left set, a retry on the same object
        // would suppress the second failure's message and read the previous
        // attempt's success as this one's.
        lock.lock()
        _reachedLive = false
        _reported = false
        creds = (host, port, user, password)
        userStopped = false
        lock.unlock()
        setLink(.connecting)
        note("\u{1B}[38;5;244mconnecting to \(user)@\(host):\(port)…\u{1B}[0m\r\n")

        let errors = ErrorCapture()
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    NIOSSHHandler(
                        role: .client(SSHClientConfiguration(
                            userAuthDelegate: SimplePasswordDelegate(
                                username: user, password: password),
                            serverAuthDelegate: TrustOnFirstUse(host: host, port: port))),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil),
                    errors,
                ])
            }

        bootstrap.connect(host: host, port: port).whenComplete { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.fail(self.describe(error))
            case .success(let connection):
                self.lock.lock()
                self.connection = connection
                self.lock.unlock()
                // A connection that closes before the shell is running failed,
                // whatever the reason — and the reason is whatever the pipeline
                // last saw. Without this the only paths that reported anything
                // were a refused TCP connect and a channel that had already
                // opened, which left the whole handshake silent.
                connection.closeFuture.whenComplete { [weak self] _ in
                    guard let self = self, !self.reachedLive else { return }
                    self.fail(self.describe(errors.error ?? Failure.closedDuringHandshake))
                }
                self.openSession(on: connection)
            }
        }
    }

    /// Latched once the shell has been running, so a connection that closes
    /// can tell "the session ended" from "it never started". It cannot be read
    /// off `link`, which is back to `.idle` by the time a clean disconnect
    /// reaches the close future — that would report every normal logout as a
    /// handshake failure.
    private var reachedLive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _reachedLive
    }

    /// Drops the link, on the user's say-so. Through termd the session on
    /// the far side keeps running and the next connection re-attaches to it;
    /// on the plain-shell fallback the far side dies with the connection,
    /// which is the trade for needing nothing installed there.
    public func disconnect() {
        lock.lock()
        userStopped = true
        lock.unlock()
        disconnectKeepingState()
        setLink(.idle)
    }

    private func openSession(on connection: Channel) {
        let created = connection.eventLoop.makePromise(of: Channel.self)
        connection.pipeline.handler(type: NIOSSHHandler.self).whenComplete { result in
            switch result {
            case .failure(let error):
                created.fail(error)
            case .success(let ssh):
                ssh.createChannel(created) { [weak self] child, type in
                    guard let self = self, type == .session else {
                        return child.eventLoop.makeFailedFuture(
                            ChannelError.inappropriateOperationForState)
                    }
                    self.lock.lock()
                    let viaTermd = self.termdMode
                    self.lock.unlock()
                    if viaTermd {
                        // `sh -lc`: a LOGIN shell, because an ssh exec channel
                        // gets sshd's minimal PATH, and starling-termd lives
                        // in ~/.local/bin on any machine it was installed to
                        // without root — which .profile puts on PATH and
                        // nothing else does.
                        return child.pipeline.addHandler(TermdChannelHandler(
                            client: self.termdClient(),
                            command: "sh -lc 'exec starling-termd --stdio'",
                            onReady: { [weak self] in self?.termdReady(child) },
                            onClose: { [weak self] why in self?.termdClosed(why) }))
                    }
                    return child.pipeline.addHandler(SessionChannelHandler(
                        session: self.session,
                        onReady: { [weak self] in self?.ready(child) },
                        onClose: { [weak self] why in self?.closed(why) }))
                }
            }
        }
        created.futureResult.whenFailure { [weak self] error in
            guard let self = self else { return }
            self.fail(self.describe(error))
        }
    }

    // MARK: - The termd link

    /// The one client this object ever has: session id and byte offset live
    /// in it, so keeping it across reconnects IS the resume.
    private func termdClient() -> TermdClient {
        lock.lock()
        if let existing = termd {
            lock.unlock()
            return existing
        }
        var attach: UInt32?
        if let c = creds {
            let key = "starling.termd.session.\(c.user)@\(c.host):\(c.port)"
            let stored = UserDefaults.standard.integer(forKey: key)
            if stored > 0 { attach = UInt32(stored) }
        }
        // A fresh launch attaches from offset zero: the server replays from
        // the oldest byte its ring holds, which rebuilds screen and
        // scrollback both. Mid-run reconnects resume from the client's own
        // offset because the client object survives them.
        let client = TermdClient(session: session, attach: attach, from: 0)
        termd = client
        lock.unlock()
        return client
    }

    private func termdReady(_ child: Channel) {
        lock.lock()
        channel = child
        _reachedLive = true
        reconnectAttempt = 0
        lock.unlock()

        let client = termdClient()
        client.sendFrame = { [weak self] frame in self?.send(frame) }
        client.onLive = { [weak self] id in
            guard let self = self else { return }
            self.lock.lock()
            let key = self.sessionKey
            self.lock.unlock()
            if let key = key { UserDefaults.standard.set(Int(id), forKey: key) }
            self.setLink(.live)
        }
        client.onEnded = { [weak self] why in
            // A protocol-level refusal will not fix itself by retrying —
            // and the stored id describes a server state that no longer
            // exists, so drop that too.
            guard let self = self else { return }
            self.lock.lock()
            self.userStopped = true
            let key = self.sessionKey
            self.lock.unlock()
            if let key = key { UserDefaults.standard.removeObject(forKey: key) }
            self.disconnectKeepingState()
            self.setLink(why.map { .failed($0) } ?? .idle)
        }
        client.begin(cols: session.emulator.cols, rows: session.emulator.rows)

        // PING every 10s and declare the link dead after 30s of silence —
        // a half-open TCP connection otherwise looks healthy forever, which
        // on a phone is the COMMON case: iOS freezes the app mid-air when it
        // is backgrounded, and the far side's RSTs go nowhere.
        lock.lock()
        keepalive?.cancel()
        keepalive = child.eventLoop.scheduleRepeatedTask(
            initialDelay: .seconds(10), delay: .seconds(10)
        ) { [weak self, weak child] _ in
            guard let self = self, let client = self.currentTermd() else { return }
            if !client.keepalive() { child?.close(promise: nil) }
        }
        lock.unlock()
    }

    private func currentTermd() -> TermdClient? {
        lock.lock(); defer { lock.unlock() }
        return termd
    }

    /// The termd channel died. Three different stories end here, told apart
    /// by what the client saw and how the bridge exited.
    private func termdClosed(_ why: String?) {
        lock.lock()
        keepalive?.cancel()
        keepalive = nil
        channel = nil
        let stopped = userStopped
        let sawServer = termd?.sawServer ?? false
        let conn = connection
        lock.unlock()
        if stopped { return }

        // starling-termd is not on that machine: the login shell said 127,
        // or sshd refused the exec outright. Fall back to a plain shell on
        // the same connection — the app still works everywhere, it merely
        // loses what termd would have given it. Only these two signatures
        // fall back: a network drop mid-handshake must reconnect instead,
        // or a flaky link would silently downgrade the session.
        let absent = (why?.contains("exited with status 127") ?? false)
            || (why?.contains("exited with status 126") ?? false)
            || (why?.contains("exec refused") ?? false)
        if !sawServer && absent {
            lock.lock()
            termdMode = false
            termd = nil
            lock.unlock()
            note("\r\n\u{1B}[38;5;244m[starling-termd is not installed on this "
                 + "machine — plain shell; the session will not survive a "
                 + "disconnect]\u{1B}[0m\r\n")
            if let conn = conn, conn.isActive {
                openSession(on: conn)
            } else {
                fail(why ?? "connection lost")
            }
            return
        }

        // The link died; the session on the far side is fine. Rebuild the
        // link and re-attach at the byte offset the client already holds.
        note("\r\n\u{1B}[38;5;244m[link lost — reconnecting…]\u{1B}[0m\r\n")
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        lock.lock()
        reconnectAttempt += 1
        let attempt = reconnectAttempt
        let c = creds
        let conn = connection
        connection = nil
        lock.unlock()
        conn?.close(promise: nil)
        guard let creds = c else { return }

        let backoff = min(8.0, pow(2.0, Double(min(attempt, 3))) * 0.25)
        DispatchQueue.global().asyncAfter(deadline: .now() + backoff) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let stopped = self.userStopped
            self.lock.unlock()
            guard !stopped else { return }
            self.connect(host: creds.host, port: creds.port,
                         user: creds.user, password: creds.password)
        }
    }

    /// Close the wire without touching `termd` — the resume state.
    private func disconnectKeepingState() {
        lock.lock()
        let (channel, connection) = (self.channel, self.connection)
        self.channel = nil
        self.connection = nil
        keepalive?.cancel()
        keepalive = nil
        lock.unlock()
        channel?.close(promise: nil)
        connection?.close(promise: nil)
    }

    private func ready(_ child: Channel) {
        lock.lock()
        channel = child
        _reachedLive = true
        lock.unlock()

        // Keys go up the wire; the grid stays here. Set after the shell is
        // running rather than at init, so anything typed while connecting is
        // not silently swallowed by a channel that does not exist yet.
        session.onOutput = { [weak self] text in
            self?.send(Array(text.utf8))
        }
        session.onResize = { [weak self] cols, rows in
            guard let self = self, let channel = self.currentChannel else { return }
            channel.triggerUserOutboundEvent(
                SSHChannelRequestEvent.WindowChangeRequest(
                    terminalCharacterWidth: cols,
                    terminalRowHeight: rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0),
                promise: nil)
        }
        setLink(.live)
    }

    private var currentChannel: Channel? {
        lock.lock(); defer { lock.unlock() }
        return channel
    }

    private func send(_ bytes: [UInt8]) {
        guard let channel = currentChannel else { return }
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        let data = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        channel.writeAndFlush(data, promise: nil)
    }

    private func closed(_ why: String?) {
        lock.lock()
        channel = nil
        lock.unlock()
        note("\r\n\u{1B}[38;5;244m[" + (why ?? "connection closed") + "]\u{1B}[0m\r\n")
        setLink(why.map { .failed($0) } ?? .idle)
    }

    /// Reports a failure once. A dead handshake reaches this twice — the
    /// session-channel promise fails and the connection then closes — and the
    /// second report would print a second red line for one event.
    private func fail(_ message: String) {
        lock.lock()
        let alreadyFailed = _reported
        _reported = true
        lock.unlock()
        guard !alreadyFailed else { return }
        note("\r\n\u{1B}[31m[" + message + "]\u{1B}[0m\r\n")
        setLink(.failed(message))
    }

    /// NIO's errors are precise and unreadable. These are the three a person
    /// actually hits, said the way they would describe them.
    private func describe(_ error: Error) -> String {
        if case Failure.hostKeyChanged = error {
            return "the host key changed since the last connection — "
                 + "if the machine was rebuilt, forget it and reconnect"
        }
        if case Failure.closedDuringHandshake = error {
            return "the connection closed before the shell started — "
                 + "wrong password, or the server refused the session"
        }
        if let ssh = error as? NIOSSHError {
            let text = "\(ssh)"
            if text.contains("authentication") || text.contains("Auth") {
                return "authentication failed — check the username and password"
            }
            return "ssh error: \(text)"
        }
        if let io = error as? IOError, io.errnoCode == ECONNREFUSED {
            return "connection refused — is sshd running and the port right?"
        }
        return "\(error)"
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
}
#endif
