// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsPageBreakPreviewTests: XCTestCase {
    func testMoveBreakMovesTheCutAndUndoesAsOne() {
        let c = WorkbookController()
        c.insertPageBreak(row: 10, col: 0)
        c.moveBreak(isRow: true, from: 10, to: 14)
        XCTAssertEqual(c.sheet.breakIds("rowBreaks"), [14])
        c.undo()
        XCTAssertEqual(c.sheet.breakIds("rowBreaks"), [10])
    }

    func testMoveBreakOnColumns() {
        let c = WorkbookController()
        c.insertPageBreak(row: 0, col: 3)
        c.moveBreak(isRow: false, from: 3, to: 5)
        XCTAssertEqual(c.sheet.breakIds("colBreaks"), [5])
        XCTAssertEqual(c.sheet.breakIds("rowBreaks"), [])
    }

    func testPreviewToggleIsViewStateOnly() {
        let c = WorkbookController()
        XCTAssertFalse(c.breakPreview)
        c.breakPreview = true
        c.undo()      // nothing to undo: a view choice is not an edit
        XCTAssertTrue(c.breakPreview)
    }

    private func tall() -> WorkbookController {
        let c = WorkbookController()
        for r in 0..<100 { c.setInput("x", at: CellAddress(row: r, col: 0)) }
        return c
    }

    func testAutomaticCutsAreDashedAndManualOnesSolid() {
        let c = tall()
        let auto = PageBreakLines.compute(c, width: { _ in 48 }, height: { _ in 15 })
        XCTAssertFalse(auto.rows.isEmpty, "100 rows of 15 pt do not fit one page")
        XCTAssertTrue(auto.rows.allSatisfy { !$0.manual })
        c.insertPageBreak(row: 20, col: 0)
        let with = PageBreakLines.compute(c, width: { _ in 48 }, height: { _ in 15 })
        XCTAssertEqual(with.rows.first?.at, 20)
        XCTAssertEqual(with.rows.first?.manual, true)
    }

    func testMovingABreakMovesTheLine() {
        let c = tall()
        c.insertPageBreak(row: 20, col: 0)
        c.moveBreak(isRow: true, from: 20, to: 30)
        let l = PageBreakLines.compute(c, width: { _ in 48 }, height: { _ in 15 })
        XCTAssertEqual(l.rows.first?.at, 30)
    }
}
