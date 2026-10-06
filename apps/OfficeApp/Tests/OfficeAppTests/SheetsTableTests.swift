// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsTableTests: XCTestCase {
    /// The fixture with a table over 'Single double'!D3:J10 (its data).
    func withTable() throws -> Data {
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
        // Only D3's empty header becomes Column1 (Excel's own repair would do the same),
        // and the cell is given that name too: Excel repairs a table whose header
        // cell disagrees with its column name, an empty cell included.
        XCTAssertEqual(was.replacingAll("name=\"Run\"", with: "name=\"Column1\""), now)
        let sheet = String(decoding: try XCTUnwrap(saved.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        XCTAssertTrue(sheet.containsSubstring("<c r=\"D3\" t=\"s\">") || sheet.containsSubstring("<c r=\"D3\" t=\"inlineStr\">"), sheet)
        let back = try Xlsx.read(try Xlsx.write(try Xlsx.read(data)))
        XCTAssertEqual(back.sheets[0].value(CellAddress("D3")!), .text("Column1"))
    }

    func testTableDeletedWithAllItsRowsLeavesNoTrace() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try withTable()))
        c.delete(.rows, at: 2, count: 8)          // rows 3…10: the whole table
        XCTAssertTrue(c.sheet.tables.isEmpty)
        XCTAssertEqual(c.sheet.removedTables.count, 1)
        let saved = try Zip.read(try Xlsx.write(c.book))
        XCTAssertNil(saved.first { $0.name == "xl/tables/table1.xml" })
        let sheet = String(decoding: try XCTUnwrap(saved.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        XCTAssertFalse(sheet.containsSubstring("tablePart"))
        let rels = String(decoding: try XCTUnwrap(saved.first { $0.name == "xl/worksheets/_rels/sheet1.xml.rels" }).data, as: UTF8.self)
        XCTAssertFalse(rels.containsSubstring("tables/table1.xml"))
        let types = String(decoding: try XCTUnwrap(saved.first { $0.name == "[Content_Types].xml" }).data, as: UTF8.self)
        XCTAssertFalse(types.containsSubstring("table1.xml"))
        // Reopening sees no table, and deleting only part of one keeps it.
        XCTAssertTrue(try Xlsx.read(try Xlsx.write(c.book)).sheets[0].tables.isEmpty)
        let d = WorkbookController()
        d.load(try Xlsx.read(try withTable()))
        d.delete(.rows, at: 2, count: 3)
        XCTAssertEqual(d.sheet.tables.first?.ref, CellRange("D3:J7"))
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

extension SheetsTableTests {
    func testStructuredReferencesSurvive() throws {
        // The fixture's D3:J10 table, with formulas Sheets cannot read.
        var entries = try Zip.read(try withTable())
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "xl/worksheets/sheet1.xml" })
        var s = String(decoding: entries[i].data, as: UTF8.self)
        let rowEnd = try XCTUnwrap(s.findRange(of: "</sheetData>"))
        s.replaceSubrange(rowEnd, with: "<row r=\"20\"><c r=\"E20\"><f>SUM(Table1[gcc 4.4.0 (32)])</f><v>11.226</v></c><c r=\"F20\"><f>Table1[[#This Row],[VC++ 10 (32)]]*2</f><v>7</v></c></row></sheetData>")
        entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
        let book = try Xlsx.read(try Zip.write(entries))
        let c = WorkbookController()
        c.load(book)
        // Read and computed now: the data rows of the gcc column, not the file's (wrong) 11.226.
        guard case .number(let sum) = c.sheet.value(CellAddress("E20")!) else { return XCTFail("not a number") }
        XCTAssertEqual(sum, 9.445, accuracy: 1e-9)
        let out = try Zip.read(try Xlsx.write(c.book))
        let sheet = String(decoding: try XCTUnwrap(out.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        XCTAssertTrue(sheet.containsSubstring("<f>SUM(Table1[gcc 4.4.0 (32)])</f>"), sheet)
        XCTAssertTrue(sheet.containsSubstring("<f>Table1[[#This Row],[VC++ 10 (32)]]*2</f>"), sheet)
    }
}

extension SheetsTableTests {
    func testUnreadableSharedAndArrayFormulasSurvive() throws {
        // A ragged array constant is one formula Sheets cannot read.
        var entries = try Zip.read(try withTable())
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "xl/worksheets/sheet1.xml" })
        var s = String(decoding: entries[i].data, as: UTF8.self)
        let rowEnd = try XCTUnwrap(s.findRange(of: "</sheetData>"))
        s.replaceSubrange(rowEnd, with: "<row r=\"30\"><c r=\"E30\"><f t=\"shared\" ref=\"E30:E31\" si=\"7\">SUM({1,2;3})*2</f><v>1</v></c><c r=\"G30\"><f t=\"array\" ref=\"G30:G31\">SUM({1,2;3})</f><v>3</v></c></row><row r=\"31\"><c r=\"E31\"><f t=\"shared\" si=\"7\"/><v>2</v></c></row></sheetData>")
        entries[i] = ZipEntry(name: entries[i].name, data: Data(s.utf8))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Zip.write(entries)))
        XCTAssertEqual(c.sheet.value(CellAddress("E31")!), .number(2))
        let out = String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        XCTAssertTrue(out.containsSubstring("<c r=\"E30\"><f ref=\"E30:E31\" si=\"7\" t=\"shared\">SUM({1,2;3})*2</f><v>1</v></c>"), out)
        XCTAssertTrue(out.containsSubstring("<c r=\"E31\"><f si=\"7\" t=\"shared\"/><v>2</v></c>"), out)
        XCTAssertTrue(out.containsSubstring("<f ref=\"G30:G31\" t=\"array\">SUM({1,2;3})</f><v>3</v>"), out)
        // Typed over, a cell is the user's again; copied, it carries its value.
        c.setInputs([(CellAddress("E30")!, "5")])
        c.select(CellAddress("E31")!)
        let clip = c.clip(cut: false, text: "")
        c.select(CellAddress("H40")!)
        c.paste(clip)
        XCTAssertNil(c.sheet.cells[CellAddress("E30")!]?.rawFormula)
        XCTAssertNil(c.sheet.cells[CellAddress("H40")!]?.rawFormula)
        XCTAssertEqual(c.sheet.value(CellAddress("H40")!), .number(2))
    }
}

extension SheetsTableTests {
    func testStructuredReferenceForms() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try withTable()))   // Table1 over D3:J10, header row 3
        func v(_ f: String, at a: String) -> CellValue { c.engine.evaluate(f, sheet: 0, at: CellAddress(a)!) }
        func n(_ x: CellValue) -> Double { x.number ?? .nan }
        XCTAssertEqual(n(v("=SUM(Table1[gcc 4.4.0 (32)])", at: "L1")), 9.445, accuracy: 1e-9)
        XCTAssertEqual(n(v("=Table1[[#This Row],[VC++ 10 (32)]]", at: "L5")), 2.568, accuracy: 1e-9)
        XCTAssertEqual(n(v("=[@[VC++ 10 (32)]]*2", at: "J5")), 5.136, accuracy: 1e-9)   // inside the table
        XCTAssertEqual(n(v("=COUNT(Table1[[gcc 4.4.0 (32)]:[Intel 11.1 (32)]])", at: "L1")), 21)
        XCTAssertEqual(n(v("=COUNTA(Table1[[#Headers],[gcc 4.4.0 (32)]:[VC++ 10 (32)]])", at: "L1")), 2)
        XCTAssertEqual(n(v("=ROWS(Table1[#All])", at: "L1")), 8)
        XCTAssertEqual(n(v("=ROWS(Table1)", at: "L1")), 7)                              // a bare name: its data rows
        XCTAssertEqual(v("=SUM(Table1[Nope])", at: "L1"), .error(.ref))
        XCTAssertEqual(v("=SUM(Nope[x])", at: "L1"), .error(.ref))
        // The text is kept exactly through a parse and print.
        let f = "SUM(Table1[[#This Row],[gcc 4.4.0 (32)]:[Intel 11.1 (32)]])+[@Run]"
        XCTAssertEqual(Formula.print(try Formula.parse("=" + f)), f)
        // Rows moving do not touch it; the table moves and the reference follows.
        c.setInputs([(CellAddress("L1")!, "=SUM(Table1[gcc 4.4.0 (32)])")])
        c.insert(.rows, at: 0, count: 3)
        XCTAssertEqual(c.input(CellAddress("L4")!), "=SUM(Table1[gcc 4.4.0 (32)])")
        XCTAssertEqual(n(c.sheet.value(CellAddress("L4")!)), 9.445, accuracy: 1e-9)
    }
}

extension SheetsTableTests {
    func testRenamingAHeaderRenamesItsReferences() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try withTable()))
        c.setInputs([(CellAddress("L1")!, "=SUM(Table1[VC++ 10 (32)])"), (CellAddress("J5")!, "=[@[VC++ 10 (32)]]*2")])
        c.setInputs([(CellAddress("F3")!, "VC [2010]")])
        XCTAssertEqual(c.input(CellAddress("L1")!), "=SUM(Table1[VC '[2010']])")
        XCTAssertEqual(c.input(CellAddress("J5")!), "=[@[VC '[2010']]]*2")
        guard case .number(let n) = c.sheet.value(CellAddress("L1")!) else { return XCTFail() }
        XCTAssertEqual(n, 10.143, accuracy: 1e-9)
        c.undo()
        XCTAssertEqual(c.input(CellAddress("L1")!), "=SUM(Table1[VC++ 10 (32)])")
    }
}
