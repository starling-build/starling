// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Sheet protection, as Excel enforces it: on a sheet whose kept
// `<sheetProtection sheet="1">` says so, locked cells (every cell, unless
// its format says `<protection locked="0"/>`) refuse edits, and formatting,
// inserting or deleting rows and columns, sorting and filtering are refused
// unless the protection allows them (its formatCells="0", insertRows="0"…).
// The password is Excel's; unprotecting is done in Excel.

import Foundation

extension WorkbookController {
    static let protectedMessage = "The cell or chart you're trying to change is on a protected sheet."

    /// The active (or given) sheet's protection attributes, when it is protected.
    func protection(_ si: Int? = nil) -> [String: String]? {
        let ws = book.sheets[si ?? activeSheet]
        guard let text = ws.keptElements.first(where: { $0.name == "sheetProtection" })?.text,
              let n = XNode.parse(Data(text.utf8)), n["sheet"] == "1" || n["sheet"] == "true" else { return nil }
        return n.attrs
    }

    /// Whether a cell's format locks it (true unless its protection says otherwise).
    func isLocked(_ a: CellAddress, sheet si: Int? = nil) -> Bool {
        let ws = book.sheets[si ?? activeSheet]
        let style = book.style(ws.cells[a]?.style ?? ws.defaultStyle(at: a))
        guard let b = style.baseXf, let src = book.styleSource, b < src.xfs.count,
              let p = src.xfs[b].protection else { return true }
        return !(p.containsSubstring("locked=\"0\"") || p.containsSubstring("locked=\"false\""))
    }

    /// True (and the reason shown) when the sheet's protection forbids
    /// changing `cells`.
    func refusesEdit(_ cells: [CellAddress], sheet si: Int? = nil) -> Bool {
        guard protection(si) != nil, cells.contains(where: { isLocked($0, sheet: si) }) else { return false }
        onCommand?(.status(Self.protectedMessage))
        return true
    }

    /// True (and the reason shown) when the protection forbids `action`
    /// (formatCells, insertRows, deleteColumns, sort, autoFilter…).
    func refuses(_ action: String) -> Bool {
        guard let p = protection() else { return false }
        if p[action] == "0" || p[action] == "false" { return false }
        onCommand?(.status(Self.protectedMessage))
        return true
    }
}

extension CellRange {
    /// Its cells, row by row (a huge range: its corners and edges' first
    /// cells — enough for the protection check, which needs any locked one).
    var cells: [CellAddress] {
        if rows * cols <= 10_000 {
            return (top ... bottom).flatMap { r in (left ... right).map { CellAddress(row: r, col: $0) } }
        }
        return [topLeft, bottomRight, CellAddress(row: top, col: right), CellAddress(row: bottom, col: left)]
    }
}
