// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import Glibc
import GuestDisplay

/// The host end of the guest helper's channel — M2, Phase 1
/// (`docs/plans/guest-seamless.md`).
///
/// A virtio-serial channel (`org.starling.agent.0`) that libvirt exposes as a
/// unix socket, carrying one JSON object per line in each direction. The
/// vocabulary is deliberately `AgentBroker`'s — `{"op":…,"id":…}` answered by
/// `{"id":…,"ok":…}`, plus unsolicited `{"event":…}` — so M3 can proxy broker
/// ops through it without a translation layer.
///
/// Two things about this socket are not obvious and both are load-bearing:
///
/// - **Its path carries the domain's RUNTIME id** and changes every boot, so
///   it is asked for through libvirt rather than composed.
/// - **It exists whether or not anything in the guest has opened its end.**
///   `connect(2)` succeeding means libvirt is there, not that a helper is.
///   Only a reply to `hello` says that, which is why `isReady` is set from the
///   reply and not from the connection.
///
/// Threading: one reader thread owns the socket. Callers may send from any
/// thread; replies and events are delivered on the main queue.
final class GuestBridge: @unchecked Sendable {

    /// The channel a Starling helper answers on. Matches the domain XML's
    /// `<target type='virtio' name='…'/>`.
    static let channelName = "org.starling.agent.0"

    let domain: String

    /// Raised on the main thread once the helper has answered `hello`.
    var onReady: ((_ helperVersion: String) -> Void)?
    /// Unsolicited `{"event":…}` lines, on the main thread.
    var onEvent: (([String: Any]) -> Void)?
    /// The channel went away — the guest closed its end, or the VM stopped.
    var onClosed: (() -> Void)?

    private var fd: Int32 = -1
    private var thread: pthread_t?
    private var running = false
    private let lock = NSLock()
    private var nextId = 0
    private var pending: [Int: ([String: Any]) -> Void] = [:]
    private(set) var isReady = false

    init(domain: String) {
        self.domain = domain
    }

    // MARK: - Lifecycle

    /// Resolve the socket and connect. Returns false when the domain has no
    /// such channel — which is the ordinary state for a domain that was
    /// created before seamless mode existed, not an error.
    @discardableResult
    func open() -> Bool {
        guard fd < 0 else { return true }
        var buf = [CChar](repeating: 0, count: 4096)
        let rc = domain.withCString { d in
            GuestBridge.channelName.withCString { c in
                guest_display_channel_path(d, c, &buf, buf.count)
            }
        }
        guard rc == 0 else {
            FileHandle.standardError.write(Data(
                "[bridge] \(domain) has no \(GuestBridge.channelName) channel — add one to the domain (docs/plans/guest-seamless.md)\n".utf8))
            return false
        }
        let path = String(cString: buf)

        let s = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard s >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard path.utf8.count <= maxLen else {
            Glibc.close(s)
            FileHandle.standardError.write(Data(
                "[bridge] socket path too long: \(path)\n".utf8))
            return false
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { p in
            path.withCString { src in
                strncpy(UnsafeMutableRawPointer(p).assumingMemoryBound(to: CChar.self),
                        src, maxLen)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Glibc.connect(s, sa, size) == 0
            }
        }
        guard ok else {
            // The socket is there but nothing accepted: libvirt owns it and
            // the guest side is closed. Not fatal — the helper may start later.
            Glibc.close(s)
            return false
        }

        fd = s
        running = true
        var t = pthread_t()
        let box = Unmanaged.passRetained(self).toOpaque()
        if pthread_create(&t, nil, { arg in
            let me = Unmanaged<GuestBridge>.fromOpaque(arg!).takeRetainedValue()
            me.readLoop()
            return nil
        }, box) == 0 {
            thread = t
        } else {
            Unmanaged<GuestBridge>.fromOpaque(box).release()
            Glibc.close(fd)
            fd = -1
            return false
        }

        // The helper announces itself; until it answers, this is just a pipe.
        send(op: "hello", args: ["client": "starling-shell"]) { [weak self] reply in
            guard let self, reply["ok"] as? Bool == true else { return }
            self.isReady = true
            self.onReady?(reply["helper"] as? String ?? "?")
        }
        return true
    }

    func close() {
        running = false
        lock.lock()
        let s = fd
        fd = -1
        pending.removeAll()
        lock.unlock()
        if s >= 0 { shutdown(s, Int32(SHUT_RDWR)); Glibc.close(s) }
        if let t = thread { pthread_join(t, nil); thread = nil }
        isReady = false
    }

    // MARK: - Sending

    /// Any thread. `reply` runs on the main queue; it is never called twice,
    /// and never at all if the channel closes first — a caller that must not
    /// leak on that path should hold no unbounded state.
    func send(op: String, args: [String: Any] = [:],
              reply: (([String: Any]) -> Void)? = nil) {
        lock.lock()
        guard fd >= 0 else { lock.unlock(); return }
        nextId += 1
        let id = nextId
        if let reply { pending[id] = reply }
        var obj = args
        obj["op"] = op
        obj["id"] = id
        let s = fd
        lock.unlock()

        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        _ = line.withCString { p in
            // One write per line, and a partial write is a closed channel
            // rather than something to loop on: these are a few hundred bytes
            // into a socket with a kernel buffer.
            Glibc.write(s, p, strlen(p))
        }
    }

    // MARK: - Reading

    private func readLoop() {
        var buf = [UInt8](repeating: 0, count: 16384)
        var acc = Data()
        while running {
            let n = Glibc.read(fd, &buf, buf.count)
            if n <= 0 { break }
            acc.append(contentsOf: buf[0..<n])
            // Lines, because the protocol is lines. A helper that writes a
            // partial object then stalls leaves it buffered, which is correct.
            while let nl = acc.firstIndex(of: 0x0A) {
                let line = acc[acc.startIndex..<nl]
                acc = acc[acc.index(after: nl)...]
                guard !line.isEmpty,
                      let obj = try? JSONSerialization.jsonObject(with: Data(line))
                          as? [String: Any] else { continue }
                deliver(obj)
            }
            if acc.count > 1 << 20 {
                FileHandle.standardError.write(Data(
                    "[bridge] a megabyte with no newline — dropping the buffer\n".utf8))
                acc.removeAll(keepingCapacity: false)
            }
        }
        let hop: () -> Void = { [weak self] in
            guard let self else { return }
            self.isReady = false
            self.onClosed?()
        }
        DispatchQueue.main.async(
            execute: unsafeBitCast(hop, to: (@Sendable () -> Void).self))
    }

    private func deliver(_ obj: [String: Any]) {
        if let id = obj["id"] as? Int {
            lock.lock()
            let cb = pending.removeValue(forKey: id)
            lock.unlock()
            guard let cb else { return }
            let hop: () -> Void = { cb(obj) }
            DispatchQueue.main.async(
                execute: unsafeBitCast(hop, to: (@Sendable () -> Void).self))
            return
        }
        guard obj["event"] is String else { return }
        let hop: () -> Void = { [weak self] in self?.onEvent?(obj) }
        DispatchQueue.main.async(
            execute: unsafeBitCast(hop, to: (@Sendable () -> Void).self))
    }
}
#endif
