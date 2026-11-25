// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsTableCommandTests: XCTestCase {
    private func sample() -> WorkbookController {
        let c = WorkbookController()
        var items: [(CellAddress, String)] = []
        for (j, h) in ["Region", "Units", "Price"].enumerated() { items.append((CellAddress(row: 0, col: j), h)) }
        for i in 1 ... 4 {
            items += [(CellAddress(row: i, col: 0), ["North", "South", "East", "West"][i - 1]),
                      (CellAddress(row: i, col: 1), "\(i * 10)"), (CellAddress(row: i, col: 2), "\(i * 2).5")]
        }
        c.setInputs(items)
        return c
    }

    private func saved(_ c: WorkbookController) throws -> (book: Workbook, parts: [String: Data]) {
        let data = try Xlsx.write(c.book)
        let parts = Dictionary(uniqueKeysWithValues: try Zip.read(data).map { ($0.name, $0.data) })
        return (try Xlsx.read(data), parts)
    }

    func testCreateWithHeadersSavesAndReloads() throws {
        let c = sample()
        XCTAssertNil(c.createTable(CellRange("A1:C5")!, hasHeaders: true))
        XCTAssertEqual(c.sheet.tables.count, 1)
        XCTAssertEqual(c.sheet.tables[0].name, "Table1")
        let (book, parts) = try saved(c)
        let t = try XCTUnwrap(book.sheets[0].tables.first)
        XCTAssertEqual(t.ref, CellRange("A1:C5"))
        XCTAssertEqual(t.style, "TableStyleMedium2")
        XCTAssertEqual(t.columnNames, ["Region", "Units", "Price"])
        let xml = String(decoding: try XCTUnwrap(parts[t.path]), as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("displayName=\"Table1\""))
        XCTAssertTrue(String(decoding: try XCTUnwrap(parts["[Content_Types].xml"]), as: UTF8.self).containsSubstring("spreadsheetml.table+xml"))
        c.undo()
        XCTAssertTrue(c.sheet.tables.isEmpty)
    }

    func testHeaderCellsAreMadeUniqueTextAndRefusals() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "Item"), (CellAddress("B1")!, "item"), (CellAddress("C1")!, ""), (CellAddress("D1")!, "2020"),
                     (CellAddress("A2")!, "x"), (CellAddress("B2")!, "1"), (CellAddress("C2")!, "2"), (CellAddress("D2")!, "3")])
        XCTAssertNil(c.createTable(CellRange("A1:D2")!, hasHeaders: true))
        XCTAssertEqual(c.sheet.tables[0].columnNames, ["Item", "item2", "Column3", "2020"])
        XCTAssertEqual(c.sheet.value(CellAddress("B1")!), .text("item2"))
        XCTAssertEqual(c.sheet.value(CellAddress("D1")!), .text("2020"))
        XCTAssertEqual(c.createTable(CellRange("C1:E3")!, hasHeaders: true), .overlap)
        XCTAssertEqual(c.createTable(CellRange("F1:G1")!, hasHeaders: true), .tooSmall)
        let (book, _) = try saved(c)
        XCTAssertEqual(book.sheets[0].tables[0].columnNames, ["Item", "item2", "Column3", "2020"])
    }

    func testNoHeadersInsertsAHeaderRow() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "1"), (CellAddress("B1")!, "2"), (CellAddress("A2")!, "3"), (CellAddress("B2")!, "4")])
        XCTAssertNil(c.createTable(CellRange("A1:B2")!, hasHeaders: false))
        XCTAssertEqual(c.sheet.tables[0].ref, CellRange("A1:B3"))
        XCTAssertEqual(c.sheet.value(CellAddress("A1")!), .text("Column1"))
        XCTAssertEqual(c.sheet.value(CellAddress("A2")!), .number(1))
        c.undo()
        XCTAssertEqual(c.sheet.value(CellAddress("A1")!), .number(1))
    }

    func testStyleBandingAndTotalsRowRoundTrip() throws {
        let c = sample()
        c.createTable(CellRange("A1:C5")!, hasHeaders: true)
        c.setTableLook(at: 0, style: .some("TableStyleLight9"), rowStripes: false, columnStripes: true, firstColumn: true, lastColumn: true)
        XCTAssertNil(c.setTableTotals(at: 0, on: true))
        XCTAssertEqual(c.sheet.tables[0].ref, CellRange("A1:C6"))
        XCTAssertEqual(c.sheet.value(CellAddress("A6")!), .text("Total"))
        XCTAssertEqual(c.sheet.value(CellAddress("C6")!), .number(22))      // 2.5 + 4.5 + 6.5 + 8.5
        let (book, parts) = try saved(c)
        let t = try XCTUnwrap(book.sheets[0].tables.first)
        XCTAssertEqual(t.ref, CellRange("A1:C6"))
        XCTAssertTrue(t.totalsRow)
        XCTAssertEqual([t.style, t.rowStripes ? "r" : "-", t.columnStripes ? "c" : "-", t.firstColumn ? "f" : "-", t.lastColumn ? "l" : "-"],
                       ["TableStyleLight9", "-", "c", "f", "l"])
        let xml = String(decoding: try XCTUnwrap(parts[t.path]), as: UTF8.self)
        XCTAssertTrue(xml.containsSubstring("totalsRowCount=\"1\""))
        XCTAssertTrue(xml.containsSubstring("totalsRowLabel=\"Total\""))
        XCTAssertTrue(xml.containsSubstring("totalsRowFunction=\"sum\""))
        XCTAssertTrue(xml.containsSubstring("<autoFilter ref=\"A1:C5\""))
        // Off again: the row is cleared and the attributes go.
        XCTAssertNil(c.setTableTotals(at: 0, on: false))
        XCTAssertEqual(c.sheet.tables[0].ref, CellRange("A1:C5"))
        XCTAssertTrue(c.sheet.value(CellAddress("A6")!).isEmpty)
        let xml2 = String(decoding: try XCTUnwrap(try saved(c).parts[t.path]), as: UTF8.self)
        XCTAssertFalse(xml2.containsSubstring("totalsRowCount"))
        XCTAssertFalse(xml2.containsSubstring("totalsRowLabel"))
        XCTAssertFalse(xml2.containsSubstring("totalsRowFunction"))
    }

    func testTotalsRowNeedsRoom() {
        let c = sample()
        c.createTable(CellRange("A1:C5")!, hasHeaders: true)
        c.setInputs([(CellAddress("B6")!, "9")])
        XCTAssertEqual(c.setTableTotals(at: 0, on: true), .noRoom)
        XCTAssertFalse(c.sheet.tables[0].totalsRow)
    }

    func testResizeAddsAndDropsColumnsAndKeepsTheHeaderRow() throws {
        let c = sample()
        c.setInputs([(CellAddress("D1")!, "Notes"), (CellAddress("E1")!, "")])
        c.createTable(CellRange("A1:C5")!, hasHeaders: true)
        XCTAssertNil(c.resizeTable(at: 0, to: CellRange("A1:E8")!))
        XCTAssertEqual(c.sheet.tables[0].ref, CellRange("A1:E8"))
        XCTAssertEqual(c.sheet.value(CellAddress("E1")!), .text("Column5"))
        XCTAssertEqual(c.resizeTable(at: 0, to: CellRange("A2:C5")!), .headerMoved)
        XCTAssertNil(c.resizeTable(at: 0, to: CellRange("A1:B3")!))
        let (book, _) = try saved(c)
        XCTAssertEqual(book.sheets[0].tables[0].ref, CellRange("A1:B3"))
        XCTAssertEqual(book.sheets[0].tables[0].columnNames, ["Region", "Units"])
        c.undo()
        XCTAssertEqual(c.sheet.tables[0].ref, CellRange("A1:E8"))
    }

    func testConvertToRangeKeepsTheLookAndDropsThePart() throws {
        let c = sample()
        c.createTable(CellRange("A1:C5")!, hasHeaders: true)
        c.convertTableToRange(at: 0)
        XCTAssertTrue(c.sheet.tables.isEmpty)
        XCTAssertTrue(c.book.style(c.sheet.cells[CellAddress("A1")!]!.style).bold)
        XCTAssertNotNil(c.book.style(c.sheet.cells[CellAddress("A1")!]!.style).fill)
        let (book, parts) = try saved(c)
        XCTAssertTrue(book.sheets[0].tables.isEmpty)
        XCTAssertNil(parts.keys.first { $0.hasPrefix("xl/tables/") })
        c.undo()
        XCTAssertEqual(c.sheet.tables.count, 1)
    }
}
