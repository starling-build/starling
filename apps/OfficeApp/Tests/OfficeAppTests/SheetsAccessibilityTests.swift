import XCTest
import Flutter
@testable import OfficeApp

/// The Sheets grid as a screen reader sees it: the sheet, then each filled cell in view, in reading order.
final class SheetsAccessibilityTests: XCTestCase {
    func testGridPublishesCellsWithTextAndFormulaAndATapSelects() throws {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Budget")]))
        c.setInputs([(CellAddress("A1")!, "Item"), (CellAddress("B1")!, "Cost"), (CellAddress("A2")!, "Tea"),
                     (CellAddress("B2")!, "2"), (CellAddress("B3")!, "3"), (CellAddress("B4")!, "=SUM(B2:B3)")])
        c.select(CellAddress("B2")!)
        let grid = SheetGrid(controller: c, zoom: 1, onEditText: { _ in }, onShortcut: { _, _ in false }, onStatus: { _ in })
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: grid, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let nodes = SemanticsSnapshot.build(from: try XCTUnwrap(ui.elements().first))
        XCTAssertTrue(nodes.contains { $0.label == "Budget, active cell B2, 2" }, "the sheet names itself and the active cell")
        let cells = nodes.filter { $0.label.count <= 3 && !$0.label.contains(",") }
        XCTAssertEqual(cells.map { $0.label }, ["A1", "B1", "A2", "B2", "B3", "B4"], "filled cells, row by row")
        XCTAssertEqual(cells.map { $0.value }, ["Item", "Cost", "Tea", "2", "3", "5"])
        XCTAssertEqual(cells[5].hint, "=SUM(B2:B3)", "a formula cell says its formula")
        XCTAssertEqual(cells.map { $0.isSelected ?? false }, [false, false, false, true, false, false])
        cells[2].tap?()
        XCTAssertEqual(c.active, CellAddress("A2")!)
    }
}
