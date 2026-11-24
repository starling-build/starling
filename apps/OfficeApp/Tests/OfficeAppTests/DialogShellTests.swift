import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// The shared dialog shell, driven headless: buttons, tabs, Enter and Esc.
final class DialogShellTests: XCTestCase {
    private func dialog(okEnabled: Bool = true, _ log: @escaping (String) -> Void) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: DialogShell(
            title: "Page Setup",
            tabs: [DialogTab(title: "Margins", page: Text("margins page")), DialogTab(title: "Paper", page: Text("paper page"))],
            okEnabled: okEnabled, onOK: { log("ok") }, onCancel: { log("cancel") }), title: "T"), size: Size(1280, 800))
    }

    func testOKAndCancelButtons() {
        var log: [String] = []
        let ui = dialog { log.append($0) }
        XCTAssertTrue(ui.has(text: "Page Setup"))
        ui.tap(text: "OK"); ui.tap(text: "Cancel")
        XCTAssertEqual(log, ["ok", "cancel"])
    }

    func testTabsSwitchThePage() {
        let ui = dialog { _ in }
        XCTAssertTrue(ui.has(text: "margins page")); XCTAssertFalse(ui.has(text: "paper page"))
        ui.tap(text: "Paper")
        XCTAssertTrue(ui.has(text: "paper page")); XCTAssertFalse(ui.has(text: "margins page"))
        XCTAssertEqual(ui.state(DialogShellState.self)?.selectedTab, 1)
    }

    func testEnterIsOKAndEscapeIsCancel() {
        var log: [String] = []
        let ui = dialog { log.append($0) }
        ui.press(.enter); ui.press(.escape)
        XCTAssertEqual(log, ["ok", "cancel"])
    }

    func testEnterAndOKDoNothingWhileOKIsDisabled() {
        var log: [String] = []
        let ui = dialog(okEnabled: false) { log.append($0) }
        ui.press(.enter); ui.tap(text: "OK")
        XCTAssertEqual(log, [])
        ui.press(.escape)
        XCTAssertEqual(log, ["cancel"])
    }

    func testTheKeysStopWorkingOnceTheDialogIsGone() {
        var log: [String] = []
        let ui = dialog { log.append($0) }
        ui.replace(with: Text("gone"))
        ui.press(.enter)
        XCTAssertEqual(log, [])
    }
}
