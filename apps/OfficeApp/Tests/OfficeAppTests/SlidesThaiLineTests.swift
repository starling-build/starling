// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SlidesThaiLineTests: XCTestCase {
    /// TH SarabunPSK is on PowerPoint's machine and not on ours. PowerPoint stands its baseline by the face's own Windows
    /// ascent and descent (850 and 460 of 1000) in the 1.2 em line, not by the stand-in's (Noto Sans Thai), which stood every
    /// title of th-cb034815ae 8 pt low and its cover's first line 15 pt low; table cells take the same ascent and descent.
    func testTHSarabunPSKStandsOnItsOwnWindowsMetrics() {
        XCTAssertEqual(SlideFonts.ownDescentShare("TH SarabunPSK") ?? 0, 460.0 / 1310, accuracy: 0.0001)
        let m = SlideFonts.windowsAscentDescent("TH SarabunPSK")
        XCTAssertEqual(m?.ascent ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(m?.descent ?? 0, 0.46, accuracy: 0.0001)
    }

    /// Cordia New, Browallia New (and the TH Sarabun faces printed in it) and Angsana New stand the same way, on their own ascent and
    /// descent as Word sets them: th-bd26062a73 (Cordia) stood 5-7 pt low, th-1ad142d29c (TH Sarabun New) 45 -> 97% of lines.
    func testCordiaBrowalliaAngsanaStandOnTheirOwnMetrics() {
        XCTAssertEqual(SlideFonts.ownDescentShare("Cordia New") ?? 0, 0.496 / 1.388, accuracy: 0.0001)
        XCTAssertEqual(SlideFonts.ownDescentShare("Browallia New") ?? 0, 789.0 / 2559, accuracy: 0.0001)
        XCTAssertEqual(SlideFonts.ownDescentShare("TH Sarabun New") ?? 0, 789.0 / 2559, accuracy: 0.0001)
        XCTAssertEqual(SlideFonts.ownDescentShare("Angsana New") ?? 0, 0.41 / 1.351, accuracy: 0.0001)
        XCTAssertEqual(SlideFonts.windowsAscentDescent("Cordia New")?.descent ?? 0, 0.496, accuracy: 0.0001)
    }
}
