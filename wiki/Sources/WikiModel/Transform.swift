// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Server-ordered operational transform over `PageOp` (docs/plans/wiki.md,
// "Collaboration", step 3). The server is the sequencer: ops arrive with
// the revision their author had seen; each is transformed past every op
// that landed since, then appended and given the next revision. Clients
// do the mirror image for the ops they have sent and not yet had back.
//
// Only positions move. A payload (styles, paragraphs, runs) is the
// author's intent and goes through unchanged, so a transformed op is the
// same edit at the place that edit's target now sits.

public enum Transform {
    /// `op`, moved past `other`, which landed first. `opWins` breaks ties at
    /// equal positions (the server gives it to the op that landed first,
    /// i.e. `other`, so `opWins` is false there and true on the client's
    /// side for its own pending ops). Empty when `other` removed what `op`
    /// edited.
    public static func transform(_ op: PageOp, past other: PageOp, opWins: Bool) -> [PageOp] {
        switch other {
        case .setDocument, .setParagraph:
            return [op]
        case .insertText(let bp, let bo, let text, _):
            return shiftOffsets(op, para: bp, from: bo, by: text.utf16.count, opWins: opWins)
        case .deleteText(let bp, let bo, let bl, _):
            return deleteOffsets(op, para: bp, from: bo, length: bl)
        case .splitParagraph(let bp, let bo, _):
            return split(op, para: bp, at: bo, opWins: opWins)
        case .mergeParagraph(let bp, let head, _):
            return [merge(op, para: bp, headLength: head)]
        case .insertParagraphs(let at, let n, _):
            return [shiftParagraphs(op, from: at, by: n, opWins: opWins)]
        case .removeParagraphs(let at, let n, _):
            return removeParagraphs(op, from: at, count: n)
        }
    }

    /// `ops` (one client's batch, in order) moved past `landed` (the
    /// server's ops since the client's revision, in order).
    public static func transform(_ ops: [PageOp], past landed: [PageOp], opsWin: Bool) -> [PageOp] {
        var out = ops
        for b in landed {
            var next: [PageOp] = []
            for a in out { next += transform(a, past: b, opWins: opsWin) }
            out = next
        }
        return out
    }

    // MARK: - Position arithmetic

    /// Rebuild `op` with a new paragraph and offset.
    static func moved(_ op: PageOp, para: Int, offset: Int) -> PageOp {
        switch op {
        case .insertText(_, _, let t, let r): return .insertText(para: para, offset: offset, text: t, runs: r)
        case .deleteText(_, _, let l, let r): return .deleteText(para: para, offset: offset, length: l, removed: r)
        case .splitParagraph(_, _, let s): return .splitParagraph(para: para, offset: offset, tailStyle: s)
        case .mergeParagraph(_, let h, let s): return .mergeParagraph(para: para, headLength: h, removedStyle: s)
        case .insertParagraphs(_, let n, let p): return .insertParagraphs(at: para, count: n, paragraphs: p)
        case .removeParagraphs(_, let n, let p): return .removeParagraphs(at: para, count: n, paragraphs: p)
        case .setParagraph(_, let w, let p): return .setParagraph(para: para, what: w, payload: p)
        case .setDocument: return op
        }
    }

    static func withParagraph(_ op: PageOp, _ f: (Int) -> Int) -> PageOp {
        guard let p = op.para else { return op }
        return moved(op, para: f(p), offset: offsetOf(op) ?? 0)
    }

    static func offsetOf(_ op: PageOp) -> Int? {
        switch op {
        case .insertText(_, let o, _, _), .deleteText(_, let o, _, _), .splitParagraph(_, let o, _): return o
        default: return nil
        }
    }

    /// Text of `length` went in at (para, from).
    static func shiftOffsets(_ op: PageOp, para: Int, from: Int, by length: Int, opWins: Bool) -> [PageOp] {
        guard op.para == para, let o = offsetOf(op) else { return [op] }
        switch op {
        case .deleteText(_, _, let l, let r):
            // A deletion spanning the insertion point leaves the new text
            // standing: what someone typed is never deleted by an edit
            // that did not see it. Two deletions, around it.
            if o < from, o + l > from {
                return [.deleteText(para: para, offset: o, length: from - o, removed: r),
                        .deleteText(para: para, offset: o + length, length: l - (from - o), removed: nil)]
            }
            return [o >= from ? moved(op, para: para, offset: o + length) : op]
        default:
            if o > from || (o == from && !opWins) { return [moved(op, para: para, offset: o + length)] }
            return [op]
        }
    }

    /// `length` units went out at (para, from).
    static func deleteOffsets(_ op: PageOp, para: Int, from: Int, length: Int) -> [PageOp] {
        guard op.para == para, let o = offsetOf(op) else { return [op] }
        let end = from + length
        switch op {
        case .deleteText(_, _, let l, let r):
            // Overlap: what both removed is gone once; keep what only this
            // op removed.
            let a = o, b = o + l
            if b <= from { return [op] }
            if a >= end { return [moved(op, para: para, offset: a - length)] }
            let lo = max(a, from), hi = min(b, end)
            let remaining = l - (hi - lo)
            if remaining <= 0 { return [] }
            return [.deleteText(para: para, offset: min(a, from), length: remaining, removed: r)]
        default:
            if o >= end { return [moved(op, para: para, offset: o - length)] }
            if o > from { return [moved(op, para: para, offset: from)] }
            return [op]
        }
    }

    /// Paragraph `para` was split at `at`; its tail is now `para + 1`.
    static func split(_ op: PageOp, para: Int, at: Int, opWins: Bool) -> [PageOp] {
        switch op {
        case .insertParagraphs(let a, _, _), .removeParagraphs(let a, _, _):
            // Paragraph-list ops count whole paragraphs: everything past
            // the split paragraph moves down one.
            return [a > para ? withParagraph(op) { $0 + 1 } : op]
        case .mergeParagraph(let p, let h, let s):
            if p > para { return [.mergeParagraph(para: p + 1, headLength: h, removedStyle: s)] }
            if p == para { return [.mergeParagraph(para: p + 1, headLength: h - at, removedStyle: s)] }   // joins what is now the tail
            return [op]
        case .setParagraph(let p, _, _):
            return [p > para ? withParagraph(op) { $0 + 1 } : op]
        case .setDocument:
            return [op]
        default:
            guard let p = op.para, let o = offsetOf(op) else { return [op] }
            if p > para { return [moved(op, para: p + 1, offset: o)] }
            if p < para { return [op] }
            if case .deleteText(_, _, let l, let r) = op, o < at, o + l > at {
                // A deletion across the split point: the head's part stays;
                // the tail's part is a second op on the new paragraph.
                return [.deleteText(para: p, offset: o, length: at - o, removed: r),
                        .deleteText(para: p + 1, offset: 0, length: o + l - at, removed: nil)]
            }
            if o > at || (o == at && !opWins) { return [moved(op, para: p + 1, offset: o - at)] }
            return [op]
        }
    }

    /// Paragraph `para + 1` was joined onto `para`, which had `headLength`.
    static func merge(_ op: PageOp, para: Int, headLength: Int) -> PageOp {
        switch op {
        case .insertParagraphs(let a, _, _), .removeParagraphs(let a, _, _):
            return a > para + 1 ? withParagraph(op) { $0 - 1 } : op
        case .setDocument:
            return op
        default:
            guard let p = op.para else { return op }
            if p > para + 1 { return withParagraph(op) { $0 - 1 } }
            if p == para + 1 { return moved(op, para: para, offset: headLength + (offsetOf(op) ?? 0)) }
            return op
        }
    }

    /// `count` paragraphs went in before `at`.
    static func shiftParagraphs(_ op: PageOp, from at: Int, by count: Int, opWins: Bool) -> PageOp {
        guard let p = op.para else { return op }
        switch op {
        case .insertParagraphs:
            return p > at || (p == at && !opWins) ? withParagraph(op) { $0 + count } : op
        default:
            return p >= at ? withParagraph(op) { $0 + count } : op
        }
    }

    /// `count` paragraphs went out at `at`.
    static func removeParagraphs(_ op: PageOp, from at: Int, count: Int) -> [PageOp] {
        guard let p = op.para else { return [op] }
        let end = at + count
        switch op {
        case .removeParagraphs(_, let n, let payload):
            let a = p, b = p + n
            if b <= at { return [op] }
            if a >= end { return [.removeParagraphs(at: a - count, count: n, paragraphs: payload)] }
            let remaining = n - (min(b, end) - max(a, at))
            return remaining <= 0 ? [] : [.removeParagraphs(at: min(a, at), count: remaining, paragraphs: payload)]
        case .insertParagraphs:
            return [p >= end ? withParagraph(op) { $0 - count } : (p > at ? withParagraph(op) { _ in at } : op)]
        case .mergeParagraph(let m, _, _):
            // Joining onto a removed paragraph, or joining a removed one:
            // nothing left to do.
            if m >= at && m < end { return [] }
            if m + 1 >= at && m + 1 < end { return [] }
            return [m >= end ? withParagraph(op) { $0 - count } : op]
        default:
            if p >= end { return [withParagraph(op) { $0 - count }] }
            if p >= at { return [] }   // the paragraph this edits is gone
            return [op]
        }
    }
}
