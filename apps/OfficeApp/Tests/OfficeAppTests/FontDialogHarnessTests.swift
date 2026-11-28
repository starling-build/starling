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

    /// The underline's style and colour and the Asian text font reach the run in one undo step and survive a save.
    func testUnderlineStyleColourAndAsianFont() throws {
        let (ui, session) = shell()
        let c = session.controller
        c.insertText("hello"); c.selectAll()
        session.onFontDialog?(); ui.pump()
        XCTAssertFalse(ui.has(id: "ft-ul-double"), "the underline style shows only while Underline is on")
        XCTAssertTrue(ui.tap(id: "ft-underline")); ui.pump()
        XCTAssertTrue(ui.tap(id: "ft-ul-double")); ui.pump()
        XCTAssertTrue(ui.tap(id: "ft-ulc-FF0000")); ui.pump()
        XCTAssertTrue(ui.tap(id: "ft-eastasia")); ui.type("MS Mincho"); ui.pump()
        ui.press(.enter); ui.pump()
        var s = c.document.paragraphs[0].runs[0].style
        XCTAssertTrue(s.underline); XCTAssertEqual(s.underlineKind, "double"); XCTAssertEqual(s.underlineColor, "FF0000")
        XCTAssertEqual(s.eastAsiaFontFamily, "MS Mincho")
        let saved = try DocxFormat.write(c.document, pageSetup: .letter)
        let xml = String(decoding: try XCTUnwrap(Zip.read(saved).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertNotNil(xml.range(of: "<w:u w:val=\"double\" w:color=\"FF0000\"/>"), "the run's XML holds the kind and colour")
        let back = try DocxFormat.read(saved).document.paragraphs[0].runs[0].style
        XCTAssertEqual(back.underlineKind, "double"); XCTAssertEqual(back.underlineColor, "FF0000")
        XCTAssertEqual(back.eastAsiaFontFamily, "MS Mincho")
        // The dialog opens on what the run holds; turning Underline off drops the kind and colour with it.
        session.onFontDialog?(); ui.pump()
        XCTAssertTrue(ui.has(id: "ft-ul-double"))
        XCTAssertTrue(ui.tap(id: "ft-underline")); ui.pump()
        ui.press(.enter); ui.pump()
        s = c.document.paragraphs[0].runs[0].style
        XCTAssertFalse(s.underline); XCTAssertNil(s.underlineKind); XCTAssertNil(s.underlineColor)
        XCTAssertEqual(s.eastAsiaFontFamily, "MS Mincho", "an untouched Asian font box keeps the face")
        c.undo(); c.undo()
        s = c.document.paragraphs[0].runs[0].style
        XCTAssertFalse(s.underline); XCTAssertNil(s.eastAsiaFontFamily, "one undo step per dialog")
    }
}
