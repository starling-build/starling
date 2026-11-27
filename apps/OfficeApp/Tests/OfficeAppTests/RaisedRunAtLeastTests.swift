// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class RaisedRunAtLeastTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// The height of a plain 12pt Times New Roman line and the line after it, holding one digit raised 3pt (`w:position` 6) among plain text, in points,
    /// under the given spacing.
    private func pitch(_ spacing: String, raise: Int = 6) throws -> Double {
        let onWin = DocxFormat.wordOnWindows, was = RichTextTheme.wordWindowsPages
        DocxFormat.wordOnWindows = true; RichTextTheme.wordWindowsPages = true
        defer { DocxFormat.wordOnWindows = onWin; RichTextTheme.wordWindowsPages = was }
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let a = xml.range(of: "<w:body>")!, b = xml.range(of: "<w:sectPr")!
        let rpr = "<w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\"/><w:sz w:val=\"24\"/>"
        let ppr = "<w:pPr><w:spacing w:after=\"0\" \(spacing)/></w:pPr>"
        let body = "<w:p>\(ppr)<w:r><w:rPr>\(rpr)</w:rPr><w:t>above</w:t></w:r></w:p><w:p>\(ppr)<w:r><w:rPr>\(rpr)</w:rPr><w:t>2</w:t></w:r><w:r><w:rPr>\(rpr)<w:position w:val=\"\(raise)\"/></w:rPr><w:t>1</w:t></w:r>"
            + "<w:r><w:rPr>\(rpr)</w:rPr><w:t xml:space=\"preserve\">. plain</w:t></w:r></w:p><w:p>\(ppr)<w:r><w:rPr>\(rpr)</w:rPr><w:t>next</w:t></w:r></w:p>"
        xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: body)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        var doc = try DocxFormat.read(try Zip.write(entries)).document
        doc.readFromFile = true
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let first = layout.caretRect(RichPosition(paragraph: 0, offset: 0), doc).top
        let next = layout.caretRect(RichPosition(paragraph: 2, offset: 0), doc).top
        return (next - first) / theme.pixelsPerPoint
    }

    /// Under a minimum below the text's own line, the raise grows the line as it does at single spacing (xs 715d0d06's raised
    /// digit: 18.84pt in Word's print against 15.84).
    func testAMinimumBelowTheTextGrowsByTheRaise() throws {
        let plain = try pitch("w:line=\"20\" w:lineRule=\"atLeast\"", raise: 0)
        XCTAssertEqual(try pitch("w:line=\"20\" w:lineRule=\"atLeast\"") - plain, 3, accuracy: 0.05)
        XCTAssertEqual(try pitch("w:line=\"20\" w:lineRule=\"atLeast\""), try pitch("w:line=\"240\" w:lineRule=\"auto\""), accuracy: 0.05)
    }

    /// A minimum that already holds the raised text keeps its height; one between the plain and the raised text's lines grows to the latter.
    func testAMinimumAboveTheTextTakesTheRaiseFirst() throws {
        XCTAssertEqual(try pitch("w:line=\"400\" w:lineRule=\"atLeast\""), 40, accuracy: 0.05)
        let plain = try pitch("w:line=\"20\" w:lineRule=\"atLeast\"", raise: 0)
        XCTAssertEqual(try pitch("w:line=\"300\" w:lineRule=\"atLeast\""), 15 + plain / 2 + 3, accuracy: 0.05)
    }
}
