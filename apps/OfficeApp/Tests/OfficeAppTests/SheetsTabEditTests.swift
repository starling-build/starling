// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-SH-1: move, copy and colour sheet tabs, saved and read back.

import XCTest
@testable import OfficeApp

final class SheetsTabEditTests: XCTestCase {
    private func book3() -> WorkbookController {
        let c = WorkbookController()
        c.addSheet(); c.addSheet()           // Sheet1, Sheet2, Sheet3 after the new ones
        return c
    }

    func testMoveKeepsPrintAreaWithItsSheetAndUndoesAsOne() throws {
        let c = book3()
        c.activeSheet = 0
        c.setPrintArea(CellRange(CellAddress(row: 0, col: 0), CellAddress(row: 4, col: 2)))
        let first = c.book.sheets[0].name
        XCTAssertTrue(c.moveSheet(0, to: 2))
        XCTAssertEqual(c.book.sheets[2].name, first)
        XCTAssertEqual(c.activeSheet, 2, "the open sheet stays open")
        XCTAssertEqual(SheetPrintLayout.printNames(c.book, sheet: 2).areas.count, 1)
        XCTAssertEqual(SheetPrintLayout.printNames(c.book, sheet: 0).areas.count, 0)
        let back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertEqual(back.sheets[2].name, first)
        XCTAssertEqual(SheetPrintLayout.printNames(back, sheet: 2).areas.count, 1)
        c.undo()
        XCTAssertEqual(c.book.sheets[0].name, first)
        XCTAssertEqual(SheetPrintLayout.printNames(c.book, sheet: 0).areas.count, 1)
    }

    func testCopyRenamesAndPointsItsOwnReferencesAtTheCopy() throws {
        let c = WorkbookController()
        c.setInput("5", at: CellAddress(row: 0, col: 0))
        c.setInput("=Sheet1!A1*2", at: CellAddress(row: 0, col: 1))
        XCTAssertTrue(c.copySheet(0))
        XCTAssertEqual(c.book.sheets.count, 2)
        XCTAssertEqual(c.book.sheets[1].name, "Sheet1 (2)")
        XCTAssertEqual(c.activeSheet, 1)
        c.setInput("7", at: CellAddress(row: 0, col: 0))
        XCTAssertEqual(c.book.sheets[1].cells[CellAddress(row: 0, col: 1)]?.input, "=Sheet1 (2)!A1*2".replacingAll("Sheet1 (2)!", with: "'Sheet1 (2)'!"))
        let back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertEqual(back.sheets.map(\.name), ["Sheet1", "Sheet1 (2)"])
        c.undo(); c.undo()
        XCTAssertEqual(c.book.sheets.count, 1)
    }

    func testTabColorSurvivesSaveAndChangesInPlace() throws {
        let c = book3()
        c.setTabColor(1, "FFC00000")
        var back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertEqual(back.sheets[1].tabColor, "FFC00000")
        c.setTabColor(1, "FF0070C0")
        back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertEqual(back.sheets[1].tabColor, "FF0070C0")
        c.setTabColor(1, nil)
        back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertNil(back.sheets[1].tabColor)
        XCTAssertEqual(SheetTabEdit_withTabColor("<sheetPr codeName=\"S\"><pageSetUpPr fitToPage=\"1\"/></sheetPr>", "FF00FF00"),
                       "<sheetPr codeName=\"S\"><tabColor rgb=\"FF00FF00\"/><pageSetUpPr fitToPage=\"1\"/></sheetPr>")
    }

    func testPageSetupFitToPageStillWorksWithAColour() throws {
        let c = book3()
        c.setTabColor(0, "FFC00000")
        c.activeSheet = 0
        c.setPageSetup(PageSetupChange(fitWide: 1, fitTall: 0))
        let back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertEqual(back.sheets[0].tabColor, "FFC00000")
        XCTAssertEqual(SheetPrintSetup.read(back.sheets[0]).fitWidth, 1)
    }

    /// Writes the file for the Excel check (only when XCHECK_DIR is set).
    func testWriteExcelCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let c = WorkbookController()
        c.setInput("Alpha", at: CellAddress(row: 0, col: 0)); c.setInput("5", at: CellAddress(row: 1, col: 0))
        c.setInput("=Sheet1!A2*2", at: CellAddress(row: 1, col: 1))
        c.addSheet(); c.addSheet()
        c.activeSheet = 0
        c.setPrintArea(CellRange(CellAddress(row: 0, col: 0), CellAddress(row: 4, col: 2)))
        XCTAssertTrue(c.copySheet(0))                     // Sheet1, Sheet1 (2), Sheet2, Sheet3
        XCTAssertTrue(c.moveSheet(0, to: 3))              // Sheet1 (2), Sheet2, Sheet3, Sheet1
        c.setTabColor(0, "FFC00000"); c.setTabColor(2, "FF0070C0")
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/6-sheet-tabs.xlsx"))
    }
}

private func SheetTabEdit_withTabColor(_ s: String, _ c: String?) -> String { WorkbookController._withTabColor(s, c) }
