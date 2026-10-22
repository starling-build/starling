// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeApp

final class SiteReaderTextTests: XCTestCase {
    private func style(_ link: String) -> CharStyle {
        var value = CharStyle.plain; value.link = link; return value
    }

    func testReferencesSurviveAsLinksWithoutLosingUnicodeOrWhitespace() {
        var paragraph = RichParagraph(text: "🕊 Read & learn\n more", runs: [
            Run(length: 3), Run(length: 12, style: style("https://example.org/read?a=1&b=2")), Run(length: 6)])
        paragraph.id = 42
        let content = SiteReaderText(document: RichDocument(paragraphs: [paragraph]))
        XCTAssertEqual(content.paragraphs[0].spans.map(\.text).joined(), paragraph.text)
        XCTAssertEqual(content.paragraphs[0].spans[1].link, "https://example.org/read?a=1&b=2")
        XCTAssertTrue(content.html.contains(#"id="p=42""#))
        XCTAssertTrue(content.html.contains(#"href="https://example.org/read?a=1&amp;b=2""#))
        XCTAssertTrue(content.html.contains("Read &amp; learn"))
        XCTAssertTrue(content.html.contains("\n more"))
    }

    func testBookmarksResolveToStableParagraphAnchorsAndUnknownTargetsStayText() {
        var target = RichParagraph(text: "A destination")
        target.id = 91; target.bookmarks = ["chapter-one"]
        let references = [
            RichParagraph(text: "Chapter", charStyle: style("#chapter-one")),
            RichParagraph(text: "Direct", charStyle: style("#p=91")),
            RichParagraph(text: "Missing", charStyle: style("#missing")),
        ]
        let content = SiteReaderText(document: RichDocument(paragraphs: [target] + references))
        XCTAssertEqual(content.paragraphs[1].spans[0].link, "#p=91")
        XCTAssertEqual(content.paragraphs[2].spans[0].link, "#p=91")
        XCTAssertNil(content.paragraphs[3].spans[0].link)
        let nested = SiteReaderText(document: RichDocument(paragraphs: [target] + references), route: "/handbook/chapter/")
        XCTAssertEqual(nested.paragraphs[1].spans[0].link, "/handbook/chapter/#p=91")
        let unsafe = SiteReaderText(document: RichDocument(paragraphs: [target] + references), route: "//other.example/")
        XCTAssertNil(unsafe.paragraphs[1].spans[0].link)
    }

    func testUnsafeLinksAndUnmappedRelativeFilesRemainReadableText() {
        let targets = ["javascript:alert(1)", "data:text/html,hello", "file:///tmp/secret", "other.docx",
                       "//example.org", "https://example.org/\nscript"]
        for target in targets {
            let paragraph = RichParagraph(text: "<script>& Keep the reference", charStyle: style(target))
            let content = SiteReaderText(document: RichDocument(paragraphs: [paragraph]))
            XCTAssertNil(content.paragraphs[0].spans[0].link, target)
            XCTAssertFalse(content.html.contains("<script>"), target)
            XCTAssertTrue(content.html.contains("&lt;script&gt;&amp; Keep the reference"), target)
        }
        let email = SiteReaderText(document: RichDocument(paragraphs: [
            RichParagraph(text: "Contact the author", charStyle: style("mailto:author@example.org"))
        ]))
        XCTAssertEqual(email.paragraphs[0].spans[0].link, "mailto:author@example.org")
    }

    func testMalformedRunsCannotLoseTextOrSplitAnEmoji() {
        var paragraph = RichParagraph(text: "🕊ABC")
        paragraph.runs = [Run(length: 1, style: style("https://example.org")), Run(length: 4)]
        for runs in [paragraph.runs, [Run(length: Int.max)], [Run(length: -1)], [Run(length: 1)]] {
            paragraph.runs = runs
            let spans = SiteReaderText(document: RichDocument(paragraphs: [paragraph])).paragraphs[0].spans
            XCTAssertEqual(spans.map(\.text).joined(), "🕊ABC")
            XCTAssertEqual(spans.count, 1)
            XCTAssertNil(spans[0].link)
        }
    }

    func testDuplicateAndMissingIDsDoNotCreateAmbiguousHTMLAnchors() {
        var first = RichParagraph(text: "First"); first.id = 12
        var second = RichParagraph(text: "Second"); second.id = 12
        let third = RichParagraph(text: "Third")
        let content = SiteReaderText(document: RichDocument(paragraphs: [first, second, third]))
        XCTAssertEqual(content.paragraphs.map(\.id), [nil, nil, nil])
        XCTAssertFalse(content.html.contains(#"id="p=12""#))
        XCTAssertFalse(content.html.contains("p=0"))
    }

    func testAmbiguousBookmarksAndParagraphIDsCannotPointAtAnArbitraryPassage() {
        var a = RichParagraph(text: "First"); a.id = 10; a.bookmarks = ["ambiguous-name"]
        var b = RichParagraph(text: "Second"); b.id = 20; b.bookmarks = ["ambiguous-name"]
        var c = RichParagraph(text: "Third"); c.id = 10; c.bookmarks = ["ambiguous-id"]
        let references = ["#ambiguous-name", "#ambiguous-id", "#p=10"].map {
            RichParagraph(text: "Ambiguous reference", charStyle: style($0))
        }
        let document = RichDocument(paragraphs: [a, b, c] + references)
        let content = SiteReaderText(document: document)
        XCTAssertTrue(content.paragraphs.suffix(3).allSatisfy { $0.spans[0].link == nil })
        XCTAssertEqual(SiteReaderText.referenceIssues(in: document).map(\.kind),
                       [.missingBookmark, .missingBookmark, .missingBookmark])
        // Duplicate bookmark names also remain ambiguous with unique IDs.
        c.id = 30
        let uniqueIDs = SiteReaderText(document: RichDocument(paragraphs: [a, b, c, references[0]]))
        XCTAssertNil(uniqueIDs.paragraphs.last?.spans[0].link)
    }

    func testStructuredPayloadPreservesHeadingDownloadsAndArticleLabel() throws {
        var paragraph = RichParagraph(text: "Heading")
        paragraph.style.heading = 2
        let content = SiteReaderText(document: RichDocument(paragraphs: [paragraph]), title: "Reader chapter",
                                     downloads: (pdf: "/book/chapter/chapter.pdf", docx: "/book/chapter/chapter.docx"))
        let data = Data(try XCTUnwrap(content.json()).utf8)
        let decoded = try JSONDecoder().decode(SiteReaderText.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.title, "Reader chapter")
        XCTAssertEqual(decoded.paragraphs[0].level, 2)
        XCTAssertEqual(decoded.downloads?.pdf, "/book/chapter/chapter.pdf")
        XCTAssertTrue(content.html.contains("<h2>Heading</h2>"))
    }

    func testAuthorReviewIdentifiesUnsupportedReferencesWithoutChangingPublicPayload() throws {
        var target = RichParagraph(text: "Heading"); target.id = 32; target.bookmarks = ["known"]
        let references = ["https://example.org/", "mailto:author@example.org", "#known", "#missing",
                          "appendix.docx", "file:///drafts/notes.docx", "javascript:alert(1)"]
        let document = RichDocument(paragraphs: [target] + references.map { RichParagraph(text: "See reference", charStyle: style($0)) })
        let before = try RichDocumentEnvelope.encode(document)
        let issues = SiteReaderText.referenceIssues(in: document)
        XCTAssertEqual(issues.map(\.target), ["#missing", "appendix.docx", "file:///drafts/notes.docx", "javascript:alert(1)"])
        XCTAssertEqual(issues.map(\.kind), [.missingBookmark, .sourceFile, .sourceFile, .unsupportedAddress])
        XCTAssertEqual(try RichDocumentEnvelope.encode(document), before)
        let payload = Data(try XCTUnwrap(SiteReaderText(document: document).json()).utf8)
        let object = try JSONSerialization.jsonObject(with: payload)
        let normalized = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        XCTAssertFalse(String(decoding: normalized, as: UTF8.self).contains("file:///drafts/notes.docx"))
    }

    func testAuthorReviewDeduplicatesFormattingRunsAndNoticesDamagedLinkedText() {
        var italic = style("appendix.docx"); italic.italic = true
        let split = RichParagraph(text: "Read this", runs: [Run(length: 5, style: style("appendix.docx")), Run(length: 4, style: italic)])
        var damaged = RichParagraph(text: "🕊ABC")
        damaged.runs = [Run(length: 1, style: style("https://example.org")), Run(length: 4)]
        let issues = SiteReaderText.referenceIssues(in: RichDocument(paragraphs: [split, damaged]))
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues.map(\.kind), [.sourceFile, .formatting])
        XCTAssertEqual(issues[0].excerpt, "Read this")
        XCTAssertNil(issues[0].paragraphID)
        var identified = split; identified.id = 55
        XCTAssertEqual(SiteReaderText.referenceIssues(in: RichDocument(paragraphs: [identified]))[0].paragraphID, 55)
    }
}
