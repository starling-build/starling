// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-RC-1: insert or delete cells (not whole rows or columns), shifting the
// cells beside them. Insert: existing cells move right or down; delete: the
// cells after the removed block close up, left or up. Formulas that point at
// the moved cells follow them (on every sheet). One undo step.

import Foundation

enum CellShift: String, CaseIterable { case right, down, left, up }

extension WorkbookController {
    /// Insert blank cells over `range`, pushing the cells there right or down.
    /// False when it cannot be done (protected sheet, or a merged cell or table would be cut).
    @discardableResult
    func insertCells(_ range: CellRange, shift: CellShift) -> Bool {
        guard shift == .right || shift == .down else { return false }
        if refuses(shift == .down ? "insertRows" : "insertColumns") { return false }
        return _shiftCells(range, axis: shift == .down ? .rows : .cols, delta: shift == .down ? range.rows : range.cols)
    }

    /// Delete the cells in `range`, closing the gap by moving the cells after it left or up.
    @discardableResult
    func deleteCells(_ range: CellRange, shift: CellShift) -> Bool {
        guard shift == .left || shift == .up else { return false }
        if refuses(shift == .up ? "deleteRows" : "deleteColumns") { return false }
        return _shiftCells(range, axis: shift == .up ? .rows : .cols, delta: -(shift == .up ? range.rows : range.cols))
    }

    private func _shiftCells(_ r: CellRange, axis: Axis, delta: Int) -> Bool {
        let ws = sheet, si = activeSheet
        let index = axis == .rows ? r.top : r.left
        let (bandLo, bandHi) = axis == .rows ? (r.left, r.right) : (r.top, r.bottom)
        let limit = axis == .rows ? CellAddress.maxRows : CellAddress.maxCols
        let deleteEnd = delta < 0 ? index - delta : index
        func along(_ a: CellAddress) -> Int { axis == .rows ? a.row : a.col }
        func across(_ a: CellAddress) -> Int { axis == .rows ? a.col : a.row }
        func at(_ i: Int, _ o: Int) -> CellAddress { axis == .rows ? CellAddress(row: i, col: o) : CellAddress(row: o, col: i) }
        func moved(_ i: Int) -> Int? {
            if delta > 0 { return i >= index ? (i + delta < limit ? i + delta : nil) : i }
            if i < index { return i }
            if i < deleteEnd { return nil }
            return i + delta
        }
        func spans(_ x: CellRange) -> (lo: Int, hi: Int, oLo: Int, oHi: Int) {
            axis == .rows ? (x.top, x.bottom, x.left, x.right) : (x.left, x.right, x.top, x.bottom)
        }
        // A merged cell or table that the shift would cut in two stops it.
        for m in ws.merges {
            let s = spans(m)
            if s.hi < index || s.oHi < bandLo || s.oLo > bandHi { continue }
            if !(s.oLo >= bandLo && s.oHi <= bandHi) || (s.lo < index && s.hi >= index) { return false }
        }
        for t in ws.tables {
            let s = spans(t.ref)
            if s.hi >= index && s.oHi >= bandLo && s.oLo <= bandHi { return false }
        }
        structural {
            var cells: [CellAddress: Cell] = [:]
            for (a, c) in ws.cells {
                if across(a) < bandLo || across(a) > bandHi { cells[a] = c; continue }
                if let j = moved(along(a)) { cells[at(j, across(a))] = c }
            }
            ws.cells = cells
            ws.merges = ws.merges.compactMap { m in
                let s = spans(m)
                if s.oLo < bandLo || s.oHi > bandHi || s.hi < index { return m }
                guard let a = moved(s.lo), let b = moved(s.hi) else { return nil }
                return axis == .rows ? CellRange(top: a, left: m.left, bottom: b, right: m.right)
                                     : CellRange(top: m.top, left: a, bottom: m.bottom, right: b)
            }
            for n in ws.notes.indices {
                guard let a = ws.notes[n].at, across(a) >= bandLo, across(a) <= bandHi else { continue }
                ws.notes[n].at = moved(along(a)).map { at($0, across(a)) }
            }
            let name = ws.name.lowercased()
            _rewriteFormulas { ref, home in
                guard ref.sheet.map({ $0.lowercased() == name }) ?? (home == si) else { return ref }
                let q = ref.range
                let s = spans(q)
                // Only references lying wholly inside the shifted band follow the move.
                guard ref.start.row != nil, ref.start.col != nil, s.oLo >= bandLo, s.oHi <= bandHi else { return ref }
                return Self._adjust(ref, axis, index: index, delta: delta)
            }
        }
        return true
    }

    /// Ctrl++ / Ctrl+-: whole rows or columns when the selection is whole ones; else the dialog's choice.
    func insertCellsAtSelection(_ shift: CellShift) { insertCells(selection, shift: shift) }
    func deleteCellsAtSelection(_ shift: CellShift) { deleteCells(selection, shift: shift) }
}
