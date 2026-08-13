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

    /// Ends the session. Unlike the termd transport there is nothing left
    /// running on the far side to reattach to: an ssh shell dies with its
    /// connection, which is the trade for needing nothing installed there.
    public func disconnect() {
        lock.lock()
        let (channel, connection) = (self.channel, self.connection)
        self.channel = nil
        self.connection = nil
        lock.unlock()
        channel?.close(promise: nil)
        connection?.close(promise: nil)
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
