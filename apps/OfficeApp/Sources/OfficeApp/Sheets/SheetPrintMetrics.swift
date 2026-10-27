// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// How Excel sizes a sheet for the PRINTER, which is not how it sizes it
// for the screen. A column's stored width is a count of the default
// font's digits, and on paper each of them is the digit's advance at the
// printer's 600 dpi: Calibri 11's is 47 of those, 5.64 pt, where the
// screen's 7 px is 5.25 pt — so every column prints some 7% wider than it
// shows, and a sheet that is ten columns across the screen's page is nine
// across the printed one. Rows go the same way by the font's height: a
// default row is the printer's line (14.52 pt for Calibri 11, not 15), and
// a height someone set is scaled by the printer's line over the screen's.
//
// The numbers are measured, not derived: Excel 16.0 printed a bordered
// grid in each face at each size (the Normal style's font; columns at
// their default, 2 and 4 characters; rows at their default, 20 and 40 pt)
// and the rules' positions were read back from the PDFs. `digit` and `row`
// are in 600ths of an inch. `screenRow` and `screenDigit` are the
// default row and the digit in pixels on the display Excel had, at 192
// dpi: the screen's half of the row scale, and the default column (which
// Excel takes up to a multiple of 8 screen pixels) depends on that display
// too — so these are the pages of an Excel at 200%, the one the corpus's
// references were made with
// (test/corpus/xlsx/README.md). Another display moves a set height by a
// few percent and a default column by under one.

import Foundation

struct SheetPrintMetrics {
    /// One character of column width, in points.
    var digit: Double
    /// A column nobody sized, in characters (padding included).
    var defaultChars: Double
    /// A row nobody sized, in points.
    var defaultRow: Double
    /// What a set row height is multiplied by.
    var rowScale: Double
    /// The digit on that Excel's screen, in its pixels.
    var screenDigit: Double
    /// A row nobody sized, on that Excel's screen, in its pixels.
    var screenRow: Double = 0

    /// A row nobody sized that holds a font with metrics `font`, in a
    /// workbook with these. Excel fits the row on the screen, to the font's
    /// line in whole pixels, and the printer takes those pixels as it takes
    /// a set height — not the font's own line on the printer. Measured with
    /// rows of ten faces in a Verdana 10 and a Calibri 11 workbook (Excel
    /// 16.0, 2026-10-15): Lucida Sans Typewriter 10 among Verdana is 34 px,
    /// 13.32 pt on paper where its own printed line is 12.6; Calibri 14 is
    /// 18.84 pt there and 18.24 among Calibri 11, its own line 18.0. Of the
    /// twelve rows taller than their default, eleven come out within a
    /// 600th of an inch; Arial 12 among Calibri is 0.3 pt short.
    /// A set row height `h` on paper: scaled as the printer scales it
    /// (`scale`, `rowScale` or less), and cut down to whole dots of the
    /// printer's 600 dpi — 20 pt in Arial 10 prints 161 dots, not 161.57
    /// (labs of twelve set heights in Arial 10 and Calibri 11, Excel 16,
    /// 2026-10-15: 22 of 24 to the dot, the others one over). Cut down
    /// from 0.12 of a dot over: lo-tdf131575's 15 pt rows of Arial 8,
    /// 125.93 dots, print 126 (179 rows), lo-tdf171828's 11.25 pt of
    /// Arial 10, 90.88, print 91 (101), where picture.xlsx's 14 pt of
    /// Calibri 11, 118.88, print 118 — and the lab's Calibri rows at .91
    /// one over, at .83 not.
    static func setRow(_ h: Double, scale: Double) -> Double {
        (h * scale * 600 / 72 + 0.12).rounded(.down) * 72 / 600
    }

    func fittedRow(_ font: SheetPrintMetrics) -> Double {
        font.screenRow * 72 / 192 * rowScale
    }

    /// A column `chars` wide, in points. Excel holds a width in whole
    /// screen pixels, so the characters that print are the pixels' worth —
    /// 0.855 characters is 13 px of a 15 px digit, 0.867 — and a run of
    /// narrow columns is a few percent wider than its numbers say.
    func column(_ chars: Double) -> Double {
        guard chars > 0 else { return 0 }
        let px = ((256 * chars + (128 / screenDigit).rounded(.down)) / 256 * screenDigit).rounded(.down)
        return px / screenDigit * digit
    }

    /// The same column on that Excel's screen, in points: its whole pixels
    /// at 192 dpi. What a row is fitted in — Excel fits on the screen.
    func screenColumn(_ chars: Double) -> Double {
        guard chars > 0 else { return 0 }
        let px = ((256 * chars + (128 / screenDigit).rounded(.down)) / 256 * screenDigit).rounded(.down)
        return px * 72 / 192
    }

    /// `offTable`: screen rows at sizes off the table, where Excel's print
    /// showed them — Tables' rows of Times New Roman 20 print 67 px, of its
    /// bold 66, where in proportion to 18 they were 68 and 67;
    /// style-alternate-content's of Malgun Gothic 6, 23 px where in
    /// proportion to 8 they were 26 (Malgun's 8 and 9 are both 35: no line
    /// to extend).
    private struct Face { var digit: [Double], row: [Double], screenRow: [Double], screenDigit: [Double], offTable: [Double: Double] = [:] }
    private static let sizes: [Double] = [8, 9, 10, 10.5, 11, 12, 14, 16, 18]
    private static let faces: [String: Face] = [
        "calibri": Face(digit: [34, 38, 42, 45, 47, 51, 59, 67, 76], row: [90, 99, 109, 116, 121, 130, 150, 171, 191], screenRow: [28, 31, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "arial": Face(digit: [37, 42, 46, 49, 51, 56, 65, 74, 83], row: [85, 93, 103, 110, 114, 123, 143, 161, 181], screenRow: [27, 31, 34, 35, 36, 40, 46, 54, 59],
            screenDigit: [12, 13, 15, 16, 16, 18, 21, 24, 27]),
        "verdana": Face(digit: [43, 48, 53, 56, 58, 64, 74, 85, 95], row: [88, 100, 108, 114, 122, 129, 150, 169, 189], screenRow: [26, 30, 33, 35, 36, 39, 47, 53, 61],
            screenDigit: [13, 15, 17, 18, 18, 20, 24, 27, 31]),
        "times new roman": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [87, 96, 106, 112, 116, 126, 145, 165, 184], screenRow: [27, 31, 35, 36, 37, 41, 47, 54, 61],
            screenDigit: [11, 12, 14, 14, 14, 16, 19, 22, 24], offTable: [20: 67]),
        "courier new": Face(digit: [40, 45, 50, 53, 55, 60, 70, 80, 90], row: [79, 88, 96, 103, 107, 115, 133, 151, 167], screenRow: [28, 32, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [13, 14, 16, 17, 17, 19, 22, 26, 29]),
        "tahoma": Face(digit: [37, 41, 45, 48, 50, 55, 64, 73, 82], row: [89, 98, 108, 114, 119, 129, 149, 168, 189], screenRow: [26, 30, 34, 35, 36, 40, 46, 53, 59],
            screenDigit: [11, 13, 15, 15, 16, 17, 20, 23, 26]),
        "ms pgothic": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [25, 28, 32, 33, 34, 38, 43, 50, 56],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "simsun": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [84, 94, 103, 108, 113, 122, 141, 162, 182], screenRow: [27, 30, 34, 35, 36, 42, 47, 54, 62],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "cambria": Face(digit: [37, 42, 46, 49, 51, 55, 65, 74, 83], row: [87, 96, 105, 112, 115, 125, 145, 164, 184], screenRow: [27, 30, 34, 35, 36, 40, 46, 54, 60],
            screenDigit: [12, 13, 15, 16, 16, 18, 20, 24, 27]),
        "segoe ui": Face(digit: [36, 40, 45, 47, 50, 54, 63, 72, 81], row: [102, 114, 124, 130, 138, 148, 171, 192, 218], screenRow: [34, 35, 41, 42, 44, 50, 54, 64, 70],
            screenDigit: [11, 13, 15, 15, 16, 17, 20, 23, 26]),
        "aptos narrow": Face(digit: [34, 38, 42, 45, 47, 51, 59, 67, 76], row: [95, 106, 116, 122, 127, 137, 159, 180, 201], screenRow: [28, 32, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "aptos": Face(digit: [36, 40, 44, 47, 49, 53, 62, 71, 80], row: [95, 106, 116, 122, 127, 137, 159, 180, 201], screenRow: [28, 32, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 13, 14, 15, 15, 17, 20, 23, 26]),
        "georgia": Face(digit: [41, 46, 51, 54, 56, 61, 72, 82, 92], row: [85, 94, 104, 108, 113, 122, 141, 160, 180], screenRow: [27, 31, 34, 35, 36, 40, 46, 53, 60],
            screenDigit: [13, 15, 17, 17, 18, 20, 23, 26, 29]),
        "trebuchet ms": Face(digit: [35, 39, 44, 46, 48, 52, 61, 70, 79], row: [92, 103, 113, 118, 124, 133, 154, 174, 195], screenRow: [28, 31, 37, 38, 38, 41, 48, 56, 62],
            screenDigit: [11, 13, 14, 15, 15, 17, 19, 23, 25]),
        "century gothic": Face(digit: [37, 42, 46, 49, 51, 55, 65, 74, 83], row: [91, 99, 108, 116, 119, 128, 151, 169, 193], screenRow: [26, 32, 35, 36, 38, 41, 46, 54, 61],
            screenDigit: [12, 13, 15, 16, 16, 18, 21, 24, 27]),
        "malgun gothic": Face(digit: [37, 41, 46, 48, 51, 55, 64, 73, 83], row: [102, 114, 124, 130, 139, 149, 172, 192, 219], screenRow: [35, 35, 42, 42, 45, 51, 55, 66, 72],
            screenDigit: [12, 13, 15, 15, 16, 18, 20, 24, 26], offTable: [6: 23]),
        "yu gothic": Face(digit: [37, 42, 46, 49, 51, 56, 65, 74, 83], row: [113, 128, 140, 149, 154, 164, 192, 219, 245], screenRow: [34, 40, 44, 45, 47, 53, 59, 69, 78],
            screenDigit: [12, 13, 15, 16, 16, 18, 21, 24, 27]),
        "microsoft yahei": Face(digit: [39, 44, 49, 52, 54, 59, 69, 78, 88], row: [99, 109, 121, 125, 130, 144, 163, 185, 208], screenRow: [30, 33, 37, 38, 40, 43, 51, 61, 65],
            screenDigit: [12, 14, 16, 16, 17, 19, 22, 25, 28]),
        "meiryo": Face(digit: [37, 42, 46, 49, 57, 62, 73, 83, 93], row: [113, 128, 140, 149, 152, 164, 190, 216, 242], screenRow: [34, 40, 44, 45, 47, 51, 58, 69, 76],
            screenDigit: [12, 13, 15, 16, 18, 20, 23, 27, 30]),
        "ms gothic": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [25, 28, 32, 33, 34, 38, 43, 50, 56],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "arial narrow": Face(digit: [31, 34, 38, 40, 42, 46, 53, 61, 68], row: [86, 97, 106, 111, 116, 126, 143, 163, 183], screenRow: [27, 31, 34, 36, 36, 40, 47, 54, 61],
            screenDigit: [10, 11, 12, 13, 13, 15, 17, 20, 22]),
        "consolas": Face(digit: [37, 41, 46, 48, 51, 55, 64, 73, 82], row: [87, 96, 105, 111, 116, 125, 145, 163, 184], screenRow: [27, 31, 35, 36, 37, 41, 47, 55, 61],
            screenDigit: [12, 13, 15, 15, 16, 18, 20, 24, 26]),
        "garamond": Face(digit: [31, 35, 39, 41, 43, 47, 55, 62, 70], row: [84, 93, 102, 107, 111, 120, 140, 158, 176], screenRow: [28, 31, 35, 36, 38, 41, 48, 55, 62],
            screenDigit: [10, 11, 13, 13, 14, 15, 17, 20, 23]),
        "book antiqua": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [91, 100, 110, 117, 120, 131, 150, 172, 193], screenRow: [28, 31, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "calibri light": Face(digit: [34, 38, 42, 45, 47, 51, 59, 67, 76], row: [90, 99, 109, 116, 121, 130, 150, 171, 191], screenRow: [28, 31, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "microsoft sans serif": Face(digit: [37, 42, 46, 49, 51, 56, 65, 74, 83], row: [84, 93, 103, 109, 112, 121, 140, 160, 178], screenRow: [27, 31, 33, 35, 36, 41, 45, 54, 60],
            screenDigit: [12, 13, 15, 16, 16, 18, 21, 24, 27]),
        "comic sans ms": Face(digit: [41, 46, 51, 54, 56, 61, 71, 81, 92], row: [111, 121, 133, 140, 147, 159, 183, 206, 234], screenRow: [32, 36, 42, 43, 44, 50, 57, 65, 73],
            screenDigit: [13, 15, 16, 17, 18, 20, 23, 26, 29]),
        "lucida sans unicode": Face(digit: [42, 47, 52, 56, 58, 63, 74, 84, 95], row: [89, 101, 109, 117, 119, 129, 152, 169, 190], screenRow: [26, 30, 36, 35, 36, 40, 46, 55, 61],
            screenDigit: [13, 15, 17, 18, 18, 20, 23, 27, 30]),
        "palatino linotype": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [101, 113, 123, 130, 137, 147, 171, 194, 216], screenRow: [30, 34, 38, 39, 40, 47, 53, 61, 67],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "pmingliu": Face(digit: [31, 35, 39, 41, 43, 47, 55, 62, 70], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [26, 30, 33, 35, 36, 39, 45, 53, 59],
            screenDigit: [10, 11, 13, 13, 14, 15, 17, 20, 23]),
        "lucida sans typewriter": Face(digit: [40, 45, 50, 53, 55, 60, 70, 80, 90], row: [87, 96, 105, 112, 116, 126, 146, 164, 184], screenRow: [26, 30, 34, 35, 36, 40, 46, 53, 59],
            screenDigit: [13, 14, 16, 17, 17, 19, 22, 26, 29]),
        "arial black": Face(digit: [45, 50, 55, 59, 61, 67, 78, 89, 100], row: [110, 122, 133, 141, 146, 159, 185, 208, 234], screenRow: [33, 36, 42, 44, 45, 49, 57, 65, 74],
            screenDigit: [14, 16, 18, 19, 19, 21, 25, 29, 32]),
        "simhei": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [25, 28, 32, 33, 34, 38, 43, 50, 56],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "mingliu": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [26, 30, 33, 35, 36, 39, 45, 53, 59],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        // The bold of a face, where a workbook's default font is bold: its
        // own line, and for some its own digit.
        "calibri bold": Face(digit: [34, 38, 42, 45, 47, 51, 59, 67, 76], row: [90, 99, 109, 116, 121, 130, 150, 171, 191], screenRow: [28, 31, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "arial bold": Face(digit: [37, 42, 46, 49, 51, 56, 65, 74, 83], row: [88, 98, 107, 113, 118, 126, 146, 165, 186], screenRow: [27, 31, 35, 36, 37, 40, 47, 55, 60],
            screenDigit: [12, 13, 15, 16, 16, 18, 21, 24, 27]),
        "verdana bold": Face(digit: [48, 53, 59, 63, 65, 71, 83, 95, 107], row: [88, 100, 108, 114, 122, 129, 150, 169, 189], screenRow: [26, 30, 33, 35, 36, 39, 47, 53, 61],
            screenDigit: [15, 17, 19, 20, 21, 23, 26, 31, 34]),
        "times new roman bold": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [87, 96, 105, 111, 116, 126, 146, 165, 184], screenRow: [27, 30, 34, 35, 36, 40, 46, 53, 60],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24], offTable: [20: 66]),
        "tahoma bold": Face(digit: [43, 48, 53, 56, 59, 64, 75, 85, 96], row: [89, 98, 108, 114, 119, 129, 149, 168, 189], screenRow: [26, 30, 34, 35, 36, 40, 46, 53, 59],
            screenDigit: [13, 15, 17, 18, 18, 20, 24, 27, 31]),
        "courier new bold": Face(digit: [40, 45, 50, 53, 55, 60, 70, 80, 90], row: [84, 93, 100, 109, 113, 122, 142, 158, 178], screenRow: [28, 32, 36, 37, 39, 43, 49, 57, 63],
            screenDigit: [13, 14, 16, 17, 17, 19, 22, 26, 29]),
        "cambria bold": Face(digit: [40, 44, 49, 52, 54, 59, 69, 79, 89], row: [87, 96, 105, 112, 115, 125, 145, 164, 184], screenRow: [27, 30, 34, 35, 36, 40, 46, 54, 60],
            screenDigit: [12, 14, 16, 17, 17, 19, 22, 25, 28]),
        "segoe ui bold": Face(digit: [39, 43, 48, 51, 53, 58, 67, 77, 86], row: [102, 114, 124, 130, 138, 148, 171, 192, 218], screenRow: [34, 35, 41, 42, 44, 50, 54, 64, 70],
            screenDigit: [12, 14, 16, 16, 17, 18, 21, 25, 28]),
    ]
    /// Other names for the measured faces: the clones this app draws with,
    /// and the East Asian faces' own spellings.
    private static let aliases: [String: String] = [
        "carlito": "calibri", "liberation sans": "arial", "arimo": "arial", "helvetica": "arial",
        "helvetica neue": "arial", "liberation serif": "times new roman", "tinos": "times new roman",
        "times": "times new roman", "liberation mono": "courier new", "cousine": "courier new",
        "courier": "courier new", "caladea": "cambria", "宋体": "simsun", "nsimsun": "simsun",
        "ｍｓ ｐゴシック": "ms pgothic", "ｍｓ ゴシック": "ms gothic", "ms ui gothic": "ms pgothic",
        "ms mincho": "ms gothic", "ms pmincho": "ms pgothic", "ｍｓ 明朝": "ms gothic", "ｍｓ ｐ明朝": "ms pgothic",
        "新細明體": "pmingliu", "맑은 고딕": "malgun gothic", "游ゴシック": "yu gothic",
        "微软雅黑": "microsoft yahei", "メイリオ": "meiryo", "meiryo ui": "meiryo",
        "ms sans serif": "microsoft sans serif", "黑体": "simhei", "細明體": "mingliu",
        "lucida sans": "lucida sans unicode", "lucida grande": "lucida sans unicode",
        // (Dotum, Gulim and Batang left Windows; Excel prints them as Malgun Gothic.)
        "돋움": "malgun gothic", "dotum": "malgun gothic", "굴림": "malgun gothic", "gulim": "malgun gothic",
        "바탕": "malgun gothic", "batang": "malgun gothic",
    ]

    private static func face(_ family: String) -> Face {
        let n = family.trimmingWhitespace().lowercased()
        if let f = faces[aliases[n] ?? n] { return f }
        // A face nobody measured: an East Asian one by its name, the rest by
        // the clone this app would draw it with.
        if n.unicodeScalars.contains(where: { $0.value > 0x2E7F }) { return faces["ms pgothic"]! }
        let clone = OfficeFonts.sheetClone(family)
        if clone == OfficeFonts.substitute("Times New Roman") { return faces["times new roman"]! }
        if clone == OfficeFonts.substitute("Courier New") { return faces["courier new"]! }
        if clone == OfficeFonts.substitute("Cambria") { return faces["cambria"]! }
        if clone == OfficeFonts.substitute("Calibri") { return faces["calibri"]! }
        return faces["arial"]!
    }

    /// A face's ascent as Windows has it (OS/2 usWinAscent, or hhea's where
    /// that is the larger: Lucida Sans Typewriter 10 stands 3.54 over a foot
    /// in Excel's print, its hhea ascent's 3.60, not its win ascent's 3.96), in ems — the
    /// line Excel stands a cell's baseline on, where the painter's comes
    /// to whole points (Calibri 11's 10.47 as 10, Calibri 9's 8.57 as 9).
    /// Nil for a face not here.
    static func ascent(family: String) -> Double? {
        let n = family.trimmingWhitespace().lowercased()
        return ascents[aliases[n] ?? n]
    }
    private static let ascents: [String: Double] = [
        "calibri": 0.9521, "arial": 0.9053, "verdana": 1.0054, "times new roman": 0.8911, "courier new": 0.8325,
        "tahoma": 1.0005, "cambria": 0.9502, "microsoft sans serif": 0.9219, "segoe ui": 1.0791, "century gothic": 1.0059,
        "aptos": 1.0098, "aptos narrow": 1.0098, "ms gothic": 0.8594, "ms pgothic": 0.8594, "simsun": 0.8594,
        "simhei": 0.8594, "microsoft yahei": 1.0581, "malgun gothic": 1.0884, "mingliu": 0.8008, "pmingliu": 0.8008,
        "yu gothic": 0.9849, "lucida sans unicode": 1.0967, "lucida sans typewriter": 0.9639, "lucida console": 0.7891,
        "garamond": 0.8618, "book antiqua": 0.9604, "palatino linotype": 1.0498, "bookman old style": 0.9419,
        "century": 0.9858, "georgia": 0.917, "trebuchet ms": 0.939, "consolas": 0.9199, "comic sans ms": 1.1021,
        "arial narrow": 0.9355, "arial black": 1.1006, "franklin gothic medium": 0.9165, "gill sans mt": 0.9292,
        "candara": 0.9521, "corbel": 0.9521, "constantia": 0.9521,
    ]

    /// A measured value at `size`: between the sizes measured, and in
    /// proportion beyond them.
    private static func at(_ values: [Double], _ size: Double) -> Double {
        if size <= sizes[0] { return values[0] * size / sizes[0] }
        if size >= sizes[sizes.count - 1] { return values[values.count - 1] * size / sizes[sizes.count - 1] }
        let i = sizes.firstIndex { $0 >= size }!
        if sizes[i] == size { return values[i] }
        let t = (size - sizes[i - 1]) / (sizes[i] - sizes[i - 1])
        return values[i - 1] + (values[i] - values[i - 1]) * t
    }

    /// The metrics of a workbook whose default font is `family` at `size`;
    /// `baseColWidth` is the sheet's (8 digits unless it says otherwise).
    static func of(family: String, size: Double, bold: Bool = false, baseColWidth: Double = 8) -> SheetPrintMetrics {
        let plain = aliases[family.trimmingWhitespace().lowercased()] ?? family.trimmingWhitespace().lowercased()
        let f = (bold ? faces[plain + " bold"] : nil) ?? face(family)
        // (A printer's line between the sizes measured is the next whole
        // dot up: 49609's Microsoft Sans Serif 8.25 is 87 of 84 and 93,
        // its set 15 pt rows 124 dots in Excel's print where 86 made 122.)
        let between = size > sizes[0] && size < sizes[sizes.count - 1]
        let digit = at(f.digit, size).rounded(), row = at(f.row, size).rounded(between ? .up : .toNearestOrAwayFromZero)
        let screenRow = max(1, (f.offTable[size] ?? at(f.screenRow, size)).rounded())
        // The default column, as that Excel's screen made it: the digit there
        // in whole pixels, its padding, and the sum up to a multiple of 8.
        let screenDigit = max(1, at(f.screenDigit, size).rounded())
        let pad = 2 * (screenDigit / 4).rounded(.up) + 1
        let px = ((baseColWidth * screenDigit + pad) / 8).rounded(.up) * 8
        return SheetPrintMetrics(digit: digit * 72 / 600, defaultChars: px / screenDigit,
                                 defaultRow: row * 72 / 600, rowScale: (row / 600) / (screenRow / 192), screenDigit: screenDigit,
                                 screenRow: screenRow)
    }
}
