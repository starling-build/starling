// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-SH-1: Select All Sheets — an edit on one sheet goes to every grouped sheet.

import XCTest
@testable import OfficeApp

final class SheetsGroupEditTests: XCTestCase {
    private func book3() -> WorkbookController {
        let c = WorkbookController()
        c.addSheet(); c.addSheet()
        c.activeSheet = 0
        return c
    }
    private let a1 = CellAddress(row: 0, col: 0)

    func testTypingGoesToEveryGroupedSheetAndUndoesAsOneStep() {
        let c = book3()
        c.selectAllSheets()
        XCTAssertTrue(c.isGrouped)
        c.setInput("hello", at: a1)
        for s in c.book.sheets { XCTAssertEqual(s.cells[a1]?.input, "hello") }
        c.undo()
        for s in c.book.sheets { XCTAssertNil(s.cells[a1]) }
        c.redo()
        for s in c.book.sheets { XCTAssertEqual(s.cells[a1]?.input, "hello") }
    }

    func testFormattingGoesToTheGroupToo() {
        let c = book3()
        c.selectAllSheets()
        c.toggleStyle(\.bold)
        for i in c.book.sheets.indices { XCTAssertTrue(c.book.style(c.book.sheets[i].cells[a1]?.style ?? 0).bold) }
    }

    func testUngroupedEditsStayOnOneSheet() {
        let c = book3()
        c.selectAllSheets()
        c.ungroupSheets()
        c.setInput("x", at: a1)
        XCTAssertEqual(c.book.sheets[0].cells[a1]?.input, "x")
        XCTAssertNil(c.book.sheets[1].cells[a1])
    }

    func testCtrlClickGroupsOnlyTheChosenSheets() {
        let c = book3()
        c.groupSheet(2, add: true)
        c.setInput("y", at: a1)
        XCTAssertEqual(c.book.sheets[0].cells[a1]?.input, "y")
        XCTAssertNil(c.book.sheets[1].cells[a1])
        XCTAssertEqual(c.book.sheets[2].cells[a1]?.input, "y")
    }
}
