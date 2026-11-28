// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-LI-1 leftovers: Legal style numbering, Link level to style, Follow number with,
/// Adjust List Indents, Define New List Style; and the Paragraph dialog keeping one size.
final class ListLeftoversTests: XCTestCase {
    /// "a", "b" (level 2), "c" (level 3), "d": one numbered list.
    private func nested(_ c: RichDocumentController) {
        c.selectAll()
        c.toggleList(.numbered)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.setListLevel(1)
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.setListLevel(2)
    }

    private func shell(_ texts: [String] = ["a", "b", "c", "d"]) -> (WidgetTester, OfficeSession) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let session = ui.state(OfficeShellState.self)!.session
        let c = session.controller
        for (i, t) in texts.enumerated() {
            if i > 0 { c.insertParagraphBreak() }
            c.insertText(t)
        }
        return (ui, session)
    }

    /// Legal style numbering: a level showing "%1.%2" under a roman level 1 shows "1.1", not "I.1",
    /// and the flag survives a save (w:isLgl). Follow number with Space survives too.
    func testLegalNumberingAndFollowSurviveSave() throws {
        let c = RichDocumentController(plainText: "a\nb\nc\nd")
        nested(c)
        var levels = c.multilevelScheme
        levels[0].format = .upperRoman; levels[0].text = "%1."
        levels[1].format = .decimal; levels[1].text = "%1.%2"; levels[1].legal = true
        levels[1].suffix = "space"
        c.selectAll()
        c.setMultilevelFormat(levels)
        let labels = RichListNumbering.labels(c.document)
        XCTAssertEqual(labels[0], "I."); XCTAssertEqual(labels[1], "1.1"); XCTAssertEqual(labels[3], "II.")
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        if let out = ProcessInfo.processInfo.environment["LI2_OUT"] { try data.write(to: URL(fileURLWithPath: out)) }
        let back = try DocxFormat.read(data).document
        XCTAssertEqual(RichListNumbering.labels(back)[1], "1.1")
        let id = try XCTUnwrap(back.paragraphs[1].style.listId)
        XCTAssertEqual(back.listFormats[id]?[1]?.legal, true)
        XCTAssertEqual(back.listFormats[id]?[1]?.suffix, "space")
        XCTAssertNil(back.listFormats[id]?[0]?.legal)
    }

    /// Link level to style: level 1 linked to Heading 1 numbers the Heading 1 paragraphs already
    /// there, and a paragraph given Heading 1 later joins the list at that level. Saved as w:pStyle.
    func testLinkLevelToStyle() throws {
        let c = RichDocumentController(plainText: "Intro\nbody\nNext\nlater")
        c.moveTo(RichPosition(paragraph: 2, offset: 0), extend: false)
        c.setNamedStyle(RichNamedStyle.headingId(1))
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.setNamedStyle(RichNamedStyle.headingId(1))
        c.toggleList(.numbered)
        var levels = c.multilevelScheme
        levels[0].styleLink = c.styleLinkId(RichNamedStyle.headingId(1))
        c.setMultilevelFormat(levels)
        XCTAssertNotNil(c.document.paragraphs[2].style.list, "the existing Heading 1 joins the list")
        XCTAssertNil(c.document.paragraphs[1].style.list)
        c.undo()
        XCTAssertNil(c.document.paragraphs[2].style.list, "one undo step")
        c.redo()
        c.moveTo(RichPosition(paragraph: 3, offset: 0), extend: false)
        c.setNamedStyle(RichNamedStyle.headingId(1))
        XCTAssertEqual(c.document.paragraphs[3].style.listId, c.document.paragraphs[0].style.listId)
        XCTAssertEqual(RichListNumbering.labels(c.document).compactMap { $0 }, ["1.", "2.", "3."])
        let linkData = try DocxFormat.write(c.document, pageSetup: .letter)
        if let out = ProcessInfo.processInfo.environment["LI2_LINK_OUT"] { try linkData.write(to: URL(fileURLWithPath: out)) }
        let back = try DocxFormat.read(linkData).document
        let id = try XCTUnwrap(back.paragraphs[0].style.listId)
        XCTAssertEqual(back.listFormats[id]?[0]?.styleLink, "Heading1")
    }

    /// Adjust List Indents: number position, text indent and follow, one undo step.
    func testAdjustListIndents() throws {
        let c = RichDocumentController(plainText: "a\nb")
        XCTAssertNil(c.currentListIndents)
        c.selectAll()
        c.toggleList(.numbered)
        let before = c.document
        c.adjustListIndents(numberAt: 12, textAt: 54, follow: "nothing")
        let id = try XCTUnwrap(c.document.paragraphs[0].style.listId)
        let f = try XCTUnwrap(c.document.listFormats[id]?[0])
        XCTAssertEqual(f.indentLeft, 54); XCTAssertEqual(f.hanging, 42); XCTAssertEqual(f.suffix, "nothing")
        let cur = try XCTUnwrap(c.currentListIndents)
        XCTAssertEqual(cur.numberAt, 12); XCTAssertEqual(cur.textAt, 54); XCTAssertEqual(cur.follow, "nothing")
        c.undo()
        XCTAssertEqual(c.document, before)
    }

    /// The right-click menu's Adjust List Indents opens the dialog; OK applies, Esc does not.
    func testAdjustListIndentsDialog() throws {
        let (ui, session) = shell(["a", "b"])
        let c = session.controller
        c.selectAll(); c.toggleList(.numbered)
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        let shellState = try XCTUnwrap(ui.state(OfficeShellState.self))
        shellState.setState { shellState._adjustIndentsOpen = true }; ui.pump()
        let st = try XCTUnwrap(ui.state(AdjustListIndentsDialogState.self))
        XCTAssertTrue(ui.has(id: "ai-number")); XCTAssertTrue(ui.has(id: "ai-text"))
        XCTAssertTrue(ui.tap(id: "ai-follow-space")); ui.pump()
        st.setNumberAt(18); st.setTextAt(45); ui.pump()
        ui.press(.enter); ui.pump()
        XCTAssertFalse(ui.has(id: "ai-number"))
        let cur = try XCTUnwrap(c.currentListIndents)
        XCTAssertEqual(cur.numberAt, 18); XCTAssertEqual(cur.textAt, 45); XCTAssertEqual(cur.follow, "space")
    }

    /// The multilevel dialog's new rows: Follow number with, Link level to style, Legal style numbering.
    func testMultilevelDialogNewRows() throws {
        let (ui, session) = shell()
        let c = session.controller
        nested(c)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        session.onMultilevelDialog?(); ui.pump()
        let st = try XCTUnwrap(ui.state(MultilevelListDialogState.self))
        XCTAssertTrue(ui.has(id: "ml-link"))
        XCTAssertTrue(ui.tap(id: "ml-follow-space")); ui.pump()
        XCTAssertTrue(ui.tap(id: "ml-legal")); ui.pump()
        XCTAssertEqual(st.levels[1].suffix, "space"); XCTAssertEqual(st.levels[1].legal, true)
        st.setLink("Heading2"); ui.pump()
        ui.press(.enter); ui.pump()
        let id = try XCTUnwrap(c.document.paragraphs[1].style.listId)
        let f = try XCTUnwrap(c.document.listFormats[id]?[1])
        XCTAssertEqual(f.suffix, "space"); XCTAssertEqual(f.legal, true); XCTAssertEqual(f.styleLink, "Heading2")
    }

    /// Define New List Style: a named list the Multilevel List menu offers; applying it numbers the
    /// selection; the name survives a save as a numbering style.
    func testDefineAndApplyListStyle() throws {
        let (ui, session) = shell(["a", "b"])
        let c = session.controller
        session.onListStyleDialog?(); ui.pump()
        XCTAssertTrue(ui.has(text: "Define New List Style"))
        let st = try XCTUnwrap(ui.state(MultilevelListDialogState.self))
        st.setName(""); ui.pump()
        XCTAssertNil(st.result, "an empty name holds OK back")
        st.setName("Outline Plan"); ui.pump()
        let before = c.document.paragraphs
        ui.press(.enter); ui.pump()
        XCTAssertEqual(c.document.paragraphs, before, "defining a list style leaves the text alone")
        XCTAssertEqual(c.listStyles.map(\.name), ["Outline Plan"])
        c.selectAll()
        c.applyListStyle(c.listStyles[0].id)
        XCTAssertEqual(c.document.paragraphs.map { $0.style.list != nil }, [true, true])
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        if let out = ProcessInfo.processInfo.environment["LI2_STYLE_OUT"] { try data.write(to: URL(fileURLWithPath: out)) }
        let back = try DocxFormat.read(data).document
        XCTAssertEqual(Array(back.listStyleNames.values), ["Outline Plan"])
        XCTAssertEqual(RichListNumbering.labels(back), RichListNumbering.labels(c.document))
    }

    /// The Paragraph dialog keeps one size: its page switch stays put across both pages and
    /// whatever spacing options show (Word's dialog never resizes).
    func testParagraphDialogKeepsOneSize() throws {
        let (ui, session) = shell(["a"])
        session.onParagraphDialog?(); ui.pump()
        let first = try XCTUnwrap(ui.centre(id: "pa-page-breaks"))
        XCTAssertTrue(ui.tap(id: "pa-line-exactly")); ui.pump()
        XCTAssertTrue(ui.tap(id: "pa-special-hanging")); ui.pump()
        XCTAssertEqual(ui.centre(id: "pa-page-breaks"), first)
        XCTAssertTrue(ui.tap(id: "pa-page-breaks")); ui.pump()
        XCTAssertEqual(ui.centre(id: "pa-page-breaks"), first)
        XCTAssertFalse(ui.has(id: "pa-align-left"), "the other page stays hidden")
        XCTAssertEqual(ui.overflowingFlexes(), 0)
    }
}
