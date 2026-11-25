// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-LI-1: Set Numbering Value is reachable; Enter applies it as one undo step, Esc changes nothing.
final class NumberingValueDialogHarnessTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        let c = session.controller
        c.insertText("one"); c.insertParagraphBreak(); c.insertText("two"); c.insertParagraphBreak(); c.insertText("three")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: true)
        c.toggleList(.numbered)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        return (ui, session)
    }

    func testEnterAppliesAndUndoes() {
        let (ui, session) = shell()
        let before = RichListNumbering.labels(session.controller.document)
        session.onNumberingValueDialog?(); ui.pump()
        XCTAssertTrue(ui.has(id: "nv-value"))
        XCTAssertTrue(ui.tap(id: "nv-value"))
        for _ in 0..<5 { ui.press(.backspace) }
        ui.type("9"); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(id: "nv-value"))
        let after = RichListNumbering.labels(session.controller.document)
        XCTAssertEqual(after, ["1.", "9.", "10."])
        session.controller.undo()
        XCTAssertEqual(RichListNumbering.labels(session.controller.document), before)
    }

    func testEscapeChangesNothing() {
        let (ui, session) = shell()
        let before = RichListNumbering.labels(session.controller.document)
        session.onNumberingValueDialog?(); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "nv-value"))
        XCTAssertEqual(RichListNumbering.labels(session.controller.document), before)
    }
}
