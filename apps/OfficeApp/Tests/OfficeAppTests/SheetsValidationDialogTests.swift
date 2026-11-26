import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-4b: the Data Validation dialog, driven headless — the Data tab opens it, the fields reach setValidation, a save keeps the result.
final class SheetsValidationDialogTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        c.select(range: CellRange("B2:B5")!, active: CellAddress("B2")!)
        return c
    }

    private func dialog(_ c: WorkbookController, _ log: @escaping (String) -> Void) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                               home: ValidationDialog(controller: c, onClose: { log("closed") }), title: "T"), size: Size(1280, 800))
    }

    private func enter(_ ui: WidgetTester, id: String, _ text: String) {
        ui.pump()
        XCTAssertTrue(ui.tap(id: id), id)
        ui.type(text)
    }

    func testAWholeNumberRuleIsSetAsOneUndoStepAndSurvivesASave() throws {
        let c = controller()
        var log: [String] = []
        let ui = dialog(c) { log.append($0) }
        let state = ui.state(ValidationDialogState.self)!
        state.setAllow("Whole number"); state.setOp("greaterThan")
        enter(ui, id: "validation-value1", "5")
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        let r = try XCTUnwrap(c.validationRules(over: CellRange("B3")!).first)
        XCTAssertEqual(r.type, "whole"); XCTAssertEqual(r.op, "greaterThan")
        XCTAssertEqual(r.ranges, [CellRange("B2:B5")!])
        c.undo()
        XCTAssertTrue(c.validationRules(over: CellRange("B2:B5")!).isEmpty)
        c.redo()
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(again.validationRules(over: CellRange("B3")!).first?.op, "greaterThan")
    }

    func testATypedListIsStoredAndTheDialogReopensFilledIn() throws {
        let c = controller()
        let ui = dialog(c) { _ in }
        ui.state(ValidationDialogState.self)!.setAllow("List")
        enter(ui, id: "validation-value1", "Yes,No")
        ui.press(.enter)
        XCTAssertEqual(c.validationChoices(at: CellAddress("B3")!) ?? [], ["Yes", "No"])
        let ui2 = dialog(c) { _ in }
        XCTAssertEqual(ui2.state(ValidationDialogState.self)?.allow, "List")
    }

    func testAnInvalidValueKeepsTheDialogOpenWithAMessage() {
        let c = controller()
        var log: [String] = []
        let ui = dialog(c) { log.append($0) }
        ui.state(ValidationDialogState.self)!.setAllow("Whole number")
        ui.press(.enter)
        XCTAssertEqual(log, [])
        XCTAssertFalse((ui.state(ValidationDialogState.self)?.message ?? "").isEmpty)
        XCTAssertTrue(c.validationRules(over: CellRange("B2:B5")!).isEmpty)
    }

    func testInputMessageAndErrorAlertTabsReachTheRule() throws {
        let c = controller()
        let ui = dialog(c) { _ in }
        let state = ui.state(ValidationDialogState.self)!
        state.setAllow("Text length"); state.setOp("lessThan")
        enter(ui, id: "validation-value1", "10")
        XCTAssertTrue(ui.tap(text: "Input Message"))
        enter(ui, id: "validation-prompt-title", "Hint")
        XCTAssertTrue(ui.tap(text: "Error Alert"))
        enter(ui, id: "validation-error-title", "Too long")
        state.setState { }
        ui.press(.enter)
        let r = try XCTUnwrap(c.validationRules(over: CellRange("B2")!).first)
        XCTAssertEqual(r.promptTitle, "Hint")
        XCTAssertEqual(r.errorTitle, "Too long")
        XCTAssertEqual(r.type, "textLength")
    }

    func testAnyValueWithOKClearsAndClearAllEmptiesTheForm() {
        let c = controller()
        let r = ValidationRule(ranges: [CellRange("B2:B5")!], type: "whole", op: "between", formula1: nil, formula2: nil,
                               allowBlank: true, refuses: true, arrow: true, errorTitle: nil, error: nil)
        XCTAssertNil(c.setValidation(r, formula1: "1", formula2: "9"))
        let ui = dialog(c) { _ in }
        XCTAssertEqual(ui.state(ValidationDialogState.self)?.allow, "Whole number")
        XCTAssertTrue(ui.tap(id: "validation-clear-all"))
        XCTAssertEqual(ui.state(ValidationDialogState.self)?.allow, "Any value")
        ui.press(.enter)
        XCTAssertTrue(c.validationRules(over: CellRange("B2:B5")!).isEmpty)
    }

    func testTheDataTabOpensTheDialogInTheSheetsShell() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "T"), size: Size(2000, 800))
        XCTAssertTrue(ui.tap(text: "Data"))
        XCTAssertTrue(ui.tap(text: "Data Validation"))
        XCTAssertTrue(ui.has(text: "Input Message"))
        ui.press(.escape)
        XCTAssertFalse(ui.has(text: "Input Message"))
    }
}
