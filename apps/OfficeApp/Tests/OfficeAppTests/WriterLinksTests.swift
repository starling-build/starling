// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

final class WriterLinksTests: XCTestCase {
    func testContentsInMicrosoftWordFixtureResolveToTheirBookmarks() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/word-boringcrypto.docx")
        let document = try DocxFormat.read(Data(contentsOf: fixture)).document
        let controller = RichDocumentController(document: document)
        let links = Set(document.paragraphs.flatMap(\.runs).compactMap(\.style.link).filter { $0.hasPrefix("#") })
        XCTAssertFalse(links.isEmpty)
        for link in links {
            XCTAssertTrue(WriterLinks.follow(link, in: controller) { _ in XCTFail("Opened browser for \(link)") }, link)
            XCTAssertTrue(controller.document.paragraphs[controller.caret.paragraph].bookmarks.contains(String(link.dropFirst())), link)
        }
        XCTAssertEqual(controller.revision, 0)
    }

    func testWordContentsJumpSurvivesSaveAndReopenWithoutOpeningBrowser() throws {
        var heading = RichParagraph(text: "Chapter One")
        heading.bookmarks = ["_Toc123"]
        var linkStyle = CharStyle.plain
        linkStyle.link = "#_Toc123"
        let document = RichDocument(paragraphs: [
            RichParagraph(text: "Chapter One", charStyle: linkStyle),
            RichParagraph(text: "Body"), heading,
        ])
        let data = try DocxFormat.write(document, pageSetup: .letter)
        let reopened = try DocxFormat.read(data).document
        let controller = RichDocumentController(document: reopened)
        let revision = controller.revision
        let original = controller.document
        var opened: [String] = []
        let link = try XCTUnwrap(reopened.paragraphs[0].runs.first?.style.link)
        XCTAssertTrue(WriterLinks.follow(link, in: controller) { opened.append($0) })
        XCTAssertEqual(controller.selection.focus, RichPosition(paragraph: 2, offset: 0))
        XCTAssertEqual(controller.pendingReveal, .top)
        XCTAssertEqual(controller.revision, revision)
        XCTAssertEqual(controller.document, original)
        XCTAssertTrue(opened.isEmpty)
    }

    func testMissingOrEmptyBookmarkDoesNotNavigateAway() {
        let controller = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(text: "Keep my work")]))
        let selection = controller.selection
        for link in ["#missing", "#", "#%ZZ"] {
            XCTAssertFalse(WriterLinks.follow(link, in: controller) { _ in XCTFail("Opened browser for \(link)") })
            XCTAssertEqual(controller.selection, selection)
        }
    }

    func testFollowingAgainRequestsRevealEvenWhenCaretHasNotMoved() {
        var paragraph = RichParagraph(text: "Heading")
        paragraph.bookmarks = ["heading"]
        let controller = RichDocumentController(document: RichDocument(paragraphs: [paragraph]))
        var reveals = 0
        controller.addListener {
            if controller.pendingReveal == .top { reveals += 1 }
            controller.pendingReveal = .visible
        }
        for _ in 0..<2 {
            XCTAssertTrue(WriterLinks.follow("#heading", in: controller) { _ in XCTFail("Opened browser") })
        }
        XCTAssertEqual(reveals, 2)
    }

    func testBookmarkAndExternalURLWithFragment() {
        var heading = RichParagraph(text: "Heading")
        heading.bookmarks = ["chapter_one"]
        let controller = RichDocumentController(document: RichDocument(paragraphs: [RichParagraph(), heading]))
        XCTAssertTrue(WriterLinks.follow("#chapter_one", in: controller) { _ in XCTFail("Opened browser") })
        XCTAssertEqual(controller.selection.focus.paragraph, 1)
        let selection = controller.selection
        var opened: [String] = []
        let url = "https://example.com/book#chapter"
        XCTAssertTrue(WriterLinks.follow(url, in: controller) { opened.append($0) })
        XCTAssertEqual(opened, [url])
        XCTAssertEqual(controller.selection, selection)
    }
}
