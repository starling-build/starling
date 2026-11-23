// The formula tokenizer on UTF-8 bytes. A formula is nearly always plain
// ASCII, and reading it as Characters (grapheme breaking on every step) was
// the biggest part of opening a workbook with a formula in every row. This
// reads the same tokens, and only for text that is all ASCII with no CR:
// anything else goes to the Character reading (`_tokenizeCharacters`).

extension Formula {
    static func _tokenize(_ s: Substring) throws -> [Token] {
        let b = Array(s.utf8)
        for x in b where x >= 0x80 || x == 0x0D { return try _tokenizeCharacters(s) }
        return try _tokenizeBytes(b)
    }

    @inline(__always) private static func isLetter(_ a: UInt8) -> Bool { (a >= 65 && a <= 90) || (a >= 97 && a <= 122) }
    @inline(__always) private static func isDigit(_ a: UInt8) -> Bool { a >= 48 && a <= 57 }
    @inline(__always) private static func isSpace(_ a: UInt8) -> Bool { a == 0x20 || a == 0x0A || a == 0x09 }
    @inline(__always) private static func str(_ b: [UInt8], _ x: Int, _ y: Int) -> String {
        String(decoding: b[x ..< y], as: UTF8.self)
    }

    private static let errorTable: [(ExcelError, [UInt8])] = ExcelError.allCases.map { ($0, Array($0.rawValue.utf8)) }

    /// A cell or row reference at `at`: the same reading as `CellRefText.parse`, on bytes.
    private struct BRef { var row: Int?; var col: Int?; var rowAbs: Bool; var colAbs: Bool; var end: Int }

    private static func refAt(_ b: [UInt8], _ at: Int) -> BRef? {
        var i = at
        let end = b.count
        var colAbs = false, rowAbs = false
        if i < end, b[i] == 0x24 { colAbs = true; i += 1 }
        var n = 0, letterCount = 0
        while i < end {
            let a = b[i]
            let up = a >= 97 ? a &- 32 : a
            guard up >= 65 && up <= 90 else { break }
            letterCount += 1
            if letterCount <= 3 { n = n * 26 + Int(up - 64) }
            i += 1
        }
        var col: Int? = nil
        if letterCount > 0 {
            guard letterCount <= 3, n - 1 < CellAddress.maxCols else { return nil }
            col = n - 1
        } else if colAbs {
            colAbs = false
            rowAbs = true
        }
        if i < end, b[i] == 0x24 {
            guard !rowAbs else { return nil }
            rowAbs = true
            i += 1
        }
        var digitCount = 0, r = 0
        while i < end, isDigit(b[i]) {
            digitCount += 1
            if digitCount <= 7 { r = r * 10 + Int(b[i] - 48) }
            i += 1
        }
        var row: Int? = nil
        if digitCount > 0 {
            guard digitCount <= 7, r >= 1, r <= CellAddress.maxRows else { return nil }
            row = r - 1
        } else if rowAbs && col != nil && letterCount > 0 {
            return nil
        }
        if row == nil && col == nil { return nil }
        return BRef(row: row, col: col, rowAbs: rowAbs, colAbs: colAbs, end: i)
    }

    private static func rowRangeAt(_ b: [UInt8], _ at: Int, sheet: String?) -> (ref: FormulaRef, end: Int)? {
        guard let a = refAt(b, at), a.col == nil, a.row != nil, a.end < b.count, b[a.end] == 0x3A,
              let c = refAt(b, a.end + 1), c.col == nil, c.row != nil else { return nil }
        if c.end < b.count, isLetter(b[c.end]) || isDigit(b[c.end]) || b[c.end] == 0x2E { return nil }
        return (FormulaRef(sheet: sheet, start: RefEnd(row: a.row, col: nil, rowAbs: a.rowAbs, colAbs: false),
                           end: RefEnd(row: c.row, col: nil, rowAbs: c.rowAbs, colAbs: false)), c.end)
    }

    private static func referenceAt(_ b: [UInt8], _ at: Int, sheet: String?) -> (ref: FormulaRef, end: Int)? {
        guard let a = refAt(b, at) else { return rowRangeAt(b, at, sheet: sheet) }
        func continuesWord(_ i: Int) -> Bool {
            guard i < b.count else { return false }
            let f = b[i]
            return isLetter(f) || isDigit(f) || f == 0x5F || f == 0x28 || f == 0x2E
        }
        let startEnd = RefEnd(row: a.row, col: a.col, rowAbs: a.rowAbs, colAbs: a.colAbs)
        if a.end < b.count, b[a.end] == 0x3A, let c = refAt(b, a.end + 1), !continuesWord(c.end),
           (a.row == nil) == (c.row == nil), (a.col == nil) == (c.col == nil) {
            let endEnd = RefEnd(row: c.row, col: c.col, rowAbs: c.rowAbs, colAbs: c.colAbs)
            return (FormulaRef(sheet: sheet, start: startEnd, end: endEnd), c.end)
        }
        guard a.row != nil, a.col != nil, !continuesWord(a.end) else { return nil }
        return (FormulaRef(sheet: sheet, start: startEnd, end: nil), a.end)
    }

    private static func bracketEnd(_ b: [UInt8], from: Int) throws -> Int {
        var depth = 0
        var j = from
        while j < b.count {
            let ch = b[j]
            if ch == 0x27 { j += 1; if j < b.count { j += 1 }; continue }
            if ch == 0x5B { depth += 1 }
            if ch == 0x5D { depth -= 1; if depth == 0 { return j + 1 } }
            j += 1
        }
        throw FormulaError(message: "unclosed [")
    }

    /// "[" digits "]" at `k`: the index just past it, if it is one.
    private static func externalBook(_ b: [UInt8], _ k: Int) -> Int? {
        guard k < b.count, b[k] == 0x5B else { return nil }
        var j = k + 1
        guard let close = b[j...].firstIndex(of: 0x5D), close > j else { return nil }
        while j < close { guard isDigit(b[j]) else { return nil }; j += 1 }
        return close + 1
    }

    private static func _tokenizeBytes(_ b: [UInt8]) throws -> [Token] {
        var out: [Token] = []
        out.reserveCapacity(b.count / 3 + 1)
        var braces = 0
        var i = 0
        let end = b.count
        while i < end {
            let c = b[i]
            if isSpace(c) {
                var j = i
                while j < end, isSpace(b[j]) { j += 1 }
                if c == 0x20, let last = out.last, j < end {
                    let n = b[j]
                    let operandBefore: Bool
                    switch last {
                    case .ref, .rparen, .structured, .spill: operandBefore = true
                    case .name: operandBefore = n != 0x28
                    default: operandBefore = false
                    }
                    if operandBefore, isLetter(n) || n == 0x24 || n == 0x27 || n == 0x28 || n == 0x5F || n == 0x5B {
                        out.append(.op(" "))
                    }
                }
                i = j
                continue
            }
            // Strings.
            if c == 0x22 {
                var t: [UInt8] = []
                i += 1
                while true {
                    guard i < end else { throw FormulaError(message: "unterminated string") }
                    if b[i] == 0x22 {
                        if i + 1 < end, b[i + 1] == 0x22 { t.append(0x22); i += 2; continue }
                        i += 1
                        break
                    }
                    t.append(b[i]); i += 1
                }
                out.append(.text(String(decoding: t, as: UTF8.self))); continue
            }
            // Errors.
            if c == 0x23 {
                var hit: ExcelError? = nil
                for (e, raw) in errorTable where i + raw.count <= end {
                    var ok = true
                    for k in 0 ..< raw.count {
                        let x = b[i + k]
                        if (x >= 97 && x <= 122 ? x &- 32 : x) != raw[k] { ok = false; break }
                    }
                    if ok { hit = e; i += raw.count; break }
                }
                if let e = hit { out.append(.error(e)); continue }
                throw FormulaError(message: "bad error literal")
            }
            // Numbers (a leading "." too).
            if isDigit(c) || (c == 0x2E && i + 1 < end && isDigit(b[i + 1])) {
                if let r = rowRangeAt(b, i, sheet: nil) { out.append(.ref(r.ref)); i = r.end; continue }
                let start = i
                while i < end, isDigit(b[i]) || b[i] == 0x2E { i += 1 }
                if i < end, b[i] == 0x65 || b[i] == 0x45 {
                    var j = i + 1
                    if j < end, b[j] == 0x2B || b[j] == 0x2D { j += 1 }
                    if j < end, isDigit(b[j]) {
                        i = j
                        while i < end, isDigit(b[i]) { i += 1 }
                    }
                }
                let t = str(b, start, i)
                guard let v = Double(t) else { throw FormulaError(message: "bad number \(t)") }
                out.append(.number(v, t)); continue
            }
            // References, names, functions, booleans — with an optional sheet prefix.
            var externalPrefix = false
            if c == 0x5B, let n = externalBook(b, i), n < end, isLetter(b[n]) || b[n] == 0x5F { externalPrefix = true }
            if c == 0x27 || c == 0x24 || isLetter(c) || c == 0x5F || externalPrefix {
                var j = i
                var sheet: String? = nil
                if c == 0x27 {
                    var name: [UInt8] = []
                    j += 1
                    while true {
                        guard j < end else { throw FormulaError(message: "unterminated sheet name") }
                        if b[j] == 0x27 {
                            if j + 1 < end, b[j + 1] == 0x27 { name.append(0x27); j += 2; continue }
                            j += 1; break
                        }
                        name.append(b[j]); j += 1
                    }
                    guard j < end, b[j] == 0x21 else { throw FormulaError(message: "expected ! after sheet name") }
                    sheet = String(decoding: name, as: UTF8.self)
                    j += 1
                } else {
                    var k = j
                    if let n = externalBook(b, k) { k = n }
                    while k < end, isLetter(b[k]) || isDigit(b[k]) || b[k] == 0x5F || b[k] == 0x2E || b[k] == 0x24 { k += 1 }
                    if k < end, b[k] == 0x21 { sheet = str(b, j, k); j = k + 1 }
                }
                if sheet == nil {
                    var k = j
                    while k < end, isLetter(b[k]) || isDigit(b[k]) || b[k] == 0x5F || b[k] == 0x2E || b[k] == 0x5C { k += 1 }
                    if k > j, k < end, b[k] == 0x5B {
                        let e = try bracketEnd(b, from: k)
                        out.append(.structured(str(b, j, e))); i = e; continue
                    }
                }
                if let r = referenceAt(b, j, sheet: sheet) {
                    if r.ref.isCell, r.end < end, b[r.end] == 0x23 {
                        out.append(.spill(r.ref)); i = r.end + 1; continue
                    }
                    out.append(.ref(r.ref)); i = r.end; continue
                }
                var k = j
                while k < end, isLetter(b[k]) || isDigit(b[k]) || b[k] == 0x5F || b[k] == 0x2E { k += 1 }
                if let sheet {
                    guard k > j, k == end || b[k] != 0x28 else { throw FormulaError(message: "bad reference after \(sheet)!") }
                    out.append(.name(Formula.quoteSheet(sheet) + "!" + str(b, j, k))); i = k; continue
                }
                guard k > j else { throw FormulaError(message: "unexpected \(Character(Unicode.Scalar(c)))") }
                let word = str(b, j, k)
                if k < end, b[k] == 0x28 {
                    out.append(.function(word.uppercased())); i = k + 1; continue
                }
                switch word.uppercased() {
                case "TRUE": out.append(.bool(true))
                case "FALSE": out.append(.bool(false))
                default: out.append(.name(word))
                }
                i = k; continue
            }
            if c == 0x5B {
                let e = try bracketEnd(b, from: i)
                out.append(.structured(str(b, i, e))); i = e; continue
            }
            switch c {
            case 0x28: out.append(.lparen)
            case 0x29: out.append(.rparen)
            case 0x7B: braces += 1; out.append(.lbrace)
            case 0x7D: braces -= 1; out.append(.rbrace)
            case 0x3B where braces > 0: out.append(.rowSep)
            case 0x2C, 0x3B: out.append(.comma)
            case 0x3C:
                if i + 1 < end, b[i + 1] == 0x3D { out.append(.op("<=")); i += 1 }
                else if i + 1 < end, b[i + 1] == 0x3E { out.append(.op("<>")); i += 1 }
                else { out.append(.op("<")) }
            case 0x3E:
                if i + 1 < end, b[i + 1] == 0x3D { out.append(.op(">=")); i += 1 } else { out.append(.op(">")) }
            case 0x2B, 0x2D, 0x2A, 0x2F, 0x5E, 0x26, 0x3D, 0x25, 0x3A, 0x40:
                out.append(.op(String(Character(Unicode.Scalar(c)))))
            default: throw FormulaError(message: "unexpected \(Character(Unicode.Scalar(c)))")
            }
            i += 1
        }
        return out
    }
}
