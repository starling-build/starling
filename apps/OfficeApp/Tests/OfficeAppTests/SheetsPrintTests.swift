// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsPrintTests: XCTestCase {
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
        XCTAssertEqual(s, 511.2 / 768 * 0.999, accuracy: 1e-9)
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
        XCTAssertEqual(s.pageSize.width, 841.89, accuracy: 0.01)    // A4 on its side
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
        XCTAssertEqual(SheetPrintLayout.usedArea(ws, book: book), CellRange("C3:E9"))
        ws.drawings = [SheetDrawing(name: "p", anchor: .twoCell(from: SheetMarker(col: 1, colOff: 0, row: 1, rowOff: 0),
                                                                 to: SheetMarker(col: 7, colOff: 0, row: 20, rowOff: 0)),
                                    kind: .picture(path: "x", data: Data()))]
        XCTAssertEqual(SheetPrintLayout.usedArea(ws, book: book), CellRange("B2:H21"))
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
        // Font and size carry across sections until changed; &"-,Regular" ends the bold.
        let s = HeaderFooterText.parse("&L&\"Arial,Bold\"&14Report&\"-,Regular\"&C&BPage &P of &N&B&R&D && &A")
        XCTAssertEqual(s.left, [.init(piece: .text("Report"), style: .init(bold: true, size: 14, family: "Arial"))])
        XCTAssertEqual(s.center.map(\.piece), [.text("Page "), .page, .text(" of "), .pages])
        XCTAssertTrue(s.center.allSatisfy { $0.style.bold && $0.style.family == "Arial" && $0.style.size == 14 })
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
