// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-ST-1: the Styles pane lists the styles, a click applies one, and a
/// custom style can be deleted (one undo step).
final class StylesPaneHarnessTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        session.controller.insertText("hello")
        return (ui, session)
    }

    func testClickAppliesStyle() {
        let (ui, session) = shell()
        session.onToggleStyles?(); ui.pump()
        XCTAssertTrue(ui.has(id: "sp-style-Heading1"))
        XCTAssertTrue(ui.tap(id: "sp-style-Heading1")); ui.pump()
        XCTAssertEqual(session.controller.currentNamedStyleId, "Heading1")
        XCTAssertFalse(ui.has(id: "sp-delete-Heading1"))
        XCTAssertFalse(ui.has(id: "sp-delete-Normal"))
    }

    func testDeleteCustomStyleAndUndo() {
        let (ui, session) = shell()
        let c = session.controller
        c.edit { c.perform(.addStyle(RichNamedStyle(id: "Mine", name: "Mine", paragraph: .body, char: CharStyle(bold: true)))) }
        c.setNamedStyle("Mine")
        session.onToggleStyles?(); ui.pump()
        XCTAssertTrue(ui.has(id: "sp-delete-Mine"))
        XCTAssertTrue(ui.tap(id: "sp-delete-Mine")); ui.pump()
        XCTAssertNil(c.document.styles["Mine"])
        XCTAssertEqual(c.currentNamedStyleId, RichNamedStyle.normalId)
        c.undo()
        XCTAssertNotNil(c.document.styles["Mine"])
        XCTAssertEqual(c.currentNamedStyleId, "Mine")
    }

    func testDeleteRepointsNextAtNormal() {
        let (_, session) = shell()
        let c = session.controller
        c.edit {
            c.perform(.addStyle(RichNamedStyle(id: "Gone", name: "Gone")))
            c.perform(.addStyle(RichNamedStyle(id: "Other", name: "Other", next: "Gone")))
        }
        XCTAssertEqual(c.document.styles["Other"]?.next, "Gone")
        c.deleteStyle("Gone")
        XCTAssertNil(c.document.styles["Gone"])
        XCTAssertEqual(c.document.styles["Other"]?.next, RichNamedStyle.normalId)
        c.undo()
        XCTAssertEqual(c.document.styles["Other"]?.next, "Gone")
        XCTAssertNotNil(c.document.styles["Gone"])
    }
}
