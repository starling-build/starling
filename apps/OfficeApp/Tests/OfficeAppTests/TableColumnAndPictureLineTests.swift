// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class TableColumnAndPictureLineTests: XCTestCase {    /// Rows that state different widths for a column give that column its widest stated width (es-e3d5fed41c).
    func testAColumnTakesTheWidestWidthTheRowsState() throws {
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let cell = { (w: Int) in "<w:tc><w:tcPr><w:tcW w:w=\"\(w)\" w:type=\"dxa\"/></w:tcPr><w:p><w:r><w:t>cell</w:t></w:r></w:p></w:tc>" }
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
            "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/></w:tblPr><w:tblGrid><w:gridCol w:w=\"4000\"/><w:gridCol w:w=\"4000\"/></w:tblGrid><w:tr>\(cell(7000))\(cell(1000))</w:tr><w:tr>\(cell(2000))\(cell(1000))</w:tr></w:tbl><w:p/>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        var doc = try DocxFormat.read(try Zip.write(entries)).document
        doc.compatibilityMode = 12
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = 468 * 96.0 / 72.0
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        layout.ensureLaidOut(doc)
        let cells = doc.paragraphs.indices.filter { doc.paragraphs[$0].cell != nil }
        let x0 = layout.geometry(cells[0]).textLeft, x1 = layout.geometry(cells[1]).textLeft
        XCTAssertGreaterThan(x1 - x0, 5 * 96.0 / 72.0 * 40, "column 0 is much wider than column 1 (\(x1 - x0) px)")
    }

    /// A picture alone whose run names a face but no size: the multiple's extra is that run's own line, not the paragraph mark's
    /// (es-3b20b19c25 p5, lab picln: Arial 12 bold mark, line 480, the note 12.6pt under the picture, the 11pt line, not 13.8).
    func testAPictureRunNamingOnlyAFaceTakesTheMultipleOfItsOwnLine() throws {
        func heightOfPictureBlock(markHalfPoints: Int) throws -> Double {
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
            var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(image: ImageAttachment(data: png, width: 10, height: 10))]), pageSetup: .letter))
            let di = entries.firstIndex { $0.name == "word/document.xml" }!
            var xml = String(decoding: entries[di].data, as: UTF8.self)
            let embed = try XCTUnwrap(xml.range(of: #"r:embed="[^"]+""#, options: .regularExpression))
            let rid = String(xml[embed])
            let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
            let picture = "<w:r><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\"/></w:rPr><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"1270000\" cy=\"1270000\"/>"
                + "<wp:docPr id=\"14\" name=\"p\"/><a:graphic xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\">"
                + "<a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><pic:pic xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\">"
                + "<pic:blipFill><a:blip \(rid)/></pic:blipFill></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>"
            xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with:
                "<w:p><w:pPr><w:spacing w:line=\"480\" w:lineRule=\"auto\"/><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\"/><w:sz w:val=\"\(markHalfPoints)\"/></w:rPr></w:pPr>\(picture)</w:p><w:p><w:r><w:t>after</w:t></w:r></w:p>")
            entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
            var doc = try DocxFormat.read(try Zip.write(entries)).document
            doc.compatibilityMode = 15
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
            theme.wordRules = true
            let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
            layout.pageSetup = .letter
            layout.width = 468 * 96.0 / 72.0
            let was = RichTextTheme.wordWindowsPages
            RichTextTheme.wordWindowsPages = true
            defer { RichTextTheme.wordWindowsPages = was }
            layout.ensureLaidOut(doc)
            return layout.geometry(1).top
        }
        let small = try heightOfPictureBlock(markHalfPoints: 22), large = try heightOfPictureBlock(markHalfPoints: 48)
        XCTAssertEqual(small, large, accuracy: 0.01, "the mark's size does not set the extra under a picture whose run names a face")
    }
}
