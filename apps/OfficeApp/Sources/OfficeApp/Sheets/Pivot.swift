// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert → PivotTable: a table made from a range. Its rows, columns, values (sum, count, average) and page filters are
// worked out here into ordinary cells (compact layout, as Excel lays one out) and written as Excel's own pivot parts
// (cache definition, cache records, pivot table), with the cache set to refresh when Excel opens the file.

import Foundation

enum PivotFunction: String, Sendable, CaseIterable {
    case sum, count, average, min, max
    var caption: String {
        switch self { case .sum: return "Sum of "; case .count: return "Count of "; case .average: return "Average of "; case .min: return "Min of "; case .max: return "Max of " }
    }
    /// The name Value Field Settings lists.
    var title: String {
        switch self { case .sum: return "Sum"; case .count: return "Count"; case .average: return "Average"; case .min: return "Min"; case .max: return "Max" }
    }
}

/// Show Values As: the figure itself, or its share of the grand total, of its row's total or of its column's total.
enum PivotShowAs: String, Sendable, CaseIterable {
    case normal, percentOfTotal, percentOfRow, percentOfCol
    var title: String {
        switch self {
        case .normal: return "No Calculation"; case .percentOfTotal: return "% of Grand Total"
        case .percentOfRow: return "% of Row Total"; case .percentOfCol: return "% of Column Total"
        }
    }
}

struct PivotDataField: Equatable, Sendable {
    var field: Int
    var function: PivotFunction
    /// The heading Value Field Settings gave it (nil: "Sum of Sales" and so on).
    var name: String? = nil
    /// A number format code for its cells (nil: General, or the percentage format Show Values As implies).
    var numberFormat: String? = nil
    var showAs: PivotShowAs = .normal
    /// The format its cells wear: the one chosen, else 0.00% for a share, else none.
    var cellFormat: String? { numberFormat ?? (showAs == .normal ? nil : "0.00%") }
}

/// A page filter: the field, and the one item the table is cut to (nil: all).
struct PivotFilter: Equatable, Sendable {
    var field: Int
    var item: String? = nil
}

/// What a pivot made here is made of. Fields are column positions in the source range (0 = its first column).
struct PivotSpec: Equatable, Sendable {
    /// Whether Insert PivotTable offers Filters (page fields): on again: the Excel crash on page-field pivots under COM refresh also hits Excel's own files
    /// (other-4efc4d8920, es-b129c8bac2), so it is that build, not what we write.
    static let offersFilters = true
    var name: String
    var rows: [Int]
    var cols: [Int]
    var data: [PivotDataField]
    var filters: [PivotFilter]
    /// Where the whole thing starts (its first page filter, or the table).
    var origin: CellAddress
    /// Fields grouped into number ranges or date parts (Excel keeps this with the cache, so every pivot on one source has the same).
    var groups: [Int: PivotGroup] = [:]
}

enum PivotDateUnit: String, Sendable, CaseIterable {
    case years, quarters, months
    var title: String { switch self { case .years: return "Years"; case .quarters: return "Quarters"; case .months: return "Months" } }
}

/// A field grouped by number ranges (`start` up to `end`, `by` wide) or by a part of a date.
enum PivotGroup: Equatable, Sendable {
    case numbers(start: Double, end: Double, by: Double)
    case dates(PivotDateUnit)

    /// The items of a grouped field, in order, empty ones included: "<first", the groups, ">last". Item `i` is group `i`.
    func items(_ values: [CellValue]) -> [PivotItem] {
        let nums = values.compactMap(\.number)
        func mk(_ labels: [String]) -> [PivotItem] { labels.enumerated().map { PivotItem(index: $0, label: $1) } }
        switch self {
        case .numbers(let start, let end, let by):
            guard by > 0, end >= start else { return [] }
            var labels = ["<" + PivotCalc.numText(start)]
            let whole = start == start.rounded() && by == by.rounded()
            for k in 0 ..< Self.bucketCount(start, end, by) {
                let lo = start + Double(k) * by
                // (The last bucket runs on to the end, inclusive, as in Excel.)
                let hi = lo + by >= end ? end : (whole ? lo + by - 1 : lo + by)
                labels.append(PivotCalc.numText(lo) + "-" + PivotCalc.numText(hi))
            }
            labels.append(">" + PivotCalc.numText(end))
            return mk(labels)
        case .dates(let unit):
            guard let lo = nums.min(), let hi = nums.max() else { return [] }
            let (y0, _, _) = ExcelDate.ymd(lo), (y1, _, _) = ExcelDate.ymd(hi)
            let first = "<" + PivotCalc.dateText(lo), last = ">" + PivotCalc.dateText(hi)
            switch unit {
            case .years: return mk([first] + (y0 ... y1).map { String($0) } + [last])
            case .quarters: return mk([first, "Qtr1", "Qtr2", "Qtr3", "Qtr4", last])
            case .months: return mk([first] + ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] + [last])
            }
        }
    }

    static func bucketCount(_ start: Double, _ end: Double, _ by: Double) -> Int {
        var n = 1
        while start + Double(n) * by < end { n += 1 }
        return n
    }

    /// The index of the group a value falls in (see `items`), or nil when it is not a number.
    func index(of v: CellValue, minYear: Int) -> Int? {
        guard let x = v.number else { return nil }
        switch self {
        case .numbers(let start, let end, let by):
            let n = Self.bucketCount(start, end, by)
            if x < start { return 0 }
            if x > end { return n + 1 }
            return min(1 + Int(((x - start) / by).rounded(.down)), n)
        case .dates(let unit):
            let (y, m, _) = ExcelDate.ymd(x)
            switch unit {
            case .years: return 1 + y - minYear
            case .quarters: return 1 + (m - 1) / 3
            case .months: return m
            }
        }
    }
}

enum PivotProblem: Equatable, Sendable {
    case noSource, sourceNeedsHeaders, needsRowField, needsValues, fieldUsedTwice, destinationInsideSource, noSuchFilterItem, structureLocked, cannotGroup

    var message: String {
        switch self {
        case .noSource: return "That is not a range on a sheet of this workbook."
        case .sourceNeedsHeaders: return "The range needs a heading in each column of its first row, and at least one row below."
        case .needsRowField: return "Choose at least one field for Rows."
        case .needsValues: return "Choose at least one field for Values."
        case .fieldUsedTwice: return "A field can be in Rows, Columns or Filters, not in two of them."
        case .destinationInsideSource: return "The pivot table cannot be placed over its own source."
        case .noSuchFilterItem: return "A filter's item is not among that field's values."
        case .cannotGroup: return "That field cannot be grouped like that: it needs numbers or dates, and a start, an end and a step that fit."
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
    /// A group of a grouped field: `index` puts it in order, `label` is what the table shows.
    init(index: Int, label: String) { kind = .number; number = Double(index); shown = label }
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
    /// The number format of data cells that have their own (a field's format, or a percentage).
    var formats: [CellAddress: String] = [:]
    /// Cells Excel draws as field buttons (it styles them `pivotButton`).
    var buttons: Set<CellAddress> = []
    /// The table (without its page filters), and everything including them.
    var location = CellRange(top: 0, left: 0, bottom: 0, right: 0)
    var whole = CellRange(top: 0, left: 0, bottom: 0, right: 0)
    var firstHeaderRow = 1, firstDataRow = 1, firstDataCol = 1
    /// Each field's items, in the order the table shows them.
    var items: [Int: [PivotItem]] = [:]
    /// Row lines: (depth, item index). Column nodes, left to right: a leaf (every column field chosen) or the
    /// subtotal of an outer item, with the item index chosen at each column field so far.
    var rowLines: [(depth: Int, item: Int)] = []
    var colNodes: [(subtotal: Bool, path: [Int])] = []
    var dataNames: [String] = []
    var headerRows: Int { firstDataRow }
}

enum PivotCalc {
    static func numText(_ n: Double) -> String { NumberFormat.display(.number(n), "General", width: 255).text }
    static func dateText(_ serial: Double) -> String { let (y, m, d) = ExcelDate.ymd(serial); return "\(m)/\(d)/\(y)" }

    /// The item a source value goes to in field `f`: its group when the field is grouped.
    static func key(_ v: CellValue, _ f: Int, _ spec: PivotSpec, _ src: PivotSource) -> PivotItem {
        guard let g = spec.groups[f] else { return PivotItem(v) }
        let items = groupItems(spec, src, f) ?? []
        let minYear = src.rows.compactMap { $0[f].number }.min().map { ExcelDate.ymd($0).0 } ?? 0
        if let i = g.index(of: v, minYear: minYear), items.indices.contains(i) { return items[i] }
        return PivotItem(v)
    }

    static func groupItems(_ spec: PivotSpec, _ src: PivotSource, _ f: Int) -> [PivotItem]? {
        spec.groups[f]?.items(src.rows.map { $0[f] })
    }

    static func problem(_ spec: PivotSpec, _ src: PivotSource) -> PivotProblem? {
        if src.headers.isEmpty || src.rows.isEmpty { return .sourceNeedsHeaders }
        if spec.rows.isEmpty { return .needsRowField }
        if spec.data.isEmpty { return .needsValues }
        let axes = spec.rows + spec.cols + spec.filters.map(\.field)
        if Set(axes).count != axes.count { return .fieldUsedTwice }
        if (axes + spec.data.map(\.field)).contains(where: { $0 < 0 || $0 >= src.headers.count }) { return .noSource }
        for f in spec.filters {
            if let i = f.item, !src.rows.contains(where: { key($0[f.field], f.field, spec, src).shown == i }) { return .noSuchFilterItem }
        }
        return nil
    }

    /// The items of every field used on an axis or as a filter.
    static func items(_ spec: PivotSpec, _ src: PivotSource) -> [Int: [PivotItem]] {
        var out: [Int: [PivotItem]] = [:]
        for f in spec.rows + spec.cols + spec.filters.map(\.field) {
            if let g = groupItems(spec, src, f) { out[f] = g; continue }
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
        case .min: return recs.compactMap { $0[d.field].number }.min().map { .number($0) } ?? .empty
        case .max: return recs.compactMap { $0[d.field].number }.max().map { .number($0) } ?? .empty
        }
    }

    static func layout(_ spec: PivotSpec, _ src: PivotSource) -> PivotLayout {
        var out = PivotLayout()
        out.items = items(spec, src)
        out.dataNames = spec.data.map { $0.name ?? $0.function.caption + src.headers[$0.field] }
        var recs = src.rows
        for f in spec.filters { if let i = f.item { recs = recs.filter { key($0[f.field], f.field, spec, src).shown == i } } }

        // Rows, in the order the table shows them.
        struct Line { var depth: Int; var item: Int; var label: String; var recs: [[CellValue]] }
        var lines: [Line] = []
        func walk(_ rs: [[CellValue]], _ depth: Int) {
            let f = spec.rows[depth]
            let its = out.items[f] ?? []
            var groups: [PivotItem: [[CellValue]]] = [:]
            for r in rs { groups[key(r[f], f, spec, src), default: []].append(r) }
            for (k, it) in its.enumerated() {
                guard let g = groups[it] else { continue }
                lines.append(Line(depth: depth, item: k, label: it.shown, recs: g))
                if depth + 1 < spec.rows.count { walk(g, depth + 1) }
            }
        }
        walk(recs, 0)
        out.rowLines = lines.map { ($0.depth, $0.item) }

        let pageRows = spec.filters.isEmpty ? 0 : spec.filters.count + 1
        let top = spec.origin.row + pageRows, left = spec.origin.col
        var grid: [[CellValue]] = []
        if spec.cols.isEmpty {
            // Several values: Excel puts a "Values" caption row above the headings.
            let several = spec.data.count > 1
            out.firstHeaderRow = 1
            out.firstDataRow = several ? 2 : 1
            if several { grid.append([.empty, .text("Values")] + Array(repeating: .empty, count: spec.data.count - 1)) }
            grid.append([.text("Row Labels")] + out.dataNames.map { .text($0) })
            for l in lines { grid.append([.text(l.label)] + spec.data.map { aggregate(l.recs, $0) }) }
            grid.append([.text("Grand Total")] + spec.data.map { aggregate(recs, $0) })
        } else {
            // Column fields: a tree like the rows, but an outer item's subtotal comes after its items.
            struct ColNode { var subtotal: Bool; var path: [Int]; var label: String; var recs: [[CellValue]] }
            var nodes: [ColNode] = []
            let n = spec.cols.count
            func walkCols(_ rs: [[CellValue]], _ depth: Int, _ path: [Int]) {
                let f = spec.cols[depth]
                var groups: [PivotItem: [[CellValue]]] = [:]
                for r in rs { groups[key(r[f], f, spec, src), default: []].append(r) }
                for (k, it) in (out.items[f] ?? []).enumerated() {
                    guard let g = groups[it] else { continue }
                    if depth + 1 < n {
                        walkCols(g, depth + 1, path + [k])
                        nodes.append(ColNode(subtotal: true, path: path + [k], label: it.shown + " Total", recs: g))
                    } else {
                        nodes.append(ColNode(subtotal: false, path: path + [k], label: it.shown, recs: g))
                    }
                }
            }
            walkCols(recs, 0, [])
            out.colNodes = nodes.map { ($0.subtotal, $0.path) }
            let several = spec.data.count > 1
            let v = several ? spec.data.count : 1
            let headerRows = 1 + n + (several ? 1 : 0)
            out.firstHeaderRow = 1
            out.firstDataRow = headerRows
            let width = 1 + (nodes.count + 1) * v
            func blankRow() -> [CellValue] { Array(repeating: .empty, count: width) }
            var head = (0 ..< headerRows).map { _ in blankRow() }
            head[0][0] = several ? .empty : .text(out.dataNames[0])
            head[0][1] = .text("Column Labels")
            head[headerRows - 1][0] = .text("Row Labels")
            var seen = Set<[Int]>()
            for (i, nd) in nodes.enumerated() {
                let c0 = 1 + i * v
                // The outer items' labels sit over the first column of their group.
                for d in 0 ..< n - 1 where !seen.contains(Array(nd.path.prefix(d + 1))) {
                    seen.insert(Array(nd.path.prefix(d + 1)))
                    if nd.path.count > d { head[1 + d][c0] = .text(out.items[spec.cols[d]]![nd.path[d]].shown) }
                }
                head[1 + (nd.subtotal ? nd.path.count - 1 : n - 1)][c0] = .text(nd.label)
                if several { for k in 0 ..< v { head[headerRows - 1][c0 + k] = .text(out.dataNames[k]) } }
            }
            let g0 = 1 + nodes.count * v
            for k in 0 ..< v { head[1][g0 + k] = .text(several ? "Total " + out.dataNames[k] : "Grand Total") }
            grid += head
            func line(_ label: String, _ rs: [[CellValue]]) -> [CellValue] {
                var row: [CellValue] = [.text(label)]
                for nd in nodes { for k in 0 ..< v { row.append(aggregate(rs.filter { r in nd.path.indices.allSatisfy { key(r[spec.cols[$0]], spec.cols[$0], spec, src) == out.items[spec.cols[$0]]![nd.path[$0]] } }, spec.data[k])) } }
                for k in 0 ..< v { row.append(aggregate(rs, spec.data[k])) }
                return row
            }
            for l in lines { grid.append(line(l.label, l.recs)) }
            grid.append(line("Grand Total", recs))
        }
        out.firstDataCol = 1
        // Show Values As: replace each data cell by its share of the grand total, its row's total or its column's total.
        if spec.data.contains(where: { $0.showAs != .normal }), grid.count > out.firstDataRow {
            let v = spec.data.count, last = grid.count - 1
            let g0 = spec.cols.isEmpty ? nil : 1 + out.colNodes.count * v
            let old = grid
            for r in out.firstDataRow ... last {
                for c in 1 ..< old[r].count {
                    let k = spec.cols.isEmpty ? c - 1 : (c - 1) % v
                    guard k < v, let x = old[r][c].number else { continue }
                    let rowTotal = g0.flatMap { old[r][$0 + k].number }
                    let colTotal = old[last][c].number
                    let grand = old[last][g0 ?? 1 + k].number
                    let den: Double?
                    switch spec.data[k].showAs {
                    case .normal: continue
                    case .percentOfTotal: den = grand
                    case .percentOfRow: den = g0 == nil ? x : rowTotal
                    case .percentOfCol: den = colTotal
                    }
                    if let den, den != 0 { grid[r][c] = .number(x / den) } else { grid[r][c] = .empty }
                }
            }
        }
        // Per-field number formats.
        for r in out.firstDataRow ..< grid.count {
            for c in 1 ..< grid[r].count {
                let v = spec.data.count, k = spec.cols.isEmpty ? c - 1 : (c - 1) % v
                if k < v, let f = spec.data[k].cellFormat { out.formats[CellAddress(row: top + r, col: left + c)] = f }
            }
        }
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
            out.buttons.insert(CellAddress(row: spec.origin.row + k, col: left))
            out.cells[CellAddress(row: spec.origin.row + k, col: left + 1)] = .text(f.item ?? "(All)")
        }
        for (r, row) in grid.enumerated() { for (c, v) in row.enumerated() where v == .text("Row Labels") || v == .text("Column Labels") { out.buttons.insert(CellAddress(row: top + r, col: left + c)) } }
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

    private static func isoDate(_ serial: Double) -> String {
        let (y, m, d) = ExcelDate.ymd(serial)
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(y)-\(two(m))-\(two(d))T00:00:00"
    }

    private static func itemXML(_ it: PivotItem, date: Bool = false) -> String {
        switch it.kind {
        case .number where date: return "<d v=\"\(isoDate(it.number))\"/>"
        case .number: return "<n v=\"\(num(it.number))\"/>"
        case .text: return "<s v=\"\(esc(it.shown))\"/>"
        case .blank: return "<m/>"
        }
    }

    /// The cache definition: every field with its heading, the axis fields with their items.
    static func cacheDefinition(_ spec: PivotSpec, _ src: PivotSource, items: [Int: [PivotItem]], relId: String) -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<pivotCacheDefinition xmlns=\"\(main)\" xmlns:r=\"\(rel)\" r:id=\"\(relId)\""
        s += " refreshOnLoad=\"1\" refreshedBy=\"Starling\" refreshedDate=\"\(num(((Date().timeIntervalSince1970 / 86400 + 25569) * 100000).rounded() / 100000))\" createdVersion=\"8\" refreshedVersion=\"8\" minRefreshableVersion=\"3\" recordCount=\"\(src.rows.count)\">"
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
            var group: PivotGroup?
            if items[f] != nil { group = spec.groups[f] }
            var isDate = false
            if case .dates = group, let lo = nums.min(), let hi = nums.max() {
                isDate = true
                a = " containsSemiMixedTypes=\"0\" containsNonDate=\"0\" containsDate=\"1\" containsString=\"0\" minDate=\"\(isoDate(lo))\" maxDate=\"\(isoDate(hi))\""
            }
            s += "<cacheField name=\"\(esc(h))\" numFmtId=\"\(isDate ? 14 : 0)\">"
            if let its = items[f] { s += "<sharedItems\(a) count=\"\(its.count)\">" + its.map { itemXML($0, date: isDate) }.joined() + "</sharedItems>" }
            else { s += "<sharedItems\(a)/>" }
            if let group, let lo = nums.min(), let hi = nums.max() {
                var range = ""
                switch group {
                case .numbers(let start, let end, let by): range = "autoStart=\"0\" autoEnd=\"0\" startNum=\"\(num(start))\" endNum=\"\(num(end))\" groupInterval=\"\(num(by))\""
                case .dates(let unit): range = "groupBy=\"\(unit.rawValue)\" startDate=\"\(isoDate(lo))\" endDate=\"\(isoDate(hi))\""
                }
                let gi = group.items(col)
                s += "<fieldGroup base=\"\(f)\"><rangePr \(range)/><groupItems count=\"\(gi.count)\">" + gi.map { "<s v=\"\(esc($0.shown))\"/>" }.joined() + "</groupItems></fieldGroup>"
            }
            s += "</cacheField>"
        }
        // (Excel's own extension block: the 2009 cache marker.)
        return s + "</cacheFields><extLst><ext uri=\"{725AE2AE-9491-48be-B2B4-4EB974FC3084}\" xmlns:x14=\"http://schemas.microsoft.com/office/spreadsheetml/2009/9/main\"><x14:pivotCacheDefinition/></ext></extLst></pivotCacheDefinition>"
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
        s += " dataCaption=\"Values\" updatedVersion=\"8\" minRefreshableVersion=\"3\" useAutoFormatting=\"1\" itemPrintTitles=\"1\" createdVersion=\"8\" indent=\"0\" outline=\"1\" outlineData=\"1\" multipleFieldFilters=\"0\""
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
        if !spec.cols.isEmpty {
            let several = spec.data.count > 1, v = several ? spec.data.count : 1
            s += "<colFields count=\"\(spec.cols.count + (several ? 1 : 0))\">" + (spec.cols.map { "<field x=\"\($0)\"/>" } + (several ? ["<field x=\"-2\"/>"] : [])).joined() + "</colFields>"
            s += "<colItems count=\"\((lay.colNodes.count + 1) * v)\">"
            for nd in lay.colNodes {
                for k in 0 ..< v {
                    s += "<i" + (nd.subtotal ? " t=\"default\"" : "") + (k > 0 ? " i=\"\(k)\"" : "") + ">" + nd.path.map(x).joined() + (several ? x(k) : "") + "</i>"
                }
            }
            for k in 0 ..< v { s += "<i t=\"grand\"" + (k > 0 ? " i=\"\(k)\"" : "") + ">" + x(several ? k : 0) + "</i>" }
            s += "</colItems>"
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
            // (Built in steps: as one `+` chain the compiler gives up type-checking it, and the iOS build fails.)
            var df = "<dataField name=\"\(esc(lay.dataNames[k]))\" fld=\"\(d.field)\""
            if d.function != .sum { df += " subtotal=\"\(d.function.rawValue)\"" }
            if d.showAs != .normal { df += " showDataAs=\"\(d.showAs.rawValue)\"" }
            if let f = d.cellFormat, let id = Xlsx.builtinFormats.first(where: { $0.value == f })?.key { df += " numFmtId=\"\(id)\"" }
            s += df + " baseField=\"0\" baseItem=\"0\"/>"
        }
        s += "</dataFields>"
        s += "<pivotTableStyleInfo name=\"\(esc(style))\" showRowHeaders=\"1\" showColHeaders=\"1\" showRowStripes=\"0\" showColStripes=\"0\" showLastColumn=\"1\"/>"
        // (Excel's own extension blocks: the 2009 table marker, and the 2016 default layout one.)
        s += "<extLst><ext uri=\"{962EF5D1-5CA2-4c93-8EF4-DBF5C05439D2}\" xmlns:x14=\"http://schemas.microsoft.com/office/spreadsheetml/2009/9/main\"><x14:pivotTableDefinition\(spec.data.count == 1 ? " hideValuesRow=\"1\"" : "") xmlns:xm=\"http://schemas.microsoft.com/office/excel/2006/main\"/></ext>"
        s += "<ext uri=\"{747A6164-185A-40DC-8AA5-F01512510D54}\" xmlns:xpdl=\"http://schemas.microsoft.com/office/spreadsheetml/2016/pivotdefaultlayout\"><xpdl:pivotTableDefinition16/></ext></extLst>"
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
        // (Excel groups in the cache, so a new pivot over a source already grouped has the same groups.)
        for ws in book.sheets { for p in ws.pivots where p.source == canon { if let g = p.made?.groups, !g.isEmpty { spec.groups = g } } }
        if let p = PivotCalc.problem(spec, src) { return p }
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
            if let f = lay.formats[a] { var st = book.style(c.style ?? ws.defaultStyle(at: a)); st.numberFormat = f; c.style = book.styleIndex(st) }
            if lay.buttons.contains(a) { var st = book.style(c.style ?? ws.defaultStyle(at: a)); st.pivotButton = true; c.style = book.styleIndex(st) }
            ws.cells[a] = c
        }
    }

    /// Lay pivot `k` of `ws` out again from `spec` over `src`, where it stands now (rows may have been inserted above it since it was made).
    func _relayPivot(_ ws: Worksheet, _ k: Int, _ made: PivotSpec, _ src: PivotSource) {
        var spec = made
        let pageRows = spec.filters.isEmpty ? 0 : spec.filters.count + 1
        var old = ws.pivots[k].ref
        // (The page filters sit above the table, of the OLD spec's count: take the old origin from the old spec.)
        let oldPage = (ws.pivots[k].made ?? ws.pivots[k].fileSpec).map { $0.filters.isEmpty ? 0 : $0.filters.count + 1 } ?? pageRows
        spec.origin = CellAddress(row: old.top - oldPage, col: old.left)
        if oldPage > 0 { old = CellRange(top: spec.origin.row, left: old.left, bottom: old.bottom, right: max(old.right, old.left + 1)) }
        let lay = PivotCalc.layout(spec, src)
        if ws.pivots[k].made != nil { ws.pivots[k].made = spec } else { ws.pivots[k].refreshedHere = true }
        _writePivot(lay, on: ws, replacing: old)
        ws.pivots[k].ref = lay.location
    }

    /// The pivot made here that the active cell is in (its page filters included).
    func madePivotIndex(on ws: Worksheet, at a: CellAddress) -> Int? {
        ws.pivots.indices.first { k in
            guard let m = ws.pivots[k].made else { return false }
            let r = ws.pivots[k].ref, pr = m.filters.isEmpty ? 0 : m.filters.count + 1
            return a.row >= r.top - pr && a.row <= r.bottom && a.col >= r.left && a.col <= r.right
        }
    }

    /// The PivotTable Fields pane: put the fields where the user dragged them. One undoable step; the problem when the new setup cannot be laid out.
    @discardableResult
    func setPivotFields(sheet ws: Worksheet, pivot k: Int, rows: [Int], cols: [Int], data: [PivotDataField], filters: [PivotFilter]) -> PivotProblem? {
        guard ws.pivots.indices.contains(k), var spec = ws.pivots[k].made, let s = ws.pivots[k].source, let src = PivotSource.read(s, book: book) else { return .noSource }
        spec.rows = rows; spec.cols = cols; spec.data = data; spec.filters = filters
        if let p = PivotCalc.problem(spec, src) { return p }
        // (A page filter added or removed moves the table down or up: the old page rows are cleared by `_relayPivot`, and the table keeps its top.)
        structural { _relayPivot(ws, k, spec, src) }
        return nil
    }

    /// Group field `f` of pivot `k` (or ungroup it with nil). Every pivot made here over the same source gets the same grouping, as
    /// Excel keeps groups in the cache the pivots share. One undoable step.
    @discardableResult
    func setPivotGroup(sheet ws: Worksheet, pivot k: Int, field f: Int, group: PivotGroup?) -> PivotProblem? {
        guard ws.pivots.indices.contains(k), ws.pivots[k].made != nil, let s = ws.pivots[k].source, let src = PivotSource.read(s, book: book), f >= 0, f < src.headers.count else { return .noSource }
        var plans: [(Worksheet, Int, PivotSpec)] = []
        for w in book.sheets {
            for j in w.pivots.indices where w.pivots[j].source == s {
                guard var spec = w.pivots[j].made else { continue }
                spec.groups[f] = group
                if let group, group.items(src.rows.map { $0[f] }).isEmpty { return .cannotGroup }
                for i in spec.filters.indices where spec.filters[i].field == f { spec.filters[i].item = nil }
                if let p = PivotCalc.problem(spec, src) { return p }
                plans.append((w, j, spec))
            }
        }
        structural { for (w, j, spec) in plans { _relayPivot(w, j, spec, src) } }
        return nil
    }

    /// Refresh the pivot tables made here from their sources as they are now; returns how many were refreshed.
    /// (A pivot table from a file is laid out again too when it is a kind made here; its parts stay as the file had them, and its cache is
    /// set to refresh when Excel opens the file. Any other kind is left for Excel.)
    @discardableResult
    func refreshPivots() -> Int {
        var n = 0
        structural {
            for ws in book.sheets {
                for k in ws.pivots.indices {
                    guard let made = ws.pivots[k].made ?? ws.pivots[k].fileSpec, let s = ws.pivots[k].source, let src = PivotSource.read(s, book: book),
                          PivotCalc.problem(made, src) == nil else { continue }
                    _relayPivot(ws, k, made, src)
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
    /// Pivots over the same source range share one cache: the first of them writes it (with the items of every
    /// field any of them puts on an axis or a filter), the others only point at it.
    var ownsCache = true
    var cacheFields: Set<Int> = []
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
        var out: [(String, String)] = []
        if ownsCache {
            var all = spec; all.rows = cacheFields.sorted(); all.cols = []; all.filters = []; all.groups = [:]
            let shared = PivotCalc.items(all, src)
            out += [
                (cache, PivotWriter.cacheDefinition(spec, src, items: shared, relId: "rId1")),
                ("xl/pivotCache/_rels/" + name(cache) + ".rels", rels("pivotCacheRecords", name(records))),
                (records, PivotWriter.cacheRecords(src, items: shared)),
            ]
        }
        out += [
            (table, PivotWriter.table(spec, src, lay, cacheId: cacheId, style: style)),
            ("xl/pivotTables/_rels/" + name(table) + ".rels", rels("pivotCacheDefinition", "../pivotCache/" + name(cache))),
        ]
        return out
    }
}
