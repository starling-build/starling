// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6c: Data → Subtotal. At each change in one column's value a row "<value> Total" is inserted
// below the group with SUBTOTAL(function, …) over the chosen columns; a "Grand Total" row closes the
// data; the grouped rows get outline level 1 so the +/- gutter collapses them. One undo step.

import Foundation

enum SubtotalFunction: Int, CaseIterable {
    case sum = 9, count = 3, average = 1, max = 4, min = 5, product = 6, countNumbers = 2
    case stdDev = 7, stdDevP = 8, variance = 10, varianceP = 11
    var label: String {
        switch self {
        case .sum: return "Sum"
        case .count: return "Count"
        case .average: return "Average"
        case .max: return "Max"
        case .min: return "Min"
        case .product: return "Product"
        case .countNumbers: return "Count Numbers"
        case .stdDev: return "StdDev"
        case .stdDevP: return "StdDevp"
        case .variance: return "Var"
        case .varianceP: return "Varp"
        }
    }
}

enum SubtotalProblem: Equatable {
    case nothingToTotal, noColumns, columnOutside, mergedCells, inTable
    var message: String {
        switch self {
        case .nothingToTotal: return "Select a header row and at least one row of data below it."
        case .noColumns: return "Choose at least one column to add subtotals to."
        case .columnOutside: return "A chosen column is outside the selected cells."
        case .mergedCells: return "Subtotals need cells of the same size. Unmerge the merged cells first."
        case .inTable: return "Subtotals can't be added inside a table. Convert the table to a range first."
        }
    }
}

extension WorkbookController {
    /// True when row `r` of `range` looks like one this feature wrote: its group column ends in
    /// " Total" (or is "Grand Total") and some other cell holds a SUBTOTAL formula.
    private func _isSubtotalRow(_ r: Int, _ range: CellRange, groupCol: Int) -> Bool {
        let label = sheet.cells[CellAddress(row: r, col: groupCol)].map { $0.input } ?? ""
        guard label.hasSuffix(" Total") || label == "Grand Total" else { return false }
        for c in range.left ... range.right where c != groupCol {
            if let f = sheet.cells[CellAddress(row: r, col: c)]?.input, f.uppercased().hasPrefix("=SUBTOTAL(") { return true }
        }
        return false
    }

    /// Add subtotals to `range` (first row is the header). With `replace`, subtotal rows already there
    /// are removed first. Returns the number of groups, or the problem.
    func addSubtotals(_ range: CellRange, groupBy: Int, function: SubtotalFunction, columns: [Int],
                      replace: Bool = true) -> (groups: Int?, problem: SubtotalProblem?) {
        guard range.bottom > range.top else { return (nil, .nothingToTotal) }
        guard !columns.isEmpty else { return (nil, .noColumns) }
        guard ([groupBy] + columns).allSatisfy({ $0 >= range.left && $0 <= range.right }) else { return (nil, .columnOutside) }
        if sheet.merges.contains(where: { $0.intersects(range) }) { return (nil, .mergedCells) }
        if sheet.tables.contains(where: { $0.ref.intersects(range) }) { return (nil, .inTable) }
        if refuses("insertRows") { return (nil, nil) }
        var groupCount = 0
        structural {
            var bottom = range.bottom
            if replace {
                for r in stride(from: bottom, to: range.top, by: -1) where _isSubtotalRow(r, range, groupCol: groupBy) {
                    _shift(.rows, at: r, by: -1); bottom -= 1
                }
            }
            let top = range.top + 1
            guard bottom >= top else { return }
            func key(_ r: Int) -> String {
                let a = CellAddress(row: r, col: groupBy)
                let code = book.style(sheet.cells[a]?.style ?? sheet.defaultStyle(at: a)).numberFormat
                return NumberFormat.display(sheet.value(a), code, width: 255).text
            }
            var groups: [(first: Int, last: Int, label: String)] = []
            for r in top ... bottom {
                let k = key(r)
                if let g = groups.last, key(g.last) == k { groups[groups.count - 1].last = r } else { groups.append((r, r, k)) }
            }
            groupCount = groups.count
            // Insert bottom-up so every position above is still where it was read.
            _shift(.rows, at: bottom + 1, by: 1)
            for g in groups.reversed() { _shift(.rows, at: g.last + 1, by: 1) }
            let n = groups.count
            func write(_ row: Int, label: String, first: Int, last: Int) {
                let la = CellAddress(row: row, col: groupBy)
                var lc = Cell(input: label); lc.value = .text(label)
                var ls = book.style(sheet.cells[CellAddress(row: top + 0, col: groupBy)]?.style ?? 0); ls.bold = true
                lc.style = book.styleIndex(ls)
                sheet.cells[la] = lc
                for c in columns {
                    let src = CellAddress(row: first, col: c)
                    var st = book.style(sheet.cells[src]?.style ?? sheet.defaultStyle(at: src)); st.bold = true
                    let col = CellAddress.columnName(c)
                    let text = "=SUBTOTAL(\(function.rawValue),\(col)\(first + 1):\(col)\(last + 1))"
                    var cell = Cell(input: text)
                    if let f = try? Formula.parse(text) { cell.formula = f; cell.value = .empty }
                    cell.style = book.styleIndex(st)
                    sheet.cells[CellAddress(row: row, col: c)] = cell
                }
            }
            for (k, g) in groups.enumerated() {
                let first = g.first + k, last = g.last + k
                write(last + 1, label: g.label + " Total", first: first, last: last)
                for r in first ... last { sheet.setOutlineAttr(.rows, r, "outlineLevel", "1") }
            }
            write(bottom + n + 1, label: "Grand Total", first: top, last: bottom + n)
            _syncOutlineLevel(sheet, .rows)
        }
        return (groupCount, nil)
    }

    /// Data → Subtotal → Remove All: the subtotal rows go and the grouping they made is undone.
    func removeSubtotals(_ range: CellRange, groupBy: Int) -> Int {
        guard range.bottom > range.top, refuses("deleteRows") == false else { return 0 }
        let rows = (range.top + 1 ... range.bottom).filter { _isSubtotalRow($0, range, groupCol: groupBy) }
        guard !rows.isEmpty else { return 0 }
        structural {
            for r in rows.reversed() { _shift(.rows, at: r, by: -1) }
            let end = range.bottom - rows.count
            if end > range.top {
                for r in range.top + 1 ... end where sheet.outlineLevel(.rows, r) > 0 { sheet.setOutlineAttr(.rows, r, "outlineLevel", nil) }
            }
            _syncOutlineLevel(sheet, .rows)
        }
        return rows.count
    }
}
