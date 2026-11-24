// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-PR-1: the page setup edits, saved and read back.

import XCTest
@testable import OfficeApp

final class SheetsPageSetupTests: XCTestCase {
    func testAttributesChangeAndTheRestStays() {
        let e = PageSetupEdit.setAttributes("<pageSetup paperSize=\"9\" scale=\"80\" r:id=\"rId1\" dpi=\"600\"/>", name: "pageSetup",
                                            [("orientation", "landscape"), ("scale", nil), ("paperSize", "1")])
        XCTAssertEqual(e, "<pageSetup paperSize=\"1\" r:id=\"rId1\" dpi=\"600\" orientation=\"landscape\"/>")
        XCTAssertEqual(PageSetupEdit.setAttributes(nil, name: "printOptions", [("gridLines", "1")]), "<printOptions gridLines=\"1\"/>")
    }

    func testPageSetupSurvivesSaveAndNeighboursStay() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: url)))
        let before = c.sheet.keptElements.map(\.name)
        c.setPageSetup(PageSetupChange(landscape: true, paperSize: 9, left: 1, right: 0.5, top: 1.25, bottom: 0.5,
                                       fitWide: 1, fitTall: 0, gridlines: true, headings: true, centerHorizontally: true))
        let back = try Xlsx.read(try Xlsx.write(c.book))
        let s = SheetPrintSetup.read(back.sheets[0])
        XCTAssertTrue(s.landscape)
        XCTAssertEqual(s.paper.width, 595.2, accuracy: 0.5)
        XCTAssertEqual(s.left, 72, accuracy: 0.01)
        XCTAssertEqual(s.top, 90, accuracy: 0.01)
        XCTAssertEqual(s.fitWidth, 1)
        XCTAssertEqual(s.fitHeight, 0)
        XCTAssertTrue(s.gridlines && s.headings && s.centerHorizontally)
        XCTAssertFalse(s.centerVertically)
        // Nothing else the sheet kept went missing.
        let after = Set(back.sheets[0].keptElements.map(\.name))
        for n in before { XCTAssertTrue(after.contains(n), n) }
        // Then back to a plain scale, and the whole edit is one undo.
        c.setPageSetup(PageSetupChange(scale: 70, gridlines: false))
        let again = SheetPrintSetup.read(try Xlsx.read(try Xlsx.write(c.book)).sheets[0])
        XCTAssertEqual(again.scale, 70)
        XCTAssertNil(again.fitWidth)
        XCTAssertFalse(again.gridlines)
        c.undo()
        XCTAssertEqual(SheetPrintSetup.read(c.sheet).fitWidth, 1)
        c.undo()
        XCTAssertEqual(c.sheet.keptElements.map(\.name), before)
    }
}

final class SheetsPrintNamesTests: XCTestCase {
    func testPrintAreaAndTitlesSurviveSaveAndUndo() throws {
        let c = WorkbookController()
        c.setInput("a", at: CellAddress(row: 0, col: 0))
        c.setPrintArea(CellRange(top: 0, left: 0, bottom: 19, right: 3))
        c.setPrintTitles(rows: 0...1, cols: 0...0)
        let back = try Xlsx.read(try Xlsx.write(c.book))
        let n = SheetPrintLayout.printNames(back, sheet: 0)
        XCTAssertEqual(n.areas, [CellRange(top: 0, left: 0, bottom: 19, right: 3)])
        XCTAssertEqual(n.titleRows, 0...1)
        XCTAssertEqual(n.titleCols, 0...0)
        c.setPrintArea(nil)
        XCTAssertTrue(SheetPrintLayout.printNames(c.book, sheet: 0).areas.isEmpty)
        c.undo()
        XCTAssertEqual(SheetPrintLayout.printNames(c.book, sheet: 0).areas.count, 1)
    }

    func testTheFormReadsAndRefusesRanges() {
        var f = PageSetupForm(SheetPrintSetup(), paper: 9)
        f.area = "A1:D20"; f.titleRows = "1:2"; f.titleCols = "A:B"
        let (n, e) = f.names()
        XCTAssertNil(e)
        XCTAssertEqual(n?.area, CellRange(top: 0, left: 0, bottom: 19, right: 3))
        XCTAssertEqual(n?.rows, 0...1)
        XCTAssertEqual(n?.cols, 0...1)
        f.titleRows = "A:B"
        XCTAssertNotNil(f.names().1)
    }
}

final class SheetsPageBreakTests: XCTestCase {
    func testBreaksSurviveSaveAndPrintLayoutSeesThem() throws {
        let c = WorkbookController()
        c.setInput("a", at: CellAddress(row: 0, col: 0))
        c.insertPageBreak(row: 5, col: 2)
        c.insertPageBreak(row: 5, col: 0)   // no duplicate
        let back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertEqual(back.sheets[0].breakIds("rowBreaks"), [5])
        XCTAssertEqual(back.sheets[0].breakIds("colBreaks"), [2])
        XCTAssertEqual(SheetPrintSetup.read(back.sheets[0]).rowBreaks, [5])
        c.removePageBreak(row: 5, col: 2)
        XCTAssertTrue(c.sheet.breakIds("rowBreaks").isEmpty)
        c.undo()
        XCTAssertEqual(c.sheet.breakIds("rowBreaks"), [5])
        c.resetPageBreaks()
        XCTAssertTrue(c.sheet.breakIds("colBreaks").isEmpty)
    }
}
