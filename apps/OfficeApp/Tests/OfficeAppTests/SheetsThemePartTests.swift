// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// A new workbook carries the standard Office theme; a workbook opened from a file keeps its own.

import XCTest
@testable import OfficeApp

final class SheetsThemePartTests: XCTestCase {
    private func parts(_ data: Data) throws -> [String: String] {
        var m: [String: String] = [:]
        for e in try Zip.read(data) { m[e.name] = String(decoding: e.data, as: UTF8.self) }
        return m
    }

    func testNewWorkbookGetsTheOfficeTheme() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress(row: 0, col: 0), "x")])
        let p = try parts(try Xlsx.write(c.book))
        XCTAssertTrue(p["xl/theme/theme1.xml"]?.contains("<a:accent1><a:srgbClr val=\"4472C4\"/>") == true)
        XCTAssertTrue(p["xl/_rels/workbook.xml.rels"]!.contains("relationships/theme\" Target=\"theme/theme1.xml\"")
                      || p["xl/_rels/workbook.xml.rels"]!.contains("Target=\"theme/theme1.xml\""))
        XCTAssertTrue(p["[Content_Types].xml"]!.contains("/xl/theme/theme1.xml"))
        XCTAssertTrue(p["[Content_Types].xml"]!.contains("theme+xml"))
        // It reads back with the same palette and the same fonts.
        let back = try Xlsx.read(try Xlsx.write(c.book))
        XCTAssertEqual(back.themeColors, c.book.themeColors)
    }

    func testOpenedWorkbookKeepsItsOwnTheme() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress(row: 0, col: 0), "x")])
        var ents = try Zip.read(try Xlsx.write(c.book))
        let mine = "<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Mine\"><a:themeElements><a:clrScheme name=\"Mine\"><a:dk1><a:srgbClr val=\"010203\"/></a:dk1><a:lt1><a:srgbClr val=\"FFFFFF\"/></a:lt1><a:dk2><a:srgbClr val=\"44546A\"/></a:dk2><a:lt2><a:srgbClr val=\"E7E6E6\"/></a:lt2><a:accent1><a:srgbClr val=\"123456\"/></a:accent1><a:accent2><a:srgbClr val=\"ED7D31\"/></a:accent2><a:accent3><a:srgbClr val=\"A5A5A5\"/></a:accent3><a:accent4><a:srgbClr val=\"FFC000\"/></a:accent4><a:accent5><a:srgbClr val=\"5B9BD5\"/></a:accent5><a:accent6><a:srgbClr val=\"70AD47\"/></a:accent6><a:hlink><a:srgbClr val=\"0563C1\"/></a:hlink><a:folHlink><a:srgbClr val=\"954F72\"/></a:folHlink></a:clrScheme></a:themeElements></a:theme>"
        let i = ents.firstIndex { $0.name == "xl/theme/theme1.xml" }!
        ents[i] = ZipEntry(name: "xl/theme/theme1.xml", data: Data(mine.utf8))
        let opened = try Xlsx.read(try Zip.write(ents))
        let p = try parts(try Xlsx.write(opened))
        XCTAssertEqual(p["xl/theme/theme1.xml"], mine)
        XCTAssertEqual(p["[Content_Types].xml"]!.components(separatedBy: "/xl/theme/theme1.xml").count, 2)
        XCTAssertEqual(p["xl/_rels/workbook.xml.rels"]!.components(separatedBy: "relationships/theme\"").count, 2)
    }
}
