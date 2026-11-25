// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import Foundation

/// A slide's faces as PowerPoint stands in for them: the shared
/// stand-ins (`OfficeFonts.substitute`), except for a name they do not
/// know. The shared rule sets that in the Cambria clone (Word on a Mac's
/// way); PowerPoint, printing a face its machine lacks, used Calibri —
/// tdf168835's "Marianne", bug65228's "Graphik" and tdf119187's
/// "BentonSans" are Calibri in its prints. (Sweep 106: ten decks
/// nearer, n862510_4's "Segoe UI Light" — a weight we have no face for
/// either way — and tdf98603's Hebrew FrankRuehl a little further.)
enum SlideFonts {
    /// The free faces bundled for families decks name (Resources/fonts/
    /// README.md): the font itself (Poppins, Work Sans) or the nearest free
    /// design (Selawik for Segoe UI, Libre Franklin, TeX Gyre's Courier,
    /// Avant Garde and Palatino).
    static let freeFaces: [String: String] = [
        "poppins": "Poppins", "poppins light": "Poppins Light", "poppins medium": "Poppins Medium",
        "poppins semibold": "Poppins SemiBold", "poppins black": "Poppins Black",
        "work sans": "Work Sans", "work sans light": "Work Sans Light", "work sans medium": "Work Sans Medium",
        "segoe ui": "Selawik Doc", "segoe ui light": "Selawik Doc Light", "segoe ui semilight": "Selawik Doc Semilight",
        "segoe ui semibold": "Selawik Doc Semibold",
        // (Myriad Pro, which PowerPoint's Mac sets in Segoe UI: HowWeRefactor.)
        "myriad pro": "Selawik Doc",
        "franklin gothic book": "Libre Franklin", "franklin gothic medium": "Libre Franklin Medium",
        "courier new": "TeX Gyre Cursor", "courier": "TeX Gyre Cursor",
        "century gothic": "TeX Gyre Adventor",
        "palatino linotype": "TeX Gyre Pagella", "palatino": "TeX Gyre Pagella", "book antiqua": "TeX Gyre Pagella",
        // (Arial Black in Archivo Black, its widths Arial Black's and its
        // strokes as heavy, where Liberation Sans Bold's letters stood thin
        // and apart at Arial Black's widths: ThemeColorTransparency.)
        "arial black": "Archivo Black",
        // (Franklin Gothic Heavy, drawn by PowerPoint in the real face: Archivo Black is the closest heavy grotesque we carry, set at the face's own measured widths.)
        "franklin gothic heavy": "Archivo Black",
        // (Lucida Sans Unicode in Liberation Sans's regular and bold under a
        // name of their own, with no italic: PowerPoint slants the regular,
        // and so does the engine. aascu 5864's p34 quote, `i="1"`, is the
        // regular slanted in PowerPoint's print, where Liberation Sans
        // Italic's letters are another design.)
        "lucida sans unicode": "Starling Lucida Sans",
    ]

    /// Arial Black is drawn in Archivo Black, which is heavy without a bold.
    static let hasHeavyStandIn = true

    /// PowerPoint for Windows has no DejaVu Sans and prints it as Verdana
    /// (Matrix's theme face, tdf134862's runs: the print's face is Verdana);
    /// its metrics and widths are Verdana's.
    /// PowerPoint (Windows) sets an eaVert column in a CLOUD-delivered face as one sideways (turned) run, and in a face installed with
    /// Windows upright. Lab vface (2026-11-22, print box): sideways exactly MS Mincho, Batang, Gulim, Meiryo (cloud-only there); upright
    /// SimHei (its system copy wins over the cloud one), MingLiU, PMingLiU, JhengHei, YaHei, SimSun, DFKai-SB, Yu Gothic, Malgun, MS Gothic.
    /// The origin of each face is DATA measured on that box (cjk-vertical-features-20261122.tsv): it reflects that box, not Office.
    /// A face with no entry is taken as installed (upright). Metrics only, no font files.
    static let cloudOnlyFaces: Set<String> = [
        "ms mincho", "ｍｓ 明朝", "ms pmincho", "ｍｓ ｐ明朝", "batang", "바탕", "batangche", "바탕체", "gulim", "굴림", "gulimche", "굴림체",
        "meiryo", "meiryo ui", "メイリオ", "hg丸ゴシックm-pro", "hg丸ｺﾞｼｯｸm-pro", "hgmarugothicmpro",
    ]

    static func setsEastAsianVerticalSideways(_ family: String) -> Bool {
        cloudOnlyFaces.contains(family.trimmingWhitespace().lowercased())
    }

    /// An upright eaVert column's line in PowerPoint's print (lab vface): the glyph is centred in a column of (win ascent + win descent)
    /// plus 0.2 em, from the column's right edge, and stands (win ascent - 0.8 em) down from the column's top. Win metrics over em by face
    /// (vertical tables, cjk-line-20261122; Yu Gothic's descent from its measured column).
    static func uprightColumn(_ family: String, bold: Bool) -> (ascent: Double, line: Double)? {
        // (Its places are wider than an em by the spacing set after each ideograph, half of which leads the glyph: taken off the along shift.)
        uprightMetrics(family, bold: bold).map { ($0.ascent - ($0.step - 1) / 2, $0.line) }
    }

    /// An upright column's face: win ascent and line, and the vmtx advance of an ideograph, all in em (vertical tables cjk-vertical-20261122).
    // (Yu Gothic: the line is win ascent + descent 2636/2048 plus 0.08 em, the one column printed in lab vface: 24.63 pt from the box left at 20 pt, 0.8 pt left of the bare sum; fitted, no table value explains it.)
    static func uprightMetrics(_ family: String, bold: Bool) -> (ascent: Double, line: Double, step: Double)? {
        switch windowsName(family) {
        case "microsoft jhenghei", "微軟正黑體": return (2203.0 / 2048, 2724.0 / 2048, 1)
        case "microsoft yahei", "微软雅黑": return (2167.0 / 2048, 2703.0 / 2048, 1)
        case "malgun gothic", "맑은 고딕": return (2229.0 / 2048, 2724.0 / 2048, 2176.0 / 2048)
        case "yu gothic", "游ゴシック": return ((bold ? 2024.0 : 2017.0) / 2048, 2636.0 / 2048, 1)
        case "simsun", "宋体", "simhei", "黑体", "nsimsun", "ms gothic", "ｍｓ ゴシック", "ms pgothic", "ｍｓ ｐゴシック", "ms ui gothic", "ｍｓ ｕｉ ゴシック": return (220.0 / 256, 1, 1)
        case "mingliu", "細明體", "pmingliu", "新細明體", "dfkai-sb", "標楷體": return (820.0 / 1024, 1, 1)
        default: return nil
        }
    }

    /// Win ascent over em of the face an upright digit is set in (lab vdig3: the digit's baseline stands this far below its slot's start).
    /// The CJK faces' come from `uprightMetrics`; the Latin ones are OS/2 winAscent / 2048 (latin-line-20261122).
    static func uprightDigitAscent(_ family: String, bold: Bool) -> Double? {
        if let m = uprightMetrics(family, bold: bold) { return m.ascent - (m.step - 1) / 2 }
        switch windowsName(family) {
        case "segoe ui": return 2210.0 / 2048
        case "times new roman": return 1825.0 / 2048
        case "verdana": return 2059.0 / 2048
        case "arial": return 1854.0 / 2048
        case "calibri": return 1950.0 / 2048
        case "cambria": return 1946.0 / 2048
        default: return nil
        }
    }

    /// A face whose upright column steps by each character's own vmtx advance (`SlideVerticalAdvances`).
    static func proportionalUprightFace(_ family: String) -> Bool {
        ["ms pgothic", "ｍｓ ｐゴシック"].contains(windowsName(family))
    }

    static func windowsName(_ family: String) -> String {
        let n = family.trimmingWhitespace().lowercased()
        if missingRoman.contains(n), OfficeFonts.installed(family) == nil, embeddedFamily(family) == nil { return "palatino linotype" }
        // (Arial's PostScript name, "ArialMT" or "Arial MT", is Arial in the print: 5ddc3269 sets "Arial MT" 20pt at Arial's widths, where
        // ours drew Carlito and broke "intercambiar ideas y" a word early.)
        if (n == "arialmt" || n == "arial mt") && OfficeFonts.installed(family) == nil && embeddedFamily(family) == nil { return "arial" }
        // (A Japanese face PowerPoint for Windows lacks (HGｺﾞｼｯｸM, HG教科書体, HGP創英角ﾎﾟｯﾌﾟ体, 游明朝, ヒラギノ角ゴ, ＤＨＰ平成ゴシックW5,
        // BIZ UDP明朝): its print draws it in Yu Gothic, regular or bold, whatever the name. Property: a name with kana, or an HG/游 name with
        // ideographs, that our East Asian width table does not know. The theme's "本文"/"見出し" aliases are not this.)
        if OfficeFonts.installed(family) == nil, embeddedFamily(family) == nil, isMissingJapaneseName(n) { return "yu gothic" }
        // (A Chinese face the print's machine lacks (隶书/LiSu, 幼圆, 方正*, 華康*, 思源*...): its print draws it in Microsoft YaHei, quotes and all,
        // e9180c676efa p13's 20 pt title line and p11's 14 pt column, whose “ ” are YaHei's full em, not a narrow stand-in's. Property: a name
        // of ideographs only (no kana, no hangul, no Latin face word) that is not a face Windows or Office ships, and not installed or embedded.)
        if OfficeFonts.installed(family) == nil, embeddedFamily(family) == nil, simplifiedDeck, isMissingChineseName(n) { return "microsoft yahei" }
        return n == "dejavu sans" && OfficeFonts.installed(family) == nil ? "verdana" : n
    }

    /// Whether the deck's Chinese runs are Simplified (lang zh-CN/zh-SG outnumber zh-TW/HK/MO): PowerPoint's fallback for a face it lacks follows the run's language.
    nonisolated(unsafe) private static var simplifiedDeck = false
    static func noteSimplifiedChinese(_ v: Bool) { simplifiedDeck = v }

    private static let windowsIdeographFaces: Set<String> = ["hgp創英角ｺﾞｼｯｸub", "hgp明朝e", "hgs創英角ｺﾞｼｯｸub", "hgs明朝e", "hg丸ｺﾞｼｯｸm-pro", "hg創英角ｺﾞｼｯｸub", "hg明朝e", "ud デジタル 教科書体 n-b", "ud デジタル 教科書体 nk-b", "ud デジタル 教科書体 np-b", "仿宋", "华文中宋", "华文仿宋", "华文新魏", "华文楷体", "华文琥珀", "华文细黑", "华文行楷", "宋体", "微軟正黑體", "微軟正黑體 light", "微软雅黑", "微软雅黑 light", "新宋体", "新細明體", "新細明體-extb", "楷体", "標楷體", "游ゴシック", "游ゴシック light", "游ゴシック medium", "游明朝", "游明朝 demibold", "等线", "等线 light", "細明體", "細明體-extb", "細明體_hkscs", "細明體_hkscs-extb", "細明體_mscs", "細明體_mscs-extb", "黑体", "ｍｓ 明朝", "ｍｓ ｐ明朝"]

    static func isMissingChineseName(_ n: String) -> Bool {
        var ideograph = false
        for u in n.unicodeScalars {
            let v = u.value
            if (v >= 0x3041 && v <= 0x30FF) || (v >= 0x31F0 && v <= 0x31FF) || (v >= 0xFF66 && v <= 0xFF9F) || (v >= 0xAC00 && v <= 0xD7A3) { return false }
            if v >= 0x4E00 && v <= 0x9FFF { ideograph = true }
        }
        guard ideograph, SlideEastAsianWidths.lookup(n) == nil else { return false }
        // The faces the print's machine has installed (measured: installed-font-aliases-20261123.tsv, every name with ideographs, localized names included).
        return !windowsIdeographFaces.contains(n)
    }

    /// A face name (ideographs in it, any script) the print's machine has under that name, by the measured table of installed names.
    static func printBoxHasIdeographName(_ n: String) -> Bool {
        SlideEastAsianWidths.lookup(n) != nil || windowsIdeographFaces.contains(n)
    }

    static func isMissingJapaneseName(_ n: String) -> Bool {
        guard !n.containsSubstring("本文"), !n.containsSubstring("見出し") else { return false }
        // (HGS明朝E is on the print machine: lab num2 prints HGSMinchoE, its line standing at the MS Mincho cut 1.03 em down, not Yu Gothic's .92.)
        guard !windowsIdeographFaces.contains(n) else { return false }
        var kana = false, ideograph = false
        for u in n.unicodeScalars {
            let v = u.value
            if (v >= 0x3041 && v <= 0x30FF) || (v >= 0x31F0 && v <= 0x31FF) || (v >= 0xFF66 && v <= 0xFF9F) { kana = true }
            else if (v >= 0x4E00 && v <= 0x9FFF) { ideograph = true }
        }
        guard kana || (ideograph && (n.hasPrefix("hg") || n.hasPrefix("游"))) else { return false }
        return SlideEastAsianWidths.lookup(n) == nil
    }

    /// Roman faces the deck names with PANOSE 02 05 (a Garamond/Caslon-type serif), pitchFamily roman and charset 0 that PowerPoint's machine
    /// lacks: it prints them in Palatino Linotype (58246e12's "Adobe Caslon Pro" runs are PalatinoLinotype in the print; the Word rule is
    /// word-missing-roman-panose-0205-is-palatino). A face Office ships (Bernard MT Condensed) is not one.
    nonisolated(unsafe) private static var missingRoman: Set<String> = []
    static func noteMissingRoman(_ names: Set<String>) {
        missingRoman = Set(names.map { $0.trimmingWhitespace().lowercased() }.filter { !OfficeFonts.wordMacFamilies.contains($0) && freeFaces[$0] == nil && $0 != "palatino linotype" })
    }

    /// The deck's own fonts (`ppt/fonts/*.fntdata`), by typeface name in
    /// lower case to the family they are loaded as. PowerPoint draws an
    /// embedded face where the machine has none of that name.
    nonisolated(unsafe) private static var embedded: [String: String] = [:]

    static func noteEmbedded(_ faces: [String: String]) {
        embedded = Dictionary(faces.map { ($0.key.trimmingWhitespace().lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }
    /// Each embedded face's Windows descent share (OS/2 winDescent over winAscent + winDescent), by lower-case typeface name. PowerPoint
    /// sets a line's baseline by it (e01f56c5361e p5: Reem Kufi, hhea 1100/400 but win 1000/500, "01" in a bottom-anchored box stood 4.7 pt low).
    nonisolated(unsafe) private static var embeddedWinShares: [String: Double] = [:]
    static func noteEmbeddedWindowsShares(_ shares: [String: Double]) {
        embeddedWinShares = Dictionary(shares.map { ($0.key.trimmingWhitespace().lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }
    static func isEmbedded(_ family: String) -> Bool { embeddedFamily(family) != nil }
    /// Whether `family` is a face the deck embeds and that has the ASCII digits: a run of digits alone, tagged with a right-to-left
    /// language, is then set in it (cc66a30f's slide-number field, fa-IR, B Nazanin embedded: 8.5 pt wide in PowerPoint's print, on
    /// the baseline of the Persian footer beside it, where Georgia's 8 was 10.7 wide and 3 pt low).
    static func embeddedFaceKeepsDigits(_ family: String) -> Bool {
        guard let registered = embeddedFamily(family) else { return false }
        return OfficeFonts.registeredFaceHasDigits(registered)
    }
    private static func embeddedFamily(_ family: String) -> String? {
        return embedded.isEmpty ? nil : embedded[family.trimmingWhitespace().lowercased()]
    }

    /// A Hangul-named gothic face Windows lacks (나눔바른고딕OTF): PowerPoint draws it in Malgun Gothic, at Malgun's widths.
    /// (The Windows Korean faces, and the serif, headline and brush kinds, are not this: Batang, Gulim, Dotum have their own.)
    static func missingKoreanGothic(_ family: String) -> Bool {
        let n = family.trimmingWhitespace()
        guard embeddedFamily(family) == nil, n.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }), OfficeFonts.installed(family) == nil else { return false }
        let own = ["맑은 고딕", "바탕", "바탕체", "돋움", "돋움체", "굴림", "굴림체", "궁서", "궁서체", "나눔고딕"]
        if own.contains(n) { return false }
        return !["궁서", "신명", "필기", "손글씨", "펜"].contains(where: { n.containsSubstring($0) })
    }

    /// The symbols Malgun Gothic sets an em wide (and draws itself): East Asian characters, so a Korean run's are drawn from the East Asian stand-in.
    static let malgunEmSymbols: [UInt32] = Array(0x2460...0x246F) + [0x24D2, 0x2500, 0x2592, 0x25A0, 0x25A1, 0x25B2, 0x25B3, 0x25BD, 0x25C6, 0x25C7, 0x25CB, 0x25CE, 0x25CF, 0x2606, 0x261E, 0x2664,
                                                                    0xFF02, 0xFF07, 0xFF08, 0xFF09, 0xFF0A, 0xFF1C, 0xFF1E, 0xFF21, 0xFF22, 0xFF3A, 0xFF5E]
    static let malgunEmSymbolSet = Set(malgunEmSymbols)

    static func koreanOwnFace(_ family: String) -> Bool {
        ["굴림", "굴림체", "바탕", "바탕체", "돋움", "돋움체", "궁서", "궁서체", "gulim", "gulimche", "batang", "batangche", "dotum", "dotumche", "gungsuh", "gungsuhche"].contains(windowsName(family))
    }

    static func resolve(_ family: String) -> String {
        // (The machine's own face, where it has it and the user takes it:
        // `OfficeFonts.installed`.)
        if let own = OfficeFonts.installed(family) { return own }
        if let mine = embeddedFamily(family) { return mine }
        // (The bundled CJK face by its own name, for the East Asian symbols a Korean run's Latin stand-in would draw small.)
        if let cjk = OfficeFonts.cjkFallback.first, family == cjk { return cjk }
        if windowsName(family) == "palatino linotype", family.trimmingWhitespace().lowercased() != "palatino linotype" { return resolve("Palatino Linotype") }
        if windowsName(family) == "arial" && family.trimmingWhitespace().lowercased() != "arial" { return resolve("Arial") }
        if let free = freeFaces[family.trimmingWhitespace().lowercased()] { return free }
        // (Century Schoolbook is a serif face: PowerPoint's print of es/66517aeb sets its text in a serif, at the face's own widths
        // from the table below; the generic stand-in is a sans, which draws the same widths as wide-spaced sans.)
        if windowsName(family) == "century schoolbook" { return OfficeFonts.serif }
        // (Rockwell, a slab serif: PowerPoint's print of es/eb013aed sets its body in a serif; the sans stand-in drew it as sans.)
        if windowsName(family) == "rockwell" { return OfficeFonts.serif }
        let face = OfficeFonts.substitute(family)
        guard face == OfficeFonts.cambria else { return face }
        let n = family.trimmingWhitespace().lowercased()
        guard !n.hasPrefix("cambria"), n != "caladea" else { return face }
        return OfficeFonts.calibri
    }

    /// The face a slide's run is set in where its widths are not the
    /// stand-in's: Lucida Sans Unicode, drawn in Liberation Sans, at its
    /// own widths — 9% wider (GeomLec1's lines wrapped a word late).
    /// Its bold and italic are made from the regular, as wide.
    private static let eastAsianLock = RegistryLock()
    nonisolated(unsafe) private static var eastAsianMade: [String: RichResolvedFace] = [:]
    static func face(_ family: String?, _ eastAsian: Bool) -> RichResolvedFace? {
        // (None of a stand-in's widths for the machine's own face.)
        guard let family, OfficeFonts.installed(family) == nil, embeddedFamily(family) == nil else { return nil }
        // (An East Asian query is answered for Malgun Gothic only, whose Hangul em the layout asks for by it.)
        // (A Traditional Chinese face PowerPoint emboldens itself: a bold ideograph steps 0.983 of the regular's, ideographs being a full em; lab vk.)
        if eastAsian, ["dfkai-sb", "標楷體", "mingliu", "pmingliu", "新細明體", "細明體"].contains(windowsName(family)) {
            var f = RichResolvedFace(family: resolve(family)); f.boldIdeographScale = SlideFontWidths.syntheticBoldAdvance; return f
        }
        guard !eastAsian || windowsName(family) == "malgun gothic" || windowsName(family) == "맑은 고딕" || missingKoreanGothic(family) || koreanOwnFace(family) else { return nil }
        if let cuts = SlideEastAsianWidths.lookup(windowsName(family)) ?? (missingKoreanGothic(family) ? SlideEastAsianWidths.malgun : nil) {
            // (An East Asian face at its own measured widths, Latin and the rest past ASCII: PowerPoint sets it by itself, not by a stand-in's.)
            // (Built once per family: parsing its advance table for every run made a 560-slide deck take over ten minutes.)
            eastAsianLock.lock(); defer { eastAsianLock.unlock() }
            if let made = eastAsianMade[family] { return made }
            var face = RichResolvedFace(family: resolve(family))
            let regular = SlideEastAsianWidths.parse(cuts.regular.other)
            // (A face with no real bold is emboldened by PowerPoint itself: the regular outline filled and stroked, each advance
            // 0.9845 of the regular's; Windows labs clbold (Calibri Light) and Gulim.)
            let k = SlideFontWidths.syntheticBoldAdvance
            let bold = cuts.bold.map { SlideEastAsianWidths.parse($0.other) } ?? regular.mapValues { $0 * k }
            face.advances = cuts.regular.ascii
            face.boldAdvances = cuts.bold?.ascii ?? cuts.regular.ascii.map { $0 * k }
            face.otherAdvances = regular
            face.boldOtherAdvances = bold
            // (The face's own measured advances for Latin-1, General Punctuation and Arrows, a full em ones too: a character PowerPoint finds in the
            // face it draws there at that advance, not at a stand-in's. 44a86430 p10's ¹ in HG Maru Gothic is 0.5 em, the stand-in's 0.333.
            // A value already measured from a print stays.)
            if let lat = SlideEastAsianLatin.lookup(windowsName(family)) {
                let kk = SlideFontWidths.syntheticBoldAdvance
                let r = SlideEastAsianWidths.parse(lat.regular)
                let b = lat.bold.map { SlideEastAsianWidths.parse($0) }
                for (c, w) in r where face.otherAdvances?[c] == nil { face.otherAdvances?[c] = w; face.boldOtherAdvances?[c] = b?[c] ?? w * kk }
            }
            // (Gulim sets a bold Hangul syllable at 0.98 em, 18.60 to 18.65 of 19 pt over 150 syllables: lab ko-squeeze2 slide 10, the narrowest box keeps "자기계발" on the line.)
            if let k = SlideEastAsianKerns.lookup(windowsName(family)) { face.kerns = k.regular; face.boldKerns = k.bold ?? k.regular; face.kernsOutsideWord = true }
            if koreanOwnFace(family) { face.otherAdvances?[0xAC00] = 1.0; face.boldOtherAdvances?[0xAC00] = cuts.bold == nil ? 0.98 : 1.0 }
            if koreanOwnFace(family), cuts.bold == nil { for u in UInt32(0xAC00) ... 0xD7A3 { face.boldOtherAdvances?[u] = 0.98 } }
            // (Malgun Gothic's Hangul is an em, which the table of advances that are not one does not hold.)
            if cuts.regular.ascii == SlideEastAsianWidths.malgun.regular.ascii { for u in UInt32(0xAC00) ... 0xD7A3 { face.otherAdvances?[u] = 1.0; face.boldOtherAdvances?[u] = 1.0 } }
            // (Malgun Gothic sets its circled numbers, geometric shapes, box line and fullwidth forms an em wide: every one that PowerPoint
            // for Windows printed in it across the Korean pilot decks, ① to ⑮, ⓒ, ─ ▒ ■ □ ▲ △ ▽ ◆ ◇ ○ ◎ ● ☆ ☞ ♤ and the fullwidth ＂ ＇ （ ） ＊ ＜ ＞ Ａ Ｂ Ｚ ～, 1.000 em
            // at 18 pt (ko-ca2dc787 p7's "□ " steps 24.3, where the Latin stand-in's □ stepped 17.7 and the line held a syllable more).)
            if cuts.regular.ascii == SlideEastAsianWidths.malgun.regular.ascii {
                let em = Self.malgunEmSymbols
                for c in em where face.otherAdvances?[c] == nil { face.otherAdvances?[c] = 1.0; face.boldOtherAdvances?[c] = 1.0 }
            }
            // (The Japanese faces do the same: PowerPoint's prints of Meiryo, Meiryo UI, Yu Gothic, MS Gothic and HG Maru Gothic set ① ② ⇒ → ○ ■ ◆ ▶ 1.000 em
            // across the Japanese pilot decks. 81d28d42 p32's "▶︎女性従業員本人に加え、" breaks after 加え、, where the DejaVu ▶ (0.77 em) took 上 on the line.)
            let jn = windowsName(family)
            if jn.hasPrefix("meiryo") || jn == "メイリオ" || jn.hasPrefix("yu gothic") || jn.hasPrefix("游ゴシック") || jn.hasPrefix("ms ") || jn.hasPrefix("ｍｓ")
                || jn.hasPrefix("hg") {
                let em: [UInt32] = Array(0x2460...0x2473) + [0x2192, 0x21D2, 0x25A0, 0x25A1, 0x25B2, 0x25B3, 0x25B6, 0x25BC, 0x25BD, 0x25C0, 0x25C6, 0x25C7, 0x25CB, 0x25CE, 0x25CF,
                                                              0x2605, 0x2606, 0xFE0E, 0xFE0F].map { $0 }
                for c in em where face.otherAdvances?[c] == nil { let w: Double = c >= 0xFE0E ? 0 : 1; face.otherAdvances?[c] = w; face.boldOtherAdvances?[c] = w }
            }
            // (MS Gothic and MS Mincho, the fixed-width faces, set the curly double quotes full width, an em; the proportional P faces keep them narrow, ja a91e3e82's “思い”: lab hang3 slide 7's ” after a kanji in MS Gothic broke "課|程”" where
            // the Latin stand-in's narrow ” kept it on the line.)
            let japaneseMS = [SlideEastAsianWidths.msGothic, SlideEastAsianWidths.msMincho, SlideEastAsianWidths.simSun]
            if japaneseMS.contains(where: { $0.regular.ascii == cuts.regular.ascii }) {
                for c: UInt32 in [0x201C, 0x201D] where face.otherAdvances?[c] == nil { face.otherAdvances?[c] = 1.0; face.boldOtherAdvances?[c] = 1.0 }
            }
            // (Rule A, lab sbold: a Japanese face with no bold cut is emboldened by one design unit per advance, in every run language; the
            // regular's table above stays the bold's here, the unit and the eighth of a point come per size in the layout.)
            if cuts.bold == nil, jn.hasPrefix("ms ") || jn.hasPrefix("ｍｓ") || jn.hasPrefix("hg") {
                let upem: Double = jn.hasPrefix("hg") ? 2048 : 256
                                face.boldUnitsPerEm = upem
                face.boldAdvances = cuts.regular.ascii
                face.boldOtherAdvances = face.otherAdvances
            }
            if let it = SlideEastAsianWidths.lookupItalic(windowsName(family)) {
                face.italicAdvances = it.regular.ascii
                face.boldItalicAdvances = it.bold?.ascii ?? it.regular.ascii
                face.italicOtherAdvances = SlideEastAsianWidths.parse(it.regular.other)
                face.boldItalicOtherAdvances = it.bold.map { SlideEastAsianWidths.parse($0.other) } ?? face.italicOtherAdvances
            }
            // (Rockwell and Tw Cen MT kern, as PowerPoint prints them, by the pairs of the font's own kern table.)
            face.hintedAdvances = ["arial", "rockwell", "tw cen mt", "trebuchet ms"].contains(windowsName(family))
            if let k = SlideLatinKerns.lookup(windowsName(family)) { face.kerns = k.regular; face.boldKerns = k.bold ?? k.regular; face.kernsOutsideWord = true }
            if let k = SlideLatinItalicKerns.lookup(windowsName(family)) { face.italicKerns = k.italic; face.boldItalicKerns = k.boldItalic ?? k.italic }
            // (A Ming, Song or Mincho name draws its ideographs in a serif, as Word's print does: PowerPoint's print of 新細明體 is a serif.
            // The Kai face, a brush hand, is nearer the serif than the sans.)
            if let serif = OfficeFonts.balloonIdeographFace(family) ?? (["dfkai-sb", "標楷體", "dfkai"].contains(windowsName(family)) ? OfficeFonts.kaiFamily : nil) { face.fallback = [serif] }
            eastAsianMade[family] = face
            return face
        }
        switch windowsName(family) {
        case "traditional arabic", "sakkal majalla", "majalla ui", "simplified arabic", "arabic typesetting":
            if let face = OfficeFonts.slidesArabicFace(family) { return face }
            return RichResolvedFace(family: resolve(family))
        case "th sarabunpsk":
            // (TH SarabunPSK, a face PowerPoint's machine has and ours lacks: its Thai and Latin advances from the Word prints of the same face
            // (OfficeFonts.thSarabunPSKThai), where the Noto Sans Thai stand-in is a third wider and wrapped every line early; th-cb034815ae.)
            var face = RichResolvedFace(family: resolve(family))
            var regular = OfficeFonts.cordiaNewAdvances, bold = OfficeFonts.cordiaNewBoldAdvances
            for (cp, w) in OfficeFonts.thSarabunPSKLatin where cp >= 0x20 && cp < 0x100 && Int(cp) - 0x20 < regular.count { regular[Int(cp) - 0x20] = w }
            for (cp, w) in OfficeFonts.thSarabunPSKBoldLatin where cp >= 0x20 && cp < 0x100 && Int(cp) - 0x20 < bold.count { bold[Int(cp) - 0x20] = w }
            face.advances = regular
            face.boldAdvances = bold
            face.otherAdvances = OfficeFonts.thSarabunPSKThai
            face.boldOtherAdvances = OfficeFonts.thSarabunPSKBoldThai
            face.classScales = [1, 1, 1, 1, 0.82]
            return face
        case "lucida sans unicode":
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.lucidaSansUnicodeAdvances
            face.boldAdvances = OfficeFonts.lucidaSansUnicodeAdvances
            face.otherAdvances = OfficeFonts.lucidaSansUnicodeOtherAdvances
            face.boldOtherAdvances = OfficeFonts.lucidaSansUnicodeOtherAdvances
            return face
        case "aptos":
            // (Word's measured Aptos widths are unkerned and PowerPoint kerns Aptos, so the GPOS pairs go with them.)
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.aptosAdvances
            face.boldAdvances = OfficeFonts.aptosBoldAdvances
            face.otherAdvances = OfficeFonts.aptosOtherAdvances
            face.boldOtherAdvances = OfficeFonts.aptosBoldOtherAdvances
            face.kerns = SlideAptosKerns.regular
            face.boldKerns = SlideAptosKerns.bold
            face.kernsOutsideWord = true
            return face
        case "verdana":
            // (Verdana in DejaVu Sans, at Verdana's widths: its space is
            // 0.35 em to DejaVu's 0.32, and pptx2svg's words stood closer
            // together than PowerPoint's.)
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.verdanaAdvances
            face.boldAdvances = OfficeFonts.verdanaBoldAdvances
            face.otherAdvances = OfficeFonts.verdanaOtherAdvances
            face.boldOtherAdvances = OfficeFonts.verdanaBoldOtherAdvances
            return face
        case "segoe ui", "segoe ui light", "segoe ui semilight", "tahoma", "trebuchet ms", "franklin gothic book",
             "franklin gothic medium", "century gothic", "gill sans mt", "candara", "palatino linotype", "corbel":
            // (Windows' own widths, `SlideFontWidths`: the bold where the
            // face has one, else the stand-in's bold.)
            let n = family.trimmingWhitespace().lowercased()
            let tables: [String: ([Double], [Double]?)] = [
                "segoe ui": (SlideFontWidths.segoeUI, SlideFontWidths.segoeUIBold),
                "segoe ui light": (SlideFontWidths.segoeUILight, nil),
                "segoe ui semilight": (SlideFontWidths.segoeUISemilight, nil),
                "tahoma": (SlideFontWidths.tahoma, SlideFontWidths.tahomaBold),
                "trebuchet ms": (SlideFontWidths.trebuchet, SlideFontWidths.trebuchetBold),
                "franklin gothic book": (SlideFontWidths.franklinGothicBook, nil),
                "franklin gothic medium": (SlideFontWidths.franklinGothicMedium, nil),
                "century gothic": (SlideFontWidths.centuryGothic, SlideFontWidths.centuryGothicBold),
                "gill sans mt": (SlideFontWidths.gillSans, SlideFontWidths.gillSansBold),
                "candara": (SlideFontWidths.candara, SlideFontWidths.candaraBold),
                "corbel": (OfficeFonts.corbelAdvances, OfficeFonts.corbelBoldAdvances),
                "palatino linotype": (SlideFontWidths.palatino, SlideFontWidths.palatinoBold),
            ]
            guard let t = tables[n] else { return nil }
            var face = RichResolvedFace(family: resolve(family))
            face.advances = t.0
            face.boldAdvances = t.1
            // (Trebuchet MS kerns as PowerPoint prints it, by the pairs of the font's own tables, measured on Windows.)
            // (head.flags bit 4 of the Windows fonts, read 2026-11-22: set in Calibri, Calibri Light, Arial, Rockwell, Tw Cen MT, Trebuchet MS; clear in the cloud Aptos and Open Sans.)
            face.hintedAdvances = ["arial", "rockwell", "tw cen mt", "trebuchet ms"].contains(n)
            if let k = SlideLatinKerns.lookup(n) { face.kerns = k.regular; face.boldKerns = k.bold ?? k.regular; face.kernsOutsideWord = true }
            if let k = SlideLatinItalicKerns.lookup(n) { face.italicKerns = k.italic; face.boldItalicKerns = k.boldItalic ?? k.italic }
            if n == "corbel" {
                // (Corbel's own widths, measured on Windows, as the Word path sets it: a ja deck's title in it fits "FEATURES OF ESCAPE PANIC"
                // on one line at 40.5 pt bold caps in PowerPoint's print, the stand-in's wider letters did not.)
                face.otherAdvances = OfficeFonts.corbelOtherAdvances
                face.boldOtherAdvances = OfficeFonts.corbelBoldOtherAdvances
                face.italicAdvances = OfficeFonts.corbelItalicAdvances
                face.boldItalicAdvances = OfficeFonts.corbelBoldItalicAdvances
            }
            if n == "tahoma" {
                // (Tahoma's own Arabic, as the Word path sets it.)
                face.joinedAdvances = WindowsArabicAdvances.tahoma
                face.boldJoinedAdvances = WindowsArabicAdvances.tahomaBold
            }
            return face
        case "open sans":
            // (A cloud face PowerPoint prints from its own copy, not installed on the Windows box: Open Sans's measured widths, the same
            // tables Word uses, set in the sans stand-in; PowerPoint's prints of the decks that name it draw "Open Sans" and "Open Sans,Bold".)
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.openSansAdvances
            face.boldAdvances = OfficeFonts.openSansBoldAdvances
            face.otherAdvances = OfficeFonts.openSansOtherAdvances
            face.boldOtherAdvances = OfficeFonts.openSansBoldOtherAdvances
            return face
        case "open sans":
            // (A cloud face PowerPoint prints from its own copy, not installed on the Windows box: Open Sans's measured widths, the same
            // tables Word uses, set in the sans stand-in; PowerPoint's prints of the decks that name it draw "Open Sans" and "Open Sans,Bold".)
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.openSansAdvances
            face.boldAdvances = OfficeFonts.openSansBoldAdvances
            face.otherAdvances = OfficeFonts.openSansOtherAdvances
            face.boldOtherAdvances = OfficeFonts.openSansBoldOtherAdvances
            return face
        case "nunito sans", "nunito sans light":
            // (Nunito Sans's own widths. Plain Nunito is not here: a deck that does not carry it is printed by PowerPoint in
            // Calibri (pilot 617866bf's Nunito Medium box held 'Actúo siempre con'); a deck that carries it is measured by
            // the embedded face itself.)
            let light = family.lowercased().hasSuffix("light")
            var face = RichResolvedFace(family: resolve(family))
            let black = family.lowercased().hasSuffix("black")
            face.advances = light ? OfficeFonts.nunitoSansLightAdvances : black ? OfficeFonts.nunitoSansBoldAdvances : OfficeFonts.nunitoSansAdvances
            face.boldAdvances = OfficeFonts.nunitoSansBoldAdvances
            face.otherAdvances = light ? OfficeFonts.nunitoSansLightOtherAdvances : black ? OfficeFonts.nunitoSansBoldOtherAdvances : OfficeFonts.nunitoSansOtherAdvances
            face.boldOtherAdvances = OfficeFonts.nunitoSansBoldOtherAdvances
            return face
        case "times new roman", "calibri":
            // (Hebrew at the face's own widths: tdf98603's title and quote
            // are a fifth narrower in PowerPoint's print than the stand-ins
            // set them, and broke a word early.)
            var face = RichResolvedFace(family: resolve(family))
            let hebrew = family.trimmingWhitespace().lowercased() == "calibri" ? SlideFontWidths.calibriHebrew : SlideFontWidths.timesHebrew
            face.otherAdvances = hebrew
            face.boldOtherAdvances = hebrew
            if family.trimmingWhitespace().lowercased() == "calibri" { face.hintedAdvances = true; face.kerns = SlideCalibriKerns.regular; face.boldKerns = SlideCalibriKerns.bold; face.kernsReplaceShaped = true
                if let k = SlideLatinItalicKerns.lookup("calibri") { face.italicKerns = k.italic; face.boldItalicKerns = k.boldItalic ?? k.italic }
                // (Calibri Italic's own advances, not Carlito Italic's, whose space and several letters run 0.04 pt narrower at 24 pt.)
                face.italicAdvances = SlideCalibriItalic.italicAscii; face.boldItalicAdvances = SlideCalibriItalic.boldItalicAscii
                face.italicOtherAdvances = hebrew.merging(SlideCalibriItalic.italicOther) { a, _ in a }
                face.boldItalicOtherAdvances = hebrew.merging(SlideCalibriItalic.boldItalicOther) { a, _ in a } }
            if family.trimmingWhitespace().lowercased() == "calibri" {
                // (A sans run face draws its Arabic in the sans Arabic face, regular and bold cuts, not DejaVu Sans with a faux bold.)
                face.fallback = ["Carlito", "Noto Sans Arabic", "Noto Naskh Arabic", OfficeFonts.emojiPictographs, "DejaVu Sans"]
            }
            if family.trimmingWhitespace().lowercased() == "times new roman" {
                face.joinedAdvances = WindowsArabicAdvances.times
                face.boldJoinedAdvances = WindowsArabicAdvances.timesBold
                // (A serif run face draws its Arabic in a serif naskh: Noto Naskh Arabic stands in, not the sans DejaVu.)
                face.fallback = ["Liberation Serif", "Noto Naskh Arabic", OfficeFonts.emojiPictographs, "DejaVu Sans"]
                face.joinedHeight = 0.5   // (as Arial's: rtl 2185f496's lines stood 1.4 pt too far apart on the fallback's height)
            }
            return face
        case "arial":
            // (Arial's own Arabic advances, as the Word path sets it: rtl/8c48d77a's body lines, 27 pt, took the DejaVu Sans stand-in's
            // widths and broke two words early.)
            var face = RichResolvedFace(family: resolve(family))
            face.fallback = ["Liberation Sans", "Noto Sans Arabic", "Noto Naskh Arabic", OfficeFonts.emojiPictographs, "DejaVu Sans"]
            face.joinedAdvances = WindowsArabicAdvances.arial
            face.boldJoinedAdvances = WindowsArabicAdvances.arialBold
            // (PowerPoint's print sets Arabic in Arial on a 1.2 em line: rtl 8c48d77a 25 pt lines 27.0 apart at 90%, 24.0 at 80%, 27 pt 32.4;
            // e08da366 18 pt 21.6. The paragraph's own line is already that; Noto Sans Arabic's taller words raised it to 31.)
            face.joinedHeight = 0.5
            return face
        case "rockwell condensed":
            // (PowerPoint's print of 6e9fe27b sets it a third narrower than the Arial it was drawn in: lines ran a third over.)
            var face = RichResolvedFace(family: resolve(family))
            face.advances = SlideFontWidths.rockwellCondensed
            face.boldAdvances = SlideFontWidths.rockwellCondensedBold
            face.otherAdvances = SlideFontWidths.rockwellCondensedOther
            face.boldOtherAdvances = SlideFontWidths.rockwellCondensedBoldOther
            return face
        case "cambria math":
            // (Cambria Math's own advances, for the symbols Calibri lacks that a run falls back to it for: ℃ is 0.9043 em.)
            var face = RichResolvedFace(family: resolve(family))
            var t: [UInt32: Double] = [:]
            for (u, w) in OfficeFonts.cambriaMathScript where u >= 0xA0 { t[u] = Double(w.0) }
            face.otherAdvances = t
            face.boldOtherAdvances = t
            return face
        case "calibri light":
            // (Calibri Light has no bold: PowerPoint emboldens the regular outline and sets each glyph at 0.9845 of the Light
            // advance (clbold lab), not at Carlito Bold's widths, which are wider and wrapped 6d178027's 48 pt title a word early.)
            var face = RichResolvedFace(family: resolve(family))
            face.boldAdvances = SlideFontWidths.calibriLightBoldLatin
            face.fakeBoldFamily = OfficeFonts.carlitoNoBold
            face.otherAdvances = SlideFontWidths.calibriHebrew
            face.boldOtherAdvances = SlideFontWidths.calibriHebrew.merging(SlideFontWidths.calibriLightBoldOther) { a, _ in a }
            face.kerns = SlideCalibriKerns.light
            face.hintedAdvances = true
            face.kernsReplaceShaped = true
            face.italicAdvances = SlideCalibriItalic.lightItalicAscii
            face.boldItalicAdvances = SlideCalibriItalic.lightItalicAscii.map { $0 * 0.9845 }
            face.italicOtherAdvances = SlideFontWidths.calibriHebrew.merging(SlideCalibriItalic.lightItalicOther) { a, _ in a }
            face.boldItalicOtherAdvances = face.italicOtherAdvances?.mapValues { $0 * 0.9845 }
            return face
        case "arial black":
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.arialBlackAdvances
            face.boldAdvances = OfficeFonts.arialBlackAdvances
            // (Past ASCII too, at Arial Black's own measured advances: its accented capitals are the base letter's width, and the
            // stand-in's are wider; 4c5084ff's 20 pt caps heading with Á, Ç, Ã.)
            face.otherAdvances = OfficeFonts.arialBlackOtherAdvances
            face.boldOtherAdvances = OfficeFonts.arialBlackOtherAdvances
            // (PowerPoint kerns Arial Black by the pairs of its own table.)
            face.kerns = SlideArialBlackKerns.regular
            face.boldKerns = SlideArialBlackKerns.regular
            face.kernsOutsideWord = true
            return face
        default:
            // (A face no one knows is Calibri in PowerPoint's print, its
            // Hebrew too: tdf98603's FrankRuehl quote, a fifth narrower
            // than Carlito's own Hebrew.)
            guard resolve(family) == OfficeFonts.calibri else { return nil }
            var face = RichResolvedFace(family: OfficeFonts.calibri)
            face.otherAdvances = SlideFontWidths.calibriHebrew
            face.boldOtherAdvances = SlideFontWidths.calibriHebrew
            // (Its Arabic is Arial's: PowerPoint's print of rtl/6f97f2ee sets the title, cs "PT Bold Heading" which the machine does not
            // have, in ArialMT at Arial's own Arabic advances.)
            face.joinedAdvances = WindowsArabicAdvances.arial
            face.boldJoinedAdvances = WindowsArabicAdvances.arialBold
            // (Drawn in the sans Arabic face, both cuts, not DejaVu Sans with a faux bold.)
            face.fallback = ["Carlito", "Noto Sans Arabic", "Noto Naskh Arabic", OfficeFonts.emojiPictographs, "DejaVu Sans"]
            return face
        }
    }

    /// Windows descent over ascent plus descent, by face (measured metrics): PowerPoint's first-line loss of a
    /// percent line spacing in a table cell is 0.3 - 1.2 x this, none below zero (lab tbl-rows3, 30 faces, within 0.002).
    static let arialDescentShare = 0.1897
    static func windowsDescentShare(_ family: String) -> Double? { descentShares[windowsName(family)] }
    private static let descentShares: [String: Double] = ["arial": 0.1897, "ｍｓ ｐゴシック": 36.0 / 256, "ｍｓ ゴシック": 36.0 / 256, "ｍｓ 明朝": 36.0 / 256, "ｍｓ ｐ明朝": 36.0 / 256, "consolas": 0.2143, "times new roman": 0.1953, "calibri": 0.2200, "calibri light": 0.2200, "cambria": 0.1895, "verdana": 0.1728, "tahoma": 0.1711, "segoe ui": 0.1887, "trebuchet ms": 0.1913, "courier new": 0.2651, "franklin gothic book": 0.1916, "palatino linotype": 0.2219, "gill sans mt": 0.1987, "candara": 0.2200, "georgia": 0.1930, "corbel": 0.2200, "constantia": 0.2200, "malgun gothic": 0.1817, "meiryo": 0.2933, "meiryo ui": 0.1653, "ms gothic": 0.1406, "ms pgothic": 0.1406, "ms mincho": 0.1406, "ms pmincho": 0.1406, "yu gothic": 0.2348, "microsoft yahei": 0.1983, "simsun": 0.1406, "lucida sans unicode": 0.2863, "comic sans ms": 0.2092, "impact": 0.1729, "garamond": 0.2339, "arial narrow": 0.1859]
    /// A face's Windows ascent and descent in ems (lab tbl-rows7: a table cell's fontAlgn t, ctr and b stand the glyph box, these two, in the 1.2 em line).
    static func windowsAscentDescent(_ family: String) -> (ascent: Double, descent: Double)? {
        switch windowsName(family) {
        case "arial": return (0.905, 0.212)
        case "times new roman": return (0.891, 0.216)
        case "calibri": return (1950.0 / 2048, 550.0 / 2048)
        case "malgun gothic", "맑은 고딕": return (2229.0 / 2048, 495.0 / 2048)
        case "meiryo": return (2171.0 / 2048, 901.0 / 2048)
        case "meiryo ui", "meiryo ui bold": return (2171.0 / 2048, 430.0 / 2048)
        case "yu gothic": return (2017.0 / 2048, 619.0 / 2048)
        case "ms gothic", "ms pgothic": return (220.0 / 256, 36.0 / 256)
        // (Lab mixrun, 35 pt lines of fontAlgn t, ctr and b: Book Antiqua 0.96 and 0.277, PMingLiU and DFKai-SB 0.803 and 0.231.)
        case "book antiqua": return (0.96, 0.277)
        case "pmingliu", "新細明體", "dfkai-sb", "標楷體": return (0.803, 0.231)
        default: return nil
        }
    }

    /// The share of the line below the baseline for a face we draw with
    /// a stand-in of other proportions — its Windows ascent and descent
    /// (Verdana 2059 and 430 of 2048, Tahoma 2049 and 423, Segoe UI 2210
    /// and 514, Lucida Sans Unicode 2246 and 901, Arial 1854 and 434,
    /// Times New Roman 1825 and 443). PowerPoint sets the
    /// baseline by them: the AES deck's Verdana stood 0.04 of its size
    /// high in DejaVu Sans's, HowWeRefactor's Segoe UI as much in its
    /// stand-in's, and GeomLec1's Lucida Sans Unicode 0.1 low.
    /// The single line, in ems, of a face drawn by a stand-in of another
    /// height (its Windows ascent, descent and gap): what a diagram's
    /// lines step at (`DeckController.naturalLines`). nil: the stand-in's
    /// own is the face's (Calibri in Carlito, the free faces themselves).
    static func ownNaturalHeight(_ family: String) -> Double? {
        guard OfficeFonts.installed(family) == nil else { return nil }
        switch windowsName(family) {
        case "courier new", "courier": return 2320.0 / 2048
        case "segoe ui", "segoe ui light", "segoe ui semilight", "segoe ui semibold": return 2724.0 / 2048
        case "franklin gothic book", "franklin gothic medium": return 2322.0 / 2048
        case "century gothic": return 2440.0 / 2048
        case "palatino linotype", "palatino": return 2763.0 / 2048
        case "verdana": return 2489.0 / 2048
        case "tahoma": return 2472.0 / 2048
        case "trebuchet ms": return 2378.0 / 2048
        case "gill sans mt": return 2375.0 / 2048
        case "candara": return 2500.0 / 2048   // (hhea 1484+564+452 = win 1950+550 = 2500 of 2048)
        case "lucida sans unicode": return 3147.0 / 2048
        default: return nil
        }
    }

    /// Faces whose single line is exactly 1.0 em (hhea = typo = win 1760 + 288 of 2048, no gap: every HG face; measured in
    /// /data/corpus-cache/metrics/cjk-line-20261122), where the flat 1.2 em would overstate it. ja f3a3058d2e's 18 pt lines on
    /// 11 pt in HGPGothicE: rows 2.6 pt under n x 18 + margins.
    static func exactSingleLineEm(_ family: String) -> Double? {
        let n = windowsName(family)
        let ms = ["ms gothic", "ｍｓ ゴシック", "ms pgothic", "ｍｓ ｐゴシック", "ms mincho", "ｍｓ 明朝", "ms pmincho", "ｍｓ ｐ明朝"].contains(n)
        return ms || n.hasPrefix("hgp") || n.hasPrefix("hgs") || n.hasPrefix("hgm") ? 1.0 : nil
    }

    /// The same by the face that draws it (what the layout knows a run
    /// by): a stand-in answers for the face it stands for.
    static func drawnNaturalHeight(_ drawn: String) -> Double? {
        switch drawn {
        case "TeX Gyre Cursor", OfficeFonts.mono: return 2320.0 / 2048
        case "Selawik Doc", "Selawik Doc Light", "Selawik Doc Semilight", "Selawik Doc Semibold": return 2724.0 / 2048
        case "Libre Franklin", "Libre Franklin Medium": return 2322.0 / 2048
        case "TeX Gyre Adventor": return 2440.0 / 2048
        case "TeX Gyre Pagella": return 2763.0 / 2048
        case OfficeFonts.verdana: return 2489.0 / 2048
        case "Starling Lucida Sans": return 3147.0 / 2048   // (GeomLec1's diagram: 33.3 pt apart at 24 pt, 90%)
        default: return nil
        }
    }

    /// A diagram's text in an East Asian face stands on Word's line, not the flat 1.2 em of a plain box (PowerPoint's prints
    /// of the SmartArt in ja b7d6faa9, bc6071ca, ff27a386, 5c820695 and en 2175d386, amd-opus puzzle 12): 1.3 of the face's
    /// win ascent and descent, the 0.3 split evenly above and below. Its height in ems and its share below the baseline.
    static func diagramEastAsianLine(_ family: String) -> (height: Double, share: Double)? {
        let n = windowsName(family)
        let units: Double, upem: Double, descent: Double
        switch n {
        case "meiryo ui": (units, upem, descent) = (2601, 2048, 430)
        case "meiryo", "メイリオ": (units, upem, descent) = (3072, 2048, 901)
        case "microsoft jhenghei", "微軟正黑體": (units, upem, descent) = (2724, 2048, 521)   // (zh c788f8818f12 p11: 18 pt lines at 90% stand 28 apart)
        case "microsoft yahei", "微软雅黑": (units, upem, descent) = (2703, 2048, 536)   // (zh c00f1ec0d573 p12: 12 pt lines at 90% stand 18.55 apart, 0.9 of 1.3 x (2167+536)/2048)
        case "ms gothic", "ｍｓ ゴシック", "ms pgothic", "ｍｓ ｐゴシック", "ms ui gothic", "ｍｓ ｕｉ ゴシック", "ms mincho", "ｍｓ 明朝", "ms pmincho", "ｍｓ ｐ明朝":
            (units, upem, descent) = (256, 256, n.containsSubstring("pgothic") || n.containsSubstring("ｐゴシック") ? 52 : 36)
        default:
            guard n.containsSubstring("dfkai") || n.containsSubstring("標楷") || n.containsSubstring("mingliu") || n.containsSubstring("細明體") else { return nil }   // (PMingLiU / MingLiU: 7c3069f9808a slide 8, 12 pt at 90% stands 14.1 apart = 0.9 x 1.306 em)
            (units, upem, descent) = (1024, 1024, 204)
        }
        return (1.3 * units / upem, (descent / units + 0.15) / 1.3)
    }

    static func isArabicLineFace(_ family: String) -> Bool {
        ["traditional arabic", "sakkal majalla", "majalla ui", "simplified arabic", "arabic typesetting"].contains(family.trimmingWhitespace().lowercased())
    }

    /// A sideways run in a turned frame (vert, eaVert's cloud faces): the column is the face's win ascent + descent plus 0.2 em split
    /// evenly, 0.1 em each side, so its baseline stands (win ascent + 0.1 em) from the column's edge on the 1.2 em line, not 1.2 em x the
    /// ascent share (lab vface, from the frame: MS Mincho 0.9585 em, Batang 0.952, Gulim 0.9515 against 0.959 and 0.958 here, ours was 1.031).
    static func sidewaysColumnShare(_ family: String) -> Double? {
        guard OfficeFonts.installed(family) == nil else { return nil }
        // The face's win ascent and descent (em); Batang and Gulim fill their em (win ascent + win descent = 1 em).
        let ad: (Double, Double)
        switch windowsName(family) {
        case "ms mincho", "ｍｓ 明朝", "ms pmincho", "ｍｓ ｐ明朝": ad = (220.0 / 256, 36.0 / 256)
        case "gulim", "굴림", "gulimche", "굴림체", "batang", "바탕", "batangche", "바탕체": ad = (879.0 / 1024, 145.0 / 1024)
        case "meiryo", "メイリオ": ad = (2171.0 / 2048, 901.0 / 2048)
        default: return nil
        }
        // One rule for every face: the glyph box (win ascent + win descent) is centred in the 1.2 em line, so the baseline
        // stands 0.6 em + (ascent - descent) / 2 from the column's edge. For a face that fills its em this is win ascent + 0.1 em.
        // (Lab vface, sideways baseline against the print: MS Mincho 0.03 pt, Batang 0.14, Gulim 0.15, Meiryo 0.05 at 20 pt.)
        return 1 - (0.6 + (ad.0 - ad.1) / 2) / 1.2
    }

    static func ownDescentShare(_ family: String) -> Double? {
        if let w = embeddedWinShares[family.trimmingWhitespace().lowercased()], embeddedFamily(family) != nil { return w }
        guard OfficeFonts.installed(family) == nil else { return nil }
        let n = windowsName(family)
        // (East Asian faces by PowerPoint's print, lab slides-cjk-lines: a line is 1.2 em at every face and size, its
        // baseline at 1.2 em x winAscent / (winAscent + winDescent): YaHei 2167+536 of 2048, Malgun 2229+495, SimSun and
        // MS Mincho/Gothic 220+36 of 256; Meiryo and Yu Gothic from their first baselines, .847 and .921 em at 18 pt.)
        switch n {
        case "microsoft yahei": return 536.0 / 2703
        case "candara": return 550.0 / 2500   // (win ascent 1950, descent 550)
        case "malgun gothic", "맑은 고딕": return 495.0 / 2724
        case "simsun", "宋体", "nsimsun", "ms mincho", "ｍｓ 明朝", "ms pmincho", "ｍｓ ｐ明朝": return 36.0 / 256
        case "ms pgothic", "ｍｓ ｐゴシック": return 52.0 / 256   // (text boxes: 5c820695 p1/p9/p11/p14 sit at 52, not the 36 of its glyph box; the table anchors take 36 from windowsAscentDescent)
        case "ms gothic", "ｍｓ ゴシック", "ms ui gothic", "ｍｓ ｕｉ ゴシック", "hgゴシックe", "hgｺﾞｼｯｸe", "hg gothic e", "hg丸ゴシックm-pro", "hg丸ｺﾞｼｯｸm-pro",
             "hgmarugothicmpro", "hg明朝e", "hg mincho e", "hgp明朝e", "hgp mincho e", "hgs明朝e", "hgs mincho e", "hgp創英角ゴシックub", "hgp創英角ｺﾞｼｯｸub", "hgpsoeikakugothicub": return 288.0 / 2048
        case "gulim", "굴림", "gulimche", "굴림체", "dotum", "돋움", "dotumche", "돋움체", "batang", "바탕", "batangche", "바탕체": return 145.0 / 1024
        case "nanumgothic", "나눔고딕": return 198.0 / 1083
        case "nunito", "nunito light", "nunito black": return 300.0 / 1377
        case "baskerville old face": return 531.0 / 2336
        case "hgpゴシックe", "hgpｺﾞｼｯｸe", "hgpgothice", "hgsゴシックe", "hgsｺﾞｼｯｸe", "hgsgothice", "hg創英角ゴシックub", "hg創英角ｺﾞｼｯｸub", "hgsoeikakugothicub",
             "hgs創英角ゴシックub", "hgs創英角ｺﾞｼｯｸub", "hgssoeikakugothicub": return 288.0 / 2048
        case "ud デジタル 教科書体 nk-b", "ud digi kyokasho nk-b", "ud デジタル 教科書体 np-b", "ud digi kyokasho np-b": return 567.0 / 2369
        case "microsoft jhenghei", "微軟正黑體": return 521.0 / 2724
        case "tw cen mt": return 477.0 / 2230
        // (Arabic faces, the same way from the span boxes of PowerPoint's print (rtl): Simplified Arabic 2416+979 of 2048 (eb7ab2c5: the first
        // baseline 34.2 pt below a 40 pt line's top, ours 38.9), Traditional Arabic 1.023+0.51 em, Sakkal Majalla .884+.319, Arabic Typesetting .701+.342.)
        case "simplified arabic": return 979.0 / 3395
        case "traditional arabic": return 0.51 / 1.533
        case "sakkal majalla", "majalla ui": return 1.0 - 0.7813 / 1.2   // (a flat 1.2 em line with the typo ascender+descender (1395, 653 of 2048) centred in it: baseline (1395 + (2457.6 - 2048) / 2) / 2048 = 0.7813 em; titles of eb7ab2c5/f355b7fc within 0.3 pt)
        case "arabic typesetting": return 1.0 - (1435.0 / 2048) / 1.2   // (first baseline 0.7007 em below the line top on a flat 1.2 em line: 8a5ae557 title 89.9 pt at 36 pt, ours was 3.7 low)
        case "noto sans": return 600.0 / 2789
        case "comic sans ms": return 597.0 / 2854
        case "gungsuh", "궁서", "gungsuhche", "궁서체": return 145.0 / 1024
        case "pmingliu", "新細明體", "mingliu", "細明體", "dfkai-sb", "標楷體", "kaiu": return 204.0 / 1024
        case "georgia": return 449.0 / 2327
        case "raleway", "raleway black", "raleway medium": return 234.0 / 1200
        case "rockwell": return 468.0 / 2405
        case "rockwell condensed": return 481.0 / 2408
        case "rockwell extra bold": return 468.0 / 2405
        case "tenorite": return 506.0 / 2458
        case "bierstadt": return 539.0 / 2341
        case "aptos display": return 563.0 / 2631
        case "nunito sans": return 327.0 / 1429
        case "franklin gothic book": return 445.0 / 2322
        case "montserrat": return 270.0 / 1379
        case "harlow solid italic", "harlow solid": return 795.0 / 2586
        case "modern love": return 1003.0 / 3358
        case "aharoni": return 518.0 / 2023
        case "lucida console": return 432.0 / 2048
        case "jokerman": return 729.0 / 3097
        case "chiller": return 625.0 / 2363
        case "segoe ui historic": return 514.0 / 2724
        case "agency fb": return 410.0 / 2299
        case "arial narrow": return 431.0 / 2319
        case "arial rounded mt bold": return 432.0 / 2370
        case "bahnschrift": return 422.0 / 2458
        case "berlin sans fb": return 416.0 / 2243
        case "berlin sans fb demi": return 419.0 / 2299
        case "bodoni mt": return 578.0 / 2456
        case "bodoni mt black": return 514.0 / 2392
        case "book antiqua": return 578.0 / 2545
        case "bradley hand itc": return 815.0 / 2554
        case "britannic bold": return 434.0 / 2269
        case "century schoolbook": return 442.0 / 2461
        case "constantia": return 550.0 / 2500
        case "cooper black": return 469.0 / 2349
        case "franklin gothic heavy": return 445.0 / 2322
        case "franklin gothic medium": return 445.0 / 2322
        case "garamond": return 539.0 / 2304
        case "impact": return 432.0 / 2498
        case "lucida calligraphy": return 666.0 / 2566
        case "lucida handwriting": return 666.0 / 2630
        case "open sans": return 600.0 / 2789
        case "palace script mt": return 496.0 / 1897
        case "roboto": return 512.0 / 2458
        case "stkaiti", "华文楷体": return 260.0 / 1120
        case "stxingkai", "华文行楷": return 289.0 / 1050
        case "stxinwei", "华文新魏": return 236.0 / 1017
        case "segoe script": return 1014.0 / 3244
        case "segoe ui symbol": return 514.0 / 2724
        case "showcard gothic": return 416.0 / 2535
        case "tw cen mt condensed extra bold": return 430.0 / 2218
        case "meiryo ui": return 430.0 / 2601
        case "yu gothic ui": return 514.0 / 2724
        case "yu gothic light", "游ゴシック light": return 610.0 / 2636
        case "yu gothic medium", "游ゴシック medium": return 608.0 / 2636
        case "meiryo", "メイリオ": return 1 - 0.847 / 1.2
        case "yu gothic", "游ゴシック", "adobe fan heiti std b", "ar pゴシック体m", "ar pゴシック体e", "ar pゴシック体l", "ar pゴシック体b", "ar pゴシック体h", "ar p丸ゴシック体m", "ar p丸ゴシック体e", "ar丸ゴシック体m", "ar丸ゴシック体e", "biz udpゴシック": return 1 - 0.921 / 1.2
        default: break
        }
        // (PowerPoint's print, lab verdana-ls: the foot of a Verdana line is 0.202 em at every size and spacing, of 1.2 em: not hhea's 430 of 2489.)
        if n == "verdana" { return 0.202 / 1.2 }
        if n.hasPrefix("tahoma") { return 423.0 / 2472 }
        if n.hasPrefix("segoe ui") { return 514.0 / 2724 }
        if n == "lucida sans unicode" { return 901.0 / 3147 }
        if n == "courier new" || n == "courier" { return 615.0 / 2320 }
        // (Helvetica by the Mac's, 1577 over and 471 under of 2048: slide-
        // sections' 36 pt titles stand a point higher in PowerPoint's
        // print than Liberation Sans's share set them.)
        if n == "helvetica" { return 471.0 / 2048 }
        // (Consolas by its own, 1884 over and 514 under, where Liberation
        // Mono's deeper share set clusterfuzz 4986's code 1 to 2 pt high.)
        if n == "consolas" { return 514.0 / 2398 }
        // (Poppins by its ascent and descent, its line gap not counted —
        // the engine puts half of it under the baseline; its descent is 0.35 of the 1.5 em with the gap, as PowerPoint prints it; Work Sans by its
        // Windows ascent and descent.)
        if n.hasPrefix("poppins") { return 0.35 / 1.5 }
        if n.hasPrefix("work sans") { return 0.343 / 1.448 }
        if n == "trebuchet ms" { return 455.0 / 2378 }
        if n.hasPrefix("franklin gothic") { return 445.0 / 2322 }
        if n == "century gothic" { return 451.0 / 2440 }
        if n == "gill sans mt" { return 472.0 / 2375 }
        if n == "palatino linotype" { return 613.0 / 2763 }
        // (Aptos, drawn in a clone of other proportions. Its twelve decks'
        // lines stood 0.02 em low; 0.21 puts ten of them within 0.016 em
        // of PowerPoint's. The `hhea` the prints' embedded copies keep,
        // 1923 over 577 — 0.23 — put them 0.02 em high: the Windows
        // metrics it goes by are stripped from those copies.)
        if n.hasPrefix("aptos") { return 0.21 }
        // (And Arial and Times New Roman by theirs, no line gap counted:
        // their clones' gap — a thirtieth and a twenty-fourth of an em —
        // put a share of it under the baseline in the engine's line, and
        // Arial's 43 decks stood 0.011 em high.)
        if n == "arial" { return 434.0 / 2288 }
        // (MS Gothic by its own, 0.859 over and 0.141 under of its square
        // 1.0 em line: lab p3lp's first baseline stood 0.073 of the size
        // high in its stand-in's depth, 1.3 pt at 18 pt, 2.2 at 32.)
        if n == "ms gothic" || n == "ｍｓ ゴシック" { return 0.141 }
        if n == "times new roman" { return 443.0 / 2268 }
        return nil
    }
}
