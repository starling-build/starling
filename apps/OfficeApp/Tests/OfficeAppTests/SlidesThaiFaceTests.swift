// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlidesThaiFaceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// How far a Slides line of `text` in `font` at 24 pt runs, as a slide's text box sets it (`DeckController._textTheme`).
    private func end(_ text: String, font: String) -> Double {
        let theme = DeckController()._textTheme(font: font, size: 24, color: Color(0xFF000000))
        var style = CharStyle()
        style.fontFamily = font
        style.complexFontFamily = font
        style.fontSize = 24
        let p = RichParagraph(text: text, runs: [Run(length: text.utf16.count, style: style)], style: RichParagraphStyle())
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.width = 2000 * theme.pixelsPerPoint
        let doc = RichDocument(paragraphs: [p])
        layout.ensureLaidOut(doc)
        let px = theme.pixelsPerPoint
        return (layout.caretRect(RichPosition(paragraph: 0, offset: text.utf16.count), doc).left
                - layout.caretRect(RichPosition(paragraph: 0, offset: 0), doc).left) / px
    }

    /// Browallia New, Cordia New and the other narrow Thai faces are on PowerPoint's machine and not on ours. The stand-in
    /// (Noto Sans Thai) drew their Thai about a third wider than PowerPoint does, so slides of th-b21a68ad64 and
    /// th-bd26062a73 wrapped words PowerPoint keeps on the line. They now take Browallia's Thai widths, as Word's do.
    func testNarrowThaiFacesTakeBrowalliaThaiWidths() {
        let text = String(repeating: "ก", count: 10)
        // Browallia New's ก is 0.4199 em: 10 x 0.4199 x 24 = 100.8 pt.
        for font in ["Browallia New", "BrowalliaUPC", "Cordia New", "CordiaUPC", "TH Sarabun New"] {
            XCTAssertEqual(end(text, font: font), 100.8, accuracy: 1.5, font)
        }
    }
}
