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
        default: return family
        }
    }

    /// The shipped face for a family name, by Word's names first and by
    /// the look of the name after that. Case-insensitive.
    static func substitute(_ family: String) -> String {
        let n = family.trimmingWhitespace().lowercased()
        switch n {
        case "liberation sans", "arial", "helvetica", "helvetica neue", "verdana", "tahoma",
             "segoe ui", "aptos", "arimo":
            return sans
        case "liberation serif", "times new roman", "times", "georgia", "book antiqua",
             "garamond", "palatino", "tinos":
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
            if n.containsSubstring("serif") && !n.containsSubstring("sans") { return serif }
            if n.containsSubstring("times") || n.containsSubstring("roman") || n.containsSubstring("garamond")
                || n.containsSubstring("baskerville") || n.containsSubstring("didot") {
                return serif
            }
            return sans
        }
    }

    /// Names a file's font table declares in the Latin character set
    /// (`w:charset` 00) that are no face Word has: "S宋体" reads as a
    /// Chinese face and is not one — Word sets its letters, digits and
    /// quotes in a Latin face. (A face Word has it knows whatever the
    /// table says: six files of the corpus declare 宋体 that way.)
    private nonisolated(unsafe) static var declaredLatin: Set<String> = []
    private static let declaredLock = NSLock()
    private static let wordsOwn: Set<String> = [
        "宋体", "simsun", "新宋体", "nsimsun", "黑体", "simhei", "楷体", "kaiti", "仿宋", "fangsong", "微软雅黑", "microsoft yahei",
        "microsoft yahei ui", "等线", "等线 light", "dengxian", "dengxian light", "新細明體", "pmingliu", "細明體", "mingliu",
        "微軟正黑體", "microsoft jhenghei", "华文中宋", "华文仿宋", "华文楷体", "华文宋体", "华文细黑", "stsong", "stkaiti",
        "stfangsong", "stzhongsong", "stxihei", "arial unicode ms", "幼圆", "youyuan", "隶书", "lisu",
    ]

    /// Takes a file's font table: each name and its `w:charset`.
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
                    "stsong", "stkaiti", "stfangsong", "stzhongsong", "stxihei", "stheiti", "songti", "heiti",
                    "pingfang", "hiragino", "mincho", "ms gothic", "yu gothic", "meiryo", "malgun", "batang", "gulim", "dotum",
                    "cjk", "source han", "wenquanyi", "arial unicode", "fzs", "fzf", "fzk", "fzh", "fzx"] where n.containsSubstring(key) {
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
        /// Word emboldens a face that has no bold of its own, and sets
        /// each character 1/57 em wider.
        var fakeBold: Bool
        /// The baseline below the top of a single line, in ems: the
        /// face's ascent and half of what Word adds to its height.
        var baseline: Double? = nil
        /// The same two for characters with a scale of their own
        /// (`w:w`), where they differ: Word measures those by the
        /// face's OS/2 ascent and descent rather than its hhea ones.
        var scaledHeight: Double? = nil
        var scaledBaseline: Double? = nil
    }

    private static let square = EastAsianFace(height: 1.3, latin: mono, latinScale: 5.0 / 6.0, fakeBold: true, baseline: 1.005)
    private static let yaHei = EastAsianFace(height: 1.72, latin: sans, latinScale: 1.07, latinClasses: [0.985, 0.92, 1.027, 0.96], fakeBold: false, baseline: 1.26)

    private static func eastAsianFace(_ family: String) -> EastAsianFace {
        let n = family.trimmingWhitespace().lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { n.containsSubstring($0) } }
        if has("yahei ui") { return EastAsianFace(height: 1.67, latin: sans, latinScale: 1.07, fakeBold: false) }
        if has("yahei", "微软雅黑") { return yaHei }
        if has("jhenghei", "微軟正黑") { return EastAsianFace(height: 1.74, latin: sans, latinScale: 1.05, latinClasses: [0.991, 0.925, 1.031, 0.95], fakeBold: false) }
        if has("dengxian", "等线") { return EastAsianFace(height: 1.36, latin: sans, latinScale: 0.955, latinClasses: [0.992, 0.927, 1.021, 0.91], fakeBold: false, baseline: 1.01) }
        if has("pmingliu", "新細明體") { return EastAsianFace(height: 1.3, latin: serif, latinScale: 0.94, fakeBold: true) }
        if has("stzhongsong", "华文中宋") {
            // (hhea 1.007 + .318, OS/2 win .912 + .225: 105.3pt a line at
            // 61pt, and 90.2 at 34% of its width.)
            return EastAsianFace(height: 1.7225, latin: serif, latinScale: 1.16, fakeBold: true, baseline: 1.206,
                                 scaledHeight: 1.478, scaledBaseline: 1.083)
        }
        if has("stfangsong", "华文仿宋") { return EastAsianFace(height: 1.71, latin: serif, latinScale: 1.0, fakeBold: false) }
        if has("stkaiti", "华文楷体") { return EastAsianFace(height: 1.7, latin: serif, latinScale: 1.04, fakeBold: true) }
        if has("stsong", "华文宋体") { return EastAsianFace(height: 1.31, latin: serif, latinScale: 1.0, fakeBold: true) }
        if has("arial unicode") { return EastAsianFace(height: 1.75, latin: sans, latinScale: 1.0, fakeBold: true) }
        // Word on a Mac has 宋体, 黑体, 楷体, 仿宋 and the 明體 pair, and
        // sets every other Chinese name — 仿宋_GB2312, the 方正 faces,
        // 標楷體 — in Microsoft YaHei, which is taller and wider than
        // any of them. `OFFICE_WORD_FONTS=mac` does the same, so that a
        // print can be compared with that Word's; without it such a
        // name is taken for the square face its author had.
        if wordOnMac, !has("simsun", "宋体", "simhei", "黑体", "kaiti", "楷体", "fangsong", "仿宋", "mingliu", "細明體",
                           "幼圆", "全真楷書") || has("仿宋_gb2312", "方正", "小标宋", "標楷") {
            return yaHei
        }
        return square
    }

    private static let wordOnMac = ProcessInfo.processInfo.environment["OFFICE_WORD_FONTS"] == "mac"

    /// The theme's `faceResolver`: the shipped face for a name, and for
    /// an East Asian face Word's measure of it — see `EastAsianFace`.
    /// East Asian text in a Latin face is set in the face Word falls
    /// back to, 宋体. The ideographs themselves are drawn by whatever
    /// the platform falls back to; they are an em wide in every face.
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
            return RichResolvedFace(family: clone, baseline: baseline)
        }
        // (A name the table declares Latin still sets East Asian text
        // as the face it names.)
        let ea = own || family.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) ? eastAsianFace(family) : square
        if eastAsian {
            var face = RichResolvedFace(family: substitute(family), naturalHeight: ea.height, boldSpread: ea.fakeBold ? 1.0 / 57 : 0,
                                        baseline: ea.baseline)
            face.scaledHeight = ea.scaledHeight
            face.scaledBaseline = ea.scaledBaseline
            return face
        }
        var face = RichResolvedFace(family: ea.latin, sizeScale: ea.latinScale, naturalHeight: ea.height,
                                    boldSpread: ea.fakeBold ? 1.0 / 57 : 0, classScales: ea.latinClasses, baseline: ea.baseline,
                                    isEastAsian: true)
        face.scaledHeight = ea.scaledHeight
        face.scaledBaseline = ea.scaledBaseline
        return face
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

    private static func _bundle(_ name: String) -> Bundle? {
        var roots: [URL] = []
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

    @discardableResult
    static func register() -> Bool {
        if _registered { return true }
        _registered = true
        #if os(WASI)
        // The page preloads UI/default faces. Other document families are
        // requested by the paragraph builder when used and trigger relayout
        // once registered (build/web-app.sh writes fonts/manifest.json).
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
        #endif
        guard let bundle = _bundle("OfficeApp_OfficeApp") else {
            FileHandle.standardError.write("[Office] font bundle not found; documents use the engine's default face\n".data(using: .utf8)!)
            return false
        }
        var ok = true
        for (file, family) in [("LiberationSans", sans), ("LiberationSerif", serif), ("LiberationMono", mono),
                               ("Carlito", calibri), ("Caladea", cambria)] {
            for variant in ["Regular", "Bold", "Italic", "BoldItalic"] {
                let path = bundle.bundleURL.appendingPathComponent("fonts/\(file)-\(variant).ttf").path
                if !flutter.swift_bridge.LoadFontFromFile(path, family) {
                    ok = false
                    FileHandle.standardError.write("[Office] could not load \(path)\n".data(using: .utf8)!)
                }
            }
        }
        return ok
        #endif
    }
}
