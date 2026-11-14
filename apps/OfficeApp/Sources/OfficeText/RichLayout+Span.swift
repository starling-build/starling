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
    static let _indicLines: [String: (Double, Double)] = [
        "yu gothic": _yuGothicLine, "mangal": (2542.0 / 2048, 898.0 / 2048), "kokila": (1504.0 / 2048, 857.0 / 2048), "nirmala ui": (2210.0 / 2048, 514.0 / 2048), "vijaya": (1462.0 / 2048, 600.0 / 2048), "latha": (2048.0 / 2048, 762.0 / 2048),
        "aparajita": (1550.0 / 2048, 870.0 / 2048), "raavi": (2048.0 / 2048, 1352.0 / 2048), "shruti": (2091.0 / 2048, 1352.0 / 2048),
        "gautami": (1892.0 / 2048, 1664.0 / 2048), "utsaah": (1518.0 / 2048, 774.0 / 2048), "vrinda": (2017.0 / 2048, 778.0 / 2048), "shonar bangla": (1655.0 / 2048, 996.0 / 2048), "shonar bangla bold": (1721.0 / 2048, 978.0 / 2048),
        // (Malgun Gothic as Word sets a line of it: hhea 1.088 + 0.242 and 0.4 of gap, 1.73 em, split evenly.)
        "malgun gothic": (1.088 + 0.2, 0.242 + 0.2)]
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
        // (An empty line whose mark is set in Nikosh (Windows lacks it) or Mangal is a line of Mangal, 1.68 em, and in Nirmala UI one of 1.33 em:
        // Word's print of lab siyam1, 3 empty paragraphs after each label, 16.8 / 13.3 pt apart at 10 pt against ours 12.2; and in Kokila its own 1.153 em, lab kokila1: 20.8 pt at 18 pt, where Calibri's gave 22.0.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile {
            let latin = (mark.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
            let face = latin == "nikosh" || latin == "mangal" ? "mangal" : (latin == "nirmala ui" ? "nirmala ui" : (latin == "kokila" ? "kokila" : ""))
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
        guard theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, !text.isEmpty else { return nil }
        let csFlag = run.keptXML.map { $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") } ?? false
        let cs = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
        let ascii = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
        var face = csFlag ? cs : ascii
        let isKalimati = face == "kalimati"
        if isKalimati { face = "mangal" }
        // Only Latha is measured for letters and digits too; the other faces only for runs of marks (Kalimati/Preeti Nepali docs drop otherwise).
        // (And Mangal itself, the face the run names: 2db27e2d's "24 × 13 = (20 + 4) × ..." line, digits and signs in Mangal runs, is Mangal's
        // 18.5 pt in Word's print where ours stood 15.1 on the Latin stand-in.)
        if face != "latha", !(face == "mangal" && !isKalimati), text.unicodeScalars.contains(where: { $0.properties.isAlphabetic || ($0.value >= 0x30 && $0.value <= 0x39) || $0.value > 0x7E }) { return nil }
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
                       held: Set<Int> = [], spread: [Int: Double] = [:], autoSpaces: ((Int, Double) -> Void)? = nil)
        -> (TextSpan, [(image: ImageAttachment?, dimensions: PlaceholderDimensions)], [Int]) {
        let named = _named(p, document)
        let pitch = (index.map { _offGrid($0, document) } ?? (p.style.eastAsian["w:snapToGrid"] == "0")) ? nil : _grid(index, document).pitch
        let mixedRubyRaise = _mixedRubyRaise(p, named: named, textWidth: textWidth, pitch: pitch)
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
            if theme.wordRules, RichTextTheme.wordWindowsPages, mark.fontFamily?.trimmingWhitespace().lowercased() == "ghea grapalat",
               document.fontAlternates["ghea grapalat"] == "franklin gothic medium cond" {
                mark.fontFamily = "Franklin Gothic Medium Cond"
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
            if theme.wordRules, p.style.list != nil, lead > 0 {
                // An empty list still has a number and its suffix. Reserve
                // their width so centered/right numbers move with the line.
                let box = RichImageSpan(alignment: .baseline, baseline: .alphabetic, style: look)
                let dimensions = PlaceholderDimensions(size: Size(lead, 0.01), alignment: .baseline,
                                                       baseline: .alphabetic, baselineOffset: 0.01)
                return (TextSpan(children: [box, TextSpan(text: "\u{200B}", style: look)]), [(nil, dimensions)], [])
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
        // (A vertical section does not widen the base for its ruby: the ruby overhangs the neighbours, and the
        // ※/☆ marks and the compressed 、 carry the width Word shows. 934bd3e5 p9: 0.5 broke 'わづか|に直衣' one
        // word early; 0 gives Word's break, 237 to 283 of 336 lines.)
        let rubyKeep = (index.map { _verticalBody($0) } ?? false) ? 0.0 : 1.0
        if theme.wordRules {
            for g in _rubyGroups(p) where g.to > g.from {
                let (ruby, base) = _rubyWidths(g, p, named: named, document, pitch: pitch)
                guard ruby > base + 0.01 else { continue }
                let share = (ruby - base) * rubyKeep / Double(g.to - g.from)
                for k in g.from ..< g.to { spread[k, default: 0] += k == g.from ? share / 2 : share }
                rubyTails[g.to, default: 0] += share / 2
            }
        }
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
        let heldSpaces = held.union(_closingSpaceHeld(p).map { [$0] } ?? [])
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
                for (i, r) in p.runs.enumerated() {
                    st += r.length
                    if i + 1 < p.runs.count, r.style.eastAsiaFontFamily != nil, p.runs[i + 1].style.eastAsiaFontFamily == nil { eaRunEnds.insert(st) }
                }
            }
            var at = 0
            var run: [Int] = []
            var nbsp: Set<Int> = []
            var left: Character? = nil
            func close(_ right: Character?) {
                defer { run = []; nbsp = [] }
                guard !run.isEmpty, document.balancesSpaceWidth else { return }
                // (A manual line break is no Latin word before spaces that open the next line, as at a paragraph's start: zh-5313b71d's "…发包结果。" ⏎ "    1.发包公告…"
                // sets its four spaces half an em each from the margin in Word's print, where ours took them for the gap between
                // Latin words and lost three.)
                func latin(_ c: Character?) -> Bool { c.map { !Self.isEastAsian($0, hinted: false) && !(RichTextTheme.wordWindowsPages && ($0 == "\n" || $0 == "\u{2028}")) } ?? false }
                if nbsp.isEmpty {
                    // (Between a Latin pair of brackets they are half an em too, in Word for Windows: zh-7b125a21's
                    // fill-in "(  )" sets its two 5.25 each at 10.5pt, where 2.6 took a character more a line. Not
                    // two spaces between words, nor a page number's "—  10  —". "[  ]" likewise: xb jpn 771abc's "[  ]は訳注" in 11pt Yu Mincho, 5.5 each.)
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
                    guard r.style.eastAsiaFontFamily == nil, r.style.fontHint != "eastAsia",
                          theme.faceResolver?(r.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true else { continue }
                    korean.formUnion(st ..< min(st + r.length, units.count))
                }
                var taken: Set<Int> = []
                for k in korean.sorted() where units[k] == 0x20 && k > 0 && korean.contains(k - 1) && (units[k - 1] != 0x20 || taken.contains(k - 1)) && !complexSpaces.contains(k) {
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
            guard theme.wordRules, p.text.utf16.contains(where: spaceUnit) else { return nil }
            let normal = _normalChar(document)
            func size(_ c: CharStyle?) -> Double { c?.fontSize ?? named?.char.fontSize ?? normal?.fontSize ?? theme.fontSize }
            var best: Double? = nil
            var at = p.text.utf16.startIndex
            for run in p.runs {
                let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
                if run.style.inlineImage != nil { return nil }
                // (Nor does a tab: IllustrativeCases' line of 11pt spaces
                // and tabs under an 8pt mark is the mark's line.)
                if p.text.utf16[at ..< end].contains(where: { $0 != 0x09 && !spaceUnit($0) }) { best = max(best ?? 0, size(run.style)) }
                at = end
            }
            if let best { return (best, false) }
            return (size(p.style.mark), true)
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
        func styled(_ rawText: Substring, _ run: CharStyle, at base: Int = 0, next: Character? = nil, symbolsShown: Bool = false) -> [TextSpan] {
            // (U+FE0F after a text-style emoji draws it in colour, U+FE0E after a colour one as an outline: each such
            // pair is a piece of its own, in its own face.)
            if !splittingVariation, let pieces = Self._variationPieces(rawText) {
                splittingVariation = true
                defer { splittingVariation = false }
                var out: [TextSpan] = []
                var at = base
                for (k, piece) in pieces.enumerated() {
                    let after = k + 1 < pieces.count ? pieces[k + 1].text.first : next
                    let spans = styled(Substring(piece.text), run, at: at, next: after, symbolsShown: symbolsShown)
                    out += piece.kind == 0 ? spans : spans.map {
                        TextSpan(text: $0.text, children: $0.children, style: Self._variationStyle($0.style, kind: piece.kind), recognizer: $0.recognizer, locale: $0.locale)
                    }
                    at += piece.text.utf16.count
                }
                return out
            }
            // (Spaces that lead a run of brackets or marks, in a missing Bengali face (Nikosh, SolaimanLipi) inside a Bengali paragraph, are a piece of their own: Word
            // draws them in Mangal without raising the line, while the bracket after them does; dx2 2263e221's " (" wrapped after its space, 16.4 pt line pitch in Word, 18.4 in ours.)
            if !splittingSpaces, rawText.count > 1, rawText.first == " ", let cut = rawText.firstIndex(where: { $0 != " " }),
               !rawText[cut...].unicodeScalars.contains(where: { $0.value >= 0x80 || $0.properties.isAlphabetic || $0.properties.numericType != nil }),
               theme.wordRules, RichTextTheme.wordWindowsPages,
               Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil,
               p.text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value >= 0x980 && $0.value <= 0x9FF }) {
                splittingSpaces = true
                defer { splittingSpaces = false }
                let n = rawText.distance(from: rawText.startIndex, to: cut)
                RuleTrace.hit("word-spaces-before-a-bracket-in-a-missing-bengali-face-are-their-own-piece")
                return styled(rawText[rawText.startIndex ..< cut], run, at: base, next: rawText[cut], symbolsShown: symbolsShown)
                    + styled(rawText[cut...], run, at: base + n, next: next, symbolsShown: symbolsShown)
            }
            // (A right-to-left run of figures alone, in a document whose complex-script face is not the Latin one: Word's print draws
            // the digits in the run's Latin face, not the complex-script face the letters take: dx2 79a15231's date cells in
            // Calibri, 5b919053, d5a4662f, f7d88376 and others likewise, where the cs name is a face Windows lacks (B Nazanin) or none; a Hebrew face (font table charset B1) is drawn in Arial, heb xb 95e6b1.)
            var run = run
            // (Word reorders "-", "/" and "%" splits only where the run's complex-script language is not Persian: lab bidi-digits2, with
            // w:lang w:bidi="fa-IR" Word draws 15-13 as written, in any table, face or alignment; without it, 13-15.)
            let bidiLanguage = [run.keptXML, named?.char.keptXML].compactMap({ Self._attribute($0, "w:bidi") }).first ?? Self._attribute(document.defaultLangXML, "w:bidi") ?? ""
            let wasRightToLeft = run.rightToLeft && !bidiLanguage.hasPrefix("fa")
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, run.rightToLeft, !splittingVariation,
               rawText.contains(where: { $0.isASCII && $0.isNumber }), rawText.allSatisfy({ ($0.isASCII && $0.isNumber) || "/-:.,% ".contains($0) }),
               let latin = run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily, !latin.isEmpty,
               document.fontCharsets[(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()] != "B1",
               !(theme.complexFaceKeepsDigits?(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") ?? false) {
                _ = latin
                run.rightToLeft = false
            }
            // (A run marked right-to-left in a left-to-right paragraph is an
            // embedding of its own: the one neutral mark that ends its Latin
            // text stands at its start. lo-bbc52bda's "after here:" is
            // ":after here" in Word's print. Moved, not marked: a direction
            // mark would reach the text layer of the PDF.)
            let moved: String? = {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, run.rightToLeft, !p.style.rightToLeft,
                      let last = rawText.last, ":;.,!?".contains(last), rawText.count > 2,
                      !rawText.dropLast().contains(where: { ch in ch.unicodeScalars.contains { ArabicForms.isArabic($0.value) || (0x590...0x8FF).contains($0.value) } || ":;.,!?".contains(ch) })
                else { return nil }
                return String(last) + rawText.dropLast()
            }()
            // (A closing run of ideographic spaces Word lets hang is set with no width: _cutTrailingSpaces.)
            let hung: String? = {
                guard let idx = index, let cut = _trailCut[idx], base + rawText.utf16.count > cut, rawText.containsSubstring("\u{3000}") else { return nil }
                var at = base, out = ""
                for c in (moved ?? String(rawText)) { out.append(c == "\u{3000}" && at >= cut ? "\u{200B}" : c); at += c.utf16.count }
                return out
            }()
            // (A space right before a danda does not hang in Word: the danda may not start a line, so the space is counted in the fit
            // and the line parts after it; lab dnd2, 33 right indents: "जाएगी " stays on a line only while the word and its space fit, the
            // danda alone below. The engine hangs a trailing space, so it is set as a no-break space with a break after it.)
            let spaceBeforeDanda: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && rawText.last == " " && (next == "\u{0964}" || next == "\u{0965}")
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value <= 0x97F })
            let text0: Substring = (spaceBeforeDanda ? Substring(String((hung ?? moved ?? String(rawText)).dropLast()) + "\u{00A0}") : hung.map { Substring($0) } ?? moved.map { Substring($0) } ?? rawText)
            // (A space + U+00A0 gap after an Indic letter is not a place to part the line: Word moves the word before it down with
            // the gap and the word after, one unit. Lab nbsp4 (dx2 6dcc4527 p2): "ਵਿਚ" + SP + NBSP + "ਭਾਰਤ" returns to the line only when
            // the edge holds the whole unit (+31 pt), never when just "ਵਿਚ" + SP would fit; NBSP alone parts at +28, SP+NBSP+NBSP at
            // +34, plain spaces never block. The space is set as a no-break space (same width). Cyrillic, Georgian and Armenian gaps
            // (3200cbc7, a6d5c830, c423753e) do part, so only an Indic letter before the gap counts.)
            let text: Substring = {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, !document.usesEastAsianLayout, text0.containsSubstring(" \u{00A0}") else { return text0 }
                var out = String.UnicodeScalarView()
                var prev: UInt32? = nil
                if base > 0, base - 1 < p.text.utf16.count {
                    prev = p.text.unicodeScalars[p.text.utf16.index(p.text.utf16.startIndex, offsetBy: base - 1)].value
                }
                var changed = false
                let sc = Array(text0.unicodeScalars)
                for (k, u) in sc.enumerated() {
                    if u == " ", k + 1 < sc.count, sc[k + 1].value == 0xA0, let pv = prev, pv >= 0x0900, pv <= 0x0DFF {
                        out.append(Unicode.Scalar(0xA0)!); changed = true
                    } else { out.append(u) }
                    prev = u.value
                }
                if changed { RuleTrace.hit("6dcc4527-indic-space-nbsp-gap-is-one-unit") }
                return changed ? Substring(String(out)) : text0
            }()
            // (A soft hyphen the line ends at is a hyphen to the line breaking
            // too — see `_layoutParagraph`.)
            if let idx = index, let shownSet = _hyphenShown[idx], !shownSet.isEmpty, text.containsSubstring("\u{00AD}") {
                var out = ""
                var at = base
                for ch in text {
                    out.append(ch == "\u{00AD}" && shownSet.contains(at) ? "-" : ch)
                    at += ch.utf16.count
                }
                if out != String(text) { return styled(Substring(out), run, at: base, next: next, symbolsShown: symbolsShown) }
            }
            // (A symbol face's characters drawn as the glyphs they stand
            // for: zh-d0a207ac's Wingdings 2 checkboxes, "£" in the file,
            // drew as "£" in the text's face where Word's print has a box.)
            if !symbolsShown, let glyphs = theme.symbolGlyphs, case let mapped = glyphs(run.fontFamily ?? named?.char.fontFamily, String(text)),
               mapped != String(text), mapped.utf16.count == text.utf16.count {
                return styled(Substring(mapped), run, at: base, next: next, symbolsShown: true)
            }
            let latinFace = theme.wordRules || theme.setsFaceAdvances
                ? theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false) : nil
            // (The face Word sets the Latin characters past ASCII in, where
            // the run names one other than its ASCII face: `w:hAnsi`.)
            let highFace = latinFace == nil ? nil : (run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }
            // (Not where the run says `w:hint="default"` over a Latin hAnsi
            // face: its shared marks are that face's then —
            // zh-785e46f8's "产业链“链长" in 仿宋_GB2312 over a Times hAnsi
            // has its "“" in Times in Word's print, 7.1pt, where ours set
            // a full-width one, 16, and the line lost a character.)
            // (zh-7fd860f9's runs say the same hint over a 仿宋_GB2312
            // hAnsi, and their "“" is full-width in Word's print: the
            // hAnsi face decides.)
            let hint = run.fontHint ?? named?.char.fontHint
            // (A hint over an East Asian face that is itself a Latin one changes nothing: hin-z21320572's "ç", hinted over
            // Normal's Times New Roman, is drawn in the run's own face in Word's print, its line not the Times line's height.)
            let eaFaceIsLatin = theme.wordRules && hint == "eastAsia"
                && (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily)
                    .flatMap { name in name.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) ? nil
                        : theme.faceResolver?(name, false) }.map { !$0.isEastAsian } == true
            let hinted = (hint == "eastAsia" && !eaFaceIsLatin) || (latinFace?.isEastAsian ?? false) && (hint != "default" || (highFace?.isEastAsian ?? true))
            // (… but an en dash, unhinted, is its hAnsi face's where that is
            // a Latin one: zh-ea70c30e's "辦公室 – 投訴", `w:ascii` PMingLiU
            // over an inherited Times hAnsi, sets its "–" in Times in Word's
            // print, half an em, where ours drew PMingLiU's at 0.82. Its
            // quotes and other marks stay East Asian: taken as Latin too,
            // eight documents fell.)
            let hAnsiFace = highFace ?? (run.fontFamily == nil ? nil
                : (named?.char.hAnsiFontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily).flatMap { theme.faceResolver?($0, false) })
            let latinDash = theme.wordRules && (run.fontHint ?? named?.char.fontHint) != "eastAsia" && (latinFace?.isEastAsian ?? false)
                && hAnsiFace.map { !$0.isEastAsian } == true
            // (An em dash, unhinted, is its hAnsi face's where that is an East
            // Asian one over a Latin ascii face: ff493b's "—" in Aptos Bold
            // over a Malgun Gothic hAnsi is Malgun Bold in Word's print, and
            // makes its line 1.73 em tall; ours set it in Aptos.)
            let eastDash = theme.wordRules && RichTextTheme.wordWindowsPages && hint == nil
                && (latinFace?.isEastAsian != true || (run.hAnsiFontFamily != nil && run.hAnsiFontFamily != (run.fontFamily ?? named?.char.fontFamily)))
                && (run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }?.isEastAsian == true
            let em = (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            // (The run's character scale, Word's `w:w`.)
            let wScale = RichTextTheme.wordWidthScale(run.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: theme.wordRules,
                eastAsiaFamily: run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
            let closes = _closesUpMarks(run, named, document)
            // (So may text whose East Asian language has no such rules —
            // its run's own, else the document's: `eastAsianLineRules`.)
            let lineRulesOff = kinsokuOff || (theme.wordRules && !Self._eastAsianLineRules(run, document, named: named))
            // A stretch is of one script, and — where the Latin face
            // stands in at a scale for each kind of character — of one
            // kind: -1 East Asian, else the kind (0 where there is one
            // scale for all).
            let classed = latinFace?.classScales != nil
            // (A right-to-left run whose Latin face is Arial Narrow: its spaces, digits and marks are the Arabic text's, in Arial, not at the
            // narrow face's widths: the Urdu forms 8963bef7, f98daa05 and 0de57755.)
            let narrowLatinInRTL = theme.wordRules && run.rightToLeft && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily)?.trimmingWhitespace().lowercased() == "arial narrow"
            var styles: [Int: TextStyle] = [:]
            // (The grid's addition to each character, unless the run opts
            // out — or its paragraph: zh-268f8d15's footer, "- 1 -" in a
            // text box whose style sets `w:snapToGrid` 0, is Times's own
            // widths in Word's print on a grid of -0.28 an em; ours set it
            // 1.3pt a character closer, and the box, sized so, lost its
            // closing dash.)
            // (A run off it by its style's characters is off it too, where
            // the run says nothing: zh-c25d08c5's Normal sets the characters'
            // `w:snapToGrid` 0 on a grid of -0.25pt, and Word's print has
            // its 16pt ideographs 16 apart; ours set them 15.75 and took a
            // character more a line.)
            let ownGridSay = run.keptXML?.containsSubstring("<w:snapToGrid") ?? false
            let runOffGrid = ownGridSay ? (run.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false)
                : theme.wordRules && (named?.char.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false)
            // (Latin text too, in a paragraph that takes itself off the
            // grid — not one its style takes off, as zh-268f8d15's footer's
            // and zh-3c055c9b's styles do: zh-c2f6d17a's paragraphs set
            // `w:snapToGrid` 0 on a grid of -0.207pt, and Word's print has
            // their Times digits 7.9 apart, half the grid's addition off
            // 8.0, as on it — ours set them 8.0, and a line of "120" and
            // "48" left a character Word takes.)
            let grid = theme.wordRules && !runOffGrid && (p.style.eastAsian["w:snapToGrid"] != "0" || p.style.ownGridOff)
                ? _grid(index, document).chars : nil
            // (Ideographs keep the grid's addition in a paragraph off the
            // grid — not in a run off it, which zh-457a8d62's "(附件一，1頁)"
            // runs are, set at their face's widths in Word's print. Lab
            // `sp`, Word for Windows, zh-3c055c9b's package: its "表標題"
            // text, `w:snapToGrid` 0, at 12pt on a grid of +1pt is set 13
            // apart spaced 0, 12 spaced -0.5 (its style's, counted twice),
            // 10.6 spaced -1.2 — in the body and in a text box alike, and
            // on a grid of -0.5pt 11.5. Ours left the grid out, and the
            // style's spacing then set its 47.8pt header cell "支出傳票"
            // where Word's print has "支出傳". Latin text keeps off it, as
            // zh-268f8d15's footer above.)
            let ideographGrid = grid ?? (theme.wordRules && !runOffGrid ? _grid(index, document).chars : nil)
            // (Where single and double byte widths are balanced, a
            // full-width character takes the run's spacing twice: 16pt
            // text spaced -0.3 is set 15.4 apart.)
            let spacing = (run.letterSpacing ?? (theme.wordRules ? named?.char.letterSpacing ?? _normalChar(document)?.letterSpacing : nil) ?? 0)
                * theme.pixelsPerPoint * scale
            let doubles = theme.wordRules && document.balancesSpaceWidth && spacing != 0
            // A character an embedded subset lacks (`RichResolvedFace.covers`)
            // is set in the face the name has unembedded, Word's fallback,
            // its line that face's height (kind -3).
            let subsetFace = theme.wordRules
                ? theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                      ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true) : nil
            let uncovered = subsetFace.flatMap { face in face.uncoveredFamily.flatMap { alt in face.covers.map { (alt, $0) } } }
            // (Where Word takes them from several faces, each its own kind,
            // -10 down: `RichResolvedFace.uncoveredChain`.)
            let chain = uncovered != nil ? subsetFace?.uncoveredChain : nil
            var chainAt: Int? = nil
            var cambriaWidth = 0.0
            // (Whether the run's shapes are its Latin face's — no East
            // Asian hint, a Latin face that is not an East Asian one.)
            let latinShapes = theme.wordRules && run.fontHint != "eastAsia"
                && theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)?.isEastAsian != true
            // (Word's "fit text", `w:fitText`: the runs of one id are spaced
            // to be val/20 pt wide together. Word for Windows, zh-c2c92639's
            // "本标准主要审查人员：" with fitText 2210: the nine ideographs
            // 11.12pt apart, the colon at its own advance, and the next text
            // 110.5pt from the start; the run's own spacing and the grid's
            // addition are gone. Spaced to it here, through the style, so the
            // line fitter sees what is drawn.)
            // (A cell's `w:tcFitText`, Word for Windows, dx2 28dd0ac0 and lab
            // tcfit1: a cell's line wider than the cell is kept on one line and
            // spaced so it ends at the cell's edge (27.72 for 28.2 at 24pt in a
            // 13684-twip cell); a line that fits is left as it is, not stretched.)
            let tcFit = theme.wordRules && RichTextTheme.wordWindowsPages && textWidth > 1
                && Self._tcFitParagraph(p, index, document)
            let fitGroup = theme.wordRules && RichTextTheme.wordWindowsPages
                ? (Self._fitText(run.keptXML) ?? (tcFit ? (textWidth / (theme.pixelsPerPoint * scale), "tc") : nil)) : nil
            var fitPitch: Double? = nil
            var fitBusy = false
            var plainPiece = false
            var latinNoScale = false
            var fitNone = false
            var fitLastSingle = false
            var fitLastEnd = 0
            func fitSpacing() -> Double? {
                guard let g = fitGroup, !fitNone else { return nil }
                if let f = fitPitch { return f }
                fitBusy = true
                defer { fitBusy = false }
                var total = 0.0, count = 0, lastLength = 0
                var at = 0
                let units = Array(p.text.utf16)
                for r in p.runs {
                    defer { at += r.length }
                    guard tcFit ? at + r.length <= units.count : (Self._fitText(r.style.keptXML)?.id == g.id && at + r.length <= units.count) else { continue }
                    let piece = String(decoding: units[at ..< at + r.length], as: UTF16.self)
                    lastLength = piece.count
                    fitLastEnd = at + r.length
                    for (k, ch) in piece.enumerated() {
                        // (A space the paragraph sets half an em wide
                        // (`wideSpaces`) is measured so, as it is painted:
                        // 6 pt at 12, not the stand-in's 3.3.)
                        if ch == " ", tcFit || wideSpaces.contains(at + k) {
                            total += _glyphWidth(style(-1), "\u{5355}") / 2
                        } else if tcFit, let u = ch.unicodeScalars.first?.value, u >= 0xAC00, u <= 0xD7A3 {
                            // (A Hangul syllable is an em in Word's Korean faces, as it is drawn below.)
                            total += _glyphWidth(style(-1), "\u{5355}")
                        } else {
                            total += _glyphWidth(style(RichLayout.isEastAsian(ch, hinted: hinted) ? -1 : 0), ch)
                        }
                        count += 1
                    }
                }
                let target = g.points * theme.pixelsPerPoint * scale
                var pitch: Double
                if tcFit {
                    // (Word's fit text in a cell, Word for Windows, labs fit1 and mar1/mar2: Word works in 96-dpi screen pixels. Each side's
                    // cell margin is rounded UP to a whole pixel, the room is the cell's width less those, and the spacing is a whole number
                    // of pixels, rounded DOWN, over the gaps (the last letter is drawn apart). 23 of fit1's 24 rows match; the 0.76 px
                    // the room is short of the cell, and which rows wrap their last letter, are OPEN.)
                    fitLastSingle = false
                    let pixel = 0.75 * theme.pixelsPerPoint * scale
                    let slack = Self._tcFitMarginSlack(p, document) * theme.pixelsPerPoint * scale
                    let room = target + slack - 0.76 * pixel
                    let gaps = max(count - 1, 0)
                    pitch = gaps > 0 ? ((room - total) / Double(gaps) / pixel).rounded(.down) * pixel : 0
                } else {
                    fitLastSingle = lastLength == 1
                    let gaps = lastLength == 1 ? count - 1 : count
                    pitch = gaps > 0 ? (target - total) / Double(gaps) : 0
                    // (Word keeps the spacing in twips, rounding a spread up: zh-a4b0f6ea's
                    // 单位(盖章)：…年   月   日 wants 0.073pt and Word sets 0.10, so 日 ends
                    // 1.6pt past the group's width as Word's print does.)
                    if pitch > 0, theme.wordRules, RichTextTheme.wordWindowsPages {
                        let unit = 0.05 * theme.pixelsPerPoint * scale
                        pitch = (pitch / unit - 1e-6).rounded(.up) * unit
                    }
                }
                // (Where the run spacing is taken twice (`doubles`), so is the pitch: Word's step is one pitch more than the glyph's.)
                fitPitch = pitch
                return pitch
            }
            // (Devanagari and Bengali, in Word for Windows: the face Word draws a run in, which sets its line (the joiner below) and its
            // width, as the face's own letters are wider or narrower than the Noto stand-in's — the ratio of the advances in the fonts Word's
            // prints embed, weighted by the letters the pages use: Mangal 1.096, Nirmala UI 1.086 (Bold 1.076, Bengali 1.062), Kokila 0.73.
            // A run mostly of such letters takes it whole. Which face: the complex-script one (Mangal, Kokila), but Kalpurush, which Windows
            // lacks, Word draws in Nirmala UI (ben-z17281487). hin-z18479909's Kokila runs print in Nirmala UI too, where mar-z19707447's and
            // hin-z20740649's, the same markup, print in Kokila: not explained (a print machine without Kokila regular?), the majority taken.)
            // (Kokila as the run's Latin face too: only then are its Latin, digits and space, and its line, Kokila's; with another Latin face
            // (cbb7ae39: Times New Roman beside a Kokila complex face) the Latin keeps that face.)
            let kokilaLatin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "kokila"
            // (The same face seen from a run of Latin: dots, digits, or spaces alone on a line, lab siyam2; spaces after Bengali on its line add nothing.)
            let malgunLatin: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && _malgunAlternate(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily, document)
            // (Arial Unicode MS with the Japanese charset in the font table, no Indic letter in the paragraph: Word prints the Latin text in Yu Gothic, a 1.67 em
            // line; dx2 3922c734, a Danish form, lines 16.7 pt apart at 10 pt against ours 13.4.)
            let aumsLatin: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile && document.fontCharsets["arial unicode ms"] == "80"
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && !p.text.unicodeScalars.contains(where: { Self._isIndic($0.value) || Self._tamil.contains($0.value) || $0.value >= 0x2E80 })
                && !(run.keptXML.map { $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") } ?? false)
            // (Arial Unicode MS in an Indic paragraph, a run with no w:cs: its Latin, digits and marks take the ascii slot, which Word lacks and draws
            // in Yu Gothic, whose line every such run sets whatever it holds; lab aumsy2 (2026-11-09): at 9 pt the steps are 12.8 into and 14.2 out of
            // a Nirmala line, for GST, commas, brackets, dots, digits, "**", regular and bold. fb94294e.)
            // (A Hangul-named face Word's box lacks: its Latin letters, digits and spaces are Yu Gothic's, so they take Yu Gothic's advances; 22de7d.)
            let yuOfMissingHangul: Bool = aumsLatin || (theme.wordRules && RichTextTheme.wordWindowsPages && _yuLatinOfMissingHangulFace(run, named, document)
                && !document.hasIndicText)
            let aumsYuInIndic: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile && document.fontCharsets["arial unicode ms"] == "80"
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && !(run.keptXML?.containsSubstring("<w:cs/>") ?? false) && !(run.keptXML?.containsSubstring("<w:cs ") ?? false)
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xB00 })
            let aumsSpaces: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xB00 })
            let mangalLatinSpace: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "mangal"
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x905 && $0.value <= 0x939 })
            let utsaahLatin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "utsaah"
            let namedFace: String? = text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && Self._isIndic($0.value) }) ? nil : _namedMetricFace(run, named, document, text)
            let indic: (face: String, scale: Double)? = {
                guard theme.wordRules, RichTextTheme.wordWindowsPages else { return nil }
                var count: [Character: Int] = [:], letters = 0
                for u in text.unicodeScalars where u.properties.isAlphabetic {
                    letters += 1
                    let v = u.value
                    if (0x0900 ... 0x097F).contains(v) { count["D", default: 0] += 1 } else if (0x0980 ... 0x09FF).contains(v) { count["B", default: 0] += 1 }
                    else if (0x0A00 ... 0x0A7F).contains(v) { count["P", default: 0] += 1 } else if (0x0A80 ... 0x0AFF).contains(v) { count["G", default: 0] += 1 }
                    else if (0x0C00 ... 0x0C7F).contains(v) { count["T", default: 0] += 1 }
                }
                guard let top = count.max(by: { $0.value < $1.value }) else {
                    // (Tamil: the line of Nirmala UI, 1.079 + 0.251 em, in the prints of tam-* and four of the xd Tamil documents.)
                    // (Width: set per word in flush() from TamilAdvances, a per-codepoint regression fit of Word's word widths
                    // (2864 words, four documents); our PDF embeds no Tamil face, so it cannot be read from glyph hmtx. No scale here.)
                    if text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) }) {
                        // (Vijaya, when the run's complex face is that: Windows has it, and Word draws it as itself; dx2 c30a7a61.)
                        return (_tamilVijaya(run.complexFontFamily, named, document) ? "vijaya" : "nirmala ui", 1)
                    }
                    // (A run with no Indic letter in a Kokila paragraph — dotted leaders, a comma, digits — is Kokila's too, in Word's print: its Latin
                    // face is Kokila as well. Left to the stand-in it set the line by Carlito's split, and stacked with the Kokila runs on the line.)
                    if kokilaLatin,
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "kokila" {
                        return ("kokila", 1)
                    }
                    // (A run with no Indic letter whose ascii and complex faces are both Vrinda, in a Bengali paragraph, is drawn in Vrinda: its Latin takes
                    // Vrinda's advances and its space is Vrinda's 0.598 em; 06800107's "(NAME OF PLACE)": Word 46.7 pt for "(NAME ", ours 41.8.)
                    if (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "vrinda",
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "vrinda",
                       p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF }) {
                        return ("vrinda", 1)
                    }
                    // (A run of only ASCII letters, digits and marks, in a face Windows lacks (SolaimanLipi, Nikosh), inside a Bengali paragraph: Word draws it in Mangal,
                    // at Mangal's advances; xd 73caaeda's "Sterile" 35.5 pt at 12 pt, the comma 3.45, where the stand-in gave 31.1 and 3.0.)
                    if _asciiRunInMissingBengaliFace(run, named, document, text, p.text) {
                        RuleTrace.hit("word-missing-bengali-face-latin-is-mangal-advances")
                        return ("mangal", 1)
                    }
                    // (A Latin-only run whose ascii and complex faces are the SAME face Windows lacks, and which Word draws in Shonar Bangla (the
                    // usb0 rule), in a Bengali paragraph: Word draws the Latin in Shonar Bangla too, at the authored size; lab bnmix2 latK, bfc234.)
                    if let f = _shonarLatinRunFace(run, named, document, p.text) {
                        RuleTrace.hit("word-latin-in-a-missing-bengali-face-run-is-shonar-bangla")
                        return (f, 1)
                    }
                    // (A run of Bengali characters with no letter (digits, signs, marks), in a face Windows lacks (Nikosh, Kalpurush...): Word draws it in Nirmala UI, so the digits take
                    // Nirmala's own advances from the table; 2263e221's "\u{9EE}" is 8.35 pt in Word, 6.5 in the stand-in.)
                    if text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF }),
                       !text.unicodeScalars.contains(where: { ($0.value < 0x980 && $0.value >= 0x900 && $0.value != 0x964 && $0.value != 0x965) || $0.value >= 0xA00 && Self._isIndic($0.value) }),
                       !["mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla", "kalimati", "latha", "vijaya"].contains(
                        (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()),
                       Self._bengaliMissingFace((run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased(), document) != "shonar bangla" {
                        RuleTrace.hit("word-bengali-digits-only-run-in-a-missing-face-is-nirmala")
                        return ("nirmala ui", 1)
                    }
                    // (A run of only a danda in a missing face, in a paragraph of Devanagari or Bengali: Word draws it in Nirmala UI, 3.89 pt at 9 pt, where the
                    // stand-in's Bengali danda is 3.41; lab dnd1: the lone "।" stays on line 2 in ours at indent 0 where Word's wraps it.)
                    if text.unicodeScalars.contains(where: { $0.value == 0x964 || $0.value == 0x965 }),
                       !text.unicodeScalars.contains(where: { $0.value != 0x964 && $0.value != 0x965 && $0.value != 0x20 }),
                       p.text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && ($0.value >= 0x900 && $0.value <= 0x97F) }),
                       !p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF }),
                       !["mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla", "kohinoor bangla", "kalimati", "latha", "vijaya"].contains(
                        (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()) {
                        RuleTrace.hit("word-danda-only-run-in-a-missing-face-is-nirmala")
                        return ("nirmala ui", 1)
                    }
                    // (A run of spaces and tabs in a missing Bengali face (Nikosh, SolaimanLipi) inside a paragraph of Bengali letters: Word draws the spaces in Mangal
                    // but they do not raise the line, which stays Nirmala UI's 1.33 em: dx2 2263e221's bold heading, 14.6 pt apart in Word, 18.5 in ours.)
                    if !text.isEmpty, !text.unicodeScalars.contains(where: { $0.value != 0x20 && $0.value != 0x09 }),
                       Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil
                        || (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "siyam rupali",
                       p.text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value >= 0x980 && $0.value <= 0x9FF }),
                       !p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && !$0.properties.isAlphabetic && $0.properties.generalCategory != .nonspacingMark && $0.properties.generalCategory != .spacingMark }) {
                        RuleTrace.hit("word-spaces-in-a-missing-bengali-face-keep-the-nirmala-line")
                        return ("nirmala ui", 1)
                    }
                    if let named = _namedMetricFace(run, named, document, text) {
                        RuleTrace.hit("word-run-with-no-indic-letters-takes-the-line-of-the-face-it-names")
                        return (named, 1)
                    }
                    // (Word's print of dx2 e86e26f7: spaces, commas, brackets and digits that fall back to Malgun inside a Bengali line do not raise it, a
                    // Bengali-only line stays at Nirmala's 13.3 pt; a run holding Latin letters still does.)
                    if malgunLatin,
                       text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 && !($0.value < 0x80 && !(($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A)) })
                        || !p.text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) && text.unicodeScalars.contains(where: { $0.value == 0x20 }) {
                        RuleTrace.hit("word-malgun-alternate-latin-run-is-malgun-line")
                        return ("malgun gothic", 1)
                    }
                    if aumsLatin, text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }) {
                        RuleTrace.hit("word-aums-latin-run-is-a-yu-gothic-line")
                        return ("yu gothic", 1)
                    }
                    if aumsYuInIndic, text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x7F }) {
                        RuleTrace.hit("word-aums-latin-run-in-indic-paragraph-is-a-yu-gothic-line")
                        return ("yu gothic", 1)
                    }
                    if utsaahLatin,
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "utsaah" {
                        return ("utsaah", 1)
                    }
                    return nil
                }
                let all = count.values.reduce(0, +)
                let cs = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                // Which face: the complex-script one where Windows has it; a face it lacks (Arial, Times, Kalpurush, Nikosh, Arial Unicode MS...)
                // Word draws in Nirmala UI, but Kalimati (Devanagari) in Mangal, and a Bengali face whose font-table signature is Bengali-only in Shonar Bangla
                // (labs bnfield: the signature decides, not name, panose, charset or alternate; dx2 prints).
                var face = cs
                switch cs {
                case "kalimati": face = "mangal"
                case "mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla": break
                default: face = top.key == "B" ? Self._bengaliMissingFace(cs, document) : (document.devanagariFirstRunMangal && cs != "times new roman" ? "mangal" : "nirmala ui")
                }
                guard var scale = Self._indicScale[face]?[top.key] else { return nil }
                if face == "nirmala ui", bold { scale *= 1.076 / 1.086 }
                // Shruti Bold runs 4% narrower than Shruti: dx2 16200736's heading, word starts 111.0 pt apart in Word, 115.9 in ours.
                if face == "shruti", bold { scale *= 0.958 }
                return (face, all * 2 >= letters ? scale : 1)
            }()
            func style(_ kind: Int) -> TextStyle {
                if !fitBusy, !plainPiece, !latinNoScale, let s = styles[kind] { return s }
                var styled = run
                let grown = wholeRaised ? theme.raisedLineHeight(for: run, in: p.style, named: named, eastAsian: kind < 0, gridPitch: pitch) : nil
                if let grown { styled.raised = grown.raise }
                if kind == -3, let (alt, _) = uncovered { styled.eastAsiaFontFamily = alt }
                if kind == -5, let h = run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily { styled.eastAsiaFontFamily = h }
                if kind <= -10, let chain, -10 - kind < chain.count { styled.eastAsiaFontFamily = chain[-10 - kind].family }
                var s = theme.textStyle(for: styled, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: kind < 0, gridPitch: pitch,
                                        characterClass: classed && kind >= 0 ? kind : nil, characterGrid: kind < 0 ? ideographGrid : grid, scriptHidden: true)
                if doubles, kind < 0 { s = s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + spacing) }
                if kind == -4, let cjk = Self._cjkFaceFamily {
                    RuleTrace.hit("word-east-asian-shape-is-the-cjk-faces-glyph")
                    s = s.copyWith(fontFamily: cjk)
                }
                // (A space set in the ideographs' face keeps the stand-in's width.)
                // (… and no line of its own: the face a space resolves to
                // is not always the ideographs', and its descent made the
                // line taller — zh-1563bd74's footer line, 19.0pt on the
                // Mac against the ideographs' 18.6, and Word's lab `hfl`
                // gives trailing spaces no height at all.)
                if kind == -2 { s = s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + _spaceWidth(style(classed ? RichResolvedFace.characterClass(" ") : 0)) - _spaceWidth(s), height: Self.shadeShows(run.highlight) ? s.height : 0.01) }
                // (Set to the original's widths, the stand-in's own
                // kerning is no part of them: Arial's pair of ones.)
                if kind >= 0, latinFace?.advances != nil { s = s.copyWith(fontFeatures: [FontFeature("kern", 0)]) }
                if kind >= 0, let indic, indic.scale != 1, !latinNoScale { s = s.copyWith(scaleX: indic.scale) }
                // (The run's own line is the face's, not the stand-in's, where the face's is the shorter: Aparajita's 1.18 em (a516bfe9: 2.7 to 92.9) where Noto
                // Sans Devanagari's is taller; the joiner above only raises a line.)
                if kind >= 0, let indic, (indic.face == "kokila" && (kokilaLatin || text.unicodeScalars.contains(where: { Self._isIndic($0.value) }))) || (indic.face == "utsaah" && utsaahLatin) || (indic.face == "malgun gothic" && malgunLatin) || (indic.face == "yu gothic" && (aumsLatin || aumsYuInIndic)) || indic.face == "vijaya" || indic.face == "latha" || indic.face == "shonar bangla" || (namedFace != nil && namedFace != "mangal") || (indic.face == "nirmala ui" && !plainPiece && !p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) })), let m = Self._indicLines[(indic.face == "shonar bangla" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? "shonar bangla bold" : indic.face], p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5 {
                    // (Kokila's line: its own ascent and descent, above and below the baseline, for every run on the line: the stand-ins'
                    // (Carlito's, Noto's) are taller above and set the line 2-3 pt low and 1.4 pt per line too far apart.)
                    // (A multiple under single too: dx2 hin-z20740649's 0.9 lines are 13.5 pt apart in Word's print, Kokila's 15.0 x 0.9.)
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    // (Word keeps the baseline where single spacing puts it and gives the multiple's extra below it; a multiple under single is cut from
                    // the top. lab mmatrix2 (2026-11-09): Kokila 18's gap to the next line is 40.8 / 43.9 / 47.0 / 51.1 for a previous 1.0 / 1.15 / 1.3 / 1.5
                    // whatever the next multiple is; `Self._multipleSplit`.)
                    // (Kokila only so far: the other faces' lines were fitted with the extra spread over both sides; each gets the shared split when its own dx2 documents agree.)
                    let split = indic.face == "kokila" || indic.face == "latha" || indic.face.hasPrefix("shonar bangla") ? Self._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple) : (m.0 * multiple, m.1 * multiple)
                    // (A character scale (w:w) is laid out as a larger size; the line's height follows the authored size: dx2 3f7da49c's 105% title, 23.7 pt in Word, 24.9 here.)
                    let wScale = RichTextTheme.wordWidthScale(run.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: theme.wordRules,
                        eastAsiaFamily: run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
                    let lineSize = wScale > 0.01 ? size / wScale : size
                    // (A run that names Calibri takes Calibri's deeper descent (win 550/2048 = 0.2686 em) under the Nirmala line even where the line holds no Latin
                    // letter: lab dpitch (Word, 12 pt): Calibri-named Devanagari lines are 16.2 pt, Arial- and Times-named 15.96. d912c25b p2.)
                    var below = split.1
                    if indic.face == "nirmala ui", theme.wordRules, RichTextTheme.wordWindowsPages,
                       (run.fontFamily ?? named?.char.fontFamily ?? "").trimmingWhitespace().lowercased() == "calibri",
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "calibri" {
                        below = max(below, 550.0 / 2048 * multiple)
                    }
                    s = s.copyWith(ascentOverride: split.0 * lineSize, descentOverride: below * lineSize, height: (m.0 * multiple + (below == split.1 ? m.1 * multiple : below)) * lineSize / size, leadingDistribution: .even)
                }
                // (Latin letters in a run whose ascii face is Nirmala UI itself (Semilight too) beside Indic text are drawn in Nirmala, so they take its line and add no Latin
                // stand-in's: dx2 426d1cc2's "l:f" in a Punjabi paragraph went 21.1 to 23.1 pt once the line was no longer held to one pitch.)
                if kind >= 0, plainPiece || indic == nil, indic == nil || indic?.face == "nirmala ui", theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5,
                   { let f = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased(); // (Spaces and marks in a run of their own (no letters, Latin or Indic) are not Nirmala's line: af19d946 ", " runs, Calibri in Word'"'"'s print; Arial'"'"'s marks are.)
                       return (f.hasPrefix("nirmala ui") && text.unicodeScalars.contains(where: { ($0.value < 0x250 && ($0.properties.isAlphabetic || ($0.value >= 0x30 && $0.value <= 0x39))) || (Self._isIndic($0.value) && !(run.keptXML?.containsSubstring("<w:cs") ?? false)) }))  || f == "arial" }(),
                   !p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) }),
                   indic != nil || (!text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) && text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }) && p.text.unicodeScalars.contains(where: { Self._indic.contains($0.value) })),
                   let m = Self._indicLines["nirmala ui"] {
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    // (A Nirmala-named run's pieces carry the line's height too; an Arial piece only the ascent/descent split: a line height on its stand-in raised the
                    // line 0.6 pt (dx2 f96948dd 16.57 against Word's 15.96, 1ca6c218's Arial-only title line 32 against 28.6), where the split alone stacks correctly.)
                    let nirmalaNamedRun = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui")
                    s = s.copyWith(ascentOverride: m.0 * multiple * size, descentOverride: m.1 * multiple * size, height: nirmalaNamedRun ? (m.0 + m.1) * multiple : nil, leadingDistribution: nirmalaNamedRun ? .even : nil)
                }
                // (A run of Latin in a face other than Kokila inside a Kokila paragraph: Word stands its line on that face's ascent (above Kokila's) and keeps the
                // Kokila split below it, at a line multiple too (dx2 cbb7ae39's Times New Roman "IRB", lab cb7; its 1.57-line paragraphs: the line is 2.0 pt taller, the
                // extra under the baseline unchanged). White space and the invisible marks beside Kokila text set no line of their own.)
                // (Shonar Bangla beside Arial: the same line, the Latin face's ascent (with its line gap) over the Bengali face's descent; lab stk1.)
                let latinOwner: String? = p.runs.contains(where: { ($0.style.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "kokila" }) ? "kokila"
                    : (p.runs.contains(where: { Self._bengaliMissingFace(($0.style.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased(), document) == "shonar bangla" })
                    ? "shonar bangla" : nil)
                if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, !kokilaLatin || (run.keptXML?.containsSubstring("<w:cs") ?? false), p.style.lineHeightPoints == nil,
                   let latinOwner, let m = Self._indicLines[latinOwner], let size = s.fontSize, size > 0.5,
                   !text.unicodeScalars.contains(where: { Self._isIndic($0.value) }), p.text.unicodeScalars.contains(where: { Self._indic.contains($0.value) }) {
                    // (Latin letters stack only when drawn in a face other than the line's Indic face: a run whose ascii face IS its complex face, such as Shonar Bangla on both, takes that face's own line and adds no Latin ascent; dx2 3f7da49c.)
                    let ownAscii: String = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                    let ownComplex: String = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                    let ownIndic: Bool = Self._bengaliMissingFace(ownAscii, document) == "shonar bangla"
                    let ownFace: Bool = latinOwner == "shonar bangla" && ownAscii == ownComplex && ownIndic
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    let split = Self._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple)
                    var above = split.0 * size
                    // (A run with the w:cs flag is drawn wholly from its complex-script face: Kokila's "(" in dx2 cbb7ae39's first lines, Times New Roman's where cs is the major bidi face.)
                    let csFlag = (run.keptXML?.containsSubstring("<w:cs") ?? false)
                    let csFace = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                    if !ownFace, text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 && (latinOwner != "shonar bangla" || !ownIndic || $0.properties.isAlphabetic || ($0.value >= 0x30 && $0.value <= 0x39)) }), !(csFlag && csFace == "kokila"),
                       let b = theme.baseline(for: run, in: { var single = p.style; single.lineSpacing = 1; return single }(), named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline),
                       let pt = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, pt > 0.5 {
                        above = max(above, b / pt * size)
                    }
                    s = s.copyWith(ascentOverride: above, descentOverride: split.1 * size, height: (above + split.1 * size) / size, leadingDistribution: .even)
                }
                if kind >= 0, let indic, indic.face == "aparajita" || indic.face == "vijaya", let m = Self._indicLines[indic.face], p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5 {
                    let multiple = p.style.lineSpacing > 1 ? p.style.lineSpacing : 1
                    s = s.copyWith(height: (m.0 + m.1) * multiple, leadingDistribution: .even)
                }
                if let grown, s.fontSize ?? 0 > 0.5 { s = s.copyWith(height: grown.height) }
                // (Thai in Browallia New or Angsana New: every run, Latin and Thai, carries its face's own split of the line (hhea ascent and
                // descent, by weight), so a line is its tallest ascent over its deepest descent, as Word's: a bold run raises only the lines it is
                // on (xd b96afb37 20.8 pt, e93587db 19.0 beside 20.6), with no stacking of the 0.82-size Thai stand-in on the Latin one.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil, s.ascentOverride == nil,
                   let size = s.fontSize, size > 0.5, let h = s.height, let split = Self._thaiLineSplit(s.debugLabel, bold: s.fontWeight == .bold), thaiParagraph {
                    s = s.copyWith(ascentOverride: size * h * split, descentOverride: size * h * (1 - split), leadingDistribution: .even)
                }
                // (Yu Gothic and Yu Mincho ideographs stand a line on the face's own split, 1.18 em above the baseline and 0.5 below
                // (`EastAsianFace.baseline`), whatever else is in the paragraph: the stand-in's own split, 0.8 above, lifted the title lines of
                // xb jpn 12d9fb 2.6pt (a Latin-only line among them kept a paragraph strut off), Word's first baseline 18.8 at 16pt, ours 21.4.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, kind < 0, pitch == nil, p.style.lineHeightPoints == nil, s.ascentOverride == nil,
                   p.style.lineSpacing > 0, let size = s.fontSize, size > 0.5,
                   let fam = (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily)?.trimmingWhitespace().lowercased(),
                   ["游ゴシック", "yu gothic", "游明朝", "yu mincho"].contains(fam), let face = theme.faceResolver?(fam, true) {
                    let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    if let t = (bold ? face.boldBaseline : nil) ?? face.baseline, let nat = (bold ? face.boldHeight : nil) ?? face.naturalHeight {
                        RuleTrace.hit("word-yu-ideograph-line-stands-on-its-own-ascent")
                        let sp = Self._multipleSplit(ascent: t, descent: nat - t, multiple: p.style.lineSpacing)
                        s = s.copyWith(ascentOverride: size * sp.0, descentOverride: size * sp.1, height: nat * max(1, p.style.lineSpacing), leadingDistribution: .even)
                    }
                }
                // (A Latin stretch in a paragraph that stands its ideographs on Yu's own split keeps its face's baseline too, the line multiple's
                // extra below it as in a Latin-only paragraph, not shared out above: xb jpn 12d9fb's subtitle, "―Amazon" 5 pt low, the next line 6 high.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, kind >= 0, pitch == nil, p.style.lineHeightPoints == nil, s.ascentOverride == nil,
                   p.style.lineSpacing > 1, let size = s.fontSize, size > 0.5, run.ruby == nil,
                   let fam = (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily)?.trimmingWhitespace().lowercased(),
                   ["游ゴシック", "yu gothic", "游明朝", "yu mincho"].contains(fam),
                   p.text.unicodeScalars.contains(where: { $0.value >= 0x3040 && $0.value < 0xA000 }),
                   let latin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily)?.trimmingWhitespace(),
                   let face = theme.faceResolver?(latin, false) {
                    let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    var single = p.style; single.lineSpacing = 1
                    let nat0 = (bold ? face.boldHeight : nil) ?? face.naturalHeight ?? theme.naturalLineHeight(family: face.family, bold: bold, italic: run.italic)
                    if let b = theme.baseline(for: run, in: single, named: named, eastAsian: false, gridPitch: pitch), let pt = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, pt > 0.5,
                       case let t = b / pt, case let nat = nat0 {
                        RuleTrace.hit("word-latin-beside-yu-keeps-baseline-extra-below")
                        let sp = Self._multipleSplit(ascent: t, descent: nat - t, multiple: p.style.lineSpacing)
                        s = s.copyWith(ascentOverride: size * sp.0, descentOverride: size * sp.1, height: nat * p.style.lineSpacing, leadingDistribution: .even)
                    }
                }
                // (A run with ruby over it makes its line room for the ruby.)
                if theme.wordRules, run.ruby != nil, s.fontSize ?? 0 > 0.5,
                   let h = theme.rubyLine(for: run, in: p.style, named: named, eastAsian: kind < 0, gridPitch: pitch) {
                    s = s.copyWith(height: h.height)
                    // (Off a grid the room for the ruby is all over the baseline, not shared with the line's foot:
                    // xb jpn 231fe1 p1 "申請者" under ﾌﾘｶﾞﾅ stands 7pt lower, the next paragraph where it was. Single spacing only: at 1.15 Word's ruby line is shorter, lo-181b561b0a.)
                    if gridPitchIsNil(pitch), p.style.lineHeightPoints == nil, abs(p.style.lineSpacing - 1) < 0.005, h.descent > 0, s.ascentOverride == nil, let size = s.fontSize,
                       !(index.map { _verticalBody($0) } ?? false) {
                        s = s.copyWith(ascentOverride: size * (h.height - h.descent), descentOverride: size * h.descent, leadingDistribution: .even, debugLabel: (s.debugLabel ?? "") + " ruby-line")
                    }
                    if h.raise != 0, NativeParagraphBuilder.supportsBaselineShift, !(index.map { _verticalBody($0) } ?? false) {
                        s = s.copyWith(baselineShift: (s.baselineShift ?? 0) - h.raise * theme.pixelsPerPoint * scale)
                    }
                } else if mixedRubyRaise != 0, run.ruby == nil, s.fontSize ?? 0 > 0.5 {
                    // (The rest of a one-line paragraph moves with its ruby's base.)
                    s = s.copyWith(baselineShift: (s.baselineShift ?? 0) - mixedRubyRaise * theme.pixelsPerPoint * scale)
                }
                // (A run of tabs alone takes no line of its own in a paragraph of
                // other text: windows-1's lab `ttab`, zh-147bdae0's "四、承諾事項"
                // — its 16pt bold tab after 14pt text, at the line's end, mid-line
                // or 14pt, leaves the 1.5 lines 27.24 apart in Word's print, the
                // 14pt text's; the tab's line set the heading 9pt lower.)
                // (Text: not a drawing's anchor alone — zh-38d26944's red-headed
                // rule stands in a paragraph of a tab and its line's anchor,
                // whose line the tab holds.)
                if theme.wordRules, !text.isEmpty, text.allSatisfy({ $0 == "\t" }),
                   p.text.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }), s.fontSize ?? 0 > 0.5 {
                    s = s.copyWith(height: 0.01)
                }
                // (A floating drawing's anchor mark, in a paragraph that has other characters, gives its line no height of its
                // own: ba75c926's first paragraph holds two anchors, a 24pt bold run and a 16pt one, and a 20pt bold space; Word sets
                // the line by the space (baseline 56.2 for the next paragraph), ours by the 24pt anchor run (60.4).)
                if theme.wordRules, RichTextTheme.wordWindowsPages, !text.isEmpty, text.allSatisfy({ $0 == "\u{FFFC}" }),
                   let key = run.inlineImage, let image = p.inlineImages[key], image.float != nil || image.textBox != nil,
                   p.text.contains(where: { $0 != "\u{FFFC}" }), s.fontSize ?? 0 > 0.5 {
                    s = s.copyWith(height: 0.01)
                }
                // (A run of spaces alone takes the line's height, not its own.)
                // (An en, an em and a four-per-em space are spaces to Word for
                // Windows as the plain one is, and give a line no height of
                // their own: lab `sp` (2026-10-30), rows of one 48pt space in a
                // 12pt row — U+0020, U+2002, U+2003 and U+2005 leave it 14.6pt,
                // in any colour, bold, highlighted or shaded; U+2000, U+2001,
                // U+2004, U+2006…200A, U+202F and a letter make it 56.7.
                // tdf153136 sets them so, 48pt, by the dozen.)
                let widerSpaces = theme.wordRules && RichTextTheme.wordWindowsPages
                let spaceLike: (Character) -> Bool = {
                    $0 == " " || $0 == "\t" || $0 == "\u{3000}"
                        || (widerSpaces && $0.unicodeScalars.count == 1 && [0x2002, 0x2003, 0x2005].contains($0.unicodeScalars.first!.value))
                }
                @inline(never) func _r0() {
                if let lineSize, !text.isEmpty, text.allSatisfy(spaceLike), let px = s.fontSize, px > 0.5 {
                    let own = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    if !lineSize.blank, kind != -2, !text.containsSubstring("\t"), !text.containsSubstring("\u{3000}") {
                        // (Beside other characters, spaces have no height
                        // at all, whatever their face or size: lab `cap2`
                        // (Word 16, 2026-10-17) — two 14pt or 20pt spaces
                        // opening a 10.5pt 宋体 caption, in 仿宋_GB2312,
                        // YaHei, Times or a face no one has, leave it one
                        // pitch of the grid, and `cap3` 20pt spaces before,
                        // within or after 10.5pt text one 10.5pt line.
                        // Sized to the text in their own face they still
                        // counted: YaHei's 10.5 is two pitches, and
                        // zh-2a241df1's caption took a line more. A tab, a
                        // no-break space and a glyph do count.)
                        // (Shaded, they paint the shade: zh-1078e06f's grey blanks
                        // after a signature line; a 0.01 box paints none.)
                        if !Self.shadeShows(run.highlight) || own > lineSize.size + 0.01 { s = s.copyWith(height: 0.01) }
                    } else if own > lineSize.size + 0.01 || (lineSize.blank && own < lineSize.size - 0.01)
                                || (lineSize.blank && p.style.mark?.fontFamily != nil && p.style.mark?.fontFamily != run.fontFamily) {
                        // (Same size, other face: a line of spaces alone is the mark's face's
                        // in Word whatever the size — lab picm2: Malgun 11pt spaces under a
                        // BatangChe 11pt mark are 10.4pt under the line above, not Malgun's 15.4.)
                        var sized = run
                        sized.fontSize = lineSize.size
                        // (The mark's line in the mark's Latin face, where
                        // the line is of spaces alone: zh-1eeb9f9a's "　"
                        // cells, 9pt in 仿宋_GB2312 under a 12pt Times New
                        // Roman mark, are one 15.6pt pitch in Word's print —
                        // Times' 12pt line; in the run's 仿宋 (YaHei to
                        // Word on a Mac) ours were two, and p11's row they
                        // stand in went over whole where Word parts it.)
                        if theme.wordRules, lineSize.blank {
                            // (A mark with no face of its own is drawn in the
                            // document default: kor-z22157092's Consolas
                            // " " line is the empty line's, not Consolas 10.)
                            sized.fontFamily = p.style.mark?.fontFamily
                        }
                        let r = theme.textStyle(for: sized, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                                eastAsian: kind < 0, gridPitch: pitch, characterClass: classed && kind >= 0 ? kind : nil,
                                                characterGrid: kind < 0 ? ideographGrid : grid, scriptHidden: true)
                        if let rs = r.fontSize, let rh = r.height, s.height != nil { s = s.copyWith(height: rs * rh / px) }
                        else if s.height == nil, r.height == nil {
                            // (Single lines in a face of its own metrics
                            // have no height to scale: the spaces are set
                            // at the mark's size, as wide as their own —
                            // IllustrativeCases' line of 11pt spaces under
                            // an 8pt mark is 9.2pt in Word's print, and at
                            // 12.65 the last of three empty lines under a
                            // table went over the page.)
                            s = r.copyWith(letterSpacing: (r.letterSpacing ?? 0) + _spaceWidth(s) - _spaceWidth(r))
                        }
                    }
                }
                }
                _r0()
                if !fitBusy, fitGroup != nil, s.fontSize ?? 0 > 0.5, let f = fitSpacing() {
                    let own = text.count == 1 && fitLastSingle && base + rawText.utf16.count >= fitLastEnd ? 0 : f
                    s = s.copyWith(letterSpacing: kind == -2 ? (s.letterSpacing ?? 0) + own : own)
                }
                if !fitBusy, !plainPiece, !latinNoScale { styles[kind] = s }
                return s
            }
            // (A zero-width character the layout puts in — a break the
            // engine would not make, or a joiner — in the Latin kind's
            // style whatever the text around it: in the East Asian style
            // its glyph is the Latin base family's, whose ascent and
            // descent split the em otherwise than the CJK face's, and a
            // line with both grew 0.9pt at 12pt — zh-799c91cd's held
            // spaces, and every line with a break before a quote.)
            // (With none of the run's spacing: a run spaced 0.6pt gave
            // each break it holds 0.6pt the fitter does not count, and
            // zh-b00fef0d's "…改革决策部署" lost "署" to the next line.)
            // (Nor any height: it sets no line, as a space sets none beside
            // other text. zh-7773163d's p38 paragraph, a 17pt "一、" head
            // over 16pt text (no strut, two sizes), took the Latin face's
            // deeper descent from its joiners, and its lines stood 24.6pt
            // apart where Word's print has 23.0. Except in a math face's
            // run, whose letters are set at 0.6 of its line to keep the
            // platform math face's split out of it: there the joiners are
            // what gives the line Cambria Math's 1.17 em, bug59058's
            // formula lines 15.24pt apart as in Word's print, 15.0 without.)
            func zeroWidth(_ kind: Int) -> TextStyle {
                let s = style(kind < 0 ? 0 : kind).copyWith(letterSpacing: 0)
                return theme.wordRules && s.fontSize ?? 0 > 0.5 && !(kind >= 0 && latinFace?.setsMath == true) ? s.copyWith(height: 0.01) : s
            }
            // (Arabic set to the original face's joining widths, word by
            // word — it parts only at spaces: each word its own span, drawn
            // condensed or widened to the width its joining forms have in
            // that face (`RichResolvedFace.joinedAdvances`), which the line
            // breaking then measures too. Spacing would split a joined
            // word's shaping or, on a zero-width character, be measured and
            // not drawn right to left — zh-d97c5474's lines broke as Word's
            // and stood 47pt past the margin — and on the spaces it ran the
            // words together, Noto Naskh being 11% wider than Arial.)
            let joinedFace: RichResolvedFace? = {
                guard theme.wordRules, run.rightToLeft else { return nil }
                let normal = _normalChar(document)
                let latin: String? = run.fontFamily ?? named?.char.fontFamily ?? normal?.fontFamily ?? theme.fontFamily
                let complex: String? = run.complexFontFamily ?? named?.char.complexFontFamily ?? normal?.complexFontFamily
                // (No complex-script face named, and Arial Narrow for Latin: Word sets the Arabic in Arial, not in the narrow face.)
                var name = complex ?? latin
                if complex == nil, name?.trimmingWhitespace().lowercased() == "arial narrow" { name = "Arial" }
                return theme.complexFaceResolver?(name)
            }()
            // (A zero-width non-joiner stays inside the word: Word sets the
            // two parts as two joined words and the mark at no width, where
            // the stand-in gave it 3pt and the parts no scale — lo
            // tdf163575's "می‌توان" 37pt to Word's 27.)
            func isArabic(_ c: Character) -> Bool { c.unicodeScalars.first.map { ArabicForms.isArabic($0.value) || $0.value == 0x200C } ?? false }
            func joinedScaled(_ word: Substring, _ s: TextStyle) -> TextStyle {
                // (Hebrew, word by word, at the advances the face carries per letter: David's, from Word's prints.)
                if let joinedFace, word.unicodeScalars.contains(where: { $0.value >= 0x5D0 && $0.value <= 0x5EA }), let px = s.fontSize, px > 0.5,
                   let table = s.fontWeight == .bold ? joinedFace.boldOtherAdvances : joinedFace.otherAdvances,
                   word.unicodeScalars.allSatisfy({ table[$0.value] != nil }) {
                    let ems = word.unicodeScalars.reduce(0.0) { $0 + (table[$1.value] ?? 0) }
                    let shaped = _wordWidth(s, String(word))
                    RuleTrace.hit("word-hebrew-face-own-advances")
                    return shaped > 0.01 ? s.copyWith(scaleX: ems * px / shaped) : s
                }
                guard let joinedFace, let first = word.first, isArabic(first), first != "\u{200C}", word.allSatisfy(isArabic),
                      let table = s.fontWeight == .bold ? joinedFace.boldJoinedAdvances : joinedFace.joinedAdvances, let px = s.fontSize, px > 0.5
                else { return s }
                var ems = 0.0, shaped = 0.0
                // (The mark is a grapheme extender: it is one Character with the
                // letter before it, so the word is cut by its scalars.)
                for part in word.unicodeScalars.split(separator: "\u{200C}", omittingEmptySubsequences: true) {
                    // (A piece at the start or end of the run joins the letter beyond it.)
                    let atStart = part.startIndex == word.unicodeScalars.startIndex, atEnd = part.endIndex == word.unicodeScalars.endIndex
                    var before: UInt32? = nil
                    if atStart, word.startIndex == text.startIndex, base > 0, base - 1 < p.text.utf16.count {
                        let i = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: base - 1)
                        before = p.text.unicodeScalars[i].value
                    }
                    let after: UInt32? = atEnd && word.endIndex == text.endIndex ? next?.unicodeScalars.first?.value : nil
                    let clusters = s.fontWeight == .bold ? joinedFace.boldJoinedClusters : joinedFace.joinedClusters
                    guard let e = ArabicForms.width(part.map { $0.value }, table, before: before, after: after, clusters: clusters) else { return s }
                    ems += e
                    shaped += _wordWidth(s, String(String.UnicodeScalarView(part)))
                }
                return shaped > 0.01 ? s.copyWith(scaleX: ems * px / shaped) : s
            }
            var notoStyle: TextStyle? = nil
            var segoeStyle: TextStyle? = nil
            var devanagariStyles: [String: TextStyle?] = [:]
            var spans: [TextSpan] = []
            var start = text.startIndex
            var current: Int? = nil
            func flush(_ end: Substring.Index) {
                guard let kind = current, start < end else { return }
                if yuOfMissingHangul, text[start ..< end].unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x250 }),
                   let y = Self._yuLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind))) {
                    RuleTrace.hit("word-missing-hangul-face-latin-takes-yu-gothic-advances")
                    spans.append(contentsOf: capped(text[start ..< end], run, y))
                    start = end
                    return
                }
                if joinedFace != nil, text[start ..< end].unicodeScalars.contains(where: { $0.value == 0x200C }) {
                    // (The mark at no width, between two words each at its
                    // own: Word's print has it so, the stand-in 3pt.)
                    let word = text[start ..< end]
                    let base = style(kind)
                    var part = String.UnicodeScalarView()
                    func put() {
                        guard !part.isEmpty else { return }
                        let piece = String(part)
                        spans.append(contentsOf: capped(Substring(piece), run, joinedScaled(Substring(piece), base)))
                        part = String.UnicodeScalarView()
                    }
                    for u in word.unicodeScalars {
                        if u.value == 0x200C {
                            put()
                            let alone = TextPainter(text: TextSpan(text: "\u{200C}", style: base), textDirection: .ltr)
                            alone.layout(minWidth: 0, maxWidth: 100_000)
                            let own = alone.width
                            alone.dispose()
                            spans.append(TextSpan(text: "\u{200C}", style: base.copyWith(letterSpacing: (base.letterSpacing ?? 0) - own)))
                        } else { part.append(u) }
                    }
                    put()
                    start = end
                    return
                }
                // (A Tamil run whose complex face Windows lacks (Arial Unicode MS): its Latin, digits and punctuation Word draws in Leelawadee UI.)
                let leelawadeeLatin = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                if kind >= 0, indic?.face == "nirmala ui" || indic?.face == "vijaya", text[start ..< end].unicodeScalars.contains(where: { Self._tamil.contains($0.value) }) {
                    // (Tamil, word by word, at the widths of Nirmala UI's code points: `TamilAdvances`.)
                    let base = style(kind)
                    var wordStart = start
                    func putWord(_ a: Substring.Index, _ b: Substring.Index) {
                        guard a < b else { return }
                        let w = text[a ..< b]
                        var st = base
                        if let px = base.fontSize, px > 0.5, let split = TamilAdvances.split(w, bold: base.fontWeight == .bold, vijaya: indic?.face == "vijaya", leelawadee: leelawadeeLatin) {
                            // (As spacing, not a scale: the line breaking measures it. Spread over the glyphs the engine draws.)
                            func measure(_ ls: Double) -> Double {
                                let t = TextPainter(text: TextSpan(text: String(w), style: base.copyWith(letterSpacing: ls)), textDirection: .ltr)
                                t.layout(minWidth: 0, maxWidth: 100_000)
                                defer { t.dispose() }
                                return t.width
                            }
                            let w0 = measure(0)
                            let n = max(1, Int((measure(10) - w0) / 10 + 0.5))
                            // (A character the table lacks keeps the stand-in's own width.)
                            var other = 0.0
                            if split.rest {
                                let t = TextPainter(text: TextSpan(text: split.known, style: base.copyWith(letterSpacing: 0)), textDirection: .ltr)
                                t.layout(minWidth: 0, maxWidth: 100_000)
                                other = w0 - t.width
                                t.dispose()
                            }
                            if w0 > 0.01 { st = base.copyWith(letterSpacing: (base.letterSpacing ?? 0) + (split.ems * px + other - w0) / Double(n)) }
                        }
                        spans.append(contentsOf: capped(w, run, st))
                    }
                    var k = start
                    while k < end {
                        if text[k] == " " || text[k] == "\u{00A0}" {
                            putWord(wordStart, k)
                            spans.append(contentsOf: capped(text[k ..< text.index(after: k)], run, base))
                            wordStart = text.index(after: k)
                        }
                        k = text.index(after: k)
                    }
                    putWord(wordStart, end)
                    start = end
                    return
                }
                // (A word the fit's cut on a neighbouring space splits out of its run is still the run's: the cut makes a run of every space and
                // word, and a word alone has no Latin to open this branch, so it fell to the flat scale and the engine found room the fit never
                // counted. Only where there is a cut: a run of one word that is its own run, as Word has it, is as it was. f0001d05.)
                if kind >= 0, indic?.face == "kokila", kokilaLatin, let px = style(kind).fontSize, px > 0.5, let m = Self._indicLines["kokila"],
                   (adjust.isEmpty ? text[start ..< end] : text[...]).unicodeScalars.contains(where: { $0.value < 0x250 || $0.value == 0x2026 || $0.value == 0x201C || $0.value == 0x201D }) {
                    // (Kokila's own Latin, digits and space: `KokilaLatin`; Devanagari stays on the flat scale.)
                    let base = style(kind)
                    var i = start
                    func isLatin(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { $0.value < 0x250 || $0.value == 0x2026 || $0.value == 0x201C || $0.value == 0x201D } }
                    while i < end {
                        var j = i
                        let latin = isLatin(text[i])
                        while j < end, isLatin(text[j]) == latin { j = text.index(after: j) }
                        let seg = text[i ..< j]
                        if latin {
                            let st = _kokilaLatinStyle(seg, base: base, px: px)
                            spans.append(contentsOf: capped(seg, run, st))
                        } else {
                            // (Kokila's own cluster widths where the table has the word: `KokilaAdvances`.)
                            let kBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                            let kItalic = run.italic || ((named?.char.italic ?? false) && !run.off.contains(.italic))
                            let authored = (run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
                            if authored > 0.5, let fitted = _clusterFitted(seg, base: base, authored: authored, table: KokilaAdvances.table(bold: kBold, italic: kItalic), flatScale: Self._indicScale["kokila"]?["D"] ?? 1) {
                                spans.append(contentsOf: capped(seg, run, fitted.style))
                            } else {
                                spans.append(contentsOf: capped(seg, run, joinedScaled(seg, base)))
                            }
                        }
                        i = j
                    }
                    start = end
                    return
                }
                if kind >= 0, let face = indic?.face, let spaceEm = (face == "vrinda" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? 0.3125 : Self._indicSpace[face], let px = style(kind).fontSize, px > 0.5,
                   face == "mangal" || (adjust.isEmpty ? text[start ..< end] : text[...]).contains(Character(" ")) || text[start ..< end].contains(Character("\u{00A0}")) {
                    // (Word's space is the face's own: Mangal 0.5 em against the stand-in's 0.26; the prints' gap between words, 5.5 pt against our 3.5 at 11 pt.)
                    let base = style(kind)
                    var spaceStyle: TextStyle? = nil
                    var wordStart = start, k = start
                    // (Mangal's own widths, Word's print: the space half an em and each cluster at its fitted advance, `MangalAdvances`, on the
                    // authored size, not the stand-in's enlarged one.)
                    let mangalBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    let mangalRegular = face == "mangal"
                    // (Mangal's table is em of the size Word WRITES, on its 0.12 pt grid (11 pt is 11.04): at 600 dpi it sets the face at a whole ppem, so a 11 pt line
                    // is 0.36% wider than exact. 9baed400's "…सम्पन्न भएको।" needs 7.6 pt of squeeze at 11.04, 6.75 at 11.0, and Word refused it.)
                    let authored = Self._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: mangalRegular && theme.wordRules && RichTextTheme.wordWindowsPages) * theme.pixelsPerPoint * scale
                    func putWord(_ a: Substring.Index, _ b: Substring.Index) {
                        guard a < b else { return }
                        let w = text[a ..< b]
                        if mangalRegular, authored > 0.5, let split = MangalAdvances.split(w, bold: mangalBold) {
                            let flat = base.copyWith(scaleX: 1)
                            func measure(_ s: String, _ ls: Double) -> Double {
                                let t = TextPainter(text: TextSpan(text: s, style: flat.copyWith(letterSpacing: ls)), textDirection: .ltr)
                                t.layout(minWidth: 0, maxWidth: 100_000)
                                defer { t.dispose() }
                                return t.width
                            }
                            let w0 = measure(String(w), 0)
                            if w0 > 0.01 {
                                let n = max(1, Int((measure(String(w), 10) - w0) / 10 + 0.5))
                                let other = split.rest ? (w0 - measure(split.known, 0)) * (Self._indicScale["mangal"]?["D"] ?? 1) : 0
                                spans.append(contentsOf: capped(w, run, flat.copyWith(letterSpacing: (flat.letterSpacing ?? 0) + (split.ems * authored + other - w0) / Double(n))))
                                return
                            }
                        }
                        // (A run whose ascii face is Vrinda too draws its Latin in Vrinda: its own advances, `VrindaAdvances`, at the authored size.)
                        if face == "vrinda", theme.wordRules, RichTextTheme.wordWindowsPages, authored > 0.5,
                           (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "vrinda",
                           w.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) {
                            let vTable = (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))) ? VrindaAdvances.bold : VrindaAdvances.regular
                            if let fitted = _clusterFitted(w, base: base, authored: authored, table: vTable, flatScale: 1, conjunctRatio: nil, block: 0x980) {
                                RuleTrace.hit("word-vrinda-latin-own-advances")
                                spans.append(contentsOf: capped(w, run, fitted.style))
                                return
                            }
                        }
                        // (A Latin word of a run that names its own Latin face is that face's, not stretched by the Indic scale, as in the Nirmala path above:
                        // dx2 88e26672's "(Police Department)", Arial 10 pt, 30.5 pt in Word.)
                        if mangalRegular, run.fontFamily != nil, !w.unicodeScalars.contains(where: { $0.value >= 0x0900 && $0.value < 0x0E00 || $0.value == 0xA0 }),
                           w.contains(where: { $0.isLetter || $0.isNumber }) {
                            latinNoScale = true
                            let plain = style(kind)
                            latinNoScale = false
                            spans.append(contentsOf: capped(w, run, joinedScaled(w, plain)))
                            return
                        }
                        spans.append(contentsOf: capped(w, run, joinedScaled(w, base)))
                    }
                    while k < end {
                        if text[k] == " " || text[k] == "\u{00A0}" {
                            putWord(wordStart, k)
                            if spaceStyle == nil {
                                // (A run whose own Latin face is Arial, drawn in Mangal only because the document's first Devanagari run names Mangal: Word's space
                                // is still Arial's, 0.278 em (2.8 pt at 10 pt), not Mangal's half em: dx2 88e26672, the gap between words 2.9 pt.)
                                let ownFace = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                                let sp = mangalRegular && document.devanagariFirstRunMangal && ownFace == "arial" && (run.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial" ? 0.2778 : spaceEm
                                spaceStyle = _indicSpaceStyle(base: base, spaceEm: sp, unit: mangalRegular ? authored : px)
                            }
                            spans.append(contentsOf: capped(text[k ..< text.index(after: k)], run, spaceStyle ?? base))
                            wordStart = text.index(after: k)
                        }
                        k = text.index(after: k)
                    }
                    putWord(wordStart, end)
                    start = end
                    return
                }
                if kind >= 0, indic?.face == "shonar bangla", text[start ..< end].unicodeScalars.contains(where: { ($0.value >= 0x980 && $0.value <= 0x9FF) || ((run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "shonar bangla" && $0.value < 0x980 && $0 != " " && ShonarAdvances.regular[String($0)] != nil) || (_shonarLatinRunFace(run, named, document, p.text) != nil && $0.value < 0x980 && $0 != " " && ShonarAdvances.regular[String($0)] != nil) || (!(run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))) && ShonarAdvances.regular[String($0)] != nil && $0.value < 0x980 && $0 != " ") }) {
                    let shBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    let shTable = shBold ? ShonarAdvances.bold : ShonarAdvances.regular
                    // (Shonar Bangla's own Bengali cluster widths, word by word: `ShonarAdvances`.)
                    let authored = (run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
                    let base = style(kind)
                    for (piece, isIndic) in Self._splitIndicLatin(text[start ..< end]) {
                                                if isIndic, authored > 0.5 {
                            var ws = piece.startIndex
                            while ws < piece.endIndex {
                                var we = ws
                                let sp = piece[ws] == " "
                                while we < piece.endIndex, (piece[we] == " ") == sp { we = piece.index(after: we) }
                                let seg = piece[ws ..< we]
                                if !sp, let fitted = _clusterFitted(seg, base: base, authored: authored, table: shTable, flatScale: Self._indicScale["shonar bangla"]?["B"] ?? 1, conjunctRatio: nil, block: 0x980) {
                                    spans.append(contentsOf: capped(seg, run, fitted.style))
                                } else if sp, let spaced = _shonarSpaced(seg, base: base, authored: authored) {
                                    // (Word's own space, 0.2065 em from the print's subset, at the authored size: the old flat scale also shrank it to 2.27 pt of 2.88.)
                                    spans.append(contentsOf: capped(seg, run, spaced))
                                } else {
                                    spans.append(contentsOf: capped(seg, run, joinedScaled(seg, style(kind))))
                                }
                                ws = we
                            }
                        } else if authored > 0.5, piece.allSatisfy({ $0 == " " }), let spaced = _shonarSpaced(piece, base: base, authored: authored) {
                            spans.append(contentsOf: capped(piece, run, spaced))
                        } else if authored > 0.5, piece.unicodeScalars.allSatisfy({ shTable[String($0)] != nil && $0.value < 0x980 }), let fitted = _clusterFitted(piece, base: base, authored: authored, table: shTable, flatScale: 1, conjunctRatio: nil, block: 0x980) {
                            spans.append(contentsOf: capped(piece, run, fitted.style))
                        } else {
                            spans.append(contentsOf: capped(piece, run, joinedScaled(piece, style(kind))))
                        }
                    }
                    start = end
                    return
                }
                if kind >= 0, indic?.face == "nirmala ui", !(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui "), text[start ..< end].unicodeScalars.contains(where: { ($0.value >= 0x900 && $0.value <= 0x9FF) || ($0.value >= 0xA00 && $0.value <= 0xAFF) }),
                   !text[start ..< end].unicodeScalars.contains(where: { Self._tamil.contains($0.value) }) {
                    // (Nirmala UI's own Devanagari cluster widths, word by word: `NirmalaAdvances`.)
                    let nBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    let authored = (run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
                    let base = style(kind)
                    for (piece, isIndic) in Self._splitIndicLatin(text[start ..< end]) {
                                                if isIndic, authored > 0.5 {
                            // (Each word on its own, so the fitted letter spacing never reaches the spaces between words.)
                            var ws = piece.startIndex
                            while ws < piece.endIndex {
                                var we = ws
                                let sp = piece[ws] == " "
                                while we < piece.endIndex, (piece[we] == " ") == sp { we = piece.index(after: we) }
                                let seg = piece[ws ..< we]
                                if !sp, let fitted = _clusterFitted(seg, base: base, authored: authored, table: NirmalaAdvances.table(bold: nBold), flatScale: 1, conjunctRatio: nil, block: seg.unicodeScalars.first(where: { $0.value >= 0x900 && $0.value < 0xB00 }).map { $0.value & ~0x7F } ?? 0x900) {
                                    spans.append(contentsOf: capped(seg, run, fitted.style))
                                } else if sp, authored > 0.5, let em = Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") {
                                    // (A Bengali face Windows lacks: Word draws the space in Mangal, half an em, not the stand-in's 0.26: xd 73caaeda, 6.0 pt at 12 pt.)
                                    RuleTrace.hit("word-missing-bengali-face-space-is-mangal-half-em")
                                    spans.append(contentsOf: capped(seg, run, _indicSpaceStyle(base: base, spaceEm: em, unit: authored)))
                                } else {
                                    spans.append(contentsOf: capped(seg, run, leelawadeeLatin ? Self._arialUnicodeLatin(seg, base: joinedScaled(seg, style(kind))) : joinedScaled(seg, style(kind))))
                                }
                                ws = we
                            }
                        } else {
                            plainPiece = !isIndic
                            // (Latin letters and digits of a run that names its own Latin face are that face's, not stretched by the Indic scale:
                            // d912c25b's "(COVID-19)", Calibri 12, 54.7 pt in Word, 57.9 here.)
                            latinNoScale = !isIndic && run.fontFamily != nil && p.text.unicodeScalars.contains(where: { $0.value >= 0x905 && $0.value <= 0x939 }) && piece.contains(where: { $0.isLetter || $0.isNumber }) && !piece.unicodeScalars.contains(where: { $0.value == 0xA0 })
                            // (A space between Devanagari words in a run whose ascii face is a Windows Latin face (Calibri, Arial): Word draws it in that face (Hindi only: the Gujarati table is not re-measured and b785c95e's lines were level only by luck) at the
                            // run's size, 0.2256 em in Calibri; the Indic stretch (scaleX) belongs to the Devanagari glyphs only. d912c25b: 2.94 pt here, 2.76 in Word. The same for the ASCII marks (not the spaces: those follow the rule above for every Windows face) of a run that names, itself, a Latin face whose Windows metrics we hold (`WordWindowsFaces.metricsHeld`; PROVISIONAL: the stand-in's advances are used, not the face's own, so only the Indic stretch is dropped); a theme-derived or Aptos run drew its marks wide (xd 77d6ca49 17.5 to 4.5): ", " "-" ". " drawn at 12.48 here against Calibri's 12.0, 0.8 pt over one line: d912c25b p2 "...एक यह".)
                            let asciiFace = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                            latinNoScale = !isIndic && theme.wordRules && RichTextTheme.wordWindowsPages && !piece.isEmpty && (piece.allSatisfy({ $0 == " " }) || run.fontFamily != nil && WordWindowsFaces.metricsHeld.contains(asciiFace) && piece.unicodeScalars.allSatisfy({ $0.value < 0x80 && !$0.properties.isAlphabetic && !($0.value >= 0x30 && $0.value <= 0x39) })) && p.text.unicodeScalars.contains(where: { $0.value >= 0x905 && $0.value <= 0x939 }) && !asciiFace.isEmpty && !asciiFace.hasPrefix("nirmala ui") && WordWindowsFaces.names.contains(asciiFace)
                            let st = style(kind)
                            latinNoScale = false
                            plainPiece = false
                            if !isIndic, authored > 0.5, theme.wordRules, RichTextTheme.wordWindowsPages, piece.allSatisfy({ $0 == " " }), (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui"), Self._splitIndicLatin(text[start ..< end]).contains(where: { $0.1 }) {
                                // (Spaces between the Devanagari words of a Nirmala UI run are Nirmala's own when the run's Latin (ascii) face is Nirmala too, 0.2739 em (bold 0.2759; in a run whose ascii face is Arial Word draws the space in Arial, 0.28 em: dx2 b785c95e, xd 1116b68d; lab/metrics/Nirmala_UI*.tsv, lab nirpitch3: Word 3.02 pt at 11 pt, the stand-in's 2.62).)
                                RuleTrace.hit("word-nirmala-space-own-advance")
                                spans.append(contentsOf: capped(piece, run, _indicSpaceStyle(base: st, spaceEm: nBold ? 0.2759 : 0.2739, unit: authored)))
                                continue
                            }
                            // (Spaces between the Bengali words of a run in a face Windows lacks (SolaimanLipi, Nikosh): Word draws them in Mangal, half an em, not the
                            // stand-in's quarter: xd 73caaeda, 6.0 pt at 12 pt, so Word's first line breaks 10 characters earlier than ours did.)
                            if !isIndic, authored > 0.5, theme.wordRules, RichTextTheme.wordWindowsPages, !piece.isEmpty, piece.allSatisfy({ $0 == " " }),
                               let em = Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? ""),
                               p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && $0.properties.isAlphabetic }) {
                                RuleTrace.hit("word-missing-bengali-face-space-between-words-is-mangal-half-em")
                                // (And it lifts the line to Mangal's 1.241 + 0.438 em as a mark does: the line of letters and spaces alone steps 20.2 in Word, 16 in ours.)
                                if !_isSolaimanLipi(run, named, document), devanagariStyles["mangal"] == nil, let m = Self._indicLines["mangal"] {
                                    devanagariStyles["mangal"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: m.0, descent: m.1)
                                }
                                let spaceBase = !_isSolaimanLipi(run, named, document) ? (devanagariStyles["mangal"].flatMap { $0 } ?? st) : st
                                spans.append(contentsOf: capped(piece, run, _indicSpaceStyle(base: spaceBase, spaceEm: em, unit: authored)))
                                continue
                            }
                            spans.append(contentsOf: capped(piece, run, leelawadeeLatin ? Self._arialUnicodeLatin(piece, base: joinedScaled(piece, st)) : joinedScaled(piece, st)))
                        }
                    }
                    start = end
                    return
                }
                if kind >= 0, indic?.face == "nirmala ui", Self._splitIndicLatin(text[start ..< end]).count > 1 {
                    // (Word builds each line from the tallest ascent and the deepest descent of the faces on it: the Latin, digits, spaces
                    // and marks between Nirmala UI's words are Arial's and carry no Nirmala line of their own.)
                    for (piece, isIndic) in Self._splitIndicLatin(text[start ..< end]) {
                                                plainPiece = !isIndic
                        latinNoScale = !isIndic && run.fontFamily != nil && p.text.unicodeScalars.contains(where: { $0.value >= 0x905 && $0.value <= 0x939 }) && piece.contains(where: { $0.isLetter || $0.isNumber }) && !piece.unicodeScalars.contains(where: { $0.value == 0xA0 })
                        let st = style(kind)
                        plainPiece = false
                        latinNoScale = false
                        spans.append(contentsOf: capped(piece, run, joinedScaled(piece, st)))
                    }
                    start = end
                    return
                }
                // (Spaces between Devanagari words, in a run of its own: Word draws them in Leelawadee UI, 0.274 em, where our stand-in's are 0.22; dx2 fb94294e.)
                if kind >= 0, aumsSpaces, text[start ..< end].allSatisfy({ $0 == " " || ($0 == "\u{00A0}" && spaceBeforeDanda) }) {
                    spans.append(contentsOf: capped(text[start ..< end], run, Self._leelaLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind)))))
                    start = end
                    return
                }
                // (A space in a run of its own whose Latin face is Mangal, in a Devanagari paragraph: Word draws it in Mangal, 0.5 em, 5.52 pt
                // at 11 pt, where the stand-in's Latin space is 3.1; dx2 2db27e2d's "है; उदाहरण", the space after the ";".)
                if kind >= 0, mangalLatinSpace, text[start ..< end].allSatisfy({ $0 == " " || ($0 == "\u{00A0}" && spaceBeforeDanda) }) {
                    RuleTrace.hit("word-mangal-latin-run-space-is-half-em")
                    let base = style(kind)
                    let authored = Self._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: true) * theme.pixelsPerPoint * scale
                    spans.append(contentsOf: capped(text[start ..< end], run, _indicSpaceStyle(base: base, spaceEm: 0.5, unit: authored)))
                    start = end
                    return
                }
                // (A run with no w:cs in an Indic paragraph, Arial Unicode MS in the ascii slot: Word draws its Latin, digits and marks in Yu Gothic; dx2 fb94294e.)
                if kind >= 0, aumsYuInIndic, let y = Self._yuLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind))) {
                    spans.append(contentsOf: capped(text[start ..< end], run, y))
                    start = end
                    return
                }
                if yuOfMissingHangul, text[start ..< end].unicodeScalars.contains(where: { $0.value >= 0x20 && $0.value < 0x250 }) {
                    // (Piece by piece: the Latin runs at Yu Gothic's advances, the Hangul between them as it was.)
                    var k = start
                    while k < end {
                        let lat = (text[k].unicodeScalars.first?.value ?? 0x3000) < 0x250
                        var m = k
                        while m < end, ((text[m].unicodeScalars.first?.value ?? 0x3000) < 0x250) == lat { m = text.index(after: m) }
                        let piece = text[k ..< m]
                        let st = joinedScaled(piece, style(kind))
                        if lat, let y = Self._yuLatinStyle(piece, base: st) {
                            RuleTrace.hit("word-missing-hangul-face-latin-takes-yu-gothic-advances")
                            spans.append(contentsOf: capped(piece, run, y))
                        } else { spans.append(contentsOf: capped(piece, run, st)) }
                        k = m
                    }
                    start = end
                    return
                }
                // (A stretch with no Indic letter in it, in a run that has some: its digits, marks and spaces are the Latin face's, at the
                // Latin face's widths; the Indic width scale is for the Indic letters. dx2 d912c25b's "(COVID-19)": Word 54.7, ours 59.2.)
                latinNoScale = kind >= 0 && indic != nil && run.fontFamily != nil && text[start ..< end].contains(where: { $0.isLetter || $0.isNumber }) && !text[start ..< end].unicodeScalars.contains(where: { $0.value == 0xA0 }) && !text[start ..< end].unicodeScalars.contains(where: { $0.value >= 0x0900 && $0.value < 0x0E00 })
                let st = style(kind)
                latinNoScale = false
                spans.append(contentsOf: capped(text[start ..< end], run, joinedScaled(text[start ..< end], st)))
                start = end
            }
            var offset = base
            var i = text.startIndex
            // (Measured as shown: a run in capitals (`capped`) is spaced,
            // kerned and put on the grid by its capitals — 60810's titles,
            // "Connection to global talent programmes/R200" in caps, lost
            // "TA" and "LT"'s kerning and wrapped a line PowerPoint fits.)
            let shownCaps = theme.measuresShownCaps && (run.caps || ((named?.char.caps ?? false) && !run.off.contains(.caps)))
            func shown(_ c: Character) -> Character {
                guard shownCaps else { return c }
                let up = String(c).uppercased()
                return up.utf16.count == String(c).utf16.count && up.count == 1 ? Character(up) : c
            }
            // (A raised or lowered run's line is its whole size's, unshifted,
            // as if it were not raised: lab `sup` (macOS-doc, Word for Mac)
            // — a 12pt 宋体 line with a 10pt YaHei superscript is 17.28pt
            // in Word, as with it plain (17.04), ours 15.57; a footnote's
            // mark the same; zh-7654804a's rows of "105" and a superscript
            // "註3" stand 3pt taller in Word's print. Its glyphs are drawn
            // shrunk and shifted; a zero-width non-joiner of its whole
            // size holds the line — part of what stands before it to the
            // line breaking, where a word joiner kept zh-424775e4's note mark
            // from opening a line after "韩国。" as Word's print has it.)
            // (Only where that line is taller than the rest of the paragraph's:
            // a Times note mark in YaHei text changes nothing, and its joiner
            // only stirred the line fitting.)
            // (Not in a line with a page number's field: its raised "/" grows the line by 1.08pt at
            // 15.5pt on 10, not by the whole size's 6.3 — lab pgf, Word for Windows, lo-198cd200's footer.)
            if theme.wordRules, run.script != .normal, NativeParagraphBuilder.supportsBaselineShift, let first = text.first,
               !p.runs.contains(where: { $0.style.field != nil && $0.style.fieldResult != nil && $0.style.script == .normal }),
               let ownLine = theme.naturalLine(for: { var w = run; w.script = .normal; return w }(), named: named, eastAsian: RichLayout.isEastAsian(first, hinted: hinted)),
               ownLine > ({ () -> Double in
                   var most = 0.0, at = 0
                   let units = Array(p.text.utf16)
                   for r in p.runs {
                       defer { at += r.length }
                       guard r.style.script == .normal, r.length > 0, at + r.length <= units.count else { continue }
                       let part = String(decoding: units[at ..< at + r.length], as: UTF16.self)
                       let rh = (r.style.fontHint ?? named?.char.fontHint) == "eastAsia"
                       let hasEA = part.contains { RichLayout.isEastAsian($0, hinted: rh) }
                       let hasLatin = part.contains { !RichLayout.isEastAsian($0, hinted: rh) && !$0.isWhitespace }
                       if hasEA { most = max(most, theme.naturalLine(for: r.style, named: named, eastAsian: true) ?? 0) }
                       if hasLatin { most = max(most, theme.naturalLine(for: r.style, named: named, eastAsian: false) ?? 0) }
                   }
                   return most
               }()) + 0.01 {
                var whole = run
                whole.script = .normal
                let s = theme.textStyle(for: whole, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                        eastAsian: RichLayout.isEastAsian(first, hinted: hinted), gridPitch: pitch, scriptHidden: true)
                // (No width of its own: shaped alone, as it is set, it has
                // one, and a line at its limit took a character less.)
                let alone = TextPainter(text: TextSpan(text: "\u{200C}", style: s), textDirection: .ltr)
                alone.layout(minWidth: 0, maxWidth: 100_000)
                let own = alone.width
                alone.dispose()
                spans.append(TextSpan(text: "\u{200C}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) - own)))
                inserts.append(offset)
            }
            while i < text.endIndex {
                let ch: Character = shown(text[i])
                let after = text.index(after: i)
                let following = (after < text.endIndex ? text[after] : next).map(shown)
                // (An ideographic space on a line of spaces alone is set
                // as the mark is, in the run's Latin face: see `lineSize`.)
                let ea = theme.wordRules && RichLayout.isEastAsian(ch, hinted: hinted || (eastDash && ch == "\u{2014}")) && !(ch == "\u{3000}" && lineSize?.blank == true)
                    && !(latinDash && ch == "\u{2013}")
                    // (Nor a "×" or "÷", Latin-1's signs, which Word sets in the hAnsi
                    // face as it does the dash: zh-7a16a243's unhinted "×" in a run of
                    // 標楷體 over its heading style's Arial hAnsi is Arial's 9.34pt and
                    // half the grid's 1.0076 in Word for Windows' print, 9.9 — ours set
                    // 標楷體's half em, 8.5, and the line "…672％)，然上開「允建樓地板面"
                    // took the "積" Word sends down.)
                    && !(latinDash && RichTextTheme.wordWindowsPages && (ch == "\u{00D7}" || ch == "\u{00F7}"))
                var kind = ea ? -1 : (classed ? RichResolvedFace.characterClass(ch) : 0)
                // (Circles, squares and stars in an East Asian run are the East Asian face's glyph
                // — an em wide, 0.86 across — not the Latin stand-in's small one: kind -4.)
                if ea, eastDash, ch == "\u{2014}" { kind = -5; RuleTrace.hit("word-em-dash-drawn-in-east-asian-hansi-face") }
                if ea, theme.wordRules, RichTextTheme.wordWindowsPages, Self._cjkFaceFamily != nil, let u = ch.unicodeScalars.first?.value,
                   (0x25A0 ... 0x25EF).contains(u) || u == 0x2605 || u == 0x2606 { kind = -4 }
                // (A curly quote an embedded subset lacks is Word's fallback face's too, full width:
                // zh-5450d509's “ ” after 仿宋_GB2312's five glyphs are JhengHei's 12pt in the
                // print; ours set them as a missing glyph, 17.8 and 12.1, and a line lost a character.)
                if ea, let (_, covers) = uncovered, let u = ch.unicodeScalars.first?.value, u >= 0x2E80 || (RichTextTheme.wordWindowsPages && ((0x2018 ... 0x201D).contains(u) || (0x2460 ... 0x2473).contains(u))) {
                    if covers.contains(u) { chainAt = nil }
                    else if let chain {
                        if let at = chainAt, chain[at].covers?.contains(u) ?? true {
                            kind = -10 - at
                        } else if chainAt == nil, let w = Self._cambriaMathOpeners[u] {
                            // (A symbol that opens a stretch is Cambria Math's,
                            // at its own width, on no line of its own: every
                            // "〔", "〕" and circled number so placed in word-win
                            // — zh-92373179's 31 "①"… at a line's start or after
                            // a held character, 1.19 em at its grid; zh-540dc149,
                            // zh-5450d509, zh-c2f6d17a, zh-e68a2f57's brackets
                            // after a digit. One after a fallen-back character
                            // keeps that one's face.)
                            kind = -9
                            cambriaWidth = w
                        } else {
                            chainAt = chain.firstIndex { $0.covers?.contains(u) ?? true } ?? chain.count - 1
                            kind = -10 - chainAt!
                        }
                    } else { kind = -3 }
                } else if chain != nil, !ch.isWhitespace {
                    // (Any other character seen ends a stretch — a digit as
                    // a held ideograph does: with that, all of the three
                    // prints' 13,171 fallen-back characters are so.)
                    chainAt = nil
                }
                // The spaces that end a paragraph after ideographs, in a run
                // whose Latin letters stand in for an East Asian face's
                // own, take the ideographs' face, at the stand-in's width
                // (kind -2): set in the stand-in, its other ascent and
                // descent made the line taller than either face. The Mac's
                // lab `hfl` (Word 16): five spaces after "红河县人民政府发布"
                // in 14pt bold 宋体 make the paragraph no taller; ours stood
                // 1.2pt taller on Linux, and zh-1563bd74's footer took a
                // line off a page. (Spaces within the line are left in the
                // stand-in: set in the ideographs' face, the line fitting
                // measured them otherwise, and lines parted elsewhere.)
                if theme.wordRules, ch == " ", afterIdeograph, offset >= trailingSpaces, latinFace?.isEastAsian == true { kind = -2 }
                if ea { afterIdeograph = true } else if ch != " " { afterIdeograph = false }
                // A stretch of Latin characters with no space in it is
                // one word to Word, which parts it only after a hyphen:
                // an address, a date with strokes, "100%200%", "(a)(b)"
                // go to the next line whole. The engine would break
                // after the stroke, the question mark, the percent
                // sign and the bracket; a word joiner holds them.
                // (One too long for any line Word parts wherever the
                // line ends, starting where it stands: a zero-width
                // space before each of its characters.)
                if ch != "." { dotsAttached = false } else if before != "." { dotsAttached = before.map { b in
                    // (Thai, Lao, Myanmar and Khmer are broken by dictionary, not by the letters' class: xd's Thai forms part their stops.)
                    let v = b.unicodeScalars.first?.value ?? 0
                    return (b.isLetter || b.isNumber || (b.unicodeScalars.first?.properties.generalCategory).map({ [.nonspacingMark, .spacingMark].contains($0) }) == true || b == ":") && !(v >= 0xE00 && v <= 0xEFF) && !(v >= 0x1000 && v <= 0x109F) && !(v >= 0x1780 && v <= 0x17FF)
                } ?? false }
                @inline(never) func _sblk0() {
                if wideStarts.contains(offset) {
                    // (A word wider than the line opens a line of its own,
                    // and is parted there: see `_wideWordStarts`.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2028}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if loose.contains(offset) {
                    flush(i)
                    // (A word wider than the line parted at a hyphenation
                    // point ends its line there with the hyphen drawn.)
                    if !ea, let idx = index, _hyphenPoints[idx]?.contains(offset) == true {
                        spans.append(TextSpan(text: "-", style: style(kind)))
                    } else {
                        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    }
                    inserts.append(offset)
                } else if let idx = index, let points = _hyphenPoints[idx], points.contains(offset), !ea {
                    // (Automatic hyphenation: a place the word may be parted
                    // at, with the hyphen drawn where the line does end.)
                    flush(i)
                    if _hyphenShown[idx]?.contains(offset) == true {
                        spans.append(TextSpan(text: "-", style: style(kind)))
                    } else {
                        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    }
                    inserts.append(offset)
                } else if theme.wordRules, !document.usesEastAsianLayout, spacesAfterNbsp, before == " ", !ea,
                          !ch.isWhitespace, ch != "\u{00A0}" {
                    // (Plain spaces after a no-break space hold the word
                    // that follows them: Word parts no line between
                    // "X)" + U+00A0 + U+0020 and the next word, so one
                    // wider than what is left of the line is cut where the
                    // line ends. LibreOffice's tdf134606, "X)\u{00A0} XXXXXXXXXXXX"
                    // in a 94pt cell: Word sets "X)  XXXXXXXXXXX" / "X
                    // XXXXXXXXX *", ours sent the 12 X's down whole, a
                    // third line, the row 12pt taller.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, (before == "." && ch == ".") || (!document.usesEastAsianLayout && (before == "…" || ch == "…") && (before == "." || before == "…") && (ch == "." || ch == "…") && Self._stopRunWidth(Array(p.text.utf16), at: offset, size: style(kind).fontSize ?? 12) > textWidth), document.usesEastAsianLayout || !dotsAttached {
                    // (Not stops that follow a word's letters, in a file that sets no East Asian
                    // layout: bede0fbc's "নাম:" + 154 stops is one word, which Word sends down
                    // whole when it fits a line of its own, and parts only if it cannot.)
                    // (A run of stops parts between any two of them, and fills each
                    // line to capacity: zh-92373179 p11's dot leader row, where the
                    // engine held the run whole and Word sets 4 + 1. Lab dot-run:
                    // even one stop alone goes down to the next line.)
                    RuleTrace.hit("92373179-dot-run-parts-between-dots")
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, before == " ", ch == "." || ch == ":" || ch == ";" || ch == "," || ch == "}" || ch == ")" || ch == "]" || ch == "!" || ch == "?" {
                    // (A line may part at a space before a stop, colon, semicolon, comma, closing bracket, "!" or "?" (xb hin-z20395192 opens lines ":<+" and "}kjk"): the engine keeps
                    // " ." together — a stop may not start a line, even after a
                    // space — and Word does not. lo-0349db3a's "Word / .doc" in a
                    // 116pt frame ends a line "…in Word /" in Word's print.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, before == " ", ch != " ", let bb = beforeBefore, bb == "\u{A1}" || bb == "\u{BF}" {
                    // (A line may part at the space after "¡" or "¿": the break table reads them as openers
                    // and keeps what follows the space with them; Word breaks at any space. xb hin-z20395192,
                    // a Kruti Dev text whose "¡" is a letter, ends a line "…'kCn l¡" and opens the next with "cuy…".)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, document.usesEastAsianLayout, before == "-", let bb = beforeBefore,
                          (document.compatibilityMode ?? 12) < 15, document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false,
                          let v = ch.unicodeScalars.first?.value, v > 0x20, v < 0x7F, let w = bb.unicodeScalars.first?.value, w > 0x20, w < 0x7F {
                    // (Before 2013's layout, with punctuation compressed, Word
                    // parts no Latin word after its hyphen either: zh-bfe04e2f
                    // carries "S19-S17" down whole, where the engine ended a line
                    // "…南槽航道S19-". `_fittingWordHyphens` has the same gate.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, document.usesEastAsianLayout, (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true), p.style.eastAsian["w:wordWrap"] != "0",
                          let b = before, let bv = b.unicodeScalars.first?.value, let v = ch.unicodeScalars.first?.value,
                          Self._fullwidthOperatorHeld(bv, v) {
                    // (Word does not part a full-width ＝ or ＋ from the ASCII "(" or digit after it: jpn-z21601833-463426's
                    // "＝(" and lab eqparen; the engine breaks there as it does between ideograph and opening bracket.)
                    RuleTrace.hit("fullwidth-operator-held")
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.eastAsian["w:wordWrap"] != "0", let b = before, b.isASCII, b.isLetter || b.isNumber,
                          let v = ch.unicodeScalars.first?.value, v >= 0xAC00, v <= 0xD7A3 {
                    // (A Latin letter or digit holds the Hangul that follows it, no space between: Word carries
                    // kor-z20746312-59e77f's "26.1퍼센트였다" down whole, where the engine ended the
                    // line "…신뢰도는 26.1".)
                    RuleTrace.hit("hangul-held-to-latin-before-it")
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.eastAsian["w:wordWrap"] != "0",
                          let b = before, let bv = b.unicodeScalars.first?.value,
                          let v = ch.unicodeScalars.first?.value,
                          Self._hangulHeldPair(bv, v) || koreanTokenJoins.contains(offset) {
                    // (Word keeps a Hangul word whole at the line end unless the paragraph's word wrap is off
                    // (census of dx2 ko: 20bb671d's "학회에서", "제1저자,"); with it off it parts mid-word.)
                    RuleTrace.hit("hangul-word-held-whole")
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules || theme.officeLatinBreaks, let b = before,
                          Self.joinsLatin(b, ch, eastAsian: document.usesEastAsianLayout) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, document.usesEastAsianLayout, ch == ">", let b = before,
                          let v = b.unicodeScalars.first?.value, (0x3400...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || v >= 0x20000,
                          !Self._traditionalChinese(document) {
                    // (">" may not begin a line in Word's Simplified
                    // Chinese list, and the engine parts it from an
                    // ideograph before it: zh-3fe252ff's "…28~31行3栏>0,"
                    // sends "栏" down with it in Word for Windows' print
                    // (lab `lan`), ours kept "栏" and every page after p22
                    // ran a line short. Not under Traditional Chinese,
                    // whose list lacks it — see `_looseWordOffsets`. And
                    // after an ideograph only: held to a closing bracket,
                    // zh-4c884684's "…2022年）>" went down whole where
                    // Word's print ends its line with it.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, ch == "\u{FE30}", let b = before, b != " " {
                    // ("︰" may not begin a line — see `_noStart` — and the engine parts it from what it
                    // follows: zh-e51c31a7's "…以為共同遵守︰" sends "守︰" down in Word's print.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, document.usesEastAsianLayout, (document.compatibilityMode ?? 12) < 15,
                          document.characterSpacingControl?.hasPrefix("compress") == true,
                          before == "-", ch.isLetter, (ch.unicodeScalars.first?.value ?? 0x3000) < 0x250,
                          beforeBefore?.isLetter == true, (beforeBefore?.unicodeScalars.first?.value ?? 0x3000) < 0x250 {
                    // (Latin letters only: zh-c8eb6e92's "评标-定标" parts after the
                    // hyphen. Nor after a hyphen between letters, before mode 15 where
                    // punctuation is compressed: labs hyc/hyd (Word for Windows,
                    // zh-424775e4's package, mode 12, compressPunctuation) send
                    // "China-sponsored" down whole with 25pt to spare, and
                    // "langkah-langkah" too; in mode 15, or under doNotCompress,
                    // it parts after the hyphen — as every other Word-win print
                    // that breaks there does.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, !document.usesEastAsianLayout, let b = before, Self._breaksAfterHyphen(beforeBefore, b, ch) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, !document.usesEastAsianLayout, before == "-", ch.isNumber,
                          let bb = beforeBefore, bb.isLetter || bb.isNumber {
                    // (Word parts a line after a hyphen before a digit —
                    // "КС-" from "2).", "А-" from "5", "2024-" from "10"
                    // — which the engine, keeping a number whole with
                    // its sign, does not. Lab `hy3` in bug65649's
                    // package, Word 16, 2026-10-15, every width that
                    // ends a line between them; its page 14's "КС-2)".
                    // Not under East Asian layout: zh-64044a1d's
                    // "0988-228598", a cell too narrow for it, Word
                    // parts after the tenth digit, not at the hyphen.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                }
                }
                _sblk0()
                // (Right-to-left digits: Word for Windows keeps "-", "/" and "%"
                // from joining the numbers round them, as the Unicode rules
                // would for "10-18/11" and "50%": each number stands whole and
                // the whole reads right to left, "11/18-10" and "%50" on the
                // page, while ":", "," and "." join as written. Lab bidi-digits,
                // Latin digits (Arabic-Indic ones the engine's own order already splits, and an
                // extra mark there only cost dx2 ur 968500c3 a point), a bidi paragraph or not, in a
                // table or not; not where the run's complex-script language is Persian. A right-to-left mark before the sign and before
                // what follows it gives that.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, wasRightToLeft, offset > 0 {
                    func digit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
                    func sign(_ c: Character) -> Bool { c == "-" || c == "/" || c == "%" }
                    if (sign(ch) && before.map(digit) == true) || (digit(ch) && before.map(sign) == true) {
                        flush(i)
                        spans.append(TextSpan(text: "\u{200F}", style: zeroWidth(current ?? kind)))
                        inserts.append(offset)
                    }
                }
                // (A distributed line's room before this character: a word
                // joiner that wide. Spacing on the character itself would
                // be set half before it, and move the line's first.)
                if let g = spread[offset], g > 0 || (g < 0 && ch == " ") {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: style(kind).copyWith(letterSpacing: g)))
                    inserts.append(offset)
                }
                // In East Asian text a curly quote is a full-width mark,
                // an em with the blank half outside it, as 宋体 and
                // every face Word sets such text in draw it; the faces
                // that stand in here draw the Latin one. The closing
                // one's blank is spacing after it.
                // A CJK compatibility ideograph Word on a Mac sets in Noto
                // Sans SC — its East Asian face has none, and its fallback
                // takes that face for these (`_notoCompatibility`) and
                // Heiti SC for the rest — gives its line Noto's height: a
                // word joiner in that face before it. Lab `cj2` (Word 16,
                // 標楷體 → YaHei 12pt, 2026-10-15): a line holding "行"
                // U+FA08 stands 1.44pt lower under the line above and
                // 0.48 higher over the next; one holding "零" U+F9B2, in
                // Heiti, is as any. zh-8e8d4c40's page 5 ran a line long.
                if theme.wordRules, ea, let u = ch.unicodeScalars.first?.value, u >= 0xF900, u <= 0xFAFF,
                   Self._notoCompatibility.contains(u),
                   theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.lacksCompatibilityIdeographs == true {
                    flush(i)
                    if notoStyle == nil {
                        var r = run
                        r.eastAsiaFontFamily = "Noto Sans SC"
                        notoStyle = theme.textStyle(for: r, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                                    eastAsian: true, gridPitch: pitch, scriptHidden: true)
                        // (Noto's line over and under the baseline, not
                        // its height shared out as the joiner's own face
                        // shares its ascent and descent: zh-8e8d4c40's
                        // lines holding "狀" and "行" stood 2.6pt under
                        // the line above, Word's 1.4, and no deeper.)
                        if let joiner = _notoJoiner(r, notoStyle!, run, named, style(kind), p.style, pitch, scale) { notoStyle = joiner }
                    }
                    // (A joiner keeps the line from parting before the
                    // character: a zero-width space before it gives the
                    // break back, the joiner going on with the character.
                    // zh-5b7ae054's "…基本抗災能力" ends its line at "能" in
                    // Word's print, "力" U+F98A opening the next; ours
                    // carried "能力" over and lost a character a line.)
                    // (After a Latin letter, a digit or a Latin closer too:
                    // zh-72da925e's "…經行政院於79年" ends a line "於79" in
                    // Word's print, "年" U+F98E opening the next; the joiner
                    // held "79年" whole and ours ended the line "於".)
                    if let b = before, Self.isEastAsian(b, hinted: true) ? !Self._openingMarks.contains(b)
                        : b.isASCII && (b.isLetter || b.isNumber || ")]}%.,;:!?".contains(b)) {
                        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                        inserts.append(offset)
                    }
                    spans.append(TextSpan(text: "\u{2060}", style: notoStyle!))
                    inserts.append(offset)
                }
                // A shape Word sets in the run's Latin face (no East Asian
                // hint), which has none, and its fallback in Segoe UI Symbol,
                // gives its line that face's ascent and descent (its hhea,
                // 2210 and 514 of 2048): a joiner sized so before it. Lab
                // `picln` (the Mac 7bd18d8e, Word 16, zh-e68a2f57's package):
                // its 9pt note, 楷体_GB2312 over Times New Roman, holding "◎"
                // stands 0.48pt lower under the line above, 0.96 at 12pt, at
                // single and 1.1 lines alike — its embedded 楷体 has the
                // glyph; "◇◆★☆" as "◎", "●□▲○■※" (Times has them) and
                // "①△" (Cambria Math) nothing. Ours drew them in YaHei, its
                // line as any, and p7's third note line stayed on the page.
                @inline(never) func _r1() {
                if latinShapes, let u = ch.unicodeScalars.first?.value, RichTextTheme.segoeSymbolShapes.contains(u) {
                    flush(i)
                    if segoeStyle == nil { segoeStyle = _segoeJoiner(run, named, style(-1), p.style, pitch, scale) }
                    if let joiner = segoeStyle {
                        // (Its break before kept: see the Noto joiner's.)
                        if let b = before, Self.isEastAsian(b, hinted: true) ? !Self._openingMarks.contains(b)
                            : b.isASCII && (b.isLetter || b.isNumber || ")]}%.,;:!?".contains(b)) {
                            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                            inserts.append(offset)
                        }
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        inserts.append(offset)
                    }
                }
                }
                _r1()
                // (A word of Devanagari or Bengali, set in the face Word draws it in, gives its line that face's height, not
                // the Latin face's: a joiner in its ascent and descent before the word. hin-z19439612's 12pt Mangal lines
                // step 23.2 in Word's print (1.680 em at 1.15 lines), ours 15.9. Which face: the run's complex-script one where
                // Windows has it (Mangal; Kokila only in italic); the rest, Kokila regular and bold and Kalpurush, Word draws in
                // Nirmala UI — hin-z18479909's 9942 regular Devanagari and ben-z17281487's Bengali are Nirmala in its prints.)
                // (A Hangul-named Latin face Word's box lacks, with no font-table entry (22de7d's theme face 함초롬돋움): Word draws the Latin letters
                // and digits in Yu Gothic and the Hangul in Malgun Gothic, so a line holding one takes Yu Gothic's deeper descent: 19.2 pt steps at 10 pt
                // against 18.5. Each face drawn on a line feeds its own ascent and descent into the line's max.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, u >= 0x20, u < 0x250, ch.unicodeScalars.count == 1, ch.isLetter || ch.isNumber,
                   !(before.map { ($0.unicodeScalars.first?.value ?? 0x3000) < 0x250 } ?? false), _yuLatinOfMissingHangulFace(run, named, document), !document.hasIndicText, !aumsLatin {
                    if devanagariStyles["missingHangulYu"] == nil {
                        devanagariStyles["missingHangulYu"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: Self._indicLines["malgun gothic"]!.0, descent: 0.492)?.copyWith(debugLabel: "yu-joiner")
                    }
                    if let joiner = devanagariStyles["missingHangulYu"] ?? nil {
                        RuleTrace.hit("word-missing-hangul-face-latin-is-yu-gothic-descent")
                        flush(i)
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        inserts.append(offset)
                    }
                }
                // (The won sign in a run whose Latin face is a Korean one with no ₩ of its own, set under no East Asian hint: Word for Windows
                // draws it in Malgun Gothic, so its line takes Malgun's height, 1.730 em. xd b6f6c7d4 p3: "(₩58,125,000,000)" in 12pt 한양신명조
                // at 1.75 lines, its line stands 3.4pt deeper than a Batang one, as ❏'s in Segoe UI Symbol.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{20A9}", run.fontHint != "eastAsia",
                   theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)?.isEastAsian == true,
                   let metrics = Self._indicLines["malgun gothic"] {
                    if devanagariStyles["wonMalgun"] == nil {
                        devanagariStyles["wonMalgun"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: metrics.0, descent: metrics.1)
                    }
                    if let joiner = devanagariStyles["wonMalgun"] ?? nil {
                        RuleTrace.hit("word-won-sign-in-korean-latin-face-is-malgun-height")
                        flush(i)
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        inserts.append(offset)
                    }
                }
                // (Tamil set in Noto Sans Tamil, a face Windows lacks: Word draws the letters in Nirmala UI but every digit, mark and Latin
                // letter in Mangal, so a line holding one is Mangal's 1.680 em tall; a line of Tamil letters and spaces stays Nirmala's 1.33.
                // xd c016493b: pitches 20.2 with a mark, 17.9 and 18.2 beside such a line, 16.0 without.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, !Self._isIndic(u) || u == 0x964 || u == 0x965,
                   !ch.isWhitespace,
                   u != 0x200B, u != 0x200C, u != 0x200D, u != 0x2060, u != 0xFFFC,
                   !(before.map { !$0.isWhitespace && !($0.unicodeScalars.first.map { Self._isIndic($0.value) } ?? false) } ?? false),
                   Self._markInMangal(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "", text) || (_isSolaimanLipi(run, named, document) && _asciiRunInMissingBengaliFace(run, named, document, text, p.text)),
                   let metrics = Self._indicLines["mangal"] {
                    if devanagariStyles["mangal"] == nil {
                        devanagariStyles["mangal"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: metrics.0, descent: metrics.1)
                    }
                    if let joiner = devanagariStyles["mangal"] ?? nil {
                        flush(i)
                        // (After a space the joiner would glue the mark to it and lose the break there: a break opportunity, as the digit rule below keeps.)
                        if before?.isWhitespace == true, _asciiRunInMissingBengaliFace(run, named, document, text, p.text) {
                            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                            inserts.append(offset)
                        }
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        inserts.append(offset)
                    }
                }
                // (A run that names Mangal and holds no Devanagari letter, digits and signs, still sets the line at Mangal's tall 18.5 pt (11 pt) in
                // Word's print, in a paragraph with no Indic letter at all (one with Devanagari already has the joiner; adding it there broke dx2 254ca33b, 375919ba): dx2 2db27e2d's "• 4(99)" bullets step 26.5 pt (8 before + 18.5), ours 20.7 on the Times line.)
                if namedFace == "mangal", theme.wordRules, RichTextTheme.wordWindowsPages, !p.text.unicodeScalars.contains(where: { Self._isIndic($0.value) }), let u = ch.unicodeScalars.first?.value, !Self._isIndic(u), !ch.isWhitespace,
                   u != 0x200B, u != 0x200C, u != 0x200D, u != 0x2060, u != 0xFFFC,
                   !(before.map { !$0.isWhitespace } ?? false),
                   let metrics = Self._indicLines["mangal"] {
                    if devanagariStyles["mangal"] == nil {
                        devanagariStyles["mangal"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: metrics.0, descent: metrics.1)
                    }
                    if let joiner = devanagariStyles["mangal"] ?? nil {
                        RuleTrace.hit("word-mangal-named-digit-run-sets-the-mangal-line-without-devanagari")
                        flush(i)
                        if let before, before.isWhitespace {
                            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                            inserts.append(offset)
                        }
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        inserts.append(offset)
                    }
                }
                // (A missing Korean face Word sets in Batang takes its quotes, circles, circled digits and middle dot from Malgun
                // Gothic, and a line holding one is Malgun's height: 6a68f6ca's lines step 29.9 into one, 31.9 out of one and 35.3
                // between two at 1.7 lines, 26.6 between plain ones. The split is Malgun's 1.175 + 0.557 against Batang's 1.009 + 0.291.)
                // (A run that names the East Asian face and hints East Asian draws its symbols in Batang, no Malgun: 218dff52's "7. ... △△△" lines step 31.2 as plain ones.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1,
                   !(run.eastAsiaFontFamily != nil && (run.fontHint ?? named?.char.fontHint) == "eastAsia"),
                   u == 0x25CB || u == 0x25B3 || u == 0xB7 || (u >= 0x2460 && u <= 0x2469) || u == 0x203B || u == 0x2192
                    || u == 0x2018 || u == 0x2019 || u == 0x201C || u == 0x201D,
                   theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true
                    // (A run that names only the ascii face, the missing Korean one, still draws △ and ○ in it (they have no ascii form; quotes in such a run stay Latin: 218dff52 page 2): 218dff52's △△△.)
                    || (u == 0x25B3 || u == 0x25CB) && (run.eastAsiaFontFamily == nil && run.fontFamily.map { theme.faceResolver?($0, true)?.malgunSymbols == true } == true) {
                    if devanagariStyles["malgunKo"] == nil {
                        devanagariStyles["malgunKo"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: 1.175, descent: 0.557)
                    }
                    if let joiner = devanagariStyles["malgunKo"] ?? nil {
                        flush(i)
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        inserts.append(offset)
                    }
                }
                // (A Devanagari word wider than its column is cut where each line fills, and every line of it is a line of Mangal: the joiner
                // that sets that line stands inside the word too, at each letter that opens a cluster. dx2 9baed400's 40 pt Kalimati cell, 21.2 pt
                // pitch in Word on every line, 17.6 on the lines ours began mid-word.)
                let insideWide = !wideIndicWords.isEmpty && wideIndicWords.contains { offset > $0.lowerBound && offset < $0.upperBound }
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, Self._isIndic(u),
                   insideWide || !(before?.unicodeScalars.first.map { Self._isIndic($0.value) || $0.value == 0x200D || $0.value == 0x200C } ?? false) {
                    let face0 = indic?.face
                    // (Shonar Bangla Bold is its own face in Word: 1721+978 of 2048 against the regular's 1655+996.)
                    let face = (face0 == "shonar bangla" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? "shonar bangla bold" : face0
                    if let face, let metrics = Self._indicLines[face] {
                        if devanagariStyles[face] == nil {
                            devanagariStyles[face] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: metrics.0, descent: metrics.1, belowOnly: face == "kokila" || face.hasPrefix("shonar bangla"))
                        }
                        if let joiner = devanagariStyles[face] ?? nil {
                            flush(i)
                            // (A zero-width space before it gives the break the joiner would forbid back: after a space the word
                            // would not part from the line, and the engine cut words inside.)
                            // (Not after an opening bracket or quote: Word keeps "(श्रमदिन)" whole, and the space let the line end on the "(": 9baed400's header cell.)
                            // (Nor after a Latin letter or digit with no space: Word keeps "…डीiseaseमल्टी…" whole, d912c25b; Devanagari only, Bengali ben-z17281487 drops with it.)
                            if let before, !"([{\u{2018}\u{201C}\u{FF08}".contains(before), !(before.isASCII && (before.isLetter || before.isNumber) && u >= 0x905 && u <= 0x97F) {
                                spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                                inserts.append(offset)
                            }
                            spans.append(TextSpan(text: "\u{2060}", style: joiner))
                            inserts.append(offset)
                        }
                    }
                }
                // (Not where the face gives the quote a width of its own
                // (`otherAdvances`): Arial Unicode MS's are narrow, and Word
                // sets them so with no blank beside them — zh-0aac9d1a.)
                let narrowQuotes = theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?
                    .otherAdvances?[0x201D] != nil
                let quote = ea && fullQuotes && (ch == "\u{201C}" || ch == "\u{2018}" || ch == "\u{201D}" || ch == "\u{2019}")
                    && !narrowQuotes
                // (None where the face's own quote is the em to a hair: Starling
                // FangSong's is 15.99997 of 16, and a blank of that hair sent
                // the squeeze the line fitting asked of an opening quote into a
                // joiner that cannot be narrower than nothing — zh-8186c98d's
                // "…中的标准计" lost its "计" on Linux.)
                let blank = quote ? max(0, em - _glyphWidth(style(kind), ch)) : 0
                let blankShown = blank > _px(0.01) ? blank : 0
                var led = false
                // (A word joiner before spaces that open the paragraph:
                // the engine moves a line on by half its first character's
                // letter spacing and, justifying, folds the spaces a line
                // opens with — zh-b378d8c4's "    1.城市内涝…", four Times
                // spaces widened to 7pt each, stand from the margin on
                // every line in Word's print, where ours started its
                // left-aligned lines 1.8pt in and set its justified ones'
                // spaces as one, 5pt out of the margin.)
                if theme.wordRules, offset == 0, ch == " " {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                }
                // (Thai, under `thaiBreaksAtSpaces`, kept together between
                // its spaces: Word for Mac's print of zh-6a4fc013 ends its
                // Thai lines only at spaces — "…ในประเทศต้นทาง" / "และพิจารณา…",
                // a justified line's gaps stretched for it — where the
                // engine's dictionary broke inside words and set 596 lines
                // to Word's 614.)
                // (A second space in a justified line, set as a patch of its
                // own: the engine takes a run of spaces for one gap and gives
                // the run one step, so "igreja.  Nos" lost a space; the
                // joiner between them makes each space a gap, stretched as
                // its neighbour is, as PowerPoint's print of Divino_Revelado
                // p12 sets them — 12.9pt for two where ours had 7.)
                else if !theme.wordRules, ch == " ", before == " ", p.style.alignment == .justify {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                }
                else if offset > 0, thaiJoins.contains(-offset), RichTextTheme.wordWindowsPages {
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                }
                else if thaiJoins.contains(offset), let b = before,
                        let pb = b.unicodeScalars.first?.value, let pc = ch.unicodeScalars.first?.value,
                        (0x0E01 ... 0x0E5B).contains(pb), (0x0E01 ... 0x0E5B).contains(pc) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                }
                else if let breaks = index.flatMap({ _hanChunks[$0] }), breaks.contains(offset) {
                    // (Word starts a long piece that does not fit the line's rest on a fresh line:
                    // `_hanPieceMoves`.)
                    flush(i)
                    spans.append(TextSpan(text: "\n", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                }
                else if hanJoins.contains(offset) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                }
                // (A place to break the line before a tab that follows text, where Word for Windows
                // takes the tab and what stands after it to the next line whole: tdf164499's
                // "…habe?)<tab>1" in a contents line — the number is no room, the dotted tab and
                // "1" go down and "habe?)" stays; the engine has no break there, wrapped "habe?)"
                // with them, and a line behind the contents ran on.)
                else if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\t", offset > 0, let b = before,
                        b != " ", b != "\t", b != "\n", b != "\u{2028}", b.isASCII || (following == "\t" && Self.isEastAsian(b, hinted: false)) {
                    // (An ideograph before a run of tabs as well (not a lone tab: zh-ab1ea005's contents lines): zh-77bd4900 p10's "…人數不得<tab><tab><tab>低於十人"
                    // keeps "得" on its line in Word's print and sends the tabs down; ours took "得" with them.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                    RuleTrace.hit("break-before-a-tab")
                }
                // A zero-width space where Word may break the line and
                // the engine would not: after spaces set as no-break
                // ones (`heldSpaces`), and before an opening curly
                // quote or after a closing one, as at any bracket —
                // the engine breaks on neither side of a quote.
                @inline(never) func _sblk1() {
                if afterHeld, ch != " ", !(breaksAtQuotes && !lineRulesOff && Self._closingMarks.contains(ch)) {
                    flush(i)
                    // (In the held spaces' own style, not the East Asian
                    // text's after them: there its glyph is the Latin base
                    // family's, whose ascent and descent split the em
                    // otherwise than the CJK face's, and the line grew
                    // 0.9pt at 12pt — zh-799c91cd's page 1 lost a line.)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(heldKind ?? current ?? kind)))
                    inserts.append(offset)
                    afterHeld = false
                } else if theme.wordRules, (before == "\u{2014}" && ch.isASCII && ch.isNumber && beforeBefore.map { $0.isASCII && $0.isNumber || Self._closingMarks.contains($0) } == true)
                            || (ch == "\u{2014}" && !ea && before.map { $0.isASCII && $0.isNumber } == true && following.map { $0.isASCII && $0.isNumber } == true)
                            || (RichTextTheme.wordWindowsPages && ch == "\u{2014}" && !ea && before.map { $0.isASCII && $0.isLetter } == true) {
                    // (… nor after one that follows a closing bracket, before digits: zh-22ecbdc8's
                    // "…达1000（含）" / "—5000人/年" in Word's print, and lab legsq's "（含）—5000" taken or
                    // left whole; ours parted "—" from "5000". Word's prints end a line on "—" with digits
                    // after it 3 times in the corpus, none after a bracket.)
                    // (Nor on either side of an em dash between digits — a span
                    // of years: zh-b378d8c4's "（2021—2030年）" goes down whole
                    // in Word's print, its "（" unable to end a line; the
                    // engine parted it at the dash.)
                    // (Before the dash, a Latin dash only, as that one is, in
                    // Times: one set in the East Asian face, hinted so, may open
                    // a line, the digits after it kept with it — zh-8d6f702e's
                    // and zh-c2f6d17a's "…面雨量达100" / "—150毫米" in Word's
                    // print, where ours took "100—150" down whole, and
                    // zh-81a32de0's "…以上。（1" / "—5分）". Lab `dash` (Word for
                    // Windows, zh-8d6f702e's package): the same "—" hinted
                    // default in Times goes down with "100—150", with or without
                    // `doNotUseEastAsianBreakRules`; the face decides.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, before == " ", ch == "/" {
                    // (Unicode forbids a break before "/" even after a space,
                    // so the engine backed up a word; Word breaks there, in
                    // Korean, Latin and Chinese alike (lab slash, 4 prints).
                    // kor-z15852510-c9baf7's `가짐." />` keeps `가짐."` and
                    // sends "/>" down.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, breaksAtQuotes, !lineRulesOff, before == " ", Self._closingMarks.contains(ch) {
                    // (Nor before a closing mark after spaces, which may no
                    // more start a line there than anywhere: zh-f47b8a74's
                    // "…将罚款缴至" and 19 underlined spaces, then "，账号",
                    // go down whole in Word's print, "至" opening the line;
                    // the engine broke after the spaces, and the line after
                    // began with the "，".)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if RichTextTheme.wordWindowsPages, theme.wordRules, ea,
                          (before == "\u{2014}" && ch == "\u{2014}")
                            || ((ch.unicodeScalars.first?.value).map { 0x2260 ... 0x226F ~= $0 } == true
                                && before.map { $0.isASCII && ($0.isLetter || $0.isNumber) } == true) {
                    // (A line may break between the two dashes of an East Asian "——", and
                    // before a mathematical sign set as East Asian after Latin letters or
                    // digits, Word for Windows: zh-447f1d5c's "…准则5号—" / "—公共基础设施》"
                    // and zh-0060058e's "…中型排水管道（600mm" / "≤管径＜1000mm）" in Word's
                    // print, both runs hinted East Asian (the comparison signs only: zh-0978dee9's
                    // ratio "6∶3∶1" stays whole); the engine kept "——" whole and
                    // "600mm≤管径" together, and carried both down.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if RichTextTheme.wordWindowsPages, theme.wordRules, ch == "/", let b = before, "）」』】〉》〕］｝".contains(b) {
                    // (A line may break between a full-width closing bracket and a "/", Word for
                    // Windows: zh-6e7ff836's cell formula "…實際數平均值）/ 前3年…" ends a line
                    // "…平均值）" in Word's print, the "/" opening the next; the engine, which never
                    // breaks before a slash, squeezed the "）" to keep "值）/" on the line.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if RichTextTheme.wordWindowsPages, theme.wordRules, ch == "\u{FE6A}", before.map({ $0.isASCII && $0.isNumber }) == true {
                    // (A line may break between a digit and the small percent
                    // sign "﹪", which is no Latin "%": zh-146f4e02's "…價值）的8﹪給予"
                    // ends a line "…的8" in Word for Windows' print, the "﹪"
                    // opening the next (six such lines); the engine keeps a
                    // number with its percent sign and carried the "8" down.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, before == "-", ch.isASCII, ch.isNumber,
                          (wordHasLetter && beforeBefore.map { $0.isASCII && ($0.isLetter || $0.isNumber) } == true)
                            || beforeBefore.map { !$0.isASCII && Self.isEastAsian($0, hinted: false) } == true {
                    // (A line may break after a hyphen before a digit, as
                    // after one before a letter: zh-15f60bac's "…公布之
                    // CNS11643-2(中文字基礎部件…" ends a line "CNS11643-" in
                    // Word's print and starts the next "2(中文字"; the
                    // engine, by Unicode's rules, keeps a hyphen with the
                    // number after it, and took "CNS11643-2" down whole.
                    // Not in a number alone: zh-64044a1d's narrow cells set
                    // "0932-757839" as "0932-75783" and "9", a telephone
                    // number parted where it fills the line, not at its
                    // hyphen; nor zh-dd4c6e05's "（110-116", a span of years,
                    // which Word keeps whole — while its "（110 年-114 年）"
                    // ends a line "年-": a hyphen after an ideograph.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, !lineRulesOff, before == " ",
                          ch == "%" || ch == "‰" || ch == "℃" || Self._closingMarks.contains(ch) {
                    // (Nor after spaces before a mark no line may start
                    // with: Word goes back to the break before them.
                    // zh-f43c9edf's "提取    %作为…" — a blank to fill in —
                    // ends a line "提" and starts the next "取    %" in
                    // Word's print; the engine parted it at the spaces and
                    // opened the line with "%".)
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if traditionalLists, !lineRulesOff, ch == "\u{FF05}", let b = before, b.isASCII, b.isNumber {
                    // (Before a full-width percent sign after a number, where
                    // Word's Traditional Chinese lists hold: they do not keep
                    // "％" from a line's start, as its Simplified one does.
                    // zh-499adba6's "…占比為38.54" ends page 25's first line
                    // in Word's print and "％，女性理事…" opens the next;
                    // the engine, by Unicode's rules, keeps a number's sign
                    // with it, took "38.54％" down and set every line after
                    // two characters behind.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                } else if RichTextTheme.wordWindowsPages, theme.wordRules, (document.compatibilityMode ?? 12) >= 15, ch == "\u{30FB}", document.hasKana,
                          document.eastAsiaLanguage?.hasPrefix("ja") != true, let b = before, (b.unicodeScalars.first?.value ?? 0) >= 0x3040, !Self._openingMarks.contains(b) {
                    // (Word for Windows opens a line with the katakana middle dot at compat 15 in kana text tagged
                    // zh-CN: 8787f4 p8 ends "…リスクテイク" and starts "・高速な…", 4 lines so; the engine keeps it with the character before.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    inserts.append(offset)
                } else if plainNoLineRules, document.hangsLatinStops, latinAfterEastAsian, let b = before, b.isASCII, !latinRunBracket || ch == "/", b.isLetter || b.isNumber || b == ".", (ch.isASCII && (ch.isLetter || ch.isNumber || ch == "/") || ch == "\u{2192}") {
                    // (The same file breaks a Latin run that follows East Asian text with no space anywhere
                    // inside it: jpn-z21601833-4e6465 ends lines "…DA|G」", "…（rev|27", "…三角形数＝2E|/3。"
                    // and starts "/450）"; a run opened by a space stays whole: "…厳密に E/3。".)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    inserts.append(offset)
                } else if plainNoLineRules, ch == "\u{30FB}", let b = before, (b.unicodeScalars.first?.value ?? 0) >= 0x3040, !Self._openingMarks.contains(b) {
                    // (A plain file with no line rules (Pandoc's en-US) opens a line with the middle dot too:
                    // jpn-z21601833-4e6465 p6 ends "…完全な終了" and starts "・完全な静止を取らない".)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    inserts.append(offset)
                } else if pausesOpenLines, ch == "\u{3001}" || ch == "\u{3002}" || ch == "\u{FF09}", let b = before, !Self._closingMarks.contains(b) {
                    // (A full-width ")" too: 8787f4 p8 ends "…（ドーシ, 1982" and opens the next line with "）。".)
                    // (Where the pause rule holds Word opens a line with 、 or 。 rather than
                    // hang it or carry the character before it down: lab `sqreal`.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    inserts.append(offset)
                } else if RichTextTheme.wordWindowsPages, theme.wordRules, (document.compatibilityMode ?? 12) == 14, document.characterSpacingControl == "compressPunctuation",
                          document.markSqueezeEm == 0, ch == "\u{FF0C}" || ch == "\u{3001}" || ch == "\u{3002}", let b = before, !Self._closingMarks.contains(b) {
                    // (Under compressPunctuation at compat 14 with no language or ko-KR, whose marks Word never
                    // squeezes (glyph advances 12.0 of 12.0 and 16.0 of 16.0, lab comma-hang7 v6/v8), Word opens
                    // a line with the mark rather than hang it or carry the character before it down.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    inserts.append(offset)
                } else if (kinsokuOff || plainNoLineRules || (RichTextTheme.wordWindowsPages && theme.wordRules && document.defaultLangXML == nil && document.eastAsianDefaultFaceIsLatin && !document.bodyStatesLang)) && !breaksAtQuotes, let b = before,
                          Self._closingMarks.contains(ch) || Self._latinCloser(b, ch)
                            || (ch != " " && (Self._openingMarks.contains(b) || Self._latinOpener(b, ch))
                                && Self._plainOrKinsoku(plainNoLineRules, kinsokuOff, Self._eastAsianLineRules(run, document, named: named)) && Self._plainOpenerBreak(plainNoLineRules && !kinsokuOff && !openerBeforeLatin, ch)) {
                    // The paragraph's explicit kinsoku=0 works without
                    // useFELayout too: fresh Word's comma/parenthesis controls
                    // have identical breaks with that switch on and off.
                    // Keep the other FE-layout break opportunities separate.
                    // This synthetic break has no line metrics: its Latin
                    // stand-in otherwise enlarges a mixed-size FangSong line
                    // (zh-202582e2 p5) despite having no glyph to draw.
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    inserts.append(offset)
                } else if RichTextTheme.wordWindowsPages, theme.wordRules, (document.compatibilityMode ?? 12) >= 15, p.style.alignment == .justify, !kinsokuOff, ch != " ", let b = before,
                          document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true, Self._openingMarks.contains(b), document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false,
                          (ch.unicodeScalars.first?.value ?? 0) >= 0x2E80, adjust[-(offset + 1)] == nil {
                    // (Under compressPunctuation Word may end a line on an opening
                    // mark, squeezed by up to half its em: labs opn1 and opn11, 8787f4.
                    // The fit decides, and a mark it would carry gets the key -(offset+1).)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    inserts.append(offset)
                } else if breaksAtQuotes, let b = before, !(Self._closingQuote(ch) && b.isASCII && b != " " && b != "\n"),
                          // (A closing quote right after an ASCII character is no break, whatever the East Asian
                          // rules say: xa gv-690391482c (en-GB East Asian language, usesEastAsianLayout) keeps
                          // "individuals.”" whole in Word's print, ours sent the quote down alone.)
                          Self._breaksBetween(b, ch, percentStarts: percentStarts, timesEastAsian: hinted, shapesPart: (document.compatibilityMode ?? 12) >= 15 || RichTextTheme.wordWindowsPages, latinQuotes: theme.wordRules && !hinted) || (lineRulesOff && (Self._closingMarks.contains(ch) || Self._latinCloser(b, ch)))
                            || (theme.wordRules && Self._closingQuote(ch) && (kinsokuOff && hinted && RichTextTheme.wordWindowsPages || !Self._eastAsianLineRules(run, document, named: named)))
                            // (And end one with an opening mark, where it is
                            // `w:kinsoku` 0 that turns them off in text of an
                            // East Asian language: zh-72da925e (zh-TW) ends
                            // a line "…（下稱「" in Word's print, "中" opening
                            // the next. Not where the language is not one —
                            // zh-c5b5087b's en-US carries "（" over.)
                            || ((kinsokuOff || plainNoLineRules) && ch != " " && (Self._openingMarks.contains(b) || Self._latinOpener(b, ch)) && Self._plainOrKinsoku(plainNoLineRules, kinsokuOff, Self._eastAsianLineRules(run, document, named: named)) && Self._plainOpenerBreak(plainNoLineRules && !kinsokuOff && !openerBeforeLatin, ch))
                            // (A full-width opening quote the same: zh-b00fef0d's "…其中" sends "“1" down whole,
                            // the quote unable to stay alone at the line's end 12pt over.)
                            || (kinsokuOff && RichTextTheme.wordWindowsPages && ch != " " && (b == "\u{201C}" || b == "\u{2018}") && runHinted(atOffset: offset - 1) && Self._eastAsianLineRules(run, document, named: named))
                            // (In a line too narrow for one character
                            // every character is a line, the marks
                            // too: zh-830ef10d's 6pt cell sets
                            // "个性要求（6分）" one to a line in Word's
                            // print, "（" and "6" and "分" and "）" each
                            // alone, where ours kept "（6" and "分）".)
                            || (b != "\n" && textWidth > 0 && textWidth < (style(kind).fontSize ?? 0)) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    inserts.append(offset)
                }
                }
                _sblk1()
                // (The opening quote's blank: a word joiner as wide as
                // the blank, which no line parts from the quote — at a
                // line's start the blank leads the mark, as in Word,
                // and none is left at the end of the line before. What
                // the line fitting takes off the quote comes off it.)
                if quote, blankShown > 0, ch == "\u{201C}" || ch == "\u{2018}" {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: style(kind).copyWith(letterSpacing: max(0, blankShown + (adjust[offset] ?? 0)))))
                    inserts.append(offset)
                    led = true
                }
                beforeBefore = before
                if ch == "(" || ch == ")" || ch == "-" { latinRunBracket = true } else if !ch.isASCII || ch == " " { latinRunBracket = false }
                if ch.isASCII, ch != " " { latinAfterEastAsian = latinAfterEastAsian || (before.map { c in let v = c.unicodeScalars.first?.value ?? 0; return !c.isASCII && v >= 0x2E80 } ?? false) } else { latinAfterEastAsian = false }
                before = ch
                if ch == "\u{00A0}" { spacesAfterNbsp = true } else if ch != " " { spacesAfterNbsp = false }
                wordHasLetter = ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-") ? wordHasLetter || ch.isLetter : false
                if let c = current, c != kind { flush(i) }
                else if joinedFace != nil, isArabic(ch) != (beforeBefore.map(isArabic) ?? false) { flush(i) }
                current = kind
                // What this character is set wider or narrower by: Word's
                // automatic space between an ideograph and the Latin
                // letter or digit beside it (`w:autoSpaceDE` and
                // `w:autoSpaceDN`, on unless the paragraph says
                // otherwise); the half em it takes off the first of two
                // punctuation marks that stand together; and what the
                // line fitting asked of this one.
                // (What the joiner could not give, the quote gives.)
                var extra = led ? min(0, blankShown + (adjust[offset] ?? 0)) : adjust[offset] ?? 0
                if quote, !led { extra += blankShown }
                // (Balanced, a half-width character takes half of the
                // grid's addition, whatever follows it: on a grid of
                // 1.008pt Word sets a digit 0.504 wider than its face
                // does, before another and before an ideograph, and a
                // bracket and a letter the same. Lab `cg3`, 2026-10-13,
                // glyph by glyph. It was the full addition before an
                // ideograph here, which the automatic space hid — see
                // the gap below — and a paragraph with that space off
                // showed: zh-457a8d62 lost a character a line.)
                // (The paragraph's last character too: zh-72da925e's 12pt
                // cell "(內湖)" is 39.02 on its grid of 1.0076 — lab tgr,
                // windows-1: Word sets each character at whole multiples
                // of the pitch, half-width ones at half — and fits its
                // 39.05 column in Word for Windows' print; ours gave the
                // closing ")" the whole addition, 39.53, and wrapped it.)
                // (Word for Windows': the Mac's print of the same file
                // gives that last character the whole addition — its
                // pair fell 86.7 -> 71.1 with this — so there it stays.)
                if !ea, document.balancesSpaceWidth, let g = grid, g != 0, ch != " ",
                   following.map({ $0 != " " }) ?? (theme.wordRules && RichTextTheme.wordWindowsPages) {
                    extra -= _px(g) / 2
                } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, document.balancesSpaceWidth, let g = grid, g != 0,
                          ch == " " || following == " ", kind >= 0, !wideSpaces.contains(offset),
                          { () -> Bool in
                              // (Latin on both sides of the space: a letter before it, the space, or a space before a letter.)
                              let gapAt = ch == " " ? i : after
                              guard gapAt > text.startIndex, gapAt < text.endIndex else { return false }
                              let before = shown(text[text.index(before: gapAt)])
                              let afterGap = text.index(after: gapAt)
                              guard afterGap < text.endIndex else { return false }
                              let nxt = shown(text[afterGap])
                              return before != " " && nxt != " " && !RichLayout.isEastAsian(before, hinted: hinted) && !RichLayout.isEastAsian(nxt, hinted: hinted)
                          }() {
                    // (A plain space between Latin words, and the letter before it, are
                    // half-width characters like the rest: half the addition each. zh-c2c92639's
                    // contents page: a word gap was 2.25 + 1.5 g, Word's 2.25 + 0.5 g.)
                    extra -= _px(g) / 2
                }
                // (In a paragraph off the grid, that half alone — no
                // whole addition to take it from: zh-8d6f702e's "24小时…
                // 150毫米" paragraph, `w:snapToGrid` 0 on a grid of -0.21,
                // sets each digit 7.90 in Word's print, Times's 8 less
                // half; ours 8.00, and the line took nothing Word's does.
                // Before a space, or a space, nothing: zh-268f8d15's
                // footer "- 1 -" is Times's own widths. Nor in a header or
                // footer, which keeps to no grid: zh-3c055c9b's page number.)
                if !ea, grid == nil, document.balancesSpaceWidth, let g = ideographGrid, g != 0, _grid(index, document).pitch != nil,
                   ch != " ", let following, following != " " {
                    extra += _px(g) / 2
                }
                // (A symbol set in an East Asian face that gives it a width
                // of its own takes that width, and half the grid's addition
                // as a half-width character does: YaHei's "…" is 0.8135 em,
                // and zh-457a8d62's "……" are 13.52pt apiece at 16pt on its
                // grid of 1.0076 in Word's print — 13.016 and 0.504 — where
                // the stand-in's em-wide glyph and the whole addition set
                // them 17.01, and its line "…奢侈放蕩……等，足以損失" lost
                // its "失".)
                if kind == -9 { extra += cambriaWidth * em - _glyphWidth(style(kind), ch) }
                // (A quotation mark in a run that says `w:hint` "default" over
                // an East Asian ASCII face and a Latin hAnsi one is the hAnsi
                // face's, at its width: zh-785e46f8's “ ” in 仿宋_GB2312 over
                // a Times hAnsi are 7.1pt at 16pt in Word's print, where the
                // stand-in set them 8.0 and the line lost a character.)
                if theme.wordRules, !ea, ch == "\u{201C}" || ch == "\u{201D}" || ch == "\u{2018}" || ch == "\u{2019}",
                   (run.fontHint ?? named?.char.fontHint) == "default", latinFace?.isEastAsian == true, highFace.map({ !$0.isEastAsian }) == true,
                   let high = run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily {
                    var alt = run
                    alt.fontFamily = high
                    let s = theme.textStyle(for: alt, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            eastAsian: false, gridPitch: pitch, characterClass: nil, characterGrid: grid, scriptHidden: true)
                    extra += _glyphWidth(s, ch) - _glyphWidth(style(kind), ch)
                }
                // (And a "×" or "÷" so set, at the hAnsi face's width: see `ea` above.)
                if !ea, latinDash, RichTextTheme.wordWindowsPages, ch == "\u{00D7}" || ch == "\u{00F7}",
                   let high = run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily {
                    var alt = run
                    alt.fontFamily = high
                    let s = theme.textStyle(for: alt, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            eastAsian: false, gridPitch: pitch, characterClass: nil, characterGrid: grid, scriptHidden: true)
                    extra += _glyphWidth(s, ch) - _glyphWidth(style(kind), ch)
                }
                // (A dash set in the hAnsi face's Times is half an em, as Word prints it: lab `semi` round 3 (Word for
                // Windows, zh-ea70c30e's 12.5pt PMingLiU run over a Times hAnsi): every "–" is 6.24, ours 5.88, and the
                // three of a line made it 1.1pt too short — it took "動" Word sends down.)
                if !ea, latinDash, RichTextTheme.wordWindowsPages, ch == "\u{2013}", highFace == nil || highFace.map({ !$0.isEastAsian }) == true {
                    extra += em / 2 - _glyphWidth(style(kind), ch)
                }
                // (An em space is an em and an en space half one, whatever face
                // sets them: zh-8415d258's paragraphs open with two U+2003 in
                // a 仿宋_GB2312 run, 15pt apiece at 15pt in Word for Windows'
                // print (in Cambria Math), where the stand-in's fallback set
                // them 6.7 and every such first line took a character more.)
                // (Arial has the en space itself, 0.557 em: ten of them are 66.84pt at
                // 12pt in Word's print — lab `spaces` — where the half em makes them 60.)
                // (A no-break space is not ASCII to Word: in a run whose ASCII
                // face is East Asian over a Calibri hAnsi it is Calibri's
                // space, 0.2261 em, not the East Asian face's half em —
                // zh-ea43dd6d's signature line, eight U+00A0 then 25 spaces
                // before "嘉兴市财政局" in 仿宋_GB2312 at 16pt: the eight
                // are 3.6pt each in Word's print, and ours set them 8 and
                // wrapped the name.)
                let nbspHAnsi = theme.wordRules && RichTextTheme.wordWindowsPages && !ea && ch == "\u{00A0}" && latinFace?.isEastAsian == true
                    && !run.hAnsiNamedAsAscii && !(run.fontFamily == nil && (named?.char.hAnsiNamedAsAscii ?? false))
                    && hAnsiFace.map({ !$0.isEastAsian && ["calibri", "carlito"].contains($0.family.lowercased()) }) == true
                if nbspHAnsi {
                    RuleTrace.hit("no-break-space-is-the-hansi-faces-not-the-east-asian-ones")
                    extra += 0.2261 * em - _glyphWidth(style(kind), ch)
                }
                if theme.wordRules, ch == "\u{2003}" || ch == "\u{2002}" {
                    let arial = ch == "\u{2002}" && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").lowercased() == "arial"
                    extra += (ch == "\u{2003}" ? 1 : arial ? 0.557 : 0.5) * em - _glyphWidth(style(kind), ch)
                }
                // (A symbol face's glyph drawn by a stand-in takes the face's
                // own advance: Wingdings 2's box is 0.89 em in Word's print
                // of zh-d0a207ac, 10.68 at 12pt, where the stand-in's is an
                // em, and its "☐鲁班杯" line lost its "杯".)
                if symbolsShown, let w = theme.symbolAdvance?(run.fontFamily ?? named?.char.fontFamily, ch) { extra += w * em - _glyphWidth(style(kind), ch) }
                // (The ballot box with check ☑, U+2611, in a SimSun run is Segoe
                // UI Symbol's in Word's print — 1758/2048 = 0.858 em — where the
                // fallback face here sets it 0.89 and zh-a7a889eb's
                // "☑10、…复印件" lost its last character.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{2611}", !(symbolsShown && theme.symbolAdvance?(run.fontFamily ?? named?.char.fontFamily, ch) != nil) {
                    RuleTrace.hit("ballot-box-with-check-is-segoe-ui-symbols")
                    extra += (1758.0 / 2048.0) * em - _glyphWidth(style(kind), ch)
                }
                // (The long double arrow ⟺, U+27FA, is Cambria Math's in Word for Windows' print, 1.183 em
                // (14.2 pt at 12 pt, jpn-z21601833-4e6465 p12), where the fallback face here sets it 1.43.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{27FA}" {
                    RuleTrace.hit("long-double-arrow-is-cambria-math")
                    extra += 1.1836 * em - _glyphWidth(style(kind), ch)
                }
                // (The rightwards arrow → in a Cambria run is 10.05 pt at 12 pt in Word for Windows' print
                // (jpn-z21601833-4e6465 p16: 301.3 to 311.3, 388.1 to 398.2), 0.8374 em, where the fallback sets it 0.8.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{2192}",
                   (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily ?? "").lowercased() == "cambria" {
                    RuleTrace.hit("rightwards-arrow-in-cambria")
                    extra += (1715.0 / 2048.0) * em - _glyphWidth(style(kind), ch)
                }
                // (A Hangul syllable is an em wide in every Korean face
                // Word for Windows sets it in — Malgun Gothic, Gulim, Batang:
                // all 1.000 em across the kor batch B prints — where the
                // Noto Sans CJK stand-in's is 0.92. Lines held 8% more text
                // and the pages drifted.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value,
                   u >= 0xAC00 && u <= 0xD7A3 {
                    let g = _glyphWidth(style(kind), ch)
                    // (A face may carry its own Hangul em under U+AC00 of otherAdvances: NanumGothic 0.94.)
                    let hEm = (theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                   ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.otherAdvances?[0xAC00]).map { $0 * em * wScale } ?? em * wScale
                    // (A character scale, w:w, narrows the syllable too: dx2 211f43df's 95% Gulim 11 pt is 10.44 in Word's print, 11.04 here.)
                    if g > 0.5, hEm < em * wScale ? abs(g - hEm) > 0.01 : g < hEm - 0.01 {
                        RuleTrace.hit("hangul-syllable-is-an-em")
                        extra += hEm - g
                    }
                }
                if ea || (ch == "\u{B7}" && (run.loneDot || tcFit) && theme.wordRules), let u = ch.unicodeScalars.first?.value, u < 0x2E80 || (u >= 0x3000 && u < 0x3100) || (u >= 0xFF00 && u < 0xFF60),
                   let eaFace = theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                    ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true),
                   ea || eaFace.malgunSymbols,
                   var w = (style(kind).fontWeight == .bold ? eaFace.boldOtherAdvances : eaFace.otherAdvances)?[u] {
                    // (A run holding ONLY the middle dot has no Hangul to take Batang from, so Word draws it in Malgun
                    // Gothic: 0.2188 em (bold 0.2617), where a dot inside a Hangul run is Batang's 0.333. 28dd0ac0's title.)
                    if u == 0xB7, eaFace.malgunSymbols, theme.wordRules, RichTextTheme.wordWindowsPages, run.loneDot || tcFit {
                        RuleTrace.hit("lone-middle-dot-run-is-malgun")
                        w = style(kind).fontWeight == .bold ? 0.2617 : 0.2188
                    }
                    extra += (w ?? 0) * em - _glyphWidth(style(kind), ch)
                    if document.balancesSpaceWidth, let g = grid, g != 0 { extra -= _px(g) / 2 }
                }
                // (Fit text: Word gives the middle dot only HALF a gap after it, labs dot1 and mar2: 7.2 pt after a Malgun dot
                // at 24 pt where a full gap is 11.7; the gap before it is the full one, from the letter ahead.)
                if ch == "\u{B7}", tcFit, fitGroup != nil, let f = fitSpacing() { extra -= f / 2 }
                // (A CJK compatibility ideograph YaHei lacks and Word for
                // Mac's Noto Sans SC does not give it is YaHei's own
                // missing-glyph box, 0.697 em, in the line's breaking as
                // in its drawing: zh-12c4f07a's "於契約…本委" ends at "委"
                // in Word's print, its "契" U+F909 a box 9.06pt wide at
                // 13pt, where ours set it an em and "委" went over. Lab
                // `cj` (Word for Mac): U+F909 and U+FA01 give 0.30 em more
                // room than U+5951 and U+5EA6, at 13 and 14pt, anywhere on
                // the line.)
                if ea, let u = ch.unicodeScalars.first?.value, u >= 0xF900, u <= 0xFAFF, !Self._notoCompatibility.contains(u),
                   theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.lacksCompatibilityIdeographs == true {
                    extra += 0.697 * em - _glyphWidth(style(kind), ch)
                }
                // A symbol an East Asian run sets in its own face (■□●○
                // ◆△※, the circled numbers, arrows) is an em wide there, as
                // every such face draws it; the face drawing it here may
                // be a Latin fallback's narrower glyph — zh-abe7e063's ■
                // came out 6.04pt at 10pt where Word's SimSun sets 10, and
                // a table cell's line took a character Word wraps.
                // (So is the hyphenation point "‧", U+2027 — the zh-TW
                // middle dot of "亞洲‧矽谷" — and the bullet and two-dot
                // leader beside it, whichever kind the layout counts
                // them: PMingLiU sets each an em, and zh-190d730c's
                // line of it at 6.2pt took a character Word wraps.)
                if let u = ch.unicodeScalars.first?.value,
                   !(symbolsShown && theme.symbolAdvance?(run.fontFamily ?? named?.char.fontFamily, ch) != nil),
                   !(theme.wordRules && RichTextTheme.wordWindowsPages && u == 0x2611),
                   (ea && u >= 0x2190 && u <= 0x266F) || u == 0x2027 || u == 0x2025 || (ea && u == 0x2022)
                    // (And the reference mark ※ where the run's Latin face is a square face too: zh-ae2dd08d's
                    // 標楷體 "※依照財政部…" sets it 14pt at 14 in Word's print, where DejaVu's 11.8 took "就"
                    // onto the line.)
                    || (u == 0x203B && (ea || latinFace?.isEastAsian == true)),
                   theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.fullWidthSymbols == true {
                    let g = _glyphWidth(style(kind), ch)
                    if g > 0.5, g < em - 0.01 { extra += em - g }
                }
                @inline(never) func _sblk2() {
                if wideSpaces.contains(offset) {
                    // (Half an em and the run's own spacing once more,
                    // as Word measures it: 8.31pt at 16pt spaced 0.15.
                    // A face Word emboldens widens each character by its
                    // spread, and the space, a half-width character,
                    // by half of it — not by the whole, and not by the
                    // Latin stand-in's once more: 5.72pt at 12pt in
                    // 楷体_GB2312 bold spaced -0.2, where 6.02 wrapped a
                    // line of zh-232090e0 that Word keeps; lab `sp`,
                    // 2026-10-14.)
                    let s = style(kind)
                    let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    let eaFace = theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily
                                                     ?? run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, true)
                    let own = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    let spread = bold ? own * theme.pixelsPerPoint * scale : 0
                    // (The stand-in's spread is in the style's spacing,
                    // which the engine applies and the line above adds
                    // once more: off twice.)
                    // (An embedded subset is different on Mac with an explicit
                    // Latin face: tc22's embedded FangSong_GB2312 over Times or
                    // Arial sets plain balanced spaces at 3/8 em, left-aligned
                    // or justified. Removing the embedding restores 1/2 em, as
                    // do ordinary named FangSong, SimSun, KaiTi and YaHei.
                    // Mixed NBSP runs keep their existing half-em rule.)
                    // (Whether or not the subset holds a space: lab esp, from
                    // zh-d9b085b1, whose FangSong_GB2312 has one — 3/8 em over
                    // Times, Arial or Courier New alike, in mode 12 and 15;
                    // 1/2 em with the embedding stripped, under 宋体, or under
                    // an embedded 黑体, which Word for Mac draws in its own
                    // SimHei. Word for Windows: 1/2 em.)
                    let missingSpace = !RichTextTheme.wordWindowsPages && ordinaryBalancedSpaces.contains(offset)
                        && latinFace?.isEastAsian == false && eaFace?.drawnFromSubset == true
                    // (The subset's spaces keep 3/8 em in bold too,
                    // while its ideographs widen: the 12/16/20pt lab.)
                    let fraction = missingSpace ? 0.375 : 0.5
                    // (Half the run's em as scaled, `w:w`: zh-4e5fe46f's space
                    // at w 95 is 4.32 in Word for Windows' print — 10.5 x 0.95
                    // / 2 less the doubled spacing — where ours set 4.55.)
                    extra += em * wScale * fraction - _spaceWidth(s) + (s.letterSpacing ?? 0)
                        - 2 * spread * (latinFace?.boldSpread ?? 0) + (missingSpace ? 0 : spread * (eaFace?.boldSpread ?? 0) / 2)
                    // (A trailing space set in the ideographs' face (kind -2)
                    // has the stand-in's width in its spacing: that is not
                    // the run's own, and not counted twice — zh-9dd9ce6d's
                    // five after "…发布" at 14.25pt are 7.15 apiece in Word's
                    // print, ours 13.3, and its footer took a line more.)
                    // (Not the fit pitch of a w:fitText group, which the space takes
                    // once like every character: zh-a4b0f6ea's "单位(盖章)：   年 月 日"
                    // set each space 0.07 too wide and 日 2 pt right of Word's.)
                    if fitGroup != nil, !fitBusy, let f = fitPitch { extra -= f }
                    if kind == -2 {
                        let base = style(classed ? RichResolvedFace.characterClass(" ") : 0)
                        extra -= 2 * ((s.letterSpacing ?? 0) - (base.letterSpacing ?? 0))
                    }
                    // (The grid's addition, which the style's spacing holds
                    // too, half of it, not twice: zh-f0bd9ea8's two spaces
                    // after "第一条" on a grid of -0.21 are 7.9pt apiece at
                    // 16pt in Word's print, ours 7.6, and every line took a
                    // character Word wraps.)
                    if let grid, grid != 0 { extra -= 1.5 * _px(grid) }
                } else if !ea, let face = (narrowLatinInRTL ? nil : latinFace), face.advances != nil, ch.unicodeScalars.count == 1,
                          let u = ch.unicodeScalars.first?.value, u >= 0x20, u <= 0x7E {
                    // The width the original face gives this character
                    // (`RichResolvedFace.advances`), at the size the
                    // style sets it less the stand-in's scales.
                    // (A trailing space set in the ideographs' face, kind
                    // -2, has the stand-in's width already: measured
                    // against the stand-in's own, as any other.)
                    let own = kind == -2 ? (classed ? RichResolvedFace.characterClass(" ") : 0) : kind
                    let s = style(own)
                    let k = Int(u) - 0x20
                    if let table = face.advanceTable(bold: s.fontWeight == .bold, italic: s.fontStyle == .italic), k < table.count, table[k] > 0, let px = s.fontSize, px > 0.5 {
                        let classScale = classed ? face.classScales.flatMap { own >= 0 && own < $0.count ? $0[own] : nil } ?? 1 : 1
                        var target = table[k] * px / (face.sizeScale * classScale)
                        // (Kerned with the next of the run by the original's
                        // pair, where the run kerns at its size: zh-d89c3840's
                        // "（TC）" in YaHei at 16pt, "T" 8.4 in Word's print
                        // where its advance is 9.17, and its line took "秘".)
                        let kernsFrom: Double? = run.kerningFrom ?? named?.char.kerningFrom ?? _normalChar(document)?.kerningFrom
                        let points: Double = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
                        let pairs: [UInt32: Double]? = s.fontWeight == .bold ? face.boldKerns : face.kerns
                        if theme.wordRules, let from = kernsFrom, from > 0, points >= from, let pairs, after < text.endIndex,
                           let v = shown(text[after]).unicodeScalars.first?.value, v >= 0x20, v <= 0x7E, let pair = pairs[u << 8 | v] {
                            target += pair * px / (face.sizeScale * classScale)
                        }
                        // (On the print's grid too, kerned as the stand-in
                        // kerns, where the theme has one: `advanceGrid`.)
                        if let grid = theme.advanceGrid, grid > 0 {
                            let size = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
                            let kerns = (run.kerningFrom ?? named?.char.kerningFrom).map { $0 > 0 && size >= $0 } ?? false
                            if kerns, let following { target += _pairAdvance(s, ch, following) - _glyphWidth(s, ch) }
                            let g = grid * theme.pixelsPerPoint * scale
                            if g > 0 { target = (target / g).rounded() * g }
                        }
                        extra += target - _glyphWidth(s, ch)
                    }
                } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, u == 0x2266 || u == 0x2267,
                          ch.unicodeScalars.count == 1, let w = RichLayout._cambriaMathOpeners2[u],
                          text[..<i].last.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) == true {
                    // (Cambria has no "≦" or "≧": Word for Windows sets them in Cambria Math, 0.7471 em wide;
                    // after a Latin letter or digit; after an ideograph it stays the East Asian face's full width (lab c2301a p3 "で≦2fm"). The fallback face's 0.84 pushed jpn-z21601833-c2301a's "…CHSH≦2、完" a character over.)
                    extra += w * em - _glyphWidth(style(kind), ch)
                } else if !ea, let grid = theme.advanceGrid, grid > 0, latinFace?.advances == nil, ch != "\t", !ch.isNewline,
                          latinFace?.otherAdvances.flatMap({ t in ch.unicodeScalars.first.flatMap { t[$0.value] } }) == nil,
                          ch.unicodeScalars.first.map({ $0.value >= 0x20 && $0.value < 0x2E80 }) ?? false {
                    // On the print's grid (`advanceGrid`) — kerned with the
                    // next where the run kerns at its size (`kerningFrom`).
                    let s = style(kind)
                    let size = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
                    let kerns = (run.kerningFrom ?? named?.char.kerningFrom).map { $0 > 0 && size >= $0 } ?? false
                    let w = kerns && following != nil ? _pairAdvance(s, ch, following!) : _glyphWidth(s, ch)
                    let g = grid * theme.pixelsPerPoint * scale
                    if g > 0, w > 0 { extra += (w / g).rounded() * g - w }
                } else if !ea, !nbspHAnsi, let u = ch.unicodeScalars.first?.value,
                          let face = (u >= 0x80 && highFace?.otherAdvances?[u] != nil ? highFace : nil) ?? latinFace, face.otherAdvances != nil,
                          // (A letter with its marks, where the table has each:
                          // Thai's "ต่", "คำ" — `OfficeFonts.browalliaAdvances`.)
                          ch.unicodeScalars.count == 1 || (u >= 0x0E00 && u < 0x0E80 && ch.unicodeScalars.allSatisfy { face.otherAdvances?[$0.value] != nil }),
                          // (Not a no-break space after an ordinary one, through
                          // others: that is the Latin text's, the space's half
                          // em — zh-f3802561's "第一条" + U+00A0, U+0020, U+00A0,
                          // U+00A0 in a 10.5pt 仿宋 run sets them 10.5, 5.25,
                          // 5.25 and 5.25 in Word's print; ours set every
                          // no-break one an em, and the line lost its "发".)
                          // (Nor one after a Latin letter or digit: zh-a7a889eb's
                          // 12pt 宋体 "3.5" + U+00A0 + U+0020 sets them 6 and 6,
                          // and its line took "业 贰 级" ours left for the next.
                          // After a "." it is an em still — zh-17749c13's
                          // "1." + U+00A0 + "船" is 14 at 14pt.)
                          !(theme.wordRules && u == 0xA0 && text[..<i].reversed().first(where: { $0 != "\u{00A0}" }).map({ $0 == " " || ($0.isASCII && ($0.isLetter || $0.isNumber)) }) == true) {
                    // … and the width it gives one the stand-in lacks.
                    // (Past ASCII, the `w:hAnsi` face's, where it has its own:
                    // zh-17749c13's no-break spaces in 仿宋_GB2312 runs whose
                    // hAnsi is 宋体 are SimSun's, an em each in Word's print.)
                    let s = style(kind)
                    let own = face.family == latinFace?.family
                    let table = s.fontWeight == .bold ? face.boldOtherAdvances : face.otherAdvances
                    let each = ch.unicodeScalars.map { table?[$0.value] }
                    if !each.contains(where: { $0 == nil }), let w = Optional(each.reduce(0) { $0 + ($1 ?? 0) }), let px = s.fontSize, px > 0.5 {
                        let classScale = classed ? face.classScales.flatMap { kind >= 0 && kind < $0.count ? $0[kind] : nil } ?? 1 : 1
                        var target = own ? w * px / (face.sizeScale * classScale) : w * em
                        // (On the print's grid, where the theme has one.)
                        if let grid = theme.advanceGrid, grid > 0 {
                            let g = grid * theme.pixelsPerPoint * scale
                            if g > 0 { target = (target / g).rounded() * g }
                        }
                        extra += target - _glyphWidth(s, ch)
                    }
                }
                }
                _sblk2()
                @inline(never) func _sblk3() {
                @inline(never) func _r2() {
                if let following {
                    // (Not beside a note's number: zh-499adba6's — "（SDGs）⁷作
                    // 為", "權能⁸，" (mode 14, 12pt) — have none either side in
                    // Word's print, and its line "…增強所有婦女和女" takes the
                    // last "女" there, 3pt nearer than ours. Other raised or
                    // lowered text keeps them: zh-27083953's "PM₂.₅为", "O₃为".)
                    let nextAt = offset + ch.utf16.count
                    let besideRaised = theme.wordRules && ((offset < raised.count && raised[offset]) || (nextAt < raised.count && raised[nextAt]))
                    // (Not where the Latin character's run names a Latin face for East Asian text, in Word for
                    // Windows: zh-cd48112c's digit runs say eastAsia "Times New Roman", and its print has no space
                    // either side of 138 digits; zh-a0e932c2's say 宋体, and it has its 5.3 at 39.)
                    // (Nor anywhere in a document whose defaults name a Latin face for East Asian text: lab `asd`
                    // (Word for Windows, mode 15, 15pt): docDefaults eastAsia Times New Roman sets "…30…" between
                    // 宋体 ideographs with no space at all, whatever the digit run says — none, Times, Times with
                    // hint eastAsia, all Times, 宋体 with the hint; with 宋体 there, a quarter em in all five.
                    // zh-a0e932c2's gaps of 5.3 are its typed spaces.)
                    if theme.wordRules, document.usesEastAsianLayout || (document.autoSpacesWithoutFELayout && document.eastAsianLineRules && (document.defaultLangXML?.containsSubstring("w:eastAsia=\"") == true || ((document.compatibilityMode ?? 15) < 15)) && RichTextTheme.wordWindowsPages), !besideRaised, !(RichTextTheme.wordWindowsPages && document.skipsAutoSpace), Self._autoSpaced(ch, following, p.style, compat: document.compatibilityMode ?? 12),
                       !(RichTextTheme.wordWindowsPages && document.eastAsianDefaultFaceIsLatin),
                       !(RichTextTheme.wordWindowsPages && eastAsianFaceIsLatin(atOffset: (ch.unicodeScalars.first?.value ?? 0) >= 0x2E80 ? nextAt : offset)) {
                        let latin = run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily
                        // (Of the grid's character, where there is a grid
                        // of them, and of the run's spacing with it; a
                        // flat quarter of the two where the widths are
                        // balanced — measured 4.0pt at 16pt, and 3.6 in
                        // Times without.)
                        // (… and of the grid's: 4.25pt either side of a
                        // digit at 16pt on that grid of 1.008.)
                        var gap = document.balancesSpaceWidth
                            // (A shrunk grid does not shrink it in a cell: lab `dig` (Word for Windows, zh-9c162f26's 9pt
                            // mode-14 cell, grid -0.21) cuts "应" between 4.21 and 4.31 over on a line with three digit
                            // boundaries and between 4.31 and 4.41 with none, the 0.15pt a quarter of the full em (2.25) over
                            // a quarter of the shrunk one (2.20) makes three times. In the body it does shrink it: zh-d68ac84a
                            // (grid -1.35), zh-eb54d3b0 and zh-8d6f702e lose lines with the full em.)
                            ? (em + _px(p.cell != nil ? max(0, grid ?? 0) : (grid ?? 0)) + 2 * spacing) / 4
                            : RichTextTheme.wordWindowsPages && ch.isASCII == false && (following.isNumber || following.isLetter) && following.isASCII
                            // (Letters the same as digits: lab jsp2, 9 prints, 7 faces, 14 and 10.5 pt: ideograph then letter a quarter em in
                            // every face, letter then ideograph half the face's OS/2 xAvgCharWidth.)
                            // (Each side its own, in Word for Windows: lab asz (zh-147bdae0's package, left-aligned,
                            // sizes varied) sets an ideograph then a digit a quarter of the ideograph's em apart —
                            // 3.00 at 12pt, 3.96-4.08 at 16, 2.28 at 9, whatever the digit's size — and a digit then
                            // an ideograph half the digit face's average width apart — Times 2.40 at 12pt, 1.86 at 9,
                            // 3.30 at 16, 標楷體 3.00 — whatever the ideograph's. Ours set both 2.70 beside Times, and
                            // lab asp's line took its character a step late.)
                            ? (em + _px(grid ?? 0) + spacing) / 4
                            : RichTextTheme.wordWindowsPages && (ch.isNumber || ch.isLetter) && ch.isASCII && following.isASCII == false
                            ? (2 * (theme.averageCharWidth?(latin) ?? 0.5) * (em + _px(grid ?? 0)) + spacing) / 4 * wScale
                            : ((0.5 + (theme.averageCharWidth?(latin) ?? 0.5)) * (em + _px(grid ?? 0)) + spacing) / 4
                        // (Twice inside text ruled round where the widths are
                        // balanced: labs `ap1`–`ap4`, zh-06c46ba9's boxed
                        // "範例1" sets "例" and "1" 21.1pt apart at 14pt in
                        // Word's print, 17.5 without the border or without
                        // the balance. Its reference lists took a character
                        // a line that Word wraps.)
                        // (A border said to be none is none: zh-f10c8f34's body runs
                        // carry `<w:bdr w:val="none"/>`, and Word sets "14号" with
                        // 2pt between, a quarter of its 8pt; ours took the run for
                        // ruled and set 4, and every line held a character less.)
                        if document.balancesSpaceWidth, let xml = run.keptXML, let r = xml.rangeOfSubstring("<w:bdr "),
                           case let tag = xml[r.upperBound...].prefix(while: { $0 != ">" }),
                           !tag.containsSubstring("w:val=\"none\""), !tag.containsSubstring("w:val=\"nil\"") { gap *= 2 }
                        extra += gap
                        autoSpaces?(offset, gap)
                    } else if ea, closes, Self.closesUp(ch, following, centred: document.marksCentred)
                                // (A middle dot after a closing mark closes it up too, in kana text at compat 15 on a grid: lab
                                // `jis4051`, Word for Windows, sets "」・" with the 」 at its half like "」。".)
                                || (following == "\u{30FB}" && Self._closingBracketMarks.contains(ch) && RichTextTheme.wordWindowsPages && theme.wordRules
                                    && (document.compatibilityMode ?? 12) >= 15 && document.lineGridPitch != nil
                                    && (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true))
                                // (The quote's own run says whether it is full-width, where the mark
                                // ends its run: zh-3ab8a2fb's "，" unhinted before a "“" hinted East
                                // Asian closes up, 7.13 in Word's print, and its line takes "机".)
                                || (fullQuotes && !narrowQuotes && (following == "\u{201C}" || following == "\u{2018}") && Self._closingMarks.contains(ch)
                                    && Self.isEastAsian(following, hinted: after < text.endIndex ? hinted : runHinted(atOffset: base + text.utf16.count)))
                                // (And before a full-width closing quote, mid-line with room as well: lab `sqp`
                                // (Word for Windows, zh-424775e4's p5 line, SimSun 12, kerned) sets "。”" 6 + 12 in
                                // modes 12 and 15 and under doNotCompress alike, and takes "机，" 6pt sooner than ours
                                // did with the "。" a whole em; the "。" not centred, as a closing bracket's.)
                                || (fullQuotes && !narrowQuotes && (following == "\u{201D}" || following == "\u{2019}") && Self._closingMarks.contains(ch)
                                    && !(document.marksCentred && "，。、；：！？".contains(ch))
                                    && Self.isEastAsian(following, hinted: after < text.endIndex ? hinted : runHinted(atOffset: base + text.utf16.count)))
                                // (Not a face's own narrow quote, which has no
                                // blank to give: zh-0aac9d1a's Arial Unicode MS
                                // "黑名单”。" keeps its 5.52pt "”" before the "。" in
                                // Word's print; ours took half an em off it, all of
                                // it, and the line took a "省" Word wraps.)
                                || (fullQuotes && !narrowQuotes && (ch == "\u{201D}" || ch == "\u{2019}") && Self.isEastAsian(ch, hinted: hinted)
                                    && (Self._closingMarks.contains(following) || Self._openingMarks.contains(following)
                                        || ((following == "\u{201C}" || following == "\u{2018}") && Self.isEastAsian(following, hinted: hinted)))) {
                        // (A closing mark before a full-width opening quote
                        // gives its half as before any opening mark: zh-15728c84's
                        // "微信、“12345”" sets "、" 5pt wide at 10pt in Word's print.)
                        // (And a full-width closing quote is a closing mark
                        // itself: the same document's "线上线下”、“舆情" sets
                        // "”" and "、" 5.2 and 5.3pt wide at 10.5, and a cell
                        // line took the character after "主体；" that ours
                        // left for the next. Where punctuation does not kern
                        // — `w:noPunctuationKerning`, zh-d68ac84a's "”（" —
                        // the quote keeps its em, as the marks do.)
                        // (Half its cell, on a character grid: labs `og3`/`og4`
                        // (Word for Windows, zh-eb54d3b0's package, 16pt)
                        // set "》，" "）、" "，“" 7.9 apart on a grid of -0.21
                        // and 8.5 on one of +1 — half the em and half the
                        // addition. Ours kept the whole addition, and
                        // zh-eb54d3b0's "…政策》，助推茶" took "产" 7.81 over
                        // where Word's is 7.91 and goes down.)
                        // (A spaced closing quote gives half its spaced width:
                        // lab `p01`, zh-01bbcd4d's "…组织成员”。" at 16pt spaced
                        // to 17 sets the "”" 8.49 before the "。" in Word's
                        // print; ours, half the em off, 9.0.)
                        // (And a mark condensed keeps half its condensed width:
                        // zh-5be7e156's Normal, spaced -0.3 with the widths
                        // balanced (so -0.6 a full-width character) on a grid
                        // of -0.21, sets "）、" and "》（" 7.6 apart in Word's
                        // print — half of 15.2 — where ours, half the em off
                        // and all of the spacing kept, set 7.3, and its p1
                        // line took a "家" Word leaves.)
                        // (Any closing mark the same: zh-01bbcd4d's "…不提交竣工材料）；" sets the "）" 8.52 before the "；"
                        // in Word's print, half of its 17; ours, 9.0, left "料）；" 0.2pt short of the line Word takes.)
                        let quoteAdd = theme.wordRules ? max(0, spacing) * (doubles ? 2 : 1) : 0
                        let condensed = theme.wordRules && spacing < 0 ? spacing * (doubles ? 2 : 1) : 0
                        extra -= (em + _px((kind < 0 ? ideographGrid : grid) ?? 0) + quoteAdd + condensed) / 2
                    }
                }
                }
                _r2()
                }
                if theme.wordRules, RichTextTheme.wordWindowsPages, kind == -1, let following, ch.unicodeScalars.count == 1, following.unicodeScalars.count == 1,
                   let u = ch.unicodeScalars.first?.value, let v = following.unicodeScalars.first?.value, u >= 0x3040, u < 0x3100, v >= 0x3000, v < 0x3100,
                   let pair = Self.yuMinchoKerns[u << 16 | v],
                   (style(kind).debugLabel?.lowercased()).map({ $0.containsSubstring("yu mincho") || $0.containsSubstring("游明朝") }) == true,
                   let from = run.kerningFrom ?? named?.char.kerningFrom ?? _normalChar(document)?.kerningFrom, from > 0,
                   (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) >= from {
                    extra += pair * em
                }
                if yuOfMissingHangul, kind >= 0, let u0 = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1, u0 >= 0x20, u0 < 0x7F {
                    // (Word's Yu Gothic Latin in a paragraph whose Hangul-named face it lacks: 22de7d.)
                    let s = style(kind)
                    let bold = s.fontWeight == .bold
                    // (Word's print of 22de7d: a space between Latin neighbours is Yu Gothic's 0.2852 em, 2.87 pt at 10 pt; one beside a Hangul syllable stays 0.5 em, 5.04 pt.)
                    // (A leading space, or one beside another space, keeps 0.5 em too: Word's 3-space indent after a line break is 15.1 pt.)
                    let hangulBeside = ![i > text.startIndex ? Optional(text[text.index(before: i)]) : nil, following].allSatisfy { c in
                        guard let v = c?.unicodeScalars.first?.value else { return false }
                        return v > 0x20 && !((v >= 0xAC00 && v <= 0xD7A3) || (v >= 0x1100 && v <= 0x11FF) || (v >= 0x3130 && v <= 0x318F))
                    }
                    let a: Double? = u0 == 0x20 ? (aumsLatin || !hangulBeside ? 584.0 / 2048 : 0.5) : (u0 == 0x28 ? Optional(791.0 / 2048) : (bold ? Self.yuGothicBold : Self.yuGothicRegular)[u0].map { Double($0) / 2048 })
                    // (The size-compensated stand-in grows lowercase letters' style size; the advance is the nominal size's, the capitals' kind.)
                    if let a, let px = style(classed ? RichResolvedFace.characterClass("H") : 0).fontSize, px > 0.5 {
                        RuleTrace.hit("word-missing-hangul-face-latin-takes-yu-gothic-advances")
                        extra = a * px - _glyphWidth(s, ch) + (adjust[offset] ?? 0)
                    }
                }
                _sblk3()
                @inline(never) func _sblk4() {
                if heldSpaces.contains(offset) {
                    flush(i)
                    // (A held space of a run that names its own Latin face is that face's, not stretched by the Indic scale: the probe sets it so.)
                    latinNoScale = kind >= 0 && indic != nil && run.fontFamily != nil
                    let s = style(kind)
                    latinNoScale = false
                    if theme.wordRules, RichTextTheme.wordWindowsPages, !document.underlinesTrailingSpaces, windowsCounted.contains(offset) {
                        // (Counted under Word for Windows' rule for a paragraph's
                        // closing spaces that open underlined
                        // (`_underlinedClosingCounted`): held to the word before
                        // them, the run as wide as it reaches past half the
                        // line, and not underlined.)
                        let width = _glyphWidth(s, " ") + extra
                        if windowsShare == nil {
                            let whole = width * Double(windowsCounted.count)
                            // (No more than lets the word before them stand on a
                            // line of its own whole: Word sets it there however
                            // far the spaces reach, where the engine would part
                            // a word wider than the line.)
                            let units = Array(p.text.utf16)
                            var word = 0.0, k = offset - 1
                            while k >= 0, units[k] != 0x20, units[k] < 0x2E80, let u = Unicode.Scalar(units[k]) {
                                word += _glyphWidth(s, Character(u))
                                k -= 1
                            }
                            let reach = min(whole - textWidth / 2, textWidth - word - _px(0.5))
                            windowsShare = whole > 0 ? max(0, reach) / whole : 0
                        }
                        var plain = s.copyWith(decoration: TextDecoration.none)
                        plain = plain.copyWith(letterSpacing: (s.letterSpacing ?? 0) + width * (windowsShare ?? 0) - _glyphWidth(s, "\u{2007}"))
                        spans.append(TextSpan(text: "\u{2007}", style: plain))
                    } else if theme.wordRules, document.underlinesTrailingSpaces, run.underline {
                        // (An underlined one under `w:ulTrailSpace` as a figure
                        // space of the space's width: the engine hangs a run of
                        // no-break spaces past the margin as it does plain ones,
                        // where Word wraps it.)
                        spans.append(TextSpan(text: "\u{2007}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + _glyphWidth(s, " ") - _glyphWidth(s, "\u{2007}"))))
                    } else if theme.wordRules, RichTextTheme.wordWindowsPages, Self._afterBreakRun(Array(p.text.utf16), offset) {
                        // (A space run that opens a line after a manual break: a figure space of the space's width, which the engine keeps at a line start where a no-break space collapses.)
                        spans.append(TextSpan(text: "\u{00A0}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + _glyphWidth(s, " ") - _glyphWidth(s, "\u{00A0}"))))
                    } else {
                        spans.append(TextSpan(text: "\u{00A0}", style: extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s))
                    }
                    start = after
                    afterHeld = true
                    heldKind = kind
                } else if theme.wordRules, let u = ch.unicodeScalars.first?.value,
                          [0x2000, 0x2001, 0x2004, 0x2006, 0x2008, 0x2009, 0x200A, 0x205F].contains(u) {
                    // (Word does not part a line at these spaces — lab `spaces`, in a body
                    // paragraph and a fixed cell alike: only U+2002, U+2003, U+2005, U+3000, the
                    // space and the zero-width space are places to break; the others are held
                    // like a no-break space, of their own width.)
                    flush(i)
                    let s = style(kind)
                    spans.append(TextSpan(text: "\u{00A0}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + _glyphWidth(s, ch) - _glyphWidth(s, "\u{00A0}"))))
                    start = after
                } else if theme.wordRules, let u = ch.unicodeScalars.first?.value, u >= 0xE000, u <= 0xF8FF,
                          let w = latinFace?.missingGlyphAdvance {
                    // (A private-use character no face has is the run's
                    // face's missing-glyph box, blank: bug59058's formulas
                    // hold U+E037/E038 from an HTML converter, 10.11pt
                    // each at 13pt in Word's print — Times' .notdef, 0.7778
                    // em — where a fallback drew a glyph near twice that
                    // and pushed every formula past the line.)
                    flush(i)
                    let s = style(kind)
                    // (A no-break space: the box is no place to part a line.)
                    spans.append(TextSpan(text: String(ch), style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + w * em - _glyphWidth(s, ch))))
                    start = after
                } else if theme.wordRules, !ea, let u = ch.unicodeScalars.first?.value, u >= 0x25A0, u <= 0x25FF,
                          (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily)?.lowercased() == "times new roman" {
                    // (A geometric shape in a Times New Roman run is that
                    // face's — Word's Times New Roman has "○", the stand-in
                    // has not; where Word's Latin face lacks it, Word falls
                    // back to YaHei as ours does, zh-454e2e29's "○" and "△",
                    // and the platform's fallback, a CJK face, made the line
                    // its own: zh-cec9d337's 22pt "○" cells on an 18pt grid
                    // are two pitches in Word's print, 36pt, and ours 37.8
                    // a row, the table's last row going over. Its line asks
                    // an em at most — off the grid. On it, the line is the
                    // Times line the grid snapped: lab `g44` in zh-cec9d337's
                    // package (Word 16, 2026-10-18), a row of these at 14pt
                    // is its 28.3pt "at least", at 18 and 22pt two pitches,
                    // 36.5, where ours, held to the em after the grid had
                    // snapped it, stood 28.25 at every size.)
                    flush(i)
                    let s = style(kind)
                    let height = pitch != nil && s.height != nil ? s.height : min(s.height ?? 1, 1.0)
                    spans.append(TextSpan(text: String(ch), style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra, height: height)))
                    start = after
                } else if theme.wordRules, let u = ch.unicodeScalars.first?.value,
                          (u >= 0x1D400 && u <= 0x1D7FF) || (u > 0x7F && latinFace?.setsMath == true && !ea) {
                    // (A mathematical letter, which no shipped face has,
                    // comes from the platform's math face — STIX Two Math
                    // on a Mac, 0.762 above and 0.238 below with a quarter
                    // em of leading — whose own split of the run's height
                    // set bug59058's formula lines 16.4pt apart where
                    // Word's, in Cambria Math, are 15.2. At four fifths of
                    // the run's height it sits inside the line the text
                    // makes; its glyphs stand on the same baseline.)
                    flush(i)
                    let s = style(kind)
                    spans.append(TextSpan(text: String(ch), style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra, height: (s.height ?? 1) * 0.6)))
                    start = after
                } else if ea, theme.wordRules, let u = ch.unicodeScalars.first?.value,
                          [0x25B2, 0x25B3, 0x25BC, 0x25BD, 0x2605, 0x2606].contains(u),
                          let symbols = theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                            ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)
                              .flatMap({ face in face.symbolsInBold || !(run.bold || (named?.char.bold ?? false) && !run.off.contains(.bold)) ? face.symbolFamily : nil }) {
                    // (A triangle or star in a face Word lacks is SimSun's,
                    // and so is its line — circles and squares are YaHei's
                    // own in Word's prints, zh-7dc3afad's ○ and □: lab `tr2`, zh-6cd1befe's "▲" in
                    // 12pt 仿宋_GB2312 on a 15.6pt grid takes one pitch in
                    // Word's print, where YaHei's line took two and every
                    // row of its task table stood 5pt tall.)
                    flush(i)
                    var r = run
                    r.eastAsiaFontFamily = symbols
                    let s = theme.textStyle(for: r, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            eastAsian: true, gridPitch: pitch)
                    spans.append(TextSpan(text: String(ch), style: extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s))
                    start = after
                } else if ea, theme.wordRules, (style(kind).fontWeight == .bold || theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.otherAdvances?[0x2160] == nil), let cjk = Self._cjkFaceFamily, let u = ch.unicodeScalars.first?.value, (0x2160 ... 0x217F).contains(u) || u == 0x25C8 {
                    // (A Roman numeral in East Asian text is the CJK face's,
                    // an em wide: zh-78729cf9's "（Ⅰ级）、重大（Ⅱ级）" in a
                    // hinted 仿宋_GB2312 run is YaHei's in Word's print, each
                    // numeral a full cell. The Latin stand-in has none, and
                    // the fallback found DejaVu's, 0.34 to 0.73 em: the line
                    // took a character more than Word's, three times.)
                    flush(i)
                    let s = style(kind)
                    var numeral = (extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s).copyWith(fontFamily: cjk)
                    #if os(Linux)
                    // (Linux's CJK face may be absent, and the glyph then
                    // the fallback's, 4.7pt where Word's print has the
                    // 仿宋_GB2312 numeral a full 16: zh-94f12659's "（Ⅰ级）"
                    // kept "故：" on a line Word wrapped. Pad to the cell.)
                    numeral = numeral.copyWith(letterSpacing: (numeral.letterSpacing ?? 0) + max(0, em - _glyphWidth(numeral, ch)))
                    #endif
                    spans.append(TextSpan(text: String(ch), style: numeral))
                    start = after
                } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, ((0x2010 ... 0x2027).contains(u) || (0x2030 ... 0x205E).contains(u)), u != 0x2011, latinFace?.isEastAsian != true, !run.formBox,
                          // (General Punctuation only, not the invisible format marks U+2028-202F and U+205F-206F (the engine's own word joiner U+2060 is one): Word's prints draw math and enclosed symbols (⌈ ① in 0d8cbc, 27083953) in Cambria Math, and U+2011 as a plain hyphen, not in the East Asian face; a form check box is a drawn box. A mark the run's Latin face lacks, by that face's cmap (Self._latinSymbolCmap, from the Windows Word box); a face not in the table keeps only ※.)
                          Self._latinFaceLacks(run.fontFamily ?? named?.char.fontFamily ?? "", u) ?? (u == 0x203B),
                          let cjk = Self._cjkFaceFamily {
                    // (The reference mark ※ in a run whose Latin face lacks it is the East Asian
                    // face's in Word's print, a full cell: jpn-z21601833-463426's Cambria italic
                    // "※ ..." paragraphs draw it in MS Mincho, 12pt, where our fallback gave
                    // 10.1 and its line stood about 1pt short.)
                    flush(i)
                    let s = style(kind)
                    var mark = (extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s).copyWith(fontFamily: cjk)
                    mark = mark.copyWith(letterSpacing: (mark.letterSpacing ?? 0) + max(0, em - _glyphWidth(mark, ch)))
                    // (A line holding it is MS Mincho's: 1.2969 em, split 0.859 / 0.141 as the face's own ascent and descent, in the 463426 print.)
                    if devanagariStyles["eaMark"] == nil {
                        devanagariStyles["eaMark"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: 0.859 * 1.2969, descent: 0.141 * 1.2969)
                    }
                    if let joiner = devanagariStyles["eaMark"] ?? nil {
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        inserts.append(offset)
                    }
                    spans.append(TextSpan(text: String(ch), style: mark))
                    start = after
                } else if ea, theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{203B}", let cjk = Self._cjkFaceFamily,
                          (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? "").lowercased().containsSubstring("meiryo")
                              || (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? "").containsSubstring("メイリオ") {
                    // (The reference mark ※ in a Meiryo run is Meiryo's own, an em wide, as the ☆ and the fullwidth digit beside it:
                    // dx2 934bd3e5's superscript "※１" is 7.0pt apiece in Word's print, where our DejaVu fallback gave 7.9
                    // for the mark and its lines broke a character early.)
                    flush(i)
                    let s = style(kind)
                    let mark = (extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s).copyWith(fontFamily: cjk)
                    spans.append(TextSpan(text: String(ch), style: mark.copyWith(letterSpacing: (mark.letterSpacing ?? 0) + max(0, (mark.fontSize ?? em) - _glyphWidth(mark, ch)))))
                    start = after
                } else if ea, theme.wordRules, ch == "\u{02D9}" {
                    // (A dot above in East Asian text is a full cell: the
                    // Bopomofo tone mark of Taiwan's faces, 標楷體's among
                    // them, an em wide in Word's print as zh-ab34d9cb's "˙"
                    // bullets are, 14pt apiece where the stand-in's Latin
                    // fallback gave 4.7 and each such line took a character
                    // more than Word's.)
                    flush(i)
                    let s = style(kind)
                    let width = _glyphWidth(s, ch)
                    spans.append(TextSpan(text: String(ch), style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + max(0, em - width))))
                    start = after
                } else if ea, theme.wordRules, let cjk = Self._cjkSymbolFamily, Self._cjkSymbols.contains(ch) {
                    // (A dash or an ellipsis in East Asian text is the
                    // CJK face's glyph, with its metrics: the Latin
                    // stand-in the East Asian style is built on has one
                    // too, and its ascent and descent split the em
                    // otherwise, so a line with it grew — zh-90e0cea8's
                    // header "DB 37/T 4497—2022" stood 1.1pt taller than
                    // Word's, and its pages' text that much lower.)
                    flush(i)
                    let s = style(kind)
                    spans.append(TextSpan(text: String(ch), style: (extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s).copyWith(fontFamily: cjk)))
                    start = after
                } else if extra != 0 {
                    flush(i)
                    // (A space the fit cut out of its run is set at the size the run's other spaces take: a Windows Latin face's own, not the Indic stand-in's, 4% wider. The fit loop counts 3.33 pt and the engine set 3.6, so a squeeze of 0.59 pt delivered 0.31 and 1116b68d's last word never fitted.)
                    var s: TextStyle
                    if ch == " ", kind >= 0, indic != nil, run.fontFamily != nil, theme.wordRules, RichTextTheme.wordWindowsPages,
                       p.text.unicodeScalars.contains(where: { $0.value >= 0x905 && $0.value <= 0x939 }) {
                        latinNoScale = true
                        s = style(kind)
                        latinNoScale = false
                    } else {
                        s = style(kind)
                    }
                    // (A space the fit gives to is set at Kokila's own width as every other space of the run is: split out of its run it would take
                    // the stand-in's, narrower, and the engine would find room the fit loop never counted. f0001d05 line 3.)
                    if ch == " ", kind >= 0, indic?.face == "kokila", kokilaLatin, let px = s.fontSize, px > 0.5, Self._indicLines["kokila"] != nil {
                        s = _kokilaLatinStyle(" ", base: s, px: px)
                    } else if ch == " ", kind >= 0, indic?.face == "shonar bangla", let px = s.fontSize, px > 0.5 {
                        // (Shonar Bangla's own space, 0.2065 em, for a space the fit cut out of its run.)
                        let authored = (run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
                        s = _indicSpaceStyle(base: s, spaceEm: 0.2065, unit: authored)
                    } else if ch == " ", kind >= 0, let face = indic?.face, face != "kokila",
                              let spaceEm = (face == "vrinda" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? 0.3125 : Self._indicSpace[face],
                              let px = s.fontSize, px > 0.5 {
                        // (The same for the faces whose space is their own, Mangal, Vrinda, Utsaah: one path, `_indicSpaceStyle`.)
                        let authored = Self._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: face == "mangal" && theme.wordRules && RichTextTheme.wordWindowsPages) * theme.pixelsPerPoint * scale
                        // (A space a justified line cut out of an Arial run drawn in Mangal only because the document's first Devanagari run names it keeps Arial's 0.278 em.)
                        let arialSpace = face == "mangal" && document.devanagariFirstRunMangal && (run.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial"
                        s = _indicSpaceStyle(base: s, spaceEm: arialSpace ? 0.2778 : spaceEm, unit: face == "mangal" ? authored : px)
                    }
                    if theme.wordRules, ch == "\u{00A0}" {
                        // (A no-break space's width on a word joiner after
                        // it: the engine sets no spacing on the space
                        // itself — zh-17749c13's "第十三条  受理…", 宋体
                        // no-break spaces an em apiece in Word's print, came
                        // out at the stand-in's 0.29 em with the em's
                        // spacing on them.)
                        spans.append(TextSpan(text: "\u{00A0}", style: s))
                        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(kind).copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra)))
                        inserts.append(offset + 1)
                    } else if theme.wordRules, ea, ch == "\u{2013}" {
                        // (So too an East Asian dash the East Asian face
                        // lacks, drawn by the glyph fallback: its own
                        // spacing came out only before a space — lab `ds`,
                        // PMingLiU's em-wide "–" stood 6.67 before "基",
                        // 12.0 before " ".)
                        spans.append(TextSpan(text: String(ch), style: s))
                        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(kind).copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra)))
                        inserts.append(offset + 1)
                    } else {
                        // (The engine spaces every glyph, so a Thai letter
                        // drawn with its marks as several takes its share
                        // on each: Cordia's "คำ" is three glyphs, and the
                        // 0.5pt it wanted made zh-6a4fc013's every "คำ"
                        // 1.5 wider; "คำถามที่ 4 ：" ran a point long and
                        // sent its question to the next line.)
                        var spacing = (s.letterSpacing ?? 0) + extra
                        // (And any character past ASCII the face draws in
                        // pieces: on the Mac the fallback for zh-d97c5474's
                        // Cambria Greek sets "ή", "ό" as a letter and an
                        // accent, and each took Cambria's width correction
                        // twice — its lines 1.7% short, a word more each.)
                        if theme.wordRules, extra != 0, let u = ch.unicodeScalars.first?.value,
                           (u >= 0x0E00 && u < 0x0E80 && ch.unicodeScalars.count > 1) || (u >= 0x80 && !(0x0E00 ..< 0x0E80).contains(u)) {
                            spacing /= Double(_glyphCount(s, ch))
                        }
                        spans.append(contentsOf: capped(text[i ..< after], run, s.copyWith(letterSpacing: spacing)))
                    }
                    start = after
                }
                }
                _sblk4()
                offset += ch.utf16.count
                i = after
            }
            flush(text.endIndex)
            if spaceBeforeDanda, let k = current ?? Optional(0) { spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(k))); inserts.append(base + text.utf16.count) }
            return spans
        }
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
            var spans = styled(p.text[...], p.runs[0].style)
            // (A right-to-left paragraph of one plain run is the
            // left-to-right stretch whole: see the embeddings below.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.rightToLeft, !p.runs[0].style.rightToLeft, !(named?.char.rightToLeft ?? false) {
                let look = theme.textStyle(for: p.runs[0].style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                           gridPitch: pitch, scriptHidden: true)
                spans = [TextSpan(text: "\u{202A}", style: look)] + spans + [TextSpan(text: "\u{202C}", style: look)]
                return (TextSpan(children: spans), [], [0, p.text.utf16.count])
            }
            if spans.count == 1 { return (spans[0], [], inserts) }
            return (TextSpan(children: spans), [], inserts)
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
                let family = String(xml[r.upperBound...].prefix { $0 != "\"" })
                if !family.isEmpty, !p.text.unicodeScalars.contains(where: { Self.isEastAsian(Character($0), hinted: true) }) {
                    // (Its face's own ascent, not a line's: the line's carries the spacing multiple.)
                    let textFace = firstLook.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily
                    let size = _px(firstLook.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * fontScale
                    if let numberBase = theme.faceResolver?(family, false)?.baseline, let textBase = theme.faceResolver?(textFace, false)?.baseline,
                       (numberBase - textBase) * size > 0.5 {
                        RuleTrace.hit("word-number-face-taller-above-the-baseline-lifts-the-first-line")
                        rise = numberBase * size
                    }
                }
            }
            let style = theme.textStyle(for: leadChar, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
            children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
            inline.append((nil, PlaceholderDimensions(size: Size(lead, 0.01), alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: 0.01)))
            // (A box sets no line height of its own: the level's face
            // reaches the line through a zero-width space in it, one
            // more character before the text.)
            if symbolLevel {
                var markStyle = style
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
                    let above = max(split.0 * size, base / pt * size)
                    markStyle = style.copyWith(ascentOverride: above, descentOverride: split.1 * size, height: (above + split.1 * size) / size, leadingDistribution: .even)
                }
                // (A Wingdings bullet over Latin text at a line multiple: Word's print stands the first line on the BULLET's ascent
                // and leaves under it what the text's own line has under ITS baseline, the multiple's extra included. 11pt Calibri at
                // 1.15 under a 16pt bold Wingdings bullet: items 19.35pt apart, where the bullet's whole line at the multiple was 20.4
                // (dx2 it df984aa4).)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil,
                   p.style.lineSpacing > 1.001, leadChar.fontFamily?.lowercased() == "wingdings", let px = style.fontSize, px > 0.5,
                   !p.style.rightToLeft, !p.text.unicodeScalars.contains(where: { $0.value >= 0x590 }) {
                    let probe = TextPainter(text: TextSpan(text: "x", style: theme.textStyle(for: firstLook, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)), textDirection: .ltr)
                    probe.layout(minWidth: 0, maxWidth: 100000)
                    let m = probe.computeLineMetrics().first
                    probe.dispose()
                    if let m {
                        let multiple = p.style.lineSpacing
                        let single = m.height / multiple
                        let own = m.baseline / multiple
                        let up = px * 1841.0 / 2048
                        if up > own + 0.01 {
                            let down = single - own + m.height - single
                            RuleTrace.hit("word-wingdings-bullet-stands-the-first-line-on-its-ascent")
                            markStyle = style.copyWith(ascentOverride: up, descentOverride: down, height: (up + down) / px)
                        }
                    }
                }
                children.append(TextSpan(text: "\u{200B}", style: markStyle))
                inserts.append(0)
            } else if let rise {
                // (The number's height above the line, as a box on the
                // baseline that reaches no lower: see `_risesForNumber`.)
                children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
                inline.append((nil, PlaceholderDimensions(size: Size(0, rise), alignment: PlaceholderAlignment.baseline,
                                                          baseline: TextBaseline.alphabetic, baselineOffset: rise)))
                inserts.append(0)
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
        @inline(never) func _sblk6() {
        for run in p.runs where run.length > 0 {
            let a = utf16.index(utf16.startIndex, offsetBy: pos)
            let b = utf16.index(a, offsetBy: run.length)
            pos += run.length
            if embeds, run.style.inlineImage == nil {
                let plain = !(run.style.rightToLeft || (named?.char.rightToLeft ?? false))
                if plain != isolated {
                    let look = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                               gridPitch: pitch, scriptHidden: true)
                    children.append(TextSpan(text: plain ? "\u{202A}" : "\u{202C}", style: look))
                    inserts.append(pos - run.length)
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
                // (A floating object takes no room in the line.)
                if theme.wordRules, let float = image.float, !float.takesRoom { w = 0; h = 0 }
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
                let alignment = centred && middle == nil ? PlaceholderAlignment.middle : PlaceholderAlignment.baseline
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
                        inserts.append(at)
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
                children.append(RichImageSpan(alignment: alignment, baseline: TextBaseline.alphabetic, style: style))
                inline.append((image, PlaceholderDimensions(size: size, alignment: alignment, baseline: TextBaseline.alphabetic,
                                                             baselineOffset: (hung ?? eqOffset ?? middle.map { size.height / 2 + _px($0) }
                                                                ?? (fittedBaseline ?? image.baseline).map { min(size.height, _px($0)) } ?? size.height)
                                                                // (Raised or lowered as its run's `w:position` says: Word
                                                                // sets a MathType object that far under the baseline
                                                                // — tdf119200's equations, lowered 2 to 4pt.)
                                                                + (theme.wordRules && image.float == nil ? _px(run.style.raised ?? named?.char.raised ?? 0) : 0))))
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
                    inserts.append(pos)
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
                inserts.append(pos - run.length)
                var hidden = run.style
                hidden.hidden = true
                children.append(contentsOf: styled(p.text[a ..< b], hidden, at: pos - run.length, next: b < utf16.endIndex ? p.text[b] : nil))
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
                        children.append(contentsOf: styled(p.text[start ..< idx], run.style, at: pos - run.length + utf16.distance(from: a, to: start), next: p.text[idx]))
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
                    children.append(contentsOf: styled(p.text[idx ..< after], hidden, at: at, next: after < p.text.endIndex ? p.text[after] : nil))
                    children.append(TextSpan(text: "\u{200B}", style: style))
                    inserts.append(at + 1)
                    children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
                    inline.append((box, PlaceholderDimensions(size: Size(_px(size * boxAdvance), _px(size * 0.936)), alignment: PlaceholderAlignment.baseline,
                                                              baseline: TextBaseline.alphabetic, baselineOffset: _px(size * 0.84))))
                    inserts.append(at + 1)
                    start = after
                }
                if start < b {
                    children.append(contentsOf: styled(p.text[start ..< b], run.style, at: pos - run.length + utf16.distance(from: a, to: start), next: b < utf16.endIndex ? p.text[b] : nil))
                }
                continue
            }
            let runStart = pos - run.length
            children.append(contentsOf: styled(p.text[a ..< b], run.style, at: runStart, next: b < utf16.endIndex ? p.text[b] : nil))
            // (The half share after a ruby's base: a word joiner that wide.)
            if let tail = rubyTails[pos], tail > 0, run.style.ruby != nil {
                rubyTails[pos] = nil
                let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            gridPitch: pitch, scriptHidden: true)
                children.append(TextSpan(text: "\u{2060}", style: style.copyWith(letterSpacing: tail)))
                inserts.append(pos)
            }
        }
        }
        _sblk6()
        if isolated, let last = p.runs.last {
            let look = theme.textStyle(for: last.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                       gridPitch: pitch, scriptHidden: true)
            children.append(TextSpan(text: "\u{202C}", style: look))
            inserts.append(p.text.utf16.count)
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
            inserts.append(p.text.utf16.count)
        }
        return (TextSpan(children: children), inline, inserts)
    }

    /// The stretches of paragraph `p` that carry one ruby (UTF-16
    /// offsets), with the first run's look.
    @inline(__always) func gridPitchIsNil(_ pitch: Double?) -> Bool { pitch == nil }

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
        guard size > 0.5, Double(p.text.utf16.count) * _px(size) <= textWidth else { return 0 }
        return theme.rubyLine(for: first.style, in: p.style, named: named, eastAsian: true, gridPitch: pitch)?.raise ?? 0
    }

    /// A ruby's own look: the base's face at the ruby's size.
    func _rubyStyle(_ g: (from: Int, to: Int, ruby: RubyText, style: CharStyle), _ p: RichParagraph, named: RichNamedStyle?,
                            _ document: RichDocument) -> TextStyle {
        var look = g.style
        look.ruby = nil
        look.letterSpacing = nil
        look.fontSize = g.ruby.size > 0 ? g.ruby.size : (g.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) / 2
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
            }
            let tp = TextPainter(text: TextSpan(text: g.ruby.text, style: style), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: Double.infinity)
            let raise = _px(g.ruby.raise > 0 ? g.ruby.raise : (g.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) / 2)
            // (On a line grid the base text was moved with the ruby line: `rubyLine`.)
            let moved = NativeParagraphBuilder.supportsBaselineShift
                ? theme.rubyLine(for: g.style, in: p.style, named: named, eastAsian: true, gridPitch: _grid(index, document).pitch)?.raise ?? 0 : 0
            if let index, _verticalBody(index) {
                _paintUprightRuby(g.ruby.text, style, x: x, step: baseWidth > rubyWidth ? (baseWidth - rubyWidth) / count : 0,
                                  centre: (first.top + first.bottom) / 2 - raise - moved * _px(1), origin: origin, canvas)
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
            if chars.contains(where: { Self.isEastAsian($0, hinted: hinted) }) { ea = true } else { latin = true }
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
    /// An empty paragraph of a Tamil document whose mark asks for Arial Unicode MS (a face Windows lacks) is a line of Mangal,
    /// 1.680 em, in Word's print: a347c3b3's empty marks step 18.5 pt at 11 pt, against the 12.65 of the Latin stand-in. A bold
    /// mark stays on Nirmala UI's line (14.6).
    @inline(never)
    func _tamilEmptyMarkJoiner(_ mark: CharStyle, named: RichNamedStyle?, _ p: RichParagraph, _ document: RichDocument,
                               look: TextStyle, pitch: Double?, scale: Double) -> TextStyle? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages,
              document.defaultLangXML?.containsSubstring("ta-IN") == true,
              (mark.complexFontFamily ?? named?.char.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms",
              let metrics = Self._indicLines[(mark.bold || (named?.char.bold ?? false)) ? "nirmala ui" : "mangal"] else { return nil }
        RuleTrace.hit("word-tamil-empty-mark-is-a-line-of-mangal")
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
    func _tamilMarkedLinesExtra(_ i: Int, _ p: RichParagraph, _ document: RichDocument, _ painter: TextPainter) -> Double {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, !p.text.isEmpty else { return 0 }
        // (Devanagari in Arial Unicode MS, whose font-table entry is the Japanese charset: the same, 0.36 em with the 1.079 of line 259;
        // lab aums2 B and H: 30.0 and 30.2 pt against 26.4, once per paragraph however many lines hold marks.)
        let tamil = document.defaultLangXML?.containsSubstring("ta-IN") == true && p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) })
        let devanagari = !tamil && document.fontCharsets["arial unicode ms"] == "80" && p.text.unicodeScalars.contains(where: { $0.value >= 0x905 && $0.value <= 0x939 })
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
        // (Word lab a347gap A: a one-line marked paragraph followed by an empty one adds nothing, 18.4 pt line to line; the paragraph's last line is not counted.)
        if tamil, !p.text.isEmpty {
            let lastStart = painter.getLineBoundary(TextPosition(offset: max(0, p.text.utf16.count - 1) + lead)).start
            if lastStart == painter.getLineBoundary(TextPosition(offset: lead)).start { starts.remove(lastStart) }  // one-line paragraphs only (a multi-line one keeps its last line's extra: a347c3b3)
        }
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
        let base = _px(whole.ascent), full = _px(whole.ascent + whole.descent)
        let probe = TextPainter(text: TextSpan(text: "\u{200B}", style: style), textDirection: .ltr)
        probe.layout(minWidth: 0, maxWidth: .infinity)
        let textAscent = probe.computeDistanceToActualBaseline(TextBaseline.alphabetic)
        probe.dispose()
        let ascent = max(textAscent, base)
        let descent = max(pitch - textAscent, full - base)
        let n = (full / pitch - 0.002).rounded(.up)
        _ = (ascent, descent)
        guard n >= 2 else { return nil }
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
    func _clusterFitted(_ w: Substring, base: TextStyle, authored: Double, table: [String: Double], flatScale: Double, conjunctRatio: Double? = 0.85, block: UInt32 = 0x900) -> (style: TextStyle, flat: TextStyle)? {
        guard let split = MangalAdvances.split(w, table: table, conjunctRatio: conjunctRatio, block: block) else { return nil }
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
        return (flat.copyWith(letterSpacing: (flat.letterSpacing ?? 0) + (split.ems * authored + other - w0) / Double(n)), flat)
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
        return paragraphText.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && $0.properties.isAlphabetic })
    }
    @inline(never) static func _missingBengaliSpaceEm(_ face: String) -> Double? {
        let f = face.trimmingWhitespace().lowercased()
        return f == "solaimanlipi" || f == "nikosh" ? 0.5 : nil
    }
    /// A space at the face's own width (`spaceEm` of `unit`), as one letter spacing on the stand-in's space.
    @inline(never)
    func _indicSpaceStyle(base: TextStyle, spaceEm: Double, unit: Double) -> TextStyle {
        let t = TextPainter(text: TextSpan(text: " ", style: base.copyWith(letterSpacing: 0)), textDirection: .ltr)
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
    @inline(never) static func _afterBreakRun(_ u: [UInt16], _ offset: Int) -> Bool {
        var k = offset - 1
        while k >= 0, u[k] == 0x20 { k -= 1 }
        return k >= 0 && (u[k] == 0x0A || u[k] == 0x2028)
    }
}
