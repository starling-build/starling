// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocSectionAfterTableTests: XCTestCase {
    /// A section mark (0C) right after a table (es-b5e3e00ade): the table is written before the paragraph that
    /// closes the section, not after it. It came out after, so the cover section was an empty paragraph and
    /// the table landed in the next section behind a blank page.
    func testTableComesBeforeTheSectionMark() {
        let inTable: [UInt8] = [0x16, 0x24, 1]
        let rowDef: [UInt8] = [0x08, 0xD6, 6, 0, 1, 0, 0, 0xE8, 0x03]
        let t: [UInt16] = [0x41, 0x07, 0x07, 0x0C]
        let pap = [
            DocPropRun(cp: 0, cpEnd: 2, grpprl: inTable),
            DocPropRun(cp: 2, cpEnd: 3, grpprl: inTable + [0x17, 0x24, 1] + rowDef),
        ]
        var ctx = DocRead.StoryContext()
        ctx.sectEnds = [3: "<w:sectPr><w:type w:val=\"nextPage\"/></w:sectPr>"]
        let xml = DocRead.paragraphs(t, pap: pap, ctx: ctx)
        let table = xml.range(of: "<w:tbl>")
        let sect = xml.range(of: "<w:sectPr>")
        XCTAssertNotNil(table, xml)
        XCTAssertNotNil(sect, xml)
        if let table, let sect { XCTAssertLessThan(table.lowerBound, sect.lowerBound, xml) }
    }
}
