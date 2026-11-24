// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Arabic letters in a run with neither `w:rtl` nor `w:cs` are set at the run's `w:sz`, not `w:szCs` (xb fas-z22867828's title: sz 40,
/// szCs 52, Word prints 20 pt and the rows step 31.3 pt, not 41).
final class ArabicPlainSizeTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func firstRunStyle(rtlFlag: Bool, csFlag: Bool = false) throws -> CharStyle {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        let onWin = DocxFormat.wordOnWindows, onFonts = OfficeFonts.wordOnWindows
        DocxFormat.wordOnWindows = true; OfficeFonts.wordOnWindows = true
        defer { RichTextTheme.wordWindowsPages = was; DocxFormat.wordOnWindows = onWin; OfficeFonts.wordOnWindows = onFonts }
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")), sect = try XCTUnwrap(xml.range(of: "<w:sectPr"))
        let run = "<w:r><w:rPr><w:rFonts w:cs=\"B Nazanin\"/>" + (csFlag ? "<w:cs/>" : "") + (rtlFlag ? "<w:rtl/>" : "") + "<w:sz w:val=\"40\"/><w:szCs w:val=\"52\"/></w:rPr><w:t>\u{627}\u{644}\u{639}\u{631}\u{628}\u{64A}\u{629}</w:t></w:r>"
        xml.replaceSubrange(body.upperBound ..< sect.lowerBound, with: "<w:p><w:pPr><w:bidi/></w:pPr>" + run + "</w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        let doc = try DocxFormat.read(try Zip.write(entries)).document
        return try XCTUnwrap(doc.paragraphs[0].runs.first).style
    }

    func testArabicInARunWithoutRtlKeepsPlainSize() throws {
        XCTAssertTrue(try firstRunStyle(rtlFlag: false).plainSize)
        XCTAssertFalse(try firstRunStyle(rtlFlag: true).plainSize)
        XCTAssertFalse(try firstRunStyle(rtlFlag: false, csFlag: true).plainSize)
    }
}
