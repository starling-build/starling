// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Making and changing Excel tables: create one over a range, give it a
// style, banding and a totals row, resize it, or turn it back into a plain
// range. Each is one undo step. The file side (the table part, its
// relationship and content type) is written by `Xlsx` and `TablesXML`.

import Foundation

enum TableProblem: Equatable {
    case noRange, overlap, merged, notATable, tooSmall, headerMoved, noRoom

    var message: String {
        switch self {
        case .noRange: return "Pick the cells the table covers."
        case .overlap: return "A table cannot overlap another table."
        case .merged: return "A table cannot contain merged cells."
        case .notATable: return "There is no table here."
        case .tooSmall: return "A table needs at least a header row and one row of data."
        case .headerMoved: return "A table's header row must stay where it is."
        case .noRoom: return "There is no room for a totals row: the cells below the table are not empty."
        }
    }
}

extension WorkbookController {
    /// The table the cell is in, as an index into the sheet's tables.
    func tableIndex(at a: CellAddress) -> Int? { sheet.tables.firstIndex { $0.ref.contains(a) } }

    /// The built-in styles offered, light to dark.
    static let tableStyleNames: [String] =
        (1 ... 21).map { "TableStyleLight\($0)" } + (1 ... 28).map { "TableStyleMedium\($0)" } + (1 ... 11).map { "TableStyleDark\($0)" }

    /// A name for a header cell: its text, "Column<n>" when empty, and unique
    /// (ignoring case) among the names already taken.
    private func _headerName(_ v: CellValue, at i: Int, used: inout Set<String>) -> String {
        var name = NumberFormat.display(v, "General", width: 255).text
        if name.isEmpty { name = "Column\(i + 1)" }
        var unique = name, n = 2
        while used.contains(unique.lowercased()) { unique = name + "\(n)"; n += 1 }
        used.insert(unique.lowercased())
        return unique
    }

    private func _setText(_ ws: Worksheet, _ a: CellAddress, _ text: String) {
        var c = ws.cells[a] ?? Cell(input: "")
        if ws.cells[a] == nil { c.style = ws.defaultStyle(at: a) }
        c.formula = nil
        c.input = text
        c.value = .text(text)
        ws.cells[a] = c
    }

    private func _freeName() -> String {
        let taken = Set(book.sheets.flatMap { $0.tables + $0.removedTables }.map { $0.name.lowercased() })
        var n = 1
        while taken.contains("table\(n)") || book.names.keys.contains(where: { $0.lowercased() == "table\(n)" }) { n += 1 }
        return "Table\(n)"
    }

    /// Make a table of `range`. With `hasHeaders` the first row names the
    /// columns (a number there becomes text, an empty or repeated name gets
    /// a fresh one); without, a header row of Column1, Column2… is inserted
    /// above, as Excel does.
    @discardableResult
    func createTable(_ range: CellRange, hasHeaders: Bool, style: String = "TableStyleMedium2") -> TableProblem? {
        if refuses("formatCells") { return nil }
        let ws = sheet
        var r = range
        guard !ws.tables.contains(where: { $0.ref.intersects(r) }) else { return .overlap }
        guard !ws.merges.contains(where: { $0.intersects(r) }) else { return .merged }
        guard !(hasHeaders && r.rows < 2) else { return .tooSmall }
        if refusesEdit(r.cells) { return nil }
        structural {
            if !hasHeaders {
                // The rows move down to make room; the range then starts one
                // row lower and the new row above it is the header.
                _shift(.rows, at: r.top, by: 1)
                r = CellRange(top: r.top, left: r.left, bottom: r.bottom + 1, right: r.right)
            }
            var used = Set<String>()
            var ids: [Int?] = []
            var names: [String] = []
            for i in 0 ..< r.cols {
                let a = CellAddress(row: r.top, col: r.left + i)
                let name = hasHeaders ? _headerName(ws.value(a), at: i, used: &used) : _headerName(.empty, at: i, used: &used)
                if hasHeaders, case .text(let s) = ws.value(a), s == name {} else { _setText(ws, a, name) }
                ids.append(nil)
                names.append(name)
            }
            var t = SheetTable(path: "", ref: r, columnIds: ids, headerRow: true)
            t.edited = true
            t.style = style
            t.name = _freeName()
            t.columnNames = names
            ws.tables.append(t)
        }
        return nil
    }

    /// Turn a table back into a plain range. Its style's fills, bold and
    /// text colours stay on the cells as formatting (its lines do not).
    func convertTableToRange(at index: Int) {
        let ws = sheet
        guard ws.tables.indices.contains(index) else { return }
        structural {
            let t = ws.tables[index]
            for row in t.ref.top ... t.ref.bottom {
                for col in t.ref.left ... t.ref.right {
                    let a = CellAddress(row: row, col: col)
                    guard let look = TableStyles.look(t, a, theme: book.themeColors, book: book),
                          look.fill != nil || look.bold || look.color != nil else { continue }
                    var c = ws.cells[a] ?? Cell(input: "")
                    if ws.cells[a] == nil { c.style = ws.defaultStyle(at: a) }
                    var st = book.style(c.style)
                    if st.fill == nil, let f = look.fill { st.fill = f }
                    if look.bold { st.bold = true }
                    if st.color == nil, let k = look.color { st.color = k }
                    c.style = book.styleIndex(st)
                    ws.cells[a] = c
                }
            }
            ws.removedTables.append(ws.tables.remove(at: index))
        }
    }

    /// The table's style (nil: none) and which of its parts show.
    func setTableLook(at index: Int, style: String?? = nil, rowStripes: Bool? = nil, columnStripes: Bool? = nil,
                      firstColumn: Bool? = nil, lastColumn: Bool? = nil) {
        let ws = sheet
        guard ws.tables.indices.contains(index) else { return }
        structural {
            var t = ws.tables[index]
            if let s = style { t.style = s }
            if let v = rowStripes { t.rowStripes = v }
            if let v = columnStripes { t.columnStripes = v }
            if let v = firstColumn { t.firstColumn = v }
            if let v = lastColumn { t.lastColumn = v }
            t.edited = true
            ws.tables[index] = t
        }
    }

    /// Show or hide the totals row: one row under the table, "Total" in its
    /// first column and a sum (a count for text) under the last.
    @discardableResult
    func setTableTotals(at index: Int, on: Bool) -> TableProblem? {
        let ws = sheet
        guard ws.tables.indices.contains(index) else { return .notATable }
        var t = ws.tables[index]
        guard t.totalsRow != on else { return nil }
        if refuses("formatCells") { return nil }
        if on {
            let row = t.ref.bottom + 1
            let free = (t.ref.left ... t.ref.right).allSatisfy { ws.value(CellAddress(row: row, col: $0)).isEmpty }
            guard free, !ws.tables.contains(where: { $0.ref.intersects(CellRange(top: row, left: t.ref.left, bottom: row, right: t.ref.right)) }) else { return .noRoom }
        }
        structural {
            t = ws.tables[index]
            let w = t.ref.cols
            if on {
                let row = t.ref.bottom + 1
                t.ref = CellRange(top: t.ref.top, left: t.ref.left, bottom: row, right: t.ref.right)
                t.totalsRow = true
                t.totalsLabels = [:]
                t.totalsFunctions = [:]
                if w > 1 { t.totalsLabels[0] = "Total"; _setText(ws, CellAddress(row: row, col: t.ref.left), "Total") }
                let lastCol = t.ref.right
                let dataTop = t.ref.top + (t.headerRow ? 1 : 0)
                let numeric = (dataTop ..< row).contains { if case .number = ws.value(CellAddress(row: $0, col: lastCol)) { return true }; return false }
                let colName = t.headerRow ? NumberFormat.display(ws.value(CellAddress(row: t.ref.top, col: lastCol)), "General", width: 255).text : ""
                let special = colName.isEmpty || colName.contains { "[]#'@".contains($0) }
                let arg = special ? CellRange(top: dataTop, left: lastCol, bottom: row - 1, right: lastCol).a1 : "\(t.name)[\(colName)]"
                let fn = numeric ? "109" : "103"
                t.totalsFunctions[w - 1] = numeric ? "sum" : "count"
                if let f = try? Formula.parse("SUBTOTAL(\(fn),\(arg))") {
                    let a = CellAddress(row: row, col: lastCol)
                    var c = ws.cells[a] ?? Cell(input: "")
                    if ws.cells[a] == nil { c.style = ws.defaultStyle(at: a) }
                    c.formula = f
                    c.value = .empty
                    ws.cells[a] = c
                }
            } else {
                let row = t.ref.bottom
                for col in t.ref.left ... t.ref.right {
                    let a = CellAddress(row: row, col: col)
                    guard var c = ws.cells[a] else { continue }
                    c.formula = nil; c.input = ""; c.value = .empty
                    ws.cells[a] = c.style == 0 ? nil : c
                }
                t.ref = CellRange(top: t.ref.top, left: t.ref.left, bottom: row - 1, right: t.ref.right)
                t.totalsRow = false
                t.totalsLabels = [:]
                t.totalsFunctions = [:]
            }
            t.edited = true
            ws.tables[index] = t
        }
        return nil
    }

    /// Change the cells the table covers. The header row stays where it is;
    /// columns added on the right are named Column<n> in the header cell,
    /// and ones taken off lose their entry.
    @discardableResult
    func resizeTable(at index: Int, to range: CellRange) -> TableProblem? {
        let ws = sheet
        guard ws.tables.indices.contains(index) else { return .notATable }
        let old = ws.tables[index]
        guard range.top == old.ref.top, range.left == old.ref.left else { return .headerMoved }
        guard range.rows >= (old.headerRow ? 2 : 1) + (old.totalsRow ? 1 : 0) else { return .tooSmall }
        guard !ws.tables.enumerated().contains(where: { $0.offset != index && $0.element.ref.intersects(range) }) else { return .overlap }
        guard !ws.merges.contains(where: { $0.intersects(range) }) else { return .merged }
        if range == old.ref { return nil }
        if refuses("formatCells") { return nil }
        structural {
            var t = ws.tables[index]
            // The totals row, if any, stays the last row.
            if t.totalsRow, range.bottom != t.ref.bottom {
                for col in t.ref.left ... t.ref.right {
                    let from = CellAddress(row: t.ref.bottom, col: col)
                    let to = CellAddress(row: range.bottom, col: col)
                    if from != to, let c = ws.cells[from], ws.cells[to] == nil || ws.value(to).isEmpty {
                        ws.cells[to] = c
                        ws.cells[from] = nil
                    }
                }
            }
            let oldW = t.ref.cols, newW = range.cols
            if newW > oldW {
                var used = Set((0 ..< oldW).map { NumberFormat.display(ws.value(CellAddress(row: t.ref.top, col: t.ref.left + $0)), "General", width: 255).text.lowercased() })
                for i in oldW ..< newW {
                    let a = CellAddress(row: t.ref.top, col: t.ref.left + i)
                    let name = _headerName(ws.value(a), at: i, used: &used)
                    if case .text(let s) = ws.value(a), s == name {} else { _setText(ws, a, name) }
                    t.columnIds.append(nil)
                }
            } else if newW < oldW {
                t.columnIds.removeLast(oldW - newW)
                t.totalsLabels = t.totalsLabels.filter { $0.key < newW }
                t.totalsFunctions = t.totalsFunctions.filter { $0.key < newW }
            }
            t.ref = range
            t.edited = true
            ws.tables[index] = t
        }
        return nil
    }
}
