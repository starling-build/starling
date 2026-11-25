// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-VW-1: View options per sheet: zoom, headings, show formulas, right-to-left. Saved and read back.

import XCTest
import Flutter
import FlutterSwiftBridge
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

    func testViewSettingsAreNotUndoStepsButMarkTheFileChanged() {
        let c = WorkbookController()
        c.setInput("x", at: CellAddress(row: 0, col: 0))
        c.markSaved()
        XCTAssertEqual(c.edits, 0)
        c.setZoom(percent: 120)
        XCTAssertGreaterThan(c.edits, 0)
        c.toggleHeadings(); c.toggleShowFormulas(); c.toggleRightToLeft(); c.toggleGridlines()
        c.undo()   // takes back the typing, not the view
        XCTAssertNil(c.sheet.cells[CellAddress(row: 0, col: 0)])
        XCTAssertEqual(c.sheet.zoomPercent, 120)
        XCTAssertFalse(c.sheet.showHeadings)
        XCTAssertTrue(c.sheet.showFormulas)
        XCTAssertTrue(c.sheet.rightToLeft)
        XCTAssertFalse(c.sheet.showGridlines)
    }

    func testShowFormulasDoublesTheColumnsOnScreen() {
        let c = WorkbookController()
        let g = SheetGridState(headless: c)
        let w = g.cols.size(0)
        c.toggleShowFormulas()
        XCTAssertEqual(g.cols.size(0), w * 2, accuracy: 0.01)
        XCTAssertEqual(g.cols.size(5), w * 2, accuracy: 0.01)
        c.toggleShowFormulas()
        XCTAssertEqual(g.cols.size(0), w, accuracy: 0.01)
    }

    func testRightToLeftSheetMirrorsTheScreenButNotThePrint() {
        let c = WorkbookController()
        let g = SheetGridState(headless: c)
        XCTAssertFalse(g.rtl)
        XCTAssertEqual(g._screen(Offset(10, 5)).dx, 10)
        c.toggleRightToLeft()
        XCTAssertTrue(g.rtl)
        XCTAssertEqual(g._screen(Offset(10, 5)).dx, -10)   // (the window is 0 wide here: x becomes width - x)
        XCTAssertEqual(g._screen(Offset(10, 5)).dy, 5)
        g.printing = true
        XCTAssertFalse(g.rtl)   // paper has its own mirroring
        g.printing = false
        c.toggleRightToLeft()
        XCTAssertFalse(g.rtl)
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

    /// Writes the right-to-left file for the Excel check (only when XCHECK_DIR is set): left, right, centre and general text, a number, a picture, a merged cell.
    func testWriteRightToLeftCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let c = WorkbookController()
        c.setInputs([(CellAddress(row: 0, col: 0), "Left"), (CellAddress(row: 1, col: 0), "Right"), (CellAddress(row: 2, col: 0), "Centre"),
                     (CellAddress(row: 3, col: 0), "General"), (CellAddress(row: 4, col: 0), "12345"), (CellAddress(row: 5, col: 0), "Merged across"),
                     (CellAddress(row: 0, col: 3), "D1"), (CellAddress(row: 0, col: 1), "B1")])
        for (row, a) in [(0, CellStyle.HAlign.left), (1, .right), (2, .center)] {
            c.select(CellAddress(row: row, col: 0))
            c.toggleAlign(a)
        }
        c.select(range: CellRange(top: 5, left: 0, bottom: 5, right: 2))
        c.toggleMerge()
        c.select(CellAddress(row: 0, col: 0))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==")!
        let ws = c.sheet
        let corner = ws.point(SheetMarker(col: 4, colOff: 0, row: 1, rowOff: 0))
        ws.drawings.append(SheetDrawing(name: "Picture 1", anchor: ws.anchor(x: corner.x, y: corner.y, width: 80, height: 60), kind: .picture(path: "xl/media/image1.png", data: png)))
        ws.drawingsEdited = true
        c.toggleRightToLeft()
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/rtl.xlsx"))
    }
}
