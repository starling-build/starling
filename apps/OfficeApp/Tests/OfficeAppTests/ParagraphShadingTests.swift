import XCTest
@testable import OfficeApp
@testable import OfficeText

final class ParagraphShadingTests: XCTestCase {
    /// A paragraph's shading keeps its pattern and its theme link through a plain open and save.
    func testParagraphShadingKeepsPatternAndThemeLink() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: """
        <w:p><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="FFFF00" w:themeFill="accent4" w:themeFillTint="33"/></w:pPr><w:r><w:t>theme</w:t></w:r></w:p>\
        <w:p><w:pPr><w:shd w:val="pct10" w:color="FF0000" w:fill="DDDDDD"/></w:pPr><w:r><w:t>pattern</w:t></w:r></w:p>
        """)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let out = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(out.containsSubstring("w:themeFill=\"accent4\""), out)
        XCTAssertTrue(out.containsSubstring("w:themeFillTint=\"33\""))
        XCTAssertTrue(out.containsSubstring("w:val=\"pct10\""))
        XCTAssertTrue(out.containsSubstring("w:color=\"FF0000\""))
    }

    func testMarkAndAutoPatternShadingSurvive() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: """
        <w:p><w:pPr><w:rPr><w:shd w:val="clear" w:color="auto" w:fill="FFFFFF"/></w:rPr></w:pPr><w:r><w:t>mark white</w:t></w:r></w:p>\
        <w:p><w:pPr><w:rPr><w:shd w:val="clear" w:color="auto" w:fill="FFFF00"/></w:rPr></w:pPr></w:p>\
        <w:p><w:pPr><w:shd w:val="pct10" w:color="FF0000" w:fill="auto"/></w:pPr><w:r><w:t>pct auto</w:t></w:r></w:p>
        """)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let out = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertEqual(out.components(separatedBy: "<w:shd ").count - 1, 3, out)
        XCTAssertTrue(out.containsSubstring("w:val=\"pct10\""), out)
    }

    func testCellShadedAutoStaysShadedAuto() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: """
        <w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="auto"/></w:tcPr><w:p><w:r><w:t>x</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/>
        """)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let out = String(decoding: try XCTUnwrap(try Zip.read(try DocxFormat.write(doc, pageSetup: .letter)).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        XCTAssertTrue(out.containsSubstring("w:fill=\"auto\""), out)
    }
}
