// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// W-FD-3: Insert > Bookmark (add, delete, go to), References > Insert Caption (a "Caption" paragraph numbered by a SEQ
/// field) and Insert > Cross-reference (a REF, PAGEREF or NOTEREF field to a bookmark round a heading, a bookmark, a
/// note's mark or a caption). Each change is one undo step; the file writer keeps bookmarks and fields as Word's.
extension RichDocumentController {
    /// A bookmark: its name and the range it covers (a point where start and end meet).
    public struct BookmarkEntry: Equatable {
        public var name: String
        public var start: RichPosition
        public var end: RichPosition
        /// Word hides the names it makes itself (`_Toc…`, `_Ref…`, `_GoBack`) unless asked.
        public var hidden: Bool { name.hasPrefix("_") }
    }

    /// Every bookmark in document order (one entry per name, the first where a name repeats).
    public func bookmarkEntries() -> [BookmarkEntry] {
        var out: [BookmarkEntry] = [], seen = Set<String>()
        var open: [String: (name: String, at: RichPosition)] = [:]
        for (i, p) in document.paragraphs.enumerated() {
            var ranged = Set<String>()
            for m in p.bookmarkMarkers {
                if let name = m.name {
                    open[m.id] = (name, RichPosition(paragraph: i, offset: min(m.offset, p.length)))
                    ranged.insert(name.lowercased())
                } else if let s = open.removeValue(forKey: m.id), seen.insert(s.name.lowercased()).inserted {
                    out.append(BookmarkEntry(name: s.name, start: s.at, end: RichPosition(paragraph: i, offset: min(m.offset, p.length))))
                }
            }
            for name in p.bookmarks where !ranged.contains(name.lowercased()) && open.values.allSatisfy({ $0.name != name })
                && seen.insert(name.lowercased()).inserted {
                let at = RichPosition(paragraph: i, offset: 0)
                out.append(BookmarkEntry(name: name, start: at, end: at))
            }
        }
        // A start whose end never came: a point.
        for s in open.values.sorted(by: { $0.at < $1.at }) where seen.insert(s.name.lowercased()).inserted {
            out.append(BookmarkEntry(name: s.name, start: s.at, end: s.at))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// Where the bookmark `name` starts (names match without regard to case, as in Word).
    public func bookmarkStart(_ name: String) -> RichPosition? {
        let key = name.lowercased()
        return bookmarkEntries().first { $0.name.lowercased() == key }?.start
    }

    /// The text the bookmark `name` covers, where it lies in one paragraph.
    public func bookmarkText(_ name: String) -> String? {
        let key = name.lowercased()
        guard let b = bookmarkEntries().first(where: { $0.name.lowercased() == key }), b.start.paragraph == b.end.paragraph else { return nil }
        let u = Array(document.paragraphs[b.start.paragraph].text.utf16)
        let lo = min(b.start.offset, u.count), hi = min(max(b.end.offset, lo), u.count)
        return String(decoding: u[lo ..< hi], as: UTF16.self)
    }

    /// Word's rule for a bookmark name: a letter first, then letters, digits and underscores, at most 40 characters.
    public static func isValidBookmarkName(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter, name.count <= 40 else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Bookmark the selection (or the caret) as `name`; a bookmark of that name moves here. False for a name Word refuses.
    @discardableResult
    public func addBookmark(_ name: String) -> Bool {
        guard !readOnly, Self.isValidBookmarkName(name) || name.hasPrefix("_Ref") else { return false }
        let a = document.clamped(selection.start), b = document.clamped(selection.end)
        edit { _setBookmark(name, a, b) }
        return true
    }

    /// Remove the bookmark `name` (the text stays).
    public func deleteBookmark(_ name: String) {
        guard !readOnly else { return }
        edit { _removeBookmark(name) }
    }

    /// Select what the bookmark `name` covers (put the caret there for a point). False where there is none.
    @discardableResult
    public func goToBookmark(_ name: String) -> Bool {
        let key = name.lowercased()
        guard let b = bookmarkEntries().first(where: { $0.name.lowercased() == key }) else { return false }
        moveTo(document.clamped(b.start), extend: false)
        if b.end != b.start { moveTo(document.clamped(b.end), extend: true) }
        return true
    }

    private func _removeBookmark(_ name: String) {
        let key = name.lowercased()
        var ids = Set<String>()
        for p in document.paragraphs { for m in p.bookmarkMarkers where m.name?.lowercased() == key { ids.insert(m.id) } }
        for (i, p) in document.paragraphs.enumerated() {
            var q = p
            q.bookmarks.removeAll { $0.lowercased() == key }
            q.bookmarkMarkers.removeAll { $0.name?.lowercased() == key || ($0.name == nil && ids.contains($0.id)) }
            if q != p { perform(.restoreParagraphs(i, count: 1, [q])) }
        }
    }

    /// Inside an edit: the bookmark `name` covers a...b (any old one of that name goes).
    private func _setBookmark(_ name: String, _ a: RichPosition, _ b: RichPosition) {
        _removeBookmark(name)
        let used = document.paragraphs.flatMap { $0.bookmarkMarkers.map(\.id) }.compactMap { Int($0) }
        let id = String((used.max() ?? 0) + 1)
        var first = document.paragraphs[a.paragraph]
        first.bookmarks.append(name)
        first.bookmarkMarkers.append(RichBookmarkMarker(id: id, name: name, offset: a.offset))
        if a.paragraph == b.paragraph {
            first.bookmarkMarkers.append(RichBookmarkMarker(id: id, offset: b.offset))
            perform(.restoreParagraphs(a.paragraph, count: 1, [first]))
        } else {
            var last = document.paragraphs[b.paragraph]
            last.bookmarkMarkers.append(RichBookmarkMarker(id: id, offset: b.offset))
            perform(.restoreParagraphs(a.paragraph, count: 1, [first]))
            perform(.restoreParagraphs(b.paragraph, count: 1, [last]))
        }
    }

    /// The hidden `_Ref` bookmark over a...b in one paragraph: the one there already, or a new one (Word's names, `_Ref`
    /// and nine digits). Inside an edit.
    private func _refBookmark(_ a: RichPosition, _ b: RichPosition) -> String {
        if let have = bookmarkEntries().first(where: { $0.name.hasPrefix("_Ref") && $0.start == a && $0.end == b }) { return have.name }
        let taken = Set(bookmarkEntries().map { $0.name.lowercased() })
        var n = 100_000_001 + taken.filter { $0.hasPrefix("_ref") }.count
        while taken.contains("_ref\(n)") { n += 1 }
        let name = "_Ref\(n)"
        _setBookmark(name, a, b)
        return name
    }
}

// MARK: - SEQ numbers and captions

extension RichDocumentController {
    /// The identifier a SEQ instruction counts (`Figure` in " SEQ Figure \* ARABIC "), nil for another field.
    public static func sequenceName(_ instr: String) -> String? {
        let words = instr.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count > 1, words[0].uppercased() == "SEQ" else { return nil }
        return String(words[1])
    }

    /// Each SEQ field's number as Word shows it, by field id: counted in body order per identifier. \r n restarts at n,
    /// \c repeats the last, \s n restarts after a heading of level n or above, \h shows nothing, \* picks the format.
    public func sequenceNumbers() -> [Int: String] {
        var count: [String: Int] = [:], resetLevel: [String: Int] = [:], out: [Int: String] = [:]
        for p in document.paragraphs {
            if let h = p.style.heading {
                for (name, level) in resetLevel where h <= level { count[name] = 0 }
            }
            for r in p.runs {
                guard r.style.fieldResult != 0, out[r.style.fieldResult] == nil, let instr = r.style.preservedField,
                      let name = Self.sequenceName(instr)?.lowercased() else { continue }
                let words = instr.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                func value(after s: String) -> String? {
                    guard let k = words.firstIndex(where: { $0.uppercased() == s }), k + 1 < words.count else { return nil }
                    return words[k + 1]
                }
                if let level = value(after: "\\S").flatMap({ Int($0) }) { resetLevel[name] = level }
                var n = count[name] ?? 0
                if let reset = value(after: "\\R").flatMap({ Int($0) }) { n = reset }
                else if !words.contains(where: { $0.uppercased() == "\\C" }) { n += 1 }
                count[name] = n
                if words.contains(where: { $0.uppercased() == "\\H" }) { out[r.style.fieldResult] = ""; continue }
                let format: ListNumberFormat
                switch value(after: "\\*") {
                case "ROMAN": format = .upperRoman
                case "roman": format = .lowerRoman
                case "ALPHABETIC": format = .upperLetter
                case "alphabetic": format = .lowerLetter
                default: format = .decimal
                }
                out[r.style.fieldResult] = format.string(n)
            }
        }
        return out
    }

    /// Word's caption labels.
    public static let captionLabels = ["Equation", "Figure", "Table"]

    public enum CaptionPlace: Sendable { case above, below }

    /// Where a caption goes: next to the table the caret is in (all of it), else next to the caret's paragraph.
    public func captionIndex(_ place: CaptionPlace) -> Int {
        let k = document.clamped(selection.focus).paragraph
        var lo = k, hi = k
        if let t = document.paragraphs[k].cell?.table {
            while lo > 0, document.paragraphs[lo - 1].cell?.table == t { lo -= 1 }
            while hi + 1 < document.paragraphs.count, document.paragraphs[hi + 1].cell?.table == t { hi += 1 }
        }
        return place == .above ? lo : hi + 1
    }

    /// The number a new caption of `label` would get at `place` (the SEQ fields of that label before it, plus one).
    /// `chapter`: the count starts again after each heading of that level or above (`SEQ … \s n`).
    public func nextCaptionNumber(_ label: String, _ place: CaptionPlace, chapter: Int? = nil) -> Int {
        let at = captionIndex(place), key = label.lowercased()
        var seen = Set<Int>()
        for p in document.paragraphs.prefix(at) {
            if let chapter, let h = p.style.heading, h <= chapter { seen = [] }
            for r in p.runs where r.style.fieldResult != 0 {
                if let instr = r.style.preservedField, Self.sequenceName(instr)?.lowercased() == key { seen.insert(r.style.fieldResult) }
            }
        }
        return seen.count + 1
    }

    /// Insert Caption > Numbering > Include chapter number: the heading level a chapter starts with and the mark
    /// between its number and the caption's (Word writes `{ STYLEREF 1 \s }-{ SEQ Figure \* ARABIC \s 1 }`).
    public struct CaptionChapter: Equatable, Sendable {
        public var level: Int
        public var separator: String
        public init(level: Int = 1, separator: String = "-") { self.level = level; self.separator = separator }
        /// Word's separators, with the names its dialog gives them.
        public static let separators: [(mark: String, title: String)] = [
            ("-", "hyphen"), (".", "period"), (":", "colon"), ("\u{2014}", "em-dash"), ("\u{2013}", "en-dash"),
        ]
    }

    /// What STYLEREF shows where it finds no heading of its level before it.
    public static let styleRefMissing = "Error! No text of specified style in document."

    /// `STYLEREF n \s` at paragraph `at`: the number of the last "Heading n" paragraph at or before it, without its
    /// words or closing punctuation ("Chapter 2." gives "2"). Nil where there is none, or it is not numbered.
    public func chapterNumber(level: Int, at: Int, labels: [String?]? = nil) -> String? {
        let ps = document.paragraphs
        guard !ps.isEmpty else { return nil }
        guard let k = stride(from: min(at, ps.count - 1), through: 0, by: -1).first(where: { ps[$0].style.heading == level }) else { return nil }
        guard let label = (labels ?? RichListNumbering.labels(document))[k] else { return nil }
        var number = String(label.split(separator: " ", omittingEmptySubsequences: true).last ?? "")
        while let last = number.last, !last.isLetter, !last.isNumber { number.removeLast() }
        return number.isEmpty ? nil : number
    }

    /// Whether any "Heading n" paragraph carries a number (Word refuses chapter numbers otherwise).
    public func headingsNumbered(level: Int) -> Bool {
        let labels = RichListNumbering.labels(document)
        return document.paragraphs.indices.contains { document.paragraphs[$0].style.heading == level && labels[$0] != nil }
    }

    /// References > Insert Caption: a new "Caption" paragraph above or below (the label, unless `excludeLabel`, a space,
    /// the SEQ field, then `title` as typed, e.g. ": A cat"). Later captions of the label are renumbered. One undo step.
    /// `chapter`: the number is the chapter's, a separator, then the count within the chapter.
    public func insertCaption(label: String, title: String, place: CaptionPlace, excludeLabel: Bool, chapter: CaptionChapter? = nil) {
        guard !readOnly, !label.isEmpty else { return }
        let at = captionIndex(place)
        var id = (document.paragraphs.flatMap { $0.runs }.map { $0.style.fieldResult }.max() ?? 0) + 1
        let number = String(nextCaptionNumber(label, place, chapter: chapter?.level))
        let lead = excludeLabel ? "" : label + " "
        var runs: [Run] = []
        var text = lead
        if !lead.isEmpty { runs.append(Run(length: lead.utf16.count, style: .plain)) }
        if let chapter {
            var ref = CharStyle.plain
            ref.preservedField = " STYLEREF \(chapter.level) \\s "
            ref.fieldResult = id
            id += 1
            let shown = chapterNumber(level: chapter.level, at: at - 1) ?? Self.styleRefMissing
            runs.append(Run(length: shown.utf16.count, style: ref))
            runs.append(Run(length: chapter.separator.utf16.count, style: .plain))
            text += shown + chapter.separator
        }
        var field = CharStyle.plain
        field.preservedField = chapter.map { " SEQ \(label) \\* ARABIC \\s \($0.level) " } ?? " SEQ \(label) \\* ARABIC "
        field.fieldResult = id
        runs.append(Run(length: number.utf16.count, style: field))
        if !title.isEmpty { runs.append(Run(length: title.utf16.count, style: .plain)) }
        text += number + title
        edit {
            if document.styles["Caption"] == nil, let entry = RichStyleSheet.word["Caption"] { perform(.addStyle(entry)) }
            var style = RichParagraphStyle()
            document.styles.apply("Caption", to: &style)
            perform(.insertParagraphs(at: at, [RichParagraph(text: text, runs: runs, style: style)]))
            _renumberSequence(label)
            moveTo(RichPosition(paragraph: at, offset: document.paragraphs[at].length), extend: false)
        }
    }

    /// Inside an edit: the SEQ fields of `label` show their numbers again.
    private func _renumberSequence(_ label: String) {
        let numbers = sequenceNumbers(), key = label.lowercased()
        for (i, p) in document.paragraphs.enumerated() {
            var text = "", runs: [Run] = [], offset = 0, changed = false
            let u = Array(p.text.utf16)
            var done = Set<Int>()
            for r in p.runs {
                let piece = String(decoding: u[min(offset, u.count) ..< min(offset + r.length, u.count)], as: UTF16.self)
                offset += r.length
                if r.style.fieldResult != 0, let instr = r.style.preservedField, Self.sequenceName(instr)?.lowercased() == key,
                   let shown = numbers[r.style.fieldResult] {
                    // A field of several runs shows its number once, in its first run's look.
                    guard done.insert(r.style.fieldResult).inserted else { changed = true; continue }
                    if shown != piece { changed = true }
                    text += shown
                    if !shown.isEmpty { runs.append(Run(length: shown.utf16.count, style: r.style)) }
                    continue
                }
                text += piece; runs.append(r)
            }
            guard changed else { continue }
            var q = p; q.text = text; q.runs = runs
            perform(.restoreParagraphs(i, count: 1, [q]))
        }
    }
}

// MARK: - Cross-references

extension RichDocumentController {
    /// Insert > Cross-reference: what the reference points at.
    public enum CrossReferenceType: Equatable, Sendable {
        case heading, bookmark, footnote, endnote
        /// Captions of this label (Figure, Table, Equation, or a SEQ name the document uses).
        case caption(String)

        public var title: String {
            switch self {
            case .heading: return "Heading"
            case .bookmark: return "Bookmark"
            case .footnote: return "Footnote"
            case .endnote: return "Endnote"
            case .caption(let label): return label
            }
        }

        /// The "Insert reference to" list, Word's wording.
        public var kinds: [CrossReferenceKind] {
            switch self {
            case .heading: return [.text, .page, .number, .aboveBelow]
            case .bookmark: return [.text, .page, .number, .aboveBelow]
            case .footnote, .endnote: return [.note, .page, .aboveBelow]
            case .caption: return [.text, .labelNumber, .captionText, .page, .aboveBelow]
            }
        }
    }

    public enum CrossReferenceKind: Equatable, Sendable {
        case text, page, number, aboveBelow, note, labelNumber, captionText

        public func title(_ type: CrossReferenceType) -> String {
            switch self {
            case .text:
                switch type {
                case .heading: return "Heading text"
                case .bookmark: return "Bookmark text"
                default: return "Entire caption"
                }
            case .page: return "Page number"
            case .number: return type == .heading ? "Heading number" : "Paragraph number"
            case .aboveBelow: return "Above/below"
            case .note: return type == .endnote ? "Endnote number" : "Footnote number"
            case .labelNumber: return "Only label and number"
            case .captionText: return "Only caption text"
            }
        }
    }

    /// One line of "For which": what it shows and where its target is.
    public struct CrossReferenceItem: Equatable {
        public var title: String
        public var start: RichPosition
        public var end: RichPosition
        /// The bookmark's own name (Bookmark type only).
        public var bookmark: String?
        /// Where the caption's number ends and its text starts (caption type only).
        public var numberEnd = 0
        public var textStart = 0
    }

    /// The types the dialog offers: Word's fixed ones and a caption type per label (the three of Word and any other the
    /// document numbers with SEQ).
    public func crossReferenceTypes() -> [CrossReferenceType] {
        var labels = Self.captionLabels
        for p in document.paragraphs {
            for r in p.runs {
                if let instr = r.style.preservedField, let name = Self.sequenceName(instr),
                   !labels.contains(where: { $0.lowercased() == name.lowercased() }) { labels.append(name) }
            }
        }
        return [.heading, .bookmark, .footnote, .endnote] + labels.sorted().map { CrossReferenceType.caption($0) }
    }

    public func crossReferenceItems(_ type: CrossReferenceType) -> [CrossReferenceItem] {
        switch type {
        case .heading:
            return document.paragraphs.enumerated().compactMap { i, p in
                guard p.style.heading != nil, p.cell == nil, !p.text.isEmpty else { return nil }
                return CrossReferenceItem(title: p.text, start: RichPosition(paragraph: i, offset: 0), end: RichPosition(paragraph: i, offset: p.length))
            }
        case .bookmark:
            return bookmarkEntries().filter { !$0.hidden }.sorted { $0.name.lowercased() < $1.name.lowercased() }.map {
                CrossReferenceItem(title: $0.name, start: $0.start, end: $0.end, bookmark: $0.name)
            }
        case .footnote, .endnote:
            let kind: NoteReference.Kind = type == .footnote ? .footnote : .endnote
            let notes = kind == .footnote ? document.footnotes : document.endnotes
            return _marks(kind).map { m in
                let body = notes[m.id]?.map(\.text).joined(separator: " ") ?? ""
                // The note's text after its own mark.
                let shown = body.hasPrefix(m.text) ? String(body.dropFirst(m.text.count).drop(while: { $0 == " " || $0 == "\t" })) : body
                return CrossReferenceItem(title: m.text + " " + shown, start: RichPosition(paragraph: m.paragraph, offset: m.offset),
                                          end: RichPosition(paragraph: m.paragraph, offset: m.offset + m.length))
            }
        case .caption(let label):
            let key = label.lowercased()
            var out: [CrossReferenceItem] = []
            for (i, p) in document.paragraphs.enumerated() {
                var offset = 0, numberEnd: Int?
                for r in p.runs {
                    offset += r.length
                    if r.style.fieldResult != 0, let instr = r.style.preservedField, Self.sequenceName(instr)?.lowercased() == key { numberEnd = offset }
                    else if numberEnd != nil { break }
                }
                guard let numberEnd else { continue }
                // The caption's text starts after the separator Word puts between number and text (": ", ". ", " - ").
                let u = Array(p.text.utf16)
                var textStart = numberEnd
                while textStart < u.count, let c = Unicode.Scalar(u[textStart]), " :.-\u{2013}\u{2014}\t".unicodeScalars.contains(c) { textStart += 1 }
                out.append(CrossReferenceItem(title: p.text, start: RichPosition(paragraph: i, offset: 0),
                                              end: RichPosition(paragraph: i, offset: p.length), numberEnd: numberEnd, textStart: textStart))
            }
            return out
        }
    }

    /// The field Word writes for `kind` to the bookmark `name`; `link` adds \h (Insert as hyperlink).
    public static func crossReferenceInstruction(_ kind: CrossReferenceKind, _ name: String, link: Bool) -> String {
        let h = link ? "\\h " : ""
        switch kind {
        case .page: return " PAGEREF \(name) \(h)"
        case .number: return " REF \(name) \\r \(h)"
        case .aboveBelow: return " REF \(name) \\p \(h)"
        case .note: return " NOTEREF \(name) \(h)"
        case .text, .labelNumber, .captionText: return " REF \(name) \(h)"
        }
    }

    /// Insert > Cross-reference: bookmark the item (a hidden `_Ref` bookmark, the bookmark itself for the Bookmark type)
    /// and put the field at the caret showing its result now. False, with nothing changed, where the reference has no
    /// result (a heading with no number). One undo step.
    @discardableResult
    public func insertCrossReference(_ type: CrossReferenceType, _ kind: CrossReferenceKind, _ item: CrossReferenceItem, link: Bool,
                                     pageOf: (Int) -> String?, pageCount: Int) -> Bool {
        guard !readOnly else { return false }
        var ok = false, made = false
        edit {
            let name: String
            if let own = item.bookmark {
                name = own
            } else {
                var a = item.start, b = item.end
                if kind == .labelNumber { b.offset = item.numberEnd }
                if kind == .captionText { a.offset = item.textStart }
                let had = bookmarkEntries().count
                name = _refBookmark(a, b)
                made = bookmarkEntries().count != had
            }
            let instr = Self.crossReferenceInstruction(kind, name, link: link)
            if hasSelection { _deleteSelectionOps() }
            let pos = document.clamped(selection.focus)
            guard let result = _fieldResult(instr, paragraph: pos.paragraph, offset: pos.offset, pageOf: pageOf, pageCount: pageCount),
                  !result.isEmpty else { return }
            let id = (document.paragraphs.flatMap { $0.runs }.map { $0.style.fieldResult }.max() ?? 0) + 1
            var style = typingStyle ?? document.paragraphs[pos.paragraph].style(at: pos.offset)
            style.preservedField = instr
            style.fieldResult = id
            style.field = nil; style.link = nil; style.note = nil; style.revision = nil
            perform(.insertText(pos, result, [Run(length: result.utf16.count, style: style)]))
            moveTo(RichPosition(paragraph: pos.paragraph, offset: pos.offset + result.utf16.count), extend: false)
            ok = true
        }
        // Nothing to show: the bookmark made for it is taken back too.
        if !ok, made { undo() }
        return ok
    }
}
