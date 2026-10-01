// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Editing that moves cells, against what Excel does: inserting and
// deleting rows and columns (references follow, ranges grow and shrink,
// deleted ones become #REF!), fills and series, Ctrl+Enter, copy and cut,
// and undo over all of it.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsEditingTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }

    private func book(_ cells: [String: String], sheets: [String] = ["Sheet1"]) -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: sheets.map { Worksheet(name: $0) }))
        c.setInputs(cells.map { (CellAddress($0.key)!, $0.value) })
        return c
    }

    func testInsertRowsMovesCellsAndReferences() {
        let c = book(["A1": "1", "A2": "2", "A3": "3", "A4": "=SUM(A1:A3)", "B1": "=A3*10", "B2": "=$A$3"])
        c.insert(.rows, at: 1)                     // a blank row 2
        XCTAssertEqual(c.sheet.value(a("A3")), .number(2))
        XCTAssertEqual(c.input(a("A5")), "=SUM(A1:A4)")   // the range grew around the new row
        XCTAssertEqual(c.input(a("B1")), "=A4*10")
        XCTAssertEqual(c.input(a("B3")), "=$A$4")         // absolute references follow too
        XCTAssertEqual(c.sheet.value(a("A5")), .number(6))
        c.undo()
        XCTAssertEqual(c.input(a("A4")), "=SUM(A1:A3)")
        XCTAssertEqual(c.sheet.value(a("A2")), .number(2))
        c.redo()
        XCTAssertEqual(c.input(a("A5")), "=SUM(A1:A4)")
    }

    func testDeleteRowsShrinksRangesAndBreaksDeletedReferences() {
        let c = book(["A1": "1", "A2": "2", "A3": "3", "A4": "4", "B1": "=SUM(A1:A4)", "B2": "=A3", "C1": "=A2+A4"])
        c.delete(.rows, at: 2)                     // row 3 goes
        XCTAssertEqual(c.input(a("B1")), "=SUM(A1:A3)")
        XCTAssertEqual(c.sheet.value(a("B1")), .number(7))
        XCTAssertEqual(c.input(a("B2")), "=#REF!")
        XCTAssertEqual(c.sheet.value(a("B2")), .error(.ref))
        XCTAssertEqual(c.input(a("C1")), "=A2+A3")         // A4 moved up
        // A range wholly deleted is #REF! too.
        c.setInput("=SUM(A2:A3)", at: a("D1"))
        c.delete(.rows, at: 1, count: 2)
        XCTAssertEqual(c.input(a("D1")), "=SUM(#REF!)")
    }

    func testColumnsAndOtherSheets() {
        let c = book(["A1": "5", "B1": "6", "C1": "=A1+B1"], sheets: ["Data", "Report"])
        c.setInputs([(a("A1"), "=Data!B1*2"), (a("A2"), "=SUM(Data!A1:C1)")], sheet: 1)
        c.insert(.cols, at: 1, count: 2)           // two blank columns before B
        XCTAssertEqual(c.input(a("E1")), "=A1+D1")
        XCTAssertEqual(c.book.sheets[1].cells[a("A1")]?.input, "=Data!D1*2")
        XCTAssertEqual(c.book.sheets[1].cells[a("A2")]?.input, "=SUM(Data!A1:E1)")
        XCTAssertEqual(c.book.sheets[1].value(a("A1")), .number(12))
    }

    func testSizesAndMergesFollow() {
        let c = book(["A1": "x"])
        c.setRowHeight(4, 30)
        c.sheet.merges = [CellRange("B5:C6")!]
        c.insert(.rows, at: 0, count: 3)
        XCTAssertEqual(c.sheet.rowHeight(7), 30)
        XCTAssertEqual(c.sheet.merges, [CellRange("B8:C9")!])
        c.delete(.rows, at: 7)
        XCTAssertEqual(c.sheet.merges, [CellRange("B8:C8")!])  // one row of two columns is still a merge
        c.delete(.cols, at: 2)
        XCTAssertEqual(c.sheet.merges, [])                 // one cell is not
    }

    func testSheetEditsUndo() {
        let c = book(["A1": "=Other!A1"], sheets: ["Sheet1", "Other"])
        c.setInputs([(a("A1"), "9")], sheet: 1)
        c.deleteSheet(1)
        XCTAssertEqual(c.input(a("A1")), "=#REF!")
        c.undo()
        XCTAssertEqual(c.book.sheets.count, 2)
        XCTAssertEqual(c.sheet.value(a("A1")), .number(9))
        c.setColumnWidth(0, 120)
        c.undo()
        XCTAssertEqual(c.sheet.colWidth(0), Worksheet.defaultColWidth)
        c.addSheet()
        XCTAssertEqual(c.book.sheets.count, 3)
        c.undo()
        XCTAssertEqual(c.book.sheets.count, 2)
    }

    func testFillDownAndCtrlEnter() {
        let c = book(["A1": "1", "A2": "2", "A3": "3", "B1": "=A1*2"])
        c.select(range: CellRange("B1:B3")!)
        c.fillDown()
        XCTAssertEqual(c.input(a("B3")), "=A3*2")
        XCTAssertEqual(c.sheet.value(a("B3")), .number(6))
        c.select(range: CellRange("C1:C3")!, active: a("C1"))
        c.fillSelection(with: "=A1+1")
        XCTAssertEqual(c.input(a("C2")), "=A2+1")
        XCTAssertEqual(c.sheet.value(a("C3")), .number(4))
        c.undo()
        XCTAssertNil(c.sheet.cells[a("C2")])
    }

    func testSeriesFill() {
        let c = book(["A1": "1", "A2": "3", "B1": "Jan", "C1": "Item 7", "D1": "1/30/2026", "E1": "5", "F1": "=A1"])
        c.select(range: CellRange("A1:A2")!)
        c.fillSeries(to: CellRange("A1:A5")!)
        XCTAssertEqual((3 ... 5).map { c.sheet.value(CellAddress(row: $0 - 1, col: 0)) }, [.number(5), .number(7), .number(9)])
        c.select(a("B1")); c.fillSeries(to: CellRange("B1:B4")!)
        XCTAssertEqual(c.sheet.value(a("B4")), .text("Apr"))
        c.select(a("C1")); c.fillSeries(to: CellRange("C1:C3")!)
        XCTAssertEqual(c.sheet.value(a("C3")), .text("Item 9"))
        c.select(a("D1")); c.fillSeries(to: CellRange("D1:D3")!)
        XCTAssertEqual(c.sheet.value(a("D3")), .number(46054))    // 1/30/2026 is 46052; two days on, across the month end
        c.select(a("E1")); c.fillSeries(to: CellRange("E1:E3")!)
        XCTAssertEqual(c.sheet.value(a("E3")), .number(5))        // one number copies, as Excel's does
        c.select(a("F1")); c.fillSeries(to: CellRange("F1:F3")!)
        XCTAssertEqual(c.input(a("F3")), "=A3")                   // a formula fills shifted
    }

    func testCopyAndCutPaste() {
        let c = book(["A1": "10", "A2": "=A1*2", "B5": "=A2+A1"])
        c.select(range: CellRange("A1:A2")!)
        let copy = c.clip(cut: false, text: "")
        c.select(a("C3"))
        c.paste(copy)
        XCTAssertEqual(c.input(a("C4")), "=C3*2")                 // shifted by the distance
        XCTAssertEqual(c.sheet.value(a("C4")), .number(20))
        XCTAssertEqual(c.selection, CellRange("C3:C4")!)
        // A cut moves the cells; formulas that pointed at them follow.
        c.select(range: CellRange("A1:A2")!)
        let cut = c.clip(cut: true, text: "")
        c.select(a("D1"))
        c.paste(cut)
        XCTAssertNil(c.sheet.cells[a("A1")])
        XCTAssertEqual(c.input(a("D2")), "=D1*2")                 // the moved formula still reads its neighbour
        XCTAssertEqual(c.input(a("B5")), "=D2+D1")
        XCTAssertEqual(c.sheet.value(a("B5")), .number(30))
        c.undo()
        XCTAssertEqual(c.input(a("B5")), "=A2+A1")
        XCTAssertEqual(c.sheet.value(a("A1")), .number(10))
    }
}
