import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
import OfficeText

/// X-FM-3: Excel's underline kinds (Single, Double, Single Accounting, Double Accounting): the Font tab's
/// Underline list and Home's Underline split set them, and a file keeps each as the font's `u val`.
final class SheetsDoubleUnderlineTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }
    private func roundTrip(_ c: WorkbookController) throws -> WorkbookController {
        let c2 = WorkbookController(); c2.load(try Xlsx.read(try Xlsx.write(c.book))); return c2
    }

    func testTheKindRoundTripsAndUnderlineOffClearsIt() {
        var s = CellStyle()
        XCTAssertNil(s.underlineKind)
        for k in ["single", "double", "singleAccounting", "doubleAccounting"] {
            s.underlineKind = k
            XCTAssertEqual(s.underlineKind, k)
            XCTAssertTrue(s.underline)
        }
        s.underlineKind = "double"
        s.underline = false
        XCTAssertNil(s.underlineKind)
        XCTAssertFalse(s.doubleUnderline)
        s.underline = true
        XCTAssertEqual(s.underlineKind, "single", "Ctrl+U after off is a plain underline")
    }

    func testEachKindIsSavedAsItsUValue() throws {
        let c = WorkbookController()
        let kinds = ["single", "double", "singleAccounting", "doubleAccounting"]
        for (i, k) in kinds.enumerated() {
            c.setInput("x", at: CellAddress(row: i, col: 0))
            c.select(CellAddress(row: i, col: 0)); c.setStyle { $0.underlineKind = k }
        }
        let entry = try XCTUnwrap(Zip.read(try Xlsx.write(c.book)).first { $0.name == "xl/styles.xml" })
        let styles = String(decoding: entry.data, as: UTF8.self)
        XCTAssertTrue(styles.containsSubstring("<u val=\"double\"/>"), styles)
        XCTAssertTrue(styles.containsSubstring("<u val=\"singleAccounting\"/>"))
        XCTAssertTrue(styles.containsSubstring("<u val=\"doubleAccounting\"/>"))
        let c2 = try roundTrip(c)
        for (i, k) in kinds.enumerated() { XCTAssertEqual(c2.style(at: CellAddress(row: i, col: 0)).underlineKind, k) }
    }

    func testTheDoubleUnderlineCommandTogglesAndSwitchesKind() {
        let c = WorkbookController()
        c.select(a("A1"))
        XCTAssertTrue(c.toggleUnderline("double"))
        XCTAssertEqual(c.style(at: a("A1")).underlineKind, "double")
        XCTAssertTrue(c.toggleUnderline("single"), "a single over a double switches, it does not take it off")
        XCTAssertEqual(c.style(at: a("A1")).underlineKind, "single")
        c.toggleUnderline("double")
        XCTAssertFalse(c.toggleUnderline("double"))
        XCTAssertNil(c.style(at: a("A1")).underlineKind)
        c.toggleUnderline("double")
        c.toggleStyle(\.underline)
        XCTAssertNil(c.style(at: a("A1")).underlineKind, "Ctrl+U takes a double underline off")
    }

    func testTheFontTabsUnderlineListSetsTheKind() throws {
        var got: CellFormatEdit?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: FormatCellsDialog(start: CellFormatEdit.Values(.plain), onApply: { got = $0 }, onClose: {}), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertTrue(ui.tap(text: "Font")); ui.pump()
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        XCTAssertTrue(ui.tap(id: "fc-underline")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Double Accounting")); ui.pump()
        ui.press(.enter); ui.pump()
        let edit = try XCTUnwrap(got)
        XCTAssertEqual(edit.underline, .set("doubleAccounting"))
        var s = CellStyle()
        edit.apply(to: &s)
        XCTAssertEqual(s.accounting, 2)
        XCTAssertTrue(s.underline)
    }

    /// Through Home's Underline split at the Mac driver's size; writes the open list's marks (SCREEN_MARKS_DIR).
    func testTheRibbonsUnderlineListDoublesTheCell() throws {
        let size = Size(1440, 932)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: size)
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        let wb = try XCTUnwrap(ui.state(SheetsShellState.self)).wb
        ui.pump()
        XCTAssertTrue(ui.tap(tip: "Underline Options")); ui.pump()
        XCTAssertEqual(ui.overflowingFlexes(), 0)
        if let dir = ProcessInfo.processInfo.environment["SCREEN_MARKS_DIR"], !dir.isEmpty {
            let lines = ScreenMarks.lines(root: ui.elements().first, view: size)
            FileManager.default.createFile(atPath: dir + "/sheets-underline-menu-1440x932.txt", contents: Data((lines.joined(separator: "\n") + "\n").utf8))
        }
        XCTAssertTrue(ui.tap(text: "Double Underline")); ui.pump()
        XCTAssertEqual(wb.style(at: a("A1")).underlineKind, "double")
        XCTAssertNil(ui.centre(ofText: "Double Underline"), "the list closed")
    }

    /// Excel's print (the underline lab, Calibri 11 and 20): single 1.2 / 2.28 pt under the baseline, 0.72 / 1.32 thick;
    /// a double's first rule 0.48 / 0.72 under it with a clear gap of one rule; accounting 3.0 / 5.4 under it,
    /// across the span given (a text cell's room) or under the text.
    func testTheRulesStandWhereExcelsDo() throws {
        let m = try XCTUnwrap(RichTextTheme.ruleMetrics("Calibri", bold: false, italic: false))
        func rects(_ size: Double, double: Bool = false, accounting: Bool = false, span: (Double, Double)? = nil) -> [Rect] {
            var s = GridTextStyle(family: "Calibri", size: size, color: 0xFF000000)
            s.underline = true; s.doubleUnderline = double; s.accounting = accounting
            s.rule = [m.up, m.ut, m.sp, m.st]
            return GridTextStyle.underlineRects(s, glyph: 100, descent: size * 0.2686, left: 10, width: 30, span: span)
        }
        let single = rects(11)
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0].top - 100, 1.2, accuracy: 0.06)
        XCTAssertEqual(single[0].height, 0.72, accuracy: 0.01)
        XCTAssertEqual(rects(20)[0].top - 100, 2.28, accuracy: 0.06)
        let double = rects(11, double: true)
        XCTAssertEqual(double.count, 2)
        XCTAssertEqual(double[0].top - 100, 0.48, accuracy: 0.06)
        XCTAssertEqual(double[1].top - double[0].bottom, double[0].height, accuracy: 0.001, "a clear gap of one rule")
        let acc = rects(11, accounting: true, span: (5, 60))
        XCTAssertEqual(acc[0].top - 100, 3.0, accuracy: 0.06)
        XCTAssertEqual(acc[0].left, 5); XCTAssertEqual(acc[0].right, 60)
        XCTAssertEqual(rects(20, double: true, accounting: true)[0].top - 100, 5.4, accuracy: 0.06)
        let number = rects(11, double: true, accounting: true)
        XCTAssertEqual(number.count, 2)
        XCTAssertEqual(number[0].left, 10); XCTAssertEqual(number[0].width, 30)
    }
}
