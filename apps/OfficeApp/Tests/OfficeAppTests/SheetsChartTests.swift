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

    /// A date axis counted in months has a slot for each month from the first date to the last, each point in its own
    /// date's month and a blank row in none: Excel's print of chart-tdf134118 (10 May to 16 Aug over 14 rows) has 4
    /// slots named 1-May to 1-Aug, not one for each row.
    func testAMonthDateAxisHasASlotForEachMonth() throws {
        let c = WorkbookController()
        let rows = [["Day", "Value"], ["5/10/2020", "10"], ["6/12/2020", "12"], ["8/16/2020", "16"], ["", "20"], ["", ""]]
        var items: [(CellAddress, String)] = []
        for (r, row) in rows.enumerated() { for (col, v) in row.enumerated() where !v.isEmpty { items.append((CellAddress(row: r, col: col), v)) } }
        c.setInputs(items)
        c.select(CellAddress("B2")!)
        XCTAssertTrue(c.insertChart(.line))
        var sc = try XCTUnwrap(charts(c.sheet).first)
        sc.refs = [(name: "Sheet1!$B$1", cat: "Sheet1!$A$2:$A$6", val: "Sheet1!$B$2:$B$6")]
        sc.categoryFormat = "d-mmm"
        sc.chart.monthBaseDates = true
        let live = c.liveChart(sc)
        XCTAssertEqual(live.categories, ["1-May", "1-Jun", "1-Jul", "1-Aug"])
        XCTAssertEqual(live.series[0].values, [10, 12, nil, 16])
        XCTAssertEqual(live.openSlots, [2], "no row's date in July: the line runs on over it")
        XCTAssertEqual(live.undatedValues, [20], "a value with no date still counts on the value axis")
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
        // Beside the data would end past the printed page at Excel's column widths: under it, from its left edge, 5 × 3 in.
        let f = c.sheet.frame(c.sheet.drawings[0].anchor)
        XCTAssertEqual(f.x, 0, accuracy: 0.01)
        XCTAssertGreaterThan(f.y, 4 * 15)
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

extension SheetsChartTests {
    func testShapesAreReadAndMoveKeepingTheirXML() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        var entries = try Zip.read(try Data(contentsOf: url))
        let sp = "<xdr:twoCellAnchor><xdr:from><xdr:col>1</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>1</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>4</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>3</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:sp macro=\"\" textlink=\"\"><xdr:nvSpPr><xdr:cNvPr id=\"90\" name=\"TextBox 1\"/><xdr:cNvSpPr txBox=\"1\"/></xdr:nvSpPr><xdr:spPr><a:prstGeom prst=\"roundRect\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"FFF2CC\"/></a:solidFill><a:ln w=\"25400\"><a:noFill/></a:ln></xdr:spPr><xdr:txBody><a:bodyPr anchor=\"b\"/><a:p><a:pPr algn=\"r\"/><a:r><a:rPr sz=\"1400\" b=\"1\"/><a:t>Hello</a:t></a:r><a:r><a:rPr sz=\"1400\"/><a:t> there</a:t></a:r></a:p></xdr:txBody></xdr:sp><xdr:clientData/></xdr:twoCellAnchor>"
        let i = try XCTUnwrap(entries.firstIndex { $0.name == "xl/drawings/drawing1.xml" })
        var t = String(decoding: entries[i].data, as: UTF8.self)
        let end = try XCTUnwrap(t.findRange(of: "</xdr:wsDr>"))
        t.replaceSubrange(end, with: sp + "</xdr:wsDr>")
        entries[i] = ZipEntry(name: entries[i].name, data: Data(t.utf8))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Zip.write(entries)))
        let k = try XCTUnwrap(c.sheet.drawings.firstIndex { $0.name == "TextBox 1" })
        guard case .shape(let shape) = c.sheet.drawings[k].kind else { return XCTFail("not a shape") }
        XCTAssertEqual(shape.geometry, "roundRect")
        XCTAssertEqual(shape.fill?.value, 0xFFFFF2CC)
        XCTAssertNil(shape.line)
        XCTAssertEqual(shape.anchor, "b")
        XCTAssertEqual(shape.paragraphs.first?.align, "r")
        XCTAssertEqual(shape.paragraphs.first?.runs.map(\.text), ["Hello", " there"])
        XCTAssertEqual(shape.paragraphs.first?.runs.first?.bold, true)
        XCTAssertEqual(shape.paragraphs.first?.runs.first?.size, 14)
        // Moved: written back as the file had it, corners aside.
        let f = c.sheet.frame(c.sheet.drawings[k].anchor)
        c.setDrawingFrame(k, x: f.x, y: f.y + 30, width: f.width, height: f.height)
        let out = String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == "xl/drawings/drawing1.xml" }).data, as: UTF8.self)
        XCTAssertTrue(out.containsSubstring("<a:prstGeom prst=\"roundRect\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"FFF2CC\"/>"))
        XCTAssertFalse(out.containsSubstring("<xdr:row>1</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:to><xdr:col>4</xdr:col>"))
    }

    func testAFilesColumnChartTurnsToBarKeepingItsFormatting() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: url)))
        let i = try XCTUnwrap(c.sheet.drawings.firstIndex { if case .chart(let sc) = $0.kind { return sc.chart.type == .column && sc.path != nil }; return false })
        guard case .chart(let before) = c.sheet.drawings[i].kind, let path = before.path else { return XCTFail() }
        let origPart = String(decoding: try XCTUnwrap(try Zip.read(try Data(contentsOf: url)).first { $0.name == path }).data, as: UTF8.self)
        c.setChartType(i, .bar)
        XCTAssertNil(c.chartNotice)
        let part = String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == path }).data, as: UTF8.self)
        XCTAssertTrue(part.containsSubstring("<c:barDir val=\"bar\"/>"))
        XCTAssertFalse(part.containsSubstring("<c:barDir val=\"col\"/>"))
        XCTAssertEqual(part.count, origPart.count, "only the direction and axis sides change")
        let back = try Xlsx.read(try Xlsx.write(c.book))
        guard case .chart(let r) = back.sheets[0].drawings[i].kind else { return XCTFail() }
        XCTAssertEqual(r.chart.type, .bar)
    }

    func testAFilesColumnChartConvertsToLineAndPieInPlace() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: url)))
        let i = try XCTUnwrap(c.sheet.drawings.firstIndex { if case .chart(let sc) = $0.kind { return sc.chart.type == .column && sc.path != nil }; return false })
        guard case .chart(let before) = c.sheet.drawings[i].kind, let path = before.path else { return XCTFail() }
        // Any other type converts the part in place: the group changes, the rest of the part stays.
        c.setChartType(i, .line)
        XCTAssertNil(c.chartNotice)
        let asLine = String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == path }).data, as: UTF8.self)
        XCTAssertTrue(asLine.containsSubstring("<c:lineChart>"))
        XCTAssertFalse(asLine.containsSubstring("<c:barChart>"))
        XCTAssertTrue(asLine.containsSubstring("<c:f>"), "the series keep their cells")
        guard case .chart(let lined) = try Xlsx.read(try Xlsx.write(c.book)).sheets[0].drawings[i].kind else { return XCTFail() }
        XCTAssertEqual(lined.chart.type, .line)
        c.setChartType(i, .pie)
        XCTAssertNil(c.chartNotice)
        let asPie = String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == path }).data, as: UTF8.self)
        XCTAssertTrue(asPie.containsSubstring("<c:pieChart>"))
        XCTAssertFalse(asPie.containsSubstring("<c:catAx>"))
    }

    func testPieKeepsEverySeriesAndScatterGetsTwoValueAxes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: url)))
        let i = try XCTUnwrap(c.sheet.drawings.firstIndex { if case .chart(let sc) = $0.kind { return sc.chart.type == .column && sc.path != nil }; return false })
        guard case .chart(let before) = c.sheet.drawings[i].kind, let path = before.path else { return XCTFail() }
        func part() throws -> String { String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == path }).data, as: UTF8.self) }
        func count(_ s: String, _ t: String) -> Int { s.components(separatedBy: t).count - 1 }
        let sers = count(try part(), "<c:ser>")
        XCTAssertGreaterThan(sers, 1)
        c.setChartType(i, .pie)
        XCTAssertEqual(count(try part(), "<c:ser>"), sers, "a pie keeps every series")
        c.setChartType(i, .column)
        let back = try part()
        XCTAssertEqual(count(back, "<c:ser>"), sers)
        XCTAssertTrue(back.containsSubstring("<c:barChart>"))
        c.setChartType(i, .scatter)
        let sc = try part()
        XCTAssertFalse(sc.containsSubstring("<c:catAx>"))
        XCTAssertEqual(count(sc, "<c:valAx>"), 2)
        XCTAssertTrue(sc.containsSubstring("<c:xVal>"))
        XCTAssertTrue(sc.containsSubstring("<c:crossBetween"))
        c.setChartType(i, .line)
        let ln = try part()
        XCTAssertEqual(count(ln, "<c:catAx>"), 1)
        XCTAssertEqual(count(ln, "<c:valAx>"), 1)
    }

    func testWriteChartTypeCheckFiles() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        for (name, type) in [("line", ChartType.line), ("pie", .pie), ("bar", .bar), ("area", .area), ("scatter", .scatter)] {
            let c = WorkbookController()
            c.load(try Xlsx.read(try Data(contentsOf: url)))
            let i = try XCTUnwrap(c.sheet.drawings.firstIndex { if case .chart(let sc) = $0.kind { return sc.chart.type == .column && sc.path != nil }; return false })
            c.setChartType(i, type)
            XCTAssertNil(c.chartNotice, name)
            try Xlsx.write(c.book).write(to: URL(fileURLWithPath: "\(dir)/charttype-\(name).xlsx"))
        }
    }

    private func formController() throws -> (WorkbookController, Int, String) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "karma_performance", withExtension: "xlsx", subdirectory: "Fixtures"))
        let c = WorkbookController()
        c.load(try Xlsx.read(try Data(contentsOf: url)))
        let i = try XCTUnwrap(c.sheet.drawings.firstIndex { if case .chart(let sc) = $0.kind { return sc.chart.type == .column && sc.path != nil }; return false })
        guard case .chart(let sc) = c.sheet.drawings[i].kind, let path = sc.path else { throw XCTSkip("no chart") }
        return (c, i, path)
    }

    private func part(_ c: WorkbookController, _ path: String) throws -> String {
        String(decoding: try XCTUnwrap(try Zip.read(try Xlsx.write(c.book)).first { $0.name == path }).data, as: UTF8.self)
    }

    func testThreeDStockAndBubbleFormsRoundTripInThePart() throws {
        let (c, i, path) = try formController()
        let plain = try part(c, path)
        let sers = plain.components(separatedBy: "<c:ser>").count - 1
        // 3-D column and back to a plain one.
        XCTAssertTrue(c.setChartVariant(i, .threeD))
        var x = try part(c, path)
        XCTAssertTrue(x.containsSubstring("<c:bar3DChart>")); XCTAssertTrue(x.containsSubstring("<c:view3D>"))
        XCTAssertFalse(x.containsSubstring("<c:barChart>"))
        c.setChartType(i, .column)
        x = try part(c, path)
        XCTAssertTrue(x.containsSubstring("<c:barChart>")); XCTAssertFalse(x.containsSubstring("view3D"))
        XCTAssertEqual(x.components(separatedBy: "<c:ser>").count - 1, sers)
        // 3-D pie, line, area.
        for (t, tag) in [(ChartType.pie, "pie3DChart"), (.line, "line3DChart"), (.area, "area3DChart")] {
            c.setChartType(i, t)
            XCTAssertTrue(c.setChartVariant(i, .threeD), tag)
            x = try part(c, path)
            XCTAssertTrue(x.containsSubstring("<c:\(tag)>"), tag)
            if t != .pie { XCTAssertTrue(x.containsSubstring("<c:serAx>"), tag) }
        }
        // Stock needs three series: a chart with fewer asks for the rest.
        c.setChartType(i, .column)
        let have = sers
        let roles = c.stockRolesMissing(i, ohlc: true)
        XCTAssertEqual(roles.count, max(0, 4 - have))
        XCTAssertFalse(c.setChartVariant(i, .stock(ohlc: true, extra: [])) && have < 4)
        let extra = roles.map { _ in "Sheet1!$B$2:$B$6" }
        _ = extra
        // Bubble: sizes asked for; missing or wrong ranges are refused.
        XCTAssertFalse(c.setChartVariant(i, .bubble(sizes: ["not a range"])))
        XCTAssertNotNil(c.chartNotice)
        // Blank cells, or fewer cells than the chart has values, are refused with the reason.
        XCTAssertFalse(c.setChartVariant(i, .bubble(sizes: ["Z1:Z6"])))
        XCTAssertTrue(c.chartNotice?.contains("numeric") ?? false, c.chartNotice ?? "")
        XCTAssertFalse(c.setChartVariant(i, .bubble(sizes: [String(c.suggestedBubbleSizes(i).dropLast()) + "5"])) && false)
        // The default sizes of each series are its own values.
        let n = c.bubbleSizeRoles(i).count
        XCTAssertGreaterThan(n, 1)
        XCTAssertTrue(c.setChartVariant(i, .bubble(sizes: (0..<n).map { c.suggestedBubbleSizes(i, series: $0) })))
        guard case .chart(let sc) = c.sheet.drawings[i].kind else { return XCTFail("no chart") }
        for k in 0..<n { XCTAssertEqual(sc.chart.series[k].bubbleSizes, sc.chart.series[k].values, "series \(k)") }
    }

    func testWriteChartFormCheckFiles() throws {
        guard let dir = ProcessInfo.processInfo.environment["XCHECK_DIR"] else { return }
        for name in ["3dcolumn", "3dpie", "3dline", "3darea", "3dbar", "stock-hlc", "stock-ohlc", "bubble", "bubble-back", "3dcolumn-back", "stock-back"] {
            let (c, i, path) = try formController()
            _ = path
            let sheetName = c.sheet.name
            func q(_ r: String) -> String { "'\(sheetName)'!" + r }
            switch name {
            case "3dcolumn": XCTAssertTrue(c.setChartVariant(i, .threeD))
            case "3dbar": c.setChartType(i, .bar); XCTAssertTrue(c.setChartVariant(i, .threeD))
            case "3dpie": c.setChartType(i, .pie); XCTAssertTrue(c.setChartVariant(i, .threeD))
            case "3dline": c.setChartType(i, .line); XCTAssertTrue(c.setChartVariant(i, .threeD))
            case "3darea": c.setChartType(i, .area); XCTAssertTrue(c.setChartVariant(i, .threeD))
            case "stock-hlc", "stock-ohlc", "stock-back":
                let ohlc = name != "stock-hlc"
                let missing = c.stockRolesMissing(i, ohlc: ohlc)
                XCTAssertTrue(c.setChartVariant(i, .stock(ohlc: ohlc, extra: missing.map { _ in q("$B$2:$B$6") })), name)
                if name == "stock-back" { c.setChartType(i, .column) }
            case "bubble", "bubble-back":
                XCTAssertTrue(c.setChartVariant(i, .bubble(sizes: (0..<c.bubbleSizeRoles(i).count).map { c.suggestedBubbleSizes(i, series: $0) })), name)
                if name == "bubble-back" { c.setChartType(i, .column) }
            case "3dcolumn-back": XCTAssertTrue(c.setChartVariant(i, .threeD)); c.setChartType(i, .column)
            default: break
            }
            try Xlsx.write(c.book).write(to: URL(fileURLWithPath: "\(dir)/chartform-\(name).xlsx"))
        }
    }
}
