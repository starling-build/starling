// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6a: Data → Remove Duplicates. Rows of the range whose chosen columns show the same text as an
// earlier row (case ignored, as Excel does) are removed; the rows below move up inside the range and the
// freed rows at its bottom are cleared. One undo step.

import Foundation

enum DuplicatesProblem: Equatable {
    case nothingToCheck, noColumns, columnOutside, mergedCells
    var message: String {
        switch self {
        case .nothingToCheck: return "Select two or more rows of data to check for duplicates."
        case .noColumns: return "Choose at least one column."
        case .columnOutside: return "A chosen column is outside the selected cells."
        case .mergedCells: return "Removing duplicates needs cells of the same size. Unmerge the merged cells first."
        }
    }
}

/// What a Remove Duplicates run did.
struct DuplicatesResult: Equatable {
    var removed: Int
    var remaining: Int
    var message: String {
        removed == 0 ? "No duplicate values found."
            : "\(removed) duplicate value\(removed == 1 ? "" : "s") found and removed; \(remaining) unique value\(remaining == 1 ? "" : "s") remain."
    }
}

extension WorkbookController {
    /// Remove the later rows of `range` that repeat an earlier row in every one of `columns`.
    /// With `hasHeader` the first row is neither compared nor moved.
    func removeDuplicates(_ range: CellRange, columns: [Int], hasHeader: Bool) -> (result: DuplicatesResult?, problem: DuplicatesProblem?) {
        guard !columns.isEmpty else { return (nil, .noColumns) }
        guard columns.allSatisfy({ $0 >= range.left && $0 <= range.right }) else { return (nil, .columnOutside) }
        let top = hasHeader ? range.top + 1 : range.top
        guard range.bottom > top else { return (nil, .nothingToCheck) }
        let data = CellRange(top: top, left: range.left, bottom: range.bottom, right: range.right)
        if sheet.merges.contains(where: { $0.intersects(data) }) { return (nil, .mergedCells) }
        if protection() != nil {
            let cells = (data.top ... data.bottom).flatMap { r in (data.left ... data.right).map { CellAddress(row: r, col: $0) } }
            if refusesEdit(cells) { return (nil, nil) }
        }
        var seen = Set<String>(), keep: [Int] = []
        for row in data.top ... data.bottom {
            let key = columns.map { col -> String in
                let a = CellAddress(row: row, col: col)
                let code = book.style(sheet.cells[a]?.style ?? sheet.defaultStyle(at: a)).numberFormat
                return NumberFormat.display(sheet.value(a), code, width: 255).text.lowercased()
            }.joined(separator: "\u{1}")
            if seen.insert(key).inserted { keep.append(row) }
        }
        let removed = (data.bottom - data.top + 1) - keep.count
        let result = DuplicatesResult(removed: removed, remaining: keep.count)
        guard removed > 0 else { return (result, nil) }
        structural {
            var moved: [CellAddress: Cell] = [:]
            for (i, old) in keep.enumerated() {
                let new = data.top + i
                for col in data.left ... data.right {
                    guard var cell = sheet.cells[CellAddress(row: old, col: col)] else { continue }
                    if let f = cell.formula, new != old {
                        let g = Formula.shifted(f, rows: new - old, cols: 0)
                        cell.formula = g
                        cell.input = Formula.text(g)
                    }
                    moved[CellAddress(row: new, col: col)] = cell
                }
            }
            for row in data.top ... data.bottom { for col in data.left ... data.right { sheet.cells[CellAddress(row: row, col: col)] = nil } }
            for (a, c) in moved { sheet.cells[a] = c }
            if sheet.autoFilter != nil { reapplyFilter() }
        }
        return (result, nil)
    }
}
