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

    func testLinkWearsTheHyperlinkCellStyleAndRemoveGivesItUp() throws {
        let c = WorkbookController()
        let r = CellRange(a(0, 0), a(0, 0))
        c.setInput("site", at: a(0, 0))
        c.setLink(r, .url("https://example.com"))
        XCTAssertTrue(c.style(at: a(0, 0)).linkStyle)
        XCTAssertTrue(c.style(at: a(0, 0)).underline)
        XCTAssertEqual(c.style(at: a(0, 0)).color, 0x0563C1)
        let bytes = try Xlsx.write(c.book)
        let styles = String(decoding: try XCTUnwrap(Zip.read(bytes).first { $0.name == "xl/styles.xml" }).data, as: UTF8.self)
        XCTAssertTrue(styles.containsSubstring("name=\"Hyperlink\" xfId=\"1\" builtinId=\"8\""), styles)
        XCTAssertTrue(styles.containsSubstring("<cellStyleXfs count=\"2\">"), styles)
        let c2 = WorkbookController(); c2.load(try Xlsx.read(bytes))
        XCTAssertTrue(c2.style(at: a(0, 0)).linkStyle, "the look survives a save and open")
        c2.removeLink(r)
        XCTAssertFalse(c2.style(at: a(0, 0)).linkStyle)
        XCTAssertFalse(c2.style(at: a(0, 0)).underline)
        XCTAssertNil(c2.style(at: a(0, 0)).color)
        // A cell the user restyled keeps its own look when the link goes.
        c2.setLink(r, .url("https://example.com"))
        c2.setStyle({ $0.linkStyle = false; $0.color = 0xFF0000 }, range: r)
        c2.removeLink(r)
        XCTAssertEqual(c2.style(at: a(0, 0)).color, 0xFF0000)
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
