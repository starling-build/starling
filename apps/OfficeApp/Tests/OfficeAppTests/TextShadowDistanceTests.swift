// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeText

final class TextShadowDistanceTests: XCTestCase {
    func testAShadowsDistanceKeepsGrowingAbove72Points() {
        // Word's lab shadow5: 96 pt reads x1.22 and 144 pt x1.58 of the set distance; a clamp at 1 above 72 pt was wrong.
        XCTAssertEqual(RichLayout._wordShadowDistanceFactor(size: 96), 1.22, accuracy: 0.02)
        XCTAssertEqual(RichLayout._wordShadowDistanceFactor(size: 144), 1.58, accuracy: 0.02)
        XCTAssertEqual(RichLayout._wordShadowDistanceFactor(size: 36), 0.62, accuracy: 0.03)
    }
}
