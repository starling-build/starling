// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// A plain open-and-save keeps the sheet view and the row/column settings the file had (amd-8's save-loss sweep).
final class SheetsSaveLossTests: XCTestCase {
    /// A one-sheet book whose sheet1.xml is `sheetXML`, saved once through our writer; returns the saved sheet1.xml.
    private func resave(_ sheetXML: String) throws -> String {
        let c = WorkbookController()
        c.setInput("1", at: CellAddress(row: 0, col: 0))
        var entries = try Zip.read(try Xlsx.write(c.book))
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "xl/worksheets/sheet1.xml" })
        entries[i] = ZipEntry(name: entries[i].name, data: Data(sheetXML.utf8))
        let again = WorkbookController()
        again.load(try Xlsx.read(try Zip.write(entries)))
        let saved = try Zip.read(try Xlsx.write(again.book))
        return String(decoding: try XCTUnwrap(saved.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
    }
    private func sheet(views: String = "", cols: String = "", rows: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
            + "<sheetViews>\(views)</sheetViews>" + cols + "<sheetData>\(rows)</sheetData></worksheet>"
    }

    func testHiddenRowsHeightsAndSpansSurvive() throws {
        let out = try resave(sheet(rows: "<row r=\"1\" spans=\"1:3\"><c r=\"A1\"><v>1</v></c><c r=\"C1\"><v>3</v></c></row>"
            + "<row r=\"2\" hidden=\"1\" ht=\"30\" customHeight=\"1\"><c r=\"A2\"><v>2</v></c></row>"
            + "<row r=\"3\" spans=\"2:4\"/>"))
        XCTAssertTrue(out.containsSubstring("<row r=\"1\" spans=\"1:3\""), out)
        XCTAssertTrue(out.containsSubstring("hidden=\"1\"") && out.containsSubstring("ht=\"30\""), out)
        XCTAssertTrue(out.containsSubstring("<row r=\"3\" spans=\"2:4\"/>"), "an empty row keeps its span: " + out)
    }

    func testHiddenColumnRunToTheEdgeAndFalseGridlinesSurvive() throws {
        let out = try resave(sheet(views: "<sheetView showGridLines=\"false\" workbookViewId=\"0\"><selection activeCell=\"A1\" sqref=\"A1\"/></sheetView>",
                                   cols: "<cols><col min=\"11\" max=\"16384\" width=\"11.4\" hidden=\"1\"/></cols>",
                                   rows: "<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>"))
        XCTAssertTrue(out.containsSubstring("showGridLines=\"0\""), out)
        XCTAssertTrue(out.containsSubstring("min=\"11\" max=\"16384\"") && out.containsSubstring("hidden=\"1\""), out)
    }

    func testSelectionsOfEveryPaneAndRangesSurvive() throws {
        let views = "<sheetView workbookViewId=\"0\"><pane xSplit=\"1\" ySplit=\"1\" topLeftCell=\"B2\" activePane=\"bottomRight\" state=\"frozen\"/>"
            + "<selection pane=\"topRight\" activeCell=\"B1\" sqref=\"B1\"/><selection pane=\"bottomLeft\" activeCell=\"A2\" sqref=\"A2\"/>"
            + "<selection pane=\"bottomRight\" activeCell=\"C4\" activeCellId=\"1\" sqref=\"B2:C3 C4\"/></sheetView>"
        let out = try resave(sheet(views: views, rows: "<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>"))
        XCTAssertTrue(out.containsSubstring("pane=\"topRight\"") && out.containsSubstring("pane=\"bottomLeft\""), out)
        XCTAssertTrue(out.containsSubstring("activeCellId=\"1\"") && out.containsSubstring("sqref=\"B2:C3 C4\""), out)
    }

    /// Hook for the Excel check: SAVELOSS_CHECK_IN=<book> SAVELOSS_CHECK_OUT=<path> writes the book through a plain open-and-save.
    func testWriteCheckBook() throws {
        let env = ProcessInfo.processInfo.environment
        guard let inp = env["SAVELOSS_CHECK_IN"], let out = env["SAVELOSS_CHECK_OUT"] else { throw XCTSkip("no SAVELOSS_CHECK_IN") }
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: URL(fileURLWithPath: inp))))
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: out))
    }
}
