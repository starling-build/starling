import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-CL-1: Excel's Paste Options button. After a paste of the app's own copy it offers the paste again another
/// way, in place of the first one, until the cells change.
final class SheetsPasteOptionsTests: XCTestCase {
    private func copied(_ c: WorkbookController) -> WorkbookController.Clip {
        c.setInput("2", at: CellAddress("A1")!); c.setInput("=A1*10", at: CellAddress("B1")!)
        c.select(range: CellRange("A1:B1")!, active: CellAddress("A1")!)
        return c.clip(cut: false, text: "")
    }
    private func at(_ c: WorkbookController, _ a: String) -> Cell? { c.sheet.cells[CellAddress(a)!] }

    func testValuesReplaceThePasteAndOneUndoTakesItAllBack() {
        let c = WorkbookController()
        let clip = copied(c)
        c.select(CellAddress("D1")!); c.pasteSpecial(clip, PasteSpecial())
        XCTAssertEqual(c.pasteOptions?.range, CellRange("D1:E1"))
        XCTAssertNotNil(at(c, "E1")?.formula)
        c.repaste(PasteSpecial(what: .values))
        XCTAssertNil(at(c, "E1")?.formula)
        XCTAssertEqual(at(c, "E1")?.value, .number(20))
        XCTAssertEqual(c.pasteOptions?.how, PasteSpecial(what: .values))
        c.undo()
        XCTAssertNil(at(c, "D1"))
        XCTAssertNil(at(c, "E1"))
    }

    func testTransposeMovesTheButtonAndAnEditHidesIt() {
        let c = WorkbookController()
        let clip = copied(c)
        c.select(CellAddress("D1")!); c.pasteSpecial(clip, PasteSpecial())
        c.repaste(PasteSpecial(transpose: true))
        XCTAssertEqual(c.pasteOptions?.range, CellRange("D1:D2"))
        XCTAssertNil(at(c, "E1"))
        XCTAssertNotNil(at(c, "D2"))
        c.setInput("x", at: CellAddress("H9")!)
        XCTAssertNil(c.pasteOptions)
    }

    func testACutHasNoButton() {
        let c = WorkbookController()
        c.setInput("2", at: CellAddress("A1")!)
        c.select(CellAddress("A1")!)
        let clip = c.clip(cut: true, text: "")
        c.select(CellAddress("D1")!); c.pasteSpecial(clip, PasteSpecial())
        XCTAssertNil(c.pasteOptions)
    }

    func testTheButtonOpensTheMenuAndValuesRepastes() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1440, 932))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        let clip = copied(wb)
        wb.select(CellAddress("D1")!); wb.pasteSpecial(clip, PasteSpecial())
        ui.pump()
        let grid = try XCTUnwrap(ui.state(SheetGridState.self))
        let b = try XCTUnwrap(grid.pasteButton())
        let box = try XCTUnwrap(grid.context?.findRenderObject() as? RenderBox)
        ui.tap(at: box.localToGlobal(b.center)); ui.pump()
        XCTAssertTrue(ui.has(id: "paste-options.Values"))
        XCTAssertTrue(ui.tap(text: "Values")); ui.pump()
        XCTAssertFalse(ui.has(id: "paste-options.Values"))
        XCTAssertNil(at(wb, "E1")?.formula)
        XCTAssertEqual(at(wb, "E1")?.value, .number(20))
    }
}
