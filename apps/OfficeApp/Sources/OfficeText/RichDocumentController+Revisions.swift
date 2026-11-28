import Foundation

/// Word's Review tab: track changes on and off, accept or reject tracked changes, and step from one to the next.
extension RichDocumentController {
    /// One tracked change, as Previous / Next steps through them: the stretch it covers.
    public struct TrackedChange: Equatable, Sendable {
        public var start: RichPosition
        public var end: RichPosition
    }

    /// Every tracked change in reading order: a stretch of inserted, deleted or reformatted text, a changed
    /// paragraph mark (from the paragraph's end to the next one's start), a paragraph whose formatting changed.
    public func trackedChanges() -> [TrackedChange] {
        var out: [TrackedChange] = []
        let ps = document.paragraphs
        for (i, p) in ps.enumerated() {
            if p.style.propertyChange != nil {
                out.append(TrackedChange(start: RichPosition(paragraph: i, offset: 0), end: RichPosition(paragraph: i, offset: p.length)))
            }
            var at = 0
            var open: (start: Int, key: String)? = nil
            func close(_ end: Int) {
                if let o = open { out.append(TrackedChange(start: RichPosition(paragraph: i, offset: o.start), end: RichPosition(paragraph: i, offset: end))) }
                open = nil
            }
            for run in p.runs {
                let key = Self._changeKey(run.style)
                if key != open?.key { close(at); if let key, run.length > 0 { open = (at, key) } }
                at += run.length
            }
            close(at)
            if p.style.markRevision != nil {
                let next = i + 1 < ps.count ? RichPosition(paragraph: i + 1, offset: 0) : RichPosition(paragraph: i, offset: p.length)
                out.append(TrackedChange(start: RichPosition(paragraph: i, offset: p.length), end: next))
            }
        }
        return out
    }

    /// What tells one change from the next along a paragraph: its kind and who made it when.
    static func _changeKey(_ s: CharStyle) -> String? {
        var key = ""
        if let r = s.revision { key += "\(r.kind.rawValue)|\(r.author)|\(r.date)|" }
        if let f = s.formatChange { key += "f|\(f.author)|\(f.date)" }
        return key.isEmpty ? nil : key
    }

    /// Next / Previous change: select the first change after the selection (before it), wrapping around as Word
    /// offers to. False when the document holds none.
    @discardableResult
    public func selectAdjacentChange(forward: Bool) -> Bool {
        let all = trackedChanges()
        guard !all.isEmpty else { return false }
        let lo = selection.start, hi = selection.end
        let pick: TrackedChange
        // Two changes can start at one place (a paragraph's formatting and its first word's): from a selected
        // change, step along the list rather than by position.
        if let k = all.firstIndex(where: { $0.start == lo && $0.end == hi }) {
            pick = all[(k + (forward ? 1 : all.count - 1)) % all.count]
        } else if forward {
            pick = all.first { $0.start >= hi } ?? all.first!
        } else {
            pick = all.last { $0.end <= lo && $0.start < lo } ?? all.last!
        }
        moveTo(pick.start, extend: false)
        moveTo(pick.end, extend: true)
        return true
    }

    /// Accept or reject the changes the selection touches; with no selection, the change at the caret (Word's
    /// Accept / Reject This Change). One undo step. Returns how many changes it resolved.
    @discardableResult
    public func resolveChanges(accept: Bool) -> Int {
        var lo = selection.start, hi = selection.end
        if lo == hi {
            guard let c = trackedChanges().first(where: { $0.start <= lo && lo <= $0.end }) else { return 0 }
            lo = c.start; hi = c.end
        }
        return _resolve(from: lo, to: hi, accept: accept)
    }

    /// Accept All / Reject All Changes. One undo step.
    @discardableResult
    public func resolveAllChanges(accept: Bool) -> Int {
        let last = document.paragraphs.count - 1
        return _resolve(from: RichPosition(paragraph: 0, offset: 0),
                        to: RichPosition(paragraph: last, offset: document.paragraphs[last].length), accept: accept, wholeDocument: true)
    }

    private func _resolve(from lo: RichPosition, to hi: RichPosition, accept: Bool, wholeDocument: Bool = false) -> Int {
        guard !readOnly else { return 0 }
        let first = lo.paragraph
        // A changed mark at the range's end joins its paragraph to the next: the slice takes that one in too.
        let lastIn = min(hi.paragraph, document.paragraphs.count - 1)
        let sliceEnd = min(lastIn + 1, document.paragraphs.count - 1)
        var slice = Array(document.paragraphs[first ... sliceEnd])
        var count = 0
        for i in stride(from: lastIn, through: first, by: -1) {
            let k = i - first
            let len = slice[k].length
            let a = i == lo.paragraph ? lo.offset : 0
            let b = i == hi.paragraph ? hi.offset : len
            // The mark is in the range when the range runs past it (or covers the whole document).
            let markIn = i < hi.paragraph || wholeDocument
            // Paragraph formatting: a paragraph the range runs through, or all of one.
            let touched = i < hi.paragraph || a < b || wholeDocument || (lo.paragraph == hi.paragraph && a == 0 && b == len)
            if touched, let change = slice[k].style.propertyChange {
                count += 1
                var style = slice[k].style
                if !accept, let was = change.restore ?? change.previous, case .paragraph(let old) = was {
                    let keep = style
                    style = old
                    style.markRevision = keep.markRevision; style.mark = keep.mark
                }
                style.propertyChange = nil
                slice[k].style = style
            }
            // The text's changes, in [a, b).
            var runs: [Run] = []
            var gone: [Range<Int>] = []
            var at = 0
            var counted = Set<String>()
            for run in slice[k].runs {
                let s = at, e = at + run.length
                at = e
                let cuts = [s, max(s, min(e, a)), max(s, min(e, b)), e]
                for j in 0 ..< 3 where cuts[j + 1] > cuts[j] || (run.length == 0 && j == 0) {
                    var style = run.style
                    let n = cuts[j + 1] - cuts[j]
                    if j == 1, let key = Self._changeKey(style) {
                        if !counted.contains(key) { counted.insert(key); count += 1 }
                        if let r = style.revision {
                            let removes = (r.kind == .inserted) != accept
                            if removes { gone.append(cuts[j] ..< cuts[j + 1]) }
                            style.revision = nil
                        }
                        if let f = style.formatChange {
                            if !accept, case .run(let old)? = f.restore {
                                var restored = old
                                restored.revision = style.revision
                                style = restored
                            }
                            style.formatChange = nil
                        }
                    }
                    runs.append(Run(length: n, style: style))
                }
            }
            slice[k].runs = runs
            slice[k].normalize()
            for r in gone.reversed() { _ = slice[k].delete(r) }
            // The paragraph mark.
            if markIn, let m = slice[k].style.markRevision {
                count += 1
                slice[k].style.markRevision = nil
                let join = (m.kind == .deleted) == accept
                if join, k + 1 < slice.count, slice[k].cell == slice[k + 1].cell, !slice[k].isImage, !slice[k + 1].isImage {
                    var merged = slice[k]
                    let next = slice.remove(at: k + 1)
                    merged.append(next)
                    // The mark that stays is the next paragraph's, and with it its formatting.
                    merged.style = next.style
                    slice[k] = merged
                }
            }
        }
        guard count > 0 else { return 0 }
        let original = sliceEnd - first + 1
        edit {
            perform(.restoreParagraphs(first, count: original, slice))
        }
        moveTo(document.clamped(lo), extend: false)
        return count
    }
}
