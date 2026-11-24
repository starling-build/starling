// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocNestedTableTests: XCTestCase {
    /// A table in a table's cell (pt-e292e4c4dc, es-ab3945e997): the inner cells and row end are 0D marks flagged 0x244B /
    /// 0x244C, at table depth 2. They make a table inside the outer cell, not more cells of the outer row.
    func testInnerTableStaysInOuterCell() {
        let inTable: [UInt8] = [0x16, 0x24, 1]
        let depth2: [UInt8] = [0x49, 0x66, 2, 0, 0, 0]
        let rowDef: [UInt8] = [0x08, 0xD6, 6, 0, 1, 0, 0, 0xE8, 0x03]
        let t: [UInt16] = [0x4F, 0x0D, 0x49, 0x0D, 0x0D, 0x07, 0x07]
        let pap = [
            DocPropRun(cp: 0, cpEnd: 2, grpprl: inTable),
            DocPropRun(cp: 2, cpEnd: 4, grpprl: inTable + depth2 + [0x4B, 0x24, 1]),
            DocPropRun(cp: 4, cpEnd: 5, grpprl: inTable + depth2 + [0x4B, 0x24, 1, 0x4C, 0x24, 1] + rowDef),
            DocPropRun(cp: 5, cpEnd: 6, grpprl: inTable),
            DocPropRun(cp: 6, cpEnd: 7, grpprl: inTable + [0x17, 0x24, 1] + rowDef),
        ]
        let xml = DocRead.paragraphs(t, pap: pap)
        XCTAssertEqual(xml.components(separatedBy: "<w:tbl>").count - 1, 2, xml)
        XCTAssertEqual(xml.components(separatedBy: "<w:tr>").count - 1, 2, xml)
        let outerCell = xml.range(of: "<w:tc>")!.upperBound
        let innerTable = xml.range(of: "<w:tbl>", range: outerCell ..< xml.endIndex)!.lowerBound
        let outerEnd = xml.range(of: "</w:tc>", options: .backwards)!.lowerBound
        XCTAssertLessThan(innerTable, outerEnd, xml)
        XCTAssertEqual(xml.components(separatedBy: "</w:tc>").count - 1, 2, xml)
    }
}
