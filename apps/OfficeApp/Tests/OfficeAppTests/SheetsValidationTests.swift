// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsValidationTests: XCTestCase {
    private func sheet() -> WorkbookController {
        let c = WorkbookController()
        c.setInputs([(CellAddress("H1")!, "Red"), (CellAddress("H2")!, "Green"), (CellAddress("H3")!, "Blue")])
        c.sheet.keptElements = [("dataValidations", "<dataValidations count=\"4\">"
            + "<dataValidation type=\"list\" allowBlank=\"1\" showErrorMessage=\"1\" sqref=\"A1:A5\"><formula1>$H$1:$H$3</formula1></dataValidation>"
            + "<dataValidation type=\"list\" showErrorMessage=\"1\" showDropDown=\"1\" sqref=\"B1\"><formula1>\"Yes,No\"</formula1></dataValidation>"
            + "<dataValidation type=\"whole\" operator=\"between\" showErrorMessage=\"1\" error=\"1 to 10, please\" sqref=\"C1:C5\"><formula1>1</formula1><formula2>10</formula2></dataValidation>"
            + "<dataValidation type=\"custom\" showErrorMessage=\"1\" sqref=\"D1:D5\"><formula1>D1&gt;C1</formula1></dataValidation>"
            + "<dataValidation type=\"whole\" errorStyle=\"warning\" showInputMessage=\"1\" showErrorMessage=\"1\" errorTitle=\"Check\" error=\"Odd value\" promptTitle=\"Score\" prompt=\"1 to 5\" sqref=\"E1\"><formula1>1</formula1><formula2>5</formula2></dataValidation>"
            + "<dataValidation type=\"whole\" errorStyle=\"information\" showErrorMessage=\"1\" sqref=\"E2\"><formula1>1</formula1><formula2>5</formula2></dataValidation>"
            + "</dataValidations>")]
        return c
    }

    func testListsAndChoices() {
        let c = sheet()
        XCTAssertEqual(c.validationChoices(at: CellAddress("A3")!), ["Red", "Green", "Blue"])
        XCTAssertEqual(c.validationChoices(at: CellAddress("B1")!), ["Yes", "No"])
        XCTAssertEqual(c.validation(at: CellAddress("B1")!)?.arrow, false)      // showDropDown="1" hides it
        XCTAssertNil(c.validationRefusal(.text("green"), at: CellAddress("A2")!))
        XCTAssertNotNil(c.validationRefusal(.text("Purple"), at: CellAddress("A2")!))
        XCTAssertNil(c.validationRefusal(.empty, at: CellAddress("A2")!))         // allowBlank
        XCTAssertNotNil(c.validationRefusal(.empty, at: CellAddress("B1")!))
        XCTAssertNil(c.validationRefusal(.text("x"), at: CellAddress("E9")!))     // no rule there
    }

    func testAlertStylesAndPrompt() {
        let c = sheet()
        // Stop refuses; Warning and Information let the value in with the message.
        XCTAssertEqual(c.validationVerdict(.number(50), at: CellAddress("C1")!)?.refused, true)
        XCTAssertEqual(c.validationVerdict(.number(50), at: CellAddress("C1")!)?.message, "1 to 10, please")
        let w = c.validationVerdict(.number(9), at: CellAddress("E1")!)
        XCTAssertEqual(w?.refused, false)
        XCTAssertEqual(w?.message, "Check: Odd value")
        XCTAssertEqual(c.validationVerdict(.number(9), at: CellAddress("E2")!)?.refused, false)
        XCTAssertNil(c.validationVerdict(.number(3), at: CellAddress("E1")!))
        XCTAssertEqual(c.validationPrompt(at: CellAddress("E1")!)?.title, "Score")
        XCTAssertEqual(c.validationPrompt(at: CellAddress("E1")!)?.text, "1 to 5")
        XCTAssertNil(c.validationPrompt(at: CellAddress("E2")!))
    }

    func testNumbersAndCustom() {
        let c = sheet()
        XCTAssertNil(c.validationRefusal(.number(4), at: CellAddress("C2")!))
        XCTAssertEqual(c.validationRefusal(.number(4.5), at: CellAddress("C2")!), "1 to 10, please")
        XCTAssertEqual(c.validationRefusal(.number(11), at: CellAddress("C2")!), "1 to 10, please")
        c.setInputs([(CellAddress("C3")!, "5")])
        XCTAssertNil(c.validationRefusal(.number(6), at: CellAddress("D3")!))     // D3 > C3
        XCTAssertNotNil(c.validationRefusal(.number(2), at: CellAddress("D3")!))
        XCTAssertNil(c.sheet.cells[CellAddress("D3")!])                           // the probe left nothing behind
    }
}
