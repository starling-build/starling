// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocListDefaultsTests: XCTestCase {
    /// The level records (LVL) of a .doc's lists follow the list headers right after PlfLst, outside the
    /// length the file records for it (lcb covers cLst and the headers only). They were not read, so every
    /// list lost its number format and text (pt-90497db98b's bullets, es-ba5f76665c's bullets).
    func testLevelRecordsPastTheRecordedLengthAreRead() {
        var t = [UInt8](repeating: 0, count: 30)
        t[0] = 1                 // cLst = 1
        t[2] = 0x2A              // lsid
        t[2 + 26] = 1            // a simple (single-level) list
        // The LVL: 28-byte LVLF, then the text (u16 cch = 3, then UTF-16: two level-1 number marks and ".").
        var lvl = [UInt8](repeating: 0, count: 28)
        lvl[0] = 3               // start at 3
        lvl[4] = 4               // nfc 4: lowerLetter
        let table = t + lvl + [3, 0, 0, 0, 0, 0, 0x2E, 0]
        var lfo = [UInt8](repeating: 0, count: 20)
        lfo[0] = 1               // one LFO
        lfo[4] = 0x2A            // its lsid
        let all = table + lfo
        let xml = DocProps.numbering(all, lst: (fc: 0, lcb: 30), lfo: (fc: table.count, lcb: 20), fonts: []) ?? ""
        XCTAssertTrue(xml.contains("<w:numFmt w:val=\"lowerLetter\"/>"), xml)
        XCTAssertTrue(xml.contains("<w:start w:val=\"3\"/>"), xml)
        XCTAssertTrue(xml.contains("<w:lvlText w:val=\"%1%1.\"/>"), xml)
    }
}
