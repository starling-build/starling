// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// The .doc reader's auto spacing (sprmPFDyaBeforeAuto / AfterAuto) and section text grid (sprmSClm, DyaLinePitch, DxtCharSpace).
final class DocSpacingGridTests: XCTestCase {
    private func sprm(_ op: Int, _ operand: [UInt8]) -> [UInt8] { [UInt8(op & 0xFF), UInt8(op >> 8)] + operand }

    func testAutoSpacingIsWrittenAsAutospacing() {
        let g = sprm(0x245B, [1]) + sprm(0x245C, [1])
        let x = DocProps.pPr(g)
        XCTAssertTrue(x.contains("w:beforeAutospacing=\"1\""), x)
        XCTAssertTrue(x.contains("w:afterAutospacing=\"1\""), x)
    }

    func testAutoSpacingOffIsWrittenZero() {
        let x = DocProps.pPr(sprm(0x245B, [0]))
        XCTAssertTrue(x.contains("w:beforeAutospacing=\"0\""), x)
    }

    func testSectionTextGridIsWrittenAsDocGrid() {
        // clm 2 (lines), pitch 360 twips, char space 0
        let g = sprm(0x5032, [2, 0]) + sprm(0x9031, [0x68, 0x01])
        let x = DocProps.sectPr(g, refs: "")
        XCTAssertTrue(x.contains("<w:docGrid w:type=\"lines\" w:linePitch=\"360\"/>"), x)
    }

    func testSectionTextGridCarriesCharSpace() {
        let g = sprm(0x5032, [1, 0]) + sprm(0x9031, [0x68, 0x01]) + sprm(0x7030, [0x00, 0x10, 0, 0])
        let x = DocProps.sectPr(g, refs: "")
        XCTAssertTrue(x.contains("w:type=\"linesAndChars\""), x)
        XCTAssertTrue(x.contains("w:charSpace=\"4096\""), x)
    }

    func testNegativeCharSpaceIsSigned() {
        // -50 as a 32-bit value: it shrinks the cell, it is not a 4-billion-twip pitch
        let g = sprm(0x5032, [1, 0]) + sprm(0x9031, [0x68, 0x01]) + sprm(0x7030, [0xCE, 0xFF, 0xFF, 0xFF])
        let x = DocProps.sectPr(g, refs: "")
        XCTAssertTrue(x.contains("w:charSpace=\"-50\""), x)
    }

    func testNoGridWithoutClm() {
        XCTAssertFalse(DocProps.sectPr([], refs: "").contains("docGrid"))
    }
}
