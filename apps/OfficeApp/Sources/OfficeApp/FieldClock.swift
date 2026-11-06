// DATE and TIME fields show the moment of printing, whatever the file cached: Word updates them as it opens and
// prints. lo-7ab8dbc4 (TIME \@ "dd.MM.yyyy" cached 13.08.2014), lo-a43021ca (bare DATE and TIME in a footer) and
// lo-72e72396 (DATE \@"dd/MM/yy" cached 3/13/14) were printed on 2026-10-30 and show that day.
// The clock is the real one, unless OFFICE_NOW ("2026-10-30T10:44:20-07:00", read as the local wall time it gives)
// pins it: the test scripts pin it to the reference PDF's creation date (test/corpus/docx/clock.tsv).
// Only DATE and TIME: CREATEDATE, SAVEDATE and PRINTDATE come from the document's properties.
// Month and weekday names are locale words we do not carry, so a picture with them keeps the cached text.
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

struct FieldClock: Equatable {
    var year, month, day, hour, minute, second: Int

    /// "2026-10-30T10:44:20-07:00" (offset, seconds and a space for the T are optional); the wall time as written.
    static func parse(_ s: String) -> FieldClock? {
        let digits = Array(s.utf8)
        var nums: [Int] = []
        var i = 0
        while i < digits.count, nums.count < 6 {
            if digits[i] >= 48 && digits[i] <= 57 {
                var n = 0
                var len = 0
                while i < digits.count, digits[i] >= 48 && digits[i] <= 57 { n = n * 10 + Int(digits[i] - 48); i += 1; len += 1 }
                if nums.count == 0 && len != 4 { return nil }
                nums.append(n)
            } else if nums.count >= 3 && (digits[i] == 43 || (digits[i] == 45 && nums.count >= 5)) { break }
            else { i += 1 }
        }
        guard nums.count >= 3 else { return nil }
        while nums.count < 6 { nums.append(0) }
        return FieldClock(year: nums[0], month: nums[1], day: nums[2], hour: nums[3], minute: nums[4], second: nums[5])
    }

    /// OFFICE_NOW if set, else the machine's local time; nil where there is no clock to read (the web build).
    static func current() -> FieldClock? {
        #if canImport(Glibc) || canImport(Darwin)
        if let p = getenv("OFFICE_NOW") {
            let s = String(cString: p)
            if !s.isEmpty { return parse(s) }
        }
        var t = time(nil)
        var tmv = tm()
        guard localtime_r(&t, &tmv) != nil else { return nil }
        return FieldClock(year: Int(tmv.tm_year) + 1900, month: Int(tmv.tm_mon) + 1, day: Int(tmv.tm_mday),
                          hour: Int(tmv.tm_hour), minute: Int(tmv.tm_min), second: Int(tmv.tm_sec))
        #else
        return nil
        #endif
    }

    private func pad(_ n: Int, _ w: Int) -> String {
        var s = String(n)
        while s.count < w { s = "0" + s }
        return s
    }

    /// A Word date-time picture: yyyy yy MM M dd d HH H hh h mm m ss s AM/PM am/pm, 'quoted text', anything else
    /// literal (年月日 included). nil for names (MMM, ddd) we cannot spell.
    func format(picture: String) -> String? {
        let c = Array(picture)
        var out = ""
        var i = 0
        let pm = hour >= 12
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        while i < c.count {
            let ch = c[i]
            var j = i
            while j < c.count, c[j] == ch { j += 1 }
            let n = j - i
            switch ch {
            case "y": out += n >= 3 ? pad(year, 4) : pad(year % 100, 2); i = j
            case "M": if n >= 3 { return nil }; out += pad(month, n); i = j
            case "d": if n >= 3 { return nil }; out += pad(day, n); i = j
            case "H": out += pad(hour, n >= 2 ? 2 : 1); i = j
            case "h": out += pad(h12, n >= 2 ? 2 : 1); i = j
            case "m": out += pad(minute, n >= 2 ? 2 : 1); i = j
            case "s": out += pad(second, n >= 2 ? 2 : 1); i = j
            case "A", "a":
                let rest = String(c[i...])
                if rest.hasPrefix("AM/PM") { out += pm ? "PM" : "AM"; i += 5 }
                else if rest.hasPrefix("am/pm") { out += pm ? "pm" : "am"; i += 5 }
                else if rest.hasPrefix("A/P") { out += pm ? "P" : "A"; i += 3 }
                else if rest.hasPrefix("a/p") { out += pm ? "p" : "a"; i += 3 }
                else { out.append(ch); i += 1 }
            case "'":
                var k = i + 1
                while k < c.count, c[k] != "'" { out.append(c[k]); k += 1 }
                i = k + 1
            case "\\":
                if i + 1 < c.count { out.append(c[i + 1]) }
                i += 2
            default: out.append(ch); i += 1
            }
        }
        return out
    }

    /// The picture a bare DATE or TIME falls back to: the shape of what the file cached (the printing machine's
    /// locale is not in the file). nil when the cache says nothing.
    static func shape(of cached: String, time: Bool) -> String? {
        let t = Array(cached.filter { $0 != " " && $0 != "\u{A0}" })
        var groups: [[Character]] = [[]]
        var seps: [Character] = []
        var tail = ""
        for (k, ch) in t.enumerated() {
            if ch.isNumber { groups[groups.count - 1].append(ch) }
            else if ch == "." || ch == "/" || ch == "-" || ch == ":" { seps.append(ch); groups.append([]) }
            else { tail = String(t[k...]); break }
        }
        if time {
            guard groups.count >= 2, seps.allSatisfy({ $0 == ":" }), groups[0].count >= 1, groups[1].count == 2 else { return nil }
            var p = (groups[0].count == 2 ? "HH" : "H") + ":mm"
            if groups.count == 3 { p += ":ss" }
            if !tail.isEmpty {
                p = (groups[0].count == 2 ? "hh" : "h") + p.dropFirst(groups[0].count == 2 ? 2 : 1)
                p += " " + (tail == tail.lowercased() ? "am/pm" : "AM/PM")
            }
            return p
        }
        guard groups.count == 3, seps.count == 2, seps[0] == seps[1], seps[0] != ":", tail.isEmpty,
              groups.allSatisfy({ !$0.isEmpty }) else { return nil }
        let s = String(seps[0])
        let a = Int(String(groups[0])) ?? 0, b = Int(String(groups[1])) ?? 0
        let year = groups[2].count == 4 ? "yyyy" : "yy"
        if s == "." || a > 12 { return "dd\(s)MM\(s)\(year)" }
        if b > 12 { return "MM\(s)dd\(s)\(year)" }
        return nil
    }

    /// The text of a DATE or TIME field whose instruction is `instr` and whose cached result is `cached`.
    func text(instr: String, cached: String) -> String? {
        let words = instr.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard let first = words.first else { return nil }
        let kind = first.uppercased()
        guard kind == "DATE" || kind == "TIME" else { return nil }
        var picture: String?
        if let r = instr.firstIndex(of: "@"), instr[instr.index(before: r)...].hasPrefix("\\") {
            var rest = String(instr[instr.index(after: r)...]).drop { $0 == " " }
            if rest.first == "\"" {
                rest = rest.dropFirst()
                if let q = rest.firstIndex(of: "\"") { picture = String(rest[..<q]) }
            } else {
                picture = String(rest.prefix { $0 != " " && $0 != "\\" })
            }
        }
        guard let p = picture ?? FieldClock.shape(of: cached, time: kind == "TIME"), let body = format(picture: p) else { return nil }
        let trailing = cached.reversed().prefix { $0 == " " || $0 == "\u{A0}" }
        return body + String(trailing.reversed())
    }
}
