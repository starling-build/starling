// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// A table stating its own 108-twip cell margins in a file with no default table style (no styles part, or one that names
/// no Normal Table) is not set out by them: Word for Windows puts its left rule on the page's margin and its text 5.4 pt in.
/// A styles part naming Normal Table sets it out, rule 5.4 pt left of the margin. Lab nosetb (no settings part, or one
/// without a mode): rules at 71.78 / 71.78 / 71.78 against 66.38 with Normal Table.
final class NoDefaultTableStyleOutdentTests: XCTestCase {
    private func outdent(styles: String?, ind: String = "") throws -> Double {
        let was = DocxFormat.wordOnWindows
        DocxFormat.wordOnWindows = true
        defer { DocxFormat.wordOnWindows = was }
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: """
        <w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>\(ind)<w:tblBorders><w:left w:val="single" w:sz="4" w:space="0" w:color="000000"/></w:tblBorders>\
        <w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr>\
        <w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid><w:tr><w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/></w:tcPr><w:p><w:r><w:t>cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/>
        """)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        if let styles {
            for k in entries.indices where entries[k].name == "word/styles.xml" { entries[k] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8)) }
        } else {
            entries.removeAll { $0.name == "word/styles.xml" }
        }
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        return try XCTUnwrap(doc.tableStyles.values.first).textOutdent
    }

    private let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""

    func testNoDefaultTableStyleLeavesTheTableOnTheMargin() throws {
        XCTAssertEqual(try outdent(styles: nil), 0, accuracy: 0.01)
        XCTAssertEqual(try outdent(styles: "<w:styles \(ns)><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val=\"22\"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>"), 0, accuracy: 0.01)
    }

    /// A table stating its own indent is measured to its text as ever: lo-b7c1b8df's tblInd 124 table, text at Word's 89.1.
    func testOwnIndentIsStillSetOut() throws {
        XCTAssertEqual(try outdent(styles: nil, ind: "<w:tblInd w:w=\"124\" w:type=\"dxa\"/>"), 5.4, accuracy: 0.01)
    }

    func testNormalTableSetsItOutByItsMargin() throws {
        let normal = "<w:styles \(ns)><w:style w:type=\"table\" w:default=\"1\" w:styleId=\"TableNormal\"><w:name w:val=\"Normal Table\"/><w:tblPr><w:tblInd w:w=\"0\" w:type=\"dxa\"/>"
            + "<w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/><w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"108\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr></w:style></w:styles>"
        XCTAssertEqual(try outdent(styles: normal), 5.4, accuracy: 0.01)
    }
}
