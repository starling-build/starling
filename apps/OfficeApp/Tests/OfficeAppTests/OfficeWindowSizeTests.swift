// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// A scripted run opens the harness's 1440x932 drawing area unless told otherwise; a plain run keeps 1440x900.
final class OfficeWindowSizeTests: XCTestCase {
    func testScriptedRunsOpenTheHarnessSize() {
        let s = OfficeWindowSize.of(["OFFICE_SCRIPT": "/x.script"])
        XCTAssertEqual(s.width, 1440); XCTAssertEqual(s.height, 932)
    }

    func testPlainRunsKeepTheirDefault() {
        let s = OfficeWindowSize.of([:])
        XCTAssertEqual(s.width, 1440); XCTAssertEqual(s.height, 900)
        XCTAssertEqual(OfficeWindowSize.of(["OFFICE_SCRIPT": ""]).height, 900, "an empty variable means unset")
    }

    func testExplicitSizeWins() {
        let s = OfficeWindowSize.of(["OFFICE_SCRIPT": "/x.script", "STARLING_WINDOW_W": "1280", "STARLING_WINDOW_H": "800"])
        XCTAssertEqual(s.width, 1280); XCTAssertEqual(s.height, 800)
        XCTAssertEqual(OfficeWindowSize.of(["OFFICE_SCRIPT": "/x", "STARLING_WINDOW_H": "junk"]).height, 932)
    }
}
