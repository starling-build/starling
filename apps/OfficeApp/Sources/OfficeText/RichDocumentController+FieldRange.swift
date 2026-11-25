// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension RichDocumentController {
    /// The field whose result holds the caret (Word shades it gray while the caret is inside): the run's stretch, with
    /// the runs next to it that belong to the same field. A caret at the very start of a field is outside it.
    public func fieldRangeAtCaret() -> RichSelection? {
        guard selection.isCollapsed else { return nil }
        let at = document.clamped(selection.focus)
        let p = document.paragraphs[at.paragraph]
        func key(_ s: CharStyle) -> String? {
            if s.fieldResult != 0 { return "r\(s.fieldResult)" }
            if let f = s.preservedField { return "p" + f }
            if let f = s.field { return "f" + f }
            return nil
        }
        var spans: [(start: Int, end: Int, key: String?)] = []
        var offset = 0
        for r in p.runs { spans.append((offset, offset + r.length, key(r.style))); offset += r.length }
        guard let i = spans.firstIndex(where: { $0.key != nil && at.offset > $0.start && at.offset <= $0.end }) else { return nil }
        var lo = i, hi = i
        while lo > 0, spans[lo - 1].key == spans[i].key { lo -= 1 }
        while hi + 1 < spans.count, spans[hi + 1].key == spans[i].key { hi += 1 }
        return RichSelection(anchor: RichPosition(paragraph: at.paragraph, offset: spans[lo].start),
                             focus: RichPosition(paragraph: at.paragraph, offset: spans[hi].end))
    }
}
