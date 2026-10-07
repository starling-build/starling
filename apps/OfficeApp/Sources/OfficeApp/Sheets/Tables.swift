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
    /// `tableStyleInfo`: the style's name and which of its parts show.
    var style: String? = nil
    var rowStripes = true
    var columnStripes = false
    var firstColumn = false
    var lastColumn = false
    var totalsRow = false
    /// The name formulas use for it (displayName), and its columns' names
    /// as the file wrote them.
    var name = ""
    var columnNames: [String] = []
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
            var t = SheetTable(path: path, ref: ref, columnIds: ids, headerRow: root["headerRowCount"] != "0")
            if let info = root.child("tableStyleInfo") {
                t.style = info["name"]
                t.rowStripes = info["showRowStripes"] == "1"
                t.columnStripes = info["showColumnStripes"] == "1"
                t.firstColumn = info["showFirstColumn"] == "1"
                t.lastColumn = info["showLastColumn"] == "1"
            }
            t.totalsRow = (Int(root["totalsRowCount"] ?? "0") ?? 0) > 0
            t.name = root["displayName"] ?? root["name"] ?? ""
            t.columnNames = root.child("tableColumns")?.kids("tableColumn").map { $0["name"] ?? "" } ?? []
            return t
        }
    }

    /// The part for a table, from the file's text: its ranges, and its
    /// column list rebuilt with names from the header cells.
    static func write(_ t: SheetTable, original: Data, header: (Int) -> String) -> Data {
        var xml = String(decoding: original, as: UTF8.self)
        // ref on the root and on its autoFilter (the first two `ref="…"`);
        // the filter stops above the totals row, as Excel writes it.
        var filterRef = t.ref
        if t.totalsRow, filterRef.bottom > filterRef.top { filterRef.bottom -= 1 }
        var at = xml.startIndex
        for which in 0 ..< 2 {
            guard let a = xml.findRange(of: " ref=\"", in: at ..< xml.endIndex),
                  let b = xml.findRange(of: "\"", in: a.upperBound ..< xml.endIndex) else { break }
            xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: which == 0 ? t.ref.a1 : filterRef.a1)
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
            // Excel's rules: never empty, unique ignoring case, and exactly
            // the header cell's text — spaces at either end included, or
            // Excel repairs the table.
            // Control characters as Excel writes them in a name (_x000a_ for a
            // line break): a raw one in an attribute reads back as a space.
            var name = (t.headerRow ? header(t.ref.left + i) : "")
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

// MARK: - Drawing

/// How a table's built-in style dresses one cell.
struct TableCellLook: Equatable {
    var fill: UInt32? = nil
    var bold = false
    var color: UInt32? = nil
    /// Lines under / over the cell, and down its left and right.
    var bottom: UInt32? = nil
    var top: UInt32? = nil
    var left: UInt32? = nil
    var right: UInt32? = nil
    var sides: UInt32? { get { left } set { left = newValue; right = newValue } }
}

/// Excel's built-in table styles, by family: each family repeats one
/// pattern over the theme's dark colour (1st) and six accents (2nd–7th).
/// An approximation of presetTableStyles — the header, stripes and lines
/// that make a table read as one, not every rule of every style.
enum TableStyles {
    static func look(_ t: SheetTable, _ a: CellAddress, theme: [UInt32]) -> TableCellLook? {
        guard t.ref.contains(a), let name = t.style, name.hasPrefix("TableStyle") else { return nil }
        let rest = name.dropFirst("TableStyle".count)
        let family = rest.prefix { $0.isLetter }
        guard let n = Int(rest.dropFirst(family.count)), n >= 1 else { return nil }
        let k = (n - 1) % 7                    // 0: the dark colour; 1–6: accent1–6
        let group = (n - 1) / 7                // which pattern in the family
        let base: UInt32 = k == 0 ? (theme.count > 1 ? theme[1] : 0) : (theme.count > k + 3 ? theme[k + 3] : 0x4472C4)
        func tint(_ f: Double) -> UInt32 { CFEvaluator._mix(base, 0xFFFFFF, f) }
        func shade(_ f: Double) -> UInt32 { CFEvaluator._mix(base, 0x000000, f) }
        let white: UInt32 = 0xFFFFFF
        let header = t.headerRow && a.row == t.ref.top
        let totals = t.totalsRow && a.row == t.ref.bottom
        let dataRow = a.row - t.ref.top - (t.headerRow ? 1 : 0)
        let dataCol = a.col - t.ref.left
        let stripe = (t.rowStripes && dataRow % 2 == 0) || (t.columnStripes && dataCol % 2 == 0)
        let edgeCol = (t.firstColumn && a.col == t.ref.left) || (t.lastColumn && a.col == t.ref.right)
        var x = TableCellLook()
        switch (family, group) {
        case ("Light", 0):                     // Light 1–7: lines above and below, light stripes
            if header { x.bold = true; x.bottom = base }
            else if !totals && stripe { x.fill = tint(0.8) }
            if a.row == t.ref.top || totals { x.top = base }
            if a.row == t.ref.bottom { x.bottom = base }
            if k > 0 { x.color = shade(0.25) }
        case ("Light", 1):                     // Light 8–14: a filled header, an outline
            if header { x.fill = base; x.color = white; x.bold = true }
            if a.row == t.ref.bottom { x.bottom = base }
            if a.col == t.ref.left { x.left = base }
            if a.col == t.ref.right { x.right = base }
            if !header && stripe { x.bottom = base }
        case ("Light", _):                     // Light 15–21: a grid
            if header { x.bold = true }
            else if stripe { x.fill = tint(0.8) }
            x.bottom = base; x.top = base; x.sides = base
        case ("Medium", 0):                    // Medium 1–7: filled header, light stripes, thin lines
            if header { x.fill = base; x.color = white; x.bold = true }
            else if !totals && stripe { x.fill = tint(0.8) }
            if !header { x.bottom = tint(0.4) }
            if totals { x.top = base; x.bold = true }
        case ("Medium", 1):                    // Medium 8–14: two-tone stripes, white lines
            if header { x.fill = base; x.color = white; x.bold = true }
            else { x.fill = stripe ? tint(0.6) : tint(0.8) }
            x.bottom = white; x.sides = white
        case ("Medium", 2):                    // Medium 15–21: dark header over a light grid
            if header { x.fill = theme.count > 1 ? theme[1] : 0; x.color = white; x.bold = true }
            else if stripe { x.fill = 0xD9D9D9 }
            x.bottom = 0x000000
        case ("Medium", _):                    // Medium 22–28: tinted body, a grid
            if header { x.bold = true; x.fill = tint(0.8) } else { x.fill = stripe ? tint(0.6) : tint(0.8) }
            x.bottom = tint(0.4); x.sides = tint(0.4)
        case ("Dark", 0):                      // Dark 1–7: shaded body, white text
            if header { x.fill = 0x000000; x.color = white; x.bold = true; x.bottom = white }
            else { x.fill = stripe ? shade(0.25) : base; x.color = white }
        case ("Dark", _):                      // Dark 8–11: light body, dark header
            if header { x.fill = 0x000000; x.color = white; x.bold = true }
            else { x.fill = stripe ? tint(0.6) : tint(0.8) }
        default:
            return nil
        }
        if edgeCol && !header { x.bold = true }
        if totals { x.bold = true; x.top = x.top ?? base }
        return x
    }
}

// MARK: - Structured references

extension CalcEngine {
    /// `Table1[Amount]` and its kin, as cells: the table by name (or the
    /// one the formula sits in, for `[@Qty]`), the rows by special item
    /// (#All, #Data, #Headers, #Totals, #This Row / @), the columns by
    /// name or `[A]:[B]` span. Unknown tables or columns are #REF!.
    func resolveStructured(_ text: String, _ ctx: EvalContext) -> EvalValue {
        guard let open = text.firstIndex(of: "[") else { return .error(.ref) }
        let tableName = String(text[..<open]).lowercased()
        var found: (Int, SheetTable)? = nil
        for (si, ws) in book.sheets.enumerated() {
            for t in ws.tables {
                if tableName.isEmpty ? (si == ctx.sheet && t.ref.contains(ctx.cell)) : t.name.lowercased() == tableName {
                    found = (si, t)
                }
            }
        }
        guard let (si, t) = found else { return .error(.ref) }
        let ws = book.sheets[si]
        // What is inside the outer brackets, split into items.
        var inner = String(text[text.index(after: open)...].dropLast())
        var items: [String] = []
        if inner.hasPrefix("@") {
            items = ["#This Row"]
            inner.removeFirst()
            if !inner.isEmpty { items.append(inner.hasPrefix("[") ? inner : "[" + inner + "]") }
        } else if !inner.hasPrefix("[") {
            if !inner.isEmpty { items = [inner.hasPrefix("#") ? inner : "[" + inner + "]"] }
        } else {
            // [a],[b]:[c] — split at top-level commas.
            var depth = 0, cur = "", escaped = false
            for ch in inner {
                if escaped { cur.append(ch); escaped = false; continue }
                if ch == "'" { cur.append(ch); escaped = true; continue }
                if ch == "[" { depth += 1 }
                if ch == "]" { depth -= 1 }
                if ch == "," && depth == 0 { items.append(cur); cur = ""; continue }
                cur.append(ch)
            }
            if !cur.isEmpty { items.append(cur) }
        }
        func unbracket(_ s: String) -> String {
            var x = s.trimmingWhitespace()
            if x.hasPrefix("[") && x.hasSuffix("]") { x = String(x.dropFirst().dropLast()) }
            var out = "", esc = false
            for ch in x { if esc { out.append(ch); esc = false } else if ch == "'" { esc = true } else { out.append(ch) } }
            return out
        }
        // Rows.
        let header = t.headerRow ? t.ref.top : nil
        let totals = t.totalsRow ? t.ref.bottom : nil
        let dataTop = t.ref.top + (t.headerRow ? 1 : 0), dataBottom = t.ref.bottom - (t.totalsRow ? 1 : 0)
        var rows: ClosedRange<Int>? = nil
        var cols: ClosedRange<Int>? = nil
        func addRows(_ r: ClosedRange<Int>) { rows = rows.map { min($0.lowerBound, r.lowerBound) ... max($0.upperBound, r.upperBound) } ?? r }
        func column(_ name: String) -> Int? {
            let n = name.lowercased()
            for c in t.ref.left ... t.ref.right {
                let i = c - t.ref.left
                let shown = NumberFormat.display(ws.value(CellAddress(row: t.ref.top, col: c)), "General", width: 255).text
                if t.headerRow && shown.lowercased() == n { return c }
                if i < t.columnNames.count && t.columnNames[i].lowercased() == n { return c }
            }
            return nil
        }
        for item in items {
            let x = unbracket(item)
            switch x.lowercased() {
            case "#all": addRows(t.ref.top ... t.ref.bottom)
            case "#data": if dataTop <= dataBottom { addRows(dataTop ... dataBottom) }
            case "#headers": guard let h = header else { return .error(.ref) }; addRows(h ... h)
            case "#totals": guard let r = totals else { return .error(.ref) }; addRows(r ... r)
            case "#this row":
                guard ctx.cell.row >= dataTop, ctx.cell.row <= dataBottom else { return .error(.value) }
                addRows(ctx.cell.row ... ctx.cell.row)
            default:
                // A column, or a span of them: [A]:[B].
                let parts = item.split(separator: ":", maxSplits: 1).map { unbracket(String($0)) }
                let found = parts.compactMap(column)
                guard found.count == parts.count, let a = found.first, let b = found.last else { return .error(.ref) }
                let span = min(a, b) ... max(a, b)
                cols = cols.map { min($0.lowerBound, span.lowerBound) ... max($0.upperBound, span.upperBound) } ?? span
            }
        }
        let r = rows ?? (dataTop <= dataBottom ? dataTop ... dataBottom : dataTop ... dataTop)
        let c = cols ?? (t.ref.left ... t.ref.right)
        let range = CellRange(top: r.lowerBound, left: c.lowerBound, bottom: r.upperBound, right: c.upperBound)
        return range.isSingle ? .scalar(value(si, range.topLeft)) : .range(sheet: si, range)
    }
}

extension WorkbookController {
    /// Header cells about to change: (table, old name) for each, so the
    /// structured references to them can follow (as Excel's do).
    func _tableHeaderNames(_ addresses: [CellAddress], sheet si: Int) -> [CellAddress: (table: SheetTable, name: String)] {
        let ws = book.sheets[si]
        var out: [CellAddress: (SheetTable, String)] = [:]
        for t in ws.tables where t.headerRow {
            for a in addresses where a.row == t.ref.top && a.col >= t.ref.left && a.col <= t.ref.right {
                out[a] = (t, NumberFormat.display(ws.value(a), "General", width: 255).text)
            }
        }
        return out
    }

    /// After header cells changed: every formula's `[Old]` / `[@Old]` for
    /// that table becomes the new name.
    func _renameTableColumns(_ before: [CellAddress: (table: SheetTable, name: String)], sheet si: Int) {
        let ws = book.sheets[si]
        func escape(_ s: String) -> String {
            var out = ""
            for ch in s { if "[]#'".contains(ch) { out.append("'") }; out.append(ch) }
            return out
        }
        for (a, old) in before {
            let new = NumberFormat.display(ws.value(a), "General", width: 255).text
            guard !old.name.isEmpty, !new.isEmpty, old.name != new else { continue }
            let table = old.table
            for (osi, other) in book.sheets.enumerated() {
                for (addr, cell) in other.cells {
                    guard let f = cell.formula else { continue }
                    let g = Formula.mapStructured(f) { text in
                        let lower = text.lowercased()
                        let named = lower.hasPrefix(table.name.lowercased() + "[")
                        let implicit = text.hasPrefix("[") && osi == si && table.ref.contains(addr)
                        guard named || implicit else { return text }
                        var t = text
                        for (from, to) in [("[" + escape(old.name) + "]", "[" + escape(new) + "]"),
                                           ("[@" + escape(old.name) + "]", "[@" + escape(new) + "]"),
                                           ("@" + escape(old.name) + "]", "@" + escape(new) + "]")] {
                            t = t.replacingAll(from, with: to)
                        }
                        return t
                    }
                    if g != f { other.cells[addr]?.formula = g; other.cells[addr]?.input = Formula.text(g) }
                }
            }
        }
    }
}
