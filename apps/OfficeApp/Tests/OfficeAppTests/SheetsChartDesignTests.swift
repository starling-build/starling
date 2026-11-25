// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-1a: Chart Design on a chart made here: its title and legend, saved and read back.

import XCTest
@testable import OfficeApp

final class SheetsChartDesignTests: XCTestCase {
    private func chartBook() -> (WorkbookController, Int) {
        let c = WorkbookController()
        c.setInputs([(CellAddress(row: 0, col: 0), "Q"), (CellAddress(row: 0, col: 1), "Sales"), (CellAddress(row: 0, col: 2), "Cost"),
                     (CellAddress(row: 1, col: 0), "Jan"), (CellAddress(row: 1, col: 1), "5"), (CellAddress(row: 1, col: 2), "3"),
                     (CellAddress(row: 2, col: 0), "Feb"), (CellAddress(row: 2, col: 1), "7"), (CellAddress(row: 2, col: 2), "4")])
        c.select(range: CellRange(top: 0, left: 0, bottom: 2, right: 2))
        XCTAssertTrue(c.insertChart(.column))
        return (c, c.selectedDrawing!)
    }

    private func chart(_ c: WorkbookController, _ i: Int) -> Chart? {
        if case .chart(let sc) = c.sheet.drawings[i].kind { return sc.chart }
        return nil
    }

    func testTitleAndLegendAreEditedAndUndone() {
        let (c, i) = chartBook()
        XCTAssertTrue(chart(c, i)!.legend)
        c.setChartTitle(i, "Results")
        XCTAssertEqual(chart(c, i)!.title, "Results")
        c.setChartLegend(i, position: "r")
        XCTAssertEqual(chart(c, i)!.legendPosition, "r")
        c.setChartLegend(i, position: nil)
        XCTAssertFalse(chart(c, i)!.legend)
        c.undo()
        XCTAssertTrue(chart(c, i)!.legend)
        c.setChartTitle(i, nil)
        XCTAssertNil(chart(c, i)!.title)
    }

    func testTitleAndLegendSaveAndReadBack() throws {
        let (c, i) = chartBook()
        c.setChartTitle(i, "Results")
        c.setChartLegend(i, position: "r")
        let back = try Xlsx.read(try Xlsx.write(c.book))
        guard let d = back.sheets[0].drawings.first(where: { $0.isChart }), case .chart(let sc) = d.kind else { return XCTFail("no chart read back") }
        XCTAssertEqual(sc.chart.title, "Results")
        XCTAssertEqual(sc.chart.legendPosition, "r")
        XCTAssertTrue(sc.chart.legend)
    }

    func testAChartFromTheFileIsRefusedNotSilentlyChanged() throws {
        let (c, i) = chartBook()
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        let before = back.sheet.drawings[j].kind
        back.setChartTitle(j, "Changed")
        XCTAssertEqual(back.sheet.drawings[j].kind, before)
        XCTAssertNotNil(back.chartNotice)
        _ = i
    }

    /// Writes the file for the Excel check (only when XCHECK_DIR is set): a chart titled "Results", legend on the right.
    func testWriteExcelCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let (c, i) = chartBook()
        c.setChartTitle(i, "Results")
        c.setChartLegend(i, position: "r")
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/chartdesign.xlsx"))
    }
}
