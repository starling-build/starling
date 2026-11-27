// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A run that opens with a combining mark (a lone hamza, U+0654) in another complex-script face than the text
/// before it is shaped apart in Word, and the mark stands on a dotted circle with the circle's width: Word's
/// print of dx2 c2c3a2f3 p3, a Times New Roman hamza after B Zar text, 8.3 pt. In the same face it attaches.
final class MarkOpeningFaceRunTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    private func width(markFace: String) -> Double {
        let was = RichTextTheme.wordWindowsPages
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = was }
        func style(_ face: String) -> CharStyle {
            var s = CharStyle()
            s.fontSize = 12
            s.complexFontSize = 12
            s.fontFamily = face
            s.complexFontFamily = face
            s.rightToLeft = true
            return s
        }
        let head = "نام شهر", tail = " آباد"
        var p = RichParagraph(text: head + "\u{0654}" + tail, style: RichParagraphStyle(spaceAfter: 0))
        p.style.rightToLeft = true
        p.runs = [Run(length: head.utf16.count, style: style("B Zar")), Run(length: 1, style: style(markFace)),
                  Run(length: tail.utf16.count, style: style("B Zar"))]
        var document = RichDocument(paragraphs: [p])
        document.readFromFile = true
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.pageSetup = PageSetup.letter
        layout.width = PageSetup.letter.columnWidth * theme.pixelsPerPoint
        layout.ensureLaidOut(document)
        return (layout.geometry(0).painter.computeLineMetrics().first?.width ?? 0) / theme.pixelsPerPoint
    }

    func testAMarkOpeningARunInAnotherFaceStandsOnADottedCircle() {
        let apart = width(markFace: "Times New Roman"), attached = width(markFace: "B Zar")
        XCTAssertGreaterThan(apart - attached, 5, "the hamza in another face takes a dotted circle's width")
        XCTAssertLessThan(apart - attached, 12)
    }
}
