import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-3c: Edit Rule. A rule the form can show in full is rewritten in place (same rank, same Stop If True),
/// as one undo step, and a save keeps it and its neighbours; a rule with settings the form cannot show is refused.
final class SheetsEditRuleTests: XCTestCase {
    private var red: DxfStyle { var d = DxfStyle(); d.fill = 0xFFC7CE; return d }
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
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

    func testTheFormReadsBackWhatEachRuleHolds() throws {
        let c = controller()
        let rows = c.conditionalRuleRows()
        let e0 = try XCTUnwrap(c.conditionalRuleForEdit(rows[0]))
        guard case .cellIs(let op, let v, nil) = e0.spec.kind else { return XCTFail("\(e0.spec.kind)") }
        XCTAssertEqual([op, v], ["greaterThan", "5"])
        XCTAssertEqual(e0.applies.map(\.a1), ["A1:A9"])
        XCTAssertNotNil(e0.dxfId)
        XCTAssertFalse(e0.lookLocked)
        guard case .dataBar(0x638EC6) = try XCTUnwrap(c.conditionalRuleForEdit(rows[2])).spec.kind else { return XCTFail() }
    }

    func testEditingInPlaceKeepsRankAndStopAndUndoes() throws {
        let c = controller()
        c.setConditionalStopIfTrue(c.conditionalRuleRows()[0], true)
        let row = c.conditionalRuleRows()[0]
        XCTAssertNil(c.editConditionalRule(row, CFSpec(kind: .cellIs(op: "between", "2", "7")), applies: row.applies.isEmpty ? [] : [CellRange("A1:A9")!], keepLook: true))
        let after = c.conditionalRuleRows()
        XCTAssertEqual(after.map { $0.summary }, ["Cell value between 2 and 7", "Top 3", "Data bar"])
        XCTAssertEqual(after[0].stopIfTrue, true)
        XCTAssertEqual(after[0].priority, row.priority)
        let back = try reopen(c).conditionalRuleRows()
        XCTAssertEqual(back.map { $0.summary }, after.map { $0.summary })
        XCTAssertEqual(back.map { $0.applies }, ["A1:A9", "B1:B9", "C1:C9"])
        c.undo()
        XCTAssertEqual(c.conditionalRuleRows().map { $0.summary }, ["Cell value > 5", "Top 3", "Data bar"])
    }

    func testChangingAppliesToMovesTheRuleButKeepsItsRank() throws {
        let c = controller()
        let row = c.conditionalRuleRows()[1]
        XCTAssertNil(c.editConditionalRule(row, CFSpec(kind: .top(rank: 5, percent: true, bottom: true), look: red),
                                           applies: WorkbookController.cfRanges("D2:D20, F1")!, keepLook: false))
        let back = try reopen(c).conditionalRuleRows()
        XCTAssertEqual(back.map { $0.applies }, ["A1:A9", "D2:D20 F1", "C1:C9"])
        XCTAssertEqual(back[1].summary, "Bottom 5%")
        c.undo()
        XCTAssertEqual(c.conditionalRuleRows().map { $0.applies }, ["A1:A9", "B1:B9", "C1:C9"])
    }

    func testANewLookAddsADxfAndKeepLookReusesTheOld() throws {
        let c = controller()
        let row = c.conditionalRuleRows()[0]
        let old = try XCTUnwrap(c.conditionalRuleForEdit(row)?.dxfId)
        var green = DxfStyle(); green.fill = 0xC6EFCE
        XCTAssertNil(c.editConditionalRule(row, CFSpec(kind: .cellIs(op: "lessThan", "0", nil), look: green), applies: [CellRange("A1:A9")!], keepLook: false))
        let new = try XCTUnwrap(c.conditionalRuleForEdit(c.conditionalRuleRows()[0])?.dxfId)
        XCTAssertNotEqual(new, old)
        XCTAssertEqual(c.book.dxfs[new].fill, 0xC6EFCE)
    }

    func testARuleWithSettingsTheFormCannotShowIsRefused() {
        let c = WorkbookController()
        var s = Worksheet(name: "Data")
        s.keptElements.append(("conditionalFormatting", "<conditionalFormatting sqref=\"A1:A9\"><cfRule type=\"colorScale\" priority=\"1\"><colorScale><cfvo type=\"min\"/><cfvo type=\"max\"/><color theme=\"4\"/><color rgb=\"FF63BE7B\"/></colorScale></cfRule></conditionalFormatting>"))
        c.load(Workbook(sheets: [s]))
        let row = c.conditionalRuleRows()[0]
        XCTAssertNil(c.conditionalRuleForEdit(row))
        let before = c.sheet.keptElements[0].text
        XCTAssertEqual(c.editConditionalRule(row, CFSpec(kind: .colorScale([0xF8696B, 0x63BE7B])), applies: [CellRange("A1:A9")!], keepLook: true), .notEditable)
        XCTAssertEqual(c.sheet.keptElements[0].text, before)
    }

    func testBadAppliesToIsRefused() {
        XCTAssertNil(WorkbookController.cfRanges("A1:B2 nonsense"))
        XCTAssertEqual(WorkbookController.cfRanges("$A$1:$B$2,C3")?.map(\.a1), ["A1:B2", "C3"])
    }

    func testEditRuleButtonOpensTheFilledFormAndOKReachesTheController() throws {
        let c = controller()
        var closed = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: ManageRulesDialog(controller: c, onClose: { closed = true }), title: "T"), size: Size(1280, 800))
        XCTAssertTrue(ui.tap(text: "Cell value > 5"))
        XCTAssertTrue(ui.tap(id: "cf-rule-edit"))
        let form = try XCTUnwrap(ui.state(ConditionalFormatDialogState.self))
        XCTAssertEqual([form.kind, form.variant, form.fill], ["Cell value", "greaterThan", ConditionalFormatDialogState.keepLook])
        XCTAssertTrue(ui.has(text: "Edit Formatting Rule"))
        form.setVariant("lessThan")
        ui.pump()
        XCTAssertTrue(ui.tap(id: "cf-value1"))
        ui.press(.enter)
        XCTAssertEqual(c.conditionalRuleRows().map { $0.summary }, ["Cell value < 5", "Top 3", "Data bar"])
        XCTAssertTrue(ui.has(text: "Manage Rules"))
        XCTAssertFalse(closed)
        c.undo()
        XCTAssertEqual(c.conditionalRuleRows().first?.summary, "Cell value > 5")
    }

    /// For the Excel check: set STARLING_UI_CHECK_DIR and the edited book is written there.
    /// A: > 5 edited in place to between 2 and 7 with Stop If True; B: Top 3 moved to D1:D9 F1:F9 as Bottom 20%;
    /// C: the data bar turned into 2010 "3 stars"; E: a new rule edited to "cells with errors" in a new green look.
    func testSaveForExcel() throws {
        guard let dir = ProcessInfo.processInfo.environment["STARLING_UI_CHECK_DIR"] else { throw XCTSkip("no check folder") }
        let c = controller()
        for col in [0, 1, 2, 3, 4, 5] { for r in 0 ..< 9 { c.setInput(col == 4 && r % 3 == 0 ? "=1/0" : "\(r + 1)", at: CellAddress(row: r, col: col)) } }
        _ = c.addConditionalFormat(CFSpec(kind: .blanks(true), look: red), on: [CellRange("E1:E9")!])
        c.setConditionalStopIfTrue(c.conditionalRuleRows()[0], true)
        var rows = c.conditionalRuleRows()
        XCTAssertNil(c.editConditionalRule(rows[0], CFSpec(kind: .cellIs(op: "between", "2", "7")), applies: [CellRange("A1:A9")!], keepLook: true))
        rows = c.conditionalRuleRows()
        XCTAssertNil(c.editConditionalRule(rows[1], CFSpec(kind: .top(rank: 20, percent: true, bottom: true)), applies: WorkbookController.cfRanges("D1:D9 F1:F9")!, keepLook: true))
        rows = c.conditionalRuleRows()
        XCTAssertNil(c.editConditionalRule(rows.first { $0.summary == "Data bar" }!, CFSpec(kind: .iconSet("3Stars")), applies: [CellRange("C1:C9")!], keepLook: false))
        rows = c.conditionalRuleRows()
        var green = DxfStyle(); green.fill = 0xFFC6EFCE; green.color = 0xFF006100
        XCTAssertNil(c.editConditionalRule(rows.last!, CFSpec(kind: .errors(true), look: green), applies: [CellRange("E1:E9")!], keepLook: false))
        let back = try reopen(c).conditionalRuleRows()
        XCTAssertEqual(back.count, 4)
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/cf-edit-rule.xlsx"))
    }
}
