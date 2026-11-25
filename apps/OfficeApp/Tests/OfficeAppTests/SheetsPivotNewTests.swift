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

    func testSeveralValuesWithAColumnField() {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [1], data: [PivotDataField(field: 2, function: .sum), PivotDataField(field: 2, function: .average)],
                                         filters: [], origin: CellAddress("F1")!, newSheet: false))
        XCTAssertEqual(v(wc, "G1"), .text("Column Labels")); XCTAssertEqual(v(wc, "F1"), .empty)
        XCTAssertEqual(v(wc, "G2"), .text("Ink")); XCTAssertEqual(v(wc, "I2"), .text("Pen"))
        XCTAssertEqual(v(wc, "K2"), .text("Total Sum of Sales")); XCTAssertEqual(v(wc, "L2"), .text("Total Average of Sales"))
        XCTAssertEqual(v(wc, "F3"), .text("Row Labels")); XCTAssertEqual(v(wc, "G3"), .text("Sum of Sales")); XCTAssertEqual(v(wc, "J3"), .text("Average of Sales"))
        XCTAssertEqual(v(wc, "F4"), .text("East"))
        XCTAssertEqual(v(wc, "G4"), .number(5)); XCTAssertEqual(v(wc, "H4"), .number(5)); XCTAssertEqual(v(wc, "I4"), .number(40)); XCTAssertEqual(v(wc, "J4"), .number(20))
        XCTAssertEqual(v(wc, "K4"), .number(45)); XCTAssertEqual(v(wc, "L4"), .number(15))
        XCTAssertEqual(v(wc, "F7"), .text("Grand Total")); XCTAssertEqual(v(wc, "K7"), .number(80)); XCTAssertEqual(v(wc, "L7"), .number(80.0 / 6))
        XCTAssertEqual(wc.sheet.pivots.last?.ref, CellRange("F1:L7"))
        XCTAssertEqual(wc.sheet.pivots.last?.headerRows, 3)
    }

    func testTwoColumnFields() {
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Product", "Year", "Sales"], ["East", "Pen", "2020", "10"], ["East", "Pen", "2021", "20"],
                                ["East", "Ink", "2020", "5"], ["West", "Pen", "2020", "7"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, x) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), x)) } }
        wc.setInputs(inputs)
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:D5", rows: [0], cols: [1, 2], data: [PivotDataField(field: 3, function: .sum)],
                                         filters: [], origin: CellAddress("F1")!, newSheet: false))
        XCTAssertEqual(v(wc, "F1"), .text("Sum of Sales")); XCTAssertEqual(v(wc, "G1"), .text("Column Labels"))
        XCTAssertEqual(v(wc, "G2"), .text("Ink")); XCTAssertEqual(v(wc, "H2"), .text("Ink Total")); XCTAssertEqual(v(wc, "I2"), .text("Pen"))
        XCTAssertEqual(v(wc, "K2"), .text("Pen Total")); XCTAssertEqual(v(wc, "L2"), .text("Grand Total"))
        XCTAssertEqual(v(wc, "F3"), .text("Row Labels")); XCTAssertEqual(v(wc, "G3"), .text("2020")); XCTAssertEqual(v(wc, "J3"), .text("2021"))
        XCTAssertEqual(v(wc, "G4"), .number(5)); XCTAssertEqual(v(wc, "I4"), .number(10)); XCTAssertEqual(v(wc, "J4"), .number(20))
        XCTAssertEqual(v(wc, "K4"), .number(30)); XCTAssertEqual(v(wc, "L4"), .number(35))
        XCTAssertEqual(v(wc, "G5"), .empty); XCTAssertEqual(v(wc, "I5"), .number(7)); XCTAssertEqual(v(wc, "L5"), .number(7))
        XCTAssertEqual(v(wc, "L6"), .number(42))
        XCTAssertEqual(wc.sheet.pivots.last?.ref, CellRange("F1:L6"))
        // The saved table lists the columns the way Excel does, subtotals after their items.
        let p = try? parts(wc)
        let t = p?["xl/pivotTables/pivotTable1.xml"] ?? ""
        XCTAssertTrue(t.containsSubstring("<colFields count=\"2\"><field x=\"1\"/><field x=\"2\"/></colFields>"))
        XCTAssertTrue(t.containsSubstring("<i t=\"default\"><x/></i>"))
        XCTAssertTrue(t.containsSubstring("<colItems count=\"6\">"))
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

    func testWriteColumnFieldCheckBook() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_PIVOT_COLS"] else { throw XCTSkip("no STARLING_PIVOT_COLS") }
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Product", "Year", "Sales", "Units"], ["East", "Pen", "2020", "10", "1"], ["East", "Pen", "2021", "20", "2"],
                                ["East", "Ink", "2020", "5", "3"], ["West", "Pen", "2020", "7", "4"], ["West", "Ink", "2021", "9", "5"], ["West", "Pen", "2021", "11", "6"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, x) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), x)) } }
        wc.setInputs(inputs)
        let s = "Sheet1!A1:E7"
        XCTAssertNil(wc.insertPivotTable(source: s, rows: [0], cols: [2], data: [PivotDataField(field: 3, function: .sum), PivotDataField(field: 4, function: .sum)],
                                         filters: [], origin: CellAddress("H1")!, newSheet: false))
        XCTAssertNil(wc.insertPivotTable(source: s, rows: [0], cols: [1, 2], data: [PivotDataField(field: 3, function: .sum)],
                                         filters: [], origin: CellAddress("H14")!, newSheet: false))
        XCTAssertNil(wc.insertPivotTable(source: s, rows: [0], cols: [1, 2], data: [PivotDataField(field: 3, function: .sum), PivotDataField(field: 4, function: .count)],
                                         filters: [], origin: CellAddress("H26")!, newSheet: false))
        try Xlsx.write(wc.book).write(to: URL(fileURLWithPath: out))
    }

    /// A pivot that came from a file is laid out again from the source, its parts stay the file's, and its cache is set to refresh.
    func testRefreshAPivotFromAFile() throws {
        let first = book()
        XCTAssertNil(first.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                            origin: CellAddress("F1")!, newSheet: false))
        let wc = WorkbookController()
        wc.load(try Xlsx.read(try Xlsx.write(first.book)))
        XCTAssertNil(wc.sheet.pivots[0].made)
        XCTAssertNotNil(wc.sheet.pivots[0].fileSpec)
        wc.setInputs([(CellAddress("C2")!, "100"), (CellAddress("C3")!, "50")])
        XCTAssertEqual(wc.refreshPivots(), 1)
        XCTAssertEqual(v(wc, "F2"), .text("East")); XCTAssertEqual(v(wc, "G2"), .number(135))
        XCTAssertEqual(v(wc, "G4"), .number(58))
        let p = try parts(wc)
        XCTAssertEqual(p.keys.filter { $0.hasPrefix("xl/pivotTables/pivotTable") && $0.hasSuffix(".xml") }.count, 1)
        XCTAssertTrue(p["xl/pivotCache/pivotCacheDefinition1.xml"]?.contains("refreshOnLoad=\"1\"") ?? false)
    }

    /// GETPIVOTDATA reads the pivot's cells, so a refresh changes it (it used to keep its cached value).
    func testGetPivotDataFollowsARefresh() throws {
        let wc = book()
        XCTAssertNil(wc.insertPivotTable(source: src, rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("F1")!, newSheet: false))
        wc.setInputs([(CellAddress("J1")!, "=GETPIVOTDATA(\"Sum of Sales\",F1,\"Region\",\"East\")"),
                      (CellAddress("J2")!, "=GETPIVOTDATA(G1,F1)")])
        let before = v(wc, "J1")
        XCTAssertEqual(before, v(wc, "G2"))
        XCTAssertEqual(v(wc, "J2"), v(wc, "G\(wc.sheet.pivots[0].ref.bottom + 1)"))
        wc.setInputs([(CellAddress("C2")!, "1000")])
        XCTAssertEqual(wc.refreshPivots(), 1)
        XCTAssertEqual(v(wc, "J1"), v(wc, "G2"))
        XCTAssertNotEqual(v(wc, "J1"), before)
        XCTAssertEqual(v(wc, "J2"), v(wc, "G\(wc.sheet.pivots[0].ref.bottom + 1)"))
    }

    /// Corpus book 54436 (a pivot Excel made): two source scores changed, refreshed here, saved for the Excel check.
    func testWriteRefreshedCorpusPivot() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_PIVOT_REFRESHED"] else { throw XCTSkip("no STARLING_PIVOT_REFRESHED") }
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 5 { dir.deleteLastPathComponent() }
        let wc = WorkbookController()
        wc.load(try Xlsx.read(try Data(contentsOf: dir.appendingPathComponent("test/corpus/xlsx/books/54436.xlsx"))))
        XCTAssertNotNil(wc.sheet.pivots[0].fileSpec)
        wc.setInputs([(CellAddress("C2")!, "11"), (CellAddress("C5")!, "14")])
        XCTAssertEqual(wc.refreshPivots(), 1)
        XCTAssertEqual(v(wc, "A9"), .text("Category 1")); XCTAssertEqual(v(wc, "B9"), .number(13))
        XCTAssertEqual(v(wc, "B10"), .number(22)); XCTAssertEqual(v(wc, "B11"), .number(35))
        try Xlsx.write(wc.book).write(to: URL(fileURLWithPath: out))
    }
}
