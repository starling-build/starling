// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Span": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichTextTheme {
    /// A character scale (`w:w`) as Word for Windows sets it, narrowed: in
    /// the Chinese system faces, SimSun, FangSong, KaiTi and SimHei, to a
    /// whole 128th (their half-width advance, 128 of 256 units). Lab `wsc`
    /// (Word for Windows, SimSun and FangSong at 9 to 28pt, a line of
    /// ideographs each) sets 95% as 121/128 (16pt: 15.12 apart, not 15.2),
    /// 99% as 126/128, 90% as 115 and 80% as 102, each to within 0.036pt
    /// where the plain percentage was out by up to 0.18 (28pt at 99%);
    /// 150% exact. zh-4e5fe46f's 95% FangSong cells set 9.225 apart in its
    /// print, ours 9.275, and broke a character early. A face of finer
    /// units comes out as asked: zh-7773163d's 18pt 細明體_HKSCS at 95%
    /// is 17.08 a character in its print (1024ths: 972), not 17.02.
    static func wordWidthScale(_ w: Double, wordRules: Bool, eastAsiaFamily: String?) -> Double {
        guard wordRules, wordWindowsPages, w > 0, w < 1, let f = eastAsiaFamily?.lowercased(), _wordGBSystemFace(f) else { return w }
        return (w * 128 + 1e-6).rounded(.down) / 128
    }

    /// SimSun, NSimSun, FangSong, KaiTi or SimHei by any of their names
    /// (the _GB2312 ones too, which Windows sets in them), not a foundry's
    /// face of the same style (方正, 华文).
    static func _wordGBSystemFace(_ f: String) -> Bool {
        let names = ["宋体", "simsun", "仿宋", "fangsong", "楷体", "kaiti", "黑体", "simhei"]
        let foundries = ["方正", "华文", "stsong", "stfangsong", "stkaiti", "fz"]
        return names.contains(where: { f.containsSubstring($0) }) && !foundries.contains(where: { f.containsSubstring($0) })
    }
}

extension RichLayout {

    /// Several inline pictures, each wide enough for a line of its own, in a paragraph on the line grid
    /// (Word for Windows): every picture's line is whole pitches (see `_span`).
    /// The ascent and descent, in ems, of the faces Word sets Devanagari in (their hhea, from the fonts Word's prints embed).
    /// The ascent and descent (ems) of a line at a line multiple: single spacing's baseline with the extra below it, or, under single, the line cut from the top.
    static func _multipleSplit(ascent: Double, descent: Double, multiple: Double) -> (Double, Double) {
        let line = (ascent + descent) * multiple
        return multiple >= 1 ? (ascent, line - ascent) : (line - descent, descent)
    }
    /// Yu Gothic's line as Word sets it: 1.3 x the face's win ascent + descent (0.985 + 0.302 em), split as hhea does with half the line gap on each side
    /// (hhea 0.880 / 0.222, gap 0.5): about 1.18 above and 0.49 below (lab aumsy2: 10.5 and 4.5 pt at 9 pt).
    static let _yuGothicLine: (Double, Double) = {
        let total = 1.3 * (0.985 + 0.302), above = 0.880 + 0.25, below = 0.222 + 0.25
        return (total * above / (above + below), total * below / (above + below))
    }()
    /// The share of a Thai line above the baseline in Word's own faces (hhea ascent over ascent + descent): Browallia New (and the TH Sarabun
    /// faces Word prints in it) 1770 / (1770 + 789), bold 1786 / (1786 + 885); Angsana New 0.941 / 1.351, bold 3949 / 5673. Nil for other faces.
    static func _thaiLineSplit(_ label: String?, bold: Bool) -> Double? {
        guard var name = label?.trimmingWhitespace().lowercased() else { return nil }
        while name.hasSuffix(".copywith") { name = String(name.dropLast(9)) }
        if name.hasPrefix("(") && name.hasSuffix(")") { name = String(name.dropFirst().dropLast()) }
        switch name {
        case "browallia new", "th sarabun new", "th sarabunit๙": return bold ? 1786.0 / 2671 : 1770.0 / 2559
        case "angsana new": return bold ? 3949.0 / 5673 : 0.941 / 1.351
        default: return nil
        }
    }
    /// Ascent and descent in ems of the faces a Word fallback chain sets text in, from Word's pitches in lab cm236c (12 pt, single and 1.5).
    /// Characters Word treats as East Asian text (CJK, kana, hangul, CJK punctuation and fullwidth forms, plane 2): not Arabic presentation forms nor math alphanumerics.
    static func _isEastAsianScalar(_ u: UInt32) -> Bool {
        (0x2E80 ... 0xA4CF).contains(u) || (0xAC00 ... 0xD7FF).contains(u) || (0xF900 ... 0xFAFF).contains(u) || (0xFE30 ... 0xFE4F).contains(u)
            || (0xFF00 ... 0xFFEF).contains(u) || (0x20000 ... 0x3FFFF).contains(u)
    }
    /// The face Word draws a CJK compatibility form (U+FE30-FE5F) in when MS Mincho/MS Gothic lack it, with that face's line: Yu Gothic for
    /// the vertical forms and small brackets, Microsoft JhengHei for the small comma and ideographic comma. Nil for the rest.
    static func _compatFormFallbackLine(_ u: UInt32) -> (String, (Double, Double))? {
        switch u {
        case 0xFE30, 0xFE36, 0xFE59, 0xFE5A, 0xFE5B, 0xFE5D: return ("yu", _chainFaceLines["Yu Gothic"] ?? (1.2, 0.473))
        case 0xFE50, 0xFE51: return ("jh", _chainFaceLines["Microsoft JhengHei"] ?? (1.30, 0.4308))
        default: return nil
        }
    }
    static let _chainFaceLines: [String: (Double, Double)] = [
        "Yu Gothic": (1.2, 0.473), "Microsoft JhengHei": (1.30, 0.4308),
    ]
    static let _indicLines: [String: (Double, Double)] = [
        "yu gothic": _yuGothicLine, "mangal": (2542.0 / 2048, 898.0 / 2048), "kokila": (1504.0 / 2048, 857.0 / 2048), "nirmala ui": (2210.0 / 2048, 514.0 / 2048), "vijaya": (1462.0 / 2048, 600.0 / 2048), "latha": (2048.0 / 2048, 762.0 / 2048),
        "aparajita": (1550.0 / 2048, 870.0 / 2048), "raavi": (2048.0 / 2048, 1352.0 / 2048), "shruti": (2091.0 / 2048, 1352.0 / 2048),
        "gautami": (1892.0 / 2048, 1664.0 / 2048), "utsaah": (1518.0 / 2048, 774.0 / 2048), "vrinda": (2017.0 / 2048, 778.0 / 2048), "shonar bangla": (1655.0 / 2048, 996.0 / 2048), "shonar bangla bold": (1721.0 / 2048, 978.0 / 2048),
        // (Malgun Gothic as Word sets a line of it: hhea 1.088 + 0.242 and 0.4 of gap, 1.73 em, split evenly.)
        "malgun gothic": (1.088 + 0.2, 0.242 + 0.2), "leelawadee ui": (1.08, 0.28),
        // (Myanmar Text: win ascent 2122, descent 1689 over 2048. Word sets a Myanmar-letter line at 1.861 em: dx2 2dbfc1a8, 22 pt a line at 11 pt on 259, ours 16.)
        "myanmar text": (2122.0 / 2048, 1689.0 / 2048),
        // (MV Boli, which Word draws Thaana in: win ascent 2333, descent 967 over 2048; dx2 3a5235d0.)
        "mv boli": (2333.0 / 2048, 967.0 / 2048)]
    /// Width of each face's letters against the Noto stand-in's, per script (D Devanagari, B Bengali, T Telugu, P Gurmukhi, G Gujarati):
    /// the median ratio of Word's word widths to ours over the dx2 Indic documents that print in that face (spread under 0.03 per face).
    static let _indicScale: [String: [Character: Double]] = [
        "mangal": ["D": 1.096], "utsaah": ["D": 0.80], "kokila": ["D": 0.725], "aparajita": ["D": 0.942],
        "nirmala ui": ["D": 1.082, "B": 1.075, "T": 1.16, "P": 1.097, "G": 1.147],
        "raavi": ["P": 1.084], "shruti": ["G": 1.153], "gautami": ["T": 0.964], "vrinda": ["B": 0.907], "shonar bangla": ["B": 0.716]]
    /// An empty paragraph whose mark is a complex-script one (`w:cs`) in Mangal (Kalimati, which Windows lacks, is drawn in it) is a Mangal line,
    /// 1.68 em: dx2 54d1d1d1's blank cell paragraphs, 11 pt marks, step 18.5 in Word's print against 15.9 in the stand-in's.
    @inline(never)
    func _mangalMarkLine(_ look: TextStyle, mark: CharStyle, named: RichNamedStyle?, document: RichDocument, lineSpacing: Double) -> TextStyle? {
        guard let px = look.fontSize, px > 0.5 else { return nil }
        // (A mark set in Raavi: Word draws the empty line in Raavi's own 1.66 em, 230be2f4's NoSpacing paragraphs between tables.)
        if (mark.fontFamily ?? "").trimmingWhitespace().lowercased() == "raavi", let r = Self._indicLines["raavi"] {
            let multiple = lineSpacing > 1 ? lineSpacing : 1
            return look.copyWith(ascentOverride: r.0 * multiple * px, descentOverride: r.1 * multiple * px, height: (r.0 + r.1) * multiple, leadingDistribution: .even)
        }
        // (An empty line whose mark is set in Nikosh (Windows lacks it) or Mangal is a line of Mangal, 1.68 em, and in Nirmala UI one of 1.33 em (Leelawadee UI has the same win box, 2210 + 514 of 2048: lab leela1, 13.3 pt a paragraph at 10 pt, 15.97 at 12, ours 11.7):
        // Word's print of lab siyam1, 3 empty paragraphs after each label, 16.8 / 13.3 pt apart at 10 pt against ours 12.2; and in Kokila its own 1.153 em, lab kokila1: 20.8 pt at 18 pt, where Calibri's gave 22.0.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile {
            let latin = (mark.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
            // (An empty paragraph's mark in Gautami or Shruti is that face's own line, 1.74 and 1.68 em: dx2 0977ae70's empty paragraph, Normal style at 14 pt, 48 pt below the title in Word's print, ours 40; 8b56cf6f's Shruti empty paragraphs.)
            // (A mark in a face Windows lacks that Word draws in Shonar Bangla (the usb0 rule) is Shonar's own line, 1.294 em: xb ben-bfc234's
            // empty ListParagraph lines, 27.2 pt at 14 pt on 1.5, where the Calibri stand-in gave 25.6.)
            let shonarMark = _shonarLatinRunFace(mark, named, document, "") != nil
            if shonarMark { RuleTrace.hit("word-empty-mark-in-a-missing-bengali-face-is-shonar-bangla") }
            let face = shonarMark ? "shonar bangla" : (latin == "nikosh" || latin == "mangal" ? "mangal" : (latin == "nirmala ui" || latin == "leelawadee ui" ? "nirmala ui" : (latin == "kokila" ? "kokila" : (latin == "utsaah" ? "utsaah" : (latin == "gautami" || latin == "shruti" ? latin : "")))))
            // (Kokila only where the mark has one size: hin-z20740649 sets sz 6 and szCs 13 and was 0.6 worse.)
            let kokilaOK = true
            if kokilaOK, let r = Self._indicLines[face] {
                RuleTrace.hit("word-empty-mark-in-nikosh-mangal-nirmala-is-that-faces-line")
                let multiple = lineSpacing > 1 ? lineSpacing : 1
                // (A complex-script mark (`w:cs`) takes its size from szCs, the document default's when it has none: dx2 2263e221's 7 pt (sz 14) mark with cs is an 11 pt Mangal line in Word's print.)
                var size = px
                if face == "mangal", let kept = mark.keptXML, kept.containsSubstring("<w:cs/>") || kept.containsSubstring("<w:cs "),
                   let f = mark.fontSize, f > 0.5, let z = mark.complexFontSize ?? named?.char.complexFontSize ?? _normalChar(document)?.complexFontSize, z > 0.5 {
                    size = px * z / f
                }
                return look.copyWith(ascentOverride: r.0 * multiple * size, descentOverride: r.1 * multiple * size, height: (r.0 + r.1) * multiple * size / px, leadingDistribution: .even)
            }
        }
        // (Arial Unicode MS with the Japanese charset in the font table: Word draws an empty mark in Yu Gothic, 1.67 em; lab aums2 F, 30.0 pt
        // a paragraph at 10 pt on line 259 with 12 pt after.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, document.fontCharsets["arial unicode ms"] == "80",
           (mark.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms",
           document.defaultLangXML?.containsSubstring("ta-IN") != true {
            RuleTrace.hit("word-empty-mark-in-arial-unicode-ms-is-a-yu-gothic-line")
            let multiple = lineSpacing > 1 ? lineSpacing : 1
            return look.copyWith(ascentOverride: 1.1 * multiple * px, descentOverride: 0.57 * multiple * px, height: 1.67 * multiple, leadingDistribution: .even)
        }
        // (Arial Unicode MS with the Simplified Chinese charset (86) as the East Asian face: Word draws an empty mark in YaHei, 1.715 em;
        // dx2 837ac08d's spacers, 10 pt on line 108, step 7.75 pt in Word's print = 0.45 x 17.2, where Arial's 1.15 em gave 5.2.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, document.fontCharsets["arial unicode ms"] == "86",
           (mark.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms" {
            RuleTrace.hit("word-empty-mark-in-arial-unicode-ms-gb2312-is-a-yahei-line")
            let multiple = lineSpacing > 0 ? lineSpacing : 1
            return look.copyWith(ascentOverride: 1.115 * multiple * px, descentOverride: 0.6 * multiple * px, height: 1.715 * multiple, leadingDistribution: .even)
        }
        // (A Bengali face Windows lacks whose font table names Malgun Gothic as the alternate: its empty mark is a line of Malgun, 1.73 em, lab siyam2.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile,
           _malgunAlternate(mark.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily, document),
           let r = Self._indicLines["malgun gothic"] {
            RuleTrace.hit("word-empty-mark-with-malgun-alternate-is-a-malgun-line")
            let multiple = lineSpacing > 1 ? lineSpacing : 1
            return look.copyWith(ascentOverride: r.0 * multiple * px, descentOverride: r.1 * multiple * px, height: (r.0 + r.1) * multiple, leadingDistribution: .even)
        }
        guard let kept = mark.keptXML, kept.containsSubstring("<w:cs/>") || kept.containsSubstring("<w:cs "),
              let m = Self._indicLines["mangal"] else { return nil }
        let cs = (mark.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
        guard cs == "kalimati" || cs == "mangal" else { return nil }
        var size = px
        if let z = mark.complexFontSize, let f = mark.fontSize, f > 0.5 { size = px * z / f }
        let multiple = lineSpacing > 1 ? lineSpacing : 1
        return look.copyWith(ascentOverride: m.0 * multiple * size, descentOverride: m.1 * multiple * size, height: (m.0 + m.1) * multiple * size / px, leadingDistribution: .even)
    }
    /// Devanagari, Bengali, Gurmukhi, Gujarati and Telugu.
    static let _indic = IndicScripts()
    /// Word's space advance (em) where it differs much from the stand-in's: Mangal. (Kokila 0.193 and Shonar Bangla 0.207 at their real width made dx2 hi/bn worse: their scales were fitted with the gap.)
    static let _indicSpace: [String: Double] = ["mangal": 0.5, "vrinda": 0.598, "utsaah": 0.199]
    struct IndicScripts {
        func contains(_ u: UInt32) -> Bool { (0x0900 ... 0x0AFF).contains(u) || (0x0C00 ... 0x0C7F).contains(u) }
    }
    /// Tamil (Word for Windows draws it in Nirmala UI, where the document's complex-script face is not Windows' own).
    static let _tamil: ClosedRange<UInt32> = 0x0B80 ... 0x0BFF
    /// Word draws a missing complex-script face's letters in Nirmala UI but every mark, digit and Latin letter in Mangal (a line holding one is
    /// Mangal's 1.680 em tall): Noto Sans Tamil in Tamil text; SolaimanLipi and Nikosh in Bengali text (xd 73caaeda: every line with a danda or comma
    /// steps 20.2 pt, ours 16.0).
    @inline(never) static func _markInMangal(_ face: String, _ text: Substring) -> Bool {
        switch face.trimmingWhitespace().lowercased() {
        case "noto sans tamil": return text.unicodeScalars.contains(where: { _tamil.contains($0.value) })
        case "solaimanlipi", "nikosh": return text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF })
        default: return false
        }
    }
    /// Latin text whose own (ascii) face is Noto Sans Tamil: Word draws it in Mangal too, even in a paragraph with no Tamil letter (xd c016493b's
    /// dash rule: hyphens 0.344 em, a line 1.680 em tall).
    @inline(never) static func _latinInNotoTamil(_ face: String) -> Bool { face.trimmingWhitespace().lowercased() == "noto sans tamil" }
    /// The Windows face Word draws Bengali in for a face it lacks (labs bnfield, 15 prints): Shonar Bangla when the font-table signature's usb0 has the
    /// Bengali bit (0x10000) and no other Indic bit (Devanagari 0x8000, Gurmukhi to Malayalam 0x20000-0x800000; those further bits are an extension of the
    /// lab, not proved), i.e. a face whose coverage is Bengali only; otherwise (no entry, no signature, a shared Indic signature such as Nikosh's) Nirmala UI.
    @inline(never) static func _bengaliMissingFace(_ cs: String, _ document: RichDocument) -> String {
        if ["mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla", "kalimati", "latha", "vijaya", "nirmala ui"].contains(cs) { return cs == "kalimati" ? "nirmala ui" : cs }
        guard let usb0 = document.fontUsb0[cs] else { return "nirmala ui" }
        return usb0 & 0x10000 != 0 && usb0 & 0x00FE_8000 == 0 ? "shonar bangla" : "nirmala ui"
    }

    /// A Latin-only run whose ascii and complex faces are one and the same face that Word's machine lacks and that it replaces with Shonar Bangla
    /// (the usb0 rule): Word draws that run's Latin in Shonar Bangla as well (lab bnmix2 latK). A run naming a face Windows has (Arial) keeps it.
    @inline(never) func _shonarLatinRunFace(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument, _ paragraphText: String) -> String? {
        let asc = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
        let cs = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
        guard !asc.isEmpty, asc == cs, document.fontUsb0[cs] != nil,
              Self._bengaliMissingFace(cs, document) == "shonar bangla", cs != "shonar bangla" else { return nil }
        return "shonar bangla"
    }

    /// A run with no Indic letters in it (marks, Latin, digits) is drawn in the face it NAMES: its complex-script face when it carries `w:cs`, otherwise
    /// its ascii face. When that face is one we hold line metrics for, the run takes that face's line (Latha 1.372 em, dx2 80152175; Mangal, and Kalimati
    /// which Windows lacks, in dx2 375919ba's leader runs). The script path picks a face only when the run names none we know.
    @inline(never) func _namedMetricFace(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument, _ text: Substring) -> String? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile || document.fromFileTextBox, !text.isEmpty else { return nil }
        let csFlag = run.keptXML.map { $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") } ?? false
        let cs = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
        let ascii = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
        var face = csFlag ? cs : ascii
        let isKalimati = face == "kalimati"
        if isKalimati { face = "mangal" }
        // (A text box's sub-document does not carry readFromFile; only a Kalimati run, drawn in Mangal, opts in there: dx2 d91478e3's "४. ......" list
        // in a box, Mangal's 20.16 pt pitch in Word's print where ours stood on Calibri's 14.65.)
        if !document.readFromFile, !isKalimati { return nil }
        // Only Latha is measured for letters and digits too; the other faces only for runs of marks (Kalimati/Preeti Nepali docs drop otherwise).
        // (And Mangal itself, the face the run names: 2db27e2d's "24 × 13 = (20 + 4) × ..." line, digits and signs in Mangal runs, is Mangal's
        // 18.5 pt in Word's print where ours stood 15.1 on the Latin stand-in.)
        if face != "latha", !(face == "mangal" && !isKalimati), text.unicodeScalars.contains(where: { $0.properties.isAlphabetic || (($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x966 && $0.value <= 0x96F)) && !(isKalimati && csFlag) || $0.value > 0x7E && !($0.value >= 0x966 && $0.value <= 0x96F && isKalimati && csFlag) }) { return nil }
        switch face {
        case "latha", "mangal", "vrinda", "aparajita", "raavi", "shruti", "gautami", "shonar bangla": return face
        default: return nil
        }
    }
    static func _isIndic(_ u: UInt32) -> Bool { _indic.contains(u) || _tamil.contains(u) }

    func _picturesTakeLines(_ p: RichParagraph, textWidth: Double) -> Bool {
        theme.wordRules && RichTextTheme.wordWindowsPages && p.image == nil
            && (p.inlineImages.count >= 2 || (p.inlineImages.count == 1 && p.text.unicodeScalars.contains { $0.value > 0x20 && $0.value != 0xFFFC }))
            && p.style.lineHeightPoints == nil && p.style.eastAsian["w:snapToGrid"] != "0"
            && p.inlineImages.values.allSatisfy { $0.float == nil && $0.textBox == nil && $0.baseline == nil && _px($0.width) * 2 > textWidth }
    }

    /// The paragraph's runs as a span tree. An empty paragraph lays out a
    /// single space so it has a line height; offsets are clamped to 0 by
    /// every caller.
    /// `autoSpaces` is told each character set wider by Word's automatic
    /// space after it (paragraph offset, pixels), for the line fitting.
    /// A run's `w:fitText`: the width its group is fitted to, in points, and
    /// the group's id (runs of one id are fitted together).
    static func _fitText(_ xml: String?) -> (points: Double, id: String)? {
        guard let xml else { return nil }
        for element in xml.split(separator: "<") where element.hasPrefix("w:fitText ") {
            let parts = element.split(separator: "\"", omittingEmptySubsequences: false)
            var val: Double? = nil
            var id = ""
            for (k, part) in parts.enumerated() where k + 1 < parts.count {
                if part.hasSuffix("w:val=") { val = Double(parts[k + 1]) }
                if part.hasSuffix("w:id=") { id = String(parts[k + 1]) }
            }
            if let val, val > 0 { return (val / 20, id) }
        }
        return nil
    }

    func _span(for p: RichParagraph, at index: Int?, _ document: RichDocument, textWidth: Double, lead: Double = 0, adjust: [Int: Double] = [:],
                       held: Set<Int> = [], spread: [Int: Double] = [:], fitProbe: Bool = false, autoSpaces: ((Int, Double) -> Void)? = nil)
        -> (TextSpan, [(image: ImageAttachment?, dimensions: PlaceholderDimensions)], [Int]) {
        let named = _named(p, document)
        // (Which face owns the Latin of a paragraph's Bengali/Kokila runs depends on the paragraph, not the run: found once per paragraph.
        // 0fd592a1, 5,789 runs in four paragraphs, took 262 s with it asked of every run.)
        lazy var paragraphLatinOwner: String? = {
            func complex(_ r: Run) -> String { (r.style.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() }
            if p.runs.contains(where: { complex($0) == "kokila" }) { return "kokila" }
            return p.runs.contains(where: { Self._bengaliMissingFace(complex($0), document) == "shonar bangla" }) ? "shonar bangla" : nil
        }()
        let pitch = (index.map { _offGrid($0, document) } ?? (p.style.eastAsian["w:snapToGrid"] == "0")) ? nil : _grid(index, document).pitch
        // (A hanging indent's first line starts out past the rest: the room it has for the paragraph to stay one line.)
        let mixedRubyRaise = _mixedRubyRaise(p, named: named, textWidth: textWidth + max(0, -_px(firstLineIndent(p, at: index, document))), pitch: pitch)
        // (`thaiBreaksAtSpaces`: the offsets inside a stretch of Thai with
        // no space in it that a line can hold — one longer than a line is
        // broken where the line fills, as in Word's print: zh-6a4fc013's
        // "1.กระทรวงแรงงาน…" starts its line and breaks in it. But only the
        // paragraph's first stretch: a longer one later in it is held
        // whole, so it starts the next line and is broken where that one
        // fills — Word for Windows' print of zh-6a4fc013 (windows'
        // 01QbbApP lab th, 2026-10-23) and Word for Mac's alike set
        // "ตอบ : 1." alone and the overlong stretch after it from the
        // next line's start. 61.2 -> 67.9 against word-win.)
        let thaiParagraph = p.text.unicodeScalars.contains(where: { (0x0E01 ... 0x0E5B).contains($0.value) })
        // (Word for Windows sets a line that holds runs of more than one Latin face as the tallest ascent over the deepest descent of the
        // faces' own win metrics, not as the paragraph face's line: lab tahcal, Calibri beside Tahoma at 11 pt, 13.96 pt = Tahoma's 11.01
        // above and Calibri's 2.95 below, where the Tahoma line alone is 13.28; sa2 78bf1be7.)
        let mixedLatinFaces: Bool = {
            // (Body text only: lab tahcal measured body paragraphs; sa1 6b74a903's footer, Arial beside the default face, grew 0.07 pt and pushed an empty line off page 2, 441 to 407 of 457 lines.)
            guard theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil, !document.isPageHeaderFooterPart else { return false }
            // (Latin script only: a paragraph with East Asian, Indic or Arabic text in it was not measured by lab tahcal, and Word's lines of those take their own face's height: zh-86547e97, 'VHF等终端' ran 1.27 pt off; the Persian and Hindi sets dropped.)
            if p.text.unicodeScalars.contains(where: { !($0.value < 0x250 || ($0.value >= 0x2000 && $0.value <= 0x2BFF) || ($0.value >= 0xFB00 && $0.value <= 0xFB06) || ($0.value >= 0xE000 && $0.value <= 0xF8FF) || $0.value == 0xFFFC) }) { return false }
            var names = Set<String>()
            var punctuation: [(String, Double)] = []
            var letterAscent = 0.0
            var measured = true
            var at = p.text.utf16.startIndex
            for run in p.runs {
                let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
                defer { at = end }
                guard run.style.script == .normal, (run.style.raised ?? 0) == 0, p.text.utf16[at ..< end].contains(where: { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0xC0 && $0 < 0x250) || ($0 > 0x20 && $0 < 0x7F) }) else { continue }
                let n = (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                // (A symbol face's letters draw as other glyphs: not Latin text in a second face.)
                if theme.isSymbolFace?(n) == true { continue }
                // (Faces count by what they resolve to: two names Word's machine lacks stand as the same substitute, one face, not two: sa1 e33fba63's Brandon Grotesque Light and Black.)
                let rf = theme.faceResolver?((run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace(), false)
                let key = rf.map { "\($0.family)|\($0.baseline ?? -1)|\($0.naturalHeight ?? -1)" } ?? n
                // (A run of punctuation alone in another face counts only where its ascent stands above the letters' faces: it can then
                // lift the line. Word's print, sa1 6f0b70eb: Tahoma stops beside Calibri lift the line; xd f7888b70's Arial stops (shorter
                // than Calibri's) do not.)
                if !p.text.utf16[at ..< end].contains(where: { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0xC0 && $0 < 0x250) }) {
                    punctuation.append((key, rf?.baseline ?? 0))
                } else {
                    names.insert(key); letterAscent = max(letterAscent, rf?.baseline ?? 0)
                }
                // (Every face of the paragraph must have a line Word's metrics give: a face on Word's machine only: one it lacks (Kruti Dev, Brandon Grotesque) stands as another, unknown, so the tallest-over-deepest of the rest is not the line: sa1 e33fba63, Brandon Grotesque beside Times New Roman ran 3.8 pt low.)
                if !WordWindowsFaces.names.contains(n) || theme.faceResolver?((run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace(), false)?.baseline == nil { measured = false }
            }
            for (key, ascent) in punctuation where ascent > letterAscent { names.insert(key) }
            return names.count > 1 && measured
        }()
        let thaiJoins = _thaiJoins(p, document, named: named, textWidth: textWidth, lead: lead)
        let hanJoins = theme.wordRules ? Self._hanJoins(p, document, index: index, fitChars: _hanFitChars(p, named: named, textWidth: textWidth)) : []
        if p.text.isEmpty {
            // (The mark under a nested table at half a point:
            // `RichParagraphStyle.markUnderNestedTable`.)
            var mark = p.runs[0].style
            if theme.wordRules, p.style.markUnderNestedTable { mark.fontSize = 0.5 }
            // (A raised or lowered mark is its whole size to the line: lab
            // `sup` (macOS-doc, Word for Mac) — zh-4a2ab598's empty
            // paragraph whose mark is 黑体 12pt superscript is 18.00pt tall
            // in Word, plain 18.24; ours, shrunk to 0.65, 11.75.)
            if theme.wordRules { mark.script = .normal }
            // (An empty paragraph's mark in GHEA Grapalat, which Word for Windows lacks, is the font-table alternate's
            // line, where the table names one (Franklin Gothic Medium Cond's; text lines in it are Sylfaen's: dx2 05a96a87's empty top paragraphs
            // step 15.7 at 12 pt on a 1.15 multiple, ours 18.2.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, (mark.fontFamily ?? named?.char.fontFamily)?.trimmingWhitespace().lowercased() == "ghea grapalat",
               let alt = document.fontAlternates["ghea grapalat"], !alt.isEmpty {
                mark.fontFamily = alt == "franklin gothic medium cond" ? "Franklin Gothic Medium Cond" : alt
                RuleTrace.hit("ghea-empty-mark-franklin")
            }
            var markNamed = named
            // A paragraph mark can turn off its style's hiding. Resolving
            // body runs also needs their hidden-mark joining semantics.
            if theme.wordRules, mark.off.contains(.hidden) { markNamed?.char.hidden = false }
            var look = theme.textStyle(for: mark, in: p.style, named: markNamed, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
            if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil, p.style.list == nil,
               let mangal = _mangalMarkLine(look, mark: mark, named: markNamed, document: document, lineSpacing: p.style.lineSpacing) {
                look = mangal
            }
            var emptyBidiOwnLine = false
            // (An empty paragraph that runs right to left, with no run to say so: Word sizes its mark on the complex-script face (Normal's
            // cs face), and where that face keeps its own line (David, FrankRuehl, Arabic faces Windows has) the line is that face's:
            // xd 38d880e8's empty paragraph after the header table, 2.9 pt taller in Word's print than the Latin face's.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.rightToLeft, p.style.list == nil, p.style.lineHeightPoints == nil,
               // (A mark that is not w:rtl and whose szCs differs from its sz is the Latin face at the szCs instead (rule below): lab tabline2 D,
               // an empty LTR-mark paragraph under Normal bidi, cs David, sz 11 / szCs 14, line 1.5: Word 36.72 apart = the tab-only line A, ours
               // 27.99 as the complex face's line.)
               // (And one whose mark has no w:rtl at all is the Latin face even where sz = szCs: xd 564a33e9's bare `<w:bidi/>` empty paragraph
               // is 13.3 pt Times New Roman in Word's print, ours 11.8 as David; its next empty David line (mark w:rtl) is 11.9 in both.)
               mark.rightToLeft,
               let px0 = look.fontSize, px0 > 0.5,
               let cs = mark.complexFontFamily ?? markNamed?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily,
               let f = theme.complexFace(cs, latin: mark.fontFamily ?? markNamed?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily), f.ownLineBaseline, let base = f.baseline, let tall = f.naturalHeight {
                RuleTrace.hit("word-empty-bidi-mark-is-the-complex-face-line")
                emptyBidiOwnLine = true
                // (The mark's size is its szCs, inherited when it has none, not its sz: lab emptymark2 (Word print, David 14 pt lines at 1.5, a
                // Narkisim mark with w:rtl): sz 14 with no szCs, sz 11 with no szCs and a David mark all 17.76 = the style's 12 pt cs size; szCs 11
                // 16.2; szCs 14 20.7. xd 72ea457a's empty mark (sz 14, no szCs) between its signature lines.)
                var px = px0
                // (Only at a multiple above single, which the lab measured; xd 414170f0's 2 pt marks at one sixth of a line keep their size.)
                if p.style.lineSpacing > 1, let z = mark.complexFontSize ?? markNamed?.char.complexFontSize ?? _normalChar(document)?.complexFontSize, z > 0.5 {
                    var atCs = mark
                    atCs.fontSize = z
                    atCs.complexFontSize = z
                    if let sized = theme.textStyle(for: atCs, in: p.style, named: markNamed, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch).fontSize, sized > 0.5 {
                        px = sized
                    }
                }
                let multiple = p.style.lineSpacing > 1 ? p.style.lineSpacing : 1
                look = look.copyWith(ascentOverride: base * multiple * px, descentOverride: (tall - base) * multiple * px, height: tall * multiple * px / px0, leadingDistribution: .even)
            }
            // (An empty paragraph whose mark is w:rtl in a complex face Word lacks, drawn in Arial: Arial's own line, 1.149 em, as its text
            // lines have (rule word-arial-stand-in-complex-run-keeps-arials-line): dx2 6e7a3d11's empty Times marks, cs B YAGOT, 10 pt on
            // a 0.9 multiple, are 10.35 apart in Word's print, ours 10.55, and the heading under them stood 2.5 pt low.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, !emptyBidiOwnLine, p.style.list == nil, p.style.lineHeightPoints == nil,
               mark.rightToLeft, look.ascentOverride == nil, let px = look.fontSize, px > 0.5,
               case let cs = mark.complexFontFamily ?? markNamed?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily,
               let f = theme.complexFace(cs, latin: mark.fontFamily ?? markNamed?.char.fontFamily ?? _normalChar(document)?.fontFamily, letters: true), f.arialStandIn {
                RuleTrace.hit("word-empty-mark-arial-stand-in-keeps-arials-line")
                let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                let sp = Self._multipleSplit(ascent: 0.905, descent: 1.149 - 0.905, multiple: multiple)
                look = look.copyWith(ascentOverride: px * sp.0, descentOverride: px * sp.1, height: 1.149 * multiple, leadingDistribution: .even)
            }
            // (An empty paragraph whose mark is w:rtl in a complex face Word lacks and names an alternate for (B YAGOT, alternate Times New
            // Roman), the face itself with no line of ours: the mark's line is the Latin face's at that size, as without w:rtl. dx2 6e7a3d11's
            // empty Times marks, 10 pt on a 0.9 multiple, are 10.35 apart in Word's print, ours 10.55 on the Noto stand-in's 1.172 em.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, !emptyBidiOwnLine, p.style.list == nil, p.style.lineHeightPoints == nil,
               mark.rightToLeft, look.ascentOverride == nil, let px = look.fontSize, px > 0.5,
               case let cs = mark.complexFontFamily ?? markNamed?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily,
               let f = theme.complexFace(cs, latin: mark.fontFamily ?? markNamed?.char.fontFamily ?? _normalChar(document)?.fontFamily, letters: true),
               !f.arialStandIn, !f.ownLineBaseline {
                var latinMark = mark
                latinMark.rightToLeft = false
                let latin = theme.textStyle(for: latinMark, in: p.style, named: markNamed, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let probe = TextPainter(text: TextSpan(text: "x", style: latin), textDirection: .ltr)
                probe.layout(minWidth: 0, maxWidth: 100000)
                let m = probe.computeLineMetrics().first
                probe.dispose()
                if let m, let lpx = latin.fontSize, lpx > 0.5, m.ascent + m.descent > 0.5 {
                    RuleTrace.hit("word-empty-rtl-mark-in-an-alternate-face-is-the-latin-line")
                    // (The probe's line already carries the paragraph's multiple.)
                    look = look.copyWith(ascentOverride: px * m.ascent / lpx, descentOverride: px * m.descent / lpx, height: (m.ascent + m.descent) / lpx, leadingDistribution: .even)
                }
            }
            // (An empty paragraph whose mark is set in a Windows Arabic face with a line of its own (Traditional Arabic's 1.495 em) is that
            // face's line, not the Latin stand-in's 1.22: xb urd-e54653's empty 16 pt mark between the keywords and the heading is 23.5 pt
            // tall in Word's print, ours 19.5, and every line after it stood 4 pt high.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.rightToLeft, p.style.list == nil, p.style.lineHeightPoints == nil,
               let px = look.fontSize, px > 0.5,
               let famName = mark.fontFamily ?? markNamed?.char.fontFamily ?? _normalChar(document)?.fontFamily, !mark.rightToLeft,
               case let fam = famName.trimmingWhitespace().lowercased(),
               ["traditional arabic", "sakkal majalla", "simplified arabic"].contains(fam),
               let f = theme.complexFace(famName, latin: famName), let tall = f.naturalHeight, tall > 1.3 {
                RuleTrace.hit("word-empty-mark-windows-arabic-own-line")
                let multiple = p.style.lineSpacing > 1 ? p.style.lineSpacing : 1
                let base = f.baseline ?? 0.9425
                look = look.copyWith(ascentOverride: base * multiple * px, descentOverride: (tall - base) * multiple * px, height: tall * multiple, leadingDistribution: .even)
            }
            // (An empty paragraph that runs right to left whose complex-script face has no line of ours: the mark is a Latin-face line at the
            // szCs, not the sz. xb ara-z5177238's footer, Normal sz 12 / szCs 14 under cs Simplified Arabic: Word's second footer line is Times New
            // Roman 14, 16.1 pt, ours 13.8.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.rightToLeft, p.style.list == nil, p.style.lineHeightPoints == nil,
               !emptyBidiOwnLine, !mark.rightToLeft, let f = mark.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, f > 0.5,
               let z = mark.complexFontSize ?? markNamed?.char.complexFontSize ?? _normalChar(document)?.complexFontSize, z > 0.5, abs(z - f) > 0.01,
               let px = look.fontSize, px > 0.5 {
                RuleTrace.hit("word-empty-bidi-mark-takes-szcs")
                look = look.copyWith(fontSize: px * z / f)
                // (And the Latin face it names keeps its own line where Windows has it with one: lab emptymark2 D, Narkisim named for ascii at
                // sz 14, cs David szCs 12, line 1.5: Word 17.8 = 0.988 em x 12 x 1.5, ours 21.96 on the stand-in's 1.22.)
                if let famName = mark.fontFamily ?? markNamed?.char.fontFamily, let face = theme.complexFace(famName, latin: famName),
                   face.ownLineBaseline, let tall = face.naturalHeight, tall > 0.5, let base = face.baseline {
                    let multiple = p.style.lineSpacing > 1 ? p.style.lineSpacing : 1
                    let sized = px * z / f
                    look = look.copyWith(ascentOverride: base * multiple * sized, descentOverride: (tall - base) * multiple * sized, height: tall * multiple, leadingDistribution: .even)
                }
            }
            if theme.wordRules, p.style.list != nil, lead > 0 {
                // An empty list still has a number and its suffix. Reserve
                // their width so centered/right numbers move with the line.
                // (Capped at the line: nothing follows the tab, so Word does not wrap it to a second line; xs 5de0db4c's
                // empty "2." row in an 846-twip cell is one line in Word's print, 16.5 pt, ours two.)
                let box = RichImageSpan(alignment: .baseline, baseline: .alphabetic, style: look)
                let dimensions = PlaceholderDimensions(size: Size(textWidth > 1 ? min(lead, textWidth - 0.5) : lead, 0.01), alignment: .baseline,
                                                       baseline: .alphabetic, baselineOffset: 0.01)
                // (An empty bullet row stands on its Wingdings bullet's ascent (1841/2048 em at the level's size) over the mark's own depth, as a
                // row with text does: 11pt Wingdings over 9pt Century Gothic marks make table rows 12.36pt apart in Word's print, ours 11.54
                // (sa1 5393bae9 page 4).)
                var markLook = look
                if RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, p.style.lineSpacing <= 1.001, p.style.list == .bullet,
                   !p.style.rightToLeft, _levelNumberFonts(p, document).latin?.lowercased() == "wingdings", let bulletPt = _levelNumberSize(p, document), bulletPt > 0.5 {
                    let up = _px(bulletPt) * fontScale * 1841.0 / 2048
                    let probe = TextPainter(text: TextSpan(text: "x", style: look), textDirection: .ltr)
                    probe.layout(minWidth: 0, maxWidth: 100000)
                    let m = probe.computeLineMetrics().first
                    probe.dispose()
                    if let m, let px = look.fontSize, px > 0.5, up > m.baseline + 0.01 {
                        RuleTrace.hit("word-empty-wingdings-bullet-row-stands-on-the-bullet-ascent")
                        markLook = look.copyWith(ascentOverride: up, descentOverride: m.descent, height: (up + m.descent) / px, leadingDistribution: .even)
                    }
                }
                return (TextSpan(children: [box, TextSpan(text: "\u{200B}", style: markLook)]), [(nil, dimensions)], [])
            }
            if let joiner = _tamilEmptyMarkJoiner(mark, named: markNamed, p, document, look: look, pitch: pitch, scale: scale) {
                return (TextSpan(children: [TextSpan(text: " ", style: look), TextSpan(text: "\u{2060}", style: joiner)]), [], [])
            }
            return (TextSpan(text: " ", style: look), [], [])
        }
        // Ruby wider than its base spreads the base across it, as Word's
        // distributeSpace does: a share between characters and half a
        // share before the first and after the last (61470's "東京"
        // under "とうきょう", 2.75pt between and 1.38 at either end).
        var spread = spread
        var rubyTails: [Int: Double] = [:]
        // (A vertical section's base is widened under a ruby longer than it, as a horizontal one's is — Word's gaps under
        // 入道 over にゅうどう are 11.4, 12.6, 11.4 — but the line is FITTED with the unwidened base: 934bd3e5 p9's column
        // holds 37 characters and ends past the foot. The first layout therefore sets the base unwidened and records the
        // width each character would carry (`_rubyWiden`); `_layoutParagraph` then fixes the line ends from it, sets the
        // base widened, and takes each line's overshoot off its last character, so the line ends stand.)
        let vertical = index.map { _verticalBody($0) } ?? false
        let rubyKeep = vertical ? (index.map { _rubyApply.contains($0) } ?? false ? 1.0 : 0.0) : 1.0
        var widen: [Int: Double] = [:]
        if theme.wordRules {
            for g in _rubyGroups(p) where g.to > g.from {
                let (ruby, base) = _rubyWidths(g, p, named: named, document, pitch: pitch)
                guard ruby > base + 0.01 else { continue }
                if vertical { widen[g.to - 1, default: 0] += ruby - base }
                let share = (ruby - base) * rubyKeep / Double(g.to - g.from)
                for k in g.from ..< g.to { spread[k, default: 0] += k == g.from ? share / 2 : share }
                rubyTails[g.to, default: 0] += share / 2
            }
        }
        if vertical, let ix = index, rubyKeep == 0 { _rubyWiden[ix] = widen.isEmpty ? nil : widen }
        // Where a zero-width space goes in, and what was before the
        // character at hand (across runs).
        var inserts: [Int] = []
        let koreanTokenJoins = theme.wordRules && RichTextTheme.wordWindowsPages ? Self._koreanTokenJoins(Array(p.text.utf16)) : []
        var before: Character? = nil
        var beforeBefore: Character? = nil
        var latinRunBracket = false
        var latinAfterEastAsian = false   // the ASCII run in hand opened right after East Asian text
        var dotsAttached = false   // the run of stops in hand follows a word's letter, with no space between
        // (Whether the plain spaces just before the character at hand
        // follow a no-break space: see the branch that joins them.)
        var spacesAfterNbsp = false
        // (Whether the run of ASCII letters, digits and hyphens the
        // character at hand ends has a letter in it: see the hyphen before
        // a digit, below.)
        var wordHasLetter = false
        // (Whether the last character that was not a space was an
        // ideograph, and where the paragraph's trailing spaces start: see
        // the spaces that end a paragraph after one, below.)
        var afterIdeograph = false
        let trailingSpaces = p.text.utf16.count - p.text.utf16.reversed().prefix(while: { $0 == 0x20 }).count
        let breaksAtQuotes = theme.wordRules && document.usesEastAsianLayout
        let percentStarts = _percentStarts(document)
        let traditionalLists = breaksAtQuotes && Self._traditionalChinese(document)
        // (A paragraph that turns the line-breaking rules off —
        // `w:kinsoku` 0 — may start a line with a closing mark (not end
        // one with an opening mark: Word keeps "（" with what it opens,
        // zh-c5b5087b, under kinsoku off and an en-US East Asian language
        // both); the engine allows neither, so a mark
        // that did not fit stayed on its line past the margin where Word
        // carries it over: zh-799c91cd's "各執1份為憑" and the "。" alone
        // under it, whose page 2 then ran a line long.)
        let kinsokuOff = theme.wordRules && p.style.eastAsian["w:kinsoku"] == "0"
        // (A file that names no compatibility mode and whose East Asian language is not Chinese, Japanese or
        // Korean (Pandoc's en-US): Word applies no line-start or line-end prohibitions. jpn-z21601833-4e6465's
        // print ends lines on "（" and "「", and opens them on "）".)
        let plainNoLineRules = RichTextTheme.wordWindowsPages && theme.wordRules && (document.hangsLatinStops || document.eastAsianDefaultFaceIsLatin && !document.bodyStatesLang && document.defaultLangXML == nil) && !document.eastAsianLineRules
        // (A file that names a compatibility mode, with Arial for East Asian text and no language (jpn-z18981562-5ff3d0): its print ends a line on "（" before a Latin word that does not fit.)
        let openerBeforeLatin = plainNoLineRules
        let pausesOpenLines = RichTextTheme.wordWindowsPages && theme.wordRules && (document.compatibilityMode ?? 12) >= 15 && document.lineGridPitch != nil && document.marksSitLeft && p.text.unicodeScalars.contains(where: { $0.value >= 0x3040 && $0.value <= 0x30FF })
        // (Not only under `w:useFELayout`: zh-202582e2's settings lack it,
        // and its “综合验一次” in YaHei for FangSong_GB2312 is an em a
        // quote in Word's print, where ours set YaHei's own 0.38 em and its
        // lines took a character more than Word's.)
        let fullQuotes = theme.wordRules
        var loose = _looseWordOffsets(p, document, textWidth: textWidth, named: named, pitch: pitch)
            .union(_wideWordHyphens(p, document, textWidth: textWidth, named: named, pitch: pitch))
            .union(_fittingWordHyphens(p, document, textWidth: textWidth, named: named, pitch: pitch))
        var wideStarts = _wideWordStarts(p, document, textWidth: textWidth, named: named, pitch: pitch)
        var rubyHeld = Set<Int>()
        if theme.wordRules, RichTextTheme.wordWindowsPages {
            for g in _rubyGroups(p) where g.to - g.from > 1 {
                let (_, base) = _rubyWidths(g, p, named: named, document, pitch: pitch)
                if base < textWidth - 1 { for k in g.from + 1 ..< g.to { rubyHeld.insert(k) } }
            }
        }
        let wideIndicWords = _wideIndicWords(p, document, textWidth: textWidth, named: named, pitch: pitch)
        // (A numbered paragraph's first word, wider than the line, is
        // parted where the line ends, beside its number: Word sets
        // LibreOffice's tdf134606 "a)" and "XXXXXXXXXX" in a 68pt text
        // column as "XXXXXXXXX" / "X", the number on the first line. The
        // engine, with the number's box on the line already, sends the
        // whole word down and parts it there, a line the row is taller
        // for — so it is told it may part anywhere, as for a word on a
        // line of its own.)
        if theme.wordRules, !document.usesEastAsianLayout, p.style.list != nil || _wordList(p, document) != nil,
           let first = p.text.utf16.firstIndex(where: { $0 != 0x20 && $0 != 0x09 }), first == p.text.utf16.startIndex {
            let units = Array(p.text.utf16)
            var end = 0
            while end < units.count, units[end] != 0x20, units[end] != 0x09, units[end] != 0x0A, units[end] != 0x2028 { end += 1 }
            if end >= 3, !units[..<end].contains(where: { $0 >= 0x2E80 || $0 == 0x2D }), let run = p.runs.first {
                let word = String(decoding: units[..<end], as: UTF16.self)
                let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let painter = TextPainter(text: TextSpan(text: word, style: style), textDirection: .ltr)
                painter.layout(minWidth: 0, maxWidth: 1_000_000)
                if painter.width > textWidth + 0.01 { loose.formUnion(1 ..< end) }
                painter.dispose()
            }
        }
        // (In a turned text box a first line indented past the line's
        // length holds its first character alone, the rest from the next
        // line: zh-b24b396a's "30" dimension labels — vert270 boxes 7.8pt
        // long, a 15pt first-line indent — set "3" at the indent, past the
        // box, and "0" on a line of its own in Word for Windows' print;
        // the engine kept the number whole on one line. Turned boxes only:
        // forcing the break across took zh-9e020c95 99.6 -> 19.7, where the
        // line part there anyway.)
        if theme.wordRules, let index,
           (_turnedBox && _px(firstLineIndent(p, at: index, document)) > textWidth + 0.01)
            || (index < _boxFirstLineShift.count && _boxFirstLineShift[index] > 0),
           let ch = p.text.first(where: { $0 != "\u{FFFC}" }), let at = p.text.firstIndex(of: ch) {
            let next = p.text.utf16.distance(from: p.text.utf16.startIndex, to: at) + ch.utf16.count
            if next < p.text.utf16.count { wideStarts.insert(next) }
        }
        // (A text box's paragraph whose first word is too long for its
        // indented first line, yet fits a whole line, holds its first
        // character alone on that line, the rest from the next: LibreOffice's
        // textframe-in-shape, "hello" in a 28.8pt box under Normal's 14.4pt
        // first-line indent, is "h" / "ello" in Word for Windows' print, where
        // the engine left the first line empty and set the word whole below.
        // One letter, not as many as fit: "he" would have.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, let index, _boxText, p.cell == nil,
           p.style.list == nil, p.runs.count == 1, !p.style.rightToLeft,
           p.style.alignment == .left || p.style.alignment == .justify {
            let lead = _px(firstLineIndent(p, at: index, document))
            let units = Array(p.text.utf16)
            let end = units.firstIndex(where: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x2028 || $0 >= 0x2E80 }) ?? units.count
            if lead > 0, end > 1, !units[..<end].contains(0x2D), !units[..<end].contains(0xFFFC) {
                let style = theme.textStyle(for: p.runs[0].style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                func width(_ n: Int) -> Double {
                    let painter = TextPainter(text: TextSpan(text: String(decoding: units[..<n], as: UTF16.self), style: style), textDirection: .ltr)
                    painter.layout(minWidth: 0, maxWidth: 1_000_000)
                    defer { painter.dispose() }
                    return painter.width
                }
                let whole = width(end)
                if lead + whole > textWidth + 0.01, whole <= textWidth + 0.01, lead + width(1) <= textWidth + 0.01 {
                    RuleTrace.hit("first-word-too-long-for-indented-line")
                    wideStarts.insert(units[0] >= 0xD800 && units[0] < 0xDC00 ? 2 : 1)
                }
            }
        }
        // (Before a "×" or "÷" after an ideograph or a full-width mark Word
        // may part a line, as between ideographs; the engine takes "％×1.2"
        // for one word. zh-7a16a243's "…可達560％×1.2=672％)" ends a line at
        // "560％" in Word's print; ours parted it before the "％", and the
        // lines after ran a character late.)
        if theme.wordRules, document.usesEastAsianLayout {
            let units = Array(p.text.utf16)
            for k in units.indices.dropFirst() where (units[k] == 0xD7 || units[k] == 0xF7) && units[k - 1] >= 0x2E80 { loose.insert(k) }
        }
        // (A hyphen between Hebrew letters parts a line after it in Word: the
        // engine's rule keeps a Hebrew letter and its hyphen together, and
        // lo-ccca8bf3 (tdf129659), "רחוב-" / "השמש,", ran a line late.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.text.utf16.contains(0x2D) {
            let units = Array(p.text.utf16)
            func hebrew(_ u: UInt16) -> Bool { u >= 0x05D0 && u <= 0x05EA }
            for k in units.indices.dropFirst(2) where units[k - 1] == 0x2D && hebrew(units[k - 2]) && hebrew(units[k]) { loose.insert(k) }
        }
        // (A run of underlined spaces held under `w:ulTrailSpace`, with the
        // character before it, is a word to Word: one wider than the line
        // opens a line of its own and is parted at the margin, as a long
        // Latin word is. zh-f47b8a74's "因" and 105 spaces of 8pt start a
        // line in Word's print and fill it, the rest of them opening the
        // next; held whole, ours ran past the margin.)
        if theme.wordRules, document.underlinesTrailingSpaces, !held.isEmpty {
            let units = Array(p.text.utf16)
            var at = 0
            for run in p.runs {
                defer { at += run.length }
                guard run.style.underline else { continue }
                var k = at
                while k < at + run.length {
                    guard held.contains(k) else { k += 1; continue }
                    var end = k
                    while end < at + run.length, held.contains(end) { end += 1 }
                    let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    let space = document.balancesSpaceWidth ? size / 2 : size / 4
                    // (The word runs back to where a line may part: an
                    // ideograph opens it, Latin text and full-width marks
                    // join it — page 12's "1．" and its blank keep their
                    // place at the paragraph's start in Word's print, the
                    // spaces wrapping; ours had parted "1" from "．".)
                    var from = k
                    while from > 0, units[from - 1] != 0x20, units[from - 1] != 0x0A, units[from - 1] != 0x2028 {
                        from -= 1
                        if (0x3400 ... 0x9FFF).contains(units[from]) || (0xF900 ... 0xFAFF).contains(units[from]) { break }
                    }
                    let width = Double(end - k) * space + (from < k ? size : 0)
                    if _px(width) > textWidth {
                        if from > 0, units[from - 1] != 0x0A, units[from - 1] != 0x2028 { wideStarts.insert(from) }
                        loose.formUnion((k + 1) ..< end)
                    }
                    k = end
                }
            }
        }
        // The spaces Word sets half an em wide (UTF-16 offsets): every
        // run of them but one between two Latin characters — see
        // `RichDocument.balancesSpaceWidth`.
        var wideSpaces: Set<Int> = []
        var ordinaryBalancedSpaces: Set<Int> = []
        // The spaces to set as no-break ones (`held`, by the layout: see
        // `_spacesToHold`), with a zero-width space after each run of
        // them for the break a space allows.
        // (Korean under wordWrap off, a line that fills to the margin: the space after its last word does not fit, and Word sets it at the START of the next line; _layoutParagraph records those, `_wwSpaceStarts`.)
        let koreanSpaces: Set<Int> = (index.map { _wwSpaceStarts[$0] ?? [] } ?? []).union(_wordWrapOffClosingSpaces(p, textWidth: textWidth))
        let heldSpaces = held.union(_closingSpaceHeld(p).map { [$0] } ?? []).union(koreanSpaces)
        // (Word for Windows' counted closing spaces, and the share of its
        // width each keeps — the run less half the line, at no less than
        // nothing — taken at the first of them.)
        let windowsCounted: Set<Int> = theme.wordRules && RichTextTheme.wordWindowsPages && !document.underlinesTrailingSpaces
            ? Self._underlinedClosingCounted(p).intersection(held) : []
        var windowsShare: Double? = nil
        var afterHeld = false
        var heldKind: Int? = nil   // the held spaces' style kind, for the break after them
        // (A run of plain and no-break spaces together is half an em from
        // its first plain space on, the no-break ones after it too, and
        // between Latin letters as well; no-break ones alone stay as they
        // are. Lab `nb` (Word 16.113.3, zh-8415d258's package, 15pt
        // 仿宋_GB2312): "甲" and ten no-break-and-plain pairs step 4.4 and
        // then 7.5 each; twenty no-break spaces 4.4 each; twenty plain
        // ones 7.5. zh-8415d258's signature opens with 155 of them
        // alternating, over two lines and a part in Word's print; ours
        // set them at the stand-in's 4.3 and the name rose a line.)
        // (A space in a run that says it is complex script (`w:cs`) keeps
        // its face's width: Word for Windows' print of zh-6a4fc013 sets
        // "คำถามที่ 4 ：" with Browallia's 3.5pt spaces beside the full-width
        // colon, where half an em took its line's 4.4pt and sent the
        // question's text down.)
        var complexSpaces: Set<Int> = []
        if theme.wordRules, document.balancesSpaceWidth {
            var start = 0
            for r in p.runs {
                defer { start += r.length }
                guard let kept = r.style.keptXML, kept.containsSubstring("<w:cs/>") || kept.containsSubstring("<w:cs w:val=\"1\"")
                    || kept.containsSubstring("<w:cs w:val=\"true\"") || kept.containsSubstring("<w:cs w:val=\"on\"") else { continue }
                complexSpaces.formUnion(start ..< start + r.length)
            }
        }
        if theme.wordRules, document.balancesSpaceWidth || document.usesEastAsianLayout, p.text.utf16.contains(0x20) {
            // (Spaces that end a run with a font of its own for East Asian text, before a run without one, are
            // half an em in Word for Windows even between Latin characters: zh-c2c92639's TOC "1␣␣" + "General
            // Provisions" sets them 5.5 each, where 3.2 left the text 4.5 pt left.)
            // (Nor the spaces after a number that opens the paragraph, "3␣␣General Regulations": the same TOC
            // lines, a single run with 宋体 for East Asian text, 5.5 apiece in Word's print.)
            let leadingNumber = p.text.prefix(while: { $0.isNumber || $0 == "." }).utf16.count
            func numberedHead(_ run: [Int]) -> Bool {
                RichTextTheme.wordWindowsPages && leadingNumber > 0 && run.count >= 2 && run.first == leadingNumber
                    && p.runs.first?.style.eastAsiaFontFamily != nil
            }
            var eaRunEnds: Set<Int> = []
            if RichTextTheme.wordWindowsPages {
                var st = 0
                let eaUnits = Array(p.text.utf16)
                // (The importer gives a run of circled digits the East Asian slot of its ascii face: here it still reads as ascii-only.)
                func circledOnly(_ from: Int, _ n: Int) -> Bool {
                    n > 0 && from + n <= eaUnits.count && eaUnits[from ..< from + n].allSatisfy { $0 >= 0x2460 && $0 <= 0x2469 }
                }
                for (i, r) in p.runs.enumerated() {
                    st += r.length
                    // (Not when the run's ascii face IS its East Asian face, NanumGothic for both: 397da2bb's "50␣Credit" space
                    // is 2.76 in Word's print, where the zh TOC's Times New Roman "1␣␣" beside 宋体 is half an em.)
                    if i + 1 < p.runs.count, r.style.eastAsiaFontFamily != nil, r.style.fontFamily != r.style.eastAsiaFontFamily,
                       p.runs[i + 1].style.eastAsiaFontFamily == nil || circledOnly(st, p.runs[i + 1].length) { eaRunEnds.insert(st) }
                }
            }
            var runStarts: [Int] = []
            do { var st = 0; for r in p.runs { runStarts.append(st); st += r.length } }
            var at = 0
            var run: [Int] = []
            var nbsp: Set<Int> = []
            var left: Character? = nil
            func close(_ right: Character?) {
                defer { run = []; nbsp = [] }
                // (A compat-15 file with the balance flag, no w:useFELayout and no East Asian default language sets a space beside
                // East Asian text at plain Latin width in Word for Windows: xb jpn a3f77cda's "CP19a ほげ" label space is 2.4, not half an em.)
                guard !run.isEmpty, document.balancesSpaceWidth,
                      !(RichTextTheme.wordWindowsPages && !document.usesEastAsianLayout && (document.compatibilityMode ?? 12) >= 15
                        && document.defaultLangXML?.containsSubstring("w:eastAsia=\"") != true) else { return }
                // (A manual line break is no Latin word before spaces that open the next line, as at a paragraph's start: zh-5313b71d's "…发包结果。" ⏎ "    1.发包公告…"
                // sets its four spaces half an em each from the margin in Word's print, where ours took them for the gap between
                // Latin words and lost three.)
                func latin(_ c: Character?) -> Bool { c.map { !Self.isEastAsian($0, hinted: false) && !(RichTextTheme.wordWindowsPages && ($0 == "\n" || $0 == "\u{2028}")) } ?? false }
                if nbsp.isEmpty {
                    // (Between a Latin pair of brackets they are half an em too, in Word for Windows: zh-7b125a21's
                    // fill-in "(  )" sets its two 5.25 each at 10.5pt, where 2.6 took a character more a line. Not
                    // two spaces between words, nor a page number's "—  10  —". "[  ]" likewise: xb jpn 771abc's "[  ]は訳注" in 11pt Yu Mincho, 5.5 each.)
                    // (A space that sits in a run whose East Asian face is a Latin one (docDefaults Calibri for all four slots), beside Han
                    // in the NEXT run, stays the Latin space: xb 7e68ac6f's "CP19a " + MS Mincho run sets it 2.4 at 11 pt, ours 5.5.)
                    if RichTextTheme.wordWindowsPages, nbsp.isEmpty, let lc = left, lc.isASCII, lc.isLetter || lc.isNumber, let rc = right, rc.unicodeScalars.first.map({ $0.value >= 0x4E00 && $0.value <= 0x9FFF || ($0.value >= 0x3040 && $0.value <= 0x30FF) }) == true, let o = run.last, run.count == 1,
                       let ri = runStarts.lastIndex(where: { $0 <= o }), ri + 1 < p.runs.count, p.runs[ri].style.eastAsiaFontFamily == nil || p.runs[ri].style.eastAsiaFontFamily == p.runs[ri].style.fontFamily,
                       o + 1 == (runStarts[ri] + p.runs[ri].length), p.runs[ri + 1].style.eastAsiaFontFamily != nil,
                       let ef = theme.faceResolver?(p.runs[ri].style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? "", true), !ef.isEastAsian {
                        RuleTrace.hit("latin-run-space-before-east-asian-run-stays-latin")
                        return
                    }
                    if !(latin(left) && latin(right)) || (RichTextTheme.wordWindowsPages && ((left == "(" && right == ")") || (left == "[" && right == "]"))) || eaRunEnds.contains((run.last ?? 0) + 1) || numberedHead(run) {
                        let balanced = run.filter { !complexSpaces.contains($0) }
                        wideSpaces.formUnion(balanced)
                        ordinaryBalancedSpaces.formUnion(balanced)
                    }
                } else if let first = run.first(where: { !nbsp.contains($0) }) {
                    wideSpaces.formUnion(run.filter { $0 >= first && !complexSpaces.contains($0) })
                }
            }
            for ch in p.text {
                if ch == " " { run.append(at) }
                else if ch == "\u{00A0}" { run.append(at); nbsp.insert(at) }
                else { close(ch); left = ch }
                at += ch.utf16.count
            }
            close(nil)
            // (A space in a run whose Latin face is a Korean one Windows lacks, set under no East Asian hint: Word draws and measures
            // it in Batang, half an em, like the spaces of runs that also name the face for East Asian text. xd ko 4fabe1f2 p1:
            // ".␣␣␣␣." in 12pt HY신명조 (ascii slot only) are 5.7 each in Word's print, where ours took the Latin stand-in's 3.8 and
            // fitted "한" on line 3 that Word wraps.)
            // (A neutral character takes the script of the one before it: only spaces that follow a character of such a run, or
            // another such space, count. xd ko 107500a8's "의무)" in a bold East Asian run, then a lone ascii-only " " before "①",
            // is a Latin-width 3.9 in Word's print.)
            if RichTextTheme.wordWindowsPages, document.balancesSpaceWidth {
                var st = 0
                let units = Array(p.text.utf16)
                var korean: Set<Int> = []
                for r in p.runs {
                    defer { st += r.length }
                    // (A run of circled digits keeps the ascii-only reading here though the importer gave it the East Asian slot
                    // of its ascii face: the space before 107500a8's "① " stays wide.)
                    let circledOnly = r.length > 0 && st + r.length <= units.count
                        && units[st ..< st + r.length].allSatisfy { $0 >= 0x2460 && $0 <= 0x2469 }
                    guard r.style.eastAsiaFontFamily == nil || circledOnly, r.style.fontHint != "eastAsia",
                          theme.faceResolver?(r.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true else { continue }
                    korean.formUnion(st ..< min(st + r.length, units.count))
                }
                var taken: Set<Int> = []
                // (A LONE space, with no space before or after it, stays the Latin stand-in's width: c466d30a's date ". ○○. ○○." in
                // ascii-only HY신명조 sets each space 3.7 in Word's print on a line that is not justified, where half an em, 5.6, wrapped a
                // character early. Runs of two or more spaces, 4fabe1f2's ".␣␣␣␣.", are half an em.)
                for k in korean.sorted() where units[k] == 0x20 && k > 0 && korean.contains(k - 1) && (units[k - 1] != 0x20 || taken.contains(k - 1))
                    && (units[k - 1] == 0x20 || (k + 1 < units.count && units[k + 1] == 0x20)) && !complexSpaces.contains(k) {
                    taken.insert(k); wideSpaces.insert(k)
                }
            }
        }
        /// A run's text as shown: capitals for Word's All caps and Small
        /// caps (the latter with the lowercase letters' capitals at 80%),
        /// the same number of UTF-16 units as the text, so that offsets
        /// into the painted text are offsets into the paragraph.
        func capped(_ text: Substring, _ run: CharStyle, _ style: TextStyle) -> [TextSpan] {
            let caps = run.caps || ((named?.char.caps ?? false) && !run.off.contains(.caps))
            let small = !caps && (run.smallCaps || ((named?.char.smallCaps ?? false) && !run.off.contains(.smallCaps)))
            if !caps && !small { return [TextSpan(text: String(text), style: style)] }
            var spans: [TextSpan] = []
            var piece = ""
            var pieceSmall = false
            // (Word draws the small letters at a size of its own, on a 0.12pt grid, not 0.8 of the
            // size: windows' lab smallcaps, 9pt -> 6.96, 10 -> 8.04, 11 and 11.5 -> 9.00, 12 -> 9.48,
            // 13 -> 10.56, 14 -> 11.04; elsewhere 0.8. The spaces between them are the small size too
            // (lab SMALLCAPS-CHARS: a TNR 11pt line's six spaces are 9.00, its commas the capitals' 11.04),
            // and each glyph's advance is the face's at that size.)
            let smallSize: Double = {
                let full = style.fontSize ?? 12
                guard theme.wordRules, RichTextTheme.wordWindowsPages else { return full * 0.8 }
                let pt = full / _px(1)
                let known: [Double: Double] = [9: 6.96, 9.5: 7.56, 10: 8.04, 10.5: 8.52, 11: 9.00, 11.5: 9.00, 12: 9.48, 12.5: 9.96, 13: 10.56, 14: 11.04]
                if let v = known[(pt * 100).rounded() / 100] { return v * _px(1) }
                return (pt * 0.8 / 0.12).rounded() * 0.12 * _px(1)
            }()
            // (The line stays as tall as the full size makes it: a line of small letters alone is not shorter in
            // Word's print, lo-af81b53e's pitch is 12.6 on every line.)
            let smallStyle = small ? style.copyWith(fontSize: smallSize, height: style.height.map { $0 * (style.fontSize ?? smallSize) / smallSize }) : style
            for ch in text {
                let s = String(ch)
                let up = s.uppercased()
                let lower = up != s && up.utf16.count == s.utf16.count
                let isSmall = small && (lower || (theme.wordRules && RichTextTheme.wordWindowsPages && ch == " "))
                if isSmall != pieceSmall, !piece.isEmpty {
                    spans.append(TextSpan(text: piece, style: pieceSmall ? smallStyle : style))
                    piece = ""
                }
                pieceSmall = isSmall
                piece += lower ? up : s
            }
            if !piece.isEmpty { spans.append(TextSpan(text: piece, style: pieceSmall ? smallStyle : style)) }
            return spans
        }
        /// A run's text as spans, East Asian stretches apart from the
        /// rest: each is set in its own face of the run (Word's
        /// `w:eastAsia` and `w:ascii`) at that face's line height.
        // The size that sets the lines' height, as Word has it: the
        // tallest character that is not a space — a run of 20pt spaces
        // in 18pt text adds nothing — and the paragraph mark's where
        // there are only spaces (prints of 2026-10-13: three 20pt spaces
        // under an 18pt mark are a line of 30.9pt, under a 14pt mark of
        // 23.9, and 18pt spaces under a 20pt mark of 34.2).
        // (A shade that shows: a white one paints nothing, and changes nothing.)
        let lineSize: (size: Double, blank: Bool)? = {
            // (Ideographic ones too: zh-64044a1d's form rows whose cells
            // hold "　" alone are as tall as its empty ones in Word's
            // print, one pitch of its line grid; ours, set in the East
            // Asian face, took two.)
            // (An en, an em and a four-per-em space too, in Word for Windows:
            // lab `sp`, see below.)
            let wider = theme.wordRules && RichTextTheme.wordWindowsPages
            func spaceUnit(_ u: UInt16) -> Bool { u == 0x20 || u == 0x3000 || (wider && (u == 0x2002 || u == 0x2003 || u == 0x2005)) }
            // (A paragraph of tabs alone is the mark's line too, whatever its run's size: dx2 hi 87097d3e's 8pt-mark
            // paragraph holding one 11pt tab is 9.2pt in Word's print, where ours took the run's 12.65 or, with the
            // size inherited, nothing at all, and its page's boxes stood 10pt high.)
            let tabsAlone = !p.text.isEmpty && p.text.utf16.allSatisfy { $0 == 0x09 }
            guard theme.wordRules, tabsAlone || p.text.utf16.contains(where: spaceUnit) else { return nil }
            let normal = _normalChar(document)
            func size(_ c: CharStyle?) -> Double { c?.fontSize ?? named?.char.fontSize ?? normal?.fontSize ?? theme.fontSize }
            var best: Double? = nil
            var floating = false, spaced = 0.0
            var at = p.text.utf16.startIndex
            for run in p.runs {
                let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
                // (A floating picture or box in the line takes no room of its own: a line of its anchors and spaces
                // is the mark's line, dx2 ja 4fbb6e32's last paragraph of two caption boxes and "　　" under a 24pt mark.)
                if let id = run.style.inlineImage {
                    if theme.wordRules, RichTextTheme.wordWindowsPages, let img = p.inlineImages[id], img.float != nil || img.textBox != nil { floating = true; at = end; continue }
                    return nil
                }
                // (Nor does a tab: IllustrativeCases' line of 11pt spaces
                // and tabs under an 8pt mark is the mark's line.)
                if p.text.utf16[at ..< end].contains(where: { $0 != 0x09 && !spaceUnit($0) }) { best = max(best ?? 0, size(run.style)) }
                else if end > at { spaced = max(spaced, size(run.style)) }
                at = end
            }
            // (A body line of anchors and spaces alone, not a header's or footer's: Word's print of lab anchor-space,
            // ASCII and ideographic spaces alike, is the mark's line; the Lincang footers (zh-4c4b1af8, zh-f59a76e9: anchor
            // and two spaces, mark 16pt, line grid) are taller than that and keep the normal line.)
            // (Anchors beside text in a body line: the spaces still add no height, as with no anchor. sa1 79f33282's
            // "Personal: ... Contratado" line, a wrapNone square anchored in it and 12pt spaces and tabs among 10pt text, is the
            // 10pt line in Word's print, 25.8 to the next paragraph where ours was 29.2. Not in a page header or footer: zh-4c4b1af8's
            // footer line of an anchor, 14pt text and 14pt trailing spaces under a 16pt line grid stays the normal line.)
            if floating && (document.isHeaderFooterPart || (best != nil && (document.isPageHeaderFooterPart || !(theme.wordRules && RichTextTheme.wordWindowsPages)))) { return nil }
            if let best { return (best, false) }
            // (With a floating anchor in the line, the larger of the mark's size and its spaces': dx2 ja 4fbb6e32's
            // 24pt under a 24pt mark is the mark's line; cs 2a42c845's header line of 11pt spaces under a mark of the
            // default size stays 11. The two cannot tell the spaces' size from the anchor run's.)
            // (A line of spaces and tabs in a paragraph that runs right to left, its mark not marked w:rtl, is the mark's line at the complex-script size, as an
            // empty one is: dx2 537b33ec's tab lines, sz 11 / szCs 14 under Normal's bidi, are 14 pt Times New Roman in Word's print.)
            var markSize = size(p.style.mark)
            if wider, p.style.rightToLeft, !floating, !(p.style.mark?.rightToLeft ?? false), p.style.mark?.fontSize == nil,
               let z = p.style.mark?.complexFontSize ?? named?.char.complexFontSize ?? normal?.complexFontSize, z > 0.5 { markSize = z }
            return (floating ? max(size(p.style.mark), spaced) : markSize, true)
        }()
        // (Which characters are a note's number: no automatic space stands
        // beside one, see below.)
        let raised: [Bool] = p.runs.flatMap { repeatElement($0.style.note != nil, count: $0.length) }
        // (Whether all the paragraph's text is raised by one `w:position`,
        // its lines then grown for it: `raisedLineHeight`.)
        let wholeRaised: Bool = {
            guard theme.wordRules, p.style.lineHeightPoints == nil else { return false }
            var raise: Double? = nil
            var at = p.text.utf16.startIndex
            for run in p.runs {
                let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
                if run.style.inlineImage != nil { return false }
                if p.text.utf16[at ..< end].contains(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x3000 }) {
                    let r = run.style.raised ?? named?.char.raised ?? 0
                    guard r > 0, raise == nil || raise == r else { return false }
                    raise = r
                }
                at = end
            }
            return raise != nil
        }()
        // (The face that decides whether a digit beside an East Asian character gets the automatic gap is the East Asian character's own
        // (its run's East Asian slot), not the digit run's: xd 03cd29dc's "2024" in Arial (eastAsia "Arial") before "년" in 바탕 has Word's
        // 2.2 pt gap at 9 pt, where ours read the digit run's Latin East Asian face and set none. Only Hangul, where it is measured.)
        func eaFaceOffset(_ ch: Character, _ following: Character?, _ offset: Int, _ nextAt: Int) -> Int {
            let ea = ch.unicodeScalars.first?.value ?? 0
            let hangul: (UInt32) -> Bool = { ($0 >= 0xAC00 && $0 <= 0xD7A3) || ($0 >= 0x1100 && $0 <= 0x11FF) || ($0 >= 0x3130 && $0 <= 0x318F) }
            if RichTextTheme.wordWindowsPages, ea >= 0x2E80, hangul(ea) { return offset }
            if RichTextTheme.wordWindowsPages, ea < 0x2E80, let f = following?.unicodeScalars.first?.value, hangul(f) { return nextAt }
            return ea >= 0x2E80 ? nextAt : offset
        }
        func eastAsianFaceIsLatin(atOffset o: Int) -> Bool {
            var c = 0
            for r in p.runs {
                if o >= c, o < c + r.length {
                    // (By name, as `eastAsianDefaultFaceIsLatin` reads the defaults: the resolver's stand-ins
                    // for East Asian names are not all flagged East Asian.)
                    guard let name = r.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily else { return false }
                    return ["times new roman", "times", "arial", "calibri", "cambria", "ms serif", "verdana", "tahoma", "helvetica", "courier new", "segoe ui"]
                        .contains(name.trimmingWhitespace().lowercased())
                }
                c += r.length
            }
            return false
        }
        func runHinted(atOffset o: Int) -> Bool {
            var c = 0
            for r in p.runs {
                if o >= c, o < c + r.length {
                    let face = theme.faceResolver?(r.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)
                    let high = (r.style.hAnsiFontFamily ?? named?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }
                    let hint = r.style.fontHint ?? named?.char.fontHint
                    return hint == "eastAsia" || (face?.isEastAsian ?? false) && (hint != "default" || (high?.isEastAsian ?? true))
                }
                c += r.length
            }
            return false
        }
        var splittingVariation = false
        var splittingSpaces = false
        var splittingMark = false
        var splittingGeorgian = false
        var splittingDigits = false
        var ctx = _SpanCtx(p: p, index: index, document: document, textWidth: textWidth, lead: lead, adjust: adjust, held: held, fitProbe: fitProbe, autoSpaces: autoSpaces, capped: capped, eaFaceOffset: eaFaceOffset, eastAsianFaceIsLatin: eastAsianFaceIsLatin, runHinted: runHinted, paragraphLatinOwnerFn: { paragraphLatinOwner }, afterHeld: afterHeld, afterIdeograph: afterIdeograph, before: before, beforeBefore: beforeBefore, breaksAtQuotes: breaksAtQuotes, complexSpaces: complexSpaces, dotsAttached: dotsAttached, fullQuotes: fullQuotes, hanJoins: hanJoins, heldSpaces: heldSpaces, inserts: inserts, kinsokuOff: kinsokuOff, koreanSpaces: koreanSpaces, koreanTokenJoins: koreanTokenJoins, latinAfterEastAsian: latinAfterEastAsian, latinRunBracket: latinRunBracket, lineSize: lineSize, loose: loose, mixedRubyRaise: mixedRubyRaise, named: named, openerBeforeLatin: openerBeforeLatin, ordinaryBalancedSpaces: ordinaryBalancedSpaces, pausesOpenLines: pausesOpenLines, percentStarts: percentStarts, pitch: pitch, plainNoLineRules: plainNoLineRules, raised: raised, rubyHeld: rubyHeld, rubyKeep: rubyKeep, rubyTails: rubyTails, spacesAfterNbsp: spacesAfterNbsp, splittingMark: splittingMark, splittingGeorgian: splittingGeorgian, splittingSpaces: splittingSpaces, splittingVariation: splittingVariation, spread: spread, thaiJoins: thaiJoins, thaiParagraph: thaiParagraph, traditionalLists: traditionalLists, vertical: vertical, wholeRaised: wholeRaised, wideIndicWords: wideIndicWords, widen: widen, wideSpaces: wideSpaces, wideStarts: wideStarts, windowsCounted: windowsCounted, windowsShare: windowsShare, wordHasLetter: wordHasLetter, mixedLatinFaces: mixedLatinFaces, heldKind: heldKind, splittingDigits: splittingDigits, trailingSpaces: trailingSpaces)
        // (A right-aligned paragraph's trailing spaces take room, as
        // Word's do: a word joiner after them, so the engine does not let
        // them hang past the margin. zh-c5b5087b's footer, "…人民政府发布"
        // and five spaces in a 203pt line, wraps four of them to a line
        // of their own in Word's print, and its page number stands a line
        // higher.)
        // (After an ideograph only: zh-7dc3afad's right-aligned figures,
        // "7,567 " in a table cell, stand where the space hangs past the
        // margin in Word's print — counted, 87 figures moved 3.5pt left.)
        // (Shaded spaces end a paragraph too: Word paints them, the engine drops
        // the shade of spaces that end a line — zh-1078e06f's blanks after a
        // signature line.)
                let roomyTrail = theme.wordRules && ((p.text.hasSuffix(" ") && (p.style.alignment == .right || Self.shadeShows(p.runs.last?.style.highlight))
            && p.text.last(where: { $0 != " " }).map({ Self.isEastAsian($0, hinted: false) }) == true)
            // (A right-aligned line's closing ideographic spaces are full-width glyphs, not blanks
            // that hang: they stand inside the margin. xb jpn 231fe1 p1 "申請者" + 14 of them
            // starts 170pt left of where the margin put it, as in Word's print.)
            || (p.style.alignment == .right && p.text.hasSuffix("\u{3000}") && p.text.contains(where: { $0 != "\u{3000}" && $0 != " " })))
        let checkboxes = theme.wordRules && p.runs.contains { $0.style.formBox || $0.style.loneDot }
        if lead == 0, p.runs.count == 1, p.runs[0].style.inlineImage == nil, !roomyTrail, !checkboxes {
            var spans = _spanStyled(&ctx, p.text[...], p.runs[0].style)
            // (A right-to-left paragraph of one plain run is the
            // left-to-right stretch whole: see the embeddings below.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.rightToLeft, !p.runs[0].style.rightToLeft, !(named?.char.rightToLeft ?? false) {
                let look = theme.textStyle(for: p.runs[0].style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                           gridPitch: pitch, scriptHidden: true)
                spans = [TextSpan(text: "\u{202A}", style: look)] + spans + [TextSpan(text: "\u{202C}", style: look)]
                return (TextSpan(children: spans), [], [0, p.text.utf16.count])
            }
            if spans.count == 1 { return (spans[0], [], ctx.inserts) }
            return (TextSpan(children: spans), [], ctx.inserts)
        }
        var children: [InlineSpan] = []
        var inline: [(image: ImageAttachment?, dimensions: PlaceholderDimensions)] = []
        children.reserveCapacity(p.runs.count + 1)
        @inline(never) func _sblk5() {
        if lead != 0 {
            // The first line's indent is a box of that width before the
            // text — of less than no width for a hanging one, which sets
            // the line out to the left and leaves it that much longer.
            // It is one more character in the painter's text than in the
            // paragraph's: `_lead` says so to every offset that crosses.
            // (A floating object's anchor opening the paragraph is no text: the label
            // is set against the first run of text — lo-eb12e7d4's "4.2", a picture
            // wrapped top and bottom in its first run, stood 5.1pt low of Word's.)
            let anchorFirst = theme.wordRules && RichTextTheme.wordWindowsPages
                && p.runs[0].style.inlineImage.map({ p.inlineImages[$0]?.float != nil }) == true
            let firstLook: CharStyle = anchorFirst ? (_firstTextRun(p)?.style ?? p.runs[0].style) : p.runs[0].style
            var leadChar = firstLook
            // (A list paragraph's first line is as tall as its number's
            // face asks: Word sets the bullet in its level's font, and
            // form_footnotes' Symbol bullets make its 10pt lines 12.24
            // in Word's print where the text's face gives 11.5 — so the
            // box before the text takes the level's face.)
            var symbolLevel = false
            if theme.wordRules, p.style.list != nil,
               let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }),
               let r = xml.rangeOfSubstring("w:ascii=\"") ?? xml.rangeOfSubstring("w:hAnsi=\"") {
                let family = String(xml[r.upperBound...].prefix { $0 != "\"" })
                // (Only the symbol faces, whose lines differ from any
                // text face's: a zero-width space before every list
                // paragraph's text, in whatever face, cost zh-90e0cea8
                // 20 points — the first character's place is read by
                // more than the offset map.)
                if ["symbol", "wingdings", "wingdings 2", "wingdings 3"].contains(family.lowercased()) {
                    // (Indic text keeps its own face in the box: Symbol's line stacks 1.6pt on
                    // Kokila's, 24.8 against Word's 23.2 — hin-z18479909-61195a.)
                    if !p.text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) { leadChar.fontFamily = family }
                    // (At the level's own size where it says one: delins's
                    // 10pt Symbol bullets under 12pt Times make a 12.25pt
                    // line of the face, under the text's 13.8 — Word's line
                    // is the text's; at the text's size it was 14.7.)
                    if let size = _levelNumberSize(p, document) { leadChar.fontSize = size }
                    // (Smaller too: a mark of no size under a style smaller than the text is the style's, lab bullet-mark2, 9pt Symbol bullets over 12pt text
                    // step 19.8 pt in Word's print, 6 before and the text's 13.8, where the bullet at the text's size made 20.66.)
                    else if _markerChar(p, document).fontSize == nil, p.style.mark != nil, let ss = (_named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize), abs(ss - (leadChar.fontSize ?? .infinity)) > 0.01 { leadChar.fontSize = ss }
                    symbolLevel = true
                }
            }
            // (A number set larger than the text — its level's own size —
            // makes the first line as tall above its baseline as a line
            // of that size, and no deeper than the text's below it.
            // bug65649's "3.1.1." in 14pt over 12pt text: its first lines
            // stand 15.72pt under the line above in Word's print, the
            // next 13.8 under them, as under any line of the text; a
            // whole 14pt line was 0.45pt deeper, and every numbered
            // paragraph set what followed that much lower.)
            var rise: Double? = nil
            if theme.wordRules, let size = _levelNumberSize(p, document) ?? (p.style.list != nil ? _markSize(p, document) : nil),
               size > (firstLook.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) + 0.01 {
                leadChar.fontSize = size
                // (On a line grid the whole line of that size, as before:
                // the grid sets lines by pitches, and zh-64044a1d's "圖1"
                // captions, a 12pt number over 11pt text, stood 6pt low
                // with the number's height alone.)
                if !symbolLevel, pitch != nil {
                    symbolLevel = true
                } else if !symbolLevel {
                    let probe = TextPainter(text: TextSpan(text: "\u{200B}", style: theme.textStyle(for: leadChar, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)),
                                            textDirection: .ltr)
                    probe.layout(minWidth: 0, maxWidth: .infinity)
                    rise = probe.computeDistanceToActualBaseline(.alphabetic)
                    probe.dispose()
                }
            }
            // (A number in a face of its own, at the text's size and taller above its baseline
            // than the text: the first line stands as high as the number does, and no deeper
            // than the text. lo-be1a88f4, Arial Black 11pt numbers over Consolas 11pt: Word's
            // lines are 15.9pt apart, ours 13.9 — the number's ascent 12.1 over the text's 10.1.)
            if rise == nil, !symbolLevel, pitch == nil, theme.wordRules, RichTextTheme.wordWindowsPages, p.style.list != nil,
               let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }),
               let r = xml.rangeOfSubstring("w:ascii=\"") {
                var family = String(xml[r.upperBound...].prefix { $0 != "\"" })
                // (A dingbat bullet (U+2700-27BF) in a Noto Sans Symbols face, which Windows lacks: Word draws it in Segoe UI Symbol, ascent 1.0791 em
                // where Arial's is 0.905: 9pt ✔ bullets over Arial at 1.5, lines 16.8 apart where plain ones are 15.48 (sa2 5cf365e6).)
                if family.lowercased().hasPrefix("noto sans symbols"),
                   let u = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)] })?.text.unicodeScalars.first?.value,
                   (0x2700 ... 0x27BF).contains(u) {
                    RuleTrace.hit("word-noto-symbols-dingbat-bullet-is-segoe-ui-symbol")
                    family = "Segoe UI Symbol"
                }
                // (Real East Asian letters only: Latin accents such as the á of "estándar" are not, and sa1 508b647e's Tahoma dash bullets over Spanish text were left unlifted by hinted: true.)
                if !family.isEmpty, !p.text.unicodeScalars.contains(where: { Self.isEastAsian(Character($0), hinted: false) }) {
                    // (Its face's own ascent, not a line's: the line's carries the spacing multiple.)
                    let textFace = firstLook.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily
                    let size = _px(firstLook.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * fontScale
                    // (The number's ascent over the text's is measured at the number's OWN size when it sets one, smaller or not: lab lblcal1 G,
                    // a 9pt Calibri number over 11pt Times stands level with a plain item in Word's print.)
                    let numberSize = _levelNumberSize(p, document).map { _px($0) * fontScale } ?? size
                    if let numberBase = theme.faceResolver?(family, false)?.baseline, let textBase = theme.faceResolver?(textFace, false)?.baseline,
                       numberBase * numberSize - textBase * size > 0.5 {
                        RuleTrace.hit("word-number-face-taller-above-the-baseline-lifts-the-first-line")
                        rise = numberBase * numberSize
                    }
                }
            }
            // (A raised or lowered text run under a larger number, in Word for Windows: the raise comes OFF the number's rise. Lab
            // pitch1/pitch2 (amd-10): 9.5pt text under a 10.5pt number stands 11.88 apart, 11.40 raised 0.5pt, 10.92 raised 1pt or more
            // (the text's own line), 12.84 lowered 1pt; under a 12pt number 12.75, 12.24 for 0.5pt, 1pt. Ours added the raise to the
            // number's rise, 12.86 at 1pt, and took no account of a lowering.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, let up = rise, pitch == nil,
               let r = p.runs.first(where: { $0.length > 0 })?.style.raised, abs(r) > 0.01 {
                RuleTrace.hit("word-list-number-rise-less-the-text-raise")
                let rpx = r * _px(1) * fontScale
                rise = up - max(0, rpx) - rpx
            }
            let style = theme.textStyle(for: leadChar, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
            children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
            inline.append((nil, PlaceholderDimensions(size: Size(lead, 0.01), alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: 0.01)))
            // (A box sets no line height of its own: the level's face
            // reaches the line through a zero-width space in it, one
            // more character before the text.)
            var dingStyle: TextStyle?
            // (A dingbat bullet (✔ U+2714) in a Noto Sans Symbols face, drawn in Segoe UI Symbol (above), at a line multiple: Word's row is the
            // text's own row at the multiple, taller by what Segoe's ascent stands over the text's single-spaced ascent, none of it below:
            // 9pt Arial at 1.5, bullet lines 16.8 apart where a plain one is 15.48 (sa2 5cf365e6).)
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil,
               p.style.lineSpacing > 1.001, p.style.list == .bullet,
               (_levelNumberFonts(p, document).latin ?? "").lowercased().hasPrefix("noto sans symbols"),
               let lvl = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)] }),
               let u = lvl.text.unicodeScalars.first?.value, (0x2700 ... 0x27BF).contains(u),
               let leadPx = style.fontSize, leadPx > 0.5, !p.style.rightToLeft {
                let bulletPt = _levelNumberSize(p, document) ?? p.style.mark?.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize
                let px = bulletPt != nil && bulletPt! > 0.5 ? _px(bulletPt!) * fontScale : leadPx
                let probe = TextPainter(text: TextSpan(text: "x", style: theme.textStyle(for: firstLook, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)), textDirection: .ltr)
                probe.layout(minWidth: 0, maxWidth: 100000)
                let m = probe.computeLineMetrics().first
                probe.dispose()
                if let m {
                    let own = m.baseline / p.style.lineSpacing
                    let up = 2210.0 / 2048 * px
                    if up > own + 0.01 {
                        RuleTrace.hit("word-noto-symbols-dingbat-bullet-is-segoe-ui-symbol-ascent-at-a-multiple")
                        let above = m.baseline + (up - own), below = m.height - m.baseline
                        dingStyle = style.copyWith(ascentOverride: above, descentOverride: below, height: (above + below) / leadPx, leadingDistribution: .even)
                    }
                }
            }
            if symbolLevel {
                var markStyle = style
                var symStands = false
                // (A Shonar Bangla paragraph's bullet stacks as Latin text does there, the Latin face's ascent over Shonar's split below the baseline,
                // not the face's whole line at the multiple: bfc234's Symbol bullets stand 30pt apart in Word's print, ours 35.9.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil,
                   let leadFace = p.runs.lazy.compactMap({ r -> String? in
                       let cs = (r.style.complexFontFamily ?? named?.char.complexFontFamily ?? self._normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                       return cs == "kokila" ? "kokila" : (Self._bengaliMissingFace(cs, document) == "shonar bangla" ? "shonar bangla" : nil) }).first,
                   p.text.unicodeScalars.contains(where: { Self._indic.contains($0.value) }),
                   let m = Self._indicLines[leadFace], let size = style.fontSize, size > 0.5,
                   let pt = leadChar.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, pt > 0.5,
                   let base = theme.baseline(for: leadChar, in: { var single = p.style; single.lineSpacing = 1; return single }(), named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) {
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    let split = Self._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple)
                    var above = max(split.0 * size, base / pt * size)
                    // (Shonar Bangla: Word stands the row on the level's symbol face, drawn at the box's size: Symbol's 1.004 em over the usual split below, 29.9 pt
                    // for the 14pt rows of xb bfc234 where the text face's ascent gave 29.3; the wrapped line below the row stays Shonar's 27.2.)
                    if leadFace == "shonar bangla", multiple > 1,
                       let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }),
                       let r = xml.rangeOfSubstring("w:ascii=\"") ?? xml.rangeOfSubstring("w:hAnsi=\""),
                       case let symFace = String(xml[r.upperBound...].prefix { $0 != "\"" }).lowercased(), symFace == "symbol",
                       let symBase = theme.faceResolver?(symFace, false)?.baseline, symBase * size > above + 0.001 {
                        RuleTrace.hit("word-shonar-symbol-bullet-row-stands-on-the-symbol-ascent")
                        above = symBase * size
                    }
                    markStyle = style.copyWith(ascentOverride: above, descentOverride: split.1 * size, height: (above + split.1 * size) / size, leadingDistribution: .even)
                }
                // (A Symbol bullet in a TH SarabunPSK Thai paragraph, single spacing: Word stands the row on Symbol's ascent (1.004 em at the bullet's size)
                // over the face's own 0.463 em below the baseline, so bullet rows are 1.467 em apart (20.5 pt at 14 pt, 23.4 at 16 pt) where the wrapped
                // line under one stays 1.314 em; ours were 18.4 and 20.9 (xd eb52ce9bb9, bullets in a table and in the body).)
                if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil, p.style.lineSpacing <= 1.001,
                   p.text.unicodeScalars.contains(where: { $0.value >= 0x0E00 && $0.value <= 0x0E7F }), let thaiRun = p.runs.first?.style,
                   (thaiRun.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "th sarabunpsk",
                   let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }),
                   let r = xml.rangeOfSubstring("w:ascii=\"") ?? xml.rangeOfSubstring("w:hAnsi=\""),
                   String(xml[r.upperBound...].prefix { $0 != "\"" }).lowercased() == "symbol",
                   let symBase = theme.faceResolver?("symbol", false)?.baseline, let bulletSize = style.fontSize, bulletSize > 0.5,
                   let textPt = thaiRun.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, textPt > 0.5 {
                    let textSize = _px(textPt) * fontScale
                    let above = symBase * bulletSize, below = 0.463 * textSize
                    RuleTrace.hit("word-symbol-bullet-row-in-th-sarabunpsk-stands-on-the-symbol-ascent")
                    markStyle = style.copyWith(ascentOverride: above, descentOverride: below, height: (above + below) / bulletSize, leadingDistribution: .even)
                }
                // (A Symbol bullet over Latin text at single spacing, drawn larger than the text: as the Wingdings ones below, Word's print stands
                // the first line on the bullet's ascent (Symbol's 1.005 em at the box's size) over the text's own depth, the bullet's adds
                // nothing: 12pt bold Symbol dashes over Arial 11, items 14.4pt apart where the bullet's whole line made them 14.8 (xb fra-g111-8b0e29).)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, p.style.lineSpacing <= 1.001,
                   p.style.list == .bullet, _levelNumberFonts(p, document).latin?.lowercased() == "symbol", let px = style.fontSize, px > 0.5,
                   !p.text.unicodeScalars.contains(where: { $0.value >= 0x590 && $0.value <= 0x8FF }),
                   let symBase = theme.faceResolver?("symbol", false)?.baseline {
                    let probe = TextPainter(text: TextSpan(text: "x", style: theme.textStyle(for: firstLook, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)), textDirection: .ltr)
                    probe.layout(minWidth: 0, maxWidth: 100000)
                    let m = probe.computeLineMetrics().first
                    probe.dispose()
                    if let m, symBase * px > m.baseline + 0.01 {
                        RuleTrace.hit("word-symbol-bullet-stands-the-first-line-on-its-ascent")
                        symStands = true
                        // (Garamond's stand-in is shallower below the baseline than the real face (0.2632 em): the line's foot is the real one, 15.2 pt for a 12pt bullet over 12pt text; Word's 15.0 in dx2 8c6b47a9.)
                        var below = m.descent
                        if (firstLook.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "garamond",
                           let textPt = firstLook.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, textPt > 0.5 {
                            below = max(below, 0.2632 * _px(textPt) * fontScale)
                        }
                        markStyle = style.copyWith(ascentOverride: symBase * px, descentOverride: below, height: (symBase * px + below) / px, leadingDistribution: .even)
                    }
                }
                // (A Wingdings bullet over Latin text at a line multiple: Word's print stands the first line on the BULLET's ascent
                // and leaves under it what the text's own line has under ITS baseline, the multiple's extra included. 11pt Calibri at
                // 1.15 under a 16pt bold Wingdings bullet: items 19.35pt apart, where the bullet's whole line at the multiple was 20.4
                // (dx2 it df984aa4).)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil,
                   p.style.lineSpacing > 1.001, leadChar.fontFamily?.lowercased() == "wingdings" || leadChar.fontFamily?.lowercased() == "symbol",
                   let leadPx = style.fontSize, leadPx > 0.5,
                   leadChar.fontFamily?.lowercased() == "symbol" || (!p.style.rightToLeft && !p.text.unicodeScalars.contains(where: { (0x590...0x8FF).contains($0.value) })) {
                    let bulletPt = _levelNumberSize(p, document) ?? p.style.mark?.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize
                    let px = leadChar.fontFamily?.lowercased() == "symbol" && bulletPt != nil && bulletPt! > 0.5 ? _px(bulletPt!) * fontScale : leadPx
                    let probe = TextPainter(text: TextSpan(text: "x", style: theme.textStyle(for: firstLook, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)), textDirection: .ltr)
                    probe.layout(minWidth: 0, maxWidth: 100000)
                    let m = probe.computeLineMetrics().first
                    probe.dispose()
                    if let m {
                        let multiple = p.style.lineSpacing
                        let single = m.height / multiple
                        let own = m.baseline / multiple
                        let isSymbol = leadChar.fontFamily?.lowercased() == "symbol"
                        let up = isSymbol ? (theme.faceResolver?("symbol", false)?.baseline ?? 0) * px : px * 1841.0 / 2048
                        // (Only when the bullet stands higher than the text's own ascent: where it does not, the row is the text's, and rebuilding it here
                        // moved where the multiple's extra falls: a 14pt Symbol bullet over bold 14pt Kalpurush at 1.5, rows 5 pt too tall, xb ben-z17281487 page 9.)
                        if up > own + 0.01 {
                            if isSymbol {
                                // (A Symbol bullet at a line multiple: Word's row is the text's own row at the multiple, taller only by what the bullet's
                                // ascent stands over the text's single-spaced ascent, none of it below: 12pt Symbol over Arial 12 at 1.08, rows 16.68 apart where a
                                // wrapped text line is 15.84; an 11pt bullet stands no higher than the text, so its rows stay 15.84 (lab bl4490).)
                                RuleTrace.hit("word-symbol-bullet-at-a-multiple-adds-its-ascent-over-the-text-above")
                                let above = m.baseline + max(0, up - own), below = m.height - m.baseline
                                markStyle = style.copyWith(ascentOverride: above, descentOverride: below, height: (above + below) / leadPx, leadingDistribution: .even)
                            } else {
                            let down = single - own + m.height - single
                            RuleTrace.hit("word-wingdings-bullet-stands-the-first-line-on-its-ascent")
                            markStyle = style.copyWith(ascentOverride: up, descentOverride: down, height: (up + down) / px)
                            }
                        }
                    }
                }
                // (A Wingdings bullet over Latin text at single spacing, drawn larger than the text: as the Symbol ones above, the first line
                // stands on the bullet's ascent (1841/2048 em at the box's size) over the text's own depth. 12pt Wingdings over 10pt Century Gothic:
                // items 12.96pt apart in Word's print, ours 13.32 with the bullet's whole line (sa1 5393bae9).)
                if !symStands, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, p.style.lineSpacing <= 1.001,
                   p.style.list == .bullet, leadChar.fontFamily?.lowercased() == "wingdings", let px = style.fontSize, px > 0.5,
                   !p.style.rightToLeft, !p.text.unicodeScalars.contains(where: { $0.value >= 0x590 && $0.value <= 0x8FF }),
                   !p.text.unicodeScalars.contains(where: { Self._isIndic($0.value) || ($0.value >= 0x2E80 && $0.value <= 0xFFEF) }) {
                    let probe = TextPainter(text: TextSpan(text: "x", style: theme.textStyle(for: firstLook, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)), textDirection: .ltr)
                    probe.layout(minWidth: 0, maxWidth: 100000)
                    let m = probe.computeLineMetrics().first
                    probe.dispose()
                    let up = px * 1841.0 / 2048
                    if let m, up > m.baseline + 0.01 {
                        RuleTrace.hit("word-wingdings-bullet-at-single-stands-the-first-line-on-its-ascent")
                        symStands = true
                        markStyle = style.copyWith(ascentOverride: up, descentOverride: m.descent, height: (up + m.descent) / px, leadingDistribution: .even)
                    }
                }
                // A Wingdings bullet over East Asian text at single spacing: Word's print stands the first line on the taller of the bullet's
                // ascent (1841/2048 em at the box's size) and the text face's own, over the deeper of the two below. Malgun Gothic's line is 1.73 em,
                // 1.288 above and 0.442 below, so 14pt boxes over 9pt rows stand 12.58 over 3.98: rows 16.56 apart where the text's line alone is 15.56
                // (xd b88f2314 p2 checkboxes, Word 16.56 against our 15.56).)
                if let px = style.fontSize, px > 0.5, leadChar.fontFamily?.lowercased() == "wingdings", _wingdingsOverMalgunText(p, document),
                   let ml = Self._indicLines["malgun gothic"],
                   let textPt = p.runs.first?.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, textPt > 0.5 {
                    let textSize = _px(textPt) * fontScale
                    let total = max(px * 1841.0 / 2048, ml.0 * textSize) + max(px * 432.0 / 2048, ml.1 * textSize)
                    // (The line's extra height is above the baseline: the text's own depth stays under it, the next line standing 15.56 on, not 16.56
                    // (xd b88f2314 p2 cell paragraphs, Word 15.5-15.6 line to line, 16.56 paragraph to paragraph).)
                    let down = max(px * 432.0 / 2048, (ml.1 - 0.1) * textSize), up = total - down
                    RuleTrace.hit("word-wingdings-bullet-over-malgun-text-stands-on-the-taller-ascent")
                    symStands = true
                    markStyle = style.copyWith(ascentOverride: up, descentOverride: down, height: (up + down) / px, leadingDistribution: .even)
                }
                // (A Wingdings 2 bullet, the empty box: Word's print stands the line on the box's ascent less its lowering (or the row's own text
                // ascent when that is taller), over the row's own text depth only: the box's depth, lowered or not, adds nothing. Lab bea-lab
                // (22pt boxes: rows 21.06 apart unlowered, 18.06 lowered 3pt, 15.07 lowered 6pt; 12pt boxes lowered 3pt are the text row alone);
                // dx2 bea98273: 22pt boxes lowered 3pt over 10.5pt Nirmala rows 18.3pt apart, where the box's whole line made them 26.9.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil,
                   _levelNumberFonts(p, document).latin?.lowercased() == "wingdings 2", let px = style.fontSize, px > 0.5,
                   let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }) {
                    var half = 0.0
                    if let pr = xml.rangeOfSubstring("<w:position w:val=\"") {
                        half = Double(xml[pr.upperBound...].prefix { $0 != "\"" }) ?? 0
                    }
                    let ownStyle = theme.textStyle(for: firstLook, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                    let probe = TextPainter(text: TextSpan(text: String(p.text.first(where: { $0 != " " }) ?? "x"), style: ownStyle), textDirection: .ltr)
                    probe.layout(minWidth: 0, maxWidth: 100000)
                    let m = probe.computeLineMetrics().first
                    probe.dispose()
                    if half <= 0, let m {
                        let lowering = -half / 2 * theme.pixelsPerPoint * scale
                        var textUp = m.baseline, textDown = m.height - m.baseline
                        // (The probe is the stand-in face's line; a row in Nirmala UI is Nirmala UI's, 2210 over 514 of 2048: dx2 bea98273's Bengali rows pitched 21.2 and 19.5
                        // on the stand-in's 3.95pt depth, Word 18.2 and 18.4.)
                        if let own = ownStyle.fontSize, (firstLook.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui"),
                           p.text.unicodeScalars.first(where: { $0.value != 0x20 }).map({ Self._isIndic($0.value) }) == true, let nl = Self._indicLines["nirmala ui"] {
                            textUp = nl.0 * own; textDown = nl.1 * own
                        }
                        let up = max(px * 1727.0 / 2048 - lowering, textUp)
                        let down = textDown
                        RuleTrace.hit("word-wingdings2-lowered-bullet-stands-the-line-on-its-ascent-less-the-lowering")
                        markStyle = style.copyWith(ascentOverride: up, descentOverride: down, height: (up + down) / px)
                    }
                }
                // (The box carries the face's whole 1.225 em line as its height too; it takes the same ascent over the text's descent.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, markStyle.ascentOverride != nil, style.ascentOverride == nil,
                   symStands, p.style.lineSpacing <= 1.001, let lastSpan = children.last, !(lastSpan is TextSpan) {
                    children[children.count - 1] = RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: markStyle)
                }
                children.append(TextSpan(text: "\u{200B}", style: markStyle))
                ctx.inserts.append(0)
            } else if let dingStyle {
                children.append(TextSpan(text: "\u{200B}", style: dingStyle))
                ctx.inserts.append(0)
            } else if let rise {
                // (The number's height above the line, as a box on the
                // baseline that reaches no lower: see `_risesForNumber`.)
                children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
                inline.append((nil, PlaceholderDimensions(size: Size(0, rise), alignment: PlaceholderAlignment.baseline,
                                                          baseline: TextBaseline.alphabetic, baselineOffset: rise)))
                ctx.inserts.append(0)
            }
        }
        }
        _sblk5()
        var pos = 0
        let utf16 = p.text.utf16
        // On a line of pictures, tabs are horizontal gaps, not text with
        // an ascent/descent or letter spacing. Letter-spacing a tab after
        // the first placeholder shifts the entire line by half that gap
        // in the engine; it also adds text descent below the pictures.
        let pictureTabs = theme.wordRules && !adjust.isEmpty && Self._picturesAndTabs(p)
        // (In a right-to-left paragraph each run takes the direction its own
        // `w:rtl` gives it: a stretch of runs without it is laid out left to
        // right as one piece, set among the rest as a whole. Word for
        // Windows, lab rtl1: "Right and RTL in M$" keeps its "$" after the
        // M, a Hebrew word and Latin text in one plain run stand in the order
        // they are written, left to right, and a "$" in a run of its own
        // marked `w:rtl` stands at the far left. A left-to-right embedding
        // round each such stretch does that.)
        let embeds = theme.wordRules && RichTextTheme.wordWindowsPages && p.style.rightToLeft
        var isolated = false
        // (In a left-to-right paragraph two or more adjacent runs marked `w:rtl` are one right-to-left embedding, reversed as a
        // unit: dx2 9baed400 p32, "१०" + "," + "०००" with the last two marked prints "१००००," in Word's print, not "१०,०००".)
        let rtlStretch = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile && !p.style.rightToLeft
        let flatRuns = p.runs.filter { $0.length > 0 }
        func _isRtlRun(_ r: Run) -> Bool { r.style.inlineImage == nil && (r.style.rightToLeft || (named?.char.rightToLeft ?? false)) }
        var runNumber = -1
        var inStretch = false
        @inline(never) func _sblk6() {
        for run in p.runs where run.length > 0 {
            let a = utf16.index(utf16.startIndex, offsetBy: pos)
            let b = utf16.index(a, offsetBy: run.length)
            pos += run.length
            runNumber += 1
            if rtlStretch {
                let here = _isRtlRun(run)
                var opens = here && !inStretch && runNumber + 1 < flatRuns.count && _isRtlRun(flatRuns[runNumber + 1])
                // (Not where the stretch holds Hebrew or Arabic-script letters: those are set by their own direction already, and
                // dx2 80c27832's Urdu lines lose their match when embedded.)
                if opens {
                    var k = runNumber, from = pos - run.length
                    while k < flatRuns.count, _isRtlRun(flatRuns[k]) {
                        let lo = utf16.index(utf16.startIndex, offsetBy: from)
                        let hi = utf16.index(lo, offsetBy: flatRuns[k].length)
                        if p.text[lo..<hi].unicodeScalars.contains(where: { (0x590...0x8FF).contains($0.value) || (0xFB1D...0xFEFF).contains($0.value) }) { opens = false; break }
                        from += flatRuns[k].length; k += 1
                    }
                }
                if opens || (inStretch && !here) {
                    let look = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                               gridPitch: pitch, scriptHidden: true)
                    children.append(TextSpan(text: opens ? "\u{202B}" : "\u{202C}", style: look))
                    ctx.inserts.append(pos - run.length)
                    inStretch = opens
                    if opens { RuleTrace.hit("word-adjacent-rtl-runs-in-a-ltr-paragraph-are-one-embedding") }
                }
            }
            if embeds, run.style.inlineImage == nil {
                let plain = !(run.style.rightToLeft || (named?.char.rightToLeft ?? false))
                if plain != isolated {
                    let look = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                               gridPitch: pitch, scriptHidden: true)
                    children.append(TextSpan(text: plain ? "\u{202A}" : "\u{202C}", style: look))
                    ctx.inserts.append(pos - run.length)
                    isolated = plain
                }
            }
            if let id = run.style.inlineImage, let image = p.inlineImages[id] {
                let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                // A picture in the line, sitting on the baseline as Word
                // sets it; shrunk to the column when wider.
                var w = _px(image.width), h = _px(image.height)
                if w > textWidth, !theme.wordRules { h *= textWidth / w; w = textWidth }
                // (Or laid out again to the line's width, where it can be:
                // `objectFitter`.)
                var fittedBaseline: Double? = nil
                if theme.wordRules, image.float == nil, image.data.isEmpty, w > textWidth + 0.5, textWidth > 0,
                   let fit = Self.objectFitter?(image, textWidth / (theme.pixelsPerPoint * scale)) {
                    w = _px(fit.width); h = _px(fit.height); fittedBaseline = fit.baseline
                }
                // (A box in the line fitted to its text's height: that tall.)
                if theme.wordRules, image.float == nil, let box = image.textBox, box.fitsHeight, let inside = _textBox(image, document) {
                    h = inside.layout.totalHeight + _px(box.insetTop + box.insetBottom)
                }
                var clearLift = false
                // (A floating object takes no room in the line.)
                if theme.wordRules, let float = image.float, !float.takesRoom { w = 0; h = 0
                    // (The first line, which ends in a line break that clears, is as tall as the floats reach: Word's
                    // print of xd 07356df9, "Source" at the foot of its figure, 0 pt of distance under it.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.clearsFirstLine, float.wraps, float.verticalFrom == "paragraph",
                       float.verticalAlign == "top" || float.verticalAlign == nil {
                        h = (float.verticalAlign == nil ? _px(float.y) : 0) + _px(image.height + float.effectBottom + float.distanceBottom)
                        clearLift = true
                        RuleTrace.hit("word-line-after-a-clearing-break-stands-under-the-floats")
                    }
                }
                // (With its character border and effects round it.)
                if theme.wordRules, image.float == nil {
                    let room = _pictureRoom(image)
                    w += room.left + room.right
                    h += room.top + room.bottom
                }
                var size = Size(w.rounded(), h.rounded())
                // (An object in the line too wide for the room beside a header
                // picture that stands the page's height: Word sets it at the top of
                // the next page and fills that page, so the paragraph after it
                // starts a page further — tdf38575, lab T255. Its box is as tall as
                // the page, hung from the baseline, and the object is drawn in its
                // top: `_pageFill`.)
                var hung: Double? = nil
                if theme.wordRules, RichTextTheme.wordWindowsPages, let at = index, at >= 0, p.cell == nil, image.float == nil {
                    let setup = _setup(ofParagraph: at)
                    let inset = _px(setup.headerWrapLeft) - _px(p.style.indentLeft)
                    if setup.headerWrapLeft > 0, inset > 0, w > _flowWidth(at) - inset + _px(0.5) {
                        RuleTrace.hit("header-wrap-object-next-page")
                        hung = size.height
                        _pageFill[image.id] = size.height
                        size = Size(size.width, max(size.height, _px(setup.contentHeight) - _px(2)))
                    }
                }
                // (Several pictures in one paragraph, each wide enough for a
                // line of its own, on a line grid: each line is as many whole
                // pitches as its picture and effect extent need, the rest
                // under the picture, the text's descent not counted. Lab
                // `inlinepic` (Word for Windows, zh-e5eb092a's pictures, a
                // 15.6pt grid): pictures of 100/111/122/133/144/166/177pt
                // stand 9.3/13.9/2.9/7.3/12.0/5.7/10.2pt apart, the pitches
                // they need; ours stood them 0 to 1.6 apart, the pages'
                // table 6 to 30pt high. The engine snapped a line only when
                // the paragraph had one.)
                if hung == nil, image.float == nil, let grid = pitch, grid > 0, size.height > 0,
                   _picturesTakeLines(p, textWidth: textWidth) {
                    let unit = _px(grid)
                    let lines = ((size.height / unit) - 0.002).rounded(.up) * unit
                    if lines > size.height + 0.01 {
                        // (The picture stands half the spare room down, as a
                        // picture alone in its paragraph does; its line's
                        // metrics stay the box's: the room all under it.)
                        hung = size.height
                        _pageFill[image.id] = size.height
                        _lineCentre[image.id] = (lines - size.height) / 2
                        size = Size(size.width, lines)
                    }
                }
                // (Word's `w:textAlignment` "center" sets what is on a
                // line by its middle: a letterhead's words half way up
                // the emblem beside them, not on its foot.)
                let centred = theme.wordRules && p.style.eastAsian["w:textAlignment"] == "center" && image.float == nil
                // (Its middle, effect extent and all, at the middle of a
                // line of the paragraph's text as Word sets one — not of
                // the stand-in face's own ascent and descent: zh-e37f8d40's
                // 16pt 宋体 stood 1.6pt high of Word's beside its emblem,
                // which Word sets 5.73pt — 0.358 em — under the box's
                // middle.)
                let middle: Double? = centred ? p.runs.first(where: { $0.length > 0 && $0.style.inlineImage == nil }).flatMap { r in
                    theme.lineMiddle(for: r.style, named: named, eastAsian: p.text.contains { Self.isEastAsian($0, hinted: false) })
                } : nil
                let alignment = clearLift ? PlaceholderAlignment.top : centred && middle == nil ? PlaceholderAlignment.middle : PlaceholderAlignment.baseline
                // (And its line as tall as its run's text: Word's line that
                // holds a picture alone is a line of that text at least —
                // drawing.docx's mastheads, tiny pictures between line
                // breaks in 8.5pt Arial, are a band 32pt tall in its print
                // where each of ours was its picture's height, 17 in all.
                // A zero-width space in the run's style before it, one
                // more character in the painter's text — only where the
                // picture stands alone between breaks, and is narrower
                // than the line (chartex's chart, as wide as its column,
                // went to the next line after the space) and shorter than
                // a line of the text: a taller one's line is its own
                // height, with no depth of the text under it — the
                // masthead's 12.8pt picture between two breaks is a line
                // of 12.7 in Word's print, the band 9.8 + 12.7 + 9.8.)
                let at = pos - run.length
                let units = p.text.utf16
                func breaks(_ k: Int) -> Bool {
                    let u = units[units.index(units.startIndex, offsetBy: k)]
                    return u == 0x0A || u == 0x2028 || u == 0x0B
                }
                // (Or the first of the pictures that are all a line of an exact
                // height holds: Word sets the baseline of such a line where
                // text's would stand, 4/5 down; with nothing but pictures
                // in it ours put it at the tallest picture's foot, 10pt down
                // an 18pt line — LibreOffice's tdf119200, seven equation
                // objects, each 6.6pt high of Word's print.)
                let exactPictures: Bool = {
                    guard theme.wordRules, at == 0, image.float == nil, let exact = p.style.lineHeightPoints, exact > 0,
                          !p.style.lineHeightIsMinimum, p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC }) else { return false }
                    return p.inlineImages.values.allSatisfy { $0.float == nil }
                }()
                // (An embedded object — an ActiveX check box — stands on the line of its own run's text, whatever else is on the
                // line: dx2 00b709dd's 37 boxes, 14.25pt in 12pt Calibri, are lines 14.65 apart in Word's print, ours 14.42.)
                let objectLine = image.name == "w:object" && image.textBox == nil && image.isActiveXControl
                if theme.wordRules, image.float == nil, w < textWidth - 1,
                   exactPictures || (at == 0 || breaks(at - 1)) && (pos >= units.count || breaks(pos)) {
                    // (In the text's own style: the picture's run keeps no
                    // look of its own, the break beside it does — the
                    // masthead's 8.5pt Arial, where the paragraph's is
                    // 12pt Times.)
                    var line = style
                    var k = 0
                    for r in p.runs {
                        if r.length > 0, k <= (pos < units.count ? pos : at - 1), (pos < units.count ? pos : at - 1) < k + r.length, r.style.inlineImage == nil {
                            line = theme.textStyle(for: r.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                            break
                        }
                        k += r.length
                    }
                    let probe = TextPainter(text: TextSpan(text: "\u{200B}", style: line), textDirection: .ltr)
                    probe.layout(minWidth: 0, maxWidth: .infinity)
                    if h < probe.height {
                        children.append(TextSpan(text: "\u{200B}", style: line))
                        ctx.inserts.append(at)
                    }
                    probe.dispose()
                }
                var eqOffset: Double? = nil
                if hung == nil, theme.wordRules, image.name == "m:oMath", image.float == nil, let grid = pitch, grid > 0, alignment == .baseline,
                   // (Not in a paragraph of more than single spacing: its strut holds every line to the one height there.)
                   !(RichTextTheme.wordWindowsPages && p.style.lineSpacing > 1.001),
                   let fit = _equationGridLine(image, size: size, style: style, pitch: _px(grid)) {
                    RuleTrace.hit("equation-whole-pitches")
                    _pageFill[image.id] = fit.full
                    _lineCentre[image.id] = fit.down
                    eqOffset = fit.offset
                    size = Size(size.width, fit.height)
                }
                if theme.wordRules, image.float == nil, image.name != "m:oMath", let cd = p.cell?.textDirection, cd != .horizontal {
                    // A turned cell lays text out as a rotated block: the picture stays upright, so along the line it takes its height.
                    // Word centres it on the text's em column, so across the line it adds nothing.
                    size = Size(size.height, 0)
                    eqOffset = 0
                }
                // (A picture opening the paragraph, wider than the line once the first-line indent stands before it: Word keeps it on that
                // first line, at the indent, running past the margin. The painter would part the indent from the picture, so the picture's
                // box is cut to fit and drawn at its own width: aea0a2a2's 243.75pt equation, 11.35pt in, stood at the margin in ours.)
                if lead > 0 { _inlineOverflow[image.id] = nil }
                if theme.wordRules, RichTextTheme.wordWindowsPages, image.float == nil, lead > 0, p.style.list == nil, p.cell == nil,
                   inline.count == 1, inline[0].image == nil, textWidth - lead >= 1, size.width > 0, size.width + lead > textWidth + 0.01 {
                    RuleTrace.hit("word-first-picture-wider-than-the-indented-line-stays-on-it")
                    _inlineOverflow[image.id] = size.width + lead - textWidth
                    size = Size(textWidth - lead, size.height)
                }
                // (An object shorter than Word's line of its run's text makes that line, as a picture does on a line grid: its box is the
                // line's, the object at its top, the room all under it. dx2 00b709dd's check boxes, 14.25pt in 12pt Calibri, 14.65 apart.)
                if objectLine, hung == nil, size.height > 0, let box = theme.winLineBox?(run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
                    .map({ $0 * max(1, style.fontSize ?? _px(run.style.fontSize ?? theme.fontSize)) }), box.rounded() > size.height {
                    hung = box
                    _pageFill[image.id] = size.height
                    _lineCentre[image.id] = 0
                    size = Size(size.width, box)
                }
                children.append(RichImageSpan(alignment: alignment, baseline: TextBaseline.alphabetic, style: style))
                var placeOffset = (hung ?? eqOffset ?? middle.map { size.height / 2 + _px($0) }
                                                                ?? (fittedBaseline ?? image.baseline).map { min(size.height, _px($0)) } ?? size.height)
                                                                // (Raised or lowered as its run's `w:position` says: Word
                                                                // sets a MathType object that far under the baseline
                                                                // — tdf119200's equations, lowered 2 to 4pt.)
                                                                + (theme.wordRules && image.float == nil ? _px(run.style.raised ?? named?.char.raised ?? 0) : 0)
                // (A picture in a line of text of an exact height, lowered or raised past that line, does not grow it: Word's line stays
                // the exact height, the picture drawn whole where it stands, over the line's edge. dx2 es 613edc1c p4's 26.4pt picture,
                // lowered 10.5pt in a cell's 26.1pt exact line, made the row 4.4pt taller in ours than in Word's print.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, image.float == nil, image.name != "m:oMath", hung == nil, eqOffset == nil,
                   let exact = p.style.lineHeightPoints, exact > 0, !p.style.lineHeightIsMinimum,
                   !p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC }), size.height > 0 {
                    let above = placeOffset, below = size.height - placeOffset
                    let upper = min(above, _px(exact * 4 / 5)), lower = min(below, _px(exact / 5))
                    if above > upper + 0.5 || below > lower + 0.5 {
                        RuleTrace.hit("word-picture-in-an-exact-line-does-not-grow-the-line")
                        _pageFill[image.id] = size.height
                        _lineCentre[image.id] = upper - above
                        placeOffset = upper
                        size = Size(size.width, upper + max(0, lower))
                    }
                }
                inline.append((image, PlaceholderDimensions(size: size, alignment: alignment, baseline: TextBaseline.alphabetic, baselineOffset: placeOffset)))
                // (Before 2013's layout a space after a picture wider than
                // the line goes to a line of its own: lab `ps` (Word 16, a
                // cell of 74.35pt) sets the paragraph under a 76 or 80pt
                // picture and a space 13.8pt lower in mode 14 than with no
                // space, and not in mode 15, nor under a 74pt picture.
                // zh-9c5d0c3f's road signs, 75pt in such cells, stood a
                // line high of their captions — "車道縮減" 21pt.)
                if theme.wordRules, (document.compatibilityMode ?? 12) < 15, image.float == nil, w > textWidth + _px(0.01),
                   pos < units.count, units[units.index(units.startIndex, offsetBy: pos)] == 0x20 {
                    children.append(TextSpan(text: "\n", style: style))
                    ctx.inserts.append(pos)
                }
                continue
            }
            if pictureTabs, p.text[a ..< b].allSatisfy({ $0 == "\t" }) {
                let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let own = _glyphWidth(style, "\t")
                for offset in (pos - run.length) ..< pos {
                    children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
                    inline.append((nil, PlaceholderDimensions(size: Size(max(0, own + (adjust[offset] ?? 0)), 0),
                                                              alignment: PlaceholderAlignment.baseline,
                                                              baseline: TextBaseline.alphabetic, baselineOffset: 0)))
                }
                continue
            }
            // Two lines in one (`w:eastAsianLayout w:combine`): Word sets
            // the run's text as two lines at half its size, the first
            // half over the second, together as tall as a line of the
            // run's own size and standing where one would. zh-454e2e29's
            // table title combines "機關名稱機關代號" at 24pt: two 12pt
            // lines 20.64 apart, 48pt wide, the upper's baseline 15.12
            // over the line's; set flat, the title took two lines and its
            // row ran 34pt tall. Drawn as a box of the two lines before
            // the run (one more character in the painter's text, as an
            // insert), the run's own text kept and hidden.
            if theme.wordRules, let kept = run.style.keptXML, kept.containsSubstring("w:combine=\"1\"") || kept.containsSubstring("w:combine=\"true\"") || kept.containsSubstring("w:combine=\"on\""),
               case let chars = Array(String(p.text[a ..< b])), chars.count > 1, !chars.contains(where: { $0.isNewline }),
               let box = _combineBox(chars, run.style, p, named: named, document) {
                let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                let baseline = theme.baseline(for: run.style, in: p.style, named: named, eastAsian: true, gridPitch: nil, centresInLine: document.spacesForUnderline) ?? size * 0.88
                let dims = PlaceholderDimensions(size: Size(_px(box.width).rounded(), _px(box.height).rounded()), alignment: PlaceholderAlignment.baseline,
                                                 baseline: TextBaseline.alphabetic, baselineOffset: _px(baseline))
                children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
                inline.append((box, dims))
                ctx.inserts.append(pos - run.length)
                var hidden = run.style
                hidden.hidden = true
                children.append(contentsOf: _spanStyled(&ctx, p.text[a ..< b], hidden, at: pos - run.length, next: b < utf16.endIndex ? p.text[b] : nil))
                continue
            }
            // A form's check box ("☐", "☒" — the reader's FORMCHECKBOX)
            // is a drawn square in Word's print, not a character: at 10pt
            // a 9.36pt box stroked 0.72, 1.06 before it and 1.08 after (an
            // 11.5pt advance), its foot 0.96 under the baseline —
            // form_footnotes' "☐ Yes ☐ No", whose "Yes" stood 2.5pt left
            // of Word's behind the glyph's 8.96. A box in the line before
            // the character, which is kept and hidden, as a combined run's.
            if theme.wordRules, run.style.formBox, p.text[a ..< b].contains(where: { $0 == "\u{2610}" || $0 == "\u{2612}" }) {
                let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                var hidden = run.style
                hidden.hidden = true
                var start = a
                for idx in p.text[a ..< b].indices where p.text[idx] == "\u{2610}" || p.text[idx] == "\u{2612}" {
                    let at = pos - run.length + utf16.distance(from: a, to: idx)
                    if start < idx {
                        children.append(contentsOf: _spanStyledByLine(&ctx, p.text[start ..< idx], run.style, at: pos - run.length + utf16.distance(from: a, to: start), next: p.text[idx]))
                    }
                    var box = ImageAttachment(data: Data(), width: size * 0.936, height: size * 0.936, name: p.text[idx] == "\u{2612}" ? "checkbox-on" : "checkbox")
                    box.outline = ShapeOutline(kind: .box, color: run.style.color ?? theme.textColor, width: size * 0.072)
                    box.effectLeft = size * 0.106
                    // (Word's advance by font, from its lab print: 1.147 em in
                    // Times/Arial, 1.219 Calibri, 1.295 in MS Gothic / SimSun /
                    // MS Mincho; the extra goes after the box.)
                    let boxFace = (run.style.fontFamily ?? named?.char.fontFamily ?? "").lowercased()
                    let boxAdvance: Double = boxFace.containsSubstring("gothic") || boxFace.containsSubstring("mincho") || boxFace.containsSubstring("simsun") ? 1.295
                        : boxFace.containsSubstring("calibri") ? 1.219 : 1.15
                    box.effectRight = size * (0.108 + boxAdvance - 1.15)
                    // (After the character, which a tab before it sets at
                    // its stop; and a zero-width space in the run's style
                    // with it, so a line of the box alone is a line of
                    // the text — Word's cells of one box are 11.52 tall
                    // at 10pt, not the box's 9.36.)
                    let after = p.text.index(after: idx)
                    children.append(contentsOf: _spanStyled(&ctx, p.text[idx ..< after], hidden, at: at, next: after < p.text.endIndex ? p.text[after] : nil))
                    children.append(TextSpan(text: "\u{200B}", style: style))
                    ctx.inserts.append(at + 1)
                    children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
                    // (A box alone in a cell narrower than it: one object on
                    // its line stays there and runs past the margin, as Word
                    // draws it; ours put it on a line under the empty one
                    // before it, a row of two lines. dx2 es cd95b495's 22pt
                    // box column holds 11.35pt for a 12.65pt advance.)
                    var boxWidth = _px(size * boxAdvance)
                    if textWidth > 0, boxWidth > textWidth, !p.text.contains(where: { $0 != "\u{2610}" && $0 != "\u{2612}" && $0 != " " && $0 != "\u{A0}" }) {
                        RuleTrace.hit("word-lone-check-box-stays-on-its-line-in-a-narrow-cell")
                        boxWidth = textWidth
                    }
                    inline.append((box, PlaceholderDimensions(size: Size(boxWidth, _px(size * 0.936)), alignment: PlaceholderAlignment.baseline,
                                                              baseline: TextBaseline.alphabetic, baselineOffset: _px(size * 0.84))))
                    ctx.inserts.append(at + 1)
                    start = after
                }
                if start < b {
                    children.append(contentsOf: _spanStyledByLine(&ctx, p.text[start ..< b], run.style, at: pos - run.length + utf16.distance(from: a, to: start), next: b < utf16.endIndex ? p.text[b] : nil))
                }
                continue
            }
            let runStart = pos - run.length
            children.append(contentsOf: _spanStyledByLine(&ctx, p.text[a ..< b], run.style, at: runStart, next: b < utf16.endIndex ? p.text[b] : nil))
            // (The half share after a ruby's base: a word joiner that wide.)
            if let tail = ctx.rubyTails[pos], tail > 0, run.style.ruby != nil {
                ctx.rubyTails[pos] = nil
                let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            gridPitch: pitch, scriptHidden: true)
                children.append(TextSpan(text: "\u{2060}", style: style.copyWith(letterSpacing: tail)))
                ctx.inserts.append(pos)
            }
        }
        }
        _sblk6()
        if inStretch, let last = p.runs.last {
            let look = theme.textStyle(for: last.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                       gridPitch: pitch, scriptHidden: true)
            children.append(TextSpan(text: "\u{202C}", style: look))
            ctx.inserts.append(p.text.utf16.count)
        }
        if isolated, let last = p.runs.last {
            let look = theme.textStyle(for: last.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                       gridPitch: pitch, scriptHidden: true)
            children.append(TextSpan(text: "\u{202C}", style: look))
            ctx.inserts.append(p.text.utf16.count)
        }
        if roomyTrail, let last = p.runs.last {
            // (In a style that adds nothing to the text's line, tried
            // beside the last ideograph: which face each style resolves
            // the joiner to differs by machine. In the run's Latin style its
            // descent — Liberation Mono's on Linux — made zh-1563bd74's
            // footer 1.2pt taller and its document a page long, though
            // alone it is the shorter line; in the ideographs' style the
            // Mac's stand-in ran a point tall. The ideographs' style first,
            // which also gives a line of the spaces alone the text's
            // height, as Word's is; else the Latin one; else one that takes
            // no part in the line.)
            func lastIdeograph(_ spans: [InlineSpan]) -> (style: TextStyle?, ch: Character)? {
                for span in spans.reversed() {
                    guard let t = span as? TextSpan else { continue }
                    if let inner = t.children, let found = lastIdeograph(inner) { return found }
                    if let text = t.text, let ch = text.last(where: { Self.isEastAsian($0, hinted: false) }) { return (t.style, ch) }
                }
                return nil
            }
            let latin = theme.textStyle(for: last.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                        gridPitch: pitch, scriptHidden: true)
            func height(_ spans: [InlineSpan]) -> Double {
                let t = TextPainter(text: TextSpan(children: spans), textDirection: .ltr)
                t.layout(minWidth: 0, maxWidth: 100_000)
                defer { t.dispose() }
                return t.height
            }
            var style = latin
            if let found = lastIdeograph(children), let own = found.style {
                let glyph = TextSpan(text: String(found.ch), style: own)
                let alone = height([glyph])
                // (Within half a point: on the Mac the Latin one sets the pair
                // 0.4pt taller, the ideographs' 0.8, and at no height a line
                // of the spaces alone — zh-c5b5087b's four — takes none,
                // where Word's is a line of the text; on Linux the
                // ideographs' adds nothing and the Latin 1.2.)
                // (Where the spaces fit the line, the joiner keeps them on it
                // and is no part of its height: on the Mac either style adds
                // to it — the Latin 0.4pt, which made zh-6e653ca0's footer,
                // "X隆阳区人民政府发布" and its spaces on one line in Word's
                // print (bold 宋体 14pt), 18.6 where Word's is 18.2, and sent
                // p8's "第四章" heading over. Where they run past the line,
                // the joiner parts them and a line of them alone takes its
                // height, as above: zh-c5b5087b's.)
                let probe = TextPainter(text: TextSpan(children: children), textAlign: .left, textDirection: .ltr)
                if !inline.isEmpty { probe.setPlaceholderDimensions(inline.map { $0.dimensions }) }
                probe.layout(minWidth: 0, maxWidth: max(1, textWidth))
                let count = probe.plainText.utf16.count
                let end = probe.getBoxesForSelection(TextSelection(baseOffset: max(0, count - 1), extentOffset: count)).map(\.right).max() ?? 0
                probe.dispose()
                let overflows = end > textWidth + _px(0.01)
                style = !theme.wordRules || overflows
                    ? [own.copyWith(letterSpacing: 0), latin].first { height([glyph, TextSpan(text: "\u{2060}", style: $0)]) <= alone + _px(0.5) }
                        ?? latin.copyWith(height: 0.01)
                    : latin.copyWith(height: 0.01)
            }
            children.append(TextSpan(text: "\u{2060}", style: style))
            ctx.inserts.append(p.text.utf16.count)
        }
        return (TextSpan(children: children), inline, ctx.inserts)
    }

    /// The stretches of paragraph `p` that carry one ruby (UTF-16
    /// offsets), with the first run's look.
    @inline(__always) func gridPitchIsNil(_ pitch: Double?) -> Bool { pitch == nil }

    /// A vertical ruby paragraph on a line grid: per ruby group, how far its column's glyphs stand toward the next column (px).
    func _rubyColumnShifts(_ i: Int, _ document: RichDocument) -> [(from: Int, to: Int, shift: Double)] {
        let p = document.paragraphs[i]
        guard theme.wordRules, _verticalBody(i), _grid(i, document).pitch != nil, p.style.lineHeightPoints == nil else { return [] }
        let named = _named(p, document)
        return _rubyGroups(p).compactMap { g in
            guard let h = theme.rubyLine(for: g.style, in: p.style, named: named, eastAsian: true, gridPitch: _grid(i, document).pitch, vertical: true), h.raise != 0 else { return nil }
            let map = _map(i)  // (the painter's offsets: list markers and inserts stand in its text)
            return (map.painter(g.from), map.painter(g.to), -h.raise * theme.pixelsPerPoint * scale)
        }
    }
    func _rubyGroups(_ p: RichParagraph) -> [(from: Int, to: Int, ruby: RubyText, style: CharStyle)] {
        var out: [(from: Int, to: Int, ruby: RubyText, style: CharStyle)] = []
        var at = 0
        for run in p.runs {
            defer { at += run.length }
            guard let ruby = run.style.ruby, run.length > 0 else { continue }
            if let last = out.last, last.ruby == ruby, last.to == at { out[out.count - 1].to = at + run.length }
            else { out.append((at, at + run.length, ruby, run.style)) }
        }
        return out
    }

    /// Whether a ruby run's line is taller, in grid pitches, than the plain text beside it. Where
    /// it is not, the plain text sets the line and the ruby base stands on its baseline with the
    /// ruby the same raise over it: fltpage4 lab, a 24pt MS Mincho title with a 11pt ruby base in
    /// it, both lines two pitches, base 48.00 and ruby 38.04 in Word's print (ours moved the 11pt
    /// base 11pt down and the title 2.15 with it).
    func _rubyShiftApplies(_ p: RichParagraph, named: RichNamedStyle?, ruby: CharStyle, pitch: Double?) -> Bool {
        guard let pitch, pitch > 0 else { return true }
        let size = ruby.fontSize ?? named?.char.fontSize ?? theme.fontSize
        guard size > 0.5, let line = theme.rubyLine(for: ruby, in: p.style, named: named, eastAsian: true, gridPitch: pitch) else { return true }
        var plain = 0.0
        for r in p.runs where r.style.ruby == nil && r.length > 0 && r.style.inlineImage == nil {
            guard let n = theme.naturalLine(for: r.style, named: named, eastAsian: true) else { continue }
            plain = max(plain, (n / pitch - 0.002).rounded(.up) * pitch)
        }
        if line.height * size > plain + 0.01 { return true }
        // (Same pitches, but the ruby stands higher than the plain text's own ascent: Word still centres the ruby's room and the text in the
        // pitches, f42177d2's 22pt title, 21pt raise, 11pt ruby, 54 pt either way: base 95.3 in Word's print, 91.3 unshifted. A ruby inside the
        // plain ascent leaves the line as the plain text has it: the fltpage4 lab.)
        guard let rt = ruby.ruby, theme.wordRules else { return false }
        let rubySize = rt.size < 0 ? size : rt.size > 0 ? rt.size : size / 2
        let raise = rt.raise > 0 ? rt.raise : size / 2
        var rs = ruby; rs.ruby = nil; rs.fontSize = rubySize
        var plainAscent = 0.0
        for r in p.runs where r.style.ruby == nil && r.length > 0 && r.style.inlineImage == nil {
            if let b = theme.baseline(for: r.style, in: p.style, named: named, eastAsian: true, gridPitch: nil) { plainAscent = max(plainAscent, b) }
        }
        guard plainAscent > 0, let rb = theme.baseline(for: rs, in: p.style, named: named, eastAsian: true, gridPitch: nil) else { return false }
        if raise + rb > plainAscent + 0.01 { RuleTrace.hit("word-ruby-above-the-plain-ascent-centres-in-the-same-pitches"); return true }
        return false
    }

    /// On a line grid a ruby's base is moved down with its line (`rubyLine`); where
    /// the paragraph is one line of that base and other text (f42177d2's
    /// "…組み合わせてみたり、参考にしたりして…" with 参考 over ruby), the text
    /// beside it moves by the same, as Word sets the whole line lower. Zero
    /// where the paragraph is all ruby, or may run to several lines.
    @inline(never)
    func _mixedRubyRaise(_ p: RichParagraph, named: RichNamedStyle?, textWidth: Double, pitch: Double?) -> Double {
        guard theme.wordRules, pitch != nil, NativeParagraphBuilder.supportsBaselineShift,
              let first = p.runs.first(where: { $0.style.ruby != nil && $0.length > 0 }),
              p.runs.contains(where: { $0.style.ruby == nil && $0.length > 0 && $0.style.inlineImage == nil }) else { return 0 }
        let size = first.style.fontSize ?? named?.char.fontSize ?? theme.fontSize
        // (Trailing blanks hang past the margin and never wrap a line: ee0b468e's 木下闇 line, "…野﨑一雄" and 22 blanks,
        // is one column in Word's print and its text is moved with the ruby like the lab's short lines.)
        var counted = Array(p.text.utf16)
        while let l = counted.last, l == 0x20 || l == 0x3000 { counted.removeLast() }
        guard size > 0.5, Double(counted.count) * _px(size) <= textWidth else { return 0 }
        guard _rubyShiftApplies(p, named: named, ruby: first.style, pitch: pitch) else { return 0 }
        return theme.rubyLine(for: first.style, in: p.style, named: named, eastAsian: true, gridPitch: pitch)?.raise ?? 0
    }

    /// A ruby's own look: the base's face at the ruby's size.
    func _rubyStyle(_ g: (from: Int, to: Int, ruby: RubyText, style: CharStyle), _ p: RichParagraph, named: RichNamedStyle?,
                            _ document: RichDocument) -> TextStyle {
        var look = g.style
        look.ruby = nil
        look.letterSpacing = nil
        look.fontSize = g.ruby.size < 0 ? (g.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) : g.ruby.size > 0 ? g.ruby.size : (g.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) / 2
        let s = theme.textStyle(for: look, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: true)
        return TextStyle(color: s.color, fontSize: s.fontSize, fontWeight: s.fontWeight, fontStyle: s.fontStyle,
                         fontFamily: s.fontFamily, fontFamilyFallback: s.fontFamilyFallback)
    }

    /// The widths of a ruby and of its base, in pixels.
    func _rubyWidths(_ g: (from: Int, to: Int, ruby: RubyText, style: CharStyle), _ p: RichParagraph, named: RichNamedStyle?,
                             _ document: RichDocument, pitch: Double?) -> (ruby: Double, base: Double) {
        func width(_ text: String, _ style: TextStyle) -> Double {
            let tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: Double.infinity)
            defer { tp.dispose() }
            return tp.maxIntrinsicWidth
        }
        let units = Array(p.text.utf16)
        let base = String(decoding: units[g.from ..< min(g.to, units.count)], as: UTF16.self)
        let ea = base.first.map { Self.isEastAsian($0, hinted: (g.style.fontHint ?? named?.char.fontHint) == "eastAsia") } ?? true
        let baseStyle = theme.textStyle(for: g.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                        eastAsian: ea, gridPitch: pitch, scriptHidden: true)
        return (width(g.ruby.text, _rubyStyle(g, p, named: named, document)), width(base, baseStyle))
    }

    /// The ruby over paragraph `p`'s text, drawn where it belongs: its
    /// baseline `raise` over its base's, centred over the base — spread
    /// across it where the base is the wider, as Word's distributeSpace
    /// sets it. `painter` is the paragraph's (or its lines'), painted at
    /// `origin`; `map` as for `_paintScripts`.
    /// Ruby in a vertical column: Word draws each ruby character upright
    /// (its own glyph, one per place), not rotated with the line.
    @inline(never)
    func _paintUprightRuby(_ text: String, _ style: TextStyle, x: Double, step: Double, centre: Double,
                           origin: Offset, _ canvas: any Canvas) {
        var at = x
        let em = style.fontSize ?? 5
        for ch in text {
            let glyph = TextPainter(text: TextSpan(text: String(ch), style: style.copyWith(letterSpacing: 0)), textDirection: .ltr)
            glyph.layout()
            let middle = glyph.computeDistanceToActualBaseline(.alphabetic) - 0.38 * em
            canvas.save()
            canvas.translate(origin.dx + at + glyph.width / 2, origin.dy + centre)
            canvas.rotate(-Double.pi / 2)
            glyph.paint(canvas, Offset(-glyph.width / 2, -middle))
            canvas.restore()
            at += glyph.width + step
            glyph.dispose()
        }
    }

    /// Emphasis marks (`w:em`): one round dot per character that is not a
    /// space, centred on it, over its baseline (under it for underDot).
    /// Word sets them as a "．" glyph; measured at 11 pt: centre 1.08 em
    /// over / 0.29 em under the baseline, 0.12 / 0.13 em across.
    func _paintEmphasis(_ p: RichParagraph, _ painter: TextPainter, at origin: Offset,
                        _ canvas: any Canvas, _ document: RichDocument, map: _OffsetMap? = nil, index: Int? = nil) {
        guard theme.wordRules, p.runs.contains(where: { $0.style.emphasis != nil }) else { return }
        if let index, _verticalBody(index) { return }
        let named = _named(p, document)
        let lines = painter.computeLineMetrics()
        let units = Array(p.text.utf16)
        var at = 0
        for run in p.runs {
            defer { at += run.length }
            guard let em = run.style.emphasis, run.length > 0 else { continue }
            let s = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: true)
            let size = s.fontSize ?? 10
            let under = em == "underDot"
            let paint = Paint()
            paint.style = .fill
            paint.color = s.color ?? Color(0xFF000000)
            for u in at ..< min(at + run.length, units.count) {
                let c = units[u]
                if c == 0x20 || c == 0x09 || c == 0x3000 || c == 0xA0 || c == 0x0A || c == 0x0D { continue }
                let a = map?.painter(u) ?? u
                guard let box = painter.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: a + 1)).first?.toRect(), box.width > 0,
                      let line = lines.min(by: { abs($0.baseline - box.bottom) < abs($1.baseline - box.bottom) }) else { continue }
                if em == "dot" {
                    // (Word sets the over-dot as a "．" text glyph, a full-width period in the East Asian face, its baseline one em over the
                    // line's and its origin 0.175 em left of the character's centre: xb jpn 837e72c4 GR16d, dots at 94.3 over 104.9, 10.56 pt.)
                    let tp = TextPainter(text: TextSpan(text: "\u{FF0E}", style: s.copyWith(fontSize: size)), textDirection: .ltr)
                    tp.layout(minWidth: 0, maxWidth: Double.infinity)
                    let x = origin.dx + (box.left + box.right) / 2 - 0.175 * size
                    tp.paint(canvas, Offset(x, origin.dy + line.baseline - size - tp.computeDistanceToActualBaseline(.alphabetic)))
                    tp.dispose()
                    continue
                }
                let cx = origin.dx + (box.left + box.right) / 2 - 0.1 * _px(1)
                let cy = origin.dy + line.baseline + (under ? 0.29 : -1.08) * size
                canvas.drawCircle(Offset(cx, cy), (under ? 0.065 : 0.06) * size, paint)
            }
        }
    }

    /// The character an `eq \o\ac(○,예)` field lays over its ring: the ring's face at the overlay's size, centred on the ring, on its baseline.
    func _paintOverlay(_ p: RichParagraph, _ painter: TextPainter, at origin: Offset,
                       _ canvas: any Canvas, _ document: RichDocument, map: _OffsetMap? = nil) {
        guard theme.wordRules, p.runs.contains(where: { $0.style.overlay != nil }) else { return }
        let named = _named(p, document)
        let lines = painter.computeLineMetrics()
        var at = 0
        for run in p.runs {
            defer { at += run.length }
            guard let text = run.style.overlay, run.length > 0 else { continue }
            let a = map?.painter(at) ?? at, b = (map?.painter(at + run.length - 1) ?? at + run.length - 1) + 1
            guard let box = painter.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b)).first?.toRect(),
                  let line = lines.min(by: { abs($0.baseline - box.bottom) < abs($1.baseline - box.bottom) }) else { continue }
            var look = run.style
            look.overlay = nil
            look.letterSpacing = nil
            let ringSize = run.style.fontSize ?? named?.char.fontSize ?? theme.fontSize
            let s = theme.textStyle(for: look, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: true)
            // (The ring's own style, with its size scaled to the overlay's: whatever the pipeline does to the size, it does to both.)
            let style = TextStyle(color: s.color, fontSize: (s.fontSize ?? 0) * run.style.overlaySize / max(ringSize, 1), fontWeight: s.fontWeight, fontStyle: s.fontStyle,
                                  fontFamily: s.fontFamily, fontFamilyFallback: s.fontFamilyFallback)
            let tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: Double.infinity)
            // Centred on the ring's em (Word's ring is an em wide, 11.7 pt at 12 pt; the selection box can be narrower).
            let x = box.left + ((s.fontSize ?? 0) - tp.maxIntrinsicWidth) / 2
            tp.paint(canvas, Offset(origin.dx + x, origin.dy + line.baseline - tp.computeDistanceToActualBaseline(.alphabetic)))
            tp.dispose()
        }
    }


    /// Where the base of a vertical ruby is drawn across its column, which the ruby is placed from: the ruby's centre is the base
    /// glyph's centre plus the raise (Word's print, MS Mincho and Meiryo labs: raise less 0.1pt). A Japanese face's column stands on
    /// its own line's middle (`_paintUpright`'s `acrossC`), not on the middle of the layout box, which stood 0.9pt off. The box
    /// already holds the baseline shift of its line; the face's place takes it separately.
    func _drawnBaseCentre(_ base: TextStyle?, first: Rect, line: LineMetrics, shiftPx: Double) -> Double {
        let boxCentre = (first.top + first.bottom) / 2
        guard theme.wordRules, let base, let em = base.fontSize, em > 0 else { return boxCentre }
        let family = base.debugLabel ?? base.fontFamily ?? ""
        let low = family.lowercased()
        guard ["meiryo", "メイリオ", "ms mincho", "ms gothic", "ＭＳ", "明朝", "yu mincho", "yu gothic", "游"].contains(where: { low.containsSubstring($0) }),
              let face = theme.faceResolver?(family, true) else { return boxCentre }
        let bold = base.fontWeight.map { $0.value >= 600 } ?? false
        guard let t = (bold ? face.boldBaseline : nil) ?? face.baseline,
              let natural = (bold ? face.boldHeight : nil) ?? face.naturalHeight else { return boxCentre }
        return line.baseline - (t - natural / 2) * em + shiftPx
    }

    func _paintRuby(_ p: RichParagraph, _ painter: TextPainter, at origin: Offset,
                            _ canvas: any Canvas, _ document: RichDocument, map: _OffsetMap? = nil, index: Int? = nil) {
        guard theme.wordRules, p.runs.contains(where: { $0.style.ruby != nil }) else { return }
        let named = _named(p, document)
        let lines = painter.computeLineMetrics()
        for g in _rubyGroups(p) where g.to > g.from && !g.ruby.text.isEmpty {
            let a = map?.painter(g.from) ?? g.from, b = (map?.painter(g.to - 1) ?? g.to - 1) + 1
            guard let first = painter.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: b)).first?.toRect() else { continue }
            let (rubyWidth, baseWidth) = _rubyWidths(g, p, named: named, document, pitch: nil)
            let wide = max(rubyWidth, baseWidth)
            let left = first.left - (rubyWidth > baseWidth ? (rubyWidth - baseWidth) / Double(g.to - g.from) / 2 : 0)
            // (The line it stands on: the one whose baseline is under the
            // base's box.)
            guard let line = lines.min(by: { abs($0.baseline - first.bottom) < abs($1.baseline - first.bottom) }) else { continue }
            var style = _rubyStyle(g, p, named: named, document)
            let count = Double(g.ruby.text.count)
            var x = left + (wide - rubyWidth) / 2
            if baseWidth > rubyWidth, count > 0, g.ruby.align == nil || g.ruby.align == "distributeSpace" {
                let share = (baseWidth - rubyWidth) / count
                style = style.copyWith(letterSpacing: share)
                x = left + share / 2
            } else if baseWidth > rubyWidth, g.ruby.align == "left" || g.ruby.align == "right",
                      !(index.map { _verticalBody($0) } ?? false) {
                // (rubyAlign left: the ruby starts at its base's left edge, dx2 3ebc3ec5's "３月振替" over "１０，０００円" at x 196.0 in Word's print, not centred
                // at 220.2. Right is the mirror, unmeasured.)
                x = g.ruby.align == "left" ? left : left + wide - rubyWidth
            }
            let tp = TextPainter(text: TextSpan(text: g.ruby.text, style: style), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: Double.infinity)
            let raise = _px(g.ruby.raise > 0 ? g.ruby.raise : (g.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) / 2)
            // (On a line grid the base text was moved with the ruby line: `rubyLine`.)
            let verticalHere = index.map { _verticalBody($0) } ?? false
            let moved = NativeParagraphBuilder.supportsBaselineShift && (verticalHere ? _grid(index, document).pitch != nil && p.style.lineHeightPoints == nil : _rubyShiftApplies(p, named: named, ruby: g.style, pitch: _grid(index, document).pitch))
                ? theme.rubyLine(for: g.style, in: p.style, named: named, eastAsian: true, gridPitch: _grid(index, document).pitch, vertical: verticalHere)?.raise ?? 0 : 0
            // (The plain text beside a ruby is moved with the ruby line only where the paragraph is all ruby or one line
            // (`_mixedRubyRaise`); in a mixed paragraph that wraps it stays, and so must the ruby's share of that move: ee0b468e's
            // 薇 over ぜんまい stood 5.4pt from its base, Word's print 13.9, the lab's one-line 14.9 with the move.)
            if let index, _verticalBody(index) {
                _paintUprightRuby(g.ruby.text, style, x: x, step: baseWidth > rubyWidth ? (baseWidth - rubyWidth) / count : 0,
                                  centre: _drawnBaseCentre(theme.textStyle(for: g.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: true), first: first, line: line, shiftPx: -moved * _px(1)) - raise, origin: origin, canvas)
                tp.dispose()
                continue
            }
            tp.paint(canvas, Offset(origin.dx + x, origin.dy + line.baseline - raise - moved * _px(1) - tp.computeDistanceToActualBaseline(.alphabetic)))
            tp.dispose()
        }
    }

    /// Where every stretch of a paragraph has one line height but not
    /// one face, each face splits that height about the baseline its own
    /// way and a line that mixes two comes out taller than either — and
    /// which lines those are depends on which face the platform falls
    /// back to for a character. A strut of that height holds every line
    /// to it. (Stretches of different heights are left to the tallest.)
    /// White space whose face and size set no line in Word's print, where
    /// the line holds anything else: the space and U+3000 (lab `el`). Not
    /// a no-break space, which stands in for a glyph no face has — the
    /// Symbol box of form_footnotes' "D - ", whose line is Symbol's.
    /// What sets no line of its own beside other text, for the first baseline: a space, and in
    /// Word a tab and (for Windows) the en, em and four-per-em spaces (lab `sp`, `ttab`) —
    /// lo-11ad5a95's rows of a label, a tab and one 48pt space stood the label 11pt low, out of
    /// its box, and the PDF lost it. (Scalars, not Characters: "\u{2000}" == "\u{2002}" in Swift,
    /// the two being canonically equivalent.)
    /// What an empty paragraph needs at a page's foot: its line taken as a single one, and its space after.
    /// Whether the table that precedes the empty paragraphs before `i` starts on `pieces` (this page).
    static func _tableBeforeEmptiesIsOn(page: Int, i: Int, cells: [_CellGeo?], pieces: [PagePiece]) -> Bool {
        var k = i - 1
        while k >= 0, cells[k] == nil { k -= 1 }
        guard k >= 0, let t = cells[k]?.table else { return false }
        while k > 0, cells[k - 1]?.table == t { k -= 1 }
        return pieces.contains { $0.paragraph == k }
    }

    static func _needs(_ height: Double, _ after: Double, _ multiple: Double) -> Double {
        (height - after) / max(1, multiple) + after
    }

    /// Where the paragraph at `i` begins on the page: `y`, or below the paragraph before it where that one stands on this page and `y` has not moved past it.
    static func _effectiveY(_ y: Double, _ i: Int, _ page: [PagePiece], _ heights: [Double]) -> Double {
        guard i > 0, let last = page.last(where: { $0.paragraph == i - 1 }) else { return y }
        return max(y, last.pageY + heights[i - 1])
    }

    /// Whether the table at `i` floats by the text straight after another floating table, with only
    /// empty paragraphs between them. compat1415b (Word for Windows, compat 14): the second stands
    /// where the empties end, without its offset.
    static func _followsFloatingTable(_ i: Int, _ table: String, document: RichDocument, cells: [_CellGeo?]) -> Bool {
        guard RichTextTheme.wordWindowsPages, let ts = document.tableStyles[table], ts.floatsOverText else { return false }
        var k = i - 1
        while k >= 0, cells[k] == nil, document.paragraphs[k].text.isEmpty { k -= 1 }
        guard k >= 0, k < i - 1, let before = cells[k], before.table != table, let first = document.tableStyles[before.table] else { return false }
        return first.floatsOverText && !first.pageAnchored && first.floatOffsetY != nil
    }

    static func _setsNoLineBesideText(_ ch: Character) -> Bool {
        _setsNoLine(ch) || ch == "\t" || (RichTextTheme.wordWindowsPages && (ch.unicodeScalars.count == 1 && [0x2002, 0x2003, 0x2005].contains(ch.unicodeScalars.first!.value)))
    }

    /// Whether some runs of `p` hold East Asian text and others only Latin (white space aside).
    func _holdsEastAsianAndLatinRuns(_ p: RichParagraph, document: RichDocument) -> Bool {
        var ea = false, latin = false, at = 0
        let named = _named(p, document)
        for run in p.runs where run.length > 0 {
            let a = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: min(at, p.text.utf16.count))
            let b = p.text.utf16.index(a, offsetBy: min(run.length, p.text.utf16.count - min(at, p.text.utf16.count)))
            at += run.length
            let hinted = (run.style.fontHint ?? named?.char.fontHint) == "eastAsia"
            let chars = p.text[a ..< b].filter { !Self._setsNoLine($0) }
            if chars.isEmpty { continue }
            if chars.contains(where: { Self.isEastAsian($0, hinted: hinted) }) { ea = true }
            // (A run of punctuation alone is not Latin text: it takes the line's face, and splitting a Korean line at a hinted "." or "/"
            // is no change of face: xd b88f2314's bullets stood 1.9 pt apart in the step where Word's pitch is the plain 15.5 pt.)
            else if !chars.allSatisfy({ $0.isASCII && !$0.isLetter && !$0.isNumber }) || !theme.wordRules { latin = true }
        }
        return ea && latin
    }

    /// The size of the largest run of only spaces in a span.
    static func _spaceSize(_ s: InlineSpan) -> Double? {
        guard let t = s as? TextSpan else { return nil }
        var m: Double? = nil
        if let text = t.text, !text.isEmpty, text.allSatisfy({ $0 == " " }), let size = t.style?.fontSize { m = size }
        for c in t.children ?? [] { if let v = _spaceSize(c) { m = max(m ?? 0, v) } }
        return m
    }

    static func _setsNoLine(_ ch: Character) -> Bool {
        // (The bidirectional controls a right-to-left run is wrapped in set none either: lo tdf163575's
        // headings end in a 20pt right-to-left space, and Word sets their lines by the 15pt text.)
        ch == " " || ch == "\u{3000}" || ch.unicodeScalars.allSatisfy { $0.value == 0x200E || $0.value == 0x200F || ($0.value >= 0x202A && $0.value <= 0x202E) || ($0.value >= 0x2066 && $0.value <= 0x2069) }
    }

    /// Whether two stretches set the same line: the same size, and heights within 1.5% (a face's bold beside its regular — see
    /// `_strut`). `wide` (Thai): any sizes, heights within 3%: a Thai stand-in is drawn at 0.82 of the size named with its height
    /// raised to match, and Angsana New's bold is 2.5% over its regular.
    static func _sameLine(_ s1: Double, _ h1: Double, _ s2: Double, _ h2: Double, wide: Bool = false) -> Bool {
        let d = abs(s1 * h1 - s2 * h2), m = max(s1 * h1, s2 * h2)
        if d < 0.01 { return true }
        return wide ? d <= 0.03 * m : (abs(s1 - s2) < 0.01 && d <= 0.015 * m)
    }
}

extension RichLayout {
    static func shadeShows(_ c: Color?) -> Bool { c.map { $0 != Color(0xFFFFFFFF) } ?? false }
}

extension RichLayout {
    /// An empty paragraph of a Tamil document whose mark asks for Arial Unicode MS (a face Windows lacks) is a line of Nirmala UI,
    /// 1.330 em (14.6 pt at 11 pt), against the 12.65 of the Latin stand-in. (It was set as Mangal's 18.5 until a347c3b3's empty line
    /// after a 9-line paragraph of 6 marked lines stood 37.4 pt under the last line and 14.6 above the next: Nirmala's line plus the
    /// marked lines' surplus, 2.76 + 6 x 3.8 + 11.87. The 18.5 seen after a one-line marked paragraph is that paragraph's own
    /// 3.8 surplus on a 14.6 line.)
    @inline(never)
    func _tamilEmptyMarkJoiner(_ mark: CharStyle, named: RichNamedStyle?, _ p: RichParagraph, _ document: RichDocument,
                               look: TextStyle, pitch: Double?, scale: Double) -> TextStyle? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages,
              document.defaultLangXML?.containsSubstring("ta-IN") == true,
              (mark.complexFontFamily ?? named?.char.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms",
              let metrics = Self._indicLines["nirmala ui"] else { return nil }
        RuleTrace.hit("word-tamil-empty-mark-is-a-line-of-nirmala")
        return _lineJoiner(mark, named, look, p.style, pitch, scale, ascent: metrics.0, descent: metrics.1)
    }
}

extension RichLayout {
    /// A Tamil run whose complex-script face is Vijaya (Word for Windows draws it as Vijaya, a narrower, shorter-lined face than Nirmala UI).
    @inline(never)
    func _tamilVijaya(_ cs: String?, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool {
        (cs ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "vijaya"
    }
}

extension RichLayout {
    /// A Tamil paragraph whose complex face is Arial Unicode MS (missing on Windows): every line that holds a non-space Latin letter,
    /// digit or punctuation mark (Word draws those in Leelawadee UI) takes Leelawadee's taller line, yet the lines keep Nirmala UI's
    /// pitch and the surplus lands after the paragraph's last line (Word lab a347gap/J-chars: marks on 3 of 8 lines, 3 x 3.8 pt at 11 pt,
    /// for every mark kind; two marks on one line count once; spaces alone nothing). 0.345 em per line (18.4 - 14.6 at 11 pt).
    @inline(never)
    /// The value of `attribute="..."` in a kept-XML fragment, or nil.
    static func _attribute(_ xml: String?, _ attribute: String) -> String? {
        guard let xml, let r = xml.rangeOfSubstring(attribute + "=\"") else { return nil }
        let rest = xml[r.upperBound...]
        guard let q = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[rest.startIndex..<q])
    }
    /// A single-spaced paragraph of Hangul text in Malgun Gothic whose list marker is a Wingdings bullet (read from a file, Windows pages).
    func _wingdingsOverMalgunText(_ p: RichParagraph, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil,
              p.style.lineSpacing <= 1.001, !p.style.rightToLeft,
              p.text.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7AF }) else { return false }
        let ea = (p.runs.first?.style.eastAsiaFontFamily ?? _named(p, document)?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? "").trimmingWhitespace()
        return ea.lowercased() == "malgun gothic" || ea == "맑은 고딕"
    }

    func _tamilMarkedLinesExtra(_ i: Int, _ p: RichParagraph, _ document: RichDocument, _ painter: TextPainter) -> Double {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, !p.text.isEmpty else { return 0 }
        // (Devanagari in Arial Unicode MS, whose font-table entry is the Japanese charset: the same, 0.36 em with the 1.079 of line 259;
        // lab aums2 B and H: 30.0 and 30.2 pt against 26.4, once per paragraph however many lines hold marks.)
        let tamil = document.defaultLangXML?.containsSubstring("ta-IN") == true && p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) })
        let devanagari = !tamil && document.fontCharsets["arial unicode ms"] == "80" && p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) })
        // (A paragraph of spaces only, in a Devanagari-language complex run of the same face: its one line is Leelawadee UI's, 3.3 pt taller than Nirmala's at 10 pt
        // (dx2 31a0a560, the blank line under the table: Word 18.5 pt from the table's bottom rule to the next text, ours 15.2).)
        let devanagariSpaces = !tamil && !devanagari && document.fontCharsets["arial unicode ms"] == "80" && !p.text.isEmpty
            && p.text.unicodeScalars.allSatisfy({ $0.value == 0x20 })
            && p.runs.contains(where: { r in
                guard let x = r.style.keptXML else { return false }
                return x.containsSubstring("w:bidi=\"") || x.containsSubstring("<w:cs/>")
            })
            && document.paragraphs.contains(where: { $0.text.unicodeScalars.contains(where: { $0.value >= 0x905 && $0.value <= 0x939 }) })
        guard tamil || devanagari || devanagariSpaces else { return 0 }
        if devanagariSpaces {
            RuleTrace.hit("word-devanagari-aums-space-only-paragraph-is-a-marked-line")
            return 0.36 * _px(p.runs.first?.style.fontSize ?? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize)
        }
        let named = _named(p, document)
        let cs = (p.style.mark?.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "")
        guard cs.trimmingWhitespace().lowercased() == "arial unicode ms"
                || devanagari && p.runs.contains(where: { ($0.style.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms" }) else { return 0 }
        let size = _px(named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize)
        let lead = _lead(i)
        var starts = Set<Int>(), yuLines = Set<Int>()
        var lineSize = [Int: Double]()
        var offset = 0
        // (Marks in a run with no w:cs flag are Yu Gothic's, not Leelawadee's: their line is the run's own (word-aums-latin-run-in-indic-paragraph-is-a-yu-gothic-line),
        // so they add nothing after the paragraph; lab aumsy2, fb94294e.)
        var runEnd = 0, runIndex = -1
        var yu = false
        let realStarts = devanagari ? _lineStarts(painter, _map(i), count: p.text.utf16.count) : []
        for u in p.text.unicodeScalars {
            while offset >= runEnd, runIndex + 1 < p.runs.count {
                runIndex += 1
                let r = p.runs[runIndex]
                runEnd += r.length
                yu = devanagari && !(r.style.keptXML?.containsSubstring("<w:cs/>") ?? false) && !(r.style.keptXML?.containsSubstring("<w:cs ") ?? false)
                    && (r.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
            }
            let n = u.value > 0xFFFF ? 2 : 1
            // (Devanagari: a line the engine ends on a zero-width space is reported joined to the next, so the lines are
            // counted by their real starts; dx2 31a0a560's paragraph with 3 marked lines was counted as 2, 7.2 pt after it, not Word's 10.8.)
            func lineStart() -> Int {
                if devanagari, let at = realStarts.last(where: { $0 <= offset }) { return at + lead }
                return painter.getLineBoundary(TextPosition(offset: offset + lead)).start
            }
            if !yu, u.value > 0x20, u.value < 0x250 {
                let at = lineStart()
                starts.insert(at)
                // (Devanagari: the extra follows the size of the run that holds the mark, not the Normal style's: fb94294e's 9 pt runs in an 11 pt
                // Normal gave 3.9 pt after the paragraph where Word's print has 2.9 to 3.1.)
                if devanagari, runIndex >= 0, let rs = p.runs[runIndex].style.fontSize { lineSize[at] = max(lineSize[at] ?? 0, _px(rs)) }
            } else if yu, u.value > 0x20 {
                yuLines.insert(lineStart())
            }
            offset += n
        }
        // (A line that already holds a Yu Gothic run is Yu's line, and the Leelawadee marks beside it add nothing after the paragraph: fb94294e's first line,
        // " (" in Leelawadee next to "Sample) " in Yu Gothic Bold, Word 22.0 pt to the next paragraph where ours gave 25.9.)
        if devanagari, !yuLines.isEmpty { starts.subtract(yuLines) }
        // (Every marked line counts, the last and a one-line paragraph's only line included: a347c3b3, with the empty mark a Nirmala line.)
        if starts.isEmpty { return 0 }
        if devanagari {
            RuleTrace.hit("word-devanagari-aums-marked-lines-add-to-the-paragraph")
            // (Real paragraph, dx2 31a0a560: 3 marked lines gave Word +11.1 pt after the paragraph, 1 marked line +3.6: per line, like Tamil.)
            return starts.reduce(0.0) { $0 + 0.36 * (lineSize[$1] ?? size) }
        }
        RuleTrace.hit("word-tamil-leelawadee-marked-lines-add-to-the-paragraph")
        return Double(starts.count) * 0.345 * size
    }
}

extension RichLayout {
    /// A run whose complex face Windows lacks (Arial Unicode MS): Word draws its Latin letters, digits, punctuation and spaces in Leelawadee UI.
    /// The style `base` with letter spacing that gives the piece Leelawadee UI's advances (`TamilAdvances.leela`, read from Word's prints; a
    /// character it lacks keeps the stand-in's width).
    @inline(never)
    static func _leelaLatinStyle(_ w: Substring, base: TextStyle) -> TextStyle {
        guard let px = base.fontSize, px > 0.5, base.fontWeight != .bold else { return base }
        var sum = 0.0, known = "", rest = false
        for u in w.unicodeScalars {
            if u.value == 0x20 { sum += 0.274; known.unicodeScalars.append(u) }
            else if let a = TamilAdvances.leela[u.value] { sum += a; known.unicodeScalars.append(u) }
            else { rest = true }
        }
        if known.isEmpty { return base }
        func measure(_ text: Substring, _ ls: Double) -> Double {
            let t = TextPainter(text: TextSpan(text: String(text), style: base.copyWith(letterSpacing: ls)), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            defer { t.dispose() }
            return t.width
        }
        let w0 = measure(w, 0)
        guard w0 > 0.01 else { return base }
        let n = max(1, Int((measure(w, 10) - w0) / 10 + 0.5))
        let other = rest ? w0 - measure(Substring(known), 0) : 0
        return base.copyWith(letterSpacing: (base.letterSpacing ?? 0) + (sum * px + other - w0) / Double(n))
    }
    /// A run cut into maximal pieces of Indic letters (with their joiners) and of everything else.
    @inline(never)
    static func _splitIndicLatin(_ t: Substring) -> [(Substring, Bool)] {
        var out: [(Substring, Bool)] = []
        var a = t.startIndex, cur: Bool? = nil
        var i = t.startIndex
        while i < t.endIndex {
            let ch = t[i]
            let v = ch.unicodeScalars.first!.value
            let ind = (v >= 0x0900 && v < 0x0E00) || v == 0x200C || v == 0x200D
            if let c = cur, c != ind { out.append((t[a ..< i], c)); a = i }
            cur = ind
            i = t.index(after: i)
        }
        if let c = cur { out.append((t[a ..< t.endIndex], c)) }
        return out
    }
}

extension RichLayout {
    /// A line grid and an inline equation taller than one pitch: Word makes the
    /// line as many whole pitches as the line (the equation's ascent and
    /// descent, the text's where they are larger) needs, with the text's
    /// strut centred in it (20d9968b: a sum 21pt tall on an 18pt grid steps
    /// the line 27pt, two pitches with the text centred).
    @inline(never)
    func _equationGridLine(_ image: ImageAttachment, size: Size, style: TextStyle, pitch: Double) -> (height: Double, offset: Double, down: Double, full: Double)? {
        guard let whole = image.naturalExtent else { return nil }
        let base = _px(whole.ascent)
        // (A fraction's line follows its ink: 20d9968b's n over k and 1 over x are one 18pt pitch in Word's print, e^x-1 over x two.)
        let full = image.naturalInk.map { _px($0.up + $0.down) } ?? _px(whole.ascent + whole.descent)
        let probe = TextPainter(text: TextSpan(text: "\u{200B}", style: style), textDirection: .ltr)
        probe.layout(minWidth: 0, maxWidth: .infinity)
        let textAscent = probe.computeDistanceToActualBaseline(TextBaseline.alphabetic)
        probe.dispose()
        let ascent = max(textAscent, base)
        let descent = max(pitch - textAscent, full - base)
        let n = (full / pitch - 0.002).rounded(.up)
        _ = (ascent, descent)
        guard n >= 2 else { return nil }
        // (A fraction holding a radical keeps its natural height, off the grid: 20d9968b's cos θ = a/√(a²+b²) lines step 27.4 and 27.9 pt in Word's print, not 36.)
        if image.naturalInk == nil, (image.sourceXML ?? "").containsSubstring("<m:rad"), (image.sourceXML ?? "").containsSubstring("<m:f>") { return nil }
        let extra = (n - 1) * pitch / 2
        let offset = textAscent + extra
        return (n * pitch, offset, offset - base, full)
    }
}

extension RichLayout {
    /// Whether the document's font table gives Malgun Gothic as the alternate of this face.
    @inline(never)
    func _malgunAlternate(_ family: String?, _ document: RichDocument) -> Bool {
        guard let family else { return false }
        return document.fontAlternates[family.trimmingWhitespace().lowercased()] == "malgun gothic"
    }
}

extension RichLayout {
    /// Whether any of the document's first paragraphs holds an Indic letter (a Hindi form with Latin-only paragraphs keeps its own rules).
    @inline(never)
    func _documentHasIndic(_ document: RichDocument) -> Bool {
        for q in document.paragraphs.prefix(300) where q.text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) { return true }
        return false
    }
}

extension RichLayout {
    @inline(never) func _shonarSpaced(_ w: Substring, base: TextStyle, authored: Double) -> TextStyle? {
        let flat = base.copyWith(scaleX: 1)
        let t = TextPainter(text: TextSpan(text: String(w), style: flat), textDirection: .ltr)
        t.layout(minWidth: 0, maxWidth: 100_000)
        defer { t.dispose() }
        guard t.width > 0.01, !w.isEmpty else { return nil }
        return flat.copyWith(letterSpacing: (flat.letterSpacing ?? 0) + (0.2065 * authored * Double(w.count) - t.width) / Double(w.count))
    }
    /// The word set so its width is the sum of the face's per-cluster advances (`MangalAdvances.split`, any table), by letter spacing on the
    /// stand-in; clusters the table lacks keep the stand-in's width times `flatScale`. Nil where the table knows none of the word.
    @inline(never)
    func _clusterFitted(_ w: Substring, base: TextStyle, authored: Double, table: [String: Double], flatScale: Double, conjunctRatio: Double? = 0.85, block: UInt32 = 0x900, lowVowelsZero: Bool = false, spaceMarks: Bool = false) -> (style: TextStyle, flat: TextStyle)? {
        guard let split = MangalAdvances.split(w, table: table, conjunctRatio: conjunctRatio, block: block, lowVowelsZero: lowVowelsZero) else { return nil }
        let flat = base.copyWith(scaleX: 1)
        func measure(_ s: String, _ ls: Double) -> Double {
            let t = TextPainter(text: TextSpan(text: s, style: flat.copyWith(letterSpacing: ls)), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            defer { t.dispose() }
            return t.width
        }
        let w0 = measure(String(w), 0)
        guard w0 > 0.01 else { return nil }
        let n = max(1, Int((measure(String(w), 10) - w0) / 10 + 0.5))
        let other = split.rest ? (w0 - measure(split.known, 0)) * flatScale : 0
        // (Word's character spacing falls on a word's letters and not on its combining marks: its Kokila words run wider
        // than ours by about the spacing per mark, dx2 hi 0c80b3a3 at -0.1 pt. The fit spreads it over the glyphs.)
        let marks = w.unicodeScalars.filter { $0.properties.generalCategory == .nonspacingMark || $0.properties.generalCategory == .spacingMark }.count
        let spaced = Double(max(0, n - (spaceMarks ? 0 : marks)))
        return (flat.copyWith(letterSpacing: ((flat.letterSpacing ?? 0) * spaced + split.ems * authored + other - w0) / Double(n)), flat)
    }
}

extension RichLayout {
    /// Hangul spellings of the Korean faces Windows itself ships (Word finds these: Malgun Gothic, Batang, Dotum, Gulim, Gungsuh and their variants).
    static let _windowsHangulNamedFaces: Set<String> = ["맑은 고딕", "바탕", "바탕체", "돋움", "돋움체", "굴림", "굴림체", "궁서", "궁서체", "새굴림", "새돋움", "새바탕", "새궁서"]
    /// Whether the run's Latin face is a Hangul-named one the document's font table does not list (so Word's box has no alternate for it and draws its Latin in Yu Gothic).
    @inline(never)
    func _yuLatinOfMissingHangulFace(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool {
        guard document.readFromFile,
              let f = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily)?.trimmingWhitespace().lowercased(), !f.isEmpty,
              document.fontAlternates[f] == nil else { return false }
        if f.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) {
            return document.fontCharsets[f] == nil && !Self._windowsHangulNamedFaces.contains(f)
        }
        // (A Latin-named face Word's box lacks, with charset 80 and no alternate in the font table: Yu Gothic too, lab fallback-ft 1.)
        return document.fontCharsets[f]?.uppercased() == "80" && !WordWindowsFaces.names.contains(f) && !f.unicodeScalars.contains(where: { $0.value > 0x24F })
    }
}


extension RichLayout {
    /// The width, in the font's own size, of the unbroken run of stops and ellipses that holds `offset`
    /// (Arial's 0.278 em stop and 1 em ellipsis): Word parts such a run between any two of its characters
    /// only when no line could hold it whole (dx2 ms 6926161f's 99 stops and 19 ellipses in a 446 pt line).
    @inline(never)
    /// A run of stops that follows a space and is no wider than a line goes down to a line of its own whole, and is not parted
    /// between its stops (dx2 54378c49's "बस्ने " + 75 dots, 324 pt of a 455 pt line: Word's print opens the next line with the whole run).
    static func _stopRunFitsAfterSpace(_ units: [UInt16], at offset: Int, measure: (String) -> Double, width: Double) -> Bool {
        func adv(_ u: UInt16) -> Double? { u == 0x2E ? 0.278 : u == 0x2026 ? 1.0 : nil }
        guard offset > 0, offset < units.count else { return false }
        var a = offset, b = offset
        while a > 0, adv(units[a - 1]) != nil { a -= 1 }
        guard a > 0, units[a - 1] == 0x20 || units[a - 1] == 0xA0 else { return false }
        while b < units.count, adv(units[b]) != nil { b += 1 }
        return measure(String(decoding: units[a ..< b], as: UTF16.self)) <= width
    }
    /// A run of stops that follows an Indic word's letters, with no space between, goes down with that word whole when the two together fit a line, and is not
    /// parted between its stops (dx2 hi 7756e774's "।मिति" + 22 stops, 147 pt of a 463 pt line: Word's print opens the line with the whole piece, where ours
    /// filled the line above with part of the run).
    static func _stopRunAfterWordFits(_ units: [UInt16], at offset: Int, measure: (String) -> Double, width: Double) -> Bool {
        guard offset > 0, offset < units.count else { return false }
        var a = offset, b = offset
        while a > 0, units[a - 1] == 0x2E { a -= 1 }
        guard a > 0, a < offset || units[a - 1] != 0x2E else { return false }
        // the stops must follow a Devanagari letter or sign (not a space, a digit or CJK text)
        func deva(_ u: UInt16) -> Bool { u >= 0x900 && u <= 0x97F }
        guard deva(units[a - 1]) else { return false }
        while b < units.count, units[b] == 0x2E { b += 1 }
        var w = a
        while w > 0, units[w - 1] != 0x20, units[w - 1] != 0xA0, units[w - 1] != 0x09 { w -= 1 }
        return measure(String(decoding: units[w ..< b], as: UTF16.self)) <= width
    }
    static func _stopRunWidth(_ units: [UInt16], at offset: Int, size: Double) -> Double {
        func adv(_ u: UInt16) -> Double? { u == 0x2E ? 0.278 : u == 0x2026 ? 1.0 : nil }
        guard offset > 0, offset < units.count else { return 0 }
        var a = offset, b = offset
        while a > 0, adv(units[a - 1]) != nil { a -= 1 }
        // (A run that follows a space goes to a line of its own whole first, and is parted only there: dx2 eu ecd418ea's
        // "Nik, ……(50)" sets "Nik, " alone on its line in Word's print.)
        if a > 0, units[a - 1] == 0x20 || units[a - 1] == 0xA0 { return 0 }
        while b < units.count, adv(units[b]) != nil { b += 1 }
        return units[a ..< b].reduce(0.0) { $0 + (adv($1) ?? 0) } * size
    }
}

extension RichLayout {
    /// A missing Bengali face (SolaimanLipi, Nikosh): Word draws its spaces in Mangal, 0.5 em.
    /// A run of only ASCII (letters, digits, marks, spaces with at least one other) whose ascii and complex faces are one missing Bengali face, in a Bengali paragraph.
    /// SolaimanLipi (missing on Windows): its lines lift to Mangal only through marks, while Nikosh's lift through its spaces too.
    @inline(never) func _isSolaimanLipi(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool {
        (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "solaimanlipi"
    }
    @inline(never) func _asciiRunInMissingBengaliFace(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument, _ text: Substring, _ paragraphText: String) -> Bool {
        let cs = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
        let asc = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
        guard Self._missingBengaliSpaceEm(cs) != nil, asc == cs else { return false }
        var other = false
        for u in text.unicodeScalars {
            if u.value < 0x20 || u.value >= 0x7F { return false }
            if u.value > 0x20 { other = true }
        }
        guard other else { return false }
        if paragraphText.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && $0.properties.isAlphabetic }) { return true }
        // (A paragraph of ASCII alone in such a face is drawn in Mangal too, in a document that has Bengali: xd 73caaeda's rule of dashes.)
        return document.hasIndicText && !paragraphText.unicodeScalars.contains(where: { $0.value >= 0x80 })
    }
    @inline(never) static func _missingBengaliSpaceEm(_ face: String) -> Double? {
        let f = face.trimmingWhitespace().lowercased()
        return f == "solaimanlipi" || f == "nikosh" ? 0.5 : nil
    }
    /// A space at the face's own width (`spaceEm` of `unit`), as one letter spacing on the stand-in's space.
    @inline(never)
    func _indicSpaceStyle(base: TextStyle, spaceEm: Double, unit: Double, glyph: String = " ") -> TextStyle {
        let t = TextPainter(text: TextSpan(text: glyph, style: base.copyWith(letterSpacing: 0)), textDirection: .ltr)
        t.layout(minWidth: 0, maxWidth: 100_000)
        let w0 = t.width
        t.dispose()
        return base.copyWith(letterSpacing: (base.letterSpacing ?? 0) + spaceEm * unit - w0)
    }

    /// Kokila's own Latin, digits and space at their widths (`KokilaLatin`), as one letter spacing on the segment.
    @inline(never)
    func _kokilaLatinStyle(_ seg: Substring, base: TextStyle, px: Double) -> TextStyle {
        var st = base.copyWith(scaleX: 1)
        let split = KokilaLatin.split(seg)
        if split.any {
            func measure(_ s: String, _ ls: Double) -> Double {
                let t = TextPainter(text: TextSpan(text: s, style: st.copyWith(letterSpacing: ls)), textDirection: .ltr)
                t.layout(minWidth: 0, maxWidth: 100_000)
                defer { t.dispose() }
                return t.width
            }
            let w0 = measure(String(seg), 0)
            let n = max(1, Int((measure(String(seg), 10) - w0) / 10 + 0.5))
            let other = split.rest ? w0 - measure(split.known, 0) : 0
            if w0 > 0.01 { st = st.copyWith(letterSpacing: (st.letterSpacing ?? 0) + (split.ems * px + other - w0) / Double(n)) }
        }
        return st
    }
}

extension RichLayout {
    /// A point size on Word's 0.12 pt (600 dpi) grid, which is the size its PDF names and the one a hinted face's advances follow. Only upward:
    /// at 10 pt (9.96) the shorter size let "कहा" onto hin-z10093577's first line where Word ends it at "प्रकृति": its advances round per glyph to the 0.12 pt
    /// pixel, not by a flat scale, so a size below the exact one is left alone until a lab says how they round.
    @inline(never)
    static func _wordGridSize(_ pt: Double, snap: Bool) -> Double { pt }
}

extension RichLayout {
    // (Only a tab in a BIGGER face than the text raises the line: xd 53eca83a and 8e81b68d, tabs the size of the text or
    // smaller, fell from 42.1 to 13.9 and 19.9 to 9.8 when theirs were flattened too.)
    static func _tabBiggerThanText(_ tab: Double, _ p: RichParagraph, _ fallback: Double) -> Bool {
        var biggest = 0.0
        var at = p.text.utf16.startIndex
        for r in p.runs {
            let end = p.text.utf16.index(at, offsetBy: r.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
            if p.text[at..<end].contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }) { biggest = max(biggest, r.style.fontSize ?? fallback) }
            at = end
        }
        return tab > biggest
    }

    @inline(never) static func _afterBreakRun(_ u: [UInt16], _ offset: Int) -> Bool {
        var k = offset - 1
        while k >= 0, u[k] == 0x20 { k -= 1 }
        return k >= 0 && (u[k] == 0x0A || u[k] == 0x2028)
    }

    /// Whether the face a run's Hangul is set in (its East Asian face, else its own) is absent from Word's Windows box, so Word prints a stand-in.
    @inline(never)
    func _hangulFaceMissingOnWord(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool {
        guard document.readFromFile else { return false }
        let own: String? = run.eastAsiaFontFamily ?? run.fontFamily
        let styled: String? = named?.char.eastAsiaFontFamily ?? named?.char.fontFamily
        let normal: String? = _normalChar(document)?.eastAsiaFontFamily ?? _normalChar(document)?.fontFamily
        let raw: String = own ?? styled ?? normal ?? ""
        let f: String = raw.trimmingWhitespace().lowercased()
        if f.isEmpty { return false }
        if f.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) { return !Self._windowsHangulNamedFaces.contains(f) }
        return !WordWindowsFaces.names.contains(f)
    }
}

extension RichLayout {
    /// A JIS symbol in Latin-1 (§ ¨ ° ± ´ ¶ × ÷, and ¡ ¿ at half an em) drawn in a fixed half-em Latin face (MS Mincho, MS Gothic, GulimChe), where it is an em.
    func _jisLatin1Symbol(_ ch: Character, theme: RichTextTheme, run: CharStyle, named: RichNamedStyle?, document: RichDocument,
                                 hint: String?) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, ch.unicodeScalars.count == 1,
              let u = ch.unicodeScalars.first?.value else { return false }
        // (U+2010 too: Word draws it a full em in an MS Mincho run, xb 5dc87fc7 K85 12.0 of 12.0.)
        let set: [UInt32] = [0xA7, 0xA8, 0xB0, 0xB1, 0xB4, 0xB6, 0xD7, 0xF7, 0xB7, 0x2C7, 0x2010, 0x2016, 0x2032, 0x2033, 0xA1, 0xBF]
        guard set.contains(u) else { return false }
        // (Under w:hint="eastAsia" the character is already East Asian and an em: lab xb e925ae95, where Word's print and our plain
        // width agree.)
        if hint == "eastAsia" { return false }
        let latinName: String? = run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily
        guard let name = latinName else { return false }
        let l = name.lowercased()
        // GulimChe draws · and ˇ a full em (the half-em target below is MS Mincho/MS Gothic only).
        if (u == 0xB7 || u == 0x2C7) && l.containsSubstring("gulim") { return false }
        let names: [String] = ["ms mincho", "ms gothic", "ｍｓ 明朝", "ｍｓ ゴシック", "ms ゴシック", "ms 明朝", "gulimche"]
        var named1 = false
        for n in names where l.containsSubstring(n) { named1 = true }
        guard named1 else { return false }
        return theme.faceResolver?(name, false)?.fixedHalfLatin == true
    }
}

extension RichLayout {
    /// The reach of a text shadow above and below its run, in points (lab shadow2): the blur radius past the offset, a fraction of it by size.
    static func _shadowReach(_ sh: CharShadow, pt: Double) -> (above: Double, below: Double) {
        let sizes = [0.0, 12, 24, 36, 55, 72], fracs = [0.0, 0.285, 0.465, 0.615, 0.84, 1.0]
        var frac = 1.0
        if pt < 72, let i = sizes.lastIndex(where: { $0 <= pt }) {
            frac = fracs[i] + (fracs[i + 1] - fracs[i]) * (pt - sizes[i]) / (sizes[i + 1] - sizes[i])
        }
        return (max(0, sh.blur - sh.dy) * frac, max(0, sh.blur + sh.dy) * frac)
    }
}
