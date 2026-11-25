// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-VW-1: View options per sheet: zoom, headings, show formulas, right-to-left. Saved and read back.

import XCTest
@testable import OfficeApp

final class SheetsViewOptionsTests: XCTestCase {
    func testZoomIsPerSheetAndClamped() {
        let c = WorkbookController()
        c.addSheet()
        c.activeSheet = 0
        c.setZoom(percent: 150)
        c.activeSheet = 1
        XCTAssertEqual(c.sheet.zoomPercent, 100)
        c.activeSheet = 0
        XCTAssertEqual(c.sheet.zoomPercent, 150)
        c.setZoom(percent: 5000)
        XCTAssertEqual(c.sheet.zoomPercent, 400)
    }

    func testTogglesAreOneUndoStepEach() {
        let c = WorkbookController()
        c.toggleHeadings(); c.toggleShowFormulas(); c.toggleRightToLeft()
        XCTAssertFalse(c.sheet.showHeadings)
        XCTAssertTrue(c.sheet.showFormulas)
        XCTAssertTrue(c.sheet.rightToLeft)
        c.undo()
        XCTAssertFalse(c.sheet.rightToLeft)
        XCTAssertTrue(c.sheet.showFormulas)
        c.undo(); c.undo()
        XCTAssertTrue(c.sheet.showHeadings)
        XCTAssertFalse(c.sheet.showFormulas)
    }

    func testViewOptionsSaveAndReadBack() throws {
        let c = WorkbookController()
        c.setZoom(percent: 130)
        c.toggleHeadings(); c.toggleShowFormulas(); c.toggleRightToLeft()
        let back = try Xlsx.read(try Xlsx.write(c.book))
        let s = back.sheets[0]
        XCTAssertEqual(s.zoomPercent, 130)
        XCTAssertFalse(s.showHeadings)
        XCTAssertTrue(s.showFormulas)
        XCTAssertTrue(s.rightToLeft)
        // A sheet left alone writes none of them.
        let plain = try Xlsx.write(WorkbookController().book)
        let entries = try Xlsx.read(plain).sheets[0]
        XCTAssertEqual(entries.zoomPercent, 100)
        XCTAssertTrue(entries.showHeadings)
    }

    /// Writes the file for the Excel check (only when XCHECK_DIR is set): zoom 130, no headings, formulas shown, right-to-left.
    func testWriteExcelCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let c = WorkbookController()
        c.setInputs([(CellAddress(row: 0, col: 0), "2"), (CellAddress(row: 0, col: 1), "=A1*3")])
        c.setZoom(percent: 130)
        c.toggleHeadings(); c.toggleShowFormulas(); c.toggleRightToLeft()
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/viewoptions.xlsx"))
    }
}
