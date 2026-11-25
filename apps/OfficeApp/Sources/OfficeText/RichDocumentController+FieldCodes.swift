// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Shift+F9 (the field at the caret) and Alt+F9 (every field): show a field as its code, "{ instruction }", in place of
/// its result, and back. The code is ordinary text while shown, so it can be edited; hiding it writes the instruction as
/// edited back into the field and puts the result the file had back (F9 brings the result up to date). One undo step.
extension RichDocumentController {
    private static func _instruction(_ s: CharStyle) -> String? { s.preservedField ?? s.field ?? s.linkField }

    private struct _Group { var runs: Range<Int>; var start: Int; var end: Int }

    /// The paragraph's fields shown as results: runs next to each other that belong to one field.
    private func _resultGroups(_ p: RichParagraph) -> [_Group] {
        var out: [_Group] = []
        var offset = 0
        var i = 0
        let runs = p.runs
        while i < runs.count {
            let s = runs[i].style
            guard s.fieldCodeID == 0, let instr = Self._instruction(s) else { offset += runs[i].length; i += 1; continue }
            var j = i + 1, end = offset + runs[i].length
            while j < runs.count, runs[j].style.fieldCodeID == 0, Self._instruction(runs[j].style) == instr,
                  runs[j].style.fieldResult == s.fieldResult, runs[j].style.linkFieldID == s.linkFieldID {
                end += runs[j].length; j += 1
            }
            if end > offset { out.append(_Group(runs: i..<j, start: offset, end: end)) }
            offset = end; i = j
        }
        return out
    }

    /// The paragraph's shown codes: runs next to each other with one code id.
    private func _codeGroups(_ p: RichParagraph) -> [(id: Int, group: _Group)] {
        var out: [(Int, _Group)] = []
        var offset = 0
        var i = 0
        let runs = p.runs
        while i < runs.count {
            let id = runs[i].style.fieldCodeID
            guard id != 0 else { offset += runs[i].length; i += 1; continue }
            var j = i + 1, end = offset + runs[i].length
            while j < runs.count, runs[j].style.fieldCodeID == id { end += runs[j].length; j += 1 }
            out.append((id, _Group(runs: i..<j, start: offset, end: end)))
            offset = end; i = j
        }
        return out
    }

    /// Whether any field's code is shown.
    public var showsFieldCodes: Bool { !_codeStash.isEmpty }

    private func _units(_ p: RichParagraph) -> [UInt16] { Array(p.text.utf16) }

    private func _showing(_ p: RichParagraph, only: _Group?) -> RichParagraph? {
        let groups = _resultGroups(p).filter { only == nil || ($0.start == only!.start && $0.end == only!.end) }
        guard !groups.isEmpty else { return nil }
        let units = _units(p)
        var q = p
        var text = "", runs: [Run] = []
        var cursor = 0, runIndex = 0
        func copyUntil(_ target: Int) {
            while runIndex < p.runs.count, cursor < target {
                let r = p.runs[runIndex]
                text += String(decoding: units[min(cursor, units.count) ..< min(cursor + r.length, units.count)], as: UTF16.self)
                runs.append(r); cursor += r.length; runIndex += 1
            }
        }
        for g in groups {
            copyUntil(g.start)
            let id = _codeNext; _codeNext += 1
            var stash: [(text: String, style: CharStyle)] = []
            var o = g.start
            for r in p.runs[g.runs] {
                stash.append((String(decoding: units[min(o, units.count) ..< min(o + r.length, units.count)], as: UTF16.self), r.style))
                o += r.length
            }
            _codeStash[id] = stash
            let first = p.runs[g.runs.lowerBound].style
            var style = first
            style.preservedField = nil; style.field = nil; style.linkField = nil; style.link = nil; style.linkTip = nil
            style.fieldResult = 0; style.linkFieldID = 0; style.fieldCodeID = id
            let code = "{ " + (Self._instruction(first) ?? "") + " }"
            text += code
            runs.append(Run(length: code.utf16.count, style: style))
            cursor = g.end
            while runIndex < p.runs.count, runIndex < g.runs.upperBound { runIndex += 1 }
        }
        copyUntil(units.count)
        q.text = text; q.runs = runs
        return q
    }

    private func _hiding(_ p: RichParagraph, ids: Set<Int>?) -> RichParagraph? {
        let groups = _codeGroups(p).filter { ids == nil || ids!.contains($0.id) }
        guard !groups.isEmpty else { return nil }
        let units = _units(p)
        var text = "", runs: [Run] = []
        var cursor = 0, runIndex = 0
        func copyUntil(_ target: Int) {
            while runIndex < p.runs.count, cursor < target {
                let r = p.runs[runIndex]
                text += String(decoding: units[min(cursor, units.count) ..< min(cursor + r.length, units.count)], as: UTF16.self)
                runs.append(r); cursor += r.length; runIndex += 1
            }
        }
        for (id, g) in groups {
            copyUntil(g.start)
            let shown = String(decoding: units[min(g.start, units.count) ..< min(g.end, units.count)], as: UTF16.self)
            var body = shown.trimmingWhitespace(newlines: true)
            if body.hasPrefix("{") { body.removeFirst() }
            if body.hasSuffix("}") { body.removeLast() }
            let instr = body.trimmingWhitespace(newlines: true)
            for (t, st) in _codeStash[id] ?? [] where !t.isEmpty {
                var style = st
                if !instr.isEmpty {
                    if style.preservedField != nil { style.preservedField = instr }
                    else if style.field != nil { style.field = instr }
                    else if style.linkField != nil { style.linkField = instr }
                }
                text += t
                runs.append(Run(length: t.utf16.count, style: style))
            }
            _codeStash[id] = nil
            cursor = g.end
            while runIndex < p.runs.count, runIndex < g.runs.upperBound { runIndex += 1 }
        }
        copyUntil(units.count)
        var q = p
        q.text = text; q.runs = runs
        return q
    }

    /// Show or hide field codes: `all` (Alt+F9) every field in the document; otherwise (Shift+F9) the field at the caret.
    public func toggleFieldCodes(all: Bool) {
        guard !readOnly else { return }
        var changed: [(Int, RichParagraph)] = []
        if all {
            let hide = showsFieldCodes
            for (i, p) in document.paragraphs.enumerated() {
                if let q = hide ? _hiding(p, ids: nil) : _showing(p, only: nil) { changed.append((i, q)) }
            }
        } else {
            let at = document.clamped(selection.focus)
            let p = document.paragraphs[at.paragraph]
            if let c = _codeGroups(p).first(where: { at.offset >= $0.group.start && at.offset <= $0.group.end }) {
                if let q = _hiding(p, ids: [c.id]) { changed.append((at.paragraph, q)) }
            } else if let g = _resultGroups(p).first(where: { at.offset >= $0.start && at.offset <= $0.end }) {
                if let q = _showing(p, only: g) { changed.append((at.paragraph, q)) }
            }
        }
        guard !changed.isEmpty else { return }
        let caret = selection.focus
        edit {
            for (i, q) in changed { perform(.restoreParagraphs(i, count: 1, [q])) }
            moveTo(document.clamped(caret), extend: false)
        }
    }
}

/// F9 (Update Field): PAGE, NUMPAGES and PAGEREF in the body brought up to date from the layout.
extension RichDocumentController {
    /// The field's new result, or nil where this update does not know the kind.
    private func _fieldResult(_ instr: String, paragraph: Int, pageOf: (Int) -> String?, pageCount: Int) -> String? {
        let words = instr.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let kind = words.first?.uppercased() else { return nil }
        if kind.hasPrefix("=") {
            // A table formula: "=SUM(ABOVE) \# "0.00"" (the picture is optional).
            var code = instr.trimmingWhitespace(newlines: true), picture = ""
            if let r = code.rangeOfSubstring("\\#") {
                picture = String(code[r.upperBound...]).trimmingWhitespace(newlines: true).filter { $0 != "\"" }
                code = String(code[..<r.lowerBound])
            }
            guard let grid = _formulaGrid(at: paragraph), let v = grid.evaluate(code) else { return nil }
            return TableFormula.format(v, picture: picture)
        }
        switch kind {
        case "PAGE": return pageOf(paragraph)
        case "NUMPAGES": return String(pageCount)
        case "REF":
            // The bookmark's text, where its start and end lie in one paragraph (a paragraph-number switch is not worked out).
            guard words.count > 1, !words.contains(where: { ["\\n", "\\r", "\\w", "\\p", "\\f"].contains($0) }) else { return nil }
            let name = words[1].filter { $0 != "\"" }.lowercased()
            for q in document.paragraphs {
                guard let start = q.bookmarkMarkers.first(where: { $0.name?.lowercased() == name }),
                      let end = q.bookmarkMarkers.first(where: { $0.name == nil && $0.id == start.id }), end.offset >= start.offset else { continue }
                let u = Array(q.text.utf16)
                return String(decoding: u[min(start.offset, u.count) ..< min(end.offset, u.count)], as: UTF16.self)
            }
            return nil
        case "PAGEREF":
            guard words.count > 1, !words.contains("\\p") else { return nil }
            let name = words[1].filter { $0 != "\"" }.lowercased()
            guard let home = document.paragraphs.firstIndex(where: { $0.bookmarks.contains { $0.lowercased() == name } }) else { return nil }
            return pageOf(home)
        default: return nil
        }
    }

    /// Update the fields in the selection, or the one at the caret. Returns how many results changed.
    @discardableResult
    public func updateFields(pageOf: (Int) -> String?, pageCount: Int) -> Int {
        guard !readOnly else { return 0 }
        let a = document.clamped(selection.start), b = document.clamped(selection.end)
        var changed: [(Int, RichParagraph)] = []
        for i in a.paragraph ... b.paragraph {
            let p = document.paragraphs[i]
            let lo = i == a.paragraph ? a.offset : 0, hi = i == b.paragraph ? b.offset : Int.max
            let groups = _resultGroups(p).filter { $0.end >= lo && $0.start <= hi }
            guard !groups.isEmpty else { continue }
            let units = _units(p)
            var text = "", runs: [Run] = [], cursor = 0, runIndex = 0, touched = false
            func copyUntil(_ target: Int) {
                while runIndex < p.runs.count, cursor < target {
                    let r = p.runs[runIndex]
                    text += String(decoding: units[min(cursor, units.count) ..< min(cursor + r.length, units.count)], as: UTF16.self)
                    runs.append(r); cursor += r.length; runIndex += 1
                }
            }
            for g in groups {
                copyUntil(g.start)
                let first = p.runs[g.runs.lowerBound].style
                guard let instr = Self._instruction(first),
                      let result = _fieldResult(instr, paragraph: i, pageOf: pageOf, pageCount: pageCount) else { continue }
                let old = String(decoding: units[min(g.start, units.count) ..< min(g.end, units.count)], as: UTF16.self)
                while runIndex < g.runs.upperBound { cursor += p.runs[runIndex].length; runIndex += 1 }
                if old == result {
                    text += old
                    for k in g.runs { runs.append(p.runs[k]) }
                } else {
                    touched = true
                    text += result
                    if !result.isEmpty { runs.append(Run(length: result.utf16.count, style: first)) }
                }
            }
            copyUntil(units.count)
            guard touched else { continue }
            var q = p; q.text = text; q.runs = runs
            changed.append((i, q))
        }
        guard !changed.isEmpty else { return 0 }
        let caret = selection.focus
        edit {
            for (i, q) in changed { perform(.restoreParagraphs(i, count: 1, [q])) }
            moveTo(document.clamped(caret), extend: false)
        }
        return changed.count
    }
}
