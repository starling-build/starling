// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import RdpServer

/// The RDP connection as the desktop's display (docs/plans/rdp-wsl.md).
///
/// The sibling of RdpService, and deliberately smaller: there is no capture
/// session to claim, no other service to exclude, and no frame pump to ride,
/// because in display mode a present *is* the frame — nothing is
/// eavesdropping on a scanout that does not exist.
///
/// Threads: `start` on main, `onActivated`/`onPointer` on the peer thread
/// (both hop to main), `submit` on the engine's raster thread, encode on a
/// queue of our own. The raster thread must never block on the network, so
/// it hands over a filled buffer and returns.
final class RdpDisplayService {

    /// Set by RdpDisplayMode: apply a client-negotiated size (metrics +
    /// layout + render target). Called on the main queue.
    var onSizeNegotiated: ((UInt32, UInt32) -> Void)?
    /// Pointer reports, on the main queue.
    var onPointer: ((Double, Double, Int64, Double, Double) -> Void)?
    /// Key events (RDP scancode, extended flag, down), on the main queue.
    var onKey: ((UInt32, Bool, Bool) -> Void)?
    /// Client lock-key state, on the main queue.
    var onKeySync: ((UInt32) -> Void)?
    /// Client left, on the main queue.
    var onClientGone: (() -> Void)?

    private var server: OpaquePointer?
    private let lock = NSLock()
    private var width: UInt32 = 0
    private var height: UInt32 = 0

    // Drop-oldest mailbox of exactly two buffers: the raster thread fills
    // one while the encoder drains the other. A third would only add
    // latency — a frame the client has not seen yet is already stale.
    private var free: [[UInt8]] = []
    private var pending: [UInt8]?
    private var encoding = false
    private let encodeQueue = DispatchQueue(label: "starling.rdp.display.encode")

    private var lastPushMs: Double = 0
    private let minIntervalMs: Double

    /// Asks the engine for one more frame; set by RdpDisplayMode once the
    /// engine exists. See the capped branch of wantsFrame for why.
    nonisolated(unsafe) var scheduleCatchUp: (() -> Void)?
    /// One catch-up in flight at a time (guarded by `lock`) — a burst of
    /// capped presents must coalesce into a single deferred frame, not queue
    /// one each.
    private var catchUpArmed = false

    init() {
        let env = ProcessInfo.processInfo.environment
        let fps = env["STARLING_RDP_FPS"].flatMap { Int($0) } ?? 30
        minIntervalMs = fps > 0 ? 1000.0 / Double(fps) : 0
    }

    /// Stand up the listener at the fallback size. The desktop runs whether
    /// or not anyone is connected — a client attaching merely renegotiates
    /// the size, exactly as plugging in a monitor would.
    func start(defaultWidth: UInt32, defaultHeight: UInt32) -> Bool {
        let env = ProcessInfo.processInfo.environment
        let port = Int32(env["STARLING_RDP_PORT"].flatMap { Int($0) } ?? 3389)
        guard let (cert, key) = RdpCertificate.resolve(env: env) else {
            warn("no certificate — cannot listen")
            return false
        }

        var cbs = RdpServerCallbacks(
            on_activated: { ud, w, h in
                guard let ud else { return -1 }
                Unmanaged<RdpDisplayService>.fromOpaque(ud)
                    .takeUnretainedValue().activated(width: w, height: h)
                return 0
            },
            on_disconnected: { ud in
                guard let ud else { return }
                Unmanaged<RdpDisplayService>.fromOpaque(ud)
                    .takeUnretainedValue().disconnected()
            },
            on_pointer: { ud, x, y, buttons, wdx, wdy in
                guard let ud else { return }
                Unmanaged<RdpDisplayService>.fromOpaque(ud)
                    .takeUnretainedValue()
                    .pointer(x: x, y: y, buttons: buttons, wdx: wdx, wdy: wdy)
            },
            on_key: { ud, scancode, extended, down in
                guard let ud else { return }
                Unmanaged<RdpDisplayService>.fromOpaque(ud)
                    .takeUnretainedValue()
                    .key(scancode: scancode, extended: extended != 0,
                         down: down != 0)
            },
            on_key_sync: { ud, flags in
                guard let ud else { return }
                Unmanaged<RdpDisplayService>.fromOpaque(ud)
                    .takeUnretainedValue().keySync(flags)
            })

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        // 1: the client's requested size wins — there is no panel to defer to.
        guard let s = rdp_server_start(nil, port, cert, key, defaultWidth,
                                       defaultHeight, 1, &cbs, selfPtr) else {
            warn("listener failed to start")
            return false
        }
        lock.lock()
        server = s
        width = defaultWidth
        height = defaultHeight
        lock.unlock()
        return true
    }

    func stop() {
        lock.lock()
        let s = server
        server = nil
        lock.unlock()
        if let s { rdp_server_stop(s) }
    }

    // MARK: Peer callbacks (peer thread → main)

    private func activated(width w: UInt32, height h: UInt32) {
        lock.lock()
        let changed = (w != width || h != height)
        width = w
        height = h
        free.removeAll()          // old buffers are the wrong size now
        pending = nil
        lock.unlock()
        warn("client connected at \(w)x\(h)\(changed ? " (resized)" : "")")
        let apply: () -> Void = { [weak self] in self?.onSizeNegotiated?(w, h) }
        DispatchQueue.main.async(
            execute: unsafeBitCast(apply, to: (@Sendable () -> Void).self))
    }

    private func disconnected() {
        lock.lock()
        pending = nil
        lock.unlock()
        let gone: () -> Void = { [weak self] in self?.onClientGone?() }
        DispatchQueue.main.async(
            execute: unsafeBitCast(gone, to: (@Sendable () -> Void).self))
    }

    private func key(scancode: UInt32, extended: Bool, down: Bool) {
        let deliver: () -> Void = { [weak self] in
            self?.onKey?(scancode, extended, down)
        }
        DispatchQueue.main.async(
            execute: unsafeBitCast(deliver, to: (@Sendable () -> Void).self))
    }

    private func keySync(_ flags: UInt32) {
        let deliver: () -> Void = { [weak self] in self?.onKeySync?(flags) }
        DispatchQueue.main.async(
            execute: unsafeBitCast(deliver, to: (@Sendable () -> Void).self))
    }

    private func pointer(x: Double, y: Double, buttons: Int64,
                         wdx: Double, wdy: Double) {
        let deliver: () -> Void = { [weak self] in
            self?.onPointer?(x, y, buttons, wdx, wdy)
        }
        DispatchQueue.main.async(
            execute: unsafeBitCast(deliver, to: (@Sendable () -> Void).self))
    }

    // MARK: Frames (engine raster thread)

    /// True when a frame is actually wanted: a client is attached and the
    /// rate cap has elapsed. Checked before the readback so a capped-out
    /// present skips the pixel work entirely rather than reading and
    /// discarding.
    func wantsFrame() -> Bool {
        lock.lock()
        let connected = server != nil && rdp_server_client_connected(server) != 0
        lock.unlock()
        guard connected else { return false }
        guard minIntervalMs > 0 else { return true }
        let now = Date().timeIntervalSince1970 * 1000
        if now - lastPushMs < minIntervalMs {
            // A frame the cap swallows must not be the last word on the
            // screen. Dropping it is fine mid-burst — another frame is
            // coming — but the LAST frame of a burst is the one that shows
            // the settled state, and nothing re-presents an idle desktop.
            // That is not hypothetical: maximising a window fires a burst
            // whose final frame (the child's re-rendered content) landed
            // inside this window and was discarded, so the client kept the
            // previous frame — the old content stretched to the new size —
            // until unrelated input forced a repaint. Ask the engine for one
            // more frame once the cap has elapsed; its present either pushes
            // (quiet again) or is capped by newer traffic and re-arms.
            armCatchUp(afterMs: minIntervalMs - (now - lastPushMs))
            return false
        }
        lastPushMs = now
        return true
    }

    private func armCatchUp(afterMs: Double) {
        lock.lock()
        if catchUpArmed || scheduleCatchUp == nil {
            lock.unlock()
            return
        }
        catchUpArmed = true
        lock.unlock()
        // +2ms so the rescheduled present lands clearly past the cap, not on
        // its edge. Main queue: it is serviced in this mode (present already
        // marshals the Wayland pacing there), and ScheduleFrame is
        // thread-safe. Same Sendable bitcast as `submit`'s delivery above —
        // this class is guarded by its own lock.
        let fire: () -> Void = { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.catchUpArmed = false
            let cb = self.scheduleCatchUp
            self.lock.unlock()
            cb?()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Int(afterMs) + 2),
            execute: unsafeBitCast(fire, to: (@Sendable () -> Void).self))
    }

    /// Borrow a buffer sized for the current frame; the caller fills it
    /// (glReadPixels) and hands it back through `submit`.
    func acquireBuffer() -> (buf: [UInt8], w: UInt32, h: UInt32)? {
        lock.lock()
        defer { lock.unlock() }
        guard width > 0, height > 0 else { return nil }
        let need = Int(width) * Int(height) * 4
        if var b = free.popLast() {
            if b.count != need { b = [UInt8](repeating: 0, count: need) }
            return (b, width, height)
        }
        return ([UInt8](repeating: 0, count: need), width, height)
    }

    /// Publish a filled buffer. Drop-oldest: an unsent frame is stale the
    /// moment a newer one exists.
    func submit(_ buf: [UInt8]) {
        lock.lock()
        if let old = pending { free.append(old) }
        pending = buf
        let kick = !encoding
        if kick { encoding = true }
        lock.unlock()
        guard kick else { return }
        let drain: () -> Void = { [weak self] in self?.drain() }
        encodeQueue.async(
            execute: unsafeBitCast(drain, to: (@Sendable () -> Void).self))
    }

    private func drain() {
        while true {
            lock.lock()
            guard let frame = pending else {
                encoding = false
                lock.unlock()
                return
            }
            pending = nil
            let s = server
            let w = width, h = height
            lock.unlock()

            if let s, frame.count == Int(w) * Int(h) * 4 {
                _ = frame.withUnsafeBufferPointer {
                    rdp_server_push_frame(s, $0.baseAddress, w, h)
                }
            }
            lock.lock()
            free.append(frame)
            lock.unlock()
        }
    }

    private func warn(_ msg: String) {
        FileHandle.standardError.write(Data("[RdpDisplay] \(msg)\n".utf8))
    }
}
#endif
