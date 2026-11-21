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
    static func windowsName(_ family: String) -> String {
        let n = family.trimmingWhitespace().lowercased()
        if missingRoman.contains(n), OfficeFonts.installed(family) == nil, embeddedFamily(family) == nil { return "palatino linotype" }
        return n == "dejavu sans" && OfficeFonts.installed(family) == nil ? "verdana" : n
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
        return !["명조", "바탕", "궁서", "신명", "필기", "손글씨", "펜"].contains(where: { n.containsSubstring($0) })
    }

    static func resolve(_ family: String) -> String {
        // (The machine's own face, where it has it and the user takes it:
        // `OfficeFonts.installed`.)
        if let own = OfficeFonts.installed(family) { return own }
        if let mine = embeddedFamily(family) { return mine }
        if windowsName(family) == "palatino linotype", family.trimmingWhitespace().lowercased() != "palatino linotype" { return resolve("Palatino Linotype") }
        if let free = freeFaces[family.trimmingWhitespace().lowercased()] { return free }
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
        guard !eastAsian || windowsName(family) == "malgun gothic" || windowsName(family) == "맑은 고딕" || missingKoreanGothic(family) else { return nil }
        if let cuts = SlideEastAsianWidths.lookup(windowsName(family)) ?? (missingKoreanGothic(family) ? SlideEastAsianWidths.malgun : nil) {
            // (An East Asian face at its own measured widths, Latin and the rest past ASCII: PowerPoint sets it by itself, not by a stand-in's.)
            // (Built once per family: parsing its advance table for every run made a 560-slide deck take over ten minutes.)
            eastAsianLock.lock(); defer { eastAsianLock.unlock() }
            if let made = eastAsianMade[family] { return made }
            var face = RichResolvedFace(family: resolve(family))
            let regular = SlideEastAsianWidths.parse(cuts.regular.other)
            let bold = cuts.bold.map { SlideEastAsianWidths.parse($0.other) } ?? regular
            face.advances = cuts.regular.ascii
            face.boldAdvances = cuts.bold?.ascii ?? cuts.regular.ascii
            face.otherAdvances = regular
            face.boldOtherAdvances = bold
            // (Malgun Gothic's Hangul is an em, which the table of advances that are not one does not hold.)
            if cuts.regular.ascii == SlideEastAsianWidths.malgun.regular.ascii { face.otherAdvances?[0xAC00] = 1.0; face.boldOtherAdvances?[0xAC00] = 1.0 }
            if let it = SlideEastAsianWidths.lookupItalic(windowsName(family)) {
                face.italicAdvances = it.regular.ascii
                face.boldItalicAdvances = it.bold?.ascii ?? it.regular.ascii
                face.italicOtherAdvances = SlideEastAsianWidths.parse(it.regular.other)
                face.boldItalicOtherAdvances = it.bold.map { SlideEastAsianWidths.parse($0.other) } ?? face.italicOtherAdvances
            }
            eastAsianMade[family] = face
            return face
        }
        switch windowsName(family) {
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
             "franklin gothic medium", "century gothic", "gill sans mt", "candara", "palatino linotype":
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
                "palatino linotype": (SlideFontWidths.palatino, SlideFontWidths.palatinoBold),
            ]
            guard let t = tables[n] else { return nil }
            var face = RichResolvedFace(family: resolve(family))
            face.advances = t.0
            face.boldAdvances = t.1
            return face
        case "nunito", "nunito light", "nunito medium", "nunito black", "nunito sans", "nunito sans light":
            // (Nunito at Nunito Sans's widths, which PowerPoint's print of e3e0b3e0 matches for Nunito Light to the
            // third place; Carlito's are 4% narrower and a line held a word more. Medium is set at the regular's,
            // Black at the bold's: no cut of either is measured.)
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
            return face
        case "calibri light":
            // (Calibri Light has no bold: PowerPoint sets a bold run of it at Calibri Regular's advances, not Carlito Bold's,
            // which are wider and wrapped 6d178027's 48 pt title a word early.)
            var face = RichResolvedFace(family: resolve(family))
            face.boldAdvances = OfficeFonts.calibriRegularLatinAdvances
            face.otherAdvances = SlideFontWidths.calibriHebrew
            face.boldOtherAdvances = SlideFontWidths.calibriHebrew
            return face
        case "arial black":
            var face = RichResolvedFace(family: resolve(family))
            face.advances = OfficeFonts.arialBlackAdvances
            face.boldAdvances = OfficeFonts.arialBlackAdvances
            return face
        default:
            // (A face no one knows is Calibri in PowerPoint's print, its
            // Hebrew too: tdf98603's FrankRuehl quote, a fifth narrower
            // than Carlito's own Hebrew.)
            guard resolve(family) == OfficeFonts.calibri else { return nil }
            var face = RichResolvedFace(family: OfficeFonts.calibri)
            face.otherAdvances = SlideFontWidths.calibriHebrew
            face.boldOtherAdvances = SlideFontWidths.calibriHebrew
            return face
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
        case "lucida sans unicode": return 3147.0 / 2048
        default: return nil
        }
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

    static func ownDescentShare(_ family: String) -> Double? {
        guard OfficeFonts.installed(family) == nil else { return nil }
        let n = windowsName(family)
        // (East Asian faces by PowerPoint's print, lab slides-cjk-lines: a line is 1.2 em at every face and size, its
        // baseline at 1.2 em x winAscent / (winAscent + winDescent): YaHei 2167+536 of 2048, Malgun 2229+495, SimSun and
        // MS Mincho/Gothic 220+36 of 256; Meiryo and Yu Gothic from their first baselines, .847 and .921 em at 18 pt.)
        switch n {
        case "microsoft yahei": return 536.0 / 2703
        case "malgun gothic", "맑은 고딕": return 495.0 / 2724
        case "simsun", "宋体", "nsimsun", "ms mincho", "ｍｓ 明朝", "ms pmincho", "ｍｓ ｐ明朝", "ms pgothic", "ｍｓ ｐゴシック": return 36.0 / 256
        case "ms gothic", "ｍｓ ゴシック", "ms ui gothic", "ｍｓ ｕｉ ゴシック", "hgゴシックe", "hgｺﾞｼｯｸe", "hg gothic e", "hg丸ゴシックm-pro", "hg丸ｺﾞｼｯｸm-pro",
             "hgmarugothicmpro", "hg明朝e", "hg mincho e", "hgp明朝e", "hgp mincho e", "hgp創英角ゴシックub", "hgp創英角ｺﾞｼｯｸub", "hgpsoeikakugothicub": return 288.0 / 2048
        case "gulim", "굴림", "gulimche", "굴림체", "dotum", "돋움", "dotumche", "돋움체", "batang", "바탕", "batangche", "바탕체": return 145.0 / 1024
        case "nanumgothic", "나눔고딕": return 198.0 / 1083
        case "nunito", "nunito light", "nunito black": return 300.0 / 1377
        case "baskerville old face": return 531.0 / 2336
        case "hgpゴシックe", "hgpｺﾞｼｯｸe", "hgpgothice", "hgsゴシックe", "hgsｺﾞｼｯｸe", "hgsgothice", "hg創英角ゴシックub", "hg創英角ｺﾞｼｯｸub", "hgsoeikakugothicub",
             "hgs創英角ゴシックub", "hgs創英角ｺﾞｼｯｸub", "hgssoeikakugothicub": return 288.0 / 2048
        case "ud デジタル 教科書体 nk-b", "ud digi kyokasho nk-b", "ud デジタル 教科書体 np-b", "ud digi kyokasho np-b": return 567.0 / 2369
        case "microsoft jhenghei", "微軟正黑體": return 521.0 / 2724
        case "tw cen mt": return 477.0 / 2230
        case "noto sans": return 600.0 / 2789
        case "comic sans ms": return 597.0 / 2854
        case "gungsuh", "궁서", "gungsuhche", "궁서체": return 145.0 / 1024
        case "pmingliu", "新細明體", "mingliu", "細明體": return 204.0 / 1024
        case "georgia": return 449.0 / 2327
        case "raleway": return 234.0 / 1388
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
        case "yu gothic", "游ゴシック": return 1 - 0.921 / 1.2
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
        // the engine puts half of it under the baseline; Work Sans by its
        // Windows ascent and descent.)
        if n.hasPrefix("poppins") { return 0.35 / 1.4 }
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
