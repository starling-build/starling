// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// In a document whose complex-script language is Hebrew, a body run of ASCII digits flagged w:rtl with no complex-script
/// size or face of its own stays complex script (Word prints it in the cs face), while the same digits as a field's result
/// (a contents list's PAGEREF) are a plain Latin run. Lab rtldigits: "2468" in Arial, a PAGE result in Calibri.
final class HebrewRtlDigitsTests: XCTestCase {
    private let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\""

    private func runs(_ paragraph: String) throws -> [(String, Bool)] {
        let was = DocxFormat.wordOnWindows
        DocxFormat.wordOnWindows = true
        defer { DocxFormat.wordOnWindows = was }
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        xml.replaceSubrange(body, with: paragraph)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let styles = "<w:styles \(ns)><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Calibri\" w:hAnsi=\"Calibri\" w:cs=\"Arial\"/>"
            + "<w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/><w:lang w:val=\"en-US\" w:bidi=\"he-IL\"/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>"
        for k in entries.indices where entries[k].name == "word/styles.xml" { entries[k] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8)) }
        let p = try XCTUnwrap(try DocxFormat.read(try Zip.write(entries)).document.paragraphs.first)
        let units = Array(p.text.utf16)
        var at = 0
        return p.runs.map { r in
            defer { at += r.length }
            return (String(decoding: units[at ..< at + r.length], as: UTF16.self), r.style.rightToLeft)
        }
    }

    func testPlainBodyDigitsStayComplex() throws {
        let got = try runs("<w:p><w:pPr><w:bidi/></w:pPr><w:r><w:rPr><w:rtl/></w:rPr><w:t xml:space=\"preserve\">א </w:t></w:r>"
            + "<w:r><w:rPr><w:rtl/><w:lang w:val=\"he-IL\"/></w:rPr><w:t>2468</w:t></w:r></w:p>")
        XCTAssertEqual(got.first { $0.0 == "2468" }?.1, true)
    }

    func testFieldResultDigitsAreLatin() throws {
        let got = try runs("<w:p><w:pPr><w:bidi/></w:pPr><w:r><w:rPr><w:rtl/></w:rPr><w:t xml:space=\"preserve\">א </w:t></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> PAGEREF _Toc1 \\h </w:instrText></w:r>"
            + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:rPr><w:rtl/></w:rPr><w:t>12</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"
            + "<w:bookmarkStart w:id=\"0\" w:name=\"_Toc1\"/><w:bookmarkEnd w:id=\"0\"/></w:p>")
        XCTAssertEqual(got.first { $0.0 == "12" }?.1, false)
    }
}
