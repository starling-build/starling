// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The shared Find and Replace dialog's side in Sheets: a pattern (plain, wildcards,
// regex; match case; whole cell), a scope (this sheet or the whole workbook),
// replace all as one undo step, and Go To a cell.

import Foundation
import OfficeText

extension WorkbookController {
    /// Where to look: 0 = the active sheet, 1 = the workbook.
    private func _scopeSheets(_ scope: Int) -> [Int] {
        scope == 1 ? Array(book.sheets.indices) : [activeSheet]
    }

    /// The next cell after the active one (row by row, then the following sheets in the workbook scope) that matches; selects it.
    @discardableResult
    func findNext(_ p: TextPattern, scope: Int, backwards: Bool = false) -> Bool {
        let sheets = _scopeSheets(scope)
        let n = sheets.count
        let start = sheets.firstIndex(of: activeSheet) ?? 0
        for step in 0 ... n {
            let si = sheets[((start + (backwards ? -step : step)) % n + n) % n]
            let ws = book.sheets[si]
            var hits = ws.cells.filter { !p.matches(in: _searchText($0.value, $0.key, sheet: ws)).isEmpty }.map(\.key).sorted()
            if backwards { hits.reverse() }
            let here = active
            let next: CellAddress? = step == 0 ? hits.first { backwards ? $0 < here : $0 > here } : hits.first
            if let a = next {
                if si != activeSheet { activeSheet = si }
                select(a)
                return true
            }
        }
        return false
    }

    /// Which match the active cell is among the cells that match, and how many there are ("3 of 12").
    func findPosition(_ p: TextPattern, scope: Int) -> (index: Int, total: Int)? {
        var total = 0, index: Int?
        for si in _scopeSheets(scope) {
            let ws = book.sheets[si]
            for a in ws.cells.filter({ !p.matches(in: _searchText($0.value, $0.key, sheet: ws)).isEmpty }).map(\.key).sorted() {
                total += 1
                if index == nil, si == activeSheet, a == active { index = total }
            }
        }
        return index.map { ($0, total) }
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
    func replaceCurrent(_ p: TextPattern, with template: String, scope: Int) -> Bool {
        if let c = sheet.cells[active], let new = _replaced(c.formula.map(Formula.text) ?? c.input, p, template) {
            setInput(new, at: active)
        }
        return findNext(p, scope: scope)
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
