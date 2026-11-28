// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Comment threads (W-RV-1): Reply, Resolve / Reopen and a comment's text edited in place, kept as Word keeps them
/// (`word/commentsExtended.xml`: `w15:paraIdParent` and `w15:done`, keyed by each comment's last `w14:paraId`).
final class CommentThreadTests: XCTestCase {
    private var savedReviewer: (() -> (author: String, date: String))!
    override func setUp() {
        savedReviewer = RichDocumentController.reviewer
        RichDocumentController.reviewer = { ("Ada Lovelace", "2026-11-28T10:00:00Z") }
    }
    override func tearDown() { RichDocumentController.reviewer = savedReviewer }

    private func commented() throws -> RichDocumentController {
        let c = RichDocumentController(document: try DocxFormat.read(try DocxFormat.write(
            RichDocument(paragraphs: [RichParagraph(text: "Hello brave new world")]), pageSetup: .letter)).document)
        c.moveTo(RichPosition(paragraph: 0, offset: 6), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 11), extend: true)
        XCTAssertEqual(c.addComment("Why brave?"), "0")
        return c
    }

    private func parts(_ c: RichDocumentController) throws -> (body: String, comments: String, ext: String, again: RichDocumentController) {
        let data = try DocxFormat.write(c.document, pageSetup: .letter)
        let entries = try Zip.read(data)
        func part(_ n: String) -> String { String(decoding: entries.first { $0.name == n }?.data ?? Data(), as: UTF8.self) }
        let rels = part("word/_rels/document.xml.rels"), types = part("[Content_Types].xml")
        XCTAssertTrue(rels.containsSubstring("Target=\"commentsExtended.xml\""), rels)
        XCTAssertTrue(types.containsSubstring("/word/commentsExtended.xml"), types)
        return (part("word/document.xml"), part("word/comments.xml"), part("word/commentsExtended.xml"),
                RichDocumentController(document: try DocxFormat.read(data).document))
    }

    func testReplyIsSavedAsWordThreadsIt() throws {
        let c = try commented()
        XCTAssertEqual(c.replyToComment("0", text: "Because."), "1")
        // A reply to the reply joins the same thread.
        XCTAssertEqual(c.replyToComment("1", text: "Fine."), "2")
        let t = c.commentThreads()
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t.first?.comment.text, "Why brave?")
        XCTAssertEqual(t.first?.replies.map(\.text), ["Because.", "Fine."])
        let (body, comments, ext, again) = try parts(c)
        // The reply covers the comment's text: its markers sit with the comment's.
        XCTAssertTrue(body.containsSubstring("<w:commentRangeStart w:id=\"0\"/><w:commentRangeStart w:id=\"1\"/>"), body)
        XCTAssertTrue(body.containsSubstring("<w:commentReference w:id=\"1\"/>"), body)
        XCTAssertTrue(comments.containsSubstring("xmlns:w14="), comments)
        let all = again.comments()
        XCTAssertEqual(all.map(\.parent), [nil, "0", "0"])
        XCTAssertTrue(ext.containsSubstring("w15:paraId=\"\(all[1].paraId)\" w15:paraIdParent=\"\(all[0].paraId)\""), ext)
        XCTAssertEqual(again.commentThreads().first?.replies.count, 2)
        // Next / Previous stop once per thread.
        XCTAssertTrue(again.selectAdjacentComment(forward: true))
        XCTAssertTrue(again.selectAdjacentComment(forward: true))
        XCTAssertEqual(again.selection.start.offset, 6)
        // One undo step takes the reply away.
        c.undo()
        XCTAssertEqual(c.commentThreads().first?.replies.map(\.text), ["Because."])
    }

    func testResolveAndReopenAreKept() throws {
        let c = try commented()
        c.replyToComment("0", text: "ok")
        XCTAssertTrue(c.setCommentResolved("1", true))       // (a reply resolves its whole thread)
        XCTAssertFalse(c.setCommentResolved("0", true))
        let (_, _, ext, again) = try parts(c)
        XCTAssertTrue(again.comments()[0].done)
        XCTAssertTrue(ext.containsSubstring("w15:paraId=\"\(again.comments()[0].paraId)\" w15:done=\"1\""), ext)
        // Word marks the reply resolved with its parent (lab/comments2 reply-resolved: both Done = True).
        XCTAssertTrue(again.comments()[1].done, ext)
        XCTAssertTrue(again.setCommentResolved("0", false))
        XCTAssertFalse(again.comments()[0].done)
        XCTAssertFalse(again.comments()[1].done)
        c.undo()
        XCTAssertFalse(c.comments()[0].done)
    }

    func testEditingACommentKeepsItsThread() throws {
        let c = try commented()
        c.replyToComment("0", text: "ok")
        let para = c.comments()[0].paraId
        XCTAssertTrue(c.setCommentText("0", "Why so brave?\nReally."))
        XCTAssertFalse(c.setCommentText("0", "Why so brave?\nReally."))
        let (_, comments, _, again) = try parts(c)
        XCTAssertEqual(again.comments()[0].text, "Why so brave?\nReally.")
        XCTAssertEqual(again.comments()[0].paraId, para)
        XCTAssertEqual(again.comments()[1].parent, "0")
        XCTAssertTrue(comments.containsSubstring("w:author=\"Ada Lovelace\""), comments)
        c.undo()
        XCTAssertEqual(c.comments()[0].text, "Why brave?")
    }

    func testDeletingACommentTakesItsRepliesAndTheirEntries() throws {
        let c = try commented()
        c.moveTo(RichPosition(paragraph: 0, offset: 16), extend: false)
        c.moveTo(RichPosition(paragraph: 0, offset: 21), extend: true)
        XCTAssertEqual(c.addComment("other"), "1")
        c.replyToComment("0", text: "reply")
        let gone = c.comments().filter { $0.id != "1" }.map(\.paraId)
        c.moveTo(RichPosition(paragraph: 0, offset: 7), extend: false)
        XCTAssertEqual(c.deleteComments(), 2)       // (the comment and its reply both cover the caret)
        XCTAssertEqual(c.comments().map(\.id), ["1"])
        XCTAssertEqual(c.commentRanges().map(\.id), ["1"])
        let (_, _, ext, _) = try parts(c)
        for p in gone { XCTAssertFalse(ext.containsSubstring(p), ext) }
        XCTAssertTrue(ext.containsSubstring(c.comments()[0].paraId), ext)
    }

    func testAFileCommentWithNoParagraphIdGetsOneForAReply() {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "abc")])
        doc.paragraphs[0].runs[0].style.comments = ["5"]
        doc.keptParts["word/comments.xml"] = Data(("<w:comments xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + "<w:comment w:id=\"5\" w:author=\"B\"><w:p><w:r><w:t>old</w:t></w:r></w:p></w:comment></w:comments>").utf8)
        let c = RichDocumentController(document: doc)
        XCTAssertEqual(c.replyToComment("5", text: "new"), "6")
        let all = c.comments()
        XCTAssertFalse(all[0].paraId.isEmpty)
        XCTAssertEqual(all[1].parent, "5")
        let xml = String(decoding: c.document.keptParts["word/comments.xml"]!, as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("xmlns:w14="), xml)
        // The top comment is listed in commentsExtended too, ahead of its reply, as Word lists every comment.
        let ext = String(decoding: c.document.keptParts["word/commentsExtended.xml"]!, as: UTF8.self)
        let top = ext.rangeOfSubstring("w15:paraId=\"\(all[0].paraId)\" w15:done=\"0\"")
        let reply = ext.rangeOfSubstring("w15:paraIdParent=\"\(all[0].paraId)\"")
        XCTAssertNotNil(top, ext)
        XCTAssertNotNil(reply, ext)
        if let top, let reply { XCTAssertLessThan(top.lowerBound, reply.lowerBound, ext) }
    }
}
