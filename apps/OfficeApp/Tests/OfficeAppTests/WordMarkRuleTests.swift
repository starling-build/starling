// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// dx2 228c1f233c7a: two rules of Word's own print.
final class WordMarkRuleTests: XCTestCase {
    private func theme() -> RichTextTheme {
        let t = RichTextTheme(fontFamily: OfficeFonts.sans)
        t.wordRules = true
        return t
    }

    /// An empty paragraph whose mark is flagged w:cs with no w:sz is a complex-script line: set at szCs (14 pt), not at sz.
    func testCsFlaggedMarkIsSetAtSzCs() {
        var normal = CharStyle()
        normal.fontSize = 11
        normal.complexFontSize = 14
        var plain = CharStyle()
        let flagged: CharStyle = { var s = CharStyle(); s.csMark = true; return s }()
        let t = theme()
        let a = t.textStyle(for: plain, in: RichParagraphStyle(), normal: normal, scale: 1).fontSize
        let b = t.textStyle(for: flagged, in: RichParagraphStyle(), normal: normal, scale: 1).fontSize
        plain.fontSize = nil
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(try XCTUnwrap(b) / XCTUnwrap(a), 14.0 / 11.0, accuracy: 0.001)
    }

    /// Word's PDF export draws no text glow: with shadows as paths (the PDF), a glowing run has no copies in the text layer.
    func testGlowIsNotDrawnInThePdf() {
        var s = CharStyle()
        var glow = CharShadow(color: Color(0xFF00FF00), dx: 0, dy: 0, blur: 4)
        glow.glow = true
        s.shadow = glow
        let t = theme()
        RichTextTheme.shadowsAsPaths = true
        defer { RichTextTheme.shadowsAsPaths = false }
        let inPdf = t.textStyle(for: s, in: RichParagraphStyle(), scale: 1).shadows ?? []
        XCTAssertTrue(inPdf.isEmpty)
        RichTextTheme.shadowsAsPaths = false
        let onScreen = t.textStyle(for: s, in: RichParagraphStyle(), scale: 1).shadows ?? []
        XCTAssertFalse(onScreen.isEmpty)
    }
}
