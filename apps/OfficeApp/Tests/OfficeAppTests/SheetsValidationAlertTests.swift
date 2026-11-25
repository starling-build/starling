import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-7b: the error alert as a dialog (Stop, Warning, Information) and Circle Invalid Data.
final class SheetsValidationAlertTests: XCTestCase {
    private func controller(style: String = "stop", alert: Bool = true) -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        let r = ValidationRule(ranges: [CellRange("A1:A5")!], type: "whole", op: "between", formula1: nil, formula2: nil,
                               allowBlank: true, refuses: alert, arrow: true, errorTitle: "Oops", error: "One to nine only",
                               errorStyle: style)
        XCTAssertNil(c.setValidation(r, formula1: "1", formula2: "9"))
        return c
    }

    private func dialog(_ style: String, _ log: @escaping (ValidationChoice) -> Void) -> WidgetTester {
        let a = ValidationAlert(style: style, title: "Oops", text: "One to nine only")
        return WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                      home: ValidationAlertDialog(alert: a, onChoice: log), title: "T"), size: Size(1280, 800))
    }

    func testTheAlertCarriesTheRulesTitleAndText() {
        let c = controller()
        let a = c.validationAlert(.number(50), at: CellAddress("A1")!)
        XCTAssertEqual(a?.title, "Oops"); XCTAssertEqual(a?.text, "One to nine only"); XCTAssertEqual(a?.style, "stop")
        XCTAssertNil(c.validationAlert(.number(5), at: CellAddress("A1")!))
    }

    func testStopOffersRetryAndCancel() {
        var got: [ValidationChoice] = []
        let ui = dialog("stop") { got.append($0) }
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertTrue(ui.has(text: "Retry")); XCTAssertTrue(ui.has(text: "Cancel")); XCTAssertFalse(ui.has(text: "Yes"))
        ui.tap(text: "Retry"); ui.tap(text: "Cancel")
        XCTAssertEqual(got, [.retry, .cancel])
    }

    func testWarningAsksYesNoCancel() {
        var got: [ValidationChoice] = []
        let ui = dialog("warning") { got.append($0) }
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertTrue(ui.has(text: "Do you want to continue?"))
        ui.tap(text: "Yes"); ui.tap(text: "No"); ui.tap(text: "Cancel")
        XCTAssertEqual(got, [.accept, .retry, .cancel])
    }

    func testInformationOffersOKAndCancel() {
        var got: [ValidationChoice] = []
        let ui = dialog("information") { got.append($0) }
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertFalse(ui.has(text: "Retry"))
        ui.tap(text: "OK"); ui.tap(text: "Cancel")
        XCTAssertEqual(got, [.accept, .cancel])
    }

    func testCircleInvalidDataFindsBreakersEvenWithTheAlertOffAndClears() {
        let c = controller(alert: false)
        c.setInputs([(CellAddress("A1")!, "5"), (CellAddress("A2")!, "50"), (CellAddress("A3")!, "abc"), (CellAddress("B1")!, "99")])
        XCTAssertEqual(c.invalidCells(), [CellAddress("A2")!, CellAddress("A3")!])
        XCTAssertFalse(c.circlesOn)
        XCTAssertEqual(c.circleInvalidData(), 2)
        XCTAssertTrue(c.circlesOn)
        c.setInputs([(CellAddress("A2")!, "4")])
        XCTAssertEqual(c.invalidCells(), [CellAddress("A3")!])
        c.clearValidationCircles()
        XCTAssertFalse(c.circlesOn)
    }
}
