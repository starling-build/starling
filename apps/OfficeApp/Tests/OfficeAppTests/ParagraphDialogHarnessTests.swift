// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-PA-1: the Paragraph dialog is reachable, its controls reach the model, Enter applies, Esc does not.
final class ParagraphDialogHarnessTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        return (ui, session)
    }

    func testControlsReachTheModelAndEnterApplies() {
        let (ui, session) = shell()
        session.onParagraphDialog?(); ui.pump()
        XCTAssertTrue(ui.has(text: "Paragraph"))
        XCTAssertTrue(ui.tap(id: "pa-align-center"))
        XCTAssertTrue(ui.tap(id: "pa-special-hanging"))
        XCTAssertTrue(ui.tap(id: "pa-line-exactly"))
        XCTAssertTrue(ui.has(id: "pa-points"))
        XCTAssertTrue(ui.tap(id: "pa-line-multiple"))
        XCTAssertTrue(ui.has(id: "pa-multiple"))
        XCTAssertTrue(ui.tap(id: "pa-line-double"))
        XCTAssertTrue(ui.tap(id: "pa-contextual"))
        XCTAssertEqual(session.controller.currentParagraphStyle.alignment, .left, "nothing applies before OK")
        ui.press(.enter); ui.pump()
        let s = session.controller.currentParagraphStyle
        XCTAssertEqual(s.alignment, .center)
        XCTAssertEqual(s.firstLineIndent, -36)
        XCTAssertEqual(s.lineSpacing, 2); XCTAssertNil(s.lineHeightPoints)
        XCTAssertTrue(s.contextualSpacing, "Don't add space between paragraphs of the same style")
        XCTAssertFalse(ui.has(id: "pa-align-center"), "the dialog closed")
        session.controller.undo()
        XCTAssertEqual(session.controller.currentParagraphStyle.alignment, .left, "one undo reverts the whole dialog")
        XCTAssertEqual(session.controller.currentParagraphStyle.firstLineIndent, 0)
        XCTAssertFalse(session.controller.currentParagraphStyle.contextualSpacing)
    }

    func testEscapeCancelsWithoutChange() {
        let (ui, session) = shell()
        session.onParagraphDialog?(); ui.pump()
        XCTAssertTrue(ui.tap(id: "pa-align-right"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "pa-align-right"))
        XCTAssertEqual(session.controller.currentParagraphStyle.alignment, .left)
    }

    /// W-PA-3: the Tabs page sets stops, Cancel on it discards them, OK on the paragraph dialog applies them in one undo step.
    func testTabsPageSetsClearsAndApplies() {
        let (ui, session) = shell()
        session.onParagraphDialog?(); ui.pump()
        XCTAssertTrue(ui.tap(id: "pa-tabs"))
        XCTAssertTrue(ui.has(id: "tb-set"))
        XCTAssertTrue(ui.tap(id: "tb-kind-right")); XCTAssertTrue(ui.tap(id: "tb-leader-dots"))
        XCTAssertTrue(ui.tap(id: "tb-set"))
        XCTAssertTrue(ui.has(id: "tb-row-0"))
        XCTAssertTrue(ui.tap(id: "tb-clear-all"))
        XCTAssertFalse(ui.has(id: "tb-row-0"))
        XCTAssertTrue(ui.tap(id: "tb-set"))
        ui.press(.escape); ui.pump()                       // Cancel: back to the paragraph page, stops dropped
        XCTAssertTrue(ui.has(id: "pa-align-left"))
        XCTAssertTrue(ui.tap(id: "pa-tabs"))
        XCTAssertFalse(ui.has(id: "tb-row-0"), "Cancel threw away the stop")
        XCTAssertTrue(ui.tap(id: "tb-kind-center")); XCTAssertTrue(ui.tap(id: "tb-set"))
        ui.press(.enter); ui.pump()                        // OK on the Tabs page: back to the paragraph page
        XCTAssertTrue(ui.has(id: "pa-align-left"))
        XCTAssertTrue(session.controller.currentParagraphStyle.tabStops.isEmpty, "nothing applies before OK")
        ui.press(.enter); ui.pump()
        let stops = session.controller.currentParagraphStyle.tabStops
        XCTAssertEqual(stops.count, 1); XCTAssertEqual(stops[0].alignment, .center)
        session.controller.undo()
        XCTAssertTrue(session.controller.currentParagraphStyle.tabStops.isEmpty)
    }
}
