import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// The Writer shell built headless: its ribbon is on screen and a tab can be tapped by its label.
final class UIShellHarnessTests: XCTestCase {
    func testTheWriterShellBuildsAndShowsItsRibbonTabs() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Insert"))
        XCTAssertFalse(ui.texts().contains("Table"), "Table is on the Insert tab, not Home")
        XCTAssertTrue(ui.tap(text: "Insert"))
        XCTAssertTrue(ui.texts().contains("Table"))
        XCTAssertFalse(ui.texts().contains("Format Painter"))
        XCTAssertNotNil(ui.state(OfficeShellState.self))
    }

    /// W-ED-1: the Paste button is on the Home ribbon and the shell has wired every way of pasting
    /// (plain click, plain-text key, the four Paste Options) to the controller.
    func testPasteAndPasteOptionsAreWiredToTheShell() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        XCTAssertTrue(ui.has(text: "Paste"))
        let state = try XCTUnwrap(ui.state(OfficeShellState.self))
        XCTAssertNotNil(state.session.onPaste)
        XCTAssertNotNil(state.session.onPasteMode)
    }
}
