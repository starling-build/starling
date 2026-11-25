// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-LI-1: Define New Number Format / Define New Bullet apply a custom label as one undo step.
final class ListFormatDialogHarnessTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        let c = session.controller
        c.insertText("one"); c.insertParagraphBreak(); c.insertText("two")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: true)
        c.toggleList(.numbered)
        return (ui, session)
    }

    func testCustomNumberFormatAppliesAndUndoes() {
        let (ui, session) = shell()
        let before = RichListNumbering.labels(session.controller.document)
        session.onListFormatDialog?(false); ui.pump()
        XCTAssertTrue(ui.has(id: "lf-text"))
        XCTAssertTrue(ui.tap(id: "lf-style-upper-roman")); ui.pump()
        XCTAssertTrue(ui.tap(id: "lf-text"))
        for _ in 0..<5 { ui.press(.backspace) }
        ui.type("(%1)"); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(id: "lf-text"))
        XCTAssertEqual(RichListNumbering.labels(session.controller.document), ["(I)", "(II)"])
        session.controller.undo()
        XCTAssertEqual(RichListNumbering.labels(session.controller.document), before)
    }

    func testNumberFormatWithoutNumberIsRejected() {
        let (ui, session) = shell()
        let before = RichListNumbering.labels(session.controller.document)
        session.onListFormatDialog?(false); ui.pump()
        XCTAssertTrue(ui.tap(id: "lf-text"))
        for _ in 0..<5 { ui.press(.backspace) }
        ui.type("x"); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertTrue(ui.has(id: "lf-text"))   // still open: nothing to show a number
        XCTAssertEqual(RichListNumbering.labels(session.controller.document), before)
    }

    func testEscapeChangesNothing() {
        let (ui, session) = shell()
        let before = RichListNumbering.labels(session.controller.document)
        session.onListFormatDialog?(true); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "lf-text"))
        XCTAssertEqual(RichListNumbering.labels(session.controller.document), before)
    }
}
