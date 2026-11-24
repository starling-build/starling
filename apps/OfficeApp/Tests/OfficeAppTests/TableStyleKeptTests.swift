// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// W-P0-4 (named table styles): a table that names a style in the file still names it after a save, with its look flags, and the
/// style's definition (its conditional parts) is written back; a table that named none still names none.
final class TableStyleKeptTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func part(_ entries: [ZipEntry], _ name: String) -> String {
        String(decoding: entries.first { $0.name == name }!.data, as: UTF8.self)
    }

    func testANamedTableStyleAndItsLookSurviveASave() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        let si = entries.firstIndex { $0.name == "word/styles.xml" }!
        var styles = String(decoding: entries[si].data, as: UTF8.self)
        let def = "<w:style w:type=\"table\" w:styleId=\"MyGrid\"><w:name w:val=\"My Grid\"/><w:basedOn w:val=\"TableNormal\"/>"
            + "<w:tblPr><w:tblBorders><w:top w:val=\"single\" w:sz=\"8\" w:space=\"0\" w:color=\"FF0000\"/></w:tblBorders></w:tblPr>"
            + "<w:tblStylePr w:type=\"firstRow\"><w:rPr><w:b/></w:rPr><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"DDDDDD\"/></w:tcPr></w:tblStylePr></w:style>"
        styles = styles.replacingAll("</w:styles>", with: def + "</w:styles>")
        entries[si] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>"))
        let sect = try XCTUnwrap(xml.range(of: "<w:sectPr", options: .backwards))
        func table(_ pr: String, _ text: String) -> String {
            "<w:tbl><w:tblPr>\(pr)<w:tblW w:w=\"4000\" w:type=\"dxa\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/></w:tblGrid>"
                + "<w:tr><w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/>"
        }
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound,
                            with: table("<w:tblStyle w:val=\"MyGrid\"/>", "styled") + table("", "plain"))
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        // (The look is stated after the width, as Word writes it.)
        var withLook = String(decoding: entries[di].data, as: UTF8.self)
        withLook = withLook.replacingAll("<w:tblW w:w=\"4000\" w:type=\"dxa\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>styled",
                                         with: "<w:tblW w:w=\"4000\" w:type=\"dxa\"/><w:tblLook w:val=\"0420\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"0\" w:lastColumn=\"0\" w:noHBand=\"0\" w:noVBand=\"1\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w=\"4000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>styled")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(withLook.utf8))

        let doc = try DocxFormat.read(try Zip.write(entries)).document
        let saved = try Zip.read(try DocxFormat.write(doc, pageSetup: .letter))
        let out = part(saved, "word/document.xml")
        XCTAssertTrue(out.containsSubstring("<w:tblStyle w:val=\"MyGrid\"/>"), "the table still names its style")
        XCTAssertTrue(out.containsSubstring("w:val=\"0420\"") && out.containsSubstring("w:noVBand=\"1\""), "and its look flags, not the fixed default")
        XCTAssertEqual(out.components(separatedBy: "<w:tblStyle ").count - 1, 1, "the plain table names none")
        let style = part(saved, "word/styles.xml")
        XCTAssertTrue(style.containsSubstring("w:styleId=\"MyGrid\"") && style.containsSubstring("w:type=\"firstRow\"") && style.containsSubstring("DDDDDD"),
                      "the style's definition, conditional part included, is written back")
        // And it reads again as it did.
        let again = try DocxFormat.read(try Zip.write(saved)).document
        XCTAssertEqual(again.paragraphs.map(\.text).filter { !$0.isEmpty }, ["styled", "plain"])
        XCTAssertEqual(Set(again.tableStyleIds.values), ["MyGrid"])
    }
}
