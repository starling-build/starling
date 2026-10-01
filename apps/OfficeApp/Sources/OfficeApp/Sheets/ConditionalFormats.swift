// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Conditional formatting, drawn (docs/plans/sheets.md: kept and drawn for
// the simple kinds, not edited). The rules are read from the sheet's kept
// `<conditionalFormatting>` elements — the XML itself is written back as
// the file had it — and evaluated for the cells on screen:
//
//   cellIs (the eight comparisons), expression, containsText / notContains /
//   beginsWith / endsWith, containsBlanks / notContainsBlanks, containsErrors
//   / notContainsErrors, top10 (top/bottom N or N%), aboveAverage (above,
//   below, or equal), duplicateValues / uniqueValues — each applying its
//   dxf; colorScale (2 or 3 colours) and dataBar (a solid bar, Excel 2007's
//   look) computed from the range.
//
// Rules apply in priority order; a cell takes the first rule's setting of
// each property, and stopIfTrue ends the walk. Formulas are relative to the
// top-left cell of the rule's first range, as Excel stores them.
// Not drawn: icon sets, the x14 rules in extLst, date-occurring rules.

import Foundation

struct CFValue: Equatable {
    var type: String          // min, max, num, percent, percentile, formula
    var value: Double?
}

struct CFRule {
    enum Kind {
        case cellIs(op: String, FormulaExpr?, FormulaExpr?)
        case expression(FormulaExpr)
        case text(op: String, String)
        case blanks(Bool)
        case errors(Bool)
        case top(rank: Int, percent: Bool, bottom: Bool)
        case average(above: Bool, equal: Bool)
        case duplicates(unique: Bool)
        case colorScale([CFValue], [UInt32])
        case dataBar(CFValue, CFValue, UInt32)
    }
    var ranges: [CellRange]
    var priority: Int
    var dxf: Int?
    var stopIfTrue: Bool
    var kind: Kind

    var origin: CellAddress { ranges.first?.topLeft ?? CellAddress(row: 0, col: 0) }
    func covers(_ a: CellAddress) -> Bool { ranges.contains { $0.contains(a) } }
}

/// What the rules say for one cell.
struct CFLook {
    var dxf = DxfStyle()
    var fill: UInt32? = nil            // from a colour scale
    var bar: (fraction: Double, color: UInt32)? = nil
    var isEmpty: Bool { dxf == DxfStyle() && fill == nil && bar == nil }
}

enum ConditionalFormats {
    /// The rules in a sheet's kept elements, by priority.
    static func rules(_ ws: Worksheet, theme: [UInt32]) -> [CFRule] {
        var out: [CFRule] = []
        for (name, text) in ws.keptElements where name == "conditionalFormatting" {
            guard let node = XNode.parse(Data(text.utf8)) else { continue }
            let ranges = (node["sqref"] ?? "").split(separator: " ").compactMap { CellRange(String($0)) }
            guard !ranges.isEmpty else { continue }
            for r in node.kids("cfRule") {
                let formulas = r.kids("formula").map { try? Formula.parse("=" + $0.text) }
                let kind: CFRule.Kind
                switch r["type"] ?? "" {
                case "cellIs":
                    kind = .cellIs(op: r["operator"] ?? "equal", formulas.first ?? nil, formulas.count > 1 ? formulas[1] : nil)
                case "expression":
                    guard let f = formulas.first ?? nil else { continue }
                    kind = .expression(f)
                case "containsText", "notContainsText", "beginsWith", "endsWith":
                    kind = .text(op: r["type"]!, r["text"] ?? "")
                case "containsBlanks": kind = .blanks(true)
                case "notContainsBlanks": kind = .blanks(false)
                case "containsErrors": kind = .errors(true)
                case "notContainsErrors": kind = .errors(false)
                case "top10":
                    kind = .top(rank: Int(r["rank"] ?? "10") ?? 10, percent: r["percent"] == "1", bottom: r["bottom"] == "1")
                case "aboveAverage":
                    kind = .average(above: r["aboveAverage"] != "0", equal: r["equalAverage"] == "1")
                case "duplicateValues": kind = .duplicates(unique: false)
                case "uniqueValues": kind = .duplicates(unique: true)
                case "colorScale":
                    guard let cs = r.child("colorScale") else { continue }
                    let vals = cs.kids("cfvo").map { CFValue(type: $0["type"] ?? "min", value: Double($0["val"] ?? "")) }
                    let colors = cs.kids("color").compactMap { Xlsx._color($0, theme: theme) }
                    guard vals.count >= 2, vals.count == colors.count else { continue }
                    kind = .colorScale(vals, colors)
                case "dataBar":
                    guard let db = r.child("dataBar") else { continue }
                    let vals = db.kids("cfvo").map { CFValue(type: $0["type"] ?? "min", value: Double($0["val"] ?? "")) }
                    guard vals.count == 2, let c = db.child("color").flatMap({ Xlsx._color($0, theme: theme) }) else { continue }
                    kind = .dataBar(vals[0], vals[1], c)
                default:
                    continue
                }
                out.append(CFRule(ranges: ranges, priority: Int(r["priority"] ?? "") ?? Int.max,
                                  dxf: r["dxfId"].flatMap { Int($0) }, stopIfTrue: r["stopIfTrue"] == "1", kind: kind))
            }
        }
        return out.sorted { $0.priority < $1.priority }
    }
}

/// The rules of one sheet with the per-range figures they need, for one
/// state of its data.
final class CFEvaluator {
    let rules: [CFRule]
    private let book: Workbook
    private let engine: CalcEngine
    private let sheet: Int
    private var _numbers: [Int: [Double]] = [:]     // rule → its range's numbers, sorted
    private var _counts: [Int: [String: Int]] = [:] // rule → how often each value occurs

    init(rules: [CFRule], book: Workbook, engine: CalcEngine, sheet: Int) {
        self.rules = rules
        self.book = book
        self.engine = engine
        self.sheet = sheet
    }

    private var _ws: Worksheet { book.sheets[sheet] }

    /// Cells of a rule's ranges that hold something: a whole-column rule
    /// visits the sheet's cells, not a million rows.
    private func _cells(_ rule: CFRule) -> [CellAddress] {
        let ws = _ws
        let area = rule.ranges.reduce(0) { $0 + $1.rows * $1.cols }
        if area <= ws.cells.count { return rule.ranges.flatMap { r in (r.top ... r.bottom).flatMap { row in (r.left ... r.right).map { CellAddress(row: row, col: $0) } } } }
        return ws.cells.keys.filter { rule.covers($0) }
    }

    private func _numbersOf(_ i: Int) -> [Double] {
        if let n = _numbers[i] { return n }
        let n = _cells(rules[i]).compactMap { engine.value(sheet, $0).number }.sorted()
        _numbers[i] = n
        return n
    }

    private func _countsOf(_ i: Int) -> [String: Int] {
        if let c = _counts[i] { return c }
        var c: [String: Int] = [:]
        for a in _cells(rules[i]) {
            let v = engine.value(sheet, a)
            if !v.isEmpty { c[_key(v), default: 0] += 1 }
        }
        _counts[i] = c
        return c
    }

    private func _key(_ v: CellValue) -> String {
        if let n = v.number { return "n\(n)" }
        return "t" + NumberFormat.display(v, "General", width: 255).text.lowercased()
    }

    /// A cfvo's number over its rule's range.
    private func _threshold(_ v: CFValue, _ i: Int) -> Double? {
        let nums = _numbersOf(i)
        guard let lo = nums.first, let hi = nums.last else { return nil }
        switch v.type {
        case "min": return lo
        case "max": return hi
        case "num": return v.value
        case "percent": return lo + (hi - lo) * (v.value ?? 0) / 100
        case "percentile":
            let p = (v.value ?? 50) / 100 * Double(nums.count - 1)
            let k = Int(p.rounded(.down)), f = p - Double(k)
            return k + 1 < nums.count ? nums[k] + (nums[k + 1] - nums[k]) * f : nums[k]
        default: return v.value
        }
    }

    private func _value(_ e: FormulaExpr?, _ rule: CFRule, _ a: CellAddress) -> CellValue {
        guard let e else { return .empty }
        let shifted = Formula.shifted(e, rows: a.row - rule.origin.row, cols: a.col - rule.origin.col)
        let ctx = EvalContext(engine: engine, sheet: sheet, cell: a)
        return engine.scalar(engine.evaluate(shifted, ctx), ctx)
    }

    private func _true(_ v: CellValue) -> Bool {
        switch v {
        case .bool(let b): return b
        case .number(let n): return n != 0
        default: return false
        }
    }

    /// What the rules make of cell `a`; nil when none applies.
    func look(_ a: CellAddress) -> CFLook? {
        var look = CFLook()
        var any = false
        for (i, rule) in rules.enumerated() where rule.covers(a) {
            let v = engine.value(sheet, a)
            var hit = false
            switch rule.kind {
            case .cellIs(let op, let f1, let f2):
                guard !v.isEmpty || op == "equal" || op == "notEqual" else { break }
                let x = _value(f1, rule, a), c1 = CalcEngine.compare(v, x)
                switch op {
                case "lessThan": hit = c1 < 0
                case "lessThanOrEqual": hit = c1 <= 0
                case "greaterThan": hit = c1 > 0
                case "greaterThanOrEqual": hit = c1 >= 0
                case "notEqual": hit = c1 != 0
                case "between", "notBetween":
                    let y = _value(f2, rule, a)
                    let lo = CalcEngine.compare(x, y) <= 0 ? x : y, hi = CalcEngine.compare(x, y) <= 0 ? y : x
                    let inside = CalcEngine.compare(v, lo) >= 0 && CalcEngine.compare(v, hi) <= 0
                    hit = op == "between" ? inside : !inside
                default: hit = c1 == 0
                }
            case .expression(let f):
                hit = _true(_value(f, rule, a))
            case .text(let op, let needle):
                let t = NumberFormat.display(v, "General", width: 255).text.lowercased(), n = needle.lowercased()
                switch op {
                case "notContainsText": hit = !t.containsSubstring(n)
                case "beginsWith": hit = t.hasPrefix(n)
                case "endsWith": hit = t.hasSuffix(n)
                default: hit = t.containsSubstring(n)
                }
            case .blanks(let want):
                let blank = v.isEmpty || (v.isText && NumberFormat.display(v, "General", width: 255).text.trimmingWhitespace().isEmpty)
                hit = blank == want
            case .errors(let want):
                if case .error = v { hit = want } else { hit = !want }
            case .top(let rank, let percent, let bottom):
                guard let n = v.number else { break }
                let nums = _numbersOf(i)
                let k = max(1, percent ? Int(Double(nums.count) * Double(rank) / 100) : rank)
                guard !nums.isEmpty else { break }
                hit = bottom ? n <= nums[min(nums.count, k) - 1] : n >= nums[max(0, nums.count - k)]
            case .average(let above, let equal):
                guard let n = v.number else { break }
                let nums = _numbersOf(i)
                guard !nums.isEmpty else { break }
                let avg = nums.reduce(0, +) / Double(nums.count)
                hit = above ? (n > avg || equal && n == avg) : (n < avg || equal && n == avg)
            case .duplicates(let unique):
                guard !v.isEmpty else { break }
                let count = _countsOf(i)[_key(v)] ?? 0
                hit = unique ? count == 1 : count > 1
            case .colorScale(let vals, let colors):
                guard let n = v.number, look.fill == nil else { break }
                let ts = vals.map { _threshold($0, i) }
                guard ts.allSatisfy({ $0 != nil }) else { break }
                let t = ts.map { $0! }
                look.fill = Self._scale(n, t, colors)
                any = true
                continue
            case .dataBar(let lo, let hi, let color):
                guard let n = v.number, look.bar == nil, let a0 = _threshold(lo, i), let b0 = _threshold(hi, i) else { break }
                // Excel 2007 bars run 10%–90% of the cell between min and max.
                let f = b0 > a0 ? min(1, max(0, (n - a0) / (b0 - a0))) : 1
                look.bar = (0.1 + 0.8 * f, color)
                any = true
                continue
            }
            guard hit else { continue }
            if let d = rule.dxf, d < book.dxfs.count {
                let x = book.dxfs[d]
                if look.dxf.bold == nil { look.dxf.bold = x.bold }
                if look.dxf.italic == nil { look.dxf.italic = x.italic }
                if look.dxf.underline == nil { look.dxf.underline = x.underline }
                if look.dxf.strike == nil { look.dxf.strike = x.strike }
                if look.dxf.color == nil { look.dxf.color = x.color }
                if look.dxf.fill == nil { look.dxf.fill = x.fill }
            }
            any = true
            if rule.stopIfTrue { break }
        }
        return any && !look.isEmpty ? look : nil
    }

    /// A colour between the scale's stops.
    static func _scale(_ n: Double, _ t: [Double], _ colors: [UInt32]) -> UInt32 {
        if n <= t[0] { return colors[0] }
        for k in 1 ..< t.count where n <= t[k] {
            let f = t[k] > t[k - 1] ? (n - t[k - 1]) / (t[k] - t[k - 1]) : 1
            return _mix(colors[k - 1], colors[k], f)
        }
        return colors[colors.count - 1]
    }

    static func _mix(_ a: UInt32, _ b: UInt32, _ f: Double) -> UInt32 {
        func ch(_ c: UInt32, _ s: UInt32) -> Double { Double((c >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) + (ch(b, s) - ch(a, s)) * f).rounded()) << s }
        return m(16) | m(8) | m(0)
    }
}
