// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp
import Flutter
import FlutterSwiftBridge

final class SheetsSeriesTests: XCTestCase {
    private func a(_ s: String) -> CellAddress { CellAddress(s)! }
    private func controller(_ cells: [String: String]) -> WorkbookController {
        let c = WorkbookController()
        c.load(Workbook(sheets: [Worksheet(name: "S")]))
        for (k, v) in cells { c.setInputs([(a(k), v)]) }
        return c
    }
    private func range(_ c: WorkbookController, _ s: String) { let p = s.split(separator: ":").map(String.init); c.select(range: CellRange(a(p[0]), a(p[1]))) }

    func testLinearDownAColumn() {
        let c = controller(["A1": "5"]); range(c, "A1:A4")
        var o = SeriesOptions(); o.step = 3
        XCTAssertNil(c.fillSeries(o))
        XCTAssertEqual((1 ... 4).map { c.sheet.cells[CellAddress(row: $0 - 1, col: 0)]?.input ?? "" }, ["5", "8", "11", "14"])
        c.undo()
        XCTAssertNil(c.sheet.cells[a("A2")])
    }

    func testGrowthAcrossARowStopsAtStop() {
        let c = controller(["A1": "2"]); range(c, "A1:H1")
        var o = SeriesOptions(); o.byRows = true; o.type = .growth; o.step = 2; o.stop = 20
        XCTAssertNil(c.fillSeries(o))
        XCTAssertEqual(["B1", "C1", "D1"].map { c.sheet.cells[a($0)]?.input ?? "" }, ["4", "8", "16"])
        XCTAssertNil(c.sheet.cells[a("E1")])
    }

    func testSingleCellRunsToStop() {
        let c = controller(["A1": "1"])
        var o = SeriesOptions(); o.step = 2; o.stop = 9
        XCTAssertNil(c.fillSeries(o))
        XCTAssertEqual(c.sheet.cells[a("A5")]?.input, "9")
        XCTAssertNil(c.sheet.cells[a("A6")])
    }

    func testDateByMonthAndWeekday() {
        let c = controller(["A1": "1/31/2024", "C1": "1/5/2024"])
        range(c, "A1:A3")
        var o = SeriesOptions(); o.type = .date; o.unit = .month
        XCTAssertNil(c.fillSeries(o))
        XCTAssertEqual(c.sheet.cells[a("A2")]?.value.number, ExcelDate.serial(2024, 2, 29))
        XCTAssertEqual(c.sheet.cells[a("A3")]?.value.number, ExcelDate.serial(2024, 3, 31))
        range(c, "C1:C3"); o.unit = .weekday
        XCTAssertNil(c.fillSeries(o))
        XCTAssertEqual(c.sheet.cells[a("C2")]?.value.number, ExcelDate.serial(2024, 1, 8))   // Fri → Mon
    }

    func testProblemsAreReported() {
        let c = controller(["A1": "x"]); range(c, "A1:A3")
        XCTAssertNotNil(c.fillSeries(SeriesOptions()))
        range(c, "A1:A1")
        XCTAssertNotNil(c.fillSeries(SeriesOptions()))
    }

    func testRibbonMenuOpensDialogAndFills() {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: SheetsShell(initialPath: nil, onSwitch: { _, _ in }), title: "t"), size: Size(1280, 800))
        let st = ui.state(SheetsShellState.self)!
        st.wb.setInputs([(a("A1"), "1")]); range(st.wb, "A1:A3")
        st.wb.onCommand?(.fillSeries); ui.pump()
        XCTAssertTrue(ui.has(text: "Step value:"))
        ui.tap(text: "OK"); ui.pump()
        XCTAssertEqual(st.wb.sheet.cells[a("A3")]?.input, "3")
    }
}
