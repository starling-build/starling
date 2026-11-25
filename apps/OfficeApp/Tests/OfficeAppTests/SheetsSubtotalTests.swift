import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-6c: Data → Subtotal, model and dialog.
final class SheetsSubtotalTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController(); c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let rows = [["Region", "Sales"], ["East", "10"], ["East", "20"], ["West", "5"], ["West", "7"], ["West", "8"]]
        for (r, row) in rows.enumerated() { for (k, t) in row.enumerated() { c.setInput(t, at: CellAddress(row: r, col: k)) } }
        c.setInput("=SUM(B2:B6)", at: CellAddress(row: 0, col: 3))
        return c
    }
    private let range = CellRange(top: 0, left: 0, bottom: 5, right: 1)
    private func col(_ c: WorkbookController, _ k: Int, _ n: Int = 9) -> [String] {
        (0 ..< n).map { r in let a = CellAddress(row: r, col: k); return c.input(a) }
    }
    private func shown(_ c: WorkbookController, _ r: Int, _ k: Int) -> String {
        let a = CellAddress(row: r, col: k)
        return NumberFormat.display(c.sheet.value(a), "General", width: 255).text
    }

    func testAddsGroupTotalsAndGrandTotalWithOutline() {
        let c = controller()
        XCTAssertEqual(c.addSubtotals(range, groupBy: 0, function: .sum, columns: [1]).groups, 2)
        XCTAssertEqual(col(c, 0), ["Region", "East", "East", "East Total", "West", "West", "West", "West Total", "Grand Total"])
        XCTAssertEqual(c.input(CellAddress(row: 3, col: 1)), "=SUBTOTAL(9,B2:B3)")
        XCTAssertEqual(c.input(CellAddress(row: 7, col: 1)), "=SUBTOTAL(9,B5:B7)")
        XCTAssertEqual(c.input(CellAddress(row: 8, col: 1)), "=SUBTOTAL(9,B2:B8)")
        XCTAssertEqual(shown(c, 3, 1), "30"); XCTAssertEqual(shown(c, 7, 1), "20"); XCTAssertEqual(shown(c, 8, 1), "50")
        XCTAssertEqual(c.input(CellAddress(row: 0, col: 3)), "=SUM(B2:B7)", "a formula over the data follows the rows that moved, as after any row insert")
        XCTAssertEqual(c.sheet.outlineLevel(.rows, 1), 1)
        XCTAssertEqual(c.sheet.outlineLevel(.rows, 3), 0)
        XCTAssertEqual(c.sheet.outlineLevel(.rows, 8), 0)
    }

    func testOneUndoStep() {
        let c = controller()
        _ = c.addSubtotals(range, groupBy: 0, function: .average, columns: [1])
        XCTAssertEqual(c.input(CellAddress(row: 3, col: 1)), "=SUBTOTAL(1,B2:B3)")
        c.undo()
        XCTAssertEqual(col(c, 0), ["Region", "East", "East", "West", "West", "West", "", "", ""])
        XCTAssertEqual(c.sheet.outlineLevel(.rows, 1), 0)
        XCTAssertEqual(c.input(CellAddress(row: 0, col: 3)), "=SUM(B2:B6)")
    }

    func testRunningAgainReplacesAndRemoveAllRestores() {
        let c = controller()
        _ = c.addSubtotals(range, groupBy: 0, function: .sum, columns: [1])
        let again = CellRange(top: 0, left: 0, bottom: 8, right: 1)
        XCTAssertEqual(c.addSubtotals(again, groupBy: 0, function: .max, columns: [1]).groups, 2)
        XCTAssertEqual(col(c, 0, 10).filter { $0.hasSuffix("Total") }.count, 3, "still three total rows, not six")
        XCTAssertEqual(c.input(CellAddress(row: 3, col: 1)), "=SUBTOTAL(4,B2:B3)")
        XCTAssertEqual(c.removeSubtotals(CellRange(top: 0, left: 0, bottom: 8, right: 1), groupBy: 0), 3)
        XCTAssertEqual(col(c, 0), ["Region", "East", "East", "West", "West", "West", "", "", ""])
        XCTAssertEqual(c.sheet.outlineLevel(.rows, 1), 0)
        XCTAssertEqual(c.input(CellAddress(row: 0, col: 3)), "=SUM(B2:B6)")
    }

    func testProblemsChangeNothing() {
        let c = controller()
        XCTAssertEqual(c.addSubtotals(range, groupBy: 0, function: .sum, columns: []).problem, .noColumns)
        XCTAssertEqual(c.addSubtotals(range, groupBy: 5, function: .sum, columns: [1]).problem, .columnOutside)
        XCTAssertEqual(c.addSubtotals(CellRange(top: 0, left: 0, bottom: 0, right: 1), groupBy: 0, function: .sum, columns: [1]).problem, .nothingToTotal)
        XCTAssertEqual(col(c, 0), ["Region", "East", "East", "West", "West", "West", "", "", ""])
        c.sheet.keptElements = [("sheetProtection", "<sheetProtection sheet=\"1\"/>")]
        let out = c.addSubtotals(range, groupBy: 0, function: .sum, columns: [1])
        XCTAssertNil(out.groups)
        XCTAssertEqual(col(c, 0), ["Region", "East", "East", "West", "West", "West", "", "", ""])
    }

    func testDialogAddsAndRemoves() {
        let c = controller()
        var closed = 0
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SubtotalDialog(controller: c, range: range, onClose: { closed += 1 }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        ui.tap(text: "OK")
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(c.input(CellAddress(row: 8, col: 0)), "Grand Total")
    }
}
