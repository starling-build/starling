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

    init(host: String, port: Int) {
        self.key = "starling.ssh.hostkey.\(host):\(port)"
    }

    static func forget(host: String, port: Int) {
        UserDefaults.standard.removeObject(
            forKey: "starling.ssh.hostkey.\(host):\(port)")
    }

    func validateHostKey(hostKey: NIOSSHPublicKey,
                         validationCompletePromise: EventLoopPromise<Void>) {
        // The key's own hash, not a transcription of it: NIOSSHPublicKey is
        // Hashable over its backing key, and a stable string of that is all a
        // comparison needs. It is not the OpenSSH fingerprint format and does
        // not try to be — nothing here shows it to a user or compares it with
        // what `ssh-keygen -lf` prints.
        var hasher = Hasher()
        hostKey.hash(into: &hasher)
        let fingerprint = String(hasher.finalize(), radix: 16)

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
        setLink(.connecting)
        note("\u{1B}[38;5;244mconnecting to \(user)@\(host):\(port)…\u{1B}[0m\r\n")

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
                self.openSession(on: connection)
            }
        }
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

    private func fail(_ message: String) {
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
