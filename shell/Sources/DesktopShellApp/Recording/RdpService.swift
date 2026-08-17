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

    /// Stand up the listener if `STARLING_RDP` is set. Returns silently
    /// when the feature is off — this is called unconditionally at startup.
    func startIfEnabled(view: OpaquePointer) {
        let env = ProcessInfo.processInfo.environment
        guard let flag = env["STARLING_RDP"], flag == "1" || flag == "true"
        else { return }

        let port = Int32(env["STARLING_RDP_PORT"].flatMap { Int($0) } ?? 3389)
        guard let (cert, key) = resolveCertificate(env: env) else {
            warn("no certificate — RDP disabled")
            return
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
            })

        // Unretained: the service outlives the server, which is stopped
        // before it could ever be freed.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let s = rdp_server_start(nil, port, cert, key, w, h,
                                       &cbs, selfPtr) else {
            warn("listener failed to start")
            return
        }
        lock.lock()
        server = s
        desktopW = w
        desktopH = h
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let s = server
        server = nil
        lock.unlock()
        if let s { rdp_server_stop(s) }
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

    /// Resolve the TLS material, generating a self-signed pair on first
    /// use. Returns nil when neither a configured nor a generated pair is
    /// available — the listener then stays down rather than falling back to
    /// an unencrypted mode, which this server does not have.
    private func resolveCertificate(env: [String: String])
        -> (cert: String, key: String)? {
        if let c = env["STARLING_RDP_CERT"], let k = env["STARLING_RDP_KEY"],
           !c.isEmpty, !k.isEmpty {
            return (c, k)
        }
        let dir = "\(LoginUser.configDir)/rdp"
        let cert = "\(dir)/server.crt"
        let key = "\(dir)/server.key"
        let fm = FileManager.default
        if fm.fileExists(atPath: cert), fm.fileExists(atPath: key) {
            return (cert, key)
        }

        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            warn("cannot create \(dir): \(error)")
            return nil
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes",
                       "-days", "3650", "-subj", "/CN=starling",
                       "-keyout", key, "-out", cert]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            warn("openssl failed: \(error)")
            return nil
        }
        guard p.terminationStatus == 0 else {
            warn("openssl exited \(p.terminationStatus)")
            return nil
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key)
        // Dev mode runs the shell as root; the packaged session does not.
        // Without this the generated pair is unreadable to the very session
        // that ships, and the failure looks like "RDP works on my box".
        if getuid() == 0 {
            let uid = LoginUser.uid
            let gid = getpwuid(uid)?.pointee.pw_gid ?? uid
            for path in [dir, cert, key] {
                try? fm.setAttributes([.ownerAccountID: uid,
                                       .groupOwnerAccountID: gid],
                                      ofItemAtPath: path)
            }
        }
        warn("generated self-signed certificate in \(dir)")
        return (cert, key)
    }

    private func warn(_ msg: String) {
        FileHandle.standardError.write(Data("[Rdp] \(msg)\n".utf8))
    }
}
#endif
