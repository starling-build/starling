import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-CE-3b: the Name Manager, driven headless — the ribbon button opens it, rows pick, Delete / OK / Close reach the controller.
final class SheetsNameManagerTests: XCTestCase {
    private func controller() -> WorkbookController {
        let book = Workbook(sheets: [Worksheet(name: "Data"), Worksheet(name: "Other")])
        book.fileNames = [
            DefinedName(name: "Rates", localSheet: nil, attrs: [:], text: "Data!$B$2:$B$9"),
            DefinedName(name: "Local", localSheet: 1, attrs: [:], text: "Other!$A$1"),
        ]
        book.names["RATES"] = "Data!$B$2:$B$9"
        book.nameSpellings["RATES"] = "Rates"
        let c = WorkbookController()
        c.load(book)
        return c
    }

    private func dialog(_ c: WorkbookController, _ log: @escaping (String) -> Void) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                               home: NameManagerDialog(controller: c, onClose: { log("closed") }), title: "T"), size: Size(1280, 800))
    }

    func testTheListShowsEveryNameAndPickingFillsTheForm() {
        let ui = dialog(controller()) { _ in }
        XCTAssertTrue(ui.has(text: "Rates")); XCTAssertTrue(ui.has(text: "Local"))
        ui.tap(text: "Rates")
        XCTAssertEqual(ui.state(NameManagerDialogState.self)?.picked, "Rates")
    }

    func testDeleteRemovesThePickedNameAsOneUndoStep() {
        let c = controller()
        let ui = dialog(c) { _ in }
        ui.tap(text: "Rates"); ui.tap(text: "Delete")
        XCTAssertNil(c.book.names["RATES"])
        XCTAssertFalse(ui.has(text: "Rates"))
        c.undo()
        XCTAssertEqual(c.book.names["RATES"], "Data!$B$2:$B$9")
    }

    func testASheetLocalNameCannotBeChangedOrDeleted() {
        let c = controller()
        var log: [String] = []
        let ui = dialog(c) { log.append($0) }
        ui.tap(text: "Local"); ui.tap(text: "Delete"); ui.press(.enter)
        XCTAssertTrue(c.book.fileNames.contains { $0.name == "Local" })
        XCTAssertEqual(log, [], "OK is greyed out for a read-only name")
        XCTAssertTrue(ui.texts().contains { $0.containsSubstring("belongs to one sheet") })
    }

    func testOKAppliesAndClosesAndAnEmptyNewNameStaysOpen() {
        let c = controller()
        var log: [String] = []
        let ui = dialog(c) { log.append($0) }
        ui.tap(text: "New"); ui.press(.enter)
        XCTAssertEqual(log, [], "an empty name is refused and the dialog stays")
        XCTAssertFalse((ui.state(NameManagerDialogState.self)?.message ?? "").isEmpty)
        ui.tap(text: "Rates"); ui.press(.enter)
        XCTAssertEqual(log, ["closed"])
        XCTAssertEqual(c.book.names["RATES"], "Data!$B$2:$B$9", "applying the unchanged name keeps it")
        ui.press(.escape)
        XCTAssertEqual(log, ["closed", "closed"])
    }

    func testTheFormulasTabOpensTheManagerInTheSheetsShell() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "T"), size: Size(1280, 800))
        XCTAssertTrue(ui.tap(text: "Formulas"))
        XCTAssertTrue(ui.tap(text: "Name Manager"))
        XCTAssertTrue(ui.has(text: "Close"))
        ui.press(.escape)
        XCTAssertFalse(ui.has(text: "Close"))
    }
}
