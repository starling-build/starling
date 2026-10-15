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
             "segoe ui", "aptos", "arimo":
            return sans
        case "verdana", "dejavu sans", "bitstream vera sans":
            return verdana
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
        /// The face's own widths for U+0020 to U+007E, in ems, and its
        /// bold's (`RichResolvedFace.advances`): the stand-in is set
        /// to them character by character.
        var latinAdvances: [Double]? = nil
        var latinBoldAdvances: [Double]? = nil
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
    private static let yaHei = EastAsianFace(height: 1.715, latin: sans, latinScale: 1.07, latinClasses: [0.985, 0.92, 1.027, 0.96],
                                             latinAdvances: yaHeiAdvances, latinBoldAdvances: yaHeiBoldAdvances, fakeBold: false, baseline: 1.26)

    // The horizontal advances of U+0020 to U+007E in the faces whose
    // Latin is drawn by a stand-in, in ems, read from the faces' own
    // tables (2026-10-12): what Word breaks a line by.
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

    private static func eastAsianFace(_ family: String) -> EastAsianFace {
        let n = family.trimmingWhitespace().lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { n.containsSubstring($0) } }
        if has("yahei ui") {
            return EastAsianFace(height: 1.67, latin: sans, latinScale: 1.07, latinAdvances: yaHeiUIAdvances, latinBoldAdvances: yaHeiUIBoldAdvances,
                                 fakeBold: false)
        }
        if has("yahei", "微软雅黑") { return yaHei }
        if has("jhenghei", "微軟正黑") {
            return EastAsianFace(height: 1.74, latin: sans, latinScale: 1.05, latinClasses: [0.991, 0.925, 1.031, 0.95],
                                 latinAdvances: jhengHeiAdvances, latinBoldAdvances: jhengHeiBoldAdvances, fakeBold: false)
        }
        if has("dengxian", "等线") {
            return EastAsianFace(height: 1.36, latin: sans, latinScale: 0.955, latinClasses: [0.992, 0.927, 1.021, 0.91],
                                 latinAdvances: dengXianAdvances, latinBoldAdvances: dengXianBoldAdvances, fakeBold: false, baseline: 1.01)
        }
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
        // (A name with an alternate the table gives is set in that,
        // where the alternate is one Word has.)
        // (Only for a name Word has no face for at all, and only to an
        // alternate it has: 楷体_GB2312 is KaiTi to it whatever the table
        // offers — zh-232090e0's 方正楷体_GBK — and 方正 names fall back.)
        let wordHas = ["simsun", "宋体", "新宋体", "simhei", "黑体", "kaiti", "楷体", "fangsong", "仿宋", "mingliu", "細明體",
                       "微软雅黑", "microsoft yahei", "幼圆", "全真楷書", "標楷", "方正", "小标宋"]
        if wordOnMac, !isEmbedded(family), !wordHas.contains(where: { n.containsSubstring($0) }),
           let alt = altName(family), alt.trimmingWhitespace().lowercased() != n {
            let a = alt.trimmingWhitespace().lowercased()
            let usable = ["simsun", "宋体", "新宋体", "simhei", "黑体", "kaiti", "楷体", "mingliu", "細明體"]
            if usable.contains(where: { a.containsSubstring($0) }), !["_gb2312", "方正", "小标宋", "標楷"].contains(where: { a.containsSubstring($0) }) {
                return eastAsianFace(alt)
            }
        }
        if wordOnMac, !isEmbedded(family), !has("simsun", "宋体", "simhei", "黑体", "kaiti", "楷体", "fangsong", "仿宋", "mingliu", "細明體",
                           "幼圆", "全真楷書") || has("仿宋_gb2312", "方正", "小标宋", "標楷") {
            return yaHei
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
            var face = RichResolvedFace(family: clone, baseline: baseline)
            if clone != calibri {
                face.otherAdvances = circled(1.2007)
                face.boldOtherAdvances = circled(1.2207)
            }
            if clone == serif {
                face.otherAdvances?.merge(timesNumerals) { $1 }
                face.boldOtherAdvances?.merge(timesBoldNumerals) { $1 }
            }
            return face
        }
        // (A name the table declares Latin still sets East Asian text
        // as the face it names.)
        let ea = own || family.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) ? eastAsianFace(family) : square
        if eastAsian {
            var face = RichResolvedFace(family: substitute(family), naturalHeight: ea.height, boldSpread: ea.fakeBold ? 1.0 / 57 : 0,
                                        baseline: ea.baseline)
            // (A square face's symbols are an em; YaHei's, JhengHei's and
            // DengXian's — the faces with Latin widths of their own — are not.)
            face.fullWidthSymbols = ea.latinAdvances == nil
            face.scaledHeight = ea.scaledHeight
            face.scaledBaseline = ea.scaledBaseline
            return face
        }
        var face = RichResolvedFace(family: ea.latin, sizeScale: ea.latinScale, naturalHeight: ea.height,
                                    boldSpread: ea.fakeBold ? 1.0 / 57 : 0, classScales: ea.latinClasses, baseline: ea.baseline,
                                    isEastAsian: true)
        face.scaledHeight = ea.scaledHeight
        face.scaledBaseline = ea.scaledBaseline
        face.advances = ea.latinAdvances
        face.boldAdvances = ea.latinBoldAdvances
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
        #if os(Windows)
        // Chinese text, named as on macOS: left to the platform, the
        // engine picks a face per run from its first character, and a
        // run of a lone "〕" came out in Yu Gothic UI, whose brackets are
        // half an em — a line of zh-1a3c7aa0 then had room for a digit
        // Word's has not. YaHei is the face Word for Mac sets these in.
        RichTextTheme.glyphFallback.append("Microsoft YaHei")
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
        var ok = true
        for (file, family) in [("LiberationSans", sans), ("LiberationSerif", serif), ("LiberationMono", mono),
                               ("Carlito", calibri), ("Caladea", cambria), ("DejaVuSans", verdana)] {
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
