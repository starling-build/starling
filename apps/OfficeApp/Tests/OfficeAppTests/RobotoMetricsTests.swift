// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// Roboto (Word's cloud font, not on our box) is laid out at its own measured advances and line,
/// drawn in the stand-in (dx2 7d4b5fee5a50: 15 pages to Word's 14 with the stand-in's widths).
final class RobotoMetricsTests: XCTestCase {
    func testRobotoAdvancesAreMeasuredAndBoldDiffers() {
        XCTAssertEqual(OfficeFonts.robotoRegularAdvances.count, 95)
        XCTAssertEqual(OfficeFonts.robotoBoldAdvances.count, 95)
        // 'A' (0x41), 1336 of 2048 units regular.
        XCTAssertEqual(OfficeFonts.robotoRegularAdvances[0x41 - 0x20], 0.6523, accuracy: 0.0005)
        XCTAssertNotEqual(OfficeFonts.robotoRegularAdvances, OfficeFonts.robotoBoldAdvances)
        XCTAssertFalse(OfficeFonts.robotoRegularOtherAdvances.isEmpty)
    }
}
