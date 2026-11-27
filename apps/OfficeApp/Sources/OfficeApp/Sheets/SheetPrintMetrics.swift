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
    /// What a set row height is multiplied by where the face's set rows stand on another screen row than its fitted ones (`Face.setScreenRow`); `rowScale` otherwise.
    var setRowScale: Double
    /// The face's set rows stand on their own screen row (see `setRowScale`).
    var setOwn: Bool = false
    /// ...and does so at 100 % too (the 8-dots-a-point grid faces: 돋움 11's 45 pt rows print 43.2 pt in ko-5907e2d9ba, a 100 % print).
    var setOwnAt100: Bool = false
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

    /// A set row of a face whose set rows stand on their own screen row, in a print at `printPct` < 100:
    /// the height is held in quarter screen pixels (50.1 pt -> 50.0625 -> 403 dots), cut to whole dots at 100 %,
    /// and the dots of the scaled print are that count times the scale, rounded half up (30.375 pt at 58 %: 142).
    /// The result is given back at 100 % (dots / scale) so the page scale that follows lands on whole dots.
    static func setRowOwn(_ h: Double, scale: Double, printPct: Double) -> Double {
        let q = (h / 0.1875).rounded() * 0.1875
        let dots100 = (q * scale * 600 / 72 + 0.12).rounded(.down)
        let s = printPct / 100
        let dots = (dots100 * s + 0.5).rounded(.down)
        return dots / s * 72 / 600
    }

    /// A row of a face the print box has but the tables lack: its stored height
    /// is a whole number of 96-dpi screen pixels, and Excel prints each pixel as
    /// 6.35 printer dots, rounded to a whole dot (Noto Sans 11: 16.5 pt = 22 px
    /// = 140 dots; Roboto 10: 12.75 pt = 17 px = 108 dots).
    static func screenPixelRow(_ pt: Double) -> Double {
        ((pt * 96 / 72).rounded() * 6.35).rounded() * 72 / 600
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

    /// `hinted`: screen rows that replace the table's where the sheet does not
    /// set its own default height (Segoe UI 8 in a Calibri 11 book fits 14.88
    /// in the Windows lab and lo-tdf76115, but ~12.4 in 56274, whose sheet
    /// sets the default).
    /// `offTable`: screen rows at sizes off the table, where Excel's print
    /// showed them — Tables' rows of Times New Roman 20 print 67 px, of its
    /// bold 66, where in proportion to 18 they were 68 and 67;
    /// style-alternate-content's of Malgun Gothic 6, 23 px where in
    /// proportion to 8 they were 26 (Malgun's 8 and 9 are both 35: no line
    /// to extend).
    private struct Face { var digit: [Double], row: [Double], screenRow: [Double], screenDigit: [Double], gridSet: Set<Double> = [], setScreenRow: [Double: Double] = [:], offTable: [Double: Double] = [:], hinted: [Double: Double] = [:], plainBook: [Double: Double] = [:] }
    private static let sizes: [Double] = [8, 9, 10, 10.5, 11, 12, 14, 16, 18]
    private static let faces: [String: Face] = [
        "calibri": Face(digit: [34, 38, 42, 45, 47, 51, 59, 67, 76], row: [90, 99, 109, 116, 121, 130, 150, 171, 191], screenRow: [28, 31, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24], hinted: [12: 41.75], plainBook: [9: 34]),
        "arial": Face(digit: [37, 42, 46, 49, 51, 56, 65, 74, 83], row: [85, 93, 103, 110, 114, 123, 143, 161, 181], screenRow: [27, 31, 34, 35, 36, 40, 46, 54, 59],
            screenDigit: [12, 13, 15, 16, 16, 18, 21, 24, 27], hinted: [12: 40.85]),
        "verdana": Face(digit: [43, 48, 53, 56, 58, 64, 74, 85, 95], row: [88, 100, 108, 114, 122, 129, 150, 169, 189], screenRow: [26, 30, 33, 35, 36, 39, 47, 53, 61],
            screenDigit: [13, 15, 17, 18, 18, 20, 24, 27, 31], hinted: [12: 40.85], plainBook: [12: 38.85]),
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
            screenDigit: [11, 13, 15, 15, 16, 17, 20, 23, 26], hinted: [8: 39, 10: 40.85], plainBook: [8: 37, 9: 36]),
        "aptos narrow": Face(digit: [34, 38, 42, 45, 47, 51, 59, 67, 76], row: [95, 106, 116, 122, 127, 137, 159, 180, 201], screenRow: [28, 32, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "aptos": Face(digit: [36, 40, 44, 47, 49, 53, 62, 71, 80], row: [95, 106, 116, 122, 127, 137, 159, 180, 201], screenRow: [28, 32, 35, 37, 38, 42, 48, 56, 62],
            screenDigit: [11, 13, 14, 15, 15, 17, 20, 23, 26]),
        "georgia": Face(digit: [41, 46, 51, 54, 56, 61, 72, 82, 92], row: [85, 94, 104, 108, 113, 122, 141, 160, 180], screenRow: [27, 31, 34, 35, 36, 40, 46, 53, 60],
            screenDigit: [13, 15, 17, 17, 18, 20, 23, 26, 29]),
        "trebuchet ms": Face(digit: [35, 39, 44, 46, 48, 52, 61, 70, 79], row: [92, 103, 113, 118, 124, 133, 154, 174, 195], screenRow: [28, 31, 37, 38, 38, 41, 48, 56, 62],
            // (Excel's own print of Trebuchet MS rows at every size 12-26, lab/trebrow, as screen px: 12 41, 13 45, 14 48, 15 51, 16 56,
            // 17 58, 18 62, 19 66, 20 68, 21 73, 22 75, 23 79, 24 82, 25 86, 26 89; the sizes between the table's points stood off by a px.)
            screenDigit: [11, 13, 14, 15, 15, 17, 19, 23, 25], offTable: [15: 51, 17: 58, 19: 66, 20: 68, 21: 73, 22: 75, 24: 82, 26: 89]),
        "century gothic": Face(digit: [37, 42, 46, 49, 51, 55, 65, 74, 83], row: [91, 99, 108, 116, 119, 128, 151, 169, 193], screenRow: [26, 32, 35, 36, 38, 41, 46, 54, 61],
            screenDigit: [12, 13, 15, 16, 16, 18, 21, 24, 27]),
        "malgun gothic": Face(digit: [37, 41, 46, 48, 51, 55, 64, 73, 83], row: [102, 114, 124, 130, 139, 149, 172, 192, 219], screenRow: [35, 35, 42, 42, 45, 51, 55, 66, 72],
            screenDigit: [12, 13, 15, 15, 16, 18, 20, 24, 26], offTable: [6: 23], hinted: [10: 41.75]),
        // Dotum and Gulim print in their own faces (the corpus prints embed them) with their own rows: the em in dots at 600 dpi
        // plus about ten (lab cjkrows3, Gulim 8-18: 77 ... 160 dots; lab xls-rowkeep, 돋움 11 rows at 12.24 pt), and on the screen
        // the em in whole pixels at 192 dpi plus five (11 pt: 34 px, so 24 pt set rows print 23.05 as in ko-6756e229a1; 10 pt: 32 px,
        // ko-3ca2381bbc's set rows of 굴림 10 at 0.93). Batang still has Malgun's rows (no lab yet). A column's unit is the face's own
        // digit (font file advances of 597, 588, 610 and 597 per 1024 em) in whole dots of the
        // 600 dpi em (11 pt: 92 dots, Dotum's digit 54 where Malgun's is 51: 0453e2c911's two columns, 509.8 pt, 36.0 + 473.8).
        "dotum": Face(digit: [39, 44, 49, 51, 54, 58, 68, 78, 88], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [26, 29, 32, 33, 34, 37, 42, 48, 53],
            screenDigit: [12, 13, 15, 15, 16, 18, 20, 24, 26], gridSet: [11]),
        "gulim": Face(digit: [38, 43, 48, 50, 53, 57, 67, 76, 86], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [26, 29, 32, 33, 34, 37, 42, 48, 53],
            screenDigit: [12, 13, 15, 15, 16, 18, 20, 24, 26]),
        // Batang has Dotum's em (879 + 145 of 1024), so its rows are Dotum's too (21 Batang books: 13 of 744 ko books up, none down).
        "batang": Face(digit: [39, 45, 50, 52, 55, 60, 70, 79, 89], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [26, 29, 32, 33, 34, 37, 42, 48, 53],
            screenDigit: [12, 13, 15, 15, 16, 18, 20, 24, 26]),
        // Nirmala UI: a wrapped line is the face's GDI height plus its descent at 600 dpi (12 pt: 133 + 26 = 159 dots, 50 screen
        // pixels; zwsp2 lab, Excel 16: one line of Nirmala UI 12 is 19.07 pt, two 38.1, three 57.2, where Calibri 12 is 15.3).
        // The other sizes follow from the face's GDI heights (gdi-textmetrics-600dpi-indic); the digits stand in as Calibri's.
        "nirmala ui": Face(digit: [34, 38, 42, 45, 47, 51, 59, 67, 76], row: [106, 119, 131, 139, 147, 159, 185, 208, 233], screenRow: [33, 37, 41, 43, 46, 50, 58, 66, 74],
            screenDigit: [12, 13, 14, 15, 15, 16, 19, 21, 24]),
        "yu gothic": Face(digit: [37, 42, 46, 49, 51, 56, 65, 74, 83], row: [113, 128, 140, 149, 154, 164, 192, 219, 245], screenRow: [34, 40, 44, 45, 47, 53, 59, 69, 78],
            screenDigit: [12, 13, 15, 16, 16, 18, 21, 24, 27]),
        "microsoft yahei": Face(digit: [39, 44, 49, 52, 54, 59, 69, 78, 88], row: [99, 109, 121, 125, 130, 144, 163, 185, 208], screenRow: [30, 33, 37, 38, 40, 43, 51, 61, 65],
            screenDigit: [12, 14, 16, 16, 17, 19, 22, 25, 28]),
        "meiryo": Face(digit: [37, 42, 46, 49, 57, 62, 73, 83, 93], row: [113, 128, 140, 149, 152, 164, 190, 216, 242], screenRow: [34, 40, 44, 45, 47, 51, 58, 69, 76],
            screenDigit: [12, 13, 15, 16, 18, 20, 23, 27, 30]),
        // Meiryo UI: the line pitch Excel prints (lab meiryoui-rows: 97, 109, 118, 131, 141, 164 dots at 8, 9, 10, 11, 12, 14 pt),
        // about 0.86 of Meiryo's; 10.5, 16 and 18 pt at the same ratio.
        // The screen rows of 16 and 18 pt step 3.5 px a point as 12 to 14 do (59, 65, lab meiryoui-rows2 auto rows 15/16/18/20/24 pt = 53/59/65/71/86 px; 20 and 24 follow the table's proportion to within a px; ja-d9ac78f0cb's auto rows of 18 pt empty cells print 25.6 pt =
        // 65 px; 69 made them 27.1 and the fit one percent short).
        "meiryo ui": Face(digit: [37, 42, 46, 49, 57, 62, 73, 83, 93], row: [97, 109, 118, 127, 131, 141, 164, 186, 209], screenRow: [27, 33, 37, 38, 40, 44, 51, 59, 65],
            screenDigit: [12, 13, 15, 16, 18, 20, 23, 27, 30], offTable: [15: 53, 20: 71, 24: 86]),
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
        // PMingLiU and MingLiU print a line of em + descent + external leading (= descent) + half the descent more, in 600-dpi dots, em = round(size x 600/72), descent = em - round(0.8008 em): GDI dump at 600 dpi, 6 sizes x 2 faces, 12/12 of Excel's pitches (the planner's spec, 2026-11-23).
        "pmingliu": Face(digit: [31, 35, 39, 41, 43, 47, 55, 62, 70], row: [87, 98, 109, 115, 119, 130, 152, 172, 195], screenRow: [26, 30, 33, 35, 36, 39, 45, 53, 59],
            screenDigit: [10, 11, 13, 13, 14, 15, 17, 20, 23], setScreenRow: [12: 43]),
        "lucida sans typewriter": Face(digit: [40, 45, 50, 53, 55, 60, 70, 80, 90], row: [87, 96, 105, 112, 116, 126, 146, 164, 184], screenRow: [26, 30, 34, 35, 36, 40, 46, 53, 59],
            screenDigit: [13, 14, 16, 17, 17, 19, 22, 26, 29]),
        "arial black": Face(digit: [45, 50, 55, 59, 61, 67, 78, 89, 100], row: [110, 122, 133, 141, 146, 159, 185, 208, 234], screenRow: [33, 36, 42, 44, 45, 49, 57, 65, 74],
            screenDigit: [14, 16, 18, 19, 19, 21, 25, 29, 32]),
        "simhei": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [25, 28, 32, 33, 34, 38, 43, 50, 56],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        // Microsoft JhengHei: rows are the MS PGothic ones: the lab cjkrows3 rows (93, 103, ... dots) cost zh-7e194ea1d0 16.6 to 13.6 against the corpus print, which sets these rows at the PGothic pitch (as for Gulim). Lab values were (lab cjkrows3, jheng-8..18: 93, 103, 113, 119, 124, 133, 155, 175, 196 dots at 8 to 18 pt);
        // digits from the GDI advances of "0" (gdi-advance-by-em-jhenghei: 12, 14, 16, 16, 17, 19, 21, 25, 28 px at the 192-dpi em,
        // 0.58 em at 600 dpi). The fitted screen rows stand at 0.32 of the print rows (not measured).
        "jhenghei-cjk": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [77, 85, 93, 98, 102, 110, 127, 143, 160], screenRow: [25, 28, 32, 33, 34, 38, 43, 50, 56],
            screenDigit: [11, 12, 14, 14, 15, 16, 19, 22, 24]),
        "mingliu": Face(digit: [34, 38, 42, 44, 46, 50, 59, 67, 75], row: [87, 98, 109, 115, 119, 130, 152, 172, 195], screenRow: [26, 30, 33, 35, 36, 39, 45, 53, 59],
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
        "courier": "courier new", "nirmala text": "nirmala ui", "caladea": "cambria", "宋体": "simsun", "nsimsun": "simsun",
        "ｍｓ ｐゴシック": "ms pgothic", "ｍｓ ゴシック": "ms gothic", "ms ui gothic": "ms pgothic",
        "ms mincho": "ms gothic", "ms pmincho": "ms pgothic", "ｍｓ 明朝": "ms gothic", "ｍｓ ｐ明朝": "ms pgothic",
        "新細明體": "pmingliu", "微軟正黑體": "jhenghei-cjk", "맑은 고딕": "malgun gothic", "游ゴシック": "yu gothic",
        "微软雅黑": "microsoft yahei", "メイリオ": "meiryo", 
        "ms sans serif": "microsoft sans serif", "黑体": "simhei", "細明體": "mingliu",
        "lucida sans": "lucida sans unicode", "lucida grande": "lucida sans unicode",
        // (Dotum, Gulim and Batang left Windows; Excel prints them as Malgun Gothic.)
        "돋움": "dotum", "굴림": "gulim", "바탕": "batang", "궁서": "dotum", "gungsuh": "dotum",
    ]

    private static func face(_ family: String) -> Face { faces[faceKey(family)]! }

    /// The key of the table face a family is measured as: its own, or the
    /// one this app would draw it with. (Its bold is that key's "bold".)
    private static func faceKey(_ family: String) -> String {
        // Asked for every measured string, always with the same few family names; the answer follows from the name alone
        // while a sheet prints (the stand-in lookups below cost more than the measure itself).
        faceKeyLock.lock(); let known = faceKeyMemo[family]; faceKeyLock.unlock()
        if let known { return known }
        let key = _faceKey(family)
        faceKeyLock.lock(); faceKeyMemo[family] = key; faceKeyLock.unlock()
        return key
    }
    #if os(WASI)
    // One thread in the browser, and no NSLock in its Foundation.
    private struct _NoLock { func lock() {}; func unlock() {} }
    private static let faceKeyLock = _NoLock()
    #else
    private static let faceKeyLock = NSLock()
    #endif
    nonisolated(unsafe) private static var faceKeyMemo: [String: String] = [:]
    private static func _faceKey(_ family: String) -> String {
        let n = family.trimmingWhitespace().lowercased()
        if faces[aliases[n] ?? n] != nil { return aliases[n] ?? n }
        // A face nobody measured: an East Asian one by its name, the rest by
        // the clone this app would draw it with.
        if n.unicodeScalars.contains(where: { $0.value > 0x2E7F }) { return "ms pgothic" }
        let clone = OfficeFonts.sheetClone(family)
        if clone == OfficeFonts.substitute("Times New Roman") { return "times new roman" }
        if clone == OfficeFonts.substitute("Courier New") { return "courier new" }
        if clone == OfficeFonts.substitute("Cambria") { return "cambria" }
        if clone == OfficeFonts.substitute("Calibri") { return "calibri" }
        return "arial"
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
    /// A face's line as Windows stands it (ascent plus descent, in ems): what a shape's
    /// text lines step by in Excel's print (Calibri 11: 13.43 pt, where the painter's whole-point 10 + 3 gives 13).
    static func lineEm(family: String) -> Double? {
        guard let a = ascent(family: family), let d = descent(family: family) else { return nil }
        return a + d
    }
    /// Where a cell's text stands: the face's own ascent and descent. No
    /// face-specific entries: Lucida Sans Unicode stands about a tenth of
    /// an em higher in Excel's print than its Windows line gives, and no
    /// rule over the measured metric fields fits it with the other faces
    /// (OPEN, baseline lab round 2).
    static func printAscent(family: String) -> Double? { ascent(family: family) }
    static func printDescent(family: String) -> Double? { descent(family: family) }
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
        // (Dotum, Gulim and Batang: win ascent 879 and descent 145 of 1024, the font files on the print box.)
        "dotum": 0.8584, "gulim": 0.8584, "batang": 0.8584,
    ]

    /// A face's descent, in its size, as `ascent` is its ascent: what
    /// Windows takes for its line under the baseline (`usWinDescent`, or
    /// the hhea descent where `ascent` is the hhea ascent). Nil for a face
    /// not known here.
    static func descent(family: String) -> Double? {
        let n = family.trimmingWhitespace().lowercased()
        return descents[aliases[n] ?? n]
    }
    private static let descents: [String: Double] = [
        "calibri": 0.2686, "arial": 0.2119, "verdana": 0.21, "times new roman": 0.2163, "courier new": 0.3003,
        "tahoma": 0.2065, "cambria": 0.2222, "microsoft sans serif": 0.21, "segoe ui": 0.251, "century gothic": 0.2202,
        "ms gothic": 0.1406, "ms pgothic": 0.1406, "simsun": 0.1406,
        "simhei": 0.1406, "microsoft yahei": 0.2617, "malgun gothic": 0.2417, "mingliu": 0.1992, "pmingliu": 0.1992,
        "yu gothic": 0.3022, "lucida sans unicode": 0.4399, "lucida sans typewriter": 0.2109, "lucida console": 0.2109,
        "garamond": 0.2632, "book antiqua": 0.2822, "palatino linotype": 0.2993, "bookman old style": 0.2319,
        "century": 0.2158, "georgia": 0.2192, "trebuchet ms": 0.2222, "consolas": 0.251, "comic sans ms": 0.2915,
        "arial narrow": 0.2119, "arial black": 0.3096, "franklin gothic medium": 0.2173, "gill sans mt": 0.2305,
        "candara": 0.2686, "corbel": 0.2686, "constantia": 0.2686,
        "dotum": 0.1416, "gulim": 0.1416, "batang": 0.1416,
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
    /// A theme-font Normal face Excel's print box fits the unsized rows in by its stored default height (labs korow3: 맑은 고딕's 17 prints
    /// 17.25 and 15 prints 15.25). The other East Asian faces measured (宋体, ＭＳ Ｐゴシック, 新細明體, 游ゴシック) print at Calibri's fit whatever
    /// default they store: that box does not have them.
    /// A face the print box has installed (even as a cloud font) that the tables have no measure of: its rows print at the height the book stored.
    static func isInstalledUnmeasured(_ family: String) -> Bool {
        let n = family.trimmingWhitespace().lowercased()
        return faces[aliases[n] ?? n] == nil && SheetInstalledFonts.names.contains(n)
    }
    static func fitsRowsInOwnFace(_ name: String) -> Bool { name == "맑은 고딕" || name.lowercased() == "malgun gothic" }

    static func of(family: String, size: Double, bold: Bool = false, baseColWidth: Double = 8, hinted: Bool = false, otherBook: Bool = false) -> SheetPrintMetrics {
        let f = (bold ? faces[faceKey(family) + " bold"] : nil) ?? face(family)
        // (A printer's line between the sizes measured is the next whole
        // dot up: 49609's Microsoft Sans Serif 8.25 is 87 of 84 and 93,
        // its set 15 pt rows 124 dots in Excel's print where 86 made 122.)
        let between = size > sizes[0] && size < sizes[sizes.count - 1]
        let digit = at(f.digit, size).rounded(), row = at(f.row, size).rounded(between ? .up : .toNearestOrAwayFromZero)
        let screenRow = max(1, f.offTable[size] ?? (hinted ? f.hinted[size] : nil) ?? (otherBook ? f.plainBook[size] : nil) ?? at(f.screenRow, size).rounded())
        // The default column, as that Excel's screen made it: the digit there
        // in whole pixels, its padding, and the sum up to a multiple of 8.
        let screenDigit = max(1, at(f.screenDigit, size).rounded())
        let pad = 2 * (screenDigit / 4).rounded(.up) + 1
        let px = ((baseColWidth * screenDigit + pad) / 8).rounded(.up) * 8
        return SheetPrintMetrics(digit: digit * 72 / 600, defaultChars: px / screenDigit,
                                 defaultRow: row * 72 / 600, rowScale: (row / 600) / (screenRow / 192), setRowScale: f.gridSet.contains(size) ? 8.0 * 72 / 600 : (row / 600) / ((f.setScreenRow[size] ?? screenRow) / 192), setOwn: f.gridSet.contains(size) || f.setScreenRow[size] != nil, setOwnAt100: f.gridSet.contains(size), screenDigit: screenDigit,
                                 screenRow: screenRow)
    }
}
