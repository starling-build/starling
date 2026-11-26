import Foundation

/// W-TB-6: the formulas of Layout > Formula in a table cell: `=SUM(ABOVE)`, `=A1+B2`, `=PRODUCT(LEFT)`,
/// with Word's `\#` number picture. Pure: it sees the table as a grid of cell texts.
public struct TableFormula {
    /// `grid[row][column]` is the text of the cell at that grid position ("" when empty or covered by a merge).
    public var grid: [[String]]
    public var row: Int
    public var column: Int

    public init(grid: [[String]], row: Int, column: Int) {
        self.grid = grid; self.row = row; self.column = column
    }

    /// The number Word reads in a cell: `$1,200.50`, `-3`, `12%` (as 12), `(5)` is not one. Nil when there is none.
    public static func number(in text: String) -> Double? {
        var s = ""
        var started = false
        for ch in text {
            if ch.isASCII && ch.isNumber { s.append(ch); started = true }
            else if ch == "." && started && !s.contains("." as Character) { s.append(ch) }
            else if ch == "," && started { continue }
            else if ch == "-" && !started && s.isEmpty { s = "-" }
            else if started { break }
            else if s == "-" { s = "" }
        }
        guard started, let v = Double(s) else { return nil }
        return v
    }

    enum Failure: Error { case syntax, reference, divideByZero }

    /// The values of the cells ABOVE / LEFT / BELOW / RIGHT of the current cell: the run of cells that hold
    /// something, up to the first empty one (text with no number in it is passed over).
    func direction(_ name: String) -> [Double] {
        var r = row, c = column
        var out: [Double] = []
        let (dr, dc): (Int, Int)
        switch name {
        case "ABOVE": (dr, dc) = (-1, 0)
        case "BELOW": (dr, dc) = (1, 0)
        case "LEFT": (dr, dc) = (0, -1)
        default: (dr, dc) = (0, 1)
        }
        while true {
            r += dr; c += dc
            guard r >= 0, r < grid.count, c >= 0, c < grid[r].count else { break }
            let t = grid[r][c]
            if t.trimmingWhitespace(newlines: true).isEmpty { break }
            if let v = Self.number(in: t) { out.append(v) }
        }
        return out
    }

    /// "A1" is column A, row 1.
    static func reference(_ s: String) -> (row: Int, column: Int)? {
        let u = Array(s.uppercased())
        var i = 0
        var col = 0
        while i < u.count, u[i].isLetter, u[i].isASCII { col = col * 26 + Int(u[i].asciiValue! - 64); i += 1 }
        guard i > 0, i < u.count, let row = Int(String(u[i...])), row >= 1 else { return nil }
        return (row - 1, col - 1)
    }

    func cellValue(_ r: Int, _ c: Int) -> Double? {
        guard r >= 0, r < grid.count, c >= 0, c < grid[r].count else { return nil }
        return Self.number(in: grid[r][c])
    }

    // MARK: parsing

    private struct Parser {
        let f: TableFormula
        let chars: [Character]
        var i = 0
        init(_ f: TableFormula, _ s: String) { self.f = f; chars = Array(s) }

        mutating func skip() { while i < chars.count, chars[i] == " " { i += 1 } }
        mutating func peek() -> Character? { skip(); return i < chars.count ? chars[i] : nil }

        mutating func expression() throws -> Double {
            var v = try term()
            while let c = peek(), c == "+" || c == "-" {
                i += 1
                let r = try term()
                v = c == "+" ? v + r : v - r
            }
            return v
        }
        mutating func term() throws -> Double {
            var v = try unary()
            while let c = peek(), c == "*" || c == "/" {
                i += 1
                let r = try unary()
                if c == "/" { if r == 0 { throw Failure.divideByZero }; v /= r } else { v *= r }
            }
            return v
        }
        mutating func unary() throws -> Double {
            if let c = peek(), c == "-" { i += 1; return -(try unary()) }
            if let c = peek(), c == "+" { i += 1; return try unary() }
            return try primary()
        }
        mutating func primary() throws -> Double {
            guard let c = peek() else { throw Failure.syntax }
            if c == "(" {
                i += 1
                let v = try expression()
                guard peek() == ")" else { throw Failure.syntax }
                i += 1
                return v
            }
            if c.isNumber || c == "." {
                var s = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." { s.append(chars[i]); i += 1 }
                guard let v = Double(s) else { throw Failure.syntax }
                return v
            }
            if c.isLetter {
                var name = ""
                while i < chars.count, chars[i].isLetter || chars[i].isNumber { name.append(chars[i]); i += 1 }
                if peek() == "(" {
                    i += 1
                    var values: [Double] = []
                    while true {
                        guard peek() != nil else { throw Failure.syntax }
                        values += try argument()
                        guard let d = peek() else { throw Failure.syntax }
                        i += 1
                        if d == ")" { break }
                        if d != "," && d != ";" { throw Failure.syntax }
                    }
                    return try apply(name.uppercased(), values)
                }
                let u = name.uppercased()
                if let ref = TableFormula.reference(u) {
                    guard let v = f.cellValue(ref.row, ref.column) else { throw Failure.reference }
                    return v
                }
                throw Failure.syntax
            }
            throw Failure.syntax
        }
        /// One argument of a function: ABOVE, A1:B3, A1, or an expression.
        mutating func argument() throws -> [Double] {
            skip()
            let save = i
            var word = ""
            while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == ":" { word.append(chars[i]); i += 1 }
            let u = word.uppercased()
            if ["ABOVE", "BELOW", "LEFT", "RIGHT"].contains(u) { return f.direction(u) }
            if u.contains(":" as Character) {
                let ends = u.split(separator: ":").map(String.init)
                guard ends.count == 2, let a = TableFormula.reference(ends[0]), let b = TableFormula.reference(ends[1]) else { throw Failure.reference }
                var out: [Double] = []
                for r in min(a.row, b.row) ... max(a.row, b.row) {
                    for c in min(a.column, b.column) ... max(a.column, b.column) { if let v = f.cellValue(r, c) { out.append(v) } }
                }
                return out
            }
            i = save
            return [try expression()]
        }
        func apply(_ name: String, _ v: [Double]) throws -> Double {
            switch name {
            case "SUM": return v.reduce(0, +)
            case "PRODUCT": return v.isEmpty ? 0 : v.reduce(1, *)
            case "COUNT": return Double(v.count)
            case "AVERAGE": if v.isEmpty { throw Failure.divideByZero }; return v.reduce(0, +) / Double(v.count)
            case "MAX": guard let m = v.max() else { throw Failure.reference }; return m
            case "MIN": guard let m = v.min() else { throw Failure.reference }; return m
            case "ABS": guard v.count == 1 else { throw Failure.syntax }; return abs(v[0])
            default: throw Failure.syntax
            }
        }
    }

    /// The value of `=SUM(ABOVE)` (with or without the leading `=`), or nil when it cannot be worked out.
    public func evaluate(_ formula: String) -> Double? {
        var s = formula.trimmingWhitespace(newlines: true)
        if s.hasPrefix("=") { s.removeFirst() }
        var p = Parser(self, s)
        guard let v = try? p.expression(), p.peek() == nil, v.isFinite else { return nil }
        return v
    }

    // MARK: number picture

    /// `value` with exactly `decimals` digits after the point (no String(format:): the web build has none).
    static func fixed(_ value: Double, _ decimals: Int) -> String {
        var scale = 1.0
        for _ in 0 ..< decimals { scale *= 10 }
        let n = Int64((abs(value) * scale).rounded(.toNearestOrAwayFromZero))
        var digits = String(n)
        while digits.count <= decimals { digits = "0" + digits }
        let cut = digits.index(digits.endIndex, offsetBy: -decimals)
        let out = decimals == 0 ? digits : String(digits[..<cut]) + "." + String(digits[cut...])
        return (value < 0 && n != 0 ? "-" : "") + out
    }

    /// Word's `\\#` picture applied to `value`: "0.00", "#,##0", "$#,##0.00;($#,##0.00)", "0%". An empty picture
    /// gives the general form (a whole number without decimals, otherwise up to ten digits).
    public static func format(_ value: Double, picture: String) -> String {
        let pic = picture.trimmingWhitespace(newlines: true)
        if pic.isEmpty {
            if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
            var s = fixed(value, 10)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s
        }
        let sections = pic.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        var chosen = sections[0]
        var v = value
        if value < 0, sections.count > 1 { chosen = sections[1]; v = -value }
        else if value == 0, sections.count > 2 { chosen = sections[2] }
        let chars = Array(chosen)
        guard let first = chars.firstIndex(where: { $0 == "0" || $0 == "#" }),
              let last = chars.lastIndex(where: { $0 == "0" || $0 == "#" }) else { return chosen }
        let prefix = String(chars[..<first].filter { $0 != "'" })
        let suffix = String(chars[(last + 1)...].filter { $0 != "'" })
        let body = String(chars[first ... last])
        let percent = suffix.contains("%" as Character) || prefix.contains("%" as Character)
        if percent { v *= 100 }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let decimals = parts.count > 1 ? parts[1].count : 0
        let grouped = parts[0].contains("," as Character)
        let minInt = parts[0].filter { $0 == "0" }.count
        var text = fixed(abs(v), decimals)
        var intPart = text, frac = ""
        if let dot = text.firstIndex(of: ".") { intPart = String(text[..<dot]); frac = String(text[text.index(after: dot)...]) }
        if parts.count > 1 {
            // "#" decimals are dropped when zero at the end.
            var keep = frac.count
            let required = parts[1].filter { $0 == "0" }.count
            while keep > required, frac.hasSuffix("0") { frac.removeLast(); keep -= 1 }
        }
        while intPart.count < minInt { intPart = "0" + intPart }
        if minInt == 0, intPart == "0" { intPart = "" }
        if grouped {
            var out = "", n = 0
            for ch in intPart.reversed() { if n > 0, n % 3 == 0 { out.append(",") }; out.append(ch); n += 1 }
            intPart = String(out.reversed())
        }
        text = intPart + (frac.isEmpty ? "" : "." + frac)
        let negative = value < 0 && sections.count < 2 && Double(fixed(abs(v), decimals)) != 0
        return (negative ? "-" : "") + prefix + text + suffix
    }
}
