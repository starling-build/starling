// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-LI-1: Define New Multilevel List, Change List Level, and the numbering commands on a list item.
final class MultilevelListTests: XCTestCase {
    /// "a", "b" (level 2), "c" (level 3), "d": one numbered list.
    private func nested(_ c: RichDocumentController) {
        c.selectAll()
        c.toggleList(.numbered)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.setListLevel(1)
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.setListLevel(2)
    }

    private func shell() -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        let c = session.controller
        for (i, t) in ["a", "b", "c", "d"].enumerated() {
            if i > 0 { c.insertParagraphBreak() }
            c.insertText(t)
        }
        nested(c)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        return (ui, session)
    }

    private func retype(_ ui: WidgetTester, _ id: String, _ text: String) {
        XCTAssertTrue(ui.tap(id: id), id)
        for _ in 0..<8 { ui.press(.backspace) }
        ui.type(text); ui.pump()
    }

    func testChangeListLevelIsOneStepAndLeavesBodyText() {
        let c = RichDocumentController(plainText: "a\nbody\nb")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.toggleList(.numbered)
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.toggleList(.numbered)
        c.selectAll()
        c.setListLevel(3)
        XCTAssertEqual(c.document.paragraphs.map(\.style.listLevel), [3, 0, 3])
        XCTAssertNil(c.document.paragraphs[1].style.list)
        XCTAssertEqual(c.currentListLevel, 3)
        c.undo()
        XCTAssertEqual(c.document.paragraphs.map(\.style.listLevel), [0, 0, 0])
    }

    func testDialogDefinesALevelAndUndoes() throws {
        let (ui, session) = shell()
        let c = session.controller
        XCTAssertEqual(RichListNumbering.labels(c.document), ["1.", "1.", "1.", "2."])
        session.onMultilevelDialog?(); ui.pump()
        XCTAssertTrue(ui.has(id: "ml-text"))
        // It opens on the caret's level (2).
        let state = try XCTUnwrap(ui.state(MultilevelListDialogState.self))
        XCTAssertEqual(state.level, 1)
        XCTAssertTrue(ui.tap(id: "ml-style-upper-roman")); ui.pump()
        retype(ui, "ml-text", "%1.%2")
        retype(ui, "ml-start", "3")
        retype(ui, "ml-indent", "60")
        retype(ui, "ml-aligned", "30")
        XCTAssertEqual(state.label(1), "1.III")
        // A bad value holds OK back.
        retype(ui, "ml-start", "x")
        XCTAssertNil(state.result)
        retype(ui, "ml-start", "3")
        XCTAssertNotNil(state.result)
        XCTAssertTrue(ui.tap(id: "ml-level-1")); ui.pump()
        XCTAssertEqual(state.level, 0)
        retype(ui, "ml-text", "(%1)")
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(id: "ml-text"))
        XCTAssertEqual(RichListNumbering.labels(c.document), ["(1)", "1.III", "1.", "(2)"])
        let id = try XCTUnwrap(c.document.paragraphs[1].style.listId)
        let l2 = try XCTUnwrap(c.document.listFormats[id]?[1])
        XCTAssertEqual(l2.indentLeft, 60); XCTAssertEqual(l2.hanging, 30); XCTAssertEqual(l2.start, 3)
        c.undo()
        XCTAssertEqual(RichListNumbering.labels(c.document), ["1.", "1.", "1.", "2."])
    }

    func testDialogEscapeChangesNothing() {
        let (ui, session) = shell()
        let before = session.controller.document
        session.onMultilevelDialog?(); ui.pump()
        XCTAssertTrue(ui.tap(id: "ml-style-bullet")); ui.pump()
        ui.press(.escape); ui.pump()
        XCTAssertFalse(ui.has(id: "ml-text"))
        XCTAssertEqual(session.controller.document, before)
    }

    /// The defined levels, a bullet level among them, survive a save: number style, text,
    /// start and both indents (the Word lab: LI1_OUT=path writes the file).
    func testDefinedLevelsSurviveSave() throws {
        let c = RichDocumentController(plainText: "a\nb\nc\nd")
        nested(c)
        var levels = c.multilevelScheme
        levels[0].text = "Part %1:"; levels[0].format = .upperRoman
        levels[1].text = "%1.%2"; levels[1].format = .decimal; levels[1].start = 3; levels[1].indentLeft = 60; levels[1].hanging = 30
        levels[2].text = "\u{25AA}"; levels[2].format = .bullet
        c.selectAll()
        c.setMultilevelFormat(levels)
        XCTAssertEqual(RichListNumbering.labels(c.document), ["Part I:", "I.3", "\u{25AA}", "Part II:"])
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        if let out = ProcessInfo.processInfo.environment["LI1_OUT"] { try data.write(to: URL(fileURLWithPath: out)) }
        let back = try DocxFormat.read(data).document
        XCTAssertEqual(RichListNumbering.labels(back), ["Part I:", "I.3", "\u{25AA}", "Part II:"])
        let id = try XCTUnwrap(back.paragraphs[1].style.listId)
        let l2 = try XCTUnwrap(back.listFormats[id]?[1])
        XCTAssertEqual(l2.indentLeft, 60); XCTAssertEqual(l2.hanging, 30); XCTAssertEqual(l2.start, 3)
        XCTAssertEqual(back.paragraphs.map(\.style.listLevel), [0, 1, 2, 0])
    }

    /// The scheme the dialog opens on: the list's own levels with their saved indents.
    func testSchemeFillsDefaults() {
        let c = RichDocumentController(plainText: "a")
        XCTAssertEqual(c.multilevelScheme.count, 9)
        XCTAssertEqual(c.multilevelScheme[2].indentLeft, 108)
        XCTAssertEqual(c.multilevelScheme[2].hanging, 18)
        c.toggleList(.numbered)
        XCTAssertEqual(c.multilevelScheme[0].text, "%1.")
    }
}
