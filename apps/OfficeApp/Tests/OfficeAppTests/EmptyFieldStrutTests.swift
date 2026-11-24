// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// An empty `fldSimple` (a PAGEREF with no result) leaves a space of the paragraph's default face in the line in Word's print, so a
/// line of smaller complex-script text stands as tall as that 12 pt Times line (fas-z22832287, lab fas1: TOC rows 22.8 pt apart with
/// the field, 22.35 without).
final class EmptyFieldStrutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func paragraphText(field: Bool, windows: Bool) throws -> String {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = windows
        defer { RichTextTheme.wordWindowsPages = was }
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let run = "<w:r><w:rPr><w:rFonts w:cs=\"Arial\"/><w:rtl/><w:sz w:val=\"14\"/><w:szCs w:val=\"14\"/></w:rPr><w:t>\u{627}\u{644}\u{639}\u{631}\u{628}\u{64A}\u{629}</w:t></w:r>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound,
            with: "<w:p><w:pPr><w:bidi/><w:spacing w:after=\"0\"/></w:pPr>" + run + (field ? "<w:fldSimple w:instr=\" PAGEREF x \\h \"/>" : "") + "</w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        return doc.paragraphs[0].text
    }

    func testAnEmptyFieldLeavesAWordJoinerStrutOnWindowsPagesOnly() throws {
        XCTAssertTrue(try paragraphText(field: true, windows: true).contains("\u{2060}"))
        XCTAssertFalse(try paragraphText(field: false, windows: true).contains("\u{2060}"))
        XCTAssertFalse(try paragraphText(field: true, windows: false).contains("\u{2060}"))
    }
}
