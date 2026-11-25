import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-CF-1: Manage Rules. Order by priority, delete, Stop If True; each one undo step; a save keeps them.
final class SheetsManageRulesTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        var red = DxfStyle(); red.fill = 0xFFC7CE
        _ = c.addConditionalFormat(CFSpec(kind: .cellIs(op: "greaterThan", "5", nil), look: red), on: [CellRange("A1:A9")!])
        _ = c.addConditionalFormat(CFSpec(kind: .top(rank: 3, percent: false, bottom: false), look: red), on: [CellRange("B1:B9")!])
        _ = c.addConditionalFormat(CFSpec(kind: .dataBar(0x638EC6)), on: [CellRange("C1:C9")!])
        return c
    }
    private func reopen(_ c: WorkbookController) throws -> WorkbookController {
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        return again
    }

    func testRowsListByPriorityInPlainWords() {
        let rows = controller().conditionalRuleRows()
        XCTAssertEqual(rows.map { $0.summary }, ["Cell value > 5", "Top 3", "Data bar"])
        XCTAssertEqual(rows.map { $0.applies }, ["A1:A9", "B1:B9", "C1:C9"])
    }

    func testMovingARuleDownSwapsOrderAndUndoes() throws {
        let c = controller()
        c.moveConditionalRule(c.conditionalRuleRows()[0], up: false)
        XCTAssertEqual(c.conditionalRuleRows().map { $0.summary }, ["Top 3", "Cell value > 5", "Data bar"])
        XCTAssertEqual(try reopen(c).conditionalRuleRows().map { $0.summary }, ["Top 3", "Cell value > 5", "Data bar"])
        c.undo()
        XCTAssertEqual(c.conditionalRuleRows().map { $0.summary }, ["Cell value > 5", "Top 3", "Data bar"])
        c.moveConditionalRule(c.conditionalRuleRows()[0], up: true)   // already first: nothing
        XCTAssertEqual(c.conditionalRuleRows().first?.summary, "Cell value > 5")
    }

    func testStopIfTrueToggleSurvivesASave() throws {
        let c = controller()
        c.setConditionalStopIfTrue(c.conditionalRuleRows()[1], true)
        XCTAssertEqual(try reopen(c).conditionalRuleRows().map { $0.stopIfTrue }, [false, true, false])
        c.setConditionalStopIfTrue(c.conditionalRuleRows()[1], false)
        XCTAssertEqual(c.conditionalRuleRows().map { $0.stopIfTrue }, [false, false, false])
    }

    func testDeleteRemovesOneRuleOnly() throws {
        let c = controller()
        c.deleteConditionalRule(c.conditionalRuleRows()[1])
        XCTAssertEqual(try reopen(c).conditionalRuleRows().map { $0.summary }, ["Cell value > 5", "Data bar"])
        c.undo()
        XCTAssertEqual(c.conditionalRuleRows().count, 3)
    }

    func testTheDialogButtonsReachTheController() throws {
        let c = controller()
        var closed = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: ManageRulesDialog(controller: c, onClose: { closed = true }), title: "T"), size: Size(1280, 800))
        XCTAssertTrue(ui.tap(text: "Top 3"))
        XCTAssertTrue(ui.tap(id: "cf-rule-up"))
        XCTAssertEqual(c.conditionalRuleRows().map { $0.summary }, ["Top 3", "Cell value > 5", "Data bar"])
        XCTAssertTrue(ui.tap(id: "cf-rule-stop"))
        XCTAssertEqual(c.conditionalRuleRows().first?.stopIfTrue, true)
        XCTAssertTrue(ui.tap(id: "cf-rule-delete"))
        XCTAssertEqual(c.conditionalRuleRows().count, 2)
        XCTAssertFalse(closed)
    }

    func testTheRibbonButtonOpensTheDialog() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"), size: Size(1280, 800))
        XCTAssertTrue(ui.tap(text: "Conditional Formatting"))
        XCTAssertTrue(ui.tap(text: "Manage Rules…"))
        ui.pump()
        XCTAssertNotNil(ui.state(ManageRulesDialogState.self))
    }

    /// For the Excel check: set STARLING_UI_CHECK_DIR and the book is written there.
    func testSaveForExcel() throws {
        guard let dir = ProcessInfo.processInfo.environment["STARLING_UI_CHECK_DIR"] else { throw XCTSkip("no check folder") }
        let c = controller()
        for r in 0 ..< 9 { for col in 0 ... 2 { c.setInput("\((r + 1) * (col + 1))", at: CellAddress(row: r, col: col)) } }
        c.moveConditionalRule(c.conditionalRuleRows()[2], up: true)
        c.setConditionalStopIfTrue(c.conditionalRuleRows()[0], true)
        c.deleteConditionalRule(c.conditionalRuleRows()[2])
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/cf-manage-rules.xlsx"))
    }
}
