// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsTableTests: XCTestCase {
    /// The fixture with a table over 'Single double'!D3:J10 (its data).
    private func withTable() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        var entries = try Zip.read(try Data(contentsOf: url))
        let names = ["Run", "gcc 4.4.0 (32)", "VC++ 10 (32)", "Intel 11.1 (32)", "gcc 4.4.0 (64)", "VC++ 10 (64)", "Intel 11.1 (64)"]
        let cols = names.enumerated().map { "<tableColumn id=\"\($0.offset + 1)\" name=\"\($0.element)\"/>" }.joined()
        let table = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<table xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" id=\"1\" name=\"Table1\" displayName=\"Table1\" ref=\"D3:J10\" totalsRowShown=\"0\"><autoFilter ref=\"D3:J10\"><filterColumn colId=\"1\"><filters><filter val=\"0.737\"/></filters></filterColumn></autoFilter><tableColumns count=\"7\">\(cols)</tableColumns><tableStyleInfo name=\"TableStyleMedium2\" showFirstColumn=\"0\" showLastColumn=\"0\" showRowStripes=\"1\" showColumnStripes=\"0\"/></table>"
        entries.append(ZipEntry(name: "xl/tables/table1.xml", data: Data(table.utf8)))
        for i in entries.indices {
            switch entries[i].name {
            case "xl/worksheets/sheet1.xml":
                var s = String(decoding: entries[i].data, as: UTF8.self)
                let end = try XCTUnwrap(s.findRange(of: "</worksheet>"))
                s.replaceSubrange(end, with: "<tableParts count=\"1\"><tablePart r:id=\"rIdT\"/></tableParts></worksheet>")
                entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
            case "xl/worksheets/_rels/sheet1.xml.rels":
                var s = String(decoding: entries[i].data, as: UTF8.self)
                let end = try XCTUnwrap(s.findRange(of: "</Relationships>"))
                s.replaceSubrange(end, with: "<Relationship Id=\"rIdT\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/table\" Target=\"../tables/table1.xml\"/></Relationships>")
                entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
            default: break
            }
        }
        return try Zip.write(entries)
    }

    func testTableFollowsRowsColumnsAndHeaders() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try withTable()))
        XCTAssertEqual(c.sheet.tables.first?.ref, CellRange("D3:J10"))
        c.insert(.rows, at: 5)                 // inside the data: the table grows
        c.insert(.cols, at: 5)                 // a new column F inside it
        c.setInputs([(CellAddress("E3")!, "GCC 32-bit"), (CellAddress("H3")!, "")])
        let t = try XCTUnwrap(c.sheet.tables.first)
        XCTAssertEqual(t.ref, CellRange("D3:K11"))
        XCTAssertEqual(t.columnIds, [1, 2, nil, 3, 4, 5, 6, 7])

        let saved = try Zip.read(try Xlsx.write(c.book))
        let xml = String(decoding: try XCTUnwrap(saved.first { $0.name == "xl/tables/table1.xml" }).data, as: UTF8.self)
        XCTAssertNotNil(XNode.parse(Data(xml.utf8)))
        XCTAssertTrue(xml.containsSubstring("displayName=\"Table1\" ref=\"D3:K11\""), xml)
        XCTAssertTrue(xml.containsSubstring("<autoFilter ref=\"D3:K11\""), xml)
        XCTAssertTrue(xml.containsSubstring("<tableColumns count=\"8\">"), xml)
        // Names come from the header cells: an edited one, a new empty one,
        // a cleared one — each unique and non-empty.
        XCTAssertTrue(xml.containsSubstring("<tableColumn id=\"1\" name=\"Column1\"/>"), xml)        // D3 is empty in the fixture
        XCTAssertTrue(xml.containsSubstring("<tableColumn id=\"2\" name=\"GCC 32-bit\"/>"), xml)
        XCTAssertTrue(xml.containsSubstring("<tableColumn id=\"8\" name=\"Column3\"/>"), xml)
        XCTAssertTrue(xml.containsSubstring("<tableColumn id=\"4\" name=\"Column5\"/>"), xml)
        XCTAssertTrue(xml.containsSubstring("name=\"Intel 11.1 (64)\""), xml)
        XCTAssertFalse(xml.containsSubstring("filterColumn"))        // positions moved
        XCTAssertTrue(xml.containsSubstring("<tableStyleInfo name=\"TableStyleMedium2\""))
    }

    func testUntouchedTableIsWrittenAsItWas() throws {
        let data = try withTable()
        let saved = try Zip.read(try Xlsx.write(try Xlsx.read(data)))
        let was = String(decoding: try XCTUnwrap(try Zip.read(data).first { $0.name == "xl/tables/table1.xml" }).data, as: UTF8.self)
        let now = String(decoding: try XCTUnwrap(saved.first { $0.name == "xl/tables/table1.xml" }).data, as: UTF8.self)
        // Only D3's empty header becomes Column1 (Excel's own repair would do the same).
        XCTAssertEqual(was.replacingAll("name=\"Run\"", with: "name=\"Column1\""), now)
    }
}

extension SheetsTableTests {
    func testBuiltInStyleLooks() {
        let theme = Xlsx._themeColors(nil)          // Office 2013: accent1 4472C4
        var t = SheetTable(path: "", ref: CellRange("B2:D6")!, columnIds: [1, 2, 3], headerRow: true)
        t.style = "TableStyleMedium2"
        let head = TableStyles.look(t, CellAddress("C2")!, theme: theme)
        XCTAssertEqual(head?.fill, 0x4472C4)
        XCTAssertEqual(head?.color, 0xFFFFFF)
        XCTAssertEqual(head?.bold, true)
        XCTAssertEqual(TableStyles.look(t, CellAddress("C3")!, theme: theme)?.fill, CFEvaluator._mix(0x4472C4, 0xFFFFFF, 0.8))
        XCTAssertNil(TableStyles.look(t, CellAddress("C4")!, theme: theme)?.fill)      // the plain stripe
        XCTAssertNil(TableStyles.look(t, CellAddress("E4")!, theme: theme))            // outside
        t.style = nil
        XCTAssertNil(TableStyles.look(t, CellAddress("C2")!, theme: theme))
    }
}
