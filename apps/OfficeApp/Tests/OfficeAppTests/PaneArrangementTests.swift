// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// Where a side pane sits: a sheet in a narrow window, a slide-over under a finger, docked under a pointer.
final class PaneArrangementTests: XCTestCase {
    func testANarrowWindowGetsABottomSheetWhateverDrivesIt() {
        XCTAssertEqual(PaneArrangement.style(narrow: true, touch: true), .bottomSheet)
        XCTAssertEqual(PaneArrangement.style(narrow: true, touch: false), .bottomSheet)
    }

    func testAWideTouchWindowGetsASlideOver() {
        XCTAssertEqual(PaneArrangement.style(narrow: false, touch: true), .slideOver)
    }

    func testAWidePointerWindowDocksThePane() {
        XCTAssertEqual(PaneArrangement.style(narrow: false, touch: false), .docked)
    }
}
