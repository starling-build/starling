// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import OfficeApp

final class DocFramedTablePageTests: XCTestCase {
    /// A table whose every paragraph carries one frame centred on the margin, `y` down the page
    /// (pt-9b0c0c8f79): Word floats the table there, centred, and the frame goes off the paragraphs.
    func testPageAnchoredCentredFrameFloatsTheTable() {
        let frame = "<w:framePr w:hAnchor=\"margin\" w:vAnchor=\"page\" w:xAlign=\"center\" w:y=\"1951\" w:wrap=\"around\"/>"
        let xml = "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:tbl><w:tblPr/><w:tblGrid/>"
            + "<w:tr><w:tc><w:p><w:pPr>\(frame)</w:pPr></w:p></w:tc></w:tr></w:tbl></w:body></w:document>"
        let root = XNode.parse(Data(xml.utf8))!
        DocxFormat._floatFramedTables(root)
        let pos = root.descendant("w:tblpPr")
        XCTAssertEqual(pos?["w:tblpY"], "1951")
        XCTAssertEqual(pos?["w:vertAnchor"], "page")
        XCTAssertEqual(pos?["w:horzAnchor"], "margin")
        XCTAssertEqual(pos?["w:tblpXSpec"], "center")
        XCTAssertNil(root.descendant("w:framePr"))
    }
}
