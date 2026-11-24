// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class ListLevelTabLayoutTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// Where the first line's text starts, in points from the paragraph's left edge, for a bullet whose level
    /// states `levelLeft`, in a paragraph that states its own left indent of 0 (and the level's hanging 18).
    private func textStart(levelLeft: Double) throws -> Double {
        var p = RichParagraph(text: "professor falar")
        p.style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1)
        p.style.list = .bullet; p.style.listId = "1"; p.style.listLevel = 0
        p.style.indentLeft = 0; p.style.listIndentLeft = 0   // the paragraph's own `w:ind w:left=0`
        var doc = RichDocument(paragraphs: [p])
        var level = ListLevelFormat(text: "\u{2022}", format: .bullet)
        level.indentLeft = levelLeft; level.hanging = 18
        doc.listFormats["1"] = [0: level]
        let back = doc
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
        theme.wordRules = true
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.width = 400
        layout.ensureLaidOut(back)
        let painter = layout.geometry(0).painter
        let box = try XCTUnwrap(painter.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: 1)).first)
        return box.right / theme.pixelsPerPoint
    }

    /// pt-90497db98b: bullets with left 0 of their own, under a level at 1020 twips, start their text at the
    /// level's indent (51pt) in Word's print, not at the paragraph's 0.
    func testANumberTabGoesToTheLevelsIndentUnderAParagraphsOwnLeft() throws {
        let start = try textStart(levelLeft: 51)
        XCTAssertEqual(start, 51, accuracy: 1.0)
    }
}
