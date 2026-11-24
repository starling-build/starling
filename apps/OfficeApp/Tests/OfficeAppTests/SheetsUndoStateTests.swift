// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// X-P0-3: the workbook reports what the title bar's Undo and Redo need.
final class SheetsUndoStateTests: XCTestCase {
    func testUndoRedoStateFollowsEdits() {
        let c = WorkbookController()
        XCTAssertFalse(c.canUndo)
        c.setInput("1", at: CellAddress("A1")!)
        XCTAssertTrue(c.canUndo)
        XCTAssertFalse(c.canRedo)
        c.undo()
        XCTAssertFalse(c.canUndo)
        XCTAssertTrue(c.canRedo)
        c.redo()
        XCTAssertTrue(c.canUndo)
    }
}
