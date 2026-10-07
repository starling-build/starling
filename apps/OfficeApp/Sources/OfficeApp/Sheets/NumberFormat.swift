// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Excel number formats: "General", and format codes such as "#,##0.00",
// "0%", "$#,##0;[Red]-$#,##0", "yyyy-mm-dd", "h:mm AM/PM", "@". Used to
// draw cells and by TEXT(). No printf: the wasm build has none of the
// legacy Foundation formatters, so digits are produced here.

import Foundation

enum NumberFormat {
    /// The text a value shows in a cell with format `code`, and a colour
    /// the format asks for ([Red] etc.), if any.
    static func display(_ v: CellValue, _ code: String, width: Int = 11) -> (text: String, color: UInt32?) {
        switch v {
        case .empty: return ("", nil)
        case .bool(let b): return display(.text(b ? "TRUE" : "FALSE"), code, width: width)
        case .error(let e): return (e.rawValue, nil)
        case .text(let s):
            let sections = _sections(code)
            if sections.count >= 4 { return (_applyText(sections[3], s), nil) }
            if sections.count == 1, sections[0].containsSubstring("@") { return (_applyText(sections[0], s), nil) }
            return (s, nil)
        case .number(let n): return format(n, code, width: width)
        }
    }

    /// `inText`: TEXT() shows a negative elapsed time ([h]:mm) with a minus
    /// where a cell shows ########.
    static func format(_ n: Double, _ code: String, width: Int = 11, inText: Bool = false) -> (text: String, color: UInt32?) {
        if code.isEmpty || code.lowercased() == "general" { return (general(n, width: width), nil) }
        let sections = _sections(code)
        let conds = sections.map(_condition)
        if conds.contains(where: { $0 != nil }) {
            // [<10]0" small";[>=100]0" big";0: the first section whose
            // condition holds, an unconditioned one for the rest, and
            // General when none applies. The number keeps its sign.
            for (i, section) in sections.enumerated() {
                if let cond = conds[i], !cond.holds(n) { continue }
                return _section(section, n, signed: true, width: width, inText: inText)
            }
            return (general(n, width: width), nil)
        }
        var section = sections[0]
        var value = n
        if sections.count >= 2, n < 0 { section = sections[1]; value = -n }
        else if sections.count >= 3, n == 0 { section = sections[2] }
        // A single section shows the sign itself.
        return _section(section, value, signed: sections.count == 1, width: width, date: n, inText: inText)
    }

    private static func _section(_ section: String, _ value: Double, signed: Bool, width: Int, date: Double? = nil, inText: Bool = false) -> (String, UInt32?) {
        let (body, color) = _stripColor(section)
        if body.lowercased() == "general" { return (general(value, width: width), color) }
        if _isDate(body) {
            let d = date ?? value
            if d < 0, inText, _hasElapsed(body) { return ("-" + _formatDate(-d, body), color) }
            return (_formatDate(d, body), color)
        }
        let sign = (signed && value < 0) ? "-" : ""
        if _isFraction(body) { return (sign + _formatFraction(abs(value), body), color) }
        return (sign + _formatNumber(abs(value), body), color)
    }

    /// [h], [mm], [s]: elapsed time rather than time of day.
    private static func _hasElapsed(_ body: String) -> Bool {
        var inQuote = false
        var i = body.startIndex
        while i < body.endIndex {
            let ch = body[i]
            if ch == "\\" { i = body.index(i, offsetBy: 2, limitedBy: body.endIndex) ?? body.endIndex; continue }
            if ch == "\"" { inQuote.toggle() }
            if !inQuote, ch == "[", let close = body[i...].firstIndex(of: "]") {
                let inner = body[body.index(after: i) ..< close].lowercased()
                if inner.hasPrefix("h") || inner.hasPrefix("m") || inner.hasPrefix("s") { return true }
                i = body.index(after: close); continue
            }
            i = body.index(after: i)
        }
        return false
    }

    /// A section's [<10] / [>=100] / [<>0] condition, if it has one.
    struct Condition {
        let op: String
        let x: Double
        func holds(_ n: Double) -> Bool {
            switch op {
            case "<": return n < x
            case "<=": return n <= x
            case ">": return n > x
            case ">=": return n >= x
            case "<>": return n != x
            default: return n == x
            }
        }
    }

    static func _condition(_ section: String) -> Condition? {
        var inQuote = false
        var i = section.startIndex
        while i < section.endIndex {
            let ch = section[i]
            if ch == "\\" { i = section.index(i, offsetBy: 2, limitedBy: section.endIndex) ?? section.endIndex; continue }
            if ch == "\"" { inQuote.toggle() }
            if !inQuote, ch == "[", let close = section[i...].firstIndex(of: "]") {
                let inner = section[section.index(after: i) ..< close]
                for op in ["<=", ">=", "<>", "<", ">", "="] where inner.hasPrefix(op) {
                    if let x = Double(inner.dropFirst(op.count).trimmingWhitespace()) { return Condition(op: op, x: x) }
                    return nil
                }
                i = section.index(after: close)
                continue
            }
            i = section.index(after: i)
        }
        return nil
    }

    // MARK: General

    /// Excel's General: integers as they are, others to at most `width`
    /// characters, scientific when too large or too small for that.
    static func general(_ n: Double, width: Int = 11) -> String {
        if n.isNaN || n.isInfinite { return "#NUM!" }
        if n == 0 { return "0" }
        let a = abs(n)
        if a >= 1e11 || a < 1e-9 { return _scientific(n, digits: 5) }
        // As many significant digits as fit.
        let intDigits = a >= 1 ? Int(log10(a)) + 1 : 1
        var decimals = max(0, width - intDigits - 1 - (n < 0 ? 1 : 0))
        decimals = min(decimals, max(0, 15 - intDigits))
        var s = fixed(n, decimals: decimals)
        if s.containsSubstring(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    /// Up to 15 significant digits, as the formula bar shows a number.
    static func full(_ n: Double) -> String {
        if n == 0 { return "0" }
        let a = abs(n)
        if a >= 1e15 || a < 1e-15 { return _scientific(n, digits: 14) }
        let mag = Int(floor(log10(a)))
        var s = fixed(n, decimals: max(0, min(15, 14 - mag)))
        if s.containsSubstring(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    /// `n` rounded to `decimals` places, as plain digits. Rounding is half
    /// away from zero, Excel's.
    static func fixed(_ n: Double, decimals: Int) -> String {
        let d = max(0, min(decimals, 15))
        let neg = n < 0
        let a = abs(n)
        let scale = _pow10(d)
        var scaled = (a * scale).rounded(.toNearestOrAwayFromZero)
        // Correct the binary representation's near misses (2.675 → 2.68).
        let alt = ((a * scale) + 1e-7).rounded(.toNearestOrAwayFromZero)
        if alt > scaled, abs((a * scale) - (alt - 0.5)) < 1e-6 { scaled = alt }
        guard scaled < 9e15 else { return (neg ? "-" : "") + _bigInteger(a) }
        let total = UInt64(scaled)
        let intPart = total / UInt64(scale)
        let frac = total % UInt64(scale)
        var s = String(intPart)
        if d > 0 {
            var f = String(frac)
            while f.count < d { f = "0" + f }
            s += "." + f
        }
        return (neg && scaled != 0 ? "-" : "") + s
    }

    private static func _bigInteger(_ a: Double) -> String {
        // Beyond 2^53 every Double is an integer; print its digits.
        var digits: [Character] = []
        var x = a.rounded()
        while x >= 1 {
            let q = (x / 10).rounded(.down)
            let r = Int(x - q * 10)
            digits.append(Character(String(max(0, min(9, r)))))
            x = q
        }
        return digits.isEmpty ? "0" : String(digits.reversed())
    }

    private static func _pow10(_ d: Int) -> Double {
        var x = 1.0
        for _ in 0 ..< d { x *= 10 }
        return x
    }

    private static func _scientific(_ n: Double, digits: Int) -> String {
        let a = abs(n)
        var exp = Int(floor(log10(a)))
        var mant = a / pow(10, Double(exp))
        // Rounding may carry to 10.0.
        if Double(fixed(mant, decimals: digits)) ?? 0 >= 10 { mant /= 10; exp += 1 }
        var m = fixed(mant, decimals: digits)
        if m.containsSubstring(".") {
            while m.hasSuffix("0") { m.removeLast() }
            if m.hasSuffix(".") { m.removeLast() }
        }
        let e = abs(exp)
        return (n < 0 ? "-" : "") + m + "E" + (exp < 0 ? "-" : "+") + (e < 10 ? "0" : "") + String(e)
    }

    // MARK: Codes

    /// Split on ";" outside quotes and brackets.
    static func _sections(_ code: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuote = false, inBracket = false, escape = false
        for ch in code {
            if escape { cur.append(ch); escape = false; continue }
            if ch == "\\" { cur.append(ch); escape = true; continue }
            if ch == "\"" { inQuote.toggle() }
            if !inQuote && ch == "[" { inBracket = true }
            if !inQuote && ch == "]" { inBracket = false }
            if ch == ";" && !inQuote && !inBracket { out.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        out.append(cur)
        return out
    }

    private static let _colors: [String: UInt32] = [
        "black": 0x000000, "blue": 0x0000FF, "cyan": 0x00FFFF, "green": 0x00FF00,
        "magenta": 0xFF00FF, "red": 0xFF0000, "white": 0xFFFFFF, "yellow": 0xFFFF00,
    ]

    /// Remove bracketed directives, returning the colour if one was named.
    /// Locale/currency brackets like [$€-407] keep their symbol.
    static func _stripColor(_ s: String) -> (String, UInt32?) {
        var out = ""
        var color: UInt32? = nil
        var i = s.startIndex
        var inQuote = false
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\"" { inQuote.toggle() }
            if !inQuote, ch == "[", let close = s[i...].firstIndex(of: "]") {
                let inner = String(s[s.index(after: i) ..< close])
                if let c = _colors[inner.lowercased()] { color = c }
                else if inner.hasPrefix("$") {
                    // [$€-407]: the symbol before the dash.
                    let sym = inner.dropFirst().split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
                    out += "\"" + sym + "\""
                } else if inner.lowercased().hasPrefix("h") || inner.lowercased().hasPrefix("m") || inner.lowercased().hasPrefix("s") {
                    out += "[" + inner + "]"  // elapsed time, kept for the date path
                }
                i = s.index(after: close)
                continue
            }
            out.append(ch)
            i = s.index(after: i)
        }
        return (out, color)
    }

    private static func _isDate(_ s: String) -> Bool {
        var inQuote = false
        var prev: Character = " "
        for ch in s.lowercased() {
            if ch == "\"" { inQuote.toggle(); continue }
            if inQuote || prev == "\\" { prev = ch; continue }
            if "ymdhs".contains(ch) { return true }
            prev = ch
        }
        return false
    }

    private static func _applyText(_ section: String, _ text: String) -> String {
        var out = ""
        let chars = Array(_stripColor(section).0)
        var k = 0
        while k < chars.count {
            let ch = chars[k]
            switch ch {
            case "\"":
                k += 1
                while k < chars.count, chars[k] != "\"" { out.append(chars[k]); k += 1 }
            case "\\": if k + 1 < chars.count { out.append(chars[k + 1]); k += 1 }
            case "_": if k + 1 < chars.count { out += " "; k += 1 }
            case "*": k += 1
            case "@": out += text
            default: out.append(ch)
            }
            k += 1
        }
        return out
    }

    enum Tok: Equatable { case lit(String), digit(Character), point, comma, percent, exp(Character, Character) }

    /// The code as tokens: literals (quoted, escaped, padded), digit
    /// placeholders, the point, commas, percent signs, E+/E-.
    private static func _tokens(_ code: String) -> [Tok] {
        var toks: [Tok] = []
        let chars = Array(code)
        var k = 0
        while k < chars.count {
            let ch = chars[k]
            switch ch {
            case "\"":
                var s = ""; k += 1
                while k < chars.count, chars[k] != "\"" { s.append(chars[k]); k += 1 }
                toks.append(.lit(s))
            case "\\": if k + 1 < chars.count { toks.append(.lit(String(chars[k + 1]))); k += 1 }
            case "_": if k + 1 < chars.count { toks.append(.lit(" ")); k += 1 }   // a space as wide as the next char
            case "*": k += 1                                                       // fill character: ignored
            case "0", "#", "?": toks.append(.digit(ch))
            case ".": toks.append(.point)
            case ",": toks.append(.comma)
            case "%": toks.append(.percent)
            case "E", "e":
                if k + 1 < chars.count, chars[k + 1] == "+" || chars[k + 1] == "-" { toks.append(.exp(ch, chars[k + 1])); k += 1 }
                else { toks.append(.lit(String(ch))) }
            default: toks.append(.lit(String(ch)))
            }
            k += 1
        }
        return toks
    }

    /// "#,##0.00", "0%", "$#,##0", "0.0E+00", "00000" and literals.
    private static func _formatNumber(_ value: Double, _ code: String) -> String {
        let toks = _tokens(code)
        let hasExp = toks.contains { if case .exp = $0 { return true }; return false }
        // Literals land before the digits, between the mantissa and the E,
        // between the E and its digits, or after everything.
        var before = "", mid = "", expMid = "", after = ""
        var intPattern = "", fracPattern = "", expPattern = ""
        var percent = 0, scaleCommas = 0, thousands = false
        var expLetter: Character = "E", expSign: Character = "+"
        // 0 before any digit, 1 integer digits, 2 fraction digits, 3 past the
        // number, 4 past the E, 5 exponent digits.
        var phase = 0
        func lit(_ s: String) {
            switch phase {
            case 0: before += s
            case 1, 2, 3: if hasExp { mid += s } else { after += s }; if phase != 0 { phase = 3 }
            case 4: expMid += s
            default: after += s
            }
        }
        for (i, t) in toks.enumerated() {
            switch t {
            case .digit(let d):
                switch phase {
                case 0, 1, 3: intPattern.append(d); phase = 1
                case 2: fracPattern.append(d)
                default: expPattern.append(d); phase = 5
                }
            case .point:
                if phase <= 1 { phase = 2 } else { lit(".") }
            case .comma:
                var nextIsDigit = false
                if i + 1 < toks.count, case .digit = toks[i + 1] { nextIsDigit = true }
                if phase == 1 && nextIsDigit { thousands = true }          // between digits: thousands
                else if (phase == 1 || phase == 2) && !hasExp { scaleCommas += 1 }   // trailing: divide by 1000
                else if phase == 0 { lit(",") }                              // past the exponent: nothing
            case .percent:
                if !hasExp { percent += 1 }
                lit("%")
            case .exp(let letter, let sign):
                expLetter = letter; expSign = sign; phase = 4
            case .lit(let s): lit(s)
            }
        }
        var v = value
        for _ in 0 ..< percent { v *= 100 }
        for _ in 0 ..< scaleCommas { v /= 1000 }
        if intPattern.isEmpty && fracPattern.isEmpty && expPattern.isEmpty { return before + mid + expMid + after }
        if hasExp {
            // The exponent is a multiple of the integer placeholders' count:
            // ##0.0E+0 is engineering notation.
            let n = max(1, intPattern.count)
            var exp = v == 0 ? 0 : Int(floor(log10(v) / Double(n))) * n
            var mant = v == 0 ? 0 : v / pow(10, Double(exp))
            if let r = Double(fixed(mant, decimals: fracPattern.count)), r >= pow(10, Double(n)) {
                exp += n; mant = v / pow(10, Double(exp))
            }
            var m = _digits(mant, intPattern, fracPattern, thousands: thousands)
            if v == 0 {
                // A zero mantissa fills every integer placeholder with 0.
                m = _digits(0, String(repeating: "0", count: max(1, intPattern.count)), fracPattern, thousands: thousands)
            }
            var es = String(abs(exp))
            // Exponent placeholders pad on the left: 0 with zeros, ? with spaces.
            let padE = max(0, expPattern.count - es.count)
            for ph in expPattern.prefix(padE).reversed() where ph != "#" { es = (ph == "0" ? "0" : " ") + es }
            let sign = exp < 0 ? "-" : (expSign == "+" ? "+" : "")
            return before + m + mid + String(expLetter) + expMid + sign + es + after
        }
        return before + _digits(v, intPattern, fracPattern, thousands: thousands) + after
    }

    /// "# ?/?", "#/8", "0 00/00": a "/" with a digit placeholder before it.
    private static func _isFraction(_ body: String) -> Bool {
        let toks = _tokens(body)
        guard let slash = toks.firstIndex(of: .lit("/")) else { return false }
        return toks[..<slash].contains { if case .digit = $0 { return true }; return false }
    }

    /// A fraction format: an optional integer part, the numerator's
    /// placeholders, "/", a denominator of placeholders or a fixed number,
    /// and literals anywhere between. The fraction is the closest with a
    /// denominator of that many digits (Excel's choice too); a whole value
    /// hides the fraction, as spaces when a ? asked for alignment.
    private static func _formatFraction(_ value: Double, _ body: String) -> String {
        let toks = _tokens(body)
        guard let slash = toks.firstIndex(of: .lit("/")) else { return _formatNumber(value, body) }
        func isDigit(_ t: Tok) -> Bool { if case .digit = t { return true }; return false }
        func placeholders(_ ts: ArraySlice<Tok>) -> [Character] { ts.compactMap { if case .digit(let d) = $0 { return d }; return nil } }
        // The numerator: the last run of placeholders before the slash.
        var numEnd = slash
        while numEnd > 0, !isDigit(toks[numEnd - 1]) { numEnd -= 1 }
        var numStart = numEnd
        while numStart > 0, isDigit(toks[numStart - 1]) { numStart -= 1 }
        let numPost = toks[numEnd ..< slash]
        let numPattern = placeholders(toks[numStart ..< numEnd])
        // The integer part: everything before, its trailing literals the separator.
        var intEnd = numStart
        while intEnd > 0, !isDigit(toks[intEnd - 1]) { intEnd -= 1 }
        let intToks = Array(toks[..<intEnd])
        let separator = Array(toks[intEnd ..< numStart])
        let intPattern = placeholders(intToks[...])
        let hasInt = !intPattern.isEmpty
        // The denominator: placeholders, or a literal number, after the slash.
        var denPre: [Tok] = []
        var j = slash + 1
        var fixedDen = ""
        var denPattern: [Character] = []
        while j < toks.count {
            if case .digit(let d) = toks[j], fixedDen.isEmpty { denPattern.append(d); j += 1; continue }
            if case .lit(let l) = toks[j], denPattern.isEmpty, l.allSatisfy(\.isNumber) { fixedDen += l; j += 1; continue }
            if denPattern.isEmpty && fixedDen.isEmpty { denPre.append(toks[j]); j += 1; continue }
            break
        }
        let after = toks[j...]
        let aligned = (intPattern + numPattern + denPattern).contains("?")
        // The value as whole + n/d: the closest fraction with that many
        // denominator digits, or over the fixed denominator.
        var whole = hasInt ? floor(value) : 0
        let frac = value - whole
        var n = 0, d = 1
        if let fd = Int(fixedDen), fd > 0 {
            d = fd; n = Int((frac * Double(d)).rounded())
        } else {
            let maxDen = max(1, Int(_pow10(max(1, denPattern.count))) - 1)
            var best = Double.infinity
            for den in 1 ... maxDen {
                let num = (frac * Double(den)).rounded()
                let err = abs(frac - num / Double(den))
                if err < best - 1e-12 { best = err; n = Int(num); d = den }
                if best == 0 { break }
            }
        }
        if n == d { whole += 1; n = 0 }
        if !hasInt { n += Int(whole) * d; whole = 0 }
        // A whole value hides the fraction, unless a 0 numerator insists on 0/1.
        let hidden = hasInt && n == 0 && !numPattern.contains("0")
        func lits(_ ts: ArraySlice<Tok>) -> String { ts.map { if case .lit(let l) = $0 { return l }; return "" }.joined() }
        func width(_ ts: ArraySlice<Tok>) -> Int {
            var w = 0
            for t in ts { if case .lit(let l) = t { w += l.count } else { w += 1 } }
            return w
        }
        // Digits into placeholders from the right, extra digits into the
        // first; an unused # is nothing, ? a space, 0 a zero; literals stay.
        func render(_ digits: String, over pattern: [Tok]) -> String {
            let slots = pattern.filter(isDigit).count
            var ds = Array(digits)
            var out = ""
            var unused = max(0, slots - ds.count)
            var first = true
            for t in pattern {
                switch t {
                case .digit(let ph):
                    if unused > 0 { unused -= 1; out += ph == "?" ? " " : (ph == "0" ? "0" : "") }
                    else if first, ds.count > slots { out += String(ds.prefix(ds.count - slots + 1)); ds.removeFirst(ds.count - slots + 1) }
                    else if !ds.isEmpty { out.append(ds.removeFirst()) }
                    first = false
                case .lit(let l): out += l
                default: break
                }
            }
            return out
        }
        var intText = ""
        var intHasDigit = false
        if hasInt {
            // A zero integer part shows as 0 when the fraction is hidden, or
            // when the value is 0 and a ? or 0 placeholder can hold it.
            if whole > 0 || hidden || (value == 0 && (intPattern.contains("?") || intPattern.contains("0"))) {
                intText = render(String(Int(whole)), over: intToks)
                if Int(whole) == 0, hidden, intPattern.allSatisfy({ $0 == "#" }) {
                    // 0 in #-only placeholders: the zero takes the last one.
                    var fixed = ""
                    var placed = false
                    for t in intToks.reversed() {
                        if case .digit = t, !placed { fixed = "0" + fixed; placed = true }
                        else if case .lit(let l) = t { fixed = l + fixed }
                    }
                    intText = fixed
                }
            } else {
                intText = render("", over: intToks)
            }
            intHasDigit = intText.contains { $0.isNumber }
        }
        if hidden {
            let fracToks = toks[numStart ..< j]
            return intText + (aligned ? String(repeating: " ", count: width(separator[...]) + width(fracToks)) : "") + lits(after)
        }
        var numText = ""
        do {
            var pad = max(0, numPattern.count - String(n).count)
            for ph in numPattern { if pad > 0 { pad -= 1; numText += ph == "?" ? " " : (ph == "0" ? "0" : "") } }
            numText += String(n)
        }
        var denText = fixedDen.isEmpty ? String(d) : fixedDen
        if fixedDen.isEmpty {
            // 0 pads a denominator on the left, ? on the right.
            let pad = max(0, denPattern.count - denText.count)
            let zeros = denPattern.prefix(pad).filter { $0 == "0" }.count
            denText = String(repeating: "0", count: zeros) + denText
            denText += String(repeating: " ", count: denPattern.suffix(pad).filter { $0 == "?" }.count)
        }
        // Without an integer part the "separator" is whatever leads the code.
        // A blank integer part takes its separator as spaces when a ? in the
        // integer or numerator asks for alignment, and drops it otherwise.
        let alignedSep = intPattern.contains("?") || numPattern.contains("?")
        let sep = !hasInt ? lits(separator[...]) : intHasDigit ? lits(separator[...]) : (alignedSep ? String(repeating: " ", count: width(separator[...])) : "")
        return intText + sep + numText + lits(numPost) + "/" + lits(denPre[...]) + denText + lits(after)
    }

    private static func _digits(_ v: Double, _ intPattern: String, _ fracPattern: String, thousands: Bool) -> String {
        let s = fixed(v, decimals: fracPattern.count)
        var parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var intDigits = parts[0]
        var frac = parts.count > 1 ? parts[1] : ""
        parts = []
        // Integer part: at least as many digits as there are 0s.
        let minInt = intPattern.filter { $0 == "0" }.count
        if intDigits == "0" && minInt == 0 { intDigits = "" }
        while intDigits.count < minInt { intDigits = "0" + intDigits }
        // An unused ? is a space as wide as a digit; a thousands separator
        // among the spaces is a space too.
        let unused = Array(intPattern.prefix(max(0, intPattern.count - intDigits.count)))
        let seq: [Character] = unused.filter { $0 == "?" }.map { _ in " " } + Array(intDigits)
        if thousands && seq.count > 3 {
            var out: [Character] = []
            for (i, ch) in seq.reversed().enumerated() {
                if i > 0 && i % 3 == 0 { out.append(ch.isNumber && (out.last?.isNumber ?? false) ? "," : " ") }
                out.append(ch)
            }
            intDigits = String(out.reversed())
        } else {
            intDigits = String(seq)
        }
        // Fraction: drop trailing zeros that only # or ? allow; ? leaves a space.
        var fp = Array(fracPattern)
        var trailing = ""
        while !frac.isEmpty, let last = fp.last, last != "0", frac.hasSuffix("0") {
            frac.removeLast(); fp.removeLast()
            if last == "?" { trailing = " " + trailing }
        }
        if frac.isEmpty && trailing.isEmpty { return fracPattern.isEmpty ? intDigits : intDigits + "." }
        return intDigits + "." + frac + trailing
    }

    // MARK: Dates

    private static let _monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                      "August", "September", "October", "November", "December"]
    private static let _dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private static func _formatDate(_ serial: Double, _ code: String) -> String {
        guard serial >= 0 else { return String(repeating: "#", count: 8) }
        let chars = Array(code)
        // Fractional seconds (ss.000) and elapsed units ([h], [mm], [s]) in
        // the code decide how the time is rounded and what h, m, s mean.
        var fracDigits = 0
        var elapsedH = false, elapsedM = false, elapsedS = false
        do {
            var k = 0
            var inQuote = false
            while k < chars.count {
                let ch = chars[k]
                if ch == "\"" { inQuote.toggle(); k += 1; continue }
                if inQuote { k += 1; continue }
                if ch == "\\" { k += 2; continue }
                if ch == "[", let close = chars[k...].firstIndex(of: "]") {
                    let inner = String(chars[(k + 1) ..< close]).lowercased()
                    if inner.hasPrefix("h") { elapsedH = true }
                    else if inner.hasPrefix("m") { elapsedM = true }
                    else if inner.hasPrefix("s") { elapsedS = true }
                    k = close + 1
                    if inner.hasPrefix("s"), k < chars.count, chars[k] == "." {
                        var n = 0
                        while k + 1 + n < chars.count, chars[k + 1 + n] == "0" { n += 1 }
                        if n > 0 { fracDigits = max(fracDigits, min(3, n)) }
                    }
                    continue
                }
                if ch == "s" || ch == "S" {
                    while k < chars.count, chars[k] == "s" || chars[k] == "S" { k += 1 }
                    if k < chars.count, chars[k] == "." {
                        var n = 0
                        while k + 1 + n < chars.count, chars[k + 1 + n] == "0" { n += 1 }
                        if n > 0 { fracDigits = max(fracDigits, min(3, n)) }
                    }
                    continue
                }
                k += 1
            }
        }
        let scale = _pow10(fracDigits)
        let totalSec = (serial * 86400 * scale).rounded(.toNearestOrAwayFromZero) / scale
        let whole = floor(totalSec)
        let fracPart = Int(((totalSec - whole) * scale).rounded())
        let dayNumber = Int(floor(whole / 86400))
        let secOfDay = Int(whole) - dayNumber * 86400
        let hh = secOfDay / 3600, mi = (secOfDay % 3600) / 60, ss = secOfDay % 60
        let elapsedHours = Int(whole) / 3600, elapsedMinutes = Int(whole) / 60, elapsedSeconds = Int(whole)
        let (y, mo, d) = ExcelDate.ymd(Double(dayNumber))
        let weekday = ExcelDate.weekday(Double(dayNumber)) - 1
        let lower = code.lowercased()
        let ampm = lower.containsSubstring("am/pm") || lower.containsSubstring("a/p")
        var out = ""
        var k = 0
        var prevToken: Character = " "
        func pad(_ n: Int, _ width: Int) -> String {
            var s = String(n)
            while s.count < width { s = "0" + s }
            return s
        }
        func two(_ n: Int) -> String { pad(n, 2) }
        func run(_ c: Character) -> Int {
            var n = 0
            while k + n < chars.count, chars[k + n].lowercased() == String(c) { n += 1 }
            return n
        }
        // The next date letter after position `from`, past literals.
        func nextToken(_ from: Int) -> Character? {
            var j = from
            var inQuote = false
            while j < chars.count {
                let ch = chars[j]
                if ch == "\"" { inQuote.toggle(); j += 1; continue }
                if inQuote { j += 1; continue }
                if ch == "\\" { j += 2; continue }
                if ch == "[", let close = chars[j...].firstIndex(of: "]") { j = close + 1; continue }
                let lc = Character(ch.lowercased())
                if "ymdhsa".contains(lc) { return lc }
                j += 1
            }
            return nil
        }
        while k < chars.count {
            let ch = chars[k]
            let lc = Character(ch.lowercased())
            switch lc {
            case "\"":
                k += 1
                while k < chars.count, chars[k] != "\"" { out.append(chars[k]); k += 1 }
                k += 1; continue
            case "\\":
                if k + 1 < chars.count { out.append(chars[k + 1]) }
                k += 2; continue
            case "y":
                let n = run("y")
                out += n <= 2 ? two(y % 100) : String(y)
                k += n; prevToken = "y"; continue
            case "d":
                let n = run("d")
                switch n {
                case 1: out += String(d)
                case 2: out += two(d)
                case 3: out += String(_dayNames[weekday].prefix(3))
                default: out += _dayNames[weekday]
                }
                k += n; prevToken = "d"; continue
            case "h":
                let n = run("h")
                var h = hh
                if elapsedH { h = elapsedHours }
                else if ampm { h = hh % 12; if h == 0 { h = 12 } }
                out += n >= 2 ? two(h) : String(h)
                k += n; prevToken = "h"; continue
            case "m":
                let n = run("m")
                // Minutes right after an hour or a second, or right before a
                // second; a month otherwise.
                if (prevToken == "h" || prevToken == "s" || nextToken(k + n) == "s") && n <= 2 {
                    let m = elapsedM ? elapsedMinutes : mi
                    out += n == 2 ? two(m) : String(m)
                } else {
                    switch n {
                    case 1: out += String(mo)
                    case 2: out += two(mo)
                    case 3: out += String(_monthNames[mo - 1].prefix(3))
                    case 5: out += String(_monthNames[mo - 1].prefix(1))
                    default: out += _monthNames[mo - 1]
                    }
                }
                k += n; prevToken = "m"; continue
            case "s":
                let n = run("s")
                let s = elapsedS ? elapsedSeconds : ss
                out += n >= 2 ? two(s) : String(s)
                k += n; prevToken = "s"
                // ss.000: the fraction, to as many places as the code has.
                if k < chars.count, chars[k] == ".", k + 1 < chars.count, chars[k + 1] == "0" {
                    var z = 0
                    while k + 1 + z < chars.count, chars[k + 1 + z] == "0" { z += 1 }
                    let shown = min(3, z)
                    var f = pad(fracPart, fracDigits)
                    if f.count > shown { f = String(f.prefix(shown)) }
                    out += "." + f + String(repeating: "0", count: z - shown)
                    k += 1 + z
                }
                continue
            case "a":
                let rest = String(chars[k...]).lowercased()
                if rest.hasPrefix("am/pm") { out += hh < 12 ? "AM" : "PM"; k += 5; continue }
                if rest.hasPrefix("a/p") {
                    // The letter keeps the case it was written in: a/p, A/P.
                    out.append(hh < 12 ? chars[k] : chars[k + 2]); k += 3; continue
                }
                out.append(ch); k += 1; continue
            case "[":
                // Elapsed time: [h], [hh], [mm], [s]…
                if let close = chars[k...].firstIndex(of: "]") {
                    let inner = String(chars[(k + 1) ..< close]).lowercased()
                    if inner.hasPrefix("h") { out += pad(elapsedHours, inner.count); prevToken = "h" }
                    else if inner.hasPrefix("m") { out += pad(elapsedMinutes, inner.count); prevToken = "m" }
                    else if inner.hasPrefix("s") { out += pad(elapsedSeconds, inner.count); prevToken = "s" }
                    k = close + 1
                    if inner.hasPrefix("s"), k < chars.count, chars[k] == ".", k + 1 < chars.count, chars[k + 1] == "0" {
                        var z = 0
                        while k + 1 + z < chars.count, chars[k + 1 + z] == "0" { z += 1 }
                        let shown = min(3, z)
                        var f = pad(fracPart, fracDigits)
                        if f.count > shown { f = String(f.prefix(shown)) }
                        out += "." + f + String(repeating: "0", count: z - shown)
                        k += 1 + z
                    }
                    continue
                }
                out.append(ch); k += 1; continue
            case "_": k += 2; out.append(" "); continue
            case "*": k += 2; continue
            default:
                out.append(ch); k += 1
            }
        }
        return out
    }
}

/// Excel's 1900 date system: serial 1 is 1900-01-01, and serial 60 is the
/// 29 February 1900 that never was (Lotus's bug, kept for compatibility).
enum ExcelDate {
    /// Days from 1970-01-01 to a civil date (Howard Hinnant's algorithm).
    static func daysFromCivil(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let y2 = m <= 2 ? y - 1 : y
        let era = (y2 >= 0 ? y2 : y2 - 399) / 400
        let yoe = y2 - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// 1899-12-30 as days since 1970: serial 0 for every date after the bug.
    private static let _epoch = daysFromCivil(1899, 12, 30)
    /// The 1904 date system (old Mac workbooks, workbookPr date1904): serial
    /// 0 is 1 January 1904 and there is no phantom 29 February 1900. Set
    /// for the open workbook when it loads.
    nonisolated(unsafe) static var system1904 = false
    private static let _epoch1904 = daysFromCivil(1904, 1, 1)

    static func serial(_ y: Int, _ m: Int, _ d: Int) -> Double {
        if system1904 {
            var yy = y, mm = m
            yy += (mm - 1) >= 0 ? (mm - 1) / 12 : -((12 - mm) / 12)
            mm = ((mm - 1) % 12 + 12) % 12 + 1
            return Double(daysFromCivil(yy, mm, 1) + (d - 1) - _epoch1904)
        }
        // DATE normalises months and days that overflow.
        var yy = y, mm = m
        yy += (mm - 1) >= 0 ? (mm - 1) / 12 : -((12 - mm) / 12)
        mm = ((mm - 1) % 12 + 12) % 12 + 1
        // The day overflows as serial days from the first of the month
        // (DATE(1900,1,22222) is 22222), and before 1 March 1900 the serials
        // are one lower than the real count: DATE(1900,2,29) is the 60.
        let first = daysFromCivil(yy, mm, 1) - _epoch
        return Double((first <= 60 ? first - 1 : first) + (d - 1))
    }

    static func ymd(_ serial: Double) -> (Int, Int, Int) {
        let s = Int(floor(serial))
        if system1904 { return civilFromDays(s + _epoch1904) }
        if s == 60 { return (1900, 2, 29) }
        if s == 0 { return (1900, 1, 0) }
        return civilFromDays((s < 60 ? s + 1 : s) + _epoch)
    }

    /// 1 = Sunday … 7 = Saturday, as WEEKDAY's default.
    static func weekday(_ serial: Double) -> Int {
        let s = Int(floor(serial))
        // 1904-01-01 was a Friday.
        if system1904 { return ((s + 5) % 7 + 7) % 7 + 1 }
        // Serial 1 (1900-01-01) was a Sunday in Excel's calendar.
        return ((s + 6) % 7 + 7) % 7 + 1
    }

    /// Now, as a serial in the local time zone.
    static func now() -> Double {
        let t = Date().timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT())
        return t / 86400 - Double(system1904 ? _epoch1904 : _epoch)
    }
}
