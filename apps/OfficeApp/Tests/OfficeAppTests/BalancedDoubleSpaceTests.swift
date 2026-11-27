// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Under w:balanceSingleByteDoubleByteWidth with w:useFELayout, Word for Windows sets two or more spaces between Latin words
/// at the Latin face's OS/2 average width when the run's East Asian slot names no face (xs 715d0d06's Sylfaen footer, 0.42 em;
/// 0658123d's Times New Roman, 0.40 em). A single space stays plain, and so does a run whose East Asian face is a Latin one.
final class BalancedDoubleSpaceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// The width, in points, of the spaces after "a" in `text` (12pt Times New Roman).
    private func gap(_ text: String, spaces: Int, eastAsia: String? = nil, lang: String? = nil) throws -> Double {
        let onWin = DocxFormat.wordOnWindows, was = RichTextTheme.wordWindowsPages
        DocxFormat.wordOnWindows = true; RichTextTheme.wordWindowsPages = true
        defer { DocxFormat.wordOnWindows = onWin; RichTextTheme.wordWindowsPages = was }
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "x")]), pageSetup: .letter))
        let di = entries.firstIndex { $0.name == "word/document.xml" }!
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let a = xml.range(of: "<w:body>")!, b = xml.range(of: "<w:sectPr")!
        let ea = eastAsia.map { " w:eastAsia=\"\($0)\"" } ?? ""
        let rpr = "<w:rFonts w:ascii=\"Times New Roman\" w:hAnsi=\"Times New Roman\"\(ea)/><w:sz w:val=\"24\"/>"
        xml.replaceSubrange(a.upperBound ..< b.lowerBound, with: "<w:p><w:r><w:rPr>\(rpr)</w:rPr><w:t xml:space=\"preserve\">\(text)</w:t></w:r></w:p>")
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        // (No East Asian face in the defaults or styles: the slot names nothing, as under a theme whose `a:ea` is empty.)
        for k in entries.indices where entries[k].name == "word/styles.xml" {
            var styles = String(decoding: entries[k].data, as: UTF8.self)
            while let r = styles.range(of: #" w:eastAsia(Theme)?="[^"]*""#, options: .regularExpression) { styles.removeSubrange(r) }
            entries[k] = ZipEntry(name: "word/styles.xml", data: Data(styles.utf8))
        }
        var doc = try DocxFormat.read(try Zip.write(entries)).document
        doc.readFromFile = true
        doc.balancesSpaceWidth = true
        doc.usesEastAsianLayout = true
        doc.compatibilityMode = 15
        if let lang { doc.defaultLangXML = "<w:lang w:val=\"en-US\" w:eastAsia=\"\(lang)\"/>" }
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        theme.faceResolver = OfficeFonts.face
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let from = layout.caretRect(RichPosition(paragraph: 0, offset: 1), doc).left
        let to = layout.caretRect(RichPosition(paragraph: 0, offset: 1 + spaces), doc).left
        return (to - from) / theme.pixelsPerPoint
    }

    func testTwoSpacesBetweenWordsTakeTheFaceAverageWidth() throws {
        XCTAssertEqual(try gap("a  b", spaces: 2), 2 * 0.400879 * 12, accuracy: 0.05)
        XCTAssertEqual(try gap("a   b", spaces: 3), 3 * 0.400879 * 12, accuracy: 0.05)
    }

    func testASingleSpaceStaysPlain() throws {
        XCTAssertNotEqual(try gap("a b", spaces: 1), 0.400879 * 12, accuracy: 0.05)
    }

    /// A Latin East Asian face (xb 7e68ac6f's Calibri) and an East Asian language leave the rule out.
    func testALatinEastAsianFaceOrAnEastAsianLanguageLeavesItOut() throws {
        XCTAssertNotEqual(try gap("a  b", spaces: 2, eastAsia: "Calibri"), 2 * 0.400879 * 12, accuracy: 0.05)
        XCTAssertNotEqual(try gap("a  b", spaces: 2, lang: "ja-JP"), 2 * 0.400879 * 12, accuracy: 0.05)
    }

    /// An East Asian face in the slot sets each space at half an em, as beside an ideograph (dx2 e9bc88f9 "Ref. No:  770").
    func testAnEastAsianFaceSetsEachSpaceAtHalfAnEm() throws {
        XCTAssertEqual(try gap("a  b", spaces: 2, eastAsia: "MS Mincho"), 2 * 6, accuracy: 0.05)
        XCTAssertEqual(try gap("a   b", spaces: 3, eastAsia: "MS Mincho", lang: "ja-JP"), 3 * 6, accuracy: 0.05)
    }
}
