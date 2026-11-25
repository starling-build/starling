// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsHyperlinkEditTests: XCTestCase {
    private func a(_ r: Int, _ c: Int) -> CellAddress { CellAddress(row: r, col: c) }

    func testUrlLinkRoundTripsAndUndoes() throws {
        let c = WorkbookController()
        c.setLink(CellRange(a(0, 0), a(0, 0)), .url("https://example.com/p#top"))
        XCTAssertEqual(c.link(at: a(0, 0)), .url("https://example.com/p#top"))
        XCTAssertEqual(c.sheet.cells[a(0, 0)]?.value.isEmpty, false, "an empty cell shows the address")
        let back = try Xlsx.read(try Xlsx.write(c.book))
        let c2 = WorkbookController(); c2.load(back)
        XCTAssertEqual(c2.link(at: a(0, 0)), .url("https://example.com/p#top"))
        c.undo(); c.undo()
        XCTAssertNil(c.link(at: a(0, 0)))
    }

    func testPlaceLinkAndRemoveKeepsText() throws {
        let c = WorkbookController()
        c.addSheet()
        c.activeSheet = 0
        c.setInput("go", at: a(1, 1))
        c.setLink(CellRange(a(1, 1), a(1, 1)), .place("Sheet2!B3"))
        XCTAssertEqual(c.link(at: a(1, 1)), .place("Sheet2!B3"))
        c.removeLink(CellRange(a(1, 1), a(1, 1)))
        XCTAssertNil(c.link(at: a(1, 1)))
        XCTAssertEqual(c.sheet.cells[a(1, 1)]?.value.isEmpty, false)
    }

    func testRelationshipIsMarkedExternal() throws {
        let c = WorkbookController()
        c.setLink(CellRange(a(0, 0), a(0, 0)), .url("https://example.com"))
        let rels = Xlsx._relsXML([("rId1", "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink", "https://example.com")])
        XCTAssertTrue(rels.containsSubstring("TargetMode=\"External\""))
    }

    func testEditingReplacesTheOldLink() {
        let c = WorkbookController()
        let r = CellRange(a(0, 0), a(0, 0))
        c.setLink(r, .url("https://one.example"))
        c.setLink(r, .url("https://two.example"))
        XCTAssertEqual(c.link(at: a(0, 0)), .url("https://two.example"))
        let kept = c.sheet.keptElements.first { $0.name == "hyperlinks" }?.text ?? ""
        XCTAssertEqual(WorkbookController._linkEntries(kept).count, 1)
    }

    /// Writes the file for the Excel check (only when XCHECK_DIR is set).
    func testWriteExcelCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let c = WorkbookController()
        c.addSheet()
        c.activeSheet = 0
        c.setInput("Plain", at: a(0, 0))
        c.setLink(CellRange(a(1, 0), a(1, 0)), .url("https://example.com/page#top"), tip: "The example site")
        c.setLink(CellRange(a(2, 0), a(2, 0)), .url("mailto:me@example.com"))
        c.setLink(CellRange(a(3, 0), a(3, 0)), .place("Sheet2!B3"))
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/7-hyperlinks.xlsx"))
    }
}
