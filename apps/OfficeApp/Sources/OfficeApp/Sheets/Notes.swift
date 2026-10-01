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

import Foundation

struct SheetNote: Equatable, Sendable {
    /// The cell the file put it on, and where that cell is now (nil once
    /// deleted).
    var origin: CellAddress
    var at: CellAddress?
    var author: String
    var text: String
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
            notes.append(SheetNote(origin: a, at: a, author: author, text: text))
        }
        return (notes, p)
    }

    /// The note parts with every reference moved to where its cell is now.
    static func write(_ notes: [SheetNote], _ p: SheetNoteParts, original: [String: Data]) -> [String: Data] {
        let moved = notes.filter { $0.at != $0.origin }
        guard !moved.isEmpty else { return [:] }
        var map: [CellAddress: CellAddress?] = [:]
        for n in moved { map[n.origin] = .some(n.at) }
        var out: [String: Data] = [:]
        // Each `<tag … ref="X" …>…</tag>` (or self-closed) with X moved or the element gone.
        func patchRefs(_ xml: String, _ tag: String) -> String {
            var s = ""
            var at = xml.startIndex
            while let a = xml.findRange(of: "<\(tag) ", in: at ..< xml.endIndex) {
                let tagEnd = xml.findRange(of: ">", in: a.upperBound ..< xml.endIndex)?.upperBound ?? xml.endIndex
                let selfClosed = xml[xml.index(tagEnd, offsetBy: -2) ..< tagEnd] == "/>"
                let end = selfClosed ? tagEnd : (xml.findRange(of: "</\(tag)>", in: tagEnd ..< xml.endIndex)?.upperBound ?? tagEnd)
                var element = String(xml[a.lowerBound ..< end])
                s += xml[at ..< a.lowerBound]
                at = end
                if let r = element.findRange(of: " ref=\""), let q = element.findRange(of: "\"", in: r.upperBound ..< element.endIndex),
                   let old = CellAddress(String(element[r.upperBound ..< q.lowerBound])), let new = map[old] {
                    guard let new else { continue }                   // its cell was deleted: so is it
                    element.replaceSubrange(r.upperBound ..< q.lowerBound, with: new.a1)
                }
                s += element
            }
            return s + xml[at...]
        }
        if let path = p.comments, let data = original[path] {
            out[path] = Data(patchRefs(String(decoding: data, as: UTF8.self), "comment").utf8)
        }
        for path in p.threaded {
            if let data = original[path] { out[path] = Data(patchRefs(String(decoding: data, as: UTF8.self), "threadedComment").utf8) }
        }
        if let path = p.vml, let data = original[path] {
            // Each note's shape: its x:Row / x:Column moved, or the shape removed.
            let xml = String(decoding: data, as: UTF8.self)
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
                   let new = map[CellAddress(row: row, col: col)] {
                    guard let new else { continue }
                    // Column first: replacing it does not move the Row text before it, nor vice versa.
                    if c0.lowerBound > r0.lowerBound {
                        shape.replaceSubrange(c0.upperBound ..< c1.lowerBound, with: "\(new.col)")
                        shape.replaceSubrange(r0.upperBound ..< r1.lowerBound, with: "\(new.row)")
                    } else {
                        shape.replaceSubrange(r0.upperBound ..< r1.lowerBound, with: "\(new.row)")
                        shape.replaceSubrange(c0.upperBound ..< c1.lowerBound, with: "\(new.col)")
                    }
                }
                s += shape
            }
            out[path] = Data((s + xml[at...]).utf8)
        }
        return out
    }
}
