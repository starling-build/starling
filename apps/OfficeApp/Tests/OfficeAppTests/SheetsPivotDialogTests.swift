import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Insert → PivotTable dialog, driven headless.
final class SheetsPivotDialogTests: XCTestCase {
    private func book() -> WorkbookController {
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Product", "Sales"], ["East", "Pen", "10"], ["West", "Pen", "20"], ["East", "Ink", "5"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), v)) } }
        wc.setInputs(inputs)
        return wc
    }
    private func dialog(_ c: WorkbookController, _ log: @escaping (String) -> Void = { _ in }) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: PivotDialog(controller: c, onClose: { log("closed") }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        return ui
    }

    func testRowsAndSumOnANewSheet() {
        let c = book(); var log: [String] = []
        let ui = dialog(c) { log.append($0) }
        XCTAssertTrue(ui.tap(id: "pivot-row-0")); XCTAssertTrue(ui.tap(id: "pivot-val-2"))
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        XCTAssertEqual(c.book.sheets.count, 2)
        XCTAssertEqual(c.sheet.value(CellAddress("A1")!), .text("Row Labels"))
        XCTAssertEqual(c.sheet.value(CellAddress("B2")!), .number(15))
        c.undo()
        XCTAssertEqual(c.book.sheets.count, 1)
    }

    func testNoValuesStaysOpenAndSaysWhy() {
        let c = book(); var log: [String] = []
        let ui = dialog(c) { log.append($0) }
        XCTAssertTrue(ui.tap(id: "pivot-row-0"))
        ui.press(.enter)
        XCTAssertEqual(log, [])
        XCTAssertEqual(c.book.sheets.count, 1)
        XCTAssertTrue(ui.texts().contains { $0.containsSubstring(PivotProblem.needsValues.message) })
    }
}
