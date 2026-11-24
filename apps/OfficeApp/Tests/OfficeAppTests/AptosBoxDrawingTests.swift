// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Aptos has six box-drawing glyphs and Word prints them in Aptos, half an em each (xb ara-z20756589: a 79-character box line fits one
/// line, 12 pt, 6.0 pt a glyph; the stand-in's wider glyphs wrapped it).
final class AptosBoxDrawingTests: XCTestCase {
    func testAptosBoxDrawingGlyphsAreHalfAnEm() {
        for u: UInt32 in [0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518] {
            XCTAssertEqual(OfficeFonts.aptosOtherAdvances[u], 0.5)
            XCTAssertEqual(OfficeFonts.aptosBoldOtherAdvances[u], 0.5)
        }
    }
}
