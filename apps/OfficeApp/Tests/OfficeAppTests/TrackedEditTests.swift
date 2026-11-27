// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
@testable import OfficeApp

/// With track changes on (`w:trackRevisions` in the settings), the editor's own edits are recorded as Word
/// records them: typed text is a `w:ins` with the reviewer's name and the time.
final class TrackedEditTests: XCTestCase {
    private var savedReviewer: (() -> (author: String, date: String))!
    override func setUp() {
        savedReviewer = RichDocumentController.reviewer
        RichDocumentController.reviewer = { ("Tester", "2026-11-27T10:00:00Z") }
    }
    override func tearDown() { RichDocumentController.reviewer = savedReviewer }

    private func open(_ text: String, tracking: Bool) throws -> RichDocumentController { try open([text], tracking: tracking) }

    private func open(_ texts: [String], tracking: Bool) throws -> RichDocumentController {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: texts.map { RichParagraph(text: $0) }), pageSetup: .letter))
        entries.removeAll { $0.name == "word/settings.xml" }
        let settings = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + (tracking ? "<w:trackRevisions/>" : "") + "<w:defaultTabStop w:val=\"720\"/></w:settings>"
        entries.append(ZipEntry(name: "word/settings.xml", data: Data(settings.utf8)))
        return RichDocumentController(document: try DocxFormat.read(try Zip.write(entries)).document)
    }

    private func saved(_ c: RichDocumentController) throws -> (body: String, settings: String) {
        let entries = try Zip.read(try DocxFormat.write(c.document, pageSetup: .letter))
        func part(_ n: String) -> String { String(decoding: entries.first { $0.name == n }?.data ?? Data(), as: UTF8.self) }
        return (part("word/document.xml"), part("word/settings.xml"))
    }

    private func count(_ s: String, _ needle: String) -> Int { s.components(separatedBy: needle).count - 1 }

    func testTypedTextIsATrackedInsertion() throws {
        let c = try open("Hello world", tracking: true)
        XCTAssertTrue(c.document.trackRevisions)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText(" there")
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello there world")
        let marked = c.document.paragraphs[0].runs.filter { $0.style.revision?.kind == .inserted }
        XCTAssertEqual(marked.map(\.length), [6])
        let out = try saved(c)
        XCTAssertEqual(count(out.body, "<w:ins "), 1)
        XCTAssertTrue(out.body.containsSubstring("w:author=\"Tester\" w:date=\"2026-11-27T10:00:00Z\""))
        XCTAssertTrue(out.body.containsSubstring("<w:t xml:space=\"preserve\"> there</w:t></w:r></w:ins>"), out.body)
        XCTAssertTrue(out.settings.containsSubstring("<w:trackRevisions/>"))
    }

    /// Enter with tracking on: Word marks the pilcrow ending the text before the caret as inserted.
    func testANewParagraphMarkIsATrackedInsertion() throws {
        let c = try open("Hello world", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertParagraphBreak()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Hello", " world"])
        XCTAssertEqual(c.document.paragraphs[0].style.markRevision?.kind, .inserted)
        XCTAssertNil(c.document.paragraphs[1].style.markRevision)
        let out = try saved(c)
        XCTAssertEqual(count(out.body, "<w:ins "), 1)
        XCTAssertTrue(out.body.containsSubstring("<w:rPr><w:ins w:id="), out.body)
    }

    func testWithoutTrackingTypingIsPlain() throws {
        let c = try open("Hello world", tracking: false)
        XCTAssertFalse(c.document.trackRevisions)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText(" there")
        c.insertParagraphBreak()
        XCTAssertFalse(try saved(c).body.containsSubstring("<w:ins "))
    }

    // MARK: Deletions (w:del)

    /// Backspace and Delete over the file's text: it stays, marked deleted by the reviewer, and saves as
    /// `w:del` with `w:delText`; Delete steps the caret past what it marked.
    func testDeletedTextStaysMarked() throws {
        let c = try open("Hello world", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.deleteBackward()
        XCTAssertEqual(c.selection.focus.offset, 4)
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.deleteForward()
        XCTAssertEqual(c.selection.focus.offset, 7)
        XCTAssertEqual(c.document.paragraphs[0].text, "Hello world")
        let marked = c.document.paragraphs[0].runs.filter { $0.style.revision?.kind == .deleted }
        XCTAssertEqual(marked.map(\.length), [1, 1])
        XCTAssertEqual(marked.first?.style.revision?.author, "Tester")
        let out = try saved(c).body
        XCTAssertEqual(count(out, "<w:del "), 2)
        XCTAssertTrue(out.containsSubstring("<w:delText>o</w:delText>"), out)
        XCTAssertTrue(out.containsSubstring("<w:delText>w</w:delText>"), out)
        XCTAssertTrue(out.containsSubstring("<w:del w:id=\"") && out.containsSubstring("w:author=\"Tester\" w:date=\"2026-11-27T10:00:00Z\""), out)
    }

    /// Deleting what the reviewer typed takes it away, leaving no change behind.
    func testDeletingOwnInsertionRemovesIt() throws {
        let c = try open("Hello world", tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 5), extend: false)
        c.insertText("abc")
        c.deleteBackward(); c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs[0].text, "Helloa world")
        c.insertParagraphBreak()
        c.deleteBackward()   // the mark the reviewer just made goes too
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["Helloa world"])
        let out = try saved(c).body
        XCTAssertEqual(count(out, "<w:ins "), 1)
        XCTAssertEqual(count(out, "<w:del "), 0)
    }

    /// Backspace at a paragraph's start marks the previous paragraph's mark deleted; the paragraphs stay.
    func testJoiningMarksTheParagraphMarkDeleted() throws {
        let c = try open(["One", "Two"], tracking: true)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["One", "Two"])
        XCTAssertEqual(c.document.paragraphs[0].style.markRevision?.kind, .deleted)
        XCTAssertEqual(c.selection.focus, RichPosition(paragraph: 0, offset: 3))
        XCTAssertTrue(try saved(c).body.containsSubstring("<w:rPr><w:del w:id="))
    }

    /// Typing over a selection that spans paragraphs: the selection is marked deleted, the marks between
    /// too, and the new text follows it as an insertion.
    func testTypingOverASelectionAcrossParagraphs() throws {
        let c = try open(["One two", "three four"], tracking: true)
        c.moveTo(RichPosition(paragraph: 0, offset: 4), extend: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 5), extend: true)
        c.insertText("X")
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["One two", "threeX four"])
        XCTAssertEqual(c.document.paragraphs[0].style.markRevision?.kind, .deleted)
        XCTAssertEqual(c.document.paragraphs[1].runs.map { $0.style.revision?.kind }, [.deleted, .inserted, nil])
        let out = try saved(c).body
        XCTAssertEqual(count(out, "<w:ins "), 1)
        XCTAssertEqual(count(out, "<w:del "), 3)  // "two", the mark, "three"
    }

    func testWithoutTrackingDeletingRemoves() throws {
        let c = try open(["One", "Two"], tracking: false)
        c.moveTo(RichPosition(paragraph: 1, offset: 0), extend: false)
        c.deleteBackward(); c.deleteBackward()
        XCTAssertEqual(c.document.paragraphs.map(\.text), ["OnTwo"])
        XCTAssertFalse(try saved(c).body.containsSubstring("<w:del "))
    }
}
