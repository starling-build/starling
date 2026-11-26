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

    /// Excel refuses a sheet whose x14:sparklineGroups is empty (0x800A03EC, even
    /// with repair; the print box bisected cf-manage-x14.xlsx, 2026-11-26), so the
    /// save drops that ext and keeps the others.
    func testAnEmptySparklineGroupsExtIsNotWritten() throws {
        let x14 = "http://schemas.microsoft.com/office/spreadsheetml/2009/9/main"
        let ext = "<extLst><ext uri=\"{05C60535-1F16-4fd2-B633-F4F36F0B64E0}\" xmlns:x14=\"\(x14)\"><x14:sparklineGroups xmlns:xm=\"http://schemas.microsoft.com/office/excel/2006/main\"/></ext>"
            + "<ext uri=\"{FCE2AD5D-F65C-4FA6-A056-5C36A1767C68}\" xmlns:x15=\"http://schemas.microsoft.com/office/spreadsheetml/2010/11/main\"><x15:dataModel/></ext></extLst>"
        let base = sheet(rows: "<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>")
        let out = try resave(base.replacingAll("</worksheet>", with: ext + "</worksheet>"))
        XCTAssertFalse(out.containsSubstring("sparklineGroups"), out)
        XCTAssertTrue(out.containsSubstring("<x15:dataModel/>"), out)
        let only = try resave(base.replacingAll("</worksheet>", with: "<extLst><ext uri=\"{05C60535-1F16-4fd2-B633-F4F36F0B64E0}\" xmlns:x14=\"\(x14)\"><x14:sparklineGroups/></ext></extLst></worksheet>"))
        XCTAssertFalse(only.containsSubstring("extLst"), "nothing left, no extLst: " + only)
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
        XCTAssertTrue(out.containsSubstring("width=\"11.4\""), "a hidden run keeps its own width: " + out)
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

    /// customHeight stays as read: a fitted row (ht without it) is refitted by Excel on open, a sized one is not.
    func testCustomHeightStaysAsRead() throws {
        let out = try resave(sheet(rows: "<row r=\"1\" ht=\"21.5\"><c r=\"A1\"><v>1</v></c></row>"
            + "<row r=\"2\" ht=\"30\" customHeight=\"1\"><c r=\"A2\"><v>2</v></c></row>"))
        XCTAssertTrue(out.containsSubstring("<row r=\"1\" ht=\"21.5\" spans"), "a fitted row gets no customHeight: " + out)
        XCTAssertTrue(out.containsSubstring("ht=\"30\" customHeight=\"1\""), out)
        // The user sizing a fitted row makes it a sized one.
        let c = WorkbookController()
        c.load(try Xlsx.read(try Zip.write({
            var e = try Zip.read(try Xlsx.write(WorkbookController().book))
            let i = try XCTUnwrap(e.firstIndex { $0.name == "xl/worksheets/sheet1.xml" })
            e[i] = ZipEntry(name: e[i].name, data: Data(sheet(rows: "<row r=\"1\" ht=\"21.5\"><c r=\"A1\"><v>1</v></c></row>").utf8))
            return e
        }())))
        c.setRowHeight(0, 40)
        let saved = try Zip.read(try Xlsx.write(c.book))
        let xml = String(decoding: try XCTUnwrap(saved.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("ht=\"40\" customHeight=\"1\""), xml)
    }
}
