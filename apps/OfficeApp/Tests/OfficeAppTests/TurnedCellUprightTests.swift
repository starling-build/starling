import XCTest
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// Plain tbRl turns a cell's ideographs with its Latin, a quarter turn; only the vertical
/// values (tbRlV, tbLrV) stand them upright. Lab turnpad3: Word's print of 职业资格 in
/// SimSun, a tbRl cell beside a tbRlV one, every vertical alignment.
final class TurnedCellUprightTests: XCTestCase {
    private func cell(_ direction: String) throws -> RichParagraph {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: """
        <w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid><w:gridCol w:w="1440"/></w:tblGrid>\
        <w:tr><w:trPr><w:trHeight w:val="2400" w:hRule="exact"/></w:trPr>\
        <w:tc><w:tcPr><w:tcW w:w="1440" w:type="dxa"/><w:textDirection w:val="\(direction)"/></w:tcPr>\
        <w:p><w:r><w:rPr><w:rFonts w:eastAsia="SimSun"/></w:rPr><w:t>职业资格</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/>
        """)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        return try XCTUnwrap(doc.paragraphs.first { $0.text == "职业资格" })
    }

    func testOnlyVerticalDirectionsStandIdeographsUpright() throws {
        for direction in ["tbRl", "tbRlV", "tbLrV"] {
            XCTAssertEqual(try cell(direction).cell?.textDirection, .down, direction)
        }
        XCTAssertNotEqual(try cell("tbRl").cell?.uprightIdeographs, true)
        XCTAssertEqual(try cell("tbRlV").cell?.uprightIdeographs, true)
        XCTAssertEqual(try cell("tbLrV").cell?.uprightIdeographs, true)
    }

    /// The value as written is kept for the save, whichever way the ideographs stand.
    func testTheWrittenDirectionIsKept() throws {
        XCTAssertEqual(try cell("tbRl").cell?.textDirectionValue, "tbRl")
        XCTAssertEqual(try cell("tbRlV").cell?.textDirectionValue, "tbRlV")
    }
}
