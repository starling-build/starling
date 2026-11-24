// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import OfficeText
@testable import OfficeApp

/// W-P0-4 (character part): a save keeps the underline kind and colour, double strike, and the
/// text effects the model cannot draw, and the neighbouring properties of the same run.
final class CharacterSaveKeepsTests: XCTestCase {
    private func fixture(_ runs: String) throws -> RichDocument {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let i = try XCTUnwrap(parts.firstIndex { $0.name == "word/document.xml" })
        parts[i] = ZipEntry(name: "word/document.xml", data: Data((
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\"><w:body><w:p>"
            + runs + "</w:p></w:body></w:document>").utf8))
        return try DocxFormat.read(Zip.write(parts)).document
    }

    private func roundTrip(_ doc: RichDocument) throws -> (RichDocument, String) {
        let bytes = try DocxFormat.write(doc, pageSetup: .letter)
        let xml = String(decoding: try XCTUnwrap(Zip.read(bytes).first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        return (try DocxFormat.read(bytes).document, xml)
    }

    func testUnderlineKindColourAndDoubleStrikeSurviveSave() throws {
        let doc = try fixture("""
            <w:r><w:rPr><w:b/><w:u w:val="wave" w:color="FF0000"/></w:rPr><w:t>wavy</w:t></w:r>\
            <w:r><w:rPr><w:i/><w:dstrike/><w:u w:val="double"/></w:rPr><w:t>twice</w:t></w:r>\
            <w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t>plain</w:t></w:r>
            """)
        let (back, xml) = try roundTrip(doc)
        let r = back.paragraphs[0].runs
        XCTAssertEqual(back.paragraphs[0].text, "wavytwiceplain"); XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r[0].style.underlineKind, "wave")
        XCTAssertEqual(r[0].style.underlineColor, "FF0000")
        XCTAssertTrue(r[0].style.bold)
        XCTAssertEqual(r[1].style.underlineKind, "double")
        XCTAssertTrue(r[1].style.doubleStrike)
        XCTAssertTrue(r[1].style.strikethrough)
        XCTAssertTrue(r[1].style.italic)
        XCTAssertNil(r[2].style.underlineKind)
        XCTAssertFalse(r[2].style.doubleStrike)
        XCTAssertTrue(xml.contains("<w:dstrike/>"))
    }

    func testTextEffectsSurviveSave() throws {
        let doc = try fixture("""
            <w:r><w:rPr><w:b/><w:shadow/><w:outline/><w14:glow w14:rad="63500"><w14:srgbClr w14:val="FF0000"><w14:alpha w14:val="40000"/></w14:srgbClr></w14:glow></w:rPr><w:t>fx</w:t></w:r>
            """)
        let (back, xml) = try roundTrip(doc)
        XCTAssertTrue(xml.contains("<w:shadow/>"), xml)
        XCTAssertTrue(xml.contains("<w:outline/>"))
        XCTAssertTrue(xml.contains("w14:glow"))
        XCTAssertTrue(back.paragraphs[0].runs[0].style.bold)
        let (_, xml2) = try roundTrip(back)
        XCTAssertTrue(xml2.contains("w14:glow"))
    }
}
