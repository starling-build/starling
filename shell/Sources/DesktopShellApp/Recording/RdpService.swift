// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import FlutterDRMBridge
import RdpServer

/// The desktop, over RDP. A client connects, sees the primary output, and
/// drives the pointer — the third consumer of the engine's single capture
/// session, alongside RecordingService and ScreenCastService, and modelled
/// closely on the latter.
///
/// Scope and security posture are both deliberately small; see
/// `docs/plans/rdp.md`. In particular there is no NLA, so anyone who can
/// reach the port owns the session: this is opt-in (`STARLING_RDP=1`) and
/// LAN/dev only.
///
/// Threads: `start`/`stop` on the main queue, `ingest` on the engine's
/// recorder writer thread, the RdpServer callbacks on the listener and
/// peer threads, `pumpTick` on the main queue. All state is behind one
/// lock, and frames leave through a depth-1 mailbox drained by a dedicated
/// encode queue — the capture callback itself only ever copies and returns.
final class RdpService {

    /// Frame routing for main.swift's trampoline: true from the moment an
    /// RDP peer claims the capture until its drain completes.
    nonisolated(unsafe) private(set) static var captureActive = false

    private enum State {
        case idle
        case starting   // engine capture requested, no frame yet
        case live       // frames flowing to the client
        case draining   // stop requested, waiting for the engine
    }

    private let lock = NSLock()
    private var state: State = .idle
    private var server: OpaquePointer?
    private var desktopW: UInt32 = 0
    private var desktopH: UInt32 = 0

    /// Depth-1 mailbox: the newest frame wins. A slow client blocks its own
    /// encode queue, never the capture thread — it simply sees the latest
    /// frame when it catches up.
    private let mailboxLock = NSLock()
    private var pendingFrame: [UInt8]?
    private var encodeQueued = false
    private let encodeQueue = DispatchQueue(label: "starling.rdp.encode")

    /// True while the frame-tick pump must run: presents carry the engine's
    /// start/stop requests and deliver the frames themselves.
    var needsFramePump: Bool {
        lock.lock(); defer { lock.unlock() }
        if case .idle = state { return false }
        return true
    }

    /// True while the capture pipeline is priming — same reason as
    /// ScreenCastService: the engine's PBO ring completes a readback a few
    /// presents after its blit, so at the pump's floor rate the client
    /// would stare at black for seconds after connecting.
    var needsPrimingRebuilds: Bool {
        lock.lock(); defer { lock.unlock() }
        if case .starting = state { return true }
        return false
    }

    // MARK: Listener lifecycle (main queue)

    /// The view to capture, remembered so the listener can be raised and
    /// dropped long after startup — Settings › Sharing toggles it at will.
    private var view: OpaquePointer?

    /// Fired on the main queue whenever the listener comes up or goes down.
    /// The Sharing switch is driven from this rather than from what the user
    /// clicked, so a failed start reports back as off.
    var onStatusChanged: (() -> Void)?

    /// The port the listener uses, running or not.
    private var port: Int32 {
        Int32(ProcessInfo.processInfo.environment["STARLING_RDP_PORT"]
                .flatMap { Int($0) } ?? 3389)
    }

    /// True while the listener is up.
    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return server != nil
    }

    /// Remember the view and raise the listener if `STARLING_RDP` says so.
    /// Called unconditionally at startup; the env var is the dev/session
    /// override, the Settings switch is the user-facing one.
    func startIfEnabled(view: OpaquePointer) {
        self.view = view
        let env = ProcessInfo.processInfo.environment
        guard let flag = env["STARLING_RDP"], flag == "1" || flag == "true"
        else { return }
        _ = start()
    }

    /// Raise the listener now. Returns false if it could not come up, which
    /// is what keeps the Sharing switch honest.
    @discardableResult
    func start() -> Bool {
        guard let view = view ?? drmViewHandle else {
            warn("no DRM view — remote desktop unavailable in this mode")
            return false
        }
        if isRunning { return true }
        let env = ProcessInfo.processInfo.environment
        let port = self.port
        guard let (cert, key) = RdpCertificate.resolve(env: env) else {
            warn("no certificate — RDP disabled")
            return false
        }

        // Advertise the primary output at its native size; capture runs at
        // shift 0 so client coordinates are engine pixels 1:1.
        let w = fl_drm_view_get_width(view)
        let h = fl_drm_view_get_height(view)

        var cbs = RdpServerCallbacks(
            on_activated: { ud, w, h in
                guard let ud else { return -1 }
                let svc = Unmanaged<RdpService>
                    .fromOpaque(ud).takeUnretainedValue()
                return svc.onActivated(width: w, height: h)
            },
            on_disconnected: { ud in
                guard let ud else { return }
                Unmanaged<RdpService>.fromOpaque(ud)
                    .takeUnretainedValue().onDisconnected()
            },
            on_pointer: { ud, x, y, buttons, wdx, wdy in
                guard let ud else { return }
                Unmanaged<RdpService>.fromOpaque(ud)
                    .takeUnretainedValue()
                    .onPointer(x: x, y: y, buttons: buttons,
                               wheelDX: wdx, wheelDY: wdy)
            },
            // Share mode mirrors a machine that has its own keyboard, and
            // the remote one would land on the same seat as the local user's
            // — deliberately not wired. Display mode is where RDP keys are
            // the only keys there are.
            on_key: nil,
            on_key_sync: nil)

        // Unretained: the service outlives the server, which is stopped
        // before it could ever be freed.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        // 0: share mode forces the client to the physical output's size —
        // the desktop is already being scanned out at it.
        guard let s = rdp_server_start(nil, port, cert, key, w, h, 0,
                                       &cbs, selfPtr) else {
            warn("listener failed to start")
            return false
        }
        lock.lock()
        server = s
        desktopW = w
        desktopH = h
        lock.unlock()
        notifyStatus()
        return true
    }

    func stop() {
        lock.lock()
        let s = server
        server = nil
        lock.unlock()
        if let s { rdp_server_stop(s) }
        notifyStatus()
    }

    /// Hand the current state to whoever is showing it. Callable from any
    /// thread — the peer callbacks run on their own.
    func notifyStatus() {
        guard let cb = onStatusChanged else { return }
        let send = unsafeBitCast(cb, to: (@Sendable () -> Void).self)
        DispatchQueue.main.async { send() }
    }

    // MARK: Peer callbacks (RdpServer threads)

    /// A client finished capability exchange. Claim the engine's capture,
    /// or refuse if another service already owns it.
    private func onActivated(width: UInt32, height: UInt32) -> Int32 {
        guard let view = drmViewHandle else { return -1 }
        guard fl_drm_view_recording_active() == 0,
              !ScreenCastService.captureActive else {
            warn("capture busy (recording or screen share) — refusing client")
            return -1
        }
        lock.lock()
        // Already ours: a re-activation the shim did not filter. Claiming
        // twice would have us refuse our own client.
        switch state {
        case .starting, .live: lock.unlock(); return 0
        case .draining: lock.unlock(); return -1
        case .idle: break
        }
        state = .starting
        Self.captureActive = true
        lock.unlock()

        // Shift 0: full resolution, so the client's framebuffer pixels are
        // the engine's physical pixels and pointer injection needs no
        // scaling. If 4K encode turns out too slow for one thread, this is
        // the knob (and injected coordinates scale by the same factor).
        fl_drm_view_recording_set_dmabuf(0)
        fl_drm_view_recording_set_max_fps(Self.maxFps)
        fl_drm_view_recording_start(view, 0)
        return 0
    }

    private func onDisconnected() {
        lock.lock()
        switch state {
        case .idle, .draining:
            lock.unlock()
        case .starting, .live:
            state = .draining
            lock.unlock()
            fl_drm_view_recording_stop(drmViewHandle)
        }
    }

    /// Pointer report from the client, in desktop physical pixels. Straight
    /// through to the engine, which marshals to its platform thread and
    /// moves the hardware cursor to match.
    private func onPointer(x: Double, y: Double, buttons: Int64,
                           wheelDX: Double, wheelDY: Double) {
        guard let view = drmViewHandle else { return }
        fl_drm_view_inject_pointer_abs(view, x, y, buttons, wheelDX, wheelDY)
    }

    // MARK: Frames (engine recorder writer thread)

    /// One top-down RGBA frame. Copy into the mailbox and get out — the
    /// encode runs on our own queue.
    func ingest(_ rgba: UnsafePointer<UInt8>?, width: Int, height: Int) {
        guard let rgba, width > 0, height > 0 else { return }
        lock.lock()
        switch state {
        case .starting:
            state = .live
            lock.unlock()
        case .live:
            lock.unlock()
        case .idle, .draining:
            lock.unlock()
            return
        }

        let count = width * height * 4
        let copy = [UInt8](UnsafeBufferPointer(start: rgba, count: count))

        mailboxLock.lock()
        pendingFrame = copy          // newest wins; an unsent frame is stale
        let needsDrain = !encodeQueued
        encodeQueued = true
        mailboxLock.unlock()

        guard needsDrain else { return }
        let drain: () -> Void = { [weak self] in self?.drainMailbox() }
        encodeQueue.async(
            execute: unsafeBitCast(drain, to: (@Sendable () -> Void).self))
    }

    /// Encode queue: send whatever is newest, then check whether more
    /// arrived while we were busy.
    private func drainMailbox() {
        while true {
            mailboxLock.lock()
            guard let frame = pendingFrame else {
                encodeQueued = false
                mailboxLock.unlock()
                return
            }
            pendingFrame = nil
            mailboxLock.unlock()

            lock.lock()
            let s = server
            let w = desktopW, h = desktopH
            lock.unlock()
            guard let s else { return }
            _ = frame.withUnsafeBufferPointer {
                rdp_server_push_frame(s, $0.baseAddress, w, h)
            }
        }
    }

    // MARK: Pump (main queue, every tick while needsFramePump)

    /// Once the engine confirms the stop drained, release the capture so
    /// recording or screen share can claim it again.
    func pumpTick() {
        lock.lock()
        guard case .draining = state,
              fl_drm_view_recording_active() == 0 else {
            lock.unlock()
            return
        }
        state = .idle
        Self.captureActive = false
        lock.unlock()
        mailboxLock.lock()
        pendingFrame = nil
        mailboxLock.unlock()
    }

    // MARK: Configuration

    /// Capture cap. Full-surface RemoteFX at panel resolution is the cost
    /// driver, so the default is well under the display's rate; presents
    /// inside the interval skip capture entirely in the engine.
    private static var maxFps: Int32 {
        let env = ProcessInfo.processInfo.environment
        return Int32(env["STARLING_RDP_FPS"].flatMap { Int($0) } ?? 15)
    }

    private func warn(_ msg: String) {
        FileHandle.standardError.write(Data("[Rdp] \(msg)\n".utf8))
    }
}
#endif
