import XCTest
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// A cell that reads down (tbRl) keeps its left margin in a document in Word 2013's mode
/// (compatibilityMode 15): centred, it stands midway between both margins (dx2 b3b6b12d,
/// lab turnpad2: ours stood 2.7pt left of Word's); at the bottom, the margin off the left
/// rule (lab turnpad3); at the top it does not move. Older modes leave the left margin out
/// (zh-b0401810, lab turnpad).
final class TurnedCellCentringTests: XCTestCase {
    private func across(compat: Int?, align: String = "center") throws -> Double {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: """
        <w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>\
        <w:tblGrid><w:gridCol w:w="1440"/></w:tblGrid><w:tr><w:trPr><w:trHeight w:val="2400" w:hRule="exact"/></w:trPr>\
        <w:tc><w:tcPr><w:tcW w:w="1440" w:type="dxa"/><w:textDirection w:val="tbRl"/><w:vAlign w:val="\(align)"/></w:tcPr>\
        <w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:t>turned</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/>
        """)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        var doc = try DocxFormat.read(try Zip.write(entries)).document
        doc.compatibilityMode = compat
        doc.readFromFile = true
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = PageSetup.letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == "turned" })
        let g = try XCTUnwrap(layout._cells[i])
        return g.across / theme.pixelsPerPoint
    }

    func testWord2013ModeCentresBetweenBothMargins() throws {
        let modern = try across(compat: 15), old = try across(compat: 14), none = try across(compat: nil)
        // `across` counts from the cell's right side: the old mode stands the line half the
        // 108-twip (5.4pt) left margin further from it.
        XCTAssertEqual(old - modern, 2.7, accuracy: 0.6)
        XCTAssertEqual(none, old, accuracy: 0.01)
    }

    func testWord2013ModeKeepsTheLeftMarginAtTheBottomAndLeavesTheTop() throws {
        XCTAssertEqual(try across(compat: 14, align: "bottom") - (try across(compat: 15, align: "bottom")), 5.4, accuracy: 0.6)
        XCTAssertEqual(try across(compat: 15, align: "top"), try across(compat: 14, align: "top"), accuracy: 0.01)
    }
}
