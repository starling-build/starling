// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Excel's formula language: a tokenizer, a recursive-descent parser to an
// AST, and a printer that turns the AST back into the text Excel shows.
// Parentheses are kept as nodes, so printing is exact; the printer is
// how references are rewritten when rows and columns move.
//
// Precedence, lowest first (Excel's, not mathematics'): comparisons,
// `&`, `+ -`, `* /`, `^`, unary `-`/`+` (so -2^2 is 4), postfix `%`,
// then `:` between references.

/// One end of a reference. Either half may be missing in a whole-column
/// (`A:A`) or whole-row (`3:3`) range.
struct RefEnd: Hashable, Sendable {
    var row: Int?
    var col: Int?
    var rowAbs: Bool
    var colAbs: Bool

    var text: String {
        var s = ""
        if let col { s += (colAbs ? "$" : "") + CellAddress.columnName(col) }
        if let row { s += (rowAbs ? "$" : "") + String(row + 1) }
        return s
    }
}

struct FormulaRef: Hashable, Sendable {
    var sheet: String?
    var start: RefEnd
    var end: RefEnd?          // nil for a single cell

    var isCell: Bool { end == nil && start.row != nil && start.col != nil }

    /// The cells it covers on its sheet.
    var range: CellRange {
        let e = end ?? start
        let top = min(start.row ?? 0, e.row ?? 0)
        let bottom = (start.row == nil || e.row == nil) ? CellAddress.maxRows - 1 : max(start.row!, e.row!)
        let left = min(start.col ?? 0, e.col ?? 0)
        let right = (start.col == nil || e.col == nil) ? CellAddress.maxCols - 1 : max(start.col!, e.col!)
        return CellRange(top: start.row == nil ? 0 : top, left: start.col == nil ? 0 : left,
                         bottom: bottom, right: right)
    }

    var text: String {
        var s = ""
        if let sheet { s = Formula.quoteSheet(sheet) + "!" }
        s += start.text
        if let end { s += ":" + end.text }
        return s
    }
}

enum BinaryOp: String, Sendable {
    case add = "+", sub = "-", mul = "*", div = "/", pow = "^", concat = "&"
    case eq = "=", ne = "<>", lt = "<", gt = ">", le = "<=", ge = ">="
    /// The intersection operator, a space between two references.
    case intersect = " "

    var precedence: Int {
        switch self {
        case .eq, .ne, .lt, .gt, .le, .ge: return 1
        case .concat: return 2
        case .add, .sub: return 3
        case .mul, .div: return 4
        case .pow: return 5
        case .intersect: return 6
        }
    }
}

indirect enum FormulaExpr: Hashable, Sendable {
    case number(Double, String)   // value and the text it was written as
    case text(String)
    case bool(Bool)
    case error(ExcelError)
    case ref(FormulaRef)
    case name(String)
    /// A table's structured reference, as written: `Table1[Amount]`,
    /// `[@Qty]`, `Table1[[#Totals],[Price]:[Tax]]`. It names cells by the
    /// table's columns, so rows moving never change its text; it is
    /// resolved against the tables when evaluated.
    case structured(String)
    /// A spill reference, A1#: the range the formula in A1 spilled over.
    case spill(FormulaRef)
    /// An array constant: {1,2;3,4} — rows of columns.
    case array([[FormulaExpr]])
    case negate(FormulaExpr)
    case plus(FormulaExpr)
    case percent(FormulaExpr)
    case binary(BinaryOp, FormulaExpr, FormulaExpr)
    case call(String, [FormulaExpr])
    case missing                  // an empty argument: IF(A1,,2)
    case paren(FormulaExpr)
}

struct FormulaError: Error, Equatable {
    let message: String
}

enum Formula {
    /// Parse the text after "=" (or with it).
    static func parse(_ text: String) throws -> FormulaExpr {
        var src = Substring(text)
        if src.hasPrefix("=") { src = src.dropFirst() }
        var p = _Parser(tokens: try _tokenize(src))
        let e = try p.expression(0)
        guard p.atEnd else { throw FormulaError(message: "unexpected \(p.peekText)") }
        return e
    }

    /// The formula as Excel writes it, with the leading "=".
    static func text(_ e: FormulaExpr) -> String { "=" + print(e) }

    static func print(_ e: FormulaExpr) -> String {
        switch e {
        case .number(_, let t): return t
        case .text(let s): return "\"" + s.replacingAll("\"", with: "\"\"") + "\""
        case .bool(let b): return b ? "TRUE" : "FALSE"
        case .error(let err): return err.rawValue
        case .ref(let r): return r.text
        case .name(let n): return n
        case .structured(let s): return s
        case .spill(let r): return print(.ref(r)) + "#"
        case .array(let rows): return "{" + rows.map { $0.map(print).joined(separator: ",") }.joined(separator: ";") + "}"
        case .negate(let x): return "-" + print(x)
        case .plus(let x): return "+" + print(x)
        case .percent(let x): return print(x) + "%"
        case .binary(let op, let a, let b): return print(a) + op.rawValue + print(b)
        case .call(let f, let args):
            if unprefixed(f).uppercased() == "SINGLE", args.count == 1 { return "@" + print(args[0]) }
            return f + "(" + args.map(print).joined(separator: ",") + ")"
        case .missing: return ""
        case .paren(let x): return "(" + print(x) + ")"
        }
    }

    static func quoteSheet(_ name: String) -> String {
        let plain = !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            && !(name.first?.isNumber ?? false) && CellRefText.parse(Substring(name)).map { !$0.rest.isEmpty } != false
        return plain ? name : "'" + name.replacingAll("'", with: "''") + "'"
    }

    /// Whether a function the engine does not have appears in it.
    static func usesUnknownFunction(_ e: FormulaExpr) -> Bool {
        switch e {
        case .call(let n, let args):
            if SheetFunctions.table[n] == nil && SheetFunctions.table[unprefixed(n)] == nil { return true }
            return args.contains(where: usesUnknownFunction)
        case .negate(let x), .plus(let x), .percent(let x), .paren(let x): return usesUnknownFunction(x)
        case .binary(_, let a, let b): return usesUnknownFunction(a) || usesUnknownFunction(b)
        default: return false
        }
    }

    /// _xlfn.XLOOKUP → XLOOKUP: functions newer than Excel 2007 carry a
    /// prefix in files, and none in the formula bar.
    static func unprefixed(_ n: String) -> String {
        let u = n.uppercased()
        for p in ["_XLFN._XLWS.", "_XLFN.", "_XLWS."] where u.hasPrefix(p) { return String(n.dropFirst(p.count)) }
        return n
    }

    /// Whether it reaches into another workbook: a sheet written as
    /// [Book1.xlsx]Sheet1 or [1]Sheet1 (the file's externalLink parts).
    static func referencesExternal(_ e: FormulaExpr) -> Bool {
        var refs: [FormulaRef] = []
        references(e, into: &refs)
        return refs.contains { ($0.sheet ?? "").hasPrefix("[") }
    }

    /// Reads something its references do not show: the clock, chance,
    /// a reference built at run time, a table — recomputed every time.
    static func isVolatile(_ e: FormulaExpr) -> Bool {
        switch e {
        case .structured: return true
        case .call(let n, let args):
            let u = unprefixed(n).uppercased()
            if ["NOW", "TODAY", "RAND", "RANDBETWEEN", "RANDARRAY", "OFFSET", "INDIRECT", "CELL", "INFO"].contains(u) { return true }
            return args.contains(where: isVolatile)
        case .negate(let x), .plus(let x), .percent(let x), .paren(let x): return isVolatile(x)
        case .binary(_, let a, let b): return isVolatile(a) || isVolatile(b)
        case .array(let rows): return rows.contains { $0.contains(where: isVolatile) }
        default: return false
        }
    }

    /// Every defined name the formula reads.
    static func names(_ e: FormulaExpr, into out: inout [String]) {
        switch e {
        case .name(let n): out.append(n)
        case .negate(let x), .plus(let x), .percent(let x), .paren(let x): names(x, into: &out)
        case .binary(_, let a, let b): names(a, into: &out); names(b, into: &out)
        case .call(let f, let args):
            // A call may be a defined name holding a LAMBDA; a built-in's
            // name simply matches no defined name.
            out.append(f)
            for a in args { names(a, into: &out) }
        default: break
        }
    }

    /// Every reference the formula reads, for the dependency graph.
    static func references(_ e: FormulaExpr, into out: inout [FormulaRef]) {
        switch e {
        case .ref(let r), .spill(let r): out.append(r)
        case .negate(let x), .plus(let x), .percent(let x), .paren(let x): references(x, into: &out)
        case .binary(_, let a, let b): references(a, into: &out); references(b, into: &out)
        case .call(_, let args): for a in args { references(a, into: &out) }
        default: break
        }
    }

    /// The formula with every reference passed through `f` — for moving,
    /// copying and inserting. `f` returns nil for a reference that no
    /// longer exists (it becomes #REF!).
    /// Every structured reference's text through `f`.
    static func mapStructured(_ e: FormulaExpr, _ f: (String) -> String) -> FormulaExpr {
        switch e {
        case .structured(let t): return .structured(f(t))
        case .negate(let x): return .negate(mapStructured(x, f))
        case .plus(let x): return .plus(mapStructured(x, f))
        case .percent(let x): return .percent(mapStructured(x, f))
        case .paren(let x): return .paren(mapStructured(x, f))
        case .binary(let op, let a, let b): return .binary(op, mapStructured(a, f), mapStructured(b, f))
        case .call(let n, let args): return .call(n, args.map { mapStructured($0, f) })
        default: return e
        }
    }

    static func mapRefs(_ e: FormulaExpr, _ f: (FormulaRef) -> FormulaRef?) -> FormulaExpr {
        switch e {
        case .ref(let r): return f(r).map { .ref($0) } ?? .error(.ref)
        case .spill(let r): return f(r).map { .spill($0) } ?? .error(.ref)
        case .negate(let x): return .negate(mapRefs(x, f))
        case .plus(let x): return .plus(mapRefs(x, f))
        case .percent(let x): return .percent(mapRefs(x, f))
        case .paren(let x): return .paren(mapRefs(x, f))
        case .binary(let op, let a, let b): return .binary(op, mapRefs(a, f), mapRefs(b, f))
        case .call(let n, let args): return .call(n, args.map { mapRefs($0, f) })
        default: return e
        }
    }

    /// The formula as it reads after moving or copying its cell by
    /// (rows, cols): relative references move with it, absolute ones stay,
    /// and a reference pushed off the sheet becomes #REF!.
    static func shifted(_ e: FormulaExpr, rows dr: Int, cols dc: Int) -> FormulaExpr {
        func end(_ x: RefEnd) -> RefEnd? {
            var x = x
            if let r = x.row, !x.rowAbs {
                let n = r + dr
                guard n >= 0, n < CellAddress.maxRows else { return nil }
                x.row = n
            }
            if let c = x.col, !x.colAbs {
                let n = c + dc
                guard n >= 0, n < CellAddress.maxCols else { return nil }
                x.col = n
            }
            return x
        }
        return mapRefs(e) { r in
            guard let s = end(r.start) else { return nil }
            var out = r
            out.start = s
            if let e = r.end {
                guard let e2 = end(e) else { return nil }
                out.end = e2
            }
            return out
        }
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double, String)
        case text(String)
        case bool(Bool)
        case error(ExcelError)
        case ref(FormulaRef)
        case function(String)      // name, the "(" consumed
        case name(String)
        case structured(String)    // Table1[…] or […], brackets balanced
        case spill(FormulaRef)     // A1#
        case lbrace, rbrace, rowSep  // an array constant's { } and its ";"
        case op(String)            // + - * / ^ & = <> < > <= >= % :
        case lparen, rparen, comma
    }

    static func _tokenize(_ s: Substring) throws -> [Token] {
        var out: [Token] = []
        var braces = 0
        var i = s.startIndex
        func peek(_ k: Int = 0) -> Character? {
            var j = i
            for _ in 0 ..< k { guard j < s.endIndex else { return nil }; j = s.index(after: j) }
            return j < s.endIndex ? s[j] : nil
        }
        while i < s.endIndex {
            let c = s[i]
            if c == " " || c == "\n" || c == "\t" {
                // A space between two references is the intersection
                // operator (A1:B5 B2:C9); any other space is nothing.
                var j = i
                while j < s.endIndex, s[j] == " " || s[j] == "\n" || s[j] == "\t" { j = s.index(after: j) }
                if c == " ", let last = out.last, let n = j < s.endIndex ? s[j] : nil {
                    let operandBefore: Bool
                    switch last {
                    case .ref, .rparen, .structured, .spill: operandBefore = true
                    case .name: operandBefore = n != "("
                    default: operandBefore = false
                    }
                    if operandBefore, n.isLetter || n == "$" || n == "'" || n == "(" || n == "_" || n == "[" {
                        out.append(.op(" "))
                    }
                }
                i = j
                continue
            }
            // Strings.
            if c == "\"" {
                var t = ""
                i = s.index(after: i)
                while true {
                    guard i < s.endIndex else { throw FormulaError(message: "unterminated string") }
                    if s[i] == "\"" {
                        let n = s.index(after: i)
                        if n < s.endIndex, s[n] == "\"" { t.append("\""); i = s.index(after: n); continue }
                        i = n
                        break
                    }
                    t.append(s[i]); i = s.index(after: i)
                }
                out.append(.text(t)); continue
            }
            // Errors.
            if c == "#" {
                let rest = s[i...].uppercased()
                if let e = ExcelError.allCases.first(where: { rest.hasPrefix($0.rawValue) }) {
                    out.append(.error(e)); i = s.index(i, offsetBy: e.rawValue.count); continue
                }
                throw FormulaError(message: "bad error literal")
            }
            // Numbers (a leading "." too).
            if c.isNumber || (c == "." && (peek(1)?.isNumber ?? false)) {
                // A row range like 3:5 is a reference, not a number.
                if let r = _rowRange(s[i...]) { out.append(.ref(r.ref)); i = r.end; continue }
                let start = i
                while i < s.endIndex, s[i].isNumber || s[i] == "." { i = s.index(after: i) }
                if i < s.endIndex, s[i] == "e" || s[i] == "E" {
                    var j = s.index(after: i)
                    if j < s.endIndex, s[j] == "+" || s[j] == "-" { j = s.index(after: j) }
                    if j < s.endIndex, s[j].isNumber {
                        i = j
                        while i < s.endIndex, s[i].isNumber { i = s.index(after: i) }
                    }
                }
                let t = String(s[start ..< i])
                guard let v = Double(t) else { throw FormulaError(message: "bad number \(t)") }
                out.append(.number(v, t)); continue
            }
            // References, names, functions, booleans — with an optional sheet prefix.
            if c == "'" || c == "$" || c.isLetter || c == "_" {
                var j = i
                var sheet: String? = nil
                if c == "'" {
                    var name = ""
                    j = s.index(after: j)
                    while true {
                        guard j < s.endIndex else { throw FormulaError(message: "unterminated sheet name") }
                        if s[j] == "'" {
                            let n = s.index(after: j)
                            if n < s.endIndex, s[n] == "'" { name.append("'"); j = s.index(after: n); continue }
                            j = n; break
                        }
                        name.append(s[j]); j = s.index(after: j)
                    }
                    guard j < s.endIndex, s[j] == "!" else { throw FormulaError(message: "expected ! after sheet name") }
                    sheet = name
                    j = s.index(after: j)
                } else {
                    // An identifier; if a "!" follows, it was a sheet name.
                    var k = j
                    while k < s.endIndex, s[k].isLetter || s[k].isNumber || s[k] == "_" || s[k] == "." || s[k] == "$" {
                        k = s.index(after: k)
                    }
                    if k < s.endIndex, s[k] == "!" {
                        sheet = String(s[j ..< k]); j = s.index(after: k)
                    }
                }
                // A table name and its brackets: a structured reference
                // (before trying a cell reference: "Tab1" reads as a cell).
                if sheet == nil {
                    var k = j
                    while k < s.endIndex, s[k].isLetter || s[k].isNumber || s[k] == "_" || s[k] == "." || s[k] == "\\" { k = s.index(after: k) }
                    if k > j, k < s.endIndex, s[k] == "[" {
                        let end = try _bracketEnd(s, from: k)
                        out.append(.structured(String(s[j ..< end]))); i = end; continue
                    }
                }
                // After a sheet prefix only a reference may follow.
                if let r = _reference(s[j...], sheet: sheet) {
                    // A1#: the spill of the formula in A1.
                    if r.ref.isCell, r.end < s.endIndex, s[r.end] == "#" {
                        out.append(.spill(r.ref)); i = s.index(after: r.end); continue
                    }
                    out.append(.ref(r.ref)); i = r.end; continue
                }
                if sheet != nil { throw FormulaError(message: "bad reference after \(sheet!)!") }
                var k = j
                while k < s.endIndex, s[k].isLetter || s[k].isNumber || s[k] == "_" || s[k] == "." { k = s.index(after: k) }
                let word = String(s[j ..< k])
                guard !word.isEmpty else { throw FormulaError(message: "unexpected \(c)") }
                if k < s.endIndex, s[k] == "(" {
                    out.append(.function(word.uppercased())); i = s.index(after: k); continue
                }
                switch word.uppercased() {
                case "TRUE": out.append(.bool(true))
                case "FALSE": out.append(.bool(false))
                default: out.append(.name(word))
                }
                i = k; continue
            }
            // A structured reference inside its own table: [@Qty], [Price].
            if c == "[" {
                let end = try _bracketEnd(s, from: i)
                out.append(.structured(String(s[i ..< end]))); i = end; continue
            }
            switch c {
            case "(": out.append(.lparen)
            case ")": out.append(.rparen)
            case "{": braces += 1; out.append(.lbrace)
            case "}": braces -= 1; out.append(.rbrace)
            case ";" where braces > 0: out.append(.rowSep)
            case ",", ";": out.append(.comma)
            case "<":
                if peek(1) == "=" { out.append(.op("<=")); i = s.index(after: i) }
                else if peek(1) == ">" { out.append(.op("<>")); i = s.index(after: i) }
                else { out.append(.op("<")) }
            case ">":
                if peek(1) == "=" { out.append(.op(">=")); i = s.index(after: i) } else { out.append(.op(">")) }
            case "+", "-", "*", "/", "^", "&", "=", "%", ":", "@": out.append(.op(String(c)))
            default: throw FormulaError(message: "unexpected \(c)")
            }
            i = s.index(after: i)
        }
        return out
    }

    /// Just past the "]" matching the "[" at `from`; inside, "'" escapes
    /// the next character (a bracket, "#", "'" in a column name).
    static func _bracketEnd(_ s: Substring, from: Substring.Index) throws -> Substring.Index {
        var depth = 0
        var j = from
        while j < s.endIndex {
            let ch = s[j]
            if ch == "'" { j = s.index(after: j); if j < s.endIndex { j = s.index(after: j) }; continue }
            if ch == "[" { depth += 1 }
            if ch == "]" { depth -= 1; if depth == 0 { return s.index(after: j) } }
            j = s.index(after: j)
        }
        throw FormulaError(message: "unclosed [")
    }

    /// A cell or range reference at the start of `s`: A1, $A$1, A1:B2,
    /// A:C (whole columns). A bare word like "SUM" is not one unless a
    /// column range follows, and nothing counts if a letter, digit or "("
    /// would continue it (that is a name or a function).
    private static func _reference(_ s: Substring, sheet: String?) -> (ref: FormulaRef, end: Substring.Index)? {
        guard let a = CellRefText.parse(s) else {
            return _rowRange(s, sheet: sheet)
        }
        func continuesWord(_ rest: Substring) -> Bool {
            guard let f = rest.first else { return false }
            return f.isLetter || f.isNumber || f == "_" || f == "(" || f == "."
        }
        let startEnd = RefEnd(row: a.row, col: a.col, rowAbs: a.rowAbs, colAbs: a.colAbs)
        if a.rest.first == ":" {
            let after = a.rest.dropFirst()
            if let b = CellRefText.parse(after), !continuesWord(b.rest),
               (a.row == nil) == (b.row == nil), (a.col == nil) == (b.col == nil) {
                let endEnd = RefEnd(row: b.row, col: b.col, rowAbs: b.rowAbs, colAbs: b.colAbs)
                return (FormulaRef(sheet: sheet, start: startEnd, end: endEnd), b.rest.startIndex)
            }
        }
        // A single cell needs both halves; letters alone are a name.
        guard a.row != nil, a.col != nil, !continuesWord(a.rest) else { return nil }
        return (FormulaRef(sheet: sheet, start: startEnd, end: nil), a.rest.startIndex)
    }

    /// 3:5 or $3:$5 — whole rows.
    private static func _rowRange(_ s: Substring, sheet: String? = nil) -> (ref: FormulaRef, end: Substring.Index)? {
        guard let a = CellRefText.parse(s), a.col == nil, a.row != nil, a.rest.first == ":",
              let b = CellRefText.parse(a.rest.dropFirst()), b.col == nil, b.row != nil else { return nil }
        if let f = b.rest.first, f.isLetter || f.isNumber || f == "." { return nil }
        return (FormulaRef(sheet: sheet, start: RefEnd(row: a.row, col: nil, rowAbs: a.rowAbs, colAbs: false),
                           end: RefEnd(row: b.row, col: nil, rowAbs: b.rowAbs, colAbs: false)), b.rest.startIndex)
    }

    // MARK: Parser

    struct _Parser {
        let tokens: [Token]
        var i = 0

        var atEnd: Bool { i >= tokens.count }
        var peekText: String { atEnd ? "end" : "\(tokens[i])" }

        mutating func next() -> Token? {
            guard i < tokens.count else { return nil }
            defer { i += 1 }
            return tokens[i]
        }

        func peek() -> Token? { i < tokens.count ? tokens[i] : nil }

        mutating func expression(_ minPrec: Int) throws -> FormulaExpr {
            var lhs = try unary()
            while case .op(let o)? = peek(), let op = BinaryOp(rawValue: o), op.precedence >= minPrec {
                _ = next()
                // ^ is left-associative in Excel too (2^3^2 = 64).
                let rhs = try expression(op.precedence + 1)
                lhs = .binary(op, lhs, rhs)
            }
            return lhs
        }

        mutating func unary() throws -> FormulaExpr {
            if case .op("-")? = peek() { _ = next(); return .negate(try unary()) }
            // @x: Excel's implicit intersection (in files, _xlfn.SINGLE(x)).
            if case .op("@")? = peek() { _ = next(); return .call("SINGLE", [try unary()]) }
            if case .op("+")? = peek() { _ = next(); return .plus(try unary()) }
            return try postfix()
        }

        mutating func postfix() throws -> FormulaExpr {
            var e = try primary()
            while case .op("%")? = peek() { _ = next(); e = .percent(e) }
            return e
        }

        mutating func primary() throws -> FormulaExpr {
            guard let t = next() else { throw FormulaError(message: "formula ends early") }
            switch t {
            case .number(let v, let s): return .number(v, s)
            case .text(let s): return .text(s)
            case .bool(let b): return .bool(b)
            case .error(let e): return .error(e)
            case .ref(let r): return .ref(r)
            case .name(let n): return .name(n)
            case .structured(let t): return .structured(t)
            case .spill(let r): return .spill(r)
            case .lbrace:
                // {a,b;c,d}: constants, columns by comma, rows by semicolon.
                var rows: [[FormulaExpr]] = [[]]
                while true {
                    rows[rows.count - 1].append(try expression(0))
                    guard let sep = next() else { throw FormulaError(message: "missing }") }
                    if case .rbrace = sep { break }
                    if case .rowSep = sep { rows.append([]); continue }
                    guard case .comma = sep else { throw FormulaError(message: "expected , in {}") }
                }
                guard Set(rows.map(\.count)).count == 1 else { throw FormulaError(message: "uneven array") }
                return .array(rows)
            case .lparen:
                let e = try expression(0)
                guard case .rparen? = next() else { throw FormulaError(message: "missing )") }
                return .paren(e)
            case .function(let f):
                var args: [FormulaExpr] = []
                if case .rparen? = peek() { _ = next(); return .call(f, []) }
                while true {
                    if case .comma? = peek() { args.append(.missing) }
                    else if case .rparen? = peek() { args.append(.missing) }
                    else { args.append(try expression(0)) }
                    guard let sep = next() else { throw FormulaError(message: "missing ) after \(f)") }
                    if case .rparen = sep { break }
                    guard case .comma = sep else { throw FormulaError(message: "expected , in \(f)") }
                }
                return .call(f, args)
            default:
                throw FormulaError(message: "unexpected \(t)")
            }
        }
    }
}
