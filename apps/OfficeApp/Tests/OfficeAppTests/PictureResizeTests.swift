// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import OfficeText
import Flutter
import FlutterSwiftBridge

/// Dragging a picture's handles: with the aspect locked (Word's default) an edge keeps the proportions too.
final class PictureResizeTests: XCTestCase {
    private let start = Size(200, 100)

    func testLockedRightEdgeBringsTheHeightAlong() {
        let s = PictureResize.size(from: start, handle: 3, dx: 100, dy: 0, keepAspect: true, maxWidth: 1000)
        XCTAssertEqual(s.width, 300, accuracy: 0.01)
        XCTAssertEqual(s.height, 150, accuracy: 0.01)
    }

    func testLockedBottomEdgeBringsTheWidthAlong() {
        let s = PictureResize.size(from: start, handle: 5, dx: 0, dy: 50, keepAspect: true, maxWidth: 1000)
        XCTAssertEqual(s.width, 300, accuracy: 0.01)
        XCTAssertEqual(s.height, 150, accuracy: 0.01)
    }

    func testUnlockedEdgeChangesOneSideOnly() {
        let s = PictureResize.size(from: start, handle: 3, dx: 100, dy: 0, keepAspect: false, maxWidth: 1000)
        XCTAssertEqual(s.width, 300, accuracy: 0.01)
        XCTAssertEqual(s.height, 100, accuracy: 0.01)
    }

    func testLockedCornerKeepsTheRatioAndUnlockedCornerDoesNot() {
        let locked = PictureResize.size(from: start, handle: 4, dx: 100, dy: 0, keepAspect: true, maxWidth: 1000)
        XCTAssertEqual(locked.width / locked.height, 2, accuracy: 0.01)
        let free = PictureResize.size(from: start, handle: 4, dx: 100, dy: 0, keepAspect: false, maxWidth: 1000)
        XCTAssertEqual(free.height, 100, accuracy: 0.01)
    }

    func testTheColumnWidthCapsAndLockedKeepsTheRatio() {
        let s = PictureResize.size(from: start, handle: 3, dx: 800, dy: 0, keepAspect: true, maxWidth: 400)
        XCTAssertEqual(s.width, 400, accuracy: 0.01)
        XCTAssertEqual(s.height, 200, accuracy: 0.01)
    }
}
