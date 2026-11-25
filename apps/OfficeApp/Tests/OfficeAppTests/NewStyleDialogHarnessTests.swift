// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-ST-1: Create a Style from Selection takes a name, makes the style from
/// the caret's formatting, applies it, and undoes as one step.
final class NewStyleDialogHarnessTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        let c = session.controller
        c.insertText("hello")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.toggleBold()
        c.setAlignment(.center)
        return (ui, session)
    }

    func testCreateAppliesAndUndoes() {
        let (ui, session) = shell()
        let c = session.controller
        let count = c.document.styles.styles.count
        session.onNewStyleDialog?(); ui.pump()
        XCTAssertTrue(ui.has(id: "ns-name"))
        XCTAssertTrue(ui.tap(id: "ns-name"))
        ui.type("My Style"); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(id: "ns-name"))
        let entry = c.document.styles["MyStyle"]
        XCTAssertEqual(entry?.name, "My Style")
        XCTAssertEqual(entry?.char.bold, true)
        XCTAssertEqual(entry?.paragraph.alignment, .center)
        XCTAssertEqual(c.currentNamedStyleId, "MyStyle")
        c.undo()
        XCTAssertEqual(c.document.styles.styles.count, count)
        XCTAssertNil(c.document.styles["MyStyle"])
        XCTAssertEqual(c.currentNamedStyleId, RichNamedStyle.normalId)
    }

    func testDuplicateNameRejected() {
        let (_, session) = shell()
        let c = session.controller
        XCTAssertNil(c.createStyleFromSelection(name: "heading 1"))
        XCTAssertNil(c.createStyleFromSelection(name: "  "))
    }

    func testEscapeChangesNothing() {
        let (ui, session) = shell()
        let count = session.controller.document.styles.styles.count
        session.onNewStyleDialog?(); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "ns-name"))
        XCTAssertEqual(session.controller.document.styles.styles.count, count)
    }
}
