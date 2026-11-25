// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-2: the column filters beside a ticked value list. A column carries ONE filter: a
// ticked list (AutoFilter.columns) or one of these rules (AutoFilter.rules): a comparison
// (one or two conditions joined by And or Or, which is how number, text and "between"
// filters are all written), the top or bottom N (items or percent), above or below
// average, a date period, or a cell or font colour. They read and write as the file's
// own customFilters, top10, dynamicFilter and colorFilter.

import Foundation

struct FilterCondition: Equatable, Sendable {
    /// equal, notEqual, greaterThan, greaterThanOrEqual, lessThan, lessThanOrEqual. Text
    /// searches are an equal or notEqual with `*` and `?`, as the file writes them.
    var op: String
    var value: String
}

enum FilterRule: Equatable, Sendable {
    case compare(FilterCondition, and: Bool, FilterCondition?)
    case top(top: Bool, percent: Bool, count: Int)
    case average(above: Bool)
    /// today, yesterday, tomorrow, thisWeek … nextYear, yearToDate.
    case period(String)
    /// The cell fill (`fill`) or font colour (not `fill`), 0xRRGGBB.
    case color(fill: Bool, UInt32)

    static let periods = ["today", "yesterday", "tomorrow", "thisWeek", "lastWeek", "nextWeek", "thisMonth", "lastMonth",
                          "nextMonth", "thisQuarter", "lastQuarter", "nextQuarter", "thisYear", "lastYear", "nextYear", "yearToDate"]
}

enum FilterProblem: Equatable {
    case needsValue, badCount, noColor, noFilter
    var message: String {
        switch self {
        case .needsValue: return "Enter a value to compare with."
        case .badCount: return "Enter a whole number above zero."
        case .noColor: return "Choose a colour."
        case .noFilter: return "Turn the filter on first."
        }
    }
}

extension FilterRule {
    /// Whether date serial `d` is in `period` of `today`.
    static func inPeriod(_ d: Double, _ period: String, today: Double) -> Bool {
        let (y, m, _) = ExcelDate.ymd(d), (ty, tm, _) = ExcelDate.ymd(today)
        let q = (m - 1) / 3 + y * 4, tq = (tm - 1) / 3 + ty * 4
        switch period {
        case "thisQuarter": return q == tq
        case "lastQuarter": return q == tq - 1
        case "nextQuarter": return q == tq + 1
        case "thisYear": return y == ty
        case "lastYear": return y == ty - 1
        case "nextYear": return y == ty + 1
        case "yearToDate": return y == ty && floor(d) <= today
        default: return CFEvaluator.inPeriod(floor(d), period, today: today)
        }
    }

    /// `*` any run, `?` any one character; case does not matter.
    static func wildcard(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern.lowercased()), t = Array(text.lowercased())
        func go(_ i: Int, _ j: Int) -> Bool {
            if i == p.count { return j == t.count }
            if p[i] == "*" { return (j ... t.count).contains { go(i + 1, $0) } }
            guard j < t.count, p[i] == "?" || p[i] == t[j] else { return false }
            return go(i + 1, j + 1)
        }
        return go(0, 0)
    }

    static func holds(_ c: FilterCondition, _ v: CellValue, shown: String) -> Bool {
        let wild = c.value.containsSubstring("*") || c.value.containsSubstring("?")
        if wild, c.op == "equal" || c.op == "notEqual" {
            return wildcard(c.value, shown) == (c.op == "equal")
        }
        let order: Int?
        if let want = Double(c.value) {
            if let n = v.number { order = n < want ? -1 : n > want ? 1 : 0 } else { order = nil }
        } else {
            let a = shown.lowercased(), b = c.value.lowercased()
            order = v.isEmpty ? nil : a < b ? -1 : a > b ? 1 : 0
        }
        guard let o = order else { return c.op == "notEqual" }
        switch c.op {
        case "equal": return o == 0
        case "notEqual": return o != 0
        case "greaterThan": return o > 0
        case "greaterThanOrEqual": return o >= 0
        case "lessThan": return o < 0
        case "lessThanOrEqual": return o <= 0
        default: return true
        }
    }
}

extension WorkbookController {
    /// Put `rule` on a filter column (replacing its ticked list or earlier rule), or take
    /// the column's filter off with nil, and re-run the filter. One undo step.
    @discardableResult
    func setFilterRule(col: Int, _ rule: FilterRule?) -> FilterProblem? {
        guard var af = sheet.autoFilter else { return .noFilter }
        if refuses("autoFilter") { return nil }
        switch rule {
        case .compare(let a, _, let b)?:
            if a.value.isEmpty && a.op != "equal" && a.op != "notEqual" { return .needsValue }
            if let b, b.value.isEmpty && b.op != "equal" && b.op != "notEqual" { return .needsValue }
        case .top(_, _, let n)?: if n < 1 { return .badCount }
        default: break
        }
        af.columns[col] = nil
        af.rules[col] = rule
        if case .color(let fill, let rgb)? = rule,
           !book.dxfs.contains(where: { (fill ? $0.fill : $0.color).map { $0 & 0xFFFFFF } == rgb & 0xFFFFFF }) {
            _ = _appendDxf(fill ? DxfStyle(fill: rgb) : DxfStyle(color: rgb))
        }
        af.raw = nil
        structural {
            sheet.autoFilter = af
            reapplyFilter()
        }
        return nil
    }

    /// The test for one column's rule over the filter's data rows.
    func _ruleTest(_ rule: FilterRule, col: Int, _ af: AutoFilter) -> (Int) -> Bool {
        let rows = af.range.top + 1 ... max(af.range.top + 1, af.range.bottom)
        func value(_ r: Int) -> CellValue { sheet.value(CellAddress(row: r, col: col)) }
        switch rule {
        case .compare(let a, let isAnd, let b):
            return { r in
                let v = value(r), t = self.filterText(CellAddress(row: r, col: col))
                let x = FilterRule.holds(a, v, shown: t)
                guard let b else { return x }
                let y = FilterRule.holds(b, v, shown: t)
                return isAnd ? x && y : x || y
            }
        case .top(let top, let percent, let count):
            let nums = rows.compactMap { value($0).number }.sorted(by: top ? { $0 > $1 } : { $0 < $1 })
            guard !nums.isEmpty else { return { _ in false } }
            let n = percent ? max(1, Int(Double(nums.count) * Double(count) / 100)) : count
            let cut = nums[min(n, nums.count) - 1]
            return { r in guard let v = value(r).number else { return false }; return top ? v >= cut : v <= cut }
        case .average(let above):
            let nums = rows.compactMap { value($0).number }
            guard !nums.isEmpty else { return { _ in false } }
            let avg = nums.reduce(0, +) / Double(nums.count)
            return { r in guard let v = value(r).number else { return false }; return above ? v > avg : v < avg }
        case .period(let p):
            let today = floor(ExcelDate.now())
            return { r in guard let v = value(r).number else { return false }; return FilterRule.inPeriod(v, p, today: today) }
        case .color(let fill, let rgb):
            return { r in
                guard let cell = self.sheet.cells[CellAddress(row: r, col: col)] else { return false }
                let st = self.book.style(cell.style)
                return (fill ? st.fill : st.color).map { $0 & 0xFFFFFF } == rgb & 0xFFFFFF
            }
        }
    }

    /// The fill colours (or font colours) on a filter column's data, most used first.
    func filterColors(col: Int, fill: Bool) -> [UInt32] {
        guard let af = sheet.autoFilter, af.range.rows > 1 else { return [] }
        var counts: [UInt32: Int] = [:]
        for r in af.range.top + 1 ... _filterBottom(af) {
            guard let cell = sheet.cells[CellAddress(row: r, col: col)] else { continue }
            let st = book.style(cell.style)
            if let c = fill ? st.fill : st.color { counts[c & 0xFFFFFF, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }
}
