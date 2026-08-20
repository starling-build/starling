// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// A termd transport over the ssh connection this process already holds — the
// iOS half of `TermdTransport` (sdk/Sources/Flutter/Terminal/TermdLink.swift).
//
// The desktops reach a daemon by forking `ssh host starling-termd --stdio` and
// reading the child's pipe. iOS cannot fork, so its ssh is NIOSSH in this
// process and the "pipe" is another channel on the connection the terminal is
// already using. One connection, two channels: the session's, and this one,
// which carries WS_* frames and no session at all.
//
// The awkward seam is threading, and it is worth naming because getting it
// wrong deadlocks rather than fails. `RemoteWorkspace` is a blocking read loop
// on its own thread — `read` waits up to a timeout and returns 0 so the caller
// can tick its ACK and heartbeat. NIO is the opposite: bytes arrive on an
// event loop that must never block. So this type is the queue between them.
// The event loop only ever appends and signals; the workspace thread only ever
// drains and waits. Nothing in `deliver`/`finish` can block, which is what
// keeps the event loop safe to call them from.
//
// Why not restructure RemoteWorkspace the way TermdClient was — protocol on
// one side, transport on the other, fed by `receive(_:)`? Because that would
// be a SECOND copy of the workspace's reconnect, debounce and re-add logic,
// and this file exists to avoid exactly that. The queue costs one thread that
// is asleep almost always; a second protocol implementation costs every bug
// twice.

#if os(iOS)
import Flutter
import Foundation
import NIOCore
import NIOSSH

/// The bytes half: a queue an event loop fills and a blocking reader drains.
///
/// `read` honours the timeout contract `TermdTransport` documents — a positive
/// count, `0` when nothing arrived in time, `-1` at end of stream — and drains
/// what is already queued before ever reporting the end, so a frame that
/// landed in the same instant the channel closed is not lost.
final class TermdSSHTransport: TermdTransport {
    private let cond = NSCondition()
    private var inbox: [UInt8] = []
    private var ended = false
    private var channel: Channel?
    private var accepted = false

    /// Set once, from the dial, before the transport is handed out.
    func bind(_ channel: Channel) {
        cond.lock()
        self.channel = channel
        cond.unlock()
    }

    /// Whether the far side accepted the exec. Lives here rather than in a
    /// captured local because the dial's completion runs on the event loop,
    /// and a `var` captured across that boundary is not sendable.
    func markAccepted(_ ok: Bool) {
        cond.lock()
        accepted = ok
        cond.unlock()
    }

    var wasAccepted: Bool {
        cond.lock()
        defer { cond.unlock() }
        return accepted
    }

    // MARK: Called from the NIO event loop — must never block

    func deliver(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        cond.lock()
        inbox.append(contentsOf: bytes)
        cond.signal()
        cond.unlock()
    }

    func finish() {
        cond.lock()
        ended = true
        cond.broadcast()
        cond.unlock()
    }

    // MARK: TermdTransport — called from the workspace's own thread

    func read(into buf: inout [UInt8], timeoutMs: Int32) -> Int {
        cond.lock()
        defer { cond.unlock() }
        if inbox.isEmpty && !ended {
            // A spurious wakeup just means an early 0, which the caller
            // already treats as "nothing yet" — so no re-wait loop is needed.
            _ = cond.wait(until: Date().addingTimeInterval(
                Double(timeoutMs) / 1000.0))
        }
        if !inbox.isEmpty {
            let n = min(buf.count, inbox.count)
            for i in 0..<n { buf[i] = inbox[i] }
            inbox.removeFirst(n)
            return n
        }
        return ended ? -1 : 0
    }

    func write(_ frame: [UInt8]) {
        cond.lock()
        let ch = channel
        cond.unlock()
        guard let ch = ch else { return }
        // Hop to the event loop rather than writing from the workspace thread:
        // a Channel is only safe to touch there.
        ch.eventLoop.execute {
            var out = ch.allocator.buffer(capacity: frame.count)
            out.writeBytes(frame)
            ch.writeAndFlush(SSHChannelData(type: .channel,
                                            data: .byteBuffer(out)),
                             promise: nil)
        }
    }

    func close() {
        cond.lock()
        let ch = channel
        channel = nil
        cond.unlock()
        ch?.close(promise: nil)
        // Unblock a reader that is mid-wait, or the workspace's thread sits
        // in `read` until its timeout for no reason.
        finish()
    }
}

/// Pumps one ssh exec channel into a `TermdSSHTransport`.
///
/// stderr is dropped rather than shown: unlike the session channel there is no
/// screen for it to land on, and the failure it would report — no daemon on
/// the far side — is already visible as the workspace never coming up.
final class TermdWorkspaceChannelHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let transport: TermdSSHTransport
    private let command: String
    private let onReady: (Bool) -> Void
    /// Guards against reporting readiness twice — exec can fail after success.
    private var reported = false

    init(transport: TermdSSHTransport, command: String,
         onReady: @escaping (Bool) -> Void) {
        self.transport = transport
        self.command = command
        self.onReady = onReady
    }

    private func report(_ ok: Bool) {
        guard !reported else { return }
        reported = true
        onReady(ok)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let exec = SSHChannelRequestEvent.ExecRequest(
            command: command, wantReply: true)
        context.triggerUserOutboundEvent(exec).whenComplete { [weak self] result in
            switch result {
            case .failure: self?.report(false)
            case .success: self?.report(true)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = self.unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        // Only the daemon's own stream is protocol; stderr is the far side's
        // shell complaining, and feeding it to the framer would desynchronise
        // every frame after it.
        guard case .channel = channelData.type else { return }
        transport.deliver(Array(buffer.readableBytesView))
    }

    func channelInactive(context: ChannelHandlerContext) {
        report(false)
        transport.finish()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        report(false)
        transport.finish()
        context.close(promise: nil)
    }
}
#endif
