import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Format Cells > Font: the Font and Size boxes show what the cell draws in (not blank for a
/// default cell), and each check box in a row has its own column.
final class SheetsFormatFontTabTests: XCTestCase {
    private func dialog(_ start: CellFormatEdit.Values, _ applied: @escaping (CellFormatEdit) -> Void = { _ in }) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: FormatCellsDialog(start: start, onApply: applied, onClose: {}), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        return ui
    }

    func testADefaultCellStartsWithTheBookFontAndSize() {
        let c = WorkbookController()
        c.select(range: CellRange("B2:B2")!)
        let v = c.formatCellsStart
        XCTAssertEqual(v.fontName, c.book.fontName(CellStyle()))
        XCTAssertEqual(v.fontSize, 11)
        // Opening and pressing OK changes nothing.
        var got: CellFormatEdit?
        let ui = dialog(v) { got = $0 }
        XCTAssertTrue(ui.tap(text: "Font"))
        ui.press(.enter)
        XCTAssertEqual(got?.fontName ?? .keep, CellFieldEdit<String?>.keep)
        XCTAssertEqual(got?.fontSize ?? .keep, CellFieldEdit<Double?>.keep)
    }

    func testACellsOwnFontWins() {
        let c = WorkbookController()
        c.select(range: CellRange("A1:A1")!); c.setStyle { $0.fontName = "Arial"; $0.fontSize = 14 }
        XCTAssertEqual(c.formatCellsStart.fontName, "Arial")
        XCTAssertEqual(c.formatCellsStart.fontSize, 14)
    }

    func testEachCheckBoxHasItsOwnColumn() throws {
        let ui = dialog(CellFormatEdit.Values(.plain))
        XCTAssertTrue(ui.tap(text: "Font"))
        for (a, b) in [("Bold", "Italic"), ("Italic", "Underline"), ("Underline", "Strikethrough"), ("Superscript", "Subscript")] {
            let x0 = try XCTUnwrap(ui.centre(id: "fc-" + (a == "Strikethrough" ? "strike" : a.lowercased())))
            let x1 = try XCTUnwrap(ui.centre(id: "fc-" + (b == "Strikethrough" ? "strike" : b.lowercased())))
            XCTAssertEqual(x1.dx - x0.dx, 112, accuracy: 0.5, "\(a) -> \(b)")
        }
    }
}
