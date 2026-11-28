// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-FI-1: the Auto Fill Options button (after a fill-handle drag: Copy Cells, Fill Series, Fill Formatting
// Only, Fill Without Formatting, and Fill Days / Weekdays / Months / Years for dates) and Flash Fill (Ctrl+E,
// Cmd+E on a Mac, Home > Fill > Flash Fill): the empty cells of a column filled by the pattern its examples
// show, taken from the columns beside it.

import Foundation

/// How a fill-handle drag fills, as Auto Fill Options names the choices. `.flash` marks a Flash Fill.
enum FillHow: Equatable {
    case auto, copy, series, formatsOnly, withoutFormatting, days, weekdays, months, years, flash
}

/// The last fill, kept so the Auto Fill Options button can make it again another way.
struct LastFill {
    let source: CellRange
    let target: CellRange
    let how: FillHow
    let sheet: Int
    let dataRevision: Int
    /// The seed is dates: the menu adds Fill Days, Weekdays, Months and Years.
    let dates: Bool
    /// Flash Fill: the cells it filled.
    var changed: [CellAddress] = []

    func with(dataRevision r: Int) -> LastFill {
        var l = LastFill(source: source, target: target, how: how, sheet: sheet, dataRevision: r, dates: dates)
        l.changed = changed
        return l
    }
}

extension WorkbookController {
    /// The Auto Fill Options button's fill: the last one, while nothing has changed the cells since and its sheet is shown.
    var fillOptions: LastFill? {
        guard let l = lastFill, l.dataRevision == dataRevision, l.sheet == activeSheet else { return nil }
        return l
    }

    /// The menu's choices for the last fill, as Excel lists them.
    static func fillChoices(_ l: LastFill) -> [(String, FillHow)] {
        if l.how == .flash { return [] }
        var out: [(String, FillHow)] = [("Copy Cells", .copy), ("Fill Series", .series),
                                        ("Fill Formatting Only", .formatsOnly), ("Fill Without Formatting", .withoutFormatting)]
        if l.dates { out += [("Fill Days", .days), ("Fill Weekdays", .weekdays), ("Fill Months", .months), ("Fill Years", .years)] }
        return out
    }

    /// The choice the menu ticks: the drag's own guess shows as Fill Series, or Copy Cells where it copied.
    func fillTicked(_ l: LastFill) -> FillHow {
        guard l.how == .auto else { return l.how }
        let ws = book.sheets[l.sheet]
        let vertical = l.target.rows != l.source.rows
        // A single line's seed says it: a series where the drag continued one.
        let line: [Cell?] = vertical ? (l.source.top ... l.source.bottom).map { ws.cells[CellAddress(row: $0, col: l.source.left)] }
                                     : (l.source.left ... l.source.right).map { ws.cells[CellAddress(row: l.source.top, col: $0)] }
        return _series(line, count: 1, forward: true) == nil ? .copy : .series
    }

    /// Make the last fill again by `how`, in place of the one before: one undo step takes the new one back.
    func refill(_ how: FillHow) {
        guard let l = fillOptions, l.how != .flash, how != l.how else { return }
        undo()
        select(range: l.source, active: l.source.topLeft)
        let was = dataRevision
        fillSeries(to: l.target, how: how)
        if dataRevision == was { redo(); lastFill = l.with(dataRevision: dataRevision) }
    }

    /// Flash Fill's Undo Flash Fill.
    func undoFlashFill() {
        guard let l = fillOptions, l.how == .flash else { return }
        undo()
        lastFill = nil
    }

    /// The seed holds dates (numbers shown with a date format), and nothing else.
    func lastFillSeedIsDates(_ r: CellRange) -> Bool {
        let ws = sheet
        var any = false
        for a in r.cells {
            guard let c = ws.cells[a], !c.value.isEmpty else { continue }
            guard c.formula == nil, c.value.number != nil else { return false }
            let f = book.style(c.style).numberFormat.lowercased()
            guard f.containsSubstring("d") || f.containsSubstring("y") else { return false }
            any = true
        }
        return any
    }

    /// Dates by a unit (Fill Days, Weekdays, Months, Years): the step between the last two seeds in that unit, else 1.
    func _dateSeries(_ seed: [Cell?], _ how: FillHow, count: Int, forward: Bool) -> [String]? {
        let nums = seed.compactMap { c -> Double? in c?.formula == nil ? c?.value.number : nil }
        guard !nums.isEmpty, nums.count == seed.count else { return nil }
        let start = forward ? nums.last! : nums.first!
        var step = 1
        if nums.count >= 2 {
            let (y1, m1, _) = ExcelDate.ymd(nums[nums.count - 2]), (y2, m2, _) = ExcelDate.ymd(nums[nums.count - 1])
            switch how {
            case .days: step = Int(nums[nums.count - 1] - nums[nums.count - 2])
            case .months: step = (y2 * 12 + m2) - (y1 * 12 + m1)
            case .years: step = y2 - y1
            default: step = 1
            }
            if step == 0 { step = 1 }
        }
        if !forward { step = -step }
        let (y, m, d) = ExcelDate.ymd(start)
        func monthDay(_ yy: Int, _ mm: Int) -> Double {
            // A day past the month's end lands on its last day (31 Jan + 1 month is 28 or 29 Feb).
            let first = ExcelDate.serial(yy, mm, 1), next = ExcelDate.serial(yy, mm + 1, 1)
            return first + Double(min(d, Int(next - first)) - 1)
        }
        var out: [String] = []
        var cur = floor(start)
        for k in 1 ... max(1, count) where k <= count {
            switch how {
            case .days: cur = floor(start) + Double(step * k)
            case .weekdays:
                var n = abs(step)
                while n > 0 {
                    cur += step > 0 ? 1 : -1
                    let wd = ExcelDate.weekday(cur)
                    if wd != 1 && wd != 7 { n -= 1 }
                }
            case .months: cur = monthDay(y, m + step * k)
            case .years: cur = monthDay(y + step * k, m)
            default: return nil
            }
            out.append(NumberFormat.full(cur + (start - floor(start))))
        }
        return out
    }

    // MARK: Flash Fill

    static let flashFillNoPattern = "We looked at all the data next to your selection and didn't see a pattern for filling in values for you. To use Flash Fill, enter a couple of examples of the output you'd like to see, keep the active cell in the column you want filled in, and click the Flash Fill button again."

    /// Fill the empty cells of the active cell's column, down its region, by the pattern of the examples typed
    /// there, from the columns beside it. Nil when done; else Excel's message.
    @discardableResult
    func flashFill() -> String? {
        let ws = sheet
        let col = active.col
        let region = currentRegion(active)
        guard region.cols > 1 else { return Self.flashFillNoPattern }
        let sources = (region.left ... region.right).filter { $0 != col }
        func text(_ r: Int, _ c: Int) -> String? {
            guard let cell = ws.cells[CellAddress(row: r, col: c)], !cell.value.isEmpty else { return nil }
            if case .text(let t) = cell.value { return t }
            return NumberFormat.display(cell.value, book.style(cell.style).numberFormat, width: 255).text
        }
        func row(_ r: Int) -> [Int: String] {
            var m: [Int: String] = [:]
            for c in sources { if let t = text(r, c) { m[c] = t } }
            return m
        }
        var examples: [(Int, String)] = []
        var blanks: [Int] = []
        for r in region.top ... region.bottom {
            if let t = text(r, col) {
                if ws.cells[CellAddress(row: r, col: col)]?.formula == nil { examples.append((r, t)) }
            } else if !row(r).isEmpty { blanks.append(r) }
        }
        guard !examples.isEmpty, !blanks.isEmpty else { return Self.flashFillNoPattern }
        // A heading over the column is not an example: without it when the rest agree and it does not.
        var program = FlashFill.learn(examples.map { (row($0.0), $0.1) })
        if program == nil, examples.count > 1, examples[0].0 == region.top {
            program = FlashFill.learn(examples.dropFirst().map { (row($0.0), $0.1) })
        }
        guard let p = program else { return Self.flashFillNoPattern }
        var fills: [(CellAddress, String)] = []
        for r in blanks {
            if let v = FlashFill.run(p, row(r)), !v.isEmpty { fills.append((CellAddress(row: r, col: col), v)) }
        }
        guard !fills.isEmpty else { return Self.flashFillNoPattern }
        if refusesEdit(fills.map(\.0)) { return nil }
        var before: [CellAddress: Cell?] = [:]
        for (a, v) in fills {
            before[a] = .some(ws.cells[a])
            var c = ws.cells[a] ?? Cell(input: "")
            c.formula = nil; c.cached = nil
            c.input = v
            c.value = .text(v)       // Flash Fill writes text, as Excel's (007 stays 007)
            ws.cells[a] = c
        }
        _record(sheet: activeSheet, before: before)
        var l = LastFill(source: CellRange(active), target: region, how: .flash, sheet: activeSheet,
                         dataRevision: dataRevision, dates: false)
        l.changed = fills.map(\.0)
        lastFill = l
        return nil
    }
}

/// Flash Fill's pattern finder: an output is learned as a run of parts, each a whole source cell, a word of one
/// (counted from the start or the end, maybe only its first letter), or fixed text, each word in a casing.
/// The cheapest run of parts that makes every example is the pattern.
enum FlashFill {
    enum Casing: CaseIterable { case same, upper, lower, proper }
    enum Part: Equatable {
        case fixed(String)
        case whole(col: Int, casing: Casing)
        case word(col: Int, index: Int, fromEnd: Bool, casing: Casing, firstLetter: Bool)
    }
    typealias Program = [Part]

    /// The words of a cell: its runs of letters and digits.
    static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        for ch in s {
            if ch.isLetter || ch.isNumber { cur.append(ch) } else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    static func cased(_ s: String, _ c: Casing) -> String {
        switch c {
        case .same: return s
        case .upper: return s.uppercased()
        case .lower: return s.lowercased()
        case .proper: return s.prefix(1).uppercased() + s.dropFirst().lowercased()
        }
    }

    static func value(_ p: Part, _ row: [Int: String]) -> String? {
        switch p {
        case .fixed(let s): return s
        case .whole(let col, let c): return row[col].map { cased($0, c) }
        case .word(let col, let i, let fromEnd, let c, let first):
            guard let t = row[col] else { return nil }
            let w = words(t)
            let k = fromEnd ? w.count - 1 - i : i
            guard k >= 0, k < w.count else { return nil }
            let s = cased(w[k], c)
            return first ? String(s.prefix(1)) : s
        }
    }

    static func run(_ p: Program, _ row: [Int: String]) -> String? {
        var out = ""
        for part in p { guard let v = value(part, row) else { return nil }; out += v }
        return out
    }

    private static func cost(_ p: Part) -> Double {
        switch p {
        case .fixed(let s): return s.reduce(0) { $0 + (($1.isLetter || $1.isNumber) ? 3 : 1) }
        case .whole(_, let c): return 1 + (c == .same ? 0 : 0.1)
        case .word(_, _, let fromEnd, let c, let first): return 1 + (c == .same ? 0 : 0.1) + (fromEnd ? 0.05 : 0) + (first ? 0.5 : 0)
        }
    }

    /// The cheapest program that makes every example's output from its row, or nil.
    static func learn(_ examples: [([Int: String], String)]) -> Program? {
        guard let (row0, out0) = examples.first else { return nil }
        let candidates = programs(row0, out0, keep: 400)
        return candidates.first { p in examples.dropFirst().allSatisfy { run(p, $0.0) == $0.1 } }
    }

    /// Programs that make `out` from `row`, cheapest first, at most `keep` for each suffix of the output.
    static func programs(_ row: [Int: String], _ out: String, keep: Int) -> [Program] {
        let o = Array(out)
        let n = o.count
        guard n > 0 else { return [] }
        // Every part that can stand at each position, with its length.
        var at: [[(Part, Int)]] = Array(repeating: [], count: n)
        for (col, t) in row.sorted(by: { $0.key < $1.key }) {
            let w = words(t)
            for pos in 0 ..< n {
                for c in Casing.allCases {
                    let whole = Array(cased(t, c))
                    if !whole.isEmpty, pos + whole.count <= n, Array(o[pos ..< pos + whole.count]) == whole {
                        at[pos].append((.whole(col: col, casing: c), whole.count))
                    }
                    for (i, word) in w.enumerated() {
                        let s = Array(cased(word, c))
                        for fromEnd in [false, true] {
                            let idx = fromEnd ? w.count - 1 - i : i
                            if pos + s.count <= n, Array(o[pos ..< pos + s.count]) == s {
                                at[pos].append((.word(col: col, index: idx, fromEnd: fromEnd, casing: c, firstLetter: false), s.count))
                            }
                            if s.count > 1, let f = s.first, o[pos] == f {
                                at[pos].append((.word(col: col, index: idx, fromEnd: fromEnd, casing: c, firstLetter: true), 1))
                            }
                        }
                    }
                }
            }
        }
        // Cheapest programs for each suffix, from the end.
        var best: [[(Program, Double)]] = Array(repeating: [], count: n + 1)
        best[n] = [([], 0)]
        for pos in stride(from: n - 1, through: 0, by: -1) {
            var here: [(Program, Double)] = []
            var options = at[pos]
            options.append((.fixed(String(o[pos])), 1))
            for (part, len) in options {
                for (rest, c) in best[pos + len] {
                    var prog = [part] + rest
                    var total = cost(part) + c
                    // Fixed text runs join into one part.
                    if case .fixed(let a) = part, case .fixed(let b)? = rest.first {
                        prog = [.fixed(a + b)] + rest.dropFirst()
                        total = cost(.fixed(a + b)) + rest.dropFirst().reduce(0) { $0 + cost($1) }
                    }
                    here.append((prog, total))
                }
            }
            here.sort { $0.1 < $1.1 }
            best[pos] = Array(here.prefix(keep))
        }
        return best[0].map(\.0)
    }
}
