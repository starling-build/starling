// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// A .doc table row that does not set sprmTDxaGapHalf keeps Word's default cell gap (108 twips each side).
final class DocTableGapTests: XCTestCase {
    private func row(extra: [UInt8] = []) -> [UInt8] {
        // sprmTDefTable: one cell, edges 0 and 2000, one 20-byte TC; the operand is preceded by a 16-bit length that counts itself less one.
        var operand: [UInt8] = [1, 0, 0, 0xD0, 0x07]
        operand += [UInt8](repeating: 0, count: 20)
        let len = operand.count + 1
        return [0x08, 0xD6, UInt8(len & 0xFF), UInt8(len >> 8)] + operand + extra
    }

    func testDefaultGapIs108() throws {
        let r = try XCTUnwrap(DocProps.row(row()))
        XCTAssertTrue(r.tblPr.contains("<w:left w:w=\"108\""), r.tblPr)
        XCTAssertTrue(r.tblPr.contains("<w:tblInd w:w=\"108\""), r.tblPr)
    }

    func testExplicitGapWins() throws {
        let r = try XCTUnwrap(DocProps.row(row(extra: [0x02, 0x96, 0x28, 0x00])))   // sprmTDxaGapHalf = 40
        XCTAssertTrue(r.tblPr.contains("<w:left w:w=\"40\""), r.tblPr)
    }
}
