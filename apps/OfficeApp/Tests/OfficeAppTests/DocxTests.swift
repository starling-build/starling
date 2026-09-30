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
        XCTAssertEqual(back.document.styles["Code"]?.char.fontFamily, OfficeFonts.mono)
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
