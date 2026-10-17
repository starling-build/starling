// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A document with comments or tracked changes prints with its markup, as
/// Word prints it: the page smaller beside a pane of balloons, its deleted
/// text gone into them (POI's six markup prints).
final class PdfMarkupTests: XCTestCase {
    private func run(_ text: String, _ style: CharStyle = CharStyle()) -> (String, Run) {
        (text, Run(length: text.utf16.count, style: style))
    }

    private func paragraph(_ pieces: [(String, Run)]) -> RichParagraph {
        RichParagraph(text: pieces.map(\.0).joined(), runs: pieces.map(\.1))
    }

    func testOnlyADocumentWithMarkupPrintsIt() {
        XCTAssertFalse(PdfExport.hasMarkup(RichDocument(paragraphs: [RichParagraph(text: "plain")])))
        var deleted = CharStyle()
        deleted.revision = RevisionMark(kind: .deleted, author: "pavel")
        XCTAssertTrue(PdfExport.hasMarkup(RichDocument(paragraphs: [paragraph([run("a"), run("b", deleted)])])))
        var commented = CharStyle()
        commented.comments = ["0"]
        XCTAssertTrue(PdfExport.hasMarkup(RichDocument(paragraphs: [paragraph([run("a", commented)])])))
    }

    /// 58067: "This is a whole paragraph where only one word is deleted."
    /// prints without "only ", which stands in a balloon level with it;
    /// a paragraph deleted mark and all is gone, its text and a ¶ in one.
    func testDeletedTextLeavesThePageForItsBalloon() {
        var deleted = CharStyle()
        deleted.revision = RevisionMark(kind: .deleted, author: "pavel")
        var gone = paragraph([run("This is another Test.", deleted)])
        gone.style.markRevision = RevisionMark(kind: .deleted, author: "pavel")
        let doc = RichDocument(paragraphs: [
            paragraph([run("This is a test.")]),
            gone,
            paragraph([run("This is a whole paragraph where "), run("only ", deleted), run("one word is deleted.")]),
        ])
        let print = PdfMarkup(doc)
        XCTAssertEqual(print.document.paragraphs.map(\.text),
                       ["This is a test.", "This is a whole paragraph where one word is deleted."])
        XCTAssertEqual(print.notes.map(\.label), ["Deleted:", "Deleted:"])
        XCTAssertEqual(print.notes.map { $0.paragraphs.joined() }, ["This is another Test.¶", "only "])
        XCTAssertEqual(print.notes.map(\.anchor), [RichPosition(paragraph: 1, offset: 0), RichPosition(paragraph: 1, offset: 32)])
    }

    /// delins: runs whose language was set to English (US) under change
    /// tracking — "Formatted: English (US)".
    func testAFormattingChangeIsDescribedAsWordDescribesIt() {
        var now = CharStyle()
        now.keptXML = "<w:lang w:val=\"en-US\" w:eastAsia=\"ru-RU\"/>"
        XCTAssertEqual(PdfMarkup._describe(now, was: "<w:rPr><w:lang w:eastAsia=\"ru-RU\"/></w:rPr>"), "English (US)")
        // Tika-792: red taken away — "Font color: Auto".
        XCTAssertEqual(PdfMarkup._describe(CharStyle(), was: "<w:rPr><w:color w:val=\"FF0000\"/></w:rPr>"), "Font color: Auto")
        var bold = CharStyle()
        bold.bold = true
        XCTAssertEqual(PdfMarkup._describe(bold, was: "<w:rPr/>"), "Font: Bold")
    }

    /// The page and a markup area 3.7in wide from its text's right edge,
    /// scaled to the paper's width: testComment (letter, 1in margins) at
    /// 0.727 in Word's print, its pane from 407.5 to 594.5.
    func testTheMarkupFrameIsWordsOnLetterPaper() {
        let frame = PdfExport.MarkupFrame(PageSetup.letter)
        XCTAssertEqual(frame.scale, 0.727, accuracy: 0.003)
        XCTAssertEqual(frame.pane.left, 407.5, accuracy: 1.5)
        XCTAssertEqual(frame.pane.right, 594.5, accuracy: 1.5)
        XCTAssertEqual(frame.pane.top, 113.6, accuracy: 1.5)
    }
}
