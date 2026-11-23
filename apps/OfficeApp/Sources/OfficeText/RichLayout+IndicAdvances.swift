// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// The width, in em, of a run of Devanagari, Bengali, Gurmukhi, Gujarati or Kannada as Excel prints it: those scripts are drawn in
/// Nirmala UI (Excel links them from Calibri, Arial and Tahoma), shaped by the font's own tables. The advances are the installed
/// font's, shaped with HarfBuzz on the print box (`IndicAdvanceData`: metrics only), scaled by the ratio the Excel print itself shows
/// (it sets Nirmala 1.2% narrower than the shaped advance; Latin in the same print is exact). A cluster the table lacks (a conjunct
/// of three consonants, a conjunct with a sign) is built the way the font builds it: the cluster up to the last letter, plus what the
/// last letter adds in the pair it forms with the one before it, which the lab check holds exact for the four scripts that ligate
/// the same way.
public enum IndicAdvances {
    /// Print width over shaped width, per face: the median over 3,006 regular and 223 bold clusters of Devanagari, Bengali, Gurmukhi and
    /// Gujarati (sd 0.006 and 0.004), comparing the Excel print of the indic1 lab (Calibri 9/12/16 text linked to Nirmala UI; cluster
    /// pitch read from the glyph origins of 12 repeats) with the HarfBuzz advances in `IndicAdvanceData`. Calibri Latin in the same
    /// print matches Calibri's own advances to 0.9996, so the narrowing belongs to Nirmala, not to the print.
    static let regularScale = 0.988
    static let boldScale = 0.990

    public static func isIndic(_ v: UInt32) -> Bool { (v >= 0x900 && v <= 0xAFF) || (v >= 0xC80 && v <= 0xCFF) }
    static func isVirama(_ v: UInt32) -> Bool { v == 0x94D || v == 0x9CD || v == 0xA4D || v == 0xACD || v == 0xCCD }
    private static func isJoiner(_ v: UInt32) -> Bool { v == 0x200C || v == 0x200D }
    private static func isMark(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory { case .spacingMark, .nonspacingMark: return true; default: return false }
    }

    private static let table: [String: (Int, Int)] = {
        var t: [String: (Int, Int)] = [:]
        for line in IndicAdvanceData.text.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 3, let r = Int(f[1]), let b = Int(f[2]) else { continue }
            t[String(f[0])] = (r, b)
        }
        return t
    }()

    /// Kannada clusters as the print sets them, in em (HarfBuzz sets Kannada conjuncts 0.12 em wider than Excel does).
    private static let printed: [String: (Int, Int)] = {
        var t: [String: (Int, Int)] = [:]
        for line in IndicPrintData.kannada.split(separator: "\n") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count == 3, let r = Int(f[1]), let b = Int(f[2]) else { continue }
            t[String(f[0])] = (r, b)
        }
        return t
    }()

    /// Advance in font units (the print's em is converted back through the face's scale so one sum serves both tables).
    private static func units(_ s: String, bold: Bool) -> Double? {
        if let p = printed[s] { return Double(bold ? p.1 : p.0) / 10000 * 2048 / (bold ? boldScale : regularScale) }
        guard let e = table[s] else { return nil }
        return Double(bold ? e.1 : e.0)
    }

    /// Advance in font units of one cluster (scalars `c`).
    private static func cluster(_ c: [Unicode.Scalar], bold: Bool) -> Double? {
        let s = String(String.UnicodeScalarView(c))
        if let u = units(s, bold: bold) { return u }
        guard c.count > 2 else { return nil }
        // A conjunct of more than two consonants: the first pair, then the rest less the letter they share.
        let vs = c.indices.filter { $0 > 0 && isVirama(c[$0].value) }
        // (Kannada stacks the later consonants under the base: the sum does not hold there, so the measured three-consonant table
        // (indic3 lab print) is used, and for a letter outside it the first pair plus the mean the third letter added there:
        // 0.488 em regular, 0.532 bold, spread about 0.08 em.)
        if c[0].value >> 7 == 0x19, c.count == 5, isVirama(c[1].value), isVirama(c[3].value),
           let x = cluster(Array(c[0...2]), bold: bold) {
            return x + (bold ? 0.5319 : 0.4882) * 2048 / (bold ? boldScale : regularScale)
        }
        if vs.count >= 2, let vi = vs.first, c[0].value >> 7 != 0x19 {
            let a = Array(c[...(vi + 1)]), rest = Array(c[(vi + 1)...])
            if let x = cluster(a, bold: bold), let y = cluster(rest, bold: bold), let z = cluster([c[vi + 1]], bold: bold) { return x + y - z }
        }
        // A trailing sign: the cluster before it, plus what the sign adds to the letter it follows.
        if let last = c.last, isMark(last), !isVirama(last.value) {
            let head = Array(c.dropLast())
            guard let base = head.last(where: { !isMark($0) }),
                  let h = cluster(head, bold: bold),
                  let withSign = cluster([base, last], bold: bold), let alone = cluster([base], bold: bold) else { return nil }
            return h + withSign - alone
        }
        return nil
    }

    /// The run's width in em, nil where it holds a character that is not one of these scripts or a cluster that cannot be built.
    public static func ems(_ run: String, bold: Bool = false) -> Double? {
        var total = 0.0, cur: [Unicode.Scalar] = []
        func flush() -> Bool {
            guard !cur.isEmpty else { return true }
            guard let u = cluster(cur, bold: bold) else { return false }
            total += u; cur = []; return true
        }
        for s in run.unicodeScalars {
            let v = s.value
            if isJoiner(v) { if cur.isEmpty { continue }; cur.append(s); continue }
            guard isIndic(v) else { return nil }
            let joins = !cur.isEmpty && (isMark(s) || isVirama(cur.last!.value) || isJoiner(cur.last!.value) && cur.count > 1 && isVirama(cur[cur.count - 2].value))
            if !joins, !flush() { return nil }
            cur.append(s)
        }
        guard flush() else { return nil }
        return total / 2048 * (bold ? boldScale : regularScale)
    }
}
