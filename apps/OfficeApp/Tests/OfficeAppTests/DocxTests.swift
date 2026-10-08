// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class DocxTests: XCTestCase {
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
        entries[i] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let back = try DocxFormat.read(try Zip.write(entries)).document
        let ts = try XCTUnwrap(back.tableStyles.values.first)
        XCTAssertTrue(ts.borders)
        XCTAssertEqual(ts.borderColor, Color(0xFFE1E1E1))
        XCTAssertEqual([ts.cellMarginTop, ts.cellMarginLeft, ts.cellMarginBottom, ts.cellMarginRight], [3.6, 3.6, 3.6, 3.6])
        let saved = String(decoding: try Zip.read(try DocxFormat.write(back, pageSetup: .letter)).first { $0.name == "word/document.xml" }!.data, as: UTF8.self)
        XCTAssertTrue(saved.contains("<w:top w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"E1E1E1\"/>"), saved)
        XCTAssertTrue(saved.contains("<w:tblCellMar><w:top w:w=\"72\" w:type=\"dxa\"/>"), saved)
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
        XCTAssertEqual(back.document.listFormats[id]?[0], ListLevelFormat(text: "%1)", format: .upperRoman))
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
        let word = TableStyle(borders: false, headerRow: true, cellMarginTop: 0, cellMarginLeft: 5.4, cellMarginBottom: 0, cellMarginRight: 5.4)
        XCTAssertEqual(back.document.tableStyles[id], word)
        // The default writes bordered, no header.
        doc.tableStyles = [:]
        let plain = try DocxFormat.read(try DocxFormat.write(doc, pageSetup: .letter))
        let plainId = try XCTUnwrap(plain.document.paragraphs[0].cell?.table)
        XCTAssertEqual(plain.document.tableStyles[plainId], TableStyle(cellMarginTop: 0, cellMarginLeft: 5.4, cellMarginBottom: 0, cellMarginRight: 5.4))
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
}
