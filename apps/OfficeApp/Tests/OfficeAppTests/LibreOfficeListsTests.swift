// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Three readings of Word's print of LibreOffice test documents (tdf158597,
/// tdf108496, tdf132752): a paragraph mark's character style, the Normal of
/// a styles part with no run defaults, and the indent of a style that turns
/// its numbering off.
final class LibreOfficeListsTests: XCTestCase {
    private func read(_ id: String) throws -> RichDocument {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("test/corpus/docx/lo/docs/\(id).docx")
        guard let data = try? Data(contentsOf: file) else { throw XCTSkip("the LibreOffice set is not checked out") }
        return try DocxFormat.read(data).document
    }

    /// tdf158597: plain text over a paragraph mark set in the Emphasis character
    /// style (16pt): the mark is 16pt, so Word's line stands as tall as it.
    func testParagraphMarkTakesItsCharacterStyle() throws {
        let doc = try read("lo-544f3da698a24b54")
        XCTAssertEqual(doc.paragraphs[1].style.mark?.fontSize, 16, "the mark of \"Char style mark\"")
        XCTAssertNil(doc.paragraphs[0].style.mark?.fontSize, "\"No style\" has no mark of its own")
    }

    /// tdf108496: a styles part with no run defaults at all and no size is Word's
    /// own Normal, 12pt (Word prints it in Calibri 12, 25pt a line with 8pt after).
    func testStylesPartWithNoRunDefaultsIsTwelvePoint() throws {
        let doc = try read("lo-029954d7cf0a8b8d")
        XCTAssertEqual(doc.styles[RichNamedStyle.normalId]?.char.fontSize, 12)
    }

    /// A file that states its Normal's size keeps it, with or without run defaults
    /// (lo-486e8e62 and lo-79583fa0 print 11pt in Word).
    func testStatedSizeStandsWithoutRunDefaults() throws {
        for id in ["lo-486e8e62d1d9861f", "lo-79583fa0c8bed68b"] {
            XCTAssertEqual(try read(id).styles[RichNamedStyle.normalId]?.char.fontSize, 11, id)
        }
    }

    /// tdf132752: "Anleitung" holds the list (numId 4) and left 2697, right 3340,
    /// hanging -2357. A style based on it that says numId 0 takes no left indent or
    /// hanging from it; one that keeps the list does.
    func testNumberingOffStyleTakesNoLeftIndentFromItsNumberedParent() throws {
        let doc = try read("lo-8882730ac6bc0cb7")
        let hinweis3 = try XCTUnwrap(doc.styles["Hinweis3"]?.paragraph)
        XCTAssertEqual(hinweis3.indentLeft, 0, accuracy: 0.01, "numId 0, no w:ind of its own")
        XCTAssertEqual(hinweis3.firstLineIndent, 0, accuracy: 0.01)
        XCTAssertEqual(hinweis3.indentRight, 167, accuracy: 0.01, "the right indent stays")
        let hinweis1 = try XCTUnwrap(doc.styles["Hinweis1"]?.paragraph)
        XCTAssertEqual(hinweis1.indentLeft, 51.05, accuracy: 0.01, "its own left")
        XCTAssertEqual(hinweis1.firstLineIndent, 0, accuracy: 0.01, "no hanging from the parent")
        let hinweis4 = try XCTUnwrap(doc.styles["Hinweis4"]?.paragraph)
        XCTAssertEqual(hinweis4.firstLineIndent, 117.85, accuracy: 0.01, "still in the list: the parent's -2357 stands")
    }
}
