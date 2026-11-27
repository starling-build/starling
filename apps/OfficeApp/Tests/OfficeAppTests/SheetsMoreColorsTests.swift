import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-FM-3: Home > Fill Color and Font Color end in "More Colors…", which opens
/// the custom colour dialog (hex or red/green/blue); OK colours the selection
/// in one undo step, Cancel changes nothing.
final class SheetsMoreColorsTests: XCTestCase {
    private func shell() throws -> (WidgetTester, WorkbookController) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1440, 932))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        wb.setInput("x", at: CellAddress("A1")!)
        wb.select(range: CellRange(top: 0, left: 0, bottom: 1, right: 1))
        ui.pump()
        return (ui, wb)
    }
    private func typeHex(_ ui: WidgetTester, _ hex: String) {
        let boxes = ui.elements().filter { $0.widget is FluentTextBox }
        let b = boxes[boxes.count - 4].findRenderObject() as! RenderBox   // the dialog's Hex box (then R, G, B)
        ui.tap(at: b.localToGlobal(Offset(b.size.width / 2, b.size.height / 2)))
        for _ in 0..<8 { ui.press(.backspace) }
        ui.type(hex)
        ui.pump()
    }

    func testFillColorMoreColorsSetsACustomFillAndUndoTakesItBack() throws {
        let (ui, wb) = try shell()
        XCTAssertTrue(ui.tap(tip: "Fill Color")); ui.pump()
        XCTAssertTrue(ui.tap(text: "More Colors…")); ui.pump()
        XCTAssertNotNil(ui.state(CustomColorDialogState.self))
        typeHex(ui, "12AB34")
        XCTAssertTrue(ui.tap(text: "OK")); ui.pump()
        XCTAssertNil(ui.state(CustomColorDialogState.self))
        for a in ["A1", "B2"] { XCTAssertEqual(wb.style(at: CellAddress(a)!).fill, 0x12AB34, a) }
        XCTAssertNil(wb.style(at: CellAddress("A1")!).color)
        wb.undo()
        XCTAssertNil(wb.style(at: CellAddress("A1")!).fill)
        XCTAssertEqual(wb.sheet.cells[CellAddress("A1")!]?.input, "x")
    }

    func testFontColorMoreColorsSetsTheTextColourAndCancelChangesNothing() throws {
        let (ui, wb) = try shell()
        XCTAssertTrue(ui.tap(tip: "Font Color")); ui.pump()
        XCTAssertTrue(ui.tap(text: "More Colors…")); ui.pump()
        typeHex(ui, "C00000")
        XCTAssertTrue(ui.tap(text: "Cancel")); ui.pump()
        XCTAssertNil(ui.state(CustomColorDialogState.self))
        XCTAssertNil(wb.style(at: CellAddress("A1")!).color)
        XCTAssertTrue(ui.tap(tip: "Font Color")); ui.pump()
        XCTAssertTrue(ui.tap(text: "More Colors…")); ui.pump()
        typeHex(ui, "C00000")
        XCTAssertTrue(ui.tap(text: "OK")); ui.pump()
        XCTAssertEqual(wb.style(at: CellAddress("B2")!).color, 0xC00000)
        XCTAssertNil(wb.style(at: CellAddress("A1")!).fill)
    }
}
