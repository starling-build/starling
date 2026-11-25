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
    /// A totals row made here: the label and function (`sum`, `count`) for
    /// the columns that carry one, by position in the table.
    var totalsLabels: [Int: String] = [:]
    var totalsFunctions: [Int: String] = [:]
    /// Made here, with no part in the file yet.
    var isNew: Bool { path.isEmpty }
}

enum TablesXML {
    /// The tables a sheet's `tableParts` name.
    static func read(sheetPath: String, parts: [String: Data], sheet: XNode? = nil) -> [SheetTable] {
        guard let sheet = sheet ?? parts[sheetPath].flatMap({ XNode.parse($0) }) else { return [] }
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
            var col: String
            if let id, let text = byId[id] {
                col = _setAttr(text, "name", Xlsx._esc(unique))
            } else {
                col = "<tableColumn id=\"\(nextId)\" name=\"\(Xlsx._esc(unique))\"/>"
                nextId += 1
            }
            if t.edited {
                // The totals row made or removed here.
                if t.totalsRow {
                    if let l = t.totalsLabels[i] { col = _setAttr(col, "totalsRowLabel", Xlsx._esc(l)) }
                    if let f = t.totalsFunctions[i] { col = _setAttr(col, "totalsRowFunction", f) }
                } else {
                    col = _removeAttr(col, "totalsRowLabel")
                    col = _removeAttr(col, "totalsRowFunction")
                    while let f = col.findRange(of: "<totalsRowFormula"), let e = col.findRange(of: "</totalsRowFormula>", in: f.upperBound ..< col.endIndex) {
                        col.removeSubrange(f.lowerBound ..< e.upperBound)
                    }
                }
            }
            cols += col
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
        if t.edited {
            if let r = xml.findRange(of: "<table "), let e = xml.findRange(of: ">", in: r.upperBound ..< xml.endIndex) {
                var tag = String(xml[r.lowerBound ..< e.upperBound])
                tag = t.totalsRow ? _removeAttr(_setAttr(tag, "totalsRowCount", "1"), "totalsRowShown") : _removeAttr(tag, "totalsRowCount")
                xml.replaceSubrange(r.lowerBound ..< e.upperBound, with: tag)
            }
            if let a = xml.findRange(of: "<tableStyleInfo"), let b = xml.findRange(of: "/>", in: a.upperBound ..< xml.endIndex) {
                xml.removeSubrange(a.lowerBound ..< b.upperBound)
            }
            if let name = t.style {
                let el = "<tableStyleInfo name=\"\(Xlsx._esc(name))\" showFirstColumn=\"\(t.firstColumn ? 1 : 0)\" showLastColumn=\"\(t.lastColumn ? 1 : 0)\" showRowStripes=\"\(t.rowStripes ? 1 : 0)\" showColumnStripes=\"\(t.columnStripes ? 1 : 0)\"/>"
                let at = xml.findRange(of: "<extLst")?.lowerBound ?? xml.findRange(of: "</table>")?.lowerBound ?? xml.endIndex
                xml.insert(contentsOf: el, at: at)
            }
        }
        return Data(xml.utf8)
    }

    /// The part for a table made here: its ranges, columns and style are
    /// filled in by `write`.
    static func newPart(_ t: SheetTable, id: Int) -> Data {
        Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<table xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" id=\"\(id)\" name=\"\(Xlsx._esc(t.name))\" displayName=\"\(Xlsx._esc(t.name))\" ref=\"A1\" totalsRowShown=\"0\"><autoFilter ref=\"A1\"/><tableColumns count=\"0\"></tableColumns></table>").utf8)
    }

    private static func _removeAttr(_ text: String, _ name: String) -> String {
        var s = text
        let tagEnd = s.firstIndex(of: ">") ?? s.endIndex
        if let a = s.findRange(of: " \(name)=\"", in: s.startIndex ..< tagEnd), let b = s.findRange(of: "\"", in: a.upperBound ..< s.endIndex) {
            s.removeSubrange(a.lowerBound ..< b.upperBound)
        }
        return s
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

/// A pivot table, as far as its style needs: where it stands, how many
/// of its rows are headings, whether its last row is the grand total,
/// and its style.
struct SheetPivot: Equatable, Sendable {
    var ref: CellRange
    /// `firstDataRow`: the rows from the top that are headings.
    var headerRows: Int
    var grandTotalRow: Bool
    var style: String?
    /// Rows heading a group of an outer field's items, set on a line of
    /// their own (outline and compact form).
    var subheadingRows: Set<Int> = []
    /// The parts, so a save can follow what moved: the pivot table part, its cache definition, the cache's source
    /// (`'Sheet 1'!A1:D20`, as a formula would write it) and the two as the file had them.
    var path: String? = nil
    var cachePath: String? = nil
    var source: String? = nil
    var originalSource: String? = nil
    var originalRef: CellRange? = nil
    /// A pivot table made here (its cells are ordinary cells; its parts are written on save).
    var made: PivotSpec? = nil
    /// What a pivot that came with the file is made of, when it is one this app can lay out again (compact form, sums, counts and
    /// averages, no hidden or grouped items); nil for the rest, which only Excel refreshes.
    var fileSpec: PivotSpec? = nil
    /// Set once the cells were laid out again here: the saved cache then tells Excel to read its source again on open.
    var refreshedHere = false
}

enum PivotsXML {
    /// The pivot tables a sheet's relationships name.
    static func read(sheetPath: String, parts: [String: Data]) -> [SheetPivot] {
        SheetDrawingsXML._relTargets(parts, of: sheetPath).values.sorted().compactMap { path in
            guard path.containsSubstring("pivotTables/"), let root = Xlsx._part(parts, path).flatMap({ XNode.parse($0) }),
                  let loc = root.child("location"), let ref = loc["ref"].flatMap({ CellRange($0) }) else { return nil }
            // (The grand total row is there unless turned off, where rows
            // are grouped by a field at all.)
            let fields = root.child("rowFields")?.kids("field").count ?? 0
            var p = SheetPivot(ref: ref, headerRows: Int(loc["firstDataRow"] ?? "1") ?? 1,
                               grandTotalRow: fields > 0 && root["rowGrandTotals"] != "0",
                               style: root.child("pivotTableStyleInfo")?["name"])
            // An item of the outermost of two or more row fields, alone on
            // its row: `<i>` with no type, nothing repeated from the row
            // above, and fewer items than fields (tabular form puts the
            // first inner item beside it).
            p.path = path; p.originalRef = ref
            p.fileSpec = spec(root)
            let cacheRoot = SheetDrawingsXML._relTargets(parts, of: path).values.sorted().first(where: { $0.containsSubstring("pivotCacheDefinition") })
                .flatMap { c in Xlsx._part(parts, c).flatMap { XNode.parse($0) }.map { (c, $0) } }
            if let (_, croot) = cacheRoot, p.fileSpec != nil {
                // (Groups live in the cache, where Excel keeps them for every pivot over it; a kind we cannot group the same way leaves the pivot to Excel.)
                if let g = groups(cache: croot) { p.fileSpec?.groups = g } else { p.fileSpec = nil }
            }
            if let cache = cacheRoot?.0,
               let src = cacheRoot?.1.child("cacheSource"), src["type"] == "worksheet",
               let ws = src.child("worksheetSource"), let sheet = ws["sheet"], let r = ws["ref"], ws["r:id"] == nil {
                p.cachePath = cache
                p.source = Formula.quoteSheet(sheet) + "!" + r
                p.originalSource = p.source
            }
            for (j, i) in (root.child("rowItems")?.kids("i") ?? []).enumerated()
            where fields >= 2 && i["t"] == nil && (Int(i["r"] ?? "0") ?? 0) == 0 && i.kids("x").count < fields {
                p.subheadingRows.insert(ref.top + p.headerRows + j)
            }
            return p
        }
    }
}

extension PivotsXML {
    /// The spec of a file's pivot table, or nil when it uses anything the compact layout here would not reproduce.
    static func spec(_ root: XNode) -> PivotSpec? {
        func idx(_ n: XNode?, _ tag: String, _ attr: String) -> [Int] { (n?.kids(tag) ?? []).compactMap { Int($0[attr] ?? "") } }
        if root["compact"] == "0" || root["outline"] == "0" || root["rowGrandTotals"] == "0" || root["colGrandTotals"] == "0"
            || root["dataOnRows"] == "1" { return nil }
        let fields = root.child("pivotFields")?.kids("pivotField") ?? []
        for f in fields {
            if f["compact"] == "0" || f["outline"] == "0" || f["defaultSubtotal"] == "0" || f["sortType"] != nil && f["sortType"] != "manual"
                || f.child("fieldGroup") != nil || f["calculatedField"] == "1" { return nil }
            for i in f.child("items")?.kids("item") ?? [] where i["h"] == "1" || i["sd"] == "0" { return nil }
        }
        let rows = idx(root.child("rowFields"), "field", "x").filter { $0 >= 0 }
        let cols = idx(root.child("colFields"), "field", "x").filter { $0 >= 0 }
        var data: [PivotDataField] = []
        for d in root.child("dataFields")?.kids("dataField") ?? [] {
            guard let f = Int(d["fld"] ?? ""), d["showDataAs"] == nil || d["showDataAs"] == "normal", d["baseField"] == nil || d["baseField"] == "0" else { return nil }
            switch d["subtotal"] ?? "sum" {
            case "sum": data.append(PivotDataField(field: f, function: .sum))
            case "count": data.append(PivotDataField(field: f, function: .count))
            case "average": data.append(PivotDataField(field: f, function: .average))
            default: return nil
            }
        }
        var filters: [PivotFilter] = []
        for g in root.child("pageFields")?.kids("pageField") ?? [] {
            guard let f = Int(g["fld"] ?? ""), g["item"] == nil else { return nil }
            filters.append(PivotFilter(field: f, item: nil))
        }
        if rows.isEmpty || data.isEmpty { return nil }
        return PivotSpec(name: root["name"] ?? "PivotTable1", rows: rows, cols: cols, data: data, filters: filters, origin: CellAddress(row: 0, col: 0))
    }

    /// The groups of a cache's fields by source column, or nil when one is of a kind the pivot here cannot lay out (days, hours, groups
    /// stacked on one another, items grouped by hand).
    static func groups(cache: XNode) -> [Int: PivotGroup]? {
        var out: [Int: PivotGroup] = [:]
        let fields = cache.child("cacheFields")?.kids("cacheField") ?? []
        for (f, cf) in fields.enumerated() {
            guard let g = cf.child("fieldGroup") else { continue }
            if g["par"] != nil || g["base"].flatMap({ Int($0) }) != f || g.child("discretePr") != nil { return nil }
            guard let r = g.child("rangePr") else { return nil }
            switch r["groupBy"] ?? "range" {
            case "range":
                guard let a = Double(r["startNum"] ?? ""), let b = Double(r["endNum"] ?? ""), let by = Double(r["groupInterval"] ?? "1"), by > 0, b >= a else { return nil }
                out[f] = .numbers(start: a, end: b, by: by)
            case let u:
                guard let unit = PivotDateUnit(rawValue: u) else { return nil }
                out[f] = .dates(unit)
            }
        }
        return out
    }

    /// `'Sheet 1'!$A$1:$D$20` as the two attributes of a worksheetSource.
    static func splitSource(_ t: String) -> (sheet: String, ref: String)? {
        guard let bang = t.lastIndex(of: "!") else { return nil }
        var sheet = String(t[t.startIndex ..< bang])
        if sheet.hasPrefix("'"), sheet.hasSuffix("'"), sheet.count >= 2 { sheet = String(sheet.dropFirst().dropLast()).replacingAll("''", with: "'") }
        let ref = String(t[t.index(after: bang)...]).replacingAll("$", with: "")
        guard CellRange(ref) != nil else { return nil }
        return (sheet, ref)
    }

    /// The attribute `name="..."` of the first `<tag ...>` in `xml` set to `value` (escaped); nil when there is none.
    private static func setAttr(_ xml: String, tag: String, _ name: String, _ value: String) -> String? {
        guard let a = xml.findRange(of: "<" + tag), let end = xml.findRange(of: ">", in: a.upperBound ..< xml.endIndex),
              let k = xml.findRange(of: " " + name + "=\"", in: a.upperBound ..< end.lowerBound),
              let q = xml.findRange(of: "\"", in: k.upperBound ..< end.lowerBound) else { return nil }
        return String(xml[..<k.upperBound]) + Xlsx._esc(value) + String(xml[q.lowerBound...])
    }

    /// The pivot parts a save must change because the sheet's cells moved or its source sheet was renamed:
    /// nothing for a pivot whose source and place are as the file had them (those parts stay byte for byte).
    static func patched(sheets: [Worksheet], parts: [String: Data]) -> [String: Data] {
        var out: [String: Data] = [:]
        for ws in sheets {
            for p in ws.pivots {
                if let path = p.path, let ref = p.ref as CellRange?, let was = p.originalRef, ref != was,
                   let d = out[path] ?? parts[path], var x = Optional(String(decoding: d, as: UTF8.self)),
                   let y = setAttr(x, tag: "location", "ref", ref.a1) { x = y; out[path] = Data(x.utf8) }
                if p.refreshedHere, let cp = p.cachePath, let d = out[cp] ?? parts[cp] {
                    var x = String(decoding: d, as: UTF8.self)
                    if x.findRange(of: "refreshOnLoad=") == nil, let a = x.findRange(of: "<pivotCacheDefinition"),
                       let e = x.findRange(of: ">", in: a.upperBound ..< x.endIndex) {
                        x.insert(contentsOf: " refreshOnLoad=\"1\"", at: e.lowerBound)
                        out[cp] = Data(x.utf8)
                    }
                }
                if let cp = p.cachePath, let src = p.source, src != p.originalSource, let (sheet, ref) = splitSource(src),
                   let d = out[cp] ?? parts[cp] {
                    var x = String(decoding: d, as: UTF8.self)
                    if let y = setAttr(x, tag: "worksheetSource", "sheet", sheet) { x = y }
                    if let y = setAttr(x, tag: "worksheetSource", "ref", ref) { x = y }
                    out[cp] = Data(x.utf8)
                }
            }
        }
        return out
    }
}

/// Excel's built-in pivot styles, so far the family most files use.
enum PivotStyles {
    static func look(_ p: SheetPivot, _ a: CellAddress, theme: [UInt32]) -> TableCellLook? {
        guard p.ref.contains(a), let name = p.style, name.hasPrefix("PivotStyleLight"),
              let n = Int(name.dropFirst("PivotStyleLight".count)), (15 ... 21).contains(n) else { return nil }
        let k = (n - 1) % 7
        let base: UInt32 = k == 0 ? (theme.count > 1 ? theme[1] : 0) : (theme.count > k + 3 ? theme[k + 3] : 0x4472C4)
        // (Tinted in HSL, as Excel tints a theme colour: 4472C4 at 0.8 is
        // its D9E1F2, where mixing toward white made DAE3F3.)
        func tint(_ f: Double) -> UInt32 { Xlsx._tinted(base, f) }
        // Light 15-21: the headings and the grand total filled at a fifth
        // of the colour and bold, a rule at two fifths between them and
        // the rows (lo-forum-mso-de-104083's Light 16 in Excel's print:
        // DDEBF7 and 9BC2E6 over accent 5B9BD5).
        var x = TableCellLook()
        let header = a.row < p.ref.top + p.headerRows
        let total = p.grandTotalRow && a.row == p.ref.bottom && !header
        if header || total { x.fill = tint(0.8); x.bold = true }
        if header && a.row == p.ref.top + p.headerRows - 1 { x.bottom = tint(0.4) }
        if total { x.top = tint(0.4) }
        // (Each heading of an outer group bold and ruled off from its
        // items: lo-pivottable_outline_mode's "1" and "2".)
        if p.subheadingRows.contains(a.row) { x.bold = true; x.bottom = tint(0.4) }
        return x
    }
}

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
    static func look(_ t: SheetTable, _ a: CellAddress, theme: [UInt32], book: Workbook? = nil) -> TableCellLook? {
        guard t.ref.contains(a), let name = t.style else { return nil }
        if let parts = book?.tableStyles[name], let book { return custom(t, a, parts: parts, dxfs: book.dxfs) }
        guard name.hasPrefix("TableStyle") else { return nil }
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
            // An outline in the lines' tint, the header inside it, as the
            // file-defined copies of Medium 2 spell it out (lo-Book1_custom;
            // lo-tdf131380's right edge in Excel's print).
            if a.col == t.ref.left { x.left = tint(0.4) }
            if a.col == t.ref.right { x.right = tint(0.4) }
            if a.row == t.ref.top { x.top = tint(0.4) }
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

    /// A style the file defines: each part's differential format laid over
    /// the last, in Excel's order — the whole table, column stripes, row
    /// stripes, last and first columns, header and totals rows — its fill,
    /// font and the rules at that part's edges and between its cells
    /// (lo-Book1_custom's green stripes and blue header, printed plain).
    static func custom(_ t: SheetTable, _ a: CellAddress, parts: [String: Int], dxfs: [DxfStyle]) -> TableCellLook {
        let r = t.ref
        let header = t.headerRow && a.row == r.top
        let totals = t.totalsRow && a.row == r.bottom
        let body = CellRange(top: r.top + (t.headerRow ? 1 : 0), left: r.left, bottom: r.bottom - (t.totalsRow ? 1 : 0), right: r.right)
        let inBody = !header && !totals
        let dataRow = a.row - body.top, dataCol = a.col - r.left
        // The parts that hold the cell, each with the range it spans.
        var regions: [(String, CellRange)] = [("wholeTable", r)]
        if t.columnStripes {
            regions.append((dataCol % 2 == 0 ? "firstColumnStripe" : "secondColumnStripe",
                            CellRange(top: body.top, left: a.col, bottom: body.bottom, right: a.col)))
        }
        if t.rowStripes && inBody {
            regions.append((dataRow % 2 == 0 ? "firstRowStripe" : "secondRowStripe",
                            CellRange(top: a.row, left: r.left, bottom: a.row, right: r.right)))
        }
        if t.lastColumn && a.col == r.right { regions.append(("lastColumn", CellRange(top: r.top, left: r.right, bottom: r.bottom, right: r.right))) }
        if t.firstColumn && a.col == r.left { regions.append(("firstColumn", CellRange(top: r.top, left: r.left, bottom: r.bottom, right: r.left))) }
        if header { regions.append(("headerRow", CellRange(top: r.top, left: r.left, bottom: r.top, right: r.right))) }
        if totals { regions.append(("totalRow", CellRange(top: r.bottom, left: r.left, bottom: r.bottom, right: r.right))) }
        var x = TableCellLook()
        for (type, g) in regions {
            guard let d = parts[type], d >= 0, d < dxfs.count else { continue }
            let s = dxfs[d]
            if let f = s.fill { x.fill = f }
            if let b = s.bold { x.bold = b }
            if let c = s.color { x.color = c }
            let b = s.borders
            if let c = a.row == g.top ? b["top"] : b["horizontal"] { x.top = c }
            if let c = a.row == g.bottom ? b["bottom"] : b["horizontal"] { x.bottom = c }
            if let c = a.col == g.left ? b["left"] : b["vertical"] { x.left = c }
            if let c = a.col == g.right ? b["right"] : b["vertical"] { x.right = c }
        }
        return x
    }
}

// MARK: - Structured references

extension CalcEngine {
    /// `Table1[Amount]` and its kin, as cells: the table by name (or the
    /// one the formula sits in, for `[@Qty]`), the rows by special item
    /// (#All, #Data, #Headers, #Totals, #This Row / @), the columns by
    /// name or `[A]:[B]` span. Unknown tables or columns are #REF!.
    /// `evaluate`, except a structured reference stays a range even for one cell (ROW, COLUMN).
    func refValue(_ e: FormulaExpr, _ ctx: EvalContext) -> EvalValue {
        if case .structured(let t) = e { return resolveStructured(t, ctx, asRange: true) }
        return evaluate(e, ctx)
    }

    func resolveStructured(_ text: String, _ ctx: EvalContext, asRange: Bool = false) -> EvalValue {
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
        return range.isSingle && !asRange ? .scalar(value(si, range.topLeft)) : .range(sheet: si, range)
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
