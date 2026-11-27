// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Drawn with the faces this app ships and no others (OFFICE_FONT_SOURCE=bundled, which every harness pins), a paragraph
/// whose text span has no style of its own (a document's first paragraph with a hanging indent is one) used to stop the
/// app on `getFullHeightForCaret`: it read the first box of a one-space template paragraph, and that template, drawn
/// with a default face nothing ships, had none. Opened in Writer under the bundled faces, such a docx died at its first paint.
final class CaretInHungParagraphTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
        _ = OfficeFonts.register()
    }

    func testACaretHeightComesFromTheTemplateThenTheStrutThenZero() {
        let strut = Flutter.StrutStyle(fontFamily: "Carlito", fontSize: 16, height: 1.4, forceStrutHeight: true)
        XCTAssertEqual(TextPainter.caretHeight(templateBox: Rect.fromLTWH(0, 0, 5, 19), strut: strut), 19)
        // No box: the template shaped nothing, and the app used to stop on its force-unwrap.
        XCTAssertEqual(TextPainter.caretHeight(templateBox: nil, strut: strut), 16 * 1.4, accuracy: 1e-9)
        XCTAssertEqual(TextPainter.caretHeight(templateBox: nil, strut: nil), 0)
    }
}
