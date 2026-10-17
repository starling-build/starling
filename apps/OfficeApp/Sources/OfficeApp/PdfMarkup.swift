// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
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
        var isComment: Bool { label.hasPrefix("Commented") }
    }

    /// The document as printed: deleted text taken out.
    let document: RichDocument
    let notes: [Note]

    init(_ source: RichDocument) {
        var paragraphs: [RichParagraph] = []
        var deletions: [Note] = []
        // A deletion still open: its text so far, and where it stands.
        var open: Note? = nil
        func close() {
            if let note = open { deletions.append(note) }
            open = nil
        }
        var pending: RichParagraph? = nil   // a paragraph whose mark was deleted, to be joined to the next
        for var p in source.paragraphs {
            if var head = pending {
                // Its mark deleted, the paragraph runs on into the next:
                // the next's text after its own, in the next's look (Word
                // keeps a paragraph's look in its mark).
                if head.cell == p.cell, p.image == nil, head.image == nil {
                    let runs = (head.runs.isEmpty && !head.text.isEmpty ? [Run(length: head.text.utf16.count)] : head.runs)
                        + (p.runs.isEmpty && !p.text.isEmpty ? [Run(length: p.text.utf16.count)] : p.runs)
                    head.text += p.text
                    head.runs = runs
                    head.style = p.style
                    p = head
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
                    let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
                    let piece = String(p.text[at ..< end])
                    at = end
                    if run.style.revision?.kind == .deleted {
                        let anchor = RichPosition(paragraph: paragraphs.count, offset: text.utf16.count)
                        if open == nil || open!.anchor != anchor {
                            close()
                            open = Note(anchor: anchor, label: "Deleted:", paragraphs: [""], author: run.style.revision?.author ?? "",
                                        family: run.style.fontFamily.map(OfficeFonts.substitute)
                                            ?? source.styles.resolve(p.style)?.char.fontFamily.map(OfficeFonts.substitute))
                        }
                        open!.paragraphs[open!.paragraphs.count - 1] += piece
                    } else {
                        if !piece.isEmpty { close() }
                        text += piece
                        runs.append(run)
                    }
                }
                p.text = text
                p.runs = runs.isEmpty ? [Run(length: 0, style: p.runs.first?.style ?? CharStyle())] : runs
            }
            if p.style.markRevision?.kind == .deleted {
                // (Its mark goes into the balloon too, as Word writes it: ¶.)
                if open != nil { open!.paragraphs[open!.paragraphs.count - 1] += "¶" }
                else if p.text.isEmpty {
                    open = Note(anchor: RichPosition(paragraph: paragraphs.count, offset: 0), label: "Deleted:", paragraphs: ["¶"],
                                author: p.style.markRevision?.author ?? "")
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
        notes = (deletions + PdfMarkup._comments(printed) + PdfMarkup._formats(printed)).sorted { $0.anchor < $1.anchor }
    }

    /// The formatting changes: a balloon for each stretch of runs whose
    /// look was changed the same way, saying how, as Word says it —
    /// "Formatted: English (US)", "Formatted: Font color: Auto".
    private static func _formats(_ document: RichDocument) -> [Note] {
        var out: [Note] = []
        for (i, p) in document.paragraphs.enumerated() {
            var at = 0
            var last: (text: String, end: Int)? = nil
            for run in p.runs {
                defer { at += run.length }
                guard run.length > 0, let change = run.style.formatChange, run.style.revision?.kind != .deleted else { last = nil; continue }
                let text = _describe(run.style, was: change.oldRPrXML)
                guard !text.isEmpty else { last = nil; continue }
                if let l = last, l.text == text, l.end == at { last = (text, at + run.length); continue }
                out.append(Note(anchor: RichPosition(paragraph: i, offset: at), label: "Formatted:", paragraphs: [text], author: change.author))
                last = (text, at + run.length)
            }
        }
        return out
    }

    /// What a run's look is now that it was not, in Word's words.
    static func _describe(_ style: CharStyle, was old: String) -> String {
        func attribute(_ xml: String, _ element: String, _ name: String = "w:val") -> String? {
            guard let r = xml.range(of: "<\(element) ") ?? xml.range(of: "<\(element)/") else { return nil }
            let tail = xml[r.upperBound...]
            guard let end = tail.firstIndex(of: ">") else { return nil }
            let tag = String(tail[..<end])
            guard let a = tag.range(of: name + "=\"") else { return "" }
            return String(tag[a.upperBound...].prefix { $0 != "\"" })
        }
        var font: [String] = []
        var rest: [String] = []
        let oldBold = attribute(old, "w:b").map { $0 != "0" && $0 != "false" } ?? false
        if style.bold != oldBold { font.append(style.bold ? "Bold" : "Not Bold") }
        let oldItalic = attribute(old, "w:i").map { $0 != "0" && $0 != "false" } ?? false
        if style.italic != oldItalic { font.append(style.italic ? "Italic" : "Not Italic") }
        if let was = attribute(old, "w:color"), !was.isEmpty, style.color == nil { rest.append("Font color: Auto") }
        let now = attribute(style.keptXML ?? "", "w:lang")
        let then = attribute(old, "w:lang")
        if let now, !now.isEmpty, now != then { rest.append(_language(now)) }
        return (font.isEmpty ? [] : ["Font: " + font.joined(separator: ", ")]).joined() + (font.isEmpty || rest.isEmpty ? "" : ", ") + rest.joined(separator: ", ")
    }

    /// A language tag as Word names it.
    private static func _language(_ tag: String) -> String {
        let names = ["en-US": "English (US)", "en-GB": "English (UK)", "en-AU": "English (Australia)", "en-CA": "English (Canada)",
                     "ru-RU": "Russian", "de-DE": "German", "fr-FR": "French", "es-ES": "Spanish", "it-IT": "Italian",
                     "uk-UA": "Ukrainian", "zh-CN": "Chinese (PRC)", "zh-TW": "Chinese (Taiwan)", "ja-JP": "Japanese",
                     "ko-KR": "Korean", "pt-BR": "Portuguese (Brazil)", "pl-PL": "Polish", "nl-NL": "Dutch"]
        return names[tag] ?? tag
    }

    /// The comments, each anchored where its range starts, numbered in
    /// order through the document: "Commented [ab1]:" and its text.
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
        var seen: Set<String> = []
        var out: [Note] = []
        for (i, p) in document.paragraphs.enumerated() {
            var at = 0
            for run in p.runs {
                defer { at += run.length }
                for id in run.style.comments where !seen.contains(id) {
                    seen.insert(id)
                    guard let body = bodies[id] else { continue }
                    out.append(Note(anchor: RichPosition(paragraph: i, offset: at), label: "Commented [\(body.initials)\(out.count + 1)]:",
                                    paragraphs: body.paragraphs, author: body.author))
                }
            }
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
        let boxLeft = textRight + 32.1, boxRight = textRight + 262.4, inset = 4.5
        var authors: [String] = []
        for n in notes where !authors.contains(n.author) { authors.append(n.author) }
        var floor = -Double.infinity
        let balloon: (family: String, size: Double) = {
            guard let style = document.styles.styles.first(where: { $0.name.lowercased() == "balloon text" }) else {
                return (OfficeFonts.substitute("Tahoma"), 8)
            }
            return (OfficeFonts.substitute(style.char.fontFamily ?? "Tahoma"), style.char.fontSize ?? 8)
        }()
        for note in notes {
            let caret = layout.caretRect(note.anchor, document)
            guard let rect = layout.canvasRects(caret).first, layout.page(atCanvasY: rect.top) == p else { continue }
            let anchor = Rect.fromLTWH(rect.left / px, (rect.top - page.top) / px, rect.width / px, rect.height / px)
            // The balloon's text: its label in bold, then its paragraphs.
            // (A change's balloon in the document's Balloon Text, else in
            // Word's own, Tahoma 8pt — delins's "Formatted:" balloons from
            // Windows stand 15.1pt apart, 58067's Lucida Grande 9pt. Its
            // deleted text in its own face at that size. A comment's in a
            // serif at 9pt, as the prints from the Mac have them.)
            let family = note.isComment ? OfficeFonts.serif : balloon.family
            let size = note.isComment ? 9 : balloon.size
            let plain = TextStyle(color: Color(0xFF000000), fontSize: size, fontFamily: note.family ?? family)
            let bold = TextStyle(color: Color(0xFF000000), fontSize: size, fontWeight: .bold, fontFamily: family)
            var spans: [InlineSpan] = [TextSpan(text: note.label + " ", style: bold)]
            spans.append(TextSpan(text: note.paragraphs.joined(separator: "\n"), style: plain))
            let tp = TextPainter(text: TextSpan(children: spans), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: boxRight - boxLeft - 2 * inset)
            defer { tp.dispose() }
            let top = max(anchor.top, floor)
            let box = Rect.fromLTRB(boxLeft, top, boxRight, top + tp.height + 2 * 2.7)
            floor = box.bottom + 2
            let colour = PdfMarkup.colours[(authors.firstIndex(of: note.author) ?? 0) % PdfMarkup.colours.count]
            let fill = Paint()
            fill.color = Color(note.label.hasPrefix("Commented") ? colour.fill : 0xFFFFFFFF)
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
            canvas.drawLine(Offset(anchor.left, under), Offset(textRight + 9.1, under), line)
            canvas.drawLine(Offset(textRight + 9.1, under), Offset(boxLeft, top + 5.5), line)
            tp.paint(canvas, Offset(boxLeft + inset, top + 2.7))
        }
    }
}
