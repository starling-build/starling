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
        case .bool(let b): return (b ? "TRUE" : "FALSE", nil)
        case .error(let e): return (e.rawValue, nil)
        case .text(let s):
            let sections = _sections(code)
            if sections.count >= 4 { return (_applyText(sections[3], s), nil) }
            if sections.count == 1, sections[0].containsSubstring("@") { return (_applyText(sections[0], s), nil) }
            return (s, nil)
        case .number(let n): return format(n, code, width: width)
        }
    }

    static func format(_ n: Double, _ code: String, width: Int = 11) -> (text: String, color: UInt32?) {
        if code.isEmpty || code.lowercased() == "general" { return (general(n, width: width), nil) }
        let sections = _sections(code)
        var section = sections[0]
        var value = n
        if sections.count >= 2, n < 0 { section = sections[1]; value = -n }
        else if sections.count >= 3, n == 0 { section = sections[2] }
        let (body, color) = _stripColor(section)
        if body.lowercased() == "general" { return (general(value, width: width), color) }
        if _isDate(body) { return (_formatDate(n, body), color) }
        // A single section shows the sign itself.
        let sign = (sections.count == 1 && n < 0) ? "-" : ""
        return (sign + _formatNumber(abs(value), body), color)
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
        var inQuote = false
        for ch in _stripColor(section).0 {
            if ch == "\"" { inQuote.toggle(); continue }
            if !inQuote && ch == "@" { out += text } else { out.append(ch) }
        }
        return out
    }

    /// "#,##0.00", "0%", "$#,##0", "0.0E+00", "00000" and literals.
    private static func _formatNumber(_ value: Double, _ code: String) -> String {
        // Tokens: digit placeholders 0 # ?, "." "," "%" "E+", literals.
        var literalBefore = "", literalAfter = ""
        var intPattern = "", fracPattern = ""
        var percent = 0
        var thousands = false
        var scaleCommas = 0
        var sci: (sign: Bool, digits: Int)? = nil
        var seenDigit = false, seenPoint = false, afterNumber = false
        var chars = Array(code)
        var k = 0
        func lit(_ s: String) { if afterNumber || seenDigit { literalAfter += s } else { literalBefore += s } }
        while k < chars.count {
            let ch = chars[k]
            switch ch {
            case "\"":
                var s = ""; k += 1
                while k < chars.count, chars[k] != "\"" { s.append(chars[k]); k += 1 }
                lit(s)
            case "\\": if k + 1 < chars.count { lit(String(chars[k + 1])); k += 1 }
            case "_": if k + 1 < chars.count { lit(" "); k += 1 }   // a space as wide as the next char
            case "*": k += 1                                       // fill character: ignored
            case "0", "#", "?":
                if sci != nil { sci!.digits += 1 }
                else if seenPoint { fracPattern.append(ch) } else { intPattern.append(ch) }
                seenDigit = true
            case ".": if sci == nil { seenPoint = true } else { lit(".") }
            case ",":
                // Between digits: thousands. Trailing: divide by 1000.
                if k + 1 < chars.count, "0#?".contains(chars[k + 1]), seenDigit, !seenPoint { thousands = true }
                else if seenDigit { scaleCommas += 1 } else { lit(",") }
            case "%": percent += 1; lit("%")
            case "E", "e":
                if k + 1 < chars.count, chars[k + 1] == "+" || chars[k + 1] == "-" {
                    sci = (chars[k + 1] == "+", 0); k += 1
                } else { lit(String(ch)) }
            default:
                lit(String(ch))
            }
            if seenDigit && !"0#?.,".contains(ch) && ch != "E" && ch != "e" && sci == nil { afterNumber = true }
            k += 1
        }
        _ = chars
        chars = []
        var v = value
        for _ in 0 ..< percent { v *= 100 }
        for _ in 0 ..< scaleCommas { v /= 1000 }
        if !seenDigit { return literalBefore + literalAfter }
        if let sci {
            var exp = v == 0 ? 0 : Int(floor(log10(v)))
            let intDigits = max(1, intPattern.count)
            exp -= intDigits - 1
            let mant = v == 0 ? 0 : v / pow(10, Double(exp))
            let m = _digits(mant, intPattern, fracPattern, thousands: false)
            let e = abs(exp)
            var es = String(e)
            while es.count < max(1, sci.digits) { es = "0" + es }
            return literalBefore + m + "E" + (exp < 0 ? "-" : (sci.sign ? "+" : "")) + es + literalAfter
        }
        return literalBefore + _digits(v, intPattern, fracPattern, thousands: thousands) + literalAfter
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
        if thousands && intDigits.count > 3 {
            var grouped = ""
            for (i, ch) in intDigits.reversed().enumerated() {
                if i > 0 && i % 3 == 0 { grouped.append(",") }
                grouped.append(ch)
            }
            intDigits = String(grouped.reversed())
        }
        // Fraction: drop trailing zeros that only # allows.
        var fp = Array(fracPattern)
        while !frac.isEmpty, let last = fp.last, last != "0", frac.hasSuffix("0") {
            frac.removeLast(); fp.removeLast()
        }
        return frac.isEmpty ? (fracPattern.isEmpty || fp.isEmpty ? intDigits : intDigits + ".") : intDigits + "." + frac
    }

    // MARK: Dates

    private static let _monthNames = ["January", "February", "March", "April", "May", "June", "July",
                                      "August", "September", "October", "November", "December"]
    private static let _dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private static func _formatDate(_ serial: Double, _ code: String) -> String {
        guard serial >= 0 else { return String(repeating: "#", count: 8) }
        let (y, mo, d) = ExcelDate.ymd(serial)
        let frac = serial - floor(serial)
        var secs = Int((frac * 86400).rounded())
        if secs >= 86400 { secs = 86399 }
        let hh = secs / 3600, mi = (secs % 3600) / 60, ss = secs % 60
        let weekday = ExcelDate.weekday(serial) - 1
        let lower = code.lowercased()
        let ampm = lower.containsSubstring("am/pm") || lower.containsSubstring("a/p")
        var out = ""
        let chars = Array(code)
        var k = 0
        var lastWasHour = false
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        func run(_ c: Character) -> Int {
            var n = 0
            while k + n < chars.count, chars[k + n].lowercased() == String(c) { n += 1 }
            return n
        }
        // Is the "m" at k minutes? Yes after an hour or before seconds.
        func minutesAhead(_ from: Int) -> Bool {
            var j = from
            while j < chars.count, "mM".contains(chars[j]) { j += 1 }
            while j < chars.count, !"ymdhsYMDHS".contains(chars[j]) { j += 1 }
            return j < chars.count && "sS".contains(chars[j])
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
                k += n; lastWasHour = false; continue
            case "d":
                let n = run("d")
                switch n {
                case 1: out += String(d)
                case 2: out += two(d)
                case 3: out += String(_dayNames[weekday].prefix(3))
                default: out += _dayNames[weekday]
                }
                k += n; lastWasHour = false; continue
            case "h":
                let n = run("h")
                var h = hh
                if ampm { h = hh % 12; if h == 0 { h = 12 } }
                out += n >= 2 ? two(h) : String(h)
                k += n; lastWasHour = true; continue
            case "m":
                let n = run("m")
                if (lastWasHour || minutesAhead(k)) && n <= 2 {
                    out += n == 2 ? two(mi) : String(mi)
                } else {
                    switch n {
                    case 1: out += String(mo)
                    case 2: out += two(mo)
                    case 3: out += String(_monthNames[mo - 1].prefix(3))
                    case 5: out += String(_monthNames[mo - 1].prefix(1))
                    default: out += _monthNames[mo - 1]
                    }
                }
                k += n; lastWasHour = false; continue
            case "s":
                let n = run("s")
                out += n >= 2 ? two(ss) : String(ss)
                k += n; lastWasHour = false; continue
            case "a":
                let rest = String(chars[k...]).lowercased()
                if rest.hasPrefix("am/pm") { out += hh < 12 ? "AM" : "PM"; k += 5; continue }
                if rest.hasPrefix("a/p") { out += hh < 12 ? "A" : "P"; k += 3; continue }
                out.append(ch); k += 1; continue
            case "[":
                // Elapsed hours [h].
                if let close = chars[k...].firstIndex(of: "]") {
                    let inner = String(chars[(k + 1) ..< close]).lowercased()
                    if inner.hasPrefix("h") { out += String(Int(serial * 24)) }
                    else if inner.hasPrefix("m") { out += String(Int(serial * 1440)) }
                    else if inner.hasPrefix("s") { out += String(Int(serial * 86400)) }
                    k = close + 1; continue
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
        let days = daysFromCivil(yy, mm, 1) + (d - 1) - _epoch
        // Before 1 March 1900 the serials are one lower than the real count.
        return Double(days <= 60 ? days - 1 : days)
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
