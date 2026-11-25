import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsPrintChoiceUITests: XCTestCase {
    func testPanelOffersThreeChoicesAndReportsSelection() {
        var got: PrintWhat?
        var closed = false
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: PrintChoicePanel(sheetName: "Sheet1", selectionText: "B2:C3",
                                   onPrint: { got = $0 }, onClose: { closed = true }),
            title: "t"), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Active sheet (Sheet1)"))
        XCTAssertTrue(ui.has(text: "Entire workbook (every visible sheet)"))
        XCTAssertTrue(ui.has(text: "Selection (B2:C3)"))
        XCTAssertTrue(ui.tap(text: "Selection (B2:C3)"))
        XCTAssertTrue(ui.tap(text: "Print"))
        XCTAssertEqual(got, .selection)
        XCTAssertTrue(closed)
    }
}
