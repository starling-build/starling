import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

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
}
