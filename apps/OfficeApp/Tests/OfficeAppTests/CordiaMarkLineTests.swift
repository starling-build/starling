// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp


/// An empty paragraph whose mark is a complex-script one (`w:cs`) in Cordia New (the Thai theme face) is a Cordia line at szCs, 1.388 em
/// with the line multiple on top: Word for Windows' print of dx2 228c1f233c7a (lab c228 v0 and v1), 22.28 pt for szCs 14 at 1.15.
final class CordiaMarkLineTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func lineHeight(cordia: Bool) -> Double {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        var mark = CharStyle()
        mark.fontSize = 11
        mark.complexFontSize = 14
        mark.complexFontFamily = cordia ? "Cordia New" : "Calibri"
        mark.keptXML = "<w:rPr><w:cs/></w:rPr>"
        var p = RichParagraph(text: "", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.15))
        p.runs = [Run(length: 0, style: mark)]
        var document = RichDocument(paragraphs: [p])
        document.readFromFile = true
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.pageSetup = PageSetup.letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(document)
        return layout.totalHeight / theme.pixelsPerPoint
    }

    func testEmptyCsMarkInCordiaNewIsACordiaLine() {
        XCTAssertEqual(lineHeight(cordia: true), 14 * 1.388 * 1.15, accuracy: 0.3)
        XCTAssertLessThan(lineHeight(cordia: false), 14 * 1.388 * 1.15 - 1)
    }
}
