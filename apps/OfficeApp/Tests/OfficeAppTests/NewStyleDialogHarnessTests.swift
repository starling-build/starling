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

    func testNewStyleSurvivesSave() throws {
        let c = RichDocumentController(document: RichDocument(paragraphs: []))
        c.insertText("hello"); c.insertParagraphBreak(); c.insertText("world")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.toggleBold(); c.setFontSize(14); c.setTextColor(Color(0xFFC00000))
        c.setParagraphSpacing(after: 12); c.setIndents(left: 36)
        XCTAssertEqual(c.createStyleFromSelection(name: "My Style"), "MyStyle")
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.setNamedStyle("MyStyle")
        let back = try DocxFormat.read(DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.styles["MyStyle"]?.name, "My Style")
        XCTAssertEqual(back.styles["MyStyle"]?.char.bold, true)
        XCTAssertEqual(back.styles["MyStyle"]?.paragraph.spaceAfter, 12)
        XCTAssertEqual(back.styles["MyStyle"]?.paragraph.indentLeft, 36)
        XCTAssertEqual(back.styles["MyStyle"]?.char.fontSize, 14)
        XCTAssertEqual(back.styles.id(of: back.paragraphs[1].style), "MyStyle")
        XCTAssertEqual(back.styles.id(of: back.paragraphs[0].style), "MyStyle")
        if let out = ProcessInfo.processInfo.environment["NEWSTYLE_OUT"] {   // for a Word open check
            try DocxFormat.write(c.document, pageSetup: .letter).write(to: URL(fileURLWithPath: out))
        }
    }

    /// Word keeps nothing direct that the style now holds: a later Modify
    /// Style reaches both the source paragraph and the one it was applied to.
    func testCreatedStyleLeavesNothingDirectAndModifyReachesBoth() {
        let c = RichDocumentController(document: RichDocument(paragraphs: []))
        c.insertText("hello"); c.insertParagraphBreak(); c.insertText("world")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.toggleBold(); c.setFontSize(14); c.setTextColor(Color(0xFFC00000))
        c.setParagraphSpacing(after: 12); c.setIndents(left: 36)
        XCTAssertEqual(c.createStyleFromSelection(name: "My Style"), "MyStyle")
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.setNamedStyle("MyStyle")
        for i in 0..<2 {
            let r = c.document.paragraphs[i].runs[0].style
            XCTAssertFalse(r.bold, "paragraph \(i) keeps direct bold")
            XCTAssertNil(r.fontSize, "paragraph \(i) keeps direct size")
            XCTAssertNil(r.color, "paragraph \(i) keeps direct colour")
            XCTAssertEqual(c.document.paragraphs[i].style.named, "MyStyle")
        }
        var e = c.document.styles["MyStyle"]!
        e.paragraph.spaceAfter = 20; e.paragraph.indentLeft = 72; e.char.fontSize = 30
        c.setStyleEntry(e)
        for i in 0..<2 {
            XCTAssertEqual(c.document.paragraphs[i].style.spaceAfter, 20, "paragraph \(i)")
            XCTAssertEqual(c.document.paragraphs[i].style.indentLeft, 72, "paragraph \(i)")
        }
        // The saved file says it too: no direct spacing, indent, bold, size or colour.
        let saved = try! DocxFormat.write(c.document, pageSetup: .letter)
        let xml = String(decoding: (try! Zip.read(saved)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        for tag in ["<w:spacing", "<w:ind", "<w:b/>", "<w:sz ", "<w:color"] {
            XCTAssertFalse(xml.containsSubstring(tag), "direct \(tag) left in the paragraphs")
        }
        XCTAssertEqual(xml.components(separatedBy: "<w:pStyle w:val=\"MyStyle\"/>").count - 1, 2)
    }
}
