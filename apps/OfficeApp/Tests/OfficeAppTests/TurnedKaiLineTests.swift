// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// A turned cell's (plain tbRl) lines of turned ideographs stand 0.0425 em further apart than the face's own line, the
/// extra split evenly about the face's own ascent. Lab kaipad2, Word's print of three-line 11 pt cells: KaiTi and
/// DFKai-SB columns 14.76 pt apart (ours stood 14.30), first baselines 1.031 em (KaiTi) and 0.973 em (DFKai-SB) in.
final class TurnedKaiLineTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// The first two baselines, in points from the paragraph's top, of a three-line tbRl cell in `face` at 11 pt.
    private func baselines(_ face: String) throws -> [Double] {
        let onWin = DocxFormat.wordOnWindows, fonts = OfficeFonts.wordOnWindows, was = RichTextTheme.wordWindowsPages
        DocxFormat.wordOnWindows = true; OfficeFonts.wordOnWindows = true; RichTextTheme.wordWindowsPages = true
        defer { DocxFormat.wordOnWindows = onWin; OfficeFonts.wordOnWindows = fonts; RichTextTheme.wordWindowsPages = was }
        var entries = try Zip.read(try DocxFormat.write(RichDocument(paragraphs: [RichParagraph(text: "a")]), pageSetup: .letter))
        let di = try XCTUnwrap(entries.firstIndex { $0.name == "word/document.xml" })
        var xml = String(decoding: entries[di].data, as: UTF8.self)
        let body = try XCTUnwrap(xml.range(of: "<w:body>")).upperBound ..< (try XCTUnwrap(xml.range(of: "<w:sectPr"))).lowerBound
        let r = "<w:r><w:rPr><w:rFonts w:eastAsia=\"\(face)\"/><w:sz w:val=\"22\"/></w:rPr>"
        xml.replaceSubrange(body, with: """
        <w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid><w:gridCol w:w="1440"/></w:tblGrid>\
        <w:tr><w:trPr><w:trHeight w:val="2400" w:hRule="exact"/></w:trPr>\
        <w:tc><w:tcPr><w:tcW w:w="1440" w:type="dxa"/><w:textDirection w:val="tbRl"/></w:tcPr>\
        <w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>\
        \(r)<w:t>中文</w:t></w:r>\(r)<w:br/><w:t>大小</w:t></w:r>\(r)<w:br/><w:t>中文</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p/>
        """)
        entries[di] = ZipEntry(name: "word/document.xml", data: Data(xml.utf8))
        var doc = try DocxFormat.read(try Zip.write(entries)).document
        doc.readFromFile = true
        doc.compatibilityMode = 15
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        theme.faceResolver = { OfficeFonts.face($0, eastAsian: $1) }
        let layout = RichLayout(theme: theme, paragraphCount: doc.paragraphs.count)
        layout.pageSetup = .letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(doc)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.text.hasPrefix("中文") })
        let lines = layout.geometry(i).painter.computeLineMetrics()
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        return lines.prefix(2).map { $0.baseline / theme.pixelsPerPoint }
    }

    func testTurnedKaiLinesStandAtWordsPitchOnTheFacesOwnSplit() throws {
        for (face, ascent) in [("KaiTi", 1.031), ("DFKai-SB", 0.973)] {
            let b = try baselines(face)
            XCTAssertEqual(b[1] - b[0], 14.76, accuracy: 0.1, face)
            XCTAssertEqual(b[0], ascent * 11, accuracy: 0.15, face)
        }
    }
}
