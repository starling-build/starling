// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge

/// What a screen reader sees of the Sheets grid: one node for the sheet (its name, the active cell and the
/// selection) and, inside it, a node per cell in view that holds something, in reading order (row by row,
/// left to right), plus the active cell even when it is empty. A cell is named by its address, its value is
/// the text the grid shows, a formula cell carries its formula as the hint, and a tap selects it.
enum SheetsAccessibility {
    /// The most cells published at once, so a full screen of data stays cheap to read.
    static let maxCells = 400

    struct Entry: Equatable {
        var address: CellAddress
        /// The cell's whole range when it is the top-left of a merge (its frame covers all of it).
        var span: CellRange
        var label: String
        var value: String
        var formula: String
        var selected: Bool
    }

    /// How far past the view (rows, columns) around the active cell a screen reader can still move to.
    static let reachRows = 60, reachCols = 26

    private static func shownText(_ a: CellAddress, in c: WorkbookController) -> String {
        guard let cell = c.sheet.cells[a] else { return "" }
        return NumberFormat.display(cell.value, c.style(at: a).numberFormat, width: 255).text
    }

    private static func isText(_ a: CellAddress, in c: WorkbookController) -> Bool {
        if case .text = c.sheet.cells[a]?.value { return true }
        return false
    }

    /// The row that names the columns: the last frozen row, else the first row of the data around the active cell.
    static func headerRow(_ c: WorkbookController) -> Int? {
        if c.sheet.freezeRows > 0 { return c.sheet.freezeRows - 1 }
        let region = c.currentRegion(c.active)
        return region.bottom > region.top ? region.top : nil
    }

    /// The column that names the rows: the last frozen column (a plain table has none).
    static func headerCol(_ c: WorkbookController) -> Int? { c.sheet.freezeCols > 0 ? c.sheet.freezeCols - 1 : nil }

    static func entry(_ a: CellAddress, in c: WorkbookController, headerRow hr: Int? = nil, headerCol hc: Int? = nil) -> Entry {
        let span = c.sheet.merges.first { $0.topLeft == a } ?? CellRange(a)
        var label = a.a1
        // The text of the cell that names this cell's column and row: "B3, Price, Tea".
        if let hr, a.row > hr, isText(CellAddress(row: hr, col: a.col), in: c) {
            label += ", " + shownText(CellAddress(row: hr, col: a.col), in: c)
        }
        if let hc, a.col > hc, isText(CellAddress(row: a.row, col: hc), in: c) {
            label += ", " + shownText(CellAddress(row: a.row, col: hc), in: c)
        }
        let formula = c.sheet.cells[a]?.formula != nil ? c.input(a) : ""
        return Entry(address: a, span: span, label: label, value: shownText(a, in: c), formula: formula,
                     selected: c.selection.contains(a))
    }

    /// What is said when the selection lands on one cell: its address with the headers that name it, its value,
    /// and whether it holds a formula: "B3, Price, 4.50, formula =A1*2"; an empty cell is "B3, blank".
    static func spoken(_ a: CellAddress, in c: WorkbookController) -> String {
        let e = entry(a, in: c, headerRow: headerRow(c), headerCol: headerCol(c))
        var parts = [e.label, e.value.isEmpty ? "blank" : e.value]
        if !e.formula.isEmpty { parts.append("formula " + e.formula) }
        return parts.joined(separator: ", ")
    }

    /// The cells to publish, in reading order: filled cells in view, and the ones within reach of the active cell
    /// (nearest first when there are too many), the active cell always; a merge once, at its top-left.
    static func entries(_ c: WorkbookController, visible: (CellAddress) -> Bool) -> [Entry] {
        let covered = Set(c.sheet.merges.flatMap { m in
            (m.top ... m.bottom).flatMap { r in (m.left ... m.right).map { CellAddress(row: r, col: $0) } }.filter { $0 != m.topLeft }
        })
        let act = c.active
        func near(_ a: CellAddress) -> Bool { abs(a.row - act.row) <= reachRows && abs(a.col - act.col) <= reachCols }
        var picked = c.sheet.cells.filter { !$0.value.value.isEmpty || $0.value.formula != nil }.keys
            .filter { !covered.contains($0) && (visible($0) || near($0)) }
        if !picked.contains(act) { picked.append(act) }
        if picked.count > maxCells {
            func rank(_ a: CellAddress) -> Int { a == act ? -1 : visible(a) ? 0 : abs(a.row - act.row) + abs(a.col - act.col) }
            picked = Array(picked.sorted { rank($0) < rank($1) }.prefix(maxCells))
        }
        picked.sort { ($0.row, $0.col) < ($1.row, $1.col) }
        let hr = headerRow(c), hc = headerCol(c)
        return picked.map { entry($0, in: c, headerRow: hr, headerCol: hc) }
    }

    static func sheetLabel(_ c: WorkbookController) -> String {
        let a = entry(c.active, in: c, headerRow: headerRow(c), headerCol: headerCol(c))
        let what = a.value.isEmpty ? "empty" : a.value
        return "\(c.sheet.name), active cell \(a.label), \(what)"
    }

    static func wrap(_ grid: Widget, controller c: WorkbookController, visible: @escaping (CellAddress) -> Bool,
                     frame: @escaping (CellRange) -> Rect) -> Widget {
        let cells: [Widget] = entries(c, visible: visible).map { e in
            let r = frame(e.span)
            return Positioned(key: ValueKey("cell \(e.address.a1)"), left: r.left, top: r.top, width: max(1, r.width), height: max(1, r.height),
                              child: Semantics(label: e.label, hint: e.formula.isEmpty ? nil : e.formula, value: e.value,
                                               selected: e.selected, onTap: { c.select(e.address) },
                                               child: SizedBox(expand: ())))
        }
        return Semantics(label: sheetLabel(c), child: Stack(children: [grid, IgnorePointer(child: Stack(children: cells))]))
    }
}
