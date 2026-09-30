// The More Colors strip: Word's theme grid and the hex field.

import XCTest
import Flutter
@testable import OfficeApp

final class ColorBarTests: XCTestCase {
    func testThemeGridMatchesWord() {
        let t = ColorBar.theme
        XCTAssertEqual(t.count, 6)
        XCTAssertEqual(t.map(\.count), Array(repeating: 10, count: 6))
        // Blue (4472C4): Word's 80 % lighter is D9E2F3, 50 % darker 203864.
        XCTAssertEqual(ColorBar.hex(t[1][4]), "#DAE3F3")
        XCTAssertEqual(ColorBar.hex(t[5][4]), "#223962")
        // White darkens, black lightens.
        XCTAssertEqual(ColorBar.hex(t[5][0]), "#808080")
        XCTAssertEqual(ColorBar.hex(t[1][1]), "#808080")
    }

    func testHexParsing() {
        XCTAssertEqual(ColorBar.parse("#4472C4").map(ColorBar.hex), "#4472C4")
        XCTAssertEqual(ColorBar.parse(" 4472c4 ").map(ColorBar.hex), "#4472C4")
        XCTAssertEqual(ColorBar.parse("#f00").map(ColorBar.hex), "#FF0000")
        XCTAssertNil(ColorBar.parse("#12345"))
        XCTAssertNil(ColorBar.parse("blue"))
    }
}
