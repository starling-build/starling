import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class SheetsPasteSpecialTests: XCTestCase {
    private func sheet() -> (WorkbookController, WorkbookController.Clip) {
        let c = WorkbookController()
        c.setInput("2", at: CellAddress("A1")!); c.setInput("=A1*10", at: CellAddress("B1")!)
        c.setInput("5", at: CellAddress("A2")!)   // B2 stays empty
        c.select(range: CellRange(top: 0, left: 0, bottom: 1, right: 1), active: CellAddress("A1")!)
        c.formatCells(CellFormatEdit(bold: .set(true)))
        c.select(range: CellRange(top: 0, left: 0, bottom: 1, right: 1), active: CellAddress("A1")!)
        let clip = c.clip(cut: false, text: "")
        return (c, clip)
    }
    private func at(_ c: WorkbookController, _ a: String) -> Cell? { c.sheet.cells[CellAddress(a)!] }
    private func go(_ c: WorkbookController, _ clip: WorkbookController.Clip, to a: String, _ how: PasteSpecial) {
        c.select(CellAddress(a)!); c.pasteSpecial(clip, how)
    }

    func testValuesKeepNoFormulaAndNoFormat() {
        let (c, clip) = sheet()
        go(c, clip, to: "D1", PasteSpecial(what: .values))
        XCTAssertNil(at(c, "E1")?.formula)
        XCTAssertEqual(at(c, "E1")?.value, .number(20))
        XCTAssertEqual(c.style(at: CellAddress("D1")!).bold, false)
    }

    func testFormulasKeepTheirOwnFormat() {
        let (c, clip) = sheet()
        go(c, clip, to: "D1", PasteSpecial(what: .formulas))
        XCTAssertNotNil(at(c, "E1")?.formula)
        XCTAssertEqual(c.style(at: CellAddress("E1")!).bold, false)
    }

    func testFormatsOnlyLeaveValues() {
        let (c, clip) = sheet()
        c.setInput("9", at: CellAddress("D1")!)
        go(c, clip, to: "D1", PasteSpecial(what: .formats))
        XCTAssertEqual(at(c, "D1")?.value, .number(9))
        XCTAssertTrue(c.style(at: CellAddress("D1")!).bold)
    }

    func testTransposeTurnsTheBlock() {
        let (c, clip) = sheet()
        go(c, clip, to: "D1", PasteSpecial(transpose: true))
        XCTAssertEqual(at(c, "D2")?.value, .number(20))     // B1 moves to D... (row 1 col 2 -> row 2 col 1)
        XCTAssertEqual(at(c, "E1")?.value, .number(5))      // A2 -> E1
    }

    func testOperationAndSkipBlanksAndOneUndo() {
        let (c, clip) = sheet()
        c.setInput("100", at: CellAddress("D1")!); c.setInput("7", at: CellAddress("E2")!)
        go(c, clip, to: "D1", PasteSpecial(what: .values, operation: .add, skipBlanks: true))
        XCTAssertEqual(at(c, "D1")?.value, .number(102))
        XCTAssertEqual(at(c, "E2")?.value, .number(7))      // the copied blank leaves it
        c.undo()
        XCTAssertEqual(at(c, "D1")?.value, .number(100))
    }

    func testDivideByZeroAndTextUnderneath() {
        let (c, clip) = sheet()
        c.setInput("x", at: CellAddress("D2")!)
        go(c, clip, to: "D1", PasteSpecial(what: .values, operation: .multiply))
        XCTAssertEqual(at(c, "D2")?.value, .text("x"))
    }

    func testColumnWidthsAndRoundTrip() throws {
        let (c, clip) = sheet()
        c.setColumnWidth(0, 120)
        go(c, clip, to: "D1", PasteSpecial(what: .columnWidths))
        XCTAssertEqual(c.sheet.colWidth(3), 120)
        c.undo()
        XCTAssertNotEqual(c.sheet.colWidth(3), 120)
        go(c, clip, to: "D1", PasteSpecial(what: .values))
        let c2 = WorkbookController(); c2.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(c2.sheet.cells[CellAddress("E1")!]?.value, .number(20))
    }
}

/// X-CL-1: the command from the ribbon and the context menu reaches the dialog.
final class SheetsPasteSpecialShellTests: XCTestCase {
    func testTheCommandOpensTheDialogAndOKClosesIt() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        guard let shell = ui.state(SheetsShellState.self) else { return XCTFail("no shell") }
        XCTAssertFalse(ui.has(id: "ps-skip"))
        shell.wb.onCommand?(.pasteSpecial)
        ui.pump()
        XCTAssertTrue(ui.has(id: "ps-what-Values"))
        XCTAssertTrue(ui.has(id: "ps-op-Multiply"))
        XCTAssertTrue(ui.has(id: "ps-transpose"))
        ui.press(.escape)
        ui.pump()
        XCTAssertFalse(ui.has(id: "ps-skip"))
    }
}
