// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// What is on a machine — the read half of the protocol, with no session and
// no workspace attached to it.
//
// Milestone 5 of docs/plans/remote-workspace.md: an arrangement that survives
// is worth nothing if the only way back to it is remembering its name. The
// daemon has always been able to answer this (LIST since v0, WS_LIST since
// workspaces); nothing on the Swift side ever asked.
//
// One shot, deliberately. This spawns a connection, asks its two questions,
// and drops it — a picker wants a snapshot, not a subscription, and the cost
// of being wrong for a few seconds is a stale row rather than a lost pane.
// Anything that needs to STAY current holds a RemoteWorkspace instead.


import Foundation

public enum TermdDirectory {

    public struct Workspace: Sendable, Equatable {
        public let id: UInt32
        public let name: String
        /// The sessions joined to it. A workspace can hold sessions that its
        /// layout no longer mentions — closing a pane detaches rather than
        /// ending anything — so this is a superset of what a client will draw.
        public let sessions: [UInt32]
        /// Whether an arrangement has ever been stored. False means "this is a
        /// name someone made and nothing more".
        public let hasLayout: Bool
    }

    public struct Session: Sendable, Equatable {
        public let id: UInt32
        public let name: String
        public let cols: Int
        public let rows: Int
        public let alive: Bool
        /// Bytes the session has ever produced — the cheapest proxy for "has
        /// anything happened here".
        public let produced: UInt64
    }

    public struct Listing: Sendable, Equatable {
        public let workspaces: [Workspace]
        public let sessions: [Session]

        /// Sessions belonging to no workspace: what someone started with the
        /// plain `starling-termd <name>` on the far machine, or what is left
        /// over from a workspace that stopped mentioning them.
        public var loose: [Session] {
            let claimed = Set(workspaces.flatMap { $0.sessions })
            return sessions.filter { !claimed.contains($0.id) }
        }
    }

    /// Ask a host what it has. `completion` runs on an internal thread, with
    /// nil when the far side could not be reached or did not answer in time —
    /// which for a picker means "show nothing", not "there is nothing".
    /// `dial` is how the host is reached; the desktops leave it nil and get
    /// the ssh child, iOS passes a channel on its existing connection.
    public static func list(host: String,
                            sshPath: String? = nil,
                            serverPath: String? = nil,
                            timeout: TimeInterval = 8,
                            dial: TermdDialer? = nil,
                            completion: @escaping @Sendable (Listing?) -> Void) {
        #if os(Linux) || os(macOS) || os(Windows)
        let paths = TermdPaths(ssh: sshPath, server: serverPath)
        let dialer = dial ?? termdChildDialer(sshPath: paths.ssh,
                                              serverPath: paths.server)
        #else
        guard let dialer = dial else {
            completion(nil)
            return
        }
        #endif
        Thread {
            guard let link = dialer(host) else {
                completion(nil)
                return
            }
            defer { link.close() }

            var hello = TermdWire.u16(UInt16(TermdWire.version))
            hello.append(contentsOf: Array("starling".utf8))
            link.write(TermdWire.frame(.hello, hello))
            link.write(TermdWire.frame(.wsList, []))
            link.write(TermdWire.frame(.list, []))

            var acc = [UInt8]()
            var buf = [UInt8](repeating: 0, count: 65536)
            var workspaces: [Workspace]?
            var sessions: [Session]?
            let deadline = Date().addingTimeInterval(timeout)

            while workspaces == nil || sessions == nil {
                if Date() >= deadline { completion(nil); return }
                let n = link.read(into: &buf, timeoutMs: 200)
                if n < 0 { completion(nil); return }
                if n > 0 { acc.append(contentsOf: buf[0..<n]) }

                while acc.count >= 8 {
                    let type = acc[0]
                    let len = Int(TermdWire.readU32(acc, 4))
                    guard len <= 1 << 21 else { completion(nil); return }
                    guard acc.count - 8 >= len else { break }
                    let body = Array(acc[8..<(8 + len)])
                    acc.removeFirst(8 + len)

                    switch type {
                    case TermdFrame.wsListReply.rawValue:
                        workspaces = decodeWorkspaces(body) ?? []
                    case TermdFrame.listReply.rawValue:
                        sessions = decodeSessions(body) ?? []
                    case TermdFrame.error.rawValue:
                        // An older daemon answers ERROR to WS_LIST and knows
                        // nothing of workspaces. Its sessions are still worth
                        // reporting, so this is an empty answer, not a failure.
                        if workspaces == nil { workspaces = [] } else { sessions = [] }
                    default:
                        break
                    }
                }
            }
            completion(Listing(workspaces: workspaces ?? [], sessions: sessions ?? []))
        }.start()
    }

    // MARK: - The two replies

    /// count u16, then count × { ws_id u32, blob_len u32, nsessions u16,
    /// sessions[nsessions] u32, name_len u16, name }
    static func decodeWorkspaces(_ b: [UInt8]) -> [Workspace]? {
        guard b.count >= 2 else { return nil }
        let count = Int(TermdWire.readU16(b, 0))
        var off = 2
        var out: [Workspace] = []
        for _ in 0..<count {
            guard off + 10 <= b.count else { return out }
            let id = TermdWire.readU32(b, off)
            let blobLen = TermdWire.readU32(b, off + 4)
            let n = Int(TermdWire.readU16(b, off + 8))
            off += 10
            guard off + n * 4 + 2 <= b.count else { return out }
            var sessions: [UInt32] = []
            for i in 0..<n { sessions.append(TermdWire.readU32(b, off + i * 4)) }
            off += n * 4
            let nameLen = Int(TermdWire.readU16(b, off))
            off += 2
            guard off + nameLen <= b.count else { return out }
            let name = String(decoding: b[off..<(off + nameLen)], as: UTF8.self)
            off += nameLen
            out.append(Workspace(id: id, name: name, sessions: sessions,
                                 hasLayout: blobLen > 0))
        }
        return out
    }

    /// count u16, then count × { id u32, cols u16, rows u16, alive u8,
    /// seq u64, name_len u16, name[name_len] }
    static func decodeSessions(_ b: [UInt8]) -> [Session]? {
        guard b.count >= 2 else { return nil }
        let count = Int(TermdWire.readU16(b, 0))
        var off = 2
        var out: [Session] = []
        for _ in 0..<count {
            guard off + 19 <= b.count else { return out }
            let id = TermdWire.readU32(b, off)
            let cols = Int(TermdWire.readU16(b, off + 4))
            let rows = Int(TermdWire.readU16(b, off + 6))
            let alive = b[off + 8] != 0
            let produced = TermdWire.readU64(b, off + 9)
            let nameLen = Int(TermdWire.readU16(b, off + 17))
            off += 19
            guard off + nameLen <= b.count else { return out }
            let name = String(decoding: b[off..<(off + nameLen)], as: UTF8.self)
            off += nameLen
            out.append(Session(id: id, name: name, cols: cols, rows: rows,
                               alive: alive, produced: produced))
        }
        return out
    }
}

