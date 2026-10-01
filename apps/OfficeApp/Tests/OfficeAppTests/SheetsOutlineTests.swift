// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsOutlineTests: XCTestCase {
    /// Rows 2–7 grouped (level 1), 3–4 within them (level 2); summaries below.
    private func outlined() -> WorkbookController {
        let c = WorkbookController()
        c.select(range: CellRange("A2:A7")!)
        c.groupRows(true)
        c.select(range: CellRange("A3:A4")!)
        c.groupRows(true)
        return c
    }

    func testGroupsAndLevels() {
        let c = outlined()
        let groups = c.sheet.rowGroups()
        XCTAssertEqual(groups, [RowGroup(level: 1, rows: 1 ... 6, summary: 7), RowGroup(level: 2, rows: 2 ... 3, summary: 4)])
        XCTAssertEqual(c.sheet.formatPrAttrs["outlineLevelRow"], "2")
        // Close the inner group, then the outer; open the outer: the inner stays closed.
        c.toggleGroup(groups[1])
        XCTAssertEqual(c.sheet.hiddenRows, [2, 3])
        XCTAssertEqual(c.sheet.rowAttrs[4]?["collapsed"], "1")
        c.toggleGroup(groups[0])
        XCTAssertEqual(c.sheet.hiddenRows, Set(1 ... 6))
        c.toggleGroup(groups[0])
        XCTAssertEqual(c.sheet.hiddenRows, [2, 3])
        // Level buttons: 1 shows only the top, 3 everything.
        c.showOutlineLevel(1)
        XCTAssertEqual(c.sheet.hiddenRows, Set(1 ... 6))
        c.showOutlineLevel(2)
        XCTAssertEqual(c.sheet.hiddenRows, [2, 3])
        c.showOutlineLevel(3)
        XCTAssertTrue(c.sheet.hiddenRows.isEmpty)
        // Ungroup the inner rows.
        c.select(range: CellRange("A3:A4")!)
        c.groupRows(false)
        XCTAssertEqual(c.sheet.rowGroups().count, 1)
        XCTAssertEqual(c.sheet.formatPrAttrs["outlineLevelRow"], "1")
        c.undo()
        XCTAssertEqual(c.sheet.rowGroups().count, 2)
    }

    func testCollapsedGroupsRoundTripWithTheirHeights() throws {
        let c = outlined()
        c.sheet.rowHeights[2] = 30
        c.toggleGroup(c.sheet.rowGroups()[0])
        let back = try Xlsx.read(try Xlsx.write(c.book))
        let ws = back.sheets[0]
        XCTAssertEqual(ws.hiddenRows, Set(1 ... 6))
        XCTAssertEqual(ws.rowHeights[2], 30)                 // kept for when it opens
        XCTAssertEqual(ws.rowAttrs[7]?["collapsed"], "1")
        XCTAssertEqual(ws.rowGroups().count, 2)
    }
}
