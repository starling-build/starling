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
