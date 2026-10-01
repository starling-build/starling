// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Excel tables (`xl/tables/tableN.xml`), kept so that Excel still opens a
// saved file without repairing it. A table names its range and lists one
// `<tableColumn>` per column, whose name must equal the header cell's
// text; Excel throws the table away ("Repaired Records: Table") when the
// two disagree. So:
//   - the range moves with rows and columns inserted or deleted, and the
//     column list follows (a column inserted inside gets a new entry, a
//     deleted one loses its own);
//   - on save the names are re-read from the header cells — unique and
//     never empty, as Excel requires.
// Everything else in the part (style, dxfs, calculated columns, totals)
// is written back as it was. Table styles are not drawn yet.

import Foundation

struct SheetTable: Equatable, Sendable {
    var path: String
    var ref: CellRange
    /// Per column, the `<tableColumn>` it came from (by id), nil for one
    /// inserted here.
    var columnIds: [Int?]
    var headerRow: Bool
    /// Something about it changed here: the part is rewritten on save.
    var edited = false
}

enum TablesXML {
    /// The tables a sheet's `tableParts` name.
    static func read(sheetPath: String, parts: [String: Data]) -> [SheetTable] {
        guard let sheet = parts[sheetPath].flatMap({ XNode.parse($0) }) else { return [] }
        let rels = SheetDrawingsXML._relTargets(parts, of: sheetPath)
        return (sheet.child("tableParts")?.kids("tablePart") ?? []).compactMap { tp in
            guard let id = tp["r:id"], let path = rels[id], let root = parts[path].flatMap({ XNode.parse($0) }),
                  let ref = root["ref"].flatMap({ CellRange($0) }) else { return nil }
            let ids = root.child("tableColumns")?.kids("tableColumn").map { Int($0["id"] ?? "") } ?? []
            return SheetTable(path: path, ref: ref, columnIds: ids, headerRow: root["headerRowCount"] != "0")
        }
    }

    /// The part for a table, from the file's text: its ranges, and its
    /// column list rebuilt with names from the header cells.
    static func write(_ t: SheetTable, original: Data, header: (Int) -> String) -> Data {
        var xml = String(decoding: original, as: UTF8.self)
        // ref on the root and on its autoFilter (the first two `ref="…"`).
        var at = xml.startIndex
        for _ in 0 ..< 2 {
            guard let a = xml.findRange(of: " ref=\"", in: at ..< xml.endIndex),
                  let b = xml.findRange(of: "\"", in: a.upperBound ..< xml.endIndex) else { break }
            xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: t.ref.a1)
            at = xml.findRange(of: "\"", in: a.upperBound ..< xml.endIndex)?.upperBound ?? xml.endIndex
        }
        guard let a = xml.findRange(of: "<tableColumns"), let b = xml.findRange(of: "</tableColumns>") else { return Data(xml.utf8) }
        let block = String(xml[a.lowerBound ..< b.upperBound])
        var byId: [Int: String] = [:]
        for kid in RawXML.split([UInt8](block.utf8)).children where kid.name == "tableColumn" {
            if let id = _attr(kid.text, "id").flatMap({ Int($0) }) { byId[id] = kid.text }
        }
        var nextId = (byId.keys.max() ?? 0) + 1
        var used = Set<String>()
        var cols = ""
        for (i, id) in t.columnIds.enumerated() {
            // Excel's rules: never empty, unique ignoring case.
            // Control characters as Excel writes them in a name (_x000a_ for a
            // line break): a raw one in an attribute reads back as a space.
            var name = (t.headerRow ? header(t.ref.left + i).trimmingWhitespace() : "")
                .replacingAll("\r\n", with: "_x000d__x000a_").replacingAll("\n", with: "_x000a_")
                .replacingAll("\r", with: "_x000d_").replacingAll("\t", with: "_x0009_")
            if name.isEmpty { name = "Column\(i + 1)" }
            var unique = name, n = 2
            while used.contains(unique.lowercased()) { unique = name + "\(n)"; n += 1 }
            used.insert(unique.lowercased())
            if let id, let text = byId[id] {
                cols += _setAttr(text, "name", Xlsx._esc(unique))
            } else {
                cols += "<tableColumn id=\"\(nextId)\" name=\"\(Xlsx._esc(unique))\"/>"
                nextId += 1
            }
        }
        let start = String(block[..<(block.firstIndex(of: ">").map { block.index(after: $0) } ?? block.endIndex)])
        xml.replaceSubrange(a.lowerBound ..< b.upperBound,
                            with: _setAttr(start, "count", "\(t.columnIds.count)") + cols + "</tableColumns>")
        // Filters by column position no longer line up when columns moved.
        if t.columnIds.contains(where: { $0 == nil }) || byId.count != t.columnIds.count {
            while let f = xml.findRange(of: "<filterColumn"), let e = xml.findRange(of: "</filterColumn>", in: f.upperBound ..< xml.endIndex) {
                xml.removeSubrange(f.lowerBound ..< e.upperBound)
            }
        }
        return Data(xml.utf8)
    }

    private static func _attr(_ tag: String, _ name: String) -> String? {
        guard let a = tag.findRange(of: " \(name)=\""), let b = tag.findRange(of: "\"", in: a.upperBound ..< tag.endIndex) else { return nil }
        return String(tag[a.upperBound ..< b.lowerBound])
    }

    /// `name="value"` in an element's start tag, replaced or added.
    private static func _setAttr(_ text: String, _ name: String, _ value: String) -> String {
        var s = text
        let tagEnd = s.firstIndex(of: ">") ?? s.endIndex
        if let a = s.findRange(of: " \(name)=\"", in: s.startIndex ..< tagEnd), let b = s.findRange(of: "\"", in: a.upperBound ..< s.endIndex) {
            s.replaceSubrange(a.upperBound ..< b.lowerBound, with: value)
        } else {
            let insertAt = s.index(before: tagEnd) < s.endIndex && s[s.index(before: tagEnd)] == "/" ? s.index(before: tagEnd) : tagEnd
            s.insert(contentsOf: " \(name)=\"\(value)\"", at: insertAt)
        }
        return s
    }
}
