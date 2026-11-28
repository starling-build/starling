// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The shared Find and Replace dialog's side in Sheets: a pattern (plain, wildcards,
// regex; match case; whole cell), a scope (this sheet or the whole workbook), Excel's
// Look in (formulas, values, notes) and search order (rows, columns), Find All,
// replace all as one undo step, and Go To a cell.

import Foundation
import OfficeText

/// Excel's "Look in": the formula bar's text, the shown value, or the cell's note.
enum FindLookIn: Int, Sendable { case formulas = 0, values, notes }

/// One cell Find All listed.
struct SheetFindHit: Equatable, Sendable {
    var sheet: Int
    var at: CellAddress
}

extension WorkbookController {
    /// Where to look: 0 = the active sheet, 1 = the workbook.
    private func _scopeSheets(_ scope: Int) -> [Int] {
        scope == 1 ? Array(book.sheets.indices) : [activeSheet]
    }

    /// The text Find tests in cell `a` for `lookIn`: nil when there is nothing to look at.
    func findText(_ a: CellAddress, sheet ws: Worksheet, lookIn: FindLookIn) -> String? {
        switch lookIn {
        case .formulas:
            return ws.cells[a].map { _searchText($0, a, sheet: ws) }
        case .values:
            guard let c = ws.cells[a] else { return nil }
            return NumberFormat.display(c.value, book.style(c.style).numberFormat, width: 255).text
        case .notes:
            return ws.notes.first { $0.at == a }?.text
        }
    }

    /// The matching cells of one sheet, in search order: row by row, or column by column.
    func findHits(_ p: TextPattern, sheet si: Int, lookIn: FindLookIn = .formulas, byColumns: Bool = false) -> [CellAddress] {
        let ws = book.sheets[si]
        let candidates = lookIn == .notes ? ws.notes.compactMap(\.at) : Array(ws.cells.keys)
        let hits = candidates.filter { a in findText(a, sheet: ws, lookIn: lookIn).map { !p.matches(in: $0).isEmpty } ?? false }
        return byColumns ? hits.sorted { ($0.col, $0.row) < ($1.col, $1.row) } : hits.sorted()
    }

    /// Find All: every matching cell in the scope, sheet by sheet, in search order.
    func findAll(_ p: TextPattern, scope: Int, lookIn: FindLookIn = .formulas, byColumns: Bool = false) -> [SheetFindHit] {
        _scopeSheets(scope).flatMap { si in findHits(p, sheet: si, lookIn: lookIn, byColumns: byColumns).map { SheetFindHit(sheet: si, at: $0) } }
    }

    /// The next cell after the active one (in search order, then the following sheets in the workbook scope) that matches; selects it.
    @discardableResult
    func findNext(_ p: TextPattern, scope: Int, lookIn: FindLookIn = .formulas, byColumns: Bool = false, backwards: Bool = false) -> Bool {
        let sheets = _scopeSheets(scope)
        let n = sheets.count
        let start = sheets.firstIndex(of: activeSheet) ?? 0
        let before: (CellAddress, CellAddress) -> Bool = byColumns ? { ($0.col, $0.row) < ($1.col, $1.row) } : { $0 < $1 }
        for step in 0 ... n {
            let si = sheets[((start + (backwards ? -step : step)) % n + n) % n]
            var hits = findHits(p, sheet: si, lookIn: lookIn, byColumns: byColumns)
            if backwards { hits.reverse() }
            let here = active
            let next: CellAddress? = step == 0 ? hits.first { backwards ? before($0, here) : before(here, $0) } : hits.first
            if let a = next {
                if si != activeSheet { activeSheet = si }
                select(a)
                return true
            }
        }
        return false
    }

    /// Which match the active cell is among the cells that match, and how many there are ("3 of 12").
    func findPosition(_ p: TextPattern, scope: Int, lookIn: FindLookIn = .formulas, byColumns: Bool = false) -> (index: Int, total: Int)? {
        let all = findAll(p, scope: scope, lookIn: lookIn, byColumns: byColumns)
        return all.firstIndex(of: SheetFindHit(sheet: activeSheet, at: active)).map { ($0 + 1, all.count) }
    }

    /// Go to one Find All hit.
    func goToHit(_ h: SheetFindHit) {
        guard book.sheets.indices.contains(h.sheet) else { return }
        if h.sheet != activeSheet { activeSheet = h.sheet }
        select(h.at)
    }

    /// The cell's text with every match replaced; nil when nothing matched.
    private func _replaced(_ text: String, _ p: TextPattern, _ template: String) -> String? {
        let ms = p.matches(in: text)
        if ms.isEmpty { return nil }
        var out = "", from = text.startIndex
        for m in ms {
            out += text[from ..< m.range.lowerBound]
            out += p.replacement(template, for: m, in: text)
            from = m.range.upperBound
        }
        return out + text[from...]
    }

    /// Replace in the active cell if it matches, then move to the next match.
    @discardableResult
    func replaceCurrent(_ p: TextPattern, with template: String, scope: Int, byColumns: Bool = false) -> Bool {
        if let c = sheet.cells[active], let new = _replaced(c.formula.map(Formula.text) ?? c.input, p, template) {
            setInput(new, at: active)
        }
        return findNext(p, scope: scope, byColumns: byColumns)
    }

    /// Every match in the scope, as one undo step. Returns the count of cells changed.
    @discardableResult
    func replaceAll(_ p: TextPattern, with template: String, scope: Int) -> Int {
        var count = 0
        structural {
            for si in _scopeSheets(scope) {
                let ws = book.sheets[si]
                for (a, c) in ws.cells {
                    let text = c.formula.map(Formula.text) ?? c.input
                    guard !p.matches(in: _searchText(c, a, sheet: ws)).isEmpty,
                          let new = _replaced(text, p, template), new != text else { continue }
                    count += 1
                    var cell = c
                    cell.input = new
                    cell.rawFormula = nil
                    if new.hasPrefix("="), let f = try? Formula.parse(new) {
                        cell.formula = f; cell.value = .empty
                    } else if let parsed = InputParser.parse(new) {
                        cell.formula = nil; cell.value = parsed.value
                    } else {
                        cell.formula = nil; cell.value = .text(new)
                    }
                    ws.cells[a] = cell
                }
            }
        }
        return count
    }

    /// Go To: a cell or a range ("B7", "A1:C3", "$D$4"), also on another sheet ("Sheet2!B7"). Nil when it worked, else the problem.
    func goTo(_ text: String) -> String? {
        var t = text
        while t.hasPrefix(" ") { t.removeFirst() }
        while t.hasSuffix(" ") { t.removeLast() }
        if t.isEmpty { return "Type a cell, like B7" }
        if let bang = t.lastIndex(of: "!") {
            var name = String(t[t.startIndex ..< bang])
            if name.hasPrefix("'"), name.hasSuffix("'"), name.count >= 2 { name = String(name.dropFirst().dropLast()) }
            guard let si = book.sheets.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) else { return "There is no sheet “\(name)”" }
            t = String(t[t.index(after: bang)...])
            if si != activeSheet { activeSheet = si }
        }
        let clean = String(t.filter { $0 != "$" }).uppercased()
        if let a = CellAddress(clean) { select(a); return nil }
        if let r = CellRange(clean) { select(range: r, active: CellAddress(row: r.top, col: r.left)); return nil }
        return "“\(text)” is not a cell. Try B7 or A1:C3"
    }
}
