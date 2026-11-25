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
}
