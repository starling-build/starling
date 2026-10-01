// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// AutoFilter: dropdowns on a table's header row that hide the rows whose
// value in a column is not among those ticked. As in Excel, a filter is
// applied when it is set (and when the table is sorted) — editing a cell
// afterwards does not re-hide its row.
//
// Rows a filter hides are their own set, not a height of 0, so turning the
// filter off gives every row back the height it had.

import Foundation

struct AutoFilter: Sendable {
    /// The header row and the data under it.
    var range: CellRange
    /// Column → the shown texts allowed through ("" is blanks). A column
    /// with no entry is not filtered.
    var columns: [Int: Set<String>] = [:]
    /// The element as the file wrote it, written back while nothing about
    /// the filter has changed: it may carry custom, top-10, colour or date
    /// filters and a sort state, none of which are modelled.
    var raw: String? = nil
}

extension WorkbookController {
    /// What a cell shows, as filters compare it.
    func filterText(_ a: CellAddress, in ws: Worksheet? = nil) -> String {
        let ws = ws ?? sheet
        guard let cell = ws.cells[a], !cell.value.isEmpty else { return "" }
        return NumberFormat.display(cell.value, book.style(cell.style).numberFormat, width: 255).text
    }

    /// Data → Filter (⌘⇧L): on for the table around the selection, or off.
    func toggleAutoFilter() {
        if sheet.autoFilter != nil {
            structural {
                sheet.autoFilter = nil
                sheet.filteredRows = []
            }
            return
        }
        var r = selection.isSingle ? currentRegion(active) : selection
        let used = sheet.usedExtent
        r = CellRange(top: r.top, left: r.left, bottom: max(r.top, min(r.bottom, used.row)), right: max(r.left, min(r.right, used.col)))
        structural { sheet.autoFilter = AutoFilter(range: r) }
    }

    /// The distinct texts in a filter column's data, in sort order, blanks
    /// last — what its dropdown lists.
    func filterValues(col: Int) -> [String] {
        guard let af = sheet.autoFilter, af.range.rows > 1 else { return [] }
        var seen = Set<String>()
        var values: [(String, CellValue)] = []
        for row in af.range.top + 1 ... _filterBottom(af) {
            let a = CellAddress(row: row, col: col)
            let t = filterText(a)
            if seen.insert(t).inserted { values.append((t, sheet.value(a))) }
        }
        return values.sorted { a, b in
            if a.0.isEmpty != b.0.isEmpty { return b.0.isEmpty }
            let c = CalcEngine.compare(a.1, b.1)
            return c == 0 ? a.0 < b.0 : c < 0
        }.map(\.0)
    }

    /// Set (or clear, with nil) the texts a column lets through, and hide
    /// what fails any column's test.
    func setFilter(col: Int, allowed: Set<String>?) {
        guard var af = sheet.autoFilter else { return }
        af.columns[col] = allowed
        af.raw = nil
        structural {
            sheet.autoFilter = af
            reapplyFilter()
        }
    }

    func clearFilters() {
        guard var af = sheet.autoFilter, !af.columns.isEmpty else { return }
        af.columns = [:]
        af.raw = nil
        structural {
            sheet.autoFilter = af
            sheet.filteredRows = []
        }
    }

    /// Re-run every column's test over the data, which grows to take in
    /// rows typed directly under it, as Excel's Reapply does.
    func reapplyFilter() {
        guard var af = sheet.autoFilter else { return }
        let bottom = _filterBottom(af)
        if bottom != af.range.bottom {
            af.range = CellRange(top: af.range.top, left: af.range.left, bottom: bottom, right: af.range.right)
            sheet.autoFilter = af
        }
        var hidden = Set<Int>()
        if !af.columns.isEmpty, af.range.rows > 1 {
            for row in af.range.top + 1 ... af.range.bottom {
                for (col, allowed) in af.columns where !allowed.contains(filterText(CellAddress(row: row, col: col))) {
                    hidden.insert(row)
                    break
                }
            }
        }
        sheet.filteredRows = hidden
    }

    /// Sort the filter's data by one column; the filter is then re-run, so
    /// what is hidden still matches what the dropdowns say.
    func sortFilter(col: Int, ascending: Bool) {
        guard let af = sheet.autoFilter, af.range.rows > 2 else { return }
        let data = CellRange(top: af.range.top + 1, left: af.range.left, bottom: _filterBottom(af), right: af.range.right)
        structural {
            sortRows(data, key: col, ascending: ascending)
            reapplyFilter()
        }
    }

    /// "12 of 40 records found" — Excel's status-bar line for a filter.
    var filterSummary: String? {
        guard let af = sheet.autoFilter, !af.columns.isEmpty, af.range.rows > 1 else { return nil }
        let total = af.range.rows - 1
        let shown = total - sheet.filteredRows.filter { $0 > af.range.top && $0 <= af.range.bottom }.count
        return "\(shown) of \(total) records found"
    }

    /// The last row of the filter's data: its range, carried on over rows
    /// filled in directly beneath it.
    func _filterBottom(_ af: AutoFilter) -> Int {
        var bottom = af.range.bottom
        func filled(_ row: Int) -> Bool {
            (af.range.left ... af.range.right).contains { !(sheet.cells[CellAddress(row: row, col: $0)]?.value.isEmpty ?? true) }
        }
        while bottom + 1 < CellAddress.maxRows, filled(bottom + 1) { bottom += 1 }
        return bottom
    }
}
