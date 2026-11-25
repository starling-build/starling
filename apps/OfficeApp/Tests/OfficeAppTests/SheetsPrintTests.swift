// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsPrintTests: XCTestCase {
    /// ICU's data and the bundled faces, before any text is laid out: a run filtered to this class (as the whole suite's first
    /// class does for the rest) has no earlier test to load them, and a wrapped cell then measures one line.
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    func testPagesGoDownThenOver() {
        // 12 columns of 64pt (768pt) and 60 rows of 15pt (900pt) on Letter
        // with Normal margins: 511.2pt by 684pt a page.
        let area = CellRange(top: 0, left: 0, bottom: 59, right: 11)
        let (pages, s) = SheetPrintLayout.pages(area: area, setup: SheetPrintSetup(), width: { _ in 64 }, height: { _ in 15 })
        XCTAssertEqual(s, 1)
        XCTAssertEqual(pages.count, 4)
        XCTAssertEqual(pages[0].cols, Array(0 ... 6))     // 7 × 64 = 448 fits, 8 would be 512
        XCTAssertEqual(pages[0].rows, Array(0 ... 44))    // 45 × 15 = 675
        XCTAssertEqual(pages[1].cols, Array(0 ... 6))     // down first
        XCTAssertEqual(pages[1].rows, Array(45 ... 59))
        XCTAssertEqual(pages[2].cols, Array(7 ... 11))
    }

    /// A manual break's page of hidden rows only is a blank page ahead of the visible ones
    /// (ja-5563bee92c: five of them before the first month in Excel's print).
    func testHiddenBreakSegmentsPrintBlank() {
        let area = CellRange(top: 0, left: 0, bottom: 39, right: 2)
        var setup = SheetPrintSetup()
        setup.fitWidth = 1
        setup.fitHeight = 0
        setup.rowBreaks = [10, 20, 30]
        let (pages, _) = SheetPrintLayout.pages(area: area, setup: setup, width: { _ in 64 },
                                                height: { $0 < 20 ? 0 : 15 })
        XCTAssertEqual(pages.map(\.rows.count), [0, 0, 10, 10])
    }

    /// Excel's print of a fit-to-one-page sheet with two title rows and 200 more
    /// (fit-titles lab, 2026-11-23): 15 pt rows are 3.24 pt apart (21%), not 3.36 (22%).
    func testFitHeightCountsTitleRowsTwice() {
        let area = CellRange(top: 0, left: 0, bottom: 201, right: 2)
        var setup = SheetPrintSetup()
        setup.fitWidth = 1
        setup.fitHeight = 1
        let (pages, s) = SheetPrintLayout.pages(area: area, setup: setup, titleHeight: 30, titleRowsEnd: 1,
                                                width: { _ in 64 }, height: { _ in 15 })
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(s, 0.21, accuracy: 0.0001)  // 22% before: the first page held the titles once
    }

    func testHiddenRowsAndFitToWidth() {
        let area = CellRange(top: 0, left: 0, bottom: 9, right: 11)
        let hidden: Set<Int> = [3, 4]
        var setup = SheetPrintSetup()
        setup.fitWidth = 1
        setup.fitHeight = 0
        let (pages, s) = SheetPrintLayout.pages(area: area, setup: setup, width: { _ in 64 },
                                                height: { hidden.contains($0) ? 0 : 15 })
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].cols.count, 12)
        XCTAssertFalse(pages[0].rows.contains(3))
        // 511.2 / 768 is 66.56%: Excel's fit is the whole percent under it.
        XCTAssertEqual(s, 0.66, accuracy: 1e-9)
    }

    func testReadsTheFilesPageSetup() {
        let ws = Worksheet(name: "S")
        ws.keptElements = [
            ("sheetPr", "<sheetPr><pageSetUpPr fitToPage=\"1\"/></sheetPr>"),
            ("printOptions", "<printOptions gridLines=\"1\" horizontalCentered=\"1\"/>"),
            ("pageMargins", "<pageMargins left=\"0.25\" right=\"0.25\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/>"),
            ("pageSetup", "<pageSetup paperSize=\"9\" orientation=\"landscape\" fitToHeight=\"0\"/>"),
        ]
        let s = SheetPrintSetup.read(ws)
        XCTAssertTrue(s.landscape)
        XCTAssertEqual(s.pageSize.width, 841.92, accuracy: 0.01)    // A4 on its side: 7016 dots of 600 dpi
        XCTAssertEqual(s.left, 18, accuracy: 1e-9)
        XCTAssertEqual(s.fitWidth, 1)
        XCTAssertEqual(s.fitHeight, 0)
        XCTAssertTrue(s.gridlines)
        XCTAssertTrue(s.centerHorizontally)
    }

    func testUsedAreaTakesFormatsAndDrawings() {
        let book = Workbook()
        let ws = book.sheets[0]
        ws.cells[CellAddress("C3")!] = Cell(input: "x", value: .text("x"))
        var st = CellStyle(); st.fill = 0xFFFF00
        ws.cells[CellAddress("E9")!] = Cell(input: "", style: book.styleIndex(st))
        // From A1, as Excel prints, to the last cell with something to show.
        XCTAssertEqual(SheetPrintLayout.usedArea(ws, book: book), CellRange("A1:E9"))
        ws.drawings = [SheetDrawing(name: "p", anchor: .twoCell(from: SheetMarker(col: 1, colOff: 0, row: 1, rowOff: 0),
                                                                 to: SheetMarker(col: 7, colOff: 0, row: 20, rowOff: 0)),
                                    kind: .picture(path: "x", data: Data()))]
        // The cells the picture covers, the one its far corner stands on too.
        XCTAssertEqual(SheetPrintLayout.usedArea(ws, book: book), CellRange("A1:H21"))
    }
}

extension SheetsPrintTests {
    func testPrintAreaAndTitlesFromTheFile() {
        let book = Workbook(sheets: [Worksheet(name: "Data")])
        book.fileNames = [
            DefinedName(name: "_xlnm.Print_Area", localSheet: 0, attrs: [:], text: "Data!$B$2:$F$90,Data!$H$1:$H$4"),
            DefinedName(name: "_xlnm.Print_Titles", localSheet: 0, attrs: [:], text: "Data!$A:$A,Data!$1:$2"),
        ]
        let n = SheetPrintLayout.printNames(book, sheet: 0)
        XCTAssertEqual(n.areas, [CellRange("B2:F90")!, CellRange("H1:H4")!])
        XCTAssertEqual(n.titleRows, 0 ... 1)
        XCTAssertEqual(n.titleCols, 0 ... 0)
        // Titles take their room on every page: 684 - 30 leaves 43 rows of 15.
        let (pages, _) = SheetPrintLayout.pages(area: n.areas[0], setup: SheetPrintSetup(), titleWidth: 64, titleHeight: 30,
                                                width: { _ in 64 }, height: { _ in 15 })
        XCTAssertEqual(pages.first?.rows.count, 43)
    }
}

extension SheetsPrintTests {
    func testHeaderFooterCodes() {
        // Each section starts in the default font (a lab, Excel 16, 2026-10-16:
        // "&L&\"Courier New,Bold\"&16AAA&CBBB&RCCC" prints BBB and CCC in Calibri
        // 11); &"-,Regular" ends the bold.
        let s = HeaderFooterText.parse("&L&\"Arial,Bold\"&14Report&\"-,Regular\"&C&BPage &P of &N&B&R&D && &A")
        XCTAssertEqual(s.left, [.init(piece: .text("Report"), style: .init(bold: true, size: 14, family: "Arial"))])
        XCTAssertEqual(s.center.map(\.piece), [.text("Page "), .page, .text(" of "), .pages])
        XCTAssertTrue(s.center.allSatisfy { $0.style.bold && $0.style.family == nil && $0.style.size == nil })
        XCTAssertEqual(s.right.map(\.piece), [.date, .text(" & "), .sheet])
        // No section code: centred, as Excel shows it.
        XCTAssertEqual(HeaderFooterText.parse("Plain").center, [.init(piece: .text("Plain"), style: .init())])
        XCTAssertTrue(HeaderFooterText.parse("Plain").left.isEmpty)
        // A colour, toggles that close, a picture that is not drawn.
        let t = HeaderFooterText.parse("&KFF0000red&K000000&Iit&I&Gplain")
        XCTAssertEqual(t.center.map(\.piece), [.text("red"), .text("it"), .text("plain")])
        XCTAssertEqual(t.center[0].style.color, 0xFFFF0000)
        XCTAssertTrue(t.center[1].style.italic)
        XCTAssertFalse(t.center[2].style.italic)
        let runs = HeaderFooterText.runs(s.center, fields: .init(page: 3, pages: 7))
        XCTAssertEqual(runs.map(\.text), ["Page 3 of 7"])
    }

    func testHeaderFooterVariantsAndBreaksFromTheFile() {
        let ws = Worksheet(name: "S")
        ws.keptElements = [
            ("pageMargins", "<pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.5\" footer=\"0.3\"/>"),
            ("pageSetup", "<pageSetup pageOrder=\"overThenDown\" firstPageNumber=\"5\" useFirstPageNumber=\"1\"/>"),
            ("headerFooter", "<headerFooter differentOddEven=\"1\" differentFirst=\"1\"><oddHeader>&amp;Codd</oddHeader>"
                + "<evenHeader>&amp;Ceven</evenHeader><firstHeader>&amp;Cfirst</firstHeader><oddFooter>&amp;P</oddFooter></headerFooter>"),
            ("rowBreaks", "<rowBreaks count=\"1\" manualBreakCount=\"1\"><brk id=\"10\" max=\"16383\" man=\"1\"/></rowBreaks>"),
            ("colBreaks", "<colBreaks count=\"1\" manualBreakCount=\"1\"><brk id=\"3\" max=\"1048575\" man=\"1\"/></colBreaks>"),
        ]
        let s = SheetPrintSetup.read(ws)
        XCTAssertEqual(s.headerMargin, 36, accuracy: 1e-9)
        XCTAssertEqual(s.firstPageNumber, 5)
        XCTAssertTrue(s.overThenDown)
        XCTAssertEqual(s.headerFooter.header(page: 1), "&Cfirst")
        XCTAssertEqual(s.headerFooter.header(page: 2), "&Ceven")
        XCTAssertEqual(s.headerFooter.header(page: 3), "&Codd")
        XCTAssertEqual(s.headerFooter.footer(page: 2), "")   // no even footer given
        XCTAssertEqual(s.rowBreaks, [10])
        XCTAssertEqual(s.colBreaks, [3])
        // Breaks start pages whatever room is left; over then down.
        let area = CellRange(top: 0, left: 0, bottom: 19, right: 5)
        let (pages, _) = SheetPrintLayout.pages(area: area, setup: s, width: { _ in 64 }, height: { _ in 15 })
        XCTAssertEqual(pages.count, 4)
        XCTAssertEqual(pages[0].cols, [0, 1, 2]); XCTAssertEqual(pages[0].rows, Array(0 ... 9))
        XCTAssertEqual(pages[1].cols, [3, 4, 5]); XCTAssertEqual(pages[1].rows, Array(0 ... 9))   // over first
        XCTAssertEqual(pages[2].rows, Array(10 ... 19))
    }
}

extension SheetsPrintTests {
    func testSheetLayoutDumpIsDiscrete() {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "A heading that is far too long for one default column"),
                     (CellAddress("B1")!, "123456789012345"),
                     (CellAddress("C1")!, "wrap me onto several lines please"),
                     (CellAddress("A2")!, "short")])
        c.setStyle({ $0.wrap = true }, range: CellRange("C1")!)
        let dump = SheetLayoutDump.text(c)
        let lines = dump.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "sheet Sheet1 rows=2 cols=3")
        XCTAssertTrue(lines.contains("col A 48"), dump)
        XCTAssertTrue(lines.contains("row 1 15"), dump)
        XCTAssertTrue(lines.contains { $0.hasPrefix("A1\tleft\tA heading") && $0.hasSuffix("\tover") }, dump)
        XCTAssertTrue(lines.contains("B1\tright\t####"), dump)          // a number too wide for its cell
        XCTAssertTrue(lines.contains { $0.hasPrefix("C1\tleft\twrap me") && $0.contains("\tlines=") && !$0.hasSuffix("lines=1") }, dump)
        XCTAssertTrue(lines.contains("A2\tleft\tshort"), dump)
        XCTAssertFalse(dump.contains("w="))
    }

    /// The GDI advance table must load: its first lookup builds a dictionary literal, which traps on a repeated
    /// face key (Arial Narrow was listed twice, 12 zh books crashed under --sheet-pdf). Every face has the same columns.
    func testGdiAdvanceTableLoadsAndCoversEveryFaceAtOneWidth() {
        XCTAssertNotNil(GdiAdvances.advance("arial narrow", bold: false, em: 30, 0x41))
        XCTAssertNotNil(GdiAdvances.advance("arial narrow", bold: true, em: 30, 0x41))
        _ = GdiAdvances.advance("arial", bold: false, em: 30, 0x4E2D)
        for face in GdiAdvances.faces {
            XCTAssertNotNil(GdiAdvances.advance(face, bold: false, em: 30, 0x20), face)
        }
    }

    /// Excel's set rows of faces the print box lacks (planner spec, from two Excel labs): 돋움 11 prints 8 dots a
    /// point (6 dots a screen pixel); 新細明體 12 prints at the table's 130/43 dots per 192-dpi pixel. A set height is held
    /// in quarter screen pixels; a scaled print takes the 100 % dot count times the scale, rounded half up.
    func testSetRowsOfMissingCjkFacesPrintOnTheirOwnGrid() {
        let dotum = SheetPrintMetrics.of(family: "돋움", size: 11)
        XCTAssertEqual(dotum.setRowScale, 0.96, accuracy: 1e-9)
        let mm = SheetPrintMetrics.of(family: "新細明體", size: 12)
        XCTAssertEqual(mm.setRowScale, (130.0 / 600) / (43.0 / 192), accuracy: 1e-9)
        XCTAssertTrue(mm.setOwn)
        let malgun = SheetPrintMetrics.of(family: "맑은 고딕", size: 11)
        XCTAssertEqual(malgun.setRowScale, malgun.rowScale, accuracy: 1e-9)
        XCTAssertFalse(malgun.setOwn)
        func dots(_ pt: Double, _ pct: Double = 100, _ m: SheetPrintMetrics = mm) -> Int {
            let h = SheetPrintMetrics.setRowOwn(pt, scale: m.setRowScale, printPct: pct)
            return Int((h * pct / 100 * 600 / 72 + 1e-6).rounded(.down))
        }
        XCTAssertEqual(dots(50.1), 403)
        XCTAssertEqual(dots(50.1, 58), 234)
        XCTAssertEqual(dots(50.1, 50), 202)
        XCTAssertEqual(dots(62.625), 505)
        XCTAssertEqual(dots(62.25), 501)
        XCTAssertEqual(dots(30.375, 58), 142)
        XCTAssertEqual(dots(73.5, 100, dotum), 588)
        XCTAssertEqual(dots(73.5, 58, dotum), 341)
    }

    /// ko-5907e2d9ba, a 100 % print of a 돋움 11 book: Excel prints its 45 pt set rows 43.2 pt (360 dots, 8 a point), not at the fitted row's .987.
    func testDotum11SetRowsStandOnTheirOwnGridAt100() {
        let dotum = SheetPrintMetrics.of(family: "돋움", size: 11)
        XCTAssertTrue(dotum.setOwnAt100)
        let h = SheetPrintMetrics.setRowOwn(45, scale: dotum.setRowScale, printPct: 100)
        XCTAssertEqual(h, 43.2, accuracy: 0.001)
        // 新細明體 12's set rows follow the fitted row at 100 % (its own grid only below)
        XCTAssertFalse(SheetPrintMetrics.of(family: "新細明體", size: 12).setOwnAt100)
        XCTAssertFalse(SheetPrintMetrics.of(family: "Calibri", size: 11).setOwnAt100)
    }
}

final class MeiryoUiBigRowsTests: XCTestCase {
    /// Excel's print of ja-d9ac78f0cb: rows fitted to 18 pt Meiryo UI cells in an 11 pt book are 25.6 pt (65 screen px), not 27.1.
    func testMeiryoUiLargeSizesFollowThePointStep() {
        let d = SheetPrintMetrics.of(family: "Meiryo UI", size: 11)
        let big = SheetPrintMetrics.of(family: "Meiryo UI", size: 18)
        XCTAssertEqual(d.fittedRow(big), 65 * 72 / 192 * d.rowScale, accuracy: 0.01)
        XCTAssertEqual(d.fittedRow(big), 25.55, accuracy: 0.05)
        XCTAssertEqual(d.fittedRow(SheetPrintMetrics.of(family: "Meiryo UI", size: 16)), 59 * 72 / 192 * d.rowScale, accuracy: 0.01)
        // lab meiryoui-rows2: Excel's auto rows at 15/16/18/20/24 pt, regular and bold, print 53/59/65/71/86 px
        for (size, px) in [(15.0, 53.0), (16, 59), (18, 65), (20, 71), (24, 86)] {
            for bold in [false, true] {
                XCTAssertEqual(d.fittedRow(SheetPrintMetrics.of(family: "Meiryo UI", size: size, bold: bold)), px * 72 / 192 * d.rowScale, accuracy: 0.01, "\(size) bold \(bold)")
            }
        }
    }
}
