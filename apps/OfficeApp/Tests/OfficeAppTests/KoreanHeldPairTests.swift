// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeText

final class KoreanHeldPairTests: XCTestCase {
    // Word keeps a space-free Hangul word whole with the ASCII punctuation around it: a form blank
    // "(주소_____" is one word, so the underscores are not parted from "소" (ko-9f116dc4aa).
    func testHangulIsHeldToAsciiPunctuationIncludingUnderscore() {
        let sym: UInt32 = 0xC18C  // 소
        for p in [0x5F, 0x5C, 0x5E, 0x60, 0x7C, 0x7E, 0x28, 0x2C, 0x2E, 0x5B, 0x7B] as [UInt32] {
            XCTAssertTrue(RichLayout._hangulHeldPair(sym, p), "Hangul then \(p)")
            XCTAssertTrue(RichLayout._hangulHeldPair(p, sym), "\(p) then Hangul")
        }
        // A Latin letter is not punctuation: it keeps its own rules.
        XCTAssertFalse(RichLayout._hangulHeldPair(sym, 0x41))
    }
}
