// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
#if canImport(FoundationXML)
import FoundationXML   // XMLParser, off Darwin
#endif
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class DocxTests: XCTestCase {
    // (ICU's data before this class lays any text out: a run filtered to
    // it has no `AAATextSetupTests` ahead of it.)
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
    }

    private func sample() -> RichDocument {
        var paragraphs: [RichParagraph] = []
        paragraphs.append(RichParagraph(text: "Title — with an em dash", style: RichParagraphStyle(heading: 1)))
        var body = RichParagraph(text: "Plain, then bold, then italic, then both.")
        body.applyStyle(12 ..< 16) { $0.bold = true }
        body.applyStyle(23 ..< 29) { $0.italic = true }
        body.applyStyle(36 ..< 40) { $0.bold = true; $0.italic = true; $0.underline = true; $0.color = Color(0xFFFF0000) }
        paragraphs.append(body)
        paragraphs.append(RichParagraph(text: "First bullet", style: RichParagraphStyle(list: .bullet)))
        paragraphs.append(RichParagraph(text: "Nested bullet", style: RichParagraphStyle(list: .bullet, listLevel: 1)))
        paragraphs.append(RichParagraph(text: "Numbered", style: RichParagraphStyle(list: .numbered)))
        paragraphs.append(RichParagraph(text: "Centred 中文 😀 tab\there", style: RichParagraphStyle(alignment: .center)))
        var link = RichParagraph(text: "See the site.")
        link.applyStyle(4 ..< 12) { $0.link = "https://example.com/a?b=1&c=2" }
        paragraphs.append(link)
        var next = RichParagraph(text: "On a new page, highlighted", style: RichParagraphStyle(pageBreakBefore: true))
        next.applyStyle(15 ..< 26) { $0.highlight = Color(0xFFFFFF00) }
        paragraphs.append(next)
        return RichDocument(paragraphs: paragraphs)
    }

    /// A cached placeholder is shared by named inline text controls. A
    /// filled control, a different name, and a block control keep their
    /// own content (Word's 55966 and independently printed variants).
    func testNamedInlinePlaceholders() throws {
        func control(_ text: String, name: String = "Shared", showing: String = "<w:showingPlcHdr/>", block: Bool = false) -> String {
            let runs = "<w:r><w:t>\(text)</w:t></w:r>"
            return "<w:sdt><w:sdtPr><w:placeholder><w:docPart w:val=\"\(name)\"/></w:placeholder>\(showing)<w:text w:multiLine=\"1\"/></w:sdtPr><w:sdtContent>\(block ? "<w:p>\(runs)</w:p>" : runs)</w:sdtContent></w:sdt>"
        }
        func read(_ body: String) throws -> RichDocument {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
            let i = entries.firstIndex { $0.name == "word/document.xml" }!
            entries[i] = ZipEntry(name: "word/document.xml", data: Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(body)</w:body></w:document>".utf8))
            return try DocxFormat.read(Zip.write(entries)).document
        }
        let shared = try read("<w:p>\(control("First"))\(control("Stale"))</w:p><w:p>\(control("Also stale"))</w:p>\(control("Block", block: true))")
        XCTAssertEqual(shared.paragraphs.map(\.text), ["FirstFirst", "First", "Block"])
        XCTAssertEqual(try DocxFormat.read(DocxFormat.write(shared, pageSetup: .letter)).document.paragraphs.map(\.text), shared.paragraphs.map(\.text))

        for flag in ["", "<w:showingPlcHdr w:val=\"0\"/>", "<w:showingPlcHdr w:val=\"false\"/>"] {
            let filled = try read("<w:p>\(control("Filled", showing: flag))\(control("Placeholder"))\(control("Stale"))\(control("Own content", showing: flag))</w:p>")
            XCTAssertEqual(filled.paragraphs.map(\.text), ["FilledPlaceholderPlaceholderOwn content"])
        }
        let distinct = try read("<w:p>\(control("First"))\(control("Different", name: "Other"))\(control("Unnamed", name: ""))\(control("Independent", name: ""))</w:p>")
        XCTAssertEqual(distinct.paragraphs.map(\.text), ["FirstDifferentUnnamedIndependent"])
        XCTAssertEqual(try read("<w:p>\(control("Another document"))</w:p>").paragraphs.map(\.text), ["Another document"])
    }

    /// Characters XML 1.0 cannot hold never reach the saved part: the
    /// copy of LibreOffice's EDB-36788-1 (bytes that were never a
    /// document, read as text) had 3,508 of them in its document.xml and
    /// no parser opened it.
    func testControlCharactersNeverReachTheXML() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "A\u{1}B\u{19}C\u{0}D\u{FFFE}E tab\there & <more>")])
        let saved = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let xml = try XCTUnwrap(saved.first { $0.name == "word/document.xml" }).data
        let parser = XMLParser(data: xml)
        XCTAssertTrue(parser.parse(), "document.xml must be well-formed: \(String(describing: parser.parserError))")
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs.map(\.text), ["ABCDE tab\there & <more>"])
    }

    /// A page break does not add a paragraph on every save. Where the
    /// file says the paragraph mark follows the break
    /// (`w:splitPgBreakAndParaMark`, before 2013's layout) each shape
    /// below read as one paragraph more after a save — LibreOffice's
    /// tdf123636_newlinePageBreak and its twelve like it.
    func testPageBreakDoesNotAddParagraphsOnEverySave() throws {
        func read(_ body: String) throws -> RichDocument {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
            let i = entries.firstIndex { $0.name == "word/document.xml" }!
            entries[i] = ZipEntry(name: "word/document.xml", data: Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(body)<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/></w:sectPr></w:body></w:document>".utf8))
            let s = entries.firstIndex { $0.name == "word/settings.xml" }!
            entries[s] = ZipEntry(name: "word/settings.xml", data: Data("<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:compat><w:splitPgBreakAndParaMark/><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"12\"/></w:compat></w:settings>".utf8))
            return try DocxFormat.read(Zip.write(entries)).document
        }
        let page = "<w:r><w:br w:type=\"page\"/></w:r>"
        func run(_ text: String) -> String { "<w:r><w:t>\(text)</w:t></w:r>" }
        let shapes: [String: String] = [
            "break alone": "<w:p>\(page)</w:p>",
            "text then break": "<w:p>\(run("A"))\(page)</w:p>",
            "text, break, text": "<w:p>\(run("A"))\(page)\(run("B"))</w:p>",
            "break alone, then a paragraph": "<w:p>\(page)</w:p><w:p>\(run("Next"))</w:p>",
            "text then break, then a paragraph": "<w:p>\(run("A"))\(page)</w:p><w:p>\(run("Next"))</w:p>",
        ]
        for (name, body) in shapes {
            let first = try read(body)
            let saved = try DocxFormat.write(first, pageSetup: .letter)
            let again = try DocxFormat.read(saved).document
            XCTAssertEqual(again.paragraphs.map(\.text), first.paragraphs.map(\.text), name)
            XCTAssertEqual(again.paragraphs.count, first.paragraphs.count, "\(name): paragraphs after one save")
            let twice = try DocxFormat.read(DocxFormat.write(again, pageSetup: .letter)).document
            XCTAssertEqual(twice.paragraphs.count, first.paragraphs.count, "\(name): paragraphs after two saves")
        }
    }

    /// The main part is the one the root relationships name, wherever it
    /// stands in `word/`: LibreOffice's tdf104713_undefinedStyles calls it
    /// `word/trial.xml`, with `word/_rels/trial.xml.rels` beside it.
    func testMainPartNamedByTheRootRelationships() throws {
        let plain = try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "Named by the root relationships")]), pageSetup: .letter)
        var entries = try Zip.read(plain)
        entries = entries.map { e in
            switch e.name {
            case "word/document.xml": return ZipEntry(name: "word/trial.xml", data: e.data)
            case "word/_rels/document.xml.rels": return ZipEntry(name: "word/_rels/trial.xml.rels", data: e.data)
            case "_rels/.rels":
                return ZipEntry(name: e.name, data: Data(String(decoding: e.data, as: UTF8.self).replacingAll("word/document.xml", with: "word/trial.xml").utf8))
            default: return e
            }
        }
        XCTAssertFalse(entries.contains { $0.name == "word/document.xml" })
        let back = try DocxFormat.read(Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs.map(\.text), ["Named by the root relationships"])
        let saved = try Zip.read(try DocxFormat.write(back, pageSetup: .letter))
        XCTAssertTrue(saved.contains { $0.name == "word/document.xml" }, "saved under the usual name")
        // No such part anywhere: still the error, not a guess.
        XCTAssertThrowsError(try DocxFormat.read(Zip.write(entries.filter { $0.name != "word/trial.xml" })))
    }

    /// A save loses no paragraph's text. LibreOffice's tdf123163-1 sets a
    /// section's columns as a table whose markup is kept for the save, and
    /// a paragraph whose picture names media the package does not hold had
    /// none: the copy left that paragraph's text out. (The copy no longer
    /// points at the picture that was never there, so its columns read as
    /// a table the second time and the paragraph counts differ: no text.)
    func testSectionColumnsKeepAParagraphWhoseMediaIsMissing() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/lo-d88152cce1e2574c.docx")
        guard let data = try? Data(contentsOf: file) else { throw XCTSkip("the LibreOffice set is not checked out") }
        let first = try DocxFormat.read(data).document
        let saved = try DocxFormat.write(first, pageSetup: .letter)
        let xml = String(decoding: try XCTUnwrap(try Zip.read(saved).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
        let lost = first.paragraphs.map(\.text).filter { text in
            let word = text.replacingOccurrences(of: "\u{FFFC}", with: " ").replacingOccurrences(of: "\u{00AD}", with: " ").split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
            return !word.isEmpty && !xml.contains(word)
        }
        XCTAssertEqual(lost, [], "paragraphs whose last word is not in the saved document")
    }

    /// A table nested in a cell that floats only in name (against the text,
    /// from the column's edge, a twip under its paragraph's top) is an
    /// inline block shifted by its x, so that it parts between its rows
    /// over a page break as one does: LibreOffice's tdf170381, a 75pt table
    /// in a 383pt cell, was a floating box that ran off the page's foot.
    func testNominallyFloatingNestedTableIsAnInlineBlock() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/lo-1e0077c34b69d826.docx")
        guard let data = try? Data(contentsOf: file) else { throw XCTSkip("the LibreOffice set is not checked out") }
        let doc = try DocxFormat.read(data).document
        let boxes = doc.paragraphs.filter { $0.image?.textBox?.growsToFit == true }
        XCTAssertEqual(boxes.count, 1)
        let box = try XCTUnwrap(boxes.first)
        XCTAssertNil(box.image?.float, "set in the flow, not floated")
        XCTAssertEqual(box.style.indentLeft, 11.35, accuracy: 0.01, "shifted by its tblpX")
        XCTAssertEqual(box.image?.width ?? 0, 74.85, accuracy: 0.01)
    }

    func testRightToLeftRunsResolveTheirComplexScriptFont() {
        let theme = RichTextTheme(fontFamily: "Latin default")
        theme.fontFamilyResolver = { _ in "Latin clone" }
        var normal = CharStyle()
        normal.complexFontFamily = "Inherited Arabic"
        var run = CharStyle()
        run.fontFamily = "Latin"
        run.rightToLeft = true
        func family() -> String? { theme.textStyle(for: run, in: RichParagraphStyle(), normal: normal, scale: 1).fontFamily }
        XCTAssertEqual(family(), "Inherited Arabic", "the Latin clone cannot supply Arabic")
        run.complexFontFamily = "Run Arabic"
        XCTAssertEqual(family(), "Run Arabic")
        theme.complexFaceResolver = { RichResolvedFace(family: "Embedded " + ($0 ?? "")) }
        XCTAssertEqual(family(), "Embedded Run Arabic")
        run.rightToLeft = false
        XCTAssertEqual(family(), "Latin clone", "Latin text inside a bidi paragraph keeps its Latin face")
    }

    /// A file with a footnotes part: the mark reads as its number in
    /// superscript, and a save carries the part, its rels, the reference
    /// and the note styles back out — Word then shows the note again.
    func testFootnotesKeptThroughSave() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "Body with a note here.")])
        doc.paragraphs[0].applyStyle(0 ..< 4) { $0.bold = true }
        let plain = try DocxFormat.write(doc, pageSetup: .letter)
        var entries = try Zip.read(plain)
        let footnotes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:id="1"><w:p><w:pPr><w:pStyle w:val="FootnoteText"/></w:pPr><w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> The note's text.</w:t></w:r></w:p></w:footnote></w:footnotes>
        """
        entries.append(ZipEntry(name: "word/footnotes.xml", data: Data(footnotes.utf8)))
        let i = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[i].data, as: UTF8.self)
        xml = xml.replacingAll("<w:t xml:space=\"preserve\"> with a note here.</w:t></w:r>",
                               with: "<w:t xml:space=\"preserve\"> with a note</w:t></w:r><w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:footnoteReference w:id=\"1\"/></w:r><w:r><w:t xml:space=\"preserve\"> here.</w:t></w:r>")
        XCTAssertTrue(xml.contains("w:footnoteReference"), "the fixture's run text must match: \(xml)")
        entries[i] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let planted = try Zip.write(entries)

        let back = try DocxFormat.read(planted).document
        XCTAssertEqual(back.paragraphs[0].text, "Body with a note1 here.")
        XCTAssertEqual(back.keptParts.keys.sorted(), ["word/footnotes.xml"])
        let mark = back.paragraphs[0].runs.first { $0.style.note != nil }
        XCTAssertEqual(mark?.style.note, NoteReference(kind: .footnote, id: 1))
        XCTAssertEqual(mark?.style.script, .superscript)
        XCTAssertEqual(mark?.length, 1)

        let saved = try Zip.read(try DocxFormat.write(back, pageSetup: .letter))
        func text(_ name: String) -> String { String(decoding: saved.first { $0.name == name }?.data ?? Data(), as: UTF8.self) }
        XCTAssertEqual(text("word/footnotes.xml"), footnotes)
        let body = text("word/document.xml")
        XCTAssertTrue(body.contains("<w:footnoteReference w:id=\"1\"/>"), body)
        XCTAssertFalse(body.contains("<w:t>1</w:t>"), "the number is Word's to show")
        XCTAssertTrue(text("word/_rels/document.xml.rels").contains("Target=\"footnotes.xml\""))
        XCTAssertTrue(text("[Content_Types].xml").contains("/word/footnotes.xml"))
        XCTAssertTrue(text("word/styles.xml").contains("w:styleId=\"FootnoteText\""))
        // Word's default table style is always there: without it Word (in
        // its legacy mode) set form_footnotes' tables 5pt to the right.
        XCTAssertTrue(text("word/styles.xml").contains("<w:style w:type=\"table\" w:default=\"1\" w:styleId=\"TableNormal\"><w:name w:val=\"Normal Table\"/><w:uiPriority w:val=\"99\"/><w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w=\"0\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"108\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr></w:style>"), text("word/styles.xml"))
        // Read again: still one mark, the same note.
        let again = try DocxFormat.read(try DocxFormat.write(back, pageSetup: .letter)).document
        XCTAssertEqual(again.paragraphs[0].text, "Body with a note1 here.")
        XCTAssertEqual(again.paragraphs[0].runs.filter { $0.style.note != nil }.count, 1)
    }

    /// Theme font references resolve through the file's theme (and the
    /// theme rides along); a table's indent and row heights survive.
    func testThemeFontsIndentAndRowHeights() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "Body")])
        var a = RichParagraph(text: "cell"); a.cell = CellRef(table: "t", row: 0, column: 0)
        var b = RichParagraph(text: "cell"); b.cell = CellRef(table: "t", row: 1, column: 0)
        doc.paragraphs += [a, b, RichParagraph()]
        doc.tableColumns["t"] = [200]
        doc.tableStyles["t"] = TableStyle(indent: 36, rowHeights: [1: 48])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let theme = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="T"><a:themeElements><a:fontScheme name="F"><a:majorFont><a:latin typeface="Georgia"/></a:majorFont><a:minorFont><a:latin typeface="Cambria"/></a:minorFont></a:fontScheme></a:themeElements></a:theme>
        """
        entries.append(ZipEntry(name: "word/theme/theme1.xml", data: Data(theme.utf8)))
        let i = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[i].data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:tblInd w:w=\"720\" w:type=\"dxa\"/>"), xml)
        XCTAssertTrue(xml.contains("<w:tr><w:trPr><w:trHeight w:val=\"960\"/></w:trPr>"), xml)
        xml = xml.replacingAll("<w:t xml:space=\"preserve\">Body</w:t>",
                               with: "<w:rPr><w:rFonts w:asciiTheme=\"minorHAnsi\" w:hAnsiTheme=\"minorHAnsi\"/></w:rPr><w:t xml:space=\"preserve\">Body</w:t>")
        entries[i] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].runs.first?.style.fontFamily, "Cambria")
        let style = back.tableStyles[back.paragraphs[1].cell!.table]
        XCTAssertEqual(style?.indent, 36)
        XCTAssertEqual(style?.rowHeights, [1: 48])
        // Header/footer distances survive (the fixture's default, 708 twips).
        let setup = try XCTUnwrap(DocxFormat.read(try Zip.write(entries)).pageSetup)
        XCTAssertEqual(setup.headerDistance, 35.4, accuracy: 0.01)
        var narrow = PageSetup.letter; narrow.headerDistance = 0; narrow.footerDistance = 10
        XCTAssertTrue(String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: narrow)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self).contains("w:header=\"0\" w:footer=\"200\""))
        // Cell margins: the table style said nothing, so Word's own.
        XCTAssertEqual(style?.cellMarginTop, 0)
        XCTAssertEqual(style?.cellMarginLeft, 5.4)
        XCTAssertEqual(back.keptParts.keys.sorted(), ["word/theme/theme1.xml"])
        let saved = try Zip.read(try DocxFormat.write(back, pageSetup: .letter))
        func text(_ name: String) -> String { String(decoding: saved.first { $0.name == name }?.data ?? Data(), as: UTF8.self) }
        XCTAssertEqual(text("word/theme/theme1.xml"), theme)
        XCTAssertTrue(text("word/_rels/document.xml.rels").contains("Target=\"theme/theme1.xml\""))
        XCTAssertTrue(text("[Content_Types].xml").contains("theme+xml"))
        XCTAssertTrue(text("word/document.xml").contains("w:ascii=\"Cambria\""))
        XCTAssertTrue(text("word/document.xml").contains("<w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"108\" w:type=\"dxa\"/></w:tblCellMar>"), text("word/document.xml"))
    }

    /// A chart (or any drawing that is not a picture) is kept as the file
    /// wrote it: its markup, its part and what that reaches, their content
    /// types, the relationship under a fresh id — and it lays out as an
    /// empty box of its size.
    func testChartKeptVerbatim() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "Before"), RichParagraph(text: "After")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        func replace(_ name: String, _ f: (String) -> String) {
            let i = entries.firstIndex { $0.name == name }!
            entries[i] = ZipEntry(name: name, data: Data(f(String(decoding: entries[i].data, as: UTF8.self)).utf8))
        }
        let drawing = "<w:drawing><wp:inline><wp:extent cx=\"2540000\" cy=\"1270000\"/><wp:docPr id=\"7\" name=\"Chart 1\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" r:id=\"rId77\"/></a:graphicData></a:graphic></wp:inline></w:drawing>"
        replace("word/document.xml") { $0.replacingAll("<w:t xml:space=\"preserve\">Before</w:t></w:r>",
                                                       with: "<w:t xml:space=\"preserve\">Before</w:t></w:r><w:r>\(drawing)</w:r>") }
        replace("word/_rels/document.xml.rels") { $0.replacingAll("</Relationships>",
            with: "<Relationship Id=\"rId77\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart1.xml\"/></Relationships>") }
        replace("[Content_Types].xml") { $0.replacingAll("</Types>",
            with: "<Override PartName=\"/word/charts/chart1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/><Default Extension=\"xlsx\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/></Types>") }
        let chart = "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><c:externalData r:id=\"rId1\"/></c:chartSpace>"
        entries.append(ZipEntry(name: "word/charts/chart1.xml", data: Data(chart.utf8)))
        entries.append(ZipEntry(name: "word/charts/_rels/chart1.xml.rels", data: Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/package\" Target=\"../embeddings/book1.xlsx\"/></Relationships>".utf8)))
        entries.append(ZipEntry(name: "word/embeddings/book1.xlsx", data: Data([1, 2, 3, 4])))

        let back = try DocxFormat.read(try Zip.write(entries)).document
        // In the line with the text, as the file had it.
        XCTAssertEqual(back.paragraphs.map(\.text), ["Before" + RichParagraph.inlineImageCharacter, "After"])
        let mark = try XCTUnwrap(back.paragraphs[0].runs.first { $0.style.inlineImage != nil })
        XCTAssertEqual(mark.length, 1)
        let object = back.paragraphs[0].inlineImages[mark.style.inlineImage!]
        XCTAssertEqual(object?.width ?? 0, 200, accuracy: 0.01)
        XCTAssertEqual(object?.height ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(object?.sourceRels.map(\.target), ["charts/chart1.xml"])
        XCTAssertTrue(object?.sourceXML?.contains("<c:chart") == true, object?.sourceXML ?? "nil")
        XCTAssertEqual(back.keptParts.keys.sorted(), ["word/charts/_rels/chart1.xml.rels", "word/charts/chart1.xml", "word/embeddings/book1.xlsx"])
        XCTAssertEqual(back.keptPartTypes["word/charts/chart1.xml"], "application/vnd.openxmlformats-officedocument.drawingml.chart+xml")
        XCTAssertEqual(back.keptPartTypes["word/embeddings/book1.xlsx"], "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

        let saved = try Zip.read(try DocxFormat.write(back, pageSetup: .letter))
        func text(_ name: String) -> String { String(decoding: saved.first { $0.name == name }?.data ?? Data(), as: UTF8.self) }
        let body = text("word/document.xml")
        XCTAssertTrue(body.contains("<c:chart r:id=\"rIdKept1\" xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"/>"), body)
        XCTAssertFalse(body.contains("rId77"))
        XCTAssertTrue(text("word/_rels/document.xml.rels").contains("Id=\"rIdKept1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart\" Target=\"charts/chart1.xml\""))
        XCTAssertEqual(text("word/charts/chart1.xml"), chart)
        XCTAssertEqual(saved.first { $0.name == "word/embeddings/book1.xlsx" }?.data, Data([1, 2, 3, 4]))
        XCTAssertTrue(text("[Content_Types].xml").contains("PartName=\"/word/charts/chart1.xml\""))
        XCTAssertTrue(text("[Content_Types].xml").contains("PartName=\"/word/embeddings/book1.xlsx\""))
        // And the same again from the copy.
        let again = try DocxFormat.read(try Zip.write(saved)).document
        XCTAssertEqual(again.paragraphs[0].inlineImages.values.first?.sourceRels.map(\.id), ["rIdKept1"])
        XCTAssertTrue(body.contains("<w:t xml:space=\"preserve\">Before</w:t></w:r><w:r><w:drawing"), body)
    }

    /// A picture inline with text takes its place in the line: the
    /// paragraph is as tall as the picture, and the text around it stays
    /// in the same paragraph through a save.
    func testInlinePictureLaysOutInTheLine() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var p = RichParagraph(text: "before" + RichParagraph.inlineImageCharacter + "after")
        let image = ImageAttachment(data: png, width: 120, height: 90)
        p.inlineImages[image.id] = image
        p.applyStyle(6 ..< 7) { $0.inlineImage = image.id }
        let doc = RichDocument(paragraphs: [p, RichParagraph(text: "plain")])
        let dump = OfficeLayoutDump.text(doc, pageSetup: .letter)
        // "¶0 block H" — the paragraph's height, in px: at least the picture's.
        let line = try XCTUnwrap(dump.split(separator: "\n").first { $0.hasPrefix("¶0 block") })
        let height = try XCTUnwrap(Double(line.split(separator: " ")[2]))
        XCTAssertGreaterThanOrEqual(height, 90, String(line))
        let plain = try XCTUnwrap(dump.split(separator: "\n").first { $0.hasPrefix("¶1 block") })
        XCTAssertLessThan(try XCTUnwrap(Double(plain.split(separator: " ")[2])), 40, String(plain))
        // And through a .docx: still one paragraph, picture between the words.
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].text, "before" + RichParagraph.inlineImageCharacter + "after")
        XCTAssertEqual(back.paragraphs[0].inlineImages.count, 1)
        XCTAssertEqual(back.paragraphs[0].inlineImages.values.first?.width ?? 0, 120, accuracy: 0.01)
    }

    /// Tracked changes stay tracked: an insertion and a deletion read as
    /// marked runs and are written back as the changes they were, so Word
    /// shows the same markup for the copy.
    func testCellLevelBordersAndMarginsBecomeTheTables() throws {
        // An HTML-converted table: nothing on the table, every cell says
        // its own grey borders and 72-twip margins.
        var a = RichParagraph(text: "a"), b = RichParagraph(text: "b")
        a.cell = CellRef(table: "T", row: 0, column: 0)
        b.cell = CellRef(table: "T", row: 0, column: 1)
        var doc = RichDocument(paragraphs: [a, b, RichParagraph(text: "")])
        doc.tableColumns["T"] = [100, 100]
        doc.tableStyles["T"] = TableStyle(borders: false)
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let i = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[i].data, as: UTF8.self)
        xml = xml.replacingAll("<w:tcPr>", with: "<w:tcPr><w:tcBorders><w:top w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"E1E1E1\"/><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"E1E1E1\"/></w:tcBorders><w:tcMar><w:top w:w=\"72\" w:type=\"dxa\"/><w:left w:w=\"72\" w:type=\"dxa\"/><w:bottom w:w=\"72\" w:type=\"dxa\"/><w:right w:w=\"72\" w:type=\"dxa\"/></w:tcMar>")
        XCTAssertTrue(xml.contains("w:tcMar"), xml)
        // Nothing on the table itself, as an HTML conversion writes it.
        xml = xml.replacingAll(String(xml[xml.range(of: "<w:tblBorders>")!.lowerBound ..< xml.range(of: "</w:tblBorders>")!.upperBound]), with: "")
        entries[i] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let ts = try XCTUnwrap(back.tableStyles.values.first)
        XCTAssertTrue(ts.borders)
        XCTAssertEqual(ts.borderColor, Color(0xFFE1E1E1))
        XCTAssertEqual([ts.cellMarginTop, ts.cellMarginLeft, ts.cellMarginBottom, ts.cellMarginRight], [3.6, 3.6, 3.6, 3.6])
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(ts.borderWidth, 0.75)
        // (The cells' own border markup is kept, attributes in the serializer's order.)
        XCTAssertTrue(saved.contains("<w:top w:color=\"E1E1E1\" w:space=\"0\" w:sz=\"6\" w:val=\"single\"/>"), saved)
        // Ruled through its cells, nothing at the table level: written back
        // the same way — no w:tblBorders, every cell its own sides.
        XCTAssertTrue(ts.bordersFromCells)
        XCTAssertFalse(saved.contains("<w:tblBorders>"), saved)
        XCTAssertEqual(saved.components(separatedBy: "<w:tcBorders><w:top w:color=\"E1E1E1\" w:space=\"0\" w:sz=\"6\" w:val=\"single\"/><w:bottom w:color=\"E1E1E1\" w:space=\"0\" w:sz=\"6\" w:val=\"single\"/></w:tcBorders>").count, 3, saved)
        // Borders toggled off in the editor: the kept markup steps aside.
        var off = back
        off.tableStyles[off.tableStyles.keys.first!]!.borders = false
        let offXML = String(decoding: try Zip.read(try DocxFormat.write(off, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertFalse(offXML.contains("w:color=\"E1E1E1\" w:space=\"0\" w:sz=\"6\" w:val=\"single\""), offXML)
        // The margins go back where the file had them: each cell's own,
        // over the table's (Word's defaults here) — a cell that states
        // none must not inherit its neighbours' (drawing.docx).
        XCTAssertEqual(saved.components(separatedBy: "<w:tcMar><w:top w:type=\"dxa\" w:w=\"72\"/>").count, 3, saved)
        XCTAssertTrue(saved.contains("<w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/>"), saved)
    }

    func testHeaderFooterTabsAreThirds() throws {
        // A footer "name <right tab> Page N": the positional tab reads as
        // two tabs (left, centre, right thirds), and the thirds write back
        // as Word's centre and right tab stops.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "x")])
        doc.footer = "Left\t\tPage {PAGE}"
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/footer1.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:tabs><w:tab w:val=\"center\" w:pos=\"4680\"/><w:tab w:val=\"right\" w:pos=\"9360\"/></w:tabs>"), xml)
        XCTAssertTrue(xml.contains("<w:r><w:tab/></w:r><w:r><w:tab/></w:r>"), xml)
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document.footer, "Left\t\tPage {PAGE}")
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let i = entries.firstIndex { $0.name == "word/footer1.xml" }!
        entries[i] = ZipEntry(name: "word/footer1.xml", data: Data(xml.replacingAll("<w:r><w:tab/></w:r><w:r><w:tab/></w:r>", with: "<w:r><w:ptab w:relativeTo=\"margin\" w:alignment=\"right\" w:leader=\"none\"/></w:r>").utf8))
        XCTAssertEqual(try DocxFormat.read(try Zip.write(entries)).document.footer, "Left\t\tPage {PAGE}")
    }

    func testStyleNumberingColourAutoAndConditionalTableParts() throws {
        // 65099: a heading style based on a blue Heading 3 that says
        // colour auto and carries its own numPr, and a table style whose
        // first row is white on black with grey bands.
        var a = RichParagraph(text: "Acronym"), b = RichParagraph(text: "Definition"), c = RichParagraph(text: "LAB"), d = RichParagraph(text: "Logical")
        a.cell = CellRef(table: "T", row: 0, column: 0); b.cell = CellRef(table: "T", row: 0, column: 1)
        c.cell = CellRef(table: "T", row: 1, column: 0); d.cell = CellRef(table: "T", row: 1, column: 1)
        var doc = RichDocument(paragraphs: [RichParagraph(text: "Acronyms"), a, b, c, d, RichParagraph(text: "")])
        doc.tableColumns["T"] = [100, 100]
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        styles = styles.replacingAll("</w:styles>", with: "<w:style w:type=\"paragraph\" w:customStyle=\"1\" w:styleId=\"EdfTitre3\"><w:name w:val=\"Edf Titre 3\"/><w:basedOn w:val=\"Heading3\"/><w:pPr><w:numPr><w:ilvl w:val=\"2\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:rPr><w:b/><w:color w:val=\"auto\"/></w:rPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"Body\"><w:name w:val=\"Body\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"120\"/></w:pPr></w:style><w:style w:type=\"table\" w:styleId=\"Grid4\"><w:name w:val=\"Grid 4\"/><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:tblPr><w:tblBorders><w:top w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"666666\"/></w:tblBorders></w:tblPr><w:tblStylePr w:type=\"firstCol\"><w:rPr><w:b/></w:rPr></w:tblStylePr><w:tblStylePr w:type=\"firstRow\"><w:rPr><w:b/><w:color w:val=\"FFFFFF\"/></w:rPr><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"000000\"/></w:tcPr></w:tblStylePr><w:tblStylePr w:type=\"band1Horz\"><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"CCCCCC\"/></w:tcPr></w:tblStylePr></w:style></w:styles>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        if let first = xml.range(of: "<w:p><w:pPr><w:spacing") {   // the first paragraph only
            xml.replaceSubrange(first, with: "<w:p><w:pPr><w:pStyle w:val=\"EdfTitre3\"/><w:spacing")
        }
        xml = xml.replacingAll("<w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/>", with: "<w:tblPr><w:tblStyle w:val=\"Grid4\"/><w:tblW w:w=\"0\" w:type=\"auto\"/>")
        xml = xml.replacingAll("<w:tblBorders>", with: "<w:tblBordersX>").replacingAll("</w:tblBorders>", with: "</w:tblBordersX>")
        // Every cell paragraph in the Body style (its spacing then comes from the chain).
        xml = xml.replacingAll("<w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p><w:pPr>", with: "<w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p><w:pPr><w:pStyle w:val=\"Body\"/>")
        xml = xml.replacingAll("<w:pStyle w:val=\"Body\"/><w:spacing w:after=\"160\" w:line=\"259\" w:lineRule=\"auto\"/>", with: "<w:pStyle w:val=\"Body\"/>")
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Body\"/>"), xml)
        xml = xml.replacingAll("<w:tblLook w:val=\"04A0\"/>", with: "<w:tblLook w:val=\"04A0\" w:firstRow=\"1\" w:firstColumn=\"1\" w:noHBand=\"0\"/>")
        let ni = entries.firstIndex { $0.name == "word/numbering.xml" }
        let numbering = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1\"/></w:lvl><w:lvl w:ilvl=\"1\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.%2\"/></w:lvl><w:lvl w:ilvl=\"2\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.%2.%3\"/><w:pPr><w:ind w:left=\"720\" w:hanging=\"720\"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        if let ni { entries[ni] = ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8)) }
        XCTAssertNotNil(ni, "the writer always ships a numbering part")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let h = back.paragraphs[0]
        XCTAssertEqual(h.style.list, .numbered)
        XCTAssertEqual(h.style.listLevel, 2)
        XCTAssertEqual(h.style.listId, "1")
        XCTAssertNil(back.styles["EdfTitre3"]?.char.color, "auto clears the inherited blue")
        XCTAssertTrue(back.styles["EdfTitre3"]?.char.bold ?? false)
        let cells = back.paragraphs.filter { $0.cell != nil }
        XCTAssertEqual(cells.map { $0.cell?.fill }, [Color(0xFF000000), Color(0xFF000000), Color(0xFFCCCCCC), Color(0xFFCCCCCC)])
        XCTAssertEqual(cells[0].runs[0].style.color, Color(0xFFFFFFFF))
        XCTAssertTrue(cells[0].runs[0].style.bold)
        XCTAssertNil(cells[2].runs[0].style.color)
        XCTAssertTrue(cells[2].runs[0].style.bold, "firstCol: the first column is bold")
        XCTAssertFalse(cells[3].runs[0].style.bold)
        // The numbering level's own indents survive the save.
        XCTAssertEqual(back.listFormats["1"]?[2]?.indentLeft, 36)
        XCTAssertEqual(back.listFormats["1"]?[2]?.hanging, 36)
        let savedNum = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/numbering.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(savedNum.contains("<w:lvlText w:val=\"%1.%2.%3\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"720\" w:hanging=\"720\"/></w:pPr>"), savedNum)
        XCTAssertEqual(back.tableStyles.values.first?.borderColor, Color(0xFF666666))
        // Inside the cells, the table style's line rule lies under the
        // paragraph style's: Body (after 120, no line) over Grid4's
        // single lines, not over the document's 1.15.
        XCTAssertEqual(cells[0].style.lineSpacing, 1.0, accuracy: 0.001)
        XCTAssertEqual(cells[0].style.spaceAfter, 6, accuracy: 0.001)
    }

    func testFileListIdsKeptAlternateContentOnceAndExplicitLeft() throws {
        // A file's list keeps its numId (kept text boxes still name it),
        // our own bullets go above it; a footer text box is read once,
        // not Choice plus Fallback; left under a centred style is written.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "Job"), RichParagraph(text: "Plain bullet"), RichParagraph(text: "Centred style, left")])
        doc.listFormats["10"] = [0: ListLevelFormat(text: ">", format: .bullet)]
        doc.paragraphs[0].style.list = .bullet; doc.paragraphs[0].style.listId = "10"
        doc.paragraphs[1].style.list = .bullet
        doc.styles["Centred"] = RichNamedStyle(id: "Centred", name: "Centred", paragraph: RichParagraphStyle(alignment: .center), char: CharStyle())
        doc.paragraphs[2].style.named = "Centred"
        doc.paragraphs[2].style.alignment = .left
        let entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let xml = String(decoding: entries.first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        let numbering = String(decoding: entries.first { $0.name == "word/numbering.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:numId w:val=\"10\"/>"), xml)
        XCTAssertTrue(xml.contains("<w:numId w:val=\"11\"/>"), xml)
        XCTAssertTrue(numbering.contains("<w:num w:numId=\"10\"><w:abstractNumId w:val=\"11\"/></w:num>"), numbering)
        XCTAssertTrue(numbering.contains("<w:num w:numId=\"11\"><w:abstractNumId w:val=\"0\"/></w:num>"), numbering)
        XCTAssertTrue(numbering.contains("<w:lvlText w:val=\"&gt;\"/>"), numbering)
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Centred\"/>"), xml)
        XCTAssertTrue(xml.contains("<w:jc w:val=\"left\"/>"), xml)
        // An indent the style sets and the paragraph unsets is written as 0.
        var hung = doc
        hung.styles["Hung"] = RichNamedStyle(id: "Hung", name: "Hung", paragraph: RichParagraphStyle(indentLeft: -54, firstLineIndent: -18), char: CharStyle())
        hung.paragraphs[2].style.named = "Hung"
        hung.paragraphs[2].style.indentLeft = 0
        hung.paragraphs[2].style.firstLineIndent = 0
        let hungXML = String(decoding: try Zip.read(try DocxFormat.write(hung, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(hungXML.contains("<w:ind w:left=\"0\" w:firstLine=\"0\" w:hanging=\"0\"/>"), hungXML)
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(hung, pageSetup: .letter)).document.paragraphs[2].style.indentLeft, 0)
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[2].style.alignment, .left)
        XCTAssertEqual(back.paragraphs[0].style.listId, "10")
        // A list paragraph's own left (bug65649: 0 under a level at 6186
        // twips) is direct formatting above the level's, and is kept.
        var own = doc
        own.paragraphs[0].style.listIndentLeft = 0
        own.paragraphs[0].style.firstLineIndent = 28.35
        let ownXML = String(decoding: try Zip.read(try DocxFormat.write(own, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(ownXML.contains("<w:ind w:left=\"0\" w:firstLine=\"567\"/>"), ownXML)
        let ownBack = try DocxFormat.read(try DocxFormat.write(own, pageSetup: .letter)).document
        XCTAssertEqual(ownBack.paragraphs[0].style.listIndentLeft, 0)
        XCTAssertNil(ownBack.paragraphs[1].style.listIndentLeft)
        var footered = doc
        footered.footer = "Page {PAGE}"
        var fe = try Zip.read(try DocxFormat.write(footered, pageSetup: .letter))
        let fi = fe.firstIndex { $0.name == "word/footer1.xml" }!
        var fxml = String(decoding: fe[fi].data, as: UTF8.self)
        let inner = fxml[fxml.range(of: "<w:p>")!.lowerBound ..< fxml.range(of: "</w:p>")!.upperBound]
        fxml = fxml.replacingAll(String(inner), with: "<w:p><w:r><mc:AlternateContent xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\"><mc:Choice Requires=\"wps\">\(inner)</mc:Choice><mc:Fallback>\(inner)</mc:Fallback></mc:AlternateContent></w:r></w:p>")
        fe[fi] = ZipEntry(name: "word/footer1.xml", data: Data(fxml.utf8))
        XCTAssertEqual(try DocxFormat.read(try Zip.write(fe)).document.footer, "Page {PAGE}")
    }

    func testFormCheckboxesTabStopsAndTenPointDefault() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "x no diploma")])
        doc.paragraphs[0].style.tabStops = [TabStop(position: 22.5), TabStop(position: 300, alignment: .right)]
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:tabs><w:tab w:val=\"left\" w:pos=\"450\"/><w:tab w:val=\"right\" w:pos=\"6000\"/></w:tabs>"), xml)
        // The "x" becomes a checked form checkbox field with no result.
        xml = xml.replacingAll("<w:t xml:space=\"preserve\">x no diploma</w:t></w:r>",
                               with: "</w:r><w:r><w:fldChar w:fldCharType=\"begin\"><w:ffData><w:name w:val=\"Check21\"/><w:checkBox><w:sizeAuto/><w:default w:val=\"1\"/></w:checkBox></w:ffData></w:fldChar></w:r><w:r><w:instrText xml:space=\"preserve\"> FORMCHECKBOX </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r><w:r><w:t xml:space=\"preserve\"> no diploma</w:t></w:r>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        // And a styles part that states no size anywhere: Word's 10pt.
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        styles = styles.replacingAll("<w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/>", with: "")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].text, "\u{2612} no diploma")
        XCTAssertEqual(back.paragraphs[0].style.tabStops, doc.paragraphs[0].style.tabStops)
        XCTAssertEqual(back.styles[RichNamedStyle.normalId]?.char.fontSize, 10)
        // And the box goes back as the form field, checked, not as a glyph
        // (whose fallback font made every line taller than Word's).
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(saved.contains("<w:checkBox><w:sizeAuto/><w:default w:val=\"1\"/></w:checkBox></w:ffData></w:fldChar></w:r><w:r><w:instrText xml:space=\"preserve\"> FORMCHECKBOX </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r><w:r><w:t xml:space=\"preserve\"> no diploma</w:t>"), saved)
        XCTAssertFalse(saved.contains("\u{2612}"), saved)
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(back, pageSetup: .letter)).document.paragraphs[0].text, "\u{2612} no diploma")
    }

    func testRichAndFirstPageHeadersKeptVerbatim() throws {
        // A default header holding a table (60329's banner) and a
        // first-page header: both parts come back as they were, the
        // first page switched on; editing the header text replaces the
        // default part with a generated one under a free name.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "body")])
        doc.header = "Banner"
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let hi = entries.firstIndex { $0.name == "word/header1.xml" }!
        let banner = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"9000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"9000\" w:type=\"dxa\"/><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"1F1F7A\"/></w:tcPr><w:p><w:r><w:t>Banner</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/></w:hdr>"
        entries[hi] = ZipEntry(name: "word/header1.xml", data: Data(banner.utf8))
        let first = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:p><w:r><w:t>First page only</w:t></w:r></w:p></w:hdr>"
        entries.append(ZipEntry(name: "word/header2.xml", data: Data(first.utf8)))
        let ri = entries.firstIndex { $0.name == "word/_rels/document.xml.rels" }!
        entries[ri] = ZipEntry(name: entries[ri].name, data: Data(String(decoding: entries[ri].data, as: UTF8.self).replacingAll("</Relationships>", with: "<Relationship Id=\"rIdFirst\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header2.xml\"/></Relationships>").utf8))
        let ci = entries.firstIndex { $0.name == "[Content_Types].xml" }!
        entries[ci] = ZipEntry(name: entries[ci].name, data: Data(String(decoding: entries[ci].data, as: UTF8.self).replacingAll("</Types>", with: "<Override PartName=\"/word/header2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml\"/></Types>").utf8))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/>", with: "<w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/><w:headerReference w:type=\"first\" r:id=\"rIdFirst\"/>")
        xml = xml.replacingAll("</w:sectPr>", with: "<w:titlePg/></w:sectPr>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        // The banner's own picture, under the name the body's first picture would take.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        entries.append(ZipEntry(name: "word/media/image1.png", data: png))
        entries.append(ZipEntry(name: "word/_rels/header1.xml.rels", data: Data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/image1.png\"/></Relationships>".utf8)))
        // The banner's paragraph names a style of its own, and the file's
        // Normal spacing differs from Word's: both must be written, or the
        // kept part lays out by our defaults.
        let hi2 = entries.firstIndex { $0.name == "word/header1.xml" }!
        let banner2 = banner.replacingAll("<w:p><w:r><w:t>Banner</w:t>", with: "<w:p><w:pPr><w:pStyle w:val=\"Kopfzeile\"/></w:pPr><w:r><w:t>Banner</w:t>")
        entries[hi2] = ZipEntry(name: "word/header1.xml", data: Data(banner2.utf8))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        styles = styles.replacingAll("<w:spacing w:after=\"160\" w:line=\"259\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault>", with: "<w:spacing w:after=\"200\" w:line=\"276\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault>")
        styles = styles.replacingAll("</w:styles>", with: "<w:style w:type=\"paragraph\" w:styleId=\"Kopfzeile\"><w:name w:val=\"header\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr></w:style></w:styles>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let savedStyles = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/styles.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(savedStyles.contains("w:styleId=\"Kopfzeile\""), savedStyles)
        XCTAssertTrue(savedStyles.contains("<w:pPrDefault><w:pPr><w:spacing w:after=\"200\" w:line=\"276\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault>"), savedStyles)
        XCTAssertEqual(back.keptParts["word/media/image1.png"], png)
        var withPicture = back
        withPicture.paragraphs.append(RichParagraph(image: ImageAttachment(data: Data([1, 2, 3]), width: 10, height: 10)))
        let saved2 = try Zip.read(try DocxFormat.write(withPicture, pageSetup: .letter))
        XCTAssertEqual(saved2.first { $0.name == "word/media/image1.png" }?.data, png, "the kept header's picture keeps its name")
        XCTAssertEqual(saved2.first { $0.name == "word/media/image2.png" }?.data, Data([1, 2, 3]), "the body's picture takes the next")
        XCTAssertEqual(back.header, "Banner")
        XCTAssertTrue(back.titlePage)
        XCTAssertEqual(back.keptHeaderFooters.map { "\($0.type):\($0.part):\($0.text)" }, ["default:word/header1.xml:Banner", "first:word/header2.xml:First page only"])
        XCTAssertEqual(back.keptParts["word/header1.xml"], Data(banner2.utf8))
        let saved = try Zip.read(try DocxFormat.write(back, pageSetup: .letter))
        XCTAssertEqual(saved.first { $0.name == "word/header1.xml" }?.data, Data(banner2.utf8))
        XCTAssertEqual(saved.first { $0.name == "word/header2.xml" }?.data, Data(first.utf8))
        let savedXML = String(decoding: saved.first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(savedXML.contains("<w:headerReference w:type=\"default\" r:id=\"rIdKeptHF0\"/><w:headerReference w:type=\"first\" r:id=\"rIdKeptHF1\"/>"), savedXML)
        XCTAssertTrue(savedXML.contains("<w:titlePg/></w:sectPr>"), savedXML)
        // A title page without a first-page part: still a title page (an
        // empty first-page header, as Word shows Bug51170's cover).
        var bare = RichDocument(paragraphs: [RichParagraph(text: "x")]); bare.header = "h"; bare.titlePage = true
        XCTAssertTrue(String(decoding: try Zip.read(try DocxFormat.write(bare, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self).contains("<w:titlePg/>"))
        let savedRels = String(decoding: saved.first { $0.name == "word/_rels/document.xml.rels" }!.data, as: UTF8.self)
        XCTAssertTrue(savedRels.contains("Id=\"rIdKeptHF0\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/header\" Target=\"header1.xml\""), savedRels)
        XCTAssertFalse(savedRels.contains("rIdHeader"), savedRels)
        let again = try DocxFormat.read(try DocxFormat.write(back, pageSetup: .letter)).document
        XCTAssertEqual(again.keptHeaderFooters.map(\.part), ["word/header1.xml", "word/header2.xml"])
        // Edited: the banner part goes, a generated header3.xml carries the text.
        var edited = back
        edited.header = "New text"
        let edit = try Zip.read(try DocxFormat.write(edited, pageSetup: .letter))
        let editXML = String(decoding: edit.first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(editXML.contains("<w:headerReference w:type=\"default\" r:id=\"rIdHeader\"/><w:headerReference w:type=\"first\" r:id=\"rIdKeptHF1\"/>"), editXML)
        XCTAssertNotNil(edit.first { $0.name == "word/header3.xml" })
        XCTAssertEqual(try DocxFormat.read(try Zip.write(edit)).document.header, "New text")
    }

    func testRightToLeftParagraphs() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "إسبانيا"), RichParagraph(text: "ltr")])
        doc.paragraphs[0].style.rightToLeft = true
        doc.styles["Arabic"] = RichNamedStyle(id: "Arabic", name: "Arabic", paragraph: { var p = RichParagraphStyle(); p.rightToLeft = true; return p }(), char: CharStyle())
        doc.paragraphs[1].style.named = "Arabic"   // left-to-right under a right-to-left style
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:bidi/>"), xml)
        XCTAssertTrue(xml.contains("<w:bidi w:val=\"0\"/>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertTrue(back.paragraphs[0].style.rightToLeft)
        XCTAssertFalse(back.paragraphs[1].style.rightToLeft)
        XCTAssertTrue(back.styles["Arabic"]?.paragraph.rightToLeft ?? false)
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: 2)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(back)
        XCTAssertEqual(layout.geometry(0).painter.textDirection, .rtl)
        XCTAssertEqual(layout.geometry(1).painter.textDirection, .ltr)
    }

    func testAnchoredPictureKeepsItsAnchor() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var doc = RichDocument(paragraphs: [RichParagraph(image: ImageAttachment(data: png, width: 72, height: 36)), RichParagraph(text: "text")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<wp:inline"), xml)
        xml = xml.replacingAll("<wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\">", with: "<wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"1\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\"><wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"column\"><wp:posOffset>914400</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>0</wp:posOffset></wp:positionV>")
        xml = xml.replacingAll("<wp:docPr", with: "<wp:wrapNone/><wp:docPr descr=\"a picture\"").replacingAll("</wp:inline>", with: "</wp:anchor>")
        // The anchor's paragraph has a 16pt mark: with no text on its
        // line, that is its height (bib-chernigovka's title box).
        xml = xml.replacingAll("</w:pPr><w:r><w:drawing>", with: "<w:rPr><w:sz w:val=\"32\"/></w:rPr></w:pPr><w:r><w:drawing>")
        XCTAssertTrue(xml.contains("<w:sz w:val=\"32\"/></w:rPr></w:pPr><w:r><w:drawing>"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].runs.first?.style.fontSize, 16)
        let att = try XCTUnwrap(back.paragraphs[0].image ?? back.paragraphs[0].inlineImages.values.first)
        XCTAssertEqual(att.data, png, "the editor still has the picture")
        XCTAssertTrue(att.sourceXML?.contains("<wp:anchor") ?? false, att.sourceXML ?? "nil")
        XCTAssertEqual(att.width, 72)
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(saved.contains("<wp:anchor ") && saved.contains("<wp:wrapNone/>") && saved.contains("<wp:posOffset>914400</wp:posOffset>"), saved)
        XCTAssertTrue(saved.contains("<w:rPr><w:sz w:val=\"32\"/><w:szCs w:val=\"32\"/></w:rPr></w:pPr><w:r><w:drawing"), saved)
        XCTAssertFalse(saved.contains("<wp:inline"), saved)
        // With inline pictures beside it: every wp:docPr id unique, every
        // media name unique (Word calls either clash unreadable content).
        var both = back
        both.paragraphs.append(RichParagraph(image: ImageAttachment(data: png, width: 10, height: 10)))
        both.paragraphs.append(RichParagraph(image: ImageAttachment(data: png, width: 12, height: 12)))
        let saved2 = try Zip.read(try DocxFormat.write(both, pageSetup: .letter))
        let xml2 = String(decoding: saved2.first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        var ids: [String] = []
        var pos = xml2.startIndex
        while let tag = xml2.range(of: "<wp:docPr", range: pos ..< xml2.endIndex) {
            let close = xml2[tag.upperBound...].firstIndex(of: ">")!
            let r = xml2.range(of: " id=\"", range: tag.upperBound ..< close)!
            let end = xml2[r.upperBound...].firstIndex(of: "\"")!
            ids.append(String(xml2[r.upperBound ..< end])); pos = close
        }
        XCTAssertEqual(ids.count, 3, xml2)
        XCTAssertEqual(Set(ids).count, 3, "\(ids)")
        XCTAssertTrue(xml2.contains("<wp:docPr descr=\"a picture\" id=\"100001\""), "a kept docPr with descr before id is renumbered too: \(xml2)")
        let names = saved2.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "\(names)")
    }

    /// 60316's sidebar: a percentage position's compatibility fallback
    /// is a page-relative offset, not the default body-column origin.
    func testDrawingPositionInAlternateContent() throws {
        let xml = """
        <wp:anchor xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:wp14="http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">
          <mc:AlternateContent><mc:Choice Requires="wp14"><wp:positionH relativeFrom="page"><wp14:pctPosHOffset>5900</wp14:pctPosHOffset></wp:positionH></mc:Choice><mc:Fallback><wp:positionH relativeFrom="page"><wp:posOffset>458470</wp:posOffset></wp:positionH></mc:Fallback></mc:AlternateContent>
          <mc:AlternateContent><mc:Choice Requires="wp14"><wp:positionV relativeFrom="margin"><wp14:pctPosVOffset>10000</wp14:pctPosVOffset></wp:positionV></mc:Choice><mc:Fallback><wp:positionV relativeFrom="margin"><wp:posOffset>914400</wp:posOffset></wp:positionV></mc:Fallback></mc:AlternateContent>
          <wp:wrapSquare wrapText="bothSides"/>
        </wp:anchor>
        """
        let node = try XCTUnwrap(XNode.parse(Data(xml.utf8)))
        let floating = try XCTUnwrap(DocxFormat._float(node))
        XCTAssertEqual(floating.horizontalFrom, "page")
        XCTAssertEqual(floating.x, 36.1, accuracy: 0.001)
        XCTAssertEqual(floating.verticalFrom, "margin")
        XCTAssertEqual(floating.y, 72, accuracy: 0.001)
        XCTAssertTrue(floating.wraps)
        // A direct position still takes precedence; an unrelated nested
        // drawing's position must not be picked up by a descendant search.
        let direct = try XCTUnwrap(XNode.parse(Data("<wp:positionH relativeFrom=\"column\"><wp:align>right</wp:align></wp:positionH>".utf8)))
        node.children.append(direct)
        XCTAssertEqual(DocxFormat._float(node)?.horizontalFrom, "column")
        XCTAssertEqual(DocxFormat._float(node)?.horizontalAlign, "right")
        XCTAssertEqual(DocxFormat._float(node)?.x, 0)
    }

    func testPageBreakEndingAParagraphLeavesNoEmptyLine() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "one"), RichParagraph(text: "BREAK"), RichParagraph(text: "two")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:t xml:space=\"preserve\">BREAK</w:t>", with: "<w:br w:type=\"page\"/>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs.map(\.text), ["one", "", "two"])
        XCTAssertTrue(back.paragraphs[2].style.pageBreakBefore)
        XCTAssertFalse(back.paragraphs[1].style.pageBreakBefore)
        // A break mid-paragraph still splits it in two.
        doc.paragraphs[1] = RichParagraph(text: "aBREAKb")
        entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        xml = String(decoding: entries[di].data, as: UTF8.self).replacingAll("BREAK", with: "</w:t></w:r><w:r><w:br w:type=\"page\"/></w:r><w:r><w:t xml:space=\"preserve\">")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let split = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(split.paragraphs.map(\.text), ["one", "a", "b", "two"])
        XCTAssertTrue(split.paragraphs[2].style.pageBreakBefore)
    }

    /// WordWithAttachments' "Словарь" box: a VML drawing canvas in the line
    /// (a `v:group`, no absolute position) holding a text box placed
    /// absolutely in the group's coordinates. The group is in the line, at
    /// its own size, and the box's text stands at the box's place in it —
    /// floated by the box inside, it took no room and the page ran 57pt high.
    func testAVMLCanvasInTheLineHoldsItsTextBoxAtItsPlace() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        if !xml.contains("xmlns:v=") { xml = xml.replacingAll("<w:document ", with: "<w:document xmlns:v=\"urn:schemas-microsoft-com:vml\" ") }
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:r><w:pict><v:group style=\"width:126pt;height:99pt;mso-position-horizontal-relative:char;mso-position-vertical-relative:line\" coordorigin=\"3834,5690\" coordsize=\"1976,1533\">"
            + "<v:shape style=\"position:absolute;left:3834;top:5690;width:1976;height:1533\"/>"
            + "<v:shape style=\"position:absolute;left:4257;top:5969;width:1130;height:1115\"><v:textbox><w:txbxContent>"
            + "<w:p><w:r><w:t>Словарь</w:t></w:r></w:p><w:p><w:r><w:t>dictionary</w:t></w:r></w:p></w:txbxContent></v:textbox></v:shape>"
            + "</v:group></w:pict></w:r><w:r><w:t>Hyperlink</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let canvas = try XCTUnwrap(doc.paragraphs.first { $0.text.contains("Hyperlink") }?.inlineImages.values.first)
        XCTAssertNil(canvas.float, "in the line")
        XCTAssertEqual(canvas.width, 126, accuracy: 0.01)
        XCTAssertEqual(canvas.height, 99, accuracy: 0.01)
        let box = try XCTUnwrap(canvas.textBox)
        // (27pt and 18pt into the group by its coordinates, and VML's
        // 7.2 and 3.6pt insets.)
        XCTAssertEqual(box.parts.first?.top ?? 0, 18.0 + 3.6, accuracy: 0.05)
        XCTAssertEqual(box.paragraphs.first?.style.indentLeft ?? 0, 27.0 + 7.2, accuracy: 0.05)
    }

    /// WordWithAttachments' "Tryhere.jpg" package prints as its icon: the
    /// object's WMF carries the icon as a bitmap (DibStretchBlt) beside
    /// its caption. Painted, the metafile asks for the bitmap, and once it
    /// is decoded draws it — before, its caption alone printed.
    func testAnObjectsMetafileDrawsTheBitmapsItCarries() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs/WordWithAttachments.docx")
        let wmf = try XCTUnwrap(try Zip.read(Data(contentsOf: file)).first { $0.name == "word/media/image1.wmf" }).data
        let icon = ImageAttachment(data: wmf, width: 54, height: 38.25, name: "image1.wmf")
        XCTAssertTrue(WriterMetafiles.register(wmf, for: icon.id))
        func painted() -> Int {
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, 54, 38.25))
            XCTAssertTrue(WriterMetafiles.paint(icon, canvas, Rect.fromLTWH(0, 0, 54, 38.25)))
            let picture = recorder.endRecording()
            defer { picture.dispose() }
            return picture.approximateBytesUsed
        }
        let caption = painted()
        let deadline = Date().addingTimeInterval(8)
        while WriterMetafiles.hasPendingImages, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        XCTAssertFalse(WriterMetafiles.hasPendingImages, "its bitmaps decoded")
        XCTAssertGreaterThan(painted(), caption, "and drawn with the caption")
    }

    /// zh-8112041b: a 1.5-spaced line's extra space stands under its text,
    /// and at a page's foot it may reach past the margin — Word's page 2
    /// keeps a fourth empty paragraph whose line runs 5pt over and whose
    /// text does not. A line whose text itself is over still goes on.
    func testAMultiplesExtraSpaceMayHangPastThePageFoot() {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        func pageOfFourth(room: (Double) -> Double) -> Int {
            var p = RichParagraph(text: "")
            p.style.lineSpacing = 1.5
            p.style.spaceBefore = 0
            p.style.spaceAfter = 0
            let doc = RichDocument(paragraphs: Array(repeating: p, count: 8))
            func laid(_ bottom: Double) -> RichLayout {
                let l = RichLayout(theme: theme, paragraphCount: 8)
                var setup = PageSetup.letter
                setup.marginTop = 72
                setup.marginBottom = bottom
                l.pageSetup = setup
                l.width = 612 * 96.0 / 72.0
                l.ensureLaidOut(doc)
                return l
            }
            let line = laid(72).geometry(0).height / theme.pixelsPerPoint
            let l = laid(792 - 72 - room(line))
            let caret = l.canvasRects(l.caretRect(RichPosition(paragraph: 3, offset: 0), doc))[0]
            return l.page(atCanvasY: (caret.top + caret.bottom) / 2)
        }
        // (A third of a 1.5-spaced line is its extra.)
        XCTAssertEqual(pageOfFourth { 4 * $0 - $0 / 6 }, 0, "its text fits, its extra hangs over")
        XCTAssertEqual(pageOfFourth { 4 * $0 - $0 / 2 }, 1, "its text is over too")
    }

    /// Word sizes a fit-to-text box once, DrawingML's (lab `ftD`) and
    /// VML's alike (lab `vf`): zh-9bcea239's VML "—10—" wraps its closing
    /// dash in the box "—1—" set, and zh-5a9a85c6's "— 15 —" stands whole
    /// in "— 1 —"'s only by halving its spaces.
    func testEitherFitToTextBoxIsFittedOnce() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let text = "<w:txbxContent><w:p><w:r><w:t>1</w:t></w:r></w:p></w:txbxContent>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:r><w:pict><v:shape xmlns:v=\"urn:schemas-microsoft-com:vml\" type=\"#_x0000_t202\" "
            + "style=\"position:absolute;margin-top:0pt;height:144pt;width:144pt;mso-wrap-style:none\" filled=\"f\" stroked=\"f\">"
            + "<v:textbox inset=\"0mm,0mm,0mm,0mm\" style=\"mso-fit-shape-to-text:t;\">\(text)</v:textbox></v:shape></w:pict></w:r></w:p>"
            + "<w:p><w:r><w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"margin\"><wp:align>outside</wp:align></wp:positionH>"
            + "<wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx=\"1828800\" cy=\"1828800\"/>"
            + "<wp:wrapNone/><wp:docPr id=\"2\" name=\"b\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
            + "<a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\">"
            + "<wps:cNvSpPr txBox=\"1\"/><wps:spPr><a:prstGeom prst=\"rect\"/></wps:spPr><wps:txbx>\(text)</wps:txbx>"
            + "<wps:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"><a:spAutoFit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let boxes = doc.paragraphs.compactMap { p in (p.image ?? p.inlineImages.values.first)?.textBox }
        XCTAssertEqual(boxes.map(\.fitsText), [true, true])
        XCTAssertEqual(boxes.map(\.fitsOnce), [true, true])
    }

    /// A lone VML shape sets its text in its type's text rectangle:
    /// zh-60c80728 p35's "alternate process" boxes (o:spt 176, inset 0,
    /// no shapetype in the file) set "由港区专" a line in 54.25pt at
    /// 10.5pt in Word's print, where the whole width took "由港区专项". A
    /// text box (202) keeps the whole box.
    func testALoneVMLShapeSetsItsTextInItsTypesTextRectangle() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let text = "<w:txbxContent><w:p><w:r><w:t>由港区专项指挥机构</w:t></w:r></w:p></w:txbxContent>"
        func shape(_ spt: Int) -> String {
            "<w:p><w:r><w:pict><v:shape xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" o:spt=\"\(spt)\" type=\"#_x0000_t\(spt)\" "
                + "style=\"position:absolute;margin-top:0pt;height:102.55pt;width:54.25pt\" filled=\"f\">"
                + "<v:textbox inset=\"0mm,0mm,0mm,0mm\">\(text)</v:textbox></v:shape></w:pict></w:r></w:p>"
        }
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with: shape(176) + shape(202))
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let boxes = doc.paragraphs.compactMap { p in (p.image ?? p.inlineImages.values.first)?.textBox }
        XCTAssertEqual(boxes.count, 2)
        // 2700 x 0.2929 of 21600 a side: 1.99pt across, 3.77 down.
        XCTAssertEqual(boxes[0].insetLeft, 54.25 * 2700 * 0.2929 / 21600, accuracy: 0.01)
        XCTAssertEqual(boxes[0].insetRight, 54.25 * 2700 * 0.2929 / 21600, accuracy: 0.01)
        XCTAssertEqual(boxes[0].insetTop, 102.55 * 2700 * 0.2929 / 21600, accuracy: 0.01)
        XCTAssertEqual(boxes[1].insetLeft, 0, accuracy: 0.001)
        XCTAssertEqual(boxes[1].insetTop, 0, accuracy: 0.001)
    }

    /// An equation is kept and drawn: zh-20ff844e's display formulas were
    /// gone from the page and from a save. Read, it has a size and a
    /// baseline, its paragraph is centred, and it is written back as the
    /// paragraph's own child, not inside a run.
    func testAnEquationIsReadDrawnAndWrittenBack() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let m = "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\""
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><m:oMathPara \(m)><m:oMath><m:r><m:t>L=99−</m:t></m:r><m:nary><m:naryPr><m:chr m:val=\"∑\"/><m:limLoc m:val=\"undOvr\"/></m:naryPr>"
            + "<m:sub><m:r><m:t>i=1</m:t></m:r></m:sub><m:sup><m:r><m:t>n</m:t></m:r></m:sup><m:e><m:sSub><m:e><m:r><m:t>B</m:t></m:r></m:e>"
            + "<m:sub><m:r><m:t>i</m:t></m:r></m:sub></m:sSub></m:e></m:nary><m:f><m:num><m:r><m:t>a</m:t></m:r></m:num><m:den><m:r><m:t>b</m:t></m:r></m:den></m:f>"
            + "</m:oMath></m:oMathPara></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let p = try XCTUnwrap(doc.paragraphs.first)
        let eq = try XCTUnwrap(p.image ?? p.inlineImages.values.first)
        XCTAssertEqual(eq.name, "m:oMathPara")
        XCTAssertGreaterThan(eq.width, 30)
        // (Taller than a line: the sum's limits stand over and under it.)
        XCTAssertGreaterThan(eq.height, 20)
        let baseline = try XCTUnwrap(eq.baseline)
        XCTAssertTrue(baseline > 0 && baseline < eq.height)
        XCTAssertEqual(p.style.alignment, .center)
        let saved = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(doc, pageSetup: .a4)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(saved.contains("<m:oMathPara"), saved)
        XCTAssertFalse(saved.contains("<w:r><m:oMathPara"), saved)
        XCTAssertTrue(saved.contains("<m:t>L=99−</m:t>"), saved)
    }

    /// A paragraph that holds a bare `m:oMath` and nothing else is a display
    /// equation to Word, centred: LibreOffice's tdf169843 (its ℝ at the page's
    /// middle in Word's print, at the left margin in ours). With text beside
    /// it, it is inline and the paragraph's alignment stands.
    func testALoneBareEquationParagraphIsCentred() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let m = "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\""
        let eq = "<m:oMath \(m)><m:r><m:t>R</m:t></m:r></m:oMath>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p>\(eq)</w:p><w:p><w:r><w:t>x </w:t></w:r>\(eq)</w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(doc.paragraphs[0].style.alignment, .center)
        XCTAssertNotEqual(doc.paragraphs[1].style.alignment, .center)
    }

    /// A line separator typed into a `w:t` is no break to Word: it prints a
    /// blank half an em wide and the line runs on (tdf152983-1-min).
    func testALineSeparatorInTextIsNotABreak() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:r><w:t>one\u{2028}two</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(doc.paragraphs[0].text, "one\u{2002}two")
    }

    /// A VML textbox's `layout-flow:vertical` reads down; with
    /// `mso-layout-flow-alt:bottom-to-top`, up (btlr-frame-vml).
    func testAVmlTextboxFlowsVertically() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        func box(_ flow: String) -> String {
            "<w:p><w:r><w:pict><v:rect xmlns:v=\"urn:schemas-microsoft-com:vml\" style=\"position:absolute;margin-top:0pt;height:144pt;width:57pt\" filled=\"f\" stroked=\"f\">"
            + "<v:textbox style=\"\(flow)\" inset=\".72pt,7.2pt,.72pt,7.2pt\"><w:txbxContent><w:p><w:r><w:t>Vertical Text</w:t></w:r></w:p></w:txbxContent></v:textbox></v:rect></w:pict></w:r></w:p>"
        }
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            box("layout-flow:vertical;mso-layout-flow-alt:bottom-to-top") + box("layout-flow:vertical") + box(""))
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let boxes = doc.paragraphs.compactMap { p in (p.image ?? p.inlineImages.values.first)?.textBox }
        XCTAssertEqual(boxes.map(\.textDirection), [.up, .down, .horizontal])
    }

    /// A section's line numbers (`w:lnNumType`) and vertical page alignment
    /// (`w:vAlign`) are read into its page setup.
    func testLineNumbersAndPageAlignmentAreReadFromTheSection() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let end = try XCTUnwrap(xml.range(of: "</w:sectPr>", options: .backwards))
        xml.replaceSubrange(end, with: "<w:vAlign w:val=\"center\"/><w:lnNumType w:countBy=\"5\" w:start=\"3\" w:distance=\"283\" w:restart=\"continuous\"/></w:sectPr>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let setup = try XCTUnwrap(DocxFormat.read(try Zip.write(entries)).pageSetup)
        XCTAssertEqual(setup.verticalAlign, "center")
        let numbering = try XCTUnwrap(setup.lineNumbers)
        XCTAssertEqual(numbering.countBy, 5)
        XCTAssertEqual(numbering.start, 3)
        XCTAssertEqual(try XCTUnwrap(numbering.distance), 14.15, accuracy: 0.01)
        XCTAssertEqual(numbering.restart, .continuous)
    }

    func testADisplayEquationWiderThanItsLineBreaksBeforeItsOperators() throws {
        // zh-db07d44e's cell "實績值=(…/…×1/3+…/…×1/3+…/…×1/3)×100%" is four
        // lines in Word's print, parted before "×" and "+" inside its
        // brackets, each after the first an inch in; ours ran past the cell.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let m = "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\""
        func frac(_ a: String, _ b: String) -> String { "<m:f><m:num><m:r><m:t>\(a)</m:t></m:r></m:num><m:den><m:r><m:t>\(b)</m:t></m:r></m:den></m:f>" }
        let inside = frac("aaaaaaaaa", "bbbbbbbbb") + "<m:r><m:t>×</m:t></m:r>" + frac("1", "3") + "<m:r><m:t>+</m:t></m:r>"
            + frac("ccccc", "ddddd") + "<m:r><m:t>×</m:t></m:r>" + frac("1", "3")
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><m:oMathPara \(m)><m:oMath><m:r><m:t>y=</m:t></m:r><m:d><m:e>\(inside)</m:e></m:d><m:r><m:t>×100%</m:t></m:r></m:oMath></m:oMathPara></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let eq = try XCTUnwrap(doc.paragraphs.first?.image ?? doc.paragraphs.first?.inlineImages.values.first)
        let narrow = eq.width * 0.55
        let fit = try XCTUnwrap(WriterMath.fit(eq, width: narrow), "an equation wider than its line breaks")
        XCTAssertLessThanOrEqual(fit.width, narrow + 0.5)
        XCTAssertGreaterThan(fit.height, eq.height * 1.8, "two lines at least")
        XCTAssertNil(WriterMath.fit(eq, width: eq.width + 10), "one that fits is left whole")
    }

    /// zh-547fc43c p6: a 233.75pt chart and 1.75pt of effect extent on a
    /// 15.6pt grid take 16 pitches in Word's print, and stand centred in
    /// them — 7.05pt of the 14.1 spare over it.
    func testAChartsLineOnTheGridHoldsItsEffectsAndCentresIt() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
        xml.replaceSubrange(body.upperBound ..< end.lowerBound, with:
            "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\"/></w:pPr><w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"3810000\" cy=\"2968625\"/>"
            + "<wp:effectExtent l=\"0\" t=\"4445\" r=\"0\" b=\"17780\"/><wp:docPr id=\"1\" name=\"s\"/>"
            + "<a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\">"
            + "<wps:wsp xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:spPr><a:prstGeom prst=\"ellipse\"/></wps:spPr><wps:bodyPr/></wps:wsp>"
            + "</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
            + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1800\" w:bottom=\"1440\" w:left=\"1800\" w:header=\"851\" w:footer=\"992\" w:gutter=\"0\"/>"
            + "<w:docGrid w:type=\"lines\" w:linePitch=\"312\"/></w:sectPr>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let picture = try XCTUnwrap(doc.paragraphs[0].image ?? doc.paragraphs[0].inlineImages.values.first)
        XCTAssertEqual(picture.effectBottom, 1.4, accuracy: 0.01)
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        l.width = 595 * 96.0 / 72.0
        l.pageSetup = .a4
        l.ensureLaidOut(doc)
        let px = theme.pixelsPerPoint
        let g = l.geometry(0)
        XCTAssertEqual((g.height - g.textTop + g.top) / px, 16 * 15.6, accuracy: 0.8)
        let box = try XCTUnwrap(l.imageRect(0))
        XCTAssertEqual((box.top - g.textTop) / px, 7.05 + 0.35, accuracy: 0.8)
    }

    /// 60316's header divider: a line 105% of the margins' height
    /// (`wp14:sizeRelV`), centred on the page, its 1.8pt bottom effect
    /// inside that share — Word's print draws it from 36.9 to 753.3 on
    /// a letter page with 54pt margins, in the theme's accent2.
    func testAShapeSizedByAShareOfTheMarginsIsCentredOnThePage() throws {
        var f = ImageFloat()
        f.verticalFrom = "page"
        f.verticalAlign = "center"
        f.horizontalFrom = "page"
        f.effectBottom = 1.8
        f.heightShare = 1.05
        var line = ImageAttachment(data: Data(), width: 2.16, height: 99)
        line.float = f
        line.outline = ShapeOutline(kind: .line, color: Color(0xFFB2B2B2), width: 0.5)
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let doc = RichDocument(paragraphs: [RichParagraph(image: line), RichParagraph(text: "body")])
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        var setup = PageSetup.letter
        setup.marginTop = 54
        setup.marginBottom = 54
        l.pageSetup = setup
        l.width = (612 - 144) * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let px = theme.pixelsPerPoint
        let box = try XCTUnwrap(l.imageRect(0))
        XCTAssertEqual(box.height / px, 716.4, accuracy: 0.1)
        // (From the flow's top, which is the top margin's foot.)
        XCTAssertEqual(box.top / px + 54, 36.9, accuracy: 0.1)
    }

    /// zh-547fc43c's 219pt chart under its page's last 154pt, with
    /// widow control off: Word starts the next page with it.
    func testAPictureThatDoesNotFitGoesToTheNextPageWithWidowControlOff() {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        var text = RichParagraph(text: "line")
        text.style.widowControl = false
        var picture = RichParagraph(image: ImageAttachment(data: Data([1, 2, 3]), width: 300, height: 219))
        picture.style.widowControl = false
        let doc = RichDocument(paragraphs: [text, text, text, picture])
        let l = RichLayout(theme: theme, paragraphCount: 4)
        var setup = PageSetup.letter
        setup.marginTop = 72
        l.width = 612 * 96.0 / 72.0
        l.pageSetup = setup
        l.ensureLaidOut(doc)
        let used = l.geometry(2).bottom / theme.pixelsPerPoint
        setup.marginBottom = 792 - 72 - used - 154
        l.pageSetup = setup
        l.ensureLaidOut(doc)
        let caret = l.canvasRects(l.caretRect(RichPosition(paragraph: 3, offset: 0), doc))[0]
        XCTAssertEqual(l.page(atCanvasY: (caret.top + caret.bottom) / 2), 1)
    }

    /// zh-8112041b's form title opens its table cell with two page breaks:
    /// Word's print sets the title on the cell's first line, so a page
    /// break in a cell is nothing — no new page, no empty line split off.
    func testAPageBreakInATableCellIsNothing() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:r><w:t>before</w:t></w:r></w:p>"
            + "<w:tbl><w:tblGrid><w:gridCol w:w=\"4000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/></w:tcPr>"
            + "<w:p><w:r><w:br w:type=\"page\"/></w:r><w:r><w:br w:type=\"page\"/></w:r><w:r><w:t>title</w:t></w:r></w:p>"
            + "</w:tc></w:tr></w:tbl><w:p/>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let cell = doc.paragraphs.filter { $0.cell != nil }
        XCTAssertEqual(cell.map(\.text), ["title"])
        XCTAssertFalse(cell[0].style.pageBreakBefore)
    }

    /// A cell merged down into a row rules it by its continuation's top
    /// line, and one that states no top takes the table's line between
    /// rows, drawn or not; one that states nil takes none (zh-db07d44e's
    /// two tables: rows of at least 22.7pt 23.2 apart where the merged
    /// column states nothing above, 22.7 where it states nil).
    func testAMergedCellsUnstatedTopRulesItsRow() throws {
        func pitch(_ continuationBorders: String) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
            let nils = "<w:tcBorders><w:top w:val=\"nil\"/><w:bottom w:val=\"nil\"/></w:tcBorders>"
            func row(_ first: String, _ text: String) -> String {
                "<w:tr><w:trPr><w:trHeight w:val=\"454\"/></w:trPr>"
                    + "<w:tc><w:tcPr><w:tcW w:w=\"1400\" w:type=\"dxa\"/>\(first)</w:tcPr><w:p/></w:tc>"
                    + "<w:tc><w:tcPr><w:tcW w:w=\"5000\" w:type=\"dxa\"/>\(nils)</w:tcPr><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"360\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p></w:tc></w:tr>"
            }
            let line = "w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\""
            xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
                "<w:tbl><w:tblPr><w:tblW w:w=\"6400\" w:type=\"dxa\"/><w:tblBorders><w:top \(line)/><w:left \(line)/><w:bottom \(line)/><w:right \(line)/><w:insideH \(line)/><w:insideV \(line)/></w:tblBorders><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr>"
                + "<w:tblGrid><w:gridCol w:w=\"1400\"/><w:gridCol w:w=\"5000\"/></w:tblGrid>"
                + row("<w:vMerge w:val=\"restart\"/>", "one") + row("<w:vMerge/>\(continuationBorders)", "two") + row("<w:vMerge/>\(continuationBorders)", "three")
                + "</w:tbl><w:p/>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let doc = try DocxFormat.read(try Zip.write(entries)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = 612 * 96.0 / 72.0
            layout.ensureLaidOut(doc)
            func top(_ text: String) throws -> Double {
                let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == text })
                return layout.caretRect(RichPosition(paragraph: k, offset: 0), doc).top / theme.pixelsPerPoint
            }
            return try top("three") - top("two")
        }
        XCTAssertEqual(try pitch(""), 23.2, accuracy: 0.05, "no top stated: the table's half point")
        XCTAssertEqual(try pitch("<w:tcBorders><w:top w:val=\"nil\"/></w:tcBorders>"), 22.7, accuracy: 0.05, "nil stated: none")
    }

    /// A number set right ends where its first line starts, and its tab
    /// goes on from there: zh-f2ca3070's "i." under a 7pt hanging indent
    /// has its text at the indent in Word's print, 7pt on — not at the
    /// next default stop, where measuring the number from the line's start
    /// sent it.
    func testARightAlignedNumbersTabGoesOnFromWhereItEnds() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let run = "<w:rPr><w:sz w:val=\"28\"/></w:rPr>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr><w:ind w:left=\"2550\" w:hanging=\"140\"/>\(run)</w:pPr><w:r>\(run)<w:t>text</w:t></w:r></w:p>"
            + "<w:p><w:pPr>\(run)</w:pPr><w:r>\(run)<w:t>text</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let numbering = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"lowerRoman\"/><w:lvlText w:val=\"%1.\"/><w:lvlJc w:val=\"right\"/><w:pPr><w:ind w:left=\"3108\" w:hanging=\"480\"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        let ni = try XCTUnwrap(entries.firstIndex { $0.name == "word/numbering.xml" })
        entries[ni] = ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(doc)
        // (By the painters' widths, the same text in each: the text's lead
        // past the indent is the difference — none, the text at the
        // indent; 16.5 to the default stop when the number was measured
        // from the line's start.)
        func width(_ i: Int) -> Double { layout.geometry(i).painter.maxIntrinsicWidth / theme.pixelsPerPoint }
        XCTAssertEqual(width(0) - width(1), 0, accuracy: 0.05, "\(width(0)) \(width(1))")
    }

    /// A Wingdings bullet is as wide as Wingdings makes it, whatever the
    /// glyph drawn for it: zh-3fe252ff's 15pt "Ø" (0.794 em) ends short
    /// of the 42pt default stop from a 30pt first-line indent, and Word
    /// starts the text there.
    func testAWingdingsBulletTakesWingdingsWidth() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!, si = entries.firstIndex { $0.name == "word/settings.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let run = "<w:rPr><w:sz w:val=\"30\"/></w:rPr>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr><w:ind w:left=\"0\" w:firstLine=\"600\"/>\(run)</w:pPr><w:r>\(run)<w:t>text</w:t></w:r></w:p>"
            + "<w:p><w:pPr>\(run)</w:pPr><w:r>\(run)<w:t>text</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let settings = String(decoding: entries[si].data, as: UTF8.self).replacingAll("<w:defaultTabStop w:val=\"720\"/>", with: "<w:defaultTabStop w:val=\"420\"/>")
        XCTAssertTrue(settings.contains("w:val=\"420\""))
        entries[si] = ZipEntry(name: "word/settings.xml", data: Data(settings.utf8))
        let numbering = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\u{F0D8}\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"1020\" w:hanging=\"420\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"Wingdings\" w:hAnsi=\"Wingdings\"/></w:rPr></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        let ni = try XCTUnwrap(entries.firstIndex { $0.name == "word/numbering.xml" })
        entries[ni] = ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(doc)
        // (By the painters' widths, the same text in each: the test
        // process has no ICU to place a caret by.)
        func width(_ i: Int) -> Double { layout.geometry(i).painter.maxIntrinsicWidth / theme.pixelsPerPoint }
        XCTAssertEqual(width(0) - width(1), 42, accuracy: 0.05, "\(width(0)) \(width(1))")
    }

    /// A paragraph of a page break alone, then one that opens with its
    /// own: Word's print has a blank page between (lab `bb`, Word 16 for
    /// Mac: "甲" / break / "[break]乙" is three pages; zh-e74dd0a1's
    /// page 63). Either break alone is one page turned.
    func testABreakOnlyParagraphThenALeadingBreakLeavesABlankPage() throws {
        func pages(_ inner: String) throws -> Int {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
            xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with: "<w:p><w:r><w:t>甲</w:t></w:r></w:p>" + inner)
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let doc = try DocxFormat.read(try Zip.write(entries)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = 612 * 96.0 / 72.0
            layout.ensureLaidOut(doc)
            return layout.pageCount
        }
        let breakOnly = "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
        let leading = "<w:p><w:r><w:br w:type=\"page\"/></w:r><w:r><w:t>乙</w:t></w:r></w:p>"
        XCTAssertEqual(try pages(breakOnly + leading), 3)
        XCTAssertEqual(try pages(breakOnly + "<w:p><w:r><w:t>乙</w:t></w:r></w:p>"), 2)
        XCTAssertEqual(try pages(leading), 2)
    }

    /// A style's `w:pageBreakBefore` breaks the page before each paragraph
    /// of it, as the paragraph's own does, and a paragraph's "off" undoes
    /// it — but not on a paragraph that is only a section's end, empty:
    /// zh-499adba6's contents section ends in an empty Heading 2.
    func testAStylesPageBreakBeforeIsTheParagraphs() throws {
        func pages(_ inner: String) throws -> Int {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
            xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with: "<w:p><w:r><w:t>甲</w:t></w:r></w:p>" + inner)
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let si = try XCTUnwrap(entries.firstIndex { $0.name == "word/styles.xml" })
            var styles = String(decoding: entries[si].data, as: UTF8.self)
            let end = try XCTUnwrap(styles.range(of: "</w:styles>"))
            styles.replaceSubrange(end, with: "<w:style w:type=\"paragraph\" w:styleId=\"Brk\"><w:name w:val=\"Brk\"/><w:pPr><w:pageBreakBefore/></w:pPr></w:style></w:styles>")
            entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
            let doc = try DocxFormat.read(try Zip.write(entries)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = 612 * 96.0 / 72.0
            layout.ensureLaidOut(doc)
            return layout.pageCount
        }
        let styled = "<w:p><w:pPr><w:pStyle w:val=\"Brk\"/></w:pPr><w:r><w:t>乙</w:t></w:r></w:p>"
        XCTAssertEqual(try pages(styled), 2)
        XCTAssertEqual(try pages("<w:p><w:pPr><w:pStyle w:val=\"Brk\"/><w:pageBreakBefore w:val=\"0\"/></w:pPr><w:r><w:t>乙</w:t></w:r></w:p>"), 1)
        let sectionEnd = "<w:p><w:pPr><w:pStyle w:val=\"Brk\"/><w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:pPr></w:p>"
        XCTAssertEqual(try pages(sectionEnd + styled), 2)
    }

    /// Word leaves a paragraph's space before behind where the paragraph
    /// heads a page after a break that ended the paragraph above; it
    /// keeps it where the paragraph itself begins with the break, and —
    /// before its 2013 layout only — under `w:pageBreakBefore`.
    func testSpaceBeforeAtAPageTop() {
        func top(mode: Int, after: Double = 0, _ set: (inout RichParagraphStyle) -> Void) -> Double {
            var x = RichParagraph(text: "two")
            x.style.pageBreakBefore = true
            set(&x.style)
            // (The page before ends with a paragraph of `after` points
            // after, which the space kept at the next page's top is less.)
            var one = RichParagraph(text: "one")
            one.style.spaceAfter = after
            var doc = RichDocument(paragraphs: [one, x])
            doc.compatibilityMode = mode
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: 2)
            layout.pageSetup = .letter
            layout.width = 612 * 96.0 / 72.0
            layout.ensureLaidOut(doc)
            XCTAssertEqual(layout.pageCount, 2)
            // (On the canvas, from its page's top.)
            let caret = layout.canvasRects(layout.caretRect(RichPosition(paragraph: 1, offset: 0), doc))[0]
            return (caret.top - layout.pageRect(1).top) / theme.pixelsPerPoint
        }
        let bare = top(mode: 15) { _ in }
        XCTAssertEqual(top(mode: 15) { $0.spaceBefore = 18; $0.breakEndsPrevious = true }, bare, accuracy: 0.01, "left behind after a break above")
        XCTAssertEqual(top(mode: 15) { $0.spaceBefore = 18; $0.pageBreakInline = true }, bare + 18, accuracy: 0.01, "kept under its own break character")
        XCTAssertEqual(top(mode: 15) { $0.spaceBefore = 18 }, bare, accuracy: 0.01, "page break before, the 2013 layout")
        XCTAssertEqual(top(mode: 14) { $0.spaceBefore = 18 }, bare + 18, accuracy: 0.01, "page break before, the layout before it")
        XCTAssertEqual(top(mode: 14, after: 6) { $0.spaceBefore = 18 }, bare + 12, accuracy: 0.01, "less the space after that ended the page before")
        XCTAssertEqual(top(mode: 14, after: 6) { $0.spaceBefore = 6 }, bare, accuracy: 0.01, "none of it where that is as much")
    }

    func testHiddenTextRoundTrip() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "shown hidden")])
        doc.paragraphs[0].runs = [Run(length: 6), Run(length: 6, style: { var c = CharStyle(); c.hidden = true; return c }())]
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:rPr><w:vanish/></w:rPr><w:t xml:space=\"preserve\">hidden</w:t>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].runs.map { $0.style.hidden }, [false, true])
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: 1)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(back)
        let visible = RichDocument(paragraphs: [RichParagraph(text: "shown ")])
        let other = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: 1)
        other.pageSetup = .letter
        other.width = 612 * 96.0 / 72.0
        other.ensureLaidOut(visible)
        XCTAssertEqual(layout.geometry(0).painter.width, other.geometry(0).painter.width, accuracy: 1, "hidden text takes no width")
    }

    func testCommentsKeptWithTheirRanges() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "a b c"), RichParagraph(text: "d e")])
        var on = CharStyle(); on.comments = ["0"]
        doc.paragraphs[0].runs = [Run(length: 2), Run(length: 3, style: on)]
        doc.paragraphs[1].runs = [Run(length: 1, style: on), Run(length: 2)]   // the range crosses the paragraph
        doc.paragraphs.insert(RichParagraph(text: "", charStyle: on), at: 1)   // and an empty paragraph inside it
        doc.keptParts["word/comments.xml"] = Data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:comments xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:comment w:id=\"0\" w:author=\"poi\" w:date=\"2021-05-20T10:57:00Z\" w:initials=\"s\"><w:p><w:r><w:annotationRef/></w:r><w:r><w:t>note</w:t></w:r></w:p></w:comment></w:comments>".utf8)
        doc.keptPartTypes["word/comments.xml"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"
        let entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let xml = String(decoding: entries.first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">a </w:t></w:r><w:commentRangeStart w:id=\"0\"/><w:r><w:t xml:space=\"preserve\">b c</w:t></w:r></w:p>"), xml)
        XCTAssertTrue(xml.contains("<w:t xml:space=\"preserve\">d</w:t></w:r><w:commentRangeEnd w:id=\"0\"/><w:r><w:rPr><w:rStyle w:val=\"CommentReference\"/></w:rPr><w:commentReference w:id=\"0\"/></w:r><w:r><w:t xml:space=\"preserve\"> e</w:t>"), xml)
        XCTAssertEqual(xml.components(separatedBy: "commentRangeStart").count - 1, 1, xml)
        XCTAssertEqual(xml.components(separatedBy: "commentRangeEnd").count - 1, 1, xml)
        // A range whose last run is a picture paragraph (written another
        // way) is still closed, once, before the next run.
        var pic = doc
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var image = RichParagraph(image: ImageAttachment(data: png, width: 10, height: 10)); image.runs[0].style.comments = ["0"]
        pic.paragraphs = [pic.paragraphs[0], image, RichParagraph(text: "after")]
        let pxml = String(decoding: try Zip.read(try DocxFormat.write(pic, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(pxml.components(separatedBy: "commentRangeStart").count - 1, 1, pxml)
        XCTAssertEqual(pxml.components(separatedBy: "commentRangeEnd").count - 1, 1, pxml)
        // And one that runs to the document's end.
        var tail = doc
        tail.paragraphs = [tail.paragraphs[0], tail.paragraphs[1]]
        tail.paragraphs[1].runs = [Run(length: 0, style: on)]
        let txml = String(decoding: try Zip.read(try DocxFormat.write(tail, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(txml.components(separatedBy: "commentRangeEnd").count - 1, 1, txml)
        // A point comment (a reference run with no range) survives as a
        // zero-width range.
        var point = RichDocument(paragraphs: [RichParagraph(text: "x")])
        point.keptParts = doc.keptParts; point.keptPartTypes = doc.keptPartTypes
        var pentries = try Zip.read(try DocxFormat.write(point, pageSetup: .letter))
        let pdi = pentries.firstIndex { $0.name == "word/document.xml" }!
        let pxml0 = String(decoding: pentries[pdi].data, as: UTF8.self).replacingAll("<w:t xml:space=\"preserve\">x</w:t></w:r>", with: "<w:t xml:space=\"preserve\">x</w:t></w:r><w:r><w:commentReference w:id=\"0\"/></w:r>")
        pentries[pdi] = ZipEntry(name: "word/document.xml", data: Data(pxml0.utf8))
        let pback = try DocxFormat.read(try Zip.write(pentries)).document
        XCTAssertEqual(pback.paragraphs[0].runs.map { $0.style.comments }, [[], ["0"]])
        let pxml1 = String(decoding: try Zip.read(try DocxFormat.write(pback, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(pxml1.contains("<w:commentRangeStart w:id=\"0\"/>") && pxml1.contains("<w:commentRangeEnd w:id=\"0\"/>") && pxml1.contains("<w:commentReference w:id=\"0\"/>"), pxml1)
        let rels = String(decoding: entries.first { $0.name == "word/_rels/document.xml.rels" }!.data, as: UTF8.self)
        XCTAssertTrue(rels.contains("relationships/comments\" Target=\"comments.xml\""), rels)
        XCTAssertNotNil(entries.first { $0.name == "word/comments.xml" })
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].runs.map { $0.style.comments }, [[], ["0"]])
        XCTAssertEqual(back.paragraphs[1].runs.map { $0.style.comments }, [["0"]], "the empty paragraph inside the range carries it")
        XCTAssertEqual(back.paragraphs[2].runs.map { $0.style.comments }, [["0"], []])
        XCTAssertNotNil(back.keptParts["word/comments.xml"])
    }

    func testTablePreferredWidthRoundTrip() throws {
        var a = RichParagraph(text: "a"), b = RichParagraph(text: "b")
        a.cell = CellRef(table: "T", row: 0, column: 0); b.cell = CellRef(table: "T", row: 0, column: 1)
        var doc = RichDocument(paragraphs: [a, b, RichParagraph(text: "")])
        doc.tableColumns["T"] = [100, 100]
        var ts = TableStyle(); ts.widthPercent = 100; doc.tableStyles["T"] = ts
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:tblPr><w:tblW w:w=\"5000\" w:type=\"pct\"/>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.tableStyles.values.first?.widthPercent, 100)
        // Fixed layout and cell spacing ride along.
        var fixed = doc
        fixed.tableStyles["T"]!.fixedLayout = true; fixed.tableStyles["T"]!.cellSpacing = 0.75
        let fxml = String(decoding: try Zip.read(try DocxFormat.write(fixed, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(fxml.contains("<w:tblCellSpacing w:w=\"15\" w:type=\"dxa\"/>") && fxml.contains("</w:tblBorders><w:tblLayout w:type=\"fixed\"/>"), fxml)
        let fback = try DocxFormat.read(try DocxFormat.write(fixed, pageSetup: .letter)).document.tableStyles.values.first
        XCTAssertEqual(fback?.fixedLayout, true)
        XCTAssertEqual(fback?.cellSpacing, 0.75)
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: 3)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(back)
        let widths = layout.columnWidths(of: back.tableStyles.keys.first!) ?? []
        XCTAssertEqual(widths.reduce(0, +), 612, accuracy: 2, "the grid scales to the full text width")
    }

    func testCellAndTableBorderSidesRoundTrip() throws {
        // bug65649: a ruled estimate table whose heading and totals cells
        // say nil on every side; Bug54771a: a title cell with a bottom
        // rule alone; form_footnotes: a table ruled outside, not between.
        var a = RichParagraph(text: "heading"), b = RichParagraph(text: "n"), c = RichParagraph(text: "v")
        a.cell = CellRef(table: "T", row: 0, column: 0, span: 2, edges: BorderEdges(all: false))
        b.cell = CellRef(table: "T", row: 1, column: 0)
        c.cell = CellRef(table: "T", row: 1, column: 1, edges: BorderEdges(right: false))
        var doc = RichDocument(paragraphs: [a, b, c, RichParagraph(text: "")])
        doc.tableColumns["T"] = [100, 100]
        var ts = TableStyle(); ts.borders = true; doc.tableStyles["T"] = ts
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:gridSpan w:val=\"2\"/><w:tcBorders><w:top w:val=\"nil\"/><w:left w:val=\"nil\"/><w:bottom w:val=\"nil\"/><w:right w:val=\"nil\"/></w:tcBorders></w:tcPr>"), xml)
        XCTAssertTrue(xml.contains("<w:tcBorders><w:right w:val=\"nil\"/></w:tcBorders>"), xml)
        XCTAssertEqual(xml.components(separatedBy: "<w:tcBorders>").count, 3, "the ruled cell says nothing of its own")
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].cell?.edges, BorderEdges(all: false))
        XCTAssertNil(back.paragraphs[1].cell?.edges)
        XCTAssertEqual(back.paragraphs[2].cell?.edges, BorderEdges(right: false))
        // LibreOffice's w:start/w:end are left/right (table-indent).
        var lo = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let li = lo.firstIndex { $0.name == "word/document.xml" }!
        var lxml = String(decoding: lo[li].data, as: UTF8.self)
        lxml = lxml.replacingAll("<w:tcBorders><w:right w:val=\"nil\"/></w:tcBorders>", with: "<w:tcBorders><w:end w:val=\"nil\"/></w:tcBorders>")
        XCTAssertTrue(lxml.contains("<w:end w:val=\"nil\"/>"), lxml)
        lo[li] = ZipEntry(name: "word/document.xml", data: Data(lxml.utf8))
        XCTAssertEqual(try DocxFormat.read(try Zip.write(lo)).document.paragraphs[2].cell?.edges, BorderEdges(right: false))
        // The other way round: a bottom rule alone in an unruled table.
        var plain = doc
        plain.tableStyles["T"]!.borders = false
        plain.paragraphs[0].cell!.edges = BorderEdges(bottom: true)
        plain.paragraphs[2].cell!.edges = nil
        let pxml = String(decoding: try Zip.read(try DocxFormat.write(plain, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(pxml.contains("<w:tcBorders><w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/></w:tcBorders>"), pxml)
        let pback = try DocxFormat.read(try DocxFormat.write(plain, pageSetup: .letter)).document
        XCTAssertEqual(pback.paragraphs[0].cell?.edges, BorderEdges(bottom: true))
        XCTAssertNil(pback.paragraphs[2].cell?.edges)
        // A table ruled outside but not between its cells.
        var frame = doc
        frame.paragraphs[0].cell!.edges = nil; frame.paragraphs[2].cell!.edges = nil
        frame.tableStyles["T"]!.edges = BorderEdges(insideH: false, insideV: false)
        let fxml = String(decoding: try Zip.read(try DocxFormat.write(frame, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(fxml.contains("<w:right w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/><w:insideH w:val=\"none\" w:sz=\"0\" w:space=\"0\" w:color=\"auto\"/><w:insideV w:val=\"none\" w:sz=\"0\" w:space=\"0\" w:color=\"auto\"/></w:tblBorders>"), fxml)
        let fback = try DocxFormat.read(try DocxFormat.write(frame, pageSetup: .letter)).document.tableStyles.values.first
        XCTAssertEqual(fback?.borders, true)
        XCTAssertEqual(fback?.edges, BorderEdges(insideH: false, insideV: false))
        // And one with only inside rules — the verdict is "on", the sides
        // outside are off.
        var inner = frame
        inner.tableStyles["T"]!.edges = BorderEdges(top: false, left: false, bottom: false, right: false)
        let iback = try DocxFormat.read(try DocxFormat.write(inner, pageSetup: .letter)).document.tableStyles.values.first
        XCTAssertEqual(iback?.edges, BorderEdges(top: false, left: false, bottom: false, right: false))
        // A line style other than single rides along (bib-chernigovka's
        // outset rules, grey 3D in Word).
        var outset = doc
        outset.tableStyles["T"]!.borderStyle = "outset"
        let oxml = String(decoding: try Zip.read(try DocxFormat.write(outset, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(oxml.contains("<w:top w:val=\"outset\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>"), oxml)
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(outset, pageSetup: .letter)).document.tableStyles.values.first?.borderStyle, "outset")
        XCTAssertNil(fback?.borderStyle, "single is the default, not a style")
        // Sides of their own style and width: double sz 6 outside, single
        // sz 4 between (form_footnotes).
        var mixed = doc
        mixed.paragraphs[0].cell!.edges = nil; mixed.paragraphs[2].cell!.edges = nil
        mixed.tableStyles["T"]!.borderStyle = "double"; mixed.tableStyles["T"]!.borderWidth = 0.75
        mixed.tableStyles["T"]!.edgeStyles = ["insideH": "single", "insideV": "single"]
        mixed.tableStyles["T"]!.edgeWidths = ["insideH": 0.5, "insideV": 0.5]
        let mxml = String(decoding: try Zip.read(try DocxFormat.write(mixed, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(mxml.contains("<w:top w:val=\"double\" w:sz=\"6\"") && mxml.contains("<w:insideH w:val=\"single\" w:sz=\"4\""), mxml)
        let mback = try XCTUnwrap(try DocxFormat.read(try DocxFormat.write(mixed, pageSetup: .letter)).document.tableStyles.values.first)
        XCTAssertEqual(mback.borderStyle, "double")
        XCTAssertEqual(mback.edgeStyles, ["insideH": "single", "insideV": "single"])
        XCTAssertEqual(mback.edgeWidths, ["insideH": 0.5, "insideV": 0.5])
    }

    func testEmptyFooterPartIsKept() throws {
        // form_footnotes: a footer of one blank paragraph reserves its
        // height in Word; the body's bottom edge moved 6pt without it.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "a")])
        doc.footer = "x"
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let fi = entries.firstIndex { $0.name == "word/footer1.xml" }!
        var fxml = String(decoding: entries[fi].data, as: UTF8.self)
        let inner = fxml[fxml.range(of: "<w:p>")!.lowerBound ..< fxml.range(of: "</w:p>")!.upperBound]
        fxml = fxml.replacingAll(String(inner), with: "<w:p><w:pPr><w:pStyle w:val=\"Footer\"/><w:jc w:val=\"right\"/></w:pPr></w:p>")
        entries[fi] = ZipEntry(name: "word/footer1.xml", data: Data(fxml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.footer, "")
        XCTAssertEqual(back.keptHeaderFooters.map(\.kind), [.footer])
        let again = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(again.contains("<w:footerReference w:type=\"default\" r:id=\"rIdKeptHF0\"/>"), again)
    }

    func testAFittedFooterBoxWidenedForItsNumberKeepsItsRightIndent() throws {
        // zh-9c162f26's "— PAGE —", in a DrawingML box fit to its text
        // and sized once, a character in from each side, its runs Times
        // hinted "default": Word prints "— 10 —" whole on page 10, where
        // ours widened the box by the left indent alone and wrapped the
        // closing dash.
        var doc = RichDocument(paragraphs: (1 ... 10).map { n in
            var p = RichParagraph(text: "page \(n)")
            p.style.pageBreakBefore = n > 1
            return p
        })
        doc.footer = "x"
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .a4))
        let fi = entries.firstIndex { $0.name == "word/footer1.xml" }!
        var fxml = String(decoding: entries[fi].data, as: UTF8.self)
        let inner = fxml[fxml.range(of: "<w:p>")!.lowerBound ..< fxml.range(of: "</w:p>")!.upperBound]
        let run = "<w:rPr><w:rFonts w:hint=\"default\" w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" w:cs=\"Times New Roman\"/><w:sz w:val=\"28\"/></w:rPr>"
        let text = "<w:txbxContent><w:p><w:pPr><w:ind w:left=\"210\" w:leftChars=\"100\" w:right=\"210\" w:rightChars=\"100\"/></w:pPr>"
            + "<w:r>\(run)<w:t xml:space=\"preserve\">— </w:t></w:r><w:r>\(run)<w:fldChar w:fldCharType=\"begin\"/></w:r><w:r>\(run)<w:instrText xml:space=\"preserve\"> PAGE </w:instrText></w:r>"
            + "<w:r>\(run)<w:fldChar w:fldCharType=\"separate\"/></w:r><w:r>\(run)<w:t>1</w:t></w:r><w:r>\(run)<w:fldChar w:fldCharType=\"end\"/></w:r><w:r>\(run)<w:t xml:space=\"preserve\"> —</w:t></w:r></w:p></w:txbxContent>"
        let box = "<w:p><w:r><w:drawing><wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"margin\"><wp:align>left</wp:align></wp:positionH>"
            + "<wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx=\"1828800\" cy=\"1828800\"/>"
            + "<wp:wrapNone/><wp:docPr id=\"2\" name=\"b\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
            + "<a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\"><wps:wsp xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\">"
            + "<wps:cNvSpPr txBox=\"1\"/><wps:spPr><a:prstGeom prst=\"rect\"/></wps:spPr><wps:txbx>\(text)</wps:txbx>"
            + "<wps:bodyPr wrap=\"none\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"><a:spAutoFit/></wps:bodyPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>"
        fxml = fxml.replacingAll(String(inner), with: box)
        if !fxml.contains("xmlns:wp=") { fxml = fxml.replacingAll("<w:ftr ", with: "<w:ftr xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" ") }
        entries[fi] = ZipEntry(name: "word/footer1.xml", data: Data(fxml.utf8))
        let opened = try DocxFormat.read(try Zip.write(entries))
        let back = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: back.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(back)
        XCTAssertEqual(l.pageCount, 10)
        // (Page 1 first, as an export paints them: its box sets the width.)
        l.paint(ParagraphHeightCanvas(), visible: l.pageRect(0), document: back, selection: nil, caret: nil)
        let canvas = ParagraphHeightCanvas()
        l.paint(canvas, visible: l.pageRect(9), document: back, selection: nil, caret: nil)
        // (14pt Times: a line is some 16pt; two lines over 30.)
        XCTAssertFalse(canvas.heights.isEmpty)
        XCTAssertLessThan((canvas.heights.max() ?? 0) / theme.pixelsPerPoint, 24, "\"— 10 —\" on one line")
    }

    func testDocumentBackgroundKeptWithItsPicture() throws {
        // bib-chernigovka: a tiled parchment background. Word lays the
        // document out differently with it, so it is kept, picture and all.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:body>", with: "<w:background w:color=\"FFFFCC\"><v:background xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" id=\"_x0000_s1025\" o:bwmode=\"white\" fillcolor=\"#ffc\"><v:fill r:id=\"rIdBg\" o:title=\"Parchment\" type=\"tile\"/></v:background></w:background><w:body>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let ri = entries.firstIndex { $0.name == "word/_rels/document.xml.rels" }!
        var rels = String(decoding: entries[ri].data, as: UTF8.self)
        rels = rels.replacingAll("</Relationships>", with: "<Relationship Id=\"rIdBg\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/parchment.jpeg\"/></Relationships>")
        entries[ri] = ZipEntry(name: "word/_rels/document.xml.rels", data: Data(rels.utf8))
        entries.append(ZipEntry(name: "word/media/parchment.jpeg", data: Data([0xFF, 0xD8, 0xFF, 0xD9])))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertTrue(back.backgroundXML?.hasPrefix("<w:background") ?? false, back.backgroundXML ?? "nil")
        XCTAssertEqual(back.backgroundRels.map(\.target), ["media/parchment.jpeg"])
        let saved = try Zip.read(try DocxFormat.write(back, pageSetup: .letter))
        let again = String(decoding: saved.first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(again.contains("><w:background ") && again.contains("w:color=\"FFFFCC\"") && again.contains("r:id=\"rIdKept1\"") && again.contains("</w:background><w:body>"), again)
        XCTAssertTrue(saved.contains { $0.name == "word/media/parchment.jpeg" }, "\(saved.map(\.name))")
        let srels = String(decoding: saved.first { $0.name == "word/_rels/document.xml.rels" }!.data, as: UTF8.self)
        XCTAssertTrue(srels.contains("Id=\"rIdKept1\"") && srels.contains("Target=\"media/parchment.jpeg\""), srels)
    }

    func testRunCharacterStyleIsResolved() throws {
        // drawing.docx: a date in a Tahoma 7.5pt shaded character style,
        // based on another that sets bold.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "12.04.2006")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:r><w:t xml:space=\"preserve\">12.04.2006</w:t>", with: "<w:r><w:rPr><w:rStyle w:val=\"date1\"/></w:rPr><w:t xml:space=\"preserve\">12.04.2006</w:t>")
        XCTAssertTrue(xml.contains("date1"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        styles = styles.replacingAll("</w:styles>", with: "<w:style w:type=\"character\" w:styleId=\"strong0\"><w:name w:val=\"strong0\"/><w:rPr><w:b/></w:rPr></w:style><w:style w:type=\"character\" w:customStyle=\"1\" w:styleId=\"date1\"><w:name w:val=\"date1\"/><w:basedOn w:val=\"strong0\"/><w:rPr><w:rFonts w:ascii=\"Tahoma\" w:hAnsi=\"Tahoma\" w:cs=\"Tahoma\"/><w:sz w:val=\"15\"/><w:szCs w:val=\"15\"/><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F1DDAB\"/></w:rPr></w:style></w:styles>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let cs = try XCTUnwrap(back.paragraphs[0].runs.first?.style)
        XCTAssertEqual(cs.fontFamily, "Tahoma")
        XCTAssertEqual(cs.fontSize, 7.5)
        XCTAssertTrue(cs.bold, "inherited from the style it is based on")
        XCTAssertEqual(cs.highlight, Color(0xFFF1DDAB))
    }

    func testFileStyleIdsAliasedForKeptMarkup() throws {
        // drawing.docx: heading 1 is style "1"; a kept nested table's
        // paragraph names it, and our sheet only defined Heading1.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "h"), RichParagraph(text: "b")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:p><w:pPr><w:spacing w:after=\"160\" w:line=\"259\" w:lineRule=\"auto\"/></w:pPr><w:r><w:t xml:space=\"preserve\">h</w:t>", with: "<w:p><w:pPr><w:pStyle w:val=\"1\"/></w:pPr><w:r><w:t xml:space=\"preserve\">h</w:t>")
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"1\"/>"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        styles = styles.replacingAll("</w:styles>", with: "<w:style w:type=\"paragraph\" w:styleId=\"1\"><w:name w:val=\"heading 1\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:keepNext/><w:outlineLvl w:val=\"0\"/></w:pPr><w:rPr><w:b/><w:sz w:val=\"32\"/></w:rPr></w:style></w:styles>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].style.heading, 1)
        XCTAssertEqual(back.styleAliases, ["1": "Heading1"])
        let again = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/styles.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(again.contains("<w:style w:type=\"paragraph\" w:styleId=\"1\"><w:name w:val=\"Heading1 1\"/><w:basedOn w:val=\"Heading1\"/></w:style>"), again)
    }

    func testSeveralHeaderRowsRepeat() throws {
        // bug59058: a caption row and a heading row both repeat.
        var a = RichParagraph(text: "caption"), b = RichParagraph(text: "Year"), c = RichParagraph(text: "1990")
        a.cell = CellRef(table: "T", row: 0, column: 0); b.cell = CellRef(table: "T", row: 1, column: 0); c.cell = CellRef(table: "T", row: 2, column: 0)
        var doc = RichDocument(paragraphs: [a, b, c, RichParagraph(text: "")])
        doc.tableColumns["T"] = [200]
        var ts = TableStyle(); ts.headerRow = true; ts.headerRowCount = 2; doc.tableStyles["T"] = ts
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<w:tblHeader/>").count, 3, xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document.tableStyles.values.first
        XCTAssertEqual(back?.headerRow, true)
        XCTAssertEqual(back?.headerRowCount, 2)
    }

    func testHiddenParagraphMarkIsKept() throws {
        // bug59058: "Bottom of Form" — hidden text under a hidden mark,
        // with a top border Word draws only when the line shows.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "Bottom of Form"), RichParagraph(text: "b")])
        doc.paragraphs[0].runs[0].style.hidden = true
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("</w:pPr><w:r><w:rPr><w:vanish/></w:rPr>", with: "<w:rPr><w:vanish/></w:rPr></w:pPr><w:r><w:rPr><w:vanish/></w:rPr>")
        XCTAssertTrue(xml.contains("<w:rPr><w:vanish/></w:rPr></w:pPr>"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertTrue(back.paragraphs[0].style.markHidden)
        XCTAssertFalse(back.paragraphs[1].style.markHidden)
        let again = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(again.contains("<w:rPr><w:vanish/></w:rPr></w:pPr><w:r><w:rPr><w:vanish/></w:rPr>"), again)
    }

    func testFileNamedFontsAreWrittenAsNamed() throws {
        // A fresh document's serif exports as Times New Roman; a file
        // that names Liberation Serif (table-indent, a LibreOffice file)
        // gets it back by name — Times New Roman's line height differs.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "a")])
        doc.paragraphs[0].runs[0].style.fontFamily = OfficeFonts.serif
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        XCTAssertTrue(xml.contains("w:ascii=\"Times New Roman\""), xml)
        xml = xml.replacingAll("w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" w:cs=\"Times New Roman\"", with: "w:ascii=\"Liberation Serif\" w:hAnsi=\"Liberation Serif\" w:cs=\"Liberation Serif\"")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertTrue(back.fileFonts.contains("Liberation Serif"), "\(back.fileFonts)")
        XCTAssertEqual(back.paragraphs[0].runs[0].style.fontFamily, "Liberation Serif")
        let again = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(again.contains("w:ascii=\"Liberation Serif\""), again)
    }

    func testLandscapeWithoutOrientStaysWithout() throws {
        // 60329: landscape dimensions and no w:orient. Word prints that onto
        // portrait paper, clipped; adding the attribute printed ours whole,
        // 15% away from the original. The editor's own landscape says so.
        var land = PageSetup.letter.rotated()
        XCTAssertTrue(land.isLandscape && land.orientStated)
        let xml = String(decoding: try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: land)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:pgSz w:w=\"15840\" w:h=\"12240\" w:orient=\"landscape\"/>"), xml)
        land.orientStated = false
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: land))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        let bare = String(decoding: entries[di].data, as: UTF8.self)
        XCTAssertTrue(bare.contains("<w:pgSz w:w=\"15840\" w:h=\"12240\"/>"), bare)
        let read = try XCTUnwrap(try DocxFormat.read(try Zip.write(entries)).pageSetup)
        XCTAssertFalse(read.orientStated)
        XCTAssertTrue(read.isLandscape)
    }

    /// Fresh Word controls: odd/even starts use the continued page number,
    /// count an inserted blank, and round a stated restart to the right side.
    /// The section can begin with a table (zh-291fcea7), not just a paragraph.
    func testOddAndEvenSectionStarts() throws {
        let geometry = "<w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\"/>"
        func check(_ kind: String, previousPages: Int = 1, previousStart: Int = 1,
                   restart: Int? = nil, evenHeaders: Bool = false, table: Bool = false, pages: Int) throws {
            var entries = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
            let index = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
            var body = "<w:p><w:r><w:t>FIRST</w:t></w:r></w:p>"
            if previousPages == 2 { body += "<w:p><w:pPr><w:pageBreakBefore/></w:pPr><w:r><w:t>CONTINUED</w:t></w:r></w:p>" }
            body += "<w:p><w:pPr><w:sectPr>\(geometry)<w:pgNumType w:start=\"\(previousStart)\"/></w:sectPr></w:pPr></w:p>"
            let second = "<w:p><w:r><w:t>SECOND</w:t></w:r></w:p>"
            body += table ? "<w:tbl><w:tblPr><w:tblpPr w:vertAnchor=\"page\" w:horzAnchor=\"margin\" w:tblpY=\"2000\" w:tblpX=\"0\"/><w:tblW w:type=\"dxa\" w:w=\"4000\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/></w:tblGrid><w:tr><w:tc>\(second)</w:tc></w:tr></w:tbl><w:p/>" : second
            body += "<w:sectPr><w:type w:val=\"\(kind)\"/>\(geometry)"
            if let restart { body += "<w:pgNumType w:start=\"\(restart)\"/>" }
            body += "</w:sectPr>"
            entries[index] = ZipEntry(name: "word/document.xml", data: Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(body)</w:body></w:document>".utf8))
            let loaded = try DocxFormat.read(Zip.write(entries))
            var doc = loaded.document
            doc.evenAndOddHeaders = evenHeaders
            let setup = try XCTUnwrap(loaded.pageSetup)
            XCTAssertEqual(setup.sectionStartParity, kind == "oddPage" ? .odd : .even)
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = setup
            layout.width = setup.width * theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            XCTAssertEqual(layout.pageCount, pages, "\(kind), previous \(previousPages) from \(previousStart), restart \(String(describing: restart)), table \(table)")
            guard layout.pageCount == pages else { return }
            let secondIndex = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "SECOND" })
            XCTAssertTrue(layout.pieces[pages - 1].contains { $0.paragraph == secondIndex })
            if pages > previousPages + 1 { XCTAssertTrue(layout.pieces[previousPages].isEmpty) }
            let back = try DocxFormat.read(DocxFormat.write(doc, pageSetup: setup))
            XCTAssertEqual(back.pageSetup?.sectionStartParity, setup.sectionStartParity)
        }
        for table in [false, true] {
            try check("oddPage", table: table, pages: 3)
            try check("evenPage", table: table, pages: 2)
            try check("oddPage", previousPages: 2, table: table, pages: 3)
            try check("evenPage", previousPages: 2, table: table, pages: 4)
            try check("oddPage", previousStart: 2, table: table, pages: 2)
            try check("evenPage", previousStart: 2, table: table, pages: 3)
            for restart in [1, 2] {
                try check("oddPage", restart: restart, table: table, pages: 2)
                try check("evenPage", restart: restart, table: table, pages: 2)
            }
        }
        try check("oddPage", restart: 1, evenHeaders: true, pages: 3)
        try check("evenPage", restart: 2, evenHeaders: true, pages: 2)
    }

    func testNoPageBreakBeforeAfterAPageStartingSection() throws {
        // bug65649: a kept next-page section break followed by a table whose
        // first paragraph also said pageBreakBefore gave Word an empty page.
        var a = RichParagraph(text: "end of section"), b = RichParagraph(text: "next")
        a.style.sectionXML = "<w:sectPr><w:type w:val=\"nextPage\"/><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"708\" w:footer=\"708\" w:gutter=\"0\"/></w:sectPr>"
        b.style.pageBreakBefore = true
        let doc = RichDocument(paragraphs: [a, b, RichParagraph(text: "tail")])
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:type w:val=\"nextPage\"/>"), xml)
        XCTAssertFalse(xml.contains("<w:pageBreakBefore/>"), xml)
        var cont = doc
        cont.paragraphs[0].style.sectionXML = cont.paragraphs[0].style.sectionXML!.replacingAll("nextPage", with: "continuous")
        let cxml = String(decoding: try Zip.read(try DocxFormat.write(cont, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(cxml.contains("<w:pageBreakBefore/>"), cxml)
    }

    /// zh-ea70c30e's "(c)" items: Body Text Indent 2 (left 1440) on a level
    /// that states only firstLine 720, the paragraph only hanging 720 — the
    /// item keeps its style's left, its label hanging half an inch.
    func testAListItemWithNoLeftOfItsOwnKeepsItsStyles() throws {
        var item = RichParagraph(text: "item")
        item.style.list = .numbered; item.style.listId = "4"
        var doc = RichDocument(paragraphs: [item])
        doc.listFormats["4"] = [0: { var f = ListLevelFormat(text: "(%1)", format: .lowerLetter); f.hanging = -36; return f }()]
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        while let r = xml.range(of: "<w:ind [^>]*/>", options: .regularExpression) { xml.removeSubrange(r) }
        xml = xml.replacingAll("<w:pStyle w:val=\"ListParagraph\"/>", with: "")
        let pPr = try XCTUnwrap(xml.range(of: "<w:pPr>"))
        xml.insert(contentsOf: "<w:pStyle w:val=\"BodyTextIndent2\"/>", at: pPr.upperBound)
        let close = try XCTUnwrap(xml.range(of: "</w:pPr>"))
        xml.insert(contentsOf: "<w:ind w:hanging=\"720\"/>", at: close.lowerBound)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        let end = try XCTUnwrap(styles.range(of: "</w:styles>"))
        styles.insert(contentsOf: "<w:style w:type=\"paragraph\" w:styleId=\"BodyTextIndent2\"><w:name w:val=\"Body Text Indent 2\"/><w:pPr><w:ind w:left=\"1440\"/></w:pPr></w:style>",
                      at: end.lowerBound)
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        // (The level says only its first line, as the file's does.)
        let ni = try XCTUnwrap(entries.firstIndex { $0.name == "word/numbering.xml" })
        var numbering = String(decoding: entries[ni].data, as: UTF8.self)
        while let r = numbering.range(of: "<w:ind w:left=\"[0-9]+\" w:firstLine=\"720\"/>", options: .regularExpression) {
            numbering.replaceSubrange(r, with: "<w:ind w:firstLine=\"720\"/>")
        }
        entries[ni] = ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertNotNil(back.paragraphs[0].style.list)
        XCTAssertNil(back.listFormats["4"]?[0]?.indentLeft ?? back.listFormats.values.first { $0[0]?.hanging == -36 }?[0]?.indentLeft)
        XCTAssertEqual(back.paragraphs[0].style.listIndentLeft, 72)
        XCTAssertEqual(back.paragraphs[0].style.listFirstLine, -36)
    }

    func testListParagraphMarkAndFirstLineKept() throws {
        // bug65649: a centred numbered heading whose mark is bold 12pt
        // (Word sets the number in it) and which says firstLine 0 under a
        // level hanging 375.
        var h = RichParagraph(text: "Heading")
        h.style.list = .numbered; h.style.listId = "19"; h.style.alignment = .center
        var doc = RichDocument(paragraphs: [h, RichParagraph(text: "body")])
        doc.listFormats["19"] = [0: { var f = ListLevelFormat(text: "%1.", format: .decimal); f.indentLeft = 47.1; f.hanging = 18.75; return f }()]
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:jc w:val=\"center\"/></w:pPr>", with: "<w:ind w:left=\"0\" w:firstLine=\"0\"/><w:jc w:val=\"center\"/><w:rPr><w:b/><w:sz w:val=\"24\"/></w:rPr></w:pPr>")
        XCTAssertTrue(xml.contains("<w:firstLine=\"0\"") || xml.contains("w:firstLine=\"0\"/>"), xml)
        let editorXML = xml
        // The file's heading has no paragraph style of its own.
        xml = xml.replacingAll("<w:pStyle w:val=\"ListParagraph\"/>", with: "")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].style.listFirstLine, 0)
        XCTAssertEqual(back.paragraphs[0].style.listIndentLeft, 0)
        XCTAssertEqual(back.paragraphs[0].style.mark?.bold, true)
        XCTAssertEqual(back.paragraphs[0].style.mark?.fontSize, 12)
        XCTAssertNil(back.paragraphs[1].style.mark)
        let again = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(again.contains("<w:ind w:left=\"0\" w:firstLine=\"0\"/>"), again)
        XCTAssertTrue(again.contains("<w:jc w:val=\"center\"/><w:rPr><w:b/><w:bCs/><w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/></w:rPr></w:pPr><w:r>"), again)
        // The file gave the heading no style, so none is added (the editor's
        // own lists get List Paragraph); contextual spacing then still
        // matches the plain paragraph after it.
        XCTAssertTrue(editorXML.contains("<w:pStyle w:val=\"ListParagraph\"/>"), "an editor-made list: \(editorXML)")
        XCTAssertFalse(again.contains("<w:pStyle w:val=\"ListParagraph\"/>"), again)
    }

    func testAutoCellWidthsAndVerticalAlignRoundTrip() throws {
        // bib-chernigovka: tcW auto everywhere (Word autofits the columns)
        // and every cell centred vertically.
        var a = RichParagraph(text: "5"), b = RichParagraph(text: "long text")
        a.cell = CellRef(table: "T", row: 0, column: 0, verticalAlign: "center")
        b.cell = CellRef(table: "T", row: 0, column: 1, verticalAlign: "center")
        var doc = RichDocument(paragraphs: [a, b, RichParagraph(text: "")])
        doc.tableColumns["T"] = [50, 400]
        var ts = TableStyle(); ts.autoCellWidths = true; doc.tableStyles["T"] = ts
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<w:tcW w:w=\"0\" w:type=\"auto\"/>").count, 3, xml)
        XCTAssertEqual(xml.components(separatedBy: "<w:vAlign w:val=\"center\"/>").count, 3, xml)
        XCTAssertFalse(xml.contains("w:type=\"dxa\"/><w:gridSpan"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.tableStyles.values.first?.autoCellWidths, true)
        XCTAssertEqual(back.paragraphs[0].cell?.verticalAlign, "center")
        // Stated widths stay stated.
        var fixed = doc
        fixed.tableStyles["T"]!.autoCellWidths = false
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(fixed, pageSetup: .letter)).document.tableStyles.values.first?.autoCellWidths ?? false, false)
    }

    func testInlinePictureKeptVerbatimUntilResized() throws {
        // issue_51265_3: four inline pictures with effectExtent, which the
        // regenerated markup dropped.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(image: ImageAttachment(data: png, width: 72, height: 36))]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<wp:docPr", with: "<wp:effectExtent l=\"19050\" t=\"0\" r=\"8214\" b=\"0\"/><wp:docPr")
        XCTAssertTrue(xml.contains("<wp:effectExtent"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        var back = try DocxFormat.read(try Zip.write(entries)).document
        let att = try XCTUnwrap(back.paragraphs[0].image)
        XCTAssertEqual(att.sourceWidth, 72)
        XCTAssertTrue(att.sourceXML?.contains("effectExtent") ?? false)
        let same = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(same.contains("<wp:effectExtent"), same)
        // Resized in the editor: regenerated at the new size.
        back.paragraphs[0].image!.width = 144; back.paragraphs[0].image!.height = 72
        let resized = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertFalse(resized.contains("<wp:effectExtent"), resized)
        XCTAssertTrue(resized.contains("cx=\"1828800\""), resized)
    }

    /// A file with an endnotes part: each note read like the body for the
    /// layout to set after the last paragraph, its own mark in the
    /// endnotes' numbering (endnotes.docx: "i XXX" in Word's print).
    func testEndnotesReadForTheLayout() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "Body with a note here.")]), pageSetup: .letter))
        let endnotes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:endnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:endnote w:type="separator" w:id="0"><w:p><w:r><w:separator/></w:r></w:p></w:endnote><w:endnote w:type="continuationSeparator" w:id="1"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:endnote><w:endnote w:id="2"><w:p><w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:endnoteRef/></w:r><w:r><w:t xml:space="preserve"> XXX</w:t></w:r></w:p></w:endnote></w:endnotes>
        """
        entries.append(ZipEntry(name: "word/endnotes.xml", data: Data(endnotes.utf8)))
        let i = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[i].data, as: UTF8.self)
        xml = xml.replacingAll("<w:t xml:space=\"preserve\">Body with a note here.</w:t></w:r>",
                               with: "<w:t xml:space=\"preserve\">Body with a note</w:t></w:r><w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:endnoteReference w:id=\"2\"/></w:r><w:r><w:t xml:space=\"preserve\"> here.</w:t></w:r>")
        XCTAssertTrue(xml.contains("w:endnoteReference"), "the fixture's run text must match: \(xml)")
        entries[i] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].text, "Body with a notei here.")
        XCTAssertEqual(back.endnotes.keys.sorted(), [2])
        XCTAssertEqual(back.endnotes[2]?.map(\.text), ["i XXX"])
        XCTAssertEqual(back.endnoteSeparator.count, 1)
    }

    func testALineWhoseNoteHasNoRoomGoesOverWithIt() throws {
        // zh-c15af02e's footnote 1, one line, is marked in the line that
        // would end page 5; with no room for a line of the note under it,
        // Word's print takes that line to page 6 with the note. Ours kept
        // the line and sent the note over alone.
        // Here: 698pt of page, a 673pt filler, then a 20pt line marking a
        // note — the line fits the 25pt left, the separator and note do not.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let footnotes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote><w:footnote w:id="1"><w:p><w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> note</w:t></w:r></w:p></w:footnote></w:footnotes>
        """
        entries.append(ZipEntry(name: "word/footnotes.xml", data: Data(footnotes.utf8)))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
        func exact(_ twips: Int) -> String { "<w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(twips)\" w:lineRule=\"exact\"/></w:pPr>" }
        xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: "<w:p>\(exact(13460))<w:r><w:t>filler</w:t></w:r></w:p>"
            + "<w:p>\(exact(400))<w:r><w:t>marked</w:t></w:r><w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:footnoteReference w:id=\"1\"/></w:r></w:p>"
            + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let opened = try DocxFormat.read(try Zip.write(entries))
        let doc = opened.document
        XCTAssertEqual(doc.footnotes.keys.sorted(), [1])
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let marked = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("marked") })
        XCTAssertEqual(l.pageCount, 2)
        XCTAssertFalse(l.pieces[0].contains { $0.paragraph == marked }, "the marking line goes over with its note")
    }

    func testAPicturesLineOffItsSectionsGridTakesItsMultiplesExtra() throws {
        // Lab `pn` (Word 16 Mac, zh-e68a2f57's package): a chart alone in
        // a paragraph of 1.1 lines, snapToGrid 0, in a section with a line
        // grid — the note under it 1.20 lower than at single, 0.1 of the
        // 9pt mark's line, as off any grid (lab `hp`); ours added nothing.
        func height(line: Int) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let picture = "<w:r><w:drawing><wp:inline xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\"><wp:extent cx=\"2540000\" cy=\"1270000\"/><wp:docPr id=\"1\" name=\"p\"/></wp:inline></w:drawing></w:r>"
            var parts: [String] = []
            parts.append("<w:p><w:pPr><w:snapToGrid w:val=\"0\"/><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(line)\" w:lineRule=\"auto\"/><w:rPr><w:sz w:val=\"18\"/></w:rPr></w:pPr>\(picture)</w:p>")
            parts.append("<w:p><w:r><w:t>note</w:t></w:r></w:p>")
            parts.append("<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/><w:docGrid w:type=\"lines\" w:linePitch=\"312\"/></w:sectPr>")
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: parts.joined())
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            XCTAssertNotNil(doc.paragraphs[0].image ?? doc.paragraphs[0].inlineImages.values.first, "the picture is read")
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            let note = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "note" })
            return try XCTUnwrap(l.pieces[0].first { $0.paragraph == note }).pageY / theme.pixelsPerPoint
        }
        let extra = try height(line: 360) - height(line: 240)
        XCTAssertGreaterThan(extra, 3, "half the mark's line under the picture at 1.5 lines")
        XCTAssertLessThan(extra, 10, "not half the picture")
    }

    func testAMergedLabelIsCentredDownToAGhostRowsPart() throws {
        // zh-9ef811c8's "综合业务", merged from a row into the next — whose
        // cells are merged down over rows holding nothing, parting at
        // page 4's foot at one of those rows' tops (lab `mg`) — stands
        // centred down to that part's foot in Word's print; ours centred
        // it in its first row alone, 43pt high.
        // Here: a row of one line with the label beside it, then a row
        // whose cells are merged over three empty rows of 60pt, two of
        // which fit the page.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
        func p(_ text: String) -> String {
            "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"400\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
        }
        func cell(_ props: String, _ content: String) -> String { "<w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/>\(props)</w:tcPr>\(content)</w:tc>" }
        let centre = "<w:vAlign w:val=\"center\"/>"
        let restart = "<w:vMerge w:val=\"restart\"/>\(centre)", goesOn = "<w:vMerge/>\(centre)"
        let borders = "<w:tblBorders><w:top w:val=\"single\" w:sz=\"4\"/><w:left w:val=\"single\" w:sz=\"4\"/><w:bottom w:val=\"single\" w:sz=\"4\"/><w:right w:val=\"single\" w:sz=\"4\"/><w:insideH w:val=\"single\" w:sz=\"4\"/><w:insideV w:val=\"single\" w:sz=\"4\"/></w:tblBorders>"
        var parts: [String] = []
        parts.append("<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"9600\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>filler</w:t></w:r></w:p>")
        parts.append("<w:tbl><w:tblPr><w:tblW w:w=\"8000\" w:type=\"dxa\"/>\(borders)</w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/><w:gridCol w:w=\"4000\"/></w:tblGrid>")
        parts.append("<w:tr>\(cell(restart, p("label one") + p("label two")))\(cell("", p("first")))</w:tr>")
        parts.append("<w:tr>\(cell(goesOn, "<w:p/>"))\(cell(restart, p("merged")))</w:tr>")
        for _ in 1 ... 3 {
            parts.append("<w:tr><w:trPr><w:trHeight w:val=\"1200\"/></w:trPr>\(cell(goesOn, "<w:p/>"))\(cell(goesOn, "<w:p/>"))</w:tr>")
        }
        parts.append("</w:tbl><w:p/><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
        xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: parts.joined())
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let opened = try DocxFormat.read(try Zip.write(entries))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        XCTAssertGreaterThan(l.pageCount, 1, "the merged rows part over the page")
        let label = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "label one" })
        let first = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "first" })
        // (Where its text is drawn on the page, against the first row's
        // line beside it.)
        func drawn(_ k: Int) throws -> Double {
            let piece = try XCTUnwrap(l.pieces[0].first { $0.paragraph == k && $0.part != .rules })
            return piece.pageY + l.geometry(k).textTop - piece.flowTop
        }
        let down = (try drawn(label) - drawn(first)) / theme.pixelsPerPoint
        XCTAssertGreaterThan(down, 30, "centred down the part on the page, not in its first row")
    }

    func testACentredCellSetWholeInAPartKeepsItsRowForAMergeAbove() throws {
        // zh-1eeb9f9a p8: "公开渠道和载体", centred and merged down into a row
        // that parts at the foot, stands centred down to that row's kept
        // lines in Word's print. Beside them the row's "其他政策文件", two
        // lines centred in the whole row, would end past the foot there —
        // but it is set whole in the part, so the row does part; ours read
        // it as keeping nothing and centred the merge over the rows above
        // alone, 8pt low.
        // Here: "merged" over two rows of one line and a third that parts
        // with two of ten lines on page 1, a centred two-line cell beside.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
        func p(_ text: String) -> String {
            "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"400\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
        }
        func cell(_ props: String, _ content: String) -> String { "<w:tc><w:tcPr><w:tcW w:w=\"2600\" w:type=\"dxa\"/>\(props)</w:tcPr>\(content)</w:tc>" }
        let centre = "<w:vAlign w:val=\"center\"/>"
        let restart = "<w:vMerge w:val=\"restart\"/>\(centre)", goesOn = "<w:vMerge/>\(centre)"
        let borders = "<w:tblBorders><w:top w:val=\"single\" w:sz=\"4\"/><w:left w:val=\"single\" w:sz=\"4\"/><w:bottom w:val=\"single\" w:sz=\"4\"/><w:right w:val=\"single\" w:sz=\"4\"/><w:insideH w:val=\"single\" w:sz=\"4\"/><w:insideV w:val=\"single\" w:sz=\"4\"/></w:tblBorders>"
        var parts: [String] = []
        parts.append("<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"12000\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>filler</w:t></w:r></w:p>")
        parts.append("<w:tbl><w:tblPr><w:tblW w:w=\"7800\" w:type=\"dxa\"/>\(borders)</w:tblPr><w:tblGrid><w:gridCol w:w=\"2600\"/><w:gridCol w:w=\"2600\"/><w:gridCol w:w=\"2600\"/></w:tblGrid>")
        parts.append("<w:tr>\(cell(restart, p("merged")))\(cell("", p("first")))\(cell("", p("x")))</w:tr>")
        parts.append("<w:tr>\(cell(goesOn, "<w:p/>"))\(cell("", p("second")))\(cell("", p("y")))</w:tr>")
        let long = (1 ... 10).map { n -> String in p("long \(n)") }.joined()
        parts.append("<w:tr>\(cell(goesOn, "<w:p/>"))\(cell(centre, p("label one") + p("label two")))\(cell("", long))</w:tr>")
        parts.append("</w:tbl><w:p/><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
        xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: parts.joined())
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let opened = try DocxFormat.read(try Zip.write(entries))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        XCTAssertGreaterThan(l.pageCount, 1, "the last row parts over the page")
        let merged = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "merged" })
        let first = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "first" })
        let long2 = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "long 2" })
        XCTAssertTrue(l.pieces[0].contains { $0.paragraph == long2 }, "two of the long cell's lines on page 1")
        func drawn(_ k: Int) throws -> Double {
            let piece = try XCTUnwrap(l.pieces[0].first { $0.paragraph == k && $0.part != .rules })
            return piece.pageY + l.geometry(k).textTop - piece.flowTop
        }
        // (Centred in 20 + 20 + 40: 30pt down; over the two rows alone, 10.)
        let down = (try drawn(merged) - drawn(first)) / theme.pixelsPerPoint
        XCTAssertEqual(down, 30, accuracy: 3, "centred down to the parted row's kept lines")
    }

    func testARowOfNoCellSpacingInASpacedTableCollapsesItsLines() throws {
        // zh-147bdae0's commitment tables state a cell spacing of 0 and
        // most of their rows nil (`w:tblPrEx`): those rows step one 0.5pt
        // line apart in Word's print, 21.1pt a one-line row, where ours
        // took the line twice, 21.6, and p17's last row went over whole.
        func step(_ rowSpacing: String) throws -> (Double, String) {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let borders = "<w:tcBorders><w:top w:val=\"single\" w:sz=\"4\"/><w:left w:val=\"single\" w:sz=\"4\"/><w:bottom w:val=\"single\" w:sz=\"4\"/><w:right w:val=\"single\" w:sz=\"4\"/></w:tcBorders>"
            func row(_ text: String) -> String {
                "<w:tr>\(rowSpacing)<w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/>\(borders)</w:tcPr><w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"400\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p></w:tc></w:tr>"
            }
            let table = "<w:tbl><w:tblPr><w:tblW w:w=\"4000\" w:type=\"dxa\"/><w:tblCellSpacing w:w=\"0\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/></w:tblGrid>"
                + row("r1") + row("r2") + row("r3") + "</w:tbl><w:p/>"
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: table + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            func drawn(_ text: String) throws -> Double {
                let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == text })
                let piece = try XCTUnwrap(l.pieces[0].first { $0.paragraph == k && $0.part != .rules })
                return piece.pageY + l.geometry(k).textTop - piece.flowTop
            }
            let saved = try Zip.read(try DocxFormat.write(doc, pageSetup: setup)).first { $0.name == "word/document.xml" }!
            return ((try drawn("r3") - drawn("r2")) / theme.pixelsPerPoint, String(decoding: saved.data, as: UTF8.self))
        }
        let spaced = try step("")
        XCTAssertEqual(spaced.0, 21, accuracy: 0.05, "each row its own two lines")
        let unspaced = try step("<w:tblPrEx><w:tblCellSpacing w:w=\"0\" w:type=\"nil\"/></w:tblPrEx>")
        XCTAssertEqual(unspaced.0, 20.5, accuracy: 0.05, "the rows share their line")
        XCTAssertTrue(unspaced.1.contains("<w:tblPrEx><w:tblCellSpacing w:type=\"nil\" w:w=\"0\"/>"), "the rows' own spacing goes back")
    }

    func testAListsLastItemInACellKeepsItsAutomaticSpaceAfter() throws {
        // zh-147bdae0's numbered commitments, automatically spaced, end
        // their cells 14pt over the bottom line in Word's print, where a
        // cell's one plain paragraph so spaced has none under it.
        func gap(numbered: Bool) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let num = numbered ? "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr>" : ""
            func p(_ text: String, _ list: String) -> String {
                "<w:p><w:pPr>\(list)<w:spacing w:before=\"100\" w:beforeAutospacing=\"1\" w:after=\"100\" w:afterAutospacing=\"1\" w:line=\"400\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
            }
            func cell(_ content: String) -> String { "<w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/></w:tcPr>\(content)</w:tc>" }
            let table = "<w:tbl><w:tblPr><w:tblW w:w=\"4000\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/></w:tblGrid>"
                + "<w:tr>\(cell(p("one", num) + p("two", num)))</w:tr><w:tr>\(cell(p("next", "")))</w:tr></w:tbl><w:p/>"
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: table + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let numbering = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/><w:pPr><w:ind w:left=\"480\" w:hanging=\"480\"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
            let ni = try XCTUnwrap(entries.firstIndex { $0.name == "word/numbering.xml" })
            entries[ni] = ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            func drawn(_ text: String) throws -> Double {
                let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == text })
                let piece = try XCTUnwrap(l.pieces[0].first { $0.paragraph == k && $0.part != .rules })
                return piece.pageY + l.geometry(k).textTop - piece.flowTop
            }
            return (try drawn("next") - drawn("two")) / theme.pixelsPerPoint
        }
        let plain = try gap(numbered: false), listed = try gap(numbered: true)
        XCTAssertEqual(plain, 20, accuracy: 0.05, "a plain paragraph's space after gives way at the cell's end")
        XCTAssertEqual(listed - plain, 14, accuracy: 0.05, "the list's last item keeps its 14pt")
    }

    func testAPartedRowOpensWithItsOwnTopLine() throws {
        // Lab `tb` (Word 16 Mac, zh-13552a3a's package): cells of top nil
        // and bottom single, a row parted at page 1's foot — page 2 opens
        // with no line and the text at the margin; with the cells' top
        // single 4 the line is drawn and the text stands 0.48 lower.
        func opening(top: String) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            func p(_ text: String) -> String {
                "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"312\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
            }
            let borders = "<w:tcBorders><w:top w:val=\"\(top)\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/><w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/></w:tcBorders>"
            func row(_ content: String) -> String { "<w:tr><w:tc><w:tcPr><w:tcW w:w=\"8000\" w:type=\"dxa\"/>\(borders)</w:tcPr>\(content)</w:tc></w:tr>" }
            var parts: [String] = ["<w:tbl><w:tblPr><w:tblW w:w=\"8000\" w:type=\"dxa\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"8000\"/></w:tblGrid>"]
            for n in 1 ... 5 { parts.append(row(p("row \(n)"))) }
            parts.append(row((1 ... 60).map { n -> String in p("long \(n)") }.joined()))
            parts.append("</w:tbl><w:p/><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: parts.joined())
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            XCTAssertGreaterThan(l.pageCount, 1)
            let first = try XCTUnwrap(l.pieces[1].filter { doc.paragraphs[$0.paragraph].text.hasPrefix("long") && $0.part != .rules }.map(\.pageY).min())
            return first / theme.pixelsPerPoint
        }
        XCTAssertEqual(try opening(top: "nil"), 0, accuracy: 0.01, "no line, no room: the text at the margin")
        XCTAssertGreaterThan(try opening(top: "single"), 0.3, "under the line it opens with")
    }

    func testAMergedCellSetWholeInAPartIsNotDrawnAgain() throws {
        // zh-13552a3a's "4.就业失业登记", centred and merged over rows 10-11,
        // stands whole in row 10's part at page 15's foot in Word's print,
        // and once; its text, centred over both rows, reaches past row 10's
        // own bottom, and ours drew those lines again at page 16's head.
        // Here: a label of three lines merged over a row of 30 lines that
        // parts at the foot and a row of 30 more, with a filler above.
        func kept(filler: Int) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            func p(_ text: String) -> String {
                "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"300\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
            }
            func long(_ tag: String) -> String { (1 ... 30).map { n -> String in p("\(tag) \(n)") }.joined() }
            let label = "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"300\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>label one</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>label two</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>label three</w:t></w:r></w:p>"
            func cell(_ props: String, _ content: String) -> String { "<w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/>\(props)</w:tcPr>\(content)</w:tc>" }
            let borders = "<w:tblBorders><w:top w:val=\"single\" w:sz=\"4\"/><w:left w:val=\"single\" w:sz=\"4\"/><w:bottom w:val=\"single\" w:sz=\"4\"/><w:right w:val=\"single\" w:sz=\"4\"/><w:insideH w:val=\"single\" w:sz=\"4\"/><w:insideV w:val=\"single\" w:sz=\"4\"/></w:tblBorders>"
            var parts: [String] = []
            parts.append("<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(filler)\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>filler</w:t></w:r></w:p>")
            parts.append("<w:tbl><w:tblPr><w:tblW w:w=\"8000\" w:type=\"dxa\"/>\(borders)</w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/><w:gridCol w:w=\"4000\"/></w:tblGrid>")
            let restart = cell("<w:vMerge w:val=\"restart\"/><w:vAlign w:val=\"center\"/>", label)
            let merged = cell("<w:vMerge/><w:vAlign w:val=\"center\"/>", "<w:p/>")
            parts.append("<w:tr>\(restart)\(cell("", long("first")))</w:tr>")
            parts.append("<w:tr>\(merged)\(cell("", long("second")))</w:tr>")
            parts.append("</w:tbl><w:p/><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: parts.joined())
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            let target = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("label") })
            // (What of its text lines each piece shows: a merged cell's
            // window may reach far past them.)
            let g = l.geometry(target)
            let top = g.textTop, bottom = g.textTop + g.painter.height
            var drawn = 0.0
            for page in 0 ..< l.pageCount {
                for piece in l.pieces[page] where piece.paragraph == target && piece.part != .rules {
                    drawn += max(0, min(piece.flowBottom, bottom) - max(piece.flowTop, top))
                }
            }
            return drawn / theme.pixelsPerPoint
        }
        // (The label's lines are drawn once, wherever the rows part.)
        for filler in stride(from: 4000, through: 9000, by: 500) {
            XCTAssertLessThanOrEqual(try kept(filler: filler), 45.5, "filler \(filler / 20)pt: the label drawn once")
        }
    }

    func testARowWhoseNoteHasNoRoomPartsWithIt() throws {
        // zh-499adba6's book is a one-column table, a paragraph a row; its
        // footnote 11, marked in the second line of a seven-line row near
        // page 90's foot, parts there in Word's print and the row with it.
        // Ours set the row whole — it fits without the note — and reserved
        // the note after it, over its last lines.
        // Here: 698pt of page, a 540pt row, then a row of seven 20pt lines
        // marking on its second a note of ten 12pt lines.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let lines = (1 ... 10).map { "<w:r><w:t>note \($0)</w:t></w:r>" }.joined(separator: "<w:r><w:br/></w:r>")
        let footnotes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote><w:footnote w:id="1"><w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="exact"/></w:pPr><w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:footnoteRef/></w:r>\(lines)</w:p></w:footnote></w:footnotes>
        """
        entries.append(ZipEntry(name: "word/footnotes.xml", data: Data(footnotes.utf8)))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
        func exact(_ twips: Int) -> String { "<w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(twips)\" w:lineRule=\"exact\"/></w:pPr>" }
        let marked = (1 ... 7).map { n in "<w:r><w:t>row \(n)</w:t></w:r>" + (n == 2 ? "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:footnoteReference w:id=\"1\"/></w:r>" : "") }
            .joined(separator: "<w:r><w:br/></w:r>")
        func row(_ p: String) -> String { "<w:tr><w:tc><w:tcPr><w:tcW w:w=\"9000\" w:type=\"dxa\"/></w:tcPr>\(p)</w:tc></w:tr>" }
        xml.replaceSubrange(body.upperBound ..< end.lowerBound, with:
            "<w:tbl><w:tblPr><w:tblW w:w=\"9000\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w=\"9000\"/></w:tblGrid>"
            + row("<w:p>\(exact(10800))<w:r><w:t>filler</w:t></w:r></w:p>")
            + row("<w:p>\(exact(400))\(marked)</w:p>")
            + "</w:tbl><w:p/><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let opened = try DocxFormat.read(try Zip.write(entries))
        let doc = opened.document
        XCTAssertEqual(doc.footnotes.keys.sorted(), [1])
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let target = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("row 1") })
        let here = l.pieces[0].filter { $0.paragraph == target && $0.part != .rules }
        let kept = here.map { $0.flowBottom - $0.flowTop }.reduce(0, +) / theme.pixelsPerPoint
        XCTAssertGreaterThan(kept, 30, "the row keeps its marking line on the page")
        XCTAssertLessThan(kept, 139, "and parts there, not set whole under its note")
    }

    func testAGridLineDoesNotHangIntoTheFootnotes() throws {
        // zh-c15af02e's page 6: lines on a grid over a one-line note. A
        // page's last line may reach past the foot by its grid's overhang,
        // but not into the notes: Word's print holds thirteen, the
        // fourteenth reaching 4.3pt into the separator's line.
        // Here: 698pt of page on a 20pt grid, a note of 6.5pt under a 12pt
        // separator — 679.5pt for 10pt lines a pitch each, the 34th 0.5pt
        // over. Without the note and with the foot 18.5pt higher, the 34th
        // hangs past it and stays.
        func kept(note: Bool) throws -> Int {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            if note {
                let footnotes = """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:footnote w:type="separator" w:id="-1"><w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="exact"/></w:pPr><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote><w:footnote w:id="1"><w:p><w:pPr><w:snapToGrid w:val="0"/><w:spacing w:before="0" w:after="0" w:line="130" w:lineRule="exact"/></w:pPr><w:r><w:rPr><w:vertAlign w:val="superscript"/><w:sz w:val="12"/></w:rPr><w:footnoteRef/></w:r><w:r><w:rPr><w:sz w:val="12"/></w:rPr><w:t xml:space="preserve"> note</w:t></w:r></w:p></w:footnote></w:footnotes>
                """
                entries.append(ZipEntry(name: "word/footnotes.xml", data: Data(footnotes.utf8)))
            }
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let ref = note ? "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:footnoteReference w:id=\"1\"/></w:r>" : ""
            let lines = (0 ..< 40).map { n in
                "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:r><w:rPr><w:sz w:val=\"20\"/></w:rPr><w:t>行文\(n)</w:t></w:r>\(n == 0 ? ref : "")</w:p>"
            }.joined()
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: lines
                + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"\(note ? 1440 : 1810)\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/><w:docGrid w:type=\"lines\" w:linePitch=\"400\"/></w:sectPr>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            theme.faceResolver = OfficeFonts.face
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            return Set(l.pieces[0].map(\.paragraph)).filter { doc.paragraphs[$0].text.hasPrefix("行文") }.count
        }
        XCTAssertEqual(try kept(note: false), 34, "the 34th hangs past a bare foot")
        XCTAssertEqual(try kept(note: true), 33, "but not into the notes")
    }

    func testACentredExactLineIsSetByTheBaselineWithoutSpaceForUL() throws {
        // Lab `ctr` (Word for Mac): zh-ee9d81b3, which lacks `w:spaceForUL`,
        // sets its 16pt YaHei in 35pt exact lines of `w:textAlignment`
        // "center" 34.53pt down — the baseline's place, 28.05, and the
        // text's middle more — where zh-1563bd74, which has it, centres
        // the text's own line in the exact one.
        func baseline(spaceForUL: Bool) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!, si = entries.firstIndex { $0.name == "word/settings.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with:
                "<w:p><w:pPr><w:spacing w:line=\"700\" w:lineRule=\"exact\"/><w:textAlignment w:val=\"center\"/></w:pPr>"
                + "<w:r><w:rPr><w:rFonts w:ascii=\"Microsoft YaHei\" w:eastAsia=\"Microsoft YaHei\" w:hAnsi=\"Microsoft YaHei\"/><w:sz w:val=\"32\"/></w:rPr>"
                + "<w:t>三、配合參加</w:t></w:r></w:p>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let settings = "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:compat>"
                + (spaceForUL ? "<w:spaceForUL/>" : "") + "</w:compat></w:settings>"
            entries[si] = ZipEntry(name: "word/settings.xml", data: Data(settings.utf8))
            let doc = try DocxFormat.read(Zip.write(entries)).document
            XCTAssertEqual(doc.spacesForUnderline, spaceForUL)
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.wordRules = true
            theme.faceResolver = OfficeFonts.face
            let p = doc.paragraphs[0]
            return try XCTUnwrap(theme.baseline(for: p.runs[0].style, in: p.style, named: nil, eastAsian: true, gridPitch: nil,
                                                centresInLine: doc.spacesForUnderline))
        }
        let centred = try baseline(spaceForUL: true), low = try baseline(spaceForUL: false)
        XCTAssertEqual(centred, 23.94, accuracy: 0.3, "the text's own line centred in the exact one")
        XCTAssertEqual(low, 34.53, accuracy: 0.6, "the baseline's place and the text's middle")
    }

    func testAPageFootLineReachesByItsOwnFaces() throws {
        // zh-c15af02e's p11: a paragraph with a "%" in another face on its
        // second line, whose one pitch leaves 1pt, keeps its fifteenth
        // line 5.4pt past the foot in Word's print; ours took the 1pt for
        // every line. Here: 20pt pitches, 10pt lines, and a run of a size
        // that fills its pitch but for under half a point — the 34th line
        // 0.5pt past the foot is kept, unless that run is on it.
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        theme.faceResolver = OfficeFonts.face
        func document(odd: Int, size: Int) throws -> (RichDocument, PageSetup) {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let runs = (0 ..< 40).map { n in
                (n == odd ? "<w:r><w:rPr><w:sz w:val=\"\(size)\"/></w:rPr><w:t>X</w:t></w:r>" : "")
                    + "<w:r><w:rPr><w:sz w:val=\"20\"/></w:rPr><w:t>行文\(n)</w:t></w:r>" + (n < 39 ? "<w:r><w:br/></w:r>" : "")
            }.joined()
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with:
                "<w:p><w:pPr><w:snapToGrid w:val=\"0\"/><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"370\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>filler</w:t></w:r></w:p>"
                + "<w:p><w:pPr><w:widowControl w:val=\"0\"/><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr>\(runs)</w:p>"
                + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/><w:docGrid w:type=\"lines\" w:linePitch=\"400\"/></w:sectPr>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            return (opened.document, opened.pageSetup ?? .a4)
        }
        // (The size: the largest in half points whose line is one pitch
        // with less than 0.45pt left under the half leading.)
        func laid(_ line: Int, _ size: Int) throws -> (doc: RichDocument, layout: RichLayout, target: Int) {
            let (doc, setup) = try document(odd: line, size: size)
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            return (doc, l, try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.contains("行文") }))
        }
        // (A size whose line is one pitch in the layout itself, with less
        // than 0.45pt left under its half leading.)
        var size: Int? = nil
        for half in stride(from: 40, through: 24, by: -1) {
            let (doc, l, target) = try laid(0, half)
            let p = doc.paragraphs[target]
            guard let run = p.runs.first(where: { $0.style.fontSize == Double(half) / 2 }),
                  let first = l.geometry(target).painter.computeLineMetrics().first,
                  abs(first.height / theme.pixelsPerPoint - 20) < 0.01 else { continue }
            let reach = theme.gridOverhang(for: run.style, in: p.style, named: doc.styles.resolve(p.style), eastAsian: false, gridPitch: 20)
            if reach > 0.01, reach < 0.45 { size = half; break }
        }
        // (Which size that is depends on the faces registered, and after
        // some other tests' fonts there is none: the case cannot be set up.)
        guard let odd = size else { throw XCTSkip("no size fills a 20pt pitch but for under half a point with these faces") }
        func kept(_ line: Int) throws -> Int {
            let (_, l, target) = try laid(line, odd)
            let piece = try XCTUnwrap(l.pieces[0].first { $0.paragraph == target })
            return Int(((piece.flowBottom - piece.flowTop) / theme.pixelsPerPoint / 20).rounded())
        }
        XCTAssertEqual(try kept(0), 34, "an odd face on the first line does not hold the 34th back")
        XCTAssertEqual(try kept(33), 33, "on the 34th itself it does")
    }

    func testEmptyPictIsNothing() throws {
        // bug59058: a paragraph of nothing but `<w:pict/>` before a table —
        // no mark on Word's print and no room, where a 300 by 200 stand-in
        // set the table 187pt low.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        let xml = String(decoding: entries[di].data, as: UTF8.self).replacingAll("<w:t xml:space=\"preserve\">x</w:t>", with: "<w:pict/>")
        XCTAssertTrue(xml.contains("<w:pict/>"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let p = try DocxFormat.read(try Zip.write(entries)).document.paragraphs[0]
        XCTAssertNil(p.image)
        XCTAssertTrue(p.inlineImages.isEmpty)
        XCTAssertEqual(p.text, "")
    }

    func testFooterTableFloatingOverTheTextTakesNoRoom() throws {
        // PageSpecificHeadFoot: a footer's page-number table anchored to
        // the text (`w:tblpY` 1 twip) lies over the line after it in
        // Word's print; the line stands where it would with no table.
        var cell = RichParagraph(text: "Page 2")
        cell.cell = CellRef(table: "t", row: 0, column: 0)
        var doc = RichDocument(paragraphs: [cell, RichParagraph(text: "footer")])
        doc.tableColumns["t"] = [200]
        var ts = TableStyle()
        ts.floatOffsetY = 0.05
        ts.floatsOverText = true
        doc.tableStyles["t"] = ts
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        func laid(_ floats: Bool) -> RichLayout {
            let layout = RichLayout(theme: theme, paragraphCount: 2)
            layout.floatsFrames = floats
            layout.width = 400
            layout.ensureLaidOut(doc)
            return layout
        }
        let footer = laid(true)
        XCTAssertEqual(footer.geometry(1).top, 0, accuracy: 0.01, "the line is the footer's first")
        XCTAssertEqual(footer.totalHeight, footer.geometry(1).height, accuracy: 0.01, "the table takes no room")
        XCTAssertEqual(try XCTUnwrap(footer.rowRect(0)).top, 0.05 * theme.pixelsPerPoint, accuracy: 0.01, "and stands its offset under the line's top")
        // (In the body it is laid in the flow, as before.)
        XCTAssertGreaterThan(laid(false).geometry(1).top, 0)
        // Read from the file's anchor.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [cell, RichParagraph(text: "x")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        let xml = String(decoding: entries[di].data, as: UTF8.self)
            .replacingAll("<w:tblPr>", with: "<w:tblPr><w:tblpPr w:vertAnchor=\"text\" w:tblpY=\"1\"/>")
        XCTAssertTrue(xml.contains("w:tblpY"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let read = try DocxFormat.read(try Zip.write(entries)).document
        let style = try XCTUnwrap(read.paragraphs[0].cell.flatMap { read.tableStyles[$0.table] })
        XCTAssertTrue(style.floatsOverText)
        XCTAssertEqual(style.floatOffsetY, 0.05)
    }

    func testAnHTMLBlocksMarginsSpaceItsParagraph() throws {
        // drawing.docx: an empty paragraph naming an HTML block (w:divId)
        // of 15 twips over and 75 under, inside a body block of 150 all
        // round; Word's print stands what follows 4.5pt lower — the
        // block's own margins, the body's nowhere.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a"), RichParagraph(text: "b")]),
                                                        pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let first = try XCTUnwrap(xml.range(of: "<w:p>") ?? xml.range(of: "<w:p "))
        xml.replaceSubrange(first, with: "<w:p><w:pPr><w:divId w:val=\"7\"/></w:pPr></w:p>" + xml[first])
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let web = "<w:webSettings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:divs>"
            + "<w:div w:id=\"1\"><w:bodyDiv w:val=\"1\"/><w:marTop w:val=\"150\"/><w:marBottom w:val=\"150\"/><w:divsChild>"
            + "<w:div w:id=\"7\"><w:marTop w:val=\"15\"/><w:marBottom w:val=\"75\"/></w:div></w:divsChild></w:div></w:divs></w:webSettings>"
        entries.append(ZipEntry(name: "word/webSettings.xml", data: Data(web.utf8)))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(doc.paragraphs[0].style.divId, "7")
        XCTAssertEqual(doc.divMargins["7"], DivMargins(top: 0.75, bottom: 3.75))
        XCTAssertEqual(doc.divMargins["1"], DivMargins(top: 7.5, bottom: 7.5))
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        func gap(_ d: RichDocument) -> Double {
            let layout = RichLayout(theme: theme, paragraphCount: d.paragraphs.count)
            layout.width = 400
            layout.ensureLaidOut(d)
            return layout.geometry(1).top / theme.pixelsPerPoint
        }
        var bare = doc
        bare.divMargins = [:]
        XCTAssertEqual(gap(doc) - gap(bare), 4.5, accuracy: 0.01, "its own block's margins, over and under")
    }

    func testACellsOwnLineWidthIsNotTheTablesSideItDoesNotName() throws {
        // zh-701eda18 p4: a form framed by a 3pt thickThinSmallGap ends
        // on a row whose tallest cell states a 0.5pt double on its right
        // alone. Word's print gives the frame's bottom its own room under
        // that row; ours gave it the cell's 0.5pt, 2.5pt short, and all
        // after it stood that much high.
        func after(cellBorders: String, single: Bool = false) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
            let frame = "<w:top w:val=\"thinThickSmallGap\" w:sz=\"24\" w:space=\"0\" w:color=\"auto\"/>"
                + "<w:left w:val=\"thinThickSmallGap\" w:sz=\"24\" w:space=\"0\" w:color=\"auto\"/>"
                + "<w:bottom w:val=\"thickThinSmallGap\" w:sz=\"24\" w:space=\"0\" w:color=\"auto\"/>"
                + "<w:right w:val=\"thickThinSmallGap\" w:sz=\"24\" w:space=\"0\" w:color=\"auto\"/>"
                + "<w:insideH w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"auto\"/>"
                + "<w:insideV w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"auto\"/>"
            let plain = ["top", "left", "bottom", "right", "insideH", "insideV"]
                .map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/>" }.joined()
            xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
                "<w:tbl><w:tblPr><w:tblW w:w=\"4000\" w:type=\"dxa\"/><w:tblBorders>\(single ? plain : frame)</w:tblBorders></w:tblPr>"
                + "<w:tblGrid><w:gridCol w:w=\"2000\"/><w:gridCol w:w=\"2000\"/></w:tblGrid><w:tr>"
                + "<w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/>\(cellBorders)</w:tcPr><w:p><w:r><w:t>one</w:t></w:r></w:p><w:p><w:r><w:t>two</w:t></w:r></w:p></w:tc>"
                + "<w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>x</w:t></w:r></w:p></w:tc>"
                + "</w:tr></w:tbl><w:p><w:r><w:t>after</w:t></w:r></w:p>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let doc = try DocxFormat.read(try Zip.write(entries)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            l.width = 400
            l.ensureLaidOut(doc)
            let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "after" })
            return l.geometry(i).top / l.theme.pixelsPerPoint
        }
        let bare = try after(cellBorders: "")
        let right = try after(cellBorders: "<w:tcBorders><w:right w:val=\"double\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/></w:tcBorders>")
        XCTAssertEqual(right, bare, accuracy: 0.05, "the frame's bottom takes its own room under the row")
        // (But a cell's thick side line is no room over or under its row: lab
        // `cal` in zh-5251dd23's package, Word 16 — rows ruled 0.5pt with a
        // 2.25pt line on a cell's left stand as tall as without it.)
        let thin = try after(cellBorders: "", single: true)
        let thick = try after(cellBorders: "<w:tcBorders><w:left w:val=\"single\" w:sz=\"18\" w:space=\"0\" w:color=\"auto\"/></w:tcBorders>", single: true)
        XCTAssertEqual(thick, thin, accuracy: 0.05, "a side line takes no room over and under the row")
    }

    func testACentredNumberedLineIsSetAcrossItsHang() throws {
        // zh-3c055c9b's caption "表1　古佳川不實核銷表(…財物)": 表標題,
        // centred, on a level with a 24pt hang, is one line in Word's
        // print centred from the hang's edge to the right indent; ours
        // was laid out between the indents, and its last two characters
        // went over the page with the table under it.
        func geometry(_ alignment: ParagraphAlignment) -> (left: Double, width: Double, ppp: Double) {
            var p = RichParagraph(text: "一二三四五")
            p.style.list = .numbered
            p.style.listIndentLeft = 24
            p.style.listFirstLine = -24
            p.style.alignment = alignment
            let doc = RichDocument(paragraphs: [p])
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 400
            l.ensureLaidOut(doc)
            return (l.geometry(0).textLeft, l.geometry(0).painter.width, l.theme.pixelsPerPoint)
        }
        let left = geometry(.left), centred = geometry(.center), right = geometry(.right)
        XCTAssertEqual((left.left - centred.left) / left.ppp, 24, accuracy: 0.01, "from the hang's edge")
        XCTAssertEqual((centred.width - left.width) / left.ppp, 24, accuracy: 0.01, "and the hang's width more")
        XCTAssertEqual(right.left, centred.left, accuracy: 0.01)
    }

    func testADigitOffTheGridByItsParagraphTakesHalfTheGrid() throws {
        // zh-8d6f702e p23: "24小时…150毫米", `w:snapToGrid` 0 on a grid
        // of -0.21 with balanceSingleByteDoubleByteWidth, sets each digit
        // 7.90 in Word's print — Times's 8 less half the grid; ours 8.00.
        func digits(grid: Bool) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let rPr = "<w:rPr><w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" w:eastAsia=\"SimSun\"/><w:sz w:val=\"32\"/></w:rPr>"
            func para(_ text: String) -> String {
                "<w:p><w:pPr><w:snapToGrid w:val=\"0\"/></w:pPr><w:r>\(rPr)<w:t>\(text)</w:t></w:r></w:p>"
            }
            let docGrid = grid ? "<w:docGrid w:type=\"linesAndChars\" w:linePitch=\"312\" w:charSpace=\"-860\"/>" : ""
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: para("1111111111字") + para("字")
                + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>\(docGrid)</w:sectPr>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let si = try XCTUnwrap(entries.firstIndex { $0.name == "word/settings.xml" })
            var settings = String(decoding: entries[si].data, as: UTF8.self)
            if let compat = settings.range(of: "<w:compat>") {
                settings.replaceSubrange(compat, with: "<w:compat><w:balanceSingleByteDoubleByteWidth/>")
            } else {
                let close = try XCTUnwrap(settings.range(of: "</w:settings>"))
                settings.replaceSubrange(close, with: "<w:compat><w:balanceSingleByteDoubleByteWidth/></w:compat></w:settings>")
            }
            entries[si] = ZipEntry(name: "word/settings.xml", data: Data(settings.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            XCTAssertTrue(opened.document.balancesSpaceWidth)
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: opened.document.paragraphs.count)
            l.width = 800
            l.ensureLaidOut(opened.document)
            let both = try XCTUnwrap(l.geometry(0).painter.computeLineMetrics().first).width
            let alone = try XCTUnwrap(l.geometry(1).painter.computeLineMetrics().first).width
            return (both - alone) / l.theme.pixelsPerPoint
        }
        XCTAssertEqual(try digits(grid: true) - (try digits(grid: false)), 10 * -0.21 / 2, accuracy: 0.05, "half the grid's -0.21 each")
    }

    func testTurnedTextMergedPastAPagesFootIsSetInItsPartOnThePage() throws {
        // zh-b4d36718 p14: "基本公共服务事项", turned and centred, merged
        // over 35 rows of which 26 are on the page — Word centres it in
        // those 26; ours centred it over all 35, 80pt low, and
        // "公共文化类" ran off the page's foot.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        var rows = ""
        for r in 0 ..< 60 {
            let merge = r == 0 ? "<w:vMerge w:val=\"restart\"/>" : "<w:vMerge/>"
            let text = r == 0 ? "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:t>TURNED</w:t></w:r></w:p>" : "<w:p/>"
            rows += "<w:tr><w:tc><w:tcPr><w:tcW w:w=\"1000\" w:type=\"dxa\"/>\(merge)<w:textDirection w:val=\"btLr\"/><w:vAlign w:val=\"center\"/></w:tcPr>\(text)</w:tc>"
                + "<w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>row \(r)</w:t></w:r></w:p></w:tc></w:tr>"
        }
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:tbl><w:tblPr><w:tblW w:w=\"5000\" w:type=\"dxa\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"1000\"/><w:gridCol w:w=\"4000\"/></w:tblGrid>\(rows)</w:tbl><w:p/>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let opened = try DocxFormat.read(try Zip.write(entries))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        XCTAssertGreaterThan(l.pageCount, 1, "the rows go on over the page")
        let turned = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "TURNED" })
        let top = try XCTUnwrap(l.pieces[0].first { $0.paragraph == turned }).flowTop
        // The page's foot in the flow: the last of the rows set on page 1.
        let foot = try XCTUnwrap(l.pieces[0].filter { $0.paragraph != turned && doc.paragraphs[$0.paragraph].text.hasPrefix("row") }
            .map(\.flowBottom).max())
        let canvas = TurnedTextCanvas()
        l.paint(canvas, visible: l.pageRect(0), document: doc, selection: nil, caret: nil)
        // Reading up, the text is turned about its part's foot — the
        // translate before the turn, in the flow's own terms — and centred
        // along it; turned about the merge's foot, it stood off the page.
        let turn = try XCTUnwrap(canvas.turns.first)
        XCTAssertGreaterThan(turn, top)
        XCTAssertLessThanOrEqual(turn, foot + 1, "turned about the part's foot, not the merge's")
    }

    func testARowPartedAtTheFootKeepsRoomForItsCellsBottomMargin() throws {
        // zh-12f87285 p6: a cell stating 1.2pt bottom margins (tcMar 24)
        // keeps three 31.3pt lines on the page in Word's print, the fourth
        // ending 0.9 clear of the foot going over — the part is closed
        // with its margin under it. Ours kept the fourth, and every page
        // after ran a line early.
        // Here: 697.9pt of page, a 17pt line, then a cell of 20pt lines —
        // the 34th would end 0.9pt over the foot.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
        func line(_ text: String, _ twips: Int) -> String {
            "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(twips)\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
        }
        let cell = (0 ..< 40).map { line("cell \($0)", 400) }.joined()
        xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: line("lead", 340)
            + "<w:tbl><w:tblPr><w:tblW w:w=\"5000\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr>"
            + "<w:tblGrid><w:gridCol w:w=\"5000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"5000\" w:type=\"dxa\"/>"
            + "<w:tcMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"24\" w:type=\"dxa\"/></w:tcMar></w:tcPr>\(cell)</w:tc></w:tr></w:tbl>"
            + "<w:p/><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let opened = try DocxFormat.read(try Zip.write(entries))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        XCTAssertGreaterThan(l.pageCount, 1, "the row parts over the page")
        let kept = Set(l.pieces[0].map(\.paragraph)).filter { doc.paragraphs[$0].text.hasPrefix("cell") }.count
        XCTAssertEqual(kept, 33, "the 34th line goes over: under it, no room for the cell's 1.2pt margin")
    }

    func testARowPartedAtTheFootIsClosedWithTheTablesBottomLine() throws {
        // Lab `ef2b` (Word 16 Mac, mode 14): a last row of four 17pt lines
        // over a 2.25pt bottom line, 15 to 25pt left under its third. Word
        // parts it after the third up to 19 and keeps all four from 20:
        // the fourth must fit with the heavy line under it. Ours, leaving
        // the top line's 0.5 under the part, took the fourth for one that
        // fits, had nothing left to send over, and took the row over whole.
        func kept(_ room: Int) throws -> (pages: Int, kept: Int) {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            func line(_ text: String, _ twips: Int) -> String {
                "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(twips)\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
            }
            func edge(_ side: String, _ sz: Int) -> String { "<w:\(side) w:val=\"single\" w:sz=\"\(sz)\" w:space=\"0\" w:color=\"000000\"/>" }
            let cell = (0 ..< 4).map { line("cell \($0)", 340) }.joined()
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: line("filler", (663 - room) * 20)
                + "<w:tbl><w:tblPr><w:tblW w:w=\"5000\" w:type=\"dxa\"/><w:tblBorders>" + edge("top", 4) + edge("left", 4) + edge("bottom", 18)
                + edge("right", 4) + edge("insideH", 4) + edge("insideV", 4) + "</w:tblBorders>"
                + "<w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"0\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr>"
                + "<w:tblGrid><w:gridCol w:w=\"5000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"5000\" w:type=\"dxa\"/></w:tcPr>\(cell)</w:tc></w:tr></w:tbl>"
                + "<w:p/><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1416\" w:right=\"1134\" w:bottom=\"1134\" w:left=\"1134\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            var doc = opened.document
            doc.compatibilityMode = 14
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            return (l.pageCount, Set(l.pieces[0].map(\.paragraph)).filter { doc.paragraphs[$0].text.hasPrefix("cell") }.count)
        }
        XCTAssertEqual(try kept(15).kept, 3)
        XCTAssertEqual(try kept(18).kept, 3, "parted after the third line, not taken over whole")
        XCTAssertEqual(try kept(19).kept, 3)
        XCTAssertEqual(try kept(20).kept, 4)
    }

    /// The first line's width, in points, of `text` in 12pt 宋体 laid out
    /// `width` points wide, mode 14, compressing punctuation, set left.
    private func firstLineWidth(_ text: String, width: Double, language: String? = nil, hangs: Bool = true,
                                mode: Int = 14, letterSpacing: Double? = nil, compresses: Bool = true,
                                hanging: Double = 0) throws -> Double {
        try firstLine(text, width: width, language: language, hangs: hangs, mode: mode,
                      letterSpacing: letterSpacing, compresses: compresses, hanging: hanging).width
    }

    /// The first line's width and the characters it holds, its paragraph
    /// of 12pt 宋体 laid out alone at `width` points.
    private func firstLine(_ text: String, width: Double, language: String? = nil, hangs: Bool = true,
                           mode: Int = 14, letterSpacing: Double? = nil, compresses: Bool = true,
                           hanging: Double = 0, justified: Bool = false,
                           documentLanguage: String? = nil, characterGrid: Double? = nil,
                           runXML: String = "", kerns: Bool = false) throws -> (width: Double, length: Int) {
        // (The fitter measures each character as the engine shapes it,
        // which wants ICU's data in the bridge: without it every one is
        // zero wide and nothing is ever over.)
        guard TestText.icuLoaded else { throw XCTSkip("no icudtl.dat (STARLING_ICU)") }
        _ = OfficeFonts.register()
        // (No other file's font table: a document read before this one
        // leaves its names' alternates and entries noted.)
        OfficeFonts.noteAltNames([:])
        OfficeFonts.noteFontEntries([:])
        OfficeFonts.noteEmbedded([])
        OfficeFonts.noteEmbeddedFaces([:])
        var style = CharStyle()
        style.fontFamily = "宋体"
        style.eastAsiaFontFamily = "宋体"
        style.fontSize = 12
        style.letterSpacing = letterSpacing
        if let language { style.keptXML = "<w:lang w:eastAsia=\"\(language)\"/>" }
        if !runXML.isEmpty { style.keptXML = (style.keptXML ?? "") + runXML }
        if kerns { style.kerningFrom = 1 }
        var p = RichParagraph(text: text, runs: [Run(length: text.utf16.count, style: style)])
        // (Set left, as every paragraph is fitted before mode 15, so the
        // line's width is what it holds.)
        p.style.alignment = justified ? .justify : .left
        if !hangs { p.style.eastAsian["w:overflowPunct"] = "0" }
        p.style.indentLeft = hanging
        p.style.firstLineIndent = -hanging
        var doc = RichDocument(paragraphs: [p])
        doc.compatibilityMode = mode
        doc.characterSpacingControl = compresses ? "compressPunctuation" : "doNotCompress"
        doc.usesEastAsianLayout = true
        if let characterGrid { doc.characterGridSpace = characterGrid }
        if let documentLanguage { doc.defaultLangXML = "<w:lang w:eastAsia=\"\(documentLanguage)\"/>" }
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: 1)
        l.width = width * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let painter = l.geometry(0).painter
        return ((painter.computeLineMetrics().first?.width ?? 0) / theme.pixelsPerPoint,
                painter.getLineBoundary(TextPosition(offset: 0)).end)
    }

    func testAFullWidthPercentMayOpenATraditionalChineseLine() throws {
        // zh-499adba6's "…占比為38.54" ends page 25's first line in Word's
        // print and "％，女性理事…" opens the next: Word's Traditional
        // Chinese lists do not keep "％" from a line's start, as its
        // Simplified one does. The engine kept "38.54％" together.
        let head = String(repeating: "一", count: 20) + "38.54"
        let text = head + "％" + String(repeating: "二", count: 10)
        // (A line as wide as the number and half the sign; no mark hangs.)
        let width = try firstLine(head, width: 1000, language: "zh-TW", hangs: false, compresses: false, documentLanguage: "zh-TW").width + 6
        let traditional = try firstLine(text, width: width, language: "zh-TW", hangs: false, compresses: false, documentLanguage: "zh-TW")
        XCTAssertEqual(traditional.width, width - 6, accuracy: 0.5, "parted before the sign, the number on the line")
        let simplified = try firstLine(text, width: width, language: "zh-CN", hangs: false, compresses: false, documentLanguage: "zh-CN")
        XCTAssertEqual(simplified.length, 20, "the number goes over with its sign")
    }

    /// Whether the fitter can measure here: ICU's data must reach the bridge
    /// before any paragraph is laid out in the process, or every character
    /// measures zero wide and nothing is ever over. `TestText` loads it
    /// before the first test of the suite (and of `DocxTests`); this says so
    /// if a run ever lays text out ahead of it.
    private func requireFitterWidths() throws {
        let twelve = String(repeating: "一", count: 12)
        guard try firstLineWidth(twelve + "，" + twelve + "二三", width: 307, hangs: false) > 302 else {
            throw XCTSkip("the fitter measured nothing: ICU's data came after a paragraph was laid out")
        }
    }

    func testAMarkBeforeATabGivesNothingToWhatFollowsIt() throws {
        try requireFitterWidths()
        // zh-499adba6 p17: "（六）<tab>推動…政策，…負擔制" leaves "度，" 7.1pt over
        // for the next line in Word's print: the comma after the tab can
        // give 6, and the label's "）" before it nothing — the tab takes
        // the text to the hanging indent however narrow the label is set.
        // (Its line is a cell's, where the last comma gives nothing; here,
        // with no hang, it gives 6 too, and "度，" is 13 over.)
        let ten = String(repeating: "一", count: 10), twelve = String(repeating: "二", count: 12)
        let text = "（六）\t" + ten + "，" + twelve + "度，擴大"
        XCTAssertLessThan(try firstLineWidth(text, width: 359, hangs: false, hanging: 48), 355, "\"度，\" goes down: two commas cannot give 13")
        // (Where all three marks follow the tab, they give it: 18 of room.)
        XCTAssertGreaterThan(try firstLineWidth("一二三\t（六）" + String(repeating: "一", count: 7) + "，" + twelve + "度，擴大", width: 359, hangs: false), 358)
        // Not a tab to an ordinary stop, which the label's marks may move
        // a stop back: zh-6a4fc013's Thai answers "ตอบ :<tab><tab>…" ran a
        // page long on the Mac with their space held.
        XCTAssertGreaterThan(try firstLineWidth(text, width: 359, hangs: false), 358, "with no hanging indent, \"）\" gives too")
    }

    func testAutomaticSpacesGiveAsMarksDoFromMode15() throws {
        try requireFitterWidths()
        // Lab `as` (Mac, Word 16, zh-5bfac68f's package: mode 15, justified,
        // compressing nothing): forty ideographs and an "i" between them,
        // two automatic spaces of 3.0, take the next 2.0pt over and not 2.5
        // — as a share of their halves no more than the line would stretch
        // by. Half of each, 3.0, took zh-5bfac68f's "並" 2.83 over.
        let text = String(repeating: "甲", count: 20) + "i" + String(repeating: "甲", count: 19) + "乙丙丁"
        let through = try firstLineWidth(text, width: 1000, mode: 15, compresses: false) - 24   // to "乙"'s end
        let taken = text.utf16.count - 2, left = taken - 1
        XCTAssertEqual(try firstLine(text, width: through - 2.0, mode: 15, compresses: false, justified: true).length, taken)
        XCTAssertEqual(try firstLine(text, width: through - 2.5, mode: 15, compresses: false, justified: true).length, left,
                       "two spaces giving 1.25 apiece would ask more of them than stretching asks of the line")
        // (Four — "a" too — take it 2.5 over, and not 3.0.)
        let four = String(repeating: "甲", count: 10) + "i" + String(repeating: "甲", count: 15) + "a" + String(repeating: "甲", count: 14) + "乙丙丁"
        let fourThrough = try firstLineWidth(four, width: 1000, mode: 15, compresses: false) - 24
        XCTAssertEqual(try firstLine(four, width: fourThrough - 2.5, mode: 15, compresses: false, justified: true).length, four.utf16.count - 2)
        XCTAssertEqual(try firstLine(four, width: fourThrough - 3.0, mode: 15, compresses: false, justified: true).length, four.utf16.count - 3)
        // (A word space among them gives a quarter and weighs whole:
        // zh-5bfac68f's cell "…（i-Taiwan Window）服務，提供年輕人返臺"
        // leaves a "投" 2.91 over that the spaces' room alone took.)
        let spaced = String(repeating: "甲", count: 20) + "i j" + String(repeating: "甲", count: 18) + "乙丙丁"
        let spacedThrough = try firstLineWidth(spaced, width: 1000, mode: 15, compresses: false) - 24
        XCTAssertEqual(try firstLine(spaced, width: spacedThrough - 2.0, mode: 15, compresses: false, justified: true).length, spaced.utf16.count - 2)
        XCTAssertEqual(try firstLine(spaced, width: spacedThrough - 2.5, mode: 15, compresses: false, justified: true).length, spaced.utf16.count - 3)
    }

    func testAKeptFinalMarkTakesNothingFromTheOthersRoom() throws {
        try requireFitterWidths()
        // Lab `s2` (Windows, Word for Windows, zh-045c5a75's package: mode
        // 14, zh-TW, compressing punctuation, set left): the sentence is one
        // line from 371pt at 13pt, "扶" 6 past the margin and "、（）" giving
        // 19 of their 19.5 — the final "。" giving nothing. Ours took its
        // half off the others' room as well and wanted 377.
        let text = "低收入戶得向戶籍所在地直轄市、縣（市）主管機關申請生活扶助。"
        XCTAssertEqual(try firstLine(text, width: 343, language: "zh-TW", documentLanguage: "zh-TW").length, text.utf16.count,
                       "\"、（）\" give the 17 it needs; \"扶\" is 5 over, inside half \"活\"")
        // (Not past what they have: 18 of room.)
        XCTAssertLessThan(try firstLine(text, width: 341, language: "zh-TW", documentLanguage: "zh-TW").length, text.utf16.count)
    }

    func testAutofitsNarrowestPieceLeavesOutTheAutomaticSpaceAfterIt() throws {
        try requireFitterWidths()
        // zh-e329b438's label cells "接聽速度30分" (mode 15, 14pt) set their
        // column at 28.08 in Word's print: "30" bare between the margins,
        // where ours took it and the automatic space before "分" and
        // widened the column to 31.6. At 12pt: "30" is 12, its space 3.
        var style = CharStyle()
        style.fontFamily = "宋体"
        style.eastAsiaFontFamily = "宋体"
        style.fontSize = 12
        let label = "接聽速度30分", body = String(repeating: "內", count: 20)
        var a = RichParagraph(text: label, runs: [Run(length: label.utf16.count, style: style)])
        var b = RichParagraph(text: body, runs: [Run(length: body.utf16.count, style: style)])
        a.cell = CellRef(table: "T", row: 0, column: 0)
        b.cell = CellRef(table: "T", row: 0, column: 1)
        var doc = RichDocument(paragraphs: [a, b, RichParagraph(text: "")])
        doc.tableColumns["T"] = [20, 400]
        doc.tableStyles["T"] = TableStyle()
        doc.compatibilityMode = 15
        doc.usesEastAsianLayout = true
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        l.width = 500 * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let first = try XCTUnwrap(l.columnWidths(of: "T")?.first)
        XCTAssertLessThan(first, 12 + 10.8 + 1, "the column holds \"30\" bare, its margins beside it")
        XCTAssertGreaterThan(first, 12 + 10.8 - 1)
        // (… and "度", its space given up at the line's end, a line alone:
        // the engine set the two on one line over the margin.)
        XCTAssertEqual(l.geometry(0).painter.computeLineMetrics().count, 6)
    }

    func testARunOffTheGridWeighsItsCharactersAtTheirOwnEms() throws {
        try requireFitterWidths()
        // zh-c15af02e (mode 15, a grid adding 1pt) sets its runs off the grid,
        // 16pt ideographs 16 apart, and takes "…已核發" 13.58pt over with four
        // marks giving; weighed at the grid's 17 a character the share test
        // left it. Here 23 characters and four marks at 12pt, the grid adding
        // 4: the next is taken 10.0 over weighed at 12 (to 10.24), not at 16
        // (to 9.76).
        let text = "甲甲甲：甲甲甲甲、甲甲（甲甲）甲甲甲甲甲甲甲甲" + "乙丙丁"
        let off = "<w:snapToGrid w:val=\"0\"/>"
        let through = try firstLine(text, width: 1000, mode: 15, characterGrid: 4, runXML: off).width - 24   // to "乙"'s end
        XCTAssertEqual(try firstLine(text, width: through - 10.0, mode: 15, justified: true, characterGrid: 4, runXML: off).length,
                       text.utf16.count - 2, "the four marks give 10.0, weighed against 23 characters of 12")
        XCTAssertEqual(try firstLine(text, width: through - 10.5, mode: 15, justified: true, characterGrid: 4, runXML: off).length,
                       text.utf16.count - 3)
    }

    func testAMarkClosedUpToTheLastHangsHalfAnEmOnALineWithWordSpaces() throws {
        try requireFitterWidths()
        // Labs `u5`/`u6` (Mac, Word 16, zh-505b9619's package: mode 15,
        // 14pt, a line with word spaces and three marks to give): "…3日）。"
        // is taken with the need over a whole em's hang up to 14.0 and not
        // from 14.25 — "）。" gives half an em for hanging, not the whole.
        // Here at 12pt the marks "（", "，", "（" give a third each.
        let text = "甲（甲甲）， 甲甲甲甲甲甲甲甲甲甲（甲甲甲甲日）。乙丙"
        let through = try firstLine(text, width: 1000, mode: 15, kerns: true).width - 24   // to "。"'s end
        func length(_ need: Double) throws -> Int {
            try firstLine(text, width: through - 12 - need, mode: 15, justified: true, kerns: true).length
        }
        let all = try length(0)   // the line through "。"
        XCTAssertEqual(try length(11.0), all)
        XCTAssertLessThan(try length(12.75), all, "with half an em to hang, 12.75 asks the marks more than the line would stretch")
        XCTAssertGreaterThan(all, text.utf16.count - 3)
    }

    func testAPercentSignStartsALineWhereTheDocumentsListLeavesItOut() throws {
        try requireFitterWidths()
        // zh-505b9619 lists Taiwan's characters that may not start a line,
        // "%" not among them, and Word's print ends a line "…契約價金總額＿"
        // and starts the next "%(由機關…"; ours took "＿%" down together.
        let text = String(repeating: "甲", count: 10) + "＿%乙"
        func first(_ list: String?) throws -> Int {
            var style = CharStyle()
            style.fontFamily = "宋体"
            style.eastAsiaFontFamily = "宋体"
            style.fontSize = 12
            var p = RichParagraph(text: text, runs: [Run(length: text.utf16.count, style: style)])
            p.style.alignment = .left
            var doc = RichDocument(paragraphs: [p])
            doc.usesEastAsianLayout = true
            if let list { doc.keptSettings["w:noLineBreaksBefore"] = "<w:noLineBreaksBefore w:lang=\"zh-TW\" w:val=\"\(list)\"/>" }
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 11 * 12 * theme.pixelsPerPoint   // "甲"×10 and "＿", not "%"
            l.ensureLaidOut(doc)
            return l.geometry(0).painter.getLineBoundary(TextPosition(offset: 0)).end
        }
        // (The line's end counts the break put in before "%" too.)
        XCTAssertEqual(try first("!),.:;?]}、。）"), 12, "\"＿\" ends the line, \"%\" opens the next")
        // (Without a list of the document's own, the defaults keep it from a line's start.)
        XCTAssertEqual(try first(nil), 10)
    }

    func testAFullWidthPercentSignStartsALineUnderTaiwansDefaultList() throws {
        try requireFitterWidths()
        // zh-499adba6 is zh-TW with no list of its own — Taiwan's, which
        // has no "%" or "％" — and its p25 paragraph "在社會組織中，根據內政部
        // …" ends "…權力分配。" in Word's print; ours, a number's sign held to
        // it, ran its lines a character short and set "分配。" alone.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-499adba6") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.contains("總幹事占比為38.54") })
        let painter = l.geometry(i).painter
        let shown = painter.plainText
        let at = try XCTUnwrap(shown.range(of: "權力分配"))
        let line = painter.getLineBoundary(TextPosition(offset: shown.utf16.distance(from: shown.utf16.startIndex, to: at.lowerBound.samePosition(in: shown.utf16)!)))
        let text = String(decoding: Array(shown.utf16)[line.start ..< line.end], as: UTF16.self)
        // (Its tenth line, as Word's: the page and every one after it then
        // a line behind no more.)
        XCTAssertTrue(text.contains("權力分配。"), text)
    }

    func testANotesNumberHasNoAutomaticSpaceBesideIt() throws {
        try requireFitterWidths()
        // zh-499adba6's notes' numbers — "（SDGs）⁷作為", "權能⁸，" — stand with
        // no automatic space either side in Word's print, where a digit
        // between ideographs has one each side.
        func width(note: Bool) throws -> Double {
            var style = CharStyle()
            style.fontFamily = "宋体"
            style.eastAsiaFontFamily = "宋体"
            style.fontSize = 12
            var number = style
            number.script = .superscript
            if note { number.note = NoteReference(kind: .footnote, id: 1) }
            let p = RichParagraph(text: "甲7乙", runs: [Run(length: 1, style: style), Run(length: 1, style: number), Run(length: 1, style: style)])
            var doc = RichDocument(paragraphs: [p])
            doc.usesEastAsianLayout = true
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 300 * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            return (l.geometry(0).painter.computeLineMetrics().first?.width ?? 0) / theme.pixelsPerPoint
        }
        XCTAssertLessThan(try width(note: true), try width(note: false) - 4, "a raised digit that is no note's number keeps its two")
    }

    func testAnUnhintedTimesSignIsALetterOfTheNumberAfterIt() throws {
        try requireFitterWidths()
        // zh-8628cfbe's cell "13.2稅前盈餘/用人費用×100%" — its runs not
        // hinted East Asian — ends a line "…用人費用" and opens the next
        // "×100%" in Word's print; ours kept "×" on the first line, as
        // zh-b56eeded's hinted "…總數）×" is.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-8628cfbe") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.contains("稅前盈餘/用人費用×100%") })
        let painter = l.geometry(i).painter
        let shown = painter.plainText
        let at = try XCTUnwrap(shown.range(of: "用人費用"))
        let line = painter.getLineBoundary(TextPosition(offset: shown.utf16.distance(from: shown.utf16.startIndex, to: at.lowerBound.samePosition(in: shown.utf16)!)))
        let text = String(decoding: Array(shown.utf16)[line.start ..< line.end], as: UTF16.self)
        XCTAssertFalse(text.contains("×"), text)
    }

    func testACellsSpacesBothSidesOfTheWordBeforeWhatIsTakenGive() throws {
        try requireFitterWidths()
        // zh-db07d44e's cell "達成預算目標者得基準分80分，每增（減）1%…" (mode 15,
        // zh-TW, 12pt) ends its first line "…分80分，" in Word's print, the
        // automatic spaces either side of "80" set at 2.2 of their 3.0 and
        // "，" at its half; ours let only the one after it give, and the cell
        // and every page after it ran a line long.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-db07d44e") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let cells = doc.paragraphs.indices.filter { doc.paragraphs[$0].text.hasPrefix("達成預算目標者得基準分80分，每增") }
        XCTAssertFalse(cells.isEmpty)
        for i in cells {
            let painter = l.geometry(i).painter
            let shown = painter.plainText
            let line = painter.getLineBoundary(TextPosition(offset: 0))
            let text = String(decoding: Array(shown.utf16)[line.start ..< line.end], as: UTF16.self)
            XCTAssertTrue(text.contains("80分，"), "\(i): \(text)")
        }
    }

    func testACellLinesSpacesAllGiveWhereTheOneBeforeWhatIsTakenDoes() throws {
        try requireFitterWidths()
        // zh-d746674a's cell "每年2次(第2、4季)" (mode 15, zh-HK, 14pt, justified)
        // is one line in Word's print, 122.15 of 122.3: "、" at its half and
        // all four automatic spaces at 2.8 of 3.5. Ours let only the space
        // before "季" give, and "季)" went to a line of its own.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-d746674a") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let cells = doc.paragraphs.indices.filter { ["每年2次(第2、4季)", "每年2次(第1、3季)"].contains(doc.paragraphs[$0].text) }
        XCTAssertEqual(cells.count, 2)
        for i in cells {
            XCTAssertEqual(l.geometry(i).painter.computeLineMetrics().count, 1, doc.paragraphs[i].text)
        }
    }

    func testAParagraphsClosingBracketDoesNotHangFrom2013sLayoutWhereMarksCompress() throws {
        try requireFitterWidths()
        // zh-20c1d74a's "二、專案單位服務規劃（…督導考核及管理等）" (mode 15,
        // compressPunctuation, justified) ends its first line "…管理" in
        // Word's print and sends "等）" down. Ours hung the "）" a whole em
        // and took "等" 9.55pt over with the line's marks; not hung, the
        // "）" gives its half with them and the share test refuses it.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-20c1d74a") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("二、專案單位服務規劃（包括徵選方式") })
        let painter = l.geometry(i).painter
        let shown = painter.plainText
        let line = painter.getLineBoundary(TextPosition(offset: 0))
        let text = String(decoding: Array(shown.utf16)[line.start ..< line.end], as: UTF16.self)
            .filter { $0 != "\u{200B}" && $0 != "\u{2060}" }
        XCTAssertTrue(text.hasSuffix("管理"), text)
    }

    func testAPageAnchoredTableThatGoesOverStandsAtItsOffsetOnTheNextPage() throws {
        // zh-0513f641's p9 form (vertAnchor page, tblpY 1322 against a
        // 1440 top margin) follows the cover that fills p8. Word's print
        // has its top line at 66.0, 6pt up into the margin; ours stood it
        // at the margin, its first row having gone over for want of room.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-0513f641") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let title = try XCTUnwrap(doc.paragraphs.indices.first { i in
            doc.paragraphs[i].text == "原住民族委員會" && doc.paragraphs[i].cell != nil
                && (i + 1 < doc.paragraphs.count && doc.paragraphs[i + 1].text.contains("綜合資料表"))
        })
        let piece = try XCTUnwrap(l.pieces.flatMap { $0 }.first { $0.paragraph == title })
        XCTAssertLessThan(piece.pageY / theme.pixelsPerPoint, -3, "the table's first row stands up in the top margin, at its offset")
    }

    func testACellsLatinWordThatStartsPastTheMarginIsNotTaken() throws {
        try requireFitterWidths()
        // zh-51af781b's mode-14 scoring cell "70%及以上客房卫生间有浴缸，得1分；
        // 所有卫生间淋浴…干湿区分离，得1分；…" ends its first line "…分离，得" in
        // Word's print. Ours took the "1" over the margin, the automatic
        // space before it already past it, the line's marks and spaces giving.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-51af781b") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.contains("所有卫生间淋浴、恭桶、面盆干湿区分离") })
        let painter = l.geometry(i).painter
        let shown = painter.plainText
        let line = painter.getLineBoundary(TextPosition(offset: 0))
        let text = String(decoding: Array(shown.utf16)[line.start ..< line.end], as: UTF16.self)
            .filter { $0 != "\u{200B}" && $0 != "\u{2060}" }
        XCTAssertTrue(text.filter { !$0.isWhitespace }.hasSuffix("分离，得"), text)
    }

    func testASectionBreaksSpaceAfterIsTakenOffTheNextParagraphsSpaceBefore() throws {
        // zh-8f9b19f4 p13: an empty paragraph that only ends a section
        // takes no room, but its space after (Normal's 8pt) is taken off
        // the next paragraph's 4.3pt before — "附件5:", the first of the
        // row its two-column section is set as, stands right under the
        // line above it in Word for Windows' print (lab `t165`); ours
        // kept the 4.3.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-8f9b19f4") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("附件5") })
        XCTAssertEqual(doc.paragraphs[i].style.spaceBefore, 4.3, accuracy: 0.01, "its own 4.3pt before")
        let g = l.geometry(i)
        XCTAssertEqual((g.textTop - g.top) / theme.pixelsPerPoint, 0, accuracy: 0.05, "the break's 8pt after takes it")
    }

    func testAJustifiedLineStretchesNothingBeforeItsLastTab() throws {
        // zh-6a4fc013's "คำถามที่  2 ：<tab>การเปิดนำเข้า…" (justified, a default
        // stop) leaves the spaces before the tab as they are in Word's
        // print, the text after it taking the line's stretch; ours
        // stretched them and set "2 ：" on. (A line the tab ends is
        // stretched as any.)
        guard TestText.icuLoaded else { throw XCTSkip("no icudtl.dat (STARLING_ICU)") }
        func x(justified: Bool) throws -> Double {
            var p = RichParagraph(text: "Question  2 :\tthe answer runs on over more words than one line holds at this width")
            p.style.alignment = justified ? .justify : .left
            let doc = RichDocument(paragraphs: [p])
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 300 * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            let painter = l.geometry(0).painter
            XCTAssertGreaterThan(painter.computeLineMetrics().count, 1)
            let at = try XCTUnwrap(Array(painter.plainText.utf16).firstIndex(of: 0x32))
            let box = try XCTUnwrap(painter.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 1)).first)
            return box.left / theme.pixelsPerPoint
        }
        XCTAssertEqual(try x(justified: true), try x(justified: false), accuracy: 0.05, "\"2\" where it stands unjustified")
    }

    func testANotoJoinerAfterADigitKeepsTheBreakBeforeItsIdeograph() throws {
        try requireFitterWidths()
        // zh-72da925e's "…經行政院於79年9月" ends a line "於79" in Word's
        // print, "年" — U+F98E, a compatibility ideograph set in Noto —
        // opening the next. The word joiner that gives its line Noto's
        // height held "79年" whole, and ours ended the line "於".
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-72da925e") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.contains("嗣後臺北市政府") })
        let shown = Array(l.geometry(i).painter.plainText.unicodeScalars.map(\.value))
        // "79", then the joiner before "年" U+F98E — with a break before it.
        let at = try XCTUnwrap((0 ..< shown.count - 3).first { shown[$0] == 0x37 && shown[$0 + 1] == 0x39 && shown[$0 + 2] != 0x39 && shown[$0 ..< min(shown.count, $0 + 5)].contains(0xF98E) })
        let after = Array(shown[(at + 2) ..< min(shown.count, at + 5)])
        guard after.contains(0x2060) else { throw XCTSkip("no Noto joiner under this platform's faces") }
        XCTAssertEqual(after.first, 0x200B, after.map { String($0, radix: 16) }.joined(separator: " "))
    }

    func testASpacedFullWidthQuoteIsOverTheMarginByHalfItsSpacingToo() throws {
        try requireFitterWidths()
        // zh-e5eb092a's runs say `w:spacing` 8 (+0.4pt): Word's print leaves
        // "“市" for the next line after "…统一修改为", the quote 6.8 past the
        // margin with half its spacing, over half "为"'s 6.4; at its em
        // alone, 6.4, ours took it.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-e5eb092a") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.contains("统一修改为“市交通") })
        let painter = l.geometry(i).painter
        let shown = painter.plainText
        let at = try XCTUnwrap(shown.range(of: "统一修改为"))
        let line = painter.getLineBoundary(TextPosition(offset: shown.utf16.distance(from: shown.utf16.startIndex, to: at.lowerBound.samePosition(in: shown.utf16)!)))
        let text = String(decoding: Array(shown.utf16)[line.start ..< line.end], as: UTF16.self)
        let clean = text.filter { $0 != "\u{200B}" && $0 != "\u{2060}" }
        XCTAssertFalse(clean.contains("修改为“"), text)
    }

    func testALinesOpeningSpacesDoNotMakeItASpacedLine() throws {
        try requireFitterWidths()
        // zh-753cd6a8's cell paragraph "  前一年度建筑业产值（…）排名，第1名得100分…"
        // (mode 14) ends its first line "…第" in Word's print, the "1" 9.1
        // over left for the next; its two leading spaces made it a line with
        // spaces in it to ours, which then took the digit as a spaced line's word.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-753cd6a8") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.contains("排名，第1名得100分") })
        let painter = l.geometry(i).painter
        let shown = painter.plainText
        let line = painter.getLineBoundary(TextPosition(offset: 0))
        let text = String(decoding: Array(shown.utf16)[line.start ..< line.end], as: UTF16.self).filter { $0 != "\u{200B}" && $0 != "\u{2060}" }
        guard text.hasSuffix("第") || text.hasSuffix("第1") else { throw XCTSkip("the line ends elsewhere under this platform's faces: \(text)") }
        XCTAssertTrue(text.hasSuffix("第"), text)
    }

    func testASpacedIdeographIsOverTheMarginByItsEmAndHalfItsSpacing() throws {
        // zh-01bbcd4d (mode 12, 16pt spaced to 17) takes "理。" with "理"
        // starting 8.2pt short of the margin: over by its em and half its
        // spacing, 8.3, inside half of "办" as spaced, 8.5. As spaced, 8.8,
        // it was not. (zh-749cb15a's "期", 7.55 so against 7.3, is left.)
        try requireFitterWidths()
        // (12pt set 13 apart, as the reader spaces a `w:spacing` of 10.)
        XCTAssertEqual(try firstLineWidth("一一", width: 300, mode: 12, letterSpacing: 1), 26, accuracy: 0.05)
        // "一，二，" and 18 ideographs, 13 apart: "办" at 286, "理" at 299.
        let text = "一，二，" + String(repeating: "三", count: 18) + "办理。四五"
        XCTAssertGreaterThan(try firstLineWidth(text, width: 305.2, mode: 12, letterSpacing: 1), 303,
                             "\"理\" 6.3 over by its em and half its spacing, within half of \"办\"'s 13")
        XCTAssertLessThan(try firstLineWidth(text, width: 304.6, mode: 12, letterSpacing: 1), 300,
                          "6.9 over so is past it")
    }

    func testACellLineFromMode15TakesTheAutomaticSpaceBeforeWhatItTakes() throws {
        // zh-db07d44e (mode 15, zh-TW 12pt): a cell line "…加(減)1分。" ends at
        // the cell's edge in Word's print with "，" and "。" at their halves
        // and the automatic space between "1" and "分" 0.53 narrower — 12.53
        // of need, where the marks give 12. Here 12.75: taken with the space
        // before "分" giving, not without it; nor where no space is before it.
        try requireFitterWidths()
        func lines(_ text: String, cellTwips: Int) throws -> Int {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
            xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
                "<w:tbl><w:tblPr><w:tblW w:w=\"\(cellTwips)\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/></w:tblPr>"
                + "<w:tblGrid><w:gridCol w:w=\"\(cellTwips)\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"\(cellTwips)\" w:type=\"dxa\"/></w:tcPr>"
                + "<w:p><w:pPr><w:jc w:val=\"both\"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" w:eastAsia=\"宋体\"/>"
                + "<w:sz w:val=\"24\"/><w:lang w:eastAsia=\"zh-TW\"/></w:rPr><w:t>\(text)</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let settings = "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:characterSpacingControl w:val=\"compressPunctuation\"/>"
                + "<w:compat><w:useFELayout/><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat></w:settings>"
            entries.removeAll { $0.name == "word/settings.xml" }
            entries.append(ZipEntry(name: "word/settings.xml", data: Data(settings.utf8)))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            l.pageSetup = opened.pageSetup ?? .a4
            l.width = (opened.pageSetup ?? .a4).columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == text })
            return l.geometry(i).painter.computeLineMetrics().count
        }
        // (The cell's margins and borders: 11.1pt in all.)
        func twips(_ textWidth: Double) -> Int { Int(((textWidth + 11.1) * 20).rounded()) }
        let text = "一二三四五，六七八1分。"
        // Its natural width, one line in a wide cell: 11 of 12, "1" and the
        // automatic spaces each side of it, 2.7 apiece.
        XCTAssertEqual(try lines(text, cellTwips: 9000), 1)
        let natural = 9 * 12.0 + 12 + 12 + 6 + 2 * 2.7
        XCTAssertEqual(try lines(text, cellTwips: twips(natural - 12.75)), 1, "the space before \"分\" gives the last 0.75 of its 1.35")
        // (And the space before "1" — the word's other side — gives too:
        // zh-db07d44e's "…分80分，", both its spaces at 2.2 of 3.0.)
        XCTAssertEqual(try lines(text, cellTwips: twips(natural - 13.75)), 1, "both of the word's spaces give: 13.75")
        XCTAssertEqual(try lines(text, cellTwips: twips(natural - 15.25)), 2, "past the marks and both spaces: 15.25")
        XCTAssertEqual(try lines("一二三四五，六七八九分。", cellTwips: twips(9 * 12.0 + 12 + 12 + 12 - 12.75)), 2, "no space before it to give")
    }

    func testANotesRaisedNumberIsNoCharacterOfItsLine() throws {
        // zh-344a8d08's footnote 2 (mode 15, overflowPunct 0, justified):
        // "2 「…規定」之相關規定。" is one line in Word's print, its "「", "」" and
        // "。" squeezed. The space after the raised "2" is no word space (one
        // would leave the corner brackets nothing to give, lab `sq-sp`), and
        // the "「" no opener of the line (which keeps its blank half).
        try requireFitterWidths()
        func lines(_ text: String, raised: Bool, width: Double) -> Int {
            var plain = CharStyle()
            plain.fontFamily = "宋体"
            plain.eastAsiaFontFamily = "宋体"
            plain.fontSize = 12
            plain.keptXML = "<w:lang w:eastAsia=\"zh-TW\"/>"
            var number = plain
            number.script = raised ? .superscript : .normal
            var p = RichParagraph(text: "2 " + text, runs: [Run(length: 1, style: number), Run(length: text.utf16.count + 1, style: plain)])
            p.style.alignment = .justify
            p.style.eastAsian["w:overflowPunct"] = "0"
            var doc = RichDocument(paragraphs: [p])
            doc.compatibilityMode = 15
            doc.characterSpacingControl = "compressPunctuation"
            doc.usesEastAsianLayout = true
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = width * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            return l.geometry(0).painter.computeLineMetrics().count
        }
        let text = "「" + String(repeating: "一", count: 20) + "」" + String(repeating: "二", count: 5) + "定。"
        // (Its natural width: one line on a wide page.)
        let wide = 2000.0
        XCTAssertEqual(lines(text, raised: true, width: wide), 1)
        // 29 characters of 12 and "2 ": the line 10pt short of all of it — the
        // "。"'s half gives 6, the three marks' halves 18.
        let probe = TextPainter(text: TextSpan(text: "2 ", style: TextStyle(fontSize: 12)), textDirection: .ltr)
        probe.layout(minWidth: 0, maxWidth: 1000)
        let natural = 29 * 12 + probe.width / RichTextTheme(fontFamily: OfficeFonts.defaultFamily).pixelsPerPoint
        probe.dispose()
        XCTAssertEqual(lines(text, raised: true, width: natural - 10), 1, "the brackets and the stop give: the number is no character")
        XCTAssertEqual(lines(text, raised: false, width: natural - 10), 2, "a plain \"2\" and its space are a word: the brackets give nothing")
    }

    func testAParagraphsLastMarkHangsOnlyOnceTheMarksCannotGiveTheLine() throws {
        // zh-e0ca7252 p13 (mode 15, compressPunctuation, justified): "…，依第17款
        // 辦理。" is 21.55pt over at 14pt, two commas and the "。" able to give
        // 21 and the automatic spaces round "17" 1.75: Word sends "理。" down,
        // the commas whole. Ours hung the "。" and squeezed the commas. Where
        // the marks can give it all the line is taken squeezed, the "。"
        // inside (zh-505b9619's "…工作天。"); where they cannot, the "。" hangs
        // (zh-021b8feb's "…核定。").
        try requireFitterWidths()
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        func layout(_ text: String, width: Double) -> RichLayout {
            var plain = CharStyle()
            plain.fontFamily = "宋体"
            plain.eastAsiaFontFamily = "宋体"
            plain.fontSize = 12
            plain.keptXML = "<w:lang w:eastAsia=\"zh-TW\"/>"
            var p = RichParagraph(text: text, runs: [Run(length: text.utf16.count, style: plain)])
            p.style.alignment = .justify
            var doc = RichDocument(paragraphs: [p])
            doc.compatibilityMode = 15
            doc.characterSpacingControl = "compressPunctuation"
            doc.usesEastAsianLayout = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = width * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            return l
        }
        func lines(_ text: String, over: Double) -> Int {
            let natural = layout(text, width: 2000).geometry(0).painter.computeLineMetrics()[0].width / theme.pixelsPerPoint
            return layout(text, width: natural - over).geometry(0).painter.computeLineMetrics().count
        }
        // Two commas and the "。" give 6 each at 12pt, the two spaces round "17" 1.5.
        let two = String(repeating: "一", count: 8) + "，" + String(repeating: "二", count: 8) + "，依第17款辦理。"
        XCTAssertEqual(lines(two, over: 15), 1, "the marks give the 15: squeezed, the \"。\" inside")
        XCTAssertEqual(lines(two, over: 18.5), 2, "more than the marks' 18 but not their 21 with the spaces: no hang, so it goes down")
        // One comma and the "。": 12 to give, so 14 over hangs the "。" and squeezes the comma.
        let one = String(repeating: "一", count: 12) + "，" + String(repeating: "二", count: 12) + "核定。"
        XCTAssertEqual(lines(one, over: 14), 1, "past what the marks give: the \"。\" hangs")
    }

    func testAHeadingKeptWithAMultipleSpacedLineLetsThatLineReachPastTheFoot() throws {
        // zh-34a6519a p28: "5.2.3 防台风Ⅱ级应急响应" keeps with a 1.5-spaced
        // paragraph whose first line ends 2.9pt past the foot by its
        // extra, which the line may reach past it by; Word sets both on
        // the page. Ours counted the extra as room the keep needed.
        func laidOut(fillerTwips: Int?) throws -> (RichLayout, RichDocument, Double) {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let filler = fillerTwips.map { "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\($0)\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>filler</w:t></w:r></w:p>" } ?? ""
            let heading = "<w:p><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"400\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>heading</w:t></w:r></w:p>"
            let words = (1 ... 60).map { "word\($0)" }.joined(separator: " ")
            let spaced = "<w:p><w:pPr><w:widowControl w:val=\"0\"/><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"360\" w:lineRule=\"auto\"/></w:pPr><w:r><w:t>\(words)</w:t></w:r></w:p>"
            let section = "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>"
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: filler + heading + spaced + section)
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            return (l, doc, setup.height - setup.marginTop - setup.marginBottom)
        }
        // The spaced paragraph's first line, extra and all, alone.
        let (probe, probed, contentH) = try laidOut(fillerTwips: nil)
        let k = try XCTUnwrap(probed.paragraphs.firstIndex { $0.text.hasPrefix("word1 ") })
        let line = try XCTUnwrap(probe.geometry(k).painter.computeLineMetrics().first).height / probe.theme.pixelsPerPoint
        XCTAssertGreaterThan(probe.geometry(k).painter.computeLineMetrics().count, 2)
        // Room for the heading and that line less a sixth of it: short of
        // the whole line, with its text (two thirds of it) inside.
        let room = 20 + line * 5 / 6
        let (l, doc, _) = try laidOut(fillerTwips: Int(((contentH - room) * 20).rounded()))
        XCTAssertGreaterThan(l.pageCount, 1)
        let heading = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "heading" })
        XCTAssertTrue(l.pieces[0].contains { $0.paragraph == heading }, "the heading stays with the line on page 1")
    }

    func testARowOpeningAPageUnderACellOfNoTopLineTakesTheTablesTopLine() throws {
        // zh-cec9d337's assignments table: a 3pt thinThickSmallGap top over
        // half-point inside lines, every cell stating its own top but some
        // middle ones. Where a row opens a page the table goes on over, Word
        // draws the table's top line over such a cell and sets the row
        // under it (p19, p25, p26: 4pt lower than ours); a row whose cells
        // all state theirs opens under its half-point line (p20-p24).
        func opening(middleTop: Bool) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let top = "<w:top w:val=\"single\" w:sz=\"4\"/>"
            func cell(_ text: String, ownTop: Bool) -> String {
                "<w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/><w:tcBorders>\(ownTop ? top : "")<w:left w:val=\"single\" w:sz=\"4\"/><w:bottom w:val=\"single\" w:sz=\"4\"/><w:right w:val=\"single\" w:sz=\"4\"/></w:tcBorders></w:tcPr>"
                    + "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"400\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p></w:tc>"
            }
            let borders = "<w:tblBorders><w:top w:val=\"thinThickSmallGap\" w:sz=\"24\"/><w:left w:val=\"single\" w:sz=\"4\"/><w:bottom w:val=\"single\" w:sz=\"4\"/><w:right w:val=\"single\" w:sz=\"4\"/><w:insideH w:val=\"single\" w:sz=\"4\"/><w:insideV w:val=\"single\" w:sz=\"4\"/></w:tblBorders>"
            let filler = "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"12000\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>filler</w:t></w:r></w:p>"
            let row = "<w:tr>\(cell("one", ownTop: true))\(cell("two", ownTop: true))\(cell("three", ownTop: true))</w:tr>"
            // The last row cannot part and does not fit page 1's foot: it opens page 2.
            let tall = (1 ... 12).map { "line \($0)" }
            let last = "<w:tr><w:trPr><w:cantSplit/></w:trPr>\(cell("left", ownTop: true))\(cell("middle", ownTop: middleTop))"
                + "<w:tc><w:tcPr><w:tcW w:w=\"3000\" w:type=\"dxa\"/><w:tcBorders>\(top)</w:tcBorders></w:tcPr>"
                + tall.map { "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"400\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\($0)</w:t></w:r></w:p>" }.joined() + "</w:tc></w:tr>"
            let table = "<w:tbl><w:tblPr><w:tblW w:w=\"9000\" w:type=\"dxa\"/>\(borders)<w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr>"
                + "<w:tblGrid><w:gridCol w:w=\"3000\"/><w:gridCol w:w=\"3000\"/><w:gridCol w:w=\"3000\"/></w:tblGrid>\(row)\(row)\(last)</w:tbl><w:p/>"
            let section = "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>"
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: filler + table + section)
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            XCTAssertGreaterThan(l.pageCount, 1)
            let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "left" })
            let piece = try XCTUnwrap(l.pieces[1].first { $0.paragraph == k && $0.part != .rules }, "the last row opens page 2")
            return (piece.pageY + l.geometry(k).textTop - piece.flowTop) / theme.pixelsPerPoint
        }
        let own = try opening(middleTop: true), none = try opening(middleTop: false)
        // (The compound line's 3 and its 1.5 gap, less the half-point line.)
        XCTAssertEqual(none - own, 4, accuracy: 0.1, "under the table's top line")
    }

    func testAShapeWordSetsInSegoeUISymbolGivesItsLineThatFacesAscent() throws {
        // Lab `picln` (Word 16 Mac, zh-e68a2f57's package): a 9pt note over
        // Times New Roman holding "◎" stands 0.48pt lower under the line
        // above than one holding "兼" — Word sets the shape in Segoe UI
        // Symbol, the run's Latin face having none — and "●", which Times
        // has, as "兼". Ours drew them all in YaHei, the line as any, and
        // p7's third note line stayed on the page.
        func nextTop(_ shape: String) throws -> Double {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), end = try XCTUnwrap(xml.range(of: "</w:body>"))
            let run = "<w:rPr><w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\" w:eastAsia=\"宋体\"/><w:sz w:val=\"18\"/></w:rPr>"
            let note = "<w:p><w:pPr><w:snapToGrid w:val=\"0\"/><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"264\" w:lineRule=\"auto\"/></w:pPr><w:r>\(run)<w:t>注：\(shape)兼容比例不超过</w:t></w:r></w:p>"
            let next = "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\"/></w:pPr><w:r>\(run)<w:t>next</w:t></w:r></w:p>"
            xml.replaceSubrange(body.upperBound ..< end.lowerBound, with: note + next
                + "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"0\" w:footer=\"0\" w:gutter=\"0\"/></w:sectPr>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            theme.faceResolver = OfficeFonts.face
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "next" })
            return l.geometry(k).top / theme.pixelsPerPoint
        }
        let plain = try nextTop("兼"), segoe = try nextTop("◎"), times = try nextTop("●")
        XCTAssertEqual(times, plain, accuracy: 0.05, "a shape Times has lifts nothing")
        // (Segoe's ascent, 1.079 em, over the line's own: 0.48 in Word's
        // 0.24 steps at 9pt.)
        XCTAssertGreaterThan(segoe - plain, 0.3, "the line holding ◎ is taller")
        XCTAssertLessThan(segoe - plain, 1.0)
    }

    func testANumberThatFitsMayPartAfterItsHyphenUnderEastAsianLayout() throws {
        // zh-b58b4f0c (mode 12, doNotCompress): a cell line ends "…8年（104-"
        // and the next opens "111年）計畫" in Word's print; zh-b2e0f286's
        // "106-" / "109 年", zh-a917e13c's "《2018-" / "2020 年" (mode 15) —
        // some seventy such lines in the corpus. Not before mode 15 where
        // punctuation is compressed: zh-0104b952 (mode 14) keeps
        // "0571-85455244" whole with room for "0571-".
        try requireFitterWidths()
        let text = String(repeating: "一", count: 12) + "（104-111年）計畫"
        XCTAssertGreaterThan(try firstLineWidth(text, width: 185, mode: 12, compresses: false), 170, "\"（104-\" ends the line")
        XCTAssertGreaterThan(try firstLineWidth(text, width: 185, mode: 15), 170, "from 2013's layout, compressing too")
        XCTAssertLessThan(try firstLineWidth(text, width: 185, mode: 14), 150, "kept whole: mode 14, compressing")
    }

    func testAMarkInTextOfNoEastAsianLanguageGivesNothing() throws {
        try requireFitterWidths()
        // zh-0513f641 p5: its body style says `w:eastAsia` x-none, and Word
        // leaves "維" 5.7pt over a line whose "：" could give 7 (lab c0513,
        // Mac: with the style saying zh-TW the colon gives, "維" taken).
        let text = String(repeating: "一", count: 8) + "：" + String(repeating: "二", count: 16) + "維運"
        // 25 characters of 14pt (12 here: 300pt) and "維" 5 over.
        XCTAssertGreaterThan(try firstLineWidth(text, width: 307, language: "zh-TW"), 306, "taken, the colon giving")
        XCTAssertLessThan(try firstLineWidth(text, width: 307, language: "x-none"), 301, "left: under no language the colon gives nothing")
        // (Nor under en-US, now in Word for Mac as in Windows: zh-c5b5087b's
        // print from a fresh Mac Word sets its en-US body's marks whole.)
        XCTAssertLessThan(try firstLineWidth(text, width: 307, language: "en-US"), 301, "en-US gives nothing either: zh-c5b5087b")
    }

    func testAHintedDegreeSignInSongTiIsAnEm() throws {
        // zh-cd8987db p7: "坡度＜25°的…", a run of 宋体 that says w:hint
        // eastAsia — Word sets its "°" in 宋体, 10.50 at 10.5pt; ours was the
        // stand-in's own 0.4 em, and the line took "土中。" Word's leaves.
        func width(_ text: String) -> Double {
            var style = CharStyle()
            style.fontFamily = "宋体"
            style.eastAsiaFontFamily = "宋体"
            style.fontHint = "eastAsia"
            style.fontSize = 10.5
            let doc = RichDocument(paragraphs: [RichParagraph(text: text, runs: [Run(length: text.utf16.count, style: style)])])
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 4000
            l.ensureLaidOut(doc)
            return (l.geometry(0).painter.computeLineMetrics().first?.width ?? 0) / l.theme.pixelsPerPoint
        }
        XCTAssertEqual(width("°"), 10.5, accuracy: 0.05, "an em")
        XCTAssertEqual(width("一°°°°一") - width("一一"), 4 * 10.5, accuracy: 4 * 0.7, "about an em each among ideographs")
    }

    func testALatinFaceForEastAsianTextInTheDefaultsIsRead() throws {
        // zh-cd48112c: its rPrDefault names Times New Roman for East Asian
        // text, and Word for Windows compresses none of its punctuation
        // (labs tcd/x); with 宋体 there it does.
        func opened(eastAsia: String) throws -> RichDocument {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .a4))
            let si = try XCTUnwrap(entries.firstIndex { $0.name == "word/styles.xml" })
            var xml = String(decoding: entries[si].data, as: UTF8.self)
            let at = try XCTUnwrap(xml.range(of: "<w:rPrDefault><w:rPr>"))
            xml.replaceSubrange(at, with: "<w:rPrDefault><w:rPr><w:rFonts w:eastAsia=\"\(eastAsia)\"/>")
            entries[si] = ZipEntry(name: "word/styles.xml", data: Data(xml.utf8))
            return try DocxFormat.read(try Zip.write(entries)).document
        }
        XCTAssertTrue(try opened(eastAsia: "Times New Roman").eastAsianDefaultFaceIsLatin)
        XCTAssertFalse(try opened(eastAsia: "宋体").eastAsianDefaultFaceIsLatin)
    }

    func testAHintedMiddleDotInSongTiIsAnEmAndGivesAsAMark() throws {
        // zh-3f871b7d p1: "…在青岛·上" — a hinted "·" Word sets in 宋体, an em
        // (SimSun is fixed-pitch), where ours set the stand-in's 0.33 and
        // the line took "合". And it gives like a mark: zh-b9af65b5's line
        // "元/建筑平米·月" (mode 14, 10.5pt) sets the dot 8.16 to keep "月".
        try requireFitterWidths()
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        func layout(_ text: String, width: Double) -> RichLayout {
            var style = CharStyle()
            style.fontFamily = "宋体"
            style.eastAsiaFontFamily = "宋体"
            style.fontHint = "eastAsia"
            style.fontSize = 10.5
            var doc = RichDocument(paragraphs: [RichParagraph(text: text, runs: [Run(length: text.utf16.count, style: style)])])
            doc.compatibilityMode = 14
            doc.characterSpacingControl = "compressPunctuation"
            doc.usesEastAsianLayout = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = width * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            return l
        }
        func natural(_ text: String) -> Double {
            (layout(text, width: 4000).geometry(0).painter.computeLineMetrics().first?.width ?? 0) / theme.pixelsPerPoint
        }
        XCTAssertEqual(natural("一·一") - natural("一一"), 10.5, accuracy: 0.05, "an em")
        let text = "元/建筑平米·月"
        let whole = natural(text)
        func lines(over: Double) -> Int { layout(text, width: whole - over).geometry(0).painter.computeLineMetrics().count }
        XCTAssertEqual(lines(over: 2.25), 1, "the dot gives the 2.25 \"月\" is over")
        XCTAssertEqual(lines(over: 6.75), 2, "more than its half: \"月\" goes down")
    }

    func testANoBreakSpaceAfterALatinDigitIsTheSpacesHalfEm() throws {
        // zh-a7a889eb p5: "3.5" + U+00A0 + U+0020 + "拟派…" in a 12pt 宋体 run
        // hinted East Asian — Word sets the no-break space 6pt, the space's
        // half em, where ours set it an em and the line lost "业 贰 级".
        // After an ideograph or a "." it is an em still (lab `nb1`;
        // zh-17749c13's "1." + U+00A0 + "船").
        func width(_ text: String) -> Double {
            var style = CharStyle()
            style.fontFamily = "宋体"
            style.eastAsiaFontFamily = "宋体"
            style.fontHint = "eastAsia"
            style.fontSize = 12
            let doc = RichDocument(paragraphs: [RichParagraph(text: text, runs: [Run(length: text.utf16.count, style: style)])])
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 4000
            l.ensureLaidOut(doc)
            return (l.geometry(0).painter.computeLineMetrics().first?.width ?? 0) / l.theme.pixelsPerPoint
        }
        XCTAssertEqual(width("3.5\u{00A0} 拟") - width("3.5 拟"), 6, accuracy: 0.3, "after a digit, half an em")
        XCTAssertEqual(width("条\u{00A0}拟") - width("条拟"), 12, accuracy: 0.3, "after an ideograph, an em")
        XCTAssertEqual(width("1.\u{00A0}船") - width("1.船"), 12, accuracy: 0.3, "after a full stop, an em")
    }

    func testABareMarksNumberIsItsParagraphStylesSize() throws {
        // zh-117cf7c6 p3: "※ 每人每月補助…", 12pt text under a "※" bullet
        // whose paragraph mark says nothing, in Normal's 14pt — Word sets
        // the bullet at 14pt in its level's 標楷體 and the line taller
        // than the text's; ours took the first run's 12pt.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-117cf7c6") })
        let entries = try Zip.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        func height(bulleted: Bool) throws -> Double {
            var parts = entries
            if !bulleted {
                // (The same paragraph with no number: its text where the
                // number's tab put it.)
                let di = try XCTUnwrap(parts.firstIndex { $0.name == "word/document.xml" })
                var xml = String(decoding: parts[di].data, as: UTF8.self)
                let at = try XCTUnwrap(xml.range(of: "每人每月補助"))
                let p = try XCTUnwrap(xml.range(of: "<w:p ", options: .backwards, range: xml.startIndex ..< at.lowerBound))
                let num = try XCTUnwrap(xml.range(of: "<w:numPr>", range: p.lowerBound ..< at.lowerBound))
                let end = try XCTUnwrap(xml.range(of: "</w:numPr>", range: num.upperBound ..< at.lowerBound))
                xml.replaceSubrange(num.lowerBound ..< end.upperBound, with: "<w:ind w:left=\"360\"/>")
                parts[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            }
            let opened = try DocxFormat.read(try Zip.write(parts))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("每人每月補助") })
            return (l.geometry(i).painter.computeLineMetrics().first?.height ?? 0) / l.theme.pixelsPerPoint
        }
        // (The number's box is a line of its own in the paragraph, the
        // first, as tall as a line of the text at the text's size — and the
        // taller for a number set larger. Its first line against the plain
        // paragraph's first: however the text wraps.)
        XCTAssertGreaterThan(try height(bulleted: true) - (try height(bulleted: false)), 0.3, "the bullet's 14pt makes its line taller")
    }

    func testACompatibilityIdeographYaHeiLacksIsItsBox() throws {
        // zh-12c4f07a's "契" U+F909 in a YaHei run: Word for Mac draws
        // YaHei's missing-glyph box, 0.697 em, and breaks the line by it
        // (lab `cj`); ours set an em.
        func width(_ text: String) -> Double {
            var style = CharStyle()
            style.fontFamily = "Microsoft YaHei"
            style.eastAsiaFontFamily = "Microsoft YaHei"
            style.fontSize = 13
            let doc = RichDocument(paragraphs: [RichParagraph(text: text, runs: [Run(length: text.utf16.count, style: style)])])
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.fontFamilyResolver = OfficeFonts.substitute
            theme.faceResolver = OfficeFonts.face
            theme.averageCharWidth = OfficeFonts.averageCharWidth
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 4000
            l.ensureLaidOut(doc)
            return (l.geometry(0).painter.computeLineMetrics().first?.width ?? 0) / l.theme.pixelsPerPoint
        }
        XCTAssertEqual(width("一\u{F909}\u{F909}一") - width("一一"), 2 * 0.697 * 13, accuracy: 0.3)
    }

    func testOneClosingSpaceAfterAHangingMarkIsSetAsACharacterUnderWordWrapOff() throws {
        // zh-c9f4d690: under wordWrap 0 "…报民航行业主管等部门。 " hangs its
        // "。" past the margin in Word's print and sets its one closing
        // space on a line of its own: it has nowhere to hang. Ours hung
        // both. The space is set as a no-break one, which takes room.
        func text(_ s: String, wordWrap: Bool) -> String {
            var p = RichParagraph(text: s)
            if !wordWrap { p.style.eastAsian["w:wordWrap"] = "0" }
            let doc = RichDocument(paragraphs: [p])
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 400
            l.ensureLaidOut(doc)
            return l.geometry(0).painter.text?.toPlainText() ?? ""
        }
        XCTAssertTrue(text("主管等部门。 ", wordWrap: false).hasSuffix("\u{00A0}"))
        XCTAssertFalse(text("主管等部门。 ", wordWrap: true).contains("\u{00A0}"), "only under wordWrap off")
        XCTAssertFalse(text("主管等部门。  ", wordWrap: false).contains("\u{00A0}"), "two spaces wrap as before")
    }

    func testACellsParagraphsShareTheirSpacing() throws {
        // drawing.docx: two headings of 12pt before and 3pt after in one
        // cell are 12pt apart in Word's print, as in the body — the larger
        // of the two spaces alone, where ours had both.
        func layout(cell: Bool, adds: Bool = false) -> (RichLayout, RichDocument) {
            var a = RichParagraph(text: "one")
            a.style.spaceBefore = 12
            a.style.spaceAfter = 3
            var b = a
            b.style.spaceAfter = 0
            if cell {
                a.cell = CellRef(table: "t", row: 0, column: 0)
                b.cell = a.cell
            }
            var doc = RichDocument(paragraphs: [a, b])
            doc.tableColumns["t"] = [200]
            doc.addsParagraphSpacing = adds
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 2)
            l.width = 400
            l.ensureLaidOut(doc)
            return (l, doc)
        }
        func gap(_ l: RichLayout) -> Double {
            (l.geometry(1).top - l.geometry(0).top - l.geometry(0).height) / l.theme.pixelsPerPoint
        }
        let (body, _) = layout(cell: false)
        let (cell, _) = layout(cell: true)
        XCTAssertEqual(gap(cell), gap(body), accuracy: 0.01, "as in the body")
        XCTAssertEqual(gap(cell), -3, accuracy: 0.6, "the 3pt after lies under the 12 before")
        // (A file from Word 2003 and before has both.)
        let (old, _) = layout(cell: true, adds: true)
        XCTAssertEqual(gap(old), 0, accuracy: 0.01)
        XCTAssertEqual(cell.totalHeight, old.totalHeight - 3 * cell.theme.pixelsPerPoint, accuracy: 1, "and the row is that much shorter")
    }

    func testAListItemUnderATablesListItemKeepsItsSpaceBefore() throws {
        // zh-06c46ba9 p39: "（二）現況分析", a numbered List Paragraph of
        // 6pt before with contextual spacing, under a table whose last
        // paragraph is a numbered List Paragraph of another list — Word
        // keeps the 6pt; ours held the two alike and dropped it.
        func before(inCell: Bool) -> Double {
            var a = RichParagraph(text: "one")
            a.style.named = "ListParagraph"
            a.style.list = .numbered
            a.style.contextualSpacing = true
            a.cell = CellRef(table: "t", row: 0, column: 0)
            var b = a
            b.style.spaceBefore = 6
            if !inCell { b.cell = nil }
            var doc = RichDocument(paragraphs: [a, b])
            doc.tableColumns["t"] = [200]
            doc.readFromFile = true
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: 2)
            l.width = 400
            l.ensureLaidOut(doc)
            return (l.geometry(1).textTop - l.geometry(1).top) / theme.pixelsPerPoint
        }
        XCTAssertEqual(before(inCell: false), 6, accuracy: 0.6, "across the table's edge: kept")
        XCTAssertEqual(before(inCell: true), 0, accuracy: 0.01, "in the same cell: alike, dropped")
    }

    func testAFirstLineCountReplacesTheStylesHangingCount() throws {
        // zh-06c46ba9 p70: style "一" hangs its first lines two characters
        // (hangingChars 200); the table's paragraphs say firstLineChars 0
        // and firstLine 0, and stand at the cell's edge in Word's print —
        // ours kept the style's count and hung them 28pt out.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a"), RichParagraph(text: "b")]),
                                                        pageSetup: .letter))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        let styles = String(decoding: entries[si].data, as: UTF8.self).replacingAll("</w:styles>", with:
            "<w:style w:type=\"paragraph\" w:customStyle=\"1\" w:styleId=\"One\"><w:name w:val=\"One\"/><w:pPr>"
            + "<w:ind w:leftChars=\"240\" w:left=\"440\" w:hangingChars=\"200\" w:hanging=\"200\"/></w:pPr></w:style></w:styles>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:pPr><w:pStyle w:val=\"One\"/><w:ind w:leftChars=\"0\" w:left=\"0\" w:firstLineChars=\"0\" w:firstLine=\"0\"/></w:pPr><w:r><w:t>二、報告撰寫</w:t></w:r></w:p>"
            + "<w:p><w:pPr><w:pStyle w:val=\"One\"/></w:pPr><w:r><w:t>二、報告撰寫</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertNil(doc.paragraphs[0].style.eastAsian["w:hangingChars"], "the paragraph's own count replaces the style's")
        XCTAssertEqual(doc.paragraphs[1].style.eastAsian["w:hangingChars"], "200", "the style's, where the paragraph says none")
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 2)
        XCTAssertEqual(layout.firstLineIndent(doc.paragraphs[0], doc), 0, accuracy: 0.01)
        XCTAssertLessThan(layout.firstLineIndent(doc.paragraphs[1], doc), -10)
    }

    func testALineOfIdeographicSpacesIsItsMarksLine() throws {
        // zh-64044a1d p100: form rows whose cells hold "　" alone (11pt,
        // 標楷體 over Times, on an 18pt line grid) are as tall as its
        // empty rows in Word's print; ours set the space in the East
        // Asian face, whose line took two pitches where the mark's
        // takes one.
        func heights(pitch: Double) -> (empty: Double, ideograph: Double, ideographicSpace: Double) {
            var style = CharStyle()
            style.fontSize = 11
            style.fontFamily = "Times New Roman"
            style.eastAsiaFontFamily = "標楷體"
            func para(_ text: String) -> RichParagraph {
                var p = RichParagraph(text: text)
                if !text.isEmpty { p.runs = [Run(length: text.utf16.count, style: style)] }
                p.style.mark = style
                return p
            }
            var doc = RichDocument(paragraphs: [para(""), para("編"), para("\u{3000}")])
            doc.lineGridPitch = pitch
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            theme.faceResolver = OfficeFonts.face
            let l = RichLayout(theme: theme, paragraphCount: 3)
            l.width = 400
            l.ensureLaidOut(doc)
            return (l.geometry(0).height, l.geometry(1).height, l.geometry(2).height)
        }
        // (A pitch the East Asian face's line takes more of than the mark's.)
        guard let pitch = stride(from: 10.0, through: 24.0, by: 0.5).first(where: { heights(pitch: $0).ideograph > heights(pitch: $0).empty + 1 }) else {
            throw XCTSkip("no pitch here parts the two faces' lines")
        }
        let h = heights(pitch: pitch)
        XCTAssertEqual(h.ideographicSpace, h.empty, accuracy: 0.5, "the mark's line, at a pitch of \(pitch)")
        XCTAssertGreaterThan(h.ideograph, h.ideographicSpace + 1, "an ideograph's is taller")
    }

    func testALineOfSpacesAloneIsSetInItsMarksLatinFace() throws {
        // zh-1eeb9f9a p11: cells holding "　" alone, 9pt with 仿宋_GB2312 as
        // their Latin face, under a 12pt Times New Roman mark, are one
        // 15.6pt pitch in Word's print — Times' 12pt line. Ours set the
        // space at the mark's size in the run's 仿宋, two pitches, and the
        // row they stand in went over whole where Word parts it.
        func heights(pitch: Double) -> (empty: Double, songLine: Double, ideographicSpace: Double) {
            var mark = CharStyle()
            mark.fontSize = 12
            mark.fontFamily = "Times New Roman"
            mark.eastAsiaFontFamily = "仿宋_GB2312"
            var run = CharStyle()
            run.fontSize = 9
            run.fontFamily = "仿宋_GB2312"
            run.eastAsiaFontFamily = "仿宋_GB2312"
            run.fontHint = "eastAsia"
            func para(_ text: String, _ style: CharStyle) -> RichParagraph {
                var p = RichParagraph(text: text)
                if !text.isEmpty { p.runs = [Run(length: text.utf16.count, style: style)] }
                p.style.mark = mark
                return p
            }
            var song = run
            song.fontSize = 12
            var doc = RichDocument(paragraphs: [para("", mark), para("a", song), para("\u{3000}", run)])
            doc.lineGridPitch = pitch
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            theme.faceResolver = OfficeFonts.face
            let l = RichLayout(theme: theme, paragraphCount: 3)
            l.width = 400
            l.ensureLaidOut(doc)
            return (l.geometry(0).height, l.geometry(1).height, l.geometry(2).height)
        }
        // (A pitch over the mark's 12pt Times line, 13.8, as the document's
        // 15.6 is, where the run's face's 12pt line takes more of it.)
        guard let pitch = stride(from: 14.0, through: 24.0, by: 0.5).first(where: { heights(pitch: $0).songLine > heights(pitch: $0).empty + 1 }) else {
            throw XCTSkip("no pitch here parts the two faces' lines")
        }
        let h = heights(pitch: pitch)
        XCTAssertEqual(h.ideographicSpace, h.empty, accuracy: 0.5, "the mark's line, in the mark's face, at a pitch of \(pitch)")
    }

    func testRubyIsReadDrawnRoomForAndSaved() throws {
        // 61470: "東京" with "とうきょう" over it (w:ruby). The reader
        // skipped the whole of it, base and all, and the page was blank.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:p><w:r><w:rPr><w:sz w:val=\"22\"/></w:rPr><w:ruby><w:rubyPr><w:rubyAlign w:val=\"distributeSpace\"/><w:hps w:val=\"11\"/>"
            + "<w:hpsRaise w:val=\"20\"/><w:hpsBaseText w:val=\"22\"/><w:lid w:val=\"ja-JP\"/></w:rubyPr><w:rt><w:r><w:rPr><w:sz w:val=\"11\"/></w:rPr>"
            + "<w:t>とうきょう</w:t></w:r></w:rt><w:rubyBase><w:r><w:rPr><w:sz w:val=\"22\"/></w:rPr><w:t>東京</w:t></w:r></w:rubyBase></w:ruby></w:r>"
            + "<w:r><w:t>都</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let p = doc.paragraphs[0]
        XCTAssertEqual(p.text, "東京都", "the base is the text")
        let ruby = try XCTUnwrap(p.runs.first?.style.ruby)
        XCTAssertEqual(ruby.text, "とうきょう")
        XCTAssertEqual(ruby.size, 5.5)
        XCTAssertEqual(ruby.raise, 10)
        XCTAssertEqual(p.runs.first?.length, 2)
        XCTAssertNil(p.runs.last?.style.ruby, "and only the base")
        // The save writes it back round its base.
        let saved = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let out = String(decoding: try XCTUnwrap(saved.first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(out.containsSubstring("<w:hpsRaise w:val=\"20\"/>"), out)
        XCTAssertTrue(out.containsSubstring("とうきょう</w:t></w:r></w:rt><w:rubyBase><w:r>"), out)
        XCTAssertEqual(out.components(separatedBy: "<w:ruby>").count, 2, "one ruby")
        let back = try DocxFormat.read(try Zip.write(saved)).document
        XCTAssertEqual(back.paragraphs[0].text, "東京都")
        XCTAssertEqual(back.paragraphs[0].runs.first?.style.ruby?.text, "とうきょう")
        // The line makes room for it, and the base is spread across it.
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        theme.faceResolver = OfficeFonts.face
        func measure(_ d: RichDocument) -> (height: Double, width: Double) {
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 400
            l.ensureLaidOut(d)
            return (l.geometry(0).height, l.geometry(0).painter.maxIntrinsicWidth)
        }
        var plain = doc
        for k in plain.paragraphs[0].runs.indices { plain.paragraphs[0].runs[k].style.ruby = nil }
        XCTAssertGreaterThan(measure(doc).height, measure(plain).height + 1, "taller, for the ruby")
        XCTAssertGreaterThan(measure(doc).width, measure(plain).width + 1, "the base spread across the ruby's width")
    }

    func testSpacesAfterIdeographsAddNothingToTheLine() throws {
        // zh-1563bd74's footer: "红河县人民政府发布" and five spaces in 14pt
        // bold 宋体, a line under a taller one. Word sets it no taller for
        // the spaces (the Mac's lab `hfl`); ours set them in the Latin
        // stand-in, whose depth the line took — 19.4pt for 18.2 on Linux.
        // The spaces now take the ideographs' face, at the stand-in's width.
        // (The unit tests have no ICU to part the line as the app does, so
        // the face is what is tested.)
        var song = CharStyle(bold: true, fontFamily: "宋体", fontSize: 14)
        song.eastAsiaFontFamily = "宋体"
        func spans(_ text: String) -> [TextSpan] {
            var p = RichParagraph(text: text)
            p.runs = [Run(length: text.utf16.count, style: song)]
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            theme.faceResolver = OfficeFonts.face
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 600
            l.ensureLaidOut(RichDocument(paragraphs: [p]))
            var out: [TextSpan] = []
            func visit(_ s: InlineSpan) {
                guard let t = s as? TextSpan else { return }
                if let x = t.text, !x.isEmpty { out.append(t) }
                for c in t.children ?? [] { visit(c) }
            }
            if let root = l.geometry(0).painter.text { visit(root) }
            return out
        }
        let all = spans("红河县人民政府发布     ")
        let ideographs = try XCTUnwrap(all.first { $0.text?.contains("红") == true })
        let tail = try XCTUnwrap(all.last { $0.text?.allSatisfy { $0 == " " } == true })
        XCTAssertEqual(tail.style?.fontFamily, ideographs.style?.fontFamily, "the trailing spaces in the ideographs' face")
        // (At the stand-in's width: as wide as spaces between Latin letters.)
        let latin = spans("红河县 A B")
        XCTAssertNotEqual(latin.first { $0.text == " A B" || $0.text?.hasPrefix(" ") == true }?.style?.fontFamily, ideographs.style?.fontFamily,
                          "spaces within the line stay in the stand-in")
    }

    func testAFrameOfNoWidthStandsWhereItIsAligned() throws {
        // Bug51170: the footer's page number is a frame aligned right in
        // the margins with no width of its own; Word sets it at the right
        // margin, ours stood it at the left on every page.
        func ends(_ align: String?) -> (left: Double, right: Double) {
            var p = RichParagraph(text: "2")
            var frame = ParagraphFrame()
            frame.horizontalAnchor = "margin"
            frame.horizontalAlign = align
            p.style.frame = frame
            let doc = RichDocument(paragraphs: [p, RichParagraph(text: "footer")])
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: 2)
            layout.floatsFrames = true
            layout.width = 400
            layout.ensureLaidOut(doc)
            let g = layout.geometry(0)
            let line = g.painter.computeLineMetrics()[0]
            return (g.textLeft + line.left, g.textLeft + line.left + line.width)
        }
        XCTAssertEqual(ends("right").right, 400, accuracy: 1, "at the band's right")
        let centred = ends("center")
        XCTAssertEqual((centred.left + centred.right) / 2, 200, accuracy: 1)
        XCTAssertEqual(ends(nil).left, 0, accuracy: 1, "and at its left with no alignment")
    }

    func testAStrokeHoldsTheLetterAfterIt() {
        // bug65649: "ИО102-20/А2М" parts after the hyphen in Word's print,
        // never after the stroke before a Cyrillic letter; ours carried
        // "А2М" down alone. (The rule, not a line: the test process has
        // no ICU, and its lines part between any two characters.)
        XCTAssertTrue(RichLayout.joinsLatin("/", "А"), "a stroke before a Cyrillic letter")
        XCTAssertTrue(RichLayout.joinsLatin("/", "A"), "and before a Latin one, as before")
        XCTAssertTrue(RichLayout.joinsLatin(")", "Ж"))
        XCTAssertTrue(RichLayout.joinsLatin("/", "é"))
        XCTAssertFalse(RichLayout.joinsLatin("/", " "), "a space parts")
        XCTAssertFalse(RichLayout.joinsLatin("/", "\u{A0}"))
        XCTAssertFalse(RichLayout.joinsLatin("/", "中"), "East Asian text keeps its own rules")
        XCTAssertFalse(RichLayout.joinsLatin("-", "А"), "a hyphen still parts")
    }

    func testPictureInABorderedRunReadsItsFrameAndEffects() throws {
        // bug59058: "tab1", an inline picture in a run with a 0.75pt grey
        // character border, its effect extent 0.75pt below; Word's line
        // holds both.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(image: ImageAttachment(data: png, width: 72, height: 36))]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<wp:docPr", with: "<wp:effectExtent l=\"152400\" t=\"0\" r=\"76200\" b=\"9525\"/><wp:docPr")
        xml = xml.replacingAll("<w:r><w:drawing>", with: "<w:r><w:rPr><w:bdr w:val=\"single\" w:sz=\"6\" w:space=\"0\" w:color=\"CCCCCC\" w:frame=\"1\"/></w:rPr><w:drawing>")
        XCTAssertTrue(xml.contains("<w:bdr "), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let opened = try DocxFormat.read(try Zip.write(entries))
        let att = try XCTUnwrap(opened.document.paragraphs[0].image)
        XCTAssertEqual(att.effectLeft, 12)
        XCTAssertEqual(att.effectRight, 6)
        let saved = try DocxFormat.read(try DocxFormat.write(opened.document, pageSetup: .letter))
        XCTAssertEqual(saved.document.paragraphs[0].image?.effectLeft, 12)
        XCTAssertEqual(saved.document.paragraphs[0].image?.effectRight, 6)
        XCTAssertEqual(att.frame?.width, 0.75)
        XCTAssertEqual(att.frame?.space, 0)
        XCTAssertEqual(att.effectBottom, 0.75)
        XCTAssertEqual(att.effectTop, 0)
        // (A border of no line is none.)
        let none = xml.replacingAll("w:val=\"single\" w:sz=\"6\"", with: "w:val=\"none\" w:sz=\"0\"")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(none.utf8))
        XCTAssertNil(try DocxFormat.read(try Zip.write(entries)).document.paragraphs[0].image?.frame)
    }

    func testMergedCellKeepsEachContinuationRowsSides() throws {
        // bug65649: a header cell merged down three rows, its first cell
        // ruled on top and open below, its last continuation ruled below.
        var a = RichParagraph(text: "head"), b = RichParagraph(text: "r0"), c = RichParagraph(text: "r1"), d = RichParagraph(text: "r2")
        a.cell = CellRef(table: "T", row: 0, column: 0, rowSpan: 3, edges: BorderEdges(top: true, bottom: false))
        a.cell!.continuationEdges = [BorderEdges(top: false, bottom: false), BorderEdges(top: false, bottom: true)]
        b.cell = CellRef(table: "T", row: 0, column: 1); c.cell = CellRef(table: "T", row: 1, column: 1); d.cell = CellRef(table: "T", row: 2, column: 1)
        var doc = RichDocument(paragraphs: [a, b, c, d, RichParagraph(text: "")])
        doc.tableColumns["T"] = [100, 100]
        var ts = TableStyle(); ts.borders = true; ts.bordersFromCells = true; doc.tableStyles["T"] = ts
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:vMerge/><w:tcBorders><w:top w:val=\"nil\"/><w:bottom w:val=\"nil\"/></w:tcBorders>"), xml)
        XCTAssertTrue(xml.contains("<w:vMerge/><w:tcBorders><w:top w:val=\"nil\"/><w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"auto\"/></w:tcBorders>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        let cell = try XCTUnwrap(back.paragraphs[0].cell)
        XCTAssertEqual(cell.rowSpan, 3)
        XCTAssertEqual(cell.continuationEdges.count, 2)
        XCTAssertEqual(cell.continuationEdges[1]?.bottom, true)
        XCTAssertEqual(cell.continuationEdges[0]?.bottom, false)
        // A cell ruled wider than the table (bug65649's 1.5pt headers over
        // 0.75pt rows) keeps its width, on its continuation rows too.
        var wide = doc
        wide.paragraphs[0].cell!.borderWidth = 1.5
        let wxml = String(decoding: try Zip.read(try DocxFormat.write(wide, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(wxml.contains("<w:top w:val=\"single\" w:sz=\"12\" w:space=\"0\" w:color=\"auto\"/><w:bottom w:val=\"nil\"/>"), wxml)
        XCTAssertTrue(wxml.contains("<w:vMerge/><w:tcBorders><w:top w:val=\"nil\"/><w:bottom w:val=\"single\" w:sz=\"12\""), wxml)
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(wide, pageSetup: .letter)).document.paragraphs[0].cell?.borderWidth, 1.5)
        // In a table with its OWN borders, a cell that draws the same
        // sides wider still keeps them (form_footnotes' heading cell).
        var own = doc
        own.tableStyles["T"]!.bordersFromCells = false
        own.paragraphs[0].cell = CellRef(table: "T", row: 0, column: 0, rowSpan: 1, edges: BorderEdges(top: true, left: true))
        own.paragraphs[0].cell!.borderWidth = 2.25
        let oback = try DocxFormat.read(try DocxFormat.write(own, pageSetup: .letter)).document.paragraphs[0].cell
        XCTAssertEqual(oback?.borderWidth, 2.25)
        XCTAssertEqual(oback?.edges, BorderEdges(top: true, left: true))
    }

    func testNamedStyleKeepsItsTabStops() throws {
        // issue_51265_3: the header style's centre and right tabs lay out
        // the kept header part; written without them it collapsed.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "h")])
        var ps = RichParagraphStyle(); ps.tabStops = [TabStop(position: 226.8, alignment: .center), TabStop(position: 453.6, alignment: .right)]
        doc.styles["Kopfzeile"] = RichNamedStyle(id: "Kopfzeile", name: "header", paragraph: ps, char: CharStyle())
        doc.paragraphs[0].style.named = "Kopfzeile"
        let styles = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/styles.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(styles.contains("w:styleId=\"Kopfzeile\"><w:name w:val=\"header\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/><w:pPr><w:tabs><w:tab w:val=\"center\" w:pos=\"4536\"/><w:tab w:val=\"right\" w:pos=\"9072\"/></w:tabs>"), styles)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.styles["Kopfzeile"]?.paragraph.tabStops, ps.tabStops)
    }

    func testComplexScriptBoldAndFormatChangeRoundTrip() throws {
        // rtl.docx: an Arabic heading bold by w:bCs alone; delins: a run
        // whose formatting was changed with tracking on.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "\u{0625}\u{0633}"), RichParagraph(text: "b"), RichParagraph(text: "Reino")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:r><w:t xml:space=\"preserve\">\u{0625}\u{0633}</w:t>", with: "<w:r><w:rPr><w:bCs/><w:szCs w:val=\"28\"/><w:rtl w:val=\"true\"/></w:rPr><w:t xml:space=\"preserve\">\u{0625}\u{0633}</w:t>")
        // Latin text in the same kind of run: the complex-script bold does
        // not apply to it.
        xml = xml.replacingAll("<w:r><w:t xml:space=\"preserve\">Reino</w:t>", with: "<w:r><w:rPr><w:i/><w:bCs/><w:rtl w:val=\"true\"/></w:rPr><w:t xml:space=\"preserve\">Reino</w:t>")
        xml = xml.replacingAll("<w:r><w:t xml:space=\"preserve\">b</w:t>", with: "<w:r><w:rPr><w:i/><w:rPrChange w:id=\"7\" w:author=\"Ann\" w:date=\"2009-03-01T10:00:00Z\"><w:rPr><w:b/></w:rPr></w:rPrChange></w:rPr><w:t xml:space=\"preserve\">b</w:t>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let a = try XCTUnwrap(back.paragraphs[0].runs.first?.style)
        XCTAssertTrue(a.bold && a.rightToLeft)
        XCTAssertEqual(a.fontSize, 14)
        let b = try XCTUnwrap(back.paragraphs[1].runs.first?.style)
        XCTAssertTrue(b.italic)
        XCTAssertEqual(b.formatChange?.author, "Ann")
        XCTAssertEqual(b.formatChange?.oldRPrXML, "<w:rPr><w:b/></w:rPr>")
        let again = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(again.contains("<w:i/><w:iCs/><w:rPrChange w:id=\"1\" w:author=\"Ann\" w:date=\"2009-03-01T10:00:00Z\"><w:rPr><w:b/></w:rPr></w:rPrChange></w:rPr>"), again)
        XCTAssertTrue(again.contains("<w:b/><w:bCs/>") && again.contains("<w:rtl/>"), again)
        let latin = try XCTUnwrap(back.paragraphs[2].runs.first?.style)
        XCTAssertTrue(latin.italic)
        XCTAssertFalse(latin.bold)
    }

    func testListLevelKeepsItsNumberLookAndSuffix() throws {
        // bug65649: sub-levels whose numbers are 14pt and not bold, and a
        // level followed by a space rather than a tab.
        var p = RichParagraph(text: "item")
        p.style.list = .numbered; p.style.listId = "7"; p.style.listLevel = 1
        var doc = RichDocument(paragraphs: [p])
        var l1 = ListLevelFormat(text: "%1.%2.", format: .decimal)
        l1.numberRPrXML = "<w:rPr><w:b w:val=\"0\"/><w:sz w:val=\"28\"/></w:rPr>"; l1.suffix = "space"
        doc.listFormats["7"] = [0: ListLevelFormat(text: "%1.", format: .decimal), 1: l1]
        let numbering = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/numbering.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(numbering.contains("<w:numFmt w:val=\"decimal\"/><w:suff w:val=\"space\"/><w:lvlText w:val=\"%1.%2.\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"1440\" w:hanging=\"360\"/></w:pPr><w:rPr><w:b w:val=\"0\"/><w:sz w:val=\"28\"/></w:rPr></w:lvl>"), numbering)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        let lvl = try XCTUnwrap(back.listFormats["7"]?[1])
        XCTAssertEqual(lvl.suffix, "space")
        XCTAssertEqual(lvl.numberRPrXML, "<w:rPr><w:b w:val=\"0\"/><w:sz w:val=\"28\"/></w:rPr>")
        XCTAssertNil(back.listFormats["7"]?[0]?.numberRPrXML)
    }

    func testALargerNumberRaisesItsLineButSetsNoDeeper() throws {
        // bug65649: "3.1.1." in 14pt over 12pt text — the first line
        // stands 15.72pt under the line above in Word's print (the 14pt
        // number's height above the baseline) and the second 13.8 under
        // it, as under any line of 12pt text; a whole 14pt line for the
        // first set every numbered paragraph 0.45pt deeper.
        _ = OfficeFonts.register()
        func baselines(numberSize: Int?) throws -> (first: Double, gap: Double) {
            var p = RichParagraph(text: String(repeating: "система должна быть ", count: 8))
            p.style.list = .numbered; p.style.listId = "7"; p.style.listLevel = 0
            var doc = RichDocument(paragraphs: [p])
            var level = ListLevelFormat(text: "%1.", format: .decimal)
            if let numberSize { level.numberRPrXML = "<w:rPr><w:sz w:val=\"\(numberSize * 2)\"/></w:rPr>" }
            doc.listFormats["7"] = [0: level]
            let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: back.paragraphs.count)
            layout.width = 300
            layout.ensureLaidOut(back)
            // (The lift is the paragraph's ink shift: its lines keep the
            // strut, zh-7773163d's "●案例" headings.)
            let geometry = layout.geometry(0)
            let lines = geometry.painter.computeLineMetrics()
            XCTAssertGreaterThan(lines.count, 2)
            return ((lines[0].baseline + geometry.inkShift) / theme.pixelsPerPoint, (lines[1].baseline - lines[0].baseline) / theme.pixelsPerPoint)
        }
        let plain = try baselines(numberSize: nil)
        let larger = try baselines(numberSize: 14)
        XCTAssertGreaterThan(larger.first, plain.first + 1, "the first line rises to the number's height")
        XCTAssertEqual(larger.gap, plain.gap, accuracy: 0.15, "and the next line is the text's line under it")
    }

    func testANumberIsOnTheGridWhereItsLevelSaysSoOverItsMark() throws {
        try requireFitterWidths()
        // zh-c15af02e's heading 6 level says `<w:snapToGrid/>` and its
        // paragraphs' text is off a grid of 1pt: Word sets "〈2〉" 17.0, 9.9
        // and 17.0 at 16pt, and p37's "〈2〉依該市社會經濟發展、交通運輸狀況、
        // 車輛持" is its first line; ours set the number off the grid with
        // the mark, the text 2.5pt early, and took "有" too.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/docs")
        let name = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: dir.path).first { $0.hasPrefix("zh-c15af02e") })
        let opened = try DocxFormat.read(try Data(contentsOf: dir.appendingPathComponent(name)))
        let doc = opened.document
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        theme.fontFamilyResolver = OfficeFonts.substitute
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.wordRules = true
        let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        let setup = opened.pageSetup ?? .a4
        l.pageSetup = setup
        l.width = setup.columnWidth * theme.pixelsPerPoint
        l.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("依該市社會經濟發展") })
        let end = l.geometry(i).painter.getLineBoundary(TextPosition(offset: 0)).end
        // (The painter's offsets count one zero-width break `_span` puts in
        // before the line's end, so the text's first line is one shorter.)
        let first = String(doc.paragraphs[i].text.utf16.prefix(end - 1)) ?? ""
        XCTAssertTrue(first.hasSuffix("車輛持"), first)
    }

    func testANumbersTabReachesTheParagraphsOwnStop() throws {
        // bug65649: "3.2.1.3." under a first-line indent of 567 twips and
        // no hanging one ends short of the paragraph's stop at 1843;
        // Word starts the text at that stop (177.1pt on its page), not at
        // the default stop before it, where ours did.
        _ = OfficeFonts.register()
        func textStart(stop: Bool) throws -> Double {
            var p = RichParagraph(text: "HHH")
            p.style.list = .numbered; p.style.listId = "7"; p.style.listLevel = 0
            p.style.listIndentLeft = 0
            p.style.listFirstLine = 28.35
            if stop { p.style.tabStops = [TabStop(position: 92.15)] }
            var doc = RichDocument(paragraphs: [p])
            doc.listFormats["7"] = [0: ListLevelFormat(text: "3.2.1.%1.", format: .decimal)]
            doc.defaultTabStop = 35.4
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: 1)
            layout.width = 600
            layout.ensureLaidOut(doc)
            // (Where the text starts: the right of the box before it —
            // the test process has no ICU for carets.)
            let box = try XCTUnwrap(layout.geometry(0).painter.inlinePlaceholderBoxes?.first)
            return box.right / theme.pixelsPerPoint
        }
        XCTAssertEqual(try textStart(stop: true), 92.15, accuracy: 0.5, "at the paragraph's own stop")
        XCTAssertEqual(try textStart(stop: false), 70.8, accuracy: 0.5, "the next default stop, with none of its own")
    }

    func testARightStopAfterANegativelySpacedStartEndsAtTheStop() throws {
        // zh-10e3a42b's first contents entry: "1．总则<tab>4", the "1"
        // spaced -0.5pt, a dotted right stop 0.2pt inside the column. The
        // engine moves a line by half its first character's spacing, and
        // the tab took that quarter point again: the line ran past the
        // column and the "4" went to a line of its own.
        _ = OfficeFonts.register()
        func width(_ spacing: Double) -> Double {
            var spaced = CharStyle.plain; spaced.letterSpacing = spacing
            var p = RichParagraph(text: "1 A\t4", runs: [Run(length: 3, style: spaced), Run(length: 2)])
            var stop = TabStop(position: 200, alignment: .right); stop.leader = "dot"
            p.style.tabStops = [stop]
            let doc = RichDocument(paragraphs: [p])
            let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: 1)
            layout.width = 200.2 * theme.pixelsPerPoint
            layout.ensureLaidOut(doc)
            return layout.geometry(0).painter.maxIntrinsicWidth / theme.pixelsPerPoint
        }
        XCTAssertLessThanOrEqual(width(-0.5), 200.01, "no wider than the stop")
        XCTAssertEqual(width(0), 200, accuracy: 0.01, "unspaced, to the stop")
    }

    func testABodyWordWiderThanTheLineOpensALine() throws {
        // bug65649: "Замечания: " and 142 underscores is the label alone
        // and two lines of underscores in Word's print; ours parted the
        // underscores straight after the label. (The rule, not a line:
        // the test process has no ICU to part lines by.)
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        let p = RichParagraph(text: "Note: " + String(repeating: "_", count: 80))
        var doc = RichDocument(paragraphs: [p])
        XCTAssertEqual(layout.wideWordStarts(p, doc, textWidth: 300), [6], "the underscores open a line")
        XCTAssertEqual(layout.wideWordStarts(p, doc, textWidth: 1000), [], "not where they fit")
        let short = RichParagraph(text: "Note: " + String(repeating: "_", count: 19))
        XCTAssertEqual(layout.wideWordStarts(short, RichDocument(paragraphs: [short]), textWidth: 50), [], "under twenty, unmeasured in the body")
        doc.usesEastAsianLayout = true
        XCTAssertEqual(layout.wideWordStarts(p, doc, textWidth: 300), [], "under East Asian layout, parted where it stands")
    }

    func testATabSeparatesAnOverlongWordAfterAFullWidthMark() throws {
        // The tab in zh-6a4fc013 Q5 belongs with its heading. Inserting a
        // hard break before it stranded its held space on a blank line.
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        let label = "标题："
        let word = String(repeating: "_", count: 80)
        let tabbed = RichParagraph(text: label + "\t" + word)
        var doc = RichDocument(paragraphs: [tabbed])
        doc.usesEastAsianLayout = true
        XCTAssertEqual(layout.wideWordStarts(tabbed, doc, textWidth: 300), [],
                       "the tab is a boundary, not the start of the overlong word")
        let joined = RichParagraph(text: label + word)
        doc.paragraphs = [joined]
        XCTAssertEqual(layout.wideWordStarts(joined, doc, textWidth: 300), [label.utf16.count],
                       "without a tab the word still starts after the full-width mark")
    }

    func testACellWordWiderThanTheLineOpensALineAfterASpace() throws {
        // zh-15f60bac's 282pt cell "…研究院(網址: http://www.tri.org.tw/page/
        // consumer.php)及…" ends its first line at "(網址: " in Word's print,
        // the address opening the next and parted at its margin; ours parted
        // it "…http://ww" where it stood. (The rule, not a line: the test
        // process has no ICU to part lines by.)
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        var p = RichParagraph(text: "研究院(網址: http://www.tri.org.tw/page/consumer.php)及中央大學")
        p.cell = CellRef(table: "t", row: 0, column: 0)
        var doc = RichDocument(paragraphs: [p])
        doc.usesEastAsianLayout = true
        let at = "研究院(網址: ".utf16.count
        XCTAssertEqual(layout.wideWordStarts(p, doc, textWidth: 200 * theme.pixelsPerPoint), [at], "the address opens a line")
        XCTAssertEqual(layout.wideWordStarts(p, doc, textWidth: 1000 * theme.pixelsPerPoint), [], "not where it fits")
        doc.usesEastAsianLayout = false
        XCTAssertEqual(layout.wideWordStarts(p, doc, textWidth: 200 * theme.pixelsPerPoint), [], "a wide cell outside East Asian layout, as before")
    }

    func testAGroupsBoxesApartKeepTheirOwnPlaces() throws {
        // shapes-with-text: a group of an arrow with text in it and a text
        // box under it, at other places and widths. Word sets each box's
        // text in its own place; ours set the first at the group's left
        // and never read the second.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        func shape(_ x: Int, _ y: Int, _ cx: Int, _ cy: Int, _ text: String) -> String {
            "<wps:wsp><wps:cNvSpPr/><wps:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></wps:spPr>"
                + "<wps:txbx><w:txbxContent><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:txbxContent></wps:txbx><wps:bodyPr anchor=\"t\"/></wps:wsp>"
        }
        let group = "<w:r><w:drawing xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:wpg=\"http://schemas.microsoft.com/office/word/2010/wordprocessingGroup\" xmlns:wps=\"http://schemas.microsoft.com/office/word/2010/wordprocessingShape\">"
            + "<wp:anchor distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\" simplePos=\"0\" relativeHeight=\"1\" behindDoc=\"0\" locked=\"0\" layoutInCell=\"1\" allowOverlap=\"1\">"
            + "<wp:simplePos x=\"0\" y=\"0\"/><wp:positionH relativeFrom=\"column\"><wp:posOffset>0</wp:posOffset></wp:positionH><wp:positionV relativeFrom=\"paragraph\"><wp:posOffset>0</wp:posOffset></wp:positionV>"
            + "<wp:extent cx=\"4333875\" cy=\"1285875\"/><wp:wrapNone/><wp:docPr id=\"9\" name=\"Group 1\"/><a:graphic><a:graphicData uri=\"http://schemas.microsoft.com/office/word/2010/wordprocessingGroup\">"
            + "<wpg:wgp><wpg:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"4333875\" cy=\"1285875\"/><a:chOff x=\"0\" y=\"3209925\"/><a:chExt cx=\"4333875\" cy=\"1285875\"/></a:xfrm></wpg:grpSpPr>"
            + shape(1076325, 3390900, 2228850, 647700, "A group of shapes") + shape(1447800, 3952875, 1209675, 542925, "Where some contain text")
            + "</wpg:wgp></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>"
        let r = try XCTUnwrap(xml.range(of: "</w:p>"))
        xml.replaceSubrange(r, with: group + "</w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        var images: [ImageAttachment] = []
        for p in doc.paragraphs { images += (p.image.map { [$0] } ?? []) + Array(p.inlineImages.values) }
        let box = try XCTUnwrap(images.compactMap(\.textBox).first)
        XCTAssertEqual(box.paragraphs.map(\.text), ["A group of shapes", "Where some contain text"], "both boxes read")
        XCTAssertEqual(box.parts.map(\.first), [0, 1])
        // (Each in its own column: the shape's left and its 7.2pt inset;
        // from its own top: the shape's top in the group and its 3.6.)
        XCTAssertEqual(box.paragraphs[0].style.indentLeft, 1076325 / 12700 + 7.2, accuracy: 0.01)
        XCTAssertEqual(box.paragraphs[1].style.indentLeft, 1447800 / 12700 + 7.2, accuracy: 0.01)
        XCTAssertEqual(box.paragraphs[1].style.indentRight, (4333875 - 1447800 - 1209675) / 12700 + 7.2, accuracy: 0.01)
        XCTAssertEqual(box.parts[1].top, (3952875 - 3209925) / 12700 + 3.6, accuracy: 0.01)
        XCTAssertEqual(box.insetLeft, 0)

        // A warped first shape is drawn with the group, not again as a
        // plain overlay. The remaining box still keeps its own place;
        // an unsupported warp must leave both ordinary boxes intact.
        for preset in ["textSlantDown", "textNoShape"] {
            var changed = xml
            let body = try XCTUnwrap(changed.range(of: "<wps:bodyPr anchor=\"t\"/>"))
            changed.replaceSubrange(body, with: "<wps:bodyPr fromWordArt=\"1\"><a:prstTxWarp prst=\"\(preset)\"><a:avLst><a:gd name=\"adj\" fmla=\"val 28569\"/></a:avLst></a:prstTxWarp></wps:bodyPr>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(changed.utf8))
            let loaded = try DocxFormat.read(Zip.write(entries))
            let image = try XCTUnwrap(loaded.document.paragraphs.lazy.compactMap { $0.image ?? $0.inlineImages.values.first }.first)
            let remaining = try XCTUnwrap(image.textBox)
            if preset == "textSlantDown" {
                XCTAssertEqual(remaining.paragraphs.map(\.text), ["Where some contain text"])
                XCTAssertEqual(remaining.parts.count, 1)
                XCTAssertEqual(remaining.paragraphs[0].style.indentLeft, 1447800 / 12700 + 7.2, accuracy: 0.01)
                XCTAssertEqual(remaining.parts[0].top, (3952875 - 3209925) / 12700 + 3.6, accuracy: 0.01)
            } else {
                XCTAssertEqual(remaining.paragraphs.map(\.text), box.paragraphs.map(\.text))
            }
            let saved = try Zip.read(DocxFormat.write(loaded.document, pageSetup: .letter))
            let markup = String(decoding: try XCTUnwrap(saved.first { $0.name == "word/document.xml" }).data, as: UTF8.self)
            XCTAssertTrue(markup.contains("prst=\"\(preset)\""))
            XCTAssertTrue(markup.contains("A group of shapes"), "warped text remains editable in the saved file")
        }
    }

    func testALineOfALonePictureIsAsTallAsItsText() throws {
        // drawing.docx: its mastheads' tiny pictures between line breaks
        // in 8.5pt Arial make a band 32pt tall in Word's print — each line
        // a line of the text at least — where ours took each picture's
        // height alone, 17pt in all.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans, fontSize: 12)
        theme.wordRules = true
        func lineHeight(_ text: String, width: Double = 1, height: Double = 1.5, wordRules: Bool = true) throws -> Double {
            var p = RichParagraph(text: text)
            let image = ImageAttachment(data: png, width: width, height: height)
            p.inlineImages[image.id] = image
            let at = (text as NSString).range(of: RichParagraph.inlineImageCharacter).location
            p.applyStyle(at ..< at + 1) { $0.inlineImage = image.id }
            let t = RichTextTheme(fontFamily: OfficeFonts.sans, fontSize: 12)
            t.wordRules = wordRules
            let layout = RichLayout(theme: t, paragraphCount: 1)
            layout.width = 400
            layout.ensureLaidOut(RichDocument(paragraphs: [p]))
            return try XCTUnwrap(layout.geometry(0).painter.computeLineMetrics().first).height / theme.pixelsPerPoint
        }
        let alone = try lineHeight(RichParagraph.inlineImageCharacter)
        XCTAssertGreaterThan(alone, 10, "a line of 12pt text at least, not the picture's 1.5pt")
        XCTAssertLessThan(try lineHeight(RichParagraph.inlineImageCharacter, wordRules: false), 3, "outside Word's rules, the picture's own")
        XCTAssertLessThan(try lineHeight(RichParagraph.inlineImageCharacter, width: 400), 3, "nor one as wide as the line")
        // (A picture taller than a line of the text is its line's height,
        // with no depth of the text under it: the masthead's 12.8pt one.)
        XCTAssertEqual(try lineHeight(RichParagraph.inlineImageCharacter, height: 30), 30, accuracy: 0.8)
    }

    func testRowPropertyExceptionsKept() throws {
        // form_footnotes: a row that rules itself (w:tblPrEx) over the table.
        var a = RichParagraph(text: "a"), b = RichParagraph(text: "b")
        a.cell = CellRef(table: "T", row: 0, column: 0); b.cell = CellRef(table: "T", row: 1, column: 0)
        var doc = RichDocument(paragraphs: [a, b, RichParagraph(text: "")])
        doc.tableColumns["T"] = [200]
        let ex = "<w:tblPrEx><w:tblBorders><w:top w:color=\"auto\" w:space=\"0\" w:sz=\"18\" w:val=\"single\"/></w:tblBorders></w:tblPrEx>"
        var ts = TableStyle(); ts.rowExceptions = [1: ex]; ts.rowHeights = [1: 45.15]; doc.tableStyles["T"] = ts
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:tr>" + ex + "<w:trPr><w:trHeight w:val=\"903\"/></w:trPr>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document.tableStyles.values.first
        XCTAssertEqual(back?.rowExceptions, [1: ex])
    }

    func testGridBeforeStartsTheRowsCellsLater() throws {
        // zh-51af781b's scoring table: rows that leave the 5-twip first
        // column empty (w:gridBefore 1) and start their number cell after it.
        var a = RichParagraph(text: "1"), b = RichParagraph(text: "text"), c = RichParagraph(text: "2"), d = RichParagraph(text: "more")
        a.cell = CellRef(table: "T", row: 0, column: 0, span: 2); b.cell = CellRef(table: "T", row: 0, column: 2)
        c.cell = CellRef(table: "T", row: 1, column: 1); d.cell = CellRef(table: "T", row: 1, column: 2)
        var doc = RichDocument(paragraphs: [a, b, c, d, RichParagraph(text: "")])
        doc.tableColumns["T"] = [0.25, 42, 395]
        var ts = TableStyle(); ts.rowsGridBefore = [1: 1]; doc.tableStyles["T"] = ts
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:trPr><w:gridBefore w:val=\"1\"/><w:wBefore w:w=\"5\" w:type=\"dxa\"/></w:trPr>"), xml)
        XCTAssertEqual(xml.components(separatedBy: "<w:tc>").count - 1, 4, "no empty cell in the skipped column: \(xml)")
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.tableStyles.values.first?.rowsGridBefore, [1: 1])
        XCTAssertEqual(back.paragraphs.first { $0.text == "2" }?.cell?.column, 1)
        XCTAssertEqual(back.paragraphs.first { $0.text == "more" }?.cell?.column, 2)
    }

    func testSpaceBeforeZeroWrittenUnderAStyleThatHasSome() throws {
        // form_footnotes: a Heading 6 spacer paragraph that says before 0.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "h"), RichParagraph(text: "plain")])
        var ps = RichParagraphStyle(); ps.spaceBefore = 2; ps.spaceAfter = 2
        doc.styles["Spacer"] = RichNamedStyle(id: "Spacer", name: "Spacer", paragraph: ps, char: CharStyle())
        doc.paragraphs[0].style.named = "Spacer"; doc.paragraphs[0].style.spaceBefore = 0; doc.paragraphs[0].style.spaceAfter = 0
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Spacer\"/><w:spacing w:before=\"0\" w:after=\"0\""), xml)
        XCTAssertEqual(xml.components(separatedBy: "w:before=").count, 2, "the plain paragraph says nothing of before: \(xml)")
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document.paragraphs[0].style.spaceBefore, 0)
    }

    func testSymbolRunsAndSymbolBulletsRoundTrip() throws {
        // form_footnotes: "OF [box] TEL" with the box as w:sym Symbol F094,
        // and lists whose bullet is the same private-use code.
        var p = RichParagraph(text: "item"); p.style.list = .bullet; p.style.listId = "2"
        var doc = RichDocument(paragraphs: [RichParagraph(text: "OF X TEL"), p])
        doc.listFormats["2"] = [0: ListLevelFormat(text: "\u{2022}", format: .bullet)]
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:r><w:t xml:space=\"preserve\">OF X TEL</w:t></w:r>", with: "<w:r><w:t xml:space=\"preserve\">OF </w:t></w:r><w:r><w:sym w:font=\"Symbol\" w:char=\"F094\"/></w:r><w:r><w:t xml:space=\"preserve\"> TEL</w:t></w:r>")
        XCTAssertTrue(xml.contains("w:sym"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let ni = entries.firstIndex { $0.name == "word/numbering.xml" }!
        var num = String(decoding: entries[ni].data, as: UTF8.self)
        let lvl = "<w:lvlText w:val=\"\u{2022}\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"720\" w:hanging=\"360\"/></w:pPr>"
        XCTAssertTrue(num.contains(lvl), num)
        num = num.replacingAll(lvl, with: "<w:lvlText w:val=\"\u{F094}\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"720\" w:hanging=\"360\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"Symbol\" w:hAnsi=\"Symbol\"/></w:rPr>")
        entries[ni] = ZipEntry(name: "word/numbering.xml", data: Data(num.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].text, "OF \u{F094} TEL")
        XCTAssertEqual(back.paragraphs[0].runs.count, 3)
        XCTAssertEqual(back.paragraphs[0].runs[1].style.fontFamily, "Symbol")
        XCTAssertEqual(back.listFormats["2"]?[0]?.rawText, "\u{F094}")
        let saved = try Zip.read(try DocxFormat.write(back, pageSetup: .letter))
        let again = String(decoding: saved.first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(again.contains("<w:sym w:font=\"Symbol\" w:char=\"F094\"/>"), again)
        let numAgain = String(decoding: saved.first { $0.name == "word/numbering.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(numAgain.contains("<w:lvlText w:val=\"\u{F094}\"/>"), numAgain)
    }

    func testNormalsLanguageTakesTheDefaultsEastAsianOneItDoesNotState() throws {
        // zh-63a571aa's Normal says only `w:bidi="ar-SA"`; its East Asian
        // text is the defaults' zh-TW, whose centred "。" keeps its em
        // before "」" in Word's print. Ours took Normal's whole and no
        // East Asian language with it, and closed the "。" up.
        let doc = RichDocument(paragraphs: [RichParagraph(text: "甲。」，乙")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        while let r = styles.range(of: "<w:lang [^>]*/>", options: .regularExpression) { styles.removeSubrange(r) }
        let defaults = try XCTUnwrap(styles.range(of: "<w:rPrDefault><w:rPr>"), styles)
        styles.insert(contentsOf: "<w:lang w:val=\"en-US\" w:eastAsia=\"zh-TW\" w:bidi=\"hi-IN\"/>", at: defaults.upperBound)
        let normal = try XCTUnwrap(styles.range(of: "w:styleId=\"Normal\""), styles)
        let end = try XCTUnwrap(styles.range(of: "</w:style>", range: normal.upperBound ..< styles.endIndex))
        if let rPr = styles.range(of: "<w:rPr>", range: normal.upperBound ..< end.lowerBound) {
            styles.insert(contentsOf: "<w:lang w:bidi=\"ar-SA\"/>", at: rPr.upperBound)
        } else {
            styles.insert(contentsOf: "<w:rPr><w:lang w:bidi=\"ar-SA\"/></w:rPr>", at: end.lowerBound)
        }
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertTrue(back.marksCentred, back.defaultLangXML ?? "no language")
        XCTAssertTrue(back.defaultLangXML?.contains("w:bidi=\"ar-SA\"") ?? false, back.defaultLangXML ?? "no language")
    }

    func testGridKeepsTheColumnsOnlySpannedCellsReach() throws {
        // bug65649: every row's last cell spans into columns no cell STARTS
        // in, so counting start columns lost the grid's tail and the
        // file's 63 widths fell back to 62 equal ones.
        var a = RichParagraph(text: "a"), b = RichParagraph(text: "b"), c = RichParagraph(text: "c")
        a.cell = CellRef(table: "T", row: 0, column: 0)
        b.cell = CellRef(table: "T", row: 0, column: 1, span: 3)
        c.cell = CellRef(table: "T", row: 1, column: 0, span: 4)
        var d = RichParagraph(text: "d")
        d.cell = CellRef(table: "T", row: 2, column: 0)   // a short row: Word allows one, and padding it adds a paragraph
        var doc = RichDocument(paragraphs: [a, b, c, d, RichParagraph(text: "")])
        doc.tableColumns["T"] = [20, 30, 40, 400]
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:tblGrid><w:gridCol w:w=\"400\"/><w:gridCol w:w=\"600\"/><w:gridCol w:w=\"800\"/><w:gridCol w:w=\"8000\"/></w:tblGrid>"), xml)
        XCTAssertTrue(xml.contains("<w:tcW w:w=\"9400\" w:type=\"dxa\"/><w:gridSpan w:val=\"3\"/>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.tableColumns.values.first ?? [], [20, 30, 40, 400])
        XCTAssertEqual(back.paragraphs.count, doc.paragraphs.count)
        XCTAssertTrue(xml.contains("<w:tr><w:tc><w:tcPr><w:tcW w:w=\"400\" w:type=\"dxa\"/></w:tcPr><w:p><w:pPr><w:spacing w:after=\"160\" w:line=\"259\" w:lineRule=\"auto\"/></w:pPr><w:r><w:t xml:space=\"preserve\">d</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"), xml)
    }

    func testSectionsAndCompatModeKeptVerbatim() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "portrait"), RichParagraph(text: "landscape")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let sect = "<w:sectPr><w:headerReference w:type=\"default\" r:id=\"rIdNone\"/><w:type w:val=\"nextPage\"/><w:pgSz w:w=\"16839\" w:h=\"11907\" w:orient=\"landscape\"/><w:pgMar w:top=\"567\" w:right=\"567\" w:bottom=\"567\" w:left=\"1134\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/><w:cols w:space=\"720\"/></w:sectPr>"
        // Into the first paragraph's properties: the last </w:pPr> before its text.
        let textAt = xml.range(of: ">portrait<")!.lowerBound
        let close = xml.range(of: "</w:pPr>", options: .backwards, range: xml.startIndex ..< textAt)!
        xml.insert(contentsOf: sect, at: close.lowerBound)
        XCTAssertTrue(xml.contains("w:orient=\"landscape\""), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let si = entries.firstIndex { $0.name == "word/settings.xml" }!
        let settings = String(decoding: entries[si].data, as: UTF8.self).replacingAll("w:val=\"15\"/></w:compat>", with: "w:val=\"14\"/><w:useFELayout/></w:compat>")
        XCTAssertTrue(settings.contains("useFELayout"), settings)
        entries[si] = ZipEntry(name: "word/settings.xml", data: Data(settings.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertTrue(back.paragraphs[1].style.pageBreakBefore)
        let kept = try XCTUnwrap(back.paragraphs[0].style.sectionXML)
        XCTAssertTrue(kept.contains("w:orient=\"landscape\"") && !kept.contains("headerReference"), kept)
        XCTAssertEqual(back.keptCompat, "<w:compat><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"14\"/><w:useFELayout/></w:compat>")
        // An EMPTY block is Word's legacy layout mode and is kept too
        // (drawing.docx wrapped tighter under mode 15).
        var legacy = entries
        let li = legacy.firstIndex { $0.name == "word/settings.xml" }!
        var lset = String(decoding: legacy[li].data, as: UTF8.self)
        lset = lset.replacingAll(String(lset[lset.range(of: "<w:compat>")!.lowerBound ..< lset.range(of: "</w:compat>")!.upperBound]), with: "<w:compat/>")
        legacy[li] = ZipEntry(name: "word/settings.xml", data: Data(lset.utf8))
        let lback = try DocxFormat.read(try Zip.write(legacy)).document
        XCTAssertEqual(lback.keptCompat, "<w:compat/>")
        let lsaved = String(decoding: try Zip.read(try DocxFormat.write(lback, pageSetup: .letter)).first { $0.name == "word/settings.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(lsaved.contains("<w:compat/>") && !lsaved.contains("compatibilityMode"), lsaved)
        let saved = try Zip.read(try DocxFormat.write(back, pageSetup: .letter))
        let savedXML = String(decoding: saved.first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(savedXML.contains("<w:sectPr><w:type w:val=\"nextPage\"/><w:pgSz w:h=\"11907\" w:orient=\"landscape\" w:w=\"16839\"/>"), savedXML)
        XCTAssertFalse(savedXML.contains("rIdNone"), savedXML)
        XCTAssertEqual(savedXML.components(separatedBy: "<w:sectPr>").count - 1, 2, "the section and the body's own")
        let savedSettings = String(decoding: saved.first { $0.name == "word/settings.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(savedSettings.contains("w:val=\"14\"/><w:useFELayout/></w:compat>"), savedSettings)
    }

    /// The settings the line fitting reads (measured against Word,
    /// 2026-10-12): balanced widths, the alternative kinsoku rules, the
    /// compatibility mode, a default tab stop of none; and a section's
    /// own line grid and first-page switch on the paragraph that ends it.
    func testSettingsAndSectionGridThatSteerTheLayout() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "first"), RichParagraph(text: "second")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let si = entries.firstIndex { $0.name == "word/settings.xml" }!
        var settings = String(decoding: entries[si].data, as: UTF8.self)
        settings = settings.replacingAll("w:val=\"15\"/></w:compat>", with: "w:val=\"14\"/><w:balanceSingleByteDoubleByteWidth/><w:useAltKinsokuLineBreakRules/><w:useFELayout/></w:compat>")
        settings = settings.replacingAll("<w:defaultTabStop w:val=\"720\"/>", with: "<w:defaultTabStop w:val=\"0\"/>")
        XCTAssertTrue(settings.contains("balanceSingleByteDoubleByteWidth") && settings.contains("<w:defaultTabStop w:val=\"0\"/>"), settings)
        entries[si] = ZipEntry(name: "word/settings.xml", data: Data(settings.utf8))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let sect = "<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/><w:titlePg/><w:docGrid w:type=\"linesAndChars\" w:linePitch=\"312\" w:charSpace=\"4096\"/></w:sectPr>"
        let textAt = xml.range(of: ">first<")!.lowerBound
        let close = xml.range(of: "</w:pPr>", options: .backwards, range: xml.startIndex ..< textAt)!
        xml.insert(contentsOf: sect, at: close.lowerBound)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertTrue(back.balancesSpaceWidth)
        XCTAssertTrue(back.hangsHalf)
        XCTAssertEqual(back.compatibilityMode, 14)
        XCTAssertEqual(back.defaultTabStop, 0)
        let section = try XCTUnwrap(back.paragraphs[0].style.sectionPage)
        XCTAssertEqual(section.lineGridPitch ?? 0, 15.6, accuracy: 0.001)
        XCTAssertEqual(section.characterGridSpace ?? 0, 1, accuracy: 0.001)
        XCTAssertTrue(section.titlePage)
        // (The last section's grid is the document's, and it has none.)
        XCTAssertNil(back.lineGridPitch)
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/settings.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(saved.contains("<w:defaultTabStop w:val=\"0\"/>"), saved)
    }

    func testRunTurningOffItsStyleBoldIsWrittenOff() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "plain heading")])
        doc.styles = OfficeStyles.sheet
        var h3 = try XCTUnwrap(doc.styles["Heading3"]); h3.char.bold = true; h3.char.italic = true; doc.styles["Heading3"] = h3
        doc.styles.apply("Heading3", to: &doc.paragraphs[0].style)
        // A plain run inherits the style's bold: nothing written (52288's
        // chapter names must stay bold).
        let plain = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertFalse(plain.contains("w:val=\"0\""), plain)
        // A run that turns them off says so, and reads back the same.
        doc.paragraphs[0].runs[0].style.off = [.bold, .italic]
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:rPr><w:b w:val=\"0\"/><w:i w:val=\"0\"/></w:rPr>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].runs[0].style.off, [.bold, .italic])
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: 1)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(back)
        XCTAssertEqual((layout.geometry(0).painter.text as? TextSpan)?.style?.fontWeight, .normal, "the editor shows it un-bold too")
    }

    func testAutoSpacingRoundTrip() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "html paragraph")])
        doc.paragraphs[0].style.spaceBefore = 5; doc.paragraphs[0].style.spaceBeforeAuto = true; doc.paragraphs[0].style.spaceAfterAuto = true
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:spacing w:before=\"100\" w:beforeAutospacing=\"1\" w:after=\"160\" w:afterAutospacing=\"1\""), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertTrue(back.paragraphs[0].style.spaceBeforeAuto && back.paragraphs[0].style.spaceAfterAuto)
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: 1)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(back)
        XCTAssertEqual(layout.geometry(0).textTop - layout.geometry(0).top, (14 * 96.0 / 72.0).rounded())
        // Under an auto-spaced style, a paragraph that turns it off says so.
        var styled = doc
        styled.styles["Web"] = RichNamedStyle(id: "Web", name: "Web", paragraph: { var p = RichParagraphStyle(); p.spaceBeforeAuto = true; p.spaceAfterAuto = true; return p }(), char: CharStyle())
        styled.paragraphs[0].style.named = "Web"
        styled.paragraphs[0].style.spaceBeforeAuto = false; styled.paragraphs[0].style.spaceAfterAuto = false; styled.paragraphs[0].style.spaceAfter = 12
        let off = String(decoding: try Zip.read(try DocxFormat.write(styled, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(off.contains("<w:spacing w:before=\"100\" w:beforeAutospacing=\"0\" w:after=\"240\" w:afterAutospacing=\"0\""), off)
    }

    func testPaginationHintsRoundTrip() throws {
        var a = RichParagraph(text: "a"), b = RichParagraph(text: "b")
        a.cell = CellRef(table: "T", row: 0, column: 0); b.cell = CellRef(table: "T", row: 1, column: 0)
        var doc = RichDocument(paragraphs: [RichParagraph(text: "head"), a, b, RichParagraph(text: "")])
        doc.tableColumns["T"] = [200]
        var ts = TableStyle(); ts.rowsCantSplit = [1]; doc.tableStyles["T"] = ts
        doc.paragraphs[0].style.keepNext = true; doc.paragraphs[0].style.keepLines = true; doc.paragraphs[0].style.widowControl = false
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:pPr><w:keepNext/><w:keepLines/><w:widowControl w:val=\"0\"/><w:spacing"), xml)
        XCTAssertTrue(xml.contains("<w:tr><w:trPr><w:cantSplit/></w:trPr>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertTrue(back.paragraphs[0].style.keepNext && back.paragraphs[0].style.keepLines && !back.paragraphs[0].style.widowControl)
        XCTAssertTrue(back.paragraphs[1].style.widowControl)
        XCTAssertEqual(back.tableStyles.values.first?.rowsCantSplit, [1])
    }

    /// A document whose one outer cell holds `inner` (a nested table's
    /// markup), read back.
    private func nestedTableDocument(_ inner: String) throws -> RichDocument {
        var a = RichParagraph(text: "outer")
        a.cell = CellRef(table: "T", row: 0, column: 0)
        let doc = RichDocument(paragraphs: [a, RichParagraph(text: "")])
        var d = doc; d.tableColumns["T"] = [300]
        var entries = try Zip.read(try DocxFormat.write(d, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let cellOpen = xml.range(of: "</w:tcPr>")!
        xml.insert(contentsOf: inner, at: cellOpen.upperBound)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        return try DocxFormat.read(try Zip.write(entries)).document
    }

    /// zh-045c5a75: a one-column table that draws nothing round a table
    /// is read as the body, and keeps the room it gives its cell above and
    /// below — the cell's margin and twice the cell spacing — as its first
    /// and last paragraphs' space, as a nested table's cells do.
    func testAnInvisibleWrapperKeepsItsCellsRoom() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let wrapper = "<w:tbl><w:tblPr><w:tblW w:w=\"5000\" w:type=\"pct\"/><w:tblCellSpacing w:w=\"15\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"15\" w:type=\"dxa\"/><w:bottom w:w=\"15\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid><w:gridCol w:w=\"9000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr>"
            + nestedTable("a", "b") + "<w:p><w:r><w:t>tail</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
        let p = xml.range(of: "<w:p>")!.lowerBound
        xml.insert(contentsOf: wrapper, at: p)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let a = try XCTUnwrap(back.paragraphs.first { $0.text == "a" })
        let tail = try XCTUnwrap(back.paragraphs.first { $0.text == "tail" })
        XCTAssertNotNil(a.cell, "the inner table is the body's")
        XCTAssertNil(tail.cell, "the wrapper is not a table")
        XCTAssertEqual(a.style.spaceBefore, 2.25, accuracy: 0.001)
        let plain = try XCTUnwrap(back.paragraphs.first { $0.text == "x" })
        XCTAssertEqual(tail.style.spaceAfter - plain.style.spaceAfter, 2.25, accuracy: 0.001)
    }

    private func nestedTable(_ first: String, _ second: String) -> String {
        "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders><w:top w:val=\"single\" w:sz=\"8\" w:space=\"0\" w:color=\"FF0000\"/></w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w=\"2000\"/><w:gridCol w:w=\"2000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>\(first)</w:t></w:r></w:p></w:tc><w:tc><w:tcPr><w:tcW w:w=\"2000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>\(second)</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
    }

    /// drawing.docx: an empty paragraph that ends a cell right under a
    /// table nested in it is set at half a point in Word's print (five
    /// such marks of 8.5pt, five lines of 0.48pt); any other empty
    /// paragraph keeps its mark's line. Flagged by the reader, not saved.
    func testTheMarkUnderANestedTableIsHalfAPoint() throws {
        let long = "in1 " + String(repeating: "x", count: 600)   // flattened, not a block
        func document(outerText: String) throws -> RichDocument {
            var a = RichParagraph(text: "outer")
            a.cell = CellRef(table: "T", row: 0, column: 0)
            var d = RichDocument(paragraphs: [a, RichParagraph(text: "")])
            d.tableColumns["T"] = [300]
            var entries = try Zip.read(try DocxFormat.write(d, pageSetup: .letter))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            xml.insert(contentsOf: nestedTable(long, "in2"), at: xml.range(of: "</w:tcPr>")!.upperBound)
            xml = xml.replacingAll(">outer</w:t>", with: ">\(outerText)</w:t>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            return try DocxFormat.read(try Zip.write(entries)).document
        }
        let marked = try document(outerText: "")
        let mark = try XCTUnwrap(marked.paragraphs.last { $0.cell != nil })
        XCTAssertTrue(mark.text.isEmpty)
        XCTAssertTrue(mark.style.markUnderNestedTable, "the cell's empty last paragraph, under the nested table")
        XCTAssertEqual(marked.paragraphs.filter { $0.style.markUnderNestedTable }.count, 1, "and no other")
        let text = try document(outerText: "after")
        XCTAssertFalse(text.paragraphs.contains { $0.style.markUnderNestedTable }, "a paragraph with text is no mark")
        // Its line is half a point's, where an empty paragraph's is its mark's.
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        func height(_ flagged: Bool) -> Double {
            var p = RichParagraph(text: "")
            p.style.markUnderNestedTable = flagged
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 400
            l.ensureLaidOut(RichDocument(paragraphs: [p]))
            // (The line, not the paragraph's spacing around it.)
            return l.geometry(0).painter.height / theme.pixelsPerPoint
        }
        XCTAssertLessThan(height(true), 1.5)
        XCTAssertGreaterThan(height(false), 8)
    }

    /// A paragraph holding only a picture shorter than its mark's line of
    /// text is that line's height, the picture at its foot (drawing.docx,
    /// the Mac's lab t50: a 4.5pt picture in a 10.35pt line of its 9pt
    /// Times mark); a taller picture is its own height.
    func testAShortPicturesLineIsItsMarksLine() throws {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        theme.faceResolver = OfficeFonts.face
        func layout(_ height: Double) -> (block: Double, drop: Double) {
            var p = RichParagraph(image: ImageAttachment(data: Data(), width: 0.75, height: height, name: "spacer"))
            p.style.spaceBefore = 0
            p.style.spaceAfter = 0
            p.style.lineSpacing = 1
            p.style.mark = CharStyle(fontFamily: "Times New Roman", fontSize: 9)
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 400
            l.ensureLaidOut(RichDocument(paragraphs: [p]))
            let g = l.geometry(0)
            return ((g.bottom - g.top) / theme.pixelsPerPoint, ((l.imageRect(0)?.top ?? g.top) - g.top) / theme.pixelsPerPoint)
        }
        let short = layout(4.5)
        XCTAssertEqual(short.block, 10.35, accuracy: 0.8, "the mark's line")
        XCTAssertEqual(short.drop, short.block - 4.5, accuracy: 0.8, "the picture at its foot")
        let tall = layout(24)
        XCTAssertEqual(tall.block, 24, accuracy: 0.8, "a taller picture is its own height")
    }

    /// drawing.docx p11: text of 14pt after, an empty paragraph whose mark
    /// is hidden, then a heading of 12pt before — the two spaces share
    /// across the hidden one in Word's print, as if it were not there.
    func testSpaceIsSharedAcrossAHiddenParagraph() throws {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        func gap(hidden: Bool) -> Double {
            var a = RichParagraph(text: "text")
            a.style.spaceBefore = 0
            a.style.spaceAfter = 14
            var b = RichParagraph(text: "Heading")
            b.style.spaceBefore = 12
            b.style.spaceAfter = 0
            var paragraphs = [a, b]
            if hidden {
                var h = RichParagraph(text: "")
                h.style.markHidden = true
                h.style.spaceBefore = 0
                h.style.spaceAfter = 0
                paragraphs.insert(h, at: 1)
            }
            let l = RichLayout(theme: theme, paragraphCount: paragraphs.count)
            l.width = 400
            l.ensureLaidOut(RichDocument(paragraphs: paragraphs))
            let last = paragraphs.count - 1
            return (l.geometry(last).textTop - (l.geometry(0).textTop + l.geometry(0).painter.height)) / theme.pixelsPerPoint
        }
        XCTAssertEqual(gap(hidden: true), gap(hidden: false), accuracy: 0.8, "as if the hidden paragraph were not there")
        XCTAssertEqual(gap(hidden: false), 14, accuracy: 0.8, "the larger space alone")
    }

    /// delins: web-spaced bullets of one list stand with no space between
    /// them; a bullet of another list under them — the same kind, another
    /// numbering — keeps the web's 14pt, and so does a list's last item
    /// over a paragraph of none.
    func testWebSpacingPartsTwoLists() throws {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        func item(_ text: String, list: String?) -> RichParagraph {
            var p = RichParagraph(text: text)
            p.style.spaceBeforeAuto = true
            p.style.spaceAfterAuto = true
            if let list { p.style.list = .bullet; p.style.listId = list }
            return p
        }
        func gap(_ a: RichParagraph, _ b: RichParagraph) -> Double {
            var doc = RichDocument(paragraphs: [a, b])
            doc.htmlAutoSpacing = true
            doc.readFromFile = true   // (a list of the editor's own is List Paragraph, contextual)
            let l = RichLayout(theme: theme, paragraphCount: 2)
            l.width = 400
            l.ensureLaidOut(doc)
            return (l.geometry(1).textTop - (l.geometry(0).textTop + l.geometry(0).painter.height)) / theme.pixelsPerPoint
        }
        XCTAssertEqual(gap(item("a", list: "1"), item("b", list: "1")), 0, accuracy: 1.1, "one list: none between")
        XCTAssertEqual(gap(item("a", list: "1"), item("b", list: "2")), 14, accuracy: 1.1, "two lists: the web's 14pt")
        XCTAssertEqual(gap(item("a", list: "1"), item("b", list: nil)), 14, accuracy: 1.1, "a list's last item over a paragraph of none")
    }

    /// delins: 10pt Symbol bullets under 12pt Times. The level's face
    /// reaches the line at the level's own size, a line no taller than the
    /// text's — Word's 13.8; at the text's size the face made it 14.7.
    func testASymbolBulletsLineIsAtTheBulletsOwnSize() throws {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        theme.faceResolver = OfficeFonts.face
        func firstLine(_ levelSize: String?) -> Double {
            var p = RichParagraph(text: "A Nepalese name for Tilaka")
            p.runs = [Run(length: p.text.utf16.count, style: CharStyle(fontFamily: "Times New Roman", fontSize: 12))]
            p.style.spaceBefore = 0
            p.style.spaceAfter = 0
            p.style.lineSpacing = 1
            p.style.list = .bullet
            p.style.listId = "1"
            p.style.listLevel = 0
            var level = ListLevelFormat(text: "\u{F0B7}", format: .bullet)
            level.indentLeft = 36
            level.hanging = 18
            level.numberRPrXML = "<w:rPr><w:rFonts w:ascii=\"Symbol\" w:hAnsi=\"Symbol\" w:hint=\"default\"/>" + (levelSize.map { "<w:sz w:val=\"\($0)\"/>" } ?? "") + "</w:rPr>"
            var doc = RichDocument(paragraphs: [p])
            doc.listFormats["1"] = [0: level]
            doc.readFromFile = true
            let l = RichLayout(theme: theme, paragraphCount: 1)
            l.width = 600
            l.ensureLaidOut(doc)
            return l.geometry(0).height / theme.pixelsPerPoint
        }
        // (A level that says no size takes the text's: its line is the
        // Symbol face's at 12pt, taller. The unit tests have no ICU, and
        // the paragraph parts somewhere; the first line is what differs:
        // by more than a point here, 0.75 with the Mac's faces.)
        XCTAssertLessThan(firstLine("20") + 0.5, firstLine(nil), "the 10pt face's line, not a 12pt one")
    }

    /// WordWithAttachments' header: "<tab>Страница 1" on a stop. The
    /// tab's widening went on the tab, which the engine sets half before
    /// it, and at a line's start the whole line moved on by half a tab.
    func testAParagraphThatOpensWithATabStaysAtItsIndent() throws {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        var p = RichParagraph(text: "\tPage")
        p.style.tabStops = [TabStop(position: 100, alignment: .left)]
        let doc = RichDocument(paragraphs: [p])
        let l = RichLayout(theme: theme, paragraphCount: 1)
        l.width = 600
        l.ensureLaidOut(doc)
        // (The tab's widening in the first line's indent box, which the
        // engine sets where it is: a box at the line's start as wide as
        // the way to the stop, less the tab's own width. The unit tests
        // have no ICU, so carets cannot say where the text stands.)
        let box = try XCTUnwrap(l.geometry(0).painter.inlinePlaceholderBoxes?.first, "a box before the text")
        XCTAssertEqual(box.left, 0, accuracy: 0.5)
        XCTAssertGreaterThan(box.right / theme.pixelsPerPoint, 50, "most of the way to the stop at 100pt")
        XCTAssertLessThanOrEqual(box.right / theme.pixelsPerPoint, 100.5)
    }

    private func tableCount(_ x: String) -> Int { x.components(separatedBy: "<w:tbl>").count + x.components(separatedBy: "<w:tbl ").count - 2 }

    /// A small nested table is a table of its own: one block in its
    /// outer cell, the table inside it (a `RichTextBox` that grows to
    /// fit), its markup kept and written back as it was.
    func testSmallNestedTableIsABlock() throws {
        let back = try nestedTableDocument(nestedTable("in1", "in2"))
        let blocks = back.paragraphs.filter { $0.keptTable != nil }
        XCTAssertEqual(blocks.count, 1)
        let box = try XCTUnwrap(blocks[0].image?.textBox)
        XCTAssertTrue(box.growsToFit)
        XCTAssertEqual(box.paragraphs.map(\.text), ["in1", "in2"])
        XCTAssertEqual(Set(box.paragraphs.compactMap { $0.cell?.table }).count, 1, "one table, its own")
        XCTAssertEqual(box.paragraphs.map { $0.cell?.column }, [0, 1])
        XCTAssertNotNil(box.tableColumns[box.paragraphs[0].cell!.table])
        XCTAssertEqual(blocks[0].cell?.table, back.paragraphs.first { $0.text == "outer" }?.cell?.table, "set in the outer cell")
        let kept = try XCTUnwrap(back.keptTables[blocks[0].keptTable!])
        XCTAssertTrue(kept.xml.hasPrefix("<w:tbl"), kept.xml)
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(saved.contains("</w:tcPr><w:tbl") && saved.contains("w:color=\"FF0000\"") && saved.contains(">in2<"), saved)
        XCTAssertEqual(tableCount(saved), 2, "the outer table and the kept inner one")
        let again = try DocxFormat.read(try DocxFormat.write(back, pageSetup: .letter)).document
        XCTAssertEqual(again.paragraphs.compactMap { $0.image?.textBox }.flatMap { $0.paragraphs.map(\.text) }, ["in1", "in2"])
    }

    /// A section of columns that a continuous section follows, filled by
    /// a column break, reads as a borderless row of a table — a cell a
    /// column and one for the gap — with its section's end left as an
    /// empty top-level paragraph, and goes back as written.
    func testColumnSectionBeforeContinuousIsARow() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "x")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let page = "<w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>"
        let body = "<w:p><w:r><w:t>left</w:t></w:r></w:p><w:p><w:r><w:br w:type=\"column\"/></w:r></w:p><w:p><w:r><w:t>right</w:t></w:r></w:p>"
            + "<w:p><w:pPr><w:sectPr>\(page)<w:cols w:num=\"2\" w:space=\"720\"/></w:sectPr></w:pPr></w:p>"
            + "<w:p><w:r><w:t>after</w:t></w:r></w:p><w:sectPr><w:type w:val=\"continuous\"/>\(page)<w:cols w:space=\"720\"/></w:sectPr>"
        let a = xml.range(of: "<w:body>")!, b = xml.range(of: "</w:body>")!
        xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: body)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let cells = back.paragraphs.filter { $0.cell != nil }
        let table = try XCTUnwrap(cells.first?.cell?.table)
        XCTAssertEqual(back.tableColumns[table]?.count, 3, "two columns and the gap between them")
        XCTAssertEqual(back.tableColumns[table]?[1], 36)
        XCTAssertEqual(cells.first { $0.text == "left" }?.cell?.column, 0)
        XCTAssertEqual(cells.first { $0.text == "right" }?.cell?.column, 2)
        XCTAssertFalse(cells.contains { $0.style.columnBreak || $0.style.pageBreakBefore })
        XCTAssertEqual(back.tableStyles[table]?.borders, false)
        let mark = try XCTUnwrap(back.paragraphs.firstIndex { $0.cell == nil && $0.style.sectionXML != nil })
        XCTAssertEqual(back.paragraphs[mark].text, "")
        XCTAssertEqual(back.paragraphs[mark + 1].text, "after")
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertFalse(saved.contains("<w:tbl"), saved)
        XCTAssertTrue(saved.contains("w:type=\"column\"") && saved.contains("w:num=\"2\"") && saved.contains(">right<"), saved)
    }

    /// The document's own last section the same, where it is continuous
    /// after another: zh-8f9b19f4 ends "填报人：" | "审核人：" | "负责人："
    /// in three columns, one line in Word's print and a page each in ours.
    /// A document of one section of columns keeps them as columns.
    /// An auto table whose stated cells are whole columns of one width in
    /// twips is fitted to its content, those columns kept: zh-72da925e's
    /// rain tables. A column stated in one row and auto in another is not.
    func testAnAutoTableWithFixedColumnsIsFittedToItsContent() throws {
        func read(_ body: String) throws -> RichDocument {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let a = xml.range(of: "<w:body>")!, b = xml.range(of: "</w:body>")!
            xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: body)
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            return try DocxFormat.read(try Zip.write(entries)).document
        }
        func table(_ second: String) -> String {
            let fixed = "<w:tc><w:tcPr><w:tcW w:w=\"794\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc>"
            let auto = "<w:tc><w:tcPr><w:tcW w:w=\"0\" w:type=\"auto\"/></w:tcPr><w:p><w:r><w:t>2001</w:t></w:r></w:p></w:tc>"
            return "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"794\"/><w:gridCol w:w=\"997\"/><w:gridCol w:w=\"997\"/></w:tblGrid>"
                + "<w:tr>\(fixed)\(auto)\(auto)</w:tr><w:tr>\(second)\(auto)\(auto)</w:tr></w:tbl><w:p/>"
        }
        let fixed = "<w:tc><w:tcPr><w:tcW w:w=\"794\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>2</w:t></w:r></w:p></w:tc>"
        let doc = try read(table(fixed))
        let style = try XCTUnwrap(doc.tableStyles.values.first)
        XCTAssertTrue(style.contentFit)
        XCTAssertEqual(style.contentFitFixed, [0: 39.7])
        let mixed = try read(table("<w:tc><w:p><w:r><w:t>2</w:t></w:r></w:p></w:tc>"))
        XCTAssertFalse(mixed.tableStyles.values.first?.contentFit ?? false)
    }

    func testAContinuousLastSectionOfColumnsIsARow() throws {
        func read(_ body: String) throws -> RichDocument {
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let a = xml.range(of: "<w:body>")!, b = xml.range(of: "</w:body>")!
            xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: body)
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            return try DocxFormat.read(try Zip.write(entries)).document
        }
        let page = "<w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>"
        let columns = "<w:p><w:r><w:t>left</w:t></w:r></w:p><w:p><w:r><w:br w:type=\"column\"/></w:r></w:p><w:p><w:r><w:t>right</w:t></w:r></w:p>"
        let last = "<w:sectPr><w:type w:val=\"continuous\"/>\(page)<w:cols w:num=\"2\" w:space=\"720\"/></w:sectPr>"
        let back = try read("<w:p><w:r><w:t>before</w:t></w:r></w:p><w:p><w:pPr><w:sectPr>\(page)<w:cols w:space=\"720\"/></w:sectPr></w:pPr></w:p>" + columns + last)
        let cells = back.paragraphs.filter { $0.cell != nil }
        XCTAssertEqual(cells.first { $0.text == "left" }?.cell?.column, 0)
        XCTAssertEqual(cells.first { $0.text == "right" }?.cell?.column, 2)
        XCTAssertFalse(cells.contains { $0.style.columnBreak || $0.style.pageBreakBefore })
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertFalse(saved.contains("<w:tbl"), saved)
        XCTAssertTrue(saved.contains("w:type=\"column\"") && saved.contains(">right<"), saved)
        let alone = try read(columns + last)
        XCTAssertFalse(alone.paragraphs.contains { $0.cell != nil }, "one section: its own columns")
        // (… and one continuous after another with a section of its own
        // page after it: zh-b8de3ae2's "資料來源" | " ".)
        let ends = "<w:p><w:pPr><w:sectPr><w:type w:val=\"continuous\"/>\(page)<w:cols w:num=\"2\" w:space=\"720\"/></w:sectPr></w:pPr></w:p>"
        let middle = try read("<w:p><w:r><w:t>before</w:t></w:r></w:p><w:p><w:pPr><w:sectPr>\(page)<w:cols w:space=\"720\"/></w:sectPr></w:pPr></w:p>"
                              + columns + ends + "<w:p><w:r><w:t>after</w:t></w:r></w:p><w:sectPr>\(page)<w:cols w:space=\"720\"/></w:sectPr>")
        XCTAssertEqual(middle.paragraphs.first { $0.text == "right" }?.cell?.column, 2)
        XCTAssertNil(middle.paragraphs.first { $0.text == "after" }?.cell)
    }

    /// A long one is flattened into its cell, kept verbatim for the save
    /// while its text stands as read.
    func testNestedTableKeptVerbatim() throws {
        let long = "in1 " + String(repeating: "x", count: 600)
        let back = try nestedTableDocument(nestedTable(long, "in2"))
        let flat = back.paragraphs.filter { $0.keptTable != nil }
        XCTAssertEqual(flat.map(\.text), [long, "in2"])
        XCTAssertEqual(flat.map { $0.cell?.table }, [flat[0].cell?.table, flat[0].cell?.table], "flattened into the outer cell")
        XCTAssertEqual(back.paragraphs.filter { $0.cell != nil }.map(\.text), [long, "in2", "outer"])
        let kept = try XCTUnwrap(back.keptTables[flat[0].keptTable!])
        XCTAssertEqual(kept.texts, [long, "in2"])
        XCTAssertTrue(kept.xml.hasPrefix("<w:tbl"), kept.xml)
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(saved.contains("</w:tcPr><w:tbl") && saved.contains("w:color=\"FF0000\"") && saved.contains("</w:tbl><w:p>"), saved)
        XCTAssertEqual(tableCount(saved), 2, "the outer table and the kept inner one")
        XCTAssertEqual(try DocxFormat.read(try DocxFormat.write(back, pageSetup: .letter)).document.paragraphs.filter { $0.keptTable != nil }.map(\.text), [long, "in2"])
        // Edited text: the flattened paragraphs are written instead.
        var edited = back
        let i = edited.paragraphs.firstIndex { $0.text == "in2" }!
        edited.paragraphs[i] = { var p = edited.paragraphs[i]; p.text = "changed"; p.runs = [Run(length: 7)]; return p }()
        let saved2 = String(decoding: try Zip.read(try DocxFormat.write(edited, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertEqual(tableCount(saved2), 1, saved2)
        XCTAssertTrue(saved2.contains(">changed<"), saved2)
    }

    func testParagraphShadingAndContextualSpacingRoundTrip() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "one"), RichParagraph(text: "two"), RichParagraph(text: "three")])
        for i in 0 ..< 2 { doc.paragraphs[i].style.named = "ListParagraph"; doc.paragraphs[i].style.contextualSpacing = true; doc.paragraphs[i].style.spaceAfter = 20 }
        doc.styles["ListParagraph"] = RichNamedStyle(id: "ListParagraph", name: "List Paragraph", paragraph: RichParagraphStyle(), char: CharStyle())
        doc.paragraphs[0].style.fill = Color(0xFFDDDDDD)
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"DDDDDD\"/>"), xml)
        XCTAssertTrue(xml.contains("<w:contextualSpacing/>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].style.fill, Color(0xFFDDDDDD))
        XCTAssertEqual(back.paragraphs.map { $0.style.contextualSpacing }, [true, true, false])
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: 3)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(back)
        // No 20pt after between the two list paragraphs; the 20pt stays after the second (the next differs).
        XCTAssertEqual(layout.geometry(0).height, layout.geometry(0).painter.height.rounded(.up), accuracy: 1)
        XCTAssertGreaterThan(layout.geometry(1).height, layout.geometry(1).painter.height + 20)
    }

    func testFrameAndLetterSpacingRoundTrip() throws {
        var doc = RichDocument(paragraphs: [RichParagraph(text: "boxed")])
        doc.paragraphs[0].style.frameXML = "<w:framePr w:w=\"2000\" w:hAnchor=\"margin\" w:xAlign=\"right\" w:wrap=\"around\"/>"
        doc.paragraphs[0].runs[0].style.letterSpacing = 1.5
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:pPr><w:framePr w:w=\"2000\""), xml)
        XCTAssertTrue(xml.contains("<w:spacing w:val=\"30\"/>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertTrue(back.paragraphs[0].style.frameXML?.contains("w:xAlign=\"right\"") ?? false)
        XCTAssertEqual(back.paragraphs[0].runs[0].style.letterSpacing, 1.5)
        // A run's own right-to-left flag and kerning threshold ride along.
        var arabic = RichDocument(paragraphs: [RichParagraph(text: "إسبانيا 504")])
        arabic.paragraphs[0].runs[0].style.rightToLeft = true
        arabic.paragraphs[0].runs[0].style.kerningFrom = 14
        let axml = String(decoding: try Zip.read(try DocxFormat.write(arabic, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(axml.contains("<w:kern w:val=\"28\"/>") && axml.contains("<w:rtl/>"), axml)
        let aback = try DocxFormat.read(try DocxFormat.write(arabic, pageSetup: .letter)).document.paragraphs[0].runs[0].style
        XCTAssertTrue(aback.rightToLeft)
        XCTAssertEqual(aback.kerningFrom, 14)
    }

    func testCapsAndParagraphBordersRoundTrip() throws {
        var p = RichParagraph(text: "Rule below")
        p.style.borders = ParagraphBorders(bottom: BorderLine(width: 0.75, color: Color(0xFFDFDFDF), space: 1))
        var cs = CharStyle()
        cs.smallCaps = true
        var q = RichParagraph(text: "Small caps", charStyle: cs)
        q.style.borders = ParagraphBorders(top: BorderLine(), bottom: BorderLine(), left: BorderLine(), right: BorderLine())
        var doc = RichDocument(paragraphs: [p, q])
        doc.paragraphs[0].runs[0].style.caps = true
        let xml = String(decoding: try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"DFDFDF\"/></w:pBdr>"), xml)
        XCTAssertTrue(xml.contains("<w:caps/>"), xml)
        XCTAssertTrue(xml.contains("<w:smallCaps/>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].style.borders, doc.paragraphs[0].style.borders)
        XCTAssertEqual(back.paragraphs[1].style.borders, doc.paragraphs[1].style.borders)
        XCTAssertTrue(back.paragraphs[0].runs[0].style.caps)
        XCTAssertTrue(back.paragraphs[1].runs[0].style.smallCaps)
        // Shown as capitals, and a bordered paragraph is taller by the
        // line and its gap on each bordered side.
        let layout = RichLayout(theme: RichTextTheme(fontFamily: OfficeFonts.sans), paragraphCount: 2)
        layout.pageSetup = .letter
        layout.width = 612 * 96.0 / 72.0
        layout.ensureLaidOut(back)
        let ppp = 96.0 / 72.0
        let g0 = layout.geometry(0), g1 = layout.geometry(1)
        // Paragraph 0: 8pt after plus a 0.75pt line 1pt below; paragraph
        // 1: lines on all four sides, so 1.75pt more at the top as well.
        XCTAssertGreaterThanOrEqual(g0.height, (g0.painter.height + ppp * (8 + 1.75)).rounded(.down))
        XCTAssertGreaterThanOrEqual(g1.textTop - g1.top, (ppp * 1.75).rounded(.down))
        XCTAssertEqual(g0.painter.text?.toPlainText(), "RULE BELOW")
        XCTAssertEqual(g1.painter.text?.toPlainText(), "SMALL CAPS")
    }

    func testTrackedChangesRoundTrip() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "Keep this")])
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let i = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[i].data, as: UTF8.self)
        xml = xml.replacingAll("<w:t xml:space=\"preserve\">Keep this</w:t></w:r>",
                               with: "<w:t xml:space=\"preserve\">Keep this</w:t></w:r><w:ins w:id=\"7\" w:author=\"Ann\" w:date=\"2020-01-02T03:04:05Z\"><w:r><w:t xml:space=\"preserve\"> new</w:t></w:r></w:ins><w:del w:id=\"8\" w:author=\"Bob\" w:date=\"2020-01-02T03:04:06Z\"><w:r><w:rPr><w:b/></w:rPr><w:delText xml:space=\"preserve\"> old</w:delText></w:r></w:del>")
        entries[i] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let p = back.paragraphs[0]
        XCTAssertEqual(p.text, "Keep this new old")
        let marks = p.runs.map { $0.style.revision }
        XCTAssertEqual(marks, [nil, RevisionMark(kind: .inserted, author: "Ann", date: "2020-01-02T03:04:05Z"),
                               RevisionMark(kind: .deleted, author: "Bob", date: "2020-01-02T03:04:06Z")])
        XCTAssertTrue(p.runs[2].style.bold)
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(saved.contains("<w:ins w:id=\"1\" w:author=\"Ann\" w:date=\"2020-01-02T03:04:05Z\"><w:r><w:t xml:space=\"preserve\"> new</w:t></w:r></w:ins>"), saved)
        XCTAssertTrue(saved.contains("<w:del w:id=\"2\" w:author=\"Bob\" w:date=\"2020-01-02T03:04:06Z\"><w:r><w:rPr><w:b/><w:bCs/></w:rPr><w:delText xml:space=\"preserve\"> old</w:delText></w:r></w:del>"), saved)
        let again = try DocxFormat.read(try DocxFormat.write(back, pageSetup: .letter)).document
        XCTAssertEqual(again.paragraphs[0].runs.map { $0.style.revision }, marks)
        // A deleted paragraph mark (delins.docx: whole bullets struck out)
        // survives too, else Word shows an empty bullet for each.
        var struck = RichDocument(paragraphs: [RichParagraph(text: "gone"), RichParagraph(text: "stays")])
        struck.paragraphs[0].style.markRevision = RevisionMark(kind: .deleted, author: "pavel", date: "2009-07-24T15:05:00Z")
        let struckXML = String(decoding: try Zip.read(try DocxFormat.write(struck, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(struckXML.contains("<w:rPr><w:del w:id=\"1\" w:author=\"pavel\" w:date=\"2009-07-24T15:05:00Z\"/></w:rPr></w:pPr>"), struckXML)
        let struckBack = try DocxFormat.read(try DocxFormat.write(struck, pageSetup: .letter)).document
        XCTAssertEqual(struckBack.paragraphs[0].style.markRevision, struck.paragraphs[0].style.markRevision)
        XCTAssertNil(struckBack.paragraphs[1].style.markRevision)
    }

    func testZipRoundTrip() throws {
        let entries = [ZipEntry(name: "a/b.txt", data: Data("hello hello hello hello".utf8)),
                       ZipEntry(name: "c.bin", data: Data((0 ..< 5000).map { UInt8($0 % 251) }))]
        let archive = try Zip.write(entries)
        let back = try Zip.read(archive)
        XCTAssertEqual(back.map(\.name), entries.map(\.name))
        XCTAssertEqual(back.map(\.data), entries.map(\.data))
    }

    func testDocxRoundTrip() throws {
        let doc = sample()
        var setup = PageSetup.a4
        setup.marginLeft = 54
        let data = try DocxFormat.write(doc, pageSetup: setup)
        let back = try DocxFormat.read(data)
        XCTAssertEqual(back.document.paragraphs.map(\.text), doc.paragraphs.map(\.text))
        let ps = back.document.paragraphs
        XCTAssertEqual(ps[0].style.heading, 1)
        XCTAssertEqual(ps[1].runs.map(\.length), doc.paragraphs[1].runs.map(\.length))
        XCTAssertTrue(ps[1].runs[1].style.bold)
        XCTAssertTrue(ps[1].runs[3].style.italic)
        XCTAssertTrue(ps[1].runs[5].style.underline)
        XCTAssertEqual(ps[1].runs[5].style.color, Color(0xFFFF0000))
        XCTAssertEqual(ps[2].style.list, .bullet)
        XCTAssertEqual(ps[3].style.listLevel, 1)
        XCTAssertEqual(ps[4].style.list, .numbered)
        XCTAssertEqual(ps[5].style.alignment, .center)
        XCTAssertEqual(ps[6].runs(in: 4 ..< 12)[0].style.link, "https://example.com/a?b=1&c=2")
        XCTAssertTrue(ps[7].style.pageBreakBefore)
        XCTAssertEqual(ps[7].runs.last?.style.highlight, Color(0xFFFFFF00))
        XCTAssertTrue(back.document.isValid)
        let readSetup = try XCTUnwrap(back.pageSetup)
        XCTAssertEqual(readSetup.width, PageSetup.a4.width, accuracy: 0.1)
        XCTAssertEqual(readSetup.marginLeft, 54, accuracy: 0.1)
    }

    func testDocxImageRoundTrip() throws {
        // A 1×1 red PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==")!
        var doc = RichDocument(plainText: "Before\nAfter")
        doc.paragraphs.insert(RichParagraph(image: ImageAttachment(data: png, width: 120, height: 80)), at: 1)
        let data = try DocxFormat.write(doc, pageSetup: .letter)
        let entries = try Zip.read(data)
        XCTAssertTrue(entries.contains { $0.name == "word/media/image1.png" })
        let back = try DocxFormat.read(data)
        XCTAssertEqual(back.document.paragraphs.map(\.text), ["Before", "", "After"])
        let pic = try XCTUnwrap(back.document.paragraphs[1].image)
        XCTAssertEqual(pic.data, png)
        XCTAssertEqual(pic.width, 120, accuracy: 0.01)
        XCTAssertEqual(pic.height, 80, accuracy: 0.01)
    }

    /// A table made in the editor is as tall after saving and reopening
    /// as before: its cell padding is the editor's, and the file says so.
    func testAnEditorsTableKeepsItsRowHeightsThroughAFile() throws {
        _ = OfficeFonts.register()
        func cell(_ t: String, _ r: Int, _ c: Int) -> RichParagraph {
            var p = RichParagraph(text: t)
            p.cell = CellRef(table: "t", row: r, column: c)
            return p
        }
        var doc = RichDocument(paragraphs: [cell("a1", 0, 0), cell("b1", 0, 1), cell("a2", 1, 0), cell("b2", 1, 1), RichParagraph(text: "after")])
        doc.tableColumns["t"] = [200, 200]
        // (In the session's own face: the file names it, and a document
        // that names none reads back in it — the sans stand-in has a
        // shorter line than Calibri's, and the reopened table came back
        // 3px taller for the face alone.)
        func height(_ d: RichDocument) -> Double {
            let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: d.paragraphs.count)
            layout.width = 468 * 96.0 / 72.0
            layout.ensureLaidOut(d)
            return layout.totalHeight
        }
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs.map(\.text), doc.paragraphs.map(\.text))
        XCTAssertEqual(height(back), height(doc), accuracy: 0.5)
    }

    func testDocxTableRoundTrip() throws {
        var doc = RichDocument(plainText: "Before\nAfter")
        func cell(_ text: String, _ r: Int, _ c: Int, bold: Bool = false) -> RichParagraph {
            var p = RichParagraph(text: text)
            if bold { p.applyStyle(0 ..< p.length) { $0.bold = true } }
            p.cell = CellRef(table: "T", row: r, column: c)
            return p
        }
        // 2 × 2, with two paragraphs in the last cell.
        doc.paragraphs.insert(contentsOf: [cell("Name", 0, 0, bold: true), cell("Count", 0, 1),
                                           cell("apples", 1, 0), cell("three", 1, 1), cell("or four", 1, 1)], at: 1)
        doc.tableColumns["T"] = [200, 300]
        let data = try DocxFormat.write(doc, pageSetup: .letter)
        let xml = String(decoding: try XCTUnwrap(Zip.read(data).first { $0.name == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:tbl>"))
        XCTAssertTrue(xml.contains("<w:gridCol w:w=\"4000\"/><w:gridCol w:w=\"6000\"/>"))
        let back = try DocxFormat.read(data)
        let ps = back.document.paragraphs
        XCTAssertEqual(ps.map(\.text), ["Before", "Name", "Count", "apples", "three", "or four", "After"])
        XCTAssertNil(ps[0].cell)
        XCTAssertNil(ps[6].cell)
        let id = try XCTUnwrap(ps[1].cell?.table)
        XCTAssertEqual(ps[1 ... 5].map { "\($0.cell!.row),\($0.cell!.column)" }, ["0,0", "0,1", "1,0", "1,1", "1,1"])
        XCTAssertTrue(ps[1 ... 5].allSatisfy { $0.cell?.table == id })
        XCTAssertTrue(ps[1].runs[0].style.bold)
        XCTAssertFalse(ps[2].runs[0].style.bold)
        XCTAssertEqual(back.document.tableColumns[id] ?? [], [200, 300])
        XCTAssertTrue(back.document.isValid)
    }

    func testDocxNamedStylesRoundTrip() throws {
        var doc = RichDocument(plainText: "The Title\nA subtitle\nBody\nA quote\nlet x = 1\nFigure 1")
        doc.styles = OfficeStyles.sheet
        for (i, id) in ["Title", "Subtitle", "Normal", "Quote", "Code", "Caption"].enumerated() {
            doc.styles.apply(id, to: &doc.paragraphs[i].style)
        }
        let data = try DocxFormat.write(doc, pageSetup: .letter)
        let xml = String(decoding: try XCTUnwrap(Zip.read(data).first { $0.name == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:pStyle w:val=\"Quote\"/>"))
        let styles = String(decoding: try XCTUnwrap(Zip.read(data).first { $0.name == "word/styles.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(styles.contains("w:styleId=\"Title\""))
        let back = try DocxFormat.read(data)
        let ids = back.document.paragraphs.map { back.document.styles.id(of: $0.style) }
        XCTAssertEqual(ids, ["Title", "Subtitle", "Normal", "Quote", "Code", "Caption"])
        XCTAssertEqual(back.document.paragraphs[3].style.alignment, .center)
        XCTAssertEqual(back.document.styles["Title"]?.char.fontSize, 28)
        XCTAssertEqual(back.document.styles["Quote"]?.char.italic, true)
        // The file names the Word font our face stands in for, and the
        // name is kept on the way back; the face it draws with is ours.
        XCTAssertEqual(back.document.styles["Code"]?.char.fontFamily, "Courier New")
        XCTAssertEqual(back.document.styles["Code"]?.char.fontFamily.map(OfficeFonts.substitute), OfficeFonts.mono)
    }

    func testDocxWordStylesShapeTheSheet() throws {
        // A package whose Heading 1 is 16pt green: the sheet takes its word.
        var doc = RichDocument(plainText: "Heading\nBody")
        doc.styles = OfficeStyles.sheet
        var h1 = try XCTUnwrap(doc.styles["Heading1"])
        h1.char.fontSize = 16
        h1.char.color = Color(0xFF00AA00)
        h1.paragraph.spaceBefore = 24
        doc.styles["Heading1"] = h1
        doc.styles.apply("Heading1", to: &doc.paragraphs[0].style)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter))
        XCTAssertEqual(back.document.paragraphs[0].style.heading, 1)
        XCTAssertEqual(back.document.paragraphs[0].style.spaceBefore, 24)
        XCTAssertEqual(back.document.styles["Heading1"]?.char.fontSize, 16)
        XCTAssertEqual(back.document.styles["Heading1"]?.char.color, Color(0xFF00AA00))
    }

    func testAContinuedCellsParagraphsAreRead() throws {
        // Word sizes a row in which every cell is merged on or down by
        // what the cells hold, and a continued cell holds the (empty)
        // paragraphs the file wrote in it: their spacing is read.
        var a = RichParagraph(text: "head"), b = RichParagraph(text: "side"), c = RichParagraph(text: "under"), d = RichParagraph(text: "last")
        a.cell = CellRef(table: "T", row: 0, column: 0, rowSpan: 2)
        a.cell!.continuationContentXML = ["<w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"600\" w:lineRule=\"exact\"/></w:pPr></w:p>"]
        b.cell = CellRef(table: "T", row: 0, column: 1, rowSpan: 2)
        c.cell = CellRef(table: "T", row: 2, column: 0); d.cell = CellRef(table: "T", row: 2, column: 1)
        var doc = RichDocument(paragraphs: [a, b, c, d, RichParagraph(text: "")])
        doc.tableColumns["T"] = [100, 100]
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        let first = try XCTUnwrap(back.paragraphs[0].cell), second = try XCTUnwrap(back.paragraphs[1].cell)
        XCTAssertEqual(first.continuationParagraphs.count, 1)
        XCTAssertEqual(first.continuationParagraphs.first?.count, 1)
        XCTAssertEqual(first.continuationParagraphs.first?.first?.style.lineHeightPoints, 30)
        XCTAssertEqual(first.continuationParagraphs.first?.first?.style.spaceAfter, 0)
        XCTAssertNil(first.continuationParagraphs.first?.first?.cell)
        // (A bare continuation has the one empty paragraph Word requires.)
        XCTAssertEqual(second.continuationParagraphs.first?.count, 1)
    }

    func testDocxMergedCellsRoundTrip() throws {
        var doc = RichDocument(plainText: "wide\nc\nd\ne\nf\n")
        for (i, ref) in [(0, 0, 2), (0, 2, 1), (1, 0, 1), (1, 1, 1), (1, 2, 1)].enumerated() {
            doc.paragraphs[i].cell = CellRef(table: "T", row: ref.0, column: ref.1, span: ref.2)
        }
        let data = try DocxFormat.write(doc, pageSetup: .letter)
        let xml = String(decoding: try XCTUnwrap(Zip.read(data).first { $0.name == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:gridSpan w:val=\"2\"/>"))
        XCTAssertEqual(xml.components(separatedBy: "<w:tc>").count - 1, 5)
        let back = try DocxFormat.read(data)
        let ps = back.document.paragraphs
        XCTAssertEqual(ps[0].cell?.span, 2)
        XCTAssertEqual(ps[1].cell?.column, 2)
        XCTAssertEqual(back.document.columnCount(of: ps[0].cell!.table), 3)
    }

    func testDocxVerticalMergeRoundTrip() throws {
        var doc = RichDocument(plainText: "tall\nb\nd\ne\nf\n")
        for (i, ref) in [(0, 0, 1, 2), (0, 1, 1, 1), (1, 1, 1, 1), (2, 0, 1, 1), (2, 1, 1, 1)].enumerated() {
            doc.paragraphs[i].cell = CellRef(table: "T", row: ref.0, column: ref.1, span: ref.2, rowSpan: ref.3)
        }
        let data = try DocxFormat.write(doc, pageSetup: .letter)
        let xml = String(decoding: try XCTUnwrap(Zip.read(data).first { $0.name == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:vMerge w:val=\"restart\"/>"))
        XCTAssertTrue(xml.contains("<w:vMerge/>"))
        XCTAssertEqual(xml.components(separatedBy: "<w:tc>").count - 1, 6)   // 3 rows × 2 cells
        let back = try DocxFormat.read(data)
        let ps = back.document.paragraphs
        XCTAssertEqual(ps.map(\.text), ["tall", "b", "d", "e", "f", ""])
        XCTAssertEqual(ps[0].cell?.rowSpan, 2)
        XCTAssertEqual(ps[2].cell?.row, 1); XCTAssertEqual(ps[2].cell?.column, 1)
    }

    func testDocxColumnsRoundTrip() throws {
        var setup = PageSetup.letter
        setup.columns = 2
        setup.columnGap = 24
        XCTAssertEqual(setup.columnWidth, (setup.contentWidth - 24) / 2, accuracy: 0.001)
        let back = try DocxFormat.read(try DocxFormat.write(RichDocument(plainText: "x"), pageSetup: setup))
        XCTAssertEqual(back.pageSetup?.columns, 2)
        XCTAssertEqual(back.pageSetup?.columnGap ?? 0, 24, accuracy: 0.001)
        // A single column writes no cols element and reads back as one.
        let one = try DocxFormat.read(try DocxFormat.write(RichDocument(plainText: "x"), pageSetup: .letter))
        XCTAssertEqual(one.pageSetup?.columns, 1)
    }

    func testDocxTableEndsTheDocument() throws {
        // A package whose body is just a table still gets a paragraph after it.
        var doc = RichDocument(plainText: "x")
        doc.paragraphs[0].cell = CellRef(table: "T", row: 0, column: 0)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter))
        XCTAssertEqual(back.document.paragraphs.map(\.text), ["x", ""])
        XCTAssertNotNil(back.document.paragraphs[0].cell)
        XCTAssertNil(back.document.paragraphs[1].cell)
    }

    func testARaisedFooterFrameWrappedRoundPartsNoRow() throws {
        // Lab `wr` (Word 16 Mac, zh-9462c6d6's package): its footer's
        // "- N -" frame, auto-sized, wrapped round and raised 15 twips over
        // its anchor, reaches over the bottom margin, and a row of 16pt
        // lines with room for two at the page's foot goes to the next page
        // whole — where without the footer it parts. A frame wrapped
        // "auto" (zh-7654804a's, raised 955 twips) parts its rows.
        func firstPageHoldsRow(wrap: String) throws -> Bool {
            var source = RichDocument(paragraphs: [RichParagraph(text: "a")])
            source.footer = "x"
            var entries = try Zip.read(try DocxFormat.write(source, pageSetup: .a4))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
            func exact(_ text: String, _ twips: Int) -> String {
                "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"\(twips)\" w:lineRule=\"exact\"/></w:pPr><w:r><w:t>\(text)</w:t></w:r></w:p>"
            }
            // (Widow control off, so that only the frame decides.)
            let lines = (1 ... 10).map { exact("row \($0)", 320) }.joined().replacingAll("<w:pPr><w:spacing", with: "<w:pPr><w:widowControl w:val=\"0\"/><w:spacing")
            // (A spacer leaving 120pt over the bottom margin, A4, 851 margins —
            // room for some lines of the row, not all ten, under the footer.)
            let room = 841.9 - 42.55 * 2 - 120
            xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with: exact("spacer", Int((room * 20).rounded()))
                + "<w:tbl><w:tblPr><w:tblW w:w=\"8000\" w:type=\"dxa\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"8000\"/></w:tblGrid>"
                + "<w:tr><w:tc><w:tcPr><w:tcW w:w=\"8000\" w:type=\"dxa\"/></w:tcPr>\(lines)</w:tc></w:tr></w:tbl><w:p/>")
            let margins = try XCTUnwrap(xml.range(of: "<w:pgMar [^>]*/>", options: .regularExpression))
            xml.replaceSubrange(margins, with: "<w:pgMar w:top=\"851\" w:right=\"851\" w:bottom=\"851\" w:left=\"851\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            let fi = try XCTUnwrap(entries.firstIndex { $0.name.hasPrefix("word/footer") })
            var footer = String(decoding: entries[fi].data, as: UTF8.self)
            let fb = try XCTUnwrap(footer.range(of: "<w:p>") ?? footer.range(of: "<w:p "))
            let fe = try XCTUnwrap(footer.range(of: "</w:ftr>"))
            footer.replaceSubrange(fb.lowerBound ..< fe.lowerBound, with:
                "<w:p><w:pPr><w:framePr w:wrap=\"\(wrap)\" w:vAnchor=\"text\" w:hAnchor=\"margin\" w:xAlign=\"center\" w:y=\"-15\"/></w:pPr><w:r><w:t>- 1 -</w:t></w:r></w:p><w:p/>")
            entries[fi] = ZipEntry(name: entries[fi].name, data: Data(footer.utf8))
            let opened = try DocxFormat.read(try Zip.write(entries))
            let doc = opened.document
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let l = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            let setup = opened.pageSetup ?? .a4
            l.pageSetup = setup
            l.width = setup.columnWidth * theme.pixelsPerPoint
            l.ensureLaidOut(doc)
            let row = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("row 1") })
            return l.pieces[0].contains { $0.paragraph == row && $0.part != .rules }
        }
        XCTAssertFalse(try firstPageHoldsRow(wrap: "around"), "the row goes over whole")
        XCTAssertTrue(try firstPageHoldsRow(wrap: "auto"), "it parts under a frame wrapped auto")
    }

    func testDocxHeaderFooterRoundTrip() throws {
        var doc = RichDocument(plainText: "Body")
        doc.header = "Quarterly report"
        doc.footer = "Page {PAGE} of {NUMPAGES}"
        let data = try DocxFormat.write(doc, pageSetup: .letter)
        let back = try DocxFormat.read(data)
        XCTAssertEqual(back.document.header, "Quarterly report")
        XCTAssertEqual(back.document.footer, "Page {PAGE} of {NUMPAGES}")
        XCTAssertEqual(RichDocument.fill(back.document.footer, page: 2, pageCount: 7), "Page 2 of 7")
        let rtf = RtfFormat.render(doc)
        let rtfBack = try XCTUnwrap(RtfFormat.parse(rtf))
        XCTAssertEqual(rtfBack.header, "Quarterly report")
        XCTAssertTrue(rtfBack.footer.contains("{PAGE}"))
        XCTAssertEqual(rtfBack.paragraphs.map(\.text), ["Body"])
    }

    func testDocxListsKeepTheirIdsAndFormats() throws {
        var doc = RichDocument(plainText: "one\ntwo\nbreak\nthree\nfour\nfive")
        for i in [0, 1, 3] {
            doc.paragraphs[i].style.list = .numbered
            doc.paragraphs[i].style.listId = "L"
        }
        doc.paragraphs[3].style.listLevel = 1
        doc.listFormats["L"] = [0: ListLevelFormat(text: "%1)", format: .upperRoman), 1: ListLevelFormat(text: "%1.%2")]
        // Two anonymous runs: separate lists in Word, each starting at 1.
        doc.paragraphs[4].style.list = .numbered
        doc.paragraphs[5].style.list = .numbered
        let data = try DocxFormat.write(doc, pageSetup: .letter)
        let back = try DocxFormat.read(data)
        let ps = back.document.paragraphs
        XCTAssertEqual(ps[0].style.listId, ps[1].style.listId)
        XCTAssertEqual(ps[0].style.listId, ps[3].style.listId)
        XCTAssertNotEqual(ps[0].style.listId, ps[4].style.listId)
        XCTAssertEqual(ps[4].style.listId, ps[5].style.listId)
        let id = try XCTUnwrap(ps[0].style.listId)
        XCTAssertEqual(back.document.listFormats[id]?[0].map { ($0.text, $0.format) }.map { "\($0.0) \($0.1)" }, "%1) upperRoman")
        XCTAssertEqual(RichListNumbering.labels(back.document), ["I)", "II)", nil, "II.1", "1.", "2."])
    }

    func testDocxTableStyleRoundTrip() throws {
        var doc = RichDocument(plainText: "a\nb\nc\nd")
        for (i, (r, col)) in [(0, 0), (0, 1), (1, 0), (1, 1)].enumerated() {
            doc.paragraphs[i].cell = CellRef(table: "T", row: r, column: col)
        }
        doc.tableStyles["T"] = TableStyle(borders: false, headerRow: true)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter))
        let id = try XCTUnwrap(back.document.paragraphs[0].cell?.table)
        // Every table reads back with its cell margins stated — Word's own
        // (0 above and below, 5.4pt at the sides) when the file said nothing.
        // (And set out by that left margin, as Word sets a table that
        // states none of its own.)
        var word = TableStyle(borders: false, headerRow: true, cellMarginTop: 0, cellMarginLeft: 5.4, cellMarginBottom: 0, cellMarginRight: 5.4)
        word.textOutdent = 5.4
        word.textOutdentRight = 5.4
        XCTAssertEqual(back.document.tableStyles[id], word)
        // The default writes bordered, no header.
        doc.tableStyles = [:]
        let plain = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter))
        let plainId = try XCTUnwrap(plain.document.paragraphs[0].cell?.table)
        var plainStyle = TableStyle(cellMarginTop: 0, cellMarginLeft: 5.4, cellMarginBottom: 0, cellMarginRight: 5.4)
        plainStyle.textOutdent = 5.4
        plainStyle.textOutdentRight = 5.4
        XCTAssertEqual(plain.document.tableStyles[plainId], plainStyle)
    }

    func testDocxBulletGlyphsRoundTrip() throws {
        var doc = RichDocument(plainText: "check\narrow")
        for i in 0 ... 1 {
            doc.paragraphs[i].style.list = .bullet
            doc.paragraphs[i].style.listId = "B"
        }
        doc.listFormats["B"] = [0: ListLevelFormat(text: "\u{2713}", format: .bullet)]
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter))
        XCTAssertEqual(RichListNumbering.labels(back.document), ["\u{2713}", "\u{2713}"])
        // Word's own Symbol-font bullet (private-use U+F0B7) reads as a bullet.
        let f = try XCTUnwrap(ListLevelFormat.bulletLibrary.first)
        XCTAssertEqual(f.text, "\u{2022}")
    }

    func testStyleWithNoIdOrTypeIsFoundByName() throws {
        // 60329: `<w:style><w:name w:val="EmptyCellLayoutStyle"/>…` has no
        // styleId and no type, and its 1pt is what every empty cell wears.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a"), RichParagraph(text: "b")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        xml = xml.replacingAll("<w:p><w:pPr><w:spacing w:after=\"160\" w:line=\"259\" w:lineRule=\"auto\"/></w:pPr><w:r><w:t xml:space=\"preserve\">b</w:t>", with: "<w:p><w:pPr><w:pStyle w:val=\"EmptyCellLayoutStyle\"/></w:pPr><w:r><w:t xml:space=\"preserve\">b</w:t>")
        XCTAssertTrue(xml.contains("EmptyCellLayoutStyle"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        styles = styles.replacingAll("</w:styles>", with: "<w:style><w:name w:val=\"EmptyCellLayoutStyle\"/><w:basedOn w:val=\"Normal\"/><w:rPr><w:sz w:val=\"2\"/></w:rPr></w:style></w:styles>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[1].style.named, "EmptyCellLayoutStyle")
        XCTAssertEqual(back.styles["EmptyCellLayoutStyle"]?.char.fontSize, 1)
        XCTAssertNil(back.paragraphs[0].style.named)
    }

    func testListsOverOneDefinitionShareTheirNumbers() throws {
        // zh-64044a1d: heading 3 numbers through its style's list 3, an
        // explicit list 33 over the same definition restarts at 一, and the
        // next style-numbered heading reads 二 in Word, not 三.
        func item(_ t: String, _ id: String) -> RichParagraph {
            var p = RichParagraph(text: t); p.style.list = .numbered; p.style.listId = id; return p
        }
        var doc = RichDocument(paragraphs: [item("a", "3"), item("b", "3"), item("c", "33"), item("d", "3")])
        doc.listCounterOf = ["3": "abstract:23", "33": "abstract:23"]
        doc.listRestarts = ["33": [0: 1]]
        XCTAssertEqual(RichListNumbering.labels(doc), ["1.", "2.", "1.", "2."])
        // Without the shared definition each list counts alone.
        var apart = doc; apart.listCounterOf = [:]; apart.listRestarts = [:]
        XCTAssertEqual(RichListNumbering.labels(apart), ["1.", "2.", "1.", "3."])
        // And a save keeps them one list in the file.
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(RichListNumbering.labels(back), ["1.", "2.", "1.", "2."])
    }

    func testALevelOfNoneShowsNoNumber() {
        // zh-90e0cea8: chapters are "%1%2　" over a level 0 of "none".
        var none = ListLevelFormat(text: "%1"); none.rawFormat = "none"
        XCTAssertEqual(none.number(1), "")
        var p = RichParagraph(text: "范围"); p.style.list = .numbered; p.style.listId = "2"; p.style.listLevel = 1
        var doc = RichDocument(paragraphs: [p])
        doc.listFormats = ["2": [0: none, 1: ListLevelFormat(text: "%1%2\u{3000}")]]
        XCTAssertEqual(RichListNumbering.labels(doc), ["1\u{3000}"])
    }

    func testCustomNumberFormats() throws {
        // POI's Numbering: Word 2010's "α, β, γ, ..." in an mc:Choice.
        var greek = ListLevelFormat(text: "%1."); greek.rawFormat = "custom:α, β, γ, ..."
        XCTAssertEqual((1 ... 19).map { greek.number($0) }.joined(), "αβγδεζηθικλμνξοπρστ")
        var padded = ListLevelFormat(text: "%1"); padded.rawFormat = "custom:001, 002, 003, ..."
        XCTAssertEqual(padded.number(7), "007")
        // And a save writes it back as Word does, so it reads the same.
        var p = RichParagraph(text: "One"); p.style.list = .numbered; p.style.listId = "5"
        var doc = RichDocument(paragraphs: [p])
        doc.listFormats = ["5": [0: greek]]
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(RichListNumbering.labels(back), ["α."])
    }

    func testDocxWrittenByWord() throws {
        // A real Microsoft Word document: BoringCrypto's FIPS security
        // policy (Google; "may be freely reproduced and distributed in its
        // entirety without modification"). 25 pages, 15 tables with merged
        // cells, a table of contents, captions, numbered headings.
        let url = try XCTUnwrap(Bundle.module.url(forResource: "word-boringcrypto", withExtension: "docx", subdirectory: "Fixtures"))
        let back = try DocxFormat.read(try Data(contentsOf: url))
        let doc = back.document
        XCTAssertGreaterThan(doc.paragraphs.count, 800)
        let tables = Set(doc.paragraphs.compactMap { $0.cell?.table })
        XCTAssertEqual(tables.count, 15)
        // The numbered headings carry Word's list, so they count on across
        // the body: 1., 2., 3., then 3.1 for the first Heading 2.
        let labels = RichListNumbering.labels(doc)
        let numbered = doc.paragraphs.indices.filter { doc.paragraphs[$0].style.heading != nil && labels[$0] != nil }
        XCTAssertEqual(numbered.prefix(4).map { labels[$0]! }, ["1.", "2.", "3.", "3.1"])
        XCTAssertEqual(doc.paragraphs[numbered[0]].text, "Introduction")
        XCTAssertEqual(doc.paragraphs[numbered[3]].text, "Cryptographic Boundary")
        // The file's Heading 1 is 16pt, not our 20; the sheet takes its word.
        XCTAssertEqual(doc.styles["Heading1"]?.char.fontSize, 16)
        // And its spacing: Word's Heading 1 has 12pt before and NONE after
        // (a 0 the model once read as "the default 8"); its body has the
        // document defaults, 8pt after and 1.08 lines; a Table Grid cell
        // has no space after and single lines.
        XCTAssertEqual(doc.paragraphs[numbered[0]].style.spaceBefore, 12)
        XCTAssertEqual(doc.paragraphs[numbered[0]].style.spaceAfter, 0)
        let body = try XCTUnwrap(doc.paragraphs.first { $0.cell == nil && $0.style.heading == nil && $0.text.count > 200 })
        XCTAssertEqual(body.style.spaceAfter, 8)
        XCTAssertEqual(body.style.lineSpacing, 259.0 / 240.0, accuracy: 0.001)
        let cell = try XCTUnwrap(doc.paragraphs.first { $0.text == "Operational Environment" })
        XCTAssertNotNil(cell.cell)
        XCTAssertEqual(cell.style.spaceAfter, 0)
        XCTAssertEqual(cell.style.lineSpacing, 1.0)
        XCTAssertEqual(doc.styles["Title"]?.char.fontSize, 18)
        XCTAssertTrue(doc.paragraphs.contains { $0.image != nil })
        XCTAssertTrue(doc.isValid)
        // And it survives our writer.
        let again = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: back.pageSetup ?? .letter))
        XCTAssertEqual(again.document.paragraphs.map(\.text), doc.paragraphs.map(\.text))
        XCTAssertEqual(RichListNumbering.labels(again.document), labels)
        // With its spacing: the writer once gave every cell paragraph the
        // body's 8pt after, and the file came back four pages longer.
        XCTAssertEqual(again.document.paragraphs.map { $0.style.spaceAfter },
                       doc.paragraphs.map { $0.style.spaceAfter })
        XCTAssertEqual(again.document.paragraphs.map { $0.style.lineSpacing },
                       doc.paragraphs.map { $0.style.lineSpacing })
    }

    func testDocxRoundTripKeepsLayout() throws {
        // The saved copy of the Word fixture paginates exactly as the
        // original: same lines, same pages (test/office-layout.sh does
        // the same against the browser). Laid out as the window would,
        // with the shipped faces; without ICU in the test process lines
        // break between characters on both sides alike, so the test
        // holds either way — what it catches is the writer changing
        // what the reader then measures.
        let url = try XCTUnwrap(Bundle.module.url(forResource: "word-boringcrypto", withExtension: "docx", subdirectory: "Fixtures"))
        let back = try DocxFormat.read(try Data(contentsOf: url))
        let setup = back.pageSetup ?? .letter
        let original = OfficeLayoutDump.text(back.document, pageSetup: setup)
        let again = try DocxFormat.read(try DocxFormat.write(back.document, pageSetup: setup))
        let copy = OfficeLayoutDump.text(again.document, pageSetup: again.pageSetup ?? setup)
        XCTAssertTrue(original.hasPrefix("pages "))
        if original != copy {
            let a = original.split(separator: "\n"), b = copy.split(separator: "\n")
            let first = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }
            XCTFail("the saved copy lays out differently: \(a.first ?? "") vs \(b.first ?? ""); first difference at line \(first?.offset ?? min(a.count, b.count)): \(first?.element.0 ?? "") | \(first?.element.1 ?? "")")
        }
    }

    /// A written package with one part's text between two markers swapped
    /// for `with` — the hand-made variants the Word rounds are probed by.
    private func patched(_ doc: RichDocument, part: String, from: String, through: String, with new: String) throws -> Data {
        var entries = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let i = try XCTUnwrap(entries.firstIndex { $0.name == part })
        var xml = String(decoding: entries[i].data, as: UTF8.self)
        let lo = try XCTUnwrap(xml.range(of: from)).lowerBound
        let hi = try XCTUnwrap(xml.range(of: through, range: lo ..< xml.endIndex)).upperBound
        xml.replaceSubrange(lo ..< hi, with: new)
        entries[i] = ZipEntry(name: part, data: Data(xml.utf8))
        return try Zip.write(entries)
    }

    private func part(_ name: String, of doc: RichDocument) throws -> String {
        String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == name }).data, as: UTF8.self)
    }

    func testComplexScriptAndEastAsianFontSlotsKept() throws {
        // rtl.docx: Arabic set in the w:cs face. Written back with the
        // Latin face in every slot, Word substituted another Arabic font
        // and wrapped each paragraph elsewhere (3.4% -> 0.00).
        let defaults = "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Liberation Serif\" w:hAnsi=\"Liberation Serif\" w:eastAsia=\"Noto Serif CJK SC\" w:cs=\"Noto Sans Arabic UI\"/><w:kern w:val=\"2\"/><w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/></w:rPr></w:rPrDefault></w:docDefaults>"
        let data = try patched(RichDocument(paragraphs: [RichParagraph(text: "a")]), part: "word/styles.xml",
                               from: "<w:docDefaults>", through: "</w:docDefaults>", with: defaults)
        let back = try DocxFormat.read(data).document
        let styles = try part("word/styles.xml", of: back)
        XCTAssertTrue(styles.contains("<w:rFonts w:ascii=\"Liberation Serif\" w:hAnsi=\"Liberation Serif\" w:cs=\"Noto Sans Arabic UI\" w:eastAsia=\"Noto Serif CJK SC\"/><w:kern w:val=\"2\"/>"), styles)
    }

    func testOptionalAndNonBreakingHyphensAreElements() throws {
        // bug65649: U+00AD as a character in w:t is no break opportunity
        // to Word; the header cell's word stayed whole and widened its
        // autofit column.
        let doc = RichDocument(paragraphs: [RichParagraph(text: "Техни\u{00AD}ческому a\u{2011}b")])
        let xml = try part("word/document.xml", of: doc)
        XCTAssertTrue(xml.contains("Техни</w:t><w:softHyphen/><w:t xml:space=\"preserve\">ческому a</w:t><w:noBreakHyphen/><w:t xml:space=\"preserve\">b</w:t>"), xml)
        let back = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter)).document
        XCTAssertEqual(back.paragraphs[0].text, "Техни\u{00AD}ческому a\u{2011}b")
    }

    func testHandWrittenPackagesReadAsWordReadsThem() throws {
        // Three of Word's rules for files no word processor wrote:
        // every w:body counts (MultipleBodyBug), a w:t without
        // xml:space="preserve" loses the XML whitespace at its ends
        // (Bug66263-paragraph's runs join) while a no-break space stays,
        // and with no styles part the paragraphs take Word's Normal of the
        // day: 12pt, 8pt after, lines of 1.16.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).lowerBound ..< (try XCTUnwrap(xml.range(of: "</w:body>"))).upperBound
        xml.replaceSubrange(body, with: "<w:body><w:p><w:r><w:t>Before </w:t></w:r><w:r><w:t>\n  After\u{00A0}</w:t></w:r><w:r><w:t xml:space=\"preserve\"> kept </w:t></w:r></w:p></w:body>"
            + "<w:body><w:p><w:r><w:t>Second body</w:t></w:r></w:p></w:body>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        entries.removeAll { $0.name == "word/styles.xml" }
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs.map(\.text), ["BeforeAfter\u{00A0} kept ", "Second body"])
        XCTAssertEqual(back.paragraphs[0].style.spaceAfter, 8)
        XCTAssertEqual(back.paragraphs[0].style.lineSpacing, 278.0 / 240, accuracy: 0.001)
        XCTAssertEqual(back.styles[RichNamedStyle.normalId]?.char.fontSize, 12)
    }

    func testHtmlBlockReferenceKeptWithTheWebSettings() throws {
        // drawing.docx: a paragraph's w:divId names a block of
        // word/webSettings.xml whose margins Word spaces it by.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        let xml = String(decoding: entries[di].data, as: UTF8.self).replacingAll("<w:p><w:pPr>", with: "<w:p><w:pPr><w:divId w:val=\"77\"/>")
        XCTAssertTrue(xml.contains("w:divId"), xml)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let web = "<w:webSettings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:divs><w:div w:id=\"77\"><w:marTop w:val=\"15\"/><w:marBottom w:val=\"75\"/></w:div></w:divs></w:webSettings>"
        // Without the part the reference would dangle, and is dropped.
        let bare = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertFalse(try part("word/document.xml", of: bare).contains("w:divId"))
        entries.append(ZipEntry(name: "word/webSettings.xml", data: Data(web.utf8)))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].style.divId, "77")
        XCTAssertTrue(try part("word/document.xml", of: back).contains("<w:divId w:val=\"77\"/>"))
        XCTAssertEqual(try part("word/webSettings.xml", of: back), web)
        XCTAssertTrue(try part("word/_rels/document.xml.rels", of: back).contains("relationships/webSettings\" Target=\"webSettings.xml\""))
    }

    func testListLevelOverrideReplacesTheDefinitionsLevel() throws {
        // form_footnotes: the list's own w:lvlOverride carries a whole
        // level (a Symbol bullet at 0.25in) over a definition that says
        // only "*"; its three instructions came back starred and deeper.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "item", style: RichParagraphStyle(list: .bullet))]), pageSetup: .letter))
        let ni = try XCTUnwrap(entries.firstIndex { $0.name == "word/numbering.xml" })
        let numbering = "<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + "<w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"*\"/><w:lvlJc w:val=\"left\"/></w:lvl></w:abstractNum>"
            + "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/><w:lvlOverride w:ilvl=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\u{2022}\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"360\" w:hanging=\"360\"/></w:pPr></w:lvl></w:lvlOverride></w:num>"
            + "<w:num w:numId=\"2\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        entries[ni] = ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>a</w:t></w:r></w:p>"
            + "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"2\"/></w:numPr></w:pPr><w:r><w:t>b</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs.map(\.style.list), [.bullet, .numbered])
        let again = try part("word/numbering.xml", of: back)
        XCTAssertTrue(again.contains("<w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\u{2022}\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"360\" w:hanging=\"360\"/>"), again)
        XCTAssertTrue(again.contains("<w:lvlText w:val=\"*\"/>"), again)
    }

    func testLinkTheFileDoesNotUnderlineStaysPlain() throws {
        // bug59058: reference links whose runs name no Hyperlink style.
        // The save names the style, so the run says "none" over it.
        var p = RichParagraph(text: "see 39 and 40")
        p.applyStyle(4 ..< 6) { $0.link = "https://example.com/a" }
        p.applyStyle(11 ..< 13) { $0.link = "https://example.com/b" }
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [p]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let first = try XCTUnwrap(xml.range(of: "<w:rStyle w:val=\"Hyperlink\"/>"))
        xml.replaceSubrange(first, with: "")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let links = back.paragraphs[0].runs.filter { $0.style.link != nil }
        XCTAssertEqual(links.map { $0.style.off.contains(.underline) }, [true, false])
        XCTAssertEqual(links.map(\.style.underline), [false, true])
        let again = try part("word/document.xml", of: back)
        XCTAssertEqual(again.components(separatedBy: "<w:u w:val=\"none\"/>").count, 2, again)
    }

    func testListNumbersWord2010EffectsLeaveTheNumberingPartWellFormed() throws {
        // A level's w:rPr is kept as written; with a w14 text effect in
        // it the saved numbering part named a prefix it never declared.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "item", style: RichParagraphStyle(list: .numbered))]), pageSetup: .letter))
        let ni = try XCTUnwrap(entries.firstIndex { $0.name == "word/numbering.xml" })
        let numbering = "<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\" xmlns:x9=\"urn:x\">"
            + "<w:abstractNum w:abstractNumId=\"0\"><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/><w:lvlJc w:val=\"left\"/>"
            + "<w:rPr><w:b/><w14:shadow w14:blurRad=\"0\"><w14:srgbClr w14:val=\"000000\"/></w14:shadow><x9:odd/></w:rPr></w:lvl></w:abstractNum>"
            + "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
        entries[ni] = ZipEntry(name: "word/numbering.xml", data: Data(numbering.utf8))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: "<w:p><w:pPr><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t>a</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let again = try part("word/numbering.xml", of: back)
        XCTAssertTrue(again.contains("<w14:shadow w14:blurRad=\"0\">"), again)
        XCTAssertFalse(again.contains("x9:"), again)
        XCTAssertNotNil(XNode.parse(Data(again.utf8)))
        let parser = XMLParser(data: Data(again.utf8))
        parser.shouldProcessNamespaces = true
        XCTAssertTrue(parser.parse(), "\(String(describing: parser.parserError))")
    }

    func testStylesPartWithNoParagraphDefaultsIsSpacedByWordsNormal() throws {
        // WPS-written Chinese documents: w:docDefaults holds the fonts and
        // no w:pPrDefault, and Word then spaces by its own Normal (8pt
        // after, lines of 278/240). An empty w:pPrDefault means none.
        func after(_ defaults: String) throws -> (Double, Double) {
            let back = try DocxFormat.read(try patched(RichDocument(paragraphs: [RichParagraph(text: "a")]), part: "word/styles.xml",
                                                       from: "<w:docDefaults>", through: "</w:docDefaults>", with: defaults)).document
            // (The writer spells spacing out on its own paragraph; read the document's Normal.)
            let n = try XCTUnwrap(back.styles[RichNamedStyle.normalId]?.paragraph)
            return (n.spaceAfter, n.lineSpacing)
        }
        let fonts = "<w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Times New Roman\"/></w:rPr></w:rPrDefault>"
        let absent = try after("<w:docDefaults>\(fonts)</w:docDefaults>")
        XCTAssertEqual(absent.0, 8); XCTAssertEqual(absent.1, 278.0 / 240, accuracy: 0.001)
        let empty = try after("<w:docDefaults>\(fonts)<w:pPrDefault/></w:docDefaults>")
        XCTAssertEqual(empty.0, 0); XCTAssertEqual(empty.1, 1.0, accuracy: 0.001)
    }

    func testDefaultTabStopKept() throws {
        // bug65649: 708 twips, not our 720 — its typed numbers are
        // followed by a tab, and every first line moved.
        let doc = RichDocument(paragraphs: [RichParagraph(text: "a")])
        XCTAssertTrue(try part("word/settings.xml", of: doc).contains("<w:defaultTabStop w:val=\"720\"/>"))
        let back = try DocxFormat.read(try patched(doc, part: "word/settings.xml", from: "<w:defaultTabStop", through: "/>",
                                                   with: "<w:defaultTabStop w:val=\"708\"/>")).document
        XCTAssertEqual(back.defaultTabStop, 35.4)
        XCTAssertTrue(try part("word/settings.xml", of: back).contains("<w:defaultTabStop w:val=\"708\"/>"))
    }

    func testStyleWithNoParentStartsFromTheDocumentDefaults() throws {
        // Bug54771b: No Spacing names no w:basedOn, so it never takes
        // Normal's 10pt after and 1.15 lines.
        let styles = "<w:docDefaults><w:pPrDefault/></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:pPr><w:spacing w:after=\"200\" w:line=\"276\" w:lineRule=\"auto\"/></w:pPr></w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"Bare\"><w:name w:val=\"Bare\"/><w:rPr><w:sz w:val=\"22\"/></w:rPr></w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"Hid\"><w:name w:val=\"Hid\"/><w:basedOn w:val=\"Normal\"/><w:rPr><w:vanish/></w:rPr></w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"Child\"><w:name w:val=\"Child\"/><w:basedOn w:val=\"Normal\"/></w:style></w:styles>"
        var entries = try Zip.read(try patched(RichDocument(paragraphs: [RichParagraph(text: "a"), RichParagraph(text: "b")]), part: "word/styles.xml",
                                               from: "<w:docDefaults>", through: "</w:styles>", with: styles))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: "<w:p><w:pPr><w:pStyle w:val=\"Bare\"/></w:pPr><w:r><w:t>a</w:t></w:r></w:p><w:p><w:pPr><w:pStyle w:val=\"Child\"/></w:pPr><w:r><w:t>b</w:t></w:r></w:p>"
            + "<w:tbl><w:tblPr><w:tblpPr w:vertAnchor=\"page\" w:horzAnchor=\"margin\" w:tblpXSpec=\"right\" w:tblpY=\"1475\"/><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblCellSpacing w:w=\"0\" w:type=\"dxa\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"3000\"/></w:tblGrid><w:tr><w:tc><w:p><w:pPr><w:pStyle w:val=\"Bare\"/></w:pPr><w:r><w:t>c</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:pPr><w:pStyle w:val=\"Hid\"/></w:pPr><w:r><w:t>Top of Form</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let ps = back.paragraphs
        XCTAssertEqual(ps[0].style.spaceAfter, 0)
        XCTAssertEqual(ps[0].style.lineSpacing, 1.0)
        XCTAssertEqual(ps[1].style.spaceAfter, 10)
        XCTAssertEqual(ps[1].style.lineSpacing, 1.15, accuracy: 0.001)
        // The same inside a table cell.
        XCTAssertEqual(ps[2].text, "c")
        XCTAssertEqual(ps[2].style.spaceAfter, 0)
        // And the table still floats where the file put it.
        let again = try part("word/document.xml", of: back)
        XCTAssertTrue(again.contains("<w:tblPr><w:tblpPr w:horzAnchor=\"margin\" w:tblpXSpec=\"right\" w:tblpY=\"1475\" w:vertAnchor=\"page\"/>"), again)
        // A cell spacing of zero is stated again (bug57031: Word rules
        // such a table cell by cell), and a style that hides its text
        // still hides it (bug59058's "Top of Form" markers).
        XCTAssertTrue(again.contains("<w:tblCellSpacing w:w=\"0\" w:type=\"dxa\"/>"), again)
        let stylesAgain = try part("word/styles.xml", of: back)
        let hid = try XCTUnwrap(stylesAgain.range(of: "w:styleId=\"Hid\""))
        XCTAssertTrue(stylesAgain[hid.upperBound...].prefix(while: { _ in true }).components(separatedBy: "</w:style>")[0].contains("<w:vanish/>"), stylesAgain)
    }

    func testHeadingsFieldsBreaksAndFramesOfAFileStayAsWordReadsThem() throws {
        // The Chinese government sample's sixth batch (2026-10-12), one
        // document each.
        let styles = "<w:docDefaults><w:pPrDefault/></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:rPr><w:kern w:val=\"2\"/></w:rPr></w:style>"
            // A numbered "heading" every paragraph wears, with no keep.
            + "<w:style w:type=\"paragraph\" w:styleId=\"5\"><w:name w:val=\"heading 5\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:outlineLvl w:val=\"4\"/></w:pPr></w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"Kept\"><w:name w:val=\"Kept\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:keepNext/></w:pPr></w:style>"
            // A style of its own: no kerning, whatever Normal says.
            + "<w:style w:type=\"paragraph\" w:styleId=\"Own\"><w:name w:val=\"Own\"/><w:rPr><w:sz w:val=\"24\"/></w:rPr></w:style>"
            + "<w:style w:type=\"paragraph\" w:styleId=\"Framed\"><w:name w:val=\"Framed\"/><w:basedOn w:val=\"Normal\"/><w:pPr><w:framePr w:w=\"9639\" w:vAnchor=\"page\" w:hAnchor=\"page\" w:y=\"6408\"/></w:pPr></w:style></w:styles>"
        var entries = try Zip.read(try patched(RichDocument(paragraphs: [RichParagraph(text: "a")]), part: "word/styles.xml",
                                               from: "<w:docDefaults>", through: "</w:styles>", with: styles))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: "<w:p><w:pPr><w:pStyle w:val=\"5\"/></w:pPr><w:r><w:t>one</w:t></w:r></w:p>"
            + "<w:p><w:pPr><w:pStyle w:val=\"Kept\"/><w:keepNext w:val=\"0\"/></w:pPr><w:r><w:t>loose</w:t></w:r></w:p>"
            // A contents line: the page number is a field Word refreshes.
            + "<w:p><w:r><w:t>Chapter</w:t></w:r><w:r><w:tab/></w:r><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> PAGEREF _Toc1 \\h </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>6</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>"
            + "<w:p><w:bookmarkStart w:id=\"0\" w:name=\"_Toc1\"/><w:r><w:t>Chapter</w:t></w:r><w:bookmarkEnd w:id=\"0\"/></w:p>"
            // A column break opening a paragraph, in a run of its own size.
            + "<w:p><w:pPr><w:ind w:firstLineChars=\"800\" w:firstLine=\"1920\"/></w:pPr><w:r><w:rPr><w:sz w:val=\"32\"/></w:rPr><w:br w:type=\"column\"/></w:r><w:r><w:t>Outline</w:t></w:r></w:p>"
            // A frame the paragraph only part states, and two lines in one.
            + "<w:p><w:pPr><w:pStyle w:val=\"Framed\"/><w:framePr w:h=\"6974\" w:x=\"1419\"/></w:pPr><w:r><w:rPr><w:eastAsianLayout w:id=\"1\" w:combine=\"1\"/></w:rPr><w:t>Title</w:t></w:r></w:p>"
            + "<w:p><w:pPr><w:pStyle w:val=\"Own\"/></w:pPr><w:r><w:t>body</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs.map(\.text), ["one", "loose", "Chapter\t6", "Chapter", "Outline", "Title", "body"])
        XCTAssertEqual(back.paragraphs[2].runs.last?.style.field, "PAGEREF _Toc1 \\h")
        XCTAssertEqual(back.paragraphs[3].bookmarks, ["_Toc1"])
        XCTAssertTrue(back.paragraphs[4].style.pageBreakBefore && back.paragraphs[4].style.columnBreak)
        let again = try part("word/document.xml", of: back)
        XCTAssertTrue(again.contains("<w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> PAGEREF _Toc1 \\h </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t xml:space=\"preserve\">6</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"), again)
        XCTAssertTrue(again.contains("w:name=\"_Toc1\"/><w:bookmarkEnd"), again)
        XCTAssertTrue(again.contains("<w:r><w:rPr><w:sz w:val=\"32\"/></w:rPr><w:br w:type=\"column\"/></w:r>"), again)
        XCTAssertFalse(again.contains("<w:pageBreakBefore/>"), again)
        XCTAssertTrue(again.contains("<w:framePr w:h=\"6974\" w:hAnchor=\"page\" w:vAnchor=\"page\" w:w=\"9639\" w:x=\"1419\" w:y=\"6408\"/>"), again)
        XCTAssertTrue(again.contains("<w:eastAsianLayout w:combine=\"1\" w:id=\"1\"/>"), again)
        XCTAssertTrue(again.contains("<w:pStyle w:val=\"Kept\"/><w:keepNext w:val=\"0\"/>"), again)
        let stylesAgain = try part("word/styles.xml", of: back)
        func style(_ id: String) throws -> String {
            let at = try XCTUnwrap(stylesAgain.range(of: "w:styleId=\"\(id)\""))
            return String(stylesAgain[at.upperBound...]).components(separatedBy: "</w:style>")[0]
        }
        XCTAssertFalse(try style("Heading5").contains("<w:keepNext/>"), stylesAgain)
        XCTAssertTrue(try style("Kept").contains("<w:keepNext/>"), stylesAgain)
        XCTAssertTrue(try style("Own").contains("<w:kern w:val=\"0\"/>"), stylesAgain)
        XCTAssertFalse(try style("Kept").contains("<w:kern w:val=\"0\"/>"), stylesAgain)
        // Our own headings still keep with what follows.
        var heading = RichParagraph(text: "h"); heading.style.heading = 1
        XCTAssertTrue(try part("word/styles.xml", of: RichDocument(paragraphs: [heading])).contains("<w:keepNext/>"))
    }

    func testBreakCharacterEndingAParagraphGoesBackThere() throws {
        // A paragraph that is only a page break, then a title with space
        // before: Word drops that space after a break character and
        // keeps it under "page break before" (6pt on every chapter page
        // of a training handbook). A column break alone likewise.
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: "<w:p><w:r><w:t>end</w:t></w:r></w:p><w:p><w:r><w:rPr><w:sz w:val=\"32\"/></w:rPr><w:br w:type=\"page\"/></w:r></w:p>"
            + "<w:p><w:pPr><w:spacing w:before=\"120\"/></w:pPr><w:r><w:t>Title</w:t></w:r></w:p>"
            + "<w:p><w:r><w:t>tail</w:t></w:r><w:r><w:br w:type=\"page\"/></w:r></w:p><w:p><w:r><w:t>next</w:t></w:r></w:p>"
            + "<w:p><w:r><w:br w:type=\"column\"/></w:r></w:p><w:p><w:r><w:t>column two</w:t></w:r></w:p>")
        // (And an edge that is no line still holds its space: Word stands
        // the text off a "none" border by it.)
        xml = xml.replacingOccurrences(of: "<w:p><w:r><w:t>end</w:t>", with: "<w:p><w:pPr><w:pBdr><w:top w:val=\"none\" w:color=\"auto\" w:sz=\"0\" w:space=\"1\"/><w:bottom w:val=\"none\" w:sz=\"0\" w:space=\"0\"/></w:pBdr></w:pPr><w:r><w:t>end</w:t>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.paragraphs[0].style.borders?.top?.space, 1)
        XCTAssertNil(back.paragraphs[0].style.borders?.bottom)
        XCTAssertTrue(try part("word/document.xml", of: back).contains("<w:pBdr><w:top w:val=\"none\" w:sz=\"0\" w:space=\"1\" w:color=\"auto\"/></w:pBdr>"))
        XCTAssertEqual(back.paragraphs.map(\.text), ["end", "", "Title", "tail", "next", "", "column two"])
        XCTAssertEqual(back.paragraphs.map(\.style.pageBreakBefore), [false, false, true, false, true, false, true])
        let again = try part("word/document.xml", of: back)
        XCTAssertFalse(again.contains("<w:pageBreakBefore/>"), again)
        XCTAssertTrue(again.contains("<w:r><w:rPr><w:sz w:val=\"32\"/></w:rPr><w:br w:type=\"page\"/></w:r></w:p>"), again)
        XCTAssertTrue(again.contains("tail</w:t></w:r><w:r><w:br w:type=\"page\"/></w:r></w:p>"), again)
        XCTAssertTrue(again.contains("<w:r><w:br w:type=\"column\"/></w:r></w:p>"), again)
        // A page break the editor makes is still the paragraph's own.
        var fresh = RichParagraph(text: "b"); fresh.style.pageBreakBefore = true
        XCTAssertTrue(try part("word/document.xml", of: RichDocument(paragraphs: [RichParagraph(text: "a"), fresh])).contains("<w:pageBreakBefore/>"))
    }

    func testCharacterStylesOfTheFileAreKeptForItsKeptMarkup() throws {
        // A kept footnote names the file's "footnote reference" by the
        // file's id; without the style its mark was full size and each
        // note of a training handbook broke a character early.
        let styles = "<w:docDefaults><w:pPrDefault/></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"a\"><w:name w:val=\"Normal\"/></w:style>"
            + "<w:style w:type=\"character\" w:default=\"1\" w:styleId=\"a0\"><w:name w:val=\"Default Paragraph Font\"/></w:style>"
            + "<w:style w:type=\"character\" w:styleId=\"a5\"><w:name w:val=\"Hyperlink\"/><w:basedOn w:val=\"a0\"/><w:rPr><w:color w:val=\"0000FF\" w:themeColor=\"hyperlink\"/><w:u w:val=\"single\"/></w:rPr></w:style>"
            + "<w:style w:type=\"character\" w:styleId=\"ae\"><w:name w:val=\"footnote reference\"/><w:link w:val=\"zz\"/><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr></w:style></w:styles>"
        var entries = try Zip.read(try patched(RichDocument(paragraphs: [RichParagraph(text: "a")]), part: "word/styles.xml",
                                               from: "<w:docDefaults>", through: "</w:styles>", with: styles))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: "<w:p><w:hyperlink w:anchor=\"there\"><w:r><w:rPr><w:rStyle w:val=\"a5\"/></w:rPr><w:t>link</w:t></w:r></w:hyperlink></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        XCTAssertEqual(back.keptCharacterStyleIds["footnote reference"], "ae")
        let stylesAgain = try part("word/styles.xml", of: back)
        XCTAssertTrue(stylesAgain.contains("<w:style w:styleId=\"ae\" w:type=\"character\"><w:name w:val=\"footnote reference\"/><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr></w:style>"), stylesAgain)
        XCTAssertTrue(stylesAgain.contains("<w:color w:val=\"0000FF\"/>"), stylesAgain)
        XCTAssertFalse(stylesAgain.contains("w:styleId=\"Hyperlink\""), stylesAgain)
        XCTAssertTrue(try part("word/document.xml", of: back).contains("<w:rStyle w:val=\"a5\"/>"))
        // A document of our own still gets ours.
        XCTAssertTrue(try part("word/styles.xml", of: RichDocument(paragraphs: [RichParagraph(text: "a")])).contains("w:styleId=\"Hyperlink\""))
    }

    func testAPositionalTabIsReadByItsPlaceAmongTheTabs() throws {
        let doc = RichDocument(paragraphs: [RichParagraph(text: "a")])
        let body = "<w:p><w:r><w:t>A</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>B</w:t></w:r><w:r><w:ptab w:relativeTo=\"margin\" w:alignment=\"right\" w:leader=\"none\"/></w:r><w:r><w:t>C</w:t></w:r><w:r><w:ptab w:relativeTo=\"margin\" w:alignment=\"center\" w:leader=\"none\"/></w:r></w:p>"
        let back = try DocxFormat.read(try patched(doc, part: "word/document.xml", from: "<w:p>", through: "</w:p>", with: body)).document
        XCTAssertEqual(back.paragraphs[0].text, "A\tB\tC\t")
        XCTAssertEqual(back.paragraphs[0].style.positionalTabs, [1: .right, 2: .center])
    }

    func testFooterThePlainFormCannotSayIsKept() throws {
        // FancyFoot: one line of text, but ruled above, in the heading
        // face, with an alignment tab and an empty paragraph under it.
        var doc = RichDocument(paragraphs: [RichParagraph(text: "a")])
        doc.footer = "x"
        let footer = "<w:p><w:pPr><w:pStyle w:val=\"Footer\"/><w:pBdr><w:top w:val=\"thinThickSmallGap\" w:sz=\"24\" w:space=\"1\" w:color=\"622423\"/></w:pBdr></w:pPr><w:r><w:t>Left</w:t></w:r><w:r><w:ptab w:relativeTo=\"margin\" w:alignment=\"right\" w:leader=\"none\"/></w:r><w:r><w:t>Right</w:t></w:r></w:p>"
        // (The last: a footer set at the left margin — headerFooter's.)
        for variant in [footer, "<w:p><w:r><w:t>Left</w:t></w:r></w:p><w:p/>", "<w:p><w:pPr><w:pStyle w:val=\"Footer\"/></w:pPr><w:r><w:t>Left</w:t></w:r></w:p>"] {
            var back = try DocxFormat.read(try patched(doc, part: "word/footer1.xml", from: "<w:p>", through: "</w:p>", with: variant)).document
            XCTAssertEqual(back.keptHeaderFooters.count, 1, variant)
            XCTAssertTrue(try part(back.keptHeaderFooters[0].part, of: back).contains(variant), variant)
            // Edited in the app, the kept part steps aside for the text.
            back.footer = "edited"
            let again = try DocxFormat.read(try DocxFormat.write(back, pageSetup: .letter)).document
            XCTAssertEqual(again.footer, "edited", variant)
        }
    }

    func testDocxWrittenByTextEdit() throws {
        // apps/OfficeApp/Tests/OfficeAppTests/Fixtures/textedit.docx: the
        // Phase 0 document, saved as RTF by Office and converted by macOS
        // `textutil -convert docx` — a package written by someone else.
        let url = try XCTUnwrap(Bundle.module.url(forResource: "textedit", withExtension: "docx", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: url)
        let back = try DocxFormat.read(data)
        let ps = back.document.paragraphs
        XCTAssertGreaterThan(ps.count, 20)
        XCTAssertEqual(ps[0].text, "Office — Phase 0 performance document")
        XCTAssertTrue(ps[0].runs[0].style.bold)
        XCTAssertEqual(ps[0].runs[0].style.fontSize, 20)
        XCTAssertEqual(ps[0].runs[0].style.color, Color(0xFF2F5496))
        XCTAssertTrue(ps[1].text.hasPrefix("3 pages, generated."))
        // A body paragraph with a bold lead and an italic word keeps both.
        let body = try XCTUnwrap(ps.first { $0.runs.count >= 3 && $0.runs[0].style.bold && !$0.runs[1].style.bold })
        XCTAssertTrue(body.runs.contains { $0.style.italic })
        XCTAssertNotNil(back.pageSetup)
    }

    /// An embedded font part: its first 32 bytes XORed with the
    /// `w:fontKey` GUID's 16 bytes, read from the GUID's last hex pair to
    /// its first (ECMA-376 part 1, 17.8.1) — the order that turned all six
    /// of zh-e37f8d40's parts back into TrueType (`00 01 00 00`).
    func testEmbeddedFontPartIsDeobfuscatedByItsKey() throws {
        let key = "{01014A78-CABC-4EF0-12AC-5CD89AEFDE01}"
        let out = try XCTUnwrap(OfficeFonts.deobfuscate(Data(count: 40), key: key))
        let expected: [UInt8] = [0x01, 0xDE, 0xEF, 0x9A, 0xD8, 0x5C, 0xAC, 0x12, 0xF0, 0x4E, 0xBC, 0xCA, 0x78, 0x4A, 0x01, 0x01]
        XCTAssertEqual(Array(out.prefix(16)), expected)
        XCTAssertEqual(Array(out[16 ..< 32]), expected)
        XCTAssertEqual(Array(out.suffix(8)), [UInt8](repeating: 0, count: 8), "only the first 32 bytes are keyed")
        XCTAssertNil(OfficeFonts.deobfuscate(Data(count: 40), key: "{not-a-guid}"))
    }
}

/// Records, for each quarter turn, the translate just before it (a
/// turned cell's corner, in the flow's terms).
/// Records the height of each paragraph drawn.
private final class ParagraphHeightCanvas: Canvas {
    var heights: [Double] = []
    func save() {}
    func saveLayer(_ bounds: Rect?, _ paint: Paint) {}
    func restore() {}
    func restoreToCount(_ count: Int) {}
    func getSaveCount() -> Int { 1 }
    func translate(_ dx: Double, _ dy: Double) {}
    func scale(_ sx: Double, _ sy: Double?) {}
    func rotate(_ radians: Double) {}
    func skew(_ sx: Double, _ sy: Double) {}
    func transform(_ matrix4: [Double]) {}
    func getTransform() -> [Double] { [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] }
    func clipRect(_ rect: Rect, clipOp: ClipOp, doAntiAlias: Bool) {}
    func clipRRect(_ rrect: RRect, doAntiAlias: Bool) {}
    func clipRSuperellipse(_ rsuperellipse: RSuperellipse, doAntiAlias: Bool) {}
    func clipPath(_ path: Path, doAntiAlias: Bool) {}
    func getLocalClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func getDestinationClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func drawColor(_ color: Color, _ blendMode: BlendMode) {}
    func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) {}
    func drawPaint(_ paint: Paint) {}
    func drawRect(_ rect: Rect, _ paint: Paint) {}
    func drawRRect(_ rrect: RRect, _ paint: Paint) {}
    func drawDRRect(_ outer: RRect, _ inner: RRect, _ paint: Paint) {}
    func drawRSuperellipse(_ rsuperellipse: RSuperellipse, _ paint: Paint) {}
    func drawOval(_ rect: Rect, _ paint: Paint) {}
    func drawCircle(_ c: Offset, _ radius: Double, _ paint: Paint) {}
    func drawArc(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint) {}
    func drawPath(_ path: Path, _ paint: Paint) {}
    func drawImage(_ image: Image, _ offset: Offset, _ paint: Paint) {}
    func drawImageRect(_ image: Image, _ src: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawImageNine(_ image: Image, _ center: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawPicture(_ picture: any FlutterSwiftBridge.Picture) {}
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) { heights.append(paragraph.height) }
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}

private final class TurnedTextCanvas: Canvas {
    var turns: [Double] = []
    private var lastDy = 0.0
    func save() {}
    func saveLayer(_ bounds: Rect?, _ paint: Paint) {}
    func restore() {}
    func restoreToCount(_ count: Int) {}
    func getSaveCount() -> Int { 1 }
    func translate(_ dx: Double, _ dy: Double) { lastDy = dy }
    func scale(_ sx: Double, _ sy: Double?) {}
    func rotate(_ radians: Double) { turns.append(lastDy) }
    func skew(_ sx: Double, _ sy: Double) {}
    func transform(_ matrix4: [Double]) {}
    func getTransform() -> [Double] { [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] }
    func clipRect(_ rect: Rect, clipOp: ClipOp, doAntiAlias: Bool) {}
    func clipRRect(_ rrect: RRect, doAntiAlias: Bool) {}
    func clipRSuperellipse(_ rsuperellipse: RSuperellipse, doAntiAlias: Bool) {}
    func clipPath(_ path: Path, doAntiAlias: Bool) {}
    func getLocalClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func getDestinationClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func drawColor(_ color: Color, _ blendMode: BlendMode) {}
    func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) {}
    func drawPaint(_ paint: Paint) {}
    func drawRect(_ rect: Rect, _ paint: Paint) {}
    func drawRRect(_ rrect: RRect, _ paint: Paint) {}
    func drawDRRect(_ outer: RRect, _ inner: RRect, _ paint: Paint) {}
    func drawRSuperellipse(_ rsuperellipse: RSuperellipse, _ paint: Paint) {}
    func drawOval(_ rect: Rect, _ paint: Paint) {}
    func drawCircle(_ c: Offset, _ radius: Double, _ paint: Paint) {}
    func drawArc(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint) {}
    func drawPath(_ path: Path, _ paint: Paint) {}
    func drawImage(_ image: Image, _ offset: Offset, _ paint: Paint) {}
    func drawImageRect(_ image: Image, _ src: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawImageNine(_ image: Image, _ center: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawPicture(_ picture: any FlutterSwiftBridge.Picture) {}
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) {}
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}
