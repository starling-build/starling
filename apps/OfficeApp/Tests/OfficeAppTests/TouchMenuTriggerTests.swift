// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import XCTest
@testable import OfficeApp

/// The touch way to a right-click menu: two fingers tapped together in place open it where the second one landed; a finger
/// that drifts, a second listener seeing the same finger, and a mouse press do not.
final class TouchMenuTriggerTests: XCTestCase {
    private func down(_ t: TouchMenuTrigger, _ pointer: Int, _ x: Double, kind: PointerDeviceKind = .touch,
                      fire: @escaping (Offset) -> Void) -> Bool {
        t.down(PointerDownEvent(pointer: pointer, kind: kind, position: Offset(x, 10)), hold: false, fire: fire)
    }

    func testTwoFingersDownAndUpInPlaceOpenTheMenuAtTheSecond() {
        let t = TouchMenuTrigger()
        var fired: [Offset] = []
        XCTAssertFalse(down(t, 1, 10) { fired.append($0) })
        XCTAssertTrue(down(t, 2, 40) { fired.append($0) })
        t.up(1)
        XCTAssertTrue(fired.isEmpty, "not until the last finger is up")
        t.up(2)
        XCTAssertEqual(fired, [Offset(40, 10)])
    }

    func testAFingerThatDriftsIsNotATap() {
        let t = TouchMenuTrigger()
        var fired = 0
        _ = down(t, 1, 10) { _ in fired += 1 }
        _ = down(t, 2, 40) { _ in fired += 1 }
        t.moved(2, Offset(40 + TouchMenuTrigger.slop + 1, 10))
        t.up(1); t.up(2)
        XCTAssertEqual(fired, 0)
    }

    func testTheSameFingerReachingASecondListenerIsNotASecondFinger() {
        let t = TouchMenuTrigger()
        XCTAssertFalse(down(t, 1, 10) { _ in })
        XCTAssertFalse(down(t, 1, 10) { _ in })
    }

    func testAMousePressIsLeftAlone() {
        let t = TouchMenuTrigger()
        XCTAssertFalse(down(t, 1, 10, kind: .mouse) { _ in })
        XCTAssertFalse(down(t, 2, 40, kind: .mouse) { _ in })
    }

    func testAFingerHeldStillOpensTheMenuAtIt() {
        let t = TouchMenuTrigger()
        let held = expectation(description: "menu")
        var at: Offset?
        _ = t.down(PointerDownEvent(pointer: 1, kind: .touch, position: Offset(7, 9)), hold: true) { at = $0; held.fulfill() }
        wait(for: [held], timeout: 2)
        XCTAssertEqual(at, Offset(7, 9))
    }

    func testAFingerThatLiftsEarlyIsNotHolding() {
        let t = TouchMenuTrigger()
        var fired = false
        _ = t.down(PointerDownEvent(pointer: 1, kind: .touch, position: Offset(7, 9)), hold: true) { _ in fired = true }
        t.up(1)
        let wait = expectation(description: "past the delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + TouchMenuTrigger.holdDelay + 0.2) { wait.fulfill() }
        self.wait(for: [wait], timeout: 2)
        XCTAssertFalse(fired)
    }
}
