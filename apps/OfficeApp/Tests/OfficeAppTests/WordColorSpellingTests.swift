import XCTest
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// A .docx may write a colour as "#013785" or by name ("white"); Word's print
/// takes both (es-e3d5fed41c: white table borders and header text on a
/// "#013785" fill). Read as bare hex they fell to auto and drew black.
final class WordColorSpellingTests: XCTestCase {
    func testSpellings() {
        XCTAssertEqual(RichLayout.wordColor("013785"), Color(0xFF013785))
        XCTAssertEqual(RichLayout.wordColor("#013785"), Color(0xFF013785))
        XCTAssertEqual(RichLayout.wordColor("white"), Color(0xFFFFFFFF))
        XCTAssertEqual(RichLayout.wordColor("darkBlue"), Color(0xFF000080))
        XCTAssertNil(RichLayout.wordColor("auto"))
        XCTAssertNil(RichLayout.wordColor("white", names: false))
        XCTAssertNil(RichLayout.wordColor("#000"))
    }

    func testTableReadsHashAndNamedColours() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: """
        <w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid><w:gridCol w:w="2000"/><w:gridCol w:w="2000"/></w:tblGrid>\
        <w:tr><w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/><w:tcBorders><w:right w:val="single" w:sz="6" w:color="white"/></w:tcBorders>\
        <w:shd w:val="clear" w:color="auto" w:fill="#013785"/></w:tcPr><w:p><w:r><w:rPr><w:color w:val="white"/></w:rPr><w:t>head</w:t></w:r></w:p></w:tc>\
        <w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/></w:tcPr><w:p><w:r><w:rPr><w:color w:val="#fd8301"/></w:rPr><w:t>b</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/>
        """)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let head = try XCTUnwrap(doc.paragraphs.first { $0.text == "head" })
        XCTAssertEqual(head.cell?.fill, Color(0xFF013785))
        XCTAssertEqual(head.runs.first?.style.color, Color(0xFFFFFFFF))
        XCTAssertEqual(RichLayout._cellSideColor(head.cell?.bordersXML, "right"), Color(0xFFFFFFFF))
        let b = try XCTUnwrap(doc.paragraphs.first { $0.text == "b" })
        XCTAssertEqual(b.runs.first?.style.color, Color(0xFFFD8301))
    }
}
