// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Review > Comments (W-RV-1): New Comment puts a comment on the text and in `word/comments.xml`, Delete takes it
/// off again, and Previous / Next select each commented stretch in turn. All saved as Word writes them.
final class CommentEditTests: XCTestCase {
    private var savedReviewer: (() -> (author: String, date: String))!
    override func setUp() {
        savedReviewer = RichDocumentController.reviewer
        RichDocumentController.reviewer = { ("Ada Lovelace", "2026-11-28T10:00:00Z") }
    }
    override func tearDown() { RichDocumentController.reviewer = savedReviewer }

    private func open(_ texts: [String]) throws -> RichDocumentController {
        RichDocumentController(document: try DocxFormat.read(try DocxFormat.write(
            RichDocument(paragraphs: texts.map { RichParagraph(text: $0) }), pageSetup: .letter)).document)
    }

    /// Saved and read back: the document part, the comments part, and the controller over the read document.
    private func roundTrip(_ c: RichDocumentController) throws -> (body: String, comments: String, again: RichDocumentController) {
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        let entries = try Zip.read(data)
        func part(_ n: String) -> String { String(decoding: entries.first { $0.name == n }?.data ?? Data(), as: UTF8.self) }
        return (part("word/document.xml"), part("word/comments.xml"),
                RichDocumentController(document: try DocxFormat.read(data).document))
    }

    func testNewCommentOnTheSelectionIsSavedAndReadBack() throws {
        let c = try open(["Hello brave new world"])
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 15), extend: true)
        XCTAssertEqual(c.addComment("Is this right?\nSecond line & more"), "0")
        XCTAssertEqual(c.commentRanges(), [.init(id: "0", start: RichPosition(paragraph: 0, offset: 6), end: RichPosition(paragraph: 0, offset: 15))])
        let (body, comments, again) = try roundTrip(c)
        XCTAssertTrue(body.containsSubstring("<w:commentRangeStart w:id=\"0\"/>"), body)
        XCTAssertTrue(body.containsSubstring("<w:commentReference w:id=\"0\"/>"), body)
        XCTAssertTrue(comments.containsSubstring("w:author=\"Ada Lovelace\""), comments)
        XCTAssertTrue(comments.containsSubstring("w:initials=\"AL\""), comments)
        XCTAssertEqual(again.comments(), [.init(id: "0", author: "Ada Lovelace", initials: "AL", date: "2026-11-28T10:00:00Z",
                                                text: "Is this right?\nSecond line & more")])
        XCTAssertEqual(again.commentRanges().map(\.start.offset), [6])
        XCTAssertEqual(again.commentRanges().map(\.end.offset), [15])
        // One undo step takes the comment and its text away together.
        c.undo()
        XCTAssertEqual(c.commentRanges(), [])
        XCTAssertNil(c.document.keptParts["word/comments.xml"])
    }

    func testNewCommentWithNoSelectionTakesTheWordAndIdsGoUp() throws {
        let c = try open(["Hello brave world", "Second paragraph"])
        c.moveTo(RichPosition(paragraph: 0, offset: 8), extend: false)
        XCTAssertEqual(c.addComment("one"), "0")
        XCTAssertEqual(c.selection.start.offset, 6)
        XCTAssertEqual(c.selection.end.offset, 11)
        c.moveTo(RichPosition(paragraph: 1, offset: 2), extend: false)
        XCTAssertEqual(c.addComment("two"), "1")
        XCTAssertEqual(c.comments().map(\.text), ["one", "two"])
        XCTAssertEqual(try roundTrip(c).again.commentRanges().map(\.id), ["0", "1"])
    }

    func testNextAndPreviousStepThroughTheCommentsAndWrap() throws {
        let c = try open(["alpha beta gamma", "delta"])
        for (p, o) in [(0, 0), (0, 12), (1, 1)] {
            c.moveTo(RichPosition(paragraph: p, offset: o), extend: false)
            c.addComment("c\(p)\(o)")
        }
        c.moveTo(RichPosition(paragraph: 0, offset: 7), extend: false)
        XCTAssertTrue(c.selectAdjacentComment(forward: true))
        XCTAssertEqual(c.currentComment()?.text, "c012")
        XCTAssertTrue(c.selectAdjacentComment(forward: true))
        XCTAssertEqual(c.currentComment()?.text, "c11")
        XCTAssertTrue(c.selectAdjacentComment(forward: true))
        XCTAssertEqual(c.currentComment()?.text, "c00")             // wrapped
        XCTAssertTrue(c.selectAdjacentComment(forward: false))
        XCTAssertEqual(c.currentComment()?.text, "c11")             // and back
    }

    func testDeleteRemovesOneCommentAndDeleteAllTheRest() throws {
        let c = try open(["alpha beta gamma"])
        for o in [0, 7, 12] { c.moveTo(RichPosition(paragraph: 0, offset: o), extend: false); c.addComment("at \(o)") }
        c.moveTo(RichPosition(paragraph: 0, offset: 8), extend: false)
        XCTAssertEqual(c.deleteComments(), 1)
        XCTAssertEqual(c.comments().map(\.text), ["at 0", "at 12"])
        XCTAssertEqual(c.commentRanges().map(\.id), ["0", "2"])
        let (body, comments, _) = try roundTrip(c)
        XCTAssertFalse(body.containsSubstring("<w:commentRangeStart w:id=\"1\"/>"), body)
        XCTAssertFalse(comments.containsSubstring("w:id=\"1\""), comments)
        XCTAssertEqual(c.deleteAllComments(), 2)
        XCTAssertEqual(c.commentRanges(), [])
        XCTAssertNil(c.document.keptParts["word/comments.xml"])
        let saved = try roundTrip(c)
        XCTAssertFalse(saved.body.containsSubstring("comment"), saved.body)
        c.undo()
        XCTAssertEqual(c.comments().count, 2)
        XCTAssertEqual(c.commentRanges().count, 2)
    }

    func testCommentTextReadsEntitiesTabsAndParagraphs() {
        let xml = "<w:comments><w:comment w:id=\"7\" w:author=\"A &amp; B\" w:initials=\"AB\"><w:p><w:r><w:annotationRef/></w:r>"
            + "<w:r><w:t>x &lt; y</w:t></w:r><w:r><w:tab/><w:t xml:space=\"preserve\">z </w:t></w:r></w:p><w:p><w:r><w:t>next</w:t></w:r></w:p>"
            + "</w:comment></w:comments>"
        let parsed = RichDocumentController._parseComments(xml)
        XCTAssertEqual(parsed, [.init(id: "7", author: "A & B", initials: "AB", date: "", text: "x < y\tz \nnext")])
        XCTAssertEqual(RichDocumentController._removingComment("7", from: xml), "<w:comments></w:comments>")
    }
}
