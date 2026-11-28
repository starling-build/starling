// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Word's underline styles (`w:u w:val`, `w:color`) are drawn as their kind: a double, dotted, dashed or wavy rule in the
/// rule's own colour, and a heavy kind at twice the weight. A run also struck keeps the plain line.
final class UnderlineStyleTests: XCTestCase {
    private func theme() -> RichTextTheme {
        let t = RichTextTheme(fontFamily: OfficeFonts.sans)
        t.wordRules = true
        return t
    }

    private func styled(_ kind: String?, color: String? = nil) -> CharStyle {
        var s = CharStyle()
        s.underline = true
        s.underlineKind = kind
        s.underlineColor = color
        return s
    }

    func testKindsMapToTheirRule() {
        let t = theme()
        let cases: [(String?, TextDecorationStyle?, Double?)] = [
            (nil, nil, nil), ("single", nil, nil), ("words", nil, nil), ("thick", nil, 2),
            ("double", .double, nil), ("dotted", .dotted, nil), ("dottedHeavy", .dotted, 2),
            ("dash", .dashed, nil), ("dotDash", .dashed, nil), ("wave", .wavy, nil), ("wavyHeavy", .wavy, 2),
        ]
        for (kind, style, weight) in cases {
            let ts = t.textStyle(for: styled(kind), in: RichParagraphStyle(), scale: 1)
            XCTAssertEqual(ts.decorationStyle, style, "\(kind ?? "nil")")
            XCTAssertEqual(ts.decorationThickness, weight, "\(kind ?? "nil")")
        }
    }

    func testRuleColourIsItsOwn() {
        var s = styled("double", color: "FF0000")
        s.color = Color(0xFF0000FF)
        let ts = theme().textStyle(for: s, in: RichParagraphStyle(), scale: 1)
        XCTAssertEqual(ts.decorationColor, Color(0xFFFF0000))
        XCTAssertEqual(ts.decorationStyle, .double)
    }

    func testStruckRunKeepsThePlainLine() {
        var s = styled("double", color: "FF0000")
        s.strikethrough = true
        let ts = theme().textStyle(for: s, in: RichParagraphStyle(), scale: 1)
        XCTAssertNil(ts.decorationStyle)
        XCTAssertNil(ts.decorationThickness)
    }
}
