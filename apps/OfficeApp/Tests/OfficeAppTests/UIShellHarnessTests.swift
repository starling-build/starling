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

    /// W-TB-2: the Table Layout tab's Borders and Shading menus reach the controller.
    func testTableLayoutBordersAndShadingReachTheController() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertTable(rows: 2, columns: 2)
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Table Layout"))
        XCTAssertTrue(ui.has(text: "Borders & Shading"))
        XCTAssertTrue(ui.tap(text: "Borders"))
        XCTAssertTrue(ui.tap(text: "Bottom Border"))
        XCTAssertTrue(c.document.paragraphs.compactMap { $0.cell }.contains { ($0.bordersXML ?? "").contains("w:bottom") })
    }
}
