// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// W-FN-1: inserting a footnote or an endnote. One undoable step: the mark in the body, the note's text for the layout
/// and the note's element in the file's notes part (made, with its separators, when the file had none), and the other
/// marks renumbered.
extension RichDocumentController {
    struct _Mark { var paragraph: Int; var offset: Int; var length: Int; var id: Int; var text: String; var style: CharStyle }

    /// The kind's numbered marks in body order (a custom mark keeps its own text and has no number).
    func _marks(_ kind: NoteReference.Kind) -> [_Mark] {
        var out: [_Mark] = []
        for (pi, p) in document.paragraphs.enumerated() {
            var offset = 0
            let units = Array(p.text.utf16)
            for r in p.runs {
                defer { offset += r.length }
                guard let n = r.style.note, n.kind == kind else { continue }
                let text = String(decoding: units[offset ..< min(offset + r.length, units.count)], as: UTF16.self)
                if text.contains("\u{200B}" as Character) { continue }
                out.append(_Mark(paragraph: pi, offset: offset, length: r.length, id: n.id, text: text, style: r.style))
            }
        }
        return out
    }

    /// The number format the file's marks use, from the first one; Word's defaults where there is none.
    private func _labelFormat(_ kind: NoteReference.Kind, _ marks: [_Mark]) -> ListNumberFormat {
        guard let first = marks.first?.text, let c = first.first else { return kind == .footnote ? .decimal : .lowerRoman }
        if c.isNumber { return .decimal }
        if first.allSatisfy({ "ivxlcdm".contains($0) }) { return .lowerRoman }
        if first.allSatisfy({ "IVXLCDM".contains($0) }) { return .upperRoman }
        if first.count == 1 || first.allSatisfy({ $0 == c }) { return c.isUppercase ? .upperLetter : .lowerLetter }
        return .decimal
    }

    /// The notes part with a new, empty note added (the part made, with its separator notes, where the file had none).
    private static func _addElement(to part: Data?, kind: NoteReference.Kind, id: Int, textStyle: String, markStyle: String) -> Data {
        let tag = kind == .footnote ? "footnote" : "endnote"
        var xml: String
        if let part { xml = String(decoding: part, as: UTF8.self) } else {
            func sep(_ type: String, _ n: Int, _ inner: String) -> String {
                "<w:\(tag) w:type=\"\(type)\" w:id=\"\(n)\"><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:r><w:\(inner)/></w:r></w:p></w:\(tag)>"
            }
            xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:\(tag)s xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
                + sep("separator", -1, "separator") + sep("continuationSeparator", 0, "continuationSeparator") + "</w:\(tag)s>"
        }
        let element = "<w:\(tag) w:id=\"\(id)\"><w:p><w:pPr><w:pStyle w:val=\"\(textStyle)\"/></w:pPr>"
            + "<w:r><w:rPr><w:rStyle w:val=\"\(markStyle)\"/></w:rPr><w:\(tag)Ref/></w:r>"
            + "<w:r><w:t xml:space=\"preserve\"> </w:t></w:r></w:p></w:\(tag)>"
        let closing = "</w:\(tag)s>"
        while let last = xml.last, last == "\n" || last == " " || last == "\r" { xml.removeLast() }
        if xml.hasSuffix(closing) { xml.removeLast(closing.count) }
        xml += element + closing
        return Data(xml.utf8)
    }

    /// Insert a footnote or endnote reference at the caret (the end of a selection) and an empty note for it; the
    /// caret stays after the mark. One undo step.
    public func insertNote(_ kind: NoteReference.Kind) {
        guard !readOnly else { return }
        let at = document.clamped(selection.end)
        guard document.paragraphs[at.paragraph].image == nil else { return }
        let marks = _marks(kind)
        let notes = kind == .footnote ? document.footnotes : document.endnotes
        let id = max(notes.keys.max() ?? 0, marks.map(\.id).max() ?? 0, 0) + 1
        let format = _labelFormat(kind, marks)
        func label(_ n: Int) -> String { format == .decimal ? String(n) : format.string(n) }
        // (Marks before the caret keep their numbers; the new one is the next, the rest move up by one.)
        let before = marks.filter { ($0.paragraph, $0.offset) < (at.paragraph, at.offset) }.count
        var numbered: [Int: Int] = [:]   // note id -> its new number
        for (i, m) in marks.enumerated() { numbered[m.id] = i < before ? i + 1 : i + 2 }
        numbered[id] = before + 1
        var state = NotesState(document)
        var markStyle = CharStyle.plain
        markStyle.script = .superscript
        markStyle.note = NoteReference(kind: kind, id: id)
        var noteMark = CharStyle.plain
        noteMark.script = .superscript
        noteMark.fontSize = 10
        var noteText = CharStyle.plain
        noteText.fontSize = 10
        let first = label(before + 1)
        let body = RichParagraph(text: first + " ", runs: [Run(length: first.utf16.count, style: noteMark), Run(length: 1, style: noteText)])
        // The notes' own marks follow their numbers.
        func relabeled(_ all: [Int: [RichParagraph]]) -> [Int: [RichParagraph]] {
            var out = all
            for (nid, paras) in all {
                guard let n = numbered[nid], var p = paras.first, let r = p.runs.first, r.length > 0,
                      Array(p.text.utf16).count >= r.length else { continue }
                let units = Array(p.text.utf16)
                let old = String(decoding: units[0 ..< r.length], as: UTF16.self)
                guard !old.isEmpty, old.allSatisfy({ $0.isLetter || $0.isNumber }) else { continue }
                let new = label(n)
                if old == new { continue }
                p = RichParagraph(text: new + String(decoding: units[r.length...], as: UTF16.self),
                                  runs: [Run(length: new.utf16.count, style: r.style)] + p.runs.dropFirst(), style: p.style)
                var list = paras; list[0] = p; out[nid] = list
            }
            return out
        }
        func textId(_ name: String, _ fallback: String) -> String { document.styles.styles.first { $0.name.lowercased() == name }?.id ?? fallback }
        func markId(_ name: String, _ fallback: String) -> String { document.keptCharacterStyleIds[name] ?? fallback }
        if kind == .footnote {
            state.footnotes = relabeled(state.footnotes); state.footnotes[id] = [body]
            state.footnotePart = Self._addElement(to: state.footnotePart, kind: .footnote, id: id, textStyle: textId("footnote text", "FootnoteText"), markStyle: markId("footnote reference", "FootnoteReference"))
        } else {
            state.endnotes = relabeled(state.endnotes); state.endnotes[id] = [body]
            state.endnotePart = Self._addElement(to: state.endnotePart, kind: .endnote, id: id, textStyle: textId("endnote text", "EndnoteText"), markStyle: markId("endnote reference", "EndnoteReference"))
        }
        let old = NotesState(document)
        edit {
            perform(.setNotes(new: state, old: old))
            // The later marks are renumbered first (last to first, so offsets before them hold), then the new one goes in.
            for (i, m) in marks.enumerated().reversed() where i >= before {
                let new = label(i + 2)
                guard new != m.text else { continue }
                let style = m.style
                let pos = RichPosition(paragraph: m.paragraph, offset: m.offset)
                perform(.deleteText(pos, m.text, [Run(length: m.length, style: style)]))
                perform(.insertText(pos, new, [Run(length: new.utf16.count, style: style)]))
            }
            perform(.insertText(at, first, [Run(length: first.utf16.count, style: markStyle)]))
            moveTo(RichPosition(paragraph: at.paragraph, offset: at.offset + first.utf16.count), extend: false)
        }
    }

    // MARK: Editing a note's text

    /// The note whose mark the caret stands next to (just before or just after it), or the one the selection is.
    public func noteAtCaret() -> NoteReference? {
        let sel = document.clamped(selection.end)
        let p = document.paragraphs[sel.paragraph]
        var offset = 0
        for r in p.runs {
            defer { offset += r.length }
            if let n = r.style.note, sel.offset >= offset, sel.offset <= offset + r.length { return n }
        }
        return nil
    }

    private static func _bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

    private static func _find(_ hay: [UInt8], _ needle: [UInt8], from: Int = 0) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count, from <= hay.count - needle.count else { return nil }
        var i = from
        while i <= hay.count - needle.count {
            if hay[i] == needle[0], Array(hay[i ..< i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }

    /// The byte range of note `id`'s element in a notes part.
    private static func _elementRange(_ part: [UInt8], kind: NoteReference.Kind, id: Int) -> Range<Int>? {
        let tag = kind == .footnote ? "footnote" : "endnote"
        guard let start = _find(part, _bytes("<w:\(tag) w:id=\"\(id)\"")),
              let close = _find(part, _bytes("</w:\(tag)>"), from: start) else { return nil }
        return start ..< close + _bytes("</w:\(tag)>").count
    }

    /// The tags a note may hold and still be edited as plain text without losing anything.
    private static let _plainTags: Set<String> = ["footnote", "endnote", "p", "pPr", "pStyle", "spacing", "r", "rPr", "rStyle", "sz", "szCs",
                                                  "vertAlign", "rFonts", "lang", "t", "footnoteRef", "endnoteRef"]

    private func _noteElement(_ n: NoteReference) -> (part: [UInt8], range: Range<Int>)? {
        guard let data = document.keptParts[n.kind == .footnote ? "word/footnotes.xml" : "word/endnotes.xml"] else { return nil }
        let part = Array(data)
        guard let r = Self._elementRange(part, kind: n.kind, id: n.id) else { return nil }
        return (part, r)
    }

    /// The note's text after its mark (paragraphs on separate lines), or nil when the note holds anything the plain
    /// editor would lose (a picture, a link, bold, a tab, a field...) or has no file element to edit.
    public func editableNoteText(_ n: NoteReference) -> String? {
        guard let (part, range) = _noteElement(n) else { return nil }
        let el = Array(part[range])
        var i = 0
        var sawRef = false
        while i < el.count {
            if el[i] == UInt8(ascii: "<"), i + 1 < el.count, el[i + 1] != UInt8(ascii: "/") {
                var j = i + 1
                while j < el.count, el[j] != UInt8(ascii: ">"), el[j] != UInt8(ascii: " "), el[j] != UInt8(ascii: "/") { j += 1 }
                let name = String(decoding: el[(i + 1) ..< j], as: UTF8.self)
                guard name.hasPrefix("w:"), Self._plainTags.contains(String(name.dropFirst(2))) else { return nil }
                if name == "w:footnoteRef" || name == "w:endnoteRef" { sawRef = true }
                i = j
            } else { i += 1 }
        }
        guard sawRef, let paras = (n.kind == .footnote ? document.footnotes : document.endnotes)[n.id], let first = paras.first,
              let markRun = first.runs.first else { return nil }
        var lines: [String] = []
        for (k, p) in paras.enumerated() {
            let units = Array(p.text.utf16)
            let from = k == 0 ? min(markRun.length, units.count) : 0
            var line = String(decoding: units[from...], as: UTF16.self)
            if k == 0, line.hasPrefix(" ") { line.removeFirst() }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func _escaped(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(c)
            }
        }
        return out
    }

    /// Replace a note's text (after its mark) by `text`, lines becoming paragraphs. One undo step; false when the note
    /// is not plain (see `editableNoteText`).
    @discardableResult
    public func setNoteText(_ n: NoteReference, _ text: String) -> Bool {
        guard !readOnly, editableNoteText(n) != nil, let (part, range) = _noteElement(n) else { return false }
        let kind = n.kind
        let tag = kind == .footnote ? "footnote" : "endnote"
        let el = Array(part[range])
        // The element up to the end of the run holding the reference mark, and the first paragraph's properties.
        guard let refAt = Self._find(el, Self._bytes("<w:\(tag)Ref")),
              let runEnd = Self._find(el, Self._bytes("</w:r>"), from: refAt) else { return false }
        let head = String(decoding: el[0 ..< runEnd + 6], as: UTF8.self)
        var pPr = ""
        if let a = Self._find(el, Self._bytes("<w:pPr>")), let b = Self._find(el, Self._bytes("</w:pPr>"), from: a), a < refAt {
            pPr = String(decoding: el[a ..< b + 8], as: UTF8.self)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func run(_ t: String) -> String {
            "<w:r><w:t xml:space=\"preserve\">\(Self._escaped(t))</w:t></w:r></w:p>"
        }
        var xml = head + run(" " + lines[0])
        for l in lines.dropFirst() { xml += "<w:p>" + pPr + run(l) }
        xml += "</w:\(tag)>"
        var newPart = Array(part[0 ..< range.lowerBound])
        newPart += Array(xml.utf8)
        newPart += Array(part[range.upperBound...])
        // The layout's copy: the mark run as it was, then the text.
        let notes = kind == .footnote ? document.footnotes : document.endnotes
        guard let old = notes[n.id], let first = old.first, let markRun = first.runs.first else { return false }
        let units = Array(first.text.utf16)
        let mark = String(decoding: units[0 ..< min(markRun.length, units.count)], as: UTF16.self)
        var bodyStyle = CharStyle.plain
        bodyStyle.fontSize = 10
        var paras: [RichParagraph] = []
        for (k, l) in lines.enumerated() {
            let t = k == 0 ? mark + " " + l : l
            var runs: [Run] = []
            if k == 0 { runs.append(Run(length: mark.utf16.count, style: markRun.style)) }
            let rest = t.utf16.count - (k == 0 ? mark.utf16.count : 0)
            if rest > 0 { runs.append(Run(length: rest, style: bodyStyle)) }
            paras.append(RichParagraph(text: t, runs: runs, style: k == 0 ? first.style : old.last?.style ?? first.style))
        }
        let before = NotesState(document)
        var after = before
        if kind == .footnote { after.footnotes[n.id] = paras; after.footnotePart = Data(newPart) }
        else { after.endnotes[n.id] = paras; after.endnotePart = Data(newPart) }
        edit { perform(.setNotes(new: after, old: before)) }
        return true
    }

    /// After an edit: a note whose mark is gone from the body (deleted with its text, or cut) goes too, in the same
    /// undo step, and the marks after it (and the notes' own) renumber. Called by `edit` at the end of the outer step.
    func _noteMarkIds() -> [Set<Int>]? {
        guard !document.footnotes.isEmpty || !document.endnotes.isEmpty else { return nil }
        var out: [Set<Int>] = [[], []]
        for p in document.paragraphs { for r in p.runs { if let n = r.style.note { out[n.kind == .footnote ? 0 : 1].insert(n.id) } } }
        return out
    }

    func _dropOrphanNotes(before: [Set<Int>]?) {
        guard let before else { return }
        for kind in [NoteReference.Kind.footnote, .endnote] {
            let notes = kind == .footnote ? document.footnotes : document.endnotes
            guard !notes.isEmpty else { continue }
            var present = Set<Int>()
            for p in document.paragraphs { for r in p.runs { if let n = r.style.note, n.kind == kind { present.insert(n.id) } } }
            let was = before[kind == .footnote ? 0 : 1]
            let gone = notes.keys.filter { was.contains($0) && !present.contains($0) }.sorted()
            guard !gone.isEmpty else { continue }
            var state = NotesState(document)
            for id in gone {
                if kind == .footnote {
                    state.footnotes[id] = nil
                    if let d = state.footnotePart { state.footnotePart = Self._removeElement(d, kind: kind, id: id) }
                } else {
                    state.endnotes[id] = nil
                    if let d = state.endnotePart { state.endnotePart = Self._removeElement(d, kind: kind, id: id) }
                }
            }
            // The rest renumber in body order.
            let marks = _marks(kind)
            let format = _labelFormat(kind, marks)
            func label(_ n: Int) -> String { format == .decimal ? String(n) : format.string(n) }
            var numbered: [Int: Int] = [:]
            for (i, m) in marks.enumerated() { numbered[m.id] = i + 1 }
            var all = kind == .footnote ? state.footnotes : state.endnotes
            for (nid, paras) in all {
                guard let n = numbered[nid], var p = paras.first, let r = p.runs.first, r.length > 0,
                      Array(p.text.utf16).count >= r.length else { continue }
                let units = Array(p.text.utf16)
                let old = String(decoding: units[0 ..< r.length], as: UTF16.self)
                guard !old.isEmpty, old.allSatisfy({ $0.isLetter || $0.isNumber }), old != label(n) else { continue }
                p = RichParagraph(text: label(n) + String(decoding: units[r.length...], as: UTF16.self),
                                  runs: [Run(length: label(n).utf16.count, style: r.style)] + p.runs.dropFirst(), style: p.style)
                var list = paras; list[0] = p; all[nid] = list
            }
            if kind == .footnote { state.footnotes = all } else { state.endnotes = all }
            let old = NotesState(document)
            perform(.setNotes(new: state, old: old))
            for (i, m) in marks.enumerated().reversed() {
                let new = label(i + 1)
                guard new != m.text else { continue }
                let pos = RichPosition(paragraph: m.paragraph, offset: m.offset)
                perform(.deleteText(pos, m.text, [Run(length: m.length, style: m.style)]))
                perform(.insertText(pos, new, [Run(length: new.utf16.count, style: m.style)]))
            }
        }
    }

    private static func _removeElement(_ data: Data, kind: NoteReference.Kind, id: Int) -> Data {
        let part = Array(data)
        guard let r = _elementRange(part, kind: kind, id: id) else { return data }
        return Data(Array(part[0 ..< r.lowerBound]) + Array(part[r.upperBound...]))
    }
}

// MARK: Footnote and Endnote options (W-FN-1)

/// The Footnote and Endnote dialog's settings for one kind of note, as the file's `w:footnotePr` / `w:endnotePr` holds them.
public struct NoteOptions: Equatable, Sendable {
    /// Footnotes: "pageBottom" or "beneathText"; endnotes: "docEnd" or "sectEnd".
    public var position: String
    public var format: ListNumberFormat
    public var start: Int
    /// "continuous", "eachSect" or "eachPage".
    public var restart: String

    public init(position: String, format: ListNumberFormat, start: Int, restart: String) {
        self.position = position; self.format = format; self.start = start; self.restart = restart
    }

    public static func defaults(_ kind: NoteReference.Kind) -> NoteOptions {
        NoteOptions(position: kind == .footnote ? "pageBottom" : "docEnd", format: kind == .footnote ? .decimal : .lowerRoman,
                    start: 1, restart: "continuous")
    }

    static func formatName(_ f: ListNumberFormat) -> String {
        switch f {
        case .lowerLetter: return "lowerLetter"
        case .upperLetter: return "upperLetter"
        case .lowerRoman: return "lowerRoman"
        case .upperRoman: return "upperRoman"
        default: return "decimal"
        }
    }

    static func format(named name: String) -> ListNumberFormat? {
        ["decimal": .decimal, "lowerLetter": .lowerLetter, "upperLetter": .upperLetter,
         "lowerRoman": .lowerRoman, "upperRoman": .upperRoman][name]
    }
}

extension RichDocumentController {
    /// The `w:val` of the first `<w:name …>` in `xml`.
    /// The `w:val` of the child `name` of a note properties element (`numRestart` → "eachPage"), or nil.
    public static func noteProperty(_ xml: String, _ name: String) -> String? { _value(xml, name) }

    private static func _value(_ xml: String, _ name: String) -> String? {
        let bytes = Array(xml.utf8)
        var from = 0
        while let at = _find(bytes, _bytes("<w:\(name)"), from: from) {
            let next = at + name.utf8.count + 3
            from = next
            guard next < bytes.count, bytes[next] == 0x20 || bytes[next] == 0x2F || bytes[next] == 0x3E else { continue }
            guard let close = _find(bytes, _bytes(">"), from: at), let v = _find(bytes, _bytes("w:val=\""), from: at), v < close else { return nil }
            let start = v + 7
            guard let end = _find(bytes, _bytes("\""), from: start) else { return nil }
            return String(decoding: bytes[start ..< end], as: UTF8.self)
        }
        return nil
    }

    /// The document's options for the kind, Word's defaults where the file states none.
    public func noteOptions(_ kind: NoteReference.Kind) -> NoteOptions {
        var o = NoteOptions.defaults(kind)
        guard let xml = kind == .footnote ? document.footnotePropertiesXML : document.endnotePropertiesXML else {
            if kind == .endnote, document.endnotesAtSectionEnd { o.position = "sectEnd" }
            return o
        }
        if let v = Self._value(xml, "pos") { o.position = v }
        if let v = Self._value(xml, "numFmt"), let f = NoteOptions.format(named: v) { o.format = f }
        if let v = Self._value(xml, "numStart"), let n = Int(v) { o.start = n }
        if let v = Self._value(xml, "numRestart") { o.restart = v }
        return o
    }

    /// The properties element for `options`, keeping the old element's separator ids; only what differs from
    /// Word's defaults is written, and nil when nothing is left.
    static func _notePropertiesXML(_ kind: NoteReference.Kind, _ options: NoteOptions, keeping old: String?) -> String? {
        let tag = kind == .footnote ? "footnote" : "endnote"
        let d = NoteOptions.defaults(kind)
        var inner = ""
        if options.position != d.position { inner += "<w:pos w:val=\"\(options.position)\"/>" }
        if options.format != d.format { inner += "<w:numFmt w:val=\"\(NoteOptions.formatName(options.format))\"/>" }
        if options.start != d.start { inner += "<w:numStart w:val=\"\(options.start)\"/>" }
        if options.restart != d.restart { inner += "<w:numRestart w:val=\"\(options.restart)\"/>" }
        // (The separator notes' ids, which close CT_FtnDocProps / CT_EdnDocProps.)
        if let old {
            let bytes = Array(old.utf8)
            var from = 0
            let open = _bytes("<w:\(tag) ")
            while let at = _find(bytes, open, from: from), let end = _find(bytes, _bytes("/>"), from: at) {
                inner += String(decoding: bytes[at ..< end + 2], as: UTF8.self)
                from = end + 2
            }
        }
        return inner.isEmpty ? nil : "<w:\(tag)Pr>\(inner)</w:\(tag)Pr>"
    }

    /// Set the kind's numbering and placement: the marks in the body and the notes renumbered to match. One undo step.
    /// (Restart each page is saved; the marks keep counting through, as there are no pages yet at edit time.)
    public func setNoteOptions(_ kind: NoteReference.Kind, _ options: NoteOptions) {
        guard !readOnly else { return }
        var state = NotesState(document)
        let oldXML = kind == .footnote ? state.footnoteProperties : state.endnoteProperties
        let xml = Self._notePropertiesXML(kind, options, keeping: oldXML)
        if kind == .footnote { state.footnoteProperties = xml } else {
            state.endnoteProperties = xml
            state.endnotesAtSectionEnd = options.position == "sectEnd"
        }
        let marks = _marks(kind)
        func label(_ n: Int) -> String { options.format.string(n) }
        var numbered: [Int: Int] = [:]
        var labels: [String] = []
        var n = options.start - 1
        var sectionOf: [Int] = []   // paragraph -> its section
        var s = 0
        for p in document.paragraphs { sectionOf.append(s); if p.style.sectionXML != nil { s += 1 } }
        var lastSection = 0
        for m in marks {
            let section = sectionOf[m.paragraph]
            if options.restart == "eachSect", section != lastSection { n = options.start - 1 }
            lastSection = section
            n += 1
            numbered[m.id] = n
            labels.append(label(n))
        }
        func relabeled(_ all: [Int: [RichParagraph]]) -> [Int: [RichParagraph]] {
            var out = all
            for (nid, paras) in all {
                guard let num = numbered[nid], var p = paras.first, let r = p.runs.first, r.length > 0 else { continue }
                let units = Array(p.text.utf16)
                guard units.count >= r.length else { continue }
                let old = String(decoding: units[0 ..< r.length], as: UTF16.self)
                guard !old.isEmpty, old.allSatisfy({ $0.isLetter || $0.isNumber }) else { continue }
                let new = label(num)
                if old == new { continue }
                p = RichParagraph(text: new + String(decoding: units[r.length...], as: UTF16.self),
                                  runs: [Run(length: new.utf16.count, style: r.style)] + p.runs.dropFirst(), style: p.style)
                var list = paras; list[0] = p; out[nid] = list
            }
            return out
        }
        if kind == .footnote { state.footnotes = relabeled(state.footnotes) } else { state.endnotes = relabeled(state.endnotes) }
        let old = NotesState(document)
        guard state != old else { return }
        edit {
            perform(.setNotes(new: state, old: old))
            for (i, m) in marks.enumerated().reversed() where labels[i] != m.text {
                let pos = RichPosition(paragraph: m.paragraph, offset: m.offset)
                perform(.deleteText(pos, m.text, [Run(length: m.length, style: m.style)]))
                perform(.insertText(pos, labels[i], [Run(length: labels[i].utf16.count, style: m.style)]))
            }
        }
    }

    /// Move the caret just past the next note mark of the kind after it (Next Footnote); wraps to the first.
    public func goToNextNote(_ kind: NoteReference.Kind) {
        let marks = _marks(kind)
        guard !marks.isEmpty else { return }
        let at = document.clamped(selection.end)
        let next = marks.first { ($0.paragraph, $0.offset) > (at.paragraph, at.offset) } ?? marks[0]
        moveTo(RichPosition(paragraph: next.paragraph, offset: next.offset), extend: false)
    }
}
