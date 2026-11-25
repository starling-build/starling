// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// W-FD-1: inserting a field (DATE, TIME, AUTHOR, PAGE...) at the caret and bringing fields up to date (F9). A field is
/// the run (or runs) of its shown result carrying the instruction (`preservedField`) and a number shared by its runs
/// (`fieldResult`); the file writer wraps them in the field characters.
extension RichDocumentController {
    /// A field's instruction and where its shown result sits (paragraph, offset, length in UTF-16 units).
    public struct FieldSpan: Equatable {
        public var paragraph: Int
        public var offset: Int
        public var length: Int
        public var instruction: String
        public var result: Int
        public var shown: String
    }

    /// Every field with a shown result in the body, in order (a field of several result runs is one span).
    public func fieldSpans() -> [FieldSpan] {
        var out: [FieldSpan] = []
        for (pi, p) in document.paragraphs.enumerated() {
            let units = Array(p.text.utf16)
            var offset = 0
            for r in p.runs {
                defer { offset += r.length }
                guard let instr = r.style.preservedField, r.style.fieldResult != 0, r.length > 0 else { continue }
                let end = min(offset + r.length, units.count)
                let text = String(decoding: units[offset ..< end], as: UTF16.self)
                if let last = out.last, last.paragraph == pi, last.result == r.style.fieldResult, last.offset + last.length == offset {
                    out[out.count - 1].length += r.length
                    out[out.count - 1].shown += text
                } else {
                    out.append(FieldSpan(paragraph: pi, offset: offset, length: r.length, instruction: instr,
                                         result: r.style.fieldResult, shown: text))
                }
            }
        }
        return out
    }

    /// Insert a field at the caret, showing `result`; the caret goes after it. One undo step.
    public func insertField(_ instruction: String, result: String) {
        guard !readOnly, !result.isEmpty else { return }
        guard document.paragraphs[selection.focus.paragraph].image == nil else { return }
        let id = (document.paragraphs.flatMap { $0.runs }.map { $0.style.fieldResult }.max() ?? 0) + 1
        edit {
            if hasSelection { _deleteSelectionOps() }
            let pos = selection.focus
            // The field looks like the text it sits in.
            var style = typingStyle ?? document.paragraphs[pos.paragraph].style(at: pos.offset)
            style.preservedField = instruction
            style.fieldResult = id
            style.field = nil
            style.link = nil
            style.note = nil
            style.revision = nil
            perform(.insertText(pos, result, [Run(length: result.utf16.count, style: style)]))
            moveTo(RichPosition(paragraph: pos.paragraph, offset: pos.offset + result.utf16.count), extend: false)
        }
    }

    /// Bring fields up to date (F9): each field in `spans` shows `evaluate(instruction, shown)` where that answers.
    /// One undo step. Returns how many fields changed.
    @discardableResult
    public func updateFields(_ spans: [FieldSpan]? = nil, evaluate: (String, String) -> String?) -> Int {
        guard !readOnly else { return 0 }
        let all = spans ?? fieldSpans()
        var changes: [(FieldSpan, String)] = []
        for f in all {
            if let new = evaluate(f.instruction, f.shown), new != f.shown { changes.append((f, new)) }
        }
        guard !changes.isEmpty else { return 0 }
        edit {
            // Last to first, so the offsets of those not yet done hold.
            for (f, new) in changes.sorted(by: { ($0.0.paragraph, $0.0.offset) > ($1.0.paragraph, $1.0.offset) }) {
                let p = document.paragraphs[f.paragraph]
                var style = CharStyle.plain
                var runs: [Run] = []
                var offset = 0
                for r in p.runs {
                    if offset >= f.offset, offset < f.offset + f.length { runs.append(r) }
                    offset += r.length
                }
                if let first = runs.first { style = first.style }
                let pos = RichPosition(paragraph: f.paragraph, offset: f.offset)
                perform(.deleteText(pos, f.shown, runs))
                perform(.insertText(pos, new, [Run(length: new.utf16.count, style: style)]))
            }
        }
        return changes.count
    }
}
