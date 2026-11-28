// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// Review > Accept and Reject are split buttons, as in Word: the button acts at once (this change, then the next is
/// selected), and only its arrow opens the menu.
final class ReviewSplitButtonTests: XCTestCase {
    private func shell() -> (WidgetTester, RichDocumentController) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "t"),
                              size: Size(1440, 932))
        let c = ui.state(OfficeShellState.self)!.session.controller
        c.insertText("Hello brave world")
        c.setTrackRevisions(true)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.insertText("A ")
        c.moveTo(RichPosition(paragraph: 0, offset: 19), extend: false)
        c.insertText(" Z")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        XCTAssertEqual(c.trackedChanges().count, 2)
        XCTAssertTrue(c.selectAdjacentChange(forward: true))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Review"))
        ui.pump()
        return (ui, c)
    }

    func testAcceptActsAtOnceAndSelectsTheNextChange() {
        let (ui, c) = shell()
        XCTAssertTrue(ui.tap(tip: "Accept this change and move to the next"))
        ui.pump()
        XCTAssertFalse(ui.has(text: "Accept All Changes"), "the button itself opens no menu")
        XCTAssertEqual(c.trackedChanges().count, 1)
        XCTAssertEqual(c.document.paragraphs[0].text, "A Hello brave world Z")
        let next = c.trackedChanges()[0]
        XCTAssertEqual(c.selection.start, next.start, "the next change is selected")
        XCTAssertEqual(c.selection.end, next.end)
    }

    func testRejectActsAtOnceAndTheArrowOpensTheMenu() {
        let (ui, c) = shell()
        XCTAssertTrue(ui.tap(tip: "Reject this change and move to the next"))
        ui.pump()
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello brave world Z", "the first insertion is gone")
        XCTAssertEqual(c.trackedChanges().count, 1)
        XCTAssertTrue(ui.tap(tip: "Reject options"))
        ui.pump()
        XCTAssertTrue(ui.tap(text: "Reject All Changes"))
        ui.pump()
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello brave world")
        XCTAssertEqual(c.trackedChanges().count, 0)
        XCTAssertTrue(c.document.trackRevisions, "plain Reject All keeps tracking on")
    }
}
