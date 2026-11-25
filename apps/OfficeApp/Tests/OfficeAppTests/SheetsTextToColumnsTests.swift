import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-6b: Data → Text to Columns, model and dialog.
final class SheetsTextToColumnsTests: XCTestCase {
    private func controller() -> WorkbookController {
        let c = WorkbookController(); c.load(Workbook(sheets: [Worksheet(name: "Data")]))
        for (r, t) in ["a,b,c", "\"x,y\",2", "solo"].enumerated() { c.setInput(t, at: CellAddress(row: r, col: 0)) }
        return c
    }
    private let range = CellRange(top: 0, left: 0, bottom: 2, right: 0)
    private func row(_ c: WorkbookController, _ r: Int) -> [String] { (0 ... 2).map { c.input(CellAddress(row: r, col: $0)) } }

    func testSplitHonoursQualifierAndConsecutive() {
        var o = TextSplitOptions()
        XCTAssertEqual(TextSplitter.split("\"x,y\",2", o), ["x,y", "2"])
        o.comma = false; o.space = true
        XCTAssertEqual(TextSplitter.split("a  b", o), ["a", "", "b"])
        o.consecutiveAsOne = true
        XCTAssertEqual(TextSplitter.split("a  b", o), ["a", "b"])
    }

    func testSplitsColumnToTheRightAsOneUndoStep() {
        let c = controller()
        XCTAssertEqual(c.textToColumns(range, options: TextSplitOptions()).columns, 3)
        XCTAssertEqual(row(c, 0), ["a", "b", "c"])
        XCTAssertEqual(row(c, 1), ["x,y", "2", ""])
        XCTAssertEqual(row(c, 2), ["solo", "", ""])
        c.undo()
        XCTAssertEqual(row(c, 0), ["a,b,c", "", ""])
        XCTAssertEqual(row(c, 1), ["\"x,y\",2", "", ""])
    }

    func testProblemsChangeNothing() {
        let c = controller()
        c.setInput("keep", at: CellAddress(row: 0, col: 2))
        XCTAssertEqual(c.textToColumns(range, options: TextSplitOptions()).problem, .wouldOverwrite)
        XCTAssertEqual(row(c, 0), ["a,b,c", "", "keep"])
        var none = TextSplitOptions(); none.comma = false
        XCTAssertEqual(c.textToColumns(range, options: none).problem, .noSeparator)
        XCTAssertEqual(c.textToColumns(CellRange(top: 0, left: 0, bottom: 2, right: 1), options: TextSplitOptions()).problem, .oneColumn)
    }

    func testDialogSplitsAndCloses() {
        let c = controller()
        var closed = 0
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: TextToColumnsDialog(controller: c, range: range, onClose: { closed += 1 }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        ui.tap(id: "ttc-semicolon")
        ui.tap(id: "ttc-comma")        // comma off, semicolon on: nothing to split by comma any more
        ui.tap(text: "OK")
        XCTAssertEqual(closed, 1)
        XCTAssertEqual(row(c, 0), ["a,b,c", "", ""])
    }
}
