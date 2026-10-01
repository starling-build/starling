// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SheetsChartTests: XCTestCase {
    private func table() -> WorkbookController {
        let c = WorkbookController()
        let rows = [["Month", "Sales", "Costs"], ["Jan", "10", "4"], ["Feb", "20", "8"], ["Mar", "15", "9"]]
        var items: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (col, v) in row.enumerated() { items.append((CellAddress(row: r, col: col), v)) } }
        c.setInputs(items)
        c.select(CellAddress("B2")!)
        return c
    }

    private func charts(_ ws: Worksheet) -> [SheetChart] {
        ws.drawings.compactMap { if case .chart(let sc) = $0.kind { return sc } else { return nil } }
    }

    func testInsertChartFromTheTable() throws {
        let c = table()
        XCTAssertTrue(c.insertChart(.column))
        XCTAssertEqual(c.selectedDrawing, 0)
        let sc = try XCTUnwrap(charts(c.sheet).first)
        XCTAssertEqual(sc.refs.count, 2)
        XCTAssertEqual(sc.refs[0].name, "Sheet1!$B$1")
        XCTAssertEqual(sc.refs[0].cat, "Sheet1!$A$2:$A$4")
        XCTAssertEqual(sc.refs[1].val, "Sheet1!$C$2:$C$4")
        let live = c.liveChart(sc)
        XCTAssertEqual(live.categories, ["Jan", "Feb", "Mar"])
        XCTAssertEqual(live.series.map(\.name), ["Sales", "Costs"])
        XCTAssertEqual(live.series[0].values, [10, 20, 15])
        XCTAssertEqual(sc.chart.title, "Chart Title")
        // Beside the data: two columns right of C, level with row 1, 5 × 3 in.
        let f = c.sheet.frame(c.sheet.drawings[0].anchor)
        XCTAssertEqual(f.x, 4 * Worksheet.defaultColWidth, accuracy: 0.01)
        XCTAssertEqual(f.width, 360, accuracy: 0.01)
        XCTAssertEqual(f.height, 216, accuracy: 0.01)
        // A cell click deselects; undo takes the chart away.
        c.select(CellAddress("A1")!)
        XCTAssertNil(c.selectedDrawing)
        c.undo()
        XCTAssertTrue(c.sheet.drawings.isEmpty)
    }

    func testSingleSeriesIsTitledAndPieKeepsOne() throws {
        let c = table()
        c.select(range: CellRange("A1:B4")!)
        XCTAssertTrue(c.insertChart(.pie))
        let sc = try XCTUnwrap(charts(c.sheet).first)
        XCTAssertEqual(sc.refs.count, 1)
        XCTAssertEqual(sc.chart.title, "Sales")
        XCTAssertTrue(sc.chart.legend)
        c.select(CellAddress("H20")!)
        XCTAssertFalse(c.insertChart(.line))     // nothing to chart there
    }

    func testNewChartRoundTripsThroughXlsx() throws {
        let c = table()
        c.insertChart(.line)
        let data = try Xlsx.write(c.book)
        let entries = try Zip.read(data)
        for e in entries where e.name.hasSuffix(".xml") || e.name.hasSuffix(".rels") {
            XCTAssertNotNil(XNode.parse(e.data), "\(e.name) is not well-formed")
        }
        let names = Set(entries.map(\.name))
        XCTAssertTrue(names.contains("xl/drawings/drawing1.xml"))
        XCTAssertTrue(names.contains("xl/charts/chart1.xml"))
        XCTAssertTrue(names.contains("xl/worksheets/_rels/sheet1.xml.rels"))
        let types = String(decoding: entries.first { $0.name == "[Content_Types].xml" }!.data, as: UTF8.self)
        XCTAssertTrue(types.containsSubstring("/xl/drawings/drawing1.xml"))
        XCTAssertTrue(types.containsSubstring("/xl/charts/chart1.xml"))
        let chartXML = String(decoding: entries.first { $0.name == "xl/charts/chart1.xml" }!.data, as: UTF8.self)
        XCTAssertFalse(chartXML.containsSubstring("externalData"))
        XCTAssertTrue(chartXML.containsSubstring("<c:f>Sheet1!$C$2:$C$4</c:f>"))

        let back = try Xlsx.read(data)
        let sc = try XCTUnwrap(charts(back.sheets[0]).first)
        XCTAssertEqual(sc.chart.type, .line)
        XCTAssertEqual(sc.refs.map(\.val), ["Sheet1!$B$2:$B$4", "Sheet1!$C$2:$C$4"])
        XCTAssertEqual(sc.chart.series[1].values, [4, 8, 9])
        XCTAssertEqual(back.sheets[0].drawings[0].anchor, c.sheet.drawings[0].anchor)
        // Saved again untouched, it is written back as read.
        let again = try Xlsx.write(back)
        XCTAssertEqual(try Zip.read(again).first { $0.name == "xl/drawings/drawing1.xml" }?.data,
                       entries.first { $0.name == "xl/drawings/drawing1.xml" }?.data)
    }

    func testEditingAFilesChartsKeepsTheRest() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let original = try Data(contentsOf: url)
        let c = WorkbookController()
        c.load(try Xlsx.read(original))
        XCTAssertEqual(c.sheet.drawings.count, 2)
        let kept = c.sheet.drawings[1]
        let f = c.sheet.frame(c.sheet.drawings[0].anchor)
        c.setDrawingFrame(0, x: f.x + 100, y: f.y + 40, width: f.width, height: f.height)
        c.setChartType(1, .bar)
        c.deleteDrawing(1)
        XCTAssertEqual(c.sheet.drawings.count, 1)
        let data = try Xlsx.write(c.book)
        let back = try Xlsx.read(data)
        XCTAssertEqual(back.sheets[0].drawings.count, 1)
        XCTAssertEqual(back.sheets[0].frame(back.sheets[0].drawings[0].anchor).x, f.x + 100, accuracy: 0.01)
        // The other sheets' drawings were not touched at all.
        for i in 1 ..< back.sheets.count { XCTAssertEqual(back.sheets[i].drawings.count, c.book.sheets[i].drawings.count) }
        let entries = try Zip.read(data)
        let o = try Zip.read(original)
        for name in ["xl/drawings/drawing2.xml", "xl/charts/chart3.xml"] {
            XCTAssertNotNil(o.first { $0.name == name }, name)
            XCTAssertEqual(entries.first { $0.name == name }?.data, o.first { $0.name == name }?.data, name)
        }
        for e in entries where e.name.hasSuffix(".xml") || e.name.hasSuffix(".rels") {
            XCTAssertNotNil(XNode.parse(e.data), "\(e.name) is not well-formed")
        }
        _ = kept
        // Deleting the last one drops the drawing part and its <drawing>.
        c.deleteDrawing(0)
        let none = try Zip.read(try Xlsx.write(c.book))
        let sheet = String(decoding: none.first { $0.name == "xl/worksheets/sheet1.xml" }!.data, as: UTF8.self)
        XCTAssertFalse(sheet.containsSubstring("<drawing"))
    }
}

extension SheetsChartTests {
    func testChartsFollowRowsAndSheetNames() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: url)))
        let before = c.sheet.drawings.map(\.anchor)
        c.insert(.rows, at: 0, count: 2)
        _ = c.renameSheet(0, "Doubles")
        guard case .chart(let sc) = c.sheet.drawings[0].kind else { return XCTFail("no chart") }
        XCTAssertEqual(sc.refs[0].val, "Doubles!$E$6:$J$6")
        if case .twoCell(let from, _) = c.sheet.drawings[0].anchor, case .twoCell(let old, _) = before[0] {
            XCTAssertEqual(from.row, old.row + 2)
        } else { XCTFail("anchor") }
        // The chart still reads the same numbers, now two rows down.
        XCTAssertEqual(c.liveChart(sc).series.map(\.values), sc.chart.series.map(\.values))

        let data = try Xlsx.write(c.book)
        let entries = try Zip.read(data)
        for e in entries where e.name.hasSuffix(".xml") || e.name.hasSuffix(".rels") {
            XCTAssertNotNil(XNode.parse(e.data), "\(e.name) is not well-formed")
        }
        let back = try Xlsx.read(data)
        let w = WorkbookController()
        w.load(back)
        guard case .chart(let sc2) = back.sheets[0].drawings[0].kind else { return XCTFail("no chart after save") }
        XCTAssertEqual(sc2.refs[0].val, "Doubles!$E$6:$J$6")
        XCTAssertEqual(w.liveChart(sc2).series.map(\.values), sc2.chart.series.map(\.values))
        XCTAssertEqual(back.sheets[0].drawings[0].anchor, c.sheet.drawings[0].anchor)
        // Every other part of the chart is as the file had it: only the references differ.
        let o = try Zip.read(try Data(contentsOf: url))
        let path = try XCTUnwrap(sc.path)
        let was = String(decoding: try XCTUnwrap(o.first { $0.name == path }).data, as: UTF8.self)
        let now = String(decoding: try XCTUnwrap(entries.first { $0.name == path }).data, as: UTF8.self)
        func withoutRefs(_ x: String) -> String {
            var out = "", at = x.startIndex
            while let a = x.findRange(of: "<c:f>", in: at ..< x.endIndex), let b = x.findRange(of: "</c:f>", in: a.upperBound ..< x.endIndex) {
                out += x[at ..< a.upperBound]; at = b.lowerBound
            }
            return out + x[at...]
        }
        XCTAssertEqual(withoutRefs(was), withoutRefs(now))
        XCTAssertTrue(now.containsSubstring("<c:f>Doubles!$E$6:$J$6</c:f>"))
        XCTAssertFalse(now.containsSubstring("Single double"))
    }
}
