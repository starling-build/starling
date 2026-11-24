// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

/// X-P0-1: a rich string in a cell survives a save.
final class SheetsRichTextTests: XCTestCase {
    static let rich = "<si><r><rPr><b/><u val=\"double\"/><sz val=\"14\"/><color theme=\"4\"/><rFont val=\"Calibri\"/><family val=\"2\"/><scheme val=\"minor\"/></rPr><t xml:space=\"preserve\">Bold </t></r>"
        + "<r><rPr><i/><vertAlign val=\"superscript\"/><rFont val=\"Calibri\"/></rPr><t>sup</t></r><rPh sb=\"0\" eb=\"2\"><t>ふり</t></rPh><phoneticPr fontId=\"1\" type=\"Hiragana\"/></si>"

    static func book() throws -> Data {
        func e(_ n: String, _ s: String) -> ZipEntry { ZipEntry(name: n, data: Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + s).utf8)) }
        let ns = "xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\""
        let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        return try Zip.write([
            e("[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/></Types>"),
            e("_rels/.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(r)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"),
            e("xl/workbook.xml", "<workbook \(ns) xmlns:r=\"\(r)\"><sheets><sheet name=\"S\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"),
            e("xl/_rels/workbook.xml.rels", "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(r)/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"\(r)/sharedStrings\" Target=\"sharedStrings.xml\"/></Relationships>"),
            e("xl/worksheets/sheet1.xml", "<worksheet \(ns)><sheetData><row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c><c r=\"C1\" t=\"s\"><v>0</v></c></row></sheetData></worksheet>"),
            e("xl/sharedStrings.xml", "<sst \(ns) count=\"3\" uniqueCount=\"2\">\(rich)<si><t>plain</t></si></sst>"),
        ])
    }

    func sst(_ data: Data) throws -> String {
        let out = try Zip.read(data)
        return String(decoding: try XCTUnwrap(out.first { $0.name == "xl/sharedStrings.xml" }).data, as: UTF8.self)
    }

    func testRichStringSurvivesASave() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try Self.book()))
        let saved = try Xlsx.write(c.book)
        // (Set RICHTEXT_SAMPLE to keep the saved file, to open it in Excel.)
        if let out = ProcessInfo.processInfo.environment["RICHTEXT_SAMPLE"] { try saved.write(to: URL(fileURLWithPath: out)) }
        let s = try sst(saved)
        for keep in ["<u val=\"double\"", "<sz val=\"14\"", "<color theme=\"4\"", "<family val=\"2\"", "<scheme val=\"minor\"", "<vertAlign val=\"superscript\"",
                     "<rPh", "ふり", "<phoneticPr", "xml:space=\"preserve\">Bold </t>", "<t>plain</t>"] {
            XCTAssertTrue(s.containsSubstring(keep), keep)
        }
        // Two cells share the rich string and the plain neighbour stays plain.
        let back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertEqual(back.sheets[0].richText[CellAddress("A1")!]?.count, 2)
        XCTAssertEqual(back.sheets[0].richText[CellAddress("C1")!]?.count, 2)
        XCTAssertNil(back.sheets[0].richText[CellAddress("B1")!])
        XCTAssertEqual(back.sheets[0].cells[CellAddress("A1")!]?.value, .text("Bold sup"))
    }

    func testEditedRichCellIsPlainAndItsNeighboursStayRich() throws {
        let c = WorkbookController()
        c.load(try Xlsx.read(try Self.book()))
        c.setInput("typed", at: CellAddress("A1")!)
        let back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertNil(back.sheets[0].richText[CellAddress("A1")!])
        XCTAssertEqual(back.sheets[0].cells[CellAddress("A1")!]?.value, .text("typed"))
        XCTAssertEqual(back.sheets[0].richText[CellAddress("C1")!]?.count, 2)
    }
}
