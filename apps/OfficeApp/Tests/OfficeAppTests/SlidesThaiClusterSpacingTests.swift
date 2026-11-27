// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlidesThaiClusterSpacingTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// Where a Slides line of TH SarabunPSK text ends: its own Thai table, as a slide's text box sets it (`DeckController._textTheme`).
    private func end(_ text: String) -> Double {
        let theme = DeckController()._textTheme(font: "TH SarabunPSK", size: 24, color: Color(0xFF000000))
        var style = CharStyle()
        style.fontFamily = "TH SarabunPSK"
        style.complexFontFamily = "TH SarabunPSK"
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

    /// "ดำ" is one letter cluster the engine draws as three glyphs (ด, the nikhahit and sara aa). Its table correction is the
    /// cluster's, so it is shared among the three; taken on each, every "ดำ" stood 10.8 pt where the table (and PowerPoint's
    /// print of th-cb034815ae) has 17, and its table rows took words PowerPoint sends to the next line.
    func testASaraAmClusterTakesItsTableWidthOnce() {
        let am = end(String(repeating: "ดำ", count: 10))
        let aa = end(String(repeating: "ดา", count: 10))
        // The table: ด 0.391, ำ 0.316 and า 0.316 em, so both runs are 10 x 0.707 x 24 = 169.7 pt.
        XCTAssertEqual(am, 169.7, accuracy: 1.5)
        XCTAssertEqual(am, aa, accuracy: 1.0)
    }
}
