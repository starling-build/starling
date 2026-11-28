import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-FM-3: Format Cells > Font > Superscript and Subscript (Excel's Effects).
/// The two are exclusive, and a script set here survives a save.
final class SheetsScriptEffectTests: XCTestCase {
    private func dialog(_ applied: @escaping (CellFormatEdit) -> Void) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: FormatCellsDialog(start: CellFormatEdit.Values(.plain), onApply: applied, onClose: {}), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        return ui
    }

    func testSuperscriptThenSubscriptLeavesOnlySubscript() {
        var got: CellFormatEdit?
        let ui = dialog { got = $0 }
        XCTAssertTrue(ui.tap(text: "Font"))
        XCTAssertTrue(ui.tap(id: "fc-superscript")); ui.pump()
        XCTAssertTrue(ui.tap(id: "fc-subscript")); ui.pump()
        ui.press(.enter)
        XCTAssertEqual(got?.script, .set(-1))
        var s = CellStyle()
        got?.apply(to: &s)
        XCTAssertEqual(s.script, -1)
    }

    func testUntickingSuperscriptClearsIt() {
        var got: CellFormatEdit?
        let ui = dialog { got = $0 }
        XCTAssertTrue(ui.tap(text: "Font"))
        XCTAssertTrue(ui.tap(id: "fc-superscript")); ui.pump()
        XCTAssertTrue(ui.tap(id: "fc-superscript")); ui.pump()
        ui.press(.enter)
        XCTAssertEqual(got?.script ?? .keep, CellFieldEdit<Int>.keep)
    }

    func testAScriptSetHereSurvivesASave() throws {
        let c = WorkbookController()
        c.setInput("m2", at: CellAddress("A1")!)
        c.setInput("H2O", at: CellAddress("A2")!)
        c.select(range: CellRange("A1:A1")!); c.setStyle { $0.script = 1 }
        c.select(range: CellRange("A2:A2")!); c.setStyle { $0.script = -1 }
        let back = WorkbookController()
        back.load(try Workbook.open(try Xlsx.write(c.book), name: "t.xlsx"))
        XCTAssertEqual(back.style(at: CellAddress("A1")!).script, 1)
        XCTAssertEqual(back.style(at: CellAddress("A2")!).script, -1)
    }
}
