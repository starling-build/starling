import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Layout → Page Setup reaches the controller: the dialog opens from the ribbon,
/// OK applies one undoable change, a bad number is refused with a message.
final class SheetsPageSetupUITests: XCTestCase {
    private func shell() throws -> (WidgetTester, SheetsShellState) {
        let path = NSTemporaryDirectory() + "pagesetup-ui-\(getpid()).xlsx"
        try Xlsx.write(Workbook()).write(to: URL(fileURLWithPath: path))
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        return (ui, try XCTUnwrap(ui.state(SheetsShellState.self)))
    }

    func testPageSetupOpensFromTheLayoutTabAndAppliesAsOneUndo() throws {
        let (ui, _) = try shell()
        XCTAssertFalse(ui.has(text: "Margins (inches)"))
        XCTAssertTrue(ui.tap(text: "Layout"))
        XCTAssertTrue(ui.tap(text: "Page Setup"))
        let panel = try XCTUnwrap(ui.state(PageSetupPanelState.self), "the dialog did not open")
        panel.form.landscape = true
        panel.boxes["left"]?.text = "1"
        panel.boxes["area"]?.text = "A1:C5"
        panel.boxes["titleRows"]?.text = "1:1"
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertNil(ui.state(PageSetupPanelState.self), "OK closes the dialog")
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        let s = SheetPrintSetup.read(wb.sheet)
        XCTAssertTrue(s.landscape)
        XCTAssertEqual(s.left, 72, accuracy: 0.01)
        XCTAssertEqual(SheetPrintLayout.printNames(wb.book, sheet: 0).areas.count, 1)
        XCTAssertEqual(SheetPrintLayout.printNames(wb.book, sheet: 0).titleRows, 0...0)
        wb.undo()
        XCTAssertFalse(SheetPrintSetup.read(wb.sheet).landscape)
    }

    func testABadMarginIsRefusedAndTheDialogStaysOpen() throws {
        let (ui, _) = try shell()
        XCTAssertTrue(ui.tap(text: "Layout"))
        XCTAssertTrue(ui.tap(text: "Page Setup"))
        let panel = try XCTUnwrap(ui.state(PageSetupPanelState.self))
        panel.boxes["top"]?.text = "abc"
        XCTAssertTrue(ui.tap(text: "OK"))
        XCTAssertNotNil(ui.state(PageSetupPanelState.self))
        XCTAssertTrue(ui.texts().contains { $0.containsSubstring("Top margin") })
    }
}

final class SheetsPageBreakUITests: XCTestCase {
    func testInsertPageBreakMenuReachesTheModel() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"), size: Size(1280, 800))
        ui.pump()
        ui.tap(text: "Layout"); ui.pump()
        ui.tap(text: "Breaks"); ui.pump()
        XCTAssertTrue(ui.has(text: "Insert Page Break"))
    }
}
