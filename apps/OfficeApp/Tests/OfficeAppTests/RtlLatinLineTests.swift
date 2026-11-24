// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
@testable import OfficeApp

final class RtlLatinLineTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    /// A right-to-left paragraph at 1.15 spacing: Arabic in a complex face Word lacks (drawn in Arial) beside a Latin run.
    private func lineBox(latinFace: String, text: String = "مرحبا 123") -> (top: Double, bottom: Double, base: Double) {
        RichTextTheme.wordWindowsPages = true
        defer { RichTextTheme.wordWindowsPages = false }
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif)
        theme.wordRules = true
        theme.complexFaceResolver = { _ in var f = RichResolvedFace(family: "Arial"); f.arialStandIn = true; return f }
        var arabic = CharStyle()
        arabic.rightToLeft = true
        arabic.csLetters = true
        arabic.complexFontFamily = "Sakkal Majalla"
        arabic.fontSize = 12
        var latin = CharStyle()
        latin.fontFamily = latinFace
        latin.fontSize = 12
        var style = RichParagraphStyle()
        style.lineSpacing = 1.15
        style.spaceAfter = 0
        let p = RichParagraph(text: text, runs: [Run(length: 6, style: arabic), Run(length: 3, style: latin)], style: style)
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.width = 450 * theme.pixelsPerPoint
        let doc = RichDocument(paragraphs: [p])
        layout.ensureLaidOut(doc)
        let r = layout.caretRect(RichPosition(paragraph: 0, offset: 7), doc)
        let px = theme.pixelsPerPoint
        return (r.top / px, r.bottom / px, 0)
    }

    func testALatinRunOfLettersKeepsTheOrdinaryLine() {
        // A run of Latin words (fas-z20703874: a trailing "doi: 10.2203..." that wraps to a line of its own) is not held to
        // its face's line: Word's own pitch for it is the shorter one.
        let h = lineBox(latinFace: "Calibri", text: "مرحبا abc")
        XCTAssertEqual(h.bottom - h.top, 12 * 1.149 * 1.15, accuracy: 0.1)
    }

    func testALatinRunBesideAnArialStandInKeepsItsOwnFacesLine() {
        // dx2 99905488: Word sets the Latin run's own line (Calibri 1.2207 em, Times New Roman 1.1499 em, times the 1.15 multiple)
        // in a right-to-left paragraph whose Arabic face is drawn in Arial; before, every such line took Arial's 1.149 em.
        let calibri = lineBox(latinFace: "Calibri")
        XCTAssertEqual(calibri.bottom - calibri.top, 12 * 1.2207 * 1.15, accuracy: 0.05)
        let times = lineBox(latinFace: "Times New Roman")
        XCTAssertEqual(times.bottom - times.top, 12 * 1.1499 * 1.15, accuracy: 0.004)
    }
}
