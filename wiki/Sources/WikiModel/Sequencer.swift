// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The server's side of one page's live session: the ordered log of ops
// since the page was opened for co-editing, and the one operation the
// server performs — take a client's batch, written against the revision
// it had seen, move it past everything since, append it, and hand back
// what everyone else must apply.

public struct PageSequencer: Sendable {
    /// The revision the log is at: the number of ops landed.
    public private(set) var revision: Int
    /// Every op landed, in order; index i is the op that took the log
    /// from revision `base + i` to `base + i + 1`.
    public private(set) var log: [PageOp] = []
    /// The revision the log starts at (older ops may have been persisted
    /// and dropped from memory).
    public let base: Int

    public init(revision: Int = 0) {
        self.revision = revision
        self.base = revision
    }

    public enum Failure: Error, Equatable {
        /// The client's revision is older than what the log remembers.
        case tooOld(clientRevision: Int, oldest: Int)
        /// The client's revision is ahead of the server's.
        case fromTheFuture(clientRevision: Int, revision: Int)
    }

    /// Land `ops`, which the client made at `clientRevision`. Returns the
    /// ops as transformed (what the server applied and what other clients
    /// must apply) and the new revision.
    @discardableResult
    public mutating func land(_ ops: [PageOp], clientRevision: Int) throws -> (ops: [PageOp], revision: Int) {
        guard clientRevision >= base else { throw Failure.tooOld(clientRevision: clientRevision, oldest: base) }
        guard clientRevision <= revision else { throw Failure.fromTheFuture(clientRevision: clientRevision, revision: revision) }
        let since = Array(log[(clientRevision - base)...])
        // The ops already landed win every tie: they came first.
        let moved = Transform.transform(ops, past: since, opsWin: false)
        log.append(contentsOf: moved)
        revision += moved.count
        return (moved, revision)
    }

    /// The ops landed after `clientRevision`, for a client catching up.
    public func ops(since clientRevision: Int) -> [PageOp]? {
        guard clientRevision >= base, clientRevision <= revision else { return nil }
        return Array(log[(clientRevision - base)...])
    }
}

/// A client's view: the ops it has sent and not yet seen come back, and
/// how an op arriving from the server is moved past them.
public struct PendingOps: Sendable {
    public private(set) var pending: [PageOp] = []
    public init() {}

    public mutating func sent(_ ops: [PageOp]) { pending += ops }

    /// The server confirmed `count` ops of ours (they come back first, in
    /// order, as the server transformed them).
    public mutating func acknowledged(_ count: Int) { pending.removeFirst(min(count, pending.count)) }

    /// A remote op arrived: move it past what we have in flight (our ops
    /// lose ties to it, since the server landed it first), and move our
    /// pending ops past it so they stay correct against the new base.
    public mutating func incoming(_ remote: PageOp) -> [PageOp] {
        var remotes = [remote]
        var newPending: [PageOp] = []
        for mine in pending {
            // mine' = mine past remote(s); remote' = remote past mine.
            let minePast = Transform.transform([mine], past: remotes, opsWin: false)
            var remotesPast: [PageOp] = []
            for r in remotes { remotesPast += Transform.transform(r, past: mine, opWins: true) }
            remotes = remotesPast
            newPending += minePast
        }
        pending = newPending
        return remotes
    }
}
