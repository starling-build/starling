// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocDefaultEastAsiaFontTests: XCTestCase {
    /// The STSH header names three standard fonts: ascii, East Asian, other. A run that names no East Asian
    /// face takes the second, not the first (ko-9f116dc4aa: Times New Roman for Latin, 바탕체 for Hangul).
    func testStshHeaderGivesTheEastAsianDefaultItsOwnFont() {
        var t = [UInt8](repeating: 0, count: 2 + 18)
        t[0] = 18  // cbStshi
        t[2 + 12] = 3  // ftcAsci
        t[2 + 14] = 7  // ftcFE
        let s = DocProps.styles(t, at: 0, count: t.count, fonts: [])
        XCTAssertEqual(s.font, 3)
        XCTAssertEqual(s.fontFE, 7)
    }
}
