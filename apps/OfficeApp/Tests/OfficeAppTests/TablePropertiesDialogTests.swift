// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// W-TB-8: the Table Properties dialog's values are read from the table, applied, and saved.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

final class TablePropertiesDialogTests: XCTestCase {
    private func grid() -> RichDocumentController {
        let c = RichDocumentController(plainText: "")
        c.insertTable(rows: 3, columns: 2)
        return c
    }

    func testDefaultsAreWordsOwn() {
        let v = TablePropertiesValues(of: grid())
        XCTAssertEqual(v.alignment, .left)
        XCTAssertEqual(v.wrap, .none)
        XCTAssertEqual(v.heightRule, .auto)
        XCTAssertTrue(v.mayBreak)
        XCTAssertFalse(v.repeatHeader)
        XCTAssertEqual(v.verticalAlign, "top")
    }

    func testApplyingSetsTableRowColumnAndCell() throws {
        let c = grid()
        var v = TablePropertiesValues(of: c)
        v.alignment = .center; v.indent = 12; v.wrap = .around
        v.heightRule = .exactly; v.height = 30; v.mayBreak = false; v.repeatHeader = true
        v.columnWidth = 100; v.verticalAlign = "center"; v.marginTop = 2; v.marginLeft = 7
        v.apply(to: c)
        let cell = try XCTUnwrap(c.currentCell)
        let t = try XCTUnwrap(c.document.tableStyles[cell.table])
        XCTAssertEqual(t.alignment, .center)
        XCTAssertEqual(t.indent, 12)
        XCTAssertNotNil(t.keptPosition)
        XCTAssertEqual(t.rowHeights[cell.row], 30)
        XCTAssertTrue(t.rowsExactHeight.contains(cell.row))
        XCTAssertTrue(t.rowsCantSplit.contains(cell.row))
        XCTAssertTrue(t.headerRow)
        XCTAssertEqual(t.cellMarginTop, 2)
        XCTAssertEqual(c.document.tableColumns[cell.table]?[cell.column], 100)
        XCTAssertEqual(c.currentCell?.verticalAlign, "center")
        let again = TablePropertiesValues(of: c)
        XCTAssertEqual(again, v)
    }

    func testTurningOffRepeatAndWrapClearsThem() throws {
        let c = grid()
        var v = TablePropertiesValues(of: c)
        v.repeatHeader = true; v.wrap = .around
        v.apply(to: c)
        v = TablePropertiesValues(of: c)
        v.repeatHeader = false; v.wrap = .none
        v.apply(to: c)
        let t = try XCTUnwrap(c.currentTableStyle)
        XCTAssertFalse(t.headerRow)
        XCTAssertNil(t.keptPosition)
    }

    func testPropertiesSurviveASave() throws {
        let c = grid()
        var v = TablePropertiesValues(of: c)
        v.alignment = .right; v.heightRule = .atLeast; v.height = 24; v.mayBreak = false; v.wrap = .around
        v.apply(to: c)
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let id = try XCTUnwrap(back.paragraphs.compactMap { $0.cell?.table }.first)
        let t = try XCTUnwrap(back.tableStyles[id])
        XCTAssertEqual(t.alignment, .right)
        XCTAssertEqual(t.rowHeights[0], 24)
        XCTAssertTrue(t.rowsCantSplit.contains(0))
        XCTAssertNotNil(t.keptPosition)
    }
}
