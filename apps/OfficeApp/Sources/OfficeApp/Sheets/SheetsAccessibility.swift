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
        var label: String
        var value: String
        var formula: String
        var selected: Bool
    }

    static func entry(_ a: CellAddress, in c: WorkbookController) -> Entry {
        var value = "", formula = ""
        if let cell = c.sheet.cells[a] {
            value = NumberFormat.display(cell.value, c.style(at: a).numberFormat, width: 255).text
            if cell.formula != nil { formula = c.input(a) }
        }
        return Entry(address: a, label: a.a1, value: value, formula: formula, selected: c.selection.contains(a))
    }

    /// The cells to publish: those of `visible` that hold a value or a formula, in reading order, and the active cell.
    static func entries(_ c: WorkbookController, visible: (CellAddress) -> Bool) -> [Entry] {
        var addresses = c.sheet.cells.filter { !$0.value.value.isEmpty || $0.value.formula != nil }.keys.filter(visible)
        if !addresses.contains(c.active) { addresses.append(c.active) }
        addresses.sort { ($0.row, $0.col) < ($1.row, $1.col) }
        return addresses.prefix(maxCells).map { entry($0, in: c) }
    }

    static func sheetLabel(_ c: WorkbookController) -> String {
        let a = entry(c.active, in: c)
        let what = a.value.isEmpty ? "empty" : a.value
        return "\(c.sheet.name), active cell \(a.label), \(what)"
    }

    static func wrap(_ grid: Widget, controller c: WorkbookController, visible: @escaping (CellAddress) -> Bool,
                     frame: @escaping (CellAddress) -> Rect) -> Widget {
        let cells: [Widget] = entries(c, visible: visible).map { e in
            let r = frame(e.address)
            return Positioned(key: ValueKey("cell \(e.label)"), left: r.left, top: r.top, width: max(1, r.width), height: max(1, r.height),
                              child: Semantics(label: e.label, hint: e.formula.isEmpty ? nil : e.formula, value: e.value,
                                               selected: e.selected, onTap: { c.select(e.address) },
                                               child: SizedBox(expand: ())))
        }
        return Semantics(label: sheetLabel(c), child: Stack(children: [grid, IgnorePointer(child: Stack(children: cells))]))
    }
}
