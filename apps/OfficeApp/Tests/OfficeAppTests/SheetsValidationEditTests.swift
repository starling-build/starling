import XCTest
@testable import OfficeApp

/// X-DA-4: setting and clearing data validation, each one undo step, and what a save keeps.
final class SheetsValidationEditTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        return c
    }
    private func rule(_ ranges: String, type: String = "whole", op: String = "between") -> ValidationRule {
        ValidationRule(ranges: ranges.split(separator: " ").compactMap { CellRange(String($0)) }, type: type, op: op,
                       formula1: nil, formula2: nil, allowBlank: true, refuses: true, arrow: true, errorTitle: "Oops", error: "Between 1 and 9 only")
    }
    private func xml(_ c: WorkbookController) -> String { c.sheet.keptElements.first { $0.name == "dataValidations" }?.text ?? "" }

    func testSetAListAndTheEntryIsRefused() {
        let c = controller()
        var r = rule("B2:B5", type: "list")
        r.formula1 = nil
        XCTAssertEqual(c.setValidation(r, formula1: WorkbookController.listFormulaText(["Yes", "No"])), nil)
        XCTAssertEqual(c.validationChoices(at: CellAddress("B3")!) ?? [], ["Yes", "No"])
        XCTAssertNotNil(c.validationRefusal(.text("Maybe"), at: CellAddress("B3")!))
        XCTAssertNil(c.validationRefusal(.text("Yes"), at: CellAddress("B3")!))
        XCTAssertNil(c.validationRefusal(.text("Maybe"), at: CellAddress("C3")!), "outside the range")
    }

    func testRefusesWhatCannotApply() {
        let c = controller()
        XCTAssertEqual(c.setValidation(rule(""), formula1: "1"), .noCells)
        XCTAssertEqual(c.setValidation(rule("A1"), formula1: nil), .needsValue)
        XCTAssertEqual(c.setValidation(rule("A1"), formula1: "1"), .needsValue, "between needs two values")
        XCTAssertEqual(c.setValidation(rule("A1"), formula1: "1", formula2: "(("), .badFormula)
        XCTAssertEqual(xml(c), "", "a refused rule changes nothing")
    }

    func testANewRuleTakesItsCellsOutOfTheOldOneAndUndoPutsThemBack() {
        let c = controller()
        XCTAssertNil(c.setValidation(rule("A1:A10"), formula1: "1", formula2: "9"))
        let before = xml(c)
        XCTAssertNil(c.setValidation(rule("A4:A5", op: "greaterThan"), formula1: "100"))
        XCTAssertEqual(c.validationRules.count, 2, "the old rule keeps one entry over the cells above and below")
        XCTAssertEqual(c.validationRules.first { $0.op == "between" }?.ranges.count, 2)
        XCTAssertEqual(c.validation(at: CellAddress("A4")!)?.op, "greaterThan")
        XCTAssertEqual(c.validation(at: CellAddress("A3")!)?.op, "between")
        XCTAssertEqual(c.validation(at: CellAddress("A6")!)?.op, "between")
        c.undo()
        XCTAssertEqual(xml(c), before)
    }

    func testClearTakesTheRuleAwayAndTheElementWhenNoneIsLeft() {
        let c = controller()
        XCTAssertNil(c.setValidation(rule("A1:B2"), formula1: "1", formula2: "9"))
        c.clearValidation(on: [CellRange("A1")!])
        XCTAssertNil(c.validation(at: CellAddress("A1")!)); XCTAssertNotNil(c.validation(at: CellAddress("B2")!))
        c.clearValidation(on: [CellRange("A1:B2")!])
        XCTAssertEqual(xml(c), "")
        c.undo(); XCTAssertNotNil(c.validation(at: CellAddress("B2")!))
    }

    func testRoundTripKeepsTheNewRuleAndAnUntouchedOne() throws {
        let c = controller()
        c.sheet.keptElements.append(("dataValidations", "<dataValidations count=\"1\"><dataValidation type=\"textLength\" operator=\"lessThan\" imeMode=\"hiragana\" allowBlank=\"1\" sqref=\"D1:D3\"><formula1>5</formula1></dataValidation></dataValidations>"))
        XCTAssertNil(c.setValidation(rule("B1:B3", type: "decimal"), formula1: "0", formula2: "1"))
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(again.validationRules.count, 2)
        XCTAssertEqual(again.validation(at: CellAddress("B2")!)?.type, "decimal")
        XCTAssertEqual(again.validation(at: CellAddress("D2")!)?.type, "textLength")
        XCTAssertTrue(xml(again).containsSubstring("imeMode=\"hiragana\""), "an attribute we do not model survives")
    }

    func testARealFileKeepsItsRulesWhenOneIsAdded() throws {
        let path = "/data/corpus-cache/test/corpus/xlsx/books/DataValidations-49244.xlsx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("corpus file not in the cache") }
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: URL(fileURLWithPath: path))))
        let rules = c.validationRules
        XCTAssertFalse(rules.isEmpty)
        XCTAssertNil(c.setValidation(rule("Z90:Z99"), formula1: "1", formula2: "9"))
        let again = WorkbookController()
        again.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertEqual(again.validationRules.count, rules.count + 1)
        for r in rules { XCTAssertEqual(again.validation(at: r.origin)?.type, r.type) }
    }
}
