// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation
#if os(macOS) || os(iOS)
import CoreText
#endif
#if os(Windows)
import WinSDK
#endif

/// The document faces Office ships: Liberation Sans/Serif/Mono, Carlito and
/// Caladea — metric clones of Arial/Times/Courier, Calibri and Cambria — so
/// a `.docx` written in those reflows the same here. Registered by path
/// (mmap, shared, evictable), each family's four files under one name —
/// the font manager picks weight and slant.
///
/// A document keeps the font names it came with; `substitute` maps a name
/// to the shipped face at render time (the theme's `fontFamilyResolver`),
/// the way Google Docs draws "Times New Roman" with Tinos. So the file
/// round-trips its fonts untouched. Where the machine has the face the
/// document names, that face draws it (`fontSource`, the user's choice;
/// `drawn`), and the stand-ins only where it has none.
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
    /// Noto Sans, the face a document names when it names it (bundled; v1.04, Apache 2.0).
    static let notoSans = "Noto Sans"
    static let cambria = "Caladea"
    /// DejaVu Sans, for Verdana: not a metric clone, but of the same
    /// family (both grew out of Bitstream Vera's design) and within a
    /// hundredth of its widths word for word, where Liberation Sans set
    /// Verdana's lines an eighth short.
    static let verdana = "DejaVu Sans"
    /// The colour-emoji face (U+1F000 and up), first in the glyph fallback; web hosts use the same name.
    static let emojiPictographs = "Noto Color Emoji Pictographs"
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
        if let alt = macTableAlternate(family) { return substitute(alt) }
        switch n {
        case "liberation sans", "arial", "helvetica", "helvetica neue", "tahoma", "raavi",
             "segoe ui", "aptos", "arimo", "arial black", "montserrat":
            return sans
        case "verdana", "dejavu sans", "bitstream vera sans":
            // (Windows has no DejaVu Sans: Word takes the font table's alternate. lo-9eaf41a6's entry says Times New
            // Roman, and its empty 12pt header line stands 13.8pt high in Word's print, not Verdana's 14.6: the body
            // and the floating tables on both pages stood 1.0pt low, every line with them.)
            if wordOnWindows, n == "dejavu sans", let alt = fontEntry(family)?.alt, !alt.isEmpty { return substitute(alt) }
            return verdana
        case "liberation serif", "times new roman", "times", "georgia", "book antiqua",
             "garamond", "palatino", "palatino linotype", "tinos":
            // (Windows has no Liberation Serif: Word takes the font table's
            // alternate, else its signature's face — `windowsSigFace`.)
            if wordOnWindows, n == "liberation serif", let by = windowsSigFace(family) { return substitute(by) }
            // (An entry whose alternate is Cambria: ukr-z4769265's body is
            // Cambria in Word's print. Times New Roman alternates print Times.)
            if wordOnWindows, n == "liberation serif", let alt = fontEntry(family)?.alt,
               alt.trimmingWhitespace().lowercased() == "cambria" { return cambria }
            return serif
        case "liberation mono", "courier new", "courier", "consolas", "menlo", "monaco",
             "lucida console", "cousine":
            return mono
        case "carlito", "calibri", "calibri light":
            // (The Windows box has no Carlito, and a file with no font-table
            // entry for it gives Word nothing to go by: its print draws the
            // run in Cambria — lo-47598455's 6pt marks are 7.03pt lines. With
            // an entry (lo-ff3b52d1) it is Calibri.)
            if wordOnWindows, n == "carlito", fontEntry(family) == nil { return cambria }
            return calibri
        case "caladea", "cambria":
            return cambria
        case "noto sans":
            // (Noto Sans itself, bundled: a document that names it — LibreOffice's
            // fdo77887, fdo48718-1 — was set in Carlito, and every line stood
            // elsewhere in Word's print, which has the real face.)
            return notoSans
        default:
            // ("code" as in Source Code Pro — not as in Lucida Sans Unicode,
            // which came up monospace for a while.)
            if faceHas(n, "mono") || faceHas(n, "courier")
                || (faceHas(n, "code") && !faceHas(n, "unicode")) {
                return mono
            }
            // (A name only: not one Word has no face for that the file's
            // table describes, which goes by the table below —
            // zh-c399c91a's "LinTimes", PANOSE Times's and no alternate,
            // is Calibri in Word's print, its "/" 4.06pt at 10.5, where
            // ours took Times and a cell's "门" stayed on the line.)
            let byTable = !wordMacFamilies.contains(n) && !family.unicodeScalars.contains { $0.value >= 0x2E80 && !(0xFB00 ... 0xFB06).contains($0.value) } && fontEntry(family) != nil
            if !byTable, faceHas(n, "serif") && !faceHas(n, "sans") { return serif }
            if !byTable, faceHas(n, "times") || faceHas(n, "roman") || faceHas(n, "garamond")
                || faceHas(n, "baskerville") || faceHas(n, "didot") {
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
            // (A mangled Latin name, "pNﬂ∑˛" for Calibri — its ligature U+FB02 — is not East Asian:
            // ita-z13342017's body, alternate Calibri, is Calibri in Word's print.)
            let eastAsianName = family.unicodeScalars.contains { $0.value >= 0x2E80 && !(0xFB00 ... 0xFB06).contains($0.value) }
            // (Word for Windows takes the table's alternate whatever the
            // PANOSE: bug59058's MinionPro-Regular and drawing's
            // PragmaticaC-Bold, alternate Times New Roman and PANOSE all
            // zeros, are Times New Roman in its prints (word-win), where
            // the Mac's are Cambria. And Windows' own FontSubstitutes name
            // a script's variant of a face for the face: "Arial CYR" is
            // Arial, "Times New Roman CYR" Times New Roman.)
            if wordOnWindows, !eastAsianName {
                for suffix in [" cyr", " ce", " baltic", " greek", " tur"] where n.hasSuffix(suffix) {
                    return substitute(String(family.trimmingWhitespace().dropLast(suffix.count)))
                }
                // (An alternate "Courier": Windows has only Courier New, so Word does not follow it. xa gv-0de3e9bcf1's
                // Sabon (roman) and Frutiger 55 (swiss), alternate Courier, PANOSE zeros, print as Cambria and Calibri.)
                if !wordMacFamilies.contains(n), let e = fontEntry(family), let alt = e.alt, !alt.isEmpty,
                   alt.trimmingWhitespace().lowercased() != n, alt.trimmingWhitespace().lowercased() != "courier" {
                    return substitute(alt)
                }
                if !wordMacFamilies.contains(n), let by = windowsSigFace(family) { return by == "ebrima" ? sans : substitute(by) }
            }
            if !eastAsianName, !wordMacFamilies.contains(n) {
                if let e = fontEntry(family) {
                    if let alt = e.alt, !alt.isEmpty, !e.panoseZero, alt.trimmingWhitespace().lowercased() != n,
                       !(wordOnWindows && alt.trimmingWhitespace().lowercased() == "courier") { return substitute(alt) }
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

    /// Whether a face name holds a keyword: `containsSubstring`, remembered. It is a pure function
    /// of the two strings (so nothing ever invalidates the memory), asked ~40 times per text span by
    /// the stand-in and East Asian face lookups with the same few names; searching by character,
    /// each answer cost more than the rest of the span. Bounded: a long-lived editor that meets
    /// many names starts over rather than grow.
    nonisolated(unsafe) private static var hasMemo: [String: [String: Bool]] = [:]
    #if os(WASI)
    private static let hasLock = _NoLock()
    #else
    private static let hasLock = NSLock()
    #endif
    static func faceHas(_ name: String, _ key: String) -> Bool {
        hasLock.lock()
        if let hit = hasMemo[name]?[key] { hasLock.unlock(); return hit }
        hasLock.unlock()
        let answer = name.containsSubstring(key)
        hasLock.lock()
        if hasMemo.count > 4096 { hasMemo.removeAll() }
        hasMemo[name, default: [:]][key] = answer
        hasLock.unlock()
        return answer
    }
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
    /// A file's font-table entry: its alternate, family, whether its
    /// PANOSE is all zeros, its charset, and the first two words of its
    /// Unicode signature (`w:sig`'s usb0 and usb1).
    /// The font table's alternate Word for Mac sets a Liberation face in,
    /// which it has none of — as it does any Latin name it lacks (see
    /// `substitute`), where the clones' names had stood for their
    /// originals here. Lab t209b (Mac Word, zh-4adfcce2 with zh-5f9b6549's
    /// fontTable.xml, the one part of six that moves it): Normal's
    /// "Liberation Serif", alternate 新細明體 and no PANOSE, sets the
    /// empty paragraph Word adds under a header (a file with a
    /// background) in 12pt PMingLiU, 15.6 a line; with no alternate, in
    /// Times — and the page's body 1.8pt higher. Nil elsewhere.
    static func macTableAlternate(_ family: String) -> String? {
        guard wordOnMac else { return nil }
        let n = family.trimmingWhitespace().lowercased()
        guard n.hasPrefix("liberation "), let e = fontEntry(family), let alt = e.alt, !alt.isEmpty, !e.panoseZero,
              !alt.trimmingWhitespace().lowercased().hasPrefix("liberation") else { return nil }
        return alt
    }

    struct FontEntry {
        var alt: String?; var family: String; var panoseZero: Bool; var charset: String = ""; var usb0: UInt32? = nil; var usb1: UInt32? = nil
        /// The family of the table's last entry for the name, where it repeats
        /// one — the entry Word for Mac reads (lab tsim2, see `eastAsianFace`).
        var lastFamily: String? = nil
    }
    nonisolated(unsafe) private static var fontEntries: [String: FontEntry] = [:]
    /// Whether the document's text holds Devanagari to Malayalam letters: Arial Unicode MS there is the Word layout's own path (Yu Gothic or Leelawadee
    /// UI by run), not the shared missing-face stand-in (which took dx2 31a0a560 from 100 to 3.8).
    nonisolated(unsafe) private static var indicText = false
    static func noteIndicText(_ on: Bool) { declaredLock.lock(); defer { declaredLock.unlock() }; indicText = on }
    static var documentHasIndicText: Bool { declaredLock.lock(); defer { declaredLock.unlock() }; return indicText }
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
        if let own = installed(family) { return own }
        #if os(Windows)
        // A face Windows has and this app has no clone of is the face, for
        // every character of the cell: style-alternate-content's 맑은 고딕
        // prints its digits, Latin and "○○○" in Malgun Gothic, where ours
        // set them in Liberation Sans and only the Hangul fell back to
        // Malgun; the format tests' Lucida Sans Typewriter is monospaced,
        // and Liberation Sans was not.
        if let face = windowsFaces[family.trimmingWhitespace().lowercased()] { return face }
        // (And a face it has no file for is Arial's, as Excel prints it —
        // Arial itself, where the clone's letters are Liberation Sans'.)
        let clone = sheetClone(family)
        if clone == sans, let arial = windowsFaces["arial"] { return arial }
        return clone
        #else
        return sheetClone(family)
        #endif
    }

    /// Whether `sheetFace` is the named face itself, not a stand-in.
    static func sheetFaceIsOwn(_ family: String) -> Bool {
        if installed(family) != nil { return true }
        #if os(Windows)
        return windowsFaces[family.trimmingWhitespace().lowercased()] != nil
        #else
        return false
        #endif
    }

    /// The clone of `sheetFace`, whatever the platform has: the face whose
    /// measures the sheet's print metrics borrow for a face nobody measured.
    /// A name Excel has no face for prints in Arial, where Word's guess
    /// was Cambria: HelveticaNeue LightExt (47862), Frutiger 45 Light,
    /// Clear Sans, FreeSans, lo-tdf171828's header in BernhardFashion BT.
    static func sheetClone(_ family: String) -> String {
        let face = substitute(family)
        let n = family.trimmingWhitespace().lowercased()
        // (Monospaced in Excel's prints, 0.6 em: the number-format books' Lucida Sans Typewriter cells. Only a cell's own face: as a
        // glyph-fallback name it moved CVLKRA-KYC, 51519 and others.)
        if n == "lucida sans typewriter" { return mono }
        if face == cambria, !n.hasPrefix("cambria"), n != "caladea" { return sans }
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
            // (Excel_file_with_trash_item's Tahoma 10 stood a point under
            // its row's Calibri in Liberation Sans.)
            (["tahoma"], "Tahoma", "tahoma.ttf"),
            (["segoe ui"], "Segoe UI", "segoeui.ttf"),
            (["georgia"], "Georgia", "georgia.ttf"),
            (["consolas"], "Consolas", "consola.ttf"),
            (["book antiqua"], "Book Antiqua", "BKANT.TTF"),
            (["calibri light"], "Calibri Light", "calibril.ttf"),
            (["verdana"], "Verdana", "verdana.ttf"),
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
            // (Their clones have their measures, not their letters: a page of
            // Arial 10, lo-pivottable_invalid_formats', within half a point of
            // Excel's everywhere and 9.9% apart in its glyphs.)
            (["arial"], "Arial", "arial.ttf"),
            (["times new roman"], "Times New Roman", "times.ttf"),
            (["calibri"], "Calibri", "calibri.ttf"),
            (["cambria"], "Cambria", "cambria.ttc"),
            (["courier new"], "Courier New", "cour.ttf"),
            (["candara"], "Candara", "Candara.ttf"),
            (["constantia"], "Constantia", "constan.ttf"),
            (["corbel"], "Corbel", "corbel.ttf"),
        ] where FileManager.default.fileExists(atPath: fonts + file) { for n in names { m[n] = face } }
        for (face, _) in cloudFaces { m[face.lowercased()] = face }
        return m
    }()

    /// Faces Office downloads for itself, into its own font cache, which
    /// Windows does not list — Excel prints Aptos Narrow, the default
    /// font of today's workbooks, in Aptos Narrow — with the files of each.
    /// Registered by `register`.
    static let cloudFaces: [(face: String, files: [String])] = {
        let cache = (ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? "") + "/Microsoft/FontCache/4/CloudFonts/"
        return ["Aptos", "Aptos Narrow", "Aptos Display"].compactMap { face in
            let dir = cache + face + "/"
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
                .filter { $0.lowercased().hasSuffix(".ttf") }.sorted().map { dir + $0 }
            return files.isEmpty ? nil : (face, files)
        }
    }()

    /// Every family name this Windows's font files give themselves, in each
    /// language they give it, to the one they give in English — 仿宋 and
    /// FangSong to FangSong, 新細明體 to PMingLiU — read from the files'
    /// `name` tables, as DirectWrite lists them: the system's fonts and the
    /// user's own. (The face table alone left FangSong, SimHei, KaiTi,
    /// PMingLiU, DFKai-SB and DengXian to the stand-ins in local mode,
    /// though every Windows has them.) A symbol-encoded face — Symbol,
    /// Wingdings — is left out: a document's symbol characters are mapped
    /// for the stand-ins, and its own code page would lose them.
    private static let systemFamilies: [String: String] = {
        let env = ProcessInfo.processInfo.environment
        var m: [String: String] = [:]
        for dir in [(env["WINDIR"] ?? "C:/Windows") + "/Fonts/", (env["LOCALAPPDATA"] ?? "") + "/Microsoft/Windows/Fonts/"] {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
                let ext = String(file.lowercased().suffix(4))
                guard ext == ".ttf" || ext == ".otf" || ext == ".ttc" || ext == ".otc" else { continue }
                for (english, names) in familyNames(dir + file) {
                    for name in names where m[name.lowercased()] == nil { m[name.lowercased()] = english }
                }
            }
        }
        return m
    }()

    /// The family names (name ID 1, Windows platform) of each face in a font
    /// file, the English one first of all; none for a symbol-encoded face.
    static func familyNames(_ path: String) -> [(english: String, names: [String])] {
        guard let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        func read(_ at: UInt64, _ count: Int) -> [UInt8] {
            guard count > 0, (try? h.seek(toOffset: at)) != nil, let d = try? h.read(upToCount: count) else { return [] }
            return [UInt8](d)
        }
        func u16(_ b: [UInt8], _ i: Int) -> Int { i >= 0 && i + 1 < b.count ? Int(b[i]) << 8 | Int(b[i + 1]) : 0 }
        func u32(_ b: [UInt8], _ i: Int) -> UInt64 { UInt64(u16(b, i)) << 16 | UInt64(u16(b, i + 2)) }
        let head = read(0, 12)
        guard head.count == 12 else { return [] }
        var offsets: [UInt64] = [0]
        if head[0 ..< 4].elementsEqual([0x74, 0x74, 0x63, 0x66]) {   // "ttcf"
            let n = Int(min(u32(head, 8), 64))
            let table = read(12, 4 * n)
            offsets = (0 ..< n).map { u32(table, 4 * $0) }
        }
        var out: [(english: String, names: [String])] = []
        for offset in offsets {
            let tables = u16(read(offset, 12), 4)
            let records = read(offset + 12, 16 * tables)
            guard let k = (0 ..< tables).first(where: {
                records.count >= 16 * $0 + 16 && records[16 * $0 ..< 16 * $0 + 4].elementsEqual([0x6E, 0x61, 0x6D, 0x65])   // "name"
            }) else { continue }
            let t = read(u32(records, 16 * k + 8), Int(min(u32(records, 16 * k + 12), 1 << 20)))
            let count = u16(t, 2), strings = u16(t, 4)
            var english: String? = nil, names: [String] = [], symbol = false
            for r in 0 ..< count {
                let at = 6 + 12 * r
                guard u16(t, at) == 3 else { continue }
                let encoding = u16(t, at + 2), language = u16(t, at + 4)
                if encoding == 0 { symbol = true }
                guard u16(t, at + 6) == 1, encoding == 1 || encoding == 10 else { continue }
                let start = strings + u16(t, at + 10), length = u16(t, at + 8)
                guard length >= 2, start + length <= t.count else { continue }
                let units = stride(from: start, to: start + length - 1, by: 2).map { UInt16(t[$0]) << 8 | UInt16(t[$0 + 1]) }
                let name = String(decoding: units, as: UTF16.self)
                if language == 0x409 { english = name }
                if !name.isEmpty { names.append(name) }
            }
            if !symbol, let first = english ?? names.first { out.append((first, names)) }
        }
        return out
    }
    #endif

    private static func fontEntry(_ family: String) -> FontEntry? {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        return fontEntries[family.trimmingWhitespace().lowercased()]
    }
    /// A Liberation, DejaVu or Noto face (none of them Word for Windows'
    /// own) whose font-table entry is charset 80 with the alternate Times
    /// New Roman: the case lab tdf measured (`standInFace`).
    private static func charsetEightyLatinFace(_ family: String) -> Bool {
        let n = family.trimmingWhitespace().lowercased()
        guard n.hasPrefix("liberation ") || n.hasPrefix("dejavu ") || n.hasPrefix("noto "), !isEmbedded(family),
              let e = fontEntry(family), e.charset.uppercased() == "80",
              e.alt?.trimmingWhitespace().lowercased() == "times new roman" else { return false }
        return true
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
    /// Each loaded embedded face's advances for the ASCII letters and
    /// digits it holds (`alnumAdvances`).
    nonisolated(unsafe) private static var embeddedAlnum: [String: [UInt32: Double]] = [:]
    /// Each loaded embedded face's own family, from its `name` table.
    nonisolated(unsafe) private static var embeddedNames: [String: String] = [:]
    /// The loaded embedded faces that carry bitmaps (`EBDT`).
    nonisolated(unsafe) private static var embeddedBitmaps: Set<String> = []

    /// Whether an sfnt has table `tag`.
    static func hasTable(_ data: Data, _ tag: String) -> Bool {
        let b = [UInt8](data)
        guard b.count > 12 else { return false }
        let count = Int(b[4]) << 8 | Int(b[5])
        return (0 ..< count).contains { t in
            let at = 12 + 16 * t
            return at + 4 <= b.count && String(decoding: b[at ..< at + 4], as: UTF8.self) == tag
        }
    }

    /// An sfnt's family name (`name` ID 1, Windows Unicode or Mac Roman).
    static func familyName(_ data: Data) -> String? {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
        func u32(_ o: Int) -> Int { u16(o) << 16 | u16(o + 2) }
        guard b.count > 12 else { return nil }
        var name = -1
        for t in 0 ..< u16(4) where 12 + 16 * t + 16 <= b.count {
            let at = 12 + 16 * t
            if String(decoding: b[at ..< at + 4], as: UTF8.self) == "name" { name = u32(at + 8) }
        }
        guard name >= 0 else { return nil }
        let count = u16(name + 2), strings = name + u16(name + 4)
        var mac: String? = nil
        for r in 0 ..< count {
            let at = name + 6 + 12 * r
            guard u16(at + 6) == 1 else { continue }
            let platform = u16(at), length = u16(at + 8), offset = strings + u16(at + 10)
            guard offset + length <= b.count else { continue }
            if platform == 3 {
                var units: [UInt16] = []
                for k in stride(from: 0, to: length - 1, by: 2) { units.append(UInt16(u16(offset + k))) }
                return String(decoding: units, as: UTF16.self)
            }
            if platform == 1, mac == nil { mac = String(decoding: b[offset ..< offset + length], as: UTF8.self) }
        }
        return mac
    }

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
    /// Latin faces Word for Windows does not ship (nor fetch), which a file embeds.
    static func embeddedLatinWanted(_ name: String) -> Bool {
        let n = name.trimmingWhitespace().lowercased()
        return !isEastAsianFace(name) && !wordMacFamilies.contains(n)
            && !["tahoma", "century gothic", "arial narrow", "calibri light", "cordia new", "angsana new", "times", "th sarabunpsk"].contains(n)
    }
    /// Whether a face maps all of A-Z and a-z. An Arabic or symbol face a file embeds (DecoType Naskh) must
    /// not stand in as a "Latin" face: text in it then shapes with no glyphs and Skia's cluster() traps.
    static func coversLatinLetters(_ data: Data) -> Bool {
        guard let covered = coverage(data) else { return false }
        return (0x41 ... 0x5A).allSatisfy { covered.contains($0) } && (0x61 ... 0x7A).allSatisfy { covered.contains($0) }
    }
    /// A Latin embedded face's line (ascent, descent in ems).
    static func embeddedLatinLine(_ registered: String) -> (ascent: Double, descent: Double)? {
        declaredLock.lock()
        defer { declaredLock.unlock() }
        return embeddedLines[registered]
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
    static func loadEmbedded(_ data: Data, sharedFamily: String? = nil) -> String? {
        guard data.count > 12 else { return nil }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        let family = sharedFamily ?? "Starling Embedded " + String(hash, radix: 16)
        let key = sharedFamily == nil ? family : family + " " + String(hash, radix: 16)
        declaredLock.lock()
        let loaded = loadedEmbedded.contains(key)
        declaredLock.unlock()
        if loaded { return family }
        let ok = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return false }
            return family.withCString { flutter.swift_bridge.LoadFontFromList(base, data.count, $0) }
        }
        guard ok else { return nil }
        let covered = coverage(data)
        declaredLock.lock()
        loadedEmbedded.insert(key)
        if let covered { embeddedCoverage[family] = (embeddedCoverage[family] ?? []).union(covered) }
        if let line = lineMetrics(data) { embeddedLines[family] = line }
        if let alnum = alnumAdvances(data) { embeddedAlnum[family] = alnum }
        if let own = familyName(data) { embeddedNames[family] = own }
        if hasTable(data, "EBDT") { embeddedBitmaps.insert(family) }
        declaredLock.unlock()
        return family
    }

    /// A face's advances, in ems, for the printable ASCII it maps to a
    /// glyph of some advance (`cmap`'s Windows Unicode subtable, `hmtx`
    /// over `head`'s units per em). Letters and digits alone at first;
    /// the space and punctuation too since zh-57f1de0d's 方正仿宋_GBK
    /// "4.1 " stood 31.8pt at 16pt in Word's print — "." 0.297 em and the
    /// space 0.445 — where the stand-in's half em made it 3.9pt narrower and
    /// the line took the ideograph Word sends down (99.9 -> 100).
    static func alnumAdvances(_ data: Data) -> [UInt32: Double]? {
        let d = [UInt8](data)
        func u16(_ at: Int) -> Int { at + 2 <= d.count ? Int(d[at]) << 8 | Int(d[at + 1]) : 0 }
        func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
        guard d.count > 12 else { return nil }
        func table(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            for k in 0 ..< u16(4) {
                let e = 12 + 16 * k
                guard e + 16 <= d.count else { return nil }
                if Array(d[e ..< e + 4]) == t { return u32(e + 8) }
            }
            return nil
        }
        guard let cmap = table("cmap"), let hhea = table("hhea"), let hmtx = table("hmtx"), let head = table("head") else { return nil }
        let units = u16(head + 18), metrics = u16(hhea + 34)
        guard units > 0, metrics > 0 else { return nil }
        var sub: Int? = nil
        for k in 0 ..< u16(cmap + 2) {
            let r = cmap + 4 + 8 * k
            if u16(r) == 3, u16(r + 2) == 1 || u16(r + 2) == 10, u16(cmap + u32(r + 4)) == 4 { sub = cmap + u32(r + 4); break }
        }
        guard let f = sub else { return nil }
        let segs = u16(f + 6) / 2
        let ends = f + 14, starts = ends + 2 * segs + 2, deltas = starts + 2 * segs, offsets = deltas + 2 * segs
        var out: [UInt32: Double] = [:]
        for c in Array(0x20 ... 0x7E) {
            var glyph = 0
            for i in 0 ..< segs where c <= u16(ends + 2 * i) {
                guard c >= u16(starts + 2 * i) else { break }
                let ro = u16(offsets + 2 * i)
                if ro == 0 { glyph = (c + u16(deltas + 2 * i)) & 0xFFFF }
                else {
                    let g = u16(offsets + 2 * i + ro + 2 * (c - u16(starts + 2 * i)))
                    glyph = g == 0 ? 0 : (g + u16(deltas + 2 * i)) & 0xFFFF
                }
                break
            }
            guard glyph != 0 else { continue }
            let advance = u16(hmtx + 4 * min(glyph, metrics - 1))
            if advance > 0 { out[UInt32(c)] = Double(advance) / Double(units) }
        }
        return out.isEmpty ? nil : out
    }

    /// Whether a face maps a character to a glyph of no advance (`cmap`'s
    /// Windows Unicode subtable, then `hmtx`); false where it maps none.
    /// Word's own subset embedding keeps the whole `cmap` and empties the
    /// glyphs the document does not use, to no outline and no advance.
    static func mapsToZeroAdvance(_ data: Data, _ scalar: UInt32) -> Bool {
        let d = [UInt8](data)
        func u16(_ at: Int) -> Int { at + 2 <= d.count ? Int(d[at]) << 8 | Int(d[at + 1]) : 0 }
        func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
        guard d.count > 12, scalar <= 0xFFFF else { return false }
        func table(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            for k in 0 ..< u16(4) {
                let e = 12 + 16 * k
                guard e + 16 <= d.count else { return nil }
                if Array(d[e ..< e + 4]) == t { return u32(e + 8) }
            }
            return nil
        }
        guard let cmap = table("cmap"), let hhea = table("hhea"), let hmtx = table("hmtx") else { return false }
        var sub: Int? = nil
        for k in 0 ..< u16(cmap + 2) {
            let r = cmap + 4 + 8 * k
            if u16(r) == 3, u16(r + 2) == 1 || u16(r + 2) == 10, u16(cmap + u32(r + 4)) == 4 { sub = cmap + u32(r + 4); break }
        }
        guard let f = sub else { return false }
        let c = Int(scalar), segs = u16(f + 6) / 2
        let ends = f + 14, starts = ends + 2 * segs + 2, deltas = starts + 2 * segs, offsets = deltas + 2 * segs
        var glyph = 0
        for i in 0 ..< segs where c <= u16(ends + 2 * i) {
            guard c >= u16(starts + 2 * i) else { return false }
            let ro = u16(offsets + 2 * i)
            if ro == 0 { glyph = (c + u16(deltas + 2 * i)) & 0xFFFF }
            else {
                let g = u16(offsets + 2 * i + ro + 2 * (c - u16(starts + 2 * i)))
                glyph = g == 0 ? 0 : (g + u16(deltas + 2 * i)) & 0xFFFF
            }
            break
        }
        guard glyph != 0 else { return false }
        let metrics = u16(hhea + 34)
        guard metrics > 0 else { return false }
        return u16(hmtx + 4 * min(glyph, metrics - 1)) == 0
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

    // These English GB2312 names are absent on Word for Mac. With no
    // font-table entry or embedded face, fresh Word prints resolve them
    // exactly like an unknown Latin name: Cambria letters/quotes and
    // SimSun ideographs (zh-202582e2 and the missing-name controls).
    // A table-described name has its own substitution rules below.
    private static func isUndeclaredMacGBName(_ family: String) -> Bool {
        guard wordOnMac else { return false }
        let n = family.trimmingWhitespace().lowercased()
        return (n == "fangsong_gb2312" || n == "kaiti_gb2312")
            && fontEntry(family) == nil && !isEmbedded(family)
    }

    /// Whether a family name is an East Asian face: written in its own
    /// script (宋体, 標楷體, ＭＳ 明朝), or one of the Latin names those
    /// faces also go by.
    static func isEastAsianFace(_ family: String) -> Bool {
        if isDeclaredLatin(family) || isUndeclaredMacGBName(family) { return false }
        return namesEastAsianFace(family)
    }

    /// The part of `isEastAsianFace` that reads only the name (the rest reads what the file declared),
    /// remembered like `faceHas`: asked for every span.
    nonisolated(unsafe) private static var eastAsianNameMemo: [String: Bool] = [:]
    private static func namesEastAsianFace(_ family: String) -> Bool {
        hasLock.lock()
        if let hit = eastAsianNameMemo[family] { hasLock.unlock(); return hit }
        hasLock.unlock()
        let answer = _namesEastAsianFace(family)
        hasLock.lock()
        if eastAsianNameMemo.count > 4096 { eastAsianNameMemo.removeAll() }
        eastAsianNameMemo[family] = answer
        hasLock.unlock()
        return answer
    }

    private static func _namesEastAsianFace(_ family: String) -> Bool {
        if family.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { return true }
        let n = family.trimmingWhitespace().lowercased()
        for key in ["simsun", "simhei", "kaiti", "fangsong", "yahei", "dengxian", "mingliu", "dfkai", "jhenghei",
                    "stsong", "stkaiti", "stfangsong", "stzhongsong", "stxihei", "stxinwei", "stheiti", "songti", "heiti",
                    "pingfang", "hiragino", "mincho", "kyokashotai", "ms gothic", "yu gothic", "meiryo", "malgun", "batang", "gulim", "dotum",
                    "cjk", "source han", "noto sans sc", "noto serif sc", "wenquanyi", "arial unicode", "fzs", "fzf", "fzk", "fzh", "fzx"] where faceHas(n, key) {
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
    /// What Word for Mac widens each character of a face it emboldens by,
    /// of the character's own advance: lab tkai2 (fresh Mac Word, 楷体_GB2312
    /// at 12pt) sets bold ideographs 12.234 and spaces 6.117 apart, 1.95%
    /// of each; FangSong's 16pt bold "第" is 16.32 (lab tflc). (The 1/48
    /// of the prints before 2026-10-26 was a Word process days old.)
    static let macBoldWiden = 0.0195

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
        /// Its own widths, in ems, for characters past ASCII that a run sets
        /// East Asian (hinted, `RichLayout.isEastAsian`): the stand-in draws
        /// them at these (`RichResolvedFace.otherAdvances`).
        var otherAdvances: [UInt32: Double]? = nil
        /// The bold cut's own widths where they differ from `otherAdvances` (Meiryo UI Bold).
        var boldOtherAdvances: [UInt32: Double]? = nil
        /// Word draws a missing Korean face's quotes, circles and circled digits in Malgun Gothic, whose taller line they give (`malgunSymbolLines`).
        var malgunSymbols = false
        /// Word emboldens a face that has no bold of its own, and sets
        /// each character wider: by `boldWiden` of an em, 1/48 where
        /// that is not said. (Word for Mac only: Word for Windows keeps
        /// the face's widths — in its prints (word-win) the bold 仿宋,
        /// 宋体, 楷体 and 黑体 runs of 34 documents stand 1.00 to 1.007 em
        /// apart, the Mac's 1.025 to 1.03.)
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
        /// `RichResolvedFace.symbolFamily` and `symbolsInBold`.
        var symbols: String? = nil
        var symbolsInBold = true
        /// Whether its symbols are an em as a square face's, where it has a
        /// table of ASCII widths besides (PMingLiU): nil, as having none.
        var squareSymbols: Bool? = nil
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
    /// Word for Windows' face for a Latin-named East Asian face it lacks
    /// that the file's table does not describe (lab t160, Windows
    /// 01QbbApP, each print the first of a fresh Word, after the font
    /// packs): MS Mincho, a square face (its hhea .859 + .141 at Word's
    /// 1.3), its letters and digits in Cambria, and the ideographs it
    /// lacks in Microsoft JhengHei, on JhengHei's line. zh-f6686f89's
    /// FZShuTi cover in word-win: the 36pt lines, each with a 单 or 总,
    /// stand 1.73 em (JhengHei's) under 1.15 spacing, the 18pt date,
    /// Mincho and Cambria only, 1.30. An invented name prints the same.
    /// (Its baseline Mincho's own ascent, 220/256, under half the 1.3
    /// line's extra: zh-8e8d4c40's "N、" labels lift their 標楷體 lines
    /// 0.72pt in Word for Windows, 0.66 at the 1.005 it had, and page 2
    /// took one line too many.)
    private static let windowsMincho = EastAsianFace(height: wordEastAsianLine(units: 256, upem: 256), latin: cambria, latinScale: 1.0, fakeBold: true, baseline: 0.859375 + 0.15 - (1.3 - wordEastAsianLine(units: 256, upem: 256)) / 2)
    /// The same face for Arial Unicode MS, whose Latin Word for Windows draws in Arial (4a21de: ArialMT in the print), not Cambria.
    private static let windowsMinchoArialLatin = EastAsianFace(height: wordEastAsianLine(units: 256, upem: 256), latin: sans, latinScale: 1.0, fakeBold: true, baseline: 0.859375 + 0.15 - (1.3 - wordEastAsianLine(units: 256, upem: 256)) / 2)
    /// What MS Mincho holds, as far as Shift_JIS (JIS X 0208) reaches —
    /// all of it Mincho's, though Mincho holds more (JIS X 0212): enough
    /// to tell 单, 总, 监 from 年, 月, 日. Nil where the encoding is not
    /// there.
    static let windowsMinchoCovers: Set<UInt32>? = {
        var out = Set<UInt32>()
        for u in UInt32(0x2E80) ... 0xFFFF {
            guard let scalar = Unicode.Scalar(u) else { continue }
            if encodesInShiftJIS(scalar) { out.insert(u) }
        }
        // The wave dash 〜 (JIS X 0208 row 1) is MS Mincho's, but Foundation's .shiftJIS
        // table (code page 932's) has only the full-width tilde for it, so it was taken for
        // a character Mincho lacks and put the line on JhengHei's 1.73 em
        // (jpn-z17607492-12a6ce: 20.7 pt lines where Word's are 15.6).
        out.insert(0x301C)
        return out.isEmpty ? nil : out
    }()
    /// Whether code page 932 holds the character — the table Foundation's
    /// `.shiftJIS` converts by on a Mac. Foundation on Windows converts
    /// nothing to it, not even "A", so there the set came out empty and
    /// Mincho's lines lost their JhengHei: zh-202582e2 108/139 in word-win
    /// natively where the Mac's Windows mode matched 136. Windows' own
    /// converter, best fit off, minus the user-defined rows it gives the
    /// private use area, which the code page's table does not have.
    private static func encodesInShiftJIS(_ scalar: Unicode.Scalar) -> Bool {
        #if os(Windows)
        guard scalar.value <= 0xFFFF, !(0xE000 ... 0xF8FF).contains(scalar.value) else { return false }
        var wide = [WCHAR(scalar.value)]
        var bytes = [CHAR](repeating: 0, count: 4)
        var usedDefault: WindowsBool = false
        let n = WideCharToMultiByte(932, DWORD(WC_NO_BEST_FIT_CHARS), &wide, 1, &bytes, 4, nil, &usedDefault)
        return n > 0 && !usedDefault.boolValue
        #else
        return String(Character(scalar)).data(using: .shiftJIS) != nil
        #endif
    }
    /// The face Word for Windows sets an East Asian name it lacks in,
    /// where that is not YaHei (nil): "mincho" (`windowsMincho`) or
    /// "jhenghei". By the file's own font-table entry, as the map
    /// test/corpus/docx/word-win-missing-faces-map.txt reads (Windows
    /// 01QbbApP, 135 names, each the first document of a fresh Word):
    /// an alternate it has wins (taken further on); with none, charset
    /// 86 (GB2312) is YaHei, 88 (Big5) JhengHei, 80 (Shift-JIS) Yu
    /// Gothic — YaHei's pitch to a third of a point, so left to it — and
    /// any other charset Mincho with JhengHei; with no entry a Latin
    /// name is Mincho with JhengHei (FZShuTi, FZXiaoBiaoSong-B05S) and a
    /// Chinese one Yu Gothic, left to YaHei.
    private static func koreanOnly(_ n: String) -> Bool {
        n.unicodeScalars.allSatisfy { $0.isASCII || ($0.value >= 0xAC00 && $0.value <= 0xD7A3) }
    }
    private static func koreanSuffix(_ n: String) -> Bool {
        n.hasSuffix(" kr") || n.hasSuffix(" kr bold") || n.hasSuffix(" korean")
    }
    private static let wordKnownEastAsianKeys: [String] = ["simsun", "宋体", "新宋体", "nsimsun", "simhei", "黑体", "kaiti", "楷体", "fangsong", "仿宋", "microsoft yahei", "微软雅黑",
                   "mingliu", "細明體", "新細明體", "microsoft jhenghei", "微軟正黑", "dengxian", "等线", "dfkai", "標楷",
                   "mincho", "明朝", "gothic", "ゴシック", "meiryo", "malgun", "batang", "gulim", "dotum", "맑은 고딕", "_gb2312", "华文", "stsong", "stkaiti",
                   "stfangsong", "stzhongsong", "stxihei", "stxinwei"]
    private static func windowsMissingFallback(_ family: String) -> String? {
        let n = family.trimmingWhitespace().lowercased()
        guard !n.isEmpty else { return nil }
        // (BatangChe and DotumChe are Word for Windows' own faces, drawn at their own widths further on.)
        if ["batangche", "dotumche", "바탕체", "돋움체"].contains(n) { return nil }
        // (NanumGothic is a face Word for Windows prints as itself (7416edcd), drawn at its own widths further on.)
        if ["nanumgothic", "나눔고딕"].contains(n) { return nil }
        // (맑은 고딕 is Word for Windows' face too: a document that names
        // 맑은 고딕 was set in MS Mincho's widths, its spaces 0.22 em where Word's Malgun
        // Gothic sets 0.35 — kor-z19176375-30dbe1, kor-z21348848-7369b1.)
        let has = wordKnownEastAsianKeys
        // (A name that lists faces, as LibreOffice writes them — "新細明體,
        // PMingLiU" — is no face Word for Windows has, whatever it lists:
        // it goes by its own entry, zh-8e8d4c40's alternate Times New Roman
        // at charset 00, Mincho — its list labels' "、" in MS Mincho in
        // word-win, their lines topped by Mincho's ascent (macos-ios'
        // measurement).)
        let listed = faceHas(n, ",")
        // (The Korean names are matched whole: 바탕체 and 돋움체 are the fixed-pitch Che faces,
        // not 바탕 and 돋움, and Word for Windows prints them differently.)
        let koreanOwn: Set<String> = ["맑은 고딕", "굴림", "굴림체", "돋움", "바탕"]
        guard listed || !(has.contains(where: { faceHas(n, $0) }) || koreanOwn.contains(n)) else { return nil }
        guard let e = fontEntry(family) else { return n.unicodeScalars.allSatisfy({ $0.isASCII }) ? "mincho" : nil }
        // (A Korean face Word lacks whose font table names 바탕 as its alternate prints in Batang: 한양신명조 at
        // charset 81 steps 1.31 em in Word's print where ours drew Malgun's 1.73, b6f6c7d4 / 07eecf7a.)
        if e.alt?.trimmingWhitespace() == "바탕", n != "바탕", e.charset == "81" || e.charset == "129" { return "batang" }
        // (A Korean-named face Word lacks whose alternate is Yu Gothic, which has no Hangul: Word draws
        // the Hangul in Malgun Gothic, 5101ed6e's "Noto Serif CJK KR", 31 lines 4 pt short in ours.)
        if e.charset.uppercased() == "80", e.alt?.trimmingWhitespace().lowercased() == "yu gothic", koreanSuffix(n) { return "malgun" }
        if let alt = e.alt?.trimmingWhitespace().lowercased(), !alt.isEmpty, alt != n,
           has.contains(where: { faceHas(alt, $0) })
            || (alt.unicodeScalars.contains(where: { $0.value >= 0x2E80 })
                // (An alternate that is itself a Korean face Word lacks, 하나 L's 가는안상수체, names nothing Word has: the face goes by its own charset and panose below.)
                && !((e.charset == "81" || e.charset == "129") && e.family == "roman" && !e.panoseZero && koreanOnly(alt))) { return nil }
        switch e.charset.uppercased() {
        case "86", "80", "": return nil
        case "88": return "jhenghei"
        case "81", "129", "01", "1":
            // A Korean face Word lacks: charset 81 with a roman (serif) panose prints in Batang
            // (HY신명조, 하나 L), any other Hangul-named or charset 81 face in Malgun Gothic
            // (나눔명조 at charset 01, 나눔바른고딕, 나눔고딕 Light); 헤드라인 faces print mixed, left alone.
            let hangul = n.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 })
            let cs = e.charset.uppercased()
            guard cs == "81" || cs == "129" || hangul else { return "mincho" }
            if faceHas(n, "헤드라인") { return "batang" }   // (lab tcfit1: Word prints HY헤드라인M in Batang)
            if (cs == "81" || cs == "129") && e.family == "roman" && !e.panoseZero { return "batang" }
            return "malgun"
        default: return "mincho"
        }
    }
    private static let square = EastAsianFace(height: 1.3, latin: mono, latinScale: 0.85, fakeBold: true, baseline: 1.005)
    // (YaHei's bold, msyhbd.ttc, is a face of its own and a line of it
    // is taller: Word sets bold YaHei lines 1.73 ems apart — 24.21 at
    // 14pt (zh-33aa9899's body), 27.66 at 16 and 34.62 at 20 (zh-7dc3afad's
    // contents) — where its regular's are 1.715. The extra goes half
    // above, half below.)
    // (Arial Unicode MS by its hhea, 1.069 over and 0.271 under, at
    // Word's 1.3 of that, the extra half above and half below: zh-4e5fe46f's
    // empty 10pt marks in it step 20.16 at 278/240 in Word's print, 1.740
    // em. Its Latin is Arial's; it has no bold, and Word emboldens it a
    // fiftieth of an em wider a character, JhengHei Light's lab `bw` rate:
    // zh-884c6e3e's bold 16pt steps 16.645 where YaHei's step 16.325.)
    private static let arialUnicode = EastAsianFace(height: 1.742, latin: sans, latinScale: 1.0, fakeBold: true, boldWiden: 1.0 / 50,
                                                    baseline: 1.270)
    /// Word's single line for an East Asian face: 1.3 x (ascent + descent), counted in the face's own font units and floored,
    /// over units-per-em (MS Mincho 220+36 of 256 gives 332/256; Malgun 2724 of 2048 gives 3541/2048 = 1.729; Meiryo UI 2601 gives 3381/2048 = 1.651).
    private static func wordEastAsianLine(units: Double, upem: Double) -> Double { (1.3 * units).rounded(.down) / upem }
    private static let malgunHeight = wordEastAsianLine(units: 2724, upem: 2048)
    private static func isYaHeiLike(_ h: Double) -> Bool { h == yaHei.height || h == malgunHeight }
    private static let yaHei = EastAsianFace(height: 1.715, latin: sans, latinScale: 1.07, latinClasses: [0.985, 0.92, 1.027, 0.96],
                                             latinAdvances: yaHeiAdvances, latinBoldAdvances: yaHeiBoldAdvances,
                                             latinKerns: yaHeiKerns, latinBoldKerns: yaHeiBoldKerns, fakeBold: false, baseline: 1.26,
                                             boldHeight: 1.73, boldBaseline: 1.2675)

    // Segoe UI's own widths, U+0020 to U+007E, in its Regular, Bold and Light, and Regular's and Bold's
    // Latin-1 (U+00A0 to U+00FF) and Russian (U+0410 to U+044F, U+0401, U+0451): the hmtx of the Windows
    // box's segoeui.ttf, segoeuib.ttf and segoeuil.ttf, 2048 units to the em (numbers only, read by
    // windows 2026-11-02; lab test/labs/segoe on wip/lab-segoe). They replace the widths read from
    // Word's prints' subsets, whose glyphs no print used were estimated. fdo78885's 9pt Segoe UI body,
    // 12.0pt lines in Word's print, ours 10.4 in the sans stand-in.
    // Palatino Linotype's own widths, U+0020 to U+007E, read from the hmtx of the subsets Word for Windows' prints embed
    // (test/tools/print-font-metrics.py, 23 prints; Regular 79 of 95 read, Bold 58, the rest estimated from the stand-in's).
    static let palatinoLinotypeAdvances: [Double] = [
        0.2500, 0.2778, 0.3711, 0.5004, 0.5004, 0.8001, 0.6002, 0.2080, 0.3330, 0.3330, 0.3502, 0.5000, 0.2500, 0.3330, 0.2500,
        0.3203, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.2500, 0.2500, 0.5000, 0.5255,
        0.5000, 0.4438, 0.6831, 0.7778, 0.6108, 0.7090, 0.7739, 0.6108, 0.5562, 0.7632, 0.8320, 0.3369, 0.5297, 0.7261, 0.6108,
        0.9458, 0.8311, 0.7861, 0.6040, 0.8241, 0.6680, 0.5249, 0.6128, 0.7778, 0.7222, 1.0000, 0.6670, 0.7067, 0.6670, 0.3330,
        0.2500, 0.3330, 0.4222, 0.5000, 0.3330, 0.5000, 0.5532, 0.4438, 0.6108, 0.4790, 0.3330, 0.5562, 0.5820, 0.2910, 0.2339,
        0.5562, 0.2910, 0.8828, 0.5820, 0.5459, 0.6011, 0.5894, 0.3950, 0.4238, 0.3262, 0.6030, 0.5649, 0.8340, 0.5161, 0.5562,
        0.5000, 0.3005, 0.2337, 0.3005, 0.5255,
    ]
    static let palatinoLinotypeBoldAdvances: [Double] = [
        0.2500, 0.2778, 0.3853, 0.4822, 0.4822, 0.7709, 0.6261, 0.2062, 0.2887, 0.2887, 0.3374, 0.5063, 0.2500, 0.2887, 0.2500,
        0.2409, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.2500, 0.2887, 0.5063, 0.5063,
        0.5063, 0.5296, 0.8454, 0.7778, 0.6606, 0.7222, 0.8311, 0.6060, 0.5576, 0.8330, 0.8330, 0.3892, 0.3892, 0.7695, 0.6060,
        1.0000, 0.8330, 0.8330, 0.6104, 0.8330, 0.7139, 0.6108, 0.6670, 0.7778, 0.7778, 1.0000, 0.6670, 0.6670, 0.6670, 0.2887,
        0.2409, 0.2887, 0.5063, 0.4822, 0.2887, 0.5000, 0.6108, 0.4438, 0.6108, 0.5000, 0.3330, 0.5557, 0.6108, 0.3330, 0.3330,
        0.6108, 0.3330, 0.8892, 0.6108, 0.5562, 0.6108, 0.6108, 0.3892, 0.4438, 0.3330, 0.6108, 0.5557, 0.8330, 0.5561, 0.5562,
        0.5000, 0.3374, 0.2426, 0.3374, 0.5063,
    ]
    // Sylfaen's own widths from the hmtx of the subsets Word for Windows' prints embed (66 prints; test/tools/print-font-metrics.py
    // with PRINTS_GLOB over the corpus-cache word-win folders): U+0020-U+007E (9 of 95 estimated) and every other code point a print used,
    // Armenian U+0531-U+0587 among them. xs 5ed52035 sets GHEA Grapalat (absent, so Word draws Sylfaen).
    // Line: win 2062 over and 635 under of 2048 (1.317 em).
    // Franklin Gothic Medium Cond's own widths from the hmtx of the subsets Word for Windows' prints embed (7 prints; only the
    // code points they used, so a missing ASCII letter keeps Sylfaen's width).
    static let franklinMediumCondAdvances: [UInt32: Double] = [
        0x20: 0.1865, 0x21: 0.3408, 0x22: 0.5112, 0x25: 0.6812, 0x28: 0.2554, 0x29: 0.2554, 0x2C: 0.2388, 0x2D: 0.2896,
        0x2E: 0.2388, 0x2F: 0.4771, 0x30: 0.5107, 0x31: 0.5107, 0x32: 0.5107, 0x33: 0.5107, 0x34: 0.5107, 0x35: 0.5107,
        0x36: 0.5107, 0x37: 0.5107, 0x38: 0.5107, 0x39: 0.5107, 0x3A: 0.2383, 0x41: 0.4941, 0x43: 0.5278, 0x45: 0.4600,
        0x48: 0.5449, 0x4B: 0.5112, 0x4D: 0.7153, 0x4E: 0.5620, 0x4F: 0.5625, 0x50: 0.4941, 0x54: 0.3750, 0x5F: 0.5000,
        0x60: 0.5000, 0x61: 0.4600, 0x63: 0.4087, 0x64: 0.4771, 0x65: 0.4429, 0x6F: 0.4600, 0x70: 0.4771, 0x72: 0.2725,
        0x78: 0.3579,
    ]
static let sylfaenAdvances: [Double] = [
        0.2500, 0.2651, 0.3481, 0.5000, 0.5004, 0.8398, 0.6002, 0.1718, 0.3271, 0.3271, 0.3120, 0.5000, 0.2500, 0.3789, 0.2500,
        0.3101, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.5000, 0.2500, 0.2500, 0.5000, 0.5000,
        0.5000, 0.3911, 0.9134, 0.7100, 0.6021, 0.6470, 0.7241, 0.5840, 0.5352, 0.7080, 0.7622, 0.3530, 0.3232, 0.6670, 0.5518,
        0.9028, 0.7261, 0.7559, 0.5898, 0.7559, 0.6528, 0.4810, 0.6030, 0.7178, 0.7119, 1.0361, 0.6519, 0.6748, 0.6240, 0.3291,
        0.2500, 0.3291, 0.4222, 0.5000, 0.5000, 0.4429, 0.5249, 0.4458, 0.5278, 0.4590, 0.3179, 0.4761, 0.5708, 0.2852, 0.2578,
        0.5298, 0.2861, 0.8208, 0.5659, 0.5078, 0.5220, 0.5151, 0.3828, 0.3589, 0.3301, 0.5410, 0.5078, 0.7710, 0.4878, 0.5181,
        0.4492, 0.3005, 0.2490, 0.3005, 0.5255,
    ]
    static let sylfaenOtherAdvances: [UInt32: Double] = [
        0x00A0: 0.2500, 0x00A8: 0.5000, 0x00AB: 0.4019, 0x00AD: 0.3789, 0x00B0: 0.3062, 0x00BA: 0.3101,
        0x00BB: 0.4019, 0x00C6: 0.9468, 0x00C7: 0.6470, 0x00D6: 0.7559, 0x00D7: 0.5000, 0x00E4: 0.4429,
        0x00E6: 0.6641, 0x00E7: 0.4458, 0x00F6: 0.5078, 0x00FC: 0.5410, 0x011F: 0.4761, 0x0130: 0.3530,
        0x0131: 0.2891, 0x0132: 0.6440, 0x0133: 0.5229, 0x0152: 0.9912, 0x0153: 0.7529, 0x015E: 0.4810,
        0x015F: 0.3589, 0x02D8: 0.5000, 0x02D9: 0.5000, 0x0308: 0.5000, 0x037E: 0.2500, 0x0410: 0.7100,
        0x0411: 0.6021, 0x0412: 0.6021, 0x0413: 0.5430, 0x0414: 0.7251, 0x0415: 0.5840, 0x0418: 0.7720,
        0x041A: 0.6729, 0x041B: 0.7100, 0x041C: 0.9028, 0x041D: 0.7622, 0x041E: 0.7559, 0x041F: 0.7500,
        0x0421: 0.6470, 0x0422: 0.6030, 0x042F: 0.6572, 0x0430: 0.4429, 0x0431: 0.5151, 0x0432: 0.4590,
        0x0433: 0.4189, 0x0434: 0.5391, 0x0435: 0.4590, 0x0436: 0.7119, 0x0437: 0.3770, 0x0438: 0.5840,
        0x0439: 0.5840, 0x043A: 0.5181, 0x043B: 0.5332, 0x043C: 0.6431, 0x043D: 0.5820, 0x043E: 0.5078,
        0x043F: 0.5679, 0x0440: 0.5220, 0x0441: 0.4458, 0x0442: 0.4390, 0x0443: 0.5181, 0x0444: 0.6689,
        0x0445: 0.4878, 0x0446: 0.5732, 0x0447: 0.5410, 0x0448: 0.7549, 0x044B: 0.7012, 0x044C: 0.4619,
        0x044D: 0.4468, 0x044F: 0.4951, 0x0531: 0.8101, 0x0532: 0.6880, 0x0533: 0.7402, 0x0534: 0.7202,
        0x0535: 0.6909, 0x0536: 0.6318, 0x0537: 0.6069, 0x0538: 0.5908, 0x0539: 0.8301, 0x053A: 0.7349,
        0x053B: 0.6260, 0x053C: 0.5771, 0x053D: 0.7769, 0x053E: 0.7422, 0x053F: 0.7148, 0x0540: 0.5181,
        0x0541: 0.6392, 0x0542: 0.7212, 0x0543: 0.6689, 0x0544: 0.8340, 0x0545: 0.5640, 0x0546: 0.7021,
        0x0547: 0.6318, 0x0548: 0.7729, 0x0549: 0.5981, 0x054A: 0.7451, 0x054B: 0.6602, 0x054C: 0.8369,
        0x054D: 0.7729, 0x054E: 0.7539, 0x054F: 0.5220, 0x0550: 0.6431, 0x0551: 0.5815, 0x0552: 0.6792,
        0x0553: 0.7451, 0x0554: 0.6660, 0x0555: 0.7559, 0x0556: 0.6851, 0x055B: 0.2651, 0x055D: 0.2710,
        0x055E: 0.3018, 0x0561: 0.8232, 0x0562: 0.4888, 0x0563: 0.5259, 0x0564: 0.5610, 0x0565: 0.5400,
        0x0566: 0.5171, 0x0567: 0.4731, 0x0568: 0.5610, 0x0569: 0.6279, 0x056A: 0.5469, 0x056B: 0.5610,
        0x056C: 0.3110, 0x056D: 0.7852, 0x056E: 0.5029, 0x056F: 0.5571, 0x0570: 0.5620, 0x0571: 0.5498,
        0x0572: 0.5610, 0x0573: 0.5518, 0x0574: 0.5742, 0x0575: 0.2578, 0x0576: 0.5479, 0x0577: 0.4639,
        0x0578: 0.5610, 0x0579: 0.3672, 0x057A: 0.8232, 0x057B: 0.4761, 0x057C: 0.5449, 0x057D: 0.5649,
        0x057E: 0.5620, 0x057F: 0.8125, 0x0580: 0.5610, 0x0581: 0.5049, 0x0582: 0.3862, 0x0583: 0.8125,
        0x0584: 0.5308, 0x0585: 0.5078, 0x0586: 0.6172, 0x0587: 0.5669, 0x0589: 0.2168, 0x10D0: 0.4253,
        0x10D1: 0.5142, 0x10D2: 0.5234, 0x10D3: 0.8447, 0x10D4: 0.4731, 0x10D5: 0.4922, 0x10D6: 0.7378,
        0x10D7: 0.8232, 0x10D8: 0.5581, 0x10D9: 0.4609, 0x10DA: 0.9561, 0x10DB: 0.4941, 0x10DC: 0.4951,
        0x10DD: 0.7061, 0x10DE: 0.4839, 0x10DF: 0.4658, 0x10E0: 0.6929, 0x10E1: 0.4941, 0x10E2: 0.7441,
        0x10E3: 0.7480, 0x10E4: 0.6948, 0x10E5: 0.4551, 0x10E6: 0.6846, 0x10E7: 0.4702, 0x10E8: 0.5098,
        0x10E9: 0.4800, 0x10EA: 0.5840, 0x10EB: 0.4951, 0x10EC: 0.5049, 0x10ED: 0.5444, 0x10EE: 0.5332,
        0x10EF: 0.7402, 0x10F0: 0.4839, 0x10F2: 0.5566, 0x2013: 0.5000, 0x2014: 1.0000, 0x2019: 0.2261,
        0x201C: 0.3838, 0x201D: 0.3838, 0x201E: 0.3838, 0x2116: 0.9219, 0x2212: 0.5000, 0x2265: 0.5000,
        0xFB01: 0.5669, 0xFB02: 0.5669, 0xFB13: 1.0669, 0xFB14: 1.0586, 0xFB15: 1.0737, 0xFB16: 1.0645,
        0xFB17: 1.3008,
    ]
    static let segoeUIAdvances: [Double] = [
        0.2739, 0.2842, 0.3921, 0.5908, 0.5391, 0.8184, 0.8003, 0.2300, 0.3018, 0.3018, 0.4170, 0.6841, 0.2168, 0.3999, 0.2168,
        0.3896, 0.5391, 0.5391, 0.5391, 0.5391, 0.5391, 0.5391, 0.5391, 0.5391, 0.5391, 0.5391, 0.2168, 0.2168, 0.6841, 0.6841,
        0.6841, 0.4482, 0.9551, 0.6450, 0.5732, 0.6191, 0.7012, 0.5059, 0.4883, 0.6860, 0.7100, 0.2661, 0.3569, 0.5801, 0.4707,
        0.8979, 0.7480, 0.7539, 0.5601, 0.7539, 0.5981, 0.5312, 0.5239, 0.6870, 0.6211, 0.9341, 0.5898, 0.5527, 0.5703, 0.3018,
        0.3789, 0.3018, 0.6841, 0.4150, 0.2681, 0.5088, 0.5879, 0.4619, 0.5889, 0.5229, 0.3130, 0.5889, 0.5659, 0.2422, 0.2422,
        0.4971, 0.2422, 0.8613, 0.5659, 0.5859, 0.5879, 0.5889, 0.3477, 0.4243, 0.3389, 0.5659, 0.4790, 0.7227, 0.4590, 0.4839,
        0.4521, 0.3018, 0.2393, 0.3018, 0.6841,
    ]

    static let segoeUIBoldAdvances: [Double] = [
        0.2759, 0.3271, 0.4932, 0.5923, 0.5752, 0.8672, 0.8496, 0.2930, 0.3691, 0.3691, 0.4551, 0.7070, 0.2710, 0.4043, 0.2710,
        0.4434, 0.5752, 0.5752, 0.5752, 0.5752, 0.5752, 0.5752, 0.5752, 0.5752, 0.5752, 0.5752, 0.2710, 0.2710, 0.7070, 0.7070,
        0.7070, 0.4380, 0.9541, 0.7031, 0.6411, 0.6240, 0.7373, 0.5322, 0.5200, 0.7109, 0.7661, 0.3169, 0.4453, 0.6489, 0.5112,
        0.9570, 0.7900, 0.7583, 0.6143, 0.7583, 0.6528, 0.5605, 0.5859, 0.7231, 0.6670, 1.0049, 0.6553, 0.6069, 0.6069, 0.3691,
        0.4360, 0.3691, 0.7070, 0.4150, 0.3140, 0.5381, 0.6201, 0.4800, 0.6191, 0.5410, 0.3833, 0.6191, 0.6021, 0.2842, 0.2842,
        0.5591, 0.2842, 0.9160, 0.6050, 0.6113, 0.6201, 0.6191, 0.3979, 0.4399, 0.3892, 0.6050, 0.5420, 0.7974, 0.5522, 0.5381,
        0.4790, 0.3691, 0.3262, 0.3691, 0.7070,
    ]

    static let segoeUILightAdvances: [Double] = [
        0.2739, 0.2842, 0.3350, 0.6040, 0.5151, 0.7842, 0.6968, 0.2139, 0.2822, 0.2822, 0.4058, 0.6499, 0.2222, 0.3979, 0.2222,
        0.3662, 0.5151, 0.3564, 0.5151, 0.5151, 0.5308, 0.5151, 0.5151, 0.4990, 0.5151, 0.5151, 0.2222, 0.2222, 0.6499, 0.6499,
        0.6499, 0.4302, 0.9438, 0.6289, 0.5439, 0.6211, 0.6738, 0.5000, 0.4648, 0.6680, 0.6768, 0.2280, 0.3242, 0.5269, 0.4580,
        0.8330, 0.7090, 0.7612, 0.5439, 0.7539, 0.5552, 0.4971, 0.5112, 0.6479, 0.6040, 0.8950, 0.5630, 0.5400, 0.5698, 0.2822,
        0.3662, 0.2822, 0.6499, 0.4150, 0.2480, 0.4941, 0.5601, 0.4438, 0.5601, 0.5049, 0.2759, 0.5601, 0.5352, 0.2051, 0.2051,
        0.4438, 0.2051, 0.8218, 0.5352, 0.5610, 0.5601, 0.5601, 0.3301, 0.3882, 0.2969, 0.5352, 0.4531, 0.6768, 0.4209, 0.4531,
        0.4639, 0.2822, 0.2261, 0.2822, 0.6499,
    ]

    static let segoeUIOtherAdvances: [UInt32: Double] = [
        0x00A0: 0.2739, 0x00A1: 0.2842, 0x00A2: 0.5391, 0x00A3: 0.5391, 0x00A4: 0.5557, 0x00A5: 0.5391, 0x00A6: 0.2393, 0x00A7: 0.4482,
        0x00A8: 0.4141, 0x00A9: 0.8901, 0x00AA: 0.3921, 0x00AB: 0.5059, 0x00AC: 0.6841, 0x00AD: 0.3999, 0x00AE: 0.8901, 0x00AF: 0.4150,
        0x00B0: 0.3770, 0x00B1: 0.6841, 0x00B2: 0.3662, 0x00B3: 0.3662, 0x00B4: 0.2822, 0x00B5: 0.5771, 0x00B6: 0.4580, 0x00B7: 0.2168,
        0x00B8: 0.2051, 0x00B9: 0.3511, 0x00BA: 0.4307, 0x00BB: 0.5059, 0x00BC: 0.9062, 0x00BD: 0.9307, 0x00BE: 0.9521, 0x00BF: 0.4482,
        0x00C0: 0.6450, 0x00C1: 0.6450, 0x00C2: 0.6450, 0x00C3: 0.6450, 0x00C4: 0.6450, 0x00C5: 0.6450, 0x00C6: 0.8604, 0x00C7: 0.6191,
        0x00C8: 0.5059, 0x00C9: 0.5059, 0x00CA: 0.5059, 0x00CB: 0.5059, 0x00CC: 0.2661, 0x00CD: 0.2661, 0x00CE: 0.2661, 0x00CF: 0.2661,
        0x00D0: 0.7012, 0x00D1: 0.7480, 0x00D2: 0.7539, 0x00D3: 0.7539, 0x00D4: 0.7539, 0x00D5: 0.7539, 0x00D6: 0.7539, 0x00D7: 0.6841,
        0x00D8: 0.7539, 0x00D9: 0.6870, 0x00DA: 0.6870, 0x00DB: 0.6870, 0x00DC: 0.6870, 0x00DD: 0.5527, 0x00DE: 0.5601, 0x00DF: 0.5439,
        0x00E0: 0.5088, 0x00E1: 0.5088, 0x00E2: 0.5088, 0x00E3: 0.5088, 0x00E4: 0.5088, 0x00E5: 0.5088, 0x00E6: 0.8320, 0x00E7: 0.4619,
        0x00E8: 0.5229, 0x00E9: 0.5229, 0x00EA: 0.5229, 0x00EB: 0.5229, 0x00EC: 0.2422, 0x00ED: 0.2422, 0x00EE: 0.2422, 0x00EF: 0.2422,
        0x00F0: 0.5591, 0x00F1: 0.5659, 0x00F2: 0.5859, 0x00F3: 0.5859, 0x00F4: 0.5859, 0x00F5: 0.5859, 0x00F6: 0.5859, 0x00F7: 0.6841,
        0x00F8: 0.5859, 0x00F9: 0.5659, 0x00FA: 0.5659, 0x00FB: 0.5659, 0x00FC: 0.5659, 0x00FD: 0.4839, 0x00FE: 0.5879, 0x00FF: 0.4839,
        0x0410: 0.6450, 0x0411: 0.5718, 0x0412: 0.5732, 0x0413: 0.4717, 0x0414: 0.6934, 0x0415: 0.5059, 0x0416: 0.8667, 0x0417: 0.5400,
        0x0418: 0.7490, 0x0419: 0.7490, 0x041A: 0.5801, 0x041B: 0.6729, 0x041C: 0.8979, 0x041D: 0.7100, 0x041E: 0.7539, 0x041F: 0.7129,
        0x0420: 0.5601, 0x0421: 0.6191, 0x0422: 0.5239, 0x0423: 0.5674, 0x0424: 0.7266, 0x0425: 0.5898, 0x0426: 0.7422, 0x0427: 0.6611,
        0x0428: 0.9492, 0x0429: 0.9800, 0x042A: 0.7056, 0x042B: 0.7832, 0x042C: 0.5762, 0x042D: 0.6162, 0x042E: 1.0186, 0x042F: 0.5908,
        0x0430: 0.5088, 0x0431: 0.5791, 0x0432: 0.5298, 0x0433: 0.3828, 0x0434: 0.5469, 0x0435: 0.5229, 0x0436: 0.7461, 0x0437: 0.4458,
        0x0438: 0.5811, 0x0439: 0.5811, 0x043A: 0.4971, 0x043B: 0.5269, 0x043C: 0.7021, 0x043D: 0.5771, 0x043E: 0.5859, 0x043F: 0.5771,
        0x0440: 0.5879, 0x0441: 0.4619, 0x0442: 0.4102, 0x0443: 0.4839, 0x0444: 0.6860, 0x0445: 0.4590, 0x0446: 0.6001, 0x0447: 0.5649,
        0x0448: 0.7998, 0x0449: 0.8242, 0x044A: 0.5908, 0x044B: 0.7095, 0x044C: 0.5039, 0x044D: 0.4619, 0x044E: 0.8130, 0x044F: 0.5029,
        0x0401: 0.5059, 0x0451: 0.5229,
    ]

    static let segoeUIBoldOtherAdvances: [UInt32: Double] = [
        0x00A0: 0.2759, 0x00A1: 0.3271, 0x00A2: 0.5752, 0x00A3: 0.5752, 0x00A4: 0.5562, 0x00A5: 0.5752, 0x00A6: 0.3262, 0x00A7: 0.4854,
        0x00A8: 0.4619, 0x00A9: 0.8740, 0x00AA: 0.4102, 0x00AB: 0.5811, 0x00AC: 0.7070, 0x00AD: 0.4043, 0x00AE: 0.8740, 0x00AF: 0.4150,
        0x00B0: 0.3799, 0x00B1: 0.7070, 0x00B2: 0.4043, 0x00B3: 0.4043, 0x00B4: 0.3032, 0x00B5: 0.6128, 0x00B6: 0.5093, 0x00B7: 0.2710,
        0x00B8: 0.2153, 0x00B9: 0.3940, 0x00BA: 0.4561, 0x00BB: 0.5811, 0x00BC: 0.9521, 0x00BD: 0.9653, 0x00BE: 0.9790, 0x00BF: 0.4380,
        0x00C0: 0.7031, 0x00C1: 0.7031, 0x00C2: 0.7031, 0x00C3: 0.7031, 0x00C4: 0.7031, 0x00C5: 0.7031, 0x00C6: 0.9351, 0x00C7: 0.6240,
        0x00C8: 0.5322, 0x00C9: 0.5322, 0x00CA: 0.5322, 0x00CB: 0.5322, 0x00CC: 0.3169, 0x00CD: 0.3169, 0x00CE: 0.3169, 0x00CF: 0.3169,
        0x00D0: 0.7373, 0x00D1: 0.7900, 0x00D2: 0.7578, 0x00D3: 0.7578, 0x00D4: 0.7578, 0x00D5: 0.7578, 0x00D6: 0.7578, 0x00D7: 0.7070,
        0x00D8: 0.7583, 0x00D9: 0.7231, 0x00DA: 0.7231, 0x00DB: 0.7231, 0x00DC: 0.7231, 0x00DD: 0.6069, 0x00DE: 0.6143, 0x00DF: 0.6279,
        0x00E0: 0.5381, 0x00E1: 0.5381, 0x00E2: 0.5381, 0x00E3: 0.5381, 0x00E4: 0.5381, 0x00E5: 0.5381, 0x00E6: 0.8281, 0x00E7: 0.4800,
        0x00E8: 0.5410, 0x00E9: 0.5410, 0x00EA: 0.5410, 0x00EB: 0.5410, 0x00EC: 0.2842, 0x00ED: 0.2842, 0x00EE: 0.2842, 0x00EF: 0.2842,
        0x00F0: 0.5933, 0x00F1: 0.6050, 0x00F2: 0.6108, 0x00F3: 0.6108, 0x00F4: 0.6108, 0x00F5: 0.6108, 0x00F6: 0.6108, 0x00F7: 0.7070,
        0x00F8: 0.6113, 0x00F9: 0.6050, 0x00FA: 0.6050, 0x00FB: 0.6050, 0x00FC: 0.6050, 0x00FD: 0.5381, 0x00FE: 0.6201, 0x00FF: 0.5381,
        0x0410: 0.7031, 0x0411: 0.6421, 0x0412: 0.6411, 0x0413: 0.5117, 0x0414: 0.7749, 0x0415: 0.5322, 0x0416: 0.9927, 0x0417: 0.5586,
        0x0418: 0.7905, 0x0419: 0.7905, 0x041A: 0.6489, 0x041B: 0.7300, 0x041C: 0.9570, 0x041D: 0.7661, 0x041E: 0.7583, 0x041F: 0.7651,
        0x0420: 0.6143, 0x0421: 0.6240, 0x0422: 0.5859, 0x0423: 0.6147, 0x0424: 0.8389, 0x0425: 0.6553, 0x0426: 0.8213, 0x0427: 0.7261,
        0x0428: 1.0112, 0x0429: 1.0664, 0x042A: 0.7573, 0x042B: 0.8984, 0x042C: 0.6230, 0x042D: 0.6235, 0x042E: 1.0640, 0x042F: 0.6401,
        0x0430: 0.5381, 0x0431: 0.6089, 0x0432: 0.5796, 0x0433: 0.4102, 0x0434: 0.6196, 0x0435: 0.5410, 0x0436: 0.8477, 0x0437: 0.4805,
        0x0438: 0.6274, 0x0439: 0.6274, 0x043A: 0.5591, 0x043B: 0.6030, 0x043C: 0.7769, 0x043D: 0.6118, 0x043E: 0.6113, 0x043F: 0.6118,
        0x0440: 0.6201, 0x0441: 0.4800, 0x0442: 0.4546, 0x0443: 0.5381, 0x0444: 0.7842, 0x0445: 0.5522, 0x0446: 0.6514, 0x0447: 0.6006,
        0x0448: 0.8618, 0x0449: 0.9014, 0x044A: 0.6484, 0x044B: 0.8149, 0x044C: 0.5591, 0x044D: 0.4790, 0x044E: 0.8838, 0x044F: 0.5684,
        0x0401: 0.5322, 0x0451: 0.5410,
    ]

    // Aptos's own widths, U+0020 to U+007E, in its Regular and Bold: read from
    // the hmtx of the subsets Word for Windows' prints embed (every print in
    // test/corpus, 2026-11-01; every glyph they hold agrees across prints).
    // Regular holds 74 of the 95, Bold 61; the others are estimates from
    // Liberation Sans's by the median ratio of the known ones of their kind
    // (upper case, lower case, digits, the rest). Aptos is the default face of
    // a document written in Word since 2023, narrower than Arial in the round
    // lower case and wider in "i l t": redline-image-inline's 12pt lines broke
    // a word early in the stand-in.
    static let aptosAdvances: [Double] = [
        0.2031, 0.2930, 0.3696, 0.5717, 0.5717, 0.8262, 0.6856, 0.2104, 0.3423, 0.3423, 0.4000, 0.6003, 0.2856, 0.3403, 0.2856,
        0.2856, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.2856, 0.2856, 0.6003, 0.5342,
        0.6003, 0.5015, 1.0435, 0.5894, 0.6040, 0.6924, 0.6860, 0.5562, 0.5244, 0.7085, 0.7070, 0.2603, 0.3311, 0.5684, 0.4995,
        0.7900, 0.7061, 0.7324, 0.5771, 0.7324, 0.6060, 0.5659, 0.4785, 0.6812, 0.5854, 0.8921, 0.5990, 0.5396, 0.5156, 0.2944,
        0.2856, 0.2944, 0.4824, 0.5717, 0.3423, 0.5312, 0.5610, 0.5249, 0.5605, 0.5269, 0.3013, 0.4844, 0.5513, 0.2388, 0.2388,
        0.4868, 0.2603, 0.8530, 0.5513, 0.5518, 0.5610, 0.5605, 0.3345, 0.4858, 0.3232, 0.5586, 0.4521, 0.7207, 0.4424, 0.4521,
        0.4380, 0.3433, 0.2670, 0.3433, 0.6003,
    ]

    // Aptos Narrow's widths, U+0020 to U+007E, in its Regular and Bold: the
    // advances of each character in Excel's prints (test/corpus/xlsx/excel,
    // every Aptos Narrow run, 2026-11-03), a character's median step over
    // its em. 69 of Regular's 95 and 27 of Bold's were measured; the others
    // are Arial's widths by the median ratio of their kind (upper case .83,
    // lower case and digits .92, the rest .92; Bold's by Regular's .. 1.03).
    static let aptosNarrowAdvances: [Double] = [
        0.1870, 0.2546, 0.3252, 0.5000, 0.5070, 0.8142, 0.6109, 0.1749, 0.3040, 0.3050, 0.3563, 0.5349, 0.2600, 0.3060, 0.2600,
        0.3130, 0.5100, 0.5100, 0.5100, 0.5100, 0.5100, 0.5100, 0.5100, 0.5100, 0.5100, 0.5100, 0.2600, 0.2546, 0.5349, 0.5100,
        0.5349, 0.5092, 0.9297, 0.5310, 0.5530, 0.6330, 0.6290, 0.5090, 0.4800, 0.6450, 0.6460, 0.2380, 0.4145, 0.5530, 0.4570,
        0.7150, 0.6410, 0.6670, 0.5320, 0.6630, 0.5550, 0.5190, 0.4360, 0.6170, 0.5310, 0.8130, 0.5530, 0.4870, 0.5066, 0.2710,
        0.2546, 0.2546, 0.4296, 0.4160, 0.3050, 0.4870, 0.5105, 0.4800, 0.5110, 0.4880, 0.2820, 0.4460, 0.5070, 0.2270, 0.2036,
        0.4430, 0.2390, 0.7840, 0.5100, 0.5000, 0.5110, 0.5110, 0.3085, 0.4430, 0.2960, 0.5100, 0.4140, 0.6520, 0.4020, 0.4140,
        0.4030, 0.3059, 0.2381, 0.3059, 0.5349,
    ]

    static let aptosNarrowBoldAdvances: [Double] = [
        0.1848, 0.2629, 0.3358, 0.5163, 0.5235, 0.8407, 0.6308, 0.1806, 0.3139, 0.3149, 0.3679, 0.5523, 0.2685, 0.3160, 0.2685,
        0.3232, 0.5266, 0.5109, 0.5104, 0.5266, 0.5266, 0.5266, 0.5266, 0.5266, 0.5266, 0.5266, 0.2685, 0.2629, 0.5523, 0.5266,
        0.5523, 0.5258, 0.9600, 0.5483, 0.5710, 0.6300, 0.6330, 0.5256, 0.4956, 0.6660, 0.6670, 0.2457, 0.4280, 0.5710, 0.4719,
        0.7383, 0.6410, 0.6887, 0.5493, 0.6846, 0.5731, 0.5420, 0.4460, 0.6371, 0.5483, 0.8395, 0.5710, 0.5028, 0.5231, 0.2798,
        0.2629, 0.2629, 0.4436, 0.4295, 0.3149, 0.4990, 0.5271, 0.4990, 0.5300, 0.5100, 0.2912, 0.4570, 0.5235, 0.2510, 0.2490,
        0.4574, 0.2710, 0.8060, 0.5220, 0.5210, 0.5276, 0.5276, 0.3360, 0.4590, 0.3150, 0.5220, 0.4450, 0.6740, 0.4151, 0.4275,
        0.4130, 0.3159, 0.2458, 0.3159, 0.5523,
    ]

    static let aptosBoldAdvances: [Double] = [
        0.2031, 0.2930, 0.4199, 0.5087, 0.5087, 0.8134, 0.6606, 0.2175, 0.3046, 0.3046, 0.3560, 0.5342, 0.2998, 0.3403, 0.2998,
        0.2541, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.5342, 0.2998, 0.3046, 0.5342, 0.5342,
        0.5342, 0.5588, 0.8920, 0.6201, 0.6191, 0.7065, 0.7070, 0.5732, 0.5366, 0.7178, 0.7290, 0.2939, 0.3667, 0.6230, 0.5117,
        0.8208, 0.7227, 0.7373, 0.6055, 0.7018, 0.6338, 0.5981, 0.5054, 0.6516, 0.6167, 0.8516, 0.6018, 0.6018, 0.5511, 0.3046,
        0.2541, 0.3046, 0.5342, 0.5087, 0.3046, 0.5518, 0.5864, 0.5488, 0.5859, 0.5562, 0.3350, 0.5112, 0.5791, 0.2681, 0.2666,
        0.5342, 0.2959, 0.8892, 0.5791, 0.5732, 0.5864, 0.5862, 0.3691, 0.5156, 0.3555, 0.5815, 0.4937, 0.7612, 0.4951, 0.4937,
        0.4658, 0.3560, 0.2559, 0.3560, 0.5342,
    ]

    // Century's own widths, U+0020 to U+007E, and its own line: 1.2021 ems by
    // its hhea (ascent 2019, descent 443 of 2048, no gap). Numbers only, read
    // from the box's century.ttf by windows' lab fontmetrics (2026-11-02). It
    // has no metric-compatible free clone; only its Regular is installed on
    // Word's box, so bold and italic keep the stand-in's widths.
    static let centuryAdvances: [Double] = [
        0.2778, 0.2959, 0.3892, 0.5562, 0.5562, 0.8330, 0.8149, 0.2041, 0.3330, 0.3330, 0.5000, 0.6060, 0.2778, 0.3330, 0.2778,
        0.2778, 0.5562, 0.5562, 0.5562, 0.5562, 0.5562, 0.5562, 0.5562, 0.5562, 0.5562, 0.5562, 0.2778, 0.2778, 0.6060, 0.6060,
        0.6060, 0.4438, 0.7368, 0.7222, 0.7222, 0.7222, 0.7778, 0.7222, 0.6670, 0.7778, 0.8330, 0.4072, 0.5562, 0.7778, 0.6670,
        0.9438, 0.8149, 0.7778, 0.6670, 0.7778, 0.7222, 0.6299, 0.6670, 0.8149, 0.7222, 0.9810, 0.7041, 0.7041, 0.6108, 0.3330,
        0.6060, 0.3330, 0.6060, 0.5000, 0.3330, 0.5562, 0.5562, 0.4438, 0.5742, 0.5000, 0.3330, 0.5371, 0.6108, 0.3149, 0.2959,
        0.5928, 0.3149, 0.8892, 0.6108, 0.5000, 0.5742, 0.5562, 0.4438, 0.4629, 0.3892, 0.6108, 0.5371, 0.7778, 0.5371, 0.5371,
        0.4810, 0.3330, 0.6060, 0.3330, 0.6060,
    ]

    // The Microsoft faces below, at their own widths (U+0020-U+007E, regular
    // and bold; italics keep the regular's) and their own line, win ascent plus
    // descent of 2048 as Word on Windows sets a line. Numbers only, read from
    // the box's font files by windows' lab fontmetrics (2026-11-02).
    static let comicSansAdvances: [Double] = [
        0.2988, 0.2378, 0.4243, 0.8428, 0.6934, 0.8203, 0.6543, 0.3882, 0.3662, 0.3662, 0.5298, 0.4805, 0.2769, 0.4165, 0.2490,
        0.5117, 0.6104, 0.4502, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.2988, 0.2988, 0.3813, 0.5103,
        0.3813, 0.5239, 0.9312, 0.7314, 0.6304, 0.6025, 0.7217, 0.6245, 0.6069, 0.6797, 0.7681, 0.5464, 0.6650, 0.6108, 0.5508,
        0.8828, 0.7969, 0.7983, 0.5205, 0.8765, 0.6284, 0.6934, 0.6797, 0.7368, 0.6499, 1.0396, 0.7236, 0.6353, 0.6934, 0.3765,
        0.5498, 0.3765, 0.5811, 0.6270, 0.5562, 0.5117, 0.5933, 0.5137, 0.5874, 0.5479, 0.5083, 0.5308, 0.5776, 0.2803, 0.4033,
        0.5400, 0.2739, 0.7769, 0.5234, 0.5259, 0.5347, 0.5200, 0.4805, 0.4868, 0.4712, 0.5200, 0.4863, 0.6841, 0.5903, 0.5205,
        0.5381, 0.3662, 0.4214, 0.3662, 0.5977,
    ]
    static let comicSansBoldAdvances: [Double] = [
        0.4336, 0.2378, 0.4375, 0.8428, 0.6934, 0.8203, 0.6543, 0.4336, 0.3662, 0.3662, 0.5298, 0.6104, 0.4336, 0.6104, 0.4336,
        0.5117, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.6104, 0.4336, 0.4336, 0.6104, 0.6104,
        0.6104, 0.5659, 0.9312, 0.7314, 0.6304, 0.6187, 0.7217, 0.6245, 0.6069, 0.6797, 0.7681, 0.5464, 0.6650, 0.6108, 0.5508,
        0.8828, 0.8130, 0.7983, 0.5327, 0.8765, 0.6401, 0.6934, 0.6958, 0.7368, 0.6748, 1.0396, 0.7236, 0.6353, 0.6934, 0.3765,
        0.5498, 0.3765, 0.6104, 0.6270, 0.5562, 0.5557, 0.5933, 0.5137, 0.5874, 0.5591, 0.5083, 0.5308, 0.5776, 0.2803, 0.4033,
        0.5400, 0.2739, 0.7769, 0.5234, 0.5259, 0.5347, 0.5200, 0.4805, 0.4868, 0.4712, 0.5200, 0.4863, 0.6841, 0.5903, 0.5527,
        0.5381, 0.3662, 0.4214, 0.3662, 0.6104,
    ]
    static let garamondAdvances: [Double] = [
        0.2500, 0.2188, 0.4062, 0.6665, 0.4478, 0.8228, 0.7290, 0.1772, 0.2915, 0.2915, 0.4272, 0.6665, 0.2188, 0.3125, 0.2188,
        0.5000, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.2188, 0.2188, 0.6665, 0.6665,
        0.6665, 0.3647, 0.9165, 0.6772, 0.6147, 0.6353, 0.7710, 0.6562, 0.5625, 0.7710, 0.7603, 0.3540, 0.3335, 0.7397, 0.5728,
        0.8335, 0.7710, 0.7812, 0.5625, 0.7710, 0.6250, 0.4790, 0.6147, 0.7085, 0.6772, 0.8853, 0.6978, 0.6562, 0.6562, 0.2710,
        0.5000, 0.2710, 0.5000, 0.5000, 0.3335, 0.4062, 0.5103, 0.4165, 0.5000, 0.4165, 0.3228, 0.4478, 0.5103, 0.2290, 0.2290,
        0.4688, 0.2290, 0.7710, 0.5103, 0.5103, 0.5103, 0.4897, 0.3335, 0.3647, 0.2915, 0.4897, 0.4688, 0.6665, 0.4585, 0.4165,
        0.4272, 0.4790, 0.5000, 0.4790, 0.6665,
    ]
    static let garamondBoldAdvances: [Double] = [
        0.2500, 0.2603, 0.5522, 0.6665, 0.4688, 0.8335, 0.8022, 0.2812, 0.3540, 0.3540, 0.4897, 0.6665, 0.2603, 0.3335, 0.2603,
        0.5522, 0.4688, 0.3960, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.2603, 0.2603, 0.6665, 0.6665,
        0.6665, 0.4165, 0.9272, 0.6562, 0.6772, 0.6772, 0.7812, 0.7085, 0.6147, 0.7290, 0.8647, 0.3960, 0.3750, 0.6772, 0.6353,
        0.9165, 0.8438, 0.7915, 0.6147, 0.7915, 0.6978, 0.5103, 0.6875, 0.7603, 0.6665, 0.8960, 0.6875, 0.6562, 0.6665, 0.3647,
        0.5522, 0.3647, 0.5835, 0.5000, 0.3335, 0.4790, 0.5522, 0.4688, 0.5522, 0.4688, 0.3022, 0.5415, 0.5522, 0.2812, 0.2603,
        0.5312, 0.2603, 0.8438, 0.5522, 0.5210, 0.5522, 0.5522, 0.3438, 0.4165, 0.3125, 0.5522, 0.4585, 0.7085, 0.5000, 0.4688,
        0.4688, 0.3960, 0.5415, 0.3960, 0.6665,
    ]
    /// Georgia's widths outside ASCII (Latin-1, Latin Extended-A, general punctuation), from the Windows Word
    /// box's cmap and advances (/data/corpus-cache/metrics/latin/Georgia_*.tsv): the stand-in's em dash is 1.0 em,
    /// Georgia's 0.8569 (xb jpn 3f592b: a line took "had" in Word, the 1.7 pt em dash kept it out).
    static let georgiaOtherAdvances: [UInt32: Double] = [
        0xA0: 0.2412, 0xA1: 0.3311, 0xA2: 0.5552, 0xA3: 0.6221, 0xA4: 0.5713, 0xA5: 0.6147, 0xA6: 0.3750, 0xA7: 0.5000,
        0xA8: 0.5000, 0xA9: 0.9419, 0xAA: 0.5000, 0xAB: 0.5811, 0xAC: 0.6431, 0xAD: 0.3740, 0xAE: 0.9419, 0xAF: 0.6431,
        0xB0: 0.4194, 0xB1: 0.6431, 0xB2: 0.5000, 0xB3: 0.5000, 0xB4: 0.5000, 0xB5: 0.5664, 0xB6: 0.5000, 0xB7: 0.2793,
        0xB8: 0.5000, 0xB9: 0.5000, 0xBA: 0.5000, 0xBB: 0.5811, 0xBC: 1.0498, 0xBD: 1.0498, 0xBE: 1.0498, 0xBF: 0.4785,
        0xC0: 0.6709, 0xC1: 0.6709, 0xC2: 0.6709, 0xC3: 0.6709, 0xC4: 0.6709, 0xC5: 0.6709, 0xC6: 0.9707, 0xC7: 0.6421,
        0xC8: 0.6533, 0xC9: 0.6533, 0xCA: 0.6533, 0xCB: 0.6533, 0xCC: 0.3896, 0xCD: 0.3896, 0xCE: 0.3896, 0xCF: 0.3896,
        0xD0: 0.7490, 0xD1: 0.7671, 0xD2: 0.7441, 0xD3: 0.7441, 0xD4: 0.7441, 0xD5: 0.7441, 0xD6: 0.7441, 0xD7: 0.6431,
        0xD8: 0.7441, 0xD9: 0.7563, 0xDA: 0.7563, 0xDB: 0.7563, 0xDC: 0.7563, 0xDD: 0.6152, 0xDE: 0.6143, 0xDF: 0.5483,
        0xE0: 0.5039, 0xE1: 0.5039, 0xE2: 0.5039, 0xE3: 0.5039, 0xE4: 0.5039, 0xE5: 0.5039, 0xE6: 0.7368, 0xE7: 0.4541,
        0xE8: 0.4834, 0xE9: 0.4834, 0xEA: 0.4834, 0xEB: 0.4834, 0xEC: 0.2930, 0xED: 0.2930, 0xEE: 0.2930, 0xEF: 0.2930,
        0xF0: 0.5317, 0xF1: 0.5908, 0xF2: 0.5391, 0xF3: 0.5391, 0xF4: 0.5391, 0xF5: 0.5391, 0xF6: 0.5391, 0xF7: 0.6431,
        0xF8: 0.5391, 0xF9: 0.5752, 0xFA: 0.5752, 0xFB: 0.5752, 0xFC: 0.5752, 0xFD: 0.4922, 0xFE: 0.5591, 0xFF: 0.4922,
        0x100: 0.6709, 0x101: 0.5039, 0x102: 0.6709, 0x103: 0.5039, 0x104: 0.6709, 0x105: 0.5039, 0x106: 0.6421, 0x107: 0.4541,
        0x108: 0.6421, 0x109: 0.4541, 0x10A: 0.6421, 0x10B: 0.4541, 0x10C: 0.6421, 0x10D: 0.4541, 0x10E: 0.7490, 0x10F: 0.6650,
        0x110: 0.7490, 0x111: 0.5742, 0x112: 0.6533, 0x113: 0.4834, 0x114: 0.6533, 0x115: 0.4834, 0x116: 0.6533, 0x117: 0.4834,
        0x118: 0.6533, 0x119: 0.4834, 0x11A: 0.6533, 0x11B: 0.4834, 0x11C: 0.7251, 0x11D: 0.5093, 0x11E: 0.7251, 0x11F: 0.5093,
        0x120: 0.7251, 0x121: 0.5093, 0x122: 0.7251, 0x123: 0.5093, 0x124: 0.8149, 0x125: 0.5820, 0x126: 0.8149, 0x127: 0.5820,
        0x128: 0.3896, 0x129: 0.2930, 0x12A: 0.3896, 0x12B: 0.2930, 0x12C: 0.3896, 0x12D: 0.2930, 0x12E: 0.3896, 0x12F: 0.2930,
        0x130: 0.3896, 0x131: 0.2930, 0x132: 0.8877, 0x133: 0.5723, 0x134: 0.5176, 0x135: 0.2920, 0x136: 0.6943, 0x137: 0.5356,
        0x138: 0.5444, 0x139: 0.6035, 0x13A: 0.2861, 0x13B: 0.6035, 0x13C: 0.2861, 0x13D: 0.6035, 0x13E: 0.3765, 0x13F: 0.6035,
        0x140: 0.4204, 0x141: 0.6035, 0x142: 0.2861, 0x143: 0.7671, 0x144: 0.5908, 0x145: 0.7671, 0x146: 0.5908, 0x147: 0.7671,
        0x148: 0.5908, 0x149: 0.6445, 0x14A: 0.7671, 0x14B: 0.5786, 0x14C: 0.7441, 0x14D: 0.5391, 0x14E: 0.7441, 0x14F: 0.5391,
        0x150: 0.7441, 0x151: 0.5391, 0x152: 0.9980, 0x153: 0.8164, 0x154: 0.7017, 0x155: 0.4097, 0x156: 0.7017, 0x157: 0.4097,
        0x158: 0.7017, 0x159: 0.4097, 0x15A: 0.5610, 0x15B: 0.4321, 0x15C: 0.5610, 0x15D: 0.4321, 0x15E: 0.5610, 0x15F: 0.4321,
        0x160: 0.5610, 0x161: 0.4321, 0x162: 0.6187, 0x163: 0.3452, 0x164: 0.6187, 0x165: 0.3452, 0x166: 0.6187, 0x167: 0.3452,
        0x168: 0.7563, 0x169: 0.5752, 0x16A: 0.7563, 0x16B: 0.5752, 0x16C: 0.7563, 0x16D: 0.5752, 0x16E: 0.7563, 0x16F: 0.5752,
        0x170: 0.7563, 0x171: 0.5752, 0x172: 0.7563, 0x173: 0.5752, 0x174: 0.9756, 0x175: 0.7373, 0x176: 0.6152, 0x177: 0.4922,
        0x178: 0.6152, 0x179: 0.6016, 0x17A: 0.4438, 0x17B: 0.6016, 0x17C: 0.4438, 0x17D: 0.6016, 0x17E: 0.4438, 0x17F: 0.2993,
        0x192: 0.5190, 0x1FA: 0.6709, 0x1FB: 0.5039, 0x1FC: 0.9707, 0x1FD: 0.7368, 0x1FE: 0.7441, 0x1FF: 0.5391, 0x218: 0.5610,
        0x219: 0.4321, 0x21A: 0.6187, 0x21B: 0.3452, 0x237: 0.2920, 0x2013: 0.6431, 0x2014: 0.8569, 0x2015: 0.8569, 0x2017: 0.6431,
        0x2018: 0.2266, 0x2019: 0.2266, 0x201A: 0.2266, 0x201B: 0.1953, 0x201C: 0.4102, 0x201D: 0.4102, 0x201E: 0.4102, 0x2020: 0.4722,
        0x2021: 0.4722, 0x2022: 0.3926, 0x2026: 0.8071, 0x2030: 1.2056, 0x2032: 0.3213, 0x2033: 0.5171, 0x2039: 0.4150, 0x203A: 0.4150,
        0x203C: 0.5752, 0x203E: 0.6431, 0x2044: 0.0811, 0x20AC: 0.6421, 0x2122: 0.9424, 0x2212: 0.6431,
    ]
    static let georgiaBoldOtherAdvances: [UInt32: Double] = [
        0xA0: 0.2539, 0xA1: 0.3765, 0xA2: 0.6055, 0xA3: 0.6899, 0xA4: 0.7031, 0xA5: 0.7324, 0xA6: 0.3877, 0xA7: 0.5635,
        0xA8: 0.5000, 0xA9: 0.9419, 0xAA: 0.5518, 0xAB: 0.6104, 0xAC: 0.7031, 0xAD: 0.3789, 0xAE: 0.9419, 0xAF: 0.7031,
        0xB0: 0.4199, 0xB1: 0.7031, 0xB2: 0.5518, 0xB3: 0.5518, 0xB4: 0.5000, 0xB5: 0.6680, 0xB6: 0.5488, 0xB7: 0.3379,
        0xB8: 0.5000, 0xB9: 0.5518, 0xBA: 0.5518, 0xBB: 0.6104, 0xBC: 1.0713, 0xBD: 1.0713, 0xBE: 1.0713, 0xBF: 0.5483,
        0xC0: 0.7583, 0xC1: 0.7583, 0xC2: 0.7583, 0xC3: 0.7583, 0xC4: 0.7583, 0xC5: 0.7583, 0xC6: 1.0698, 0xC7: 0.7153,
        0xC8: 0.7212, 0xC9: 0.7212, 0xCA: 0.7212, 0xCB: 0.7212, 0xCC: 0.4458, 0xCD: 0.4458, 0xCE: 0.4458, 0xCF: 0.4458,
        0xD0: 0.8340, 0xD1: 0.8394, 0xD2: 0.8198, 0xD3: 0.8198, 0xD4: 0.8198, 0xD5: 0.8198, 0xD6: 0.8198, 0xD7: 0.7031,
        0xD8: 0.8198, 0xD9: 0.8335, 0xDA: 0.8335, 0xDB: 0.8335, 0xDC: 0.8335, 0xDD: 0.7319, 0xDE: 0.7080, 0xDF: 0.6577,
        0xE0: 0.5957, 0xE1: 0.5957, 0xE2: 0.5957, 0xE3: 0.5957, 0xE4: 0.5957, 0xE5: 0.5957, 0xE6: 0.8574, 0xE7: 0.5312,
        0xE8: 0.5718, 0xE9: 0.5718, 0xEA: 0.5718, 0xEB: 0.5718, 0xEC: 0.3535, 0xED: 0.3535, 0xEE: 0.3535, 0xEF: 0.3535,
        0xF0: 0.6377, 0xF1: 0.6899, 0xF2: 0.6357, 0xF3: 0.6357, 0xF4: 0.6357, 0xF5: 0.6357, 0xF6: 0.6357, 0xF7: 0.7031,
        0xF8: 0.6357, 0xF9: 0.6768, 0xFA: 0.6768, 0xFB: 0.6768, 0xFC: 0.6768, 0xFD: 0.5620, 0xFE: 0.6450, 0xFF: 0.5620,
        0x100: 0.7583, 0x101: 0.5957, 0x102: 0.7583, 0x103: 0.5957, 0x104: 0.7583, 0x105: 0.5957, 0x106: 0.7153, 0x107: 0.5312,
        0x108: 0.7153, 0x109: 0.5312, 0x10A: 0.7153, 0x10B: 0.5312, 0x10C: 0.7153, 0x10D: 0.5312, 0x10E: 0.8340, 0x10F: 0.8257,
        0x110: 0.8340, 0x111: 0.6631, 0x112: 0.7212, 0x113: 0.5718, 0x114: 0.7212, 0x115: 0.5718, 0x116: 0.7212, 0x117: 0.5718,
        0x118: 0.7212, 0x119: 0.5718, 0x11A: 0.7212, 0x11B: 0.5718, 0x11C: 0.8071, 0x11D: 0.5767, 0x11E: 0.8071, 0x11F: 0.5767,
        0x120: 0.8071, 0x121: 0.5767, 0x122: 0.8071, 0x123: 0.5767, 0x124: 0.9131, 0x125: 0.6797, 0x126: 0.9131, 0x127: 0.6797,
        0x128: 0.4458, 0x129: 0.3535, 0x12A: 0.4458, 0x12B: 0.3535, 0x12C: 0.4458, 0x12D: 0.3535, 0x12E: 0.4458, 0x12F: 0.3535,
        0x130: 0.4458, 0x131: 0.3535, 0x132: 0.9961, 0x133: 0.6768, 0x134: 0.5952, 0x135: 0.3462, 0x136: 0.8169, 0x137: 0.6318,
        0x138: 0.6426, 0x139: 0.6855, 0x13A: 0.3442, 0x13B: 0.6855, 0x13C: 0.3442, 0x13D: 0.6855, 0x13E: 0.5073, 0x13F: 0.6855,
        0x140: 0.5361, 0x141: 0.6855, 0x142: 0.3442, 0x143: 0.8394, 0x144: 0.6899, 0x145: 0.8394, 0x146: 0.6899, 0x147: 0.8394,
        0x148: 0.6899, 0x149: 0.8271, 0x14A: 0.8394, 0x14B: 0.6807, 0x14C: 0.8198, 0x14D: 0.6357, 0x14E: 0.8198, 0x14F: 0.6357,
        0x150: 0.8198, 0x151: 0.6357, 0x152: 1.1006, 0x153: 0.9380, 0x154: 0.7974, 0x155: 0.5200, 0x156: 0.7974, 0x157: 0.5200,
        0x158: 0.7974, 0x159: 0.5200, 0x15A: 0.6489, 0x15B: 0.5127, 0x15C: 0.6489, 0x15D: 0.5127, 0x15E: 0.6489, 0x15F: 0.5127,
        0x160: 0.6489, 0x161: 0.5127, 0x162: 0.6841, 0x163: 0.3975, 0x164: 0.6841, 0x165: 0.3975, 0x166: 0.6841, 0x167: 0.3975,
        0x168: 0.8335, 0x169: 0.6768, 0x16A: 0.8335, 0x16B: 0.6768, 0x16C: 0.8335, 0x16D: 0.6768, 0x16E: 0.8335, 0x16F: 0.6768,
        0x170: 0.8335, 0x171: 0.6768, 0x172: 0.8335, 0x173: 0.6768, 0x174: 1.1265, 0x175: 0.8633, 0x176: 0.7319, 0x177: 0.5620,
        0x178: 0.7319, 0x179: 0.6895, 0x17A: 0.5254, 0x17B: 0.6895, 0x17C: 0.5254, 0x17D: 0.6895, 0x17E: 0.5254, 0x17F: 0.3530,
        0x192: 0.5791, 0x1FA: 0.7583, 0x1FB: 0.5957, 0x1FC: 1.0698, 0x1FD: 0.8574, 0x1FE: 0.8198, 0x1FF: 0.6357, 0x218: 0.6489,
        0x219: 0.5127, 0x21A: 0.6841, 0x21B: 0.3975, 0x237: 0.3462, 0x2013: 0.7031, 0x2014: 0.9277, 0x2015: 0.9277, 0x2017: 0.7031,
        0x2018: 0.2686, 0x2019: 0.2686, 0x201A: 0.2686, 0x201B: 0.2686, 0x201C: 0.5190, 0x201D: 0.5190, 0x201E: 0.5190, 0x2020: 0.4819,
        0x2021: 0.4819, 0x2022: 0.4375, 0x2026: 0.9419, 0x2030: 1.3086, 0x2032: 0.3213, 0x2033: 0.5327, 0x2039: 0.3960, 0x203A: 0.3960,
        0x203C: 0.6646, 0x203E: 0.7031, 0x2044: 0.0947, 0x20AC: 0.7153, 0x2122: 0.9473, 0x2212: 0.7031,
    ]
    static let georgiaAdvances: [Double] = [
        0.2412, 0.3311, 0.4116, 0.6431, 0.6099, 0.8174, 0.7104, 0.2153, 0.3750, 0.3750, 0.4722, 0.6431, 0.2695, 0.3740, 0.2695,
        0.4688, 0.6138, 0.4297, 0.5586, 0.5518, 0.5649, 0.5283, 0.5659, 0.5024, 0.5962, 0.5659, 0.3125, 0.3125, 0.6431, 0.6431,
        0.6431, 0.4785, 0.9287, 0.6709, 0.6538, 0.6421, 0.7490, 0.6533, 0.5991, 0.7251, 0.8149, 0.3896, 0.5176, 0.6943, 0.6035,
        0.9272, 0.7671, 0.7441, 0.6099, 0.7441, 0.7017, 0.5610, 0.6187, 0.7563, 0.6665, 0.9756, 0.7104, 0.6152, 0.6016, 0.3750,
        0.4688, 0.3750, 0.6431, 0.6431, 0.5000, 0.5039, 0.5601, 0.4541, 0.5742, 0.4834, 0.3252, 0.5093, 0.5820, 0.2930, 0.2920,
        0.5356, 0.2861, 0.8809, 0.5908, 0.5391, 0.5713, 0.5596, 0.4097, 0.4321, 0.3452, 0.5752, 0.4966, 0.7373, 0.5049, 0.4922,
        0.4438, 0.4302, 0.3750, 0.4302, 0.6431,
    ]
    static let georgiaBoldAdvances: [Double] = [
        0.2539, 0.3765, 0.5098, 0.7031, 0.6406, 0.8794, 0.7993, 0.2690, 0.4468, 0.4468, 0.4819, 0.7031, 0.3281, 0.3789, 0.3281,
        0.4717, 0.7012, 0.4897, 0.6265, 0.6245, 0.6494, 0.5991, 0.6479, 0.5542, 0.6763, 0.6479, 0.3672, 0.3672, 0.7031, 0.7031,
        0.7031, 0.5483, 0.9668, 0.7583, 0.7573, 0.7153, 0.8340, 0.7212, 0.6714, 0.8071, 0.9131, 0.4458, 0.5952, 0.8169, 0.6855,
        1.0234, 0.8394, 0.8198, 0.7012, 0.8198, 0.7974, 0.6489, 0.6841, 0.8335, 0.7622, 1.1265, 0.8086, 0.7319, 0.6895, 0.4468,
        0.4717, 0.4468, 0.7031, 0.7031, 0.5000, 0.5957, 0.6455, 0.5312, 0.6631, 0.5718, 0.3931, 0.5767, 0.6797, 0.3535, 0.3462,
        0.6318, 0.3442, 1.0156, 0.6899, 0.6357, 0.6577, 0.6484, 0.5200, 0.5127, 0.3975, 0.6768, 0.5669, 0.8633, 0.5879, 0.5620,
        0.5254, 0.5000, 0.3877, 0.5000, 0.7031,
    ]
    // Candara's widths (U+0020-U+007E, ems) from the hmtx of the subsets Word's and PowerPoint's prints embed (the
    // same widths as the Slides table); its line is hhea 1484/564/452 over 2048, which Word steps 1.2207 em, baseline
    // at the win ascent (xd 07356df9: 18 pt bold italic steps 22.0, the Liberation Sans stand-in 20.7). Italic and
    // bold italic: the glyphs the prints used, the rest the regular's by the median ratio of the known of their kind.
    static let candaraAdvances: [Double] = [
        0.2168, 0.2520, 0.4521, 0.5044, 0.4438, 0.5044, 0.6816, 0.2544, 0.3530, 0.3530, 0.5044, 0.5044, 0.2520, 0.2520, 0.2520,
        0.2671, 0.5493, 0.3496, 0.4619, 0.4858, 0.5332, 0.4912, 0.5518, 0.4727, 0.5503, 0.5483, 0.2520, 0.2520, 0.5044, 0.5044,
        0.5044, 0.3530, 1.0088, 0.6162, 0.5859, 0.5493, 0.6426, 0.5205, 0.4893, 0.6206, 0.6519, 0.2764, 0.4155, 0.5918, 0.4897,
        0.8535, 0.6738, 0.6938, 0.5527, 0.6938, 0.6055, 0.5112, 0.5093, 0.6826, 0.5537, 0.8862, 0.5581, 0.5503, 0.5186, 0.3530,
        0.2671, 0.3530, 0.5044, 0.5044, 0.2744, 0.4907, 0.5557, 0.4517, 0.5503, 0.5132, 0.3389, 0.5396, 0.5415, 0.2178, 0.2178,
        0.4883, 0.2290, 0.8188, 0.5415, 0.5586, 0.5557, 0.5562, 0.3545, 0.4189, 0.3589, 0.5356, 0.4805, 0.7661, 0.5039, 0.4648,
        0.4556, 0.3530, 0.2520, 0.3530, 0.5044,
    ]
    static let candaraBoldAdvances: [Double] = [
        0.2168, 0.2520, 0.4570, 0.5044, 0.4438, 0.5044, 0.6816, 0.2520, 0.3530, 0.3530, 0.5044, 0.5044, 0.2520, 0.2520, 0.2520,
        0.2671, 0.5342, 0.3345, 0.4795, 0.4707, 0.5366, 0.4731, 0.5288, 0.4648, 0.5361, 0.5278, 0.2520, 0.2520, 0.5044, 0.5044,
        0.5044, 0.3530, 1.0088, 0.6299, 0.5977, 0.5522, 0.6450, 0.5273, 0.4907, 0.6216, 0.6533, 0.2788, 0.3994, 0.5894, 0.4854,
        0.8638, 0.6646, 0.6968, 0.5557, 0.6968, 0.5957, 0.5229, 0.5259, 0.6577, 0.5737, 0.9165, 0.5874, 0.5518, 0.5146, 0.3530,
        0.2671, 0.3530, 0.5044, 0.5044, 0.2744, 0.4912, 0.5547, 0.4453, 0.5503, 0.5122, 0.3618, 0.5508, 0.5498, 0.2490, 0.2490,
        0.5103, 0.2578, 0.8320, 0.5498, 0.5586, 0.5596, 0.5547, 0.3853, 0.4194, 0.3628, 0.5405, 0.4893, 0.7876, 0.5151, 0.4893,
        0.4346, 0.3530, 0.2520, 0.3530, 0.5044,
    ]
    static let candaraItalicAdvances: [Double] = [
        0.2061, 0.2520, 0.4355, 0.5044, 0.4438, 0.5044, 0.6816, 0.2393, 0.3530, 0.3530, 0.5044, 0.5044, 0.2520, 0.2520, 0.2520,
        0.2671, 0.5347, 0.3408, 0.4321, 0.4639, 0.4985, 0.4585, 0.5216, 0.4468, 0.5201, 0.5183, 0.2520, 0.2520, 0.5044, 0.5044,
        0.5044, 0.3530, 1.0088, 0.5699, 0.5419, 0.4932, 0.5913, 0.4814, 0.4546, 0.5679, 0.6029, 0.2412, 0.3843, 0.5473, 0.4529,
        0.7783, 0.6232, 0.6436, 0.5112, 0.6417, 0.5600, 0.4873, 0.5044, 0.6313, 0.5121, 0.8999, 0.5162, 0.5090, 0.4796, 0.3530,
        0.2671, 0.3530, 0.5044, 0.5044, 0.2744, 0.4785, 0.5400, 0.4219, 0.5381, 0.4756, 0.3325, 0.5078, 0.5249, 0.2271, 0.2271,
        0.4868, 0.2295, 0.8027, 0.5229, 0.5298, 0.5366, 0.5424, 0.3638, 0.3921, 0.3716, 0.5229, 0.4688, 0.7397, 0.4946, 0.4531,
        0.4194, 0.3530, 0.2520, 0.3530, 0.5044,
    ]
    static let candaraBoldItalicAdvances: [Double] = [
        0.2114, 0.2520, 0.4526, 0.5044, 0.4438, 0.5044, 0.6816, 0.2456, 0.3530, 0.3530, 0.5044, 0.5044, 0.2520, 0.2520, 0.2520,
        0.2671, 0.5498, 0.3633, 0.4512, 0.4668, 0.5103, 0.4702, 0.5269, 0.4673, 0.5335, 0.5252, 0.2520, 0.2520, 0.5044, 0.5044,
        0.5044, 0.3530, 1.0088, 0.5938, 0.5742, 0.5122, 0.6157, 0.5034, 0.4790, 0.5884, 0.6343, 0.2803, 0.3989, 0.5662, 0.4663,
        0.8096, 0.6384, 0.6509, 0.5532, 0.6509, 0.5830, 0.5054, 0.5181, 0.6318, 0.5511, 0.9092, 0.5643, 0.5200, 0.4943, 0.3530,
        0.2671, 0.3530, 0.5044, 0.5044, 0.2744, 0.5034, 0.5444, 0.4229, 0.5430, 0.4814, 0.3384, 0.5259, 0.5347, 0.2383, 0.2383,
        0.4966, 0.2534, 0.8149, 0.5337, 0.5347, 0.5405, 0.5382, 0.3696, 0.3965, 0.3643, 0.5303, 0.4790, 0.7637, 0.5005, 0.4712,
        0.4216, 0.3530, 0.2520, 0.3530, 0.5044,
    ]
    static let corbelAdvances: [Double] = [
        0.2002, 0.2642, 0.3623, 0.6548, 0.5127, 0.8047, 0.6694, 0.1958, 0.2998, 0.2998, 0.5376, 0.5127, 0.2637, 0.3325, 0.2642,
        0.2749, 0.5137, 0.4482, 0.5107, 0.4531, 0.5166, 0.4800, 0.5244, 0.4277, 0.5146, 0.5244, 0.2642, 0.2666, 0.5127, 0.5127,
        0.5127, 0.4263, 1.0107, 0.6353, 0.5933, 0.5894, 0.6709, 0.5513, 0.5044, 0.6680, 0.6675, 0.2456, 0.3745, 0.6050, 0.5205,
        0.8218, 0.6963, 0.7305, 0.5703, 0.7393, 0.5918, 0.5518, 0.5552, 0.6709, 0.6069, 0.8818, 0.5840, 0.5942, 0.5854, 0.3154,
        0.2749, 0.3154, 0.5127, 0.4883, 0.3418, 0.4897, 0.5356, 0.4385, 0.5356, 0.4976, 0.3179, 0.5308, 0.5322, 0.2319, 0.2412,
        0.4868, 0.2319, 0.8286, 0.5273, 0.5332, 0.5308, 0.5234, 0.3350, 0.4043, 0.3472, 0.5176, 0.4619, 0.7119, 0.4551, 0.4795,
        0.4443, 0.3003, 0.2271, 0.3003, 0.5127,
    ]
    static let corbelBoldAdvances: [Double] = [
        0.2061, 0.2925, 0.3945, 0.6646, 0.5273, 0.8271, 0.6919, 0.2104, 0.3057, 0.3057, 0.5278, 0.5273, 0.3169, 0.3325, 0.2925,
        0.2944, 0.5151, 0.4946, 0.4990, 0.4878, 0.5278, 0.4893, 0.5503, 0.4883, 0.5557, 0.5508, 0.2925, 0.3169, 0.5273, 0.5273,
        0.5273, 0.4492, 1.0244, 0.6572, 0.6230, 0.5845, 0.6890, 0.5679, 0.5210, 0.6724, 0.6982, 0.2759, 0.4023, 0.6318, 0.5376,
        0.8262, 0.7275, 0.7344, 0.6006, 0.7603, 0.6279, 0.5771, 0.5703, 0.7002, 0.6377, 0.9102, 0.6357, 0.6343, 0.6011, 0.3154,
        0.2944, 0.3154, 0.5273, 0.4883, 0.3906, 0.5146, 0.5571, 0.4409, 0.5576, 0.5127, 0.3281, 0.5498, 0.5596, 0.2485, 0.2627,
        0.5161, 0.2524, 0.8521, 0.5547, 0.5537, 0.5498, 0.5498, 0.3496, 0.4238, 0.3794, 0.5449, 0.4912, 0.7490, 0.5215, 0.5137,
        0.4678, 0.3052, 0.2368, 0.3052, 0.5273,
    ]
    static let consolasAdvances: [Double] = [
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
    ]
    static let consolasBoldAdvances: [Double] = [
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
    ]
    static let centuryGothicAdvances: [Double] = [
        0.2769, 0.2949, 0.3091, 0.7202, 0.5542, 0.7749, 0.7568, 0.1978, 0.3691, 0.3691, 0.4248, 0.6060, 0.2769, 0.3320, 0.2769,
        0.4370, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.2769, 0.2769, 0.6060, 0.6060,
        0.6060, 0.5908, 0.8672, 0.7397, 0.5742, 0.8130, 0.7441, 0.5361, 0.4849, 0.8721, 0.6831, 0.2261, 0.4819, 0.5908, 0.4619,
        0.9189, 0.7397, 0.8691, 0.5918, 0.8711, 0.6069, 0.4980, 0.4258, 0.6548, 0.7021, 0.9600, 0.6089, 0.5918, 0.4800, 0.3511,
        0.6050, 0.3511, 0.6719, 0.5000, 0.3779, 0.6831, 0.6821, 0.6470, 0.6851, 0.6499, 0.3140, 0.6729, 0.6099, 0.2002, 0.2031,
        0.5020, 0.2002, 0.9380, 0.6099, 0.6548, 0.6821, 0.6821, 0.3008, 0.3882, 0.3389, 0.6079, 0.5542, 0.8311, 0.4800, 0.5361,
        0.4248, 0.3511, 0.6719, 0.3511, 0.6060,
    ]
    static let centuryGothicBoldAdvances: [Double] = [
        0.2798, 0.2798, 0.3599, 0.6001, 0.5601, 0.8599, 0.6802, 0.2202, 0.3799, 0.3799, 0.4399, 0.6001, 0.2798, 0.4199, 0.2798,
        0.4600, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.2798, 0.2798, 0.6001, 0.6001,
        0.6001, 0.5601, 0.7397, 0.7397, 0.5801, 0.7798, 0.7002, 0.5200, 0.4800, 0.8398, 0.6802, 0.2798, 0.4800, 0.6201, 0.4399,
        0.8999, 0.7397, 0.8398, 0.5601, 0.8398, 0.5801, 0.5200, 0.4199, 0.6401, 0.7002, 0.8999, 0.6802, 0.6201, 0.5000, 0.3198,
        0.6401, 0.3198, 0.6001, 0.5000, 0.4199, 0.6602, 0.6602, 0.6401, 0.6602, 0.6401, 0.2798, 0.6602, 0.6001, 0.2397, 0.2598,
        0.5801, 0.2397, 0.9399, 0.6001, 0.6401, 0.6602, 0.6602, 0.3198, 0.4399, 0.2998, 0.6001, 0.5601, 0.7998, 0.5601, 0.5801,
        0.4600, 0.3398, 0.6001, 0.3398, 0.6001,
    ]

    // Their italics and bold italics (Garamond has no bold italic; Word then
    // draws the italic emboldened, at the italic's widths).
    static let garamondItalicAdvances: [Double] = [
        0.2500, 0.2188, 0.4165, 0.6665, 0.4375, 0.7500, 0.9062, 0.2188, 0.2710, 0.2710, 0.4272, 0.6665, 0.2188, 0.2603, 0.2188,
        0.5000, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.4688, 0.2188, 0.2188, 0.6665, 0.6665,
        0.6665, 0.3647, 0.9165, 0.7603, 0.5625, 0.6250, 0.7290, 0.6875, 0.5728, 0.7085, 0.7710, 0.3228, 0.3228, 0.5938, 0.6353,
        0.8228, 0.7812, 0.6772, 0.5312, 0.6875, 0.6250, 0.5000, 0.5835, 0.7188, 0.8022, 0.8853, 0.7397, 0.6460, 0.6040, 0.3022,
        0.5000, 0.3022, 0.5000, 0.5000, 0.3335, 0.4062, 0.4062, 0.2710, 0.4062, 0.2915, 0.2188, 0.3228, 0.4165, 0.2290, 0.2085,
        0.5210, 0.2188, 0.6250, 0.4272, 0.3540, 0.4062, 0.4272, 0.3022, 0.2915, 0.2500, 0.4272, 0.3438, 0.5312, 0.5000, 0.3335,
        0.4165, 0.4790, 0.5000, 0.4790, 0.6665,
    ]
    static let georgiaItalicAdvances: [Double] = [
        0.2412, 0.3311, 0.4116, 0.6431, 0.6099, 0.8174, 0.7104, 0.2153, 0.3750, 0.3750, 0.4722, 0.6431, 0.2695, 0.3740, 0.2695,
        0.4688, 0.6138, 0.4297, 0.5586, 0.5518, 0.5649, 0.5283, 0.5659, 0.4966, 0.5962, 0.5659, 0.3838, 0.3838, 0.6431, 0.6431,
        0.6431, 0.4785, 0.9287, 0.6709, 0.6538, 0.6421, 0.7490, 0.6533, 0.5991, 0.7251, 0.8149, 0.3896, 0.5176, 0.6943, 0.6035,
        0.9272, 0.7671, 0.7305, 0.6099, 0.7305, 0.7017, 0.5610, 0.6187, 0.7563, 0.6665, 0.9756, 0.7104, 0.6152, 0.6016, 0.3750,
        0.4688, 0.3750, 0.6431, 0.6431, 0.5000, 0.5728, 0.5537, 0.4536, 0.5752, 0.4717, 0.3286, 0.5728, 0.5625, 0.2974, 0.2910,
        0.5278, 0.2852, 0.8794, 0.5898, 0.5371, 0.5781, 0.5552, 0.4614, 0.4312, 0.3472, 0.5752, 0.5381, 0.8223, 0.5010, 0.5596,
        0.4438, 0.4302, 0.3750, 0.4302, 0.6431,
    ]
    static let georgiaBoldItalicAdvances: [Double] = [
        0.2539, 0.3765, 0.5098, 0.7031, 0.6406, 0.8794, 0.7993, 0.2690, 0.4468, 0.4468, 0.4819, 0.7031, 0.3281, 0.3789, 0.3281,
        0.4717, 0.7012, 0.4897, 0.6265, 0.6245, 0.6494, 0.5991, 0.6479, 0.5664, 0.6763, 0.6479, 0.3672, 0.3672, 0.7031, 0.7031,
        0.7031, 0.5483, 0.9668, 0.7583, 0.7593, 0.7153, 0.8340, 0.7212, 0.6714, 0.8071, 0.9131, 0.4507, 0.5952, 0.8169, 0.6855,
        1.0332, 0.8296, 0.8198, 0.7061, 0.8198, 0.7974, 0.6528, 0.6841, 0.8335, 0.7622, 1.1265, 0.8022, 0.7319, 0.6895, 0.4468,
        0.4717, 0.4468, 0.7031, 0.7031, 0.5000, 0.6602, 0.6489, 0.5356, 0.6626, 0.5571, 0.3809, 0.6494, 0.6753, 0.3657, 0.3647,
        0.6411, 0.3545, 1.0020, 0.6899, 0.6357, 0.6626, 0.6499, 0.5337, 0.5171, 0.4170, 0.6851, 0.6123, 0.9336, 0.5835, 0.6694,
        0.5171, 0.5000, 0.3877, 0.5000, 0.7031,
    ]
    static let corbelItalicAdvances: [Double] = [
        0.2002, 0.2642, 0.3521, 0.6299, 0.5029, 0.8271, 0.6357, 0.1855, 0.2832, 0.2832, 0.5356, 0.5127, 0.2646, 0.3228, 0.2646,
        0.2749, 0.5049, 0.4536, 0.5039, 0.4536, 0.5020, 0.4873, 0.5073, 0.4194, 0.5039, 0.5073, 0.2646, 0.2646, 0.5127, 0.5127,
        0.5127, 0.4150, 0.9937, 0.6113, 0.5908, 0.5635, 0.6504, 0.5239, 0.4780, 0.6714, 0.6543, 0.2495, 0.3628, 0.5708, 0.4966,
        0.7910, 0.6743, 0.6968, 0.5693, 0.6968, 0.5811, 0.5469, 0.5171, 0.6445, 0.5723, 0.8589, 0.5801, 0.5356, 0.5674, 0.3091,
        0.2749, 0.3091, 0.5127, 0.4883, 0.3418, 0.5063, 0.4878, 0.4146, 0.5127, 0.4561, 0.3145, 0.4990, 0.5225, 0.2134, 0.2251,
        0.4536, 0.2397, 0.7822, 0.5176, 0.4912, 0.4995, 0.4941, 0.3179, 0.3984, 0.3413, 0.4980, 0.4673, 0.7124, 0.4556, 0.4697,
        0.4268, 0.2925, 0.2271, 0.2925, 0.5127,
    ]
    static let corbelBoldItalicAdvances: [Double] = [
        0.2061, 0.2925, 0.3945, 0.6460, 0.5176, 0.8643, 0.7129, 0.2104, 0.3057, 0.3057, 0.5278, 0.5273, 0.3213, 0.3325, 0.3003,
        0.2944, 0.5005, 0.4814, 0.4990, 0.4590, 0.5171, 0.4878, 0.5420, 0.4531, 0.5459, 0.5469, 0.3027, 0.3140, 0.5273, 0.5273,
        0.5273, 0.4492, 0.9980, 0.6475, 0.6084, 0.5786, 0.6743, 0.5449, 0.5010, 0.6782, 0.6650, 0.2690, 0.3901, 0.5850, 0.5381,
        0.7974, 0.6924, 0.7051, 0.5864, 0.7100, 0.5972, 0.5630, 0.5669, 0.6587, 0.6221, 0.9053, 0.6338, 0.5674, 0.5996, 0.3154,
        0.2944, 0.3154, 0.5273, 0.4883, 0.3906, 0.5381, 0.5054, 0.4351, 0.5405, 0.4839, 0.3599, 0.5156, 0.5435, 0.2451, 0.2583,
        0.4854, 0.2720, 0.7998, 0.5386, 0.5117, 0.5122, 0.5137, 0.3584, 0.4185, 0.3735, 0.5249, 0.4941, 0.7310, 0.5010, 0.4912,
        0.4561, 0.3052, 0.2368, 0.3052, 0.5273,
    ]
    static let consolasItalicAdvances: [Double] = [
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
    ]
    static let consolasBoldItalicAdvances: [Double] = [
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
        0.5498, 0.5498, 0.5498, 0.5498, 0.5498,
    ]
    static let centuryGothicItalicAdvances: [Double] = [
        0.2769, 0.2949, 0.3091, 0.7202, 0.5542, 0.7749, 0.7568, 0.1978, 0.3691, 0.3691, 0.4248, 0.6060, 0.2769, 0.3320, 0.2769,
        0.4370, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.5542, 0.2769, 0.2769, 0.6060, 0.6060,
        0.6060, 0.5908, 0.8672, 0.7397, 0.5742, 0.8130, 0.7441, 0.5361, 0.4849, 0.8721, 0.6831, 0.2261, 0.4819, 0.5908, 0.4619,
        0.9189, 0.7397, 0.8691, 0.5918, 0.8711, 0.6069, 0.4980, 0.4258, 0.6548, 0.7021, 0.9600, 0.6089, 0.5918, 0.4800, 0.3511,
        0.6050, 0.3511, 0.6719, 0.5000, 0.3779, 0.6831, 0.6821, 0.6470, 0.6851, 0.6499, 0.3140, 0.6729, 0.6099, 0.2002, 0.2031,
        0.5020, 0.2002, 0.9380, 0.6099, 0.6548, 0.6821, 0.6821, 0.3008, 0.3882, 0.3389, 0.6079, 0.5542, 0.8311, 0.4800, 0.5361,
        0.4248, 0.3511, 0.6719, 0.3511, 0.6060,
    ]
    static let centuryGothicBoldItalicAdvances: [Double] = [
        0.2798, 0.2798, 0.3599, 0.6001, 0.5601, 0.8599, 0.6802, 0.2202, 0.3799, 0.3799, 0.4399, 0.6001, 0.2798, 0.4199, 0.2798,
        0.4600, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.5601, 0.2798, 0.2798, 0.6001, 0.6001,
        0.6001, 0.5601, 0.7397, 0.7397, 0.5801, 0.7798, 0.7002, 0.5200, 0.4800, 0.8398, 0.6802, 0.2798, 0.4800, 0.6201, 0.4399,
        0.8999, 0.7397, 0.8398, 0.5601, 0.8398, 0.5801, 0.5200, 0.4199, 0.6401, 0.7002, 0.8999, 0.6802, 0.6201, 0.5000, 0.3198,
        0.6401, 0.3198, 0.6001, 0.5000, 0.4199, 0.6602, 0.6602, 0.6401, 0.6602, 0.6401, 0.2798, 0.6602, 0.6001, 0.2397, 0.2598,
        0.5801, 0.2397, 0.9399, 0.6001, 0.6401, 0.6602, 0.6602, 0.3198, 0.4399, 0.2998, 0.6001, 0.5601, 0.7998, 0.5601, 0.5801,
        0.4600, 0.3398, 0.6001, 0.3398, 0.6001,
    ]
    static let verdanaItalicAdvances: [Double] = [
        0.3516, 0.3936, 0.4590, 0.8184, 0.6357, 1.0762, 0.7266, 0.2686, 0.4541, 0.4541, 0.6357, 0.8184, 0.3638, 0.4541, 0.3638,
        0.4541, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.6357, 0.4541, 0.4541, 0.8184, 0.8184,
        0.8184, 0.5454, 1.0000, 0.6826, 0.6855, 0.6982, 0.7656, 0.6323, 0.5747, 0.7754, 0.7515, 0.4209, 0.4546, 0.6929, 0.5566,
        0.8428, 0.7480, 0.7871, 0.6030, 0.7871, 0.6953, 0.6836, 0.6162, 0.7319, 0.6826, 0.9902, 0.6851, 0.6152, 0.6851, 0.4541,
        0.4541, 0.4541, 0.8184, 0.6357, 0.6357, 0.6006, 0.6230, 0.5210, 0.6230, 0.5957, 0.3516, 0.6216, 0.6328, 0.2744, 0.3442,
        0.5869, 0.2744, 0.9731, 0.6328, 0.6069, 0.6230, 0.6230, 0.4268, 0.5210, 0.3940, 0.6328, 0.5908, 0.8184, 0.5918, 0.5908,
        0.5254, 0.6348, 0.4541, 0.6348, 0.8184,
    ]
    static let verdanaBoldItalicAdvances: [Double] = [
        0.3418, 0.4023, 0.5874, 0.8672, 0.7109, 1.2720, 0.8623, 0.3320, 0.5435, 0.5435, 0.7109, 0.8672, 0.3613, 0.4800, 0.3613,
        0.6895, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.7109, 0.4023, 0.4023, 0.8672, 0.8672,
        0.8672, 0.6167, 0.9639, 0.7764, 0.7617, 0.7236, 0.8301, 0.6831, 0.6504, 0.8110, 0.8374, 0.5459, 0.5552, 0.7710, 0.6372,
        0.9478, 0.8467, 0.8501, 0.7329, 0.8501, 0.7822, 0.7104, 0.6816, 0.8120, 0.7637, 1.1284, 0.7637, 0.7368, 0.6919, 0.5435,
        0.6895, 0.5435, 0.8672, 0.7109, 0.7109, 0.6680, 0.6992, 0.5884, 0.6992, 0.6641, 0.4224, 0.6992, 0.7124, 0.3418, 0.4028,
        0.6709, 0.3418, 1.0581, 0.7124, 0.6855, 0.6992, 0.6992, 0.4971, 0.5933, 0.4556, 0.7124, 0.6489, 0.9795, 0.6689, 0.6509,
        0.5967, 0.7109, 0.5435, 0.7109, 0.8672,
    ]

    // Tahoma's own widths, U+0020 to U+007E, in its Regular and Bold, and its
    // own line: 1.2070 ems by its hhea (ascent 2049, descent 423 of 2048, no
    // gap). Numbers only, read from the subsets Word's and PowerPoint's
    // Windows prints embed by test/tools/print-font-metrics.py (55 and 57 of
    // the 95 glyphs from the subsets' hmtx; the rest estimated from Liberation
    // Sans by the median ratio of their kind). Tahoma has no metric-compatible
    // free clone; the sans stand-in's lines held a word too many.
    // Arial Narrow, which has no free clone (Liberation Sans Narrow is GPL, not bundled): the sans stand-in
    // driven by Arial Narrow's own advances in ems, from the hmtx of the subsets Word's Windows prints embed
    // (86 of 95 regular, 81 of 95 bold read; the rest estimated from Liberation Sans). Line 1916+434 of 2048.
    static let arialNarrowAdvances: [Double] = [
        0.2280, 0.2280, 0.2910, 0.4561, 0.4561, 0.7290, 0.5469, 0.1566, 0.2729, 0.2729, 0.3188, 0.4790, 0.2280, 0.2729, 0.2280,
        0.2280, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.2280, 0.2280, 0.4790, 0.4790,
        0.4789, 0.4561, 0.8320, 0.5469, 0.5469, 0.5918, 0.5918, 0.5469, 0.5010, 0.6382, 0.5918, 0.2280, 0.4102, 0.5469, 0.4561,
        0.6831, 0.5918, 0.6382, 0.5469, 0.6382, 0.5918, 0.5469, 0.5010, 0.5918, 0.5469, 0.7739, 0.5469, 0.5469, 0.5010, 0.2278,
        0.2278, 0.2278, 0.3848, 0.4561, 0.2729, 0.4561, 0.4561, 0.4102, 0.4561, 0.4561, 0.2280, 0.4561, 0.4561, 0.1821, 0.1821,
        0.4102, 0.1821, 0.6831, 0.4561, 0.4561, 0.4561, 0.4561, 0.2729, 0.4102, 0.2280, 0.4561, 0.4102, 0.5918, 0.4102, 0.4102,
        0.4102, 0.2739, 0.2129, 0.2739, 0.4790,
    ]
    // Arial Narrow's accented letters sit at their base letter's width (a 22% narrower than the sans stand-in's), the marks that
    // widen a letter (í, ť) and the curly quote and ellipsis as the Word prints measure them (median over every adjacent pair in
    // the word-win prints: ellipsis 0.815 em regular, 0.8267 bold; dx2 pl 16d0d0a2's 25-stop runs were 11.0 pt a stop, Word's 9.0).
    static let arialNarrowOtherAdvances: [UInt32: Double] = [0xC0: 0.5469, 0xC1: 0.5469, 0xC2: 0.5469, 0xC3: 0.5469, 0xC4: 0.5469, 0xC5: 0.5469, 0xC7: 0.5918, 0xC8: 0.5469, 0xC9: 0.5469, 0xCA: 0.5469, 0xCB: 0.5469, 0xCC: 0.228, 0xCD: 0.228, 0xCE: 0.228, 0xCF: 0.228, 0xD1: 0.5918, 0xD2: 0.6382, 0xD3: 0.6382, 0xD4: 0.6382, 0xD5: 0.6382, 0xD6: 0.6382, 0xD9: 0.5918, 0xDA: 0.588, 0xDB: 0.5918, 0xDC: 0.5918, 0xDD: 0.5469, 0xE0: 0.4561, 0xE1: 0.459, 0xE2: 0.4561, 0xE3: 0.4561, 0xE4: 0.4561, 0xE5: 0.4561, 0xE7: 0.4102, 0xE8: 0.456, 0xE9: 0.459, 0xEA: 0.4561, 0xEB: 0.4561, 0xEC: 0.1821, 0xED: 0.228, 0xEE: 0.1821, 0xEF: 0.1821, 0xF1: 0.4561, 0xF2: 0.456, 0xF3: 0.456, 0xF4: 0.4561, 0xF5: 0.4561, 0xF6: 0.4561, 0xF9: 0.4561, 0xFA: 0.459, 0xFB: 0.4561, 0xFC: 0.4561, 0xFD: 0.41, 0xFF: 0.4102, 0x100: 0.5469, 0x101: 0.4561, 0x102: 0.5469, 0x103: 0.4561, 0x104: 0.5469, 0x105: 0.457, 0x106: 0.5918, 0x107: 0.41, 0x108: 0.5918, 0x109: 0.4102, 0x10A: 0.5918, 0x10B: 0.4102, 0x10C: 0.592, 0x10D: 0.41, 0x10E: 0.5918, 0x10F: 0.4561, 0x111: 0.453, 0x112: 0.5469, 0x113: 0.4561, 0x114: 0.5469, 0x115: 0.4561, 0x116: 0.5469, 0x117: 0.4561, 0x118: 0.5469, 0x119: 0.456, 0x11A: 0.5469, 0x11B: 0.459, 0x11C: 0.6382, 0x11D: 0.4561, 0x11E: 0.6382, 0x11F: 0.4561, 0x120: 0.6382, 0x121: 0.4561, 0x122: 0.6382, 0x123: 0.4561, 0x124: 0.5918, 0x125: 0.4561, 0x128: 0.228, 0x129: 0.1821, 0x12A: 0.228, 0x12B: 0.1821, 0x12C: 0.228, 0x12D: 0.1821, 0x12E: 0.228, 0x12F: 0.1821, 0x130: 0.228, 0x134: 0.4102, 0x135: 0.1821, 0x136: 0.5469, 0x137: 0.4102, 0x139: 0.4561, 0x13A: 0.1821, 0x13B: 0.4561, 0x13C: 0.1821, 0x13D: 0.4561, 0x13E: 0.1821, 0x142: 0.182, 0x143: 0.5918, 0x144: 0.4561, 0x145: 0.5918, 0x146: 0.4561, 0x147: 0.5918, 0x148: 0.456, 0x14C: 0.6382, 0x14D: 0.4561, 0x14E: 0.6382, 0x14F: 0.4561, 0x150: 0.6382, 0x151: 0.4561, 0x154: 0.5918, 0x155: 0.2729, 0x156: 0.5918, 0x157: 0.2729, 0x158: 0.5918, 0x159: 0.273, 0x15A: 0.5469, 0x15B: 0.41, 0x15C: 0.5469, 0x15D: 0.4102, 0x15E: 0.5469, 0x15F: 0.4102, 0x160: 0.5469, 0x161: 0.41, 0x162: 0.501, 0x163: 0.228, 0x164: 0.501, 0x165: 0.3045, 0x168: 0.5918, 0x169: 0.4561, 0x16A: 0.5918, 0x16B: 0.4561, 0x16C: 0.5918, 0x16D: 0.4561, 0x16E: 0.5918, 0x16F: 0.459, 0x170: 0.5918, 0x171: 0.4561, 0x172: 0.5918, 0x173: 0.4561, 0x174: 0.7739, 0x175: 0.5918, 0x176: 0.5469, 0x177: 0.4102, 0x178: 0.5469, 0x179: 0.501, 0x17A: 0.4102, 0x17B: 0.501, 0x17C: 0.41, 0x17D: 0.501, 0x17E: 0.41, 0x2019: 0.182, 0x201C: 0.2771, 0x2026: 0.815]
    static let arialNarrowBoldOtherAdvances: [UInt32: Double] = [0xC0: 0.5918, 0xC1: 0.5918, 0xC2: 0.5918, 0xC3: 0.5918, 0xC4: 0.5918, 0xC5: 0.5918, 0xC7: 0.5918, 0xC8: 0.5469, 0xC9: 0.5469, 0xCA: 0.5469, 0xCB: 0.5469, 0xCC: 0.228, 0xCD: 0.228, 0xCE: 0.228, 0xCF: 0.228, 0xD1: 0.5918, 0xD2: 0.6382, 0xD3: 0.6382, 0xD4: 0.6382, 0xD5: 0.6382, 0xD6: 0.6382, 0xD9: 0.5918, 0xDA: 0.5918, 0xDB: 0.5918, 0xDC: 0.5918, 0xDD: 0.5469, 0xE0: 0.4561, 0xE1: 0.456, 0xE2: 0.4561, 0xE3: 0.4561, 0xE4: 0.4561, 0xE5: 0.4561, 0xE7: 0.4561, 0xE8: 0.46, 0xE9: 0.4561, 0xEA: 0.4561, 0xEB: 0.4561, 0xEC: 0.228, 0xED: 0.228, 0xEE: 0.228, 0xEF: 0.228, 0xF1: 0.501, 0xF2: 0.502, 0xF3: 0.501, 0xF4: 0.501, 0xF5: 0.501, 0xF6: 0.501, 0xF9: 0.501, 0xFA: 0.501, 0xFB: 0.501, 0xFC: 0.501, 0xFD: 0.458, 0xFF: 0.4561, 0x100: 0.5918, 0x101: 0.4561, 0x102: 0.5918, 0x103: 0.4561, 0x104: 0.5918, 0x105: 0.4561, 0x106: 0.5918, 0x107: 0.4561, 0x108: 0.5918, 0x109: 0.4561, 0x10A: 0.5918, 0x10B: 0.4561, 0x10C: 0.5918, 0x10D: 0.459, 0x10E: 0.5918, 0x10F: 0.501, 0x111: 0.504, 0x112: 0.5469, 0x113: 0.4561, 0x114: 0.5469, 0x115: 0.4561, 0x116: 0.5469, 0x117: 0.4561, 0x118: 0.5469, 0x119: 0.4561, 0x11A: 0.5469, 0x11B: 0.459, 0x11C: 0.6382, 0x11D: 0.501, 0x11E: 0.6382, 0x11F: 0.501, 0x120: 0.6382, 0x121: 0.501, 0x122: 0.6382, 0x123: 0.501, 0x124: 0.5918, 0x125: 0.501, 0x128: 0.228, 0x129: 0.228, 0x12A: 0.228, 0x12B: 0.228, 0x12C: 0.228, 0x12D: 0.228, 0x12E: 0.228, 0x12F: 0.228, 0x130: 0.228, 0x134: 0.4561, 0x135: 0.228, 0x136: 0.5918, 0x137: 0.4561, 0x139: 0.501, 0x13A: 0.228, 0x13B: 0.501, 0x13C: 0.228, 0x13D: 0.501, 0x13E: 0.228, 0x143: 0.5918, 0x144: 0.501, 0x145: 0.5918, 0x146: 0.501, 0x147: 0.5918, 0x148: 0.501, 0x14C: 0.6382, 0x14D: 0.501, 0x14E: 0.6382, 0x14F: 0.501, 0x150: 0.6382, 0x151: 0.501, 0x154: 0.5918, 0x155: 0.3188, 0x156: 0.5918, 0x157: 0.3188, 0x158: 0.5918, 0x159: 0.319, 0x15A: 0.5469, 0x15B: 0.4561, 0x15C: 0.5469, 0x15D: 0.4561, 0x15E: 0.5469, 0x15F: 0.4561, 0x160: 0.5469, 0x161: 0.459, 0x162: 0.501, 0x163: 0.2729, 0x164: 0.501, 0x165: 0.2729, 0x168: 0.5918, 0x169: 0.501, 0x16A: 0.5918, 0x16B: 0.501, 0x16C: 0.5918, 0x16D: 0.501, 0x16E: 0.5918, 0x16F: 0.501, 0x170: 0.5918, 0x171: 0.501, 0x172: 0.5918, 0x173: 0.501, 0x174: 0.7739, 0x175: 0.6382, 0x176: 0.5469, 0x177: 0.4561, 0x178: 0.5469, 0x179: 0.501, 0x17A: 0.4102, 0x17B: 0.501, 0x17C: 0.4102, 0x17D: 0.501, 0x17E: 0.41, 0x2019: 0.228, 0x2026: 0.8267]
    static let arialNarrowBoldAdvances: [Double] = [
        0.2280, 0.2729, 0.3892, 0.4561, 0.4561, 0.7290, 0.5922, 0.1950, 0.2729, 0.2729, 0.3191, 0.4789, 0.2280, 0.2729, 0.2280,
        0.2280, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.4561, 0.2729, 0.2731, 0.4789, 0.4790,
        0.4789, 0.5010, 0.7997, 0.5918, 0.5918, 0.5918, 0.5918, 0.5469, 0.5010, 0.6382, 0.5918, 0.2280, 0.4561, 0.5918, 0.5010,
        0.6831, 0.5918, 0.6382, 0.5469, 0.6382, 0.5918, 0.5469, 0.5010, 0.5918, 0.5469, 0.7739, 0.5469, 0.5469, 0.5010, 0.2729,
        0.2278, 0.2729, 0.4789, 0.4561, 0.2729, 0.4561, 0.5010, 0.4561, 0.5010, 0.4561, 0.2729, 0.5010, 0.5010, 0.2280, 0.2280,
        0.4561, 0.2280, 0.7290, 0.5010, 0.5010, 0.5010, 0.5010, 0.3188, 0.4561, 0.2729, 0.5010, 0.4561, 0.6382, 0.4561, 0.4561,
        0.4102, 0.3191, 0.2300, 0.3191, 0.4790,
    ]
    // Source Sans Pro (Word's Windows prints embed it; no stand-in is bundled): advances in ems from the hmtx of the subsets in 12 dx2 prints, 25 and 42 glyphs
    // estimated (test/tools/print-font-metrics.py with PRINTS_GLOB). Line 0.984 + 0.273. Space 0.200, where the sans stand-in's was 0.226 (dx2 c5311ac7's 24 pt title).
    static let sourceSansProAdvances: [Double] = [
        0.2000, 0.2890, 0.4250, 0.5110, 0.5110, 0.8170, 0.6128, 0.2490, 0.3030, 0.3030, 0.3576, 0.5366, 0.2490, 0.3060, 0.2490,
        0.3500, 0.4970, 0.4970, 0.4970, 0.4970, 0.4970, 0.4970, 0.4970, 0.4970, 0.4970, 0.4970, 0.2490, 0.2553, 0.5366, 0.5366,
        0.5366, 0.5110, 0.9327, 0.5440, 0.5880, 0.5710, 0.6150, 0.5270, 0.4940, 0.6170, 0.6520, 0.2630, 0.4800, 0.5790, 0.4860,
        0.7270, 0.6470, 0.6640, 0.5660, 0.6640, 0.6165, 0.5340, 0.5360, 0.6450, 0.5150, 0.7860, 0.5694, 0.4760, 0.5390, 0.3030,
        0.2553, 0.3030, 0.4311, 0.5000, 0.3060, 0.5040, 0.5530, 0.4560, 0.5550, 0.4960, 0.2920, 0.5040, 0.5440, 0.2460, 0.2470,
        0.4950, 0.2550, 0.8290, 0.5470, 0.5420, 0.5550, 0.5488, 0.3470, 0.4190, 0.3380, 0.5440, 0.4670, 0.7180, 0.4934, 0.4670,
        0.4250, 0.3069, 0.2410, 0.3069, 0.5366,
    ]
    static let sourceSansProBoldAdvances: [Double] = [
        0.2000, 0.3400, 0.5360, 0.5745, 0.5745, 0.9185, 0.7460, 0.3000, 0.3440, 0.3440, 0.4020, 0.6033, 0.3000, 0.3200, 0.3000,
        0.3390, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.3000, 0.3440, 0.6033, 0.6033,
        0.6033, 0.6310, 1.0073, 0.5730, 0.6180, 0.6180, 0.6350, 0.5310, 0.5000, 0.6657, 0.6180, 0.2910, 0.5090, 0.6140, 0.5000,
        0.7620, 0.6180, 0.6600, 0.5800, 0.6657, 0.6000, 0.5560, 0.5560, 0.6650, 0.5708, 0.8130, 0.5708, 0.5708, 0.5228, 0.3440,
        0.2870, 0.3440, 0.6033, 0.5000, 0.3440, 0.5270, 0.5730, 0.4670, 0.5730, 0.5180, 0.3410, 0.5340, 0.5710, 0.2760, 0.2780,
        0.5480, 0.2860, 0.8570, 0.5720, 0.5550, 0.5530, 0.5722, 0.3980, 0.4430, 0.3830, 0.5680, 0.4990, 0.7760, 0.4900, 0.5210,
        0.4600, 0.4020, 0.2890, 0.4020, 0.6033,
    ]
    // (Source Sans Pro Bold Italic: no table of its own was kept, but Word's prints embed its subsets with the real advances of every
    // glyph they draw: the 43 ASCII glyphs the dx2 prints use are read from them (4b3e599b p2's "(insert school year), (insert adjusted,
    // four-year graduation rate)" is 303.3 pt in Word, 312.1 in the bold table); the others stay the bold table's.)
    static let sourceSansProBoldItalicAdvances: [Double] = [
        0.1980, 0.3310, 0.5100, 0.5745, 0.5745, 0.9185, 0.7460, 0.2910, 0.3290, 0.3310, 0.4020, 0.6033, 0.2910, 0.3200, 0.2910,
        0.3390, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.5171, 0.2910, 0.3440, 0.6033, 0.6033,
        0.6033, 0.6310, 1.0073, 0.5480, 0.6180, 0.6180, 0.6350, 0.5270, 0.5040, 0.6657, 0.6180, 0.2940, 0.5090, 0.6140, 0.5000,
        0.7400, 0.6180, 0.6600, 0.5830, 0.6657, 0.5960, 0.5290, 0.5560, 0.6650, 0.5708, 0.8130, 0.5708, 0.5708, 0.5228, 0.3440,
        0.2870, 0.3440, 0.6033, 0.5000, 0.3440, 0.5520, 0.5530, 0.4430, 0.5460, 0.4960, 0.3270, 0.5460, 0.5460, 0.2650, 0.2670,
        0.5480, 0.2750, 0.8270, 0.5520, 0.5330, 0.5530, 0.5722, 0.3840, 0.4240, 0.3670, 0.5450, 0.4990, 0.7480, 0.4900, 0.4990,
        0.4600, 0.4020, 0.2890, 0.4020, 0.6033,
    ]
    /// Mangal's ASCII advances (em), 0 where no print's subset holds the glyph yet: Word draws the Latin of a Nikosh run (Windows lacks Nikosh)
    /// in Mangal, whose dot is 0.2876 against Carlito's 0.2524 (bede0fbc: every dotted leader line ran short). hmtx of the subsets in dx2's prints.
    static let nikoshAdvances: [Double] = [0.5, 0.2876, 0.3672, 0, 0, 0, 0, 0, 0.3447, 0.3447, 0, 0.6045, 0.2876, 0.3447, 0.2876, 0.2876, 0.5757, 0.5757, 0.5757, 0.5757, 0.5757, 0.5757, 0.5757, 0.5757, 0.5757, 0.5757, 0.2876, 0.2876, 0, 0.6045, 0, 0.5757, 0, 0, 0.6914, 0, 0, 0, 0, 0, 0, 0.2881, 0, 0, 0, 0.8638, 0.748, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.2876, 0, 0.2876, 0, 0.5713, 0, 0, 0, 0, 0.5762, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.3447, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    /// Mangal's own ASCII advances (em), U+0020-007E: the median over every Mangal-embedding Word print (n >= 5, sd < 0.012; the rest as nikoshAdvances,
    /// 0 where no print holds the glyph). Word draws the digits, marks and space of a run whose Latin face is Mangal in it: digit 0.576 against the
    /// stand-in's 0.556, hyphen 0.342, full stop 0.285 (the space stays with mangalLatinSpace).
    static let mangalAdvances: [Double] = [0.0000, 0.2876, 0.3720, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.3450, 0.3420, 0.0000, 0.6040, 0.2880, 0.3420, 0.2850, 0.2830, 0.5761, 0.5760, 0.5760, 0.5760, 0.5760, 0.5760, 0.5760, 0.5760, 0.5760, 0.5761, 0.2826, 0.2900, 0.0000, 0.6087, 0.0000, 0.5761, 0.0000, 0.0000, 0.6914, 0.7480, 0.7480, 0.0000, 0.0000, 0.0000, 0.0000, 0.2881, 0.0000, 0.0000, 0.0000, 0.8640, 0.7480, 0.0000, 0.6910, 0.0000, 0.0000, 0.6910, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.2876, 0.0000, 0.2876, 0.0000, 0.5713, 0.0000, 0.5760, 0.0000, 0.5180, 0.5683, 0.5790, 0.0000, 0.0000, 0.5760, 0.2360, 0.0000, 0.5217, 0.2390, 0.8600, 0.5760, 0.5755, 0.5790, 0.0000, 0.3490, 0.5180, 0.2880, 0.0000, 0.5227, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000, 0.0000]
    static let tahomaAdvances: [Double] = [
        0.3125, 0.3320, 0.4014, 0.6289, 0.6289, 1.0054, 0.7542, 0.2159, 0.3828, 0.3828, 0.4400, 0.6603, 0.3027, 0.3633, 0.3027,
        0.3823, 0.5459, 0.5459, 0.5459, 0.5459, 0.5459, 0.5459, 0.5459, 0.5459, 0.5459, 0.5459, 0.3535, 0.3142, 0.6603, 0.6603,
        0.6603, 0.6289, 0.9092, 0.5996, 0.5894, 0.6006, 0.6782, 0.5610, 0.5215, 0.6992, 0.6753, 0.2498, 0.4495, 0.5996, 0.5000,
        0.7705, 0.6675, 0.7075, 0.5513, 0.6992, 0.6206, 0.5571, 0.5840, 0.6558, 0.5996, 0.8485, 0.5996, 0.5996, 0.5491, 0.3142,
        0.3142, 0.3142, 0.5306, 0.6289, 0.3766, 0.5249, 0.5527, 0.4614, 0.5527, 0.5264, 0.3184, 0.5527, 0.5576, 0.2285, 0.2213,
        0.4980, 0.2285, 0.8398, 0.5576, 0.5430, 0.5527, 0.5539, 0.3604, 0.4463, 0.3345, 0.5576, 0.4980, 0.7193, 0.4951, 0.4980,
        0.4980, 0.3777, 0.2937, 0.3777, 0.6603,
    ]
    // Tahoma's Greek (U+0370-U+03FF) advances in ems, from the hmtx of the
    // subsets Word's Windows prints embed (ell-z10407270-89615d and its
    // pair). Without them Greek was set at the sans stand-in's Arial
    // widths, 5-10% narrower, and Greek lines took a word too many.
    static let tahomaGreekAdvances: [UInt32: Double] = [
        0x384: 0.5459, 0x386: 0.5996, 0x388: 0.6782, 0x38A: 0.4854, 0x38C: 0.8003, 0x391: 0.5996,
        0x392: 0.5894, 0x393: 0.5073, 0x394: 0.6191, 0x395: 0.561, 0x396: 0.5591, 0x397: 0.6753,
        0x398: 0.7075, 0x399: 0.373, 0x39A: 0.5879, 0x39B: 0.5967, 0x39C: 0.7705, 0x39D: 0.6675,
        0x39E: 0.5664, 0x39F: 0.7075, 0x3A0: 0.6753, 0x3A1: 0.5513, 0x3A3: 0.5562, 0x3A4: 0.584,
        0x3A5: 0.5762, 0x3A6: 0.7485, 0x3A7: 0.5806, 0x3A8: 0.7935, 0x3A9: 0.7021, 0x3AC: 0.5547,
        0x3AD: 0.4551, 0x3AE: 0.5576, 0x3AF: 0.2285, 0x3B1: 0.5547, 0x3B2: 0.5552, 0x3B3: 0.498,
        0x3B4: 0.543, 0x3B5: 0.4551, 0x3B6: 0.3911, 0x3B7: 0.5576, 0x3B8: 0.5547, 0x3B9: 0.2285,
        0x3BA: 0.498, 0x3BB: 0.498, 0x3BC: 0.5679, 0x3BD: 0.498, 0x3BE: 0.4331, 0x3BF: 0.543,
        0x3C0: 0.5635, 0x3C1: 0.5518, 0x3C2: 0.4302, 0x3C3: 0.5815, 0x3C4: 0.4668, 0x3C5: 0.5566,
        0x3C6: 0.7061, 0x3C7: 0.4971, 0x3C8: 0.7144, 0x3C9: 0.7246, 0x3CA: 0.2285, 0x3CB: 0.5566,
        0x3CC: 0.543, 0x3CD: 0.5566, 0x3CE: 0.7246,
    ]
    static let tahomaGreekBoldAdvances: [UInt32: Double] = [
        0x384: 0.5459, 0x388: 0.7866, 0x391: 0.6846, 0x392: 0.686, 0x393: 0.5654, 0x394: 0.7041,
        0x395: 0.6152, 0x397: 0.7642, 0x398: 0.77, 0x399: 0.4834, 0x39A: 0.6963, 0x39B: 0.6748,
        0x39C: 0.8931, 0x39D: 0.7705, 0x39F: 0.77, 0x3A0: 0.7642, 0x3A1: 0.6572, 0x3A3: 0.6113,
        0x3A4: 0.6123, 0x3A5: 0.6704, 0x3A7: 0.6846, 0x3A8: 0.9019, 0x3A9: 0.7695, 0x3AC: 0.6294,
        0x3AD: 0.5234, 0x3AE: 0.6392, 0x3AF: 0.3018, 0x3B1: 0.6294, 0x3B2: 0.6411, 0x3B3: 0.5786,
        0x3B4: 0.6172, 0x3B5: 0.5234, 0x3B7: 0.6392, 0x3B8: 0.6309, 0x3B9: 0.3018, 0x3BA: 0.5996,
        0x3BB: 0.5776, 0x3BC: 0.6509, 0x3BD: 0.5786, 0x3BE: 0.5127, 0x3BF: 0.6172, 0x3C0: 0.6465,
        0x3C1: 0.6294, 0x3C2: 0.5039, 0x3C3: 0.6562, 0x3C4: 0.5205, 0x3C5: 0.6348, 0x3C6: 0.8364,
        0x3C7: 0.563, 0x3C8: 0.8545, 0x3C9: 0.8096, 0x3CC: 0.6172, 0x3CD: 0.6348, 0x3CE: 0.8096,
    ]
    // Cambria's Cyrillic advances in ems, from the hmtx of the subsets Word's
    // Windows prints embed. Caladea has no Cyrillic, so Ukrainian/Russian text
    // in Cambria was set at DejaVu Sans widths, far too wide (ukr-z4769265).
    static let cambriaCyrillicAdvances: [UInt32: Double] = [
        0x404: 0.5698, 0x406: 0.3242, 0x407: 0.3242, 0x410: 0.623, 0x411: 0.5991, 0x412: 0.6113, 0x413: 0.5342,
        0x414: 0.6548, 0x417: 0.543, 0x418: 0.6919, 0x419: 0.6919, 0x41A: 0.6499, 0x41B: 0.6777, 0x41C: 0.8154,
        0x41D: 0.6865, 0x41E: 0.6533, 0x41F: 0.6743, 0x420: 0.5679, 0x421: 0.5625, 0x422: 0.5928, 0x423: 0.6001,
        0x424: 0.7788, 0x425: 0.5713, 0x426: 0.6719, 0x427: 0.626, 0x429: 0.9268, 0x42E: 0.9209, 0x42F: 0.6309,
        0x430: 0.4883, 0x431: 0.541, 0x432: 0.5229, 0x433: 0.4468, 0x434: 0.5581, 0x435: 0.4878, 0x436: 0.7139,
        0x437: 0.458, 0x438: 0.5898, 0x439: 0.5898, 0x43A: 0.54, 0x43B: 0.5591, 0x43C: 0.6729, 0x43D: 0.5889,
        0x43E: 0.5308, 0x43F: 0.5669, 0x440: 0.5562, 0x441: 0.4409, 0x442: 0.5112, 0x443: 0.5039, 0x444: 0.6851,
        0x445: 0.4834, 0x446: 0.5698, 0x447: 0.5308, 0x448: 0.8008, 0x449: 0.8008, 0x44B: 0.748, 0x44C: 0.5142,
        0x44E: 0.7671, 0x44F: 0.5308, 0x454: 0.4702, 0x456: 0.2778, 0x457: 0.2778, 0x491: 0.417,
    ]
    // Montserrat's own widths (Version 7.200, 1000 upm), U+0020-U+007E and the rest in a dictionary, from Word's cloud copy
    // (lab/montserrat, 2026-11-14). Metrics only: drawn as the sans clone. Line: hhea 968/-251, typo the same (1.219 em).
    static let montserratAdvances: [Double] = [
        0.2620, 0.2600, 0.3730, 0.6960, 0.6150, 0.8290, 0.6690, 0.2020, 0.3290, 0.3290, 0.3860, 0.5750, 0.2120, 0.3820, 0.2120,
        0.3350, 0.6620, 0.3610, 0.5680, 0.5640, 0.6610, 0.5660, 0.6090, 0.5890, 0.6380, 0.6090, 0.2120, 0.2120, 0.5750, 0.5750,
        0.5750, 0.5670, 1.0330, 0.7170, 0.7540, 0.7190, 0.8260, 0.6690, 0.6330, 0.7730, 0.8130, 0.3020, 0.5010, 0.7110, 0.5890,
        0.9550, 0.8130, 0.8390, 0.7180, 0.8390, 0.7230, 0.6150, 0.5740, 0.7920, 0.6980, 1.1110, 0.6560, 0.6350, 0.6510, 0.3180,
        0.3350, 0.3180, 0.5760, 0.5000, 0.6000, 0.5900, 0.6780, 0.5630, 0.6780, 0.6040, 0.3390, 0.6860, 0.6770, 0.2690, 0.2740,
        0.6010, 0.2690, 1.0610, 0.6770, 0.6270, 0.6780, 0.6780, 0.4010, 0.4890, 0.4060, 0.6730, 0.5420, 0.8790, 0.5340, 0.5420,
        0.5110, 0.3340, 0.2950, 0.3340, 0.5750,
    ]
    static let montserratOtherAdvances: [UInt32: Double] = [
        0xA0: 0.2620, 0xA1: 0.2600, 0xA2: 0.5630, 0xA3: 0.6370, 0xA4: 0.7000, 0xA5: 0.6950,
        0xA6: 0.2950, 0xA7: 0.4900, 0xA8: 0.6000, 0xA9: 0.8090, 0xAA: 0.4010, 0xAB: 0.4770,
        0xAC: 0.5750, 0xAD: 0.3820, 0xAE: 0.8090, 0xAF: 0.6000, 0xB0: 0.4190, 0xB1: 0.5750,
        0xB2: 0.4300, 0xB3: 0.4300, 0xB4: 0.6000, 0xB5: 0.6780, 0xB6: 0.6320, 0xB7: 0.2520,
        0xB8: 0.6000, 0xB9: 0.4300, 0xBA: 0.4140, 0xBB: 0.4770, 0xBC: 1.0290, 0xBD: 1.0290,
        0xBE: 1.0290, 0xBF: 0.5670, 0xC0: 0.7170, 0xC1: 0.7170, 0xC2: 0.7170, 0xC3: 0.7170,
        0xC4: 0.7170, 0xC5: 0.7170, 0xC6: 1.0330, 0xC7: 0.7190, 0xC8: 0.6690, 0xC9: 0.6690,
        0xCA: 0.6690, 0xCB: 0.6690, 0xCC: 0.3020, 0xCD: 0.3020, 0xCE: 0.3020, 0xCF: 0.3020,
        0xD0: 0.8310, 0xD1: 0.8130, 0xD2: 0.8390, 0xD3: 0.8390, 0xD4: 0.8390, 0xD5: 0.8390,
        0xD6: 0.8390, 0xD7: 0.5750, 0xD8: 0.8390, 0xD9: 0.7920, 0xDA: 0.7920, 0xDB: 0.7920,
        0xDC: 0.7920, 0xDD: 0.6350, 0xDE: 0.7180, 0xDF: 0.6680, 0xE0: 0.5900, 0xE1: 0.5900,
        0xE2: 0.5900, 0xE3: 0.5900, 0xE4: 0.5900, 0xE5: 0.5900, 0xE6: 0.9860, 0xE7: 0.5630,
        0xE8: 0.6040, 0xE9: 0.6040, 0xEA: 0.6040, 0xEB: 0.6040, 0xEC: 0.2690, 0xED: 0.2690,
        0xEE: 0.2690, 0xEF: 0.2690, 0xF0: 0.6330, 0xF1: 0.6770, 0xF2: 0.6270, 0xF3: 0.6270,
        0xF4: 0.6270, 0xF5: 0.6270, 0xF6: 0.6270, 0xF7: 0.5750, 0xF8: 0.6270, 0xF9: 0.6730,
        0xFA: 0.6730, 0xFB: 0.6730, 0xFC: 0.6730, 0xFD: 0.5420, 0xFE: 0.6780, 0xFF: 0.5420,
        0x100: 0.7170, 0x101: 0.5900, 0x102: 0.7170, 0x103: 0.5900, 0x104: 0.7170, 0x105: 0.5900,
        0x106: 0.7190, 0x107: 0.5630, 0x108: 0.7190, 0x109: 0.5630, 0x10A: 0.7190, 0x10B: 0.5630,
        0x10C: 0.7190, 0x10D: 0.5630, 0x10E: 0.8260, 0x10F: 0.6780, 0x110: 0.8310, 0x111: 0.6780,
        0x112: 0.6690, 0x113: 0.6040, 0x114: 0.6690, 0x115: 0.6040, 0x116: 0.6690, 0x117: 0.6040,
        0x118: 0.6690, 0x119: 0.6040, 0x11A: 0.6690, 0x11B: 0.6040, 0x11C: 0.7730, 0x11D: 0.6860,
        0x11E: 0.7730, 0x11F: 0.6860, 0x120: 0.7730, 0x121: 0.6860, 0x122: 0.7730, 0x123: 0.6860,
        0x124: 0.8130, 0x125: 0.6770, 0x126: 0.8230, 0x127: 0.6770, 0x128: 0.3020, 0x129: 0.2690,
        0x12A: 0.3020, 0x12B: 0.2690, 0x12C: 0.3020, 0x12D: 0.2690, 0x12E: 0.3020, 0x12F: 0.2690,
        0x130: 0.3020, 0x131: 0.2690, 0x132: 0.7180, 0x133: 0.5430, 0x134: 0.5010, 0x135: 0.2740,
        0x136: 0.7110, 0x137: 0.6010, 0x138: 0.5900, 0x139: 0.5890, 0x13A: 0.2690, 0x13B: 0.5890,
        0x13C: 0.2690, 0x13D: 0.5890, 0x13E: 0.2690, 0x13F: 0.5890, 0x140: 0.3140, 0x141: 0.5940,
        0x142: 0.2790, 0x143: 0.8130, 0x144: 0.6770, 0x145: 0.8130, 0x146: 0.6770, 0x147: 0.8130,
        0x148: 0.6770, 0x149: 0.7500, 0x14A: 0.8130, 0x14B: 0.6770, 0x14C: 0.8390, 0x14D: 0.6270,
        0x14E: 0.8390, 0x14F: 0.6270, 0x150: 0.8390, 0x151: 0.6270, 0x152: 1.1210, 0x153: 1.0680,
        0x154: 0.7230, 0x155: 0.4010, 0x156: 0.7230, 0x157: 0.4010, 0x158: 0.7230, 0x159: 0.4010,
        0x15A: 0.6150, 0x15B: 0.4890, 0x15C: 0.6150, 0x15D: 0.4890, 0x15E: 0.6150, 0x15F: 0.4890,
        0x160: 0.6150, 0x161: 0.4890, 0x162: 0.5740, 0x163: 0.4060, 0x164: 0.5740, 0x165: 0.4060,
        0x166: 0.5740, 0x167: 0.4160, 0x168: 0.7920, 0x169: 0.6730, 0x16A: 0.7920, 0x16B: 0.6730,
        0x16C: 0.7920, 0x16D: 0.6730, 0x16E: 0.7920, 0x16F: 0.6730, 0x170: 0.7920, 0x171: 0.6730,
        0x172: 0.7920, 0x173: 0.6730, 0x174: 1.1110, 0x175: 0.8790, 0x176: 0.6350, 0x177: 0.5420,
        0x178: 0.6350, 0x179: 0.6510, 0x17A: 0.5110, 0x17B: 0.6510, 0x17C: 0.5110, 0x17D: 0.6510,
        0x17E: 0.5110, 0x17F: 0.2950, 0x18F: 0.8170, 0x192: 0.4380, 0x1A0: 0.8390, 0x1A1: 0.6270,
        0x1AF: 0.7970, 0x1B0: 0.6790, 0x1B7: 0.6150, 0x1C4: 1.4560, 0x1C5: 1.3370, 0x1C6: 1.2020,
        0x1C7: 1.0900, 0x1C8: 0.8630, 0x1C9: 0.5430, 0x1CA: 1.3140, 0x1CB: 1.0870, 0x1CC: 0.9510,
        0x1CD: 0.7170, 0x1CE: 0.5900, 0x1D3: 0.7920, 0x1D4: 0.6730, 0x1E4: 0.8060, 0x1E5: 0.6910,
        0x1E6: 0.7730, 0x1E7: 0.6860, 0x1E8: 0.7110, 0x1E9: 0.6010, 0x1EA: 0.8390, 0x1EB: 0.6270,
        0x1EE: 0.6150, 0x1EF: 0.5140, 0x1FA: 0.7170, 0x1FB: 0.5900, 0x1FC: 1.0330, 0x1FD: 0.9860,
        0x1FE: 0.8390, 0x1FF: 0.6270, 0x200: 0.7170, 0x201: 0.5900, 0x202: 0.7170, 0x203: 0.5900,
        0x204: 0.6690, 0x205: 0.6040, 0x206: 0.6690, 0x207: 0.6040, 0x208: 0.3020, 0x209: 0.2690,
        0x20A: 0.3020, 0x20B: 0.2690, 0x20C: 0.8390, 0x20D: 0.6270, 0x20E: 0.8390, 0x20F: 0.6270,
        0x210: 0.7230, 0x211: 0.4010, 0x212: 0.7230, 0x213: 0.4010, 0x214: 0.7920, 0x215: 0.6730,
        0x216: 0.7920, 0x217: 0.6730, 0x218: 0.6150, 0x219: 0.4890, 0x21A: 0.5740, 0x21B: 0.4060,
        0x21E: 0.8130, 0x21F: 0.6770, 0x22A: 0.8390, 0x22B: 0.6270, 0x22C: 0.8390, 0x22D: 0.6270,
        0x230: 0.8390, 0x231: 0.6270, 0x232: 0.6350, 0x233: 0.5420, 0x237: 0.2740, 0x400: 0.6590,
        0x401: 0.6590, 0x402: 0.8250, 0x403: 0.5720, 0x404: 0.7070, 0x405: 0.6270, 0x406: 0.3090,
        0x407: 0.3020, 0x408: 0.5270, 0x409: 1.1860, 0x40A: 1.1840, 0x40B: 0.8350, 0x40C: 0.7020,
        0x40D: 0.8240, 0x40E: 0.6800, 0x40F: 0.8060, 0x410: 0.7440, 0x411: 0.7270, 0x412: 0.7490,
        0x413: 0.5720, 0x414: 0.7940, 0x415: 0.6590, 0x416: 1.0110, 0x417: 0.6360, 0x418: 0.8240,
        0x419: 0.8240, 0x41A: 0.7020, 0x41B: 0.7850, 0x41C: 0.9630, 0x41D: 0.8210, 0x41E: 0.8510,
        0x41F: 0.8250, 0x420: 0.7100, 0x421: 0.7160, 0x422: 0.5880, 0x423: 0.6800, 0x424: 0.9170,
        0x425: 0.6500, 0x426: 0.8270, 0x427: 0.7310, 0x428: 1.0940, 0x429: 1.1170, 0x42A: 0.8200,
        0x42B: 0.9780, 0x42C: 0.7100, 0x42D: 0.7060, 0x42E: 1.0920, 0x42F: 0.7320, 0x430: 0.5830,
        0x431: 0.6590, 0x432: 0.6080, 0x433: 0.4750, 0x434: 0.6510, 0x435: 0.6180, 0x436: 0.8260,
        0x437: 0.5340, 0x438: 0.6880, 0x439: 0.6880, 0x43A: 0.5810, 0x43B: 0.6320, 0x43C: 0.7900,
        0x43D: 0.6750, 0x43E: 0.6360, 0x43F: 0.6740, 0x440: 0.6860, 0x441: 0.5630, 0x442: 0.4730,
        0x443: 0.5580, 0x444: 0.7850, 0x445: 0.5260, 0x446: 0.6840, 0x447: 0.5990, 0x448: 0.9290,
        0x449: 0.9290, 0x44A: 0.6210, 0x44B: 0.7850, 0x44C: 0.5630, 0x44D: 0.5710, 0x44E: 0.8650,
        0x44F: 0.6060, 0x450: 0.6180, 0x451: 0.6180, 0x452: 0.6710, 0x453: 0.4750, 0x454: 0.5720,
        0x455: 0.5280, 0x456: 0.2730, 0x457: 0.2690, 0x458: 0.2740, 0x459: 0.9220, 0x45A: 0.9440,
        0x45B: 0.6700, 0x45C: 0.5810, 0x45D: 0.6880, 0x45E: 0.5580, 0x45F: 0.6390, 0x462: 0.8020,
        0x463: 0.5960, 0x46A: 0.8840, 0x46B: 0.6800, 0x472: 0.8510, 0x473: 0.6460, 0x474: 0.7480,
        0x475: 0.5760, 0x48A: 0.8480, 0x48B: 0.7080, 0x48C: 0.7350, 0x48D: 0.5930, 0x48E: 0.7320,
        0x48F: 0.6970, 0x490: 0.5750, 0x491: 0.4490, 0x492: 0.6080, 0x493: 0.5020, 0x494: 0.7010,
        0x495: 0.5920, 0x496: 1.0520, 0x497: 0.8620, 0x498: 0.6360, 0x499: 0.5340, 0x49A: 0.7480,
        0x49B: 0.5810, 0x49C: 0.7280, 0x49D: 0.5970, 0x49E: 0.7240, 0x49F: 0.5810, 0x4A0: 0.8130,
        0x4A1: 0.6460, 0x4A2: 0.8450, 0x4A3: 0.6940, 0x4A4: 1.0880, 0x4A5: 0.8770, 0x4A6: 1.2040,
        0x4A7: 0.9690, 0x4A8: 0.9720, 0x4A9: 0.7940, 0x4AA: 0.7160, 0x4AB: 0.5630, 0x4AC: 0.5880,
        0x4AD: 0.4730, 0x4AE: 0.6520, 0x4AF: 0.5590, 0x4B0: 0.6350, 0x4B1: 0.5590, 0x4B2: 0.6900,
        0x4B3: 0.5260, 0x4B4: 0.9670, 0x4B5: 0.7570, 0x4B6: 0.7550, 0x4B7: 0.6200, 0x4B8: 0.7310,
        0x4B9: 0.5990, 0x4BA: 0.7310, 0x4BB: 0.6700, 0x4BC: 0.9740, 0x4BD: 0.7520, 0x4BE: 0.9740,
        0x4BF: 0.7520, 0x4C0: 0.3100, 0x4C1: 1.0110, 0x4C2: 0.8260, 0x4C3: 0.7020, 0x4C4: 0.5810,
        0x4C6: 0.6520, 0x4C7: 0.8160, 0x4C8: 0.6820, 0x4C9: 0.8450, 0x4CA: 0.6950, 0x4CB: 0.7280,
        0x4CC: 0.5970, 0x4CD: 0.9920, 0x4CE: 0.8160, 0x4CF: 0.2740, 0x4D0: 0.7440, 0x4D1: 0.5830,
        0x4D2: 0.7440, 0x4D3: 0.5830, 0x4D4: 1.0260, 0x4D5: 0.9900, 0x4D6: 0.6590, 0x4D7: 0.6180,
        0x4D8: 0.8240, 0x4D9: 0.6170, 0x4DA: 0.8240, 0x4DB: 0.6170, 0x4DC: 1.0110, 0x4DD: 0.8260,
        0x4DE: 0.6360, 0x4DF: 0.5340, 0x4E0: 0.6150, 0x4E1: 0.5140, 0x4E2: 0.8240, 0x4E3: 0.6880,
        0x4E4: 0.8240, 0x4E5: 0.6880, 0x4E6: 0.8510, 0x4E7: 0.6360, 0x4E8: 0.8510, 0x4E9: 0.6460,
        0x4EA: 0.8510, 0x4EB: 0.6460, 0x4EC: 0.7060, 0x4ED: 0.5710, 0x4EE: 0.6800, 0x4EF: 0.5580,
        0x4F0: 0.6800, 0x4F1: 0.5580, 0x4F2: 0.6800, 0x4F3: 0.5580, 0x4F4: 0.7310, 0x4F5: 0.5990,
        0x4F6: 0.5720, 0x4F7: 0.4750, 0x4F8: 0.9780, 0x4F9: 0.7850, 0x4FA: 0.6090, 0x4FB: 0.4780,
        0x4FC: 0.6510, 0x4FD: 0.5240, 0x4FE: 0.6680, 0x4FF: 0.5550,
    ]
    static let montserratBoldAdvances: [Double] = [
        0.2830, 0.2890, 0.4370, 0.7200, 0.6380, 0.8770, 0.7280, 0.2300, 0.3570, 0.3580, 0.4340, 0.5990, 0.2620, 0.3860, 0.2620,
        0.3920, 0.6790, 0.3920, 0.5900, 0.5920, 0.6890, 0.5950, 0.6370, 0.6200, 0.6600, 0.6370, 0.2620, 0.2620, 0.5990, 0.5990,
        0.5990, 0.5890, 1.0350, 0.7660, 0.7650, 0.7330, 0.8260, 0.6710, 0.6390, 0.7710, 0.8080, 0.3280, 0.5410, 0.7400, 0.6040,
        0.9550, 0.8080, 0.8440, 0.7320, 0.8440, 0.7350, 0.6380, 0.6180, 0.7880, 0.7460, 1.1630, 0.7140, 0.6760, 0.6710, 0.3680,
        0.3920, 0.3680, 0.6000, 0.5000, 0.6000, 0.6170, 0.6900, 0.5910, 0.6920, 0.6310, 0.3870, 0.7000, 0.6910, 0.3010, 0.3070,
        0.6600, 0.3010, 1.0490, 0.6910, 0.6550, 0.6900, 0.6900, 0.4310, 0.5310, 0.4350, 0.6870, 0.5980, 0.9370, 0.5950, 0.5980,
        0.5430, 0.3910, 0.3090, 0.3910, 0.5990,
    ]
    static let montserratBoldOtherAdvances: [UInt32: Double] = [
        0xA0: 0.2830, 0xA1: 0.2890, 0xA2: 0.5910, 0xA3: 0.6680, 0xA4: 0.7000, 0xA5: 0.7360,
        0xA6: 0.3090, 0xA7: 0.5220, 0xA8: 0.6000, 0xA9: 0.7850, 0xAA: 0.4120, 0xAB: 0.5680,
        0xAC: 0.5990, 0xAD: 0.3860, 0xAE: 0.7850, 0xAF: 0.6000, 0xB0: 0.4180, 0xB1: 0.5990,
        0xB2: 0.4300, 0xB3: 0.4300, 0xB4: 0.6000, 0xB5: 0.6900, 0xB6: 0.6860, 0xB7: 0.3020,
        0xB8: 0.6000, 0xB9: 0.4300, 0xBA: 0.4270, 0xBB: 0.5680, 0xBC: 1.0440, 0xBD: 1.0440,
        0xBE: 1.0440, 0xBF: 0.5890, 0xC0: 0.7660, 0xC1: 0.7660, 0xC2: 0.7660, 0xC3: 0.7660,
        0xC4: 0.7660, 0xC5: 0.7660, 0xC6: 1.0800, 0xC7: 0.7330, 0xC8: 0.6710, 0xC9: 0.6710,
        0xCA: 0.6710, 0xCB: 0.6710, 0xCC: 0.3280, 0xCD: 0.3280, 0xCE: 0.3280, 0xCF: 0.3280,
        0xD0: 0.8390, 0xD1: 0.8080, 0xD2: 0.8440, 0xD3: 0.8440, 0xD4: 0.8440, 0xD5: 0.8440,
        0xD6: 0.8440, 0xD7: 0.5990, 0xD8: 0.8440, 0xD9: 0.7880, 0xDA: 0.7880, 0xDB: 0.7880,
        0xDC: 0.7880, 0xDD: 0.6760, 0xDE: 0.7320, 0xDF: 0.6930, 0xE0: 0.6170, 0xE1: 0.6170,
        0xE2: 0.6170, 0xE3: 0.6170, 0xE4: 0.6170, 0xE5: 0.6170, 0xE6: 0.9960, 0xE7: 0.5910,
        0xE8: 0.6310, 0xE9: 0.6310, 0xEA: 0.6310, 0xEB: 0.6310, 0xEC: 0.3010, 0xED: 0.3010,
        0xEE: 0.3010, 0xEF: 0.3010, 0xF0: 0.6570, 0xF1: 0.6910, 0xF2: 0.6550, 0xF3: 0.6550,
        0xF4: 0.6550, 0xF5: 0.6550, 0xF6: 0.6550, 0xF7: 0.5990, 0xF8: 0.6550, 0xF9: 0.6870,
        0xFA: 0.6870, 0xFB: 0.6870, 0xFC: 0.6870, 0xFD: 0.5980, 0xFE: 0.6900, 0xFF: 0.5980,
        0x100: 0.7660, 0x101: 0.6170, 0x102: 0.7660, 0x103: 0.6170, 0x104: 0.7660, 0x105: 0.6170,
        0x106: 0.7330, 0x107: 0.5910, 0x108: 0.7330, 0x109: 0.5910, 0x10A: 0.7330, 0x10B: 0.5910,
        0x10C: 0.7330, 0x10D: 0.5910, 0x10E: 0.8260, 0x10F: 0.6920, 0x110: 0.8390, 0x111: 0.6920,
        0x112: 0.6710, 0x113: 0.6310, 0x114: 0.6710, 0x115: 0.6310, 0x116: 0.6710, 0x117: 0.6310,
        0x118: 0.6710, 0x119: 0.6310, 0x11A: 0.6710, 0x11B: 0.6310, 0x11C: 0.7710, 0x11D: 0.7000,
        0x11E: 0.7710, 0x11F: 0.7000, 0x120: 0.7710, 0x121: 0.7000, 0x122: 0.7710, 0x123: 0.7000,
        0x124: 0.8080, 0x125: 0.6910, 0x126: 0.8340, 0x127: 0.6910, 0x128: 0.3280, 0x129: 0.3010,
        0x12A: 0.3280, 0x12B: 0.3010, 0x12C: 0.3280, 0x12D: 0.3010, 0x12E: 0.3280, 0x12F: 0.3010,
        0x130: 0.3280, 0x131: 0.3010, 0x132: 0.7240, 0x133: 0.6080, 0x134: 0.5410, 0x135: 0.3070,
        0x136: 0.7400, 0x137: 0.6600, 0x138: 0.6450, 0x139: 0.6040, 0x13A: 0.3010, 0x13B: 0.6040,
        0x13C: 0.3010, 0x13D: 0.6040, 0x13E: 0.3010, 0x13F: 0.6040, 0x140: 0.4200, 0x141: 0.6170,
        0x142: 0.3270, 0x143: 0.8080, 0x144: 0.6910, 0x145: 0.8080, 0x146: 0.6910, 0x147: 0.8080,
        0x148: 0.6910, 0x149: 0.8200, 0x14A: 0.8080, 0x14B: 0.6910, 0x14C: 0.8440, 0x14D: 0.6550,
        0x14E: 0.8440, 0x14F: 0.6550, 0x150: 0.8440, 0x151: 0.6550, 0x152: 1.1360, 0x153: 1.0640,
        0x154: 0.7350, 0x155: 0.4310, 0x156: 0.7350, 0x157: 0.4310, 0x158: 0.7350, 0x159: 0.4310,
        0x15A: 0.6380, 0x15B: 0.5310, 0x15C: 0.6380, 0x15D: 0.5310, 0x15E: 0.6380, 0x15F: 0.5310,
        0x160: 0.6380, 0x161: 0.5310, 0x162: 0.6180, 0x163: 0.4350, 0x164: 0.6180, 0x165: 0.4350,
        0x166: 0.6180, 0x167: 0.4450, 0x168: 0.7880, 0x169: 0.6870, 0x16A: 0.7880, 0x16B: 0.6870,
        0x16C: 0.7880, 0x16D: 0.6870, 0x16E: 0.7880, 0x16F: 0.6870, 0x170: 0.7880, 0x171: 0.6870,
        0x172: 0.7880, 0x173: 0.6870, 0x174: 1.1630, 0x175: 0.9370, 0x176: 0.6760, 0x177: 0.5980,
        0x178: 0.6760, 0x179: 0.6710, 0x17A: 0.5430, 0x17B: 0.6710, 0x17C: 0.5430, 0x17D: 0.6710,
        0x17E: 0.5430, 0x17F: 0.3330, 0x18F: 0.8170, 0x192: 0.4810, 0x1A0: 0.8440, 0x1A1: 0.6550,
        0x1AF: 0.8010, 0x1B0: 0.7010, 0x1B7: 0.6380, 0x1C4: 1.4490, 0x1C5: 1.3690, 0x1C6: 1.2330,
        0x1C7: 1.1450, 0x1C8: 0.9110, 0x1C9: 0.6080, 0x1CA: 1.3490, 0x1CB: 1.1150, 0x1CC: 0.9980,
        0x1CD: 0.7660, 0x1CE: 0.6170, 0x1D3: 0.7880, 0x1D4: 0.6870, 0x1E4: 0.8110, 0x1E5: 0.7110,
        0x1E6: 0.7710, 0x1E7: 0.7000, 0x1E8: 0.7400, 0x1E9: 0.6600, 0x1EA: 0.8440, 0x1EB: 0.6550,
        0x1EE: 0.6380, 0x1EF: 0.5540, 0x1FA: 0.7660, 0x1FB: 0.6170, 0x1FC: 1.0800, 0x1FD: 0.9960,
        0x1FE: 0.8440, 0x1FF: 0.6550, 0x200: 0.7660, 0x201: 0.6170, 0x202: 0.7660, 0x203: 0.6170,
        0x204: 0.6710, 0x205: 0.6310, 0x206: 0.6710, 0x207: 0.6310, 0x208: 0.3280, 0x209: 0.3010,
        0x20A: 0.3280, 0x20B: 0.3010, 0x20C: 0.8440, 0x20D: 0.6550, 0x20E: 0.8440, 0x20F: 0.6550,
        0x210: 0.7350, 0x211: 0.4310, 0x212: 0.7350, 0x213: 0.4310, 0x214: 0.7880, 0x215: 0.6870,
        0x216: 0.7880, 0x217: 0.6870, 0x218: 0.6380, 0x219: 0.5310, 0x21A: 0.6180, 0x21B: 0.4350,
        0x21E: 0.8080, 0x21F: 0.6910, 0x22A: 0.8440, 0x22B: 0.6550, 0x22C: 0.8440, 0x22D: 0.6550,
        0x230: 0.8440, 0x231: 0.6550, 0x232: 0.6760, 0x233: 0.5980, 0x237: 0.3070, 0x400: 0.6730,
        0x401: 0.6730, 0x402: 0.8490, 0x403: 0.5930, 0x404: 0.7150, 0x405: 0.6530, 0x406: 0.3350,
        0x407: 0.3280, 0x408: 0.5680, 0x409: 1.1850, 0x40A: 1.1710, 0x40B: 0.8570, 0x40C: 0.7350,
        0x40D: 0.8210, 0x40E: 0.7240, 0x40F: 0.8080, 0x410: 0.7990, 0x411: 0.7380, 0x412: 0.7450,
        0x413: 0.5930, 0x414: 0.8310, 0x415: 0.6730, 0x416: 1.0790, 0x417: 0.6560, 0x418: 0.8210,
        0x419: 0.8210, 0x41A: 0.7350, 0x41B: 0.7990, 0x41C: 0.9630, 0x41D: 0.8170, 0x41E: 0.8420,
        0x41F: 0.8120, 0x420: 0.7240, 0x421: 0.7260, 0x422: 0.6370, 0x423: 0.7240, 0x424: 0.9500,
        0x425: 0.7220, 0x426: 0.8410, 0x427: 0.7490, 0x428: 1.0980, 0x429: 1.1300, 0x42A: 0.8450,
        0x42B: 1.0280, 0x42C: 0.7210, 0x42D: 0.7140, 0x42E: 1.1140, 0x42F: 0.7340, 0x430: 0.6040,
        0x431: 0.6730, 0x432: 0.6220, 0x433: 0.5140, 0x434: 0.7010, 0x435: 0.6430, 0x436: 0.9130,
        0x437: 0.5630, 0x438: 0.7100, 0x439: 0.7100, 0x43A: 0.6420, 0x43B: 0.6660, 0x43C: 0.8150,
        0x43D: 0.6940, 0x43E: 0.6540, 0x43F: 0.6850, 0x440: 0.6940, 0x441: 0.5920, 0x442: 0.5350,
        0x443: 0.6140, 0x444: 0.8490, 0x445: 0.5920, 0x446: 0.7040, 0x447: 0.6340, 0x448: 0.9710,
        0x449: 0.9710, 0x44A: 0.6820, 0x44B: 0.8590, 0x44C: 0.6050, 0x44D: 0.5900, 0x44E: 0.9030,
        0x44F: 0.6280, 0x450: 0.6430, 0x451: 0.6430, 0x452: 0.6850, 0x453: 0.5140, 0x454: 0.5920,
        0x455: 0.5510, 0x456: 0.3050, 0x457: 0.3010, 0x458: 0.3060, 0x459: 0.9650, 0x45A: 0.9720,
        0x45B: 0.6850, 0x45C: 0.6420, 0x45D: 0.7100, 0x45E: 0.6140, 0x45F: 0.6610, 0x462: 0.8290,
        0x463: 0.6480, 0x46A: 0.9450, 0x46B: 0.7710, 0x472: 0.8420, 0x473: 0.6610, 0x474: 0.7930,
        0x475: 0.6480, 0x48A: 0.8600, 0x48B: 0.7370, 0x48C: 0.7520, 0x48D: 0.6410, 0x48E: 0.7350,
        0x48F: 0.7030, 0x490: 0.5950, 0x491: 0.5020, 0x492: 0.6400, 0x493: 0.5490, 0x494: 0.7060,
        0x495: 0.6270, 0x496: 1.1110, 0x497: 0.9400, 0x498: 0.6560, 0x499: 0.5630, 0x49A: 0.7720,
        0x49B: 0.6420, 0x49C: 0.7750, 0x49D: 0.6570, 0x49E: 0.7580, 0x49F: 0.6400, 0x4A0: 0.8610,
        0x4A1: 0.7280, 0x4A2: 0.8520, 0x4A3: 0.7200, 0x4A4: 1.0780, 0x4A5: 0.9030, 0x4A6: 1.1780,
        0x4A7: 0.9950, 0x4A8: 0.9770, 0x4A9: 0.8330, 0x4AA: 0.7260, 0x4AB: 0.5920, 0x4AC: 0.6370,
        0x4AD: 0.5350, 0x4AE: 0.7120, 0x4AF: 0.6160, 0x4B0: 0.6760, 0x4B1: 0.6160, 0x4B2: 0.7510,
        0x4B3: 0.5920, 0x4B4: 0.9930, 0x4B5: 0.7990, 0x4B6: 0.7840, 0x4B7: 0.6670, 0x4B8: 0.7490,
        0x4B9: 0.6340, 0x4BA: 0.7490, 0x4BB: 0.6850, 0x4BC: 1.0180, 0x4BD: 0.8150, 0x4BE: 1.0180,
        0x4BF: 0.8150, 0x4C0: 0.3370, 0x4C1: 1.0790, 0x4C2: 0.9130, 0x4C3: 0.7440, 0x4C4: 0.6420,
        0x4C6: 0.6930, 0x4C7: 0.8140, 0x4C8: 0.6970, 0x4C9: 0.8560, 0x4CA: 0.7210, 0x4CB: 0.7440,
        0x4CC: 0.6290, 0x4CD: 1.0170, 0x4CE: 0.8580, 0x4CF: 0.3050, 0x4D0: 0.7990, 0x4D1: 0.6040,
        0x4D2: 0.7990, 0x4D3: 0.6040, 0x4D4: 1.0910, 0x4D5: 0.9950, 0x4D6: 0.6730, 0x4D7: 0.6430,
        0x4D8: 0.8210, 0x4D9: 0.6430, 0x4DA: 0.8210, 0x4DB: 0.6430, 0x4DC: 1.0790, 0x4DD: 0.9130,
        0x4DE: 0.6560, 0x4DF: 0.5630, 0x4E0: 0.6380, 0x4E1: 0.5540, 0x4E2: 0.8210, 0x4E3: 0.7100,
        0x4E4: 0.8210, 0x4E5: 0.7100, 0x4E6: 0.8420, 0x4E7: 0.6540, 0x4E8: 0.8420, 0x4E9: 0.6610,
        0x4EA: 0.8420, 0x4EB: 0.6610, 0x4EC: 0.7140, 0x4ED: 0.5900, 0x4EE: 0.7240, 0x4EF: 0.6140,
        0x4F0: 0.7240, 0x4F1: 0.6140, 0x4F2: 0.7240, 0x4F3: 0.6140, 0x4F4: 0.7490, 0x4F5: 0.6340,
        0x4F6: 0.5930, 0x4F7: 0.5140, 0x4F8: 1.0280, 0x4F9: 0.8590, 0x4FA: 0.6410, 0x4FB: 0.5220,
        0x4FC: 0.7190, 0x4FD: 0.5940, 0x4FE: 0.7310, 0x4FF: 0.6090,
    ]
    static let tahomaBoldAdvances: [Double] = [
        0.2930, 0.3428, 0.4893, 0.6255, 0.6255, 1.0001, 0.7812, 0.2754, 0.4541, 0.4541, 0.4377, 0.6569, 0.3125, 0.4312, 0.3125,
        0.5771, 0.6367, 0.6367, 0.6367, 0.6367, 0.6367, 0.6367, 0.6367, 0.6367, 0.6367, 0.6367, 0.3633, 0.3633, 0.6569, 0.6569,
        0.6569, 0.6871, 1.0968, 0.6846, 0.6860, 0.6675, 0.7573, 0.6152, 0.5811, 0.7582, 0.7642, 0.4834, 0.5005, 0.6963, 0.5723,
        0.8931, 0.7039, 0.7700, 0.6572, 0.7582, 0.7261, 0.6333, 0.6123, 0.7039, 0.6502, 1.0278, 0.6502, 0.6502, 0.5954, 0.4541,
        0.3125, 0.4541, 0.6569, 0.6255, 0.3746, 0.5986, 0.6318, 0.5273, 0.6294, 0.5938, 0.3490, 0.6294, 0.6401, 0.3018, 0.2911,
        0.5828, 0.3018, 0.9536, 0.6401, 0.6172, 0.6294, 0.6401, 0.4336, 0.5146, 0.4155, 0.6401, 0.5786, 0.8151, 0.6045, 0.5757,
        0.5240, 0.4377, 0.3147, 0.4377, 0.6569,
    ]


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

    // Cambria's own Greek widths, U+0384 to U+03CE, and its bold's
    // (cambria.ttc and cambriab.ttf, read off the Windows box by windows
    // 01QbbApP; the 37 zh-d97c5474's print embeds are the same). Caladea
    // has no Greek, and its fallback, DejaVu Sans, set it wider.
    static let cambriaGreekAdvances: [UInt32: Double] = [
        0x0384: 0.2847, 0x0385: 0.2847, 0x0386: 0.6187, 0x0387: 0.2441, 0x0388: 0.7061, 0x0389: 0.8125, 0x038A: 0.4502, 0x038C: 0.7358,
        0x038E: 0.7783, 0x038F: 0.7563, 0x0390: 0.2842, 0x0391: 0.6230, 0x0392: 0.6113, 0x0393: 0.5361, 0x0394: 0.5957, 0x0395: 0.5752,
        0x0396: 0.5376, 0x0397: 0.6865, 0x0398: 0.6533, 0x0399: 0.3242, 0x039A: 0.6294, 0x039B: 0.6055, 0x039C: 0.8154, 0x039D: 0.6807,
        0x039E: 0.5718, 0x039F: 0.6533, 0x03A0: 0.6743, 0x03A1: 0.5679, 0x03A3: 0.5479, 0x03A4: 0.5928, 0x03A5: 0.6074, 0x03A6: 0.7852,
        0x03A7: 0.5713, 0x03A8: 0.7827, 0x03A9: 0.6792, 0x03AA: 0.3242, 0x03AB: 0.6074, 0x03AC: 0.5742, 0x03AD: 0.4438, 0x03AE: 0.5430,
        0x03AF: 0.2842, 0x03B0: 0.5410, 0x03B1: 0.5742, 0x03B2: 0.5552, 0x03B3: 0.5068, 0x03B4: 0.5249, 0x03B5: 0.4438, 0x03B6: 0.3999,
        0x03B7: 0.5430, 0x03B8: 0.5469, 0x03B9: 0.2842, 0x03BA: 0.5269, 0x03BB: 0.4878, 0x03BC: 0.5459, 0x03BD: 0.4819, 0x03BE: 0.4048,
        0x03BF: 0.5308, 0x03C0: 0.6021, 0x03C1: 0.5322, 0x03C2: 0.4312, 0x03C3: 0.5718, 0x03C4: 0.4780, 0x03C5: 0.5410, 0x03C6: 0.7119,
        0x03C7: 0.4858, 0x03C8: 0.7192, 0x03C9: 0.7510, 0x03CA: 0.2842, 0x03CB: 0.5410, 0x03CC: 0.5308, 0x03CD: 0.5410, 0x03CE: 0.7510,
    ]
    static let cambriaBoldGreekAdvances: [UInt32: Double] = [
        0x0384: 0.2861, 0x0385: 0.2861, 0x0386: 0.6519, 0x0387: 0.2319, 0x0388: 0.7153, 0x0389: 0.8604, 0x038A: 0.4897, 0x038C: 0.7744,
        0x038E: 0.8403, 0x038F: 0.8062, 0x0390: 0.3281, 0x0391: 0.6519, 0x0392: 0.6514, 0x0393: 0.5508, 0x0394: 0.6421, 0x0395: 0.5776,
        0x0396: 0.5664, 0x0397: 0.7217, 0x0398: 0.7051, 0x0399: 0.3496, 0x039A: 0.6816, 0x039B: 0.6523, 0x039C: 0.8462, 0x039D: 0.6792,
        0x039E: 0.5913, 0x039F: 0.6953, 0x03A0: 0.7012, 0x03A1: 0.6138, 0x03A3: 0.5908, 0x03A4: 0.6392, 0x03A5: 0.6602, 0x03A6: 0.8018,
        0x03A7: 0.6187, 0x03A8: 0.8379, 0x03A9: 0.7441, 0x03AA: 0.3496, 0x03AB: 0.6602, 0x03AC: 0.6191, 0x03AD: 0.4927, 0x03AE: 0.5991,
        0x03AF: 0.3281, 0x03B0: 0.5801, 0x03B1: 0.6191, 0x03B2: 0.6011, 0x03B3: 0.5649, 0x03B4: 0.5708, 0x03B5: 0.4927, 0x03B6: 0.4561,
        0x03B7: 0.5991, 0x03B8: 0.5801, 0x03B9: 0.3281, 0x03BA: 0.6040, 0x03BB: 0.5278, 0x03BC: 0.6084, 0x03BD: 0.5552, 0x03BE: 0.4448,
        0x03BF: 0.5693, 0x03C0: 0.6279, 0x03C1: 0.5854, 0x03C2: 0.4780, 0x03C3: 0.6118, 0x03C4: 0.5571, 0x03C5: 0.5801, 0x03C6: 0.7539,
        0x03C7: 0.5371, 0x03C8: 0.8018, 0x03C9: 0.7988, 0x03CA: 0.3281, 0x03CB: 0.5801, 0x03CC: 0.5693, 0x03CD: 0.5801, 0x03CE: 0.7988,
    ]

    // Nunito Sans's own widths, U+0020 to U+007E and Latin-1, the common
    // marks past it and the five Greek letters it has (Δ Σ Ω μ π), in its
    // Light (300), Regular and Bold (700) at its 12pt optical size:
    // Office's cloud font, which Word for Windows and Word for Mac both
    // set and embed (zh-d97c5474's and zh-8d72961c's subsets, every one of
    // their widths equal to these). The stand-in was Carlito, some 9%
    // narrower.
    static let nunitoSansLightAdvances: [Double] = [
        0.251, 0.219, 0.366, 0.600, 0.600, 0.923, 0.678, 0.211, 0.299, 0.299, 0.449, 0.600, 0.219, 0.420, 0.219,
        0.269, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.219, 0.219, 0.600, 0.600,
        0.600, 0.436, 0.945, 0.722, 0.671, 0.670, 0.733, 0.576, 0.542, 0.722, 0.756, 0.245, 0.310, 0.607, 0.535,
        0.849, 0.736, 0.759, 0.624, 0.759, 0.661, 0.607, 0.594, 0.724, 0.678, 1.096, 0.640, 0.586, 0.582, 0.298,
        0.269, 0.298, 0.600, 0.500, 0.500, 0.522, 0.575, 0.459, 0.575, 0.527, 0.319, 0.578, 0.560, 0.222, 0.225,
        0.484, 0.285, 0.847, 0.560, 0.547, 0.575, 0.575, 0.342, 0.478, 0.335, 0.553, 0.509, 0.835, 0.515, 0.509,
        0.459, 0.335, 0.254, 0.335, 0.600,
    ]
    static let nunitoSansLightOtherAdvances: [UInt32: Double] = [
        0x00A0: 0.251, 0x00A1: 0.219, 0x00A2: 0.600, 0x00A3: 0.600, 0x00A4: 0.600, 0x00A5: 0.600, 0x00A6: 0.254, 0x00A7: 0.534,
        0x00A8: 0.500, 0x00A9: 0.815, 0x00AA: 0.321, 0x00AB: 0.417, 0x00AC: 0.600, 0x00AD: 0.420, 0x00AE: 0.815, 0x00AF: 0.500,
        0x00B0: 0.367, 0x00B1: 0.600, 0x00B2: 0.380, 0x00B3: 0.380, 0x00B4: 0.500, 0x00B5: 0.600, 0x00B6: 0.572, 0x00B7: 0.219,
        0x00B8: 0.500, 0x00B9: 0.380, 0x00BA: 0.332, 0x00BB: 0.417, 0x00BC: 0.885, 0x00BD: 0.927, 0x00BE: 0.885, 0x00BF: 0.436,
        0x00C0: 0.722, 0x00C1: 0.722, 0x00C2: 0.722, 0x00C3: 0.722, 0x00C4: 0.722, 0x00C5: 0.722, 0x00C6: 0.976, 0x00C7: 0.670,
        0x00C8: 0.576, 0x00C9: 0.576, 0x00CA: 0.576, 0x00CB: 0.576, 0x00CC: 0.245, 0x00CD: 0.245, 0x00CE: 0.245, 0x00CF: 0.245,
        0x00D0: 0.733, 0x00D1: 0.736, 0x00D2: 0.759, 0x00D3: 0.759, 0x00D4: 0.759, 0x00D5: 0.759, 0x00D6: 0.759, 0x00D7: 0.600,
        0x00D8: 0.759, 0x00D9: 0.724, 0x00DA: 0.724, 0x00DB: 0.724, 0x00DC: 0.724, 0x00DD: 0.586, 0x00DE: 0.625, 0x00DF: 0.597,
        0x00E0: 0.522, 0x00E1: 0.522, 0x00E2: 0.522, 0x00E3: 0.522, 0x00E4: 0.522, 0x00E5: 0.522, 0x00E6: 0.859, 0x00E7: 0.459,
        0x00E8: 0.527, 0x00E9: 0.527, 0x00EA: 0.527, 0x00EB: 0.527, 0x00EC: 0.222, 0x00ED: 0.222, 0x00EE: 0.222, 0x00EF: 0.222,
        0x00F0: 0.550, 0x00F1: 0.560, 0x00F2: 0.547, 0x00F3: 0.547, 0x00F4: 0.547, 0x00F5: 0.547, 0x00F6: 0.547, 0x00F7: 0.600,
        0x00F8: 0.547, 0x00F9: 0.553, 0x00FA: 0.553, 0x00FB: 0.553, 0x00FC: 0.553, 0x00FD: 0.509, 0x00FE: 0.575, 0x00FF: 0.509,
        0x2013: 0.500, 0x2014: 1.000, 0x2018: 0.219, 0x2019: 0.219, 0x201C: 0.372, 0x201D: 0.372, 0x2022: 0.524, 0x2026: 0.659,
        0x0394: 0.722, 0x03A3: 0.600, 0x03A9: 0.769, 0x03BC: 0.553, 0x03C0: 0.573,
    ]
    static let nunitoSansAdvances: [Double] = [
        0.257, 0.228, 0.391, 0.600, 0.600, 0.930, 0.693, 0.221, 0.317, 0.317, 0.450, 0.600, 0.228, 0.424, 0.228,
        0.283, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.228, 0.228, 0.600, 0.600,
        0.600, 0.443, 0.946, 0.729, 0.676, 0.673, 0.742, 0.583, 0.548, 0.726, 0.761, 0.256, 0.324, 0.625, 0.543,
        0.855, 0.740, 0.767, 0.633, 0.767, 0.669, 0.615, 0.602, 0.728, 0.689, 1.101, 0.650, 0.596, 0.589, 0.315,
        0.283, 0.315, 0.600, 0.500, 0.500, 0.530, 0.583, 0.463, 0.583, 0.532, 0.333, 0.586, 0.568, 0.232, 0.236,
        0.500, 0.296, 0.856, 0.568, 0.556, 0.583, 0.583, 0.358, 0.481, 0.350, 0.561, 0.515, 0.841, 0.525, 0.514,
        0.463, 0.352, 0.265, 0.352, 0.600,
    ]
    static let nunitoSansOtherAdvances: [UInt32: Double] = [
        0x00A0: 0.257, 0x00A1: 0.228, 0x00A2: 0.600, 0x00A3: 0.600, 0x00A4: 0.600, 0x00A5: 0.600, 0x00A6: 0.265, 0x00A7: 0.545,
        0x00A8: 0.500, 0x00A9: 0.815, 0x00AA: 0.327, 0x00AB: 0.441, 0x00AC: 0.600, 0x00AD: 0.424, 0x00AE: 0.815, 0x00AF: 0.500,
        0x00B0: 0.371, 0x00B1: 0.600, 0x00B2: 0.380, 0x00B3: 0.380, 0x00B4: 0.500, 0x00B5: 0.600, 0x00B6: 0.588, 0x00B7: 0.228,
        0x00B8: 0.500, 0x00B9: 0.380, 0x00BA: 0.339, 0x00BB: 0.441, 0x00BC: 0.893, 0x00BD: 0.937, 0x00BE: 0.893, 0x00BF: 0.443,
        0x00C0: 0.729, 0x00C1: 0.729, 0x00C2: 0.729, 0x00C3: 0.729, 0x00C4: 0.729, 0x00C5: 0.729, 0x00C6: 0.981, 0x00C7: 0.673,
        0x00C8: 0.583, 0x00C9: 0.583, 0x00CA: 0.583, 0x00CB: 0.583, 0x00CC: 0.256, 0x00CD: 0.256, 0x00CE: 0.256, 0x00CF: 0.256,
        0x00D0: 0.742, 0x00D1: 0.740, 0x00D2: 0.767, 0x00D3: 0.767, 0x00D4: 0.767, 0x00D5: 0.767, 0x00D6: 0.767, 0x00D7: 0.600,
        0x00D8: 0.767, 0x00D9: 0.728, 0x00DA: 0.728, 0x00DB: 0.728, 0x00DC: 0.728, 0x00DD: 0.596, 0x00DE: 0.634, 0x00DF: 0.615,
        0x00E0: 0.530, 0x00E1: 0.530, 0x00E2: 0.530, 0x00E3: 0.530, 0x00E4: 0.530, 0x00E5: 0.530, 0x00E6: 0.861, 0x00E7: 0.463,
        0x00E8: 0.532, 0x00E9: 0.532, 0x00EA: 0.532, 0x00EB: 0.532, 0x00EC: 0.232, 0x00ED: 0.232, 0x00EE: 0.232, 0x00EF: 0.232,
        0x00F0: 0.559, 0x00F1: 0.568, 0x00F2: 0.556, 0x00F3: 0.556, 0x00F4: 0.556, 0x00F5: 0.556, 0x00F6: 0.556, 0x00F7: 0.600,
        0x00F8: 0.556, 0x00F9: 0.561, 0x00FA: 0.561, 0x00FB: 0.561, 0x00FC: 0.561, 0x00FD: 0.514, 0x00FE: 0.583, 0x00FF: 0.514,
        0x2013: 0.500, 0x2014: 1.000, 0x2018: 0.228, 0x2019: 0.228, 0x201C: 0.394, 0x201D: 0.394, 0x2022: 0.524, 0x2026: 0.686,
        0x0394: 0.729, 0x03A3: 0.600, 0x03A9: 0.778, 0x03BC: 0.561, 0x03C0: 0.587,
    ]
    static let nunitoSansBoldAdvances: [Double] = [
        0.270, 0.248, 0.447, 0.600, 0.600, 0.945, 0.726, 0.242, 0.358, 0.358, 0.452, 0.600, 0.248, 0.434, 0.248,
        0.313, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.600, 0.248, 0.248, 0.600, 0.600,
        0.600, 0.459, 0.950, 0.744, 0.688, 0.679, 0.762, 0.597, 0.562, 0.736, 0.773, 0.281, 0.355, 0.664, 0.562,
        0.868, 0.748, 0.785, 0.652, 0.785, 0.686, 0.631, 0.621, 0.738, 0.713, 1.113, 0.672, 0.618, 0.605, 0.354,
        0.313, 0.354, 0.600, 0.500, 0.500, 0.547, 0.600, 0.472, 0.600, 0.542, 0.364, 0.604, 0.585, 0.255, 0.259,
        0.536, 0.319, 0.877, 0.585, 0.576, 0.600, 0.600, 0.392, 0.488, 0.384, 0.579, 0.527, 0.853, 0.546, 0.526,
        0.474, 0.391, 0.289, 0.391, 0.600,
    ]
    static let nunitoSansBoldOtherAdvances: [UInt32: Double] = [
        0x00A0: 0.270, 0x00A1: 0.248, 0x00A2: 0.600, 0x00A3: 0.600, 0x00A4: 0.600, 0x00A5: 0.600, 0x00A6: 0.289, 0x00A7: 0.569,
        0x00A8: 0.500, 0x00A9: 0.815, 0x00AA: 0.339, 0x00AB: 0.494, 0x00AC: 0.600, 0x00AD: 0.434, 0x00AE: 0.815, 0x00AF: 0.500,
        0x00B0: 0.379, 0x00B1: 0.600, 0x00B2: 0.380, 0x00B3: 0.380, 0x00B4: 0.500, 0x00B5: 0.600, 0x00B6: 0.625, 0x00B7: 0.248,
        0x00B8: 0.500, 0x00B9: 0.380, 0x00BA: 0.353, 0x00BB: 0.494, 0x00BC: 0.911, 0x00BD: 0.959, 0x00BE: 0.911, 0x00BF: 0.459,
        0x00C0: 0.744, 0x00C1: 0.744, 0x00C2: 0.744, 0x00C3: 0.744, 0x00C4: 0.744, 0x00C5: 0.744, 0x00C6: 0.992, 0x00C7: 0.679,
        0x00C8: 0.597, 0x00C9: 0.597, 0x00CA: 0.597, 0x00CB: 0.597, 0x00CC: 0.281, 0x00CD: 0.281, 0x00CE: 0.281, 0x00CF: 0.281,
        0x00D0: 0.762, 0x00D1: 0.748, 0x00D2: 0.785, 0x00D3: 0.785, 0x00D4: 0.785, 0x00D5: 0.785, 0x00D6: 0.785, 0x00D7: 0.600,
        0x00D8: 0.785, 0x00D9: 0.738, 0x00DA: 0.738, 0x00DB: 0.738, 0x00DC: 0.738, 0x00DD: 0.618, 0x00DE: 0.654, 0x00DF: 0.653,
        0x00E0: 0.547, 0x00E1: 0.547, 0x00E2: 0.547, 0x00E3: 0.547, 0x00E4: 0.547, 0x00E5: 0.547, 0x00E6: 0.865, 0x00E7: 0.472,
        0x00E8: 0.542, 0x00E9: 0.542, 0x00EA: 0.542, 0x00EB: 0.542, 0x00EC: 0.255, 0x00ED: 0.255, 0x00EE: 0.255, 0x00EF: 0.255,
        0x00F0: 0.580, 0x00F1: 0.585, 0x00F2: 0.576, 0x00F3: 0.576, 0x00F4: 0.576, 0x00F5: 0.576, 0x00F6: 0.576, 0x00F7: 0.600,
        0x00F8: 0.576, 0x00F9: 0.579, 0x00FA: 0.579, 0x00FB: 0.579, 0x00FC: 0.579, 0x00FD: 0.526, 0x00FE: 0.600, 0x00FF: 0.526,
        0x2013: 0.500, 0x2014: 1.000, 0x2018: 0.248, 0x2019: 0.248, 0x201C: 0.443, 0x201D: 0.443, 0x2022: 0.524, 0x2026: 0.745,
        0x0394: 0.744, 0x03A3: 0.600, 0x03A9: 0.799, 0x03BC: 0.579, 0x03C0: 0.618,
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
    static let thaiWordFaces: Set<String> = ["th sarabun new", "th sarabunpsk", "browallia new", "browalliaupc", "cordia new", "cordiaupc", "th sarabunit๙",
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
    /// TH SarabunPSK's own advances in ems, regular and bold, Latin and
    /// Thai, read from the hmtx of the subsets Word for Windows embeds in
    /// its prints (the face is not Browallia: Thai about 7% narrower).
    static let thSarabunPSKLatin: [UInt32: Double] = [0x20: 0.216, 0x21: 0.147, 0x22: 0.208, 0x25: 0.585, 0x26: 0.423, 0x27: 0.12, 0x28: 0.19, 0x29: 0.19, 0x2A: 0.285, 0x2B: 0.411, 0x2C: 0.162, 0x2D: 0.216, 0x2E: 0.162, 0x2F: 0.27, 0x30: 0.362, 0x31: 0.362, 0x32: 0.362, 0x33: 0.362, 0x34: 0.362, 0x35: 0.362, 0x36: 0.362, 0x37: 0.362, 0x38: 0.362, 0x39: 0.362, 0x3A: 0.162, 0x3B: 0.162, 0x3C: 0.411, 0x3D: 0.411, 0x3E: 0.411, 0x3F: 0.283, 0x40: 0.536, 0x41: 0.4, 0x42: 0.378, 0x43: 0.406, 0x44: 0.431, 0x45: 0.351, 0x46: 0.351, 0x47: 0.425, 0x48: 0.441, 0x49: 0.147, 0x4A: 0.264, 0x4B: 0.376, 0x4C: 0.353, 0x4D: 0.548, 0x4E: 0.441, 0x4F: 0.486, 0x50: 0.378, 0x51: 0.487, 0x52: 0.379, 0x53: 0.352, 0x54: 0.379, 0x55: 0.466, 0x56: 0.39, 0x57: 0.588, 0x58: 0.418, 0x59: 0.366, 0x5A: 0.424, 0x5B: 0.196, 0x5D: 0.196, 0x5F: 0.352, 0x61: 0.344, 0x62: 0.401, 0x63: 0.331, 0x64: 0.401, 0x65: 0.374, 0x66: 0.206, 0x67: 0.311, 0x68: 0.39, 0x69: 0.143, 0x6A: 0.155, 0x6B: 0.316, 0x6C: 0.2, 0x6D: 0.601, 0x6E: 0.39, 0x6F: 0.398, 0x70: 0.401, 0x71: 0.401, 0x72: 0.217, 0x73: 0.282, 0x74: 0.238, 0x75: 0.39, 0x76: 0.341, 0x77: 0.507, 0x78: 0.318, 0x79: 0.337, 0x7A: 0.321, 0x7C: 0.153]
    static let thSarabunPSKBoldLatin: [UInt32: Double] = [0x20: 0.226, 0x21: 0.168, 0x22: 0.291, 0x25: 0.688, 0x28: 0.244, 0x29: 0.244, 0x2A: 0.343, 0x2C: 0.172, 0x2D: 0.226, 0x2E: 0.172, 0x2F: 0.276, 0x30: 0.378, 0x31: 0.378, 0x32: 0.378, 0x33: 0.378, 0x34: 0.378, 0x35: 0.378, 0x36: 0.378, 0x37: 0.378, 0x38: 0.378, 0x39: 0.378, 0x3A: 0.172, 0x3E: 0.417, 0x41: 0.451, 0x42: 0.396, 0x43: 0.432, 0x44: 0.459, 0x45: 0.358, 0x46: 0.358, 0x47: 0.454, 0x48: 0.472, 0x49: 0.163, 0x4A: 0.282, 0x4B: 0.411, 0x4C: 0.359, 0x4D: 0.574, 0x4E: 0.472, 0x4F: 0.518, 0x50: 0.39, 0x51: 0.518, 0x52: 0.395, 0x53: 0.365, 0x54: 0.421, 0x55: 0.482, 0x56: 0.422, 0x57: 0.612, 0x59: 0.396, 0x61: 0.367, 0x62: 0.435, 0x63: 0.347, 0x64: 0.435, 0x65: 0.391, 0x66: 0.254, 0x67: 0.332, 0x68: 0.423, 0x69: 0.163, 0x6A: 0.171, 0x6B: 0.34, 0x6C: 0.213, 0x6D: 0.636, 0x6E: 0.423, 0x6F: 0.412, 0x70: 0.431, 0x71: 0.431, 0x72: 0.246, 0x73: 0.296, 0x74: 0.258, 0x75: 0.418, 0x76: 0.358, 0x77: 0.48, 0x78: 0.349, 0x79: 0.361, 0x7A: 0.358]
    static let thSarabunPSKThai: [UInt32: Double] = [0x0E01: 0.386, 0x0E02: 0.378, 0x0E04: 0.393, 0x0E06: 0.408, 0x0E07: 0.294, 0x0E08: 0.367, 0x0E09: 0.377, 0x0E0A: 0.38, 0x0E0B: 0.384, 0x0E0D: 0.519, 0x0E0E: 0.425, 0x0E0F: 0.425, 0x0E10: 0.343, 0x0E11: 0.461, 0x0E12: 0.532, 0x0E13: 0.543, 0x0E14: 0.391, 0x0E15: 0.391, 0x0E16: 0.378, 0x0E17: 0.43, 0x0E18: 0.335, 0x0E19: 0.42, 0x0E1A: 0.428, 0x0E1B: 0.428, 0x0E1C: 0.381, 0x0E1D: 0.381, 0x0E1E: 0.447, 0x0E1F: 0.447, 0x0E20: 0.425, 0x0E21: 0.4, 0x0E22: 0.375, 0x0E23: 0.322, 0x0E24: 0.378, 0x0E25: 0.381, 0x0E27: 0.335, 0x0E28: 0.393, 0x0E29: 0.438, 0x0E2A: 0.381, 0x0E2B: 0.427, 0x0E2C: 0.454, 0x0E2D: 0.387, 0x0E2E: 0.372, 0x0E2F: 0.391, 0x0E30: 0.357, 0x0E31: 0.0, 0x0E32: 0.316, 0x0E33: 0.316, 0x0E34: 0.0, 0x0E35: 0.0, 0x0E36: 0.0, 0x0E37: 0.0, 0x0E38: 0.0, 0x0E39: 0.0, 0x0E3A: 0.0, 0x0E40: 0.203, 0x0E41: 0.377, 0x0E42: 0.237, 0x0E43: 0.242, 0x0E44: 0.244, 0x0E45: 0.205, 0x0E46: 0.399, 0x0E47: 0.0, 0x0E48: 0.0, 0x0E49: 0.0, 0x0E4A: 0.0, 0x0E4B: 0.0, 0x0E4C: 0.0, 0x0E4D: 0.0, 0x0E50: 0.449, 0x0E51: 0.449, 0x0E52: 0.449, 0x0E53: 0.449, 0x0E54: 0.449, 0x0E55: 0.449, 0x0E56: 0.449, 0x0E57: 0.449, 0x0E58: 0.449, 0x0E59: 0.449]
    static let thSarabunPSKBoldThai: [UInt32: Double] = [0x0E01: 0.391, 0x0E02: 0.415, 0x0E04: 0.403, 0x0E07: 0.318, 0x0E08: 0.39, 0x0E09: 0.405, 0x0E0A: 0.415, 0x0E0B: 0.431, 0x0E0D: 0.565, 0x0E0E: 0.425, 0x0E0F: 0.425, 0x0E10: 0.372, 0x0E11: 0.492, 0x0E12: 0.551, 0x0E13: 0.576, 0x0E14: 0.405, 0x0E15: 0.405, 0x0E16: 0.391, 0x0E17: 0.438, 0x0E18: 0.358, 0x0E19: 0.433, 0x0E1A: 0.445, 0x0E1B: 0.445, 0x0E1C: 0.414, 0x0E1D: 0.414, 0x0E1E: 0.482, 0x0E1F: 0.482, 0x0E20: 0.425, 0x0E21: 0.417, 0x0E22: 0.386, 0x0E23: 0.329, 0x0E24: 0.391, 0x0E25: 0.399, 0x0E27: 0.379, 0x0E28: 0.403, 0x0E29: 0.461, 0x0E2A: 0.399, 0x0E2B: 0.438, 0x0E2C: 0.468, 0x0E2D: 0.394, 0x0E2E: 0.385, 0x0E2F: 0.38, 0x0E30: 0.34, 0x0E31: 0.0, 0x0E32: 0.336, 0x0E33: 0.336, 0x0E34: 0.0, 0x0E35: 0.0, 0x0E36: 0.0, 0x0E37: 0.0, 0x0E38: 0.0, 0x0E39: 0.0, 0x0E3A: 0.0, 0x0E40: 0.208, 0x0E41: 0.395, 0x0E42: 0.252, 0x0E43: 0.269, 0x0E44: 0.252, 0x0E45: 0.209, 0x0E46: 0.437, 0x0E47: 0.0, 0x0E48: 0.0, 0x0E49: 0.0, 0x0E4A: 0.0, 0x0E4C: 0.0, 0x0E4D: 0.0, 0x0E50: 0.456, 0x0E51: 0.456, 0x0E52: 0.456, 0x0E53: 0.456, 0x0E54: 0.456, 0x0E55: 0.456, 0x0E56: 0.456, 0x0E57: 0.456, 0x0E58: 0.456, 0x0E59: 0.456]

    /// Browallia New regular's widths for U+0021 to U+007E, in ems, from Word
    /// for Windows' print of lab fitedge2/d00 (30 copies of each; means). They are
    /// the bold Cordia table's, not the regular one's (P 0.435 not 0.400, "!" 0.181 not 0.218).
    static let browalliaLatinAdvances: [Double] = [
        0.1810, 0.2322, 0.3626, 0.3626, 0.5798, 0.4352, 0.1244, 0.2175, 0.2175, 0.2542, 0.3817, 0.1810, 0.2175, 0.1810, 0.1810, 0.3626, 0.3626, 0.3626, 0.3626, 0.3626, 0.3626, 0.3626, 0.3626, 0.3626, 0.3626, 0.1810, 0.1810, 0.3817, 0.3817, 0.3817, 0.3626, 0.6622, 0.4352, 0.4352, 0.4714, 0.4714, 0.4352, 0.3987, 0.5073, 0.4714, 0.1810, 0.3256, 0.4352, 0.3626, 0.5434, 0.4714, 0.5073, 0.4352, 0.5073, 0.4714, 0.4352, 0.3987, 0.4714, 0.4352, 0.6160, 0.4352, 0.4352, 0.3987, 0.1810, 0.1810, 0.1810, 0.3064, 0.3626, 0.2175, 0.3626, 0.3626, 0.3256, 0.3626, 0.3626, 0.1810, 0.3626, 0.3626, 0.1446, 0.1446, 0.3256, 0.1446, 0.5434, 0.3626, 0.3626, 0.3626, 0.3626, 0.2175, 0.3256, 0.1810, 0.3626, 0.3256, 0.4714, 0.3256, 0.3256, 0.3256, 0.2180, 0.1689, 0.2180, 0.3817,
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
    /// Browallia New's Thai widths, in ems, regular and bold: the face
    /// Word for Mac draws "TH Sarabun New" in, measured from its print of
    /// zh-6a4fc013 (the median step from each letter to the next, over
    /// 19,801 Thai characters; marks none; "ำ" as "า", which the print
    /// reads as "ํา"). Cordia New, which draws them, is within a few per
    /// cent letter by letter and 0.5% over a line.
    static let browalliaAdvances: [UInt32: Double] = [0x0E01: 0.4199, 0x0E02: 0.4072, 0x0E04: 0.4189, 0x0E06: 0.5039, 0x0E07: 0.3232, 0x0E08: 0.3721, 0x0E09: 0.4341, 0x0E0A: 0.415, 0x0E0B: 0.4463, 0x0E0D: 0.562, 0x0E0E: 0.4619, 0x0E0F: 0.4531, 0x0E10: 0.354, 0x0E11: 0.5352, 0x0E12: 0.5522, 0x0E13: 0.5933, 0x0E14: 0.4209, 0x0E15: 0.4253, 0x0E16: 0.4263, 0x0E17: 0.46, 0x0E18: 0.373, 0x0E19: 0.4463, 0x0E1A: 0.4521, 0x0E1B: 0.4531, 0x0E1C: 0.4272, 0x0E1D: 0.4263, 0x0E1E: 0.4951, 0x0E1F: 0.4951, 0x0E20: 0.4692, 0x0E21: 0.4321, 0x0E22: 0.4082, 0x0E23: 0.3262, 0x0E24: 0.4253, 0x0E25: 0.3882, 0x0E27: 0.3652, 0x0E28: 0.418, 0x0E29: 0.4854, 0x0E2A: 0.397, 0x0E2B: 0.458, 0x0E2C: 0.501, 0x0E2D: 0.395, 0x0E2E: 0.4062, 0x0E2F: 0.3911, 0x0E30: 0.3252, 0x0E31: 0, 0x0E32: 0.334, 0x0E33: 0.3322, 0x0E34: 0, 0x0E35: 0, 0x0E36: 0, 0x0E37: 0, 0x0E38: 0, 0x0E39: 0, 0x0E3A: 0, 0x0E40: 0.2241, 0x0E41: 0.3901, 0x0E42: 0.2783, 0x0E43: 0.2612, 0x0E44: 0.3071, 0x0E46: 0.4712, 0x0E47: 0, 0x0E48: 0, 0x0E49: 0, 0x0E4A: 0, 0x0E4B: 0, 0x0E4C: 0, 0x0E4D: 0, 0x0E4E: 0, 0x0E50: 0.415, 0x0E51: 0.437, 0x0E52: 0.5083, 0x0E53: 0.4873, 0x0E54: 0.4961, 0x0E55: 0.4731, 0x0E56: 0.4224, 0x0E57: 0.5332, 0x0E58: 0.4751, 0x0E59: 0.4434]
    static let browalliaBoldAdvances: [UInt32: Double] = [0x0E01: 0.4541, 0x0E02: 0.4434, 0x0E03: 0.4502, 0x0E04: 0.4722, 0x0E05: 0.4702, 0x0E06: 0.5171, 0x0E07: 0.3433, 0x0E08: 0.4082, 0x0E09: 0.478, 0x0E0A: 0.4409, 0x0E0B: 0.4673, 0x0E0C: 0.5942, 0x0E0D: 0.5942, 0x0E0E: 0.458, 0x0E0F: 0.4644, 0x0E10: 0.4092, 0x0E11: 0.5601, 0x0E12: 0.6221, 0x0E13: 0.644, 0x0E14: 0.4722, 0x0E15: 0.4819, 0x0E16: 0.4463, 0x0E17: 0.4863, 0x0E18: 0.4351, 0x0E19: 0.499, 0x0E1A: 0.4829, 0x0E1B: 0.4839, 0x0E1C: 0.4541, 0x0E1D: 0.4541, 0x0E1E: 0.502, 0x0E1F: 0.5063, 0x0E20: 0.458, 0x0E21: 0.4839, 0x0E22: 0.4419, 0x0E23: 0.3711, 0x0E24: 0.4561, 0x0E25: 0.4443, 0x0E26: 0.4644, 0x0E27: 0.3989, 0x0E28: 0.4712, 0x0E29: 0.5029, 0x0E2A: 0.4419, 0x0E2B: 0.481, 0x0E2C: 0.5073, 0x0E2D: 0.4512, 0x0E2E: 0.4409, 0x0E2F: 0.4199, 0x0E30: 0.3579, 0x0E31: 0, 0x0E32: 0.3643, 0x0E33: 0.373, 0x0E34: 0, 0x0E35: 0, 0x0E36: 0, 0x0E37: 0, 0x0E38: 0, 0x0E39: 0, 0x0E3A: 0, 0x0E3F: 0.4712, 0x0E40: 0.2422, 0x0E41: 0.437, 0x0E42: 0.2622, 0x0E43: 0.3042, 0x0E44: 0.3081, 0x0E45: 0.3643, 0x0E46: 0.5713, 0x0E47: 0, 0x0E48: 0, 0x0E49: 0, 0x0E4A: 0, 0x0E4B: 0, 0x0E4C: 0, 0x0E4D: 0, 0x0E4E: 0, 0x0E4F: 0.5103, 0x0E50: 0.4502, 0x0E51: 0.4663, 0x0E52: 0.5029, 0x0E53: 0.4873, 0x0E54: 0.478, 0x0E55: 0.499, 0x0E56: 0.4863, 0x0E57: 0.561, 0x0E58: 0.4932, 0x0E59: 0.5259, 0x0E5A: 0.5342, 0x0E5B: 0.8159]
    /// Angsana New's own advances in ems (Word for Windows draws the real face): Latin U+0020-U+007E and Thai, read from the hmtx
    /// of the subsets its prints embed (32 prints; Latin letters it never used are estimated from Liberation Sans by the median
    /// ratio). Line: hhea 3854 + 1679 of 4096 = 1.351 em regular (Word's 21.6 pt pitch at 16 pt).
    static let angsanaNewLatin: [UInt32: Double] = [0x20: 0.165, 0x21: 0.2197, 0x22: 0.2695, 0x23: 0.3669, 0x24: 0.3669, 0x25: 0.5498, 0x26: 0.5134, 0x27: 0.1189, 0x28: 0.2197, 0x29: 0.2197, 0x2A: 0.3301, 0x2B: 0.3853, 0x2C: 0.165, 0x2D: 0.2197, 0x2E: 0.165, 0x2F: 0.1833, 0x30: 0.3301, 0x31: 0.3301, 0x32: 0.3301, 0x33: 0.3301, 0x34: 0.3301, 0x35: 0.3301, 0x36: 0.3301, 0x37: 0.3301, 0x38: 0.3301, 0x39: 0.3301, 0x3A: 0.1833, 0x3B: 0.1833, 0x3C: 0.3853, 0x3D: 0.3723, 0x3E: 0.3853, 0x3F: 0.293, 0x40: 0.6079, 0x41: 0.4766, 0x42: 0.4402, 0x43: 0.4402, 0x44: 0.4766, 0x45: 0.4031, 0x46: 0.3672, 0x47: 0.4766, 0x48: 0.4766, 0x49: 0.2197, 0x4A: 0.2568, 0x4B: 0.4766, 0x4C: 0.4031, 0x4D: 0.5869, 0x4E: 0.4766, 0x4F: 0.4766, 0x50: 0.3672, 0x51: 0.5133, 0x52: 0.4402, 0x53: 0.3672, 0x54: 0.4031, 0x55: 0.4766, 0x56: 0.4766, 0x57: 0.623, 0x58: 0.4766, 0x59: 0.4766, 0x5A: 0.4031, 0x5B: 0.1833, 0x5C: 0.1833, 0x5D: 0.1833, 0x5E: 0.3096, 0x5F: 0.3669, 0x60: 0.2197, 0x61: 0.293, 0x62: 0.3301, 0x63: 0.293, 0x64: 0.3301, 0x65: 0.293, 0x66: 0.2197, 0x67: 0.3301, 0x68: 0.3301, 0x69: 0.1833, 0x6A: 0.1833, 0x6B: 0.3301, 0x6C: 0.1833, 0x6D: 0.5134, 0x6E: 0.3301, 0x6F: 0.3301, 0x70: 0.3301, 0x71: 0.3364, 0x72: 0.2197, 0x73: 0.2568, 0x74: 0.1833, 0x75: 0.3301, 0x76: 0.3301, 0x77: 0.4766, 0x78: 0.3301, 0x79: 0.3301, 0x7A: 0.3025, 0x7B: 0.2203, 0x7C: 0.1714, 0x7D: 0.2203, 0x7E: 0.3853]
    static let angsanaNewBoldLatin: [UInt32: Double] = [0x20: 0.165, 0x21: 0.2197, 0x22: 0.3665, 0x23: 0.3669, 0x24: 0.3669, 0x25: 0.5866, 0x26: 0.4764, 0x27: 0.1569, 0x28: 0.2197, 0x29: 0.2197, 0x2A: 0.2567, 0x2B: 0.3853, 0x2C: 0.165, 0x2D: 0.2197, 0x2E: 0.165, 0x2F: 0.1833, 0x30: 0.3301, 0x31: 0.3301, 0x32: 0.3301, 0x33: 0.3301, 0x34: 0.3301, 0x35: 0.3301, 0x36: 0.3301, 0x37: 0.3301, 0x38: 0.3301, 0x39: 0.3301, 0x3A: 0.2197, 0x3B: 0.2197, 0x3C: 0.3853, 0x3D: 0.3853, 0x3E: 0.3853, 0x3F: 0.403, 0x40: 0.6433, 0x41: 0.4766, 0x42: 0.4402, 0x43: 0.4766, 0x44: 0.4766, 0x45: 0.4402, 0x46: 0.4031, 0x47: 0.5133, 0x48: 0.5134, 0x49: 0.2568, 0x4A: 0.367, 0x4B: 0.5134, 0x4C: 0.4031, 0x4D: 0.623, 0x4E: 0.4766, 0x4F: 0.5133, 0x50: 0.4031, 0x51: 0.5133, 0x52: 0.4766, 0x53: 0.3672, 0x54: 0.4402, 0x55: 0.4766, 0x56: 0.4402, 0x57: 0.6229, 0x58: 0.4402, 0x59: 0.4402, 0x5A: 0.4031, 0x5B: 0.2197, 0x5C: 0.1833, 0x5D: 0.2197, 0x5E: 0.3853, 0x5F: 0.3669, 0x60: 0.2197, 0x61: 0.3301, 0x62: 0.3672, 0x63: 0.293, 0x64: 0.3672, 0x65: 0.293, 0x66: 0.2197, 0x67: 0.3301, 0x68: 0.3672, 0x69: 0.1833, 0x6A: 0.167, 0x6B: 0.3343, 0x6C: 0.1833, 0x6D: 0.5498, 0x6E: 0.3672, 0x6F: 0.3301, 0x70: 0.3672, 0x71: 0.3672, 0x72: 0.293, 0x73: 0.2568, 0x74: 0.2197, 0x75: 0.3672, 0x76: 0.3301, 0x77: 0.4766, 0x78: 0.3301, 0x79: 0.3301, 0x7A: 0.3006, 0x7B: 0.2567, 0x7C: 0.1846, 0x7D: 0.2567, 0x7E: 0.3853]
    static let angsanaNewThai: [UInt32: Double] = [0x00A0: 0.165, 0x00B2: 0.1978, 0x2013: 0.3301, 0x2014: 0.6599, 0x2019: 0.2197, 0x201C: 0.293, 0x201D: 0.293, 0x2022: 0.231, 0x2026: 0.6599, 0x0E01: 0.396, 0x0E02: 0.3979, 0x0E04: 0.3979, 0x0E07: 0.3149, 0x0E08: 0.355, 0x0E09: 0.428, 0x0E0A: 0.405, 0x0E0B: 0.4399, 0x0E0D: 0.522, 0x0E0E: 0.4199, 0x0E0F: 0.425, 0x0E10: 0.3779, 0x0E11: 0.5239, 0x0E12: 0.521, 0x0E13: 0.5339, 0x0E14: 0.3999, 0x0E15: 0.4009, 0x0E16: 0.395, 0x0E17: 0.45, 0x0E18: 0.3799, 0x0E19: 0.46, 0x0E1A: 0.45, 0x0E1B: 0.45, 0x0E1C: 0.3911, 0x0E1D: 0.3911, 0x0E1E: 0.4641, 0x0E1F: 0.4641, 0x0E20: 0.4141, 0x0E21: 0.4199, 0x0E22: 0.343, 0x0E23: 0.342, 0x0E24: 0.395, 0x0E25: 0.395, 0x0E27: 0.354, 0x0E28: 0.3899, 0x0E29: 0.4409, 0x0E2A: 0.4399, 0x0E2B: 0.467, 0x0E2D: 0.394, 0x0E2E: 0.3711, 0x0E2F: 0.3999, 0x0E30: 0.3579, 0x0E31: 0.0, 0x0E32: 0.2849, 0x0E34: 0.0, 0x0E35: 0.0, 0x0E36: 0.0, 0x0E37: 0.0, 0x0E38: 0.0, 0x0E39: 0.0, 0x0E40: 0.168, 0x0E41: 0.377, 0x0E42: 0.342, 0x0E43: 0.3059, 0x0E44: 0.344, 0x0E46: 0.425, 0x0E47: 0.0, 0x0E48: 0.0, 0x0E49: 0.0, 0x0E4A: 0.0, 0x0E4B: 0.0, 0x0E4C: 0.0, 0x0E4D: 0.0, 0x0E50: 0.4021, 0x0E51: 0.4041, 0x0E52: 0.5681, 0x0E53: 0.51, 0x0E54: 0.512, 0x0E55: 0.5281, 0x0E56: 0.427, 0x0E57: 0.5359, 0x0E58: 0.502, 0x0E59: 0.408]
    static let angsanaNewBoldThai: [UInt32: Double] = [0x00A0: 0.165, 0x0E01: 0.3831, 0x0E02: 0.415, 0x0E04: 0.4041, 0x0E07: 0.324, 0x0E08: 0.3799, 0x0E09: 0.426, 0x0E0A: 0.4031, 0x0E0D: 0.5449, 0x0E0F: 0.449, 0x0E10: 0.386, 0x0E12: 0.561, 0x0E13: 0.543, 0x0E14: 0.4109, 0x0E15: 0.418, 0x0E16: 0.3979, 0x0E17: 0.447, 0x0E18: 0.3831, 0x0E19: 0.46, 0x0E1A: 0.4419, 0x0E1B: 0.4441, 0x0E1C: 0.4141, 0x0E1D: 0.4141, 0x0E1E: 0.4939, 0x0E1F: 0.4939, 0x0E20: 0.4331, 0x0E21: 0.4351, 0x0E22: 0.3701, 0x0E23: 0.3491, 0x0E24: 0.387, 0x0E25: 0.3831, 0x0E27: 0.3601, 0x0E28: 0.417, 0x0E29: 0.4419, 0x0E2A: 0.4199, 0x0E2B: 0.4619, 0x0E2C: 0.5681, 0x0E2D: 0.3831, 0x0E30: 0.3501, 0x0E31: 0.0, 0x0E32: 0.2839, 0x0E34: 0.0, 0x0E35: 0.0, 0x0E36: 0.0, 0x0E37: 0.0, 0x0E38: 0.0, 0x0E39: 0.0, 0x0E40: 0.1741, 0x0E41: 0.356, 0x0E42: 0.251, 0x0E43: 0.2319, 0x0E44: 0.291, 0x0E47: 0.0, 0x0E48: 0.0, 0x0E49: 0.0, 0x0E4C: 0.0, 0x0E4D: 0.0]
    static let arialBlackAdvances: [Double] = [
        0.3335, 0.333, 0.5, 0.6602, 0.667, 1, 0.8892, 0.2778, 0.3892, 0.3892, 0.5562, 0.6602, 0.333, 0.333, 0.333,
        0.2778, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.667, 0.333, 0.333, 0.6602, 0.6602,
        0.6602, 0.6108, 0.7402, 0.7778, 0.7778, 0.7778, 0.7778, 0.7222, 0.667, 0.833, 0.833, 0.3892, 0.667, 0.833, 0.667,
        0.9438, 0.833, 0.833, 0.7222, 0.833, 0.7778, 0.7222, 0.7222, 0.833, 0.7778, 1, 0.7778, 0.7778, 0.7222, 0.3892,
        0.2778, 0.3892, 0.6602, 0.5, 0.333, 0.667, 0.667, 0.667, 0.667, 0.667, 0.3892, 0.667, 0.667, 0.333, 0.333,
        0.667, 0.333, 1, 0.667, 0.667, 0.667, 0.667, 0.4438, 0.6108, 0.4438, 0.667, 0.6108, 0.9438, 0.667, 0.6108,
        0.5562, 0.3892, 0.2778, 0.3892, 0.6602,
    ]
    /// PMingLiU's ASCII as Word sets it, per em: Times' at 0.94 — the
    /// stand-in's — but for the space, 0.26 and not 0.235 (the /Widths of
    /// Word's embedded PMingLiU in 97 prints of the corpus; every other
    /// character it prints agrees with the stand-in's to the unit).
    private static let pMingLiUAdvances: [Double] = [
        0.260, 0.313, 0.384, 0.470, 0.470, 0.782, 0.731, 0.169, 0.313, 0.313, 0.470, 0.530, 0.235, 0.313, 0.235,
        0.261, 0.470, 0.470, 0.470, 0.470, 0.470, 0.470, 0.470, 0.470, 0.470, 0.470, 0.261, 0.261, 0.530, 0.530,
        0.530, 0.417, 0.866, 0.678, 0.627, 0.627, 0.678, 0.574, 0.522, 0.678, 0.678, 0.313, 0.365, 0.678, 0.574,
        0.835, 0.678, 0.678, 0.522, 0.678, 0.627, 0.522, 0.574, 0.678, 0.678, 0.887, 0.678, 0.678, 0.574, 0.313,
        0.261, 0.313, 0.441, 0.470, 0.313, 0.417, 0.470, 0.417, 0.470, 0.417, 0.313, 0.470, 0.470, 0.261, 0.261,
        0.470, 0.261, 0.731, 0.470, 0.470, 0.470, 0.470, 0.313, 0.365, 0.261, 0.470, 0.470, 0.678, 0.470, 0.470,
        0.417, 0.451, 0.188, 0.451, 0.508,
    ]
    // Yu Mincho's Latin widths, U+0020 to U+007E in ems: medians of the glyph steps in the word-win prints that use it
    // (20 batch B documents; ! # $ * ; < > @ J Q X Y Z \ ` { } ~ no print used are estimates).
    private static let yuMinchoAdvances: [Double] = [
        0.260, 0.270, 0.395, 0.540, 0.540, 0.907, 0.739, 0.226, 0.431, 0.431, 0.500, 0.706, 0.273, 0.398, 0.273,
        0.466, 0.542, 0.542, 0.543, 0.544, 0.542, 0.544, 0.542, 0.542, 0.544, 0.542, 0.283, 0.283, 0.705, 0.705,
        0.705, 0.522, 0.900, 0.707, 0.692, 0.730, 0.830, 0.636, 0.603, 0.807, 0.819, 0.354, 0.500, 0.716, 0.639,
        0.957, 0.806, 0.851, 0.602, 0.850, 0.682, 0.559, 0.726, 0.773, 0.648, 0.949, 0.700, 0.700, 0.650, 0.431,
        0.466, 0.430, 0.535, 0.500, 0.300, 0.479, 0.557, 0.463, 0.557, 0.490, 0.330, 0.524, 0.566, 0.287, 0.287,
        0.510, 0.272, 0.851, 0.581, 0.535, 0.568, 0.558, 0.388, 0.409, 0.341, 0.567, 0.488, 0.716, 0.476, 0.487,
        0.464, 0.430, 0.388, 0.430, 0.705,
    ]
    // Malgun Gothic's own Latin widths, U+0020 to U+007E in ems: the hmtx of the subsets Word for Windows
    // embeds in word-win prints (majority of ~170 prints; ^ ` and a few bold glyphs no print used are estimates).
    /// Batang's and Dotum's Latin advances, space to ~, read from the hmtx of the subsets embedded in Word for Windows' prints
    /// (dx2 and new-b ko docs). Letters no subset held take Arial's width.
    private static let batangSymbolAdvances: [UInt32: Double] = [
        0x2013: 0.5000, 0x2015: 0.6875, 0x2017: 0.5000, 0x201A: 0.2920, 0x201B: 0.2920, 0x201E: 0.5000, 0x2020:
        0.5938, 0x2021: 0.5869, 0x2022: 0.3750, 0x2032: 0.2646, 0x2033: 0.3916, 0x2039: 0.3311, 0x203A: 0.3311,
        0x203C: 0.6250, 0x203E: 0.5000, 0x2044: 0.5000, 0x207F: 0.4326, 0x20A3: 0.6250, 0x20A4: 0.5488, 0x20A7:
        0.6582, 0x20AC: 0.6738, 0x2105: 0.8877, 0x2113: 0.4189, 0x2126: 0.7188, 0x212E: 0.6729, 0x215B: 0.5625,
        0x215C: 0.5625, 0x215D: 0.5303, 0x215E: 0.5625, 0x2191: 0.7500, 0x2193: 0.7500, 0x2195: 0.7500, 0x21A8:
        0.7500, 0x2202: 0.5000, 0x2206: 0.6133, 0x220F: 0.7002, 0x2211: 0.8125, 0x2212: 0.8125, 0x2215: 0.3330,
        0x2219: 0.2646, 0x221A: 0.5488, 0x221E: 0.9111, 0x221F: 0.9512, 0x2229: 0.6680, 0x222B: 0.4854, 0x2248:
        0.7676, 0x2260: 0.8125, 0x2261: 0.8125, 0x2264: 0.8125, 0x2265: 0.8125, 0x2302: 0.5996, 0x2310: 0.8076,
        0x2320: 0.6250, 0x2321: 0.5996, 0x2590: 0.5000, 0x25A0: 0.8896, 0x25A1: 0.8896, 0x25AA: 0.3750, 0x25AB:
        0.3750, 0x25B2: 0.9141, 0x25BA: 0.7500, 0x25BC: 0.9141, 0x25C4: 0.7500, 0x25CA: 0.7744, 0x25E6: 0.3750,
        0x263C: 0.9160, 0x2640: 0.7295, 0x2642: 0.6240, 0x2660: 0.7500, 0x2663: 0.8438, 0x2665: 0.7930, 0x2666:
        0.7744, 0x266A: 0.6875, 0x266B: 0.7627
    ]
    private static let batangAdvances: [Double] = [
        0.333, 0.312, 0.417, 0.556, 0.556, 0.855, 0.667, 0.250, 0.377, 0.377, 0.500, 0.833, 0.292, 0.625, 0.292,
        0.375, 0.596, 0.596, 0.596, 0.596, 0.596, 0.596, 0.596, 0.596, 0.596, 0.596, 0.333, 0.278, 0.625, 0.625,
        0.625, 0.500, 1.000, 0.736, 0.708, 0.708, 0.734, 0.672, 0.645, 0.740, 0.766, 0.326, 0.500, 0.746, 0.639,
        0.895, 0.722, 0.736, 0.654, 0.738, 0.672, 0.625, 0.750, 0.775, 0.750, 0.944, 0.667, 0.667, 0.611, 0.500,
        0.278, 0.500, 0.469, 0.500, 0.333, 0.542, 0.576, 0.542, 0.576, 0.576, 0.365, 0.583, 0.574, 0.289, 0.222,
        0.500, 0.292, 0.846, 0.570, 0.583, 0.574, 0.556, 0.439, 0.520, 0.359, 0.566, 0.572, 0.809, 0.605, 0.588,
        0.500, 0.334, 0.260, 0.334, 0.750,
    ]
    private static let dotumAdvances: [Double] = [
        0.334, 0.334, 0.417, 0.556, 0.556, 0.889, 0.667, 0.291, 0.375, 0.375, 0.389, 0.584, 0.375, 0.590, 0.375,
        0.417, 0.583, 0.583, 0.583, 0.583, 0.583, 0.583, 0.556, 0.583, 0.556, 0.583, 0.340, 0.278, 0.625, 0.584,
        0.625, 0.583, 1.000, 0.667, 0.667, 0.721, 0.725, 0.629, 0.611, 0.778, 0.722, 0.278, 0.500, 0.667, 0.556,
        0.809, 0.722, 0.778, 0.667, 0.778, 0.722, 0.639, 0.611, 0.722, 0.667, 0.944, 0.667, 0.667, 0.611, 0.278,
        0.278, 0.278, 0.469, 0.556, 0.333, 0.583, 0.600, 0.559, 0.604, 0.559, 0.344, 0.598, 0.561, 0.229, 0.222,
        0.500, 0.230, 0.917, 0.568, 0.600, 0.602, 0.556, 0.320, 0.516, 0.312, 0.555, 0.475, 0.725, 0.500, 0.480,
        0.482, 0.334, 0.260, 0.334, 0.584,
    ]
    /// Gulim's Latin advances, space to ~, read from the hmtx of the Gulim subsets embedded in Word for Windows' prints
    /// (kor-z19176375, -z20746312, -z23132029). # $ & ' @ \ ^ ` { | } were not in any subset: Arial's widths stand in.
    private static let gulimAdvances: [Double] = [
        0.333, 0.333, 0.375, 0.556, 0.556, 0.875, 0.667, 0.191, 0.375, 0.375, 0.500, 0.625, 0.334, 0.625, 0.334,
        0.417, 0.574, 0.574, 0.574, 0.574, 0.574, 0.574, 0.574, 0.574, 0.574, 0.574, 0.334, 0.334, 0.625, 0.625,
        0.625, 0.542, 1.015, 0.646, 0.677, 0.718, 0.722, 0.625, 0.596, 0.770, 0.730, 0.270, 0.500, 0.635, 0.543,
        0.812, 0.699, 0.770, 0.637, 0.773, 0.666, 0.633, 0.582, 0.711, 0.600, 0.895, 0.625, 0.625, 0.625, 0.500,
        0.278, 0.500, 0.469, 0.500, 0.333, 0.562, 0.605, 0.572, 0.605, 0.567, 0.342, 0.605, 0.571, 0.241, 0.241,
        0.500, 0.231, 0.861, 0.580, 0.605, 0.605, 0.605, 0.333, 0.525, 0.313, 0.570, 0.500, 0.750, 0.500, 0.500,
        0.500, 0.334, 0.260, 0.334, 0.792,
    ]
    /// GulimChe is fixed-pitch: every Latin character is half an em.
    private static let gulimCheAdvances: [Double] = Array(repeating: 0.5, count: 95)
    /// NanumGothic's Latin, U+0020 to U+007E, read from the subsets in Word's prints (unread glyphs: Liberation Sans x 1.09).
    private static let nanumGothicAdvances: [Double] = [0.28, 0.424, 0.43, 0.606, 0.606, 0.969, 0.727, 0.208, 0.363, 0.363, 0.424, 0.637, 0.303, 0.363, 0.303, 0.303, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.303, 0.303, 0.637, 0.637, 0.637, 0.606, 1.107, 0.727, 0.727, 0.787, 0.787, 0.727, 0.666, 0.848, 0.787, 0.303, 0.545, 0.727, 0.606, 0.969, 0.787, 0.848, 0.727, 0.848, 0.787, 0.727, 0.666, 0.787, 0.727, 1.029, 0.727, 0.727, 0.666, 0.303, 0.303, 0.303, 0.512, 0.606, 0.363, 0.606, 0.606, 0.545, 0.606, 0.606, 0.303, 0.606, 0.606, 0.242, 0.242, 0.545, 0.242, 0.908, 0.606, 0.606, 0.606, 0.606, 0.363, 0.545, 0.303, 0.606, 0.545, 0.787, 0.545, 0.545, 0.545, 0.364, 0.283, 0.364, 0.637]
    private static let nanumGothicBoldAdvances: [Double] = [0.28, 0.424, 0.43, 0.606, 0.606, 0.969, 0.727, 0.208, 0.363, 0.363, 0.424, 0.636, 0.303, 0.363, 0.303, 0.375, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.606, 0.303, 0.303, 0.636, 0.636, 0.636, 0.606, 1.106, 0.727, 0.727, 0.672, 0.787, 0.576, 0.666, 0.848, 0.787, 0.303, 0.545, 0.727, 0.606, 0.969, 0.727, 0.848, 0.577, 0.848, 0.787, 0.545, 0.545, 0.787, 0.727, 1.029, 0.727, 0.727, 0.666, 0.303, 0.303, 0.303, 0.511, 0.606, 0.363, 0.545, 0.606, 0.545, 0.606, 0.545, 0.303, 0.606, 0.606, 0.242, 0.242, 0.545, 0.242, 0.908, 0.606, 0.606, 0.606, 0.606, 0.363, 0.545, 0.363, 0.606, 0.545, 0.787, 0.545, 0.545, 0.545, 0.364, 0.283, 0.364, 0.636]

    private static let malgunAdvances: [Double] = [
        0.3516, 0.2891, 0.3950, 0.6064, 0.5508, 0.8364, 0.8179, 0.2319, 0.3047, 0.3047, 0.4248, 0.7007, 0.2188, 0.4102, 0.2188,
        0.3960, 0.5508, 0.5508, 0.5508, 0.5508, 0.5508, 0.5508, 0.5508, 0.5508, 0.5508, 0.5508, 0.2188, 0.2188, 0.7007, 0.7007,
        0.7007, 0.4600, 0.9795, 0.6582, 0.5835, 0.6348, 0.7173, 0.5171, 0.4985, 0.7017, 0.7246, 0.2700, 0.3599, 0.5903, 0.4800,
        0.9170, 0.7651, 0.7734, 0.5708, 0.7734, 0.6099, 0.5430, 0.5337, 0.7026, 0.6343, 0.9536, 0.6011, 0.5635, 0.5825, 0.3047,
        0.7637, 0.3047, 0.5000, 0.4258, 0.3000, 0.5200, 0.6006, 0.4727, 0.6021, 0.5352, 0.3164, 0.6021, 0.5786, 0.2461, 0.2461,
        0.5059, 0.2461, 0.8799, 0.5781, 0.5991, 0.6006, 0.6021, 0.3535, 0.4331, 0.3447, 0.5781, 0.4873, 0.7363, 0.4648, 0.4927,
        0.4619, 0.3047, 0.2393, 0.3047, 0.7007
    ]
    private static let malgunBoldAdvances: [Double] = [
        0.3516, 0.3232, 0.4761, 0.6079, 0.5796, 0.8755, 0.8569, 0.2817, 0.3579, 0.3579, 0.4561, 0.7192, 0.2617, 0.4136, 0.2617,
        0.4390, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.5796, 0.2617, 0.2617, 0.7192, 0.7192,
        0.7192, 0.4521, 1.0000, 0.7036, 0.6372, 0.6387, 0.7456, 0.5386, 0.5244, 0.7222, 0.7695, 0.3101, 0.4307, 0.6450, 0.5122,
        0.9644, 0.7979, 0.7764, 0.6147, 0.7764, 0.6538, 0.5659, 0.5825, 0.7310, 0.6709, 1.0098, 0.6800, 0.6064, 0.6113, 0.3579,
        0.7637, 0.3579, 0.6, 0.4258, 0.5000, 0.5430, 0.6265, 0.4873, 0.6260, 0.5498, 0.3726, 0.6260, 0.6069, 0.2744, 0.2793,
        0.5552, 0.2744, 0.9233, 0.6084, 0.6196, 0.6265, 0.6260, 0.3936, 0.4619, 0.3843, 0.6084, 0.5366, 0.7954, 0.5386, 0.5356,
        0.4834, 0.3700, 0.2800, 0.3700, 0.7192
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
    // JhengHei UI Light's, where its print gives them: zh-167ee06c's
    // embedded subset has the space, "(", ")", "-", "." and the digits
    // but 7 and 9 (taken as the rest's 0.558; its "1" is 0.387 and its
    // "4" 0.575). The rest are JhengHei's. Word for Mac emboldens the
    // Light, so its bold is these and the face's spread.
    private static let jhengHeiUILightAdvances: [Double] = [
        0.296, 0.3042, 0.416, 0.6382, 0.5796, 0.8804, 0.8608, 0.2441, 0.306, 0.306, 0.4473, 0.7373, 0.2305, 0.43, 0.239,
        0.417, 0.558, 0.387, 0.558, 0.558, 0.575, 0.558, 0.558, 0.558, 0.558, 0.558, 0.2305, 0.2305, 0.7373, 0.7373,
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

    /// (No longer an em a glyph for an embedded SimSun with bitmaps: that
    /// was Word for Mac's fault since 2026-10-18 — it draws any embedded
    /// face as blank one-em glyphs — and the user chose Word's real
    /// behaviour, Word for Windows' print, which sets the face's own
    /// widths. The names and bitmaps are still recorded for whoever needs
    /// them.)
    private static func eastAsianFace(_ family: String, ignoringEmbedding: Bool = false) -> EastAsianFace {
        eastAsianFaceAsNamed(family, ignoringEmbedding: ignoringEmbedding)
    }

    private static func eastAsianFaceAsNamed(_ family: String, ignoringEmbedding: Bool = false) -> EastAsianFace {
        let n = family.trimmingWhitespace().lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { faceHas(n, $0) } }
        if wordOnWindows, !isEmbedded(family), let fallback = windowsMissingFallback(family) { switch fallback {
            case "mincho": return windowsMincho
            case "batang":
                var face = eastAsianFace("Batang"); face.malgunSymbols = true
                // (Its "·" is Batang's own, 0.333 em, read from lab tcfit1's print of HY헤드라인M.)
                face.otherAdvances = [0x2018: 0.228, 0x2019: 0.228, 0x201C: 0.38, 0x201D: 0.38, 0xB7: 0.333]
                return face
            case "malgun": return eastAsianFace("맑은 고딕")
            default: return eastAsianFace("Microsoft JhengHei")
            } }
        // (The faces Word for Windows takes an embedded 仿宋_GB2312's missing
        // characters from (`windowsSubsetFallback`), each on its own line,
        // its win ascent and descent at Word's 1.3, the extra split evenly
        // about them: MS Gothic's .859 + .141, Yu Gothic's .985 + .302.)
        // Mac Word uses MS Gothic's own line too: five 12pt lines of
        // 田 in a fresh print step exactly 15.6pt, not YaHei's 20.58.
        // Treating the explicit name as a missing face made the first
        // two mixed-font lines of zh-8d72961c too tall.
        // Gulim and GulimChe (Word for Windows prints 12pt Korean text in them
        // on a 15.6pt step, 1.3 em, MS Gothic's line; ours drew YaHei's
        // 1.715 em: kor-z19176375-004d7a, 35 pages in Word, 40 here).
        // (Dotum and Batang too, whole names: the 11pt single lines of dx2's ko docs step 1.304 em in Dotum
        // and 1.30 in Batang in Word's print where ours drew 1.72, and their pages doubled.)
        if wordOnWindows, n == "dotum" || n == "돋움" || n == "batang" || n == "바탕" {
            var face = EastAsianFace(height: 1.3, latin: sans, latinScale: 1.0, fakeBold: true, baseline: 0.15 + 0.859375)
            RuleTrace.hit("batang-dotum-own-latin-widths")
            face.latinAdvances = (n == "batang" || n == "바탕") ? batangAdvances : dotumAdvances
            face.latinBoldAdvances = face.latinAdvances
            // (Word's own Dotum and Batang set ‘ ’ at 0.292 em, and Batang's “ ” at 0.5, read from the hmtx of the subsets embedded in
            // its prints; dbd695fe's Dotum "(이하 ‘표준’)" stood 0.6 pt narrow at each quote at Malgun's 0.228. A Korean face Word lacks
            // is drawn in Batang with its quotes in Malgun Gothic, at 0.228 and 0.38: 6a68f6ca's "(이하 ‘작가’)" -- the `case "batang"` fallback.)
            face.otherAdvances = [0x2018: 0.292, 0x2019: 0.292, 0x201C: 0.5, 0x201D: 0.5]
            if n == "batang" || n == "바탕" { face.otherAdvances?[0x2027] = 1.0 }
            if n == "batang" || n == "바탕" { face.otherAdvances = batangSymbolAdvances.merging(face.otherAdvances ?? [:]) { $1 } }   // (Batang's own symbol advances, /data/corpus-cache/metrics/ko/Batang_Regular.tsv: ♣ 0.8438)   // (U+2027 from PMingLiU, lab u2027)
            return face
        }
        // (NanumGothic: Latin its own, Hangul 0.94 em (key U+AC00 of otherAdvances carries it for the Hangul rule),
        // line 1.3 x (885+198)/1000 from its OS/2 metrics; 7416edcd's 8 pt lines pitch 12.95 pt in Word's print.)
        if wordOnWindows, has("nanumgothic", "나눔고딕") {
            RuleTrace.hit("nanum-gothic-own-widths")
            // (Regular is taller than bold in Word's print: 7416edcd's empty 9 pt lines pitch 16.85 pt at 1.15, 1.628 em.)
            var face = EastAsianFace(height: 1.628, latin: sans, latinScale: 1.0, fakeBold: true, baseline: 0.1625 + 0.885 + 0.11)
            face.boldHeight = 1.408
            face.boldBaseline = 0.1625 + 0.885
            face.latinAdvances = nanumGothicAdvances
            face.latinBoldAdvances = nanumGothicBoldAdvances
            face.otherAdvances = [0xAC00: 0.94]
            return face
        }
        // (BatangChe and DotumChe: the same square line as GulimChe (hhea 879/145 of 1024, Word's 1.3) and Latin
        // fixed at half an em, read from the subsets in Word's prints of 7416edcd, 07eecf7a and dx4j-7acb626022.)
        if wordOnWindows, has("batangche", "바탕체", "dotumche", "돋움체") {
            RuleTrace.hit("che-own-latin-widths")
            var face = EastAsianFace(height: 1.3, latin: sans, latinScale: 1.0, fakeBold: true, baseline: 0.15 + 0.859375)
            face.latinAdvances = gulimCheAdvances
            face.latinBoldAdvances = gulimCheAdvances
            return face
        }
        if wordOnWindows || wordOnMac, has("ms gothic", "ｍｓ ゴシック", "gulim", "굴림") {
            var face = EastAsianFace(height: 1.3, latin: sans, latinScale: 1.0, fakeBold: true, baseline: 0.15 + 0.859375)
            if wordOnWindows, has("ms gothic", "ｍｓ ゴシック") {
                // (MS Gothic is monospaced: its Latin is fixed at half an em, as MS Mincho's.)
                face.latinAdvances = gulimCheAdvances
                face.latinBoldAdvances = gulimCheAdvances
                face.squareSymbols = true  // (※ and the like stay a full em: jpn-g1-5d7ee6's superscript ※１)
            }
            if wordOnWindows, has("gulim", "굴림") {
                // (Gulim's Latin is its own proportional design, GulimChe's fixed at half an em; Arial's widths were
                // used for both. Word for Windows' prints of kor-z19176375 and two more give each its table.)
                RuleTrace.hit("gulim-own-latin-widths")
                let che = has("gulimche", "굴림체")
                // (Gulim's single line is 1332/1024 em, not 1.3: 43 lines in Word's print of 004d7a step 15.6105 pt, 24 in 16de187a
                // 1.3006 em, so a page drifts 0.4 pt per 40 lines against 15.6.)
                face.height = 1332.0 / 1024
                face.latinAdvances = che ? gulimCheAdvances : gulimAdvances
                face.latinBoldAdvances = face.latinAdvances
                // (Curly quotes: Word's print of kor-z19176375-004d7a steps 6 pt at each double and 4 pt at each single
                // quote in 12 pt Gulim, 0.5 and 1/3 em; they were drawn a full em or a third of it.)
                if !che { face.otherAdvances = [0x2018: 1.0 / 3, 0x2019: 1.0 / 3, 0x201C: 0.5, 0x201D: 0.5, 0x2027: 0.5] }   // (U+2027 from MS Gothic, lab u2027)
            }
            return face
        }
        // (MS PGothic, MS Mincho and MS PMincho are Word for Windows' own faces,
        // each MS Gothic's square line, hhea .859 + .141 at Word's 1.3: jpn-z22855378's
        // 11pt 1.5-spaced lines on an 18pt line grid are 27.0 apart in word-win's print,
        // one pitch and a half, where YaHei's 1.715 em made them two pitches, 36.)
        if wordOnWindows, has("ms pgothic", "ｍｓ ｐゴシック", "ms mincho", "ｍｓ 明朝", "ms pmincho", "ｍｓ ｐ明朝", "hgskyokashotai", "hgpkyokashotai", "hgkyokashotai", "ブーケ") {
            RuleTrace.hit("ms-japanese-face-square-line")
            // (HG Kyokasho-tai is not on Word's machine: a91d8fed's runs print in MS Mincho, the document's East Asian default.)
            var ms = EastAsianFace(height: wordEastAsianLine(units: 256, upem: 256), latin: has("mincho", "明朝", "kyokashotai", "ブーケ") ? serif : sans, latinScale: 1.0, fakeBold: true, baseline: 0.15 + 0.859375 - (1.3 - wordEastAsianLine(units: 256, upem: 256)) / 2)
            // (Its Latin is MS Mincho's, fixed at half an em: a91d8fed's "ex." steps 5.3 pt a letter at 10.5 pt.)
            if has("kyokashotai", "ブーケ") || (has("ms mincho", "ｍｓ 明朝") && !has("ms pmincho", "ｍｓ ｐ明朝")) { ms.latinAdvances = gulimCheAdvances; ms.latinBoldAdvances = gulimCheAdvances; ms.squareSymbols = true }
            // (MS PGothic is proportional: its kana, brackets and digits step narrower than an em, read from
            // the hmtx of the subsets embedded in Word's prints; cab6d785's 9 pt cell holds "「教科書を使っ" on a
            // line, where full-width ones broke it a character sooner and the document ran a page long.)
            if has("ms pgothic", "ｍｓ ｐゴシック") { ms.otherAdvances = [0x3001: 0.6641, 0x3002: 0.6641, 0x300C: 0.5, 0x300D: 0.5, 0x3010: 0.5, 0x3011: 0.5, 0x3042: 0.9414, 0x3044: 0.9453, 0x3046: 0.707, 0x3048: 0.9023, 0x304A: 0.9453, 0x304D: 0.8438, 0x304F: 0.5898, 0x3050: 0.8164, 0x3051: 0.9453, 0x3052: 0.9805, 0x3053: 0.7969, 0x3054: 0.8945, 0x3055: 0.7656, 0x3057: 0.7656, 0x3058: 0.7656, 0x3059: 0.9609, 0x305A: 0.9805, 0x305D: 0.9219, 0x305F: 0.9219, 0x3060: 0.9219, 0x3061: 0.8633, 0x3063: 0.8047, 0x3064: 0.9531, 0x3065: 0.957, 0x3066: 0.9023, 0x3067: 0.9023, 0x3068: 0.7656, 0x3069: 0.8828, 0x306A: 0.9023, 0x306B: 0.9414, 0x3072: 0.9609, 0x3073: 0.9609, 0x307E: 0.8906, 0x3080: 0.9805, 0x3081: 0.9805, 0x3082: 0.8047, 0x3086: 0.9805, 0x3087: 0.7266, 0x3088: 0.8633, 0x3089: 0.8047, 0x308A: 0.7461, 0x308B: 0.8633, 0x308D: 0.8438, 0x3092: 0.8555, 0x3093: 0.9609, 0x30A1: 0.7578, 0x30A3: 0.6523, 0x30A4: 0.8242, 0x30A8: 0.8945, 0x30A9: 0.8086, 0x30AA: 0.9336, 0x30AB: 0.8242, 0x30AC: 0.9219, 0x30AD: 0.9609, 0x30AF: 0.8047, 0x30B1: 0.9297, 0x30B7: 0.8984, 0x30B8: 0.8984, 0x30B9: 0.9023, 0x30BB: 0.9141, 0x30BF: 0.7656, 0x30C0: 0.9219, 0x30C3: 0.7344, 0x30C4: 0.8633, 0x30C6: 0.8867, 0x30C7: 0.9609, 0x30C8: 0.6484, 0x30C9: 0.707, 0x30D5: 0.8047, 0x30D6: 0.8828, 0x30D7: 0.8828, 0x30DA: 0.9453, 0x30DC: 0.9531, 0x30DD: 0.9531, 0x30DE: 0.9023, 0x30E0: 0.9766, 0x30E5: 0.8125, 0x30E7: 0.6289, 0x30E9: 0.8086, 0x30EA: 0.7461, 0x30EC: 0.8516, 0x30EF: 0.9414, 0x30F3: 0.8633, 0x30FB: 0.5, 0x30FC: 0.9609, 0xFF08: 0.5, 0xFF09: 0.5, 0xFF0E: 0.6641, 0xFF10: 0.6836, 0xFF11: 0.6836, 0xFF12: 0.6836, 0xFF13: 0.6836, 0xFF14: 0.6836, 0xFF15: 0.6836, 0xFF16: 0.6836, 0xFF17: 0.6836, 0xFF18: 0.6836, 0xFF19: 0.6836, 0xFF1A: 0.5, 0xFF30: 0.7109] }
            // (MS PMincho likewise: the widths in the subsets of Word's prints; MS Mincho keeps its em.)
            if has("ms pmincho", "ｍｓ ｐ明朝") { ms.otherAdvances = [0x3001: 0.6641, 0x3002: 0.6641, 0x3008: 0.5, 0x3009: 0.5, 0x300C: 0.5, 0x300D: 0.5, 0x300E: 0.5, 0x300F: 0.5, 0x3010: 0.5, 0x3011: 0.5, 0x3014: 0.5, 0x3015: 0.5, 0x3042: 0.8828, 0x3044: 0.9531, 0x3046: 0.6172, 0x3048: 0.8984, 0x304B: 0.9453, 0x304C: 0.9492, 0x304D: 0.793, 0x304F: 0.6445, 0x3051: 0.9141, 0x3052: 0.9805, 0x3053: 0.7539, 0x3054: 0.8672, 0x3055: 0.7539, 0x3056: 0.8828, 0x3057: 0.7773, 0x3058: 0.7773, 0x305D: 0.9219, 0x305F: 0.9062, 0x3060: 0.9492, 0x3061: 0.9023, 0x3063: 0.8555, 0x3066: 0.9023, 0x3067: 0.9414, 0x3068: 0.7031, 0x3069: 0.8438, 0x306A: 0.9023, 0x306B: 0.9492, 0x306E: 0.9492, 0x306F: 0.9688, 0x307E: 0.8242, 0x3081: 0.9531, 0x3082: 0.7578, 0x3086: 0.9336, 0x3088: 0.7852, 0x3089: 0.7656, 0x308A: 0.6406, 0x308B: 0.793, 0x308C: 0.9844, 0x308F: 0.9531, 0x3092: 0.8555, 0x3093: 0.9453, 0x30A4: 0.7773, 0x30A6: 0.8008, 0x30A8: 0.9414, 0x30B5: 0.9531, 0x30C1: 0.9648, 0x30C8: 0.5898, 0x30CA: 0.9727, 0x30CE: 0.6992, 0x30E5: 0.793, 0x30F3: 0.8633, 0x30FB: 0.5, 0xFF08: 0.5, 0xFF09: 0.5, 0xFF0C: 0.6641, 0xFF21: 0.8047, 0xFF23: 0.7617, 0xFF29: 0.3594, 0xFF2A: 0.3594] }
            return ms
        }
        // HG Maru Gothic M-PRO sets single lines 1.3 em apart in Word's print (jpn-g5-b79900: 11 pt
        // lines step 14.3 where the generic CJK line gave 18.9, and the 2-page document ran to 1).
        // (HG Soei Kakugothic UB, S and P: hhea 1760+288 of 2048 in the subsets of 4fbb6e32's print, the same 1.3 em single line; ours ran 1.71 em and pushed the page's stacked empty paragraphs down.)
        if wordOnWindows, has("hg丸", "hgmarugothic", "創英角ｺﾞｼｯｸ", "創英角ゴシック", "soeikakugothic") {
            var hg = EastAsianFace(height: 1.3, latin: sans, latinScale: 1.0, fakeBold: true, baseline: 0.15 + 0.859375)
            // (HG Soei Kakugothic UB, P: proportional. Its kana, punctuation and fullwidth forms step narrower than an
            // em, from the Windows box's cmap advances (dx2 4fbb6e32: "つまずいているポイントを" is 12 characters in
            // Word's 194 pt line, where em-wide kana broke it after 10). The S face is full width throughout.)
            if has("hgp創英角", "hgpsoei") { hg.otherAdvances = [0x2010: 0.5, 0x2013: 0.5, 0x2018: 0.5, 0x2019: 0.5, 0x201C: 0.5, 0x201D: 0.5, 0x2020: 0.5, 0x2021: 0.5, 0x3000: 0.6641, 0x3001: 0.6641, 0x3002: 0.6641, 0x3008: 0.5, 0x3009: 0.5, 0x300A: 0.5859, 0x300B: 0.5859, 0x300C: 0.5, 0x300D: 0.5, 0x300E: 0.5, 0x300F: 0.5, 0x3010: 0.5, 0x3011: 0.5, 0x3014: 0.5, 0x3015: 0.5, 0x3016: 0.5781, 0x3017: 0.5781, 0x3018: 0.5781, 0x3019: 0.5781, 0x3041: 0.6953, 0x3042: 0.8984, 0x3043: 0.7188, 0x3044: 0.9297, 0x3045: 0.6094, 0x3046: 0.7891, 0x3047: 0.6992, 0x3048: 0.8359, 0x3049: 0.7109, 0x304A: 0.9023, 0x304B: 0.9453, 0x304C: 0.9414, 0x304D: 0.8047, 0x304E: 0.8789, 0x304F: 0.668, 0x3050: 0.8125, 0x3051: 0.8906, 0x3052: 0.9492, 0x3053: 0.8203, 0x3054: 0.8789, 0x3055: 0.8164, 0x3056: 0.918, 0x3057: 0.7812, 0x3058: 0.7773, 0x3059: 0.8711, 0x305A: 0.8945, 0x305B: 0.9219, 0x305C: 0.9414, 0x305D: 0.8672, 0x305E: 0.9062, 0x305F: 0.9023, 0x3060: 0.9023, 0x3061: 0.8398, 0x3062: 0.9102, 0x3063: 0.7617, 0x3064: 0.9297, 0x3065: 0.9375, 0x3066: 0.8711, 0x3067: 0.8828, 0x3068: 0.7969, 0x3069: 0.8086, 0x306A: 0.8828, 0x306B: 0.9219, 0x306C: 0.9258, 0x306D: 0.9258, 0x306E: 0.9258, 0x306F: 0.9258, 0x3070: 0.9219, 0x3071: 0.9219, 0x3072: 0.9023, 0x3073: 0.9102, 0x3074: 0.918, 0x3075: 0.9297, 0x3076: 0.9297, 0x3077: 0.9297, 0x3078: 0.9375, 0x3079: 0.9688, 0x307A: 0.9336, 0x307B: 0.9297, 0x307C: 0.957, 0x307D: 0.9375, 0x307E: 0.8203, 0x307F: 0.9805, 0x3080: 0.8516, 0x3081: 0.9141, 0x3082: 0.8477, 0x3083: 0.7461, 0x3084: 0.9141, 0x3085: 0.7148, 0x3086: 0.9102, 0x3087: 0.7422, 0x3088: 0.8633, 0x3089: 0.832, 0x308A: 0.7266, 0x308B: 0.8438, 0x308C: 0.918, 0x308D: 0.8633, 0x308E: 0.75, 0x308F: 0.918, 0x3090: 0.9102, 0x3091: 0.8477, 0x3092: 0.8164, 0x3093: 0.8828, 0x3095: 0.75, 0x3096: 0.7109, 0x309B: 0.5, 0x309C: 0.5, 0x309D: 0.582, 0x309E: 0.6484, 0x30A1: 0.7109, 0x30A2: 0.8828, 0x30A3: 0.6016, 0x30A4: 0.7852, 0x30A5: 0.6719, 0x30A6: 0.8672, 0x30A7: 0.7344, 0x30A8: 0.8867, 0x30A9: 0.6406, 0x30AA: 0.8242, 0x30AB: 0.8203, 0x30AC: 0.8398, 0x30AD: 0.8828, 0x30AE: 0.9102, 0x30AF: 0.8281, 0x30B0: 0.8477, 0x30B1: 0.8711, 0x30B2: 0.9062, 0x30B3: 0.793, 0x30B4: 0.8398, 0x30B5: 0.8672, 0x30B6: 0.8984, 0x30B7: 0.8711, 0x30B8: 0.8711, 0x30B9: 0.8711, 0x30BA: 0.9258, 0x30BB: 0.8828, 0x30BC: 0.8828, 0x30BD: 0.8398, 0x30BE: 0.9141, 0x30BF: 0.8086, 0x30C0: 0.8398, 0x30C1: 0.8555, 0x30C2: 0.8906, 0x30C3: 0.7617, 0x30C4: 0.8789, 0x30C5: 0.9102, 0x30C6: 0.832, 0x30C7: 0.9023, 0x30C8: 0.6211, 0x30C9: 0.6562, 0x30CA: 0.8555, 0x30CB: 0.8828, 0x30CC: 0.8281, 0x30CD: 0.8438, 0x30CE: 0.7109, 0x30CF: 0.9375, 0x30D0: 0.9375, 0x30D1: 0.9375, 0x30D2: 0.7617, 0x30D3: 0.8242, 0x30D4: 0.8047, 0x30D5: 0.832, 0x30D6: 0.9102, 0x30D7: 0.875, 0x30D8: 0.9336, 0x30D9: 0.9336, 0x30DA: 0.9336, 0x30DB: 0.9062, 0x30DC: 0.9062, 0x30DD: 0.9062, 0x30DE: 0.8594, 0x30DF: 0.7422, 0x30E0: 0.8906, 0x30E1: 0.7734, 0x30E2: 0.875, 0x30E3: 0.707, 0x30E4: 0.8906, 0x30E5: 0.6836, 0x30E6: 0.8906, 0x30E7: 0.6094, 0x30E8: 0.7852, 0x30E9: 0.832, 0x30EA: 0.6992, 0x30EB: 0.9258, 0x30EC: 0.8008, 0x30ED: 0.8047, 0x30EE: 0.6602, 0x30EF: 0.8516, 0x30F0: 0.8789, 0x30F1: 0.8828, 0x30F2: 0.7852, 0x30F3: 0.8633, 0x30F4: 0.918, 0x30F5: 0.6719, 0x30F6: 0.7227, 0x30FB: 0.5, 0x30FC: 0.8477, 0x30FD: 0.5391, 0x30FE: 0.6562, 0xFF08: 0.5, 0xFF09: 0.5, 0xFF0C: 0.6641, 0xFF0E: 0.6641, 0xFF10: 0.75, 0xFF11: 0.75, 0xFF12: 0.75, 0xFF13: 0.75, 0xFF14: 0.75, 0xFF15: 0.75, 0xFF16: 0.75, 0xFF17: 0.75, 0xFF18: 0.75, 0xFF19: 0.75, 0xFF1A: 0.5, 0xFF1B: 0.5, 0xFF21: 0.75, 0xFF22: 0.7383, 0xFF23: 0.8047, 0xFF24: 0.7578, 0xFF25: 0.6914, 0xFF26: 0.6758, 0xFF27: 0.8281, 0xFF28: 0.7656, 0xFF29: 0.2773, 0xFF2A: 0.5977, 0xFF2B: 0.7656, 0xFF2C: 0.668, 0xFF2D: 0.918, 0xFF2E: 0.7891, 0xFF2F: 0.8594, 0xFF30: 0.6992, 0xFF31: 0.8594, 0xFF32: 0.7305, 0xFF33: 0.7383, 0xFF34: 0.7109, 0xFF35: 0.7422, 0xFF36: 0.7344, 0xFF37: 0.9414, 0xFF38: 0.7695, 0xFF39: 0.7227, 0xFF3A: 0.7539, 0xFF3B: 0.5, 0xFF3D: 0.5, 0xFF3E: 0.5, 0xFF40: 0.5, 0xFF41: 0.6367, 0xFF42: 0.6719, 0xFF43: 0.6406, 0xFF44: 0.668, 0xFF45: 0.6797, 0xFF46: 0.4062, 0xFF47: 0.6602, 0xFF48: 0.6445, 0xFF49: 0.2656, 0xFF4A: 0.3242, 0xFF4B: 0.625, 0xFF4C: 0.2656, 0xFF4D: 0.9453, 0xFF4E: 0.6445, 0xFF4F: 0.6719, 0xFF50: 0.6758, 0xFF51: 0.6758, 0xFF52: 0.418, 0xFF53: 0.5977, 0xFF54: 0.4023, 0xFF55: 0.6133, 0xFF56: 0.5977, 0xFF57: 0.8906, 0xFF58: 0.6367, 0xFF59: 0.5859, 0xFF5A: 0.6055, 0xFF5B: 0.5, 0xFF5D: 0.5, 0xFF5F: 0.5781] }
            return hg
        }
        // Meiryo UI sets its lines 1.65 em apart in Word's print (jpn-g11-40dd71 and lab ovl2: 9 pt lines step 14.88,
        // 10 pt 16.44, 10.5 pt 17.28/17.4, 11 pt 18.12/18.24; 1.64 left a 2 pt gap over 7 lines) where YaHei's 1.715 em gave 17.2.
        // Meiryo (not UI): hhea 2171+901 = 3072 units of 2048, so Word's single line is floor(1.3 x 3072)/2048 = 1.95 em
        // (dx2 934bd3e5's vertical print: plain columns step two 18 pt grid pitches at 10.5 pt).
        if wordOnWindows, has("meiryo", "メイリオ"), !has("meiryo ui") {
            var meiryo = yaHei
            meiryo.height = wordEastAsianLine(units: 3072, upem: 2048)
            meiryo.baseline = 1.26 * meiryo.height / 1.715 + 0.08
            meiryo.boldHeight = meiryo.height
            meiryo.boldBaseline = 1.2675 * meiryo.height / 1.715 + 0.08
            return meiryo
        }
        if wordOnWindows, has("meiryo ui") {
            var meiryo = yaHei
            meiryo.height = wordEastAsianLine(units: 2601, upem: 2048)
            meiryo.baseline = 1.26 * meiryo.height / 1.715 + 0.08
            meiryo.boldHeight = meiryo.height
            meiryo.boldBaseline = 1.2675 * meiryo.height / 1.715 + 0.08
            // (Its kana and marks are proportional: advances from the font itself, lab/metrics/Meiryo_UI.tsv;
            // f42177d2's "・・・" run steps half an em in Word.)
            meiryo.otherAdvances = [0x3000: 0.6641, 0x3001: 0.6641, 0x3002: 0.6641, 0x3008: 0.5000, 0x3009: 0.5000, 0x300A: 0.5000, 0x300B: 0.5000, 0x300C: 0.5000, 0x300D: 0.5000, 0x300E: 0.5000, 0x300F: 0.5000, 0x3010: 0.5000, 0x3011: 0.5000, 0x3014: 0.5000, 0x3015: 0.5000, 0x3041: 0.6367, 0x3042: 0.8164, 0x3043: 0.6602, 0x3044: 0.8164, 0x3045: 0.4727, 0x3046: 0.6392, 0x3047: 0.6289, 0x3048: 0.7852, 0x3049: 0.6602, 0x304A: 0.8164, 0x304B: 0.8164, 0x304C: 0.8164, 0x304D: 0.7539, 0x304E: 0.8008, 0x304F: 0.5039, 0x3050: 0.6289, 0x3051: 0.8164, 0x3052: 0.8164, 0x3053: 0.6914, 0x3054: 0.7695, 0x3055: 0.6914, 0x3056: 0.7695, 0x3057: 0.7227, 0x3058: 0.7227, 0x3059: 0.8477, 0x305A: 0.8477, 0x305B: 0.8477, 0x305C: 0.8477, 0x305D: 0.7461, 0x305E: 0.7969, 0x305F: 0.7852, 0x3060: 0.7852, 0x3061: 0.7617, 0x3062: 0.7852, 0x3063: 0.6289, 0x3064: 0.7852, 0x3065: 0.8164, 0x3066: 0.7852, 0x3067: 0.8164, 0x3068: 0.6289, 0x3069: 0.6289, 0x306A: 0.8555, 0x306B: 0.7852, 0x306C: 0.8477, 0x306D: 0.8867, 0x306E: 0.8164, 0x306F: 0.8555, 0x3070: 0.8555, 0x3071: 0.8555, 0x3072: 0.8164, 0x3073: 0.8320, 0x3074: 0.8320, 0x3075: 0.8164, 0x3076: 0.8164, 0x3077: 0.8164, 0x3078: 0.8164, 0x3079: 0.8164, 0x307A: 0.8164, 0x307B: 0.8555, 0x307C: 0.8555, 0x307D: 0.8555, 0x307E: 0.7539, 0x307F: 0.8867, 0x3080: 0.8164, 0x3081: 0.8164, 0x3082: 0.7617, 0x3083: 0.6914, 0x3084: 0.8477, 0x3085: 0.6602, 0x3086: 0.8555, 0x3087: 0.5977, 0x3088: 0.7539, 0x3089: 0.6914, 0x308A: 0.6289, 0x308B: 0.7617, 0x308C: 0.8867, 0x308D: 0.7617, 0x308E: 0.6914, 0x308F: 0.8477, 0x3090: 0.8555, 0x3091: 0.8555, 0x3092: 0.7539, 0x3093: 0.8164, 0x3094: 0.7666, 0x3095: 0.6719, 0x3096: 0.6758, 0x309B: 0.5000, 0x309C: 0.5000, 0x309D: 0.7344, 0x309E: 0.7344, 0x30A1: 0.5859, 0x30A2: 0.7539, 0x30A3: 0.5664, 0x30A4: 0.7227, 0x30A5: 0.5859, 0x30A6: 0.7422, 0x30A7: 0.5977, 0x30A8: 0.7539, 0x30A9: 0.6602, 0x30AA: 0.7656, 0x30AB: 0.7148, 0x30AC: 0.8008, 0x30AD: 0.8164, 0x30AE: 0.8320, 0x30AF: 0.6914, 0x30B0: 0.7695, 0x30B1: 0.7852, 0x30B2: 0.8164, 0x30B3: 0.6914, 0x30B4: 0.7695, 0x30B5: 0.8164, 0x30B6: 0.8320, 0x30B7: 0.8164, 0x30B8: 0.8320, 0x30B9: 0.7656, 0x30BA: 0.8164, 0x30BB: 0.8164, 0x30BC: 0.8320, 0x30BD: 0.7539, 0x30BE: 0.8008, 0x30BF: 0.6914, 0x30C0: 0.7227, 0x30C1: 0.7852, 0x30C2: 0.7852, 0x30C3: 0.5781, 0x30C4: 0.7344, 0x30C5: 0.8008, 0x30C6: 0.7656, 0x30C7: 0.8164, 0x30C8: 0.7070, 0x30C9: 0.7070, 0x30CA: 0.8008, 0x30CB: 0.7461, 0x30CC: 0.7227, 0x30CD: 0.8164, 0x30CE: 0.6602, 0x30CF: 0.8086, 0x30D0: 0.8477, 0x30D1: 0.8477, 0x30D2: 0.6523, 0x30D3: 0.7070, 0x30D4: 0.7383, 0x30D5: 0.6758, 0x30D6: 0.7539, 0x30D7: 0.7539, 0x30D8: 0.8164, 0x30D9: 0.8164, 0x30DA: 0.8164, 0x30DB: 0.8164, 0x30DC: 0.8164, 0x30DD: 0.8164, 0x30DE: 0.7539, 0x30DF: 0.5977, 0x30E0: 0.8164, 0x30E1: 0.6914, 0x30E2: 0.7539, 0x30E3: 0.6602, 0x30E4: 0.8164, 0x30E5: 0.6602, 0x30E6: 0.8164, 0x30E7: 0.5039, 0x30E8: 0.6289, 0x30E9: 0.6914, 0x30EA: 0.5859, 0x30EB: 0.8164, 0x30EC: 0.7539, 0x30ED: 0.7227, 0x30EE: 0.5820, 0x30EF: 0.7539, 0x30F0: 0.8164, 0x30F1: 0.8164, 0x30F2: 0.7070, 0x30F3: 0.7461, 0x30F4: 0.7852, 0x30F5: 0.5781, 0x30F6: 0.6602, 0x30F7: 0.7539, 0x30F8: 0.8838, 0x30F9: 0.9648, 0x30FA: 0.7070, 0x30FB: 0.5000, 0x30FC: 0.8164, 0x30FD: 0.7461, 0x30FE: 0.7461, 0xFF61: 0.5000, 0xFF62: 0.5000, 0xFF63: 0.5000, 0xFF64: 0.5000, 0xFF65: 0.5000, 0xFF66: 0.5000, 0xFF67: 0.5000, 0xFF68: 0.5000, 0xFF69: 0.5000, 0xFF6A: 0.5000, 0xFF6B: 0.5000, 0xFF6C: 0.5000, 0xFF6D: 0.5000, 0xFF6E: 0.5000, 0xFF6F: 0.5000, 0xFF70: 0.5000, 0xFF71: 0.5000, 0xFF72: 0.5000, 0xFF73: 0.5000, 0xFF74: 0.5000, 0xFF75: 0.5000, 0xFF76: 0.5000, 0xFF77: 0.5000, 0xFF78: 0.5000, 0xFF79: 0.5000, 0xFF7A: 0.5000, 0xFF7B: 0.5000, 0xFF7C: 0.5000, 0xFF7D: 0.5000, 0xFF7E: 0.5000, 0xFF7F: 0.5000, 0xFF80: 0.5000, 0xFF81: 0.5000, 0xFF82: 0.5000, 0xFF83: 0.5000, 0xFF84: 0.5000, 0xFF85: 0.5000, 0xFF86: 0.5000, 0xFF87: 0.5000, 0xFF88: 0.5000, 0xFF89: 0.5000, 0xFF8A: 0.5000, 0xFF8B: 0.5000, 0xFF8C: 0.5000, 0xFF8D: 0.5000, 0xFF8E: 0.5000, 0xFF8F: 0.5000, 0xFF90: 0.5000, 0xFF91: 0.5000, 0xFF92: 0.5000, 0xFF93: 0.5000, 0xFF94: 0.5000, 0xFF95: 0.5000, 0xFF96: 0.5000, 0xFF97: 0.5000, 0xFF98: 0.5000, 0xFF99: 0.5000, 0xFF9A: 0.5000, 0xFF9B: 0.5000, 0xFF9C: 0.5000, 0xFF9D: 0.5000, 0xFF9E: 0.5000, 0xFF9F: 0.5000]
            // (The bold cut's own: lab/metrics/Meiryo_UI_Bold.tsv, e.g. ト 0.753 against 0.707.)
            meiryo.boldOtherAdvances = (meiryo.otherAdvances ?? [:]).merging([0x2010: 0.4678, 0x2011: 0.4678, 0x2012: 0.4678, 0x2013: 0.6768, 0x2014: 1.0000, 0x2015: 1.0000, 0x2016: 1.0000, 0x2017: 0.6768, 0x2018: 0.2964, 0x2019: 0.2964, 0x201A: 0.2964, 0x201B: 0.3066, 0x201C: 0.5371, 0x201D: 0.5371, 0x201E: 0.5371, 0x201F: 0.5098, 0x2020: 1.0000, 0x2021: 1.0000, 0x2022: 0.6768, 0x2023: 1.0000, 0x2024: 0.3472, 0x2025: 1.0000, 0x2026: 1.0000, 0x2027: 0.3472, 0x2028: 1.0000, 0x2029: 1.0000, 0x202A: 1.0000, 0x202B: 1.0000, 0x202C: 1.0000, 0x202D: 1.0000, 0x202E: 1.0000, 0x2030: 1.0000, 0x2031: 2.0859, 0x2032: 0.2964, 0x2033: 0.5371, 0x2034: 0.6191, 0x2035: 0.2012, 0x2036: 0.4102, 0x2037: 0.6191, 0x2038: 0.2769, 0x2039: 0.5342, 0x203A: 0.5342, 0x203B: 1.0000, 0x203C: 1.0000, 0x203D: 0.6016, 0x203E: 0.6768, 0x203F: 0.0000, 0x2040: 0.0000, 0x2041: 0.2720, 0x2042: 1.0000, 0x2043: 0.4678, 0x2044: 0.1719, 0x2045: 0.4702, 0x2046: 0.4702, 0x2047: 1.0000, 0x2048: 1.0000, 0x2049: 1.0000, 0x2051: 1.0000, 0x3000: 0.6641, 0x3001: 0.6641, 0x3002: 0.6641, 0x3003: 1.0000, 0x3004: 1.0000, 0x3005: 1.0000, 0x3006: 1.0000, 0x3007: 1.0000, 0x3008: 0.5000, 0x3009: 0.5000, 0x300A: 0.5000, 0x300B: 0.5000, 0x300C: 0.5000, 0x300D: 0.5000, 0x300E: 0.5000, 0x300F: 0.5000, 0x3010: 0.5000, 0x3011: 0.5000, 0x3012: 1.0000, 0x3013: 1.0000, 0x3014: 0.5000, 0x3015: 0.5000, 0x3016: 1.0000, 0x3017: 1.0000, 0x3018: 1.0000, 0x3019: 1.0000, 0x301A: 1.0000, 0x301B: 1.0000, 0x301C: 1.0000, 0x301D: 1.0000, 0x301E: 1.0000, 0x301F: 1.0000, 0x3020: 1.0000, 0x3030: 1.0000, 0x3031: 1.0000, 0x3032: 1.0000, 0x3033: 1.0000, 0x3034: 1.0000, 0x3035: 1.0000, 0x3036: 1.0000, 0x3037: 1.0000, 0x303B: 1.0000, 0x303C: 1.0000, 0x303D: 1.0000, 0x3041: 0.7681, 0x3042: 0.8999, 0x3043: 0.7422, 0x3044: 0.8721, 0x3045: 0.6113, 0x3046: 0.7134, 0x3047: 0.7227, 0x3048: 0.8574, 0x3049: 0.7515, 0x304A: 0.8359, 0x304B: 0.8760, 0x304C: 0.9414, 0x304D: 0.7632, 0x304E: 0.8218, 0x304F: 0.5620, 0x3050: 0.7314, 0x3051: 0.8555, 0x3052: 0.8916, 0x3053: 0.7251, 0x3054: 0.8765, 0x3055: 0.7866, 0x3056: 0.8145, 0x3057: 0.7446, 0x3058: 0.7446, 0x3059: 0.8501, 0x305A: 0.8936, 0x305B: 0.8491, 0x305C: 0.9141, 0x305D: 0.7588, 0x305E: 0.8408, 0x305F: 0.8350, 0x3060: 0.8423, 0x3061: 0.8135, 0x3062: 0.8135, 0x3063: 0.6948, 0x3064: 0.8232, 0x3065: 0.8647, 0x3066: 0.8047, 0x3067: 0.8804, 0x3068: 0.7095, 0x3069: 0.6924, 0x306A: 0.9004, 0x306B: 0.8140, 0x306C: 0.9517, 0x306D: 0.8877, 0x306E: 0.9175, 0x306F: 0.8906, 0x3070: 0.9707, 0x3071: 0.9233, 0x3072: 0.8340, 0x3073: 0.9458, 0x3074: 0.8574, 0x3075: 0.8901, 0x3076: 0.8975, 0x3077: 0.8901, 0x3078: 0.8223, 0x3079: 0.8223, 0x307A: 0.8223, 0x307B: 0.8901, 0x307C: 0.8823, 0x307D: 0.8975, 0x307E: 0.8096, 0x307F: 0.8569, 0x3080: 0.8745, 0x3081: 0.8643, 0x3082: 0.8438, 0x3083: 0.7671, 0x3084: 0.8325, 0x3085: 0.7549, 0x3086: 0.8359, 0x3087: 0.6973, 0x3088: 0.8457, 0x3089: 0.7524, 0x308A: 0.6777, 0x308B: 0.8032, 0x308C: 0.8374, 0x308D: 0.8013, 0x308E: 0.7275, 0x308F: 0.8452, 0x3090: 0.8936, 0x3091: 0.8501, 0x3092: 0.8140, 0x3093: 0.8594, 0x3094: 0.8262, 0x3095: 0.7153, 0x3096: 0.6948, 0x3099: 0.5000, 0x309A: 0.5000, 0x309B: 0.6226, 0x309C: 0.5737, 0x309D: 0.7026, 0x309E: 0.7817, 0x309F: 0.9688, 0x30A0: 0.9351, 0x30A1: 0.6763, 0x30A2: 0.8247, 0x30A3: 0.7036, 0x30A4: 0.8130, 0x30A5: 0.6826, 0x30A6: 0.8115, 0x30A7: 0.7017, 0x30A8: 0.8032, 0x30A9: 0.7158, 0x30AA: 0.7983, 0x30AB: 0.8135, 0x30AC: 0.8135, 0x30AD: 0.8301, 0x30AE: 0.8589, 0x30AF: 0.8081, 0x30B0: 0.8589, 0x30B1: 0.8057, 0x30B2: 0.8379, 0x30B3: 0.7344, 0x30B4: 0.7988, 0x30B5: 0.8115, 0x30B6: 0.8555, 0x30B7: 0.8159, 0x30B8: 0.8423, 0x30B9: 0.8164, 0x30BA: 0.8911, 0x30BB: 0.8071, 0x30BC: 0.8374, 0x30BD: 0.7671, 0x30BE: 0.9009, 0x30BF: 0.8013, 0x30C0: 0.8135, 0x30C1: 0.7954, 0x30C2: 0.8218, 0x30C3: 0.6528, 0x30C4: 0.8184, 0x30C5: 0.9443, 0x30C6: 0.7759, 0x30C7: 0.8203, 0x30C8: 0.7534, 0x30C9: 0.7534, 0x30CA: 0.7993, 0x30CB: 0.7891, 0x30CC: 0.7891, 0x30CD: 0.8350, 0x30CE: 0.7036, 0x30CF: 0.8525, 0x30D0: 0.8989, 0x30D1: 0.8989, 0x30D2: 0.6997, 0x30D3: 0.7524, 0x30D4: 0.7749, 0x30D5: 0.7109, 0x30D6: 0.8911, 0x30D7: 0.8638, 0x30D8: 0.8174, 0x30D9: 0.8174, 0x30DA: 0.8174, 0x30DB: 0.8350, 0x30DC: 0.8350, 0x30DD: 0.8350, 0x30DE: 0.8047, 0x30DF: 0.7139, 0x30E0: 0.8257, 0x30E1: 0.8037, 0x30E2: 0.7783, 0x30E3: 0.6899, 0x30E4: 0.8057, 0x30E5: 0.7085, 0x30E6: 0.7979, 0x30E7: 0.6387, 0x30E8: 0.7778, 0x30E9: 0.7910, 0x30EA: 0.7012, 0x30EB: 0.8379, 0x30EC: 0.7583, 0x30ED: 0.8076, 0x30EE: 0.6729, 0x30EF: 0.8120, 0x30F0: 0.8247, 0x30F1: 0.8145, 0x30F2: 0.7983, 0x30F3: 0.7764, 0x30F4: 0.8115, 0x30F5: 0.6860, 0x30F6: 0.6919, 0x30F7: 0.8740, 0x30F8: 0.9048, 0x30F9: 0.8262, 0x30FA: 0.8062, 0x30FB: 0.5205, 0x30FC: 0.8818, 0x30FD: 0.7417, 0x30FE: 0.8057, 0x30FF: 0.9331, 0xFF01: 1.0000, 0xFF02: 1.0000, 0xFF03: 1.0000, 0xFF04: 1.0000, 0xFF05: 1.0000, 0xFF06: 1.0000, 0xFF07: 1.0000, 0xFF08: 1.0000, 0xFF09: 1.0000, 0xFF0A: 1.0000, 0xFF0B: 1.0000, 0xFF0C: 1.0000, 0xFF0D: 1.0000, 0xFF0E: 1.0000, 0xFF0F: 1.0000, 0xFF10: 1.0000, 0xFF11: 1.0000, 0xFF12: 1.0000, 0xFF13: 1.0000, 0xFF14: 1.0000, 0xFF15: 1.0000, 0xFF16: 1.0000, 0xFF17: 1.0000, 0xFF18: 1.0000, 0xFF19: 1.0000, 0xFF1A: 1.0000, 0xFF1B: 1.0000, 0xFF1C: 1.0000, 0xFF1D: 1.0000, 0xFF1E: 1.0000, 0xFF1F: 1.0000, 0xFF20: 1.0000, 0xFF21: 1.0000, 0xFF22: 1.0000, 0xFF23: 1.0000, 0xFF24: 1.0000, 0xFF25: 1.0000, 0xFF26: 1.0000, 0xFF27: 1.0000, 0xFF28: 1.0000, 0xFF29: 1.0000, 0xFF2A: 1.0000, 0xFF2B: 1.0000, 0xFF2C: 1.0000, 0xFF2D: 1.0000, 0xFF2E: 1.0000, 0xFF2F: 1.0000, 0xFF30: 1.0000, 0xFF31: 1.0000, 0xFF32: 1.0000, 0xFF33: 1.0000, 0xFF34: 1.0000, 0xFF35: 1.0000, 0xFF36: 1.0000, 0xFF37: 1.0000, 0xFF38: 1.0000, 0xFF39: 1.0000, 0xFF3A: 1.0000, 0xFF3B: 1.0000, 0xFF3C: 1.0000, 0xFF3D: 1.0000, 0xFF3E: 1.0000, 0xFF3F: 1.0000, 0xFF40: 1.0000, 0xFF41: 1.0000, 0xFF42: 1.0000, 0xFF43: 1.0000, 0xFF44: 1.0000, 0xFF45: 1.0000, 0xFF46: 1.0000, 0xFF47: 1.0000, 0xFF48: 1.0000, 0xFF49: 1.0000, 0xFF4A: 1.0000, 0xFF4B: 1.0000, 0xFF4C: 1.0000, 0xFF4D: 1.0000, 0xFF4E: 1.0000, 0xFF4F: 1.0000, 0xFF50: 1.0000, 0xFF51: 1.0000, 0xFF52: 1.0000, 0xFF53: 1.0000, 0xFF54: 1.0000, 0xFF55: 1.0000, 0xFF56: 1.0000, 0xFF57: 1.0000, 0xFF58: 1.0000, 0xFF59: 1.0000, 0xFF5A: 1.0000, 0xFF5B: 1.0000, 0xFF5C: 1.0000, 0xFF5D: 1.0000, 0xFF5E: 1.0000, 0xFF5F: 1.0000, 0xFF60: 1.0000, 0xFF61: 0.5000, 0xFF62: 0.5000, 0xFF63: 0.5000, 0xFF64: 0.5000, 0xFF65: 0.5000, 0xFF66: 0.5000, 0xFF67: 0.5000, 0xFF68: 0.5000, 0xFF69: 0.5000, 0xFF6A: 0.5000, 0xFF6B: 0.5000, 0xFF6C: 0.5000, 0xFF6D: 0.5000, 0xFF6E: 0.5000, 0xFF6F: 0.5000, 0xFF70: 0.5000, 0xFF71: 0.5000, 0xFF72: 0.5000, 0xFF73: 0.5000, 0xFF74: 0.5000, 0xFF75: 0.5000, 0xFF76: 0.5000, 0xFF77: 0.5000, 0xFF78: 0.5000, 0xFF79: 0.5000, 0xFF7A: 0.5000, 0xFF7B: 0.5000, 0xFF7C: 0.5000, 0xFF7D: 0.5000, 0xFF7E: 0.5000, 0xFF7F: 0.5000, 0xFF80: 0.5000, 0xFF81: 0.5000, 0xFF82: 0.5000, 0xFF83: 0.5000, 0xFF84: 0.5000, 0xFF85: 0.5000, 0xFF86: 0.5000, 0xFF87: 0.5000, 0xFF88: 0.5000, 0xFF89: 0.5000, 0xFF8A: 0.5000, 0xFF8B: 0.5000, 0xFF8C: 0.5000, 0xFF8D: 0.5000, 0xFF8E: 0.5000, 0xFF8F: 0.5000, 0xFF90: 0.5000, 0xFF91: 0.5000, 0xFF92: 0.5000, 0xFF93: 0.5000, 0xFF94: 0.5000, 0xFF95: 0.5000, 0xFF96: 0.5000, 0xFF97: 0.5000, 0xFF98: 0.5000, 0xFF99: 0.5000, 0xFF9A: 0.5000, 0xFF9B: 0.5000, 0xFF9C: 0.5000, 0xFF9D: 0.5000, 0xFF9E: 0.5000, 0xFF9F: 0.5000, 0xFFE0: 1.0000, 0xFFE1: 1.0000, 0xFFE2: 1.0000, 0xFFE3: 1.0000, 0xFFE4: 1.0000, 0xFFE5: 1.0000, 0xFFE6: 1.0000, 0xFFE8: 0.5000, 0xFFE9: 0.5000, 0xFFEA: 0.5000, 0xFFEB: 0.5000, 0xFFEC: 0.5000, 0xFFED: 0.5000, 0xFFEE: 0.5000]) { $1 }
            return meiryo
        }
        // Yu Mincho shares Yu Gothic's line (jpn-z23845932-12d9fb: 10.5pt Body
        // Text at 1.5 lines steps 26.4pt in Word's print = 1.676 em natural,
        // where YaHei's 1.715 em gave 27.0).
        if wordOnWindows, has("yu mincho", "游明朝") {
            // (Its Latin text is set in its own narrower widths: jpn-z19171856's English body, 207 lines
            // here against Word's 169.)
            var yu = EastAsianFace(height: 1.2871 * 1.3, latin: sans, latinScale: 1.0, fakeBold: true, baseline: 1.2871 * 0.15 + 0.98486)
            yu.latinAdvances = yuMinchoAdvances
            // (Yu Mincho's bold is Word's synthetic bold, drawn in the one Yu Mincho face with the regular widths:
            // jpn-z19171856-2c8799's bold "Hypothesis: " ends the line in Word's print where Liberation Bold's widths wrapped it.)
            yu.latinBoldAdvances = yuMinchoAdvances
            // (Greek and symbols stay full width: own Latin widths would otherwise switch that off,
            // jpn-z19410533-d8cc8f's nu.)
            yu.squareSymbols = true
            // (Word sets its Greek letters an em: jpn-z19410533-d8cc8f's nu steps 10.6 pt at 10.5 pt.)
            var yuGreek: [UInt32: Double] = [:]
            for u in UInt32(0x391)...UInt32(0x3C9) where u != 0x3A2 { yuGreek[u] = 1.0 }
            yu.otherAdvances = yuGreek
            return yu
        }
        // (AR P Maru Gothic E, not on Word's machine, prints as Yu Gothic: f42177d2. BIZ UDPゴシック, also missing there,
        // prints as Yu Gothic too: lab opn3 D against B, identical prints.)
        if wordOnWindows, has("yu gothic", "游ゴシック", "yu mincho", "游明朝", "ar p丸ゴシック", "ar丸ゴシック", "biz udpゴシック") {
            return EastAsianFace(height: 1.2871 * 1.3, latin: sans, latinScale: 1.0, fakeBold: true, baseline: 1.2871 * 0.15 + 0.98486)
        }
        if wordOnWindows, has("malgun", "맑은 고딕") {
            RuleTrace.hit("malgun-gothic-own-latin-widths")
            var malgun = yaHei
            malgun.height = malgunHeight
            malgun.baseline = 1.288
            // (Word sets Malgun's curly quotes at their own narrow widths, with no blank beside them:
            // kor-z17264683-7d8a4b's "‘필수 재료’로" steps 0.228 em at each single quote and 0.38 at a double one.)
            var malgunQuotes: [UInt32: Double] = [0x2018: 0.228, 0x2019: 0.228, 0x201C: 0.38, 0x201D: 0.38,
                                                  // (Malgun's corner brackets are proportional, read from f457e50c's print: 「 0.566, 」 0.577, 『 』 0.517 em.)
                                                  0x300C: 0.566, 0x300D: 0.577, 0x300E: 0.517, 0x300F: 0.517,
                                                  // (Malgun's middle dot, from the face's own hmtx (lab/metrics/Malgun_Gothic.tsv): 448/2048 = 0.2188 em; ours drew the Latin stand-in's.)
                                                  0x00B7: 0.2188, 0x2022: 0.4175,
                                                  // (U+2027: Malgun has none; Word draws it in MS Gothic, half an em, regular and bold (lab u2027, 20-dot runs).)
                                                  0x2027: 0.5]
            // (Roman numerals U+2160-2179: Malgun Gothic Regular sets them 0.9502 em (Malgun_Gothic_Regular.tsv), Bold a full em;
            // kor-z19176375-30dbe1's "제Ⅹ부" lines ran ~4 pt wide at our em. The bold table below stays at the em default.)
            var malgunBoldQuotes = malgunQuotes
            for u in UInt32(0x2160)...UInt32(0x2179) { malgunQuotes[u] = 0.9502 }
            malgun.otherAdvances = malgunQuotes
            // (Bold cut: U+00B7 is 0.2617 em, from lab/metrics/Malgun_Gothic_Bold.tsv.)
            malgunBoldQuotes[0x00B7] = 0.2617
            malgun.boldOtherAdvances = malgunBoldQuotes
            malgun.latinScale = 1.0
            malgun.latinClasses = nil
            malgun.latinAdvances = malgunAdvances
            malgun.latinBoldAdvances = malgunBoldAdvances
            malgun.latinKerns = nil
            malgun.latinBoldKerns = nil
            return malgun
        }
        if has("yahei ui") {
            return EastAsianFace(height: 1.67, latin: sans, latinScale: 1.07, latinAdvances: yaHeiUIAdvances, latinBoldAdvances: yaHeiUIBoldAdvances,
                                 latinKerns: yaHeiKerns, latinBoldKerns: yaHeiBoldKerns,
                                 fakeBold: false)
        }
        // (YaHei Light, msyhl.ttc, is a shorter line: Word for Windows
        // measures it by its usWinAscent 2080 and usWinDescent 536 in 2048
        // — regular's ascent is 2167 — at Word's 1.3, 1.6605 em, the extra
        // half above and half below. zh-a7a889eb's contents, each line's
        // mark and page number 微软雅黑 Light 14pt at 0.8125 auto, step 36.21
        // in Word for Windows' print; at regular's line ours stepped 36.83.
        // Word for Mac has no Light and sets regular's, as its print does.)
        if has("yahei", "微软雅黑"), has("light"), !wordOnMac {
            var light = yaHei
            light.height = 2616 * 1.3 / 2048
            light.baseline = (2080 + 2616 * 0.15) / 2048
            return light
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
                                 latinAdvances: has("light") ? jhengHeiUILightAdvances : jhengHeiAdvances,
                                 latinBoldAdvances: has("light") ? jhengHeiUILightAdvances : jhengHeiBoldAdvances, latinKerns: jhengHeiKerns,
                                 fakeBold: has("light"), boldWiden: 1.0 / 50, baseline: 1.206)
        }
        if has("jhenghei", "微軟正黑") {
            // (Word for Windows sets it at its hhea's 1.0757 + 0.2544 times
            // 1.3, 1.729 — zh-cb57eaad's 12pt lines step 20.76 in word-win,
            // the Mac's 1.74 20.88 — its baseline half the extra over the
            // ascent, 1.275: zh-f6686f89's 36pt cover lines, JhengHei for
            // what Mincho lacks (`windowsMincho`), stand their baselines
            // 46pt under the line's top; without one the line took the
            // drawing face's, Mincho's, 9.8pt high.)
            return EastAsianFace(height: wordOnWindows ? 1.3301 * 1.3 : 1.74, latin: sans, latinScale: 1.05, latinClasses: [0.991, 0.925, 1.031, 0.95],
                                 latinAdvances: jhengHeiAdvances, latinBoldAdvances: jhengHeiBoldAdvances, latinKerns: jhengHeiKerns, fakeBold: false,
                                 baseline: wordOnWindows ? (1.3301 * 1.3 - 1.3301) / 2 + 1.0757 : nil)
        }
        if has("dengxian", "等线") {
            var face = EastAsianFace(height: 1.36, latin: sans, latinScale: 0.955, latinClasses: [0.992, 0.927, 1.021, 0.91],
                                     latinAdvances: dengXianAdvances, latinBoldAdvances: dengXianBoldAdvances, fakeBold: false, baseline: 1.01)
            // (Its curly quotes are its own, 0.35 em, not an em: zh-55270438's table note
            // "“项目运营”与“项目维护”" in 等线 at 10.5pt sets each quote 3.6-3.7pt in Word
            // for Windows' print, and its line holds "…与“项目维" where ours, with em
            // quotes, ended two characters sooner.)
            if wordOnWindows { face.otherAdvances = [0x201C: 0.352, 0x201D: 0.352] }
            return face
        }
        // (Not 1.3 em but 1332/1024 — 1.3 of its 1024-unit em, rounded
        // up to a whole unit: Word fits 48 lines of 12pt to a page only
        // with 8..12 twips over 48 x 312, and 24 lines of 24pt with the
        // same over 24 x 624 — labs `ln`, `lb`, Word 16, 2026-10-16. The
        // 0.2 twip a line kept zh-e061a08e's page 1 a line long.)
        // (Its baseline is its hhea ascent, 820 of 1024, and half of what
        // Word adds — 974/1024. With none of its own the engine spread a
        // spaced line's extra over and under, and zh-b8de3ae2's 13.5pt
        // notes at 1.39 lines stood 3.8pt under Word's print, where Word
        // sets all of it under the text.)
        if has("pmingliu", "新細明體") {
            // (Its space as its own: 3.12 at 12pt, where the stand-in's was
            // 2.82 — zh-1d3d66d3's "（資本門預算數） ×100％" ends at "100％" in
            // Word's print of a 7-em cell and opens the next line "（以".)
            // (Its bold is the regular drawn heavier, so the same widths: zh-b8de3ae2's 34 bold 22pt spaces
            // before "貳、本區預算分析" are 5.74 each in Word's print, 0.26 em, where ours took Times Bold's
            // 0.235 and stood the heading 18.6pt left.)
            return EastAsianFace(height: 1332.0 / 1024.0, latin: serif, latinScale: 0.94, latinAdvances: pMingLiUAdvances,
                                 latinBoldAdvances: pMingLiUAdvances, fakeBold: true, baseline: 974.0 / 1024.0, squareSymbols: true)
        }
        if has("stzhongsong", "华文中宋") {
            // (hhea 1.007 + .318, OS/2 win .912 + .225: 105.3pt a line at
            // 61pt, and 90.2 at 34% of its width.)
            // (Word for Windows takes the OS/2 line for all of it:
            // zh-17ac8aa2's empty 22pt mark in it before the form's table
            // is 5.5pt shorter in the word-win print than ours was at
            // the hhea line, and every row after stood that much low.)
            return EastAsianFace(height: wordOnWindows ? 1.478 : 1.7225, latin: serif, latinScale: 1.16, fakeBold: true,
                                 baseline: wordOnWindows ? 1.083 : 1.206, scaledHeight: 1.478, scaledBaseline: 1.083)
        }
        // (hhea 0.8 + 0.236, no gap — the STXINWEI.ttf Word carries: a 24pt
        // line is 32.3pt, three pitches of a 15.6 grid, and zh-424775e4's
        // title, centred in them, has its baseline at 117.84 in Word's
        // print. Taken for YaHei's, ours was two pitches and every page
        // after it ran 15.6pt early.)
        // (Word for Windows sets each 华文 face on its OS/2 win line at
        // 1.3, the baseline its win ascent and 0.15 of that line's ems
        // over — windows' lab t179, every face at 12 and 22pt fresh,
        // within 0.06pt: 新魏 .781 + .236, 仿宋 and 楷体 .86 + .26. See
        // 华文中宋 above.)
        if has("stxinwei", "华文新魏") {
            if wordOnWindows { return EastAsianFace(height: 1.322, latin: serif, latinScale: 1.0, fakeBold: true, baseline: 0.934) }
            return EastAsianFace(height: 1.036 * 1.3, latin: serif, latinScale: 1.0, fakeBold: true, baseline: 0.8 + (1.036 * 1.3 - 1.036) / 2)
        }
        if has("stfangsong", "华文仿宋") {
            return EastAsianFace(height: wordOnWindows ? 1.456 : 1.71, latin: serif, latinScale: 1.0, fakeBold: false, baseline: wordOnWindows ? 1.028 : nil)
        }
        if has("stkaiti", "华文楷体") {
            return EastAsianFace(height: wordOnWindows ? 1.456 : 1.7, latin: serif, latinScale: 1.04, fakeBold: true, baseline: wordOnWindows ? 1.028 : nil)
        }
        if has("stsong", "华文宋体") { return EastAsianFace(height: 1.31, latin: serif, latinScale: 1.0, fakeBold: true) }
        // (Word for Windows has no Arial Unicode MS: its Japanese text prints
        // in MS Mincho on that face's 1.3 em line, Latin in Arial —
        // jpn-z17544993-4a21de, 11pt lines 16.4 apart at 1.15 spacing, where
        // Arial Unicode's 1.742 em gave 22.0; 40 pages here against 32.)
        // (A GB2312 (charset 86) Arial Unicode MS is Chinese text: Word for Windows prints it in Microsoft YaHei, its line 1.715 em,
        // not in MS Mincho; 837ac08d's 10pt body steps 20.2 at 283 auto where Mincho's 1.3 em gave 15.3.)
        if has("arial unicode"), wordOnWindows, fontEntry(family)?.charset == "86" { return yaHei }
        if has("arial unicode") { return wordOnWindows ? windowsMinchoArialLatin : arialUnicode }
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
        // alternate it has; 方正 names fall back. 仿宋_GB2312 and
        // 楷体_GB2312 are such names too: a fresh Word for Mac sets each
        // in its table's alternate — 仿宋 in FangSong (zh-447f1d5c,
        // zh-f59a76e9, 33 of the 151 reprinted 2026-10-26), 宋体 in SimSun
        // (zh-146f4e02), Arial Unicode MS in that (zh-de97afa7) — and
        // with none in YaHei (95). The KaiTi or YaHei, alt or not, and
        // the Arial Unicode MS of the prints of 2026-10-12 to 10-24 were
        // one Word process days old, not Word.)
        let wordHas = ["simsun", "宋体", "新宋体", "simhei", "黑体", "kaiti", "楷体", "fangsong", "仿宋", "mingliu", "細明體",
                       "微软雅黑", "microsoft yahei", "幼圆", "全真楷書", "標楷", "方正", "小标宋"]
        let gb2312 = has("仿宋_gb2312", "fangsong_gb2312", "楷体_gb2312", "kaiti_gb2312")
        // (A 方正 name likewise: zh-2f9463d6's 方正小标宋简体, alternate 黑体,
        // sets its p12 title in SimHei in a fresh Word for Mac's print, as
        // Word for Windows' does — 20pt on SimHei's line, where YaHei's
        // stood it 9pt lower.)
        let fangZheng = has("方正", "小标宋")
        // (By its English name and with no alternate, a Latin face Word
        // lacks: its Chinese falls back to 宋体, as an alternate in Latin
        // does below — zh-202582e2's "FangSong_GB2312" body is SimSun in
        // a fresh Word for Mac's print, 118 runs of it.)
        if wordOnMac, ignoringEmbedding || !isEmbedded(family), n == "fangsong_gb2312" || n == "kaiti_gb2312", altName(family) == nil {
            return eastAsianFace("SimSun")
        }
        if wordOnMac, ignoringEmbedding || !isEmbedded(family), gb2312 || fangZheng || !wordHas.contains(where: { faceHas(n, $0) }),
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
            // Missing 方正 names can use Arial Unicode MS too: d5cc's
            // fresh-process title takes it, no alternate takes YaHei,
            // and alternate 黑体 takes SimHei, with the same package.
            let usable = ["simsun", "宋体", "新宋体", "simhei", "黑体", "kaiti", "楷体", "mingliu", "細明體", "jhenghei"]
                + (gb2312 ? ["仿宋", "fangsong"] : [])
                + (gb2312 || fangZheng ? ["arial unicode"] : [])
            if usable.contains(where: { faceHas(a, $0) }), !["_gb2312", "方正", "小标宋", "標楷"].contains(where: { faceHas(a, $0) }) {
                return eastAsianFace(alt)
            }
        }
        // (Word for Windows with the Chinese font packs — the reference
        // since 2026-10-24, word-win — sets 仿宋_GB2312 and 楷体_GB2312
        // in its FangSong and KaiTi, whatever the table's alternate:
        // 209 and 98 documents of the reprint. Word fixes a missing
        // name's face once a process, from the first file that names it,
        // and the first run, unwarmed, flipped between these and YaHei.)
        // (Not where the file carries 仿宋_GB2312: what its subset lacks
        // Word for Windows sets on YaHei's lines, as before the font
        // packs — zh-5450d509's embedded 仿宋_GB2312 stands 31.2pt a
        // 1.5-spaced 12pt line in word-win, YaHei's, not FangSong's 23.4,
        // fresh-process print or not (db46d815). An embedded 楷体_GB2312's
        // missing characters are KaiTi's, its lines the square face's:
        // zh-1cfb652b 67.9 -> 87.5 with that; YaHei there, nothing better.)
        if wordOnWindows, !isEmbedded(family) || (ignoringEmbedding && has("楷体_gb2312", "kaiti_gb2312")) {
            if has("仿宋_gb2312", "fangsong_gb2312") { return eastAsianFace("仿宋", ignoringEmbedding: ignoringEmbedding) }
            if has("楷体_gb2312", "kaiti_gb2312") { return eastAsianFace("楷体", ignoringEmbedding: ignoringEmbedding) }
            // (And 標楷體 is its DFKai-SB, a square face like KaiTi but of
            // a 1024-unit em: 1.3 em rounded up to a whole unit, 1332, as
            // PMingLiU's (labs ln/lb), its ascent 820 and half the 308 Word
            // adds under its baseline — kaiu.ttf, and Windows' lab `round`:
            // 15.612pt a 12pt line, 18.213 at 14. zh-74b34f3b's 12pt footer,
            // 49.6 up an 841.9 page, then reaches over the 36th exact 20pt
            // line's foot at 776.7, which opens page 2 in Word's print; at
            // KaiTi's 15.6 ours kept it, and every page after ran a line
            // early. Lab `kai`: zh-d35cbbdb's glyphs on Word's baselines.)
            if has("標楷", "dfkai") {
                var face = eastAsianFace("楷体", ignoringEmbedding: ignoringEmbedding)
                face.height = 1332.0 / 1024
                face.baseline = (820.0 + (1332 - 1024) / 2) / 1024
                return face
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
        let windowsLacks = !windowsHas.contains(where: { faceHas(n, $0) }) || has("_gb2312", "方正", "小标宋", "標楷")
        if wordOnWindows, windowsLacks, ignoringEmbedding || !isEmbedded(family), let alt = altName(family) {
            let a = alt.trimmingWhitespace().lowercased()
            // (An alternate that is itself a CESI face, absent from Windows:
            // zh-ac627439's 方正小标宋简体, alternate CESI仿宋-GB13000, is YaHei's
            // in Word's print, its "2012" digits 0.59 em, not FangSong's half.)
            // (The Japanese MS faces are on Windows too: dx2 c4ac3232's "Mincho", alternate ＭＳ 明朝, is MS Mincho's,
            // its ○ a full em as in the face's cmap, where the YaHei default drew 0.604.)
            let jaAlt = ["ms mincho", "ｍｓ 明朝", "ms gothic", "ｍｓ ゴシック", "ms pmincho", "ｍｓ ｐ明朝", "ms pgothic", "ｍｓ ｐゴシック"]
            if a != n, jaAlt.contains(where: { faceHas(a, $0) }) {
                return eastAsianFace(alt, ignoringEmbedding: ignoringEmbedding)
            }
            if a != n, windowsHas.contains(where: { faceHas(a, $0) }), !a.hasPrefix("cesi"),
               !["_gb2312", "方正", "小标宋", "標楷"].contains(where: { faceHas(a, $0) }) {
                return eastAsianFace(alt, ignoringEmbedding: ignoringEmbedding)
            }
        }
        // (A Japanese face (charset 80) that Word's machine lacks, one no rule above holds metrics or a stand-in for, prints as Yu Gothic:
        // lab hgpop's HG創英角ﾎﾟｯﾌﾟ体 and a made-up name alike, Yu Gothic's line even on an empty paragraph, 40.1 pt at 24 pt where
        // MS Gothic's is 31.1; the same as AR P Maru Gothic E (f42177d2) and BIZ UDPゴシック (lab opn3) above.)
        if wordOnWindows, !isEmbedded(family), !wordKnownEastAsianKeys.contains(where: { faceHas(n, $0) }),
           fontEntry(family)?.charset.uppercased() == "80" {
            RuleTrace.hit("missing-japanese-face-yu-gothic")
            return EastAsianFace(height: 1.2871 * 1.3, latin: sans, latinScale: 1.0, fakeBold: true, baseline: 1.2871 * 0.15 + 0.98486)
        }
        if wordOnWindows, windowsLacks, ignoringEmbedding || !isEmbedded(family) {
            var standIn = yaHei
            standIn.symbols = "SimSun"
            // (Not in bold: zh-f6886fbb's bold 方正楷体简体 "★★★" is
            // YaHei Bold's in Word for Windows' print, 9.83 apart at 12pt;
            // ours, SimSun's, an em, and its line lost "重". Every regular
            // star and triangle in such a face there is SimSun's.)
            standIn.symbolsInBold = false
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
            // (With no alternate, a name whose table entry is of the roman
            // family is SimSun instead — the last entry, where the table
            // names it twice. Lab tsim2 (Mac Word, macOS-doc and macos):
            // zh-4c5da793's 仿宋_GB2312, entries swiss then roman, is SimSun
            // in a fresh Word for Mac's print; with only the swiss, the two
            // swapped, or the roman made modern, YaHei; with only the roman,
            // no 宋体 entry in the table, SimSun still.)
            if wordOnMac, altName(family) == nil, let e = fontEntry(family), (e.lastFamily ?? e.family) == "roman" {
                return eastAsianFace("SimSun")
            }
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
        // (SimHei has the same shorter line in Word for Mac: fresh controls
        // at 10, 10.5, 12, 14 and 18pt, both separate paragraphs and forced
        // breaks, bound its advance to 1.29684..1.29697 em: 332/256,
        // within the print's 0.24pt raster at every size. In
        // zh-4c5da793 its single-line section rows accumulated enough of
        // the old 1.3-em excess to part page 15's last row a line early.
        // Keep its own Latin advances and the Windows metrics.)
        if wordOnMac, has("simhei", "黑体") {
            var face = square
            face.height = wordEastAsianLine(units: 256, upem: 256)
            face.baseline = 1.005 - (1.3 - face.height) / 2
            return face
        }
        // (SimSun's line is 1.2972 em, not 1.3: lab `f` (macOS-doc, Word
        // for Mac, zh-7b125a21's package) sets its 10.5pt lines 13.614
        // apart on the mean (1.2958-1.2973 em by the 0.24pt raster its
        // print rounds to) and 12pt ones 15.559, by 宋体, SimSun or the
        // CESI宋体 that stands for it alike; zh-0978dee9's 10pt cells are
        // 12.976 apart over 30 lines (1.2972-1.2980), and their page foot
        // takes a line by that. Ours, 13.65 at 10.5, fitted a line less
        // to zh-7b125a21's page 90, and the fifteen pages after ran behind.)
        if has("simsun", "宋体") {
            var face = square
            face.height = 1.2972
            face.baseline = 1.005 - (1.3 - 1.2972) / 2
            // (SimSun is fixed-pitch: of what it maps from U+00A1 to U+024F,
            // GB2312's eight are an em and the rest half one — read from
            // Word's own Simsun.ttc. Set East Asian, its "·" is an em:
            // zh-3f871b7d's "…在青岛·上合…", hinted, steps 15.96 at 16pt in
            // Word for Windows' print, where the stand-in drew Liberation
            // Sans's, 5.33, and its line took "合".)
            face.otherAdvances = Dictionary(uniqueKeysWithValues: simSunFullLatin.map { ($0, 1.0) } + simSunHalfLatin.map { ($0, 0.5) })
            return face
        }
        // (And FangSong's, in Word for Windows: zh-b00fef0d's 12pt
        // 仿宋_GB2312 cells, FangSong in word-win, step 18.0 and 18.12 on the
        // 1/600in raster, 18.03 on the mean — SimSun's 1.2972 em under the
        // 278/240 lines of a styles part with no defaults; the square's 1.3
        // made them 18.07, every three-line row 0.19 taller, and by p17's
        // foot a row went over that Word parts.)
        if wordOnWindows, has("仿宋", "fangsong") {
            var face = square
            face.height = 1.2972
            face.baseline = 1.005 - (1.3 - 1.2972) / 2
            return face
        }
        return square
    }

    /// SimSun's characters from U+00A1 to U+024F an em wide, and those half
    /// one (Simsun.ttc, Word's own; it maps no others there). Plus GB2312's
    /// primes ′ ″, an em as well: zh-cd8987db's "e′（波美度）" in 宋体 steps
    /// 10.6 at 10.5pt in Word's print, ours 2.0.
    private static let simSunFullLatin: [UInt32] = [0x00A4, 0x00A7, 0x00A8, 0x00B0, 0x00B1, 0x00B7, 0x00D7, 0x00F7, 0x2032, 0x2033]
    private static let simSunHalfLatin: [UInt32] = [
        0x00A1, 0x00A2, 0x00A3, 0x00A5, 0x00A6, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
        0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE,
        0x00BF, 0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C6, 0x00C7, 0x00C8, 0x00C9, 0x00CA,
        0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF, 0x00D0, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6,
        0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00DF, 0x00E0, 0x00E1, 0x00E2, 0x00E3,
        0x00E4, 0x00E5, 0x00E6, 0x00E7, 0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF,
        0x00F0, 0x00F1, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC,
        0x00FD, 0x00FE, 0x00FF, 0x0101, 0x0113, 0x011B, 0x012B, 0x0144, 0x0148, 0x014D, 0x0152, 0x0153,
        0x0160, 0x0161, 0x016B, 0x0178, 0x0192, 0x01CE, 0x01D0, 0x01D2, 0x01D4, 0x01D6, 0x01D8, 0x01DA,
        0x01DC, 0x01F9,
    ]

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
    /// `OFFICE_WORD_FONTS=mac`, for what sets text as Word for Mac does
    /// beyond the faces (`Chart.macSimplifiedFace`).
    static var wordForMacFaces: Bool { wordOnMac }
    /// `OFFICE_WORD_FONTS=windows`: the faces Word for Windows sets on a
    /// stock machine — a missing name's font-table alternate where that
    /// is a face it has (仿宋 for 仿宋_GB2312 is its cloud FangSong), else
    /// YaHei — to compare with its prints. The default is the faces the
    /// author had (`fangSongFamily`, the 方正 titles' own line).
    /// The widths and line Word's print gave a face we hold a table for
    /// (Georgia, Garamond, Corbel, Consolas, Century Gothic, Comic Sans),
    /// laid over its stand-in. Word reads it on Windows only; Sheets reads
    /// it through `tabledFace`.
    static func applyTabled(_ family: String, to face: inout RichResolvedFace) {
        switch family.trimmingWhitespace().lowercased() {
                case "comic sans ms": face.advances = comicSansAdvances; face.boldAdvances = comicSansBoldAdvances; face.naturalHeight = 1.3936; face.baseline = 1.1021
                case "garamond": face.advances = garamondAdvances; face.boldAdvances = garamondBoldAdvances; face.italicAdvances = garamondItalicAdvances; face.naturalHeight = 1.1250; face.baseline = 0.8618
                case "georgia": face.advances = georgiaAdvances; face.boldAdvances = georgiaBoldAdvances; face.italicAdvances = georgiaItalicAdvances; face.boldItalicAdvances = georgiaBoldItalicAdvances; face.otherAdvances = georgiaOtherAdvances; face.boldOtherAdvances = georgiaBoldOtherAdvances; face.naturalHeight = 1.1362; face.baseline = 0.9170
                case "candara": face.advances = candaraAdvances; face.boldAdvances = candaraBoldAdvances; face.italicAdvances = candaraItalicAdvances; face.boldItalicAdvances = candaraBoldItalicAdvances; face.naturalHeight = 1.2207; face.baseline = 0.9521
                case "corbel": face.advances = corbelAdvances; face.boldAdvances = corbelBoldAdvances; face.italicAdvances = corbelItalicAdvances; face.boldItalicAdvances = corbelBoldItalicAdvances; face.naturalHeight = 1.2207; face.baseline = 0.9521
                case "consolas": face.advances = consolasAdvances; face.boldAdvances = consolasBoldAdvances; face.italicAdvances = consolasItalicAdvances; face.boldItalicAdvances = consolasBoldItalicAdvances; face.naturalHeight = 1.1709; face.baseline = 0.9199
                case "century gothic": face.advances = centuryGothicAdvances; face.boldAdvances = centuryGothicBoldAdvances; face.italicAdvances = centuryGothicItalicAdvances; face.boldItalicAdvances = centuryGothicBoldItalicAdvances; face.naturalHeight = 1.2261; face.baseline = 1.0059
        default: break
        }
    }

    /// The faces whose Word tables Sheets reads (lower case).
    static let tabledNames: Set<String> = ["georgia", "century gothic", "comic sans ms", "garamond", "corbel", "consolas", "tahoma"]
    nonisolated(unsafe) private static var tabledCache: [String: RichResolvedFace?] = [:]
    private static let tabledLock = RegistryLock()
    static func tabledFaceCached(_ name: String) -> RichResolvedFace? {
        tabledLock.lock(); defer { tabledLock.unlock() }
        if let known = tabledCache[name] { return known }
        let f = tabledFace(name); tabledCache[name] = f; return f
    }

    /// `family`'s stand-in with its own widths laid on, for the faces that
    /// have a table (Windows-gated for Word, here not): what a page of cells reads.
    static func tabledFace(_ family: String) -> RichResolvedFace? {
        guard var face = standInFace(family, eastAsian: false) else { return nil }
        applyTabled(family, to: &face)
        return face
    }

    private static let wordOnWindows = ProcessInfo.processInfo.environment["OFFICE_WORD_FONTS"] == "windows"
    /// The face Word for Windows sets a Latin name it has no face for,
    /// and whose font-table entry gives no alternate, by the entry's
    /// Unicode signature — not its PANOSE (windows' labs `lint` and
    /// `sigmap`, 2026-10-24: zh-c399c91a's "LinTimes", PANOSE Times's,
    /// is Ebrima whatever its PANOSE or family; with no sig, Calibri).
    /// Only the signatures the corpus holds: a Latin-only one, 00000003,
    /// is Times New Roman (zh-e2dc9dce's "Times Roman"); 00000287/
    /// 00000800 Calibri (zh-015abfaf's "Nimbus Roman"); 00007A87/
    /// 80000000 Ebrima. nil: the table's other rules.
    /// (Never for a face Word has, whatever its entry says: zh-2dfde99a's
    /// table gives Times New Roman LinTimes' signature, as WPS writes it.)
    private static func windowsSigFace(_ family: String) -> String? {
        guard !wordMacFamilies.contains(family.trimmingWhitespace().lowercased()),
              let e = fontEntry(family), e.alt?.isEmpty ?? true, let usb0 = e.usb0 else { return nil }
        switch (usb0, e.usb1 ?? 0) {
        // (Only a face of family roman: lo 090716_Studentische_Arbeit_VWS'
        // "Univers 45 Light" (auto) and "DIN-Bold" (swiss), the same
        // signature, are Calibri in Word's print — its headings 2.3pt
        // taller a line than Times'.)
        case (0x0000_0003, 0): return e.family == "roman" ? "times new roman" : nil
        case (0x0000_0287, 0x0000_0800): return "calibri"
        case (0x0000_7A87, 0x8000_0000): return "ebrima"
        // (LibreOffice's "Liberation Serif" entry with no alternate: a name
        // Windows lacks, set in Cambria in Word's print of tdf153136 —
        // 56.7pt for a line of 48pt, Liberation Serif's 55.7 — where the
        // 13 files whose entry names Times New Roman as its alternate
        // print Times. Nor the three others of charset 00 (ANSI) with this entry:
        // lo-e6dce9d6, lo-06933f8e and lo-c4c60fcb print Times; tdf153136's is
        // charset CC.)
        case (0xE000_0AFF, 0x5000_78FF): return e.charset.isEmpty || e.charset == "00" ? nil : "cambria"
        default: return nil
        }
    }
    /// Ebrima's widths, in ems, and its bold's: the characters Word's
    /// print of zh-c399c91a sets in it (its embedded subsets, ebrima.ttf
    /// 2048 units); others keep the sans clone's.
    static let ebrimaAdvances: [UInt32: Double] = [
        0x20: 0.2739, 0x21: 0.2842, 0x22: 0.3921, 0x2A: 0.417, 0x2E: 0.2168, 0x2F: 0.3896,
        0x30: 0.5391, 0x31: 0.5391, 0x32: 0.5391, 0x33: 0.5391, 0x34: 0.5391, 0x35: 0.5391, 0x36: 0.5391, 0x37: 0.5391,
        0x38: 0.5391, 0x39: 0.5391, 0x43: 0.6191, 0x4D: 0.8979, 0x55: 0.687, 0x64: 0.5889, 0x72: 0.3477,
    ]
    static let ebrimaBoldAdvances: [UInt32: Double] = [0x20: 0.2759, 0x21: 0.3271, 0x22: 0.4932, 0x4D: 0.957, 0x64: 0.6191, 0x72: 0.3979]
    /// How much wider Word for Windows sets each character of a face it
    /// emboldens, in ems: one unit of that face's em — 1/256 for KaiTi,
    /// FangSong, SimHei, SimSun and MS Mincho, 1/1024 for DFKai-SB,
    /// PMingLiU and MingLiU, 1/2048 for JhengHei (windows' labs `bold`
    /// and `bold2`, 2026-10-24: bold KaiTi 12pt steps 12.044, 1/256 em).
    /// A name Windows lacks counts as the face its alternate gives.
    /// (Not the Mac's 1/48, and not nothing: zh-457a8d62's bold 標楷體
    /// 16pt on a character grid took a character a line more than Word,
    /// every page after p2 a line ahead; a flat 1/256 for all took
    /// zh-aa3f29a0's 20pt DFKai-SB title onto a second line, and the
    /// alternate's 1/2048 keeps zh-167ee06c's 華康雅風體 — JhengHei UI
    /// Light to Word — where it was.)
    private static func windowsBoldWiden(_ family: String) -> Double {
        func units(_ name: String) -> Double? {
            let n = name.lowercased()
            if ["標楷", "dfkai", "細明", "mingliu"].contains(where: { faceHas(n, $0) }) { return 1024 }
            if ["jhenghei", "正黑", "yahei", "雅黑"].contains(where: { faceHas(n, $0) }) { return 2048 }
            if ["kaiti", "楷体", "fangsong", "仿宋", "simhei", "黑体", "simsun", "宋体", "mincho", "明朝"].contains(where: { faceHas(n, $0) }) { return 256 }
            return nil
        }
        return 1 / (units(family) ?? altName(family).flatMap(units) ?? 256)
    }

    /// Noto Serif CJK TC with its ink moved 0.07 em down (the engine reads the "Ink+" prefix): Word's
    /// print draws PMingLiU's ideographs and marks that much lower than the stand-in's outlines on the
    /// same baseline, 0.062-0.076 em at 9 to 32 pt in seven documents. Advances, metrics and the PDF's
    /// text layer are the stand-in's own. An engine without the prefix draws the face unmoved.
    static let pmingliuInkFamily = "Ink+0.07 Noto Serif CJK TC"

    /// The face a margin balloon sets a Mincho, Song or Ming name's ideographs and kana in, a full em each.
    static func balloonIdeographFace(_ family: String) -> String? { serifIdeographs(family, eastAsianFace(family)) }

    /// The face a Song, Ming or Mincho name's ideographs are drawn in
    /// where the platform has none of those faces: Noto Serif CJK, in
    /// the variant of the name's script. Left to the theme's fallback
    /// every Chinese and Japanese face came out in Noto Sans CJK, where
    /// Word's print of 宋体, 細明體 and ＭＳ 明朝 is a serif (61470's
    /// "東京"). Only the square faces: a name Word on a Mac sets in YaHei
    /// stays sans, as YaHei is. It draws only what the stand-in lacks,
    /// so letters and digits keep their widths and the lines their breaks.
    private static func serifIdeographs(_ family: String, _ ea: EastAsianFace) -> String? {
        #if os(macOS)
        return wordMacIdeographs(family, ea)
        #elseif os(Linux)
        guard abs(ea.height - square.height) < 0.01 else { return nil }
        let n = family.trimmingWhitespace().lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { faceHas(n, $0) } }
        if has("mincho", "明朝") { return "Noto Serif CJK JP" }
        if has("mingliu", "明體") { return pmingliuInkFamily }
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
    /// The Arabic and Hebrew faces Word for Windows has of its own, which a
    /// missing complex-script name must not be mistaken for.
    private static let windowsComplexFaces: Set<String> = [
        "traditional arabic", "sakkal majalla", "arabic typesetting", "simplified arabic", "simplified arabic fixed", "andalus",
        "segoe ui", "tahoma", "aharoni", "david", "miriam", "narkisim", "gisha", "levenim mt", "frankruehl", "rod", "miriam fixed",
        "microsoft sans serif", "sylfaen", "urdu typesetting", "aldhabi", "estrangelo edessa", "mudir mt", "times new roman", "arial",
        "calibri", "cambria", "cambria math", "courier new", "dubai", "myriad arabic", "arial unicode ms", "gadugi", "nirmala ui", "leelawadee ui",
    ]

    /// FrankRuehl's own advances (em), read from the face embedded in Word's prints (7 prints, no conflicts): its Hebrew letters, digits and marks.
    static let frankRuehlOtherAdvances: [UInt32: Double] = [0x20: 0.2070, 0x21: 0.4429, 0x22: 0.3872, 0x27: 0.2212, 0x28: 0.2769, 0x29: 0.2769, 0x2C: 0.2212, 0x2D: 0.3320, 0x2E: 0.2212, 0x2F: 0.3599, 0x30: 0.4150, 0x31: 0.4150, 0x32: 0.4150, 0x33: 0.4150, 0x34: 0.4150, 0x35: 0.4150, 0x36: 0.4150, 0x37: 0.4150, 0x38: 0.4150, 0x39: 0.4150, 0x3A: 0.3320, 0x3B: 0.3320, 0x5B: 0.2769, 0x5D: 0.2769, 0x5D0: 0.4702, 0x5D1: 0.4429, 0x5D2: 0.3320, 0x5D3: 0.4150, 0x5D4: 0.4702, 0x5D5: 0.2769, 0x5D6: 0.2769, 0x5D7: 0.4980, 0x5D8: 0.4980, 0x5D9: 0.2490, 0x5DA: 0.4150, 0x5DB: 0.4150, 0x5DC: 0.4150, 0x5DD: 0.4702, 0x5DE: 0.4980, 0x5DF: 0.2769, 0x5E0: 0.2769, 0x5E1: 0.4429, 0x5E2: 0.4429, 0x5E3: 0.4429, 0x5E4: 0.4429, 0x5E5: 0.4429, 0x5E6: 0.4429, 0x5E7: 0.4429, 0x5E8: 0.3872, 0x5E9: 0.5811, 0x5EA: 0.4702, 0x2013: 0.5000]
    static let davidOtherAdvances: [UInt32: Double] = [0x0: 0.0000, 0xD: 0.2212, 0x20: 0.2212, 0x21: 0.3042, 0x22: 0.4429, 0x25: 0.7749, 0x27: 0.2212, 0x28: 0.2490, 0x29: 0.2490, 0x2A: 0.3599, 0x2B: 0.6108, 0x2C: 0.2490, 0x2D: 0.3320, 0x2E: 0.2490, 0x2F: 0.3320, 0x30: 0.4429, 0x31: 0.4429, 0x32: 0.4429, 0x33: 0.4429, 0x34: 0.4429, 0x35: 0.4429, 0x36: 0.4429, 0x37: 0.4429, 0x38: 0.4429, 0x39: 0.4429, 0x3A: 0.3872, 0x3B: 0.3872, 0x3F: 0.3599, 0x40: 0.9209, 0x41: 0.7222, 0x45: 0.6108, 0x46: 0.5562, 0x49: 0.3330, 0x4C: 0.6108, 0x4D: 0.8892, 0x52: 0.6670, 0x53: 0.5562, 0x54: 0.6108, 0x55: 0.7222, 0x5B: 0.2490, 0x5D: 0.2490, 0x5F: 0.5039, 0x61: 0.4438, 0x63: 0.4438, 0x64: 0.5000, 0x65: 0.4438, 0x66: 0.3330, 0x67: 0.5000, 0x68: 0.5000, 0x69: 0.2778, 0x6A: 0.2778, 0x6B: 0.5000, 0x6C: 0.2778, 0x6D: 0.7778, 0x6E: 0.5000, 0x6F: 0.5000, 0x70: 0.5000, 0x72: 0.3330, 0x73: 0.3892, 0x74: 0.2778, 0x75: 0.5000, 0x76: 0.5000, 0x77: 0.7222, 0x78: 0.5000, 0xBD: 0.6641, 0x5D0: 0.5811, 0x5D1: 0.4702, 0x5D2: 0.3320, 0x5D3: 0.4702, 0x5D4: 0.5532, 0x5D5: 0.3042, 0x5D6: 0.3599, 0x5D7: 0.5532, 0x5D8: 0.5811, 0x5D9: 0.3042, 0x5DA: 0.4702, 0x5DB: 0.4702, 0x5DC: 0.4429, 0x5DD: 0.6089, 0x5DE: 0.5811, 0x5DF: 0.3042, 0x5E0: 0.3042, 0x5E1: 0.5811, 0x5E2: 0.4429, 0x5E3: 0.4702, 0x5E4: 0.4429, 0x5E5: 0.4429, 0x5E6: 0.4980, 0x5E7: 0.5811, 0x5E8: 0.4702, 0x5E9: 0.6089, 0x5EA: 0.5811, 0x2009: 0.0977, 0x2013: 0.5000, 0x2022: 0.3501, 0x20AA: 0.7280, 0x25CC: 0.5942, 0xF8FF: 0.3042, 0xFB2A: 0.6089, 0xFB2B: 0.6089, 0xFB35: 0.3042, 0xFB4B: 0.3042, 0xFB4F: 0.5811]
    static let davidBoldOtherAdvances: [UInt32: Double] = [0x0: 0.0000, 0xD: 0.2212, 0x20: 0.2212, 0x21: 0.3872, 0x22: 0.4980, 0x25: 0.7749, 0x27: 0.2769, 0x28: 0.3042, 0x29: 0.3042, 0x2A: 0.3599, 0x2B: 0.6108, 0x2C: 0.2769, 0x2D: 0.4429, 0x2E: 0.2769, 0x2F: 0.3599, 0x30: 0.4429, 0x31: 0.4429, 0x32: 0.4429, 0x33: 0.4429, 0x34: 0.4429, 0x35: 0.4429, 0x36: 0.4429, 0x37: 0.4429, 0x38: 0.4429, 0x39: 0.4429, 0x3A: 0.3872, 0x3B: 0.3872, 0x3D: 0.6108, 0x3F: 0.4429, 0x42: 0.6670, 0x45: 0.6670, 0x4C: 0.6670, 0x4D: 0.9438, 0x52: 0.7222, 0x58: 0.7222, 0x5B: 0.3042, 0x5D: 0.3042, 0x5F: 0.5039, 0x63: 0.4438, 0x64: 0.5562, 0x65: 0.4438, 0x66: 0.3330, 0x6E: 0.5562, 0x6F: 0.5000, 0x72: 0.4438, 0x73: 0.3892, 0x74: 0.3330, 0x75: 0.5562, 0x5D0: 0.5532, 0x5D1: 0.4702, 0x5D2: 0.3599, 0x5D3: 0.4702, 0x5D4: 0.5811, 0x5D5: 0.2769, 0x5D6: 0.3320, 0x5D7: 0.5532, 0x5D8: 0.6089, 0x5D9: 0.3320, 0x5DA: 0.4702, 0x5DB: 0.4702, 0x5DC: 0.4429, 0x5DD: 0.6089, 0x5DE: 0.5811, 0x5DF: 0.2769, 0x5E0: 0.3320, 0x5E1: 0.6089, 0x5E2: 0.4702, 0x5E3: 0.4702, 0x5E4: 0.4980, 0x5E5: 0.4702, 0x5E6: 0.4702, 0x5E7: 0.5811, 0x5E8: 0.4702, 0x5E9: 0.6919, 0x5EA: 0.5811, 0x2009: 0.0977, 0x2013: 0.5000, 0x20AA: 0.7280, 0x25CC: 0.5942, 0xF8FF: 0.3320, 0xFB4F: 0.5532]
    // (Times New Roman's Hebrew letters, read from Word's prints of the Hebrew docs in xb: the Liberation Serif stand-in's are 14% wider.)
    static let timesHebrewAdvances: [UInt32: Double] = [0x5BE: 0.356, 0x5D0: 0.481, 0x5D1: 0.455, 0x5D2: 0.335, 0x5D3: 0.419, 0x5D4: 0.471, 0x5D5: 0.279, 0x5D6: 0.286, 0x5D7: 0.477, 0x5D8: 0.476, 0x5D9: 0.267, 0x5DA: 0.452, 0x5DB: 0.433, 0x5DC: 0.432, 0x5DD: 0.507, 0x5DE: 0.485, 0x5DF: 0.274, 0x5E0: 0.305, 0x5E1: 0.475, 0x5E2: 0.454, 0x5E3: 0.454, 0x5E4: 0.440, 0x5E5: 0.482, 0x5E6: 0.460, 0x5E7: 0.474, 0x5E8: 0.469, 0x5E9: 0.610, 0x5EA: 0.500, 0x5F3: 0.209, 0x5F4: 0.372]
    static let timesHebrewBoldAdvances: [UInt32: Double] = [0x5BE: 0.363, 0x5D0: 0.527, 0x5D1: 0.459, 0x5D2: 0.367, 0x5D3: 0.464, 0x5D4: 0.512, 0x5D5: 0.298, 0x5D6: 0.317, 0x5D7: 0.504, 0x5D8: 0.529, 0x5D9: 0.311, 0x5DA: 0.458, 0x5DB: 0.446, 0x5DC: 0.435, 0x5DD: 0.511, 0x5DE: 0.533, 0x5DF: 0.326, 0x5E0: 0.316, 0x5E1: 0.478, 0x5E2: 0.507, 0x5E3: 0.493, 0x5E4: 0.457, 0x5E5: 0.564, 0x5E6: 0.515, 0x5E7: 0.483, 0x5E8: 0.464, 0x5E9: 0.688, 0x5EA: 0.518, 0x5F3: 0.255, 0x5F4: 0.460]
    private static let windowsArabicWidthsOn = true
    // (Arabic and Hebrew faces Windows has and we do not: their own line heights.)
    private static let windowsArabicLines: [String: Double] = ["traditional arabic": 1.495, "sakkal majalla": 1.40, "simplified arabic": 3395.0 / 2048, "david": 2015.0 / 2048, "frankruehl": 1904.0 / 2048]

    /// An installed complex-script face of its own (David, Simplified Arabic, Urdu Typesetting...): Word's prints draw a
    /// right-to-left run of digits in it. Arial, Times New Roman and Tahoma are the Latin faces too, and a name Windows
    /// lacks (B Nazanin) is not here: their digits take the run's Latin face (dx2 79a15231; xd David docs keep David).
    static func complexFaceKeepsDigits(_ name: String) -> Bool {
        let n = name.trimmingWhitespace().lowercased()
        return windowsComplexFaces.contains(n) && !["arial", "times new roman", "tahoma", "segoe ui", "microsoft sans serif"].contains(n)
    }

    static func complexFace(_ family: String?) -> RichResolvedFace? {
        // (A face neither embedded nor on the machine is the one Word sets
        // the text in, Times New Roman, and not a name nothing answers to:
        // rtl.docx's "Noto Sans Arabic UI" took the platform's default face
        // for its lines' height — Segoe UI's 1.33 em on Windows, 15.96pt a
        // 12pt line where Word's step 14 — and every line from the third
        // stood over 3pt low.)
        // (Its spaces and neutral marks in Cambria, the Arabic in Times:
        // Word-win's rtl print has 115 spaces of Cambria's 2.64pt at 12pt
        // and the letters in TimesNewRomanPSMT. In Times' own 3.0pt spaces
        // the paragraph's lines took three letters fewer each, and it ran
        // to 8 lines where Word's has 7.)
        var name = family ?? "Times New Roman"
        var missing = embeddedFamily(name) == nil && installedFamilies[name.trimmingWhitespace().lowercased()] == nil
        // (A name the font table gives an Arabic charset (B2) and no more is
        // Arial in Word for Windows' print, not Times: lo tdf163575's
        // "B Mitra". A name the table does not know stays Times', as
        // rtl.docx's "Noto Sans Arabic UI".)
        // (And a complex-script name the table lists with no alternate, whatever its
        // charset, that Word's Windows does not have: Arial, as Word's prints set
        // Guttman Keren (Hebrew, B1) and Jameel Noori Nastaleeq, Alvi Nastaleeq
        // (Urdu, charset 00) — heb-z5059159, urd-z8387389, z7427432, z17694236 —
        // where the same Jameel with Times New Roman as its alternate, urd-z7538882's
        // table, prints in Times. The faces Windows ships are as they were.)
        if missing, wordOnWindows, let entry = fontEntry(name), !Self.windowsComplexFaces.contains(name.trimmingWhitespace().lowercased()),
           entry.alt?.trimmingWhitespace().isEmpty ?? true {
            RuleTrace.hit("missing-complex-face-is-arial")
            name = "Arial"
            missing = false
        }
        // (A file that NAMES Times New Roman or Arial for its complex text
        // has them on Word's machine, whatever this one holds: lo tdf129659's
        // Hebrew body sets its spaces and marks in Times New Roman, not the
        // Cambria of a face Word lacks.)
        let wordHasIt = wordOnWindows && ["times new roman", "arial", "tahoma"].contains(name.trimmingWhitespace().lowercased())
        if missing, wordHasIt { missing = false }
        let asked = name.trimmingWhitespace().lowercased()
        if missing { name = "Times New Roman" }
        var face = RichResolvedFace(family: missing ? cambria : embeddedFamily(name) ?? name)
        face.fallback = [cambria, "Times New Roman", "Noto Naskh Arabic", emojiPictographs, "DejaVu Sans"]
        // (Hebrew in Times New Roman or Arial: the Liberation clones have
        // the letters at Times' and Arial's widths — alef 0.600 em, 0.628
        // — where the chain's first face with Hebrew was DejaVu Sans at
        // 0.668, which broke lo tdf129659's paragraph a word early and
        // set its letters in the wrong face. Arabic has no Liberation
        // glyphs and still falls through to the Naskh.)
        switch name.trimmingWhitespace().lowercased() {
        case "times new roman": face.fallback.insert("Liberation Serif", at: 2)
        case "arial": face.fallback.insert("Liberation Sans", at: 2)
        default: break
        }
        // (Word for Windows' Arabic in Arial and Times New Roman, which the
        // stand-ins have none of: Noto Naskh draws it, 11% wider than Arial
        // over zh-d97c5474's Arabic paragraph — 1817pt to Word's 1634 —
        // and its lines broke elsewhere. Each word is set to its joining
        // forms' widths in Word's face.)
        if wordOnWindows, embeddedFamily(name) == nil {
            switch name.trimmingWhitespace().lowercased() {
            case "arial":
                // (In the sans Arabic, nearer Arial's than the Naskh is.)
                face.fallback = [cambria, "Times New Roman", "Liberation Sans", "Noto Sans Arabic", "Noto Naskh Arabic", emojiPictographs, "DejaVu Sans"]
                face.joinedAdvances = WindowsArabicAdvances.arial
                face.boldJoinedAdvances = WindowsArabicAdvances.arialBold
            case "times new roman":
                face.joinedAdvances = WindowsArabicAdvances.times
                face.boldJoinedAdvances = WindowsArabicAdvances.timesBold
                face.otherAdvances = timesHebrewAdvances; face.boldOtherAdvances = timesHebrewBoldAdvances
            case "tahoma":
                // (Tahoma's own Arabic, read from its hmtx: the Urdu docs name it throughout.)
                face.joinedAdvances = WindowsArabicAdvances.tahoma
                face.boldJoinedAdvances = WindowsArabicAdvances.tahomaBold
            default: break
            }
            if missing, Self.windowsArabicWidthsOn {
                switch asked {
                case "traditional arabic":
                    face.joinedAdvances = WindowsArabicAdvances.tradArabic
                    face.boldJoinedAdvances = WindowsArabicAdvances.tradArabicBold
                    face.joinedClusters = WindowsArabicAdvances.tradArabicClusters
                    face.boldJoinedClusters = WindowsArabicAdvances.tradArabicBoldClusters
                case "sakkal majalla":
                    face.joinedAdvances = WindowsArabicAdvances.sakkal
                    face.boldJoinedAdvances = WindowsArabicAdvances.sakkalBold
                    face.joinedClusters = WindowsArabicAdvances.sakkalClusters
                    face.boldJoinedClusters = WindowsArabicAdvances.sakkalBoldClusters
                default: break
                }
            }
        }
        // (Traditional Arabic's and Sakkal Majalla's own lines, which Windows has and we
        // do not: Word's prints step single-spaced 14pt lines 20.93 and 19.6 apart,
        // 1.495 and 1.40 em — ara-z8157766 and ara-z18174368 — where the Times
        // stand-in's 1.15 ran those documents two pages short in three.)
        // (FrankRuehl, which Windows has and we do not: the headers of the Israeli court files set it at 14pt, 0.415 em a digit
        // where the stand-in's digits are wider, and the line of case number and parties wrapped one word early. xd 38d880e8.)
        if wordOnWindows, missing, embeddedFamily(asked) == nil, asked == "frankruehl" {
            RuleTrace.hit("windows-frankruehl-own-advances")
            face.otherAdvances = frankRuehlOtherAdvances; face.boldOtherAdvances = frankRuehlOtherAdvances
        }
        if wordOnWindows, missing, embeddedFamily(asked) == nil, let tall = Self.windowsArabicLines[asked] {
            RuleTrace.hit("windows-arabic-face-own-line")
            // (David: hhea 1505 + 510 over 2048, bold the same, read from Word's prints; 12pt lines at 1.5 step 17.7.)
            // (FrankRuehl: hhea 1462 + 442 over 2048, from the face embedded in Word's prints.)
            if asked == "frankruehl" { face.baseline = 1462.0 / 2048 }
            if asked == "david" {
                face.baseline = 1505.0 / 2048
                // (Its Hebrew letters' own advances, read from Word's prints: set word by word, `joinedScaled`.)
                face.otherAdvances = davidOtherAdvances; face.boldOtherAdvances = davidBoldOtherAdvances
            }
            face.naturalHeight = tall; face.boldHeight = asked == "simplified arabic" ? 3405.0 / 2048 : tall
            // (Simplified Arabic: hhea 2416 + 979 over 2048, bold 989, from Word's print; a4945c74's 14pt lines under a 0.7 multiple step 16.3.)
        }
        // (… and its clone first in the chain, so the spaces and marks are set
        // in the clone and not the Cambria stand-in that comes before it.)
        if wordHasIt, embeddedFamily(name) == nil, installedFamilies[name.trimmingWhitespace().lowercased()] == nil {
            let clone = ["arial", "tahoma"].contains(name.trimmingWhitespace().lowercased()) ? "Liberation Sans" : "Liberation Serif"
            face.fallback.removeAll { $0 == clone }
            face.fallback.insert(clone, at: 0)
            // (Arial's own line: 1.1499 em, 13.8pt at 12 — the Cambria stand-in's
            // 14.0 put lo tdf163575's page 19pt low.)
            if clone == "Liberation Sans" { face.naturalHeight = 1.1499; face.baseline = 0.9053 }
            // (Tahoma's complex face: its own line, 2049 + 423 over 2048, and the sans Arabic after the clone.)
            if asked == "tahoma" {
                face.naturalHeight = 1.2070; face.baseline = 1.0005; face.boldHeight = 1.2070
                face.fallback = ["Liberation Sans", cambria, "Times New Roman", "Liberation Sans", "Noto Sans Arabic", "Noto Naskh Arabic", emojiPictographs, "DejaVu Sans"]
                RuleTrace.hit("tahoma-complex-face")
            }
        }
        return face
    }

    /// The face to set `family` in (the theme's `faceResolver`): the stand-in
    /// and its corrections (`standInFace`), or — where the machine has the
    /// face itself and the user takes the machine's faces — that face, with
    /// Word's line and baseline for it but none of the widths, scales or
    /// substitutes that make a stand-in pass for it.
    static func face(_ family: String?, eastAsian: Bool) -> RichResolvedFace? {
        let face = standInFace(family, eastAsian: eastAsian)
        guard let family, let face else { return face }
        guard let own = installed(family) ?? installedOriginal(of: face.family, for: family, math: face.setsMath) else { return face }
        return installedFace(own, as: face)
    }

    /// The machine's own face that the stand-in `standIn` is a clone of,
    /// for a name the machine lacks: the face Word sets the name in. So
    /// 仿宋_GB2312, which Windows substitutes with FangSong (FontSubstitutes'
    /// FangSong_GB2312), is FangSong, as Word's print of zh-6d1afa56 has it,
    /// and a Latin name Word gives Arial or Times New Roman is that. A
    /// stand-in that is the machine's own face already — the YaHei a 方正
    /// name is set in — has none, and keeps Word's corrections. An East
    /// Asian name's Latin is its face's too, not its clone's (a square
    /// face's Liberation Mono is not Courier New): zh-6d1afa56's
    /// 仿宋_GB2312 digits are FangSong's in Word's print.
    /// (Only where Word has no face of the name either: a math face, or off
    /// Windows a face Word brings with it, is that face in Word's print,
    /// not the clone's original. bug59058's Cambria Math — in Word for Mac's
    /// own fonts, not the Mac's — went to Times New Roman, its ∑ out of a
    /// system fallback at 14.3pt where Word's is 6.86, and the document fell
    /// from 99.9 to 76.5 against the Mac's prints.)
    static func installedOriginal(of standIn: String, for family: String, math: Bool) -> String? {
        guard !math else { return nil }
        #if !os(Windows)
        guard !wordMacFamilies.contains(family.trimmingWhitespace().lowercased()) else { return nil }
        #endif
        let n = standIn.trimmingWhitespace().lowercased()
        let original: String? = isEastAsianFace(family)
            ? (n == starlingFangSong.lowercased() || fangSongFamily(family) == starlingFangSong ? "FangSong" : nil)
            : [sans.lowercased(): "Arial", wordSans.lowercased(): "Arial", serif.lowercased(): "Times New Roman",
               wordSerif.lowercased(): "Times New Roman", mono.lowercased(): "Courier New", calibri.lowercased(): "Calibri",
               cambria.lowercased(): "Cambria", verdana.lowercased(): "Verdana"][n]
        return original.flatMap(installed)
    }

    /// `face` made the machine's own: the drawn family, and of the stand-in's
    /// settings only what Word does with the face whatever draws it — its
    /// line, its baseline, the widening of a face it emboldens — and what
    /// Word does past the face's own glyphs: the widths it sets characters
    /// past ASCII at, read from its print, and the faces it falls back to.
    /// (Windows' local check of zh-4f70ee2d, 512 -> 462 lines: p14's line
    /// opens "③", which Times New Roman lacks; Word sets it in Cambria
    /// Math, 19.44 wide, and the stand-in's table says so — the installed
    /// Times without it fell back to DejaVu Sans' 14.34, and "方" came up.)
    static func installedFace(_ own: String, as standIn: RichResolvedFace) -> RichResolvedFace {
        var face = RichResolvedFace(family: own, naturalHeight: standIn.naturalHeight, boldSpread: standIn.boldSpread,
                                    baseline: standIn.baseline, isEastAsian: standIn.isEastAsian)
        face.scaledHeight = standIn.scaledHeight
        face.scaledBaseline = standIn.scaledBaseline
        face.boldHeight = standIn.boldHeight
        face.boldBaseline = standIn.boldBaseline
        face.setsMath = standIn.setsMath
        #if os(Windows)
        // (A face with no bold of its own, which Word emboldens, DirectWrite
        // emboldens too, and sets each character 5/256 of an em wider for it,
        // where Word widens it by one unit of the face's em alone: lab `bw`
        // (Word for Windows, 標楷體, 楷体, 黑体, 仿宋 and 新細明體 at 10 to
        // 24pt) — bold DFKai-SB 12pt steps 12.014 in Word's print, 12.246 in
        // ours, and zh-ae2dd08d's bold cell "材料費編列" lost its "列".)
        if face.boldSpread > 0 { face.boldSpread -= 5.0 / 256 }
        #endif
        face.malgunSymbols = standIn.malgunSymbols
        face.otherAdvances = standIn.otherAdvances
        face.boldOtherAdvances = standIn.boldOtherAdvances
        face.fullWidthSymbols = standIn.fullWidthSymbols
        face.missingGlyphAdvance = standIn.missingGlyphAdvance
        face.lacksCompatibilityIdeographs = standIn.lacksCompatibilityIdeographs
        face.fallback = standIn.fallback
        face.symbolFamily = standIn.symbolFamily
        face.symbolsInBold = standIn.symbolsInBold
        return face
    }

    /// Where text is drawn from (T203, the user's choice): the faces this
    /// machine has (`local`, the default), else the stand-ins this app
    /// ships; or the stand-ins only (`bundled`). OFFICE_FONT_SOURCE=bundled
    /// or local wins over the user's setting — every harness pins bundled,
    /// so that no baseline moves with the machine's fonts. The web has no
    /// list of the machine's faces: bundled only.
    enum FontSource: String { case local, bundled }
    nonisolated(unsafe) private static var _fontSource: FontSource? = nil
    static var fontSource: FontSource {
        #if os(WASI)
        return .bundled
        #else
        if let s = _fontSource { return s }
        let env = ProcessInfo.processInfo.environment["OFFICE_FONT_SOURCE"].flatMap { FontSource(rawValue: $0.lowercased()) }
        let s = env ?? (OfficeSettings.useInstalledFonts ? .local : .bundled)
        _fontSource = s
        return s
        #endif
    }
    /// Whether the user's setting is overridden by OFFICE_FONT_SOURCE (the
    /// settings page then says so).
    static var fontSourcePinned: Bool { ProcessInfo.processInfo.environment["OFFICE_FONT_SOURCE"].flatMap { FontSource(rawValue: $0.lowercased()) } != nil }
    /// Forget the cached choice, after the user changes it.
    static func fontSourceChanged() { _fontSource = nil }

    /// The face the machine has for `family`, as it names it, where the user
    /// takes the machine's faces; nil otherwise.
    static func installed(_ family: String) -> String? {
        guard fontSource == .local else { return nil }
        let n = family.trimmingWhitespace().lowercased()
        guard !n.isEmpty else { return nil }
        return installedFamilies[n]
    }

    /// The family a run named `family` is drawn in (the theme's
    /// `fontFamilyResolver`): the machine's own (`installed`), else the
    /// stand-in (`substitute`, which the layout's rules still read).
    static func drawn(_ family: String) -> String {
        installed(family) ?? installedOriginal(of: substitute(family), for: family, math: standInFace(family, eastAsian: false)?.setsMath ?? false)
            ?? substitute(family)
    }

    /// The machine's faces by name, lowercased: fontconfig's families on
    /// Linux, Core Text's on macOS and iOS, and on Windows every family its
    /// font files name (`systemFamilies`), with the faces `windowsFaces`
    /// finds the files of — Office's cloud faces among them — over those.
    /// (On iOS that is the system's faces and any the app registered;
    /// fonts a font-provider app installs are another app's, and Core Text
    /// lists them only to apps that ask for them by entitlement.)
    static let installedFamilies: [String: String] = {
        var m: [String: String] = [:]
        #if os(Windows)
        m = systemFamilies
        for (name, face) in windowsFaces { m[name] = face }
        #elseif os(macOS) || os(iOS)
        for name in (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? [] { m[name.lowercased()] = name }
        #elseif os(Linux)
        let tool = ["/usr/bin/fc-list", "/bin/fc-list"].first { FileManager.default.isExecutableFile(atPath: $0) }
        if let tool {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = [":", "family"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    // (Each face's names, comma-separated — its own and its
                    // localized ones, "SimSun,宋体" — any of which fontconfig
                    // matches; "\-" escapes a hyphen.)
                    for name in line.split(separator: ",") {
                        let family = String(name).replacingAll("\\-", with: "-").trimmingWhitespace()
                        if !family.isEmpty { m[family.lowercased()] = family }
                    }
                }
            }
        }
        #endif
        return m
    }()

    static func standInFace(_ family: String?, eastAsian: Bool) -> RichResolvedFace? {
        guard let family else { return nil }
        if let alt = macTableAlternate(family) { return standInFace(alt, eastAsian: eastAsian) }
        // (Word's Korean faces are one family under two names: a run naming 맑은 고딕 for its Latin text is Malgun Gothic, line and all.
        // xd 658a33bb: ascii 맑은 고딕 gave the empty 20pt marks Carlito's 28 pt line where Word's print steps Malgun's 39.8.)
        if wordOnWindows, !eastAsian, family.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }),
           family.trimmingWhitespace() == "맑은 고딕" {
            RuleTrace.hit("hangul-named-malgun-latin-is-malgun-gothic")
            return standInFace("Malgun Gothic", eastAsian: false)
        }
        let own = isEastAsianFace(family)
        // (A face Windows lacks whose font table names Malgun Gothic as the alternate: Word draws its Latin letters, digits and
        // spaces in Malgun Gothic, a 0.35 em space where Liberation Sans' is 0.28. dx2 e86e26f7, Siyam Rupali: 71.7 to 78.3.)
        if wordOnWindows, !own, !eastAsian, !isEmbedded(family), family.trimmingWhitespace().lowercased() != "malgun gothic",
           fontEntry(family)?.alt?.trimmingWhitespace().lowercased() == "malgun gothic" {
            RuleTrace.hit("missing-face-with-malgun-alternate-latin-is-malgun")
            return standInFace("Malgun Gothic", eastAsian: false)
        }
        // (A Hangul-named face Word for Windows lacks, with no font-table entry (so no altName, which Word follows first):
        // Word draws its Latin letters, digits and spaces in Yu Gothic Regular whatever the language (labs kor-yu c, d, e;
        // Hangul stays Malgun). Without it a theme face such as 함초롬돋움 gave pure-English lines Malgun's 1.729 em
        // where Word's Yu Gothic is 1.673 (kor-z19581051-22de7d pages 3-7: 18.5 pt pitch against 18.0).)
        if wordOnWindows, !eastAsian, !isEmbedded(family), fontEntry(family) == nil,
           family.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }),
           !["맑은 고딕", "바탕", "바탕체", "돋움", "돋움체", "굴림", "굴림체", "궁서", "궁서체", "새굴림", "새돋움", "새바탕", "새궁서", "나눔고딕"].contains(family.trimmingWhitespace()) {
            RuleTrace.hit("missing-hangul-face-no-entry-latin-is-yu-gothic")
            return standInFace("Yu Gothic", eastAsian: false)
        }
        // (A Latin-named face Word for Windows lacks, whose font-table entry has charset 80 (Shift-JIS) and no alternate name:
        // Word draws it in Yu Gothic Regular, line 1.67 em (lab fallback-ft 1, against charset 00 which gives Calibri). The
        // same fallback as the Hangul-named case above and amd-1's Arial Unicode MS (charset 80).)
        if wordOnWindows, !eastAsian, !isEmbedded(family), let e = fontEntry(family), e.charset.uppercased() == "80",
           (e.alt ?? "").trimmingWhitespace().isEmpty,
           !WordWindowsFaces.names.contains(family.trimmingWhitespace().lowercased()),
           !(family.trimmingWhitespace().lowercased() == "arial unicode ms" && documentHasIndicText),
           !family.unicodeScalars.contains(where: { $0.value > 0x24F }) {
            RuleTrace.hit("missing-latin-face-charset-80-is-yu-gothic")
            return standInFace("Yu Gothic", eastAsian: false)
        }
        // (A Latin-named East Asian face Word for Windows lacks, with no font-table entry ("Noto Sans CJK JP"): Word draws
        // its Latin-only lines in Cambria, line 1.172 em, while its ideographs stay MS Mincho's. Taken for Mincho throughout,
        // jpn-z20806225-930d98's Latin lines stepped 15.0 where Word's print steps 13.5, and the document ran a page long.)
        if wordOnWindows, own, !eastAsian, !isEmbedded(family), fontEntry(family) == nil,
           family.unicodeScalars.allSatisfy({ $0.isASCII }), windowsMissingFallback(family) == "mincho" {
            RuleTrace.hit("missing-latin-named-ea-face-latin-lines-are-cambria")
            return standInFace("Cambria", eastAsian: false)
        }
        guard own || eastAsian else {
            // (A Latin-named face Word for Windows lacks, whose font-table
            // entry says charset 80 (Shift-JIS) and alternate Times New
            // Roman, is not Times there: Word reads it as an East Asian font
            // it has to substitute, sets its text in Calibri and its line
            // 1.875 ems tall — 22.5pt at 12, 44.9 at 24 — where charset 00,
            // or no entry, is Times' 1.15. Lab tdf (windows 01QbbApP, on
            // tdf103931's Liberation Serif): 33.9pt paragraphs, 24.0 once the
            // charset is 00 or the entry gone. Only this entry is probed.)
            if wordOnWindows, charsetEightyLatinFace(family), var face = standInFace(calibri, eastAsian: false) {
                let before = face.naturalHeight ?? 1.2207
                face.naturalHeight = 1.875
                face.baseline = (face.baseline ?? 0.9625) + (1.875 - before) / 2
                return face
            }
            // A Latin face: its clone, and where Word sets the baseline
            // of the face it is the clone of — its ascent under its line
            // gap (Arial .905 + .033, Times .891 + .042, Calibri .75 +
            // .22, Cambria .95, Courier .833).
            if wordOnWindows, let registered = embeddedFamily(family), registered.hasPrefix("Starling Embedded Latin "),
               let line = embeddedLatinLine(registered) {
                var face = RichResolvedFace(family: registered, baseline: line.ascent)
                face.naturalHeight = line.ascent + line.descent
                face.fallback = ["Times New Roman", "Liberation Serif", "DejaVu Sans"]
                return face
            }
            let clone = substitute(family)
            let baseline: Double
            switch clone {
            case serif: baseline = 0.933
            case mono: baseline = 0.833
            case calibri: baseline = 0.9625
            case cambria: baseline = 0.95
            // (Noto Sans, bundled, is its own face: its baseline is its ascent, 2189 of 2048, no gap. The default's .938 stood
            // every line 0.13 em high: lo-27918bf0's 14pt lines 1.9pt, its 12pt 1.6, in Word's print.)
            case notoSans: baseline = 1.0688
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
                if wordOnWindows {
                    face.advances = aptosAdvances
                    face.boldAdvances = aptosBoldAdvances
                    RuleTrace.hit("aptos-own-widths")
                }
            }
            // Segoe UI's Latin line in Mac Word is its own 2210/514
            // ascent/descent in 2048 units. A fresh five-line 12pt probe
            // steps 15.96pt, where the Arial stand-in gave 13.8. Keep
            // these metrics when it shares a line with MS Gothic or
            // JhengHei (zh-8d72961c), without imposing one paragraph strut.
            if wordOnMac || wordOnWindows, family.trimmingWhitespace().lowercased() == "segoe ui" {
                face.naturalHeight = 2724.0 / 2048
                face.baseline = 2210.0 / 2048
                // (And its own widths, from Word's prints: see `segoeUIAdvances`.)
                face.advances = segoeUIAdvances
                face.boldAdvances = segoeUIBoldAdvances
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(segoeUIOtherAdvances) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(segoeUIBoldOtherAdvances) { $1 }
                RuleTrace.hit("segoe-ui-own-widths")
            }
            // Book Antiqua's own line in Word for Windows' print: hhea 1891 over and 578 under of 2048 (1.2056 em; ara-z4399437's
            // 8pt lines step 9.65 where the Times stand-in's 1.15 stepped 9.2, and its empty 12pt paragraphs stood 20pt short in all).
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "book antiqua" {
                face.naturalHeight = 2469.0 / 2048
                face.baseline = 1891.0 / 2048
                RuleTrace.hit("book-antiqua-own-line")
            }
            // Franklin Gothic Medium Cond's own line (hhea 1886 over, 436 under of 2048: 1.134 em): the line Word gives an
            // empty paragraph mark set in GHEA Grapalat (dx2 05a96a87: marks step 15.7 at 12 pt, 1.15 multiple).
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "franklin gothic medium cond" {
                face.naturalHeight = 2322.0 / 2048
                face.baseline = 1886.0 / 2048
                RuleTrace.hit("franklin-cond-own-line")
            }
            // Sylfaen's own line in Word for Windows' print: win 2062 over and 635 under of 2048 (1.317 em). xs 5ed52035's 11pt
            // Armenian lines (set in GHEA Grapalat, which Word for Windows lacks and draws as Sylfaen) at 1.0667 step 15.5 in Word, where the DejaVu stand-in stepped 14.0; and its own widths.
            if wordOnWindows, ["sylfaen", "ghea grapalat"].contains(family.trimmingWhitespace().lowercased()) {
                face.naturalHeight = 2697.0 / 2048
                face.baseline = 2062.0 / 2048
                face.advances = sylfaenAdvances
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(sylfaenOtherAdvances) { $1 }
                // (No bold in the prints: the regular widths stand for it.)
                face.boldAdvances = sylfaenAdvances
                face.boldOtherAdvances = face.otherAdvances
                RuleTrace.hit("sylfaen-own-line")
                // GHEA Grapalat whose font table gives Franklin Gothic Medium Cond as its alternate: Word draws the Armenian
                // letters in Sylfaen but the space, digits and Latin in the alternate (dx2 hy 05a96a87: space 0.1865 em, not Sylfaen's 0.25).
                if family.trimmingWhitespace().lowercased() == "ghea grapalat",
                   altName(family)?.trimmingWhitespace().lowercased() == "franklin gothic medium cond" {
                    var adv = sylfaenAdvances
                    for (cp, w) in franklinMediumCondAdvances where cp >= 0x20 && Int(cp) < 0x20 + adv.count { adv[Int(cp) - 0x20] = w }
                    face.advances = adv
                    face.boldAdvances = adv
                    face.sizeScale = 1   // (the table's widths are true em; the Franklin stand-in's scale would narrow them)
                    face.classScales = nil
                    RuleTrace.hit("ghea-franklin-latin")
                }
            }
            // Palatino Linotype's own line in Word for Windows' print: win/hhea 2150 over and 613 under of 2048 (1.3491 em).
            // xs 8d372494's 14pt lines step 19.0 and its 24pt headings 32.4 in Word, where the Times stand-in's 1.15 stepped 16.1 and 27.6.
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "palatino linotype" {
                face.naturalHeight = 2763.0 / 2048
                face.baseline = 2150.0 / 2048
                face.advances = palatinoLinotypeAdvances
                face.boldAdvances = palatinoLinotypeBoldAdvances
                RuleTrace.hit("palatino-linotype-own-line")
            }
            // (Its weights Light, Semilight, Semibold and Black have the same line as Regular: 2210 over and
            // 514 under of 2048 by their hhea. lo-cc084a84's 20pt "Segoe UI Light" title stands 2.6pt
            // under Word's print's in the stand-in's 0.95 ascent.)
            if wordOnMac || wordOnWindows, ["segoe ui light", "segoe ui semilight", "segoe ui semibold", "segoe ui black"].contains(family.trimmingWhitespace().lowercased()) {
                face.naturalHeight = 2724.0 / 2048
                face.baseline = 2210.0 / 2048
                if family.trimmingWhitespace().lowercased() == "segoe ui light" {
                    face.advances = segoeUILightAdvances
                    face.boldAdvances = segoeUIBoldAdvances
                }
                RuleTrace.hit("segoe-ui-weights-own-line")
            }
            // (Ebrima, drawn as the sans clone at its own widths, on its
            // own line: 2210 over and 514 under of 2048, its OS/2 win
            // metrics — `windowsSigFace`.)
            if wordOnWindows, windowsSigFace(family) == "ebrima" {
                face.naturalHeight = 2724.0 / 2048
                face.baseline = 2210.0 / 2048
                face.missingGlyphAdvance = 1322.0 / 2048
                face.otherAdvances = ebrimaAdvances
                face.boldOtherAdvances = ebrimaBoldAdvances
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
            // page ran 4pt short, a row over. Segoe UI Symbol's is 2210
            // over and 514 under of 2048, 1.330 ems: zh-a7a889eb's
            // checklist cells, "☑12、…" at 12pt in 0.8625 auto lines, step
            // 17.16 in Word for Windows' print, where the clone's line
            // under SimSun's set them 0.8pt short a line.
            let symbolLines: [String: (height: Double, baseline: Double)] = [
                "symbol": (1.225, 1.005), "wingdings": (1.11, 0.899), "wingdings 2": (1.054, 0.843), "wingdings 3": (1.139, 0.928),
                "segoe ui symbol": (2724.0 / 2048, 2210.0 / 2048),
            ]
            if let own = symbolLines[family.trimmingWhitespace().lowercased()] {
                face.naturalHeight = own.height
                face.baseline = own.baseline
            }
            // (Not Sylfaen, nor GHEA Grapalat drawn as it: their own tables, set above, are not the circled digits'.)
            if clone != calibri, !(wordOnWindows && ["sylfaen", "ghea grapalat"].contains(family.trimmingWhitespace().lowercased())) {
                face.otherAdvances = circled(1.2007)
                face.boldOtherAdvances = circled(1.2207)
            }
            // (Cambria's Greek, which its stand-in lacks, at Cambria's widths:
            // zh-d97c5474's Greek notice, in Cambria runs, left words to the
            // next line in the fallback's that Word's lines hold.)
            if clone == cambria {
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(cambriaGreekAdvances) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(cambriaBoldGreekAdvances) { $1 }
            }
            // (Nunito Sans keeps its own widths and line: 1.364 ems by its
            // hhea, 1011 over and 353 under of 1000, no gap. zh-d97c5474's
            // 12pt notice in its Light steps 16.37 in Word's prints, where
            // Carlito's 14.6 put every line of it high and a word long.)
            let lower = family.trimmingWhitespace().lowercased()
            if lower.hasPrefix("nunito sans") {
                let light = faceHas(lower, "light")
                face.advances = light ? nunitoSansLightAdvances : nunitoSansAdvances
                face.boldAdvances = nunitoSansBoldAdvances
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(light ? nunitoSansLightOtherAdvances : nunitoSansOtherAdvances) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(nunitoSansBoldOtherAdvances) { $1 }
                face.naturalHeight = 1.364
                face.baseline = 1.011
                return face
            }
            // (Verdana set to its own widths and line — 1.2153 ems, its
            // hhea ascent and descent with no gap: drawing.docx's Verdana
            // 9 lines held a word fewer in the stand-in's, and every page
            // of its Russian news ran on.)
            if clone == verdana {
                face.advances = verdanaAdvances
                face.boldAdvances = verdanaBoldAdvances
                face.italicAdvances = verdanaItalicAdvances
                face.boldItalicAdvances = verdanaBoldItalicAdvances
                face.otherAdvances?.merge(verdanaOtherAdvances) { $1 }
                face.boldOtherAdvances?.merge(verdanaBoldOtherAdvances) { $1 }
                face.naturalHeight = 1.2153
                face.baseline = 1.0054
            }
            // (Century, at its own widths and line: lo-6b7d4262's lines set a
            // letter wider in Word's print than the stand-in's.)
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "century" {
                face.advances = centuryAdvances
                face.naturalHeight = 1.2021
                face.baseline = 0.9858
                RuleTrace.hit("century-own-widths")
            }
            if wordOnWindows { Self.applyTabled(family, to: &face) }
            // (Arial Narrow, drawn as the sans clone, at its own widths and line.)
            if family.trimmingWhitespace().lowercased() == "arial narrow" {
                face.advances = arialNarrowAdvances
                face.italicAdvances = arialNarrowAdvances
                face.boldAdvances = arialNarrowBoldAdvances
                face.boldItalicAdvances = arialNarrowBoldAdvances
                face.otherAdvances = arialNarrowOtherAdvances
                face.boldOtherAdvances = arialNarrowBoldOtherAdvances
                face.naturalHeight = 1.1475
                face.baseline = 0.9355
                RuleTrace.hit("arial-narrow-own-widths")
            }
            // (Source Sans Pro, drawn as the sans clone, at its own widths.)
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "source sans pro" {
                face.advances = sourceSansProAdvances
                face.italicAdvances = sourceSansProAdvances
                face.boldAdvances = sourceSansProBoldAdvances
                face.boldItalicAdvances = sourceSansProBoldItalicAdvances
                face.naturalHeight = 1.257
                face.baseline = 0.984
                // (The no-break space is the face's space: our danda rule sets the space before a danda as one, and the stand-in's own 0.226 em made c5311ac7's line 0.3 pt too wide.)
                if let sp = sourceSansProAdvances.first, let spb = sourceSansProBoldAdvances.first {
                    face.otherAdvances = (face.otherAdvances ?? [:]).merging([0xA0: sp]) { $1 }
                    face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging([0xA0: spb]) { $1 }
                }
                // (The line is the face's own hhea 984+273 over 1000, read from Word's subsets: lab c53, Word's Source Sans lines are 0.43 pt taller than the stand-in's at 12 pt; the 1 pt that 17a0d0c7 once showed is its line-break-first paragraph, see the board.)
                RuleTrace.hit("source-sans-pro-own-widths")
            }
            // (Mangal itself: its ASCII digits and marks, and the en dash, ellipsis and right quote, at its own advances; 2db27e2d's en dash is
            // 3.36 pt at 11 pt in Word's print, the stand-in's 6.12.)
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "mangal" {
                face.otherAdvances = (face.otherAdvances ?? [:]).merging([0x2013: 0.3043, 0x2019: 0.2283, 0x2026: 0.585]) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging([0x2013: 0.3043, 0x2019: 0.2283, 0x2026: 0.585]) { $1 }
                RuleTrace.hit("mangal-ascii-own-widths")
            }
            // (Nikosh, which Windows lacks, is drawn in Mangal: its ASCII punctuation and digits at Mangal's advances.)
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "nikosh" {
                face.advances = nikoshAdvances
                face.boldAdvances = nikoshAdvances
                face.naturalHeight = 1.679
                face.baseline = 1.241
                RuleTrace.hit("nikosh-latin-in-mangal-widths")
            }
            // (Montserrat, a cloud face we hold no file for: the sans clone at its own widths and line.)
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "montserrat" {
                face.advances = montserratAdvances
                face.boldAdvances = montserratBoldAdvances
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(montserratOtherAdvances) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(montserratBoldOtherAdvances) { $1 }
                face.naturalHeight = 1.219
                face.baseline = 0.968
                RuleTrace.hit("montserrat-own-widths")
            }
            // (Tahoma, drawn as the sans clone, at its own widths and line.)
            if family.trimmingWhitespace().lowercased() == "tahoma" {
                face.advances = tahomaAdvances
                face.boldAdvances = tahomaBoldAdvances
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(tahomaGreekAdvances) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(tahomaGreekBoldAdvances) { $1 }
                face.naturalHeight = 1.2070
                face.baseline = 1.0005
                RuleTrace.hit("tahoma-own-widths")
            }
            // (Impact's own line, 1.2197 ems by its hhea (ascent 2066, descent
            // 432 over 2048); the stand-in's 1.149 left every Impact line
            // 0.07 em short: ukr-z4769265's 13pt and 30pt headings.)
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "impact" {
                face.naturalHeight = 1.2197
                face.baseline = 1.0088
                RuleTrace.hit("impact-own-line")
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
            // (Not "Liberation Serif" on Windows, which Word draws in Cambria by its font-table signature —
            // `windowsSigFace` — with Cambria's own line: lo-11ad5a95's 48pt lines step 56.77 in Word's print,
            // 56.48 with this one; tdf153136's 56.7.)
            if clone == cambria, !["cambria", "caladea", "carlito"].contains(family.trimmingWhitespace().lowercased()),
               !(wordOnWindows && family.trimmingWhitespace().lowercased() == "liberation serif") {
                face.naturalHeight = 0.95 + 0.2163
                // (A face whose font-table alternate is "Courier", which Word does not follow on Windows, is drawn as the
                // real Cambria, with Cambria's own line, 2401 of 2048: xa gv-690391482c's Sabon at 1.15 steps 14.82 in
                // Word's print, 14.75 with the line above, and a page of them ran 2 to 4pt short, so a paragraph and its
                // footnote fitted on page 8 that Word split.)
                if wordOnWindows, fontEntry(family)?.alt?.trimmingWhitespace().lowercased() == "courier" {
                    face.naturalHeight = 2401.0 / 2048
                    RuleTrace.hit("courier-alternate-face-is-cambria-with-its-own-line")
                }
            }
            // (Only faces that really are Cambria here: any other face drawn as the
            // Cambria clone would gain otherAdvances and switch off the
            // "otherAdvances == nil" Indic rules, as Kokila's Hindi did.)
            if wordOnWindows, clone == cambria,
               ["cambria", "caladea", "liberation serif"].contains(family.trimmingWhitespace().lowercased()) {
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(cambriaCyrillicAdvances) { $1 }
                RuleTrace.hit("cambria-cyrillic-widths")
            }
            if clone == serif {
                face.otherAdvances?.merge(timesNumerals) { $1 }
                // (Times' superscript minus, 0.345 em in Word's print; Liberation Serif has none and the DejaVu Sans that draws it is 0.53 — fd00b5's "MJ m⁻² day⁻¹" cell wrapped by it.)
                face.otherAdvances?[0x207B] = 0.3447
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
                // (Its spaces Browallia's, which Word draws them in, not
                // Cordia's: Word for Windows' print of zh-6a4fc013 sets 818
                // regular ones at 0.222 em and 483 bold at 0.181, where
                // Cordia's are 0.182 and 0.224 — its bold "คำถามที่ 9 ："
                // took 0.7pt a space too much and its line one fewer word.)
                var regular = cordiaNewAdvances, bold = cordiaNewBoldAdvances
                regular[0] = 0.222
                if ["browallia new", "th sarabun new", "th sarabunpsk", "th sarabunit๙"].contains(family.trimmingWhitespace().lowercased()) {
                    for (j, w) in Self.browalliaLatinAdvances.enumerated() { regular[j + 1] = w }
                }
                bold[0] = 0.181
                face.advances = regular
                face.boldAdvances = bold
                #if os(macOS)
                // (Under OFFICE_WORD_FONTS=mac, with Word's Cordia New loaded,
                // the Thai itself in Cordia, at its own widths: drawn by
                // Thonburi, scaled, PDFKit read whole clusters of it — the
                // "คำ" of every "คำถาม" — back as nothing.)
                if _cordiaLoaded {
                    face.fallback = [cordiaNew]
                    face.otherAdvances = (face.otherAdvances ?? [:]).merging(browalliaAdvances) { $1 }
                    face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(browalliaBoldAdvances) { $1 }
                } else { face.classScales = [1, 1, 1, 1, 0.75] }
                #elseif os(Windows)
                // (On Windows the platform's Thai is Leelawadee UI, and
                // Browallia's own widths set it, as Cordia's draw it on a
                // Mac: at 0.729 of Leelawadee's, zh-6a4fc013's Thai ran
                // 2.5% narrow of Word's for Windows over 11,356 letters.)
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(browalliaAdvances) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(browalliaBoldAdvances) { $1 }
                #else
                // (On Linux the fallback is Noto Sans Thai: shaped over
                // zh-6a4fc013's Thai it is 1/0.70 of Cordia's widths, and
                // 0.66 sets the document's 614 lines on 26 pages as Word
                // does — 0.70 gives 627 on 27, unscaled 726 on 30. That was
                // measured with the Thai drawn by the host's fallback; with
                // the bundled Noto Sans Thai in the glyph chain, the scale
                // that sets 616 lines on 27 pages, as Word's print has them,
                // is 0.82: 0.66 gives 560 on 25, 0.74 597 on 26.)
                face.classScales = [1, 1, 1, 1, 0.82]
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(browalliaAdvances) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(browalliaBoldAdvances) { $1 }
                #endif
            }
            if wordOnWindows, ["browallia new", "th sarabun new", "th sarabunit๙"].contains(family.trimmingWhitespace().lowercased()) {
            // Word for Windows prints these in Browallia New: hhea 1770/789 of 2048 (1.249 em).
            face.naturalHeight = 1.249
            face.baseline = 0.864
            // (Its bold has its own line: hhea 1786 + 885 of 2048 = 1.3042 em, ascent 0.872; Word steps 16pt bold lines 20.7 apart, ours 20.0.)
            face.boldHeight = 1.3042
            face.boldBaseline = 0.872
            RuleTrace.hit("th-browallia-own-line")
        }
        if wordOnWindows, family.trimmingWhitespace().lowercased() == "th sarabunpsk" {
                // (Word for Windows has the real TH SarabunPSK, not
                // Browallia: its own widths from the print's subsets.)
                for (cp, w) in Self.thSarabunPSKLatin where cp >= 0x21 { face.advances?[Int(cp) - 0x20] = w }
                if let w = Self.thSarabunPSKLatin[0x20] { face.advances?[0] = w }
                for (cp, w) in Self.thSarabunPSKBoldLatin where cp >= 0x21 { face.boldAdvances?[Int(cp) - 0x20] = w }
                if let w = Self.thSarabunPSKBoldLatin[0x20] { face.boldAdvances?[0] = w }
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(Self.thSarabunPSKThai) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(Self.thSarabunPSKBoldThai) { $1 }
                // (Its own line: ascent 0.85 + descent 0.46 em in the print's
                // subsets, a 20.95 pt pitch at 16 pt; ours ran 18.4 pt.)
                face.naturalHeight = 1.31
                face.baseline = 0.85
                RuleTrace.hit("th-sarabunpsk-own-widths")
            }
            if wordOnWindows, family.trimmingWhitespace().lowercased() == "angsana new" {
                // (Word for Windows has the real Angsana New: its own widths and line, from the print's subsets.)
                for (cp, w) in Self.angsanaNewLatin where cp >= 0x21 { face.advances?[Int(cp) - 0x20] = w }
                if let w = Self.angsanaNewLatin[0x20] { face.advances?[0] = w }
                for (cp, w) in Self.angsanaNewBoldLatin where cp >= 0x21 { face.boldAdvances?[Int(cp) - 0x20] = w }
                if let w = Self.angsanaNewBoldLatin[0x20] { face.boldAdvances?[0] = w }
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(Self.angsanaNewThai) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(Self.angsanaNewBoldThai) { $1 }
                face.naturalHeight = 1.351
                face.baseline = 0.941
                face.boldHeight = 5673.0 / 4096
                face.boldBaseline = 3949.0 / 4096
                RuleTrace.hit("th-angsana-own-widths")
            }
            // (An embedded face whose font-table entry names an East Asian
            // charset keeps Word for Windows' East Asian line though its
            // name is Latin: 1.3 of its own ascent and descent, the extra
            // split evenly. Lab ft/ft2 (windows, zh-1cfb652b's footer: an
            // embedded GWZT-EN, charset 86, 0.863 + 0.250): its 14pt mark
            // stands 14.45 over the baseline at 471 auto and 14.53 single —
            // 12.08 + 2.34 — and its page number, a box hung from the
            // paragraph, 6.07 higher than ours at the face's bare 1.113.)
            // (Word for Mac's print the same: zh-1cfb652b's number stands at
            // 788.4 there, 788.1 in Windows', where the bare face's line
            // put ours 6pt lower.)
            if wordOnWindows || wordOnMac, let registered = embeddedFamily(family), let entry = fontEntry(family),
               ["86", "88", "80", "81"].contains(entry.charset.uppercased()) {
                declaredLock.lock()
                let line = embeddedLines[registered]
                declaredLock.unlock()
                if let line, line.ascent + line.descent > 0.5 {
                    let h = line.ascent + line.descent
                    face.naturalHeight = h * 1.3
                    face.baseline = line.ascent + h * 0.15
                }
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
        // (A Latin face Word for Windows has sets the East Asian text it
        // holds none of as a name it lacks: MS Mincho, and JhengHei for
        // what Mincho lacks, each on its own line — zh-d97c5474's Chinese,
        // in runs that name only Latin faces (its style's theme ea is
        // empty), steps 20.7 at 12pt single in word-win, JhengHei's 1.729
        // em, where the square face made it 16.)
        let ea = own || family.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) || Self.isEastAsianFace(family) ? eastAsianFace(family)
            : wordOnWindows ? windowsMincho : square
        if eastAsian {
            // (An embedded face draws its own characters; what its subset
            // lacks falls back as before.)
            var face = RichResolvedFace(family: (own ? embeddedFamily(family) : nil) ?? fangSongFamily(family) ?? substitute(family), naturalHeight: ea.height, boldSpread: ea.fakeBold ? (wordOnWindows ? windowsBoldWiden(family) : ea.boldWiden ?? macBoldWiden) : 0,
                                        baseline: ea.baseline)
            // (細明體_HKSCS sets its first line 1pt higher at 18pt than 細明體 does:
            // zh-7773163d's lines stand 71, 95, 128 ... in Word for Windows' print and one
            // point lower in ours, with the same pitch.)
            if wordOnWindows, family.lowercased().containsSubstring("hkscs"), let b = face.baseline { face.baseline = b - 1.0 / 18 }
            // (A square face's symbols are an em; YaHei's, JhengHei's and
            // DengXian's — the faces with Latin widths of their own — are not.)
            face.fullWidthSymbols = ea.squareSymbols ?? (ea.latinAdvances == nil)
            face.malgunSymbols = ea.malgunSymbols
            // (Ideographs in a serif where the name is a Song, Ming or
            // Mincho face: `serifIdeographs`.)
            if !own || embeddedFamily(family) == nil, let serif = serifIdeographs(family, ea) { face.fallback = [serif] }
            // (YaHei has none of the compatibility ideographs Word sets in
            // Noto Sans SC; PMingLiU and the others it has draw their own —
            // zh-db93607e's in PMingLiU are as any character in Word's print.)
            face.lacksCompatibilityIdeographs = isYaHeiLike(ea.height)
            // (What an embedded subset lacks, Word sets in the face the
            // name has unembedded — YaHei, for the names it stands in
            // for — and the line takes that face's height: zh-92373179's
            // FangSong_GB2312 holds none of "运用", "易", "贡献", and its
            // 1.5-spaced 16pt lines that hold one are 41.2pt apart in
            // Word's print, YaHei's, where the subset's square line made
            // them 31.2.)
            // (The ideographs Mincho lacks, in JhengHei on its line:
            // `windowsMincho`.)
            if wordOnWindows, !isEmbedded(family), ea.height == windowsMincho.height, ea.baseline == windowsMincho.baseline, ea.latin == cambria,
               let covered = windowsMinchoCovers {
                face.covers = covered
                face.uncoveredFamily = "Microsoft JhengHei"
            }
            // Mac Word uses MS Gothic's short line only for characters
            // the face holds. Its missing ideographs use YaHei: the
            // all-Gothic control of zh-8d72961c agrees for all 167 CJK
            // characters, including the taller lines with missing glyphs.
            if wordOnMac, !isEmbedded(family), ["ms gothic", "ｍｓ ゴシック"].contains(family.trimmingWhitespace().lowercased()) {
                face.covers = WindowsFallbackCovers.msGothic
                face.uncoveredFamily = "Microsoft YaHei"
            }
            if own, let registered = embeddedFamily(family), let covered = embeddedCovers(registered),
               isYaHeiLike(eastAsianFace(family, ignoringEmbedding: true).height) {
                face.covers = covered
                face.uncoveredFamily = "Microsoft YaHei"
                face.drawnFromSubset = true
                // (Word for Windows takes an embedded 仿宋_GB2312's missing
                // characters from MS Gothic, else Yu Gothic, else Microsoft
                // JhengHei, a stretch of them keeping the face it is in
                // while that has the next: zh-e68a2f57, zh-c2f6d17a and
                // zh-92373179's fresh word-win prints, 13,100 such
                // characters, all but 17 so by the faces' own cmaps
                // (`WindowsFallbackCovers`). Each line takes its faces'
                // heights: zh-e68a2f57's TOC at 1.75 lines steps 44.4 with
                // MS Gothic alone — its square line — and 56.4 with
                // JhengHei; ours, YaHei for all, 56 throughout.)
                if wordOnWindows, ["仿宋_gb2312", "fangsong_gb2312"].contains(where: { faceHas(family.lowercased(), $0) }) {
                    face.uncoveredChain = [("MS Gothic", WindowsFallbackCovers.msGothic), ("Yu Gothic", WindowsFallbackCovers.yuGothic),
                                           ("Microsoft JhengHei", nil)]
                    face.uncoveredFamily = "Microsoft JhengHei"
                }
            }
            face.symbolFamily = ea.symbols
            face.symbolsInBold = ea.symbolsInBold
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
            // (And its white circle "○", 0.604 em as its "■": zh-7654804a's
            // "○○公司", placeholders in 標楷體 hinted East Asian, step 10.17
            // at 16pt on a grid of +1.0076 in Word's print — 9.66 and half
            // the grid, as a symbol of its own width takes — where the
            // stand-in fell back to Liberation Sans's glyph and the whole
            // addition, 10.67.)
            if isYaHeiLike(ea.height) {
                // (YaHei's geometric shapes and arrows, measured in Word's
                // msyh.ttc and msyhbd.ttc: both use these advances /2048.
                // In particular □ is wider than ■; zh-e0ca7252's form
                // lines wrapped late when □ inherited the black square.)
                let shapes: [UInt32: Double] = [0x25A1: 1336.0 / 2048, 0x25CF: 1336.0 / 2048,
                                              0x25C7: 1229.0 / 2048, 0x25C6: 1229.0 / 2048, 0x203B: 1724.0 / 2048,
                                              0x2190: 1, 0x2192: 1, 0x2191: 0.5, 0x2193: 0.5]
                face.otherAdvances = [0x2026: 0.8135, 0x2014: 1.0801, 0xB7: 0.2407, 0x2027: 0.2407, 0x221A: 0.7017, 0x2500: 0.7085, 0x25A0: 0.604,
                                      0x25CB: 0.604].merging(circled(1.0)) { $1 }
                // (And its bold "★", 1678/2048: zh-f6886fbb's bold
                // "★★★" steps 9.83 at 12pt in Word for Windows' print.)
                face.boldOtherAdvances = [0x2026: 0.9629, 0x2014: 1.0801, 0xB7: 0.4395, 0x2027: 0.2861, 0x2605: 1678.0 / 2048].merging(circled(1.0)) { $1 }
                face.otherAdvances = face.otherAdvances?.merging(shapes) { $1 }
                face.boldOtherAdvances = face.boldOtherAdvances?.merging(shapes) { $1 }
            }
            // (The face's own widths past ASCII: SimSun's, `EastAsianFace.otherAdvances`.)
            if let own = ea.otherAdvances {
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(own) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(ea.boldOtherAdvances ?? own) { $1 }
            }
            // (PMingLiU's en dash is an em, where the run sets it East
            // Asian — hinted, or by its Latin face: zh-05699f05's
            // "（100%+目標值）–基準維護件數】" in 新細明體 sets "–" 12.0 at
            // 12pt in Word's print — beside ideographs, spaces, Latin
            // letters or digits alike, hinted or not (lab `ds`) — where the
            // stand-in drew Liberation Sans's 6.67, and the cell's line held
            // the "數】" Word sends down. Its "×" is half an em, 6.0, but
            // set so alone it let lines take what the no-break space beside
            // it, 6.0 in Word's print and 2.82 in ours, gives back:
            // zh-e061a08e's "數）×100％" took "（以". Left for both.)
            // (The "×" at its half: zh-0daa510e's 12pt cell "（A）×75%＋我國
            // 籍民" is one line in Word's print, "×" 5.95, where ours set it
            // 6.91 and left "民".)
            if ea.height == 1332.0 / 1024.0, face.otherAdvances == nil {
                // (And "÷" 0.591, the half-width corner brackets half an em —
                // the symbols of Word's embedded PMingLiU that are not an em,
                // in every print of the corpus.)
                face.otherAdvances = [0x2013: 1.0, 0xD7: 0.5, 0xF7: 0.591, 0xFF62: 0.5, 0xFF63: 0.5]
                face.boldOtherAdvances = [0x2013: 1.0, 0xD7: 0.5, 0xF7: 0.591, 0xFF62: 0.5, 0xFF63: 0.5]
            }
            // (DFKai-SB's hyphen U+2010 is half an em: zh-6d402586's "COVID‐19" in
            // 標楷體 14pt steps 7.0 in Word's print, 4.6 in the stand-in's, and the
            // line held a character Word sends down.)
            if wordOnWindows, ["標楷", "dfkai"].contains(where: { family.lowercased().containsSubstring($0) }) {
                face.otherAdvances = (face.otherAdvances ?? [:]).merging([0x2010: 0.5]) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging([0x2010: 0.5]) { $1 }
            }
            // (The square faces set GB2312's Latin-1 symbols an em, as
            // their ideographs: a "°" in a run Word sets in 宋体 — `w:hint`
            // eastAsia — is 10.50 at 10.5pt in its print of zh-cd8987db,
            // and "°" and "×" are an em in SimSun and SimHei wherever
            // Word's prints have them; the stand-in drew its own 0.4 em
            // "°", and "5.5.1 坡度＜25°…" took the "土中。" Word's leaves.)
            // (Arial Unicode MS's curly quotes are its own narrow ones, not an
            // em: zh-0aac9d1a's 楷体_GB2312 heading "（一）物业服务企业守信“红名单”。"
            // steps 5.52 at each quote at 16pt in Word's print, and no blank
            // stands beside them.)
            if ea.height == arialUnicode.height, ea.baseline == arialUnicode.baseline {
                let quotes: [UInt32: Double] = [0x2018: 0.345, 0x2019: 0.345, 0x201C: 0.345, 0x201D: 0.345]
                face.otherAdvances = quotes
                face.boldOtherAdvances = quotes
            }
            // (And GB2312's primes, ′ and ″ (A1E4, A1E5), an em as well:
            // zh-38d26944's "＞40″扣30分，方位角闭合差在20″～30″扣5分，＜20″"
            // in 仿宋 steps 10.44-10.56 at each ″ at 10.5pt in Word for
            // Windows' print; Starling FangSong's own ″ is 3.32, and the
            // line took the "＜" Word sends on.)
            // (Not 細明體's: Word for Windows sets zh-7773163d's "§" in 細明體_HKSCS half an em, 9pt
            // at 18pt, and no blank after it; the table is GB2312's.)
            if ea.latin == mono, face.otherAdvances == nil, !["細明體", "新細明體", "mingliu", "pmingliu"].contains(where: { family.lowercased().containsSubstring($0) }) {
                let gb: [UInt32: Double] = [0xA4: 1, 0xA7: 1, 0xA8: 1, 0xB0: 1, 0xB1: 1, 0xD7: 1, 0xF7: 1, 0x2032: 1, 0x2033: 1]
                face.otherAdvances = gb
                face.boldOtherAdvances = gb
            }
            // (Windows' FangSong sets its middle dot an em, where the
            // stand-in's is half of one: every "·" Word for Windows draws
            // in FangSong is 0.9 to 1.0 em — zh-6d1afa56, zh-20ff844e,
            // zh-e653f583's bold "12·4" 16.2 at 16pt, whose line then sends
            // "传" down; ours took it. Its "×" too: an em in all of the
            // 270 Word for Windows draws in FangSong, zh-22ecbdc8's
            // "㎜×700㎜" among them. After the defaults above, not before: they
            // test `otherAdvances == nil`, and a merge here defeated them,
            // taking the en dash, the corner brackets and GB2312's ° ′ ″ from
            // FangSong runs — zh-bfe04e2f 99.1 -> 93.4, zh-cc7a08e8 100 -> 98.2.)
            if wordOnWindows, fangSongFamily(family) == starlingFangSong {
                face.otherAdvances = (face.otherAdvances ?? [:]).merging([0xB7: 1.0, 0xD7: 1.0]) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging([0xB7: 1.0, 0xD7: 1.0]) { $1 }
            }
            face.scaledHeight = ea.scaledHeight
            face.scaledBaseline = ea.scaledBaseline
            face.boldHeight = ea.boldHeight
            face.boldBaseline = ea.boldBaseline
            return face
        }
        var face = RichResolvedFace(family: ea.latin, sizeScale: ea.latinScale, naturalHeight: ea.height,
                                    boldSpread: ea.fakeBold ? (wordOnWindows ? windowsBoldWiden(family) : ea.boldWiden ?? macBoldWiden) : 0, classScales: ea.latinClasses, baseline: ea.baseline,
                                    isEastAsian: true)
        // (What the Latin stand-in lacks, the face the name stands for
        // draws: Word sets zh-117cf7c6's "※" bullet, 標楷體 with no hint,
        // in YaHei, and its line is that face's height. Left to the glyph
        // fallback, Linux drew it in DejaVu Sans and the line stood 2.5pt
        // short; the Mac's system fallback found PingFang.)
        if !own || embeddedFamily(family) == nil { face.fallback = [substitute(family)] + (bundledAlias(family).map { [$0] } ?? []) + cjkFallback }
        face.scaledHeight = ea.scaledHeight
        face.scaledBaseline = ea.scaledBaseline
        face.boldHeight = ea.boldHeight
        face.boldBaseline = ea.boldBaseline
        face.advances = ea.latinAdvances
        face.boldAdvances = ea.latinBoldAdvances
        // (The square faces' Latin is half an em a character — SimSun's, MingLiU's — and the stand-in is
        // drawn at 85% of the size, Liberation Mono's 0.6em then 0.51: the width is the table's,
        // not the drawn glyph's. At the 0.833 that made it exactly half, the matcher took a
        // row number "11" at 9.2pt beside 11pt text for a mark of the next cell's line:
        // zh-8415d258's numbered rows.)
        // 仿宋 and 標楷體 keep the old drawn-width stand-in: its digits stand ~1% wider than a half em in Word
        // (zh-5450d509), and widening them breaks ~100 documents on a knife-edge.
        let fangsong = ["仿宋", "fangsong", "標楷", "dfkai", "kaiu"].contains(where: { family.lowercased().containsSubstring($0) })
        if fangsong, ea.latin == mono, ea.latinAdvances == nil, ea.latinScale == 0.85 {
            face.sizeScale = 1024.0 / 1229.0
        } else if ea.latin == mono, ea.latinAdvances == nil, ea.latinScale == 0.85 {
            face.advances = [Double](repeating: 0.5, count: 95)
            face.boldAdvances = [Double](repeating: 0.5, count: 95)
        }
        // (Fixed half-em Latin: a table of 0.5s, or FangSong's drawn-width stand-in above; lab sqz4 squeezes spaces only in these.)
        face.fixedHalfLatin = (face.advances.map { !$0.isEmpty && $0.allSatisfy { abs($0 - 0.5) < 1e-6 } } ?? false)
            || (fangsong && ["仿宋", "fangsong"].contains(where: { family.lowercased().containsSubstring($0) }) && ea.latin == mono && ea.latinAdvances == nil)
        face.kerns = ea.latinKerns
        face.boldKerns = ea.latinBoldKerns
        face.symbolFamily = ea.symbols
        face.symbolsInBold = ea.symbolsInBold
        // (YaHei's middle dot, which its table of ASCII widths leaves to
        // the stand-in's: see the East Asian face above.)
        // (And its circled numbers, an em: Word's print of zh-34a6519a sets
        // "①".."⑤" in YaHei 12.0pt apart at 12pt and 10.5 at 10.5, where
        // the stand-in, which has none, drew DejaVu's at 0.9 — "⑤有应急…"
        // then took "承" on its first line by a squeeze Word's does not
        // make, and every page from p11 ran early.)
        if isYaHeiLike(ea.height) {
            face.otherAdvances = [0xB7: 0.2407].merging(circled(1.0)) { $1 }
            face.boldOtherAdvances = [0xB7: 0.4395].merging(circled(1.0)) { $1 }
        }
        if let own = ea.otherAdvances {
            face.otherAdvances = (face.otherAdvances ?? [:]).merging(own) { $1 }
            face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(ea.boldOtherAdvances ?? own) { $1 }
            // (SimSun's curly quotes, an em, where the run's Latin face is SimSun and nothing hints
            // East Asian: lab pc2 (Word for Windows, 10.5pt, 宋体 in every slot) sets "“" 10.68-10.80
            // and "”" 10.56-10.68; ours 3.5. The hinted quotes take the East Asian face's, as before:
            // the same quotes in zh-e74dd0a1, zh-424775e4 and others, hinted, fell 99.9 to 54.)
            let lowerFamily = family.lowercased()
            if wordOnWindows, ["simsun", "宋体", "宋體"].contains(where: { lowerFamily.containsSubstring($0) }) {
                let quotes: [UInt32: Double] = [0x2018: 1, 0x2019: 1, 0x201C: 1, 0x201D: 1]
                face.otherAdvances = face.otherAdvances?.merging(quotes) { $1 }
                face.boldOtherAdvances = face.boldOtherAdvances?.merging(quotes) { $1 }
            }
        }
        // A no-break space in a square face is an em, where its space is
        // half of one (lab `nb1`, Word 16, 2026-10-15: "甲" + ten U+00A0 +
        // "乙" at 12pt is 12pt a space in 宋体, 黑体, 楷体 and 仿宋, 6pt
        // with U+0020; 3pt in a run whose Latin face is Times, 3.55 in
        // YaHei, its own). Chinese forms space their "年  月  日" lines
        // with them: zh-0aac9d1a's stamp line holds 18 before its "日"
        // and is 444pt to there in Word's print, where it was 336 here.
        // (Not 標楷體's, which Word for Windows sets in DFKai-SB at half an
        // em: zh-dc9e54ca's "附件一" + 37 U+00A0 + 23 spaces + "單位：新臺幣元",
        // 12pt, is 480pt on one centred line in word-win, every space 6.0;
        // ours, KaiTi's em each, wrapped "單位" and the form under it.)
        if ea.latin == mono, ea.latinAdvances == nil {
            let lower = family.lowercased()
            let nbsp = wordOnWindows && (faceHas(lower, "標楷") || faceHas(lower, "dfkai")) ? 0.5 : 1.0
            // (And GB2312's primes ′ ″ an em, as in the East Asian face
            // above: Word counts them the square face's own.)
            face.otherAdvances = [0xA0: nbsp, 0x2032: 1, 0x2033: 1]
            face.boldOtherAdvances = [0xA0: nbsp, 0x2032: 1, 0x2033: 1]
        }
        // Korean Batang and Dotum: a no-break space is half an em (b8f72871's
        // Batang 10 pt "\u{A0}한글을" steps 5.0; ours 2.8 wrapped a word early).
        if wordOnWindows, ["dotum", "돋움", "batang", "바탕"].contains(family.lowercased()) {
            face.otherAdvances = (face.otherAdvances ?? [:]).merging([0xA0: 0.5]) { $1 }
            face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging([0xA0: 0.5]) { $1 }
        }
        // (Word for Windows sets the letters and digits an embedded subset
        // lacks in Calibri, at Calibri's widths, and those it holds in the
        // subset: zh-92373179's 仿宋_GB2312 holds four digits — its 155
        // held letters and digits print in the subset, the 133 others in
        // Calibri — and zh-5450d509's holds none, its "2017", "42" 6.12
        // and 6.08 at 12pt in word-win where ours, the stand-in's half em,
        // set 6.0, and its p1 line took "署，" Word's leaves.)
        // (And those it holds at the subset's own widths, in Word for
        // Windows and on a Mac: zh-57f1de0d's 方正仿宋_GBK sets "1" 0.645
        // em and "4" 0.539 in both prints — a 16pt "1） 应建立…培训，" then
        // 450.3pt with its "有", 0.5 over the line, and Word sends the
        // "有" down; ours, the stand-in's half em, took it.)
        if own, let registered = embeddedFamily(family) {
            declaredLock.lock()
            let alnum = embeddedAlnum[registered]
            declaredLock.unlock()
            if let alnum {
                face.otherAdvances = (face.otherAdvances ?? [:]).merging(alnum) { $1 }
                face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging(alnum) { $1 }
            }
        }
        if wordOnWindows, own, let registered = embeddedFamily(family), let covered = embeddedCovers(registered) {
            for (u, w) in Self.calibriAlnumAdvances where !covered.contains(u) { face.otherAdvances = (face.otherAdvances ?? [:]).merging([u: w]) { $1 } }
            for (u, w) in Self.calibriBoldAlnumAdvances where !covered.contains(u) { face.boldOtherAdvances = (face.boldOtherAdvances ?? [:]).merging([u: w]) { $1 } }
        }
        return face
    }

    /// Calibri's advances (ems, its hmtx: Word 16's Calibri.ttf and
    /// Calibrib.ttf) for the ASCII letters and digits.
    static let calibriAlnumAdvances: [UInt32: Double] = [0x30: 0.5068, 0x31: 0.5068, 0x32: 0.5068, 0x33: 0.5068, 0x34: 0.5068, 0x35: 0.5068, 0x36: 0.5068, 0x37: 0.5068, 0x38: 0.5068, 0x39: 0.5068, 0x41: 0.5786, 0x42: 0.5439, 0x43: 0.5332, 0x44: 0.6152, 0x45: 0.4883, 0x46: 0.4595, 0x47: 0.6309, 0x48: 0.6230, 0x49: 0.2520, 0x4A: 0.3188, 0x4B: 0.5195, 0x4C: 0.4204, 0x4D: 0.8550, 0x4E: 0.6455, 0x4F: 0.6621, 0x50: 0.5166, 0x51: 0.6729, 0x52: 0.5430, 0x53: 0.4595, 0x54: 0.4873, 0x55: 0.6416, 0x56: 0.5674, 0x57: 0.8896, 0x58: 0.5190, 0x59: 0.4873, 0x5A: 0.4683, 0x61: 0.4790, 0x62: 0.5254, 0x63: 0.4229, 0x64: 0.5254, 0x65: 0.4976, 0x66: 0.3052, 0x67: 0.4707, 0x68: 0.5254, 0x69: 0.2295, 0x6A: 0.2393, 0x6B: 0.4546, 0x6C: 0.2295, 0x6D: 0.7988, 0x6E: 0.5254, 0x6F: 0.5273, 0x70: 0.5254, 0x71: 0.5254, 0x72: 0.3486, 0x73: 0.3911, 0x74: 0.3350, 0x75: 0.5254, 0x76: 0.4517, 0x77: 0.7148, 0x78: 0.4331, 0x79: 0.4526, 0x7A: 0.3950]
    static let calibriBoldAlnumAdvances: [UInt32: Double] = [0x30: 0.5068, 0x31: 0.5068, 0x32: 0.5068, 0x33: 0.5068, 0x34: 0.5068, 0x35: 0.5068, 0x36: 0.5068, 0x37: 0.5068, 0x38: 0.5068, 0x39: 0.5068, 0x41: 0.6060, 0x42: 0.5605, 0x43: 0.5293, 0x44: 0.6304, 0x45: 0.4878, 0x46: 0.4590, 0x47: 0.6372, 0x48: 0.6309, 0x49: 0.2666, 0x4A: 0.3311, 0x4B: 0.5469, 0x4C: 0.4229, 0x4D: 0.8740, 0x4E: 0.6587, 0x4F: 0.6763, 0x50: 0.5322, 0x51: 0.6860, 0x52: 0.5630, 0x53: 0.4727, 0x54: 0.4951, 0x55: 0.6528, 0x56: 0.5913, 0x57: 0.9062, 0x58: 0.5508, 0x59: 0.5195, 0x5A: 0.4780, 0x61: 0.4937, 0x62: 0.5366, 0x63: 0.4185, 0x64: 0.5366, 0x65: 0.5034, 0x66: 0.3164, 0x67: 0.4741, 0x68: 0.5366, 0x69: 0.2456, 0x6A: 0.2554, 0x6B: 0.4800, 0x6C: 0.2456, 0x6D: 0.8135, 0x6E: 0.5366, 0x6F: 0.5376, 0x70: 0.5366, 0x71: 0.5366, 0x72: 0.3555, 0x73: 0.3989, 0x74: 0.3467, 0x75: 0.5366, 0x76: 0.4731, 0x77: 0.7451, 0x78: 0.4595, 0x79: 0.4736, 0x7A: 0.3975]

    /// The faces this platform draws Chinese in where the named one is
    /// missing, after the symbol fallback (`RichTextTheme.glyphFallback`):
    /// what the Latin side of an East Asian family falls back to first.
    nonisolated(unsafe) static var cjkFallback: [String] = []
    /// The bundled face a Word font name stands for (Resources/fonts/fonts-aliases.tsv, read with
    /// fonts.tsv at registration): its ideographs are drawn in that face before the glyph fallback's
    /// general chain. Empty where the faces are not bundled (macOS, Windows, the web).
    nonisolated(unsafe) static var bundledAliases: [String: String] = [:]
    static func bundledAlias(_ name: String) -> String? {
        bundledAliases.isEmpty ? nil : bundledAliases[name.lowercased()]
    }

    /// The Chinese faces Word for Mac carries (its DFonts), registered
    /// under their family names when OFFICE_WORD_FONTS=mac finds Word
    /// installed: the ideographs of a print to compare are then drawn in
    /// the face Word drew them in, where they were the system's PingFang
    /// — whose outlines (`hvgl`, neither TrueType nor CFF) the PDF can
    /// only carry as Type 3 glyphs, one font per few characters. PDFKit
    /// read those back as lines broken where no line breaks, and
    /// zh-b8de3ae2 scored 2 points under its own layout. Its symbols
    /// are Word's too: "※" is 0.84 em in YaHei, an em in PingFang.
    nonisolated(unsafe) static var _wordMacFacesLoaded = false
    static func registerWordMacFaces() -> Bool {
        let dir = "/Applications/Microsoft Word.app/Contents/Resources/DFonts/"
        guard FileManager.default.fileExists(atPath: dir + "msyh.ttc") else { return false }
        // (A collection's first face: SimSun's, YaHei's, MingLiU's — whose
        // ideographs are PMingLiU's.)
        for (file, families) in [("msyh.ttc", ["Microsoft YaHei"]), ("msyhbd.ttc", ["Microsoft YaHei"]), ("Simsun.ttc", ["SimSun"]),
                                 ("SimHei.ttf", ["SimHei"]), ("Kaiti.ttf", ["KaiTi"]), ("Fangsong.ttf", ["FangSong"]),
                                 ("mingliu.ttc", ["PMingLiU"]), ("Deng.ttf", ["DengXian"]), ("Dengb.ttf", ["DengXian"]),
                                 ("STZHONGS.ttf", ["STZhongsong"]), ("STXINWEI.ttf", ["STXinwei"])]
            where FileManager.default.fileExists(atPath: dir + file) {
            for family in families { _ = flutter.swift_bridge.LoadFontFromFile(dir + file, family) }
        }
        _ = registerWordCordia()
        _wordMacFacesLoaded = true
        return true
    }
    @discardableResult
    static func registerWordCordia() -> Bool {
        let dir = "/Applications/Microsoft Word.app/Contents/Resources/DFonts/"
        // (Thai: Cordia New, whose widths are Browallia New's, the face
        // Word for Mac draws "TH Sarabun New" in — `thaiWordFaces`. Its
        // bold is the collection's second face, which the engine's loader
        // does not reach: taken out as a face of its own.)
        if let cordia = FileManager.default.contents(atPath: dir + "cordia.ttc") {
            var ok = flutter.swift_bridge.LoadFontFromFile(dir + "cordia.ttc", cordiaNew)
            if ok, let bold = _collectionFace(cordia, 1) {
                ok = bold.withUnsafeBytes { buffer in
                    buffer.baseAddress.map { flutter.swift_bridge.LoadFontFromList($0.assumingMemoryBound(to: UInt8.self), buffer.count, cordiaNew) } ?? false
                }
            }
            _cordiaLoaded = ok
        }
        return _cordiaLoaded
    }
    static let cordiaNew = "Cordia New"
    nonisolated(unsafe) static var _cordiaLoaded = false
    /// Face `index` of a TrueType collection as a font file of its own:
    /// its table directory, with each table copied after it.
    static func _collectionFace(_ data: Data, _ index: Int) -> Data? {
        let b = [UInt8](data)
        func u32(_ o: Int) -> Int { o + 4 <= b.count ? Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3]) : 0 }
        func u16(_ o: Int) -> Int { o + 2 <= b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
        guard b.count > 12, b[0] == 0x74, b[1] == 0x74, b[2] == 0x63, b[3] == 0x66, index < u32(8) else { return nil }
        let face = u32(12 + 4 * index), n = u16(face + 4)
        guard n > 0, face + 12 + 16 * n <= b.count else { return nil }
        var out = [UInt8](b[face ..< face + 12])
        var body: [UInt8] = []
        let start = 12 + 16 * n
        var records: [UInt8] = []
        for t in 0 ..< n {
            let r = face + 12 + 16 * t, off = u32(r + 8), len = u32(r + 12)
            guard off + len <= b.count else { return nil }
            records += b[r ..< r + 8]
            let at = start + body.count
            records += [UInt8(at >> 24 & 0xFF), UInt8(at >> 16 & 0xFF), UInt8(at >> 8 & 0xFF), UInt8(at & 0xFF)]
            records += b[r + 12 ..< r + 16]
            body += b[off ..< off + len]
            while body.count % 4 != 0 { body.append(0) }
        }
        out += records
        out += body
        return Data(out)
    }
    /// Word's line for `family` set East Asian, and its baseline under the
    /// line's top, in ems (`EastAsianFace`); nil where the face says no
    /// baseline of its own. A chart title's line too: lab `ctitle` (Word
    /// for Mac, zh-13d11e99's chart, its title at 10 to 24pt) sets SimSun
    /// 1.293 em, its baseline 1.017 down; YaHei 1.72 and 1.27; PMingLiU's
    /// baseline 0.95 — each `EastAsianFace`'s to a tenth of a point.
    static func eastAsianLine(_ family: String, bold: Bool = false) -> (height: Double, baseline: Double)? {
        let ea = eastAsianFace(family)
        guard let baseline = bold ? ea.boldBaseline ?? ea.baseline : ea.baseline else { return nil }
        return (bold ? ea.boldHeight ?? ea.height : ea.height, baseline)
    }
    /// The Word for Mac face that draws `family`'s ideographs, as a
    /// chart's theme face (`Chart.macSimplifiedFace`); nil where none is
    /// loaded or the name is YaHei's.
    static func wordMacIdeographFace(_ family: String) -> String? { wordMacIdeographs(family, eastAsianFace(family)) }
    /// The Word face that draws a name's ideographs (`registerWordMacFaces`);
    /// nil for YaHei's stand-ins, which the glyph fallback draws.
    private static func wordMacIdeographs(_ family: String, _ ea: EastAsianFace) -> String? {
        guard _wordMacFacesLoaded, !isYaHeiLike(ea.height) else { return nil }
        if isUndeclaredMacGBName(family) { return "SimSun" }
        let n = family.trimmingWhitespace().lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { faceHas(n, $0) } }
        if has("明體", "mingliu") { return "PMingLiU" }
        if has("黑体", "simhei") { return "SimHei" }
        if has("楷体", "kaiti") { return "KaiTi" }
        if has("仿宋", "fangsong") { return "FangSong" }
        if has("华文中宋", "stzhongsong") { return "STZhongsong" }
        if has("华文新魏", "stxinwei") { return "STXinwei" }
        if has("等线", "dengxian") { return "DengXian" }
        // (宋体 and the names Word sets in it: FZXiaoBiaoSong by its ASCII
        // name, and a Latin alternate's.)
        if ea.height == square.height || has("宋", "simsun", "song") { return "SimSun" }
        return nil
    }

    /// Starling FangSong: Zhuque Fangsong (OFL) set to FangSong's metrics —
    /// its Latin half an em, its curly quotes and full-width forms an em,
    /// a line of one em (Resources/fonts/README.md). Whether it loaded.
    static let starlingFangSong = "Starling FangSong"
    nonisolated(unsafe) static var _fangSongLoaded = false

    /// The face that draws a 仿宋 name's ideographs, where it is one:
    /// Starling FangSong, in place of the system's fallback (PingFang, a
    /// sans). Its widths are FangSong's, so no line moves; only the
    /// drawing does. Under OFFICE_WORD_FONTS=mac only the names Word for
    /// Mac draws in its own FangSong — 仿宋 and FangSong, and 仿宋_GB2312
    /// where its table's alternate is 仿宋; there the other 仿宋_GB2312
    /// and the 方正 names are YaHei's, as in its prints. In a
    /// document shown as its author had it, those too. (华文仿宋 is a
    /// face of its own, and keeps its own.)
    static func fangSongFamily(_ family: String) -> String? {
        let n = family.trimmingWhitespace().lowercased()
        if _wordMacFacesLoaded, n == "仿宋" || n == "fangsong" { return "FangSong" }
        // (And, in Word for Mac, a _GB2312 name whose table gives it 仿宋:
        // see `eastAsianFace`.)
        if wordOnMac, n == "仿宋_gb2312" || n == "fangsong_gb2312",
           case let a = altName(family)?.trimmingWhitespace().lowercased() ?? "", a == "仿宋" || a == "fangsong" {
            if _wordMacFacesLoaded { return "FangSong" }
            if _fangSongLoaded { return starlingFangSong }
        }
        guard _fangSongLoaded else { return nil }
        if n == "仿宋" || n == "fangsong" { return starlingFangSong }
        guard !wordOnMac, !faceHas(n, "华文"), !n.hasPrefix("st") else { return nil }
        // (As Word for Windows sets it: a name it lacks is FangSong only
        // where its font table gives 仿宋 for it — `wordOnWindows`.)
        if wordOnWindows {
            if n == "仿宋_gb2312" || n == "fangsong_gb2312" { return starlingFangSong }
            let a = altName(family)?.trimmingWhitespace().lowercased() ?? ""
            return (a == "仿宋" || a == "fangsong") ? starlingFangSong : nil
        }
        return faceHas(n, "仿宋") || faceHas(n, "fangsong") ? starlingFangSong : nil
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
        // (A Noto CJK name Word for Windows lacks: it draws the Latin in Cambria, so the gap beside
        // ideographs is half Cambria's average, 0.615 em, not 0.5: jpn 930d98, 2.72-2.77 pt at 9 pt.)
        if let family, wordOnWindows, family.lowercased().hasPrefix("noto sans cjk") || family.lowercased().hasPrefix("noto serif cjk"),
           let w = osAverageWidth["cambria"] { return w }
        guard let family, !isEastAsianFace(family), !family.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) else { return 0.5 }
        // (Word's gap beside East Asian text is half this face's OS/2 xAvgCharWidth: read from the real
        // faces, lab/metrics/latin_avg_all.tsv, 567 faces; a face not in it takes its stand-in's value.)
        if let w = osAverageWidth[family.lowercased()] { return w }
        if let w = standInAverageWidth(substitute(family)) { return w }
        switch substitute(family) {
        case serif: return 0.401
        case mono: return 0.6
        case calibri: return 0.52
        case cambria: return 0.55
        default: return 0.441
        }
    }

    nonisolated(unsafe) private static var _standInAvg: [String: Double?] = [:]
    /// OS/2 xAvgCharWidth over unitsPerEm of the bundled stand-in we actually draw (Regular), for a
    /// face the Word-machine table lacks; nil where the file or table cannot be read.
    static func standInAverageWidth(_ family: String) -> Double? {
        #if os(WASI)
        return nil
        #else
        declaredLock.lock()
        defer { declaredLock.unlock() }
        if let known = _standInAvg[family] { return known }
        var result: Double? = nil
        let files = [sans: "LiberationSans", serif: "LiberationSerif", mono: "LiberationMono",
                     calibri: "Carlito", cambria: "Caladea", verdana: "DejaVuSans"]
        if let file = files[family], let bundle = _bundle("OfficeApp_OfficeApp") {
            let resources = bundle.resourceURL ?? bundle.bundleURL
            let path = resources.appendingPathComponent("fonts/\(file)-Regular.ttf").path
            if let data = FileManager.default.contents(atPath: path) { result = sfntAverageWidth(data) }
        }
        _standInAvg[family] = result
        return result
        #endif
    }

    /// xAvgCharWidth / unitsPerEm from an sfnt's OS/2 and head tables.
    static func sfntAverageWidth(_ data: Data) -> Double? {
        let b = [UInt8](data)
        func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
        func u32(_ o: Int) -> Int { u16(o) << 16 | u16(o + 2) }
        guard b.count > 12 else { return nil }
        var head = -1, os2 = -1
        for t in 0 ..< u16(4) where 12 + 16 * t + 16 <= b.count {
            let at = 12 + 16 * t
            let tag = String(decoding: b[at ..< at + 4], as: UTF8.self)
            if tag == "head" { head = u32(at + 8) } else if tag == "OS/2" { os2 = u32(at + 8) }
        }
        guard head >= 0, os2 >= 0, head + 20 <= b.count, os2 + 4 <= b.count, case let em = u16(head + 18), em > 0 else { return nil }
        let w = u16(os2 + 2)
        let signed = w >= 0x8000 ? w - 0x10000 : w
        return signed > 0 ? Double(signed) / Double(em) : nil
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
        faces += ["Regular", "Bold", "Italic", "BoldItalic"].map { ("NotoSans-\($0).ttf", "Noto Sans") }
        // (Lucida Sans Unicode's stand-in, Liberation Sans's regular and
        // bold with no italic: the face has none, and PowerPoint's print
        // slants its regular — the engine does the same for a family with
        // no italic, where Liberation Sans's own italic has other letters.)
        faces += [("LiberationSans-Regular.ttf", "Starling Lucida Sans"), ("LiberationSans-Bold.ttf", "Starling Lucida Sans")]
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
        // (Word for Windows sets "◎", "◇" and "◆" in Cambria Math, not
        // Segoe UI Symbol, and their line stands no taller for them — lab
        // e6p; "★" and "☆" are Segoe UI Symbol's there too, ~0.067em up.)
        if wordOnWindows { RichTextTheme.segoeSymbolShapes.subtract([0x25CE, 0x25C7, 0x25C6]) }
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
        for (face, files) in cloudFaces {
            for file in files { _ = flutter.swift_bridge.LoadFontFromFile(file, face) }
        }
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
        // (Under OFFICE_WORD_FONTS=mac, Word's own: `registerWordMacFaces`.)
        if wordOnMac, registerWordMacFaces() { RichTextTheme.glyphFallback = ["Microsoft YaHei", "PingFang SC"] }
        // (Mac mode's alone, and here on purpose: macOS and iOS only.)
        if wordOnMac { RichTextTheme.thaiBreaksAtSpaces = true }
        // (Windows mode too: Word for Windows draws these Thai faces in
        // Browallia New, whose widths are Cordia's, and Thonburi's text
        // layer loses clusters — zh-6a4fc013's Thai pages.)
        if wordOnWindows { registerWordCordia() }
        #endif
        // (Word for Windows breaks Thai at its spaces as Word for Mac does:
        // windows' lab, 52 of zh-6a4fc013's 54 matched lines. Only where
        // the Thai is at Browallia's widths, Cordia's: on Linux's Noto
        // Sans Thai at 0.66 its lines ran long — 91.7 -> 89.4, 638 lines
        // to Word's 614 (office1's check).)
        if wordOnWindows { RichTextTheme.thaiBreaksAtSpaces = true }
        // (And on a Windows host, which has no Word for Mac's Cordia to
        // load and so never came here: its Thai, Browallia's widths in
        // Leelawadee UI, broke inside words where Word's breaks at spaces
        // — zh-6a4fc013 48.5 -> 66.9 here, where a Mac host's run of the
        // same Windows mode scores 93.5.)
        #if os(Windows)
        if wordOnWindows { RichTextTheme.thaiBreaksAtSpaces = true }
        #endif
        // (On every platform: set inside the macOS branch, Linux and
        // Windows sweeps under OFFICE_WORD_FONTS=windows never had it, and
        // bug59058's page 28 still lost its last line there.)
        if wordOnWindows { RichTextTheme.wordWindowsPages = true }
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
        // The CJK and script faces a machine would otherwise supply: Resources/fonts/fonts.tsv lists
        // them (file, face of a collection, family, weight, script, fallback order — the one table
        // the web build's manifest reads as well), so a render does not depend on which fonts the
        // machine has installed. A family with a fallback order above 0 joins the glyph fallback.
        if let table = try? String(contentsOf: resources.appendingPathComponent("fonts/fonts.tsv"), encoding: .utf8) {
            var chain: [(order: Int, family: String)] = []
            for line in table.split(separator: "\n").dropFirst() {
                let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard c.count >= 7, let index = Int32(c[1]), let order = Int(c[6]) else { continue }
                let path = resources.appendingPathComponent("fonts/\(c[0])").path
                guard FileManager.default.fileExists(atPath: path) else { continue }
                let loaded = index < 0 ? flutter.swift_bridge.LoadFontFromFile(path, c[2])
                                       : flutter.swift_bridge.LoadFontFromFileFace(path, c[2], index)
                if !loaded {
                    FileHandle.standardError.write("[Office] could not load \(c[2]) from \(path)\n".data(using: .utf8)!)
                } else if order > 0, !chain.contains(where: { $0.family == c[2] }) {
                    chain.append((order, c[2]))
                }
                #if os(Linux)
                // (The Traditional Chinese serif a Ming name's ideographs are drawn in, a second time
                // as the engine's "Ink+<em> " face: the same outlines drawn 0.07 em lower, as Word's
                // print of PMingLiU stands on the same baseline: see `pmingliuInkFamily`.)
                if c[2] == "Noto Serif CJK TC" {
                    _ = flutter.swift_bridge.LoadFontFromFileFace(path, pmingliuInkFamily, index)
                }
                #endif
            }
            // (Bundled mode is the same on every platform: the system's CJK face — PingFang on a Mac
            // or iPhone, YaHei on Windows — gives way to the bundled one. Where the user chose the
            // installed fonts, or Word for Mac's own faces are in play, the system's stay in front.)
            #if !os(Linux)
            if fontSource == .bundled, !wordOnMac, chain.contains(where: { $0.family == "Noto Sans CJK SC" }) {
                RichTextTheme.glyphFallback.removeAll { $0 == "PingFang SC" || $0 == "Microsoft YaHei" }
                cjkFallback = ["Noto Sans CJK SC"]
            }
            #endif
            for (_, family) in chain.sorted(by: { $0.order < $1.order }) where !RichTextTheme.glyphFallback.contains(family) {
                RichTextTheme.glyphFallback.append(family)
            }
            // (The colour pictographs go AHEAD of DejaVu Sans, which draws some of the same emoji as black
            // outlines: Word and PowerPoint draw a plain-run emoji in colour. The subset holds only
            // U+1F000 and up, so the BMP symbols — a black U+263A — stay on the faces that have them.)
            if let i = RichTextTheme.glyphFallback.firstIndex(of: OfficeFonts.emojiPictographs), i > 0 {
                RichTextTheme.glyphFallback.remove(at: i)
                RichTextTheme.glyphFallback.insert(OfficeFonts.emojiPictographs, at: 0)
            }
        }
        if let table = try? String(contentsOf: resources.appendingPathComponent("fonts/fonts-aliases.tsv"), encoding: .utf8) {
            var aliases: [String: String] = [:]
            for line in table.split(separator: "\n").dropFirst() {
                let c = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                if c.count >= 2 { aliases[c[0].lowercased()] = c[1] }
            }
            if fontSource == .bundled, !wordOnMac { bundledAliases = aliases }
        }
        // (OFFICE_BUNDLED_FONTS_ONLY=1: the engine's font lookup sees only the faces registered
        // above — no fontconfig, CoreText or DirectWrite fallback behind them. On whenever the
        // harness pins OFFICE_FONT_SOURCE=bundled, so no baseline moves with the machine's fonts
        // (proved: all 756 + 593 documents print byte-identically with /usr/share/fonts hidden);
        // =0 turns it off, =1 turns it on without the pin. A user running the app with no pin
        // keeps the system fonts for the GUI. An engine without the call says so and goes on.)
        let only = ProcessInfo.processInfo.environment["OFFICE_BUNDLED_FONTS_ONLY"]
        let pinnedBundled = ProcessInfo.processInfo.environment["OFFICE_FONT_SOURCE"]?.lowercased() == "bundled"
        if only == "1" || (pinnedBundled && only != "0") {
            let known = dlopen(nil, RTLD_NOW).map { dlsym($0, "StarlingTextBundledFontsOnlySupported") != nil } ?? false
            if known { flutter.swift_bridge.DisableSystemFontFallback() }
            else { FileHandle.standardError.write("[Office] this engine cannot turn the system fonts off; they stay\n".data(using: .utf8)!) }
        }
        _registrationSucceeded = ok
        return ok
        #endif
    }
}
