// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocHeaderStoryTests: XCTestCase {
    /// A story's last mark closes it: "text CR CR CR" is the text's paragraph and one empty paragraph.
    func testStoryLastMarkTakesNoLine() {
        let t: [UInt16] = [0x41, 0x0D, 0x0D, 0x0D]
        let xml = DocRead.paragraphs(Array(t[..<DocRead.storyEnd(0, t.count)]))
        XCTAssertEqual(xml.components(separatedBy: "<w:p>").count - 1, 2)
        XCTAssertEqual(DocRead.storyEnd(5, 6), 6)  // a lone mark stays
    }

    /// A binary file's pages break as Word's earlier modes do.
    func testSettingsCarrySplitBreakFlag() {
        XCTAssertTrue(DocRead.settingsXML(facing: false).contains("<w:splitPgBreakAndParaMark/>"))
        XCTAssertFalse(DocRead.settingsXML(facing: false).contains("evenAndOddHeaders"))
        XCTAssertTrue(DocRead.settingsXML(facing: true).contains("evenAndOddHeaders"))
    }
}
