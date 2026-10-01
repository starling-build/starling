// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Notes (Excel's legacy comments) and threaded comments: shown, and kept
// pointing at their cells. A note lives in two parts — `commentsN.xml`
// (`<comment ref="B3">` and its text) and the sheet's VML drawing (the
// yellow box, placed by `<x:Row>`/`<x:Column>`); a threaded comment adds
// `threadedComments/…` (`<threadedComment ref="B3">`). When rows or
// columns move, every one of those references moves with its cell, and
// a note whose cell was deleted is removed from all three, as Excel does.
// Everything else in the parts is written back as it was.

import Flutter
import FlutterSwiftBridge
import Foundation

struct SheetNote: Equatable, Sendable {
    /// The cell the file put it on (nil for a note made here), and where
    /// that cell is now (nil once deleted).
    var origin: CellAddress?
    var at: CellAddress?
    var author: String
    /// The whole text, Excel's way: "Author:" then a line break, then the note.
    var text: String
    /// Its text was changed here.
    var edited = false
    /// A threaded comment's legacy copy (edited in Excel, not here).
    var threaded = false

    /// The note without Excel's "Author:" heading line.
    var body: String {
        let head = author + ":"
        if !author.isEmpty, text.hasPrefix(head) {
            var rest = text.dropFirst(head.count)
            if rest.hasPrefix("\n") { rest = rest.dropFirst() }
            return String(rest)
        }
        return text
    }
}

/// What saving one sheet's notes adds to the package.
struct NoteParts {
    var parts: [String: Data] = [:]
    var overrides: [(String, String)] = []
    /// The sheet's `<legacyDrawing>` when the notes' VML part is new.
    var element: String? = nil
}

/// The note parts of one sheet.
struct SheetNoteParts: Equatable, Sendable {
    var comments: String? = nil
    var vml: String? = nil
    var threaded: [String] = []
}

enum NotesXML {
    static func read(sheetPath: String, parts: [String: Data]) -> ([SheetNote], SheetNoteParts) {
        let dir = sheetPath.deletingLastPathComponent
        let rels = Xlsx._relList(parts[Xlsx._relsPath(sheetPath)])
        var p = SheetNoteParts()
        for r in rels {
            let path = Xlsx._resolve(r.target, base: dir.isEmpty ? "" : dir + "/")
            if r.type.hasSuffix("/comments") { p.comments = path }
            else if r.type.hasSuffix("/vmlDrawing") { p.vml = path }
            else if r.type.hasSuffix("/threadedComment") { p.threaded.append(path) }
        }
        guard let path = p.comments, let root = parts[path].flatMap({ XNode.parse($0) }) else { return ([], p) }
        let authors = root.child("authors")?.kids("author").map(\.text) ?? []
        var notes: [SheetNote] = []
        for c in root.child("commentList")?.kids("comment") ?? [] {
            guard let a = c["ref"].flatMap({ CellAddress($0) }) else { continue }
            var text = ""
            func walk(_ n: XNode) {
                if n.name == "t" || n.name.hasSuffix(":t") { text += n.text }
                for k in n.children { walk(k) }
            }
            if let t = c.child("text") { walk(t) }
            let author = Int(c["authorId"] ?? "").flatMap { $0 < authors.count ? authors[$0] : nil } ?? ""
            notes.append(SheetNote(origin: a, at: a, author: author, text: text,
                                   threaded: author.hasPrefix("tc=") || text.hasPrefix("[Threaded comment]")))
        }
        return (notes, p)
    }

    private static let commentsType = "application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml"
    private static let vmlType = "application/vnd.openxmlformats-officedocument.vmlDrawing"
    private static let relBase = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    /// The note parts for a sheet whose notes changed here: references
    /// moved, deleted notes gone, edited text rewritten, new notes added —
    /// in the file's own parts, or in new ones when it had none.
    static func write(_ ws: Worksheet, sheetPath: String, original: [String: Data], taken: inout Set<String>,
                      sheetRels: inout [(id: String, type: String, target: String)], relsChanged: inout Bool) -> NoteParts {
        var out = NoteParts()
        let notes = ws.notes, p = ws.noteParts
        let added = notes.filter { $0.origin == nil && $0.at != nil }
        guard notes.contains(where: { $0.origin != $0.at || $0.edited }) else { return out }
        var map: [CellAddress: SheetNote] = [:]
        for n in notes { if let o = n.origin { map[o] = n } }

        // The comments part: the file's, patched, or a new one.
        var commentsPath = p.comments
        var comments: String
        if let path = commentsPath, let data = original[path] {
            comments = String(decoding: data, as: UTF8.self)
        } else {
            guard !added.isEmpty else { return out }
            commentsPath = _fresh("xl/", "comments", ".xml", original, &taken)
            comments = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<comments xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><authors></authors><commentList></commentList></comments>"
            out.overrides.append(("/" + commentsPath!, commentsType))
            sheetRels.append((Xlsx._freshId(sheetRels), "\(relBase)/comments", "../" + String(commentsPath!.dropFirst("xl/".count))))
            relsChanged = true
        }
        comments = _patchElements(comments, "comment") { element, ref in
            guard let note = map[ref] else { return element }
            guard let at = note.at else { return nil }
            var e = _setRef(element, at)
            if note.edited, let a = e.findRange(of: "<text>"), let b = e.findRange(of: "</text>") {
                e.replaceSubrange(a.lowerBound ..< b.upperBound, with: _textXML(note))
            }
            return e
        }
        // New notes, and any author they bring.
        var authors = _authors(comments)
        for n in added {
            var id = authors.firstIndex(of: n.author)
            if id == nil {
                authors.append(n.author)
                id = authors.count - 1
                comments = _insert(comments, before: "</authors>", "<author>\(Xlsx._esc(n.author))</author>", orEmpty: "<authors/>")
            }
            comments = _insert(comments, before: "</commentList>",
                               "<comment ref=\"\(n.at!.a1)\" authorId=\"\(id!)\">\(_textXML(n))</comment>", orEmpty: "<commentList/>")
        }
        out.parts[commentsPath!] = Data(comments.utf8)

        // The VML: each note's box, moved, removed or added.
        var vmlPath = p.vml
        var vml: String
        if let path = vmlPath, let data = original[path] {
            vml = String(decoding: data, as: UTF8.self)
        } else {
            vmlPath = _fresh("xl/drawings/", "vmlDrawing", ".vml", original, &taken)
            let n = Int(vmlPath!.filter(\.isNumber)) ?? 1
            vml = "<xml xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:x=\"urn:schemas-microsoft-com:office:excel\"><o:shapelayout v:ext=\"edit\"><o:idmap v:ext=\"edit\" data=\"\(n)\"/></o:shapelayout>"
                + "<v:shapetype id=\"_x0000_t202\" coordsize=\"21600,21600\" o:spt=\"202\" path=\"m,l,21600r21600,l21600,xe\"><v:stroke joinstyle=\"miter\"/><v:path gradientshapeok=\"t\" o:connecttype=\"rect\"/></v:shapetype></xml>"
            out.overrides.append(("/" + vmlPath!, vmlType))
            let id = Xlsx._freshId(sheetRels)
            sheetRels.append((id, "\(relBase)/vmlDrawing", "../" + String(vmlPath!.dropFirst("xl/".count))))
            relsChanged = true
            out.element = "<legacyDrawing xmlns:r=\"\(relBase)\" r:id=\"\(id)\"/>"
        }
        vml = _patchShapes(vml, map)
        if !added.isEmpty {
            if !vml.containsSubstring("id=\"_x0000_t202\"") {
                vml = _insert(vml, before: "</xml>", "<v:shapetype id=\"_x0000_t202\" coordsize=\"21600,21600\" o:spt=\"202\" path=\"m,l,21600r21600,l21600,xe\"><v:stroke joinstyle=\"miter\"/><v:path gradientshapeok=\"t\" o:connecttype=\"rect\"/></v:shapetype>", orEmpty: nil)
            }
            // Shape ids follow the file's: one past the largest.
            var next = 1024
            var at = vml.startIndex
            while let r = vml.findRange(of: "_x0000_s", in: at ..< vml.endIndex) {
                var j = r.upperBound, digits = ""
                while j < vml.endIndex, vml[j].isNumber { digits.append(vml[j]); j = vml.index(after: j) }
                next = max(next, Int(digits) ?? 0)
                at = j
            }
            for n in added {
                next += 1
                let a = n.at!
                vml = _insert(vml, before: "</xml>", "<v:shape id=\"_x0000_s\(next)\" type=\"#_x0000_t202\" style=\"position:absolute;margin-left:59.25pt;margin-top:1.5pt;width:108pt;height:59.25pt;z-index:\(next - 1024);visibility:hidden\" fillcolor=\"#ffffe1\" o:insetmode=\"auto\"><v:fill color2=\"#ffffe1\"/><v:shadow on=\"t\" color=\"black\" obscured=\"t\"/><v:path o:connecttype=\"none\"/><v:textbox style=\"mso-direction-alt:auto\"><div style=\"text-align:left\"></div></v:textbox><x:ClientData ObjectType=\"Note\"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>\(a.col + 1), 15, \(max(0, a.row - 1)), 10, \(a.col + 3), 15, \(a.row + 3), 4</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>\(a.row)</x:Row><x:Column>\(a.col)</x:Column></x:ClientData></v:shape>", orEmpty: nil)
            }
        }
        out.parts[vmlPath!] = Data(vml.utf8)

        for path in p.threaded {
            guard let data = original[path] else { continue }
            out.parts[path] = Data(_patchElements(String(decoding: data, as: UTF8.self), "threadedComment") { element, ref in
                guard let note = map[ref] else { return element }
                return note.at.map { _setRef(element, $0) }
            }.utf8)
        }
        return out
    }

    /// Excel's note text: the author's line bold, the rest plain, Tahoma 9.
    private static func _textXML(_ n: SheetNote) -> String {
        let pr = "<sz val=\"9\"/><color indexed=\"81\"/><rFont val=\"Tahoma\"/><family val=\"2\"/>"
        let head = n.author.isEmpty ? "" : "<r><rPr><b/>\(pr)</rPr><t>\(Xlsx._esc(n.author)):</t></r>"
        let body = (n.author.isEmpty ? "" : "\n") + n.body
        return "<text>\(head)<r><rPr>\(pr)</rPr><t xml:space=\"preserve\">\(Xlsx._esc(body))</t></r></text>"
    }

    private static func _authors(_ xml: String) -> [String] {
        guard let root = XNode.parse(Data(xml.utf8)) else { return [] }
        return root.child("authors")?.kids("author").map(\.text) ?? []
    }

    private static func _fresh(_ dir: String, _ stem: String, _ ext: String, _ original: [String: Data], _ taken: inout Set<String>) -> String {
        var n = 1
        while taken.contains("\(dir)\(stem)\(n)\(ext)") || original["\(dir)\(stem)\(n)\(ext)"] != nil { n += 1 }
        let p = "\(dir)\(stem)\(n)\(ext)"
        taken.insert(p)
        return p
    }

    /// `text` with `new` before the last `marker`, or in place of `empty`
    /// (a self-closed form of the same element).
    private static func _insert(_ text: String, before marker: String, _ new: String, orEmpty empty: String?) -> String {
        var s = text
        if let r = s.findRange(of: marker, backwards: true) { s.insert(contentsOf: new, at: r.lowerBound); return s }
        if let empty, let r = s.findRange(of: empty) {
            let name = String(empty.dropFirst().dropLast(2))
            s.replaceSubrange(r, with: "<\(name)>\(new)</\(name)>")
        }
        return s
    }

    private static func _setRef(_ element: String, _ a: CellAddress) -> String {
        var e = element
        if let r = e.findRange(of: " ref=\""), let q = e.findRange(of: "\"", in: r.upperBound ..< e.endIndex) {
            e.replaceSubrange(r.upperBound ..< q.lowerBound, with: a.a1)
        }
        return e
    }

    /// Each `<tag … ref="X" …>…</tag>` (or self-closed) through `f`, given
    /// its ref; nil removes it.
    private static func _patchElements(_ xml: String, _ tag: String, _ f: (String, CellAddress) -> String?) -> String {
        var s = ""
        var at = xml.startIndex
        while let a = xml.findRange(of: "<\(tag) ", in: at ..< xml.endIndex) {
            let tagEnd = xml.findRange(of: ">", in: a.upperBound ..< xml.endIndex)?.upperBound ?? xml.endIndex
            let selfClosed = xml[xml.index(tagEnd, offsetBy: -2) ..< tagEnd] == "/>"
            let end = selfClosed ? tagEnd : (xml.findRange(of: "</\(tag)>", in: tagEnd ..< xml.endIndex)?.upperBound ?? tagEnd)
            let element = String(xml[a.lowerBound ..< end])
            s += xml[at ..< a.lowerBound]
            at = end
            if let r = element.findRange(of: " ref=\""), let q = element.findRange(of: "\"", in: r.upperBound ..< element.endIndex),
               let ref = CellAddress(String(element[r.upperBound ..< q.lowerBound])) {
                if let kept = f(element, ref) { s += kept }
            } else {
                s += element
            }
        }
        return s + xml[at...]
    }

    /// Each note shape's x:Row / x:Column moved, or the shape removed.
    private static func _patchShapes(_ xml: String, _ map: [CellAddress: SheetNote]) -> String {
        var s = ""
        var at = xml.startIndex
        while let a = xml.findRange(of: "<v:shape ", in: at ..< xml.endIndex),
              let b = xml.findRange(of: "</v:shape>", in: a.upperBound ..< xml.endIndex) {
            var shape = String(xml[a.lowerBound ..< b.upperBound])
            s += xml[at ..< a.lowerBound]
            at = b.upperBound
            if let r0 = shape.findRange(of: "<x:Row>"), let r1 = shape.findRange(of: "</x:Row>", in: r0.upperBound ..< shape.endIndex),
               let c0 = shape.findRange(of: "<x:Column>"), let c1 = shape.findRange(of: "</x:Column>", in: c0.upperBound ..< shape.endIndex),
               let row = Int(shape[r0.upperBound ..< r1.lowerBound].trimmingWhitespace()),
               let col = Int(shape[c0.upperBound ..< c1.lowerBound].trimmingWhitespace()),
               let note = map[CellAddress(row: row, col: col)] {
                guard let new = note.at else { continue }
                if new != note.origin {
                    // The later of the two first, so the earlier's range still holds.
                    if c0.lowerBound > r0.lowerBound {
                        shape.replaceSubrange(c0.upperBound ..< c1.lowerBound, with: "\(new.col)")
                        shape.replaceSubrange(r0.upperBound ..< r1.lowerBound, with: "\(new.row)")
                    } else {
                        shape.replaceSubrange(r0.upperBound ..< r1.lowerBound, with: "\(new.row)")
                        shape.replaceSubrange(c0.upperBound ..< c1.lowerBound, with: "\(new.col)")
                    }
                }
            }
            s += shape
        }
        return s + xml[at...]
    }
}

// MARK: - Editing

extension WorkbookController {
    func note(at a: CellAddress) -> SheetNote? { sheet.notes.first { $0.at == a } }

    /// Review → New Note / Edit Note: the note's words (without the author
    /// line, which a new one gets from the user's name, as Excel's do).
    func setNote(_ body: String, at a: CellAddress) {
        let ws = sheet
        let body = body.trimmingWhitespace()
        guard !body.isEmpty else { deleteNote(at: a); return }
        if let i = ws.notes.firstIndex(where: { $0.at == a }) {
            guard !ws.notes[i].threaded else { onCommand?(.status("This is a threaded comment; reply to it in Excel")); return }
            guard ws.notes[i].body != body else { return }
            structural {
                var n = ws.notes[i]
                n.text = n.author.isEmpty ? body : n.author + ":\n" + body
                n.edited = true
                ws.notes[i] = n
            }
        } else {
            let author = PdfExport.authorName()
            structural {
                ws.notes.append(SheetNote(origin: nil, at: a, author: author,
                                          text: author.isEmpty ? body : author + ":\n" + body, edited: true))
            }
        }
    }

    /// The note after (or before) the active cell, row by row; selects it.
    func goToNote(_ step: Int) {
        let cells = sheet.notes.compactMap(\.at).sorted()
        guard !cells.isEmpty else { onCommand?(.status("This sheet has no notes")); return }
        let next = step > 0 ? cells.first { $0 > active } ?? cells[0] : cells.last { $0 < active } ?? cells[cells.count - 1]
        select(next)
    }

    func deleteNote(at a: CellAddress) {
        let ws = sheet
        guard let i = ws.notes.firstIndex(where: { $0.at == a }) else { return }
        structural {
            if ws.notes[i].origin == nil { ws.notes.remove(at: i) } else { ws.notes[i].at = nil }
        }
    }
}

/// The note editor: the note's words in a box beside the cell.
final class NoteEditor: StatefulWidget {
    let initial: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(initial: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onSave = onSave
        self.onCancel = onCancel
        super.init()
    }

    override func createState() -> State<StatefulWidget> { NoteEditorState() }
}

final class NoteEditorState: State<StatefulWidget> {
    private let _text = TextEditingController()
    private var _w: NoteEditor { widget as! NoteEditor }

    override func initState() {
        super.initState()
        _text.text = _w.initial
    }

    override func dispose() {
        _text.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        let save = _w.onSave, cancel = _w.onCancel, text = _text
        return FlyoutContent(child: SizedBox(width: 260, height: nil, child: Column(mainAxisSize: .min, crossAxisAlignment: .stretch, children: [
            Text("Note", style: fluent.typography.bodyStrong),
            Chrome.gap(6),
            SizedBox(width: nil, height: 110, child: FluentTextBox(controller: _text, placeholderText: "Type a note", maxLines: 6)),
            Chrome.gap(8),
            Row(mainAxisAlignment: .end, children: [
                FilledButton(onPressed: { save(text.text) }, child: Text("Save")),
                Chrome.gap(6),
                Button(onPressed: cancel, child: Text("Cancel")),
            ]),
        ])))
    }
}
