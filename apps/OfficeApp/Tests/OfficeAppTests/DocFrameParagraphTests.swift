// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocFrameParagraphTests: XCTestCase {
    /// A paragraph in a text frame (pt-90497db98b: the page number in the header, right-aligned beside the
    /// title) keeps its frame, so it no longer takes a line of its own.
    func testFrameSprmsBecomeFramePr() {
        let g: [UInt8] = [0x1B, 0x26, 96, 0x18, 0x84, 0xF8, 0xFF, 0x19, 0x84, 1, 0, 0x23, 0x24, 2]
        let x = DocProps.pPr(g)
        XCTAssertTrue(x.containsSubstring("<w:framePr"), x)
        XCTAssertTrue(x.containsSubstring("w:xAlign=\"right\""), x)
        XCTAssertTrue(x.containsSubstring("w:hAnchor=\"margin\""), x)
        XCTAssertTrue(x.containsSubstring("w:vAnchor=\"text\""), x)
        XCTAssertTrue(x.containsSubstring("w:y=\"1\""), x)
        XCTAssertTrue(x.containsSubstring("w:wrap=\"around\""), x)
    }

    func testNoFrameSprmsNoFramePr() {
        XCTAssertFalse(DocProps.pPr([0x06, 0x24, 1]).containsSubstring("framePr"))
    }
}
