import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-DA-6: Review → Protect Sheet / Protect Workbook and the Format Cells Protection tab, driven headless.
final class SheetsProtectDialogTests: XCTestCase {
    private func dialog(_ c: WorkbookController, workbook: Bool, _ log: @escaping (String) -> Void = { _ in }) -> WidgetTester {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: ProtectDialog(controller: c, workbook: workbook, onClose: { log("closed") }), title: "T"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        return ui
    }
    private func type(_ ui: WidgetTester, _ id: String, _ text: String) {
        XCTAssertTrue(ui.tap(id: id), id); ui.type(text)
    }
    private func controller() -> WorkbookController {
        let c = WorkbookController(); c.load(Workbook(sheets: [Worksheet(name: "Data")])); return c
    }

    func testProtectSheetWithPasswordAndOneAllowedAction() {
        let c = controller(); var log: [String] = []
        let ui = dialog(c, workbook: false) { log.append($0) }
        XCTAssertTrue(ui.tap(id: "prot-sort"))
        type(ui, "prot-password", "password"); type(ui, "prot-again", "password")
        ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        XCTAssertEqual(c.protection()?["sort"], "0")
        XCTAssertEqual(c.protection()?["password"], "83AF")
    }

    func testMismatchedPasswordsStayOpenAndProtectNothing() {
        let c = controller(); var log: [String] = []
        let ui = dialog(c, workbook: false) { log.append($0) }
        type(ui, "prot-password", "a"); type(ui, "prot-again", "b")
        ui.press(.enter)
        XCTAssertEqual(log, [])
        XCTAssertNil(c.protection())
        XCTAssertTrue(ui.texts().contains { $0.containsSubstring("do not match") })
    }

    func testUnprotectNeedsTheRightPassword() {
        let c = controller()
        XCTAssertNil(c.protectSheet(SheetProtectionOptions(), password: "password"))
        var log: [String] = []
        let ui = dialog(c, workbook: false) { log.append($0) }
        type(ui, "prot-password", "nope"); ui.press(.enter)
        XCTAssertEqual(log, []); XCTAssertNotNil(c.protection())
        XCTAssertTrue(ui.texts().contains { $0.containsSubstring("not correct") || $0.containsSubstring("password") })
        let ui2 = dialog(c, workbook: false) { log.append($0) }
        type(ui2, "prot-password", "password"); ui2.press(.enter)
        XCTAssertEqual(log, ["closed"]); XCTAssertNil(c.protection())
    }

    func testProtectWorkbookLocksStructure() {
        let c = controller()
        let ui = dialog(c, workbook: true)
        ui.press(.enter)
        XCTAssertTrue(c.book.structureLocked)
        c.undo()
        XCTAssertFalse(c.book.structureLocked)
    }

    func testFormatCellsProtectionTabReportsLockAndHidden() {
        var got: CellFormatEdit?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: FormatCellsDialog(start: CellFormatEdit.Values(.plain), onApply: { got = $0 }, onClose: {}), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertTrue(ui.tap(text: "Protection"))
        XCTAssertTrue(ui.tap(id: "fc-locked")); XCTAssertTrue(ui.tap(id: "fc-hidden"))
        ui.press(.enter)
        XCTAssertEqual(got?.locked, .set(false))
        XCTAssertEqual(got?.formulaHidden, .set(true))
    }
}
