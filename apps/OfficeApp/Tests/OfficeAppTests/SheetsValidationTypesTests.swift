import XCTest
@testable import OfficeApp

/// X-DA-7: every kind of rule the dialog offers, set through the model, checked on entry, and kept by a save.
final class SheetsValidationTypesTests: XCTestCase {
    static func book() -> WorkbookController {
        let c = WorkbookController(); c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        func rule(_ r: String, _ type: String, _ op: String = "between", style: String = "stop") -> ValidationRule {
            var v = ValidationRule(ranges: [CellRange(r)!], type: type, op: op, formula1: nil, formula2: nil, allowBlank: true,
                                   refuses: true, arrow: true, errorTitle: "Not allowed", error: "Check the \(type) rule")
            v.errorStyle = style; v.promptTitle = type; v.prompt = "Enter a \(type)"
            return v
        }
        _ = c.setValidation(rule("A2:A6", "list", "between"), formula1: WorkbookController.listFormulaText(["Red", "Green", "Blue"]))
        _ = c.setValidation(rule("B2:B6", "whole"), formula1: "1", formula2: "10")
        _ = c.setValidation(rule("C2:C6", "decimal", "greaterThan", style: "warning"), formula1: "0.5")
        _ = c.setValidation(rule("D2:D6", "date", "greaterThanOrEqual"), formula1: "DATE(2024,1,1)")
        _ = c.setValidation(rule("E2:E6", "textLength", "lessThanOrEqual", style: "information"), formula1: "5")
        _ = c.setValidation(rule("F2:F6", "custom", "between"), formula1: "ISNUMBER(F2)")
        return c
    }
    private func at(_ s: String) -> CellAddress { CellAddress(s)! }

    func testEachKindAcceptsAndRefuses() {
        let c = Self.book()
        XCTAssertNil(c.validationRefusal(.text("Red"), at: at("A2")))
        XCTAssertNotNil(c.validationRefusal(.text("Pink"), at: at("A2")))
        XCTAssertNil(c.validationRefusal(.number(10), at: at("B2")))
        XCTAssertNotNil(c.validationRefusal(.number(11), at: at("B2")))
        XCTAssertNotNil(c.validationRefusal(.number(2.5), at: at("B2")), "a whole number rule refuses a fraction")
        XCTAssertNil(c.validationRefusal(.number(0.75), at: at("C2")))
        XCTAssertNotNil(c.validationRefusal(.number(0.5), at: at("C2")))
        XCTAssertNil(c.validationRefusal(.number(45292), at: at("D2")), "1 Jan 2024")
        XCTAssertNotNil(c.validationRefusal(.number(45291), at: at("D2")), "31 Dec 2023")
        XCTAssertNil(c.validationRefusal(.text("abcde"), at: at("E2")))
        XCTAssertNotNil(c.validationRefusal(.text("abcdef"), at: at("E2")))
        XCTAssertNil(c.validationRefusal(.number(3), at: at("F2")))
        XCTAssertNotNil(c.validationRefusal(.text("x"), at: at("F2")))
    }

    func testAlertStyleDecidesWhetherTheEntryIsRefused() {
        let c = Self.book()
        XCTAssertEqual(c.validationVerdict(.number(11), at: at("B3"))?.refused, true)
        XCTAssertEqual(c.validationVerdict(.number(0.1), at: at("C3"))?.refused, false, "a Warning lets it in")
        XCTAssertEqual(c.validationVerdict(.text("toolong"), at: at("E3"))?.refused, false, "Information lets it in")
        XCTAssertNil(c.validationVerdict(.number(5), at: at("B3")))
    }

    func testInputMessageAndSurvivesASave() throws {
        let c = Self.book()
        XCTAssertEqual(c.validationPrompt(at: at("D4"))?.text, "Enter a date")
        let again = WorkbookController(); again.load(try Xlsx.read(Xlsx.write(c.book)))
        for (cell, type) in [("A3", "list"), ("B3", "whole"), ("C3", "decimal"), ("D3", "date"), ("E3", "textLength"), ("F3", "custom")] {
            XCTAssertEqual(again.validation(at: at(cell))?.type, type)
        }
        XCTAssertEqual(again.validation(at: at("C3"))?.errorStyle, "warning")
        XCTAssertEqual(again.validation(at: at("A3"))?.error, "Check the list rule")
        XCTAssertNotNil(again.validationRefusal(.number(11), at: at("B3")))
    }
}
