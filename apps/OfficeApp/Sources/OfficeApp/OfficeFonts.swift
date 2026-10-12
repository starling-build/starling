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

    /// Whether a family name is an East Asian face: written in its own
    /// script (宋体, 標楷體, ＭＳ 明朝), or one of the Latin names those
    /// faces also go by.
    static func isEastAsianFace(_ family: String) -> Bool {
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
        /// Word emboldens a face that has no bold of its own, and sets
        /// each character 1/57 em wider.
        var fakeBold: Bool
    }

    private static let square = EastAsianFace(height: 1.3, latin: mono, latinScale: 5.0 / 6.0, fakeBold: true)
    private static let yaHei = EastAsianFace(height: 1.72, latin: sans, latinScale: 1.07, fakeBold: false)

    private static func eastAsianFace(_ family: String) -> EastAsianFace {
        let n = family.trimmingWhitespace().lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { n.containsSubstring($0) } }
        if has("yahei ui") { return EastAsianFace(height: 1.67, latin: sans, latinScale: 1.07, fakeBold: false) }
        if has("yahei", "微软雅黑") { return yaHei }
        if has("jhenghei", "微軟正黑") { return EastAsianFace(height: 1.74, latin: sans, latinScale: 1.05, fakeBold: false) }
        if has("dengxian", "等线") { return EastAsianFace(height: 1.36, latin: sans, latinScale: 0.955, fakeBold: false) }
        if has("pmingliu", "新細明體") { return EastAsianFace(height: 1.3, latin: serif, latinScale: 0.94, fakeBold: true) }
        if has("stzhongsong", "华文中宋") { return EastAsianFace(height: 1.74, latin: serif, latinScale: 1.16, fakeBold: true) }
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
        guard own || eastAsian else { return nil }
        let ea = own ? eastAsianFace(family) : square
        if eastAsian {
            return RichResolvedFace(family: substitute(family), naturalHeight: ea.height, boldSpread: ea.fakeBold ? 1.0 / 57 : 0)
        }
        return RichResolvedFace(family: ea.latin, sizeScale: ea.latinScale, naturalHeight: ea.height,
                                boldSpread: ea.fakeBold ? 1.0 / 57 : 0)
    }

    /// The theme's `averageCharWidth`: the OS/2 average character width
    /// of the face Word sets a Latin name in, in ems.
    static func averageCharWidth(_ family: String?) -> Double {
        guard let family, !isEastAsianFace(family) else { return 0.5 }
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
