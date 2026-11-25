import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Grouping a pivot field: number ranges and date parts, the same on every pivot over one source, and the cache XML for Excel.
final class SheetsPivotGroupTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int) -> String { String(Int(ExcelDate.serial(y, m, day))) }
    private func book(dates: Bool) -> WorkbookController {
        let wc = WorkbookController()
        let rows: [[String]] = dates
            ? [["Day", "Sales"], [d(2024, 1, 15), "10"], [d(2024, 2, 20), "20"], [d(2024, 2, 25), "5"], [d(2024, 4, 2), "30"], [d(2025, 1, 5), "8"]]
            : [["Age", "Sales"], ["3", "10"], ["12", "20"], ["18", "5"], ["25", "30"], ["31", "8"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), v)) } }
        wc.setInputs(inputs)
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:B6", rows: [0], cols: [], data: [PivotDataField(field: 1, function: .sum)], filters: [],
                                         origin: CellAddress("D1")!, newSheet: false))
        return wc
    }
    private func column(_ wc: WorkbookController) -> [String] {
        (0 ... 12).compactMap { r in wc.sheet.cells[CellAddress(row: r, col: 3)].map { NumberFormat.display($0.value, "General", width: 255).text } }
    }
    private func sums(_ wc: WorkbookController) -> [Double] {
        (1 ... 12).compactMap { r in wc.sheet.cells[CellAddress(row: r, col: 4)]?.value.number }
    }

    func testNumberRanges() {
        let wc = book(dates: false)
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: .numbers(start: 0, end: 29, by: 10)))
        // (a group nobody falls in is not shown, as in Excel)
        XCTAssertEqual(column(wc), ["Row Labels", "0-9", "10-19", "20-29", ">29", "Grand Total"])
        XCTAssertEqual(wc.sheet.cells[CellAddress("E2")!]?.value.number, 10)
        XCTAssertEqual(wc.sheet.cells[CellAddress("E3")!]?.value.number, 25)
        XCTAssertEqual(wc.sheet.cells[CellAddress("E4")!]?.value.number, 30)
        XCTAssertEqual(wc.sheet.cells[CellAddress("E5")!]?.value.number, 8)
    }

    func testLastBucketRunsToTheEndInclusive() {
        let g = PivotGroup.numbers(start: 0, end: 80, by: 10)
        let labels = g.items([]).map(\.shown)
        XCTAssertEqual(labels, ["<0", "0-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "70-80", ">80"])
        XCTAssertEqual(g.index(of: .number(80), minYear: 0), 8)
        XCTAssertEqual(g.index(of: .number(70), minYear: 0), 8)
        XCTAssertEqual(g.index(of: .number(81), minYear: 0), 9)
        XCTAssertEqual(g.index(of: .number(-1), minYear: 0), 0)
    }

    func testDateMonthsAndYears() {
        let wc = book(dates: true)
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: .dates(.years)))
        XCTAssertTrue(column(wc).contains("2024") && column(wc).contains("2025"), "\(column(wc))")
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: .dates(.months)))
        XCTAssertTrue(column(wc).contains("Jan") && column(wc).contains("Apr") && !column(wc).contains("Dec"))
        // January: 10 (2024) + 8 (2025)
        let jan = (1 ... 20).first { wc.sheet.cells[CellAddress(row: $0, col: 3)].map { NumberFormat.display($0.value, "General", width: 255).text } == "Jan" }!
        XCTAssertEqual(wc.sheet.cells[CellAddress(row: jan, col: 4)]?.value.number, 18)
    }

    func testUngroupAndUndo() {
        let wc = book(dates: false)
        let before = column(wc)
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: .numbers(start: 0, end: 29, by: 10)))
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: nil))
        XCTAssertEqual(column(wc), before)
        XCTAssertNotNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: .numbers(start: 5, end: 1, by: 10)))
    }

    func testGroupsApplyToEveryPivotOnTheSource() {
        let wc = book(dates: false)
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:B6", rows: [0], cols: [], data: [PivotDataField(field: 1, function: .count)], filters: [],
                                         origin: CellAddress("H1")!, newSheet: false))
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: .numbers(start: 0, end: 29, by: 10)))
        XCTAssertEqual(wc.sheet.cells[CellAddress("H2")!]?.value, wc.sheet.cells[CellAddress("D2")!]?.value)
        // a pivot made afterwards starts grouped too
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:B6", rows: [0], cols: [], data: [PivotDataField(field: 1, function: .sum)], filters: [],
                                         origin: CellAddress("K1")!, newSheet: false))
        XCTAssertEqual(wc.sheet.cells[CellAddress("K3")!]?.value, wc.sheet.cells[CellAddress("D3")!]?.value)
    }

    func testCacheXMLHasTheFieldGroup() throws {
        let wc = book(dates: false)
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: .numbers(start: 0, end: 29, by: 10)))
        let files = try Zip.read(try Xlsx.write(wc.book))
        let cache = try XCTUnwrap(files.first { $0.name.hasPrefix("xl/pivotCache/pivotCacheDefinition") }.map { String(decoding: $0.data, as: UTF8.self) })
        XCTAssertTrue(cache.contains("<fieldGroup base=\"0\"><rangePr autoStart=\"0\" autoEnd=\"0\" startNum=\"0\" endNum=\"29\" groupInterval=\"10\"/><groupItems count=\"5\">"), cache)
        XCTAssertTrue(cache.contains("<s v=\"10-19\"/>"))
    }

    func testDialogOffersRangeForNumbersAndGroupsOnOK() {
        let wc = book(dates: false)
        wc.select(CellAddress("D2")!)
        let t = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: PivotGroupDialog(controller: wc, field: 0, onClose: {}), title: "Test"), size: Size(600, 900))
        XCTAssertTrue(t.has(id: "pvg-start"))
        XCTAssertTrue(t.has(id: "pvg-end"))
        XCTAssertTrue(t.has(id: "pvg-by"))
        XCTAssertEqual(wc.pivotGroupInfo(0)?.min, 3)
        XCTAssertEqual(wc.pivotGroupInfo(0)?.isDate, false)
    }
}

/// Four pivots for Excel to open: numbers by 10, dates by months, years, quarters (the last two share one source, so they are grouped alike).
final class SheetsPivotGroupCheckBook: XCTestCase {
    func testWriteGroupCheckBook() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_PIVOT_GROUPS"] else { throw XCTSkip("no STARLING_PIVOT_GROUPS") }
        let wc = WorkbookController()
        var rows: [[String]] = [["Age", "Day", "Sales"]]
        for i in 0 ..< 24 { rows.append([String(3 + i * 3), String(Int(ExcelDate.serial(2024 + i / 12, 1 + i % 12, 1 + (i * 5) % 27))), String(10 + i)]) }
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, x) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), x)) } }
        wc.setInputs(inputs)
        var st = wc.book.style(0); st.numberFormat = "m/d/yyyy"
        let dateStyle = wc.book.styleIndex(st)
        for r in 1 ... 24 { wc.sheet.cells[CellAddress(row: r, col: 1)]?.style = dateStyle }
        // Age by tens beside one sheet's source; the Day source groups by months (a second pivot over it, grouped the same).
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:C25", rows: [0], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [], origin: CellAddress("F1")!, newSheet: false))
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:C25", rows: [1], cols: [], data: [PivotDataField(field: 2, function: .sum)], filters: [], origin: CellAddress("J1")!, newSheet: false))
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:C25", rows: [1], cols: [], data: [PivotDataField(field: 2, function: .count)], filters: [], origin: CellAddress("N1")!, newSheet: false))
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 0, field: 0, group: .numbers(start: 0, end: 80, by: 10)))
        XCTAssertNil(wc.setPivotGroup(sheet: wc.sheet, pivot: 1, field: 1, group: .dates(.months)))
        try Xlsx.write(wc.book).write(to: URL(fileURLWithPath: out))
    }
}
