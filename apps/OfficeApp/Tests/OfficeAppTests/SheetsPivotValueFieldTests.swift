import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Value Field Settings: the function, the heading, the number format and Show Values As.
final class SheetsPivotValueFieldTests: XCTestCase {
    private func book(cols: [Int] = []) -> WorkbookController {
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Product", "Sales"], ["East", "Pen", "10"], ["West", "Pen", "20"], ["East", "Ink", "5"],
                                ["East", "Pen", "30"], ["West", "Ink", "8"], ["North", "Pen", "7"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), v)) } }
        wc.setInputs(inputs)
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:C7", rows: [0], cols: cols, data: [PivotDataField(field: 2, function: .sum)], filters: [],
                                         origin: CellAddress("F1")!, newSheet: false))
        wc.select(CellAddress("F2")!)
        return wc
    }
    private func num(_ wc: WorkbookController, _ a: String) -> Double? { wc.sheet.cells[CellAddress(a)!]?.value.number }

    /// The saved dataField carries its function, Show Values As and number format, and omits what is the default
    /// (the attributes are built one at a time: as a single `+` chain the iOS compiler timed out on them).
    func testTheSavedDataFieldCarriesFunctionShowAsAndFormat() throws {
        func saved(_ d: PivotDataField) throws -> String {
            let wc = book()
            XCTAssertNil(wc.setPivotValueField(0, d))
            let zip = try Zip.read(try Xlsx.write(wc.book))
            let entry = try XCTUnwrap(zip.first { $0.name == "xl/pivotTables/pivotTable1.xml" })
            return String(decoding: entry.data, as: UTF8.self)
        }
        let plain = try saved(PivotDataField(field: 2, function: .sum))
        XCTAssertTrue(plain.contains("fld=\"2\" baseField=\"0\" baseItem=\"0\"/>"), plain)
        XCTAssertFalse(plain.contains("subtotal="))
        XCTAssertFalse(plain.contains("showDataAs="))
        XCTAssertFalse(plain.contains("numFmtId="))
        let max = try saved(PivotDataField(field: 2, function: .max, name: "Biggest"))
        XCTAssertTrue(max.contains("<dataField name=\"Biggest\" fld=\"2\" subtotal=\"max\" baseField=\"0\""), max)
        let share = try saved(PivotDataField(field: 2, function: .sum, showAs: .percentOfTotal))
        XCTAssertTrue(share.contains("showDataAs=\"percentOfTotal\" numFmtId=\"10\" baseField=\"0\""), share)
    }

    func testMinMaxAndName() {
        let wc = book()
        XCTAssertNil(wc.setPivotValueField(0, PivotDataField(field: 2, function: .max, name: "Biggest")))
        XCTAssertEqual(wc.sheet.cells[CellAddress("G1")!]?.value, .text("Biggest"))
        XCTAssertEqual(num(wc, "G2"), 30)   // East
        XCTAssertNil(wc.setPivotValueField(0, PivotDataField(field: 2, function: .min)))
        XCTAssertEqual(wc.sheet.cells[CellAddress("G1")!]?.value, .text("Min of Sales"))
        XCTAssertEqual(num(wc, "G2"), 5)
        XCTAssertEqual(num(wc, "G5"), 5)    // Grand Total
    }

    func testPercentOfGrandTotalAndFormat() {
        let wc = book()
        XCTAssertNil(wc.setPivotValueField(0, PivotDataField(field: 2, function: .sum, showAs: .percentOfTotal)))
        XCTAssertEqual(num(wc, "G2")!, 45.0 / 80, accuracy: 1e-9)
        XCTAssertEqual(num(wc, "G5")!, 1, accuracy: 1e-9)
        XCTAssertEqual(wc.book.style(wc.sheet.cells[CellAddress("G2")!]!.style ?? 0).numberFormat, "0.00%")
        XCTAssertNil(wc.setPivotValueField(0, PivotDataField(field: 2, function: .sum, numberFormat: "#,##0.00")))
        XCTAssertEqual(wc.book.style(wc.sheet.cells[CellAddress("G2")!]!.style ?? 0).numberFormat, "#,##0.00")
        XCTAssertEqual(num(wc, "G2"), 45)
    }

    func testPercentOfRowAndColumnWithColumnField() {
        let wc = book(cols: [1])      // Ink, Pen, Grand Total
        XCTAssertNil(wc.setPivotValueField(0, PivotDataField(field: 2, function: .sum, showAs: .percentOfRow)))
        // East: Ink 5, Pen 40, total 45
        XCTAssertEqual(num(wc, "G3")!, 5.0 / 45, accuracy: 1e-9)
        XCTAssertEqual(num(wc, "I3")!, 1, accuracy: 1e-9)
        XCTAssertNil(wc.setPivotValueField(0, PivotDataField(field: 2, function: .sum, showAs: .percentOfCol)))
        // Pen column: East 40 of 67
        XCTAssertEqual(num(wc, "H3")!, 40.0 / 67, accuracy: 1e-9)
    }
}

final class SheetsPivotValueFieldDialogTests: XCTestCase {
    func testDialogChangesTheValueField() {
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Sales"], ["East", "10"], ["West", "20"], ["East", "5"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, v) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), v)) } }
        wc.setInputs(inputs)
        XCTAssertNil(wc.insertPivotTable(source: "Sheet1!A1:B4", rows: [0], cols: [], data: [PivotDataField(field: 1, function: .sum)], filters: [],
                                         origin: CellAddress("D1")!, newSheet: false))
        wc.select(CellAddress("D2")!)
        let t = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: PivotValueFieldDialog(controller: wc, index: 0, onClose: {}), title: "Test"), size: Size(600, 900))
        XCTAssertTrue(t.has(id: "pvv-function"))
        XCTAssertTrue(t.has(id: "pvv-showas"))
        XCTAssertTrue(t.has(id: "pvv-format"))
        XCTAssertTrue(t.has(id: "pvv-name"))
    }
}

final class SheetsPivotValueFieldCheckBook: XCTestCase {
    /// Four pivots for Excel to open: Min and Max with a custom name; % of grand total; % of row total with a column field; a number format.
    func testWriteValueFieldCheckBook() throws {
        guard let out = ProcessInfo.processInfo.environment["STARLING_PIVOT_VALUES"] else { throw XCTSkip("no STARLING_PIVOT_VALUES") }
        let wc = WorkbookController()
        let rows: [[String]] = [["Region", "Product", "Sales", "Units"], ["East", "Pen", "10", "1"], ["East", "Pen", "20", "2"], ["East", "Ink", "5", "3"],
                                ["West", "Pen", "7", "4"], ["West", "Ink", "9", "5"], ["West", "Pen", "11", "6"]]
        var inputs: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (c, x) in row.enumerated() { inputs.append((CellAddress(row: r, col: c), x)) } }
        wc.setInputs(inputs)
        let s = "Sheet1!A1:D7"
        let specs: [(String, [Int], PivotDataField)] = [
            ("F1", [], PivotDataField(field: 2, function: .max, name: "Biggest sale")),
            ("F8", [], PivotDataField(field: 2, function: .min)),
            ("F15", [], PivotDataField(field: 2, function: .sum, showAs: .percentOfTotal)),
            ("F22", [1], PivotDataField(field: 2, function: .sum, showAs: .percentOfRow)),
            ("F30", [], PivotDataField(field: 2, function: .average, numberFormat: "#,##0.00")),
        ]
        for (at, cols, d) in specs {
            XCTAssertNil(wc.insertPivotTable(source: s, rows: [0], cols: cols, data: [d], filters: [], origin: CellAddress(at)!, newSheet: false))
        }
        try Xlsx.write(wc.book).write(to: URL(fileURLWithPath: out))
    }
}
