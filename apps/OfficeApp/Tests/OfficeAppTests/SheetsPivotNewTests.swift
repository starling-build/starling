import XCTest
@testable import OfficeApp

/// Insert → PivotTable: the cells it makes, undo, refresh, and the Excel parts a save writes.
final class SheetsPivotNewTests: XCTestCase {
    /// Region, Product, Sales over A1:C7.
    private func book() -> WorkbookController {
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Product", "Sales"], ["East", "Pen", "10"], ["West", "Pen", "20"], ["East", "Ink", "5"],
                                ["East", "Pen", "30"], ["West", "Ink", "8"], ["North", "Pen", "7"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), v)) } }
        wc.setInputs(inputs)
        return wc
    }
    private func v(_ wc: WorkbookController, _ a: String) -> CellValue { wc.sheet.value(CellAddress(a)!) }
    private let src = "Sheet1!A1:C7"
    private func parts(_ c: WorkbookController) throws -> [String: String] {
        Dictionary(try Zip.read(try Xlsx.write(c.book)).map { ($0.name, String(decoding: $0.data, as: UTF8.self)) }, uniquingKeysWith: { a, _ in a })
    }

    func testRowsAndSum() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("F1")!, newSheet: false))
        XCTAssertEqual(v(wc, "F1"), .text("Row Labels"))
        XCTAssertEqual(v(wc, "G1"), .text("Sum of Sales"))
        XCTAssertEqual(v(wc, "F2"), .text("East")); XCTAssertEqual(v(wc, "G2"), .number(45))
        XCTAssertEqual(v(wc, "F3"), .text("North")); XCTAssertEqual(v(wc, "G3"), .number(7))
        XCTAssertEqual(v(wc, "F4"), .text("West")); XCTAssertEqual(v(wc, "G4"), .number(28))
        XCTAssertEqual(v(wc, "F5"), .text("Grand Total")); XCTAssertEqual(v(wc, "G5"), .number(80))
        XCTAssertEqual(wc.sheet.pivots.last?.ref, CellRange("F1:G5"))
    }

    func testCountAverageAndSeveralValues() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [1], cols: [], data: [PivotDataField(field: 2, function: .count), PivotDataField(field: 2, function: .average)],
                                         filters: [], origin: CellAddress("F1")!, newSheet: false))
        // Excel puts a "Values" caption row above the headings when there are several values.
        XCTAssertEqual(v(wc, "G1"), .text("Values")); XCTAssertEqual(v(wc, "F1"), .empty)
        XCTAssertEqual(v(wc, "F2"), .text("Row Labels")); XCTAssertEqual(v(wc, "G2"), .text("Count of Sales")); XCTAssertEqual(v(wc, "H2"), .text("Average of Sales"))
        XCTAssertEqual(v(wc, "F3"), .text("Ink")); XCTAssertEqual(v(wc, "G3"), .number(2)); XCTAssertEqual(v(wc, "H3"), .number(6.5))
        XCTAssertEqual(v(wc, "G5"), .number(6)); XCTAssertEqual(v(wc, "H5"), .number(80.0 / 6))
        XCTAssertEqual(wc.sheet.pivots.last?.ref, CellRange("F1:H5"))
        XCTAssertEqual(wc.sheet.pivots.last?.headerRows, 2)
    }

    func testColumnField() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [1], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("F1")!, newSheet: false))
        XCTAssertEqual(v(wc, "F1"), .text("Sum of Sales")); XCTAssertEqual(v(wc, "G1"), .text("Column Labels"))
        XCTAssertEqual(v(wc, "F2"), .text("Row Labels")); XCTAssertEqual(v(wc, "G2"), .text("Ink")); XCTAssertEqual(v(wc, "H2"), .text("Pen")); XCTAssertEqual(v(wc, "I2"), .text("Grand Total"))
        XCTAssertEqual(v(wc, "G3"), .number(5)); XCTAssertEqual(v(wc, "H3"), .number(40)); XCTAssertEqual(v(wc, "I3"), .number(45))
        XCTAssertTrue(v(wc, "G4").isEmpty, "North sold no Ink")
        XCTAssertEqual(v(wc, "I6"), .number(80))
    }

    func testTwoRowFieldsNest() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0, 1], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("F1")!, newSheet: false))
        // East (45): Ink 5, Pen 40; North (7): Pen 7; West (28): Ink 8, Pen 20; Grand Total.
        XCTAssertEqual(v(wc, "F2"), .text("East")); XCTAssertEqual(v(wc, "G2"), .number(45))
        XCTAssertEqual(v(wc, "F3"), .text("Ink")); XCTAssertEqual(v(wc, "G3"), .number(5))
        XCTAssertEqual(v(wc, "F4"), .text("Pen")); XCTAssertEqual(v(wc, "G4"), .number(40))
        XCTAssertEqual(v(wc, "F10"), .text("Grand Total")); XCTAssertEqual(v(wc, "G10"), .number(80))
    }

    func testFilterCutsTheTable() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)],
                                         filters: [PivotFilter(field: 1, item: "Pen")], origin: CellAddress("F1")!, newSheet: false))
        XCTAssertEqual(v(wc, "F1"), .text("Product")); XCTAssertEqual(v(wc, "G1"), .text("Pen"))
        XCTAssertEqual(v(wc, "F3"), .text("Row Labels"))
        XCTAssertEqual(v(wc, "G4"), .number(40)); XCTAssertEqual(v(wc, "G7"), .number(67))
        XCTAssertEqual(wc.sheet.pivots.last?.ref, CellRange("F3:G7"))
        let all = book()
        XCTAssertNil(all.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)],
                                          filters: [PivotFilter(field: 1)], origin: CellAddress("F1")!, newSheet: false))
        XCTAssertEqual(v(all, "G1"), .text("(All)")); XCTAssertEqual(v(all, "G7"), .number(80))
    }

    func testProblemsAndUndo() {
        let wc = book()
        let sum = [PivotDataField(field: 2, function: .sum)]
        func put(_ r: [Int], _ c: [Int], _ d: [PivotDataField], at: String = "F1") -> PivotProblem? {
            wc.insertPivotTable(source: src, rows: r, cols: c, data: d, filters: [], origin: CellAddress(at)!, newSheet: false)
        }
        XCTAssertEqual(put([], [], sum), .needsRowField)
        XCTAssertEqual(put([0], [], []), .needsValues)
        XCTAssertEqual(put([0], [0], sum), .fieldUsedTwice)
        XCTAssertEqual(put([0], [1], sum + sum), .columnFieldNeedsOneValue)
        XCTAssertEqual(put([0], [], sum, at: "B2"), .destinationInsideSource)
        XCTAssertEqual(wc.insertPivotTable(source: "Nowhere!A1:C7", rows: [0], cols: [], data: sum, filters: [], origin: CellAddress("F1")!, newSheet: false), .noSource)
        XCTAssertEqual(wc.insertPivotTable(source: src, rows: [0], cols: [], data: sum, filters: [PivotFilter(field: 1, item: "Cap")], origin: CellAddress("F1")!, newSheet: false), .noSuchFilterItem)
        XCTAssertTrue(wc.sheet.pivots.isEmpty)
        XCTAssertNil(put([0], [], sum))
        XCTAssertEqual(wc.sheet.pivots.count, 1)
        wc.undo()
        XCTAssertTrue(wc.sheet.pivots.isEmpty)
        XCTAssertTrue(v(wc, "F1").isEmpty && v(wc, "G5").isEmpty)
        wc.redo()
        XCTAssertEqual(v(wc, "G5"), .number(80))
    }

    func testNewSheetIsOneUndoStep() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("A3")!, newSheet: true))
        XCTAssertEqual(wc.book.sheets.count, 2)
        XCTAssertEqual(wc.activeSheet, 1)
        XCTAssertEqual(v(wc, "A3"), .text("Row Labels"))
        XCTAssertEqual(wc.book.sheets[1].pivots.first?.source, "Sheet1!A1:C7")
        wc.undo()
        XCTAssertEqual(wc.book.sheets.count, 1)
    }

    func testRefreshReadsTheSourceAgain() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("F1")!, newSheet: false))
        wc.setInputs([(CellAddress("C2")!, "110"), (CellAddress("A7")!, "South")])
        XCTAssertEqual(v(wc, "G2"), .number(45), "a pivot table is not live until refreshed")
        XCTAssertEqual(wc.refreshPivots(), 1)
        XCTAssertEqual(v(wc, "G2"), .number(145))
        XCTAssertEqual(v(wc, "F3"), .text("South"))
        XCTAssertEqual(v(wc, "G5"), .number(180))
        wc.undo()
        XCTAssertEqual(v(wc, "G2"), .number(45))
    }

    func testRefreshAfterRowsInsertedAboveItAndSheetRenamed() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("F1")!, newSheet: false))
        wc.activeSheet = 0
        wc.insert(.rows, at: 0, count: 2)
        XCTAssertTrue(wc.renameSheet(0, "Data"))
        XCTAssertEqual(wc.sheet.pivots.last?.source, "Data!A3:C9")
        XCTAssertEqual(wc.refreshPivots(), 1)
        XCTAssertEqual(v(wc, "G3"), .text("Sum of Sales"))
        XCTAssertEqual(v(wc, "G7"), .number(80))
    }

    func testSaveWritesExcelPivotParts() throws {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [1], data: [PivotDataField(field: 2, function: .sum)],
                                         filters: [], origin: CellAddress("F1")!, newSheet: false))
        let p = try parts(wc)
        for n in ["xl/pivotTables/pivotTable1.xml", "xl/pivotTables/_rels/pivotTable1.xml.rels", "xl/pivotCache/pivotCacheDefinition1.xml",
                  "xl/pivotCache/_rels/pivotCacheDefinition1.xml.rels", "xl/pivotCache/pivotCacheRecords1.xml"] {
            let text = try XCTUnwrap(p[n], n)
            XCTAssertNotNil(XNode.parse(Data(text.utf8)), "\(n) is well-formed")
        }
        XCTAssertTrue(p["xl/pivotCache/pivotCacheDefinition1.xml"]!.contains("<worksheetSource ref=\"A1:C7\" sheet=\"Sheet1\"/>"))
        XCTAssertTrue(p["xl/pivotCache/pivotCacheDefinition1.xml"]!.contains("refreshOnLoad=\"1\""))
        XCTAssertTrue(p["xl/pivotCache/pivotCacheRecords1.xml"]!.contains("count=\"6\""))
        let t = try XCTUnwrap(p["xl/pivotTables/pivotTable1.xml"])
        XCTAssertTrue(t.contains("<location ref=\"F1:I6\" firstHeaderRow=\"1\" firstDataRow=\"2\" firstDataCol=\"1\"/>"), t)
        XCTAssertTrue(t.contains("<colFields count=\"1\"><field x=\"1\"/></colFields>"))
        XCTAssertTrue(t.contains("<dataField name=\"Sum of Sales\" fld=\"2\""))
        XCTAssertTrue(p["xl/workbook.xml"]!.contains("<pivotCaches><pivotCache cacheId=\"1\" r:id=\""))
        XCTAssertTrue(p["xl/_rels/workbook.xml.rels"]!.contains("pivotCacheDefinition1.xml"))
        XCTAssertTrue(p["xl/worksheets/_rels/sheet1.xml.rels"]!.contains("../pivotTables/pivotTable1.xml"))
        let ct = try XCTUnwrap(p["[Content_Types].xml"])
        for k in ["pivotTable+xml", "pivotCacheDefinition+xml", "pivotCacheRecords+xml"] { XCTAssertTrue(ct.contains(k), k) }
        // The saved file reads back as a pivot table at the same place, over the same source.
        let back = try Xlsx.read(try Xlsx.write(wc.book))
        XCTAssertEqual(back.sheets[0].pivots.first?.ref, CellRange("F1:I6"))
        XCTAssertEqual(back.sheets[0].pivots.first?.source, "Sheet1!A1:C7")
    }

    /// With STARLING_PIVOT_NEW set: the book for Excel to open (rows, a column field, a filter), a second book with two row fields and two values.
    func testWriteExcelCheckBooks() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_PIVOT_NEW"] else { throw XCTSkip("no STARLING_PIVOT_NEW") }
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [1], data: [PivotDataField(field: 2, function: .sum)],
                                         filters: [], origin: CellAddress("F1")!, newSheet: false))
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum), PivotDataField(field: 2, function: .average)],
                                         filters: [PivotFilter(field: 1, item: nil)], origin: CellAddress("F12")!, newSheet: false))
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0, 1], cols: [], data: [PivotDataField(field: 2, function: .count)],
                                         filters: [], origin: CellAddress("F24")!, newSheet: false))
        try Xlsx.write(wc.book).write(to: URL(fileURLWithPath: out))
    }
}
