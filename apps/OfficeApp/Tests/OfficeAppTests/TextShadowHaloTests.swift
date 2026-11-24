// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
@testable import OfficeText

final class TextShadowHaloTests: XCTestCase {
    func testAShadowIsSetDownByTheLineGrowthOfItsRun() {
        // A run whose line was grown for its shadow carries the shift in its style (`shadow-line`); the shadow is lowered by it.
        let plain = TextSpan(text: "ab")
        let grown = TextSpan(text: "cd", style: TextStyle(baselineShift: 4, debugLabel: "x shadow-line@4"))
        let root = TextSpan(children: [plain, grown])
        XCTAssertEqual(RichLayout._shadowLineShift(root, at: 0), 0)
        XCTAssertEqual(RichLayout._shadowLineShift(root, at: 3), 4)
    }

    func testABlurredShadowFadesOutAtHalfTheBlurByTheDistanceFactor() {
        // Lab shadow5: pink fades out to 0.5 x blur x (size/72)^(2/3) past the letters, the same on all four sides.
        XCTAssertEqual(RichLayout._shadowHaloReach(blur: 8, distanceFactor: 1), 4, accuracy: 1e-9)
        XCTAssertEqual(RichLayout._shadowHaloReach(blur: 4, distanceFactor: 0.5), 1, accuracy: 1e-9)
    }
}
