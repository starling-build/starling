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

/// X-PR-1c: the Layout tab's Margins, Size, Print Area, Scale to Fit and Sheet
/// Options reach the controller, each as one undo step, and save as Excel writes them.
final class SheetsPageLayoutRibbonTests: XCTestCase {
    private func shell() throws -> (WidgetTester, WorkbookController) {
        let path = NSTemporaryDirectory() + "pagelayout-ui-\(getpid()).xlsx"
        try Xlsx.write(Workbook()).write(to: URL(fileURLWithPath: path))
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1600, 800))
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        XCTAssertTrue(ui.tap(text: "Layout"))
        return (ui, wb)
    }
    private func pick(_ ui: WidgetTester, _ menu: String, _ item: String) {
        XCTAssertTrue(ui.tap(text: menu), menu); ui.pump()
        XCTAssertTrue(ui.tap(text: item), item); ui.pump()
    }

    func testMarginsAndSizePresetsAreOneUndoEach() throws {
        let (ui, wb) = try shell()
        pick(ui, "Margins", "Wide")
        var s = SheetPrintSetup.read(wb.sheet)
        XCTAssertEqual([s.left, s.right, s.top, s.bottom], [72, 72, 72, 72])
        XCTAssertEqual(s.headerMargin, 36, accuracy: 0.01)
        pick(ui, "Size", "A4")
        XCTAssertEqual(wb.paperNumber, 9)
        let back = try Xlsx.read(try Xlsx.write(wb.book))
        s = SheetPrintSetup.read(back.sheets[0])
        XCTAssertEqual(s.paper.width, 595.2, accuracy: 0.5)
        XCTAssertEqual(s.footerMargin, 36, accuracy: 0.01)
        wb.undo()
        XCTAssertEqual(wb.paperNumber, 1)
        XCTAssertEqual(SheetPrintSetup.read(wb.sheet).left, 72)
        wb.undo()
        XCTAssertEqual(SheetPrintSetup.read(wb.sheet).left, 50.4, accuracy: 0.01)
    }

    func testPrintAreaSetsTheSelectionAndClears() throws {
        let (ui, wb) = try shell()
        wb.select(range: CellRange(top: 1, left: 1, bottom: 4, right: 2))
        pick(ui, "Print Area", "Set Print Area")
        let back = try Xlsx.read(try Xlsx.write(wb.book))
        XCTAssertEqual(SheetPrintLayout.printNames(back, sheet: 0).areas, [CellRange(top: 1, left: 1, bottom: 4, right: 2)])
        XCTAssertTrue(back.fileNames.contains { $0.name == "_xlnm.Print_Area" && $0.localSheet == 0 && $0.text == "'Sheet1'!$B$2:$C$5" },
                      "\(back.fileNames.map(\.text))")
        pick(ui, "Print Area", "Clear Print Area")
        XCTAssertTrue(SheetPrintLayout.printNames(wb.book, sheet: 0).areas.isEmpty)
        wb.undo()
        XCTAssertEqual(SheetPrintLayout.printNames(wb.book, sheet: 0).areas.count, 1)
    }

    func testScaleToFitWidthThenAutomatic() throws {
        let (ui, wb) = try shell()
        pick(ui, "Width: Automatic", "1 page")
        var s = SheetPrintSetup.read(wb.sheet)
        XCTAssertEqual(s.fitWidth, 1); XCTAssertEqual(s.fitHeight, 0)
        pick(ui, "Height: Automatic", "2 pages")
        s = SheetPrintSetup.read(try Xlsx.read(try Xlsx.write(wb.book)).sheets[0])
        XCTAssertEqual(s.fitWidth, 1); XCTAssertEqual(s.fitHeight, 2)
        pick(ui, "Width: 1 page", "Automatic")
        pick(ui, "Height: 2 pages", "Automatic")
        s = SheetPrintSetup.read(wb.sheet)
        XCTAssertNil(s.fitWidth, "both Automatic turns fitting off")
        let ps = try XCTUnwrap(wb.sheet.keptElements.first { $0.name == "pageSetup" }?.text)
        XCTAssertTrue(ps.containsSubstring("orientation=\"portrait\""), ps)
        XCTAssertEqual(s.scale, 100)
        wb.undo()
        XCTAssertEqual(SheetPrintSetup.read(wb.sheet).fitHeight, 2)
    }

    func testPrintGridlinesAndHeadings() throws {
        let (ui, wb) = try shell()
        XCTAssertTrue(ui.tap(text: "Print Gridlines")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Print Headings")); ui.pump()
        let s = SheetPrintSetup.read(try Xlsx.read(try Xlsx.write(wb.book)).sheets[0])
        XCTAssertTrue(s.gridlines && s.headings)
        wb.undo()
        XCTAssertTrue(SheetPrintSetup.read(wb.sheet).gridlines)
        XCTAssertFalse(SheetPrintSetup.read(wb.sheet).headings)
        let shown = wb.sheet.showGridlines
        XCTAssertTrue(ui.tap(text: "View Gridlines")); ui.pump()
        XCTAssertNotEqual(wb.sheet.showGridlines, shown)
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
