// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// A font-table entry of an East Asian charset is never read as a Thaana face (한컴바탕's table sets every script bit).
final class DocxThaanaCharsetTests: XCTestCase {
    func testEastAsianCharsetsAreRecognised() {
        for c in ["80", "81", "86", "88", "8a"] { XCTAssertEqual(DocxFormat.isEastAsianCharset(c), c != "8a", c) }
        XCTAssertFalse(DocxFormat.isEastAsianCharset("00"))
        XCTAssertFalse(DocxFormat.isEastAsianCharset(nil))
    }

    func testHangulFaceWithAllScriptBitsIsNotThaana() throws {
        let font = """
        <w:fonts xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:font w:name="한컴바탕"><w:charset w:val="81"/><w:sig w:usb0="FFFFFFFF" w:usb1="FFFFFFFF" w:usb2="FFFFFFFF" w:usb3="FFFFFFFF" w:csb0="FFFFFFFF" w:csb1="FFFFFFFF"/></w:font></w:fonts>
        """
        let r = try DocxFormat.thaanaFaceNames(fontTableXML: font)
        XCTAssertTrue(r.isEmpty, "\(r)")
    }
}
