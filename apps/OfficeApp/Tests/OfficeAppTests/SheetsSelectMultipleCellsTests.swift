// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A finger has no Shift: Select Multiple makes a tap on a cell extend the selection from its anchor, as Shift-click does.

import XCTest
@testable import OfficeApp

final class SheetsSelectMultipleCellsTests: XCTestCase {
    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "S")]))
        return c
    }

    func testExtendsOnlyWithShiftOrSelectMultiple() {
        let c = book()
        XCTAssertFalse(c.extendsSelection(shift: false))
        XCTAssertTrue(c.extendsSelection(shift: true))
        c.selectMultiple = true
        XCTAssertTrue(c.extendsSelection(shift: false), "a finger: the toggle stands in for Shift")
    }

    func testATapWithSelectMultipleOnExtendsTheRange() {
        let c = book()
        c.select(CellAddress(row: 1, col: 1))
        c.selectMultiple = true
        c.select(CellAddress(row: 3, col: 2), extend: c.extendsSelection(shift: false))
        XCTAssertEqual(c.selection, CellRange(top: 1, left: 1, bottom: 3, right: 2))
        c.selectMultiple = false
        c.select(CellAddress(row: 5, col: 5), extend: c.extendsSelection(shift: false))
        XCTAssertEqual(c.selection, CellRange(top: 5, left: 5, bottom: 5, right: 5), "off: a tap just selects")
    }
}
