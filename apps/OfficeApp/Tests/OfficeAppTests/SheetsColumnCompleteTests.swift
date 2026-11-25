import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsColumnCompleteTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }

    func testSuggestionComesFromTheUnbrokenRunOfText() {
        let c = WorkbookController(); c.load(Workbook(sheets: [Worksheet(name: "S")]))
        c.setInputs([(a("A1"), "Apple"), (a("A2"), "Banana"), (a("A3"), "apple"), (a("A4"), "5"), (a("A7"), "Avocado")])
        XCTAssertEqual(c.columnWords(at: a("A5")), ["Apple", "Banana"], "the number is skipped, the blank row ends the run, case-duplicates merge")
        XCTAssertEqual(c.columnSuggestion(for: "ap", at: a("A5")), "Apple")
        XCTAssertNil(c.columnSuggestion(for: "Apple", at: a("A5")), "nothing left to add")
        XCTAssertNil(c.columnSuggestion(for: "=ap", at: a("A5")))
        XCTAssertNil(c.columnSuggestion(for: "12", at: a("A5")))
        XCTAssertNil(c.columnSuggestion(for: "Av", at: a("A5")), "Avocado is past the blank row")
    }

    func testEnterTakesTheSuggestion() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"),
                              size: Size(1280, 800))
        let st = ui.state(SheetsShellState.self)!
        st.wb.setInputs([(a("A1"), "Apple")])
        st.wb.select(range: CellRange(a("A2"), a("A2")))
        ui.type("ap"); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertEqual(st.wb.input(a("A2")), "Apple")
    }
}
