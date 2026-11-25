import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-3b: the Conditional Formatting dialog, driven headless: the Home tab opens it, the fields reach addConditionalFormat, a save keeps the rule.
final class SheetsConditionalFormatDialogTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        c.select(range: CellRange("B2:B5")!, active: CellAddress("B2")!)
        return c
    }

    private func dialog(_ c: WorkbookController, _ log: @escaping (String) -> Void) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                               home: ConditionalFormatDialog(controller: c, onClose: { log("closed") }), title: "T"), size: Size(1280, 800))
    }

    func testACellValueRuleIsAddedAsOneUndoStepAndSurvivesASave() throws {
        let c = controller()
        var log: [String] = []
        let ui = dialog(c) { log.append($0) }
        ui.state(ConditionalFormatDialogState.self)!.setVariant("greaterThan")
        ui.pump()
        XCTAssertTrue(ui.tap(id: "cf-value1"))
        ui.type("10")
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        let rules = c.conditionalRules(over: CellRange("B3")!)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].ranges, [CellRange("B2:B5")!])
        c.undo()
        XCTAssertTrue(c.conditionalRules(over: CellRange("B2:B5")!).isEmpty)
        c.redo()
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(again.conditionalRules(over: CellRange("B3")!).count, 1)
    }

    func testAColorScaleNeedsNoValuesAndABlankValueKeepsTheDialogOpen() {
        let c = controller()
        var log: [String] = []
        let ui = dialog(c) { log.append($0) }
        let state = ui.state(ConditionalFormatDialogState.self)!
        ui.press(.enter)
        XCTAssertTrue(log.isEmpty)
        XCTAssertEqual(state.message, CFProblem.needsValue.message)
        state.setKind("Color scale")
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        XCTAssertEqual(c.conditionalRules(over: CellRange("B2")!).count, 1)
    }

    func testTheKindChangesTheOffersAndTopNTakesACount() {
        let c = controller()
        let ui = dialog(c) { _ in }
        let state = ui.state(ConditionalFormatDialogState.self)!
        state.setKind("Top / bottom")
        XCTAssertEqual(state.variant, "top")
        ui.pump()
        XCTAssertTrue(ui.tap(id: "cf-value1"))
        ui.type("2")
        XCTAssertTrue(ui.tap(id: "cf-percent"))
        XCTAssertTrue(state.percent)
        ui.press(.enter)
        XCTAssertEqual(c.conditionalRules(over: CellRange("B2")!).count, 1)
    }

    func testClearRulesTakesEveryRuleOffTheSelection() {
        let c = controller()
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .duplicates(unique: false), look: DxfStyle(fill: 0xFFFFC7CE)), on: [CellRange("B2:B5")!]))
        let ui = dialog(c) { _ in }
        XCTAssertTrue(ui.has(text: "The selection has 1 rule already."))
        XCTAssertTrue(ui.tap(id: "cf-clear-rules"))
        XCTAssertTrue(c.conditionalRules(over: CellRange("B2:B5")!).isEmpty)
    }

    func testTheHomeTabOpensTheDialogInTheSheetsShell() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "T"), size: Size(1280, 800))
        XCTAssertTrue(ui.tap(text: "Conditional Formatting"))
        XCTAssertTrue(ui.tap(text: "New Rule…"))
        XCTAssertTrue(ui.has(text: "Format cells based on"))
        ui.press(.escape)
        XCTAssertFalse(ui.has(text: "Format cells based on"))
    }
}
