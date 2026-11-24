// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocVerdanaKernTests: XCTestCase {
    /// A .doc run's kerning size (sprm 0x484B, half-points) is read as w:kern.
    func testDocRunKernIsRead() {
        let xml = DocProps.rPr([0x4B, 0x48, 0x14, 0x00], fonts: [])
        XCTAssertTrue(xml.contains("<w:kern w:val=\"20\"/>"), xml)
    }

    /// Verdana's own pair table: "F," pulls 0.1465 em, as Word's print of Verdana text shows.
    func testVerdanaPairTable() {
        let v = VerdanaKerns.regular[(0x46 << 8) | 0x2C]
        XCTAssertNotNil(v)
        XCTAssertEqual(v ?? 0, -0.1465, accuracy: 0.0002)
        XCTAssertGreaterThan(VerdanaKerns.regular.count, 300)
    }
}
