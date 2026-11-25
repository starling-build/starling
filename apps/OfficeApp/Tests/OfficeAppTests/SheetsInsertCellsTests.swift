import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsInsertCellsTests: XCTestCase {
    private func book() -> WorkbookController {
        let c = WorkbookController()
        for (a, v) in [("A1", "1"), ("B1", "2"), ("A2", "3"), ("B2", "4"), ("A3", "5"), ("C1", "=A1+A3"), ("D1", "=SUM(A1:A3)")] {
            c.setInput(v, at: CellAddress(a)!)
        }
        return c
    }
    private func v(_ c: WorkbookController, _ a: String) -> CellValue? { c.sheet.cells[CellAddress(a)!]?.value }

    func testInsertShiftDownMovesOnlyThatColumnAndFormulasFollow() {
        let c = book()
        XCTAssertTrue(c.insertCells(CellRange(top: 1, left: 0, bottom: 1, right: 0), shift: .down))
        XCTAssertTrue(c.sheet.cells[CellAddress("A2")!] == nil || c.sheet.cells[CellAddress("A2")!]!.value.isEmpty)
        XCTAssertEqual(v(c, "A3"), .number(3))
        XCTAssertEqual(v(c, "A4"), .number(5))
        XCTAssertEqual(v(c, "B2"), .number(4))            // column B did not move
        XCTAssertEqual(c.sheet.cells[CellAddress("C1")!]?.input, "=A1+A4")
        c.undo()
        XCTAssertEqual(v(c, "A2"), .number(3))
        XCTAssertEqual(c.sheet.cells[CellAddress("C1")!]?.input, "=A1+A3")
    }

    func testInsertShiftRight() {
        let c = book()
        XCTAssertTrue(c.insertCells(CellRange(top: 0, left: 0, bottom: 0, right: 0), shift: .right))
        XCTAssertEqual(v(c, "B1"), .number(1))
        XCTAssertEqual(v(c, "C1"), .number(2))
        XCTAssertEqual(v(c, "A2"), .number(3))
    }

    func testDeleteShiftUpClosesTheGapAndRefsToDeletedCellsBreak() {
        let c = book()
        XCTAssertTrue(c.deleteCells(CellRange(top: 1, left: 0, bottom: 1, right: 0), shift: .up))
        XCTAssertEqual(v(c, "A2"), .number(5))
        XCTAssertEqual(c.sheet.cells[CellAddress("C1")!]?.input, "=A1+A2")
        XCTAssertEqual(c.sheet.cells[CellAddress("D1")!]?.input, "=SUM(A1:A2)")
        XCTAssertEqual(v(c, "B2"), .number(4))
    }

    func testDeleteShiftLeft() {
        let c = book()
        XCTAssertTrue(c.deleteCells(CellRange(top: 0, left: 0, bottom: 0, right: 0), shift: .left))
        XCTAssertEqual(v(c, "A1"), .number(2))
    }

    func testSizesAreOneUndoStep() {
        let c = book()
        c.select(range: CellRange(top: 0, left: 0, bottom: 2, right: 1), active: CellAddress("A1")!)
        c.setRowHeights(30); c.setColumnWidths(60)
        XCTAssertEqual(c.sheet.rowHeight(1), 30)
        XCTAssertEqual(c.sheet.colWidth(1), 60)
        c.undo()
        XCTAssertNotEqual(c.sheet.colWidth(1), 60)
    }
}

final class SheetsInsertCellsShellTests: XCTestCase {
    func testCommandsOpenTheDialogsAndEscapeClosesThem() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        guard let shell = ui.state(SheetsShellState.self) else { return XCTFail("no shell") }
        shell.wb.onCommand?(.cellsDialog(insert: true))
        ui.pump()
        XCTAssertTrue(ui.has(id: "cells-shiftDown"))
        XCTAssertTrue(ui.has(id: "cells-entireRow"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "cells-shiftDown"))
        shell.wb.onCommand?(.sizeDialog(.rowHeight))
        ui.pump()
        XCTAssertTrue(ui.has(id: "size-input"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "size-input"))
    }
}
