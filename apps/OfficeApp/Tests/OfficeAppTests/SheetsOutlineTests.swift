// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsOutlineTests: XCTestCase {
    /// Rows 2–7 grouped (level 1), 3–4 within them (level 2); summaries below.
    private func outlined() -> WorkbookController {
        let c = WorkbookController()
        c.select(range: CellRange("A2:A7")!)
        c.group(true)
        c.select(range: CellRange("A3:A4")!)
        c.group(true)
        return c
    }

    func testGroupsAndLevels() {
        let c = outlined()
        let groups = c.sheet.rowGroups()
        XCTAssertEqual(groups, [OutlineGroup(level: 1, span: 1 ... 6, summary: 7), OutlineGroup(level: 2, span: 2 ... 3, summary: 4)])
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
        c.group(false)
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

    func testColumnGroupsSplitTheFilesRunsAndRoundTrip() throws {
        let c = WorkbookController()
        // A styled run over B:F, as a file would have it.
        c.sheet.colAttrRuns = [(1, 5, ["style": "0"])]
        c.select(range: CellRange(top: 0, left: 2, bottom: CellAddress.maxRows - 1, right: 3))   // C:D
        c.group(true)
        XCTAssertEqual(c.sheet.outlineGroups(.cols), [OutlineGroup(level: 1, span: 2 ... 3, summary: 4)])
        XCTAssertEqual(c.sheet.formatPrAttrs["outlineLevelCol"], "1")
        XCTAssertEqual((1 ... 5).map { c.sheet.outlineAttr(.cols, $0, "style") }, Array(repeating: "0", count: 5))
        c.toggleGroup(c.sheet.outlineGroups(.cols)[0], .cols)
        XCTAssertEqual(c.sheet.hiddenCols, [2, 3])
        XCTAssertEqual(c.sheet.outlineAttr(.cols, 4, "collapsed"), "1")
        let back = try Xlsx.read(try Xlsx.write(c.book)).sheets[0]
        XCTAssertEqual(back.hiddenCols, [2, 3])
        XCTAssertEqual(back.outlineGroups(.cols), [OutlineGroup(level: 1, span: 2 ... 3, summary: 4)])
        XCTAssertEqual(back.outlineAttr(.cols, 4, "collapsed"), "1")
        XCTAssertEqual(back.outlineAttr(.cols, 5, "style"), "0")
        // Level 2 opens it again.
        c.showOutlineLevel(2, .cols)
        XCTAssertTrue(c.sheet.hiddenCols.isEmpty)
        XCTAssertNil(c.sheet.outlineAttr(.cols, 4, "collapsed"))
    }

    func testHideAndUnhideKeepSizes() throws {
        let c = WorkbookController()
        c.sheet.colWidths[1] = 120
        c.sheet.rowHeights[4] = 33
        c.select(range: CellRange(top: 0, left: 1, bottom: CellAddress.maxRows - 1, right: 1))
        c.setHidden(.cols, true)
        c.select(range: CellRange(top: 4, left: 0, bottom: 5, right: CellAddress.maxCols - 1))
        c.setHidden(.rows, true)
        XCTAssertTrue(c.sheet.isColHidden(1))
        XCTAssertEqual(c.sheet.hiddenRows, [4, 5])
        let back = try Xlsx.read(try Xlsx.write(c.book)).sheets[0]
        XCTAssertEqual(back.hiddenCols, [1])
        XCTAssertEqual(back.colWidths[1] ?? 0, 120, accuracy: 1)
        XCTAssertEqual(back.hiddenRows, [4, 5])
        XCTAssertEqual(back.rowHeights[4], 33)
        // Unhide by selecting across them: A:C, rows 4–7.
        c.select(range: CellRange(top: 0, left: 0, bottom: CellAddress.maxRows - 1, right: 2))
        c.setHidden(.cols, false)
        c.select(range: CellRange(top: 3, left: 0, bottom: 6, right: CellAddress.maxCols - 1))
        c.setHidden(.rows, false)
        XCTAssertTrue(c.sheet.hiddenCols.isEmpty)
        XCTAssertTrue(c.sheet.hiddenRows.isEmpty)
        XCTAssertEqual(c.sheet.colWidths[1], 120)
        // Every row at once is refused.
        c.select(range: CellRange(top: 0, left: 0, bottom: CellAddress.maxRows - 1, right: CellAddress.maxCols - 1))
        c.setHidden(.rows, true)
        XCTAssertTrue(c.sheet.hiddenRows.isEmpty)
    }
}
