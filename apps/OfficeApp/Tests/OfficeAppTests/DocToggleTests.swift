// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class DocToggleTests: XCTestCase {
    /// A character flag stored as 0x81 is the opposite of what the paragraph style gives: bold in a bold style
    /// is off, bold in a plain style is on. It was read as plain "on" either way.
    private let boldOp: [UInt8] = [0x35, 0x08, 0x81]   // sprmCFBold, toggle

    func testAToggleReadsAsAToggleMarker() {
        let xml = DocProps.rPr(boldOp, fonts: [], toggles: true)
        XCTAssertTrue(xml.contains("<w:b w:val=\"toggle\"/>"), xml)
    }

    func testAToggleOnAPlainStyleIsOn() {
        let styles = "<w:style w:styleId=\"S0\"><w:rPr></w:rPr></w:style>"
        let out = DocProps.settleToggles("<w:rPr><w:b w:val=\"toggle\"/></w:rPr>", styles: styles, istd: 0)
        XCTAssertEqual(out, "<w:rPr><w:b/></w:rPr>")
    }

    func testAToggleOnABoldStyleIsOff() {
        let styles = "<w:style w:styleId=\"S0\"><w:rPr><w:b/></w:rPr></w:style>"
        let out = DocProps.settleToggles("<w:rPr><w:b w:val=\"toggle\"/></w:rPr>", styles: styles, istd: 0)
        XCTAssertEqual(out, "<w:rPr><w:b w:val=\"0\"/></w:rPr>")
    }
}
