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

    private func app(_ home: Widget) -> WidgetTester {
        WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: home, title: "Test"), size: Size(1280, 800))
    }

    func testTheSlidesShellBuildsAndItsTabsTap() {
        let ui = app(SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }))
        XCTAssertNotNil(ui.state(SlidesShellState.self))
        XCTAssertTrue(ui.has(text: "Insert"))
        XCTAssertTrue(ui.tap(text: "Insert"))
    }

    func testTheSheetsShellBuildsAndItsTabsTap() {
        let ui = app(SheetsShell(initialPath: nil, onSwitch: { _, _ in }))
        XCTAssertNotNil(ui.state(SheetsShellState.self))
        XCTAssertTrue(ui.has(text: "Insert"))
        XCTAssertTrue(ui.tap(text: "Insert"))
    }

    func testAnIconOnlyButtonIsFoundByItsTooltip() {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        XCTAssertFalse(ui.tips().isEmpty, "the ribbon has icon buttons with tooltips")
        let tip = ui.tips()[0]
        XCTAssertTrue(ui.has(tip: tip))
        XCTAssertTrue(ui.tap(tip: tip))
        XCTAssertFalse(ui.tap(tip: "no such button"))
    }

    func testKeysAndTextReachTheFocusedField() {
        let controller = TextEditingController()
        var enters = 0
        let ui = app(Column(children: [
            SizedBox(width: 200, height: 30, child: FluentTextBox(controller: controller, onSubmitted: { _ in enters += 1 })),
        ]))
        let box = ui.elements().first { $0.widget is FluentTextBox }!
        let r = box.findRenderObject() as! RenderBox
        ui.tap(at: r.localToGlobal(Offset(r.size.width / 2, r.size.height / 2)))
        ui.type("ab")
        XCTAssertEqual(controller.text, "ab")
        ui.press(.backspace)
        XCTAssertEqual(controller.text, "a")
        ui.press(.enter)
        XCTAssertEqual(enters, 1)
    }

    /// W-ED-1: the Paste button is on the Home ribbon, its arrow opens the four Paste Options, and the shell has
    /// wired plain click, plain-text key and each option to the controller.
    func testPasteOptionsArrowOpensTheFourChoices() throws {
        let ui = app(OfficeShell(initialPath: nil, startBlank: true))
        XCTAssertTrue(ui.has(text: "Paste"))
        let state = try XCTUnwrap(ui.state(OfficeShellState.self))
        XCTAssertNotNil(state.session.onPaste)
        XCTAssertNotNil(state.session.onPasteMode)
        XCTAssertFalse(ui.has(text: "Merge Formatting"))
        XCTAssertTrue(ui.tap(tip: "Paste Options"))
        for item in ["Keep Source Formatting", "Merge Formatting", "Picture", "Keep Text Only"] {
            XCTAssertTrue(ui.has(text: item), item)
        }
    }
}
