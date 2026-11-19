// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class UpdateCheckTests: XCTestCase {
    final class Store: UpdateStore {
        var d: [String: String] = [:]
        func get(_ k: String) -> String? { d[k] }
        func set(_ k: String, _ v: String) { d[k] = v }
    }
    struct Boom: Error {}

    private let json = """
    [{"tag_name":"desktop-v9.9.9","html_url":"https://x/d"},
     {"tag_name":"office-v0.9.0","html_url":"https://x/9"},
     {"tag_name":"office-v0.10.0","html_url":"https://x/10"},
     {"tag_name":"office-v0.11.0","draft":true,"html_url":"https://x/11"},
     {"tag_name":"office-v0.12.0-rc1","prerelease":true,"html_url":"https://x/12"},
     {"tag_name":"office-v0.13.0","prerelease":true,"html_url":"https://x/13"},
     {"tag_name":"office-vbad","html_url":"https://x/bad"}]
    """.data(using: .utf8)!

    func testVersionComparison() {
        XCTAssertTrue(OfficeVersion.isNewer("0.5.0", than: "0.1.0"))
        XCTAssertTrue(OfficeVersion.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertFalse(OfficeVersion.isNewer("0.9.0", than: "0.10.0"))
        XCTAssertFalse(OfficeVersion.isNewer("0.5.0", than: "0.5.0"))
        XCTAssertTrue(OfficeVersion.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(OfficeVersion.isNewer("0.5.0", than: "dev"))
    }

    func testDevVersionNeverNags() {
        for v in [nil, "", "dev", "0.0.0", "0.5.0-rc1"] as [String?] {
            XCTAssertFalse(OfficeVersion.isCheckable(v), "\(String(describing: v))")
            let store = Store()
            var fetched = false
            let r = UpdateCheck.run(current: v, store: store, now: { 1000 }, fetch: { fetched = true; return self.json })
            XCTAssertNil(r)
            XCTAssertFalse(fetched)
        }
        XCTAssertTrue(OfficeVersion.isCheckable("0.1.0"))
    }

    func testTagFiltering() {
        let r = UpdateCheck.newest(inJSON: json)
        XCTAssertEqual(r, OfficeRelease(version: "0.10.0", url: "https://x/10"))
        XCTAssertNil(UpdateCheck.newest(inJSON: Data("[]".utf8)))
        XCTAssertNil(UpdateCheck.newest(inJSON: Data("not json".utf8)))
    }

    func testDailyThrottleWithInjectedClock() {
        let store = Store()
        var now = 1_000_000.0
        var fetches = 0
        func go() -> OfficeRelease? {
            UpdateCheck.run(current: "0.1.0", store: store, now: { now }, fetch: { fetches += 1; return self.json })
        }
        XCTAssertEqual(go()?.version, "0.10.0")
        XCTAssertEqual(fetches, 1)
        now += 3600
        XCTAssertEqual(go()?.version, "0.10.0")   // announced from the stored sighting
        XCTAssertEqual(fetches, 1)
        now += 24 * 3600
        _ = go()
        XCTAssertEqual(fetches, 2)
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: 5000, now: 100))   // clock went back
    }

    func testOfflineIsSilentAndRetriedNextLaunch() {
        let store = Store()
        var fetches = 0
        var logged: [String] = []
        let r = UpdateCheck.run(current: "0.1.0", store: store, now: { 10 },
                                fetch: { fetches += 1; throw Boom() }, log: { logged.append($0) })
        XCTAssertNil(r)
        XCTAssertEqual(logged.count, 1)
        XCTAssertNil(store.get(UpdateCheck.lastCheckKey))   // a failure does not use up the day
        _ = UpdateCheck.run(current: "0.1.0", store: store, now: { 20 }, fetch: { fetches += 1; throw Boom() })
        XCTAssertEqual(fetches, 2)
        // Garbage in the answer is no release either.
        XCTAssertNil(UpdateCheck.run(current: "0.1.0", store: store, now: { 30 }, fetch: { Data("<html>".utf8) }))
    }

    func testDismissedVersionIsNotShownAgainButANewerOneIs() {
        let store = Store()
        let r = UpdateCheck.run(current: "0.1.0", store: store, now: { 0 }, fetch: { self.json })!
        UpdateCheck.dismiss(r, store: store)
        XCTAssertNil(UpdateCheck.run(current: "0.1.0", store: store, now: { 1 }, fetch: { self.json }))
        store.set(UpdateCheck.dismissedKey, "0.9.0")
        XCTAssertEqual(UpdateCheck.run(current: "0.1.0", store: store, now: { 2 }, fetch: { self.json })?.version, "0.10.0")
    }

    func testAlreadyCurrentIsNotAnnounced() {
        XCTAssertNil(UpdateCheck.run(current: "0.10.0", store: Store(), now: { 0 }, fetch: { self.json }))
        XCTAssertNil(UpdateCheck.run(current: "0.11.0", store: Store(), now: { 0 }, fetch: { self.json }))
    }
}
