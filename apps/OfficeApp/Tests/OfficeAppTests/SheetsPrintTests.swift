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
