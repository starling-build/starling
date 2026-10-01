// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Formula evaluation: references resolve against the workbook, values
// coerce the way Excel coerces them, and a recalculation evaluates every
// formula once, on demand and memoised, so the order follows the
// dependencies by itself. A formula met again while it is being computed
// is a circular reference: Excel warns and shows 0, and so does this.
//
// Recalculation is whole-workbook for now (one pass over every formula,
// each evaluated once): fast enough well past the sheets people type by
// hand. A dependency graph that recomputes only what a change reaches is
// the plan's next step when a real file says it is needed.

import Foundation

/// What an expression evaluates to before it lands in a cell: a value, a
/// reference to cells (a function like SUM wants the cells, not one
/// value), or an array (a function's computed list).
enum EvalValue {
    case scalar(CellValue)
    case range(sheet: Int, CellRange)
    case array([[CellValue]])

    static func number(_ n: Double) -> EvalValue {
        n.isNaN || n.isInfinite ? .scalar(.error(.num)) : .scalar(.number(n))
    }
    static func error(_ e: ExcelError) -> EvalValue { .scalar(.error(e)) }
}

/// Where a formula is being evaluated: its sheet and cell.
struct EvalContext {
    let engine: CalcEngine
    let sheet: Int
    let cell: CellAddress
}

final class CalcEngine {
    let book: Workbook
    /// Formula cells of this pass: being computed, or done.
    private var _visiting: [SheetCell] = []
    private var _done: Set<SheetCell> = []
    /// Cells found in a cycle during the last recalculation.
    private(set) var circular: Set<SheetCell> = []
    /// NOW()/TODAY() during one pass, so a sheet agrees with itself.
    private(set) var now: Double = ExcelDate.now()

    struct SheetCell: Hashable {
        let sheet: Int
        let cell: CellAddress
    }

    init(_ book: Workbook) { self.book = book }

    /// Recompute every formula in the workbook.
    func recalculate() {
        _done.removeAll(keepingCapacity: true)
        _visiting.removeAll()
        circular.removeAll()
        now = ExcelDate.now()
        for (si, sheet) in book.sheets.enumerated() {
            for (addr, cell) in sheet.cells where cell.formula != nil {
                _ = value(si, addr)
            }
        }
    }

    /// A cell's value, computing its formula if this pass has not yet.
    func value(_ sheet: Int, _ addr: CellAddress) -> CellValue {
        guard sheet >= 0, sheet < book.sheets.count else { return .error(.ref) }
        let ws = book.sheets[sheet]
        guard let cell = ws.cells[addr] else { return .empty }
        guard let f = cell.formula else { return cell.value }
        let key = SheetCell(sheet: sheet, cell: addr)
        if _done.contains(key) { return cell.value }
        if let at = _visiting.firstIndex(of: key) {
            // Every cell on the loop shows 0, as Excel's do.
            for k in _visiting[at...] { circular.insert(k) }
            return .number(0)
        }
        _visiting.append(key)
        let ctx = EvalContext(engine: self, sheet: sheet, cell: addr)
        var v = scalar(evaluate(f, ctx), ctx)
        if circular.contains(key) { v = .number(0) }
        _visiting.removeLast()
        _done.insert(key)
        // A function we do not have: show what the file last computed.
        if v == .error(.name), let cached = cell.cached, Formula.usesUnknownFunction(f) { v = cached }
        // So does an array formula's cell, until arrays spill here.
        if cell.arrayRef != nil, let cached = cell.cached { v = cached }
        // An empty result of a formula shows as 0, as Excel's does.
        if v.isEmpty { v = .number(0) }
        ws.cells[addr]?.value = v
        return v
    }

    /// Evaluate a formula that is not in a cell (the formula bar's preview,
    /// a test), as if it were in `cell` on `sheet`.
    func evaluate(_ text: String, sheet: Int = 0, at cell: CellAddress = CellAddress(row: 0, col: 0)) -> CellValue {
        guard let f = try? Formula.parse(text) else { return .error(.name) }
        let ctx = EvalContext(engine: self, sheet: sheet, cell: cell)
        let v = scalar(evaluate(f, ctx), ctx)
        return v.isEmpty ? .number(0) : v
    }

    // MARK: Expressions

    func evaluate(_ e: FormulaExpr, _ ctx: EvalContext) -> EvalValue {
        switch e {
        case .number(let n, _): return .scalar(.number(n))
        case .text(let s): return .scalar(.text(s))
        case .bool(let b): return .scalar(.bool(b))
        case .error(let err): return .error(err)
        case .missing: return .scalar(.empty)
        case .paren(let x): return evaluate(x, ctx)
        case .ref(let r): return resolve(r, ctx)
        case .structured(let t): return resolveStructured(t, ctx)
        case .name(let n):
            guard let target = book.names[n.uppercased()],
                  let parsed = try? Formula.parse(target) else {
                // A table's own name is its data rows (Table1 = Table1[]).
                if book.sheets.contains(where: { $0.tables.contains { $0.name.lowercased() == n.lowercased() } }) {
                    return resolveStructured(n + "[]", ctx)
                }
                return .error(.name)
            }
            return evaluate(parsed, ctx)
        case .negate(let x):
            switch number(evaluate(x, ctx), ctx) {
            case .success(let n): return .number(-n)
            case .failure(let err): return .error(err)
            }
        case .plus(let x): return evaluate(x, ctx)
        case .percent(let x):
            switch number(evaluate(x, ctx), ctx) {
            case .success(let n): return .number(n / 100)
            case .failure(let err): return .error(err)
            }
        case .binary(let op, let a, let b):
            return binary(op, scalar(evaluate(a, ctx), ctx), scalar(evaluate(b, ctx), ctx))
        case .call(let name, let args):
            guard let f = SheetFunctions.table[name] ?? SheetFunctions.table[_stripPrefix(name)] else {
                return .error(.name)
            }
            return f(args, ctx)
        }
    }

    /// _xlfn.XLOOKUP → XLOOKUP (newer functions carry a prefix in files).
    private func _stripPrefix(_ n: String) -> String {
        for p in ["_XLFN._XLWS.", "_XLFN.", "_XLWS."] where n.hasPrefix(p) { return String(n.dropFirst(p.count)) }
        return n
    }

    func resolve(_ r: FormulaRef, _ ctx: EvalContext) -> EvalValue {
        var sheet = ctx.sheet
        if let name = r.sheet {
            guard let i = book.sheet(named: name) else { return .error(.ref) }
            sheet = i
        }
        if r.isCell, let row = r.start.row, let col = r.start.col {
            return .scalar(value(sheet, CellAddress(row: row, col: col)))
        }
        return .range(sheet: sheet, r.range)
    }

    /// One value from anything: a range in a single cell's place gives the
    /// cell in the formula's row or column (Excel's implicit intersection).
    func scalar(_ v: EvalValue, _ ctx: EvalContext) -> CellValue {
        switch v {
        case .scalar(let s): return s
        case .array(let rows): return rows.first?.first ?? .empty
        case .range(let sheet, let r):
            if r.isSingle { return value(sheet, r.topLeft) }
            if r.cols == 1, ctx.cell.row >= r.top, ctx.cell.row <= r.bottom {
                return value(sheet, CellAddress(row: ctx.cell.row, col: r.left))
            }
            if r.rows == 1, ctx.cell.col >= r.left, ctx.cell.col <= r.right {
                return value(sheet, CellAddress(row: r.top, col: ctx.cell.col))
            }
            return .error(.value)
        }
    }

    // MARK: Coercion

    func number(_ v: EvalValue, _ ctx: EvalContext) -> Result<Double, ExcelError> {
        CalcEngine.toNumber(scalar(v, ctx))
    }

    static func toNumber(_ v: CellValue) -> Result<Double, ExcelError> {
        switch v {
        case .number(let n): return .success(n)
        case .bool(let b): return .success(b ? 1 : 0)
        case .empty: return .success(0)
        case .error(let e): return .failure(e)
        case .text(let s):
            if let n = InputParser.number(s)?.value { return .success(n) }
            return .failure(.value)
        }
    }

    static func toText(_ v: CellValue) -> Result<String, ExcelError> {
        switch v {
        case .number(let n): return .success(NumberFormat.full(n))
        case .text(let s): return .success(s)
        case .bool(let b): return .success(b ? "TRUE" : "FALSE")
        case .empty: return .success("")
        case .error(let e): return .failure(e)
        }
    }

    static func toBool(_ v: CellValue) -> Result<Bool, ExcelError> {
        switch v {
        case .bool(let b): return .success(b)
        case .number(let n): return .success(n != 0)
        case .empty: return .success(false)
        case .error(let e): return .failure(e)
        case .text(let s):
            switch s.uppercased() {
            case "TRUE": return .success(true)
            case "FALSE": return .success(false)
            default: return .failure(.value)
            }
        }
    }

    // MARK: Operators

    func binary(_ op: BinaryOp, _ a: CellValue, _ b: CellValue) -> EvalValue {
        if let e = a.error { return .error(e) }
        if let e = b.error { return .error(e) }
        switch op {
        case .concat:
            guard case .success(let x) = CalcEngine.toText(a), case .success(let y) = CalcEngine.toText(b) else {
                return .error(.value)
            }
            return .scalar(.text(x + y))
        case .eq, .ne, .lt, .gt, .le, .ge:
            let c = CalcEngine.compare(a, b)
            let r: Bool
            switch op {
            case .eq: r = c == 0
            case .ne: r = c != 0
            case .lt: r = c < 0
            case .gt: r = c > 0
            case .le: r = c <= 0
            default: r = c >= 0
            }
            return .scalar(.bool(r))
        default:
            let x: Double, y: Double
            switch CalcEngine.toNumber(a) { case .success(let n): x = n; case .failure(let e): return .error(e) }
            switch CalcEngine.toNumber(b) { case .success(let n): y = n; case .failure(let e): return .error(e) }
            switch op {
            case .add: return .number(x + y)
            case .sub: return .number(x - y)
            case .mul: return .number(x * y)
            case .div: return y == 0 ? .error(.div0) : .number(x / y)
            case .pow:
                if x == 0 && y < 0 { return .error(.div0) }
                if x < 0 && y != y.rounded() { return .error(.num) }
                return .number(pow(x, y))
            default: return .error(.value)
            }
        }
    }

    /// Excel's ordering for comparisons and sorting: numbers < text <
    /// booleans, text case-insensitively; an empty cell is 0, "" or FALSE
    /// to match the other side.
    static func compare(_ a: CellValue, _ b: CellValue) -> Int {
        func rank(_ v: CellValue) -> Int {
            switch v {
            case .number, .empty: return 0
            case .text: return 1
            case .bool: return 2
            case .error: return 3
            }
        }
        var a = a, b = b
        if a.isEmpty {
            switch b { case .text: a = .text(""); case .bool: a = .bool(false); default: a = .number(0) }
        }
        if b.isEmpty {
            switch a { case .text: b = .text(""); case .bool: b = .bool(false); default: b = .number(0) }
        }
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb ? -1 : 1 }
        switch (a, b) {
        case (.number(let x), .number(let y)):
            // Excel compares to 15 significant digits: 0.1+0.2 = 0.3 is TRUE.
            if x == y || abs(x - y) <= max(abs(x), abs(y)) * 1e-15 { return 0 }
            return x < y ? -1 : 1
        case (.text(let x), .text(let y)):
            let lx = x.lowercased(), ly = y.lowercased()
            return lx < ly ? -1 : (lx > ly ? 1 : 0)
        case (.bool(let x), .bool(let y)): return x == y ? 0 : (!x ? -1 : 1)
        default: return 0
        }
    }

    // MARK: Ranges

    /// Every value in a range, row by row; empty cells included when asked.
    func values(_ sheet: Int, _ r: CellRange, includeEmpty: Bool = false) -> [CellValue] {
        guard sheet >= 0, sheet < book.sheets.count else { return [] }
        let ws = book.sheets[sheet]
        let area = r.rows * r.cols
        if !includeEmpty && area > ws.cells.count * 2 {
            // A big range over a sparse sheet: walk the cells that exist.
            return ws.cells.keys.filter { r.contains($0) }.sorted().map { value(sheet, $0) }
        }
        let used = ws.usedExtent
        let bottom = includeEmpty ? r.bottom : min(r.bottom, used.row)
        let right = includeEmpty ? r.right : min(r.right, used.col)
        guard bottom >= r.top, right >= r.left else { return [] }
        var out: [CellValue] = []
        out.reserveCapacity((bottom - r.top + 1) * (right - r.left + 1))
        for row in r.top ... bottom {
            for col in r.left ... right {
                let v = value(sheet, CellAddress(row: row, col: col))
                if includeEmpty || !v.isEmpty { out.append(v) }
            }
        }
        return out
    }

    /// A range or array as a grid of values, empties included — for
    /// lookups and INDEX, which address by position. Clipped to the
    /// sheet's used area (a whole column has a million rows).
    func grid(_ v: EvalValue, _ ctx: EvalContext) -> [[CellValue]] {
        switch v {
        case .scalar(let s): return [[s]]
        case .array(let a): return a
        case .range(let sheet, let r):
            guard sheet >= 0, sheet < book.sheets.count else { return [[.error(.ref)]] }
            let used = book.sheets[sheet].usedExtent
            let bottom = min(r.bottom, max(used.row, r.top))
            let right = min(r.right, max(used.col, r.left))
            return (r.top ... bottom).map { row in
                (r.left ... right).map { col in value(sheet, CellAddress(row: row, col: col)) }
            }
        }
    }
}

/// How Excel reads what is typed into a cell: numbers (with thousands
/// separators, a currency sign, a percent sign, scientific notation),
/// booleans, errors, dates and times; anything else is text, and a
/// leading apostrophe forces text.
enum InputParser {
    enum Parsed: Equatable {
        case value(CellValue, format: String?)
    }

    /// A number in `text`, and the format it implies ("0%", "$#,##0.00",
    /// "m/d/yyyy"…) when it implies one.
    static func number(_ text: String) -> (value: Double, format: String?)? {
        var s = text.trimmingWhitespace()
        guard !s.isEmpty else { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() }
        else if s.hasPrefix("+") { s.removeFirst() }
        var currency = false
        if s.hasPrefix("$") { currency = true; s.removeFirst() }
        if s.hasPrefix("-") && !negative { negative = true; s.removeFirst() }
        var percent = false
        if s.hasSuffix("%") { percent = true; s.removeLast() }
        let hadComma = s.containsSubstring(",")
        if hadComma {
            // Commas only as thousands separators: groups of three.
            let intPart = s.split(separator: ".", maxSplits: 1).first.map(String.init) ?? s
            let groups = intPart.split(separator: ",", omittingEmptySubsequences: false)
            guard groups.count > 1, groups.dropFirst().allSatisfy({ $0.count == 3 }),
                  let f = groups.first, !f.isEmpty, f.count <= 3 else { return nil }
            s = s.replacingAll(",", with: "")
        }
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "e" || $0 == "E" || $0 == "+" || $0 == "-" }),
              s.first!.isNumber || s.first == ".", let v = Double(s) else {
            return _dateOrTime(text).map { ($0.0, $0.1) }
        }
        var value = negative ? -v : v
        if percent { value /= 100 }
        let decimals = s.split(separator: ".").count > 1 && !s.lowercased().contains("e")
            ? s.split(separator: ".")[1].count : 0
        var format: String? = nil
        if percent { format = decimals > 0 ? "0." + String(repeating: "0", count: decimals) + "%" : "0%" }
        else if currency { format = decimals > 0 ? "$#,##0.00" : "$#,##0" }
        else if hadComma { format = decimals > 0 ? "#,##0.00" : "#,##0" }
        else if s.lowercased().contains("e") { format = "0.00E+00" }
        return (value, format)
    }

    /// Dates as m/d/yyyy, m/d, yyyy-mm-dd and d-mmm-yyyy; times as h:mm,
    /// h:mm:ss, with AM/PM. The US order, as Excel's en-US default.
    private static func _dateOrTime(_ text: String) -> (Double, String)? {
        let t = text.trimmingWhitespace()
        // Time.
        var timePart = t.lowercased()
        var pm: Bool? = nil
        if timePart.hasSuffix(" am") || timePart.hasSuffix("am") {
            pm = false; timePart = String(timePart.dropLast(timePart.hasSuffix(" am") ? 3 : 2))
        } else if timePart.hasSuffix(" pm") || timePart.hasSuffix("pm") {
            pm = true; timePart = String(timePart.dropLast(timePart.hasSuffix(" pm") ? 3 : 2))
        }
        let tp = timePart.split(separator: ":")
        if tp.count >= 2, tp.count <= 3, tp.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber } }),
           var h = Int(tp[0]), let m = Int(tp[1]), m < 60 {
            let sec = tp.count == 3 ? Int(tp[2]) ?? 0 : 0
            if let pm { guard h >= 1 && h <= 12 else { return nil }; h = h % 12 + (pm ? 12 : 0) }
            let v = (Double(h) * 3600 + Double(m) * 60 + Double(sec)) / 86400
            let f = pm != nil ? (tp.count == 3 ? "h:mm:ss AM/PM" : "h:mm AM/PM") : (tp.count == 3 ? "h:mm:ss" : "h:mm")
            return (v, f)
        }
        // m/d/yyyy or m/d.
        let slash = t.split(separator: "/")
        if slash.count == 2 || slash.count == 3, slash.allSatisfy({ $0.allSatisfy { $0.isNumber } && !$0.isEmpty }),
           let m = Int(slash[0]), let d = Int(slash[1]), (1 ... 12).contains(m), (1 ... 31).contains(d) {
            var y = slash.count == 3 ? Int(slash[2]) ?? 0 : _currentYear()
            if slash.count == 3 && slash[2].count <= 2 { y += y < 30 ? 2000 : 1900 }
            guard _valid(y, m, d) else { return nil }
            return (ExcelDate.serial(y, m, d), slash.count == 3 ? "m/d/yyyy" : "d-mmm")
        }
        // yyyy-mm-dd.
        let dash = t.split(separator: "-")
        if dash.count == 3, dash[0].count == 4, dash.allSatisfy({ $0.allSatisfy { $0.isNumber } && !$0.isEmpty }),
           let y = Int(dash[0]), let m = Int(dash[1]), let d = Int(dash[2]), _valid(y, m, d) {
            return (ExcelDate.serial(y, m, d), "yyyy-mm-dd")
        }
        // d-mmm-yyyy, d mmm yyyy.
        let words = t.split(whereSeparator: { $0 == "-" || $0 == " " })
        if words.count == 3, let d = Int(words[0]), let m = _month(String(words[1])), let y = Int(words[2]) {
            let yy = words[2].count <= 2 ? y + (y < 30 ? 2000 : 1900) : y
            if _valid(yy, m, d) { return (ExcelDate.serial(yy, m, d), "d-mmm-yy") }
        }
        return nil
    }

    private static func _valid(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        guard y >= 1900, y <= 9999, (1 ... 12).contains(m), d >= 1 else { return false }
        let days = [31, (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return d <= days[m - 1]
    }

    private static func _month(_ s: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let l = s.lowercased()
        guard l.count >= 3 else { return nil }
        return names.firstIndex { l.hasPrefix($0) }.map { $0 + 1 }
    }

    private static func _currentYear() -> Int { ExcelDate.ymd(ExcelDate.now()).0 }

    /// What typing `text` into a cell stores: a value and the format it
    /// implies, or nil for a formula (the caller parses it).
    static func parse(_ text: String) -> (value: CellValue, format: String?)? {
        if text.hasPrefix("=") && text.count > 1 { return nil }
        if text.isEmpty { return (.empty, nil) }
        if text.hasPrefix("'") { return (.text(String(text.dropFirst())), nil) }
        switch text.uppercased() {
        case "TRUE": return (.bool(true), nil)
        case "FALSE": return (.bool(false), nil)
        default: break
        }
        if let e = ExcelError(rawValue: text.uppercased()) { return (.error(e), nil) }
        if let n = number(text) { return (.number(n.value), n.format) }
        return (.text(text), nil)
    }
}
