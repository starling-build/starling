import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-CL-1: Paste Special's other choices (Comments and Notes, Validation, Formulas and number formats,
/// All using Source theme, All merging conditional formats) and Paste Link, each one undo step.
final class SheetsPasteSpecialMoreTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }
    private func book() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        c.setInput("2", at: a("A1")); c.setInput("=A1*10", at: a("B1"))
        c.setInput("5", at: a("A2"))
        return c
    }
    private func copyA1B2(_ c: WorkbookController) -> WorkbookController.Clip {
        c.select(range: CellRange("A1:B2")!, active: a("A1"))
        return c.clip(cut: false, text: "")
    }
    private func go(_ c: WorkbookController, _ clip: WorkbookController.Clip, to s: String, _ how: PasteSpecial) {
        c.select(a(s)); c.pasteSpecial(clip, how)
    }
    private func roundTrip(_ c: WorkbookController) throws -> WorkbookController {
        let c2 = WorkbookController(); c2.load(try Xlsx.read(try Xlsx.write(c.book))); return c2
    }

    func testCommentsAndNotesTakeOnlyTheNotes() throws {
        let c = book()
        c.setNote("check this", at: a("A1"))
        c.setNote("old", at: a("E2"))
        c.setInput("7", at: a("D1"))
        let clip = copyA1B2(c)
        go(c, clip, to: "D1", PasteSpecial(what: .comments))
        XCTAssertEqual(c.note(at: a("D1"))?.body, "check this")
        XCTAssertNil(c.note(at: a("E2")), "the pasted cells take the copied cells' notes, none included")
        XCTAssertEqual(c.sheet.cells[a("D1")]?.value, .number(7), "values stay")
        XCTAssertNil(c.sheet.cells[a("E1")], "nothing else is pasted")
        XCTAssertEqual(try roundTrip(c).note(at: a("D1"))?.body, "check this")
        c.undo()
        XCTAssertNil(c.note(at: a("D1")))
        XCTAssertEqual(c.note(at: a("E2"))?.body, "old")
    }

    func testCommentsWithSkipBlanksKeepTheOtherNotes() {
        let c = book()
        c.setNote("check this", at: a("A1"))
        c.setNote("old", at: a("E2"))
        let clip = copyA1B2(c)
        go(c, clip, to: "D1", PasteSpecial(what: .comments, skipBlanks: true))
        XCTAssertEqual(c.note(at: a("D1"))?.body, "check this")
        XCTAssertEqual(c.note(at: a("E2"))?.body, "old")
    }

    func testValidationMovesTheRuleAndReadsItFromTheNewCells() throws {
        let c = book()
        // A2:A3 must exceed the cell above: relative, so the paste must keep "the cell above".
        let r = ValidationRule(ranges: [CellRange("A1:A3")!], type: "custom", op: "between", formula1: nil, formula2: nil,
                               allowBlank: true, refuses: true, arrow: true, errorTitle: nil, error: nil)
        XCTAssertNil(c.setValidation(r, formula1: "A1>B1"))
        c.select(range: CellRange("A2:A3")!, active: a("A2"))
        let clip = c.clip(cut: false, text: "")
        go(c, clip, to: "D5", PasteSpecial(what: .validation))
        let rules = c.validationRules(over: CellRange("D5:D6")!)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.ranges, [CellRange("D5:D6")!])
        XCTAssertEqual(rules.first?.formula1.map(Formula.print), "D5>E5", "the rule's first cell tests its own row")
        XCTAssertNil(c.sheet.cells[a("D5")], "values are not pasted")
        XCTAssertEqual(c.validationRules(over: CellRange("A1:A3")!).first?.ranges, [CellRange("A1:A3")!], "the copied rule stays")
        XCTAssertEqual(try roundTrip(c).validationRules(over: CellRange("D5")!).first?.ranges, [CellRange("D5:D6")!])
        c.undo()
        XCTAssertTrue(c.validationRules(over: CellRange("D5:D6")!).isEmpty)
    }

    func testValidationReplacesTheRuleThere() {
        let c = book()
        let old = ValidationRule(ranges: [CellRange("D1:D9")!], type: "whole", op: "between", formula1: nil, formula2: nil,
                                 allowBlank: true, refuses: true, arrow: true, errorTitle: nil, error: nil)
        XCTAssertNil(c.setValidation(old, formula1: "1", formula2: "9"))
        let clip = copyA1B2(c)   // no rule there
        go(c, clip, to: "D1", PasteSpecial(what: .validation))
        XCTAssertTrue(c.validationRules(over: CellRange("D1:D2")!).isEmpty)
        XCTAssertEqual(c.validationRules(over: CellRange("D3")!).first?.ranges, [CellRange("D3:D9")!])
    }

    func testFormulasAndNumberFormats() {
        let c = book()
        c.select(a("B1")); c.formatCells(CellFormatEdit(bold: .set(true)))
        c.select(a("B1")); c.formatCells(CellFormatEdit(numberFormat: .set("0.00%")))
        let clip = copyA1B2(c)
        go(c, clip, to: "D1", PasteSpecial(what: .formulasAndNumberFormats))
        XCTAssertEqual(c.sheet.cells[a("E1")]?.formula.map(Formula.text), "=D1*10")
        XCTAssertEqual(c.style(at: a("E1")).numberFormat, "0.00%")
        XCTAssertFalse(c.style(at: a("E1")).bold, "only the number format comes along")
    }

    func testAllUsingSourceThemeIsAll() {
        let c = book()
        let clip = copyA1B2(c)
        go(c, clip, to: "D1", PasteSpecial(what: .allUsingSourceTheme))
        XCTAssertEqual(c.sheet.cells[a("E1")]?.formula.map(Formula.text), "=D1*10")
        XCTAssertEqual(c.sheet.cells[a("D2")]?.value, .number(5))
    }

    func testAllMergingConditionalFormatsAddsTheRulesAfterTheCellsOwn() throws {
        let c = book()
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .expression("A1>1"), look: DxfStyle(fill: 0xFFFFC7CE)), on: [CellRange("A1:A2")!]))
        XCTAssertNil(c.addConditionalFormat(CFSpec(kind: .expression("D1<0"), look: DxfStyle(fill: 0xFFC6EFCE)), on: [CellRange("D1:D9")!]))
        let clip = copyA1B2(c)
        go(c, clip, to: "D1", PasteSpecial(what: .allMergingConditionalFormats))
        XCTAssertEqual(c.sheet.cells[a("E1")]?.formula.map(Formula.text), "=D1*10", "pasted as All")
        let rules = c.conditionalRules(over: CellRange("D1")!)
        XCTAssertEqual(rules.count, 2, "the cell's own rule and the copied one")
        XCTAssertEqual(rules.first?.ranges, [CellRange("D1:D9")!], "the cell's own rule still comes first")
        XCTAssertEqual(rules.last?.ranges, [CellRange("D1:D2")!])
        let priorities = rules.map(\.priority)
        XCTAssertEqual(Set(priorities).count, priorities.count)
        XCTAssertEqual(try roundTrip(c).conditionalRules(over: CellRange("D2")!).count, 2)
        c.undo()
        XCTAssertEqual(c.conditionalRules(over: CellRange("D1")!).count, 1)
        XCTAssertNil(c.sheet.cells[a("E1")])
    }

    func testPasteLinkFromTheDialog() {
        let c = book()
        let clip = copyA1B2(c)
        var how = PasteSpecial(); how.link = true
        go(c, clip, to: "D1", how)
        XCTAssertEqual(c.sheet.cells[a("E1")]?.formula.map(Formula.text), "=B1")
        XCTAssertEqual(c.sheet.cells[a("E1")]?.value, .number(20))
    }
}

/// The dialog shows Excel's twelve Paste choices in two columns, without overflow, and Paste Link.
final class SheetsPasteSpecialDialogLayoutTests: XCTestCase {
    func testEveryChoiceFitsAndPasteLinkApplies() {
        var applied: [PasteSpecial] = []
        var closed = 0
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: PasteSpecialDialog(onApply: { applied.append($0) }, onClose: { closed += 1 }), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        ui.pump()
        for (name, _) in PasteSpecialDialog.whats { XCTAssertTrue(ui.has(id: "ps-what-\(name)"), name) }
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        XCTAssertTrue(ui.has(id: "dialog-middle"), "Paste Link is offered for All")
        ui.tap(id: "ps-what-Validation"); ui.pump()
        XCTAssertFalse(ui.has(id: "dialog-middle"), "and greyed (gone) for a choice it cannot link")
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        ui.tap(id: "ps-what-All"); ui.pump()
        ui.tap(id: "dialog-middle"); ui.pump()
        XCTAssertEqual(applied.first?.link, true)
        XCTAssertEqual(closed, 1)
    }

    /// In the Sheets window at the Mac driver's size: no overflow, and (SCREEN_MARKS_DIR) the marks a Mac script clicks.
    func testInTheShellAtTheDriverSize() {
        let size = Size(1440, 932)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"), size: size)
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        guard let shell = ui.state(SheetsShellState.self) else { return XCTFail("no shell") }
        shell.wb.onCommand?(.pasteSpecial)
        ui.pump()
        XCTAssertTrue(ui.has(id: "ps-what-All merging conditional formats"))
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        if let dir = ProcessInfo.processInfo.environment["SCREEN_MARKS_DIR"], !dir.isEmpty {
            let lines = ScreenMarks.lines(root: ui.elements().first, view: size)
            FileManager.default.createFile(atPath: dir + "/sheets-pastespecial-1440x932.txt", contents: Data((lines.joined(separator: "\n") + "\n").utf8))
        }
    }
}
