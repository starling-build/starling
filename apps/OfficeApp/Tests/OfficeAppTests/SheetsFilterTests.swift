// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsFilterTests: XCTestCase {
    /// Region | Sales, five rows of data, one blank region.
    private func table() -> WorkbookController {
        let c = WorkbookController()
        let rows: [(String, String)] = [("Region", "Sales"), ("East", "10"), ("West", "20"), ("East", "30"), ("", "40"), ("North", "50")]
        var items: [(CellAddress, String)] = []
        for (i, r) in rows.enumerated() {
            items.append((CellAddress(row: i, col: 0), r.0))
            items.append((CellAddress(row: i, col: 1), r.1))
        }
        c.setInputs(items)
        c.select(CellAddress("A1")!)
        return c
    }

    func testFilterHidesAndCounts() {
        let c = table()
        c.toggleAutoFilter()
        XCTAssertEqual(c.sheet.autoFilter?.range, CellRange("A1:B6"))
        XCTAssertEqual(c.filterValues(col: 0), ["East", "North", "West", ""])
        c.setFilter(col: 0, allowed: ["East"])
        XCTAssertEqual(c.sheet.filteredRows, [2, 4, 5])
        XCTAssertEqual(c.filterSummary, "2 of 5 records found")
        // The status bar's figures skip hidden rows.
        c.select(range: CellRange("B2:B6")!)
        XCTAssertEqual(c.selectionStats.sum, 40)
        // Blanks are a value like any other.
        c.setFilter(col: 0, allowed: ["East", ""])
        XCTAssertEqual(c.sheet.filteredRows, [2, 5])
        // A second column narrows it further.
        c.setFilter(col: 1, allowed: ["30", "40"])
        XCTAssertEqual(c.sheet.filteredRows, [1, 2, 5])
        c.clearFilters()
        XCTAssertTrue(c.sheet.filteredRows.isEmpty)
        XCTAssertNotNil(c.sheet.autoFilter)
        c.undo()
        XCTAssertEqual(c.sheet.filteredRows, [1, 2, 5])
        c.toggleAutoFilter()
        XCTAssertNil(c.sheet.autoFilter)
        XCTAssertTrue(c.sheet.filteredRows.isEmpty)
    }

    func testRowsMoveAndSortReapplies() {
        let c = table()
        c.toggleAutoFilter()
        c.setFilter(col: 0, allowed: ["East"])
        // Insert a row above the table: everything moves down one.
        c.insert(.rows, at: 0)
        XCTAssertEqual(c.sheet.autoFilter?.range, CellRange("A2:B7"))
        XCTAssertEqual(c.sheet.filteredRows, [3, 5, 6])
        c.undo()
        // Sorting by Sales descending keeps the East rows the shown ones.
        c.sortFilter(col: 1, ascending: false)
        XCTAssertEqual(c.sheet.value(CellAddress("A2")!), .text("North"))
        XCTAssertEqual(c.sheet.filteredRows, [1, 2, 4])
        XCTAssertEqual(c.sheet.value(CellAddress("B4")!), .number(30))   // North 50, blank 40, East 30…
        // A row typed under the table joins it on reapply.
        c.setInputs([(CellAddress("A7")!, "South"), (CellAddress("B7")!, "60")])
        c.structural { c.reapplyFilter() }
        XCTAssertEqual(c.sheet.autoFilter?.range, CellRange("A1:B7"))
        XCTAssertTrue(c.sheet.filteredRows.contains(6))
    }

    func testGridAxisSkipsHidden() {
        let ax = GridAxis(def: 10, overrides: [3: 30], hidden: [1, 2], scale: 1)
        XCTAssertEqual(ax.start(1), 10)
        XCTAssertEqual(ax.start(3), 10)
        XCTAssertEqual(ax.start(4), 40)
        XCTAssertEqual(ax.start(6), 60)
        XCTAssertEqual(ax.index(at: 5), 0)
        XCTAssertEqual(ax.index(at: 10), 3)     // 1 and 2 have no height
        XCTAssertEqual(ax.index(at: 39), 3)
        XCTAssertEqual(ax.index(at: 40), 4)
        XCTAssertEqual(ax.index(at: 55), 5)
        XCTAssertEqual(ax.size(2), 0)
        XCTAssertEqual(ax.size(9), 10)
    }

    func testXlsxRoundTrip() throws {
        let c = table()
        c.sheet.rowHeights[3] = 24
        c.toggleAutoFilter()
        c.setFilter(col: 0, allowed: ["West", ""])
        let data = try Xlsx.write(c.book)
        let back = try Xlsx.read(data)
        let ws = back.sheets[0]
        XCTAssertEqual(ws.autoFilter?.range, CellRange("A1:B6"))
        XCTAssertEqual(ws.autoFilter?.columns[0], ["West", ""])
        XCTAssertEqual(ws.filteredRows, [1, 3, 5])
        XCTAssertEqual(ws.rowHeights[3], 24)     // hidden by the filter, its height kept
        XCTAssertNil(ws.autoFilter?.raw)
    }

    func testUnmodelledFilterIsKeptAsWritten() throws {
        let c = table()
        c.toggleAutoFilter()
        c.setFilter(col: 1, allowed: ["10"])
        var data = try Xlsx.write(c.book)
        // Swap in a custom (greater-than) filter that is not modelled.
        var entries = try Zip.read(data)
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "xl/worksheets/sheet1.xml" })
        var sheet = String(decoding: entries[i].data, as: UTF8.self)
        let start = sheet.findRange(of: "<autoFilter")!.lowerBound, end = sheet.findRange(of: "</autoFilter>")!.upperBound
        let custom = "<autoFilter ref=\"A1:B6\"><filterColumn colId=\"1\"><customFilters><customFilter operator=\"greaterThan\" val=\"25\"/></customFilters></filterColumn></autoFilter>"
        sheet.replaceSubrange(start ..< end, with: custom)
        entries[i] = ZipEntry(name: entries[i].name, data: Data(sheet.utf8))
        data = try Zip.write(entries)
        let book = try Xlsx.read(data)
        XCTAssertEqual(book.sheets[0].autoFilter?.raw, custom)
        let out = try Zip.read(try Xlsx.write(book))
        let again = String(decoding: try XCTUnwrap(out.first { $0.name == "xl/worksheets/sheet1.xml" }).data, as: UTF8.self)
        XCTAssertTrue(again.containsSubstring(custom))
    }
}
