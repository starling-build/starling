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

    private func styledFixture(_ runs: String) throws -> Data {
        var parts = try Zip.read(DocxFormat.write(RichDocument(paragraphs: [RichParagraph()]), pageSetup: .letter))
        let d = try XCTUnwrap(parts.firstIndex { $0.name == "word/document.xml" })
        parts[d] = ZipEntry(name: "word/document.xml", data: Data((
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:w14=\"http://schemas.microsoft.com/office/word/2010/wordml\"><w:body><w:p>"
            + runs + "</w:p></w:body></w:document>").utf8))
        let st = try XCTUnwrap(parts.firstIndex { $0.name == "word/styles.xml" })
        var xml = String(decoding: parts[st].data, as: UTF8.self)
        xml = xml.replacingOccurrences(of: "</w:styles>", with: "<w:style w:type=\"character\" w:styleId=\"Loud\"><w:name w:val=\"Loud\"/><w:rPr><w:b/><w:color w:val=\"C00000\"/></w:rPr></w:style></w:styles>")
        parts[st] = ZipEntry(name: "word/styles.xml", data: Data(xml.utf8))
        return try Zip.write(parts)
    }

    func testCharacterStyleNameSurvivesSave() throws {
        let doc = try DocxFormat.read(try styledFixture("<w:r><w:rPr><w:rStyle w:val=\"Loud\"/><w:i/></w:rPr><w:t>loud</w:t></w:r><w:r><w:t>plain</w:t></w:r>")).document
        XCTAssertEqual(doc.paragraphs[0].runs[0].style.styleId, "Loud")
        XCTAssertTrue(doc.paragraphs[0].runs[0].style.bold)
        let bytes = try DocxFormat.write(doc, pageSetup: .letter)
        let parts = try Zip.read(bytes)
        let xml = String(decoding: try XCTUnwrap(parts.first { $0.name == "word/document.xml" }).data, as: UTF8.self)
        let styles = String(decoding: try XCTUnwrap(parts.first { $0.name == "word/styles.xml" }).data, as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:rStyle w:val=\"Loud\"/>"), xml)
        XCTAssertTrue(styles.contains("w:styleId=\"Loud\""))
        let back = try DocxFormat.read(bytes).document
        XCTAssertEqual(back.paragraphs[0].runs[0].style.styleId, "Loud")
        XCTAssertTrue(back.paragraphs[0].runs[0].style.italic)
        XCTAssertNil(back.paragraphs[0].runs[1].style.styleId)
    }

    /// Writes the file Word is asked to open (set CHECK_OUT to a folder); skipped otherwise.
    func testWriteWordCheckFile() throws {
        guard let out = ProcessInfo.processInfo.environment["CHECK_OUT"] else { throw XCTSkip("CHECK_OUT not set") }
        let kinds = ["single", "double", "thick", "dotted", "dash", "dotDash", "wave", "words"]
        var runs = kinds.map { "<w:r><w:rPr><w:u w:val=\"\($0)\" w:color=\"FF0000\"/></w:rPr><w:t>u-\($0) </w:t></w:r>" }.joined()
        runs += "<w:r><w:rPr><w:dstrike/></w:rPr><w:t>double strike </w:t></w:r>"
        runs += "<w:r><w:rPr><w:shadow/></w:rPr><w:t>shadow </w:t></w:r><w:r><w:rPr><w:outline/></w:rPr><w:t>outline </w:t></w:r>"
        runs += "<w:r><w:rPr><w:emboss/></w:rPr><w:t>emboss </w:t></w:r>"
        runs += "<w:r><w:rPr><w14:glow w14:rad=\"101600\"><w14:srgbClr w14:val=\"FF0000\"><w14:alpha w14:val=\"40000\"/></w14:srgbClr></w14:glow></w:rPr><w:t>glow </w:t></w:r>"
        runs += "<w:r><w:rPr><w:rStyle w:val=\"Loud\"/><w:b/><w:i/><w:color w:val=\"0000FF\"/><w:sz w:val=\"36\"/><w:u w:val=\"wave\" w:color=\"00AA00\"/><w:dstrike/><w:shadow/><w:outline/><w14:glow w14:rad=\"63500\"><w14:srgbClr w14:val=\"FFC000\"/></w14:glow></w:rPr><w:t>everything at once</w:t></w:r>"
        let doc = try DocxFormat.read(try styledFixture(runs)).document
        let bytes = try DocxFormat.write(doc, pageSetup: .letter)
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        try bytes.write(to: URL(fileURLWithPath: out + "/char-effects-check.docx"))
    }
}
