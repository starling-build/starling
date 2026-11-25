// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// W-FD-1d: the Properties dialog writes the document's title, subject, author; Esc changes nothing; undo restores.
final class PropertiesDialogHarnessTests: XCTestCase {
    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        return (ui, ui.state(OfficeShellState.self)!.session)
    }

    func testTypingATitleAndEnterSetsItAndTheFieldReadsIt() {
        let (ui, session) = shell()
        session.onPropertiesDialog?(); ui.pump()
        ui.type("Quarterly plan"); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertEqual(session.controller.document.property("title"), "Quarterly plan")
        let props = FieldEvaluator.properties(keptParts: session.controller.document.keptParts)
        XCTAssertEqual(FieldEvaluator.evaluate("TITLE", shown: "x", clock: nil, properties: props), "Quarterly plan")
        session.controller.undo()
        XCTAssertEqual(session.controller.document.property("title"), "")
    }

    func testEscapeChangesNothing() {
        let (ui, session) = shell()
        session.onPropertiesDialog?(); ui.pump()
        ui.type("zzz"); ui.press(.escape); ui.pump()
        XCTAssertEqual(session.controller.document.property("title"), "")
        XCTAssertNil(session.controller.document.keptParts["docProps/core.xml"])
    }
}
