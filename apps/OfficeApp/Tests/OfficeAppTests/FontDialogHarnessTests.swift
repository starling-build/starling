// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-CH-2: the Font dialog is reachable, its controls reach the model, Enter applies in one undo, Esc does not.
final class FontDialogHarnessTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "t"))
        let session = ui.state(OfficeShellState.self)!.session
        return (ui, session)
    }

    func testSwitchesReachTheModelAndEnterApplies() {
        let (ui, session) = shell()
        session.controller.insertText("hello"); session.controller.selectAll()
        session.onFontDialog?(); ui.pump()
        XCTAssertTrue(ui.has(id: "ft-family"))
        XCTAssertTrue(ui.tap(id: "ft-bold"))
        XCTAssertTrue(ui.tap(id: "ft-double"))
        XCTAssertTrue(ui.tap(id: "ft-smallcaps"))
        XCTAssertTrue(ui.tap(id: "ft-super"))
        XCTAssertFalse(session.controller.currentCharStyle.bold, "nothing applies before OK")
        ui.press(.enter); ui.pump()
        let s = session.controller.currentCharStyle
        XCTAssertTrue(s.bold); XCTAssertTrue(s.doubleStrike); XCTAssertTrue(s.smallCaps)
        XCTAssertEqual(s.script, .superscript)
        XCTAssertFalse(ui.has(id: "ft-bold"), "the dialog closed")
        session.controller.undo()
        XCTAssertFalse(session.controller.currentCharStyle.bold, "one undo reverts the whole dialog")
        XCTAssertFalse(session.controller.currentCharStyle.doubleStrike)
    }

    func testEscapeCancelsWithoutChange() {
        let (ui, session) = shell()
        session.controller.insertText("hello"); session.controller.selectAll()
        session.onFontDialog?(); ui.pump()
        XCTAssertTrue(ui.tap(id: "ft-italic"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "ft-italic"))
        XCTAssertFalse(session.controller.currentCharStyle.italic)
    }
}
