// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// A document printed with its markup, as Word prints one that carries
/// comments or tracked changes: the page drawn smaller beside a markup
/// pane (`PdfExport.MarkupFrame`), each comment and each deletion in a
/// balloon there, level with the line it stands on. Deleted text leaves
/// the page for its balloon, as in Word's balloons view.
struct PdfMarkup {
    /// One balloon: where in the printed document it is anchored, what it
    /// says (a bold label, then its text a paragraph a line), and whose.
    struct Note {
        var anchor: RichPosition
        var label: String
        var paragraphs: [String]
        var author: String
        /// The face its text is set in (a deletion's, its own); nil for
        /// the balloons' own.
        var family: String? = nil
        /// The deleted paragraph's own side indents (points): Word for Windows
        /// sets its balloon text in from them, at a quarter (lab ctdel).
        var indentLeft = 0.0
        var indentRight = 0.0
        var isComment: Bool { label.hasPrefix("Commented") }
    }

    /// The document as printed: deleted text taken out.
    let document: RichDocument
    let notes: [Note]

    init(_ source: RichDocument) {
        var paragraphs: [RichParagraph] = []
        var deletions: [Note] = []
        // What Word marks of text gone with no balloon of its own: where
        // moved text went, all of it then deleted, and how the text moved
        // away had been reformatted (Tika-792's "Moved (insertion) [1]"
        // and "Formatted: Font color: Auto").
        var places: [Note] = []
        var gone: [Note] = []
        // A deletion still open: its text so far, and where it stands.
        var open: Note? = nil
        func close() {
            if var note = open {
                // (A deleted mark ends its line in the balloon; nothing after it.)
                if note.paragraphs.count > 1, note.paragraphs.last == "" { note.paragraphs.removeLast() }
                deletions.append(note)
            }
            open = nil
        }
        var pending: RichParagraph? = nil   // a paragraph whose mark was deleted, to be joined to the next
        // A table moved away whole (TC-table-DnD-move): one balloon, "Moved
        // down [1]: A1", for the whole of it, and one empty line where it
        // stood.
        var movedTable: String? = nil
        for (srcIndex, var p) in source.paragraphs.enumerated() {
            if let c = p.cell, let mark = p.style.markRevision, mark.kind == .deleted, mark.moved, !mark.nested,
               p.runs.allSatisfy({ $0.length == 0 || ($0.style.revision?.kind == .deleted && $0.style.revision?.moved == true && $0.style.revision?.nested != true) }) {
                if movedTable != c.table {
                    movedTable = c.table
                    close()
                    if let head = pending { paragraphs.append(head); pending = nil }
                    deletions.append(Note(anchor: RichPosition(paragraph: paragraphs.count, offset: 0), label: "Moved:", paragraphs: [p.text],
                                          author: mark.author))
                }
                // (Its rows are laid out as ordinary Normal paragraphs, not as
                // the table's cell paragraphs: 23 pt each at Calibri 11
                // whatever the moved table's text, in Word's print.)
                var empty = p
                empty.text = ""
                let normal = source.styles[RichNamedStyle.normalId]
                if let n = normal?.paragraph {
                    empty.style.spaceAfter = n.spaceAfter
                    empty.style.spaceAfterAuto = n.spaceAfterAuto
                    empty.style.lineSpacing = n.lineSpacing
                }
                empty.style.markRevision = nil
                empty.runs = [Run(length: 0, style: normal?.char ?? CharStyle())]
                paragraphs.append(empty)
                continue
            }
            // Where this paragraph's own text begins (after a joined head's).
            var own = 0
            if var head = pending {
                // Its mark deleted, the paragraph runs on into the next:
                // the next's text after its own, in the next's look (Word
                // keeps a paragraph's look in its mark).
                // (Not the document's first, empty, into an empty section end:
                // that mark stays its own, tdf120336's deleted first mark on
                // page 1 of two; a run of them in n830205 joins as it did.)
                if head.cell == p.cell, p.image == nil, head.image == nil,
                   !(paragraphs.isEmpty && p.style.sectionXML != nil && p.text.isEmpty && head.text.isEmpty) {
                    let runs = (head.runs.isEmpty && !head.text.isEmpty ? [Run(length: head.text.utf16.count)] : head.runs)
                        + (p.runs.isEmpty && !p.text.isEmpty ? [Run(length: p.text.utf16.count)] : p.runs)
                    own = head.text.utf16.count
                    head.text += p.text
                    head.runs = runs
                    head.style = p.style
                    p = head
                } else if head.cell != nil, head.text.isEmpty, head.image == nil {
                    // (A deleted table's cells, each emptied: no rows left to
                    // lay out, n830205's page 2.)
                } else {
                    paragraphs.append(head)
                }
                pending = nil
            }
            // The paragraph's deleted runs: out of its text, into a balloon
            // anchored where they stood.
            if p.runs.contains(where: { $0.style.revision?.kind == .deleted }) {
                var text = ""
                var runs: [Run] = []
                var at = p.text.utf16.startIndex
                for run in p.runs {
                    let start = p.text.utf16.distance(from: p.text.utf16.startIndex, to: at)
                    let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
                    var piece = String(p.text[at ..< end])
                    at = end
                    if let r = run.style.revision, r.kind == .deleted, r.moved, r.nested {
                        if let change = run.style.formatChange, case let said = PdfMarkup._describe(run.style, was: change.oldRPrXML), !said.isEmpty {
                            gone.append(Note(anchor: RichPosition(paragraph: paragraphs.count, offset: text.utf16.count), label: "Formatted:",
                                             paragraphs: [said], author: change.author))
                        }
                        continue
                    }
                    if run.style.revision?.kind == .deleted {
                        let anchor = RichPosition(paragraph: paragraphs.count, offset: text.utf16.count)
                        if run.style.revision?.nested == true, places.last?.anchor != anchor {
                            places.append(Note(anchor: anchor, label: "Moved (insertion)", paragraphs: [""], author: run.style.revision?.author ?? ""))
                        }
                        let label = run.style.revision?.moved == true ? "Moved:" : "Deleted:"
                        if open == nil || open!.anchor != anchor || open!.label != label {
                            close()
                            open = Note(anchor: anchor, label: label, paragraphs: [""], author: run.style.revision?.author ?? "",
                                        family: (run.style.fontFamily ?? source.styles.resolve(p.style)?.char.fontFamily
                                            ?? source.styles[RichNamedStyle.normalId]?.char.fontFamily).map(OfficeFonts.drawn))
                            open!.indentLeft = p.style.indentLeft
                            open!.indentRight = p.style.indentRight
                        }
                        // A list item deleted with its mark loses its number
                        // too, which Word writes "<#>" (delins's tika items).
                        if start == own, run.length > 0, p.style.list != nil, p.style.markRevision?.kind == .deleted { piece = "<#>" + piece }
                        open!.paragraphs[open!.paragraphs.count - 1] += piece
                    } else {
                        // (Text of a joined head's own, before the deletion that
                        // went on from its mark, parts nothing: the balloon runs on
                        // from "def¶" into the next paragraph's "ghi", merge_hidden_redline.)
                        if !piece.isEmpty, start >= own { close() }
                        text += piece
                        runs.append(run)
                    }
                }
                p.text = text
                p.runs = runs.isEmpty ? [Run(length: 0, style: p.runs.first?.style ?? CharStyle())] : runs
            }
            if p.style.markRevision?.kind == .deleted {
                // (Its mark goes into the balloon too, as Word writes it: ¶,
                // and the next deleted paragraph starts a line of its own.)
                if p.style.sectionXML != nil, p.text.isEmpty, case let said = PdfMarkup._sectionBreak(source.paragraphs, after: srcIndex) {
                    // A deleted section break is drawn as itself, a rule round
                    // its name, on a line of its own in the balloon (n830205's
                    // "Deleted: Section Break (Continuous)").
                    if open == nil {
                        // (Where the mark stands: at the end of the line before it.)
                        let before = max(0, paragraphs.count - 1)
                        open = Note(anchor: RichPosition(paragraph: before, offset: paragraphs.last?.text.utf16.count ?? 0), label: "Deleted:", paragraphs: [said, ""],
                                    author: p.style.markRevision?.author ?? "")
                    } else {
                        if open!.paragraphs[open!.paragraphs.count - 1].isEmpty { open!.paragraphs[open!.paragraphs.count - 1] = said }
                        else { open!.paragraphs.append(said) }
                        open!.paragraphs.append("")
                    }
                }
                else if open != nil { open!.paragraphs[open!.paragraphs.count - 1] += "¶"; open!.paragraphs.append("") }
                else if p.text.isEmpty {
                    open = Note(anchor: RichPosition(paragraph: paragraphs.count, offset: 0), label: "Deleted:", paragraphs: ["¶"],
                                author: p.style.markRevision?.author ?? "")
                    open!.indentLeft = p.style.indentLeft
                    open!.indentRight = p.style.indentRight
                } else if p.style.frame != nil || !p.runs.contains(where: { $0.style.revision?.kind == .inserted }) {
                    // (A framed paragraph's mark cannot run into the next: its
                    // own "Deleted: ¶", tdf125894's third. Nor does the mark of a
                    // paragraph with text and no deletion in it: its own
                    // "Deleted: ¶" at the end of the line, merge_hidden_redline's 8 and 10; but
                    // not where the text is itself an insertion, n830205's 2.x.)
                    RuleTrace.hit("deleted-mark-own-balloon")
                    deletions.append(Note(anchor: RichPosition(paragraph: paragraphs.count, offset: p.text.utf16.count), label: "Deleted:",
                                          paragraphs: ["¶"], author: p.style.markRevision?.author ?? ""))
                }
                pending = p
                continue
            }
            if !p.text.isEmpty { close() }
            paragraphs.append(p)
        }
        if let head = pending { paragraphs.append(head) }
        close()
        var printed = source
        printed.paragraphs = paragraphs
        // (Deletions anchored past the text's end stand at its last paragraph.)
        let last = max(0, paragraphs.count - 1)
        deletions = deletions.map { var n = $0; if n.anchor.paragraph > last { n.anchor = RichPosition(paragraph: last, offset: 0) }; return n }
        document = printed
        // (By anchor, and in the order made where two share one: a
        // field's "Field Code Changed" before its result's "Formatted".)
        // (A move's new place before a deletion at the same spot, as
        // Tika-792's stand.)
        let tos = PdfMarkup._insertedMoves(printed)
        let made = PdfMarkup._moves(tos + places.filter { p in !tos.contains { $0.anchor == p.anchor } } + deletions)
            + PdfMarkup._comments(printed) + PdfMarkup._formats(printed) + gone
        // (Within one line of the page — a paragraph, or a table row — Word
        // stacks the balloons of text taken out before the ones for text
        // reformatted: n830205's "Deleted" pair before its "Formatted", and
        // tdf123001's "Deleted", "Deleted Cells", then "Formatted: Right: 0"".)
        var rowStart: [Int] = []
        for (i, p) in printed.paragraphs.enumerated() {
            if i > 0, let c = p.cell, let b = printed.paragraphs[i - 1].cell, b.table == c.table, b.row == c.row { rowStart.append(rowStart[i - 1]) }
            else { rowStart.append(i) }
        }
        func line(_ n: Note) -> Int { n.anchor.paragraph < rowStart.count ? rowStart[n.anchor.paragraph] : n.anchor.paragraph }
        // (A comment's balloon before a deletion's, whichever comes first in
        // the text: lab bal 08 and 09, Word for Windows.)
        func rank(_ n: Note) -> Int { n.label == "Formatted:" || n.label == "Field Code Changed" ? 2 : n.isComment ? 0 : 1 }
        notes = made.enumerated()
            .sorted { a, b in
                let ka = (line(a.element), rank(a.element), a.element.anchor, a.offset), kb = (line(b.element), rank(b.element), b.element.anchor, b.offset)
                return ka < kb
            }.map(\.element)
    }

    /// What Word calls the section break that ends the section at `index`: by
    /// how the next section starts (its `w:type`; a next page where it
    /// states none, or where no section follows).
    private static func _sectionBreak(_ paragraphs: [RichParagraph], after index: Int) -> String {
        let kinds = ["continuous": "Continuous", "evenPage": "Even Page", "oddPage": "Odd Page", "nextColumn": "Column"]
        if let next = paragraphs[(index + 1)...].first(where: { $0.style.sectionXML != nil }), let xml = next.style.sectionXML {
            for (key, name) in kinds where xml.containsSubstring("w:type w:val=\"\(key)\"") { return "Section Break (\(name))" }
        }
        return "Section Break (Next Page)"
    }

    /// Where moved text went: "Moved (insertion) [n]" at the start of each
    /// stretch of it, as Word labels the new place.
    private static func _insertedMoves(_ document: RichDocument) -> [Note] {
        var out: [Note] = []
        // (A moved table's cells are one move: its balloon stands once,
        // at its first.)
        var inMove = false
        var table: String? = nil
        for (i, p) in document.paragraphs.enumerated() {
            var at = 0
            if p.cell == nil || p.cell?.table != table { inMove = false }
            table = p.cell?.table
            for run in p.runs {
                defer { at += run.length }
                let moved = run.length > 0 && run.style.revision?.moved == true && run.style.revision?.kind == .inserted
                if moved, !inMove {
                    out.append(Note(anchor: RichPosition(paragraph: i, offset: at), label: "Moved (insertion)", paragraphs: [""],
                                    author: run.style.revision?.author ?? ""))
                }
                // (An insertion inside the moved range does not end it: Word
                // gives "Moved (insertion) [1]" once for tdf104797's "Will this
                // sentence be duplicated" and "?" with " ADDED STUFF" between.)
                let inserted = run.length > 0 && !moved && run.style.revision?.kind == .inserted && run.style.revision?.moved != true
                if run.length > 0, !inserted { inMove = moved }
            }
        }
        return out
    }

    /// Moves numbered in order, each pair's ends the same number: the
    /// new place "Moved (insertion) [n]", the old "Moved up [n]:" or
    /// "Moved down [n]:" with its text, as Word words them.
    private static func _moves(_ notes: [Note]) -> [Note] {
        let tos = notes.filter { $0.label == "Moved (insertion)" }.sorted { $0.anchor < $1.anchor }
        let froms = notes.filter { $0.label == "Moved:" }.sorted { $0.anchor < $1.anchor }
        return notes.map { note in
            var n = note
            if let k = tos.firstIndex(where: { $0.anchor == note.anchor && $0.label == note.label }) {
                n.label = "Moved (insertion) [\(k + 1)]"
            } else if let k = froms.firstIndex(where: { $0.anchor == note.anchor && $0.label == note.label }) {
                let up = k < tos.count && tos[k].anchor < note.anchor
                n.label = "Moved \(up ? "up" : "down") [\(k + 1)]:"
            }
            return n
        }
    }

    /// The formatting changes: a balloon for each stretch of runs whose
    /// look was changed the same way, saying how, as Word says it —
    /// "Formatted: English (US)", "Formatted: Font color: Auto". A field's
    /// start or end breaks a stretch (a link's text and the words after it
    /// are two); a reformatted paragraph mark joins the stretch it ends
    /// and the next paragraph's, as Word's delins joins three headings'.
    private static func _formats(_ document: RichDocument) -> [Note] {
        var out: [Note] = []
        // The stretch still open: what it says, and the field it is in.
        var last: (text: String, field: Int)? = nil
        // (A field whose code was reformatted: "Field Code Changed" where
        // its result ends, after the result's own "Formatted" and the next
        // words' — delins's link items in Word for Windows' print stack
        // "Formatted", "Formatted", "Field Code Changed", and an item
        // whose words after the link were not reformatted has its field's
        // balloon before the next item's.)
        var codeChanged: (field: Int, author: String)? = nil
        var cellsSeen: Set<String> = []
        var paragraphLast: String? = nil
        // (A run of paragraph marks reformatted alike is one balloon, at the last of
        // them: lo n830205 in Word for Windows' print — four headings each reformatted
        // in their words and in their marks say "Font: 9 pt" once, under the four.)
        var markNote: (index: Int, paragraph: Int, text: String)? = nil
        for (i, p) in document.paragraphs.enumerated() {
            // (A cell deleted with its row's tracked change: one "Deleted
            // Cells" for the cell, at its first paragraph — tdf123001's.)
            if let c = p.cell, let rev = c.revision, rev.kind == .deleted, cellsSeen.insert("\(c.table)/\(c.row)/\(c.column)").inserted {
                out.append(Note(anchor: RichPosition(paragraph: i, offset: 0), label: "Deleted Cells", paragraphs: [""], author: rev.author))
            }
            // (A paragraph whose indents or alignment were changed: a
            // balloon for the stretch of paragraphs changed alike, "Formatted:
            // Centered", "Formatted: Right: 0\"".)
            if let change = p.style.propertyChange {
                let said = Self._describe(paragraph: p.style, was: change.oldRPrXML)
                if said.isEmpty { paragraphLast = nil } else if paragraphLast != said {
                    out.append(Note(anchor: RichPosition(paragraph: i, offset: 0), label: "Formatted:", paragraphs: [said], author: change.author))
                    paragraphLast = said
                }
            } else { paragraphLast = nil }
            // (A result that runs to its paragraph's end ends there.)
            defer {
                if let c = codeChanged {
                    out.append(Note(anchor: RichPosition(paragraph: i, offset: p.text.utf16.count), label: "Field Code Changed", paragraphs: [""], author: c.author))
                    codeChanged = nil
                }
            }
            var at = 0
            // (An empty run, an empty paragraph's, breaks nothing.)
            for run in p.runs where run.length > 0 {
                defer { at += run.length }
                var ended: String? = nil
                if let c = codeChanged, run.style.fieldResult != c.field { ended = c.author; codeChanged = nil }
                defer {
                    if let ended { out.append(Note(anchor: RichPosition(paragraph: i, offset: at), label: "Field Code Changed", paragraphs: [""], author: ended)) }
                }
                if run.style.fieldCodeChanged, run.style.revision?.kind != .deleted {
                    codeChanged = (run.style.fieldResult, run.style.formatChange?.author ?? "")
                    last = nil
                }
                guard let change = run.style.formatChange, run.style.revision?.kind != .deleted else { last = nil; continue }
                let text = _describe(run.style, was: change.oldRPrXML)
                guard !text.isEmpty else { last = nil; continue }
                let field = run.style.fieldResult
                if let l = last, l.text == text, l.field == field { continue }
                out.append(Note(anchor: RichPosition(paragraph: i, offset: at), label: "Formatted:", paragraphs: [text], author: change.author))
                last = (text, field)
            }
            guard let mark = p.style.mark, let change = mark.formatChange, p.style.markRevision?.kind != .deleted else { last = nil; continue }
            let text = _describe(mark, was: change.oldRPrXML)
            guard !text.isEmpty else { last = nil; continue }
            if let l = last, l.text == text, l.field == 0 { continue }
            if let m = markNote, m.paragraph == i - 1, m.text == text {
                out[m.index].anchor = RichPosition(paragraph: i, offset: p.text.utf16.count)
                markNote = (m.index, i, text)
                last = (text, 0)
                continue
            }
            markNote = (out.count, i, text)
            out.append(Note(anchor: RichPosition(paragraph: i, offset: p.text.utf16.count), label: "Formatted:", paragraphs: [text],
                            author: change.author))
            last = (text, 0)
        }
        return out
    }

    /// What a paragraph's alignment and side indents are now that they were
    /// not, in Word's words (inches, two places: `Right: 0"`).
    static func _describe(paragraph style: RichParagraphStyle, was old: String) -> String {
        func attribute(_ element: String, _ name: String) -> String? {
            guard let r = old.rangeOfSubstring("<\(element) ") ?? old.rangeOfSubstring("<\(element)/") else { return nil }
            let tail = old[r.upperBound...]
            guard let end = tail.firstIndex(of: ">") else { return nil }
            let tag = String(tail[..<end])
            guard let a = tag.rangeOfSubstring(name + "=\"") else { return nil }
            return String(tag[a.upperBound...].prefix { $0 != "\"" })
        }
        func inches(_ points: Double) -> String {
            let v = (points / 72 * 100).rounded() / 100
            return (v == v.rounded() ? String(Int(v)) : String(v)) + "\""
        }
        var said: [String] = []
        let oldAlign: ParagraphAlignment = {
            switch attribute("w:jc", "w:val") {
            case "center": return .center
            case "right", "end": return .right
            case "both", "distribute": return .justify
            default: return .left
            }
        }()
        if style.alignment != oldAlign {
            switch style.alignment {
            case .center: said.append("Centered")
            case .right: said.append("Right")
            case .justify: said.append("Justified")
            default: said.append("Left")
            }
        }
        func twips(_ names: [String]) -> Double {
            for n in names { if let v = attribute("w:ind", n).flatMap({ Double($0) }) { return v / 20 } }
            return 0
        }
        let oldLeft = twips(["w:left", "w:start"]), oldRight = twips(["w:right", "w:end"])
        if abs(style.indentLeft - oldLeft) > 0.01 { said.append("Left: " + inches(style.indentLeft)) }
        if abs(style.indentRight - oldRight) > 0.01 { said.append("Right: " + inches(style.indentRight)) }
        return said.joined(separator: ", ")
    }

    /// What a run's look is now that it was not, in Word's words.
    static func _describe(_ style: CharStyle, was old: String) -> String {
        func attribute(_ xml: String, _ element: String, _ name: String = "w:val") -> String? {
            guard let r = xml.rangeOfSubstring("<\(element) ") ?? xml.rangeOfSubstring("<\(element)/") else { return nil }
            let tail = xml[r.upperBound...]
            guard let end = tail.firstIndex(of: ">") else { return nil }
            let tag = String(tail[..<end])
            guard let a = tag.rangeOfSubstring(name + "=\"") else { return "" }
            return String(tag[a.upperBound...].prefix { $0 != "\"" })
        }
        var font: [String] = []
        var rest: [String] = []
        // (The face when it is not the one it was — "(Default) Arial", as Word
        // words it — before the style words, then the size and the highlight:
        // n830205's "Font: (Default) Arial, 9 pt" and "Font: 9 pt, Highlight".)
        let oldFace = attribute(old, "w:rFonts", "w:ascii")
        if let face = style.fontFamily, !face.isEmpty, face != oldFace { font.append("(Default) " + face) }
        let oldBold = attribute(old, "w:b").map { $0 != "0" && $0 != "false" } ?? false
        if style.bold != oldBold { font.append(style.bold ? "Bold" : "Not Bold") }
        let oldItalic = attribute(old, "w:i").map { $0 != "0" && $0 != "false" } ?? false
        if style.italic != oldItalic { font.append(style.italic ? "Italic" : "Not Italic") }
        if let size = style.fontSize, attribute(old, "w:sz").flatMap({ Double($0) }).map({ $0 / 2 != size }) ?? true {
            font.append((size == size.rounded() ? String(Int(size)) : String(size)) + " pt")
        }
        if style.highlight != nil, attribute(old, "w:highlight") == nil { font.append("Highlight") }
        if let was = attribute(old, "w:color"), !was.isEmpty, style.color == nil { rest.append("Font color: Auto") }
        let now = attribute(style.keptXML ?? "", "w:lang")
        let then = attribute(old, "w:lang")
        // (Both an Asian and a Latin language changed: Word names each, as
        // ins-then-format-self's "(Asian) Chinese (Simplified, Mainland
        // China), (Other) French (France)"; one alone stands bare.)
        let nowAsian = attribute(style.keptXML ?? "", "w:lang", "w:eastAsia")
        let thenAsian = attribute(old, "w:lang", "w:eastAsia")
        let asianChanged = nowAsian.map { !$0.isEmpty && $0 != thenAsian } ?? false
        let latinChanged = now.map { !$0.isEmpty && $0 != then } ?? false
        if asianChanged, latinChanged, let nowAsian, let now {
            rest.append("(Asian) " + _language(nowAsian) + ", (Other) " + _language(now))
        } else if latinChanged, let now { rest.append(_language(now)) }
        return (font.isEmpty ? [] : ["Font: " + font.joined(separator: ", ")]).joined() + (font.isEmpty || rest.isEmpty ? "" : ", ") + rest.joined(separator: ", ")
    }

    /// A language tag as Word names it.
    private static func _language(_ tag: String) -> String {
        let names = ["en-US": "English (US)", "en-GB": "English (UK)", "en-AU": "English (Australia)", "en-CA": "English (Canada)",
                     "ru-RU": "Russian", "de-DE": "German", "fr-FR": "French", "es-ES": "Spanish", "it-IT": "Italian",
                     "uk-UA": "Ukrainian", "zh-CN": "Chinese (PRC)", "zh-TW": "Chinese (Taiwan)", "ja-JP": "Japanese",
                     "ko-KR": "Korean", "pt-BR": "Portuguese (Brazil)", "pl-PL": "Polish", "nl-NL": "Dutch"]
        // (Word for Windows spells the country out: delins's twenty-three
        // "Formatted: English (United States)" in word-win.)
        if DocxFormat.wordOnWindows, tag == "en-US" { return "English (United States)" }
        if DocxFormat.wordOnWindows, let full = ["fr-FR": "French (France)", "de-DE": "German (Germany)", "en-GB": "English (United Kingdom)",
                                                  "zh-CN": "Chinese (Simplified, Mainland China)", "zh-TW": "Chinese (Traditional, Taiwan)"][tag] { return full }
        return names[tag] ?? tag
    }

    /// The comments, numbered in order through the document —
    /// "Commented [ab1]:" and its text — each anchored where its range
    /// ends, by its reference: WordWithAttachments' comments over whole
    /// quatrains stand level with their last lines in Word's print.
    /// The comments Word for Windows prints no balloon for: one that covers
    /// no text (no range, or an empty one) standing at the very start of
    /// the document. Lab na (Word for Windows, comment.docx's package):
    /// its reference there — alone in the first paragraph, before text, or
    /// with an empty range — prints nothing, and comment.docx, with nothing
    /// else marked, prints no pane; after any text, a space or an empty
    /// paragraph it has its balloon, as has a range from the start with
    /// text in it. (Word for Mac's print of comment.docx has the balloon.)
    static func silentComments(_ document: RichDocument) -> Set<String> {
        guard DocxFormat.wordOnWindows, let first = document.paragraphs.first else { return [] }
        let units = Array(first.text.utf16)
        var at = 0, silent: Set<String> = []
        for run in first.runs {
            let piece = units[min(at, units.count) ..< min(at + run.length, units.count)]
            if piece.contains(where: { $0 != 0x200B }) { break }
            silent.formUnion(run.style.comments)
            at += run.length
        }
        guard !silent.isEmpty else { return [] }
        // (Only one with no text of its own anywhere.)
        for p in document.paragraphs {
            let units = Array(p.text.utf16)
            var at = 0
            for run in p.runs {
                defer { at += run.length }
                if run.style.comments.contains(where: { silent.contains($0) }),
                   units[min(at, units.count) ..< min(at + run.length, units.count)].contains(where: { $0 != 0x200B }) {
                    silent.subtract(run.style.comments)
                }
            }
        }
        return silent
    }

    private static func _comments(_ document: RichDocument) -> [Note] {
        guard let data = document.keptParts["word/comments.xml"], let root = XNode.parse(data) else { return [] }
        var bodies: [String: (author: String, initials: String, paragraphs: [String])] = [:]
        for c in root.all("w:comment") {
            guard let id = c["w:id"] else { continue }
            var paragraphs: [String] = []
            var stack: [XNode] = c.children.reversed()
            while let n = stack.popLast() {
                if n.name == "w:p" {
                    var text = ""
                    var inner: [XNode] = n.children.reversed()
                    while let m = inner.popLast() {
                        if m.name == "w:t" { text += m.text } else if m.name == "w:tab" { text += "\t" }
                        else { inner.append(contentsOf: m.children.reversed()) }
                    }
                    paragraphs.append(text)
                } else {
                    stack.append(contentsOf: n.children.reversed())
                }
            }
            bodies[id] = (c["w:author"] ?? "", c["w:initials"] ?? "", paragraphs.isEmpty ? [""] : paragraphs)
        }
        // (In the order the ranges start; each one's end, the last run it covers.)
        var order: [String] = []
        var ends: [String: RichPosition] = [:]
        for (i, p) in document.paragraphs.enumerated() {
            var at = 0
            for run in p.runs {
                defer { at += run.length }
                for id in run.style.comments {
                    if ends[id] == nil { order.append(id) }
                    ends[id] = RichPosition(paragraph: i, offset: at + run.length)
                }
            }
        }
        // (Its text in Comment Text's face, else Normal's: WordWithAttachments'
        // in Times under Tahoma labels, testComment's in Calibri.)
        let face = (document.styles.styles.first { $0.name.lowercased() == "annotation text" }?.char.fontFamily
            ?? document.styles[RichNamedStyle.normalId]?.char.fontFamily).map(OfficeFonts.drawn)
        var out: [Note] = []
        let silent = silentComments(document)
        for id in order where !silent.contains(id) {
            guard let body = bodies[id], let end = ends[id] else { continue }
            out.append(Note(anchor: end, label: "Commented [\(body.initials)\(out.count + 1)]:", paragraphs: body.paragraphs, author: body.author,
                            family: face))
        }
        return out
    }

    /// Word's reviewer colours, a line and a fill each, by the order the
    /// authors first appear.
    private static let colours: [(line: Int64, fill: Int64)] = [
        (0xFFCC3595, 0xFFF7DDED), (0xFF49820A, 0xFFECFDD7), (0xFF6B5FD3, 0xFFDEDAFA), (0xFF2E74B5, 0xFFDEEAF6),
        (0xFFC55A11, 0xFFFBE4D5), (0xFF00838F, 0xFFD6F2F4), (0xFFB8860B, 0xFFFFF2CC), (0xFF7F7F7F, 0xFFEDEDED),
    ]

    /// The balloons of page `p`, painted in the page's own points (the
    /// markup frame's scale already set on `canvas`), stacked down the
    /// pane from their anchors' lines, each joined to its anchor.
    func paint(page p: Int, layout: RichLayout, setup: PageSetup, theme: RichTextTheme, zoom: Double, canvas: any Canvas) {
        let px = theme.pixelsPerPoint * zoom
        let page = layout.pageRect(p)
        let textRight = setup.width - setup.marginRight
        // (Word for Windows, lab bp: its boxes stand 31.5 to 261.8pt past
        // the text; the line from the anchor turns 4.6pt past the text and
        // meets the box 6pt under its top. Its lines are 2.2pt inside the
        // box top and foot, and a box stacked under another stands 1.1pt
        // clear of it: lab bh's nine stacked deletions, 1.07-1.21 apart,
        // 2.15-2.3 over and under their lines at 8, 10 and 14pt; word-win's
        // Tika-792, 16.2-16.5pt boxes of a Segoe UI 9pt line, 1.2 apart, and
        // delins, 13.8-13.9 boxes of a Tahoma 8pt line, 1.2-1.3 apart.
        // Word for Mac's: 32.1 to 262.4, 9.1 and 5.5, 2.7 and 2.7, edge
        // to edge.)
        let windows = DocxFormat.wordOnWindows
        let boxLeft = textRight + (windows ? 31.5 : 32.1), boxRight = textRight + (windows ? 261.8 : 262.4), inset = 4.5
        let padTop = windows ? 2.2 : 2.7, padBottom = windows ? 2.2 : 2.7, gap = windows ? 1.1 : 0
        let turn = textRight + (windows ? 4.6 : 9.1), meet = windows ? 6.0 : 5.5
        var authors: [String] = []
        for n in notes where !authors.contains(n.author) { authors.append(n.author) }
        let balloon: (family: String, size: Double, line: Double?) = {
            // (Word for Windows' own face is Segoe UI 9pt, its lines 1.33
            // ems, and it is what Word for Windows sets for a Balloon Text
            // in a Mac face it lacks: 58067's Lucida Grande, lab bp's no
            // style at all.)
            let segoe = (OfficeFonts.drawn("Segoe UI"), 9.0, Optional(1.33))
            guard let style = document.styles.styles.first(where: { $0.name.lowercased() == "balloon text" }) else {
                return windows ? segoe : (OfficeFonts.serif, 9, nil)
            }
            // (Its lines as high as Word's face has them, where that is
            // not its clone's: Tahoma's 1.207 ems, its ascent and descent
            // — delins's balloons stand 15.06pt apart, a 9.66pt line and
            // the padding, where the clone's line put them 15.75 apart.)
            let family = style.char.fontFamily ?? "Tahoma"
            if windows, family.trimmingWhitespace().lowercased() == "lucida grande" { return segoe }
            return (OfficeFonts.drawn(family), style.char.fontSize ?? 8,
                    family.trimmingWhitespace().lowercased() == "tahoma" ? 1.207 : nil)
        }()
        let plainEllipsis = TextStyle(color: Color(0xFF000000), fontSize: balloon.size, fontFamily: balloon.family)
        var entries: [(note: Note, anchor: Rect, tp: TextPainter, indent: Double, want: Double)] = []
        for note in notes {
            let caret = layout.caretRect(note.anchor, document)
            guard let rect = layout.canvasRects(caret).first, layout.page(atCanvasY: rect.top) == p else { continue }
            let anchor = Rect.fromLTWH(rect.left / px, (rect.top - page.top) / px, rect.width / px, rect.height / px)
            // The balloon's text: its label in bold, then its paragraphs.
            // (In the document's Balloon Text — delins's Tahoma 8pt,
            // 58067's Lucida Grande 9pt, testComment's 宋体 — else in Word
            // for Mac's own, Times 9pt: Tika-792's and comment's balloons.
            // Deleted text and a comment's in their own face at that size.)
            let family = balloon.family, size = balloon.size
            let lineHeight = note.family == nil ? balloon.line : nil
            let plain = TextStyle(color: Color(0xFF000000), fontSize: size, height: lineHeight, fontFamily: note.family ?? family)
            let bold = TextStyle(color: Color(0xFF000000), fontSize: size, fontWeight: .bold, height: lineHeight, fontFamily: family)
            var spans: [InlineSpan] = [TextSpan(text: note.label + " ", style: bold)]
            // (A deleted section break alone in its balloon stands on the
            // label's line, its name in smaller type: lab bal 02 and 04, Word
            // for Windows, "Deleted:" at 436.9 and "Section Break (Next
            // Page)" at 500.0, 6.1pt against the 6.8pt of the label.)
            if windows, note.label == "Deleted:", note.paragraphs.filter({ !$0.isEmpty }).count == 1,
               let said = note.paragraphs.first(where: { $0.hasPrefix("Section Break (") }) {
                RuleTrace.hit("deleted-section-break-stands-on-the-labels-line")
                let small = TextStyle(color: Color(0xFF000000), fontSize: size * 0.9, height: lineHeight, fontFamily: note.family ?? family)
                spans.append(TextSpan(text: said, style: small))
            } else if windows, note.label == "Deleted:", note.paragraphs.contains(where: { $0.hasPrefix("Section Break (") }) {
                // (After deleted text the name is a line of its own, set in
                // 48.8pt and smaller: lab bal 03, "Section Break (Next Page)"
                // at 485.7 under "Deleted: XXX¶" at 436.9.)
                RuleTrace.hit("deleted-section-break-after-text-is-a-small-indented-line")
                let small = TextStyle(color: Color(0xFF000000), fontSize: size * 0.9, height: lineHeight, fontFamily: note.family ?? family)
                var first = true
                for line in note.paragraphs where !(line.isEmpty && !first) {
                    if !first { spans.append(TextSpan(text: "\n", style: plain)) }
                    first = false
                    if line.hasPrefix("Section Break (") {
                        spans.append(TextSpan(text: String(repeating: "\u{2002}", count: 16) + line, style: small))
                    } else {
                        spans.append(TextSpan(text: line, style: plain))
                    }
                }
            } else {
                spans.append(TextSpan(text: note.paragraphs.joined(separator: "\n"), style: plain))
            }
            let tp = TextPainter(text: TextSpan(children: spans), textDirection: .ltr)
            tp.fractionalLineHeights = true
            // (A deletion's text stands 8.8pt further in: delins's "Deleted:"
            // lines start at 424.0 where its "Formatted:" ones do at 417.9,
            // scaled, and part where Word's do. Word for Windows indents only
            // deleted list items, delins's "<#>" ones: Tika-792's "Deleted:
            // s.", 58067's "Deleted: This is another Test.¶" and lab bp's
            // stand with the other balloons.)
            var indent = note.label == "Deleted:" && (!windows || note.paragraphs.contains { $0.hasPrefix("<#>") }) ? 8.8 : 0
            // (Word for Windows sets a deletion's text in from its paragraph's
            // own side indents, at a quarter of them: lab ctdel, one deleted
            // paragraph in twelve forms: left 864 twips moves the text 8.2pt
            // on the print, right 864 narrows the line, a style's the same as
            // direct, centring, a first-line indent, the kept mark and a
            // pPrChange nothing. LibreOffice's CT-formatted-deletion, in Quote.)
            var narrower = 0.0
            if windows, note.label == "Deleted:", note.indentLeft > 0 || note.indentRight > 0 {
                RuleTrace.hit("balloon-text-follows-the-deleted-paragraphs-indents")
                indent += max(0, note.indentLeft) / 4
                narrower = max(0, note.indentRight) / 4
            }
            tp.layout(minWidth: 0, maxWidth: boxRight - boxLeft - 2 * inset - indent - narrower)
            // (Whole paragraphs deleted stand a little above the line they
            // are anchored to: at most 6.27pt under the line before them.
            // Labs `dl` (Word 16, delins's package, "the subcommentaries"
            // above two deleted list items above "March 2009"): its box top
            // is 6.27 page-points under the line before whether the space
            // between is 10, 14 or 28pt, or the line it marks has 30pt
            // more over it — and at that line's top once it is nearer.)
            var want = anchor.top
            if note.label == "Deleted:", note.anchor.offset == 0, note.anchor.paragraph > 0,
               note.paragraphs.contains(where: { $0.hasSuffix("¶") }) {
                let above = document.paragraphs[note.anchor.paragraph - 1]
                let end = layout.caretRect(RichPosition(paragraph: note.anchor.paragraph - 1, offset: above.text.utf16.count), document)
                if let r = layout.canvasRects(end).first, layout.page(atCanvasY: r.top) == p {
                    want = min(want, (r.bottom - page.top) / px + 6.27)
                }
            }
            entries.append((note, anchor, tp, indent, want))
        }
        defer { for e in entries { e.tp.dispose() } }
        // Where each box stands: under its anchor and clear of the one before.
        // A column that would run off the page is packed up instead (Word's
        // n830205: the boxes ride above their lines, edge to edge) and, short
        // of room even so, its tallest box is cut short with a "..." at its foot.
        let limit = setup.height - setup.marginBottom + 6
        var heights = entries.map { $0.tp.height + padTop + padBottom }
        var tops: [Double] = []
        var f = -Double.infinity
        for (i, e) in entries.enumerated() {
            let t = max(e.want, f)
            tops.append(t)
            f = t + heights[i] + gap
        }
        var shown = entries.count
        var cut: Int? = nil
        if let lt = tops.last, lt + heights[heights.count - 1] > limit {
            // Packed from the first box down, edge to edge; the one that runs
            // past the page's foot is cut short and the rest are not shown.
            var g = tops[0]
            for i in 0 ..< entries.count {
                tops[i] = g
                if g + heights[i] > limit {
                    if limit - g > 24 { heights[i] = limit - g; cut = i; shown = i + 1 } else { shown = i }
                    break
                }
                g += heights[i] + gap
            }
        }
        for (i, e) in entries.enumerated() where i < shown {
            let note = e.note, anchor = e.anchor, tp = e.tp, indent = e.indent
            let top = tops[i]
            let box = Rect.fromLTRB(boxLeft, top, boxRight, top + heights[i])
            // (Stacked edge to edge: delins's one-line balloons stand
            // 15.1pt apart, an 8pt line and the padding.)
            let colour = PdfMarkup.colours[(authors.firstIndex(of: note.author) ?? 0) % PdfMarkup.colours.count]
            let fill = Paint()
            fill.color = Color(note.isComment ? colour.fill : 0xFFFFFFFF)
            canvas.drawRect(box, fill)
            let line = Paint()
            line.style = .stroke
            line.strokeWidth = 0.5
            line.color = Color(colour.line)
            canvas.drawRect(box, line)
            // Joined to its anchor: along under the anchor's line to the
            // pane, then up to the balloon.
            line.strokeWidth = 0.25
            let under = anchor.bottom
            canvas.drawLine(Offset(anchor.left, under), Offset(turn, under), line)
            canvas.drawLine(Offset(turn, under), Offset(boxLeft, top + meet), line)
            if cut == i {
                canvas.save()
                canvas.clipRect(box)
                tp.paint(canvas, Offset(boxLeft + inset + indent, top + padTop))
                canvas.restore()
                let more = TextPainter(text: TextSpan(text: "...", style: plainEllipsis), textDirection: .ltr)
                more.layout(minWidth: 0, maxWidth: 40)
                more.paint(canvas, Offset(boxRight - inset - more.width, box.bottom - padBottom - more.height))
                more.dispose()
            } else {
                tp.paint(canvas, Offset(boxLeft + inset + indent, top + padTop))
            }
        }
    }
}
