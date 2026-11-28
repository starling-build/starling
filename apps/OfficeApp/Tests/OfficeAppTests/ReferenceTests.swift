import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// W-FD-3: bookmarks, captions (SEQ) and cross-references (REF, PAGEREF, NOTEREF).
final class ReferenceTests: XCTestCase {
    private func controller(_ texts: [String], heading: Int? = nil) -> RichDocumentController {
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: texts.enumerated().map { i, t in
            var p = RichParagraph(text: t)
            if i == heading { p.style.heading = 1 }
            return p
        }))
        return c
    }

    private func update(_ c: RichDocumentController, pages: [Int: String] = [:]) {
        c.selectAll()
        _ = c.updateFields(pageOf: { pages[$0] ?? "1" }, pageCount: 3, everywhere: true, other: { _, _ in nil })
    }

    func testAddGoToDeleteBookmark() throws {
        let c = controller(["Alpha beta gamma", "Delta"])
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 10), extend: true)
        XCTAssertTrue(c.addBookmark("Beta"))
        XCTAssertFalse(c.addBookmark("1bad"))
        XCTAssertFalse(c.addBookmark("has space"))
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        XCTAssertTrue(c.addBookmark("Apple"))
        XCTAssertEqual(c.bookmarkEntries().map(\.name), ["Beta", "Apple"])   // by location
        XCTAssertEqual(c.bookmarkText("beta"), "beta")
        XCTAssertTrue(c.goToBookmark("BETA"))
        XCTAssertEqual(c.selection.start, RichPosition(paragraph: 0, offset: 6))
        XCTAssertEqual(c.selection.end, RichPosition(paragraph: 0, offset: 10))
        // The same name again moves the bookmark.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: true)
        c.addBookmark("beta")
        XCTAssertEqual(c.bookmarkEntries().count, 2)
        XCTAssertEqual(c.bookmarkText("Beta"), "Alpha")
        // It survives a save.
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let d = RichDocumentController(); d.load(back)
        XCTAssertEqual(Set(d.bookmarkEntries().map { $0.name.lowercased() }), ["beta", "apple"])
        XCTAssertEqual(d.bookmarkText("beta"), "Alpha")
        c.deleteBookmark("Apple")
        XCTAssertEqual(c.bookmarkEntries().map(\.name), ["beta"])
        c.undo()
        XCTAssertEqual(c.bookmarkEntries().count, 2)
    }

    func testCaptionsNumberAndRenumber() throws {
        let c = controller(["Picture one", "Picture two"])
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.insertCaption(label: "Figure", title: ": Second", place: .below, excludeLabel: false)
        XCTAssertEqual(c.document.paragraphs[2].text, "Figure 1: Second")
        XCTAssertEqual(c.document.paragraphs[2].style.named, "Caption")
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.insertCaption(label: "Figure", title: ": First", place: .below, excludeLabel: false)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Picture one", "Figure 1: First", "Picture two", "Figure 2: Second"])
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.insertCaption(label: "Table", title: "", place: .above, excludeLabel: true)
        XCTAssertEqual(c.document.paragraphs[0].text, "1")
        // The fields are SEQ, kept by a save, and F9 counts them the same.
        let seq = c.fieldSpans().map(\.instruction)
        XCTAssertEqual(seq, [" SEQ Table \\* ARABIC ", " SEQ Figure \\* ARABIC ", " SEQ Figure \\* ARABIC "])
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[4].text, "Figure 2: Second")
        let d = RichDocumentController(); d.load(back)
        XCTAssertEqual(Set(d.sequenceNumbers().values), ["1", "2"])
        c.undo()
        XCTAssertEqual(c.document.paragraphs.count, 4)
    }

    func testSequenceSwitches() {
        let c = controller(["", "", "", ""])
        for (i, instr) in [" SEQ X \\* ROMAN ", " SEQ X \\r 5 ", " SEQ X \\c ", " SEQ X \\h "].enumerated() {
            c.moveTo(RichPosition(paragraph: i, offset: 0), extend: false)
            c.insertField(instr, result: "?")
        }
        update(c)
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["I", "5", "5", ""])
    }

    func testCrossReferenceToHeadingTextPageAndAboveBelow() {
        let c = controller(["Intro", "Body text", "Tail"], heading: 0)
        let items = c.crossReferenceItems(.heading)
        XCTAssertEqual(items.map(\.title), ["Intro"])
        c.moveTo(RichPosition(paragraph: 1, offset: 9), extend: false)
        c.insertText(" see ")
        XCTAssertTrue(c.insertCrossReference(.heading, .text, items[0], link: true, pageOf: { _ in "1" }, pageCount: 1))
        c.insertText(" on page ")
        XCTAssertTrue(c.insertCrossReference(.heading, .page, items[0], link: true, pageOf: { _ in "1" }, pageCount: 1))
        c.insertText(" ")
        XCTAssertTrue(c.insertCrossReference(.heading, .aboveBelow, items[0], link: false, pageOf: { _ in "1" }, pageCount: 1))
        XCTAssertEqual(c.document.paragraphs[1].text, "Body text see Intro on page 1 above")
        let instr = c.fieldSpans().map(\.instruction)
        XCTAssertEqual(instr.count, 3)
        XCTAssertTrue(instr[0].hasPrefix(" REF _Ref") && instr[0].hasSuffix(" \\h "), instr[0])
        XCTAssertTrue(instr[1].hasPrefix(" PAGEREF _Ref"), instr[1])
        XCTAssertTrue(instr[2].hasSuffix(" \\p "), instr[2])
        // One hidden bookmark serves all three.
        XCTAssertEqual(c.bookmarkEntries().filter(\.hidden).count, 1)
        // The heading changes and moves to page 2; F9 follows.
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText("duction")
        update(c, pages: [0: "2"])
        XCTAssertEqual(c.document.paragraphs[1].text, "Body text see Introduction on page 2 above")
    }

    func testCrossReferenceToCaptionPartsAndFootnote() {
        let c = controller(["Picture", "Text"])
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.insertCaption(label: "Figure", title: ": A cat", place: .below, excludeLabel: false)
        let items = c.crossReferenceItems(.caption("Figure"))
        XCTAssertEqual(items.map(\.title), ["Figure 1: A cat"])
        XCTAssertTrue(c.crossReferenceTypes().contains(.caption("Equation")))
        c.moveTo(RichPosition(paragraph: 2, offset: 4), extend: false)
        c.insertText(" ")
        c.insertCrossReference(.caption("Figure"), .labelNumber, items[0], link: true, pageOf: { _ in "1" }, pageCount: 1)
        c.insertText(" / ")
        c.insertCrossReference(.caption("Figure"), .captionText, items[0], link: true, pageOf: { _ in "1" }, pageCount: 1)
        XCTAssertEqual(c.document.paragraphs[2].text, "Text Figure 1 / A cat")
        // A footnote's number.
        c.moveTo(RichPosition(paragraph: 0, offset: 7), extend: false)
        c.insertNote(.footnote)
        c.moveTo(RichPosition(paragraph: 2, offset: c.document.paragraphs[2].length), extend: false)
        c.insertText(" note ")
        let notes = c.crossReferenceItems(.footnote)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(c.insertCrossReference(.footnote, .note, notes[0], link: true, pageOf: { _ in "1" }, pageCount: 1))
        XCTAssertTrue(c.document.paragraphs[2].text.hasSuffix(" note 1"), c.document.paragraphs[2].text)
        XCTAssertTrue(c.fieldSpans().contains { $0.instruction.hasPrefix(" NOTEREF _Ref") })
    }

    func testCtrlShiftF5OpensBookmarkDialogAndAddsTheName() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: OfficeShell(initialPath: nil, startBlank: true), title: "Test"), size: Size(1280, 800))
        let state = ui.state(OfficeShellState.self)!
        let f5 = KeyData(timeStamp: 0, type: .down, physical: 0, logical: 0x1_0000_0805, character: nil, synthesized: false)
        state.session.controller.insertText("Hello")
        XCTAssertTrue(state._shortcut(f5, [.primary, .shift]))
        ui.pump()
        let dialog = ui.state(BookmarkDialogState.self)!
        dialog.name.text = "Greeting"
        dialog.add()
        ui.pump()
        XCTAssertNil(ui.state(BookmarkDialogState.self))
        XCTAssertEqual(state.session.controller.bookmarkEntries().map(\.name), ["Greeting"])
    }

    /// Insert Caption with "Include chapter number": the last Heading 1's number, the separator, then the count, which
    /// starts again in each chapter (Word's `{ STYLEREF 1 \s }-{ SEQ Figure \* ARABIC \s 1 }`); saved and F9 keep it.
    func testChapterNumberedCaptions() throws {
        func heading(_ t: String) -> RichParagraph {
            var p = RichParagraph(text: t)
            p.style.heading = 1; p.style.list = .numbered; p.style.listId = "7"
            return p
        }
        let c = RichDocumentController()
        c.load(RichDocument(paragraphs: [heading("Start"), RichParagraph(text: "Pic a"), RichParagraph(text: "Pic b"),
                                         heading("Next"), RichParagraph(text: "Pic c")]))
        XCTAssertTrue(c.headingsNumbered(level: 1))
        XCTAssertFalse(c.headingsNumbered(level: 2))
        let chapter = RichDocumentController.CaptionChapter(level: 1, separator: "-")
        for k in [4, 2, 1] {
            c.moveTo(RichPosition(paragraph: k, offset: 0), extend: false)
            XCTAssertEqual(c.nextCaptionNumber("Figure", .below, chapter: 1), 1, "inserted last-first: none before")
            c.insertCaption(label: "Figure", title: ": x", place: .below, excludeLabel: false, chapter: chapter)
        }
        let texts = c.document.paragraphs.map(\.text)
        XCTAssertEqual(texts, ["Start", "Pic a", "Figure 1-1: x", "Pic b", "Figure 1-2: x", "Next", "Pic c", "Figure 2-1: x"])
        XCTAssertEqual(c.fieldSpans().map(\.instruction).prefix(2), [" STYLEREF 1 \\s ", " SEQ Figure \\* ARABIC \\s 1 "])
        // Saved and reopened, then every field updated: the same numbers.
        let back = try DocxFormat.read(try DocxFormat.write(c.document, pageSetup: .letter)).document
        let d = RichDocumentController(); d.load(back)
        d.updateFields(pageOf: { _ in nil }, pageCount: 1, everywhere: true)
        XCTAssertEqual(d.document.paragraphs.map(\.text), texts)
        // An em dash, and the chapter's words and period dropped ("Chapter 2." shows 2).
        XCTAssertEqual(d.chapterNumber(level: 1, at: 7, labels: [nil, nil, nil, nil, nil, "Chapter 2.", nil, nil]), "2")
        c.moveTo(RichPosition(paragraph: 6, offset: 0), extend: false)
        c.insertCaption(label: "Table", title: "", place: .above, excludeLabel: false,
                        chapter: .init(level: 1, separator: "\u{2014}"))
        XCTAssertEqual(c.document.paragraphs[6].text, "Table 2\u{2014}1")
        // Before any heading, Word's STYLEREF error.
        c.moveTo(RichPosition(paragraph: 0, offset: 0), extend: false)
        c.insertCaption(label: "Table", title: "", place: .above, excludeLabel: true, chapter: chapter)
        XCTAssertEqual(c.document.paragraphs[0].text, RichDocumentController.styleRefMissing + "-1")
    }
}
