// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert → PivotTable: a table made from a range. Its rows, columns, values (sum, count, average) and page filters are
// worked out here into ordinary cells (compact layout, as Excel lays one out) and written as Excel's own pivot parts
// (cache definition, cache records, pivot table), with the cache set to refresh when Excel opens the file.

import Foundation

enum PivotFunction: String, Sendable, CaseIterable {
    case sum, count, average
    var caption: String { self == .sum ? "Sum of " : self == .count ? "Count of " : "Average of " }
}

struct PivotDataField: Equatable, Sendable {
    var field: Int
    var function: PivotFunction
}

/// A page filter: the field, and the one item the table is cut to (nil: all).
struct PivotFilter: Equatable, Sendable {
    var field: Int
    var item: String? = nil
}

/// What a pivot made here is made of. Fields are column positions in the source range (0 = its first column).
struct PivotSpec: Equatable, Sendable {
    var name: String
    var rows: [Int]
    var cols: [Int]
    var data: [PivotDataField]
    var filters: [PivotFilter]
    /// Where the whole thing starts (its first page filter, or the table).
    var origin: CellAddress
}

enum PivotProblem: Equatable, Sendable {
    case noSource, sourceNeedsHeaders, needsRowField, needsValues, oneColumnField, columnFieldNeedsOneValue, fieldUsedTwice, destinationInsideSource, noSuchFilterItem, structureLocked

    var message: String {
        switch self {
        case .noSource: return "That is not a range on a sheet of this workbook."
        case .sourceNeedsHeaders: return "The range needs a heading in each column of its first row, and at least one row below."
        case .needsRowField: return "Choose at least one field for Rows."
        case .needsValues: return "Choose at least one field for Values."
        case .oneColumnField: return "A pivot table made here takes one field for Columns."
        case .columnFieldNeedsOneValue: return "With a field for Columns, choose exactly one field for Values."
        case .fieldUsedTwice: return "A field can be in Rows, Columns or Filters, not in two of them."
        case .destinationInsideSource: return "The pivot table cannot be placed over its own source."
        case .noSuchFilterItem: return "A filter's item is not among that field's values."
        case .structureLocked: return "The workbook's structure is protected: a new sheet cannot be added."
        }
    }
}

/// An item of a field as the pivot sees it: numbers first, then text (case does not matter), then blank.
struct PivotItem: Hashable, Comparable, Sendable {
    enum Kind: Int, Sendable { case number, text, blank }
    var kind: Kind
    var number = 0.0
    var text = ""
    var shown = ""

    init(_ v: CellValue) {
        switch v {
        case .empty: kind = .blank; shown = "(blank)"
        case .number(let n): kind = .number; number = n; shown = NumberFormat.display(v, "General", width: 255).text
        case .text(let s): kind = .text; text = s.lowercased(); shown = s
        case .bool(let b): kind = .text; text = b ? "true" : "false"; shown = b ? "TRUE" : "FALSE"
        case .error(let e): kind = .text; text = e.rawValue.lowercased(); shown = e.rawValue
        }
    }
    static func == (a: PivotItem, b: PivotItem) -> Bool { a.kind == b.kind && a.number == b.number && a.text == b.text }
    func hash(into h: inout Hasher) { h.combine(kind); h.combine(number); h.combine(text) }
    static func < (a: PivotItem, b: PivotItem) -> Bool {
        if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
        return a.kind == .number ? a.number < b.number : a.text < b.text
    }
}

/// The source range read: its headings and its rows.
struct PivotSource {
    var sheet: String
    var ref: CellRange
    var headers: [String]
    var rows: [[CellValue]]

    static func read(_ text: String, book: Workbook) -> PivotSource? {
        guard let (sheet, refText) = PivotsXML.splitSource(text), let ref = CellRange(refText),
              let ws = book.sheets.first(where: { $0.name.lowercased() == sheet.lowercased() }) else { return nil }
        var headers: [String] = []
        for c in ref.left ... ref.right {
            headers.append(NumberFormat.display(ws.value(CellAddress(row: ref.top, col: c)), "General", width: 255).text)
        }
        var rows: [[CellValue]] = []
        if ref.bottom > ref.top {
            for r in (ref.top + 1) ... ref.bottom { rows.append((ref.left ... ref.right).map { ws.value(CellAddress(row: r, col: $0)) }) }
        }
        return PivotSource(sheet: ws.name, ref: ref, headers: headers, rows: rows)
    }
}

/// A pivot table worked out: its cells, and the structure its XML needs.
struct PivotLayout {
    var cells: [CellAddress: CellValue] = [:]
    /// The table (without its page filters), and everything including them.
    var location = CellRange(top: 0, left: 0, bottom: 0, right: 0)
    var whole = CellRange(top: 0, left: 0, bottom: 0, right: 0)
    var firstHeaderRow = 1, firstDataRow = 1, firstDataCol = 1
    /// Each field's items, in the order the table shows them.
    var items: [Int: [PivotItem]] = [:]
    /// Row lines: (depth, item index) and the column items (item index into the column field).
    var rowLines: [(depth: Int, item: Int)] = []
    var colLines: [Int] = []
    var dataNames: [String] = []
    var headerRows: Int { firstDataRow }
}

enum PivotCalc {
    static func problem(_ spec: PivotSpec, _ src: PivotSource) -> PivotProblem? {
        if src.headers.isEmpty || src.rows.isEmpty { return .sourceNeedsHeaders }
        if spec.rows.isEmpty { return .needsRowField }
        if spec.data.isEmpty { return .needsValues }
        if spec.cols.count > 1 { return .oneColumnField }
        if !spec.cols.isEmpty && spec.data.count != 1 { return .columnFieldNeedsOneValue }
        let axes = spec.rows + spec.cols + spec.filters.map(\.field)
        if Set(axes).count != axes.count { return .fieldUsedTwice }
        if (axes + spec.data.map(\.field)).contains(where: { $0 < 0 || $0 >= src.headers.count }) { return .noSource }
        for f in spec.filters {
            if let i = f.item, !src.rows.contains(where: { PivotItem($0[f.field]).shown == i }) { return .noSuchFilterItem }
        }
        return nil
    }

    /// The items of every field used on an axis or as a filter.
    static func items(_ spec: PivotSpec, _ src: PivotSource) -> [Int: [PivotItem]] {
        var out: [Int: [PivotItem]] = [:]
        for f in spec.rows + spec.cols + spec.filters.map(\.field) {
            out[f] = Array(Set(src.rows.map { PivotItem($0[f]) })).sorted()
        }
        return out
    }

    private static func aggregate(_ recs: [[CellValue]], _ d: PivotDataField) -> CellValue {
        switch d.function {
        case .count: return recs.isEmpty ? .empty : .number(Double(recs.filter { !$0[d.field].isEmpty }.count))
        case .sum:
            let n = recs.compactMap { $0[d.field].number }
            return recs.isEmpty ? .empty : .number(n.reduce(0, +))
        case .average:
            let n = recs.compactMap { $0[d.field].number }
            return n.isEmpty ? .empty : .number(n.reduce(0, +) / Double(n.count))
        }
    }

    static func layout(_ spec: PivotSpec, _ src: PivotSource) -> PivotLayout {
        var out = PivotLayout()
        out.items = items(spec, src)
        out.dataNames = spec.data.map { $0.function.caption + src.headers[$0.field] }
        var recs = src.rows
        for f in spec.filters { if let i = f.item { recs = recs.filter { PivotItem($0[f.field]).shown == i } } }

        // Rows, in the order the table shows them.
        struct Line { var depth: Int; var item: Int; var label: String; var recs: [[CellValue]] }
        var lines: [Line] = []
        func walk(_ rs: [[CellValue]], _ depth: Int) {
            let f = spec.rows[depth]
            let its = out.items[f] ?? []
            var groups: [PivotItem: [[CellValue]]] = [:]
            for r in rs { groups[PivotItem(r[f]), default: []].append(r) }
            for (k, it) in its.enumerated() {
                guard let g = groups[it] else { continue }
                lines.append(Line(depth: depth, item: k, label: it.shown, recs: g))
                if depth + 1 < spec.rows.count { walk(g, depth + 1) }
            }
        }
        walk(recs, 0)
        out.rowLines = lines.map { ($0.depth, $0.item) }

        var colItemsShown: [(item: Int, it: PivotItem)] = []
        if let cf = spec.cols.first {
            let present = Set(recs.map { PivotItem($0[cf]) })
            for (k, it) in (out.items[cf] ?? []).enumerated() where present.contains(it) { colItemsShown.append((k, it)) }
            out.colLines = colItemsShown.map(\.item)
        }

        let pageRows = spec.filters.isEmpty ? 0 : spec.filters.count + 1
        let top = spec.origin.row + pageRows, left = spec.origin.col
        var grid: [[CellValue]] = []
        if spec.cols.isEmpty {
            out.firstHeaderRow = spec.data.count > 1 ? 0 : 1
            out.firstDataRow = 1
            grid.append([.text("Row Labels")] + out.dataNames.map { .text($0) })
            for l in lines { grid.append([.text(l.label)] + spec.data.map { aggregate(l.recs, $0) }) }
            grid.append([.text("Grand Total")] + spec.data.map { aggregate(recs, $0) })
        } else {
            out.firstHeaderRow = 1
            out.firstDataRow = 2
            let d = spec.data[0]
            grid.append([.text(out.dataNames[0]), .text("Column Labels")] + Array(repeating: .empty, count: colItemsShown.count))
            grid.append([.text("Row Labels")] + colItemsShown.map { .text($0.it.shown) } + [.text("Grand Total")])
            let cf = spec.cols[0]
            for l in lines {
                grid.append([.text(l.label)] + colItemsShown.map { c in aggregate(l.recs.filter { PivotItem($0[cf]) == c.it }, d) } + [aggregate(l.recs, d)])
            }
            grid.append([.text("Grand Total")] + colItemsShown.map { c in aggregate(recs.filter { PivotItem($0[cf]) == c.it }, d) } + [aggregate(recs, d)])
        }
        out.firstDataCol = 1
        let width = grid.map(\.count).max() ?? 1
        for (r, row) in grid.enumerated() {
            for c in 0 ..< width {
                let v = c < row.count ? row[c] : .empty
                if !v.isEmpty { out.cells[CellAddress(row: top + r, col: left + c)] = v }
            }
        }
        // Page filters above the table: the field and the item (or "(All)").
        for (k, f) in spec.filters.enumerated() {
            out.cells[CellAddress(row: spec.origin.row + k, col: left)] = .text(src.headers[f.field])
            out.cells[CellAddress(row: spec.origin.row + k, col: left + 1)] = .text(f.item ?? "(All)")
        }
        out.location = CellRange(top: top, left: left, bottom: top + grid.count - 1, right: left + width - 1)
        out.whole = CellRange(top: spec.origin.row, left: left, bottom: out.location.bottom, right: max(out.location.right, spec.filters.isEmpty ? 0 : left + 1))
        return out
    }
}

// MARK: - The Excel parts

enum PivotWriter {
    private static func esc(_ s: String) -> String { Xlsx._esc(s) }
    private static func num(_ n: Double) -> String { Xlsx._num(n) }
    private static let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    private static func itemXML(_ it: PivotItem) -> String {
        switch it.kind {
        case .number: return "<n v=\"\(num(it.number))\"/>"
        case .text: return "<s v=\"\(esc(it.shown))\"/>"
        case .blank: return "<m/>"
        }
    }

    /// The cache definition: every field with its heading, the axis fields with their items.
    static func cacheDefinition(_ spec: PivotSpec, _ src: PivotSource, items: [Int: [PivotItem]], relId: String) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<pivotCacheDefinition xmlns=\"\(main)\" xmlns:r=\"\(rel)\" r:id=\"\(relId)\""
        s += " refreshOnLoad=\"1\" refreshedBy=\"Starling\" refreshedDate=\"0\" createdVersion=\"6\" refreshedVersion=\"6\" minRefreshableVersion=\"3\" recordCount=\"\(src.rows.count)\">"
        s += "<cacheSource type=\"worksheet\"><worksheetSource ref=\"\(esc(src.ref.a1))\" sheet=\"\(esc(src.sheet))\"/></cacheSource>"
        s += "<cacheFields count=\"\(src.headers.count)\">"
        for (f, h) in src.headers.enumerated() {
            let col = src.rows.map { $0[f] }
            let nums = col.compactMap(\.number)
            let hasText = col.contains { if case .text = $0 { return true }; if case .bool = $0 { return true }; if case .error = $0 { return true }; return false }
            let hasBlank = col.contains(where: \.isEmpty)
            var a = ""
            if !nums.isEmpty {
                if !hasText {
                    a = hasBlank ? " containsString=\"0\" containsBlank=\"1\" containsNumber=\"1\"" : " containsSemiMixedTypes=\"0\" containsString=\"0\" containsNumber=\"1\""
                } else {
                    a = " containsMixedTypes=\"1\" containsNumber=\"1\"" + (hasBlank ? " containsBlank=\"1\"" : "")
                }
                if nums.allSatisfy({ $0 == $0.rounded() && abs($0) < 1e15 }) { a += " containsInteger=\"1\"" }
                a += " minValue=\"\(num(nums.min()!))\" maxValue=\"\(num(nums.max()!))\""
            } else if hasBlank {
                a = hasText ? " containsBlank=\"1\"" : " containsString=\"0\" containsBlank=\"1\""
            }
            s += "<cacheField name=\"\(esc(h))\" numFmtId=\"0\">"
            if let its = items[f] { s += "<sharedItems\(a) count=\"\(its.count)\">" + its.map(itemXML).joined() + "</sharedItems>" }
            else { s += "<sharedItems\(a)/>" }
            s += "</cacheField>"
        }
        return s + "</cacheFields></pivotCacheDefinition>"
    }

    static func cacheRecords(_ src: PivotSource, items: [Int: [PivotItem]]) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<pivotCacheRecords xmlns=\"\(main)\" xmlns:r=\"\(rel)\" count=\"\(src.rows.count)\">"
        var index: [Int: [PivotItem: Int]] = [:]
        for (f, its) in items { index[f] = Dictionary(uniqueKeysWithValues: its.enumerated().map { ($1, $0) }) }
        for r in src.rows {
            s += "<r>"
            for (f, v) in r.enumerated() {
                if let k = index[f]?[PivotItem(v)] { s += "<x v=\"\(k)\"/>"; continue }
                switch v {
                case .number(let n): s += "<n v=\"\(num(n))\"/>"
                case .text(let t): s += "<s v=\"\(esc(t))\"/>"
                case .bool(let b): s += "<b v=\"\(b ? 1 : 0)\"/>"
                case .error(let e): s += "<e v=\"\(esc(e.rawValue))\"/>"
                case .empty: s += "<m/>"
                }
            }
            s += "</r>"
        }
        return s + "</pivotCacheRecords>"
    }

    static func table(_ spec: PivotSpec, _ src: PivotSource, _ lay: PivotLayout, cacheId: Int, style: String) -> String {
        let loc = lay.location
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<pivotTableDefinition xmlns=\"\(main)\" name=\"\(esc(spec.name))\" cacheId=\"\(cacheId)\""
        s += " applyNumberFormats=\"0\" applyBorderFormats=\"0\" applyFontFormats=\"0\" applyPatternFormats=\"0\" applyAlignmentFormats=\"0\" applyWidthHeightFormats=\"1\""
        s += " dataCaption=\"Values\" updatedVersion=\"6\" minRefreshableVersion=\"3\" useAutoFormatting=\"1\" itemPrintTitles=\"1\" createdVersion=\"6\" indent=\"0\" outline=\"1\" outlineData=\"1\" multipleFieldFilters=\"0\""
        if spec.data.count > 1 { s += " dataOnRows=\"0\"" }
        s += ">"
        s += "<location ref=\"\(loc.a1)\" firstHeaderRow=\"\(lay.firstHeaderRow)\" firstDataRow=\"\(lay.firstDataRow)\" firstDataCol=\"\(lay.firstDataCol)\""
        if !spec.filters.isEmpty { s += " rowPageCount=\"\(spec.filters.count)\" colPageCount=\"1\"" }
        s += "/>"
        s += "<pivotFields count=\"\(src.headers.count)\">"
        for f in src.headers.indices {
            let axis = spec.rows.contains(f) ? "axisRow" : spec.cols.contains(f) ? "axisCol" : spec.filters.contains { $0.field == f } ? "axisPage" : nil
            var a = ""
            if let axis { a += " axis=\"\(axis)\"" }
            if spec.data.contains(where: { $0.field == f }) { a += " dataField=\"1\"" }
            if let its = lay.items[f] {
                s += "<pivotField\(a) showAll=\"0\"><items count=\"\(its.count + 1)\">" + its.indices.map { "<item x=\"\($0)\"/>" }.joined() + "<item t=\"default\"/></items></pivotField>"
            } else { s += "<pivotField\(a) showAll=\"0\"/>" }
        }
        s += "</pivotFields>"
        s += "<rowFields count=\"\(spec.rows.count)\">" + spec.rows.map { "<field x=\"\($0)\"/>" }.joined() + "</rowFields>"
        func x(_ v: Int) -> String { v == 0 ? "<x/>" : "<x v=\"\(v)\"/>" }
        s += "<rowItems count=\"\(lay.rowLines.count + 1)\">"
        for l in lay.rowLines { s += "<i" + (l.depth > 0 ? " r=\"\(l.depth)\"" : "") + ">" + x(l.item) + "</i>" }
        s += "<i t=\"grand\"><x/></i></rowItems>"
        if let cf = spec.cols.first {
            s += "<colFields count=\"1\"><field x=\"\(cf)\"/></colFields><colItems count=\"\(lay.colLines.count + 1)\">"
            for c in lay.colLines { s += "<i>" + x(c) + "</i>" }
            s += "<i t=\"grand\"><x/></i></colItems>"
        } else if spec.data.count > 1 {
            s += "<colFields count=\"1\"><field x=\"-2\"/></colFields><colItems count=\"\(spec.data.count)\">"
            for k in spec.data.indices { s += "<i" + (k > 0 ? " i=\"\(k)\"" : "") + ">" + x(k) + "</i>" }
            s += "</colItems>"
        } else { s += "<colItems count=\"1\"><i/></colItems>" }
        if !spec.filters.isEmpty {
            s += "<pageFields count=\"\(spec.filters.count)\">"
            for f in spec.filters {
                let k = f.item.flatMap { it in lay.items[f.field]?.firstIndex(where: { $0.shown == it }) }
                s += "<pageField fld=\"\(f.field)\"" + (k.map { " item=\"\($0)\"" } ?? "") + " hier=\"-1\"/>"
            }
            s += "</pageFields>"
        }
        s += "<dataFields count=\"\(spec.data.count)\">"
        for (k, d) in spec.data.enumerated() {
            s += "<dataField name=\"\(esc(lay.dataNames[k]))\" fld=\"\(d.field)\"" + (d.function == .sum ? "" : " subtotal=\"\(d.function.rawValue)\"") + " baseField=\"0\" baseItem=\"0\"/>"
        }
        s += "</dataFields>"
        s += "<pivotTableStyleInfo name=\"\(esc(style))\" showRowHeaders=\"1\" showColHeaders=\"1\" showRowStripes=\"0\" showColStripes=\"0\" showLastColumn=\"1\"/>"
        return s + "</pivotTableDefinition>"
    }
}

// MARK: - The controller

extension WorkbookController {
    /// The headings of a source range (for the dialog's field list), or nil when it is not a range of this book.
    func pivotFields(source: String) -> [String]? {
        PivotSource.read(source, book: book).map(\.headers)
    }

    /// Insert a pivot table: one undoable step. `newSheet` puts it on a new sheet (at `origin`), else on the active sheet.
    @discardableResult
    func insertPivotTable(source: String, rows: [Int], cols: [Int], data: [PivotDataField], filters: [PivotFilter],
                          origin: CellAddress, newSheet: Bool) -> PivotProblem? {
        if newSheet && book.structureLocked { return .structureLocked }
        guard let src = PivotSource.read(source, book: book), let (sheetName, refText) = PivotsXML.splitSource(source), CellRange(refText) != nil else { return .noSource }
        var spec = PivotSpec(name: "", rows: rows, cols: cols, data: data, filters: filters, origin: origin)
        if let p = PivotCalc.problem(spec, src) { return p }
        let canon = Formula.quoteSheet(src.sheet) + "!" + src.ref.a1
        _ = sheetName
        if !newSheet {
            let lay = PivotCalc.layout(spec, src)
            if sheet.name == src.sheet, lay.whole.top <= src.ref.bottom, lay.whole.bottom >= src.ref.top, lay.whole.left <= src.ref.right, lay.whole.right >= src.ref.left {
                return .destinationInsideSource
            }
        }
        spec.name = "PivotTable\(1 + book.sheets.reduce(0) { $0 + $1.pivots.count })"
        let lay = PivotCalc.layout(spec, src)
        structural {
            if newSheet { _insertFreshSheet() }
            let target = sheet
            _writePivot(lay, on: target, replacing: nil)
            var p = SheetPivot(ref: lay.location, headerRows: lay.firstDataRow, grandTotalRow: true, style: "PivotStyleLight16")
            p.source = canon
            p.made = spec
            target.pivots.append(p)
        }
        return nil
    }

    /// Cells of a pivot written (the old ones, if it is being refreshed, cleared first).
    func _writePivot(_ lay: PivotLayout, on ws: Worksheet, replacing old: CellRange?) {
        if let old {
            for r in old.top ... old.bottom { for c in old.left ... old.right { ws.cells[CellAddress(row: r, col: c)] = nil } }
        }
        for (a, v) in lay.cells {
            var c = ws.cells[a] ?? Cell(input: "")
            c.formula = nil; c.arrayRef = nil; c.rawFormula = nil
            c.input = NumberFormat.display(v, "General", width: 255).text
            c.value = v; c.cached = v
            ws.cells[a] = c
        }
    }

    /// Refresh the pivot tables made here from their sources as they are now; returns how many were refreshed.
    /// (A pivot table that came with a file is kept as the file had it, and Excel refreshes it.)
    @discardableResult
    func refreshPivots() -> Int {
        var n = 0
        structural {
            for ws in book.sheets {
                for k in ws.pivots.indices {
                    guard let made = ws.pivots[k].made, let s = ws.pivots[k].source, let src = PivotSource.read(s, book: book),
                          PivotCalc.problem(made, src) == nil else { continue }
                    // Where it stands now (rows may have been inserted above it since it was made).
                    var spec = made
                    let pageRows = spec.filters.isEmpty ? 0 : spec.filters.count + 1
                    var old = ws.pivots[k].ref
                    spec.origin = CellAddress(row: old.top - pageRows, col: old.left)
                    if pageRows > 0 { old = CellRange(top: spec.origin.row, left: old.left, bottom: old.bottom, right: max(old.right, old.left + 1)) }
                    let lay = PivotCalc.layout(spec, src)
                    ws.pivots[k].made = spec
                    _writePivot(lay, on: ws, replacing: old)
                    ws.pivots[k].ref = lay.location
                    n += 1
                }
            }
        }
        return n
    }
}

/// The parts of one pivot table made here, and where they go in the package.
struct MadePivotParts {
    var sheet: Int
    var spec: PivotSpec
    var src: PivotSource
    var location: CellRange
    var style: String
    var table: String, cache: String, records: String
    var cacheId: Int
    /// The workbook's relationship id for the cache definition.
    var workbookRel: String

    /// Every part this pivot adds (the sheet's and the workbook's relationships are added by the writer).
    func parts() -> [(String, String)] {
        var lay = PivotCalc.layout(spec, src)
        lay.location = location
        let items = lay.items
        func name(_ p: String) -> String { String(p[p.index(after: p.lastIndex(of: "/")!)...]) }
        func rels(_ type: String, _ target: String) -> String {
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\(type)\" Target=\"\(target)\"/></Relationships>"
        }
        return [
            (cache, PivotWriter.cacheDefinition(spec, src, items: items, relId: "rId1")),
            ("xl/pivotCache/_rels/" + name(cache) + ".rels", rels("pivotCacheRecords", name(records))),
            (records, PivotWriter.cacheRecords(src, items: items)),
            (table, PivotWriter.table(spec, src, lay, cacheId: cacheId, style: style)),
            ("xl/pivotTables/_rels/" + name(table) + ".rels", rels("pivotCacheDefinition", "../pivotCache/" + name(cache))),
        ]
    }
}
