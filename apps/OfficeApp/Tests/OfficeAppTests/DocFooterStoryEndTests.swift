// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// The paragraph mark that ends a .doc footer story is not a line of its own.
final class DocFooterStoryEndTests: XCTestCase {
    func testFooterLosesItsStoryEnd() {
        let xml = "<w:p><w:r><w:t>a</w:t></w:r></w:p><w:p></w:p>"
        XCTAssertEqual(DocRead.withoutStoryEnd(xml, isFooter: true), "<w:p><w:r><w:t>a</w:t></w:r></w:p>")
    }
    func testHeaderKeepsIt() {
        let xml = "<w:p><w:r><w:t>a</w:t></w:r></w:p><w:p></w:p>"
        XCTAssertEqual(DocRead.withoutStoryEnd(xml, isFooter: false), xml)
    }
    func testTableMustBeFollowedByAParagraph() {
        let xml = "<w:tbl></w:tbl><w:p></w:p>"
        XCTAssertEqual(DocRead.withoutStoryEnd(xml, isFooter: true), xml)
    }
    func testLoneParagraphStays() {
        XCTAssertEqual(DocRead.withoutStoryEnd("<w:p></w:p>", isFooter: true), "<w:p></w:p>")
    }
}
