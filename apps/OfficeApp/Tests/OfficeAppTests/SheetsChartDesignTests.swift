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

    func testAChartFromTheFileIsPatchedOnlyInItsTitleAndLegend() throws {
        let (c, _) = chartBook()
        let first = try Xlsx.write(c.book)
        let back = WorkbookController(); back.load(try Xlsx.read(first))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        back.setChartTitle(j, "Changed")
        back.setChartLegend(j, position: "t")
        XCTAssertNil(back.chartNotice)
        let again = try Xlsx.read(try Xlsx.write(back.book))
        guard let d = again.sheets[0].drawings.first(where: { $0.isChart }), case .chart(let sc) = d.kind else { return XCTFail("no chart") }
        XCTAssertEqual(sc.chart.title, "Changed")
        XCTAssertEqual(sc.chart.legendPosition, "t")
        // Removing both, and a title with markup characters.
        back.setChartTitle(j, "A & <B>"); back.setChartLegend(j, position: nil)
        let third = try Xlsx.read(try Xlsx.write(back.book))
        guard let d3 = third.sheets[0].drawings.first(where: { $0.isChart }), case .chart(let s3) = d3.kind else { return XCTFail("no chart") }
        XCTAssertEqual(s3.chart.title, "A & <B>")
        XCTAssertFalse(s3.chart.legend)
    }

    func testPatchChangesNothingButTheTitleAndLegend() {
        let xml = "<c:chartSpace><c:chart><c:title><c:tx><c:rich><a:p><a:r><a:rPr b=\"1\"/><a:t>Old</a:t></a:r><a:r><a:t>x</a:t></a:r></a:p></c:rich></c:tx></c:title><c:autoTitleDeleted val=\"0\"/><c:plotArea><c:title>AXIS</c:title></c:plotArea><c:legend><c:legendPos val=\"r\"/></c:legend></c:chart></c:chartSpace>"
        let t = SheetDrawingsXML._patchChartTitle(xml, .set("New"))
        XCTAssertTrue(t.contains("<a:rPr b=\"1\"/><a:t>New</a:t></a:r><"))
        XCTAssertFalse(t.contains("Old")); XCTAssertTrue(t.contains("AXIS"))
        let l = SheetDrawingsXML._patchChartLegend(xml, .set("b"))
        XCTAssertTrue(l.contains("<c:legendPos val=\"b\"/>"))
        XCTAssertEqual(SheetDrawingsXML._patchChartLegend(xml, .remove).contains("legend"), false)
        XCTAssertTrue(SheetDrawingsXML._patchChartTitle(xml, .remove).contains("autoTitleDeleted val=\"1\""))
    }

    /// Writes the file for the Excel check (only when XCHECK_DIR is set): a chart titled "Results", legend on the right.
    func testWriteExcelCheckFile() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let (c, i) = chartBook()
        c.setChartTitle(i, "Results")
        c.setChartLegend(i, position: "r")
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/chartdesign.xlsx"))
        // The same chart after a trip through a file: title "From file", legend at the top.
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        back.setChartTitle(j, "From file"); back.setChartLegend(j, position: "t")
        try Xlsx.write(back.book).write(to: URL(fileURLWithPath: dir + "/chartfile.xlsx"))
    }
}
