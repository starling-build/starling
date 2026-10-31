// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// ICU's data for the whole test process, loaded before any test lays text
/// out. The line fitter measures each character as the engine shapes it,
/// and the engine sets up its text state on the first layout: loaded after
/// that, the data does nothing and every character measures zero wide.
/// The app loads it first thing (`main.swift`); a test process has no such
/// start, so the first class to run (they run by name, and this one sorts
/// first) loads it, and so does `DocxTests` for a run filtered to it.
enum TestText {
    /// Whether ICU's data is in the bridge (from `STARLING_ICU`, else
    /// `icudtl.dat` in `FLUTTER_SWIFT_ENGINE_OUT` or `STARLING_ENGINE_OUT`).
    static let icuLoaded: Bool = {
        let env = ProcessInfo.processInfo.environment
        let engineOut = env["FLUTTER_SWIFT_ENGINE_OUT"] ?? env["STARLING_ENGINE_OUT"]
        guard let icu = env["STARLING_ICU"] ?? engineOut.map({ $0 + "/icudtl.dat" }),
              FileManager.default.fileExists(atPath: icu) else { return false }
        return flutter.swift_bridge.InitializeICU(icu)
    }()
}

final class AAATextSetupTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
    }

    func testICUDataIsLoadedBeforeAnyTextIsLaidOut() throws {
        guard TestText.icuLoaded else { throw XCTSkip("ICU unavailable (STARLING_ICU, FLUTTER_SWIFT_ENGINE_OUT or STARLING_ENGINE_OUT)") }
    }

    func testBundledOfficeFontsLoadBeforeLayoutTests() {
        XCTAssertTrue(OfficeFonts.register(), "layout tests must use the shipped fonts, not a system fallback")
        XCTAssertTrue(OfficeFonts.register(), "repeated registration reports the same result")
    }
}
