// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
import Flutter
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
    /// `icudtl.dat` in `FLUTTER_SWIFT_ENGINE_OUT`).
    static let icuLoaded: Bool = {
        let env = ProcessInfo.processInfo.environment
        guard let icu = env["STARLING_ICU"] ?? env["FLUTTER_SWIFT_ENGINE_OUT"].map({ $0 + "/icudtl.dat" }),
              FileManager.default.fileExists(atPath: icu) else { return false }
        _ = flutter.swift_bridge.InitializeICU(icu)
        return true
    }()
}

final class AAATextSetupTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = TestText.icuLoaded
    }

    func testICUDataIsLoadedBeforeAnyTextIsLaidOut() throws {
        guard TestText.icuLoaded else { throw XCTSkip("no icudtl.dat (STARLING_ICU or FLUTTER_SWIFT_ENGINE_OUT)") }
    }
}
