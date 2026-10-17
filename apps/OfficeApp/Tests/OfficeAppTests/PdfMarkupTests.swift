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

    /// delins: a hyperlink field whose code was reformatted under change
    /// tracking — "Field Code Changed" where its result begins, before the
    /// result's own "Formatted:".
    func testAReformattedFieldCodeHasItsBalloon() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let change = "<w:rPrChange w:id=\"1\" w:author=\"pavel\"><w:rPr/></w:rPrChange>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
            + "<w:r><w:rPr>\(change)</w:rPr><w:instrText xml:space=\"preserve\"> HYPERLINK \"http://x\" </w:instrText></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            + "<w:r><w:rPr><w:lang w:val=\"en-US\"/>\(change)</w:rPr><w:t>Lucene Boot Camp</w:t></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r><w:r><w:t> - a session</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let runs = doc.paragraphs[0].runs
        XCTAssertTrue(runs.first?.style.fieldCodeChanged == true, "the result's first run")
        XCTAssertFalse(runs.dropFirst().contains { $0.style.fieldCodeChanged }, "and no other")
        XCTAssertEqual(PdfMarkup(doc).notes.map(\.label), ["Field Code Changed", "Formatted:"])
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
