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
        XCTAssertEqual(session.controller.currentParagraphStyle.alignment, .left, "nothing applies before OK")
        ui.press(.enter); ui.pump()
        let s = session.controller.currentParagraphStyle
        XCTAssertEqual(s.alignment, .center)
        XCTAssertEqual(s.firstLineIndent, -36)
        XCTAssertEqual(s.lineSpacing, 2); XCTAssertNil(s.lineHeightPoints)
        XCTAssertFalse(ui.has(id: "pa-align-center"), "the dialog closed")
        session.controller.undo()
        XCTAssertEqual(session.controller.currentParagraphStyle.alignment, .left, "one undo reverts the whole dialog")
        XCTAssertEqual(session.controller.currentParagraphStyle.firstLineIndent, 0)
    }

    func testEscapeCancelsWithoutChange() {
        let (ui, session) = shell()
        session.onParagraphDialog?(); ui.pump()
        XCTAssertTrue(ui.tap(id: "pa-align-right"))
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "pa-align-right"))
        XCTAssertEqual(session.controller.currentParagraphStyle.alignment, .left)
    }
}
