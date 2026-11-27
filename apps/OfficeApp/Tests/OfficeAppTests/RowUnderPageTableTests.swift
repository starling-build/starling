// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
import Flutter
@testable import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class RowUnderPageTableTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func row(_ text: String) -> String {
        "<w:tr><w:trPr><w:trHeight w:val=\"600\" w:hRule=\"exact\"/></w:trPr><w:tc><w:tcPr><w:tcW w:w=\"6000\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:tc></w:tr>"
    }

    /// A row of a table in the flow that would run into a table placed against the page, across
    /// the same width, starts under it (Word's print of dx2 c2c3a2f3 p10: rows 2 and 3 of a
    /// 701pt table stand under the centred 602pt table placed at 319.6 to 453.2, row 1 above it).
    func testARowThatMeetsAPagePlacedTableStartsUnderIt() throws {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        var entries = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let index = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        let grid = "<w:tblW w:w=\"6000\" w:type=\"dxa\"/><w:jc w:val=\"center\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"6000\"/></w:tblGrid>"
        var body = "<w:tbl><w:tblPr><w:tblpPr w:leftFromText=\"180\" w:rightFromText=\"180\" w:vertAnchor=\"page\" w:horzAnchor=\"margin\" w:tblpXSpec=\"center\" w:tblpY=\"2600\"/>"
            + grid + row("F1") + row("F2") + "</w:tbl>"
        body += "<w:p/><w:tbl><w:tblPr>" + grid + row("A1") + row("A2") + row("A3") + "</w:tbl><w:p/>"
        body += "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\"/></w:sectPr>"
        entries[index] = ZipEntry(name: "word/document.xml", data: Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(body)</w:body></w:document>".utf8))
        let loaded = try DocxFormat.read(Zip.write(entries))
        var doc = loaded.document
        doc.readFromFile = true
        let setup = try XCTUnwrap(loaded.pageSetup)
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = setup
        layout.width = setup.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let ppp = theme.pixelsPerPoint
        func top(_ text: String) throws -> Double {
            let k = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text == text }, text)
            return try XCTUnwrap(layout.pieces[0].first { $0.paragraph == k }, text).pageY / ppp
        }
        let f1 = try top("F1"), f2 = try top("F2"), a1 = try top("A1"), a2 = try top("A2"), a3 = try top("A3")
        XCTAssertEqual(f2 - f1, 30, accuracy: 0.5)
        // Row 1 ends above the placed table and stays; rows 2 and 3 go under its foot (F2's row + 30pt).
        XCTAssertLessThan(a1 + 30, f1 + 0.5)
        XCTAssertGreaterThan(a2, f2 + 30 - 0.5, "row 2 must start under the placed table")
        XCTAssertEqual(a3 - a2, 30, accuracy: 0.5)
    }
}
