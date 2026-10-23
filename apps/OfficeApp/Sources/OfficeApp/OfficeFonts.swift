// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

/// The document faces Office ships: Liberation Sans/Serif/Mono, Carlito and
/// Caladea — metric clones of Arial/Times/Courier, Calibri and Cambria — so
/// a `.docx` written in those reflows the same here. Registered by path
/// (mmap, shared, evictable), each family's four files under one name —
/// the font manager picks weight and slant.
///
/// A document keeps the font names it came with; `substitute` maps a name
/// to the shipped face at render time (the theme's `fontFamilyResolver`),
/// the way Google Docs draws "Times New Roman" with Tinos. So the file
/// round-trips its fonts untouched, and looks the same on every platform,
/// because no platform's own fonts are ever consulted.
///
/// Found by searching for the SwiftPM resource bundle, never through
/// `Bundle.module`: that accessor bakes the BUILD directory's absolute path
/// into the binary, so a shipped .app would find its fonts only on the
/// machine that built it (`TerminalView.swift` learned this the hard way).
enum OfficeFonts {
    static let sans = "Liberation Sans"
    static let serif = "Liberation Serif"
    static let mono = "Liberation Mono"
    static let calibri = "Carlito"
    static let cambria = "Caladea"
    /// DejaVu Sans, for Verdana: not a metric clone, but of the same
    /// family (both grew out of Bitstream Vera's design) and within a
    /// hundredth of its widths word for word, where Liberation Sans set
    /// Verdana's lines an eighth short.
    static let verdana = "DejaVu Sans"
    /// Liberation Sans and Serif as a Word document's lines take them:
    /// the same faces with their line gap moved over the ascent (see
    /// `_gapAbove`), registered under these names beside the plain ones.
    static let wordSans = "Liberation Sans Word"
    static let wordSerif = "Liberation Serif Word"

    /// The name a file gets for one of our faces: the Word font it is the
    /// clone of, so that Word opens the file in the real thing. Any other
    /// name (a document's own) passes through.
    static func exportName(_ family: String) -> String {
        switch family {
        case sans: return "Arial"
        case serif: return "Times New Roman"
        case mono: return "Courier New"
        case calibri: return "Calibri"
        case cambria: return "Cambria"
        case verdana: return "Verdana"
        default: return family
        }
    }

    /// The shipped face for a family name, by Word's names first and by
    /// the look of the name after that. Case-insensitive.
    static func substitute(_ family: String) -> String {
        let n = family.trimmingWhitespace().lowercased()
        switch n {
        case "liberation sans", "arial", "helvetica", "helvetica neue", "tahoma",
             "segoe ui", "aptos", "arimo", "arial black":
            return sans
        case "verdana", "dejavu sans", "bitstream vera sans":
            return verdana
        case "liberation serif", "times new roman", "times", "georgia", "book antiqua",
             "garamond", "palatino", "palatino linotype", "tinos":
            return serif
        case "liberation mono", "courier new", "courier", "consolas", "menlo", "monaco",
             "lucida console", "cousine":
            return mono
        case "carlito", "calibri", "calibri light":
            return calibri
        case "caladea", "cambria":
            return cambria
        default:
            // ("code" as in Source Code Pro — not as in Lucida Sans Unicode,
            // which came up monospace for a while.)
            if n.containsSubstring("mono") || n.containsSubstring("courier")
                || (n.containsSubstring("code") && !n.containsSubstring("unicode")) {
                return mono
            }
            // (A name only: not one Word has no face for that the file's
            // table describes, which goes by the table below —
            // zh-c399c91a's "LinTimes", PANOSE Times's and no alternate,
            // is Calibri in Word's print, its "/" 4.06pt at 10.5, where
            // ours took Times and a cell's "门" stayed on the line.)
            let byTable = !wordMacFamilies.contains(n) && !family.unicodeScalars.contains { $0.value >= 0x2E80 } && fontEntry(family) != nil
            if !byTable, n.containsSubstring("serif") && !n.containsSubstring("sans") { return serif }
            if !byTable, n.containsSubstring("times") || n.containsSubstring("roman") || n.containsSubstring("garamond")
                || n.containsSubstring("baskerville") || n.containsSubstring("didot") {
                return serif
            }
            // A Latin name Word on a Mac has no face for goes by the
            // file's font table (labs `fs`, `fs2`, `fs3` in bug59058's
            // package and two others, Word 16, 2026-10-15): an entry
            // with an alternate and a PANOSE that is not all zeros, or
            // none, is set in the alternate ("agencyr" in Times New
            // Roman, "TestE" in Arial); one whose PANOSE is all zeros
            // keeps no alternate — of family roman it is Cambria
            // ("MinionPro-Regular", alternate Times, is Cambria in the
            // print), else Calibri; an entry with neither alternate nor
            // PANOSE is Calibri whatever its family ("S宋体", "xits-math";
            // zh-a4b0f6ea's digits are Calibri's 8.15pt at 16pt); and a
            // name the table does not hold at all is Cambria, in a file
            // of any theme ("FooSerif Book", "BarSans Light"). bug59058's
            // body, MinionPro-Regular, had been Liberation Sans here and
            // wrapped on every line of 52 pages; Caladea's advances are
            // Cambria's to the unit.
            // (Only for a name Word on a Mac has no face for: one of its
            // own or the Mac's — `wordMacFamilies` — keeps the guesses
            // above and below, as does an East Asian name set for Latin
            // characters, whose face Word has too: zh-6d1afa56's "√" in
            // 仿宋 is FangSong's in the print.)
            let eastAsianName = family.unicodeScalars.contains { $0.value >= 0x2E80 }
            if !eastAsianName, !wordMacFamilies.contains(n) {
                if let e = fontEntry(family) {
                    if let alt = e.alt, !alt.isEmpty, !e.panoseZero, alt.trimmingWhitespace().lowercased() != n { return substitute(alt) }
                    if e.panoseZero { return e.family == "roman" ? cambria : calibri }
                    return calibri
                }
                return cambria
            }
            // (A name the font table declares Latin and Word has no face
            // for — "S宋体" — Word sets in Calibri: zh-a4b0f6ea's digits
            // are Calibri's 8.15pt at 16pt in its print, and Arial's 8.9
            // pushed a "〔2021〕" off the line Word keeps it on.)
            if isDeclaredLatin(family) { return calibri }
            return sans
        }
    }

    /// Names a file's font table declares in the Latin character set
    /// (`w:charset` 00) that are no face Word has: "S宋体" reads as a
    /// Chinese face and is not one — Word sets its letters, digits and
    /// quotes in a Latin face. (A face Word has it knows whatever the
    /// table says: six files of the corpus declare 宋体 that way.)
    private nonisolated(unsafe) static var declaredLatin: Set<String> = []
    #if os(WASI)
    // One thread in the browser, and no NSLock in its Foundation.
    private struct _NoLock { func lock() {}; func unlock() {} }
    private static let declaredLock = _NoLock()
    #else
    private static let declaredLock = NSLock()
    #endif
    private static let wordsOwn: Set<String> = [
        "宋体", "simsun", "新宋体", "nsimsun", "黑体", "simhei", "楷体", "kaiti", "仿宋", "fangsong", "微软雅黑", "microsoft yahei",
        "microsoft yahei ui", "等线", "等线 light", "dengxian", "dengxian light", "新細明體", "pmingliu", "細明體", "mingliu",
        "微軟正黑體", "microsoft jhenghei", "华文中宋", "华文仿宋", "华文楷体", "华文宋体", "华文细黑", "stsong", "stkaiti",
        "stfangsong", "stzhongsong", "stxihei", "arial unicode ms", "幼圆", "youyuan", "隶书", "lisu",
    ]

    /// Takes a file's font table: each name and its `w:charset`.
    /// The East Asian faces a file carries in it (`w:embedRegular` in
    /// its font table). Word sets those in the face itself, not in the
    /// YaHei it falls back to for a name it lacks: zh-e37f8d40 embeds
    /// 仿宋_GB2312, and Word's print draws FangSong_GB2312, its ASCII
    /// half an em wide — a line of ours took one character more beside
    /// YaHei's narrower brackets. Kept per name, like the charsets: a
    /// file that embeds a face notes it; another that names it without
    /// does not unnote it, nor does it need to (the note only stops the
    /// fallback).
    nonisolated(unsafe) private static var embedded: Set<String> = []
    /// The font table's `w:altName` for each East Asian name: the face
    /// Word uses where it has none of the name's own. zh-64044a1d's
    /// cover names 華康粗圓體, alternate 新細明體, and Word's print draws
    /// PMingLiU — where ours took the YaHei this Word falls back to for
    /// a name with no alternate, and the cover's seven 26pt lines came
    /// out three pitches each instead of two (121 pages to Word's 103).
    nonisolated(unsafe) private static var altNames: [String: String] = [:]
    static func noteAltNames(_ names: [String: String]) {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        altNames = Dictionary(names.map { ($0.key.trimmingWhitespace().lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }
    private static func altName(_ family: String) -> String? {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        return altNames[family.trimmingWhitespace().lowercased()]
    }
    /// The font table's whole say on each name: its alternate, its
    /// `w:family` and whether its PANOSE is all zeros — what Word on a
    /// Mac goes by for a Latin name it has no face for (`substitute`).
    struct FontEntry { var alt: String?; var family: String; var panoseZero: Bool }
    nonisolated(unsafe) private static var fontEntries: [String: FontEntry] = [:]
    static func noteFontEntries(_ entries: [String: FontEntry]) {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        fontEntries = Dictionary(entries.map { ($0.key.trimmingWhitespace().lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }
    /// The Latin and other families Word 16 for Mac can set text in:
    /// the faces it bundles (its DFonts) and the Mac's own, by family
    /// name, lowercased — read off this box on 2026-10-15. A name not
    /// here is one Word has no face for, and `substitute` goes by the
    /// file's font table for it.
    static let wordMacFamilies: Set<String> = [
        "abadi mt condensed extra bold", "abadi mt condensed light", "academy engraved let", "al bayan",
        "al nile", "al tarikh", "american typewriter", "andale mono", "angsana new", "apple braille",
        "apple chancery", "apple color emoji", "apple sd gothic neo", "apple symbols", "applegothic",
        "applemyungjo", "aptos", "aptos black", "aptos extrabold", "aptos light", "aptos narrow",
        "aptos semibold", "arial", "arial black", "arial hebrew", "arial hebrew scholar", "arial narrow",
        "arial rounded mt bold", "arial unicode ms", "athelas", "avenir", "avenir black",
        "avenir black oblique", "avenir book", "avenir heavy", "avenir light", "avenir medium",
        "avenir next", "avenir next condensed", "avenir next condensed demi bold",
        "avenir next condensed heavy", "avenir next condensed medium", "avenir next condensed ultra light",
        "avenir next demi bold", "avenir next heavy", "avenir next medium", "avenir next ultra light",
        "ayuthaya", "baghdad", "bangla mn", "bangla sangam mn", "baskerville", "baskerville old face",
        "batang", "batangche", "bauhaus 93", "beirut", "bell mt", "bernard mt condensed", "big caslon",
        "bodoni 72", "bodoni 72 oldstyle", "bodoni 72 smallcaps", "bodoni ornaments", "book antiqua",
        "bookman old style", "bookshelf symbol 7", "bradley hand", "braggadocio", "britannic bold",
        "brush script mt", "calibri", "calibri light", "calisto mt", "cambria", "cambria math", "candara",
        "century", "century gothic", "century schoolbook", "chalkboard", "chalkboard se", "chalkduster",
        "charter", "charter black", "cochin", "colonna mt", "comic sans ms", "consolas", "constantia",
        "cooper black", "copperplate", "copperplate gothic bold", "corbel", "cordia new", "cordiaupc",
        "corsiva hebrew", "courier", "courier new", "curlz mt", "damascus", "david", "decotype naskh",
        "dengxian", "dengxian light", "desdemona", "devanagari mt", "devanagari sangam mn", "didot",
        "din alternate", "din condensed", "diwan kufi", "diwan thuluth", "dotum", "dotumche", "dubai",
        "dubai light", "dubai medium", "edwardian script itc", "engravers mt", "euphemia ucas", "eurostile",
        "fangsong", "farah", "farisi", "footlight mt light", "franklin gothic book", "franklin gothic demi",
        "franklin gothic demi cond", "franklin gothic heavy", "franklin gothic medium",
        "franklin gothic medium cond", "futura", "gabriola", "galvji", "garamond", "gautami",
        "gb18030 bitmap", "geeza pro", "geneva", "georgia", "gill sans", "gill sans mt",
        "gill sans mt condensed", "gill sans mt ext condensed bold", "gill sans ultra bold",
        "gloucester mt extra condensed", "goudy old style", "grantha sangam mn", "gujarati mt",
        "gujarati sangam mn", "gulim", "gulimche", "gungsuh", "gungsuhche", "gurmukhi mn", "gurmukhi mt",
        "gurmukhi sangam mn", "haettenschweiler", "harrington", "heiti sc", "heiti tc", "helvetica",
        "helvetica neue", "herculanum", "hggothice", "hgmarugothicmpro", "hgminchoe", "hgpgothice",
        "hgpminchoe", "hgpsoeikakugothicub", "hgsgothice", "hgsminchoe", "hgsoeikakugothicub",
        "hgssoeikakugothicub", "hiragino kaku gothic pro", "hiragino kaku gothic pro w3",
        "hiragino kaku gothic pro w6", "hiragino kaku gothic pron", "hiragino kaku gothic pron w3",
        "hiragino kaku gothic pron w6", "hiragino kaku gothic std", "hiragino kaku gothic std w8",
        "hiragino kaku gothic stdn", "hiragino kaku gothic stdn w8", "hiragino maru gothic pro",
        "hiragino maru gothic pro w4", "hiragino maru gothic pron", "hiragino maru gothic pron w4",
        "hiragino mincho pro", "hiragino mincho pro w3", "hiragino mincho pro w6", "hiragino mincho pron",
        "hiragino mincho pron w3", "hiragino mincho pron w6", "hiragino sans", "hiragino sans gb",
        "hiragino sans gb w3", "hiragino sans gb w6", "hiragino sans w0", "hiragino sans w1",
        "hiragino sans w2", "hiragino sans w3", "hiragino sans w4", "hiragino sans w5", "hiragino sans w6",
        "hiragino sans w7", "hiragino sans w8", "hiragino sans w9", "hoefler text", "hoefler text ornaments",
        "impact", "imprint mt shadow", "inaimathi", "iowan old style", "iowan old style black",
        "itf devanagari", "itf devanagari marathi", "kailasa", "kaiti", "kannada mn", "kannada sangam mn",
        "kartika", "kefa iii", "khmer mn", "khmer sangam mn", "kino mt", "kohinoor bangla",
        "kohinoor devanagari", "kohinoor gujarati", "kohinoor telugu", "kokonor", "krungthep",
        "kufistandardgk", "lao mn", "lao sangam mn", "latha", "lucida blackletter", "lucida bright",
        "lucida calligraphy", "lucida console", "lucida fax", "lucida grande", "lucida handwriting",
        "lucida sans", "lucida sans typewriter", "lucida sans unicode", "luminari", "malayalam mn",
        "malayalam sangam mn", "malgun gothic", "malgun gothic semilight", "mangal", "marion", "marker felt",
        "marlett", "matura mt script capitals", "meiryo", "meiryo ui", "menlo", "microsoft himalaya",
        "microsoft jhenghei", "microsoft new tai lue", "microsoft sans serif", "microsoft tai le",
        "microsoft yahei", "microsoft yahei light", "microsoft yahei ui", "microsoft yahei ui light",
        "microsoft yi baiti", "mingliu", "mingliu-extb", "mingliu_hkscs", "mingliu_hkscs-extb", "mishafi",
        "mishafi gold", "mistral", "modern no. 20", "monaco", "mongolian baiti", "monotype corsiva",
        "monotype sorts", "ms gothic", "ms mincho", "ms pgothic", "ms pmincho", "ms reference sans serif",
        "ms reference specialty", "ms ui gothic", "mshtakan", "mt extra", "mukta mahee", "muktamahee bold",
        "muktamahee extrabold", "muktamahee extralight", "muktamahee light", "muktamahee medium",
        "muktamahee regular", "muktamahee semibold", "muna", "myanmar mn", "myanmar sangam mn",
        "myanmar text", "nadeem", "new peninim mt", "news gothic mt", "noteworthy", "noto nastaliq urdu",
        "noto sans adlam", "noto sans armenian", "noto sans armenian blk", "noto sans armenian extbd",
        "noto sans armenian extlt", "noto sans armenian light", "noto sans armenian med",
        "noto sans armenian sembd", "noto sans armenian thin", "noto sans avestan", "noto sans bamum",
        "noto sans bassa vah", "noto sans batak", "noto sans bhaiksuki", "noto sans buginese",
        "noto sans buhid", "noto sans carian", "noto sans caucalban", "noto sans caucasian albanian",
        "noto sans chakma", "noto sans cham", "noto sans coptic", "noto sans cuneiform", "noto sans cypriot",
        "noto sans duployan", "noto sans egypthiero", "noto sans egyptian hieroglyphs", "noto sans elbasan",
        "noto sans glagolitic", "noto sans gothic", "noto sans gunjala gondi", "noto sans hanifi rohingya",
        "noto sans hanifirohg", "noto sans hanunoo", "noto sans hatran", "noto sans imparamaic",
        "noto sans imperial aramaic", "noto sans inscriptional pahlavi", "noto sans inscriptional parthian",
        "noto sans inspahlavi", "noto sans insparthi", "noto sans javanese", "noto sans kaithi",
        "noto sans kannada", "noto sans kannada black", "noto sans kannada extrabold",
        "noto sans kannada extralight", "noto sans kannada light", "noto sans kannada medium",
        "noto sans kannada semibold", "noto sans kannada thin", "noto sans kayah li", "noto sans kharoshthi",
        "noto sans khojki", "noto sans khudawadi", "noto sans lepcha", "noto sans limbu",
        "noto sans linear a", "noto sans linear b", "noto sans lisu", "noto sans lycian", "noto sans lydian",
        "noto sans mahajani", "noto sans mandaic", "noto sans manichaean", "noto sans marchen",
        "noto sans masaram gondi", "noto sans meetei mayek", "noto sans meeteimayek",
        "noto sans mende kikakui", "noto sans meroitic", "noto sans miao", "noto sans modi",
        "noto sans mongolian", "noto sans mro", "noto sans multani", "noto sans myanmar",
        "noto sans myanmar blk", "noto sans myanmar extbd", "noto sans myanmar extlt",
        "noto sans myanmar light", "noto sans myanmar med", "noto sans myanmar sembd",
        "noto sans myanmar thin", "noto sans nabataean", "noto sans nag mundari", "noto sans new tai lue",
        "noto sans newa", "noto sans newtailue", "noto sans nko", "noto sans ol chiki",
        "noto sans old hungarian", "noto sans old italic", "noto sans old north arabian",
        "noto sans old permic", "noto sans old persian", "noto sans old south arabian",
        "noto sans old turkic", "noto sans oldhung", "noto sans oldnorarab", "noto sans oldpersian",
        "noto sans oldsouarab", "noto sans oriya", "noto sans osage", "noto sans osmanya",
        "noto sans pahawh hmong", "noto sans palmyrene", "noto sans pau cin hau", "noto sans paucinhau",
        "noto sans phagspa", "noto sans phoenician", "noto sans psalter pahlavi", "noto sans psapahlavi",
        "noto sans rejang", "noto sans samaritan", "noto sans saurashtra", "noto sans sharada",
        "noto sans siddham", "noto sans sora sompeng", "noto sans sorasomp", "noto sans sundanese",
        "noto sans sunuwar", "noto sans syloti nagri", "noto sans syriac", "noto sans tagalog",
        "noto sans tagbanwa", "noto sans tai le", "noto sans tai tham", "noto sans tai viet",
        "noto sans takri", "noto sans thaana", "noto sans tifinagh", "noto sans tirhuta",
        "noto sans ugaritic", "noto sans vai", "noto sans wancho", "noto sans warang citi",
        "noto sans warangciti", "noto sans yi", "noto sans zawgyi", "noto sans zawgyi blk",
        "noto sans zawgyi extbd", "noto sans zawgyi extlt", "noto sans zawgyi light", "noto sans zawgyi med",
        "noto sans zawgyi sembd", "noto sans zawgyi thin", "noto serif ahom", "noto serif balinese",
        "noto serif hmong nyiakeng", "noto serif myanmar", "noto serif myanmar blk",
        "noto serif myanmar extbd", "noto serif myanmar extlt", "noto serif myanmar light",
        "noto serif myanmar med", "noto serif myanmar sembd", "noto serif myanmar thin", "noto serif yezidi",
        "nsimsun", "nyala", "onyx", "optima", "oriya mn", "oriya sangam mn", "palatino", "palatino linotype",
        "papyrus", "party let", "perpetua", "perpetua titling mt", "phosphate", "plantagenet cherokee",
        "pmingliu", "pmingliu-extb", "pt mono", "pt sans", "pt sans caption", "pt sans narrow", "pt serif",
        "pt serif caption", "raanana", "rockwell", "rockwell condensed", "rockwell extra bold", "sana",
        "sathu", "savoye let", "segoe print", "segoe script", "segoe ui historic", "segoe ui symbol",
        "seravek", "seravek extralight", "seravek light", "seravek medium", "shree devanagari 714",
        "signpainter", "signpainter-housescript", "silom", "simhei", "simsun", "simsun-extb", "sinhala mn",
        "sinhala sangam mn", "skia", "snell roundhand", "songti sc", "songti tc", "stencil", "sthupo",
        "stix two math", "stix two text", "stixgeneral", "stixintegralsd", "stixintegralssm",
        "stixintegralsup", "stixintegralsupd", "stixintegralsupsm", "stixnonunicode", "stixsizefivesym",
        "stixsizefoursym", "stixsizeonesym", "stixsizethreesym", "stixsizetwosym", "stixvariants", "stliti",
        "stsong", "stxingkai", "stxinwei", "stzhongsong", "sukhumvit set", "superclarendon", "symbol",
        "system font", "tahoma", "tamil mn", "tamil sangam mn", "telugu mn", "telugu sangam mn",
        "th sarabunpsk", "thonburi", "times", "times new roman", "trattatello", "trebuchet ms", "tunga",
        "tw cen mt", "tw cen mt condensed", "tw cen mt condensed extra bold", "verdana", "waseem",
        "webdings", "wide latin", "wingdings", "wingdings 2", "wingdings 3", "yu gothic", "yu gothic light",
        "yu gothic medium", "yu gothic ui", "yu gothic ui light", "yu gothic ui semibold",
        "yu gothic ui semilight", "yu mincho", "yu mincho demibold", "yu mincho light", "zapf dingbats",
        "zapfino",
    ]
    /// The shipped face for a workbook's font name. A workbook has no font
    /// table, so `substitute`'s guesses for a name Word on a Mac has no
    /// face for — Cambria, for one the table does not hold — are not
    /// Excel's: chart-tdf150434's "Open Sans" prints sans, where ours was
    /// Caladea and its long text ran a page short.
    static func sheetFace(_ family: String) -> String {
        #if os(Windows)
        // A face Windows has and this app has no clone of is the face, for
        // every character of the cell: style-alternate-content's 맑은 고딕
        // prints its digits, Latin and "○○○" in Malgun Gothic, where ours
        // set them in Liberation Sans and only the Hangul fell back to
        // Malgun; the format tests' Lucida Sans Typewriter is monospaced,
        // and Liberation Sans was not.
        if let face = windowsFaces[family.trimmingWhitespace().lowercased()] { return face }
        #endif
        return sheetClone(family)
    }

    /// The clone of `sheetFace`, whatever the platform has: the face whose
    /// measures the sheet's print metrics borrow for a face nobody measured.
    static func sheetClone(_ family: String) -> String {
        let face = substitute(family)
        if face == cambria, family.lowercased().containsSubstring("sans") { return sans }
        return face
    }

    #if os(Windows)
    /// Names, and the Windows face each prints in, where this Windows has
    /// its font file (Dotum, Gulim and Batang left Windows; Excel prints
    /// them as Malgun Gothic — see SheetPrintMetrics' aliases). The faces
    /// this app has clones of (Calibri, Arial, Times New Roman, ...) keep
    /// their clones.
    private static let windowsFaces: [String: String] = {
        let fonts = (ProcessInfo.processInfo.environment["WINDIR"] ?? "C:/Windows") + "/Fonts/"
        var m: [String: String] = [:]
        for (names, face, file) in [
            (["맑은 고딕", "malgun gothic", "돋움", "dotum", "굴림", "gulim", "바탕", "batang"], "Malgun Gothic", "malgun.ttf"),
            (["ｍｓ ｐゴシック", "ms pgothic"], "MS PGothic", "msgothic.ttc"),
            (["ｍｓ ゴシック", "ms gothic"], "MS Gothic", "msgothic.ttc"),
            (["宋体", "simsun"], "SimSun", "simsun.ttc"),
            (["新宋体", "nsimsun"], "NSimSun", "simsun.ttc"),
            (["微软雅黑", "microsoft yahei"], "Microsoft YaHei", "msyh.ttc"),
            (["微軟正黑體", "microsoft jhenghei"], "Microsoft JhengHei", "msjh.ttc"),
            (["游ゴシック", "yu gothic"], "Yu Gothic", "YuGothR.ttc"),
            (["lucida sans typewriter"], "Lucida Sans Typewriter", "LTYPE.TTF"),
            (["lucida sans", "lucida sans regular"], "Lucida Sans", "LSANS.TTF"),
            (["lucida sans unicode"], "Lucida Sans Unicode", "l_10646.ttf"),
            (["comic sans ms"], "Comic Sans MS", "comic.ttf"),
            (["century gothic"], "Century Gothic", "GOTHIC.TTF"),
            (["trebuchet ms"], "Trebuchet MS", "trebuc.ttf"),
            (["microsoft sans serif", "ms sans serif"], "Microsoft Sans Serif", "micross.ttf"),
            (["arial black"], "Arial Black", "ariblk.ttf"),
            (["arial narrow"], "Arial Narrow", "ARIALN.TTF"),
            (["arial rounded mt bold"], "Arial Rounded MT Bold", "ARLRDBD.TTF"),
            (["garamond"], "Garamond", "GARA.TTF"),
            (["palatino linotype"], "Palatino Linotype", "pala.ttf"),
            (["britannic bold"], "Britannic Bold", "BRITANIC.TTF"),
        ] where FileManager.default.fileExists(atPath: fonts + file) { for n in names { m[n] = face } }
        return m
    }()
    #endif

    private static func fontEntry(_ family: String) -> FontEntry? {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        return fontEntries[family.trimmingWhitespace().lowercased()]
    }
    static func noteEmbedded(_ names: [String]) {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        embedded = Set(names.map { $0.trimmingWhitespace().lowercased() })
    }
    private static func isEmbedded(_ family: String) -> Bool {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        return embedded.contains(family.trimmingWhitespace().lowercased())
    }

    /// The East Asian faces a file embeds, loaded: each name the file
    /// gives it and the family it is registered as. Word draws such a
    /// name in the file's own face — zh-e37f8d40's print is in the
    /// FangSong_GB2312, SimHei and KaiTi_GB2312 it carries — where ours
    /// drew the platform's (PingFang) for every one. The measure stays
    /// the square model `eastAsianFace` gives an embedded name; the face
    /// changes what is drawn, not where.
    nonisolated(unsafe) private static var embeddedFaces: [String: String] = [:]
    nonisolated(unsafe) private static var loadedEmbedded: Set<String> = []
    /// Each loaded embedded face's line (`lineMetrics`).
    nonisolated(unsafe) private static var embeddedLines: [String: (ascent: Double, descent: Double)] = [:]
    /// The characters each loaded embedded face holds (its `cmap`).
    nonisolated(unsafe) private static var embeddedCoverage: [String: Set<UInt32>] = [:]

    /// The characters an sfnt's `cmap` maps (formats 4 and 12, Unicode
    /// subtables); nil where it has none this reads.
    /// A face's hhea ascent and descent, in ems.
    static func lineMetrics(_ data: Data) -> (ascent: Double, descent: Double)? {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
        func u32(_ o: Int) -> Int { u16(o) << 16 | u16(o + 2) }
        func s16(_ o: Int) -> Int { let v = u16(o); return v >= 0x8000 ? v - 0x10000 : v }
        guard b.count > 12 else { return nil }
        var head = -1, hhea = -1
        for t in 0 ..< u16(4) where 12 + 16 * t + 16 <= b.count {
            let at = 12 + 16 * t
            let tag = String(decoding: b[at ..< at + 4], as: UTF8.self)
            if tag == "head" { head = u32(at + 8) } else if tag == "hhea" { hhea = u32(at + 8) }
        }
        guard head >= 0, hhea >= 0, head + 20 <= b.count, hhea + 8 <= b.count, case let em = u16(head + 18), em > 0 else { return nil }
        return (Double(s16(hhea + 4)) / Double(em), Double(-s16(hhea + 6)) / Double(em))
    }

    static func coverage(_ data: Data) -> Set<UInt32>? {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
        func u32(_ o: Int) -> Int { u16(o) << 16 | u16(o + 2) }
        guard b.count > 12 else { return nil }
        var cmap = -1
        for t in 0 ..< u16(4) where 12 + 16 * t + 16 <= b.count {
            let at = 12 + 16 * t
            if b[at] == 0x63, b[at + 1] == 0x6D, b[at + 2] == 0x61, b[at + 3] == 0x70 { cmap = u32(at + 8) }
        }
        guard cmap >= 0, cmap + 4 <= b.count else { return nil }
        var best = -1, bestFormat = 0
        for k in 0 ..< u16(cmap + 2) {
            let rec = cmap + 4 + 8 * k
            let platform = u16(rec), encoding = u16(rec + 2), sub = cmap + u32(rec + 4)
            guard platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10)) else { continue }
            let format = u16(sub)
            if format == 12 || (format == 4 && bestFormat != 12) { best = sub; bestFormat = format }
        }
        guard best >= 0 else { return nil }
        var out = Set<UInt32>()
        if bestFormat == 12 {
            for g in 0 ..< u32(best + 12) {
                let at = best + 16 + 12 * g
                let start = u32(at), end = u32(at + 4)
                guard end >= start, end - start < 0x20000 else { continue }
                for c in start ... end { out.insert(UInt32(c)) }
            }
        } else {
            let segs = u16(best + 6) / 2
            let ends = best + 14, starts = ends + 2 * segs + 2, deltas = starts + 2 * segs, offsets = deltas + 2 * segs
            for s in 0 ..< segs {
                let start = u16(starts + 2 * s), end = u16(ends + 2 * s)
                let delta = u16(deltas + 2 * s), range = u16(offsets + 2 * s)
                guard end >= start, end != 0xFFFF || start != 0xFFFF else { continue }
                for c in start ... end {
                    var glyph: Int
                    if range == 0 { glyph = (c + delta) & 0xFFFF } else {
                        let at = offsets + 2 * s + range + 2 * (c - start)
                        glyph = u16(at)
                        if glyph != 0 { glyph = (glyph + delta) & 0xFFFF }
                    }
                    if glyph != 0 { out.insert(UInt32(c)) }
                }
            }
        }
        return out
    }

    /// Notes the faces a file embeds (name to registered family).
    static func noteEmbeddedFaces(_ faces: [String: String]) {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        embeddedFaces = Dictionary(faces.map { ($0.key.trimmingWhitespace().lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }
    private static func embeddedFamily(_ family: String) -> String? {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        return embeddedFaces.isEmpty ? nil : embeddedFaces[family.trimmingWhitespace().lowercased()]
    }
    private static func embeddedCovers(_ registered: String) -> Set<UInt32>? {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        return embeddedCoverage[registered]
    }

    /// Loads one embedded face (`word/fonts/*.odttf`, already
    /// de-obfuscated) and returns the family it is drawn as. Named by its
    /// bytes, not by the file's name for it: a file saves a SUBSET of the
    /// face (zh-e37f8d40's 仿宋_GB2312 holds 656 characters, its
    /// 楷体_GB2312 22), and two files' subsets under one name would be
    /// one family whose glyphs come from either. Loaded once per process.
    static func loadEmbedded(_ data: Data) -> String? {
        guard data.count > 12 else { return nil }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        let family = "Starling Embedded " + String(hash, radix: 16)
        declaredLock.lock()
        let loaded = loadedEmbedded.contains(family)
        declaredLock.unlock()
        if loaded { return family }
        let ok = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return family.withCString { flutter.swift_bridge.LoadFontFromList(base, data.count, $0) }
        }
        guard ok else { return nil }
        let covered = coverage(data)
        declaredLock.lock()
        loadedEmbedded.insert(family)
        if let covered { embeddedCoverage[family] = covered }
        if let line = lineMetrics(data) { embeddedLines[family] = line }
        declaredLock.unlock()
        return family
    }

    /// An embedded font part's bytes as a font: ECMA-376 part 1, 17.8.1 —
    /// the first 32 bytes are XORed with the `w:fontKey` GUID, its 32 hex
    /// digits read as 16 bytes from the last pair to the first.
    static func deobfuscate(_ data: Data, key: String) -> Data? {
        let hex = Array(key.unicodeScalars.filter { ("0" ... "9").contains($0) || ("a" ... "f").contains($0) || ("A" ... "F").contains($0) })
        guard hex.count == 32, data.count >= 32 else { return nil }
        var keyBytes: [UInt8] = []
        for i in 0 ..< 16 {
            let pair = String(String.UnicodeScalarView(hex[30 - 2 * i ..< 32 - 2 * i]))
            guard let byte = UInt8(pair, radix: 16) else { return nil }
            keyBytes.append(byte)
        }
        var out = data
        for i in 0 ..< 32 {
            let index = out.startIndex + i
            out[index] ^= keyBytes[i % 16]
        }
        return out
    }

    static func noteFontTable(_ charsets: [String: String]) {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        for (name, charset) in charsets {
            let parts = name.split(separator: ",").map { $0.trimmingWhitespace().lowercased() }
            if charset == "00", !parts.contains(where: { wordsOwn.contains($0) }) {
                declaredLatin.insert(name)
            } else {
                declaredLatin.remove(name)
            }
        }
    }

    private static func isDeclaredLatin(_ family: String) -> Bool {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        return !declaredLatin.isEmpty && declaredLatin.contains(family)
    }

    /// Whether a family name is an East Asian face: written in its own
    /// script (宋体, 標楷體, ＭＳ 明朝), or one of the Latin names those
    /// faces also go by.
    static func isEastAsianFace(_ family: String) -> Bool {
        if isDeclaredLatin(family) { return false }
        if family.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { return true }
        let n = family.trimmingWhitespace().lowercased()
        for key in ["simsun", "simhei", "kaiti", "fangsong", "yahei", "dengxian", "mingliu", "dfkai", "jhenghei",
                    "stsong", "stkaiti", "stfangsong", "stzhongsong", "stxihei", "stxinwei", "stheiti", "songti", "heiti",
                    "pingfang", "hiragino", "mincho", "ms gothic", "yu gothic", "meiryo", "malgun", "batang", "gulim", "dotum",
                    "cjk", "source han", "noto sans sc", "noto serif sc", "wenquanyi", "arial unicode", "fzs", "fzf", "fzk", "fzh", "fzx"] where n.containsSubstring(key) {
            return true
        }
        return false
    }

    /// How Word sets an East Asian face, measured from Word 16's prints
    /// (2026-10-12): its line height as a multiple of the size — Word
    /// sets these faces at 1.3 times their ascent and descent, which is
    /// 1.3 for the square ones (宋体, 黑体, 楷体, 仿宋, 細明體) and more
    /// for the tall ones — and what its Latin letters and digits are
    /// like: half an em each in the square faces, proportional in the
    /// rest, given here as the shipped face nearest in shape and the
    /// scale that brings its widths to the original's.
    private struct EastAsianFace {
        var height: Double
        var latin: String
        var latinScale: Double
        /// The stand-in's scale for digits, capitals, small letters and
        /// the rest, over `latinScale`, where one scale does not do.
        var latinClasses: [Double]? = nil
        /// The face's own widths for U+0020 to U+007E, in ems, and its
        /// bold's (`RichResolvedFace.advances`): the stand-in is set
        /// to them character by character.
        var latinAdvances: [Double]? = nil
        var latinBoldAdvances: [Double]? = nil
        /// Its kern pairs among those, and its bold's
        /// (`RichResolvedFace.kerns`).
        var latinKerns: [UInt32: Double]? = nil
        var latinBoldKerns: [UInt32: Double]? = nil
        /// Word emboldens a face that has no bold of its own, and sets
        /// each character wider: by `boldWiden` of an em, 1/48 where
        /// that is not said.
        var fakeBold: Bool
        var boldWiden: Double? = nil
        /// The baseline below the top of a single line, in ems: the
        /// face's ascent and half of what Word adds to its height.
        var baseline: Double? = nil
        /// The same two for characters with a scale of their own
        /// (`w:w`), where they differ: Word measures those by the
        /// face's OS/2 ascent and descent rather than its hhea ones.
        var scaledHeight: Double? = nil
        var scaledBaseline: Double? = nil
        /// `RichResolvedFace.symbolFamily`.
        var symbols: String? = nil
        /// The same two for the face's bold, where it is a face of its
        /// own with other metrics.
        var boldHeight: Double? = nil
        var boldBaseline: Double? = nil
    }

    // (Its Latin exactly half an em, as 宋体's is: Liberation Mono's
    // advance is 1229/2048 of its em, not 0.6, and at 5/6 every character
    // came out a thousandth of an em wide — 20 on zh-f6686f89's line
    // "…（TSG S7001-2013）…。（      ）" put the "）" 0.02pt past the
    // margin, a line down, where Word's ends on it.)
    private static let square = EastAsianFace(height: 1.3, latin: mono, latinScale: 1024.0 / 1229.0, fakeBold: true, baseline: 1.005)
    // (YaHei's bold, msyhbd.ttc, is a face of its own and a line of it
    // is taller: Word sets bold YaHei lines 1.73 ems apart — 24.21 at
    // 14pt (zh-33aa9899's body), 27.66 at 16 and 34.62 at 20 (zh-7dc3afad's
    // contents) — where its regular's are 1.715. The extra goes half
    // above, half below.)
    private static let yaHei = EastAsianFace(height: 1.715, latin: sans, latinScale: 1.07, latinClasses: [0.985, 0.92, 1.027, 0.96],
                                             latinAdvances: yaHeiAdvances, latinBoldAdvances: yaHeiBoldAdvances,
                                             latinKerns: yaHeiKerns, latinBoldKerns: yaHeiBoldKerns, fakeBold: false, baseline: 1.26,
                                             boldHeight: 1.73, boldBaseline: 1.2675)

    // Lucida Sans Unicode's own widths, U+0020 to U+007E: its lower case
    // is 5-37% wider than Arial's, its digits all 0.632, and the sans
    // stand-in set bug59058's "SEER 9 Incidence…" note on one line where
    // Word's print has two (and its last four pages a line off). The
    // 41 characters that note and the fact sheet use are the /Widths of
    // the subset Word's print of bug59058 embeds (2026-10-16), and 71 are
    // those of the subsets in PowerPoint's prints (GeomLec1, aascu 5864;
    // 2026-10-17: 18 of the estimates were out, "/" 0.32 for 0.52, "?"
    // 0.63 for 0.42, "J" 0.48 for 0.31); the rest are estimates from
    // Arial's: capitals at 0.96 of them, lower case at 1.12, other signs
    // at 1.14.
    static let lucidaSansUnicodeAdvances: [Double] = [
        0.3160, 0.3167, 0.4047, 0.6340, 0.6340, 1.0136, 0.6970, 0.2176, 0.3250, 0.3250, 0.4436, 0.7950, 0.3160, 0.5790, 0.3160,
        0.5240, 0.6320, 0.6320, 0.6320, 0.6320, 0.6320, 0.6320, 0.6320, 0.6320, 0.6320, 0.6320, 0.3160, 0.3167, 0.6657, 0.7950,
        0.6657, 0.4220, 1.1573, 0.6900, 0.5750, 0.6920, 0.7490, 0.5420, 0.5360, 0.7230, 0.7350, 0.2880, 0.3110, 0.6530, 0.5330,
        0.8610, 0.7390, 0.7770, 0.5530, 0.7467, 0.6320, 0.5390, 0.6320, 0.6930, 0.6540, 0.8550, 0.6260, 0.6230, 0.5864, 0.3167,
        0.3167, 0.3167, 0.5349, 0.6340, 0.3796, 0.5520, 0.6290, 0.5120, 0.6290, 0.5570, 0.3680, 0.6240, 0.6210, 0.2890, 0.3040,
        0.5840, 0.2890, 0.9340, 0.6210, 0.6140, 0.6290, 0.6290, 0.4090, 0.5100, 0.3740, 0.6210, 0.5180, 0.7710, 0.6130, 0.5220,
        0.5730, 0.3807, 0.2961, 0.3807, 0.6657,
    ]

    // Verdana's own widths, which its stand-in (DejaVu Sans, a few per
    // cent wider in its letters, narrower in its space) is set to: U+0020
    // to U+007E, then Latin-1, Cyrillic and the usual punctuation, read
    // from Windows' verdana.ttf and verdanab.ttf (2026-10-15).
    static let verdanaAdvances: [Double] = [
        0.3516, 0.3936, 0.4590, 0.8184, 0.6357, 1.0762, 0.7266, 0.2686, 0.4541, 0.4541, 0.6357, 0.8184, 0.3638, 0.4541, 0.3638,
        0.4541, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.4541, 0.4541, 0.8184, 0.8184,
        0.8184, 0.5454, 1.0000, 0.6836, 0.6855, 0.6982, 0.7705, 0.6323, 0.5747, 0.7754, 0.7515, 0.4209, 0.4546, 0.6929, 0.5566,
        0.8428, 0.7480, 0.7871, 0.6030, 0.7871, 0.6953, 0.6836, 0.6162, 0.7319, 0.6836, 0.9888, 0.6851, 0.6152, 0.6851, 0.4541,
        0.4541, 0.4541, 0.8184, 0.6357, 0.6357, 0.6006, 0.6230, 0.5210, 0.6230, 0.5957, 0.3516, 0.6230, 0.6328, 0.2744, 0.3442,
        0.5918, 0.2744, 0.9727, 0.6328, 0.6069, 0.6230, 0.6230, 0.4268, 0.5210, 0.3940, 0.6328, 0.5918, 0.8184, 0.5918, 0.5918,
        0.5254, 0.6348, 0.4541, 0.6348, 0.8184
    ]
    static let verdanaBoldAdvances: [Double] = [
        0.3418, 0.4023, 0.5874, 0.8672, 0.7109, 1.2720, 0.8623, 0.3320, 0.5435, 0.5435, 0.7109, 0.8672, 0.3613, 0.4800, 0.3613,
        0.6895, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.4023, 0.4023, 0.8672, 0.8672,
        0.8672, 0.6167, 0.9639, 0.7764, 0.7617, 0.7236, 0.8301, 0.6831, 0.6504, 0.8110, 0.8374, 0.5459, 0.5552, 0.7710, 0.6372,
        0.9478, 0.8467, 0.8501, 0.7329, 0.8501, 0.7822, 0.7104, 0.6816, 0.8120, 0.7637, 1.1284, 0.7637, 0.7368, 0.6919, 0.5435,
        0.6895, 0.5435, 0.8672, 0.7109, 0.7109, 0.6680, 0.6992, 0.5884, 0.6992, 0.6641, 0.4224, 0.6992, 0.7124, 0.3418, 0.4028,
        0.6709, 0.3418, 1.0581, 0.7124, 0.6865, 0.6992, 0.6992, 0.4971, 0.5933, 0.4556, 0.7124, 0.6499, 0.9795, 0.6689, 0.6509,
        0.5967, 0.7109, 0.5435, 0.7109, 0.8672
    ]
    /// Lucida Sans Unicode's dash, quotes and ellipsis, from the same
    /// prints.
    static let lucidaSansUnicodeOtherAdvances: [UInt32: Double] = [
        0x2013: 0.5000, 0x2018: 0.3160, 0x2019: 0.3160, 0x201C: 0.3740, 0x201D: 0.3740, 0x2026: 1.0000,
    ]

    static let verdanaOtherAdvances: [UInt32: Double] = [
        0x00A0: 0.3516, 0x00A1: 0.3936, 0x00A2: 0.6357, 0x00A3: 0.6357, 0x00A4: 0.6357, 0x00A5: 0.6357, 0x00A6: 0.4541, 0x00A7: 0.6357,
        0x00A8: 0.6357, 0x00A9: 1.0000, 0x00AA: 0.5454, 0x00AB: 0.6445, 0x00AC: 0.8184, 0x00AD: 0.4541, 0x00AE: 1.0000, 0x00AF: 0.6357,
        0x00B0: 0.5420, 0x00B1: 0.8184, 0x00B2: 0.5420, 0x00B3: 0.5420, 0x00B4: 0.6357, 0x00B5: 0.6416, 0x00B6: 0.6357, 0x00B7: 0.3638,
        0x00B8: 0.6357, 0x00B9: 0.5420, 0x00BA: 0.5454, 0x00BB: 0.6445, 0x00BC: 1.0000, 0x00BD: 1.0000, 0x00BE: 1.0000, 0x00BF: 0.5454,
        0x00C0: 0.6836, 0x00C1: 0.6836, 0x00C2: 0.6836, 0x00C3: 0.6836, 0x00C4: 0.6836, 0x00C5: 0.6836, 0x00C6: 0.9844, 0x00C7: 0.6982,
        0x00C8: 0.6323, 0x00C9: 0.6323, 0x00CA: 0.6323, 0x00CB: 0.6323, 0x00CC: 0.4209, 0x00CD: 0.4209, 0x00CE: 0.4209, 0x00CF: 0.4209,
        0x00D0: 0.7754, 0x00D1: 0.7480, 0x00D2: 0.7871, 0x00D3: 0.7871, 0x00D4: 0.7871, 0x00D5: 0.7871, 0x00D6: 0.7871, 0x00D7: 0.8184,
        0x00D8: 0.7871, 0x00D9: 0.7319, 0x00DA: 0.7319, 0x00DB: 0.7319, 0x00DC: 0.7319, 0x00DD: 0.6152, 0x00DE: 0.6055, 0x00DF: 0.6201,
        0x00E0: 0.6006, 0x00E1: 0.6006, 0x00E2: 0.6006, 0x00E3: 0.6006, 0x00E4: 0.6006, 0x00E5: 0.6006, 0x00E6: 0.9551, 0x00E7: 0.5210,
        0x00E8: 0.5957, 0x00E9: 0.5957, 0x00EA: 0.5957, 0x00EB: 0.5957, 0x00EC: 0.2744, 0x00ED: 0.2744, 0x00EE: 0.2744, 0x00EF: 0.2744,
        0x00F0: 0.6118, 0x00F1: 0.6328, 0x00F2: 0.6069, 0x00F3: 0.6069, 0x00F4: 0.6069, 0x00F5: 0.6069, 0x00F6: 0.6069, 0x00F7: 0.8184,
        0x00F8: 0.6069, 0x00F9: 0.6328, 0x00FA: 0.6328, 0x00FB: 0.6328, 0x00FC: 0.6328, 0x00FD: 0.5918, 0x00FE: 0.6230, 0x00FF: 0.5918,
        0x0401: 0.6323, 0x0402: 0.7925, 0x0403: 0.5664, 0x0404: 0.7007, 0x0405: 0.6836, 0x0406: 0.4209, 0x0407: 0.4209, 0x0408: 0.4546,
        0x0409: 1.1182, 0x040A: 1.1030, 0x040B: 0.8179, 0x040C: 0.6929, 0x040D: 0.7505, 0x040E: 0.6152, 0x040F: 0.7515, 0x0410: 0.6836,
        0x0411: 0.6855, 0x0412: 0.6855, 0x0413: 0.5664, 0x0414: 0.7456, 0x0415: 0.6323, 0x0416: 0.9731, 0x0417: 0.6157, 0x0418: 0.7505,
        0x0419: 0.7505, 0x041A: 0.6929, 0x041B: 0.7344, 0x041C: 0.8428, 0x041D: 0.7515, 0x041E: 0.7871, 0x041F: 0.7515, 0x0420: 0.6030,
        0x0421: 0.6982, 0x0422: 0.6162, 0x0423: 0.6152, 0x0424: 0.8188, 0x0425: 0.6851, 0x0426: 0.7612, 0x0427: 0.7119, 0x0428: 1.0303,
        0x0429: 1.0449, 0x042A: 0.7832, 0x042B: 0.9204, 0x042C: 0.6807, 0x042D: 0.7012, 0x042E: 1.0342, 0x042F: 0.7061, 0x0430: 0.6006,
        0x0431: 0.6143, 0x0432: 0.5947, 0x0433: 0.4712, 0x0434: 0.6216, 0x0435: 0.5957, 0x0436: 0.7979, 0x0437: 0.5244, 0x0438: 0.6401,
        0x0439: 0.6401, 0x043A: 0.5918, 0x043B: 0.6206, 0x043C: 0.6963, 0x043D: 0.6372, 0x043E: 0.6069, 0x043F: 0.6372, 0x0440: 0.6230,
        0x0441: 0.5342, 0x0442: 0.4961, 0x0443: 0.5918, 0x0444: 0.8408, 0x0445: 0.5918, 0x0446: 0.6445, 0x0447: 0.6055, 0x0448: 0.8760,
        0x0449: 0.8877, 0x044A: 0.6406, 0x044B: 0.7944, 0x044C: 0.5708, 0x044D: 0.5469, 0x044E: 0.8389, 0x044F: 0.5996, 0x0451: 0.5957,
        0x0452: 0.6328, 0x0453: 0.4712, 0x0454: 0.5469, 0x0455: 0.5210, 0x0456: 0.2744, 0x0457: 0.2744, 0x0458: 0.3442, 0x0459: 0.9141,
        0x045A: 0.9141, 0x045B: 0.6328, 0x045C: 0.5918, 0x045D: 0.6401, 0x045E: 0.5918, 0x045F: 0.6372, 0x0490: 0.5664, 0x0491: 0.4712,
        0x2013: 0.6357, 0x2014: 1.0000, 0x2018: 0.2686, 0x2019: 0.2686, 0x201A: 0.2686, 0x201C: 0.4590, 0x201D: 0.4590, 0x201E: 0.4590,
        0x2022: 0.5454, 0x2026: 0.8184, 0x20AC: 0.6357, 0x2116: 1.1719, 0x2122: 0.9766
    ]
    static let verdanaBoldOtherAdvances: [UInt32: Double] = [
        0x00A0: 0.3418, 0x00A1: 0.4023, 0x00A2: 0.7109, 0x00A3: 0.7109, 0x00A4: 0.7109, 0x00A5: 0.7109, 0x00A6: 0.5435, 0x00A7: 0.7109,
        0x00A8: 0.7109, 0x00A9: 0.9639, 0x00AA: 0.5977, 0x00AB: 0.8496, 0x00AC: 0.8672, 0x00AD: 0.4800, 0x00AE: 0.9639, 0x00AF: 0.7109,
        0x00B0: 0.5874, 0x00B1: 0.8672, 0x00B2: 0.5977, 0x00B3: 0.5977, 0x00B4: 0.7109, 0x00B5: 0.7212, 0x00B6: 0.7109, 0x00B7: 0.3613,
        0x00B8: 0.7109, 0x00B9: 0.5977, 0x00BA: 0.5977, 0x00BB: 0.8496, 0x00BC: 1.1816, 0x00BD: 1.1816, 0x00BE: 1.1816, 0x00BF: 0.6167,
        0x00C0: 0.7764, 0x00C1: 0.7764, 0x00C2: 0.7764, 0x00C3: 0.7764, 0x00C4: 0.7764, 0x00C5: 0.7764, 0x00C6: 1.0938, 0x00C7: 0.7236,
        0x00C8: 0.6831, 0x00C9: 0.6831, 0x00CA: 0.6831, 0x00CB: 0.6831, 0x00CC: 0.5459, 0x00CD: 0.5459, 0x00CE: 0.5459, 0x00CF: 0.5459,
        0x00D0: 0.8301, 0x00D1: 0.8467, 0x00D2: 0.8501, 0x00D3: 0.8501, 0x00D4: 0.8501, 0x00D5: 0.8501, 0x00D6: 0.8501, 0x00D7: 0.8672,
        0x00D8: 0.8501, 0x00D9: 0.8120, 0x00DA: 0.8120, 0x00DB: 0.8120, 0x00DC: 0.8120, 0x00DD: 0.7368, 0x00DE: 0.7349, 0x00DF: 0.7129,
        0x00E0: 0.6680, 0x00E1: 0.6680, 0x00E2: 0.6680, 0x00E3: 0.6680, 0x00E4: 0.6680, 0x00E5: 0.6680, 0x00E6: 1.0181, 0x00E7: 0.5884,
        0x00E8: 0.6641, 0x00E9: 0.6641, 0x00EA: 0.6641, 0x00EB: 0.6641, 0x00EC: 0.3418, 0x00ED: 0.3418, 0x00EE: 0.3418, 0x00EF: 0.3418,
        0x00F0: 0.6792, 0x00F1: 0.7124, 0x00F2: 0.6865, 0x00F3: 0.6865, 0x00F4: 0.6865, 0x00F5: 0.6865, 0x00F6: 0.6865, 0x00F7: 0.8672,
        0x00F8: 0.6865, 0x00F9: 0.7124, 0x00FA: 0.7124, 0x00FB: 0.7124, 0x00FC: 0.7124, 0x00FD: 0.6509, 0x00FE: 0.6992, 0x00FF: 0.6509,
        0x0401: 0.6831, 0x0402: 0.9106, 0x0403: 0.6372, 0x0404: 0.7417, 0x0405: 0.7104, 0x0406: 0.5459, 0x0407: 0.5459, 0x0408: 0.5552,
        0x0409: 1.2222, 0x040A: 1.2144, 0x040B: 0.9360, 0x040C: 0.7710, 0x040D: 0.8457, 0x040E: 0.7368, 0x040F: 0.8374, 0x0410: 0.7764,
        0x0411: 0.7578, 0x0412: 0.7617, 0x0413: 0.6372, 0x0414: 0.8413, 0x0415: 0.6831, 0x0416: 1.1152, 0x0417: 0.7065, 0x0418: 0.8457,
        0x0419: 0.8457, 0x041A: 0.7710, 0x041B: 0.8452, 0x041C: 0.9478, 0x041D: 0.8374, 0x041E: 0.8501, 0x041F: 0.8374, 0x0420: 0.7329,
        0x0421: 0.7236, 0x0422: 0.6816, 0x0423: 0.7368, 0x0424: 0.9521, 0x0425: 0.7637, 0x0426: 0.8496, 0x0427: 0.7871, 0x0428: 1.1636,
        0x0429: 1.1772, 0x042A: 0.9072, 0x042B: 1.0625, 0x042C: 0.7578, 0x042D: 0.7417, 0x042E: 1.1953, 0x042F: 0.7949, 0x0430: 0.6680,
        0x0431: 0.6968, 0x0432: 0.6772, 0x0433: 0.5312, 0x0434: 0.6914, 0x0435: 0.6641, 0x0436: 0.9990, 0x0437: 0.5879, 0x0438: 0.7202,
        0x0439: 0.7202, 0x043A: 0.6709, 0x043B: 0.7095, 0x043C: 0.8301, 0x043D: 0.7197, 0x043E: 0.6865, 0x043F: 0.7197, 0x0440: 0.6992,
        0x0441: 0.5981, 0x0442: 0.5352, 0x0443: 0.6509, 0x0444: 0.9658, 0x0445: 0.6689, 0x0446: 0.7290, 0x0447: 0.6841, 0x0448: 1.0024,
        0x0449: 1.0127, 0x044A: 0.7432, 0x044B: 0.9370, 0x044C: 0.6494, 0x044D: 0.6060, 0x044E: 0.9941, 0x044F: 0.6816, 0x0451: 0.6641,
        0x0452: 0.7124, 0x0453: 0.5312, 0x0454: 0.6055, 0x0455: 0.5933, 0x0456: 0.3418, 0x0457: 0.3418, 0x0458: 0.4028, 0x0459: 1.0122,
        0x045A: 1.0195, 0x045B: 0.7124, 0x045C: 0.6709, 0x045D: 0.7202, 0x045E: 0.6509, 0x045F: 0.7197, 0x0490: 0.6372, 0x0491: 0.5312,
        0x2013: 0.7109, 0x2014: 1.0000, 0x2018: 0.3320, 0x2019: 0.3320, 0x201A: 0.3320, 0x201C: 0.5874, 0x201D: 0.5874, 0x201E: 0.5874,
        0x2022: 0.7109, 0x2026: 1.0488, 0x20AC: 0.7109, 0x2116: 1.2939, 0x2122: 0.9639
    ]

    // The horizontal advances of U+0020 to U+007E in the faces whose
    // Latin is drawn by a stand-in, in ems, read from the faces' own
    // tables (2026-10-12): what Word breaks a line by.
    /// Arial Black's widths for U+0020 to U+007E, in ems (Word's
    /// DFonts ariblk.ttf).
    /// Faces Word sets Thai in, narrow ones all: see `cordiaNewAdvances`.
    static let thaiWordFaces: Set<String> = ["th sarabun new", "th sarabunpsk", "browallia new", "browalliaupc", "cordia new", "cordiaupc",
                                             "angsana new", "angsanaupc"]
    /// Cordia New's widths for U+0020 to U+007E, in ems, and its bold's
    /// (the face Word for Mac carries, DFonts cordia.ttc).
    static let cordiaNewAdvances: [Double] = [
        0.1821, 0.2183, 0.1821, 0.3645, 0.3645, 0.5825, 0.437, 0.1455, 0.2183, 0.2183, 0.2549, 0.4326, 0.1821, 0.2183, 0.1821,
        0.1821, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.1821, 0.1821, 0.4326, 0.4326,
        0.4326, 0.3276, 0.5239, 0.437, 0.437, 0.4731, 0.4731, 0.4001, 0.3645, 0.5095, 0.4731, 0.1821, 0.3276, 0.437, 0.3645,
        0.5457, 0.4731, 0.5095, 0.4001, 0.5095, 0.437, 0.4001, 0.3645, 0.4731, 0.4001, 0.5825, 0.4001, 0.4001, 0.4001, 0.2183,
        0.1821, 0.2183, 0.4326, 0.3276, 0.2183, 0.3645, 0.4001, 0.3645, 0.4001, 0.3645, 0.1821, 0.4001, 0.3645, 0.1455, 0.1455,
        0.3276, 0.1455, 0.5457, 0.3645, 0.3645, 0.4001, 0.4001, 0.2183, 0.3276, 0.1821, 0.3645, 0.3276, 0.4731, 0.3276, 0.3276,
        0.3276, 0.2183, 0.1455, 0.2183, 0.4326,
    ]
    static let cordiaNewBoldAdvances: [Double] = [
        0.2241, 0.1821, 0.2327, 0.3645, 0.3645, 0.5825, 0.437, 0.125, 0.2183, 0.2183, 0.2549, 0.3826, 0.1821, 0.2183, 0.1821,
        0.1821, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.3645, 0.1821, 0.1821, 0.3826, 0.3826,
        0.3826, 0.3645, 0.665, 0.437, 0.437, 0.4731, 0.4731, 0.437, 0.4001, 0.5095, 0.4731, 0.1821, 0.3276, 0.437, 0.3645,
        0.5457, 0.4731, 0.5095, 0.437, 0.5095, 0.4731, 0.437, 0.4001, 0.4731, 0.437, 0.6184, 0.437, 0.437, 0.4001, 0.1821,
        0.1821, 0.1821, 0.3074, 0.3645, 0.2183, 0.3645, 0.3645, 0.3276, 0.3645, 0.3645, 0.1821, 0.3645, 0.3645, 0.1455, 0.1455,
        0.3276, 0.1455, 0.5457, 0.3645, 0.3645, 0.3645, 0.3645, 0.2183, 0.3276, 0.1821, 0.3645, 0.3276, 0.4731, 0.3276, 0.3276,
        0.3276, 0.2188, 0.1702, 0.2188, 0.3826,
    ]
    static let arialBlackAdvances: [Double] = [
        0.3335, 0.333, 0.5, 0.6602, 0.667, 1, 0.8892, 0.2778, 0.3892, 0.3892, 0.5562, 0.6602, 0.333, 0.333, 0.333,
        0.2778, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.333, 0.333, 0.6602, 0.6602,
        0.6602, 0.6108, 0.7402, 0.7778, 0.7778, 0.7778, 0.7778, 0.7222, 0.667, 0.833, 0.833, 0.3892, 0.667, 0.833, 0.667,
        0.9438, 0.833, 0.833, 0.7222, 0.833, 0.7778, 0.7222, 0.7222, 0.833, 0.7778, 1, 0.7778, 0.7778, 0.7222, 0.3892,
        0.2778, 0.3892, 0.6602, 0.5, 0.333, 0.667, 0.667, 0.667, 0.667, 0.667, 0.3892, 0.667, 0.667, 0.333, 0.333,
        0.667, 0.333, 1, 0.667, 0.667, 0.667, 0.667, 0.4438, 0.6108, 0.4438, 0.667, 0.6108, 0.9438, 0.667, 0.6108,
        0.5562, 0.3892, 0.2778, 0.3892, 0.6602,
    ]
    private static let yaHeiAdvances: [Double] = [
        0.2959, 0.3125, 0.4355, 0.6382, 0.5864, 0.8896, 0.8701, 0.2563, 0.334, 0.334, 0.4551, 0.7417, 0.2407, 0.4326, 0.2407,
        0.4272, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.2407, 0.2407, 0.7417, 0.7417,
        0.7417, 0.4829, 1.0312, 0.7036, 0.6274, 0.6689, 0.7617, 0.5498, 0.5312, 0.7437, 0.7734, 0.2939, 0.396, 0.6348, 0.5132,
        0.9771, 0.813, 0.8149, 0.6118, 0.8149, 0.6528, 0.5771, 0.5732, 0.7466, 0.6763, 1.0176, 0.645, 0.6035, 0.6201, 0.334,
        0.416, 0.334, 0.7417, 0.4482, 0.2949, 0.5527, 0.6387, 0.5015, 0.6396, 0.5674, 0.3467, 0.6396, 0.6157, 0.2661, 0.2671,
        0.5444, 0.2661, 0.937, 0.6162, 0.6357, 0.6387, 0.6396, 0.3818, 0.4629, 0.3726, 0.6162, 0.5249, 0.7896, 0.5068, 0.5293,
        0.4917, 0.334, 0.269, 0.334, 0.7417
    ]
    private static let yaHeiBoldAdvances: [Double] = [
        0.2979, 0.3486, 0.521, 0.6401, 0.6167, 0.9312, 0.9111, 0.3081, 0.3896, 0.3896, 0.4873, 0.7612, 0.2856, 0.4365, 0.2856,
        0.4727, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.2856, 0.2856, 0.7612, 0.7612,
        0.7612, 0.4741, 1.0298, 0.752, 0.6836, 0.6733, 0.7915, 0.5718, 0.5581, 0.7651, 0.8213, 0.3354, 0.4702, 0.6929, 0.5469,
        1.0283, 0.8481, 0.8184, 0.6572, 0.8184, 0.6982, 0.6016, 0.6255, 0.7764, 0.7148, 1.0762, 0.7002, 0.6484, 0.6504,
        0.3896, 0.4644, 0.3896, 0.7612, 0.4482, 0.3335, 0.5776, 0.666, 0.5166, 0.6646, 0.582, 0.4053, 0.6646, 0.6455, 0.2959,
        0.3018, 0.5962, 0.2959, 0.9819, 0.6479, 0.6572, 0.666, 0.6646, 0.4238, 0.4937, 0.4141, 0.6479, 0.5771, 0.8516, 0.585,
        0.5742, 0.5137, 0.3896, 0.3413, 0.3896, 0.7612
    ]
    private static let yaHeiUIAdvances: [Double] = [
        0.2959, 0.3125, 0.4355, 0.6382, 0.5864, 0.8896, 0.8701, 0.2563, 0.334, 0.334, 0.4551, 0.7417, 0.2407, 0.4326, 0.2407,
        0.4272, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.5864, 0.2407, 0.2407, 0.7417, 0.7417,
        0.7417, 0.4829, 1.0312, 0.7036, 0.6274, 0.6689, 0.7617, 0.5498, 0.5312, 0.7437, 0.7734, 0.2939, 0.396, 0.6348, 0.5132,
        0.9771, 0.813, 0.8149, 0.6118, 0.8149, 0.6528, 0.5771, 0.5732, 0.7466, 0.6763, 1.0176, 0.645, 0.6035, 0.6201, 0.334,
        0.416, 0.334, 0.7417, 0.4482, 0.2949, 0.5527, 0.6387, 0.5015, 0.6396, 0.5674, 0.3467, 0.6396, 0.6157, 0.2661, 0.2671,
        0.5444, 0.2661, 0.937, 0.6162, 0.6357, 0.6387, 0.6396, 0.3818, 0.4629, 0.3726, 0.6162, 0.5249, 0.7896, 0.5068, 0.5293,
        0.4917, 0.334, 0.269, 0.334, 0.7417
    ]
    private static let yaHeiUIBoldAdvances: [Double] = [
        0.2979, 0.3486, 0.521, 0.6401, 0.6167, 0.9312, 0.9111, 0.3081, 0.3896, 0.3896, 0.4873, 0.7612, 0.2856, 0.4365, 0.2856,
        0.4727, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.6167, 0.2856, 0.2856, 0.7612, 0.7612,
        0.7612, 0.4741, 1.0298, 0.752, 0.6836, 0.6733, 0.7915, 0.5718, 0.5581, 0.7651, 0.8213, 0.3354, 0.4702, 0.6929, 0.5469,
        1.0283, 0.8481, 0.8184, 0.6572, 0.8184, 0.6982, 0.6016, 0.6255, 0.7764, 0.7148, 1.0762, 0.7002, 0.6484, 0.6504,
        0.3896, 0.4644, 0.3896, 0.7612, 0.4482, 0.3335, 0.5776, 0.666, 0.5166, 0.6646, 0.582, 0.4053, 0.6646, 0.6455, 0.2959,
        0.3018, 0.5962, 0.2959, 0.9819, 0.6479, 0.6572, 0.666, 0.6646, 0.4238, 0.4937, 0.4141, 0.6479, 0.5771, 0.8516, 0.585,
        0.5742, 0.5137, 0.3896, 0.3413, 0.3896, 0.7612
    ]
    // YaHei's kern pairs among U+0020 to U+007E, in ems, keyed first << 8 |
    // second (`RichResolvedFace.kerns`), from msyh.ttc's `kern` table as
    // Word for Mac carries it; YaHei UI has the same pairs. Word's prints
    // set them where the run kerns: zh-d89c3840's "TC" 8.4pt at 16, T's
    // advance 9.17 less the pair's 0.77, and 23 of the corpus's 33 pairs
    // over 0.3pt the same way (the rest in runs that do not kern).
    private static let yaHeiKerns: [UInt32: Double] = [
        0x2272: -0.0269, 0x2273: -0.0347, 0x2772: -0.0269, 0x2773: -0.0347, 0x286A: 0.123, 0x2A41: -0.0874, 0x2A4A: -0.0811,
        0x2A63: -0.0537, 0x2A64: -0.0537, 0x2A65: -0.0537, 0x2A67: -0.0537, 0x2A6F: -0.0537, 0x2A71: -0.0537, 0x412A: -0.0679,
        0x412C: 0.0356, 0x413B: 0.0356, 0x4143: -0.0142, 0x4147: -0.0142, 0x414A: 0.0498, 0x414F: -0.0142, 0x4154: -0.0776,
        0x4155: -0.0142, 0x4156: -0.0615, 0x4157: -0.0391, 0x4159: -0.082, 0x415A: 0.0312, 0x4174: -0.0142, 0x4176: -0.0225,
        0x4177: -0.0142, 0x4179: -0.0195, 0x4254: -0.0483, 0x4259: -0.0347, 0x433F: 0.001, 0x4343: -0.0288, 0x4347: -0.0288,
        0x434F: -0.0142, 0x4351: -0.0288, 0x442C: -0.0679, 0x442E: -0.0679, 0x4441: -0.0176, 0x4454: -0.0483, 0x4458: -0.0278,
        0x445A: -0.0259, 0x4541: 0.0054, 0x454A: 0.0356, 0x4554: 0.002, 0x4557: 0.0151, 0x4558: 0.0044, 0x462C: -0.0811,
        0x462E: -0.0811, 0x4641: -0.0703, 0x464A: -0.0347, 0x4653: -0.0142, 0x4654: 0.0073, 0x4661: -0.04, 0x4666: 0.0054,
        0x4754: -0.0259, 0x4756: -0.0142, 0x4779: -0.0142, 0x4A2C: -0.0537, 0x4A2E: -0.0537, 0x4A41: -0.0195, 0x4A4A: -0.0347,
        0x4A61: -0.0142, 0x4B2C: 0.0205, 0x4B3B: 0.0205, 0x4B43: -0.0474, 0x4B47: -0.0474, 0x4B4A: 0.0474, 0x4B4F: -0.0474,
        0x4B51: -0.0474, 0x4B58: 0.0195, 0x4B5A: 0.0205, 0x4B63: -0.0142, 0x4B64: -0.0142, 0x4B65: -0.0142, 0x4B67: -0.0142,
        0x4B6F: -0.0142, 0x4B71: -0.0142, 0x4B74: -0.0249, 0x4B76: -0.0391, 0x4B77: -0.0278, 0x4B79: -0.0483, 0x4C2A: -0.1094,
        0x4C3F: -0.0537, 0x4C41: 0.0312, 0x4C43: -0.0347, 0x4C47: -0.0347, 0x4C4A: 0.0527, 0x4C4F: -0.0371, 0x4C51: -0.0371,
        0x4C54: -0.0596, 0x4C55: -0.0151, 0x4C56: -0.0615, 0x4C57: -0.0259, 0x4C59: -0.0679, 0x4C5A: 0.0312, 0x4C74: -0.0142,
        0x4C76: -0.0537, 0x4C77: -0.0347, 0x4C79: -0.04, 0x4F2C: -0.0483, 0x4F2E: -0.0483, 0x4F41: -0.0142, 0x4F4A: -0.0054,
        0x4F54: -0.0483, 0x4F58: -0.0195, 0x4F59: -0.0132, 0x4F5A: -0.0259, 0x502C: -0.1719, 0x502E: -0.1719, 0x5041: -0.0835,
        0x5047: -0.0054, 0x504A: -0.0679, 0x5057: 0.0205, 0x5058: -0.0322, 0x5061: -0.0347, 0x5063: -0.04, 0x5064: -0.04,
        0x5065: -0.04, 0x5067: -0.04, 0x506F: -0.04, 0x5071: -0.0391, 0x512C: -0.0483, 0x512E: -0.0679, 0x5141: -0.0142,
        0x5154: -0.0483, 0x5158: -0.0195, 0x5159: -0.0054, 0x515A: -0.0259, 0x523B: 0.0435, 0x5243: -0.0151, 0x5247: -0.0151,
        0x524A: 0.0303, 0x524F: -0.0107, 0x5251: -0.0107, 0x5254: -0.0278, 0x5259: -0.0205, 0x5263: -0.0278, 0x5264: -0.0278,
        0x5265: -0.0303, 0x5267: -0.0303, 0x526F: -0.0312, 0x5271: -0.0278, 0x5374: -0.0347, 0x5376: -0.0259, 0x5377: -0.0142,
        0x5379: -0.0249, 0x542C: -0.0679, 0x542E: -0.0947, 0x543A: -0.0122, 0x543B: -0.0122, 0x5441: -0.0811, 0x5443: -0.0483,
        0x5447: -0.0483, 0x544A: -0.0596, 0x544F: -0.0483, 0x5451: -0.0483, 0x5454: 0.0205, 0x5456: 0.0225, 0x5457: 0.0205,
        0x5458: -0.0029, 0x5459: 0.0151, 0x5461: -0.1143, 0x5463: -0.1113, 0x5464: -0.1113, 0x5465: -0.1113, 0x5466: -0.0508,
        0x5467: -0.1113, 0x546D: -0.0938, 0x546E: -0.0938, 0x546F: -0.1113, 0x5470: -0.0938, 0x5471: -0.1113, 0x5472: -0.0938,
        0x5473: -0.0811, 0x5475: -0.0938, 0x5476: -0.0537, 0x5477: -0.0596, 0x5478: -0.0947, 0x5479: -0.0596, 0x547A: -0.0679,
        0x5541: -0.0215, 0x562C: -0.1079, 0x562E: -0.1206, 0x5641: -0.0615, 0x5643: -0.0225, 0x5647: -0.0225, 0x564A: -0.0371,
        0x564F: -0.0063, 0x5651: -0.0225, 0x5653: -0.0142, 0x5654: 0.0205, 0x5661: -0.0776, 0x5663: -0.0679, 0x5664: -0.0679,
        0x5665: -0.0679, 0x5667: -0.0679, 0x566D: -0.04, 0x566E: -0.04, 0x566F: -0.0679, 0x5670: -0.04, 0x5671: -0.0679,
        0x5672: -0.04, 0x5673: -0.0347, 0x5675: -0.04, 0x572C: -0.0615, 0x572E: -0.0679, 0x5741: -0.0391, 0x5754: 0.0205,
        0x5761: -0.04, 0x5763: -0.0259, 0x5764: -0.0259, 0x5765: -0.0259, 0x5767: -0.0259, 0x576F: -0.0259, 0x5771: -0.0259,
        0x582C: 0.0356, 0x582E: 0.0303, 0x583B: 0.0435, 0x5843: -0.0122, 0x5847: -0.0122, 0x584A: 0.0508, 0x584F: -0.0122,
        0x5851: -0.0122, 0x5854: 0.0176, 0x592C: -0.0928, 0x592E: -0.103, 0x5941: -0.0835, 0x5943: -0.0239, 0x5947: -0.0239,
        0x594A: -0.0347, 0x594F: -0.0239, 0x5951: -0.0239, 0x5953: -0.0142, 0x5954: 0.0205, 0x5961: -0.105, 0x5963: -0.0947,
        0x5964: -0.0947, 0x5965: -0.0947, 0x5966: -0.0142, 0x5967: -0.0947, 0x596D: -0.0742, 0x596E: -0.0742, 0x596F: -0.0947,
        0x5970: -0.0742, 0x5971: -0.0947, 0x5972: -0.0742, 0x5973: -0.0703, 0x5975: -0.0742, 0x5A4A: 0.0435, 0x5A54: 0.0205,
        0x5A79: -0.0278, 0x5B6A: 0.123, 0x6261: -0.0142, 0x6266: -0.0054, 0x6278: -0.0132, 0x634A: 0.0371, 0x6354: -0.0537,
        0x6359: -0.04, 0x6522: -0.0547, 0x6527: -0.0547, 0x6629: 0.0742, 0x662C: -0.0679, 0x662D: -0.0537, 0x662E: -0.0679,
        0x663A: 0.0435, 0x663B: 0.0435, 0x663F: 0.0347, 0x665D: 0.0742, 0x6662: 0.0093, 0x6668: 0.0093, 0x6674: 0.0195,
        0x6676: 0.0205, 0x6677: 0.0205, 0x6678: 0.0093, 0x6679: 0.0176, 0x667D: 0.0435, 0x676A: 0.0249, 0x6A6A: 0.0186,
        0x6B2C: 0.0435, 0x6B2D: -0.0732, 0x6B2E: 0.0435, 0x6B3A: 0.0435, 0x6B3B: 0.0435, 0x6B63: -0.0215, 0x6B64: -0.0142,
        0x6B65: -0.0215, 0x6B67: -0.0215, 0x6B6F: -0.0215, 0x6B71: -0.0142, 0x6B74: -0.0083, 0x6E22: -0.0547, 0x6E27: -0.0547,
        0x6F22: -0.0767, 0x6F27: -0.0767, 0x6F61: -0.0142, 0x6F66: -0.0195, 0x6F78: -0.0132, 0x7061: -0.0142, 0x7066: -0.0195,
        0x7078: -0.0132, 0x716A: 0.0537, 0x722C: -0.0835, 0x722D: -0.0679, 0x722E: -0.0898, 0x723A: 0.0435, 0x723B: 0.0435,
        0x7263: -0.0142, 0x7264: -0.0142, 0x7265: -0.0142, 0x7266: 0.0205, 0x7267: -0.0142, 0x726D: -0.002, 0x726E: -0.002,
        0x726F: -0.0142, 0x7271: -0.0142, 0x7273: 0.0073, 0x7274: 0.0312, 0x7276: 0.0435, 0x7277: 0.0435, 0x7278: 0.0312,
        0x7279: 0.0435, 0x727A: 0.0205, 0x742D: -0.0596, 0x743F: -0.0278, 0x7463: -0.0142, 0x7464: -0.0142, 0x7465: -0.0083,
        0x7467: -0.0083, 0x746F: -0.0083, 0x7471: -0.0083, 0x7478: 0.0151, 0x7522: -0.0347, 0x7527: -0.0347, 0x762C: -0.0615,
        0x762E: -0.0679, 0x7661: -0.0195, 0x7663: -0.0063, 0x7664: -0.0083, 0x7665: -0.0063, 0x7667: -0.0063, 0x766F: -0.0063,
        0x7671: -0.0083, 0x772C: -0.0474, 0x772E: -0.0537, 0x7763: -0.0029, 0x7764: -0.0054, 0x7765: -0.0054, 0x7767: -0.0029,
        0x776F: -0.0029, 0x7771: -0.0054, 0x7863: -0.0083, 0x7864: -0.0083, 0x7865: -0.0083, 0x7867: -0.0083, 0x786F: -0.0083,
        0x7871: -0.0083, 0x7922: 0.0151, 0x7927: 0.0151, 0x792C: -0.0537, 0x792E: -0.0669, 0x793F: -0.04, 0x7963: -0.0054,
        0x7964: -0.0054, 0x7965: -0.0054, 0x7966: 0.002, 0x7967: -0.0054, 0x796F: -0.0054, 0x7971: -0.0054, 0x7974: 0.0029,
        0x7B6A: 0.1069,
    ]
    // … its bold's,
    private static let yaHeiBoldKerns: [UInt32: Double] = [
        0x2272: -0.0215, 0x2273: -0.0278, 0x2772: -0.0317, 0x2773: -0.0522, 0x286A: 0.1025, 0x2A41: -0.0718, 0x2A4A: -0.0669,
        0x2A63: -0.0444, 0x2A64: -0.0444, 0x2A65: -0.0444, 0x2A67: -0.0444, 0x2A6F: -0.0444, 0x2A71: -0.0444, 0x412A: -0.0654,
        0x412C: 0.0312, 0x413B: 0.0312, 0x4143: -0.0161, 0x4147: -0.0117, 0x414A: 0.042, 0x414F: -0.0161, 0x4154: -0.0757,
        0x4155: -0.0186, 0x4156: -0.0601, 0x4157: -0.0356, 0x4159: -0.0811, 0x415A: 0.0142, 0x4174: -0.02, 0x4176: -0.0239,
        0x4177: -0.0161, 0x4179: -0.021, 0x4254: -0.0283, 0x4259: -0.0278, 0x433F: 0.0107, 0x4343: -0.0317, 0x4347: -0.0317,
        0x434F: -0.0132, 0x4351: -0.0244, 0x442C: -0.0557, 0x442E: -0.0557, 0x4441: -0.0161, 0x4454: -0.0391, 0x4458: -0.0317,
        0x445A: -0.0215, 0x4541: 0.0142, 0x454A: 0.0269, 0x4554: 0.0078, 0x4556: 0.0044, 0x4557: 0.0205, 0x4558: 0.019,
        0x462C: -0.0757, 0x462E: -0.0757, 0x4641: -0.0601, 0x464A: -0.0278, 0x4653: -0.0117, 0x4654: 0.0127, 0x4661: -0.0332,
        0x4666: 0.0083, 0x4754: -0.0215, 0x4756: -0.0117, 0x4779: -0.0117, 0x4A2C: -0.0444, 0x4A2E: -0.0444, 0x4A41: -0.0308,
        0x4A4A: -0.0278, 0x4A61: -0.0117, 0x4B2C: 0.0308, 0x4B3B: 0.0308, 0x4B3F: 0.0107, 0x4B43: -0.0327, 0x4B47: -0.0327,
        0x4B4A: 0.0327, 0x4B4F: -0.0327, 0x4B51: -0.0327, 0x4B54: 0.0044, 0x4B58: 0.021, 0x4B5A: 0.021, 0x4B63: -0.0117,
        0x4B64: -0.0117, 0x4B65: -0.0117, 0x4B67: -0.0117, 0x4B6F: -0.0117, 0x4B71: -0.0117, 0x4B74: -0.0269, 0x4B76: -0.0381,
        0x4B77: -0.0269, 0x4B79: -0.0454, 0x4C2A: -0.1079, 0x4C3F: -0.0444, 0x4C41: 0.0249, 0x4C43: -0.0278, 0x4C47: -0.0278,
        0x4C4A: 0.0322, 0x4C4F: -0.0278, 0x4C51: -0.0278, 0x4C54: -0.0698, 0x4C55: -0.0205, 0x4C56: -0.062, 0x4C57: -0.0366,
        0x4C59: -0.0762, 0x4C5A: 0.0308, 0x4C74: -0.0117, 0x4C76: -0.0483, 0x4C77: -0.0327, 0x4C79: -0.0381, 0x4F2C: -0.0537,
        0x4F2E: -0.0425, 0x4F41: -0.0161, 0x4F4A: -0.0107, 0x4F54: -0.0435, 0x4F58: -0.0259, 0x4F59: -0.02, 0x4F5A: -0.0215,
        0x502C: -0.1836, 0x502E: -0.1631, 0x5041: -0.0659, 0x5047: 0.0039, 0x504A: -0.0703, 0x5057: 0.019, 0x5058: -0.0249,
        0x5061: -0.0278, 0x5063: -0.0332, 0x5064: -0.0332, 0x5065: -0.0332, 0x5067: -0.0332, 0x506F: -0.0332, 0x5071: -0.0332,
        0x512C: -0.0425, 0x512E: -0.0449, 0x5141: -0.0117, 0x5154: -0.0435, 0x5158: -0.021, 0x5159: -0.0146, 0x515A: -0.0215,
        0x523B: 0.043, 0x5243: -0.0117, 0x5247: -0.0117, 0x524A: 0.0264, 0x524F: -0.0112, 0x5251: -0.0112, 0x5254: -0.022,
        0x5259: -0.0122, 0x5263: -0.0269, 0x5264: -0.0269, 0x5265: -0.0273, 0x5267: -0.0273, 0x526F: -0.0273, 0x5271: -0.0269,
        0x5374: -0.0278, 0x5376: -0.0215, 0x5377: -0.0117, 0x5379: -0.0269, 0x542C: -0.0762, 0x542E: -0.0977, 0x543A: -0.0093,
        0x543B: -0.0093, 0x5441: -0.0757, 0x5443: -0.0391, 0x5447: -0.0391, 0x544A: -0.0698, 0x544F: -0.041, 0x5451: -0.041,
        0x5454: 0.021, 0x5456: 0.0298, 0x5457: 0.021, 0x5458: -0.002, 0x5459: 0.0205, 0x5461: -0.0942, 0x5463: -0.0986,
        0x5464: -0.0986, 0x5465: -0.0986, 0x5466: -0.0439, 0x5467: -0.0986, 0x546D: -0.0767, 0x546E: -0.0767, 0x546F: -0.0986,
        0x5470: -0.0718, 0x5471: -0.0986, 0x5472: -0.0825, 0x5473: -0.0811, 0x5475: -0.0767, 0x5476: -0.0444, 0x5477: -0.0493,
        0x5478: -0.0776, 0x5479: -0.0493, 0x547A: -0.0449, 0x5541: -0.0234, 0x554A: -0.0176, 0x562C: -0.1079, 0x562E: -0.1094,
        0x563A: -0.0186, 0x563B: -0.0186, 0x563F: 0.0068, 0x5641: -0.0566, 0x5643: -0.021, 0x5647: -0.021, 0x564A: -0.0581,
        0x564F: -0.0024, 0x5651: -0.0142, 0x5653: -0.0117, 0x5654: 0.021, 0x5661: -0.0806, 0x5663: -0.0698, 0x5664: -0.0698,
        0x5665: -0.0698, 0x5667: -0.0654, 0x566D: -0.0381, 0x566E: -0.0332, 0x566F: -0.0698, 0x5670: -0.0381, 0x5671: -0.0698,
        0x5672: -0.0381, 0x5673: -0.0405, 0x5675: -0.0303, 0x572C: -0.0645, 0x572E: -0.0654, 0x573A: -0.0098, 0x573B: -0.0098,
        0x5741: -0.0381, 0x5754: 0.0156, 0x5761: -0.0425, 0x5763: -0.0283, 0x5764: -0.0283, 0x5765: -0.0283, 0x5767: -0.0283,
        0x576F: -0.0283, 0x5771: -0.0215, 0x582C: 0.0312, 0x582E: 0.0308, 0x583B: 0.0322, 0x5843: -0.0156, 0x5847: -0.0156,
        0x584A: 0.0376, 0x584F: -0.0156, 0x5851: -0.0156, 0x5854: 0.0205, 0x592C: -0.1172, 0x592E: -0.1182, 0x5941: -0.0811,
        0x5943: -0.0264, 0x5947: -0.0264, 0x594A: -0.0581, 0x594F: -0.0264, 0x5951: -0.0264, 0x5953: -0.0117, 0x5954: 0.021,
        0x5961: -0.0981, 0x5963: -0.0972, 0x5964: -0.0972, 0x5965: -0.0972, 0x5966: -0.0161, 0x5967: -0.0972, 0x596D: -0.0703,
        0x596E: -0.0703, 0x596F: -0.0972, 0x5970: -0.0723, 0x5971: -0.0972, 0x5972: -0.0703, 0x5973: -0.061, 0x5975: -0.0703,
        0x5A4A: 0.0278, 0x5A54: 0.021, 0x5A79: -0.0269, 0x5B6A: 0.0938, 0x6261: -0.0117, 0x6266: -0.0049, 0x6278: -0.02,
        0x634A: 0.0371, 0x6354: -0.0444, 0x6359: -0.0332, 0x6522: -0.0444, 0x6527: -0.0728, 0x6629: 0.0449, 0x662A: 0.0195,
        0x662C: -0.0557, 0x662D: -0.0444, 0x662E: -0.0557, 0x663A: 0.043, 0x663B: 0.043, 0x663F: 0.0327, 0x665D: 0.0449,
        0x6662: 0.0151, 0x6668: 0.0088, 0x666B: 0.0044, 0x666C: 0.0044, 0x6674: 0.021, 0x6676: 0.021, 0x6677: 0.021,
        0x6678: 0.0088, 0x6679: 0.0205, 0x667D: 0.0322, 0x676A: 0.0107, 0x6A6A: 0.0156, 0x6B2C: 0.043, 0x6B2D: -0.0615,
        0x6B2E: 0.043, 0x6B3A: 0.043, 0x6B3B: 0.043, 0x6B63: -0.0156, 0x6B64: -0.0117, 0x6B65: -0.0156, 0x6B67: -0.0156,
        0x6B6F: -0.0156, 0x6B71: -0.0117, 0x6B74: -0.0059, 0x6B7A: 0.0068, 0x6E22: -0.0444, 0x6E27: -0.064, 0x6F22: -0.063,
        0x6F27: -0.085, 0x6F61: -0.0117, 0x6F66: -0.0166, 0x6F6A: -0.002, 0x6F78: -0.02, 0x7061: -0.0117, 0x7066: -0.0166,
        0x7078: -0.02, 0x716A: 0.0479, 0x722C: -0.0854, 0x722D: -0.0557, 0x722E: -0.0864, 0x723A: 0.043, 0x723B: 0.043,
        0x7263: -0.0049, 0x7264: -0.0049, 0x7265: -0.0049, 0x7266: 0.0264, 0x7267: -0.0049, 0x7268: 0.0024, 0x7269: 0.0034,
        0x726D: 0.0024, 0x726E: 0.0024, 0x726F: -0.0049, 0x7271: -0.0117, 0x7273: 0.0059, 0x7274: 0.0308, 0x7275: 0.0024,
        0x7276: 0.043, 0x7277: 0.0376, 0x7278: 0.0288, 0x7279: 0.043, 0x727A: 0.021, 0x742D: -0.0493, 0x743F: -0.041,
        0x7463: -0.0049, 0x7464: -0.0049, 0x7465: -0.0044, 0x7467: -0.0044, 0x746F: -0.0044, 0x7471: -0.0044, 0x7478: 0.0151,
        0x7522: -0.0278, 0x7527: -0.042, 0x762C: -0.0645, 0x762E: -0.0654, 0x7661: -0.0166, 0x7663: -0.0068, 0x7664: -0.0068,
        0x7665: -0.0107, 0x7667: -0.0107, 0x766F: -0.0107, 0x7671: -0.0107, 0x772C: -0.0435, 0x772E: -0.0444, 0x7763: -0.0049,
        0x7764: -0.0049, 0x7765: -0.0049, 0x7767: -0.0049, 0x776F: -0.0049, 0x7771: -0.0049, 0x7863: -0.0176, 0x7864: -0.0176,
        0x7865: -0.0176, 0x7867: -0.0176, 0x786F: -0.0176, 0x7871: -0.0176, 0x7922: 0.0127, 0x7927: 0.0205, 0x792C: -0.0596,
        0x792E: -0.061, 0x793F: -0.0039, 0x7963: -0.0107, 0x7964: -0.0107, 0x7965: -0.0107, 0x7966: 0.0073, 0x7967: -0.0107,
        0x796F: -0.0107, 0x7971: -0.0107, 0x7974: 0.002, 0x7B6A: 0.0864,
    ]
    // … and JhengHei's, MSJH.ttf's (its bold has none).
    private static let jhengHeiKerns: [UInt32: Double] = [
        0x2272: -0.0269, 0x2273: -0.0347, 0x2772: -0.0269, 0x2773: -0.0347, 0x286A: 0.123, 0x2A41: -0.0874, 0x2A4A: -0.0811,
        0x2A63: -0.0537, 0x2A64: -0.0537, 0x2A65: -0.0537, 0x2A67: -0.0537, 0x2A6F: -0.0537, 0x2A71: -0.0537, 0x412A: -0.0679,
        0x412C: 0.0356, 0x413B: 0.0356, 0x4143: -0.0142, 0x4147: -0.0142, 0x414A: 0.0498, 0x414F: -0.0142, 0x4154: -0.0776,
        0x4155: -0.0142, 0x4156: -0.0615, 0x4157: -0.0391, 0x4159: -0.082, 0x415A: 0.0312, 0x4174: -0.0142, 0x4176: -0.0225,
        0x4177: -0.0142, 0x4179: -0.0195, 0x4254: -0.0483, 0x4259: -0.0347, 0x433F: 0.001, 0x4343: -0.0288, 0x4347: -0.0288,
        0x434F: -0.0142, 0x4351: -0.0288, 0x442C: -0.0679, 0x442E: -0.0679, 0x4441: -0.0176, 0x4454: -0.0483, 0x4458: -0.0278,
        0x445A: -0.0259, 0x4541: 0.0054, 0x454A: 0.0356, 0x4554: 0.002, 0x4557: 0.0151, 0x4558: 0.0044, 0x462C: -0.0811,
        0x462E: -0.0811, 0x4641: -0.0703, 0x464A: -0.0347, 0x4653: -0.0142, 0x4654: 0.0073, 0x4661: -0.04, 0x4666: 0.0054,
        0x4754: -0.0259, 0x4756: -0.0142, 0x4779: -0.0142, 0x4A2C: -0.0537, 0x4A2E: -0.0537, 0x4A41: -0.0195, 0x4A4A: -0.0347,
        0x4A61: -0.0142, 0x4B2C: 0.0205, 0x4B3B: 0.0205, 0x4B43: -0.0474, 0x4B47: -0.0474, 0x4B4A: 0.0474, 0x4B4F: -0.0474,
        0x4B51: -0.0474, 0x4B58: 0.0195, 0x4B5A: 0.0205, 0x4B63: -0.0142, 0x4B64: -0.0142, 0x4B65: -0.0142, 0x4B67: -0.0142,
        0x4B6F: -0.0142, 0x4B71: -0.0142, 0x4B74: -0.0249, 0x4B76: -0.0391, 0x4B77: -0.0278, 0x4B79: -0.0483, 0x4C2A: -0.1094,
        0x4C3F: -0.0537, 0x4C41: 0.0312, 0x4C43: -0.0347, 0x4C47: -0.0347, 0x4C4A: 0.0527, 0x4C4F: -0.0371, 0x4C51: -0.0371,
        0x4C54: -0.0596, 0x4C55: -0.0151, 0x4C56: -0.0615, 0x4C57: -0.0259, 0x4C59: -0.0679, 0x4C5A: 0.0312, 0x4C74: -0.0142,
        0x4C76: -0.0537, 0x4C77: -0.0347, 0x4C79: -0.04, 0x4F2C: -0.0483, 0x4F2E: -0.0483, 0x4F41: -0.0142, 0x4F4A: -0.0054,
        0x4F54: -0.0483, 0x4F58: -0.0195, 0x4F59: -0.0132, 0x4F5A: -0.0259, 0x502C: -0.1719, 0x502E: -0.1719, 0x5041: -0.0835,
        0x5047: -0.0054, 0x504A: -0.0679, 0x5057: 0.0205, 0x5058: -0.0322, 0x5061: -0.0347, 0x5063: -0.04, 0x5064: -0.04,
        0x5065: -0.04, 0x5067: -0.04, 0x506F: -0.04, 0x5071: -0.0391, 0x512C: -0.0483, 0x512E: -0.0679, 0x5141: -0.0142,
        0x5154: -0.0483, 0x5158: -0.0195, 0x5159: -0.0054, 0x515A: -0.0259, 0x523B: 0.0435, 0x5243: -0.0151, 0x5247: -0.0151,
        0x524A: 0.0303, 0x524F: -0.0107, 0x5251: -0.0107, 0x5254: -0.0278, 0x5259: -0.0205, 0x5263: -0.0278, 0x5264: -0.0278,
        0x5265: -0.0303, 0x5267: -0.0303, 0x526F: -0.0312, 0x5271: -0.0278, 0x5374: -0.0347, 0x5376: -0.0259, 0x5377: -0.0142,
        0x5379: -0.0249, 0x542C: -0.0679, 0x542E: -0.0947, 0x543A: -0.0122, 0x543B: -0.0122, 0x5441: -0.0811, 0x5443: -0.0483,
        0x5447: -0.0483, 0x544A: -0.0596, 0x544F: -0.0483, 0x5451: -0.0483, 0x5454: 0.0205, 0x5456: 0.0225, 0x5457: 0.0205,
        0x5458: -0.0029, 0x5459: 0.0151, 0x5461: -0.1143, 0x5463: -0.1113, 0x5464: -0.1113, 0x5465: -0.1113, 0x5466: -0.0508,
        0x5467: -0.1113, 0x546D: -0.0938, 0x546E: -0.0938, 0x546F: -0.1113, 0x5470: -0.0938, 0x5471: -0.1113, 0x5472: -0.0938,
        0x5473: -0.0811, 0x5475: -0.0938, 0x5476: -0.0537, 0x5477: -0.0596, 0x5478: -0.0947, 0x5479: -0.0596, 0x547A: -0.0679,
        0x5541: -0.0215, 0x562C: -0.1079, 0x562E: -0.1206, 0x5641: -0.0615, 0x5643: -0.0225, 0x5647: -0.0225, 0x564A: -0.0371,
        0x564F: -0.0063, 0x5651: -0.0225, 0x5653: -0.0142, 0x5654: 0.0205, 0x5661: -0.0776, 0x5663: -0.0679, 0x5664: -0.0679,
        0x5665: -0.0679, 0x5667: -0.0679, 0x566D: -0.04, 0x566E: -0.04, 0x566F: -0.0679, 0x5670: -0.04, 0x5671: -0.0679,
        0x5672: -0.04, 0x5673: -0.0347, 0x5675: -0.04, 0x572C: -0.0615, 0x572E: -0.0679, 0x5741: -0.0391, 0x5754: 0.0205,
        0x5761: -0.04, 0x5763: -0.0259, 0x5764: -0.0259, 0x5765: -0.0259, 0x5767: -0.0259, 0x576F: -0.0259, 0x5771: -0.0259,
        0x582C: 0.0356, 0x582E: 0.0303, 0x583B: 0.0435, 0x5843: -0.0122, 0x5847: -0.0122, 0x584A: 0.0508, 0x584F: -0.0122,
        0x5851: -0.0122, 0x5854: 0.0176, 0x592C: -0.0928, 0x592E: -0.103, 0x5941: -0.0835, 0x5943: -0.0239, 0x5947: -0.0239,
        0x594A: -0.0347, 0x594F: -0.0239, 0x5951: -0.0239, 0x5953: -0.0142, 0x5954: 0.0205, 0x5961: -0.105, 0x5963: -0.0947,
        0x5964: -0.0947, 0x5965: -0.0947, 0x5966: -0.0142, 0x5967: -0.0947, 0x596D: -0.0742, 0x596E: -0.0742, 0x596F: -0.0947,
        0x5970: -0.0742, 0x5971: -0.0947, 0x5972: -0.0742, 0x5973: -0.0703, 0x5975: -0.0742, 0x5A4A: 0.0435, 0x5A54: 0.0205,
        0x5A79: -0.0278, 0x5B6A: 0.123, 0x6261: -0.0142, 0x6266: -0.0054, 0x6278: -0.0132, 0x634A: 0.0371, 0x6354: -0.0537,
        0x6359: -0.04, 0x6522: -0.0547, 0x6527: -0.0547, 0x6629: 0.0742, 0x662C: -0.0679, 0x662D: -0.0537, 0x662E: -0.0679,
        0x663A: 0.0435, 0x663B: 0.0435, 0x663F: 0.0347, 0x665D: 0.0742, 0x6662: 0.0093, 0x6668: 0.0093, 0x6674: 0.0195,
        0x6676: 0.0205, 0x6677: 0.0205, 0x6678: 0.0093, 0x6679: 0.0176, 0x667D: 0.0435, 0x676A: 0.0249, 0x6A6A: 0.0186,
        0x6B2C: 0.0435, 0x6B2D: -0.0732, 0x6B2E: 0.0435, 0x6B3A: 0.0435, 0x6B3B: 0.0435, 0x6B63: -0.0215, 0x6B64: -0.0142,
        0x6B65: -0.0215, 0x6B67: -0.0215, 0x6B6F: -0.0215, 0x6B71: -0.0142, 0x6B74: -0.0083, 0x6E22: -0.0547, 0x6E27: -0.0547,
        0x6F22: -0.0767, 0x6F27: -0.0767, 0x6F61: -0.0142, 0x6F66: -0.0195, 0x6F78: -0.0132, 0x7061: -0.0142, 0x7066: -0.0195,
        0x7078: -0.0132, 0x716A: 0.0537, 0x722C: -0.0835, 0x722D: -0.0679, 0x722E: -0.0898, 0x723A: 0.0435, 0x723B: 0.0435,
        0x7263: -0.0142, 0x7264: -0.0142, 0x7265: -0.0142, 0x7266: 0.0205, 0x7267: -0.0142, 0x726D: -0.002, 0x726E: -0.002,
        0x726F: -0.0142, 0x7271: -0.0142, 0x7273: 0.0073, 0x7274: 0.0312, 0x7276: 0.0435, 0x7277: 0.0435, 0x7278: 0.0312,
        0x7279: 0.0435, 0x727A: 0.0205, 0x742D: -0.0596, 0x743F: -0.0278, 0x7463: -0.0142, 0x7464: -0.0142, 0x7465: -0.0083,
        0x7467: -0.0083, 0x746F: -0.0083, 0x7471: -0.0083, 0x7478: 0.0151, 0x7522: -0.0347, 0x7527: -0.0347, 0x762C: -0.0615,
        0x762E: -0.0679, 0x7661: -0.0195, 0x7663: -0.0063, 0x7664: -0.0083, 0x7665: -0.0063, 0x7667: -0.0063, 0x766F: -0.0063,
        0x7671: -0.0083, 0x772C: -0.0474, 0x772E: -0.0537, 0x7763: -0.0029, 0x7764: -0.0054, 0x7765: -0.0054, 0x7767: -0.0029,
        0x776F: -0.0029, 0x7771: -0.0054, 0x7863: -0.0083, 0x7864: -0.0083, 0x7865: -0.0083, 0x7867: -0.0083, 0x786F: -0.0083,
        0x7871: -0.0083, 0x7922: 0.0151, 0x7927: 0.0151, 0x792C: -0.0537, 0x792E: -0.0669, 0x793F: -0.04, 0x7963: -0.0054,
        0x7964: -0.0054, 0x7965: -0.0054, 0x7966: 0.002, 0x7967: -0.0054, 0x796F: -0.0054, 0x7971: -0.0054, 0x7974: 0.0029,
        0x7B6A: 0.1069,
    ]
    private static let jhengHeiAdvances: [Double] = [
        0.25, 0.3042, 0.416, 0.6382, 0.5796, 0.8804, 0.8608, 0.2441, 0.3208, 0.3208, 0.4473, 0.7373, 0.2305, 0.4316, 0.2305,
        0.417, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.2305, 0.2305, 0.7373, 0.7373,
        0.7373, 0.4844, 1.0312, 0.6929, 0.6143, 0.668, 0.7549, 0.5444, 0.5249, 0.7388, 0.7627, 0.2842, 0.3789, 0.6216, 0.5054,
        0.9653, 0.8052, 0.814, 0.6011, 0.814, 0.6421, 0.5718, 0.5615, 0.7397, 0.6675, 1.0039, 0.6328, 0.5933, 0.6133, 0.3208,
        0.4053, 0.3208, 0.7373, 0.4482, 0.2861, 0.5474, 0.6323, 0.4976, 0.6338, 0.5635, 0.333, 0.6338, 0.6089, 0.2593, 0.2588,
        0.5322, 0.2593, 0.9263, 0.6084, 0.6309, 0.6323, 0.6338, 0.3721, 0.4561, 0.3628, 0.6084, 0.5127, 0.7749, 0.4893, 0.5186,
        0.4863, 0.3208, 0.252, 0.3208, 0.7373
    ]
    private static let jhengHeiBoldAdvances: [Double] = [
        0.25, 0.4824, 0.4619, 0.6387, 0.5957, 0.9023, 0.8828, 0.272, 0.3511, 0.3511, 0.4648, 0.7476, 0.2544, 0.4341, 0.2544,
        0.4414, 0.5957, 0.5957, 0.5957, 0.5957, 0.5957, 0.5957, 0.5957, 0.5957, 0.5957, 0.5957, 0.2544, 0.2544, 0.7476, 0.7476,
        0.7476, 0.48, 1.0308, 0.7188, 0.6445, 0.6704, 0.771, 0.5566, 0.5396, 0.7505, 0.7881, 0.3066, 0.4189, 0.6528, 0.5234,
        0.9922, 0.8237, 0.8159, 0.6255, 0.8159, 0.6665, 0.5845, 0.5894, 0.7559, 0.688, 1.0356, 0.6621, 0.6172, 0.6294, 0.3511,
        0.4312, 0.3511, 0.7476, 0.4482, 0.3066, 0.5605, 0.647, 0.5059, 0.647, 0.5718, 0.3647, 0.647, 0.625, 0.2754, 0.2778,
        0.5601, 0.2754, 0.9507, 0.626, 0.6426, 0.647, 0.647, 0.3945, 0.4722, 0.3853, 0.626, 0.541, 0.8086, 0.5308, 0.543, 0.4985,
        0.3511, 0.291, 0.3511, 0.7476
    ]
    private static let dengXianAdvances: [Double] = [
        0.2739, 0.2842, 0.3633, 0.5972, 0.5269, 0.5, 0.7485, 0.2217, 0.292, 0.292, 0.4111, 0.667, 0.2192, 0.5, 0.2192, 0.3779,
        0.5269, 0.5269, 0.5269, 0.5269, 0.5269, 0.5269, 0.5269, 0.5269, 0.5269, 0.5269, 0.2192, 0.2192, 0.667, 0.667, 0.667,
        0.439, 0.9492, 0.6362, 0.5586, 0.6201, 0.6875, 0.5029, 0.4766, 0.6768, 0.6934, 0.2471, 0.3403, 0.5532, 0.4644, 0.8652,
        0.7285, 0.7573, 0.5518, 0.7573, 0.5767, 0.5142, 0.5176, 0.6675, 0.6123, 0.9146, 0.5762, 0.5464, 0.5698, 0.292, 0.3726,
        0.292, 0.667, 0.415, 0.2578, 0.501, 0.5737, 0.4526, 0.5742, 0.5137, 0.2944, 0.5742, 0.5503, 0.2236, 0.2236, 0.4702,
        0.2236, 0.8413, 0.5503, 0.5732, 0.5737, 0.5742, 0.3389, 0.4062, 0.3179, 0.5508, 0.4658, 0.6997, 0.4404, 0.4683, 0.458,
        0.292, 0.2324, 0.292, 0.667
    ]
    private static let dengXianBoldAdvances: [Double] = [
        0.2749, 0.3037, 0.4375, 0.5913, 0.5552, 0.5, 0.8223, 0.2583, 0.332, 0.332, 0.4341, 0.6943, 0.2412, 0.5, 0.2412, 0.4136,
        0.5552, 0.5552, 0.5552, 0.5552, 0.5552, 0.5552, 0.5552, 0.5552, 0.5552, 0.5552, 0.2412, 0.2412, 0.6943, 0.6943, 0.6943,
        0.4438, 0.9546, 0.6714, 0.604, 0.6211, 0.7173, 0.5176, 0.5024, 0.6973, 0.7354, 0.2915, 0.3965, 0.6108, 0.4888, 0.9243,
        0.7671, 0.7559, 0.5845, 0.7559, 0.6226, 0.5444, 0.5518, 0.7031, 0.6416, 0.9658, 0.6191, 0.5771, 0.5869, 0.332, 0.4048,
        0.332, 0.6943, 0.415, 0.2886, 0.522, 0.6025, 0.4702, 0.6025, 0.5312, 0.3447, 0.6025, 0.582, 0.2612, 0.2612, 0.5249,
        0.2612, 0.8857, 0.5835, 0.5972, 0.6025, 0.6025, 0.3701, 0.4312, 0.3613, 0.5835, 0.5073, 0.7563, 0.501, 0.5083, 0.4644,
        0.332, 0.2783, 0.332, 0.6943
    ]

    private static func eastAsianFace(_ family: String, ignoringEmbedding: Bool = false) -> EastAsianFace {
        let n = family.trimmingWhitespace().lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { n.containsSubstring($0) } }
        if has("yahei ui") {
            return EastAsianFace(height: 1.67, latin: sans, latinScale: 1.07, latinAdvances: yaHeiUIAdvances, latinBoldAdvances: yaHeiUIBoldAdvances,
                                 latinKerns: yaHeiKerns, latinBoldKerns: yaHeiBoldKerns,
                                 fakeBold: false)
        }
        if has("yahei", "微软雅黑") { return yaHei }
        // (JhengHei UI's line is its own: an ascent of 2080 and a descent of
        // 521 in 2048, Word's 1.3 of that — zh-167ee06c's Light, set from
        // the face its print embeds.)
        // (Its Light has no bold, and Word emboldens it a fiftieth of an em
        // wider a character — lab `bw` (Word 16.113.3, 8 to 32pt): 0.0200
        // em at every size, where PMingLiU's and SimSun's are 0.0195.
        // zh-167ee06c's 18.5pt title, 22 characters at 18.87, ends 0.16pt
        // inside its margin; at 1/48 it wrapped, and at 1/57 the file ran a
        // page long. Its bold 14pt line "七、經同意…為必要" then leaves "要"
        // for the next line, as Word's print does: the line's two marks
        // cannot give the 14pt it is over.)
        if has("jhenghei ui") {
            return EastAsianFace(height: 1.651, latin: sans, latinScale: 1.05, latinClasses: [0.991, 0.925, 1.031, 0.95],
                                 latinAdvances: jhengHeiAdvances, latinBoldAdvances: jhengHeiBoldAdvances, latinKerns: jhengHeiKerns,
                                 fakeBold: has("light"), boldWiden: 1.0 / 50, baseline: 1.206)
        }
        if has("jhenghei", "微軟正黑") {
            return EastAsianFace(height: 1.74, latin: sans, latinScale: 1.05, latinClasses: [0.991, 0.925, 1.031, 0.95],
                                 latinAdvances: jhengHeiAdvances, latinBoldAdvances: jhengHeiBoldAdvances, latinKerns: jhengHeiKerns, fakeBold: false)
        }
        if has("dengxian", "等线") {
            return EastAsianFace(height: 1.36, latin: sans, latinScale: 0.955, latinClasses: [0.992, 0.927, 1.021, 0.91],
                                 latinAdvances: dengXianAdvances, latinBoldAdvances: dengXianBoldAdvances, fakeBold: false, baseline: 1.01)
        }
        // (Not 1.3 em but 1332/1024 — 1.3 of its 1024-unit em, rounded
        // up to a whole unit: Word fits 48 lines of 12pt to a page only
        // with 8..12 twips over 48 x 312, and 24 lines of 24pt with the
        // same over 24 x 624 — labs `ln`, `lb`, Word 16, 2026-10-16. The
        // 0.2 twip a line kept zh-e061a08e's page 1 a line long.)
        if has("pmingliu", "新細明體") { return EastAsianFace(height: 1332.0 / 1024.0, latin: serif, latinScale: 0.94, fakeBold: true) }
        if has("stzhongsong", "华文中宋") {
            // (hhea 1.007 + .318, OS/2 win .912 + .225: 105.3pt a line at
            // 61pt, and 90.2 at 34% of its width.)
            return EastAsianFace(height: 1.7225, latin: serif, latinScale: 1.16, fakeBold: true, baseline: 1.206,
                                 scaledHeight: 1.478, scaledBaseline: 1.083)
        }
        // (hhea 0.8 + 0.236, no gap — the STXINWEI.ttf Word carries: a 24pt
        // line is 32.3pt, three pitches of a 15.6 grid, and zh-424775e4's
        // title, centred in them, has its baseline at 117.84 in Word's
        // print. Taken for YaHei's, ours was two pitches and every page
        // after it ran 15.6pt early.)
        if has("stxinwei", "华文新魏") {
            return EastAsianFace(height: 1.036 * 1.3, latin: serif, latinScale: 1.0, fakeBold: true, baseline: 0.8 + (1.036 * 1.3 - 1.036) / 2)
        }
        if has("stfangsong", "华文仿宋") { return EastAsianFace(height: 1.71, latin: serif, latinScale: 1.0, fakeBold: false) }
        if has("stkaiti", "华文楷体") { return EastAsianFace(height: 1.7, latin: serif, latinScale: 1.04, fakeBold: true) }
        if has("stsong", "华文宋体") { return EastAsianFace(height: 1.31, latin: serif, latinScale: 1.0, fakeBold: true) }
        if has("arial unicode") { return EastAsianFace(height: 1.75, latin: sans, latinScale: 1.0, fakeBold: true) }
        // (Noto Sans SC, which Word's fallback takes for some CJK
        // compatibility ideographs — `RichLayout._notoCompatibility`: its
        // hhea 1.16 + 0.288 ems with Word's 30% more, the baseline 1.377
        // down. Lab `cj2`: the line 1.44pt lower and 0.48 deeper at 12pt
        // than YaHei's.) Its line is set by a sized joiner
        // (`RichLayout._notoJoiner`), which takes this height and
        // baseline as they are: both what is over YaHei's line and what
        // is under it come from them.
        if has("noto sans sc") { return EastAsianFace(height: 1.8824, latin: sans, latinScale: 1.0, fakeBold: false, baseline: 1.377) }
        // Word on a Mac has 宋体, 黑体, 楷体, 仿宋 and the 明體 pair, and
        // sets every other Chinese name — 仿宋_GB2312, 楷体_GB2312, the
        // 方正 faces, 標楷體 — in Microsoft YaHei, which is taller and wider than
        // any of them. `OFFICE_WORD_FONTS=mac` does the same, so that a
        // print can be compared with that Word's; without it such a
        // name is taken for the square face its author had.
        // (A name with an alternate the table gives is set in that,
        // where the alternate is one Word has.)
        // (Only for a name Word has no face for at all, and only to an
        // alternate it has; 方正 names fall back. 楷体_GB2312 was KaiTi in
        // the prints of 2026-10-12 and is YaHei in Word 16.113.3's, alt
        // name or not: zh-78729cf9 reprinted, zh-17749c13's alt 楷体.)
        let wordHas = ["simsun", "宋体", "新宋体", "simhei", "黑体", "kaiti", "楷体", "fangsong", "仿宋", "mingliu", "細明體",
                       "微软雅黑", "microsoft yahei", "幼圆", "全真楷書", "標楷", "方正", "小标宋"]
        if wordOnMac, ignoringEmbedding || !isEmbedded(family), !wordHas.contains(where: { n.containsSubstring($0) }),
           let alt = altName(family), alt.trimmingWhitespace().lowercased() != n {
            let a = alt.trimmingWhitespace().lowercased()
            // (… JhengHei too: zh-167ee06c's 華康雅風體W3(P), alternate
            // "Microsoft JhengHei UI Light", is drawn in that face in Word's
            // print, its 1.5-spaced 14pt lines 34.7pt apart where YaHei's
            // stood 36.3.)
            // (An alternate that is a Latin face Word has draws the name's
            // letters, and that face has no Chinese: Word falls back to
            // 宋体 for it. zh-10e3a42be's headings are FZHei-B01, alternate
            // Calibri, and Word's print sets "．应急保障" in SimSun on lines
            // 3.7pt shorter than YaHei's.)
            if ["calibri", "arial", "times new roman", "cambria"].contains(a) { return eastAsianFace("SimSun") }
            let usable = ["simsun", "宋体", "新宋体", "simhei", "黑体", "kaiti", "楷体", "mingliu", "細明體", "jhenghei"]
            if usable.contains(where: { a.containsSubstring($0) }), !["_gb2312", "方正", "小标宋", "標楷"].contains(where: { a.containsSubstring($0) }) {
                return eastAsianFace(alt)
            }
        }
        // (As Word for Windows sets it, a name it has no face for is its font
        // table's alternate, where that is one it has — the other way round
        // from Word for Mac, which never reads it — and YaHei where it is
        // not. Word for Windows' prints (~/starling-doc-check/lab/fsw on the
        // Windows box): zh-f59a76e9's 方正小标宋_GBK, alternate 微软雅黑, is
        // YaHei, a 22pt line three 15.6 pitches; zh-34a6519a's 仿宋_GB2312,
        // alternate 微软雅黑, is YaHei, 53 pages; zh-dc9cfa34's 方正仿宋_GBK,
        // no alternate, is YaHei.)
        let windowsHas = ["simsun", "宋体", "新宋体", "simhei", "黑体", "kaiti", "楷体", "fangsong", "仿宋", "microsoft yahei", "微软雅黑",
                          "mingliu", "細明體", "新細明體", "microsoft jhenghei", "微軟正黑", "dengxian", "等线"]
        let windowsLacks = !windowsHas.contains(where: { n.containsSubstring($0) }) || has("_gb2312", "方正", "小标宋", "標楷")
        if wordOnWindows, windowsLacks, ignoringEmbedding || !isEmbedded(family), let alt = altName(family) {
            let a = alt.trimmingWhitespace().lowercased()
            if a != n, windowsHas.contains(where: { a.containsSubstring($0) }),
               !["_gb2312", "方正", "小标宋", "標楷"].contains(where: { a.containsSubstring($0) }) {
                return eastAsianFace(alt, ignoringEmbedding: ignoringEmbedding)
            }
        }
        if wordOnWindows, windowsLacks, ignoringEmbedding || !isEmbedded(family) {
            var standIn = yaHei
            standIn.symbols = "SimSun"
            return standIn
        }
        // (方正小标宋 by its ASCII name is SimSun's, not YaHei's:
        // zh-202582e2's title, FZXiaoBiaoSong-B05S with no entry in its
        // font table, is drawn in SimSun in Word's print, its 21.6pt line
        // 5pt shorter than YaHei's. Not every "FZ…" name: zh-f6686f89's
        // FZShuTi, no entry either, is YaHei in its print.)
        if wordOnMac, ignoringEmbedding || !isEmbedded(family), n.hasPrefix("fzxiaobiaosong"), n.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return eastAsianFace("SimSun")
        }
        if wordOnMac, ignoringEmbedding || !isEmbedded(family), !has("simsun", "宋体", "simhei", "黑体", "kaiti", "楷体", "fangsong", "仿宋", "mingliu", "細明體",
                           "幼圆", "全真楷書") || has("仿宋_gb2312", "fangsong_gb2312", "楷体_gb2312", "kaiti_gb2312", "方正", "小标宋", "標楷") {
            // (The English name too: zh-202582e2's body is
            // "FangSong_GB2312", and its 15.5pt lines at 1.32 stand 35pt
            // apart in Word's print, YaHei's 1.72 em; ours took FangSong.)
            var standIn = yaHei
            standIn.symbols = "SimSun"
            return standIn
        }
        // (An embedded face taller than its em is measured by its own
        // line, Word's 1.3 of hhea's ascent and descent, as the faces
        // above are: zh-e8d4c046's title is in the FZXiaoBiaoSong-B05S
        // it carries, 0.867 + 0.297, and its 22pt lines stand 33.4pt
        // apart in Word's print — ours, at the square 1.3, 29. A face of
        // one em — SimSun's and FangSong's subsets — is the square.)
        if !ignoringEmbedding, let registered = embeddedFamily(family) {
            declaredLock.lock()
            let line = embeddedLines[registered]
            declaredLock.unlock()
            if let line, line.ascent + line.descent > 1.01 {
                var face = square
                let h = line.ascent + line.descent
                face.height = h * 1.3
                face.baseline = line.ascent + h * 0.15
                return face
            }
        }
        // (The 方正 Song titles as their author had them: FZXiaoBiaoSong's
        // line, 0.867 + 0.297 ems by Word's 1.3, as zh-e8d4c046 embeds it —
        // a 22pt title three 15.6 pitches, where the square face is two.)
        if has("小标宋", "大标宋", "xiaobiaosong", "dabiaosong") {
            var face = square
            face.height = 1.164 * 1.3
            face.baseline = 0.867 + 1.164 * 0.15
            return face
        }
        return square
    }

    // Times New Roman's Roman numerals, Ⅰ to Ⅻ and ⅰ to ⅻ (U+2160 and
    // U+2170 on), in ems, regular and bold: Word's Times has them and
    // sets them where a run of a Chinese document leaves its "Ⅳ级" in
    // the Latin face; Liberation Serif has none, and what falls back
    // for it draws them an em wide (measured 2026-10-13 from the face
    // Word for Mac carries; a line of zh-6cd1befe with 0.3pt to spare
    // took a character more than Word's).
    private static func numerals(_ upper: [Double], _ lower: [Double]) -> [UInt32: Double] {
        var table: [UInt32: Double] = [:]
        for (k, w) in upper.enumerated() { table[0x2160 + UInt32(k)] = w }
        for (k, w) in lower.enumerated() { table[0x2170 + UInt32(k)] = w }
        return table
    }
    // The circled numbers ⓪ and ① to ⑳: Calibri has its own (and
    // Carlito the same), and for a run in Times New Roman, Arial or
    // Cambria Word takes Cambria Math's, 1.2 ems wide — 1.22 in bold
    // (lab `cn`, ten of each per face, 2026-10-13). A paragraph that
    // opens "⑤" is a fifth of an em further along than a fallback's
    // em-wide glyph puts it, and zh-6cd1befe's lists broke by it.
    private static func circled(_ ems: Double) -> [UInt32: Double] {
        var table: [UInt32: Double] = [0x24EA: ems]
        for u in UInt32(0x2460) ... 0x2473 { table[u] = ems }
        return table
    }
    private static let timesNumerals = numerals([0.3330, 0.6465, 0.9595, 1.0513, 0.7222, 1.0474, 1.3604, 1.6733, 1.0527, 0.7222, 1.0479, 1.3608],
                                                [0.2778, 0.5244, 0.7710, 0.7393, 0.5000, 0.7612, 1.0078, 1.2544, 0.7661, 0.5000, 0.7588, 1.0054])
    private static let timesBoldNumerals = numerals([0.3892, 0.7646, 1.1401, 1.1113, 0.7222, 1.1089, 1.4844, 1.8599, 1.1123, 0.7222, 1.1123, 1.4878],
                                                    [0.2778, 0.5537, 0.8296, 0.7588, 0.5000, 0.7778, 1.0537, 1.3296, 0.7734, 0.5000, 0.7705, 1.0464])

    private static let wordOnMac = ProcessInfo.processInfo.environment["OFFICE_WORD_FONTS"] == "mac"
    /// `OFFICE_WORD_FONTS=windows`: the faces Word for Windows sets on a
    /// stock machine — a missing name's font-table alternate where that
    /// is a face it has (仿宋 for 仿宋_GB2312 is its cloud FangSong), else
    /// YaHei — to compare with its prints. The default is the faces the
    /// author had (`fangSongFamily`, the 方正 titles' own line).
    private static let wordOnWindows = ProcessInfo.processInfo.environment["OFFICE_WORD_FONTS"] == "windows"

    /// The face a Song, Ming or Mincho name's ideographs are drawn in
    /// where the platform has none of those faces: Noto Serif CJK, in
    /// the variant of the name's script. Left to the theme's fallback
    /// every Chinese and Japanese face came out in Noto Sans CJK, where
    /// Word's print of 宋体, 細明體 and ＭＳ 明朝 is a serif (61470's
    /// "東京"). Only the square faces: a name Word on a Mac sets in YaHei
    /// stays sans, as YaHei is. It draws only what the stand-in lacks,
    /// so letters and digits keep their widths and the lines their breaks.
    private static func serifIdeographs(_ family: String, _ ea: EastAsianFace) -> String? {
        #if os(Linux)
        guard abs(ea.height - square.height) < 0.01 else { return nil }
        let n = family.trimmingWhitespace().lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { n.containsSubstring($0) } }
        if has("mincho", "明朝") { return "Noto Serif CJK JP" }
        if has("mingliu", "明體") { return "Noto Serif CJK TC" }
        if has("simsun", "宋体", "宋體", "songti") { return "Noto Serif CJK SC" }
        #endif
        return nil
    }

    /// The theme's `faceResolver`: the shipped face for a name, and for
    /// an East Asian face Word's measure of it — see `EastAsianFace`.
    /// East Asian text in a Latin face is set in the face Word falls
    /// back to, 宋体. The ideographs themselves are drawn by whatever
    /// the platform falls back to; they are an em wide in every face.
    /// Complex-script text needs the requested face itself: the shipped
    /// Latin metric clones do not include Arabic. Try the document's
    /// embedded face first, then installed Arabic-capable families. Word
    /// uses Cambria for spaces/punctuation and Times New Roman for Arabic
    /// when the named face is absent (rtl.docx and missing-face labs).
    static func complexFace(_ family: String?) -> RichResolvedFace? {
        let name = family ?? "Times New Roman"
        var face = RichResolvedFace(family: embeddedFamily(name) ?? name)
        face.fallback = [cambria, "Times New Roman", "Noto Naskh Arabic", "DejaVu Sans"]
        return face
    }

    static func face(_ family: String?, eastAsian: Bool) -> RichResolvedFace? {
        guard let family else { return nil }
        let own = isEastAsianFace(family)
        guard own || eastAsian else {
            // A Latin face: its clone, and where Word sets the baseline
            // of the face it is the clone of — its ascent under its line
            // gap (Arial .905 + .033, Times .891 + .042, Calibri .75 +
            // .22, Cambria .95, Courier .833).
            let clone = substitute(family)
            let baseline: Double
            switch clone {
            case serif: baseline = 0.933
            case mono: baseline = 0.833
            case calibri: baseline = 0.9625
            case cambria: baseline = 0.95
            default: baseline = 0.938
            }
            // (Times and Arial as a Word line holds them, where they are
            // registered so: `wordSans`.)
            let drawn = !_gapAboveLoaded ? clone : clone == serif ? wordSerif : clone == sans ? wordSans : clone
            var face = RichResolvedFace(family: drawn, baseline: baseline)
            // (The missing-glyph box of the face it stands for, as
            // Word's own fonts have it: a private-use character is set
            // at that width.)
            switch clone {
            case serif: face.missingGlyphAdvance = 0.7778
            case sans: face.missingGlyphAdvance = 0.75
            case calibri: face.missingGlyphAdvance = 0.5068
            case cambria: face.missingGlyphAdvance = 0.6582
            case verdana: face.missingGlyphAdvance = 1.0
            default: break
            }
            // (Aptos, drawn as the sans clone, keeps its own line: 1.22
            // ems, its baseline .94 down — lab `ap`, Word for Windows,
            // 12pt lines 14.64 apart and the first baseline 11.28 down,
            // where the clone's 13.8 put table-alignment's paragraphs
            // between tables 2pt short.)
            // (Cambria Math keeps Cambria's line, 1.172 ems — its hhea
            // ascent and descent; its huge OS/2 win metrics are for the
            // equation editor — and sets its math letters at its own
            // widths. bug59058's formulas, written as runs of "𝑘𝑖" in it at
            // 13pt, are 15.2pt lines in Word's print; the fallback that
            // draws them here made them 16.2 and 𝑖 3.6pt wide to Word's 4.1.)
            if family.trimmingWhitespace().lowercased() == "cambria math" {
                face.naturalHeight = 1.172
                face.setsMath = true
                face.otherAdvances = cambriaMathAdvances
                face.boldOtherAdvances = cambriaMathAdvances
                return face
            }
            if family.trimmingWhitespace().lowercased() == "aptos" {
                face.naturalHeight = 1.22
                face.baseline = 0.94
            }
            // (Lucida Sans Unicode keeps its own line too, a tall one:
            // 1.537 ems by its hhea, 2246 over and 901 under of 2048, no
            // gap — the face Word's print of bug59058 embeds. Its 9.5pt
            // lines step 14.52 there, where the sans clone's 10.9 set
            // the fact sheet's heading and table 1.4 to 5pt high.)
            if family.trimmingWhitespace().lowercased() == "lucida sans unicode" {
                face.naturalHeight = 1.5366
                face.baseline = 1.0967
                face.advances = lucidaSansUnicodeAdvances
            }
            // Word's symbol faces keep their own lines too — its own
            // symbol.ttf and the Wingdings three, by their hhea ascent
            // and descent (no line gap): a line with a Symbol box or
            // bullet on it is 1.225 ems. form_footnotes' 10pt lines with
            // a `w:sym` box, or a Symbol bullet, are 12.24 apart in
            // Word's print where the clone's were 11.5, and its first
            // page ran 4pt short, a row over.
            let symbolLines: [String: (height: Double, baseline: Double)] = [
                "symbol": (1.225, 1.005), "wingdings": (1.11, 0.899), "wingdings 2": (1.054, 0.843), "wingdings 3": (1.139, 0.928),
            ]
            if let own = symbolLines[family.trimmingWhitespace().lowercased()] {
                face.naturalHeight = own.height
                face.baseline = own.baseline
            }
            if clone != calibri {
                face.otherAdvances = circled(1.2007)
                face.boldOtherAdvances = circled(1.2207)
            }
            // (Verdana set to its own widths and line — 1.2153 ems, its
            // hhea ascent and descent with no gap: drawing.docx's Verdana
            // 9 lines held a word fewer in the stand-in's, and every page
            // of its Russian news ran on.)
            if clone == verdana {
                face.advances = verdanaAdvances
                face.boldAdvances = verdanaBoldAdvances
                face.otherAdvances?.merge(verdanaOtherAdvances) { $1 }
                face.boldOtherAdvances?.merge(verdanaBoldOtherAdvances) { $1 }
                face.naturalHeight = 1.2153
                face.baseline = 1.0054
            }
            // (Arial Black, which Word has and the stand-in is far
            // narrower than — its letters 15% wider than Liberation Sans
            // Bold's on average: its own widths and line, 1.41 ems by
            // its hhea, the ascent 1.1006. SampleDoc's 16pt heading.)
            if family.trimmingWhitespace().lowercased() == "arial black" {
                face.advances = arialBlackAdvances
                face.boldAdvances = arialBlackAdvances
                face.naturalHeight = 1.4102
                face.baseline = 1.1006
            }
            // (A face Word does not have, which it draws in Cambria, is a
            // line of Cambria's ascent over Times New Roman's descent:
            // 1.166 ems, where Cambria's own is 1.172. bug59058's
            // MinionPro-Regular text, 13pt at least 15, steps 15.17 in
            // Word's print over 29 lines and its MinionPro-It titles
            // beside Times 15.16 over 69; Caladea's line made both 15.24.)
            if clone == cambria, !["cambria", "caladea"].contains(family.trimmingWhitespace().lowercased()) {
                face.naturalHeight = 0.95 + 0.2163
            }
            if clone == serif {
                face.otherAdvances?.merge(timesNumerals) { $1 }
                face.boldOtherAdvances?.merge(timesBoldNumerals) { $1 }
            }
            // (Word's Thai faces set to Cordia New's widths: Word for Mac
            // draws "TH Sarabun New" — which it has under no such name —
            // in Browallia New, whose advances are Cordia's to half a per
            // cent (digits 0.3645 em; Thai 0.303 on average over
            // zh-6a4fc013's text, a 47-character line 255.9pt to the
            // print's 257.1). Its digits and Latin take Cordia's table;
            // its Thai, drawn by the platform's fallback, the class scale
            // that brings that face to Browallia's. On a Mac the fallback is
            // Thonburi: Word's print advances 6.17pt a Thai character at
            // 16pt and ours 8.96 (0.689), and 0.75 sets zh-6a4fc013's 614
            // lines on 26 pages as Word does (0.689 gives 588, and the
            // fonts' tables, which count Thonburi's marks, 0.549 and 541).
            // Ours set them unscaled: 693 lines on 29 pages. On Windows the
            // fallback is Leelawadee UI, 0.729 (Windows 01QbbApP).)
            if Self.thaiWordFaces.contains(family.trimmingWhitespace().lowercased()) {
                face.advances = cordiaNewAdvances
                face.boldAdvances = cordiaNewBoldAdvances
                #if os(macOS)
                face.classScales = [1, 1, 1, 1, 0.75]
                #elseif os(Windows)
                face.classScales = [1, 1, 1, 1, 0.729]
                #else
                // (On Linux the fallback is Noto Sans Thai: shaped over
                // zh-6a4fc013's Thai it is 1/0.70 of Cordia's widths, and
                // 0.66 sets the document's 614 lines on 26 pages as Word
                // does — 0.70 gives 627 on 27, unscaled 726 on 30.)
                face.classScales = [1, 1, 1, 1, 0.66]
                #endif
            }
            return face
        }
        // (A name the table declares Latin still sets East Asian text
        // as the face it names.)
        // (An East Asian face by its ASCII name as well: zh-202582e2's
        // "FangSong_GB2312" is YaHei to Word on a Mac, its quotes an em
        // as the stand-in's symbols set them; taken for the square face,
        // ours drew YaHei's own 0.38 em quotes and its lines took a
        // character more than Word's.)
        let ea = own || family.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) || Self.isEastAsianFace(family) ? eastAsianFace(family) : square
        if eastAsian {
            // (An embedded face draws its own characters; what its subset
            // lacks falls back as before.)
            var face = RichResolvedFace(family: (own ? embeddedFamily(family) : nil) ?? fangSongFamily(family) ?? substitute(family), naturalHeight: ea.height, boldSpread: ea.fakeBold ? ea.boldWiden ?? 1.0 / 48 : 0,
                                        baseline: ea.baseline)
            // (A square face's symbols are an em; YaHei's, JhengHei's and
            // DengXian's — the faces with Latin widths of their own — are not.)
            face.fullWidthSymbols = ea.latinAdvances == nil
            // (Ideographs in a serif where the name is a Song, Ming or
            // Mincho face: `serifIdeographs`.)
            if !own || embeddedFamily(family) == nil, let serif = serifIdeographs(family, ea) { face.fallback = [serif] }
            // (YaHei has none of the compatibility ideographs Word sets in
            // Noto Sans SC; PMingLiU and the others it has draw their own —
            // zh-db93607e's in PMingLiU are as any character in Word's print.)
            face.lacksCompatibilityIdeographs = ea.height == yaHei.height
            // (What an embedded subset lacks, Word sets in the face the
            // name has unembedded — YaHei, for the names it stands in
            // for — and the line takes that face's height: zh-92373179's
            // FangSong_GB2312 holds none of "运用", "易", "贡献", and its
            // 1.5-spaced 16pt lines that hold one are 41.2pt apart in
            // Word's print, YaHei's, where the subset's square line made
            // them 31.2.)
            if own, let registered = embeddedFamily(family), let covered = embeddedCovers(registered),
               eastAsianFace(family, ignoringEmbedding: true).height == yaHei.height {
                face.covers = covered
                face.uncoveredFamily = "Microsoft YaHei"
            }
            face.symbolFamily = ea.symbols
            // (YaHei's ellipsis is its own width, not an em: 0.8135, and
            // 0.9629 in bold, by msyh.ttc and msyhbd.ttc. zh-457a8d62's
            // "……" in 標楷體 runs — YaHei to Word on a Mac — are 13.52pt
            // apiece at 16pt on its grid in Word's print, where the stand-in's
            // em-wide glyph set them 17.01.)
            // (And its middle dot, a run's "·" Word sets in the East
            // Asian face — `w:hint`: 0.2407 em, 0.4395 bold, where the
            // Latin stand-in's is Arial's 0.333. zh-6d1afa56's
            // "·申报内容（含项目名称、项" fills its cell's 106.2pt in
            // Word's print, its dot 2.2pt; ours put "项" on the next line.)
            // (Its "√", "─" and "■" too: 0.7017, 0.7085 and 0.604 em —
            // zh-6d1afa56's ticks, rules and boxes in Word's print — where
            // the stand-in drew Liberation Sans's √ at 0.549, and the box
            // an em.)
            // (And its em dash, 1.0801 em regular and bold, where the
            // stand-in's is an em: zh-8d6f702e's "160—230" sets "—"
            // 17.18pt at 16pt on its grid of -0.21 in Word's print, ours
            // 15.79, and the line then took "累", which Word wraps.)
            // (And its hyphenation point "‧", U+2027, a dot as narrow:
            // 0.2407 em, 0.2861 bold. zh-5f9b6549's 標楷體 title,
            // "…場域實證‧共創解題」補", fills its text box in Word's print,
            // the dot 3.37pt at 14pt; ours set it half an em and wrapped
            // "補".)
            if ea.height == yaHei.height {
                face.otherAdvances = [0x2026: 0.8135, 0x2014: 1.0801, 0xB7: 0.2407, 0x2027: 0.2407, 0x221A: 0.7017, 0x2500: 0.7085, 0x25A0: 0.604].merging(circled(1.0)) { $1 }
                face.boldOtherAdvances = [0x2026: 0.9629, 0x2014: 1.0801, 0xB7: 0.4395, 0x2027: 0.2861].merging(circled(1.0)) { $1 }
            }
            // (The square faces set GB2312's Latin-1 symbols an em, as
            // their ideographs: a "°" in a run Word sets in 宋体 — `w:hint`
            // eastAsia — is 10.50 at 10.5pt in its print of zh-cd8987db,
            // and "°" and "×" are an em in SimSun and SimHei wherever
            // Word's prints have them; the stand-in drew its own 0.4 em
            // "°", and "5.5.1 坡度＜25°…" took the "土中。" Word's leaves.)
            if ea.latin == mono, face.otherAdvances == nil {
                let gb: [UInt32: Double] = [0xA4: 1, 0xA7: 1, 0xA8: 1, 0xB0: 1, 0xB1: 1, 0xD7: 1, 0xF7: 1]
                face.otherAdvances = gb
                face.boldOtherAdvances = gb
            }
            face.scaledHeight = ea.scaledHeight
            face.scaledBaseline = ea.scaledBaseline
            face.boldHeight = ea.boldHeight
            face.boldBaseline = ea.boldBaseline
            return face
        }
        var face = RichResolvedFace(family: ea.latin, sizeScale: ea.latinScale, naturalHeight: ea.height,
                                    boldSpread: ea.fakeBold ? ea.boldWiden ?? 1.0 / 48 : 0, classScales: ea.latinClasses, baseline: ea.baseline,
                                    isEastAsian: true)
        // (What the Latin stand-in lacks, the face the name stands for
        // draws: Word sets zh-117cf7c6's "※" bullet, 標楷體 with no hint,
        // in YaHei, and its line is that face's height. Left to the glyph
        // fallback, Linux drew it in DejaVu Sans and the line stood 2.5pt
        // short; the Mac's system fallback found PingFang.)
        if !own || embeddedFamily(family) == nil { face.fallback = [substitute(family)] + cjkFallback }
        face.scaledHeight = ea.scaledHeight
        face.scaledBaseline = ea.scaledBaseline
        face.boldHeight = ea.boldHeight
        face.boldBaseline = ea.boldBaseline
        face.advances = ea.latinAdvances
        face.boldAdvances = ea.latinBoldAdvances
        face.kerns = ea.latinKerns
        face.boldKerns = ea.latinBoldKerns
        face.symbolFamily = ea.symbols
        // (YaHei's middle dot, which its table of ASCII widths leaves to
        // the stand-in's: see the East Asian face above.)
        // (And its circled numbers, an em: Word's print of zh-34a6519a sets
        // "①".."⑤" in YaHei 12.0pt apart at 12pt and 10.5 at 10.5, where
        // the stand-in, which has none, drew DejaVu's at 0.9 — "⑤有应急…"
        // then took "承" on its first line by a squeeze Word's does not
        // make, and every page from p11 ran early.)
        if ea.height == yaHei.height {
            face.otherAdvances = [0xB7: 0.2407].merging(circled(1.0)) { $1 }
            face.boldOtherAdvances = [0xB7: 0.4395].merging(circled(1.0)) { $1 }
        }
        // A no-break space in a square face is an em, where its space is
        // half of one (lab `nb1`, Word 16, 2026-10-15: "甲" + ten U+00A0 +
        // "乙" at 12pt is 12pt a space in 宋体, 黑体, 楷体 and 仿宋, 6pt
        // with U+0020; 3pt in a run whose Latin face is Times, 3.55 in
        // YaHei, its own). Chinese forms space their "年  月  日" lines
        // with them: zh-0aac9d1a's stamp line holds 18 before its "日"
        // and is 444pt to there in Word's print, where it was 336 here.
        if ea.latin == mono, ea.latinAdvances == nil {
            face.otherAdvances = [0xA0: 1.0]
            face.boldOtherAdvances = [0xA0: 1.0]
        }
        return face
    }

    /// The faces this platform draws Chinese in where the named one is
    /// missing, after the symbol fallback (`RichTextTheme.glyphFallback`):
    /// what the Latin side of an East Asian family falls back to first.
    nonisolated(unsafe) static var cjkFallback: [String] = []

    /// Starling FangSong: Zhuque Fangsong (OFL) set to FangSong's metrics —
    /// its Latin half an em, its curly quotes and full-width forms an em,
    /// a line of one em (Resources/fonts/README.md). Whether it loaded.
    static let starlingFangSong = "Starling FangSong"
    nonisolated(unsafe) static var _fangSongLoaded = false

    /// The face that draws a 仿宋 name's ideographs, where it is one:
    /// Starling FangSong, in place of the system's fallback (PingFang, a
    /// sans). Its widths are FangSong's, so no line moves; only the
    /// drawing does. Under OFFICE_WORD_FONTS=mac only the names Word for
    /// Mac draws in its own FangSong — 仿宋 and FangSong; there
    /// 仿宋_GB2312 and the 方正 names are YaHei's, as in its prints. In a
    /// document shown as its author had it, those too. (华文仿宋 is a
    /// face of its own, and keeps its own.)
    static func fangSongFamily(_ family: String) -> String? {
        guard _fangSongLoaded else { return nil }
        let n = family.trimmingWhitespace().lowercased()
        if n == "仿宋" || n == "fangsong" { return starlingFangSong }
        guard !wordOnMac, !n.containsSubstring("华文"), !n.hasPrefix("st") else { return nil }
        // (As Word for Windows sets it: a name it lacks is FangSong only
        // where its font table gives 仿宋 for it — `wordOnWindows`.)
        if wordOnWindows {
            let a = altName(family)?.trimmingWhitespace().lowercased() ?? ""
            return (a == "仿宋" || a == "fangsong") ? starlingFangSong : nil
        }
        return n.containsSubstring("仿宋") || n.containsSubstring("fangsong") ? starlingFangSong : nil
    }

    /// Whether `wordSans` and `wordSerif` are registered.
    nonisolated(unsafe) static var _gapAboveLoaded = false

    /// A face's line gap moved over its ascent (`hhea`: the ascender
    /// takes the gap, which is then 0), in place; false when the data
    /// has no such table. The engine shares a face's gap out half over
    /// its text and half under it; Word sets the whole of it over —
    /// Times New Roman's baseline .891 + .042 down its 1.15-em line —
    /// so a line where Times stands beside a face with none (Cambria)
    /// is that face's ascent and Times's descent in Word, and the
    /// engine's half-gap deeper. bug59058's references, 13pt Times at
    /// least 15pt with Cambria titles, step 15.24 in Word's print where
    /// a title is on the line and 15.45 here, 2.3pt by a page's foot.
    /// (And `OS/2`'s Windows ascent raised by as much: DirectWrite takes
    /// a face's ascent from `usWinAscent` and its gap from what `hhea`
    /// says beyond the Windows ascent and descent, so on Windows the
    /// `hhea` change alone moved nothing — bug59058's mixed lines stepped
    /// 15.45 there, 75% of its lines, where Linux's are Word's and 100%.)
    static func _gapAbove(_ data: inout Data) -> Bool {
        func u16(_ at: Int) -> Int { Int(data[at]) << 8 | Int(data[at + 1]) }
        func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
        guard data.count > 12 else { return false }
        let tables = u16(4)
        func table(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            for k in 0 ..< tables {
                let entry = 12 + 16 * k
                guard entry + 16 <= data.count else { return nil }
                if data[entry] == t[0], data[entry + 1] == t[1], data[entry + 2] == t[2], data[entry + 3] == t[3] { return u32(entry + 8) }
            }
            return nil
        }
        guard let at = table("hhea"), at + 10 <= data.count else { return false }
        let ascender = Int16(truncatingIfNeeded: u16(at + 4)), gap = Int16(truncatingIfNeeded: u16(at + 8))
        guard gap > 0 else { return true }
        let raised = UInt16(bitPattern: ascender &+ gap)
        data[at + 4] = UInt8(raised >> 8); data[at + 5] = UInt8(raised & 0xFF)
        data[at + 8] = 0; data[at + 9] = 0
        if let os2 = table("OS/2"), os2 + 78 <= data.count {
            let win = UInt16(truncatingIfNeeded: u16(os2 + 74) + Int(gap))
            data[os2 + 74] = UInt8(win >> 8); data[os2 + 75] = UInt8(win & 0xFF)
        }
        return true
    }

    /// The theme's `averageCharWidth`: the OS/2 average character width
    /// of the face Word sets a Latin name in, in ems.
    static func averageCharWidth(_ family: String?) -> Double {
        // (An East Asian face counts half an em whatever its own
        // average: 4.0pt at 16pt beside YaHei's digits as beside 宋体's.)
        guard let family, !isEastAsianFace(family), !family.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) else { return 0.5 }
        switch substitute(family) {
        case serif: return 0.401
        case mono: return 0.6
        case calibri: return 0.52
        case cambria: return 0.55
        default: return 0.441
        }
    }

    /// Families the font menu offers. On macOS CoreText resolves any
    /// installed family by name, so a few system faces join the list.
    /// The names Word users know, which the document keeps; each draws
    /// with its clone from `substitute`. The same list on every platform.
    /// New documents start in Calibri, as Word's did for fifteen years.
    static let defaultFamily = "Calibri"
    static let families = ["Calibri", "Arial", "Times New Roman", "Cambria", "Courier New"]

    /// The list with the current family in it, wherever it came from.
    static func families(including current: String?) -> [String] {
        guard let current, !current.isEmpty, !families.contains(current) else { return families }
        return families + [current]
    }

    nonisolated(unsafe) private static var _registered = false
    nonisolated(unsafe) private static var _registrationSucceeded = false

    #if canImport(ObjectiveC)
    private final class ResourceOwner: NSObject {}
    #endif

    private static func _bundle(_ name: String) -> Bundle? {
        var roots: [URL] = []
        #if canImport(ObjectiveC)
        // Under XCTest this module is in the test bundle, while main is
        // Xcode's test runner. SwiftPM puts our resources beside the code.
        if let resources = Bundle(for: ResourceOwner.self).resourceURL { roots.append(resources) }
        // (And beside the test bundle: the command line's `swift test` puts
        // OfficeApp_OfficeApp.bundle in .build/<config>, next to
        // OfficeAppPackageTests.xctest, not inside it, and the runner is
        // /usr/bin/xctest — no shipped font loaded, and layout tests ran
        // on the system's faces.)
        roots.append(Bundle(for: ResourceOwner.self).bundleURL.deletingLastPathComponent())
        #endif
        if let resources = Bundle.main.resourceURL { roots.append(resources) }
        roots.append(Bundle.main.bundleURL)
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() { roots.append(exe) }
        for root in roots {
            for suffix in ["bundle", "resources"] {
                if let b = Bundle(url: root.appendingPathComponent("\(name).\(suffix)")) { return b }
            }
        }
        return nil
    }

    /// The files of Slides' free faces and the family each is loaded as.
    static let slideFaces: [(String, String)] = {
        var faces: [(String, String)] = []
        for (file, family) in [("Poppins", "Poppins"), ("WorkSans", "Work Sans"), ("LibreFranklin", "Libre Franklin")] {
            faces += ["Regular", "Bold", "Italic", "BoldItalic"].map { ("\(file)-\($0).ttf", family) }
        }
        for weight in ["Light", "Medium", "SemiBold", "Black"] {
            faces += [("Poppins-\(weight).ttf", "Poppins \(weight)"), ("Poppins-\(weight)Italic.ttf", "Poppins \(weight)")]
        }
        for weight in ["Light", "Medium"] {
            faces += [("WorkSans-\(weight).ttf", "Work Sans \(weight)"), ("WorkSans-\(weight)Italic.ttf", "Work Sans \(weight)")]
        }
        faces += [("LibreFranklin-Medium.ttf", "Libre Franklin Medium"), ("LibreFranklin-MediumItalic.ttf", "Libre Franklin Medium")]
        faces += [("ArchivoBlack-Regular.ttf", "Archivo Black")]
        faces += [("SelawikDoc-Regular.ttf", "Selawik Doc"), ("SelawikDoc-Bold.ttf", "Selawik Doc"),
                  ("SelawikDoc-Light.ttf", "Selawik Doc Light"), ("SelawikDoc-Semilight.ttf", "Selawik Doc Semilight"),
                  ("SelawikDoc-Semibold.ttf", "Selawik Doc Semibold")]
        for (file, family) in [("TeXGyreCursor", "TeX Gyre Cursor"), ("TeXGyreAdventor", "TeX Gyre Adventor"), ("TeXGyrePagella", "TeX Gyre Pagella")] {
            faces += ["Regular", "Bold", "Italic", "BoldItalic"].map { ("\(file)-\($0).otf", family) }
        }
        return faces
    }()

    @discardableResult
    static func register() -> Bool {
        if _registered { return _registrationSucceeded }
        _registered = true
        #if os(WASI)
        // The page preloads UI/default faces. Other document families are
        // requested by the paragraph builder when used and trigger relayout
        // once registered (build/web-app.sh writes fonts/manifest.json,
        // with `wordSans` and `wordSerif` among them, made as below).
        _gapAboveLoaded = true
        _registrationSucceeded = true
        return true
        #else
        // (#else, not an early return: the body below names FileHandle,
        // which the web link does not have, and whether dead code after a
        // return reaches the linker depends on what got inlined where.)
        // The ribbon's glyphs and its face: the Fluent System Icons font and
        // Selawik ship in the SDK and are registered by whoever draws them
        // (the shell does the same).
        _ = FluentSystemIcons.registerFont()
        _ = SelawikFont.registerFont()
        // Coverage for what the document faces lack (⌘, arrows): the browser
        // build lists DejaVu Sans as its glyph fallback and macOS has the
        // system's; Linux and Windows have neither, so the same face is
        // loaded here and every document style falls back to it.
        #if !os(macOS) && !os(iOS)
        if let symbols = TerminalFontLoader.registerSymbolFallback() {
            RichTextTheme.glyphFallback = [symbols]
        }
        #if os(Windows)
        // Chinese text, named as on macOS: left to the platform, the
        // engine picks a face per run from its first character, and a
        // run of a lone "〕" came out in Yu Gothic UI, whose brackets are
        // half an em — a line of zh-1a3c7aa0 then had room for a digit
        // Word's has not. YaHei is the face Word for Mac sets these in.
        cjkFallback = ["Microsoft YaHei"]
        RichTextTheme.glyphFallback += cjkFallback
        #elseif os(Linux)
        // Chinese text, named: the engine's Linux font manager reads
        // /usr/share/fonts but finds no face for a character itself, so
        // with nothing named every ideograph was a missing-glyph box.
        // Noto Sans CJK (Ubuntu's fonts-noto-cjk) is square like YaHei,
        // its brackets and marks a full em; the rest are what other
        // distributions carry.
        cjkFallback = ["Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei", "Droid Sans Fallback"]
        RichTextTheme.glyphFallback += cjkFallback
        // (And math letters, the same way: Cambria Math's formulas are
        // runs of Mathematical Alphanumeric Symbols — 𝑆, 𝑧, 𝛼 — which
        // no face named above has, and bug57031's printed as boxes. Set
        // at Cambria Math's widths whichever draws them; a serif first,
        // as Cambria Math is.)
        RichTextTheme.glyphFallback += ["STIX Two Math", "DejaVu Math TeX Gyre", "Noto Sans Math"]
        #endif
        #else
        // Chinese text is drawn by the system's face, which the engine
        // finds character by character — and finds in its regular weight
        // whatever was asked: no bold heading was bold. Named as a
        // fallback family it is matched like one, weight and all.
        RichTextTheme.glyphFallback = ["PingFang SC"]
        #endif
        guard let bundle = _bundle("OfficeApp_OfficeApp") else {
            FileHandle.standardError.write("[Office] font bundle not found; documents use the engine's default face\n".data(using: .utf8)!)
            return false
        }
        // Xcode's SwiftPM backend uses Contents/Resources; the native
        // backend and our staged app use a flat resource bundle.
        let resources = bundle.resourceURL ?? bundle.bundleURL
        var ok = true
        var gapAboveFailed = false
        for (file, family) in [("LiberationSans", sans), ("LiberationSerif", serif), ("LiberationMono", mono),
                               ("Carlito", calibri), ("Caladea", cambria), ("DejaVuSans", verdana)] {
            for variant in ["Regular", "Bold", "Italic", "BoldItalic"] {
                let path = resources.appendingPathComponent("fonts/\(file)-\(variant).ttf").path
                if !flutter.swift_bridge.LoadFontFromFile(path, family) {
                    ok = false
                    FileHandle.standardError.write("[Office] could not load \(path)\n".data(using: .utf8)!)
                }
                if family == sans || family == serif, var data = FileManager.default.contents(atPath: path), _gapAbove(&data) {
                    let loaded = data.withUnsafeBytes { buffer in
                        buffer.baseAddress.map {
                            flutter.swift_bridge.LoadFontFromList($0.assumingMemoryBound(to: UInt8.self), buffer.count, family == sans ? wordSans : wordSerif)
                        } ?? false
                    }
                    if !loaded { gapAboveFailed = true }
                }
            }
        }
        _gapAboveLoaded = !gapAboveFailed
        // 仿宋's ideographs in a 仿宋 face (`fangSongFamily`).
        let fangSong = resources.appendingPathComponent("fonts/StarlingFangSong-Regular.ttf").path
        if FileManager.default.fileExists(atPath: fangSong) {
            if flutter.swift_bridge.LoadFontFromFile(fangSong, starlingFangSong) {
                _fangSongLoaded = true
            } else {
                FileHandle.standardError.write("[Office] could not load \(fangSong)\n".data(using: .utf8)!)
            }
        }
        if gapAboveFailed {
            FileHandle.standardError.write("[Office] the Word line faces did not load; Times and Arial lines keep the engine's gap\n".data(using: .utf8)!)
        }
        // Slides' free faces (Resources/fonts/README.md), each file under
        // the family `SlideFonts.resolve` names.
        for (file, family) in slideFaces {
            let path = resources.appendingPathComponent("fonts/\(file)").path
            if !flutter.swift_bridge.LoadFontFromFile(path, family) {
                ok = false
                FileHandle.standardError.write("[Office] could not load \(path)\n".data(using: .utf8)!)
            }
        }
        _registrationSucceeded = ok
        return ok
        #endif
    }
}
