// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
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
    /// tracking — "Field Code Changed" where its result ends, after the
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
        XCTAssertEqual(PdfMarkup(doc).notes.map(\.label), ["Formatted:", "Field Code Changed"])
    }

    /// delins: a link item whose language was set under change tracking
    /// has three balloons in Word's print — the link text's, the words
    /// after it with the paragraph's mark, then the field code's; a field's
    /// end breaks a stretch, a reformatted mark joins it to the next
    /// paragraph's (three headings, one balloon).
    func testAFieldsEndBreaksAFormattingStretchAndAMarkJoinsOne() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let change = "<w:rPrChange w:id=\"1\" w:author=\"pavel\"><w:rPr/></w:rPrChange>"
        let english = "<w:rPr><w:lang w:val=\"en-US\"/>\(change)</w:rPr>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:pPr>\(english)</w:pPr><w:r>\(english)<w:t>March 2009</w:t></w:r></w:p>"
            + "<w:p><w:pPr>\(english)</w:pPr><w:r>\(english)<w:t>Apache Tika 0.3</w:t></w:r></w:p>"
            + "<w:p><w:pPr>\(english)</w:pPr><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r>"
            + "<w:r><w:rPr>\(change)</w:rPr><w:instrText xml:space=\"preserve\"> HYPERLINK \"http://x\" </w:instrText></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            + "<w:r>\(english)<w:t>Lucene Boot Camp</w:t></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r><w:r>\(english)<w:t xml:space=\"preserve\"> - a session</w:t></w:r></w:p>"
            + "<w:p><w:r><w:t>plain</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let notes = PdfMarkup(try DocxFormat.read(try Zip.write(entries)).document).notes
        XCTAssertEqual(notes.map(\.label), ["Formatted:", "Formatted:", "Formatted:", "Field Code Changed"])
        XCTAssertEqual(notes.map(\.anchor), [RichPosition(paragraph: 0, offset: 0), RichPosition(paragraph: 2, offset: 0),
                                             RichPosition(paragraph: 2, offset: 16), RichPosition(paragraph: 2, offset: 16)])
    }

    /// delins: two list items deleted marks and all are one balloon, each
    /// on its own line and its lost number written "<#>", as Word prints
    /// them.
    func testDeletedListItemsTakeALineEach() {
        var deleted = CharStyle()
        deleted.revision = RevisionMark(kind: .deleted, author: "pavel")
        func item(_ text: String) -> RichParagraph {
            var p = paragraph([run(text, deleted)])
            p.style.list = .bullet
            p.style.markRevision = RevisionMark(kind: .deleted, author: "pavel")
            return p
        }
        let print = PdfMarkup(RichDocument(paragraphs: [item("A pendant."), item("Tika Waylan"), paragraph([run("March 2009")])]))
        XCTAssertEqual(print.document.paragraphs.map(\.text), ["March 2009"])
        XCTAssertEqual(print.notes.map(\.label), ["Deleted:"])
        XCTAssertEqual(print.notes.first?.paragraphs, ["<#>A pendant.¶", "<#>Tika Waylan¶"])
    }

    /// WordWithAttachments: a comment over a whole quatrain has its
    /// balloon level with the quatrain's last line, where its reference
    /// stands, not its first.
    func testACommentsBalloonHangsAtTheCommentsEnd() {
        var commented = CharStyle()
        commented.comments = ["3"]
        var doc = RichDocument(paragraphs: [
            paragraph([run("Всех, кто стар и кто молод,", commented)]),
            paragraph([run("Мы уйдем; и за нами", commented), run(" придут.")]),
        ])
        doc.keptParts["word/comments.xml"] = Data(("<w:comments xmlns:w=\"w\"><w:comment w:id=\"3\" w:author=\"vbiryukova\" w:initials=\"v\">"
            + "<w:p><w:r><w:t>Первое четверостишье</w:t></w:r></w:p></w:comment></w:comments>").utf8)
        let notes = PdfMarkup(doc).notes
        XCTAssertEqual(notes.map(\.label), ["Commented [v1]:"])
        XCTAssertEqual(notes.first?.anchor, RichPosition(paragraph: 1, offset: 19))
    }

    /// Tika-792: moved text was skipped whole, gone from the page and the
    /// save. Its new place is an insertion and its old a deletion, both
    /// marked moved; a save writes them back as an insertion and a
    /// deletion.
    func testMovedTextIsReadAndKept() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:r><w:t xml:space=\"preserve\">Here </w:t></w:r><w:moveTo w:id=\"1\" w:author=\"Author\"><w:r><w:t>moved</w:t></w:r></w:moveTo></w:p>"
            + "<w:p><w:r><w:t xml:space=\"preserve\">There </w:t></w:r><w:moveFrom w:id=\"2\" w:author=\"Author\"><w:r><w:t>moved</w:t></w:r></w:moveFrom></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(doc.paragraphs.map(\.text), ["Here moved", "There moved"])
        XCTAssertEqual(doc.paragraphs[0].runs.last?.style.revision, RevisionMark(kind: .inserted, author: "Author", moved: true))
        XCTAssertEqual(doc.paragraphs[1].runs.last?.style.revision, RevisionMark(kind: .deleted, author: "Author", moved: true))
        let saved = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data,
                           as: UTF8.self)
        XCTAssertTrue(saved.contains("moved</w:t></w:r></w:ins>") && saved.contains("moved</w:delText></w:r></w:del>"), saved)
        let print = PdfMarkup(doc)
        XCTAssertEqual(print.document.paragraphs.map(\.text), ["Here moved", "There "])
        XCTAssertEqual(print.notes.map(\.label), ["Moved (insertion) [1]", "Moved up [1]:"])
    }

    /// Tika-792: a period deleted in moved text's new place, and a "b"
    /// typed then moved away. Word prints the place "Moved (insertion)
    /// [1]" ahead of "Deleted: s." (in the deletion's own face), nothing
    /// for the "b" but how it had been reformatted, and no body text.
    func testAChangeInsideAMoveIsPrintedAsWordPrintsIt() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:del w:id=\"1\" w:author=\"A\"><w:r><w:delText>s</w:delText></w:r></w:del>"
            + "<w:moveTo w:id=\"3\" w:author=\"A\"><w:del w:id=\"4\" w:author=\"A\"><w:r><w:delText>.</w:delText></w:r></w:del></w:moveTo></w:p>"
            + "<w:p><w:moveFrom w:id=\"6\" w:author=\"A\"><w:ins w:id=\"7\" w:author=\"A\"><w:r><w:rPr><w:rPrChange w:id=\"8\" w:author=\"A\">"
            + "<w:rPr><w:color w:val=\"FF0000\"/></w:rPr></w:rPrChange></w:rPr><w:t>b</w:t></w:r></w:ins></w:moveFrom></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let print = PdfMarkup(doc)
        XCTAssertEqual(print.document.paragraphs.map(\.text), ["", ""])
        XCTAssertEqual(print.notes.map(\.label), ["Moved (insertion) [1]", "Deleted:", "Formatted:"])
        XCTAssertEqual(print.notes.map(\.paragraphs), [[""], ["s."], ["Font color: Auto"]])
        XCTAssertEqual(print.notes[1].family, doc.styles[RichNamedStyle.normalId]?.char.fontFamily.map(OfficeFonts.substitute))
        XCTAssertNotNil(print.notes[1].family)
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
    /// How much text a PDF's pages show: every `<…> Tj` string's bytes
    /// (a glyph's code is one or two, by the face).
    private func shownGlyphs(_ document: RichDocument) throws -> Int {
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("shown-\(UUID().uuidString).pdf").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertTrue(PdfExport.write(document, pageSetup: .a4, theme: theme, to: path, title: "t"))
        let pdf = try Data(contentsOf: URL(fileURLWithPath: path))
        var count = 0
        var from = pdf.startIndex
        while let start = pdf.range(of: Data("stream\n".utf8), in: from ..< pdf.endIndex),
              let end = pdf.range(of: Data("endstream".utf8), in: start.upperBound ..< pdf.endIndex) {
            from = end.upperBound
            guard let body = try? Zip.inflate(Data(pdf[start.upperBound ..< end.lowerBound].dropFirst(2)), expected: 4096) else { continue }
            let text = String(decoding: body, as: UTF8.self)
            guard text.contains(" Tf") else { continue }
            for piece in text.components(separatedBy: "> Tj").dropLast() {
                guard let open = piece.lastIndex(of: "<") else { continue }
                count += piece[piece.index(after: open)...].count / 2
            }
        }
        return count
    }

    func testAStretchOfItsOwnScaleIsPrintedOnce() throws {
        var squeezed = CharStyle()
        squeezed.horizontalScale = 0.8
        // (Mid-line, as zh-701eda18's "員" is between "聽打" and "本人":
        // what is left of the line round it is no one rectangle.)
        let mixed = RichDocument(paragraphs: [paragraph([run("BBBB"), run("AAAA", squeezed), run("CCCC")])])
        let plain = RichDocument(paragraphs: [paragraph([run("BBBB"), run("AAAA"), run("CCCC")])])
        let once = try shownGlyphs(plain)
        XCTAssertGreaterThanOrEqual(once, 12)
        // (Drawn twice, once under a clip that hides it: a PDF keeps
        // what a clip hides, and its text read "BBBBAAAACCCCAAAA".)
        XCTAssertEqual(try shownGlyphs(mixed), once)
    }
}
