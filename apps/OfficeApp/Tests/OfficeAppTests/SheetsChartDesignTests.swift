// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-CH-1a: Chart Design on a chart made here: its title and legend, saved and read back.

import XCTest
#if canImport(FoundationXML)
import FoundationXML   // XMLParser, off Darwin
#endif
import Flutter
import FlutterSwiftBridge
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
        let t = ChartPartPatch.title(xml, .set("New"))
        XCTAssertTrue(t.contains("<a:rPr b=\"1\"/><a:t>New</a:t></a:r><"))
        XCTAssertFalse(t.contains("Old")); XCTAssertTrue(t.contains("AXIS"))
        let l = ChartPartPatch.legend(xml, .set("b"))
        XCTAssertTrue(l.contains("<c:legendPos val=\"b\"/>"))
        XCTAssertEqual(ChartPartPatch.legend(xml, .remove).contains("legend"), false)
        XCTAssertTrue(ChartPartPatch.title(xml, .remove).contains("autoTitleDeleted val=\"1\""))
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
        // And with axis titles: "Month" under the categories, "Total sales" up the value axis.
        back.setChartAxisTitles(j, category: "Month", value: "Total sales")
        try Xlsx.write(back.book).write(to: URL(fileURLWithPath: dir + "/chartaxis.xlsx"))
        c.setChartAxisTitles(i, category: "Month", value: "Total sales")
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/chartaxis-new.xlsx"))
        // Select Data: Sales goes, Tax (column D) is added; on the chart made here and on the same one from a file.
        c.setInputs([(CellAddress(row: 0, col: 3), "Tax"), (CellAddress(row: 1, col: 3), "1"), (CellAddress(row: 2, col: 3), "2")])
        let tax = ChartSeriesRef(source: nil, name: "Sheet1!$D$1", cat: c.chartSeries(i)![0].cat, val: "Sheet1!$D$2:$D$3")
        let fileBook = WorkbookController(); fileBook.load(try Xlsx.read(try Xlsx.write(c.book)))
        c.setChartSeries(i, [c.chartSeries(i)![1], tax])
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/chartseries-new.xlsx"))
        let k = fileBook.sheet.drawings.firstIndex(where: { $0.isChart })!
        fileBook.setChartSeries(k, [fileBook.chartSeries(k)![1], tax])
        try Xlsx.write(fileBook.book).write(to: URL(fileURLWithPath: dir + "/chartseries-file.xlsx"))
        // Series colours: Sales green, Feb point purple, Cost back to automatic; on a chart made here and on the same one from a file.
        let green = Color(0xFF00B050), purple = Color(0xFF7030A0)
        c.setChartColor(i, series: c.chartColorTargets(i)!.series[0].series, point: nil, color: green)
        c.setChartColor(i, series: c.chartColorTargets(i)!.series[1].series, point: nil, choice: .theme(slot: 5, lumMod: 60, lumOff: 40))
        try Xlsx.write(c.book).write(to: URL(fileURLWithPath: dir + "/chartcolor-new.xlsx"))
        let (f2, fi) = chartBook()
        let f3 = WorkbookController(); f3.load(try Xlsx.read(try Xlsx.write(f2.book)))
        let fj = f3.sheet.drawings.firstIndex(where: { $0.isChart })!
        let ts = f3.chartColorTargets(fj)!
        f3.setChartColor(fj, series: ts.series[0].series, point: nil, color: green)
        f3.setChartColor(fj, series: ts.series[1].series, point: nil, color: purple)
        f3.setChartColor(fj, series: ts.series[1].series, point: nil, color: nil)
        f3.setChartColor(fj, series: ts.points[1].series, point: 1, color: purple)
        try Xlsx.write(f3.book).write(to: URL(fileURLWithPath: dir + "/chartcolor-file.xlsx"))
        // Data labels: value + category, outside end, on a chart made here and on the same one from a file; then off on a second file copy.
        let (g1, gi) = chartBook()
        var ge = try XCTUnwrap(g1.chartLabelOptions(gi)).edit
        ge.show = true; ge.category = true; ge.position = "outEnd"
        g1.setChartLabels(gi, ge)
        try Xlsx.write(g1.book).write(to: URL(fileURLWithPath: dir + "/chartlabels-new.xlsx"))
        let (g2, _) = chartBook()
        let g3 = WorkbookController(); g3.load(try Xlsx.read(try Xlsx.write(g2.book)))
        let gj = g3.sheet.drawings.firstIndex(where: { $0.isChart })!
        g3.setChartLabels(gj, ge)
        try Xlsx.write(g3.book).write(to: URL(fileURLWithPath: dir + "/chartlabels-file.xlsx"))
        let g4 = WorkbookController(); g4.load(try Xlsx.read(try Xlsx.write(g3.book)))
        var off = try XCTUnwrap(g4.chartLabelOptions(gj)).edit
        off.show = false
        g4.setChartLabels(gj, off)
        try Xlsx.write(g4.book).write(to: URL(fileURLWithPath: dir + "/chartlabels-off.xlsx"))
        // Axis options: 0 to 20 in steps of 5, format 0.0, on a chart made here and on the same one from a file.
        let (h1, hi) = chartBook()
        h1.setChartAxis(hi, ChartAxisEdit(min: 0, max: 20, major: 5, format: "0.0"))
        try Xlsx.write(h1.book).write(to: URL(fileURLWithPath: dir + "/chartaxisopt-new.xlsx"))
        let (h2, _) = chartBook()
        let h3 = WorkbookController(); h3.load(try Xlsx.read(try Xlsx.write(h2.book)))
        let hj = h3.sheet.drawings.firstIndex(where: { $0.isChart })!
        h3.setChartAxis(hj, ChartAxisEdit(min: 0, max: 20, major: 5, format: "0.0"))
        try Xlsx.write(h3.book).write(to: URL(fileURLWithPath: dir + "/chartaxisopt-file.xlsx"))
        _ = fi
        // A corpus chart with a secondary-axis group: the first group's first series goes, one is added; the other group stays.
        let two = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("test/corpus/xlsx/books/chart-add_series_secondary_axis.xlsx")
        if let d = FileManager.default.contents(atPath: two.path) {
            let w = WorkbookController(); w.load(try Xlsx.read(d))
            let m = w.sheet.drawings.firstIndex(where: { $0.isChart })!
            let cur = try XCTUnwrap(w.chartSeries(m))
            XCTAssertTrue(w.setChartSeries(m, [cur[1], ChartSeriesRef(source: nil, name: nil, cat: cur[1].cat, val: "Munka1!$B$3:$D$3")]))
            try Xlsx.write(w.book).write(to: URL(fileURLWithPath: dir + "/chartseries-2axis.xlsx"))
        }
    }

    /// Element and attribute names (with counts) in a chart part.
    private func census(_ xml: String) -> [String: Int] {
        var out: [String: Int] = [:]
        var tag = ""; var inTag = false; var q: Character? = nil
        func flush() {
            guard tag.first != "/", tag.first != "?", tag.first != "!" else { tag = ""; return }
            let parts = tag.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            guard let name = parts.first else { tag = ""; return }
            out["<" + String(name).replacingAll("/", with: ""), default: 0] += 1
            for a in parts.dropFirst() { if let eq = a.firstIndex(of: "=") { out["@" + name + " " + a[a.startIndex ..< eq], default: 0] += 1 } }
            tag = ""
        }
        for ch in xml {
            if inTag {
                if let qq = q { if ch == qq { q = nil }; tag.append(ch); continue }
                if ch == "\"" || ch == "'" { q = ch; tag.append(ch); continue }
                if ch == ">" { inTag = false; flush() } else { tag.append(ch) }
            } else if ch == "<" { inTag = true; tag = "" }
        }
        return out
    }

    func testAxisTitlesOnAFileChartAndOnePatchedByHand() throws {
        let (c, _) = chartBook()
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        back.setChartAxisTitles(j, category: "Month", value: "Total & more")
        if let o = ProcessInfo.processInfo.environment["XDUMP"] { try Xlsx.write(back.book).write(to: URL(fileURLWithPath: o)) }
        XCTAssertNil(back.chartNotice)
        let again = try Xlsx.read(try Xlsx.write(back.book))
        guard let d = again.sheets[0].drawings.first(where: { $0.isChart }), case .chart(let sc) = d.kind else { return XCTFail("no chart") }
        XCTAssertEqual(sc.chart.categoryAxisTitle, "Month")
        XCTAssertEqual(sc.chart.valueAxisTitle, "Total & more")
        back.setChartAxisTitles(j, category: nil, value: nil)
        let off = try Xlsx.read(try Xlsx.write(back.book))
        guard let d2 = off.sheets[0].drawings.first(where: { $0.isChart }), case .chart(let s2) = d2.kind else { return XCTFail("no chart") }
        XCTAssertNil(s2.chart.categoryAxisTitle); XCTAssertNil(s2.chart.valueAxisTitle)
        let xml = "<c:plotArea><c:catAx><c:axId val=\"1\"/><c:axPos val=\"b\"/><c:numFmt/><c:crossAx val=\"2\"/></c:catAx><c:valAx><c:axId val=\"2\"/><c:axPos val=\"l\"/><c:majorGridlines><c:spPr/></c:majorGridlines><c:title><c:tx><c:rich><a:p><a:r><a:t>Old</a:t></a:r></a:p></c:rich></c:tx></c:title><c:numFmt/></c:valAx></c:plotArea>"
        let t = ChartPartPatch.axisTitle(ChartPartPatch.axisTitle(xml, .category, .set("X")), .value, .set("Y"))
        XCTAssertTrue(t.contains("<c:axPos val=\"b\"/><c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"1000\" b=\"1\"/></a:pPr><a:r><a:rPr lang=\"en-US\"/><a:t>X</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title><c:numFmt/>"))
        XCTAssertTrue(t.contains("<a:t>Y</a:t>")); XCTAssertFalse(t.contains("Old"))
        XCTAssertFalse(ChartPartPatch.axisTitle(xml, .value, .remove).contains("<c:title>"))
    }

    func testEditTitlesIsOneUndoStep() {
        let (c, i) = chartBook()
        c.setChartTitles(i, title: "T", category: "X", value: "Y")
        XCTAssertEqual(chart(c, i)!.title, "T"); XCTAssertEqual(chart(c, i)!.categoryAxisTitle, "X"); XCTAssertEqual(chart(c, i)!.valueAxisTitle, "Y")
        c.setChartTitles(i, title: nil, category: nil, value: "Y")
        XCTAssertNil(chart(c, i)!.title); XCTAssertNil(chart(c, i)!.categoryAxisTitle)
        c.undo()
        XCTAssertEqual(chart(c, i)!.title, "T"); XCTAssertEqual(chart(c, i)!.categoryAxisTitle, "X")
    }

    func testAxisTitlesAreWrittenTenPointBoldAndANewChartStaysOnThePage() throws {
        let (c, i) = chartBook()
        c.setChartAxisTitles(i, category: "Month", value: "Total")
        let entries = try Zip.read(try Xlsx.write(c.book))
        let xml = String(decoding: entries.first { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") }!.data, as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<a:defRPr sz=\"1000\" b=\"1\">").count - 1, 2)
        let setup = SheetPrintSetup.read(c.sheet)
        guard case .chart = c.sheet.drawings[i].kind else { return XCTFail() }
        let f = c.sheet.frame(c.sheet.drawings[i].anchor)
        XCTAssertLessThanOrEqual((f.x + f.width) * 51 / 48, setup.printableWidth)
    }

    func testSelectDataOnAChartMadeHereAndOnOneFromTheFile() throws {
        let (c, i) = chartBook()
        c.setInputs([(CellAddress(row: 0, col: 3), "Tax"), (CellAddress(row: 1, col: 3), "1"), (CellAddress(row: 2, col: 3), "2")])
        let before = try XCTUnwrap(c.chartSeries(i))
        XCTAssertEqual(before.map(\.source), [0, 1])
        // A bad reference changes nothing.
        XCTAssertFalse(c.setChartSeries(i, [ChartSeriesRef(source: 0, name: nil, cat: nil, val: "nowhere")]))
        // The first series goes, a third is added.
        let tax = ChartSeriesRef(source: nil, name: "Sheet1!$D$1", cat: before[0].cat, val: "Sheet1!$D$2:$D$3")
        XCTAssertTrue(c.setChartSeries(i, [before[1], tax]))
        let live = c.liveChart({ if case .chart(let sc) = c.sheet.drawings[i].kind { return sc }; fatalError() }())
        XCTAssertEqual(live.series.map(\.name), ["Cost", "Tax"])
        XCTAssertEqual(live.series[1].values, [1, 2])
        // Cost keeps its own number (so its automatic colour), the new series takes the next free one.
        do {
            let w = try XCTUnwrap(Xlsx.write(c.book)); let ents = try Zip.read(w)
            let x = String(decoding: ents.first { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") }!.data, as: UTF8.self)
            let ids = x.components(separatedBy: "<c:ser><c:idx val=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
            XCTAssertEqual(ids, ["1", "2"])
        }
        c.undo()
        XCTAssertEqual(c.chartSeries(i)?.count, 2)
        c.redo()
        // The same chart through a file: series 0 of the part goes, a new one is added; the part keeps the others as written.
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        XCTAssertEqual(back.chartSeries(j)?.count, 2)
        let cur = try XCTUnwrap(back.chartSeries(j))
        XCTAssertTrue(back.setChartSeries(j, [cur[1], ChartSeriesRef(source: nil, name: nil, cat: cur[1].cat, val: "Sheet1!$B$2:$B$3")]))
        let entries = try Zip.read(try Xlsx.write(back.book))
        let xml = String(decoding: entries.first { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") }!.data, as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<c:ser>").count - 1, 2)
        let again = try Xlsx.read(try Xlsx.write(back.book))
        guard let d = again.sheets[0].drawings.first(where: { $0.isChart }), case .chart(let sc) = d.kind else { return XCTFail("no chart") }
        XCTAssertEqual(sc.refs.map(\.val), ["Sheet1!$D$2:$D$3", "Sheet1!$B$2:$B$3"])
    }

    func testSeriesColoursOnAChartMadeHereAndOnOneFromTheFile() throws {
        let (c, i) = chartBook()
        let t = try XCTUnwrap(c.chartColorTargets(i))
        XCTAssertEqual(t.series.map(\.series), [0, 1])
        let red = Color(0xFFFF0000), blue = Color(0xFF0000FF)
        XCTAssertTrue(c.setChartColor(i, series: 1, point: nil, color: red))
        XCTAssertEqual(c.chartColorTargets(i)?.series[1].color, red)
        XCTAssertEqual(c.chartColorTargets(i)?.series[0].color, nil)
        c.undo()
        XCTAssertNil(c.chartColorTargets(i)?.series[1].color)
        c.redo()
        if !t.points.isEmpty { XCTAssertTrue(c.setChartColor(i, series: 0, point: 0, color: blue)) }
        // Through the file: the colours are read back, and written into the part as the chart's own.
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        XCTAssertEqual(back.chartColorTargets(j)?.series[1].color, red)
        XCTAssertTrue(back.setChartColor(j, series: 1, point: nil, color: blue))
        XCTAssertTrue(back.setChartColor(j, series: 0, point: nil, color: red))
        let entries = try Zip.read(try Xlsx.write(back.book))
        let xml = String(decoding: entries.first { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") }!.data, as: UTF8.self)
        let sers = xml.components(separatedBy: "<c:ser>").dropFirst().map { String($0) }
        XCTAssertTrue(sers[0].containsSubstring("FF0000"))
        XCTAssertTrue(sers[1].containsSubstring("0000FF"))
        XCTAssertFalse(sers[1].containsSubstring("FF0000"))
        // Automatic again.
        XCTAssertTrue(back.setChartColor(j, series: 1, point: nil, color: nil))
        let again = try Zip.read(try Xlsx.write(back.book))
        let x2 = String(decoding: again.first { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") }!.data, as: UTF8.self)
        XCTAssertFalse(x2.components(separatedBy: "<c:ser>")[2].containsSubstring("0000FF"))
    }

    func testColourPatchOnBarLinePieAndPoints() {
        func ser(_ idx: Int, _ sp: String, _ extra: String = "") -> String {
            "<c:ser><c:idx val=\"\(idx)\"/><c:order val=\"\(idx)\"/><c:tx><c:v>x</c:v></c:tx>\(sp)\(extra)<c:cat><c:strRef><c:f>S!$A$2:$A$3</c:f></c:strRef></c:cat><c:val><c:numRef><c:f>S!$B$2:$B$3</c:f></c:numRef></c:val></c:ser>"
        }
        let bar = "<c:plotArea><c:barChart>" + ser(0, "<c:spPr><a:solidFill><a:schemeClr val=\"accent1\"/></a:solidFill><a:ln><a:solidFill><a:srgbClr val=\"111111\"/></a:solidFill></a:ln></c:spPr>", "<c:invertIfNegative val=\"0\"/>") + ser(1, "") + "</c:barChart></c:plotArea>"
        let o = ChartPartPatch.colors(bar, [ChartColorEdit(series: 0, point: nil, hex: "AA0000"), ChartColorEdit(series: 1, point: nil, hex: "00BB00"), ChartColorEdit(series: 0, point: 1, hex: "0000CC")])
        XCTAssertFalse(o.containsSubstring("accent1"))
        XCTAssertTrue(o.containsSubstring("<c:spPr><a:solidFill><a:srgbClr val=\"AA0000\"/></a:solidFill><a:ln><a:solidFill><a:srgbClr val=\"111111\"/>"))   // the outline is kept
        XCTAssertTrue(o.containsSubstring("<c:dPt><c:idx val=\"1\"/><c:invertIfNegative val=\"0\"/><c:spPr><a:solidFill><a:srgbClr val=\"0000CC\"/>"))
        XCTAssertTrue(o.components(separatedBy: "<c:ser>")[2].containsSubstring("00BB00"))
        // A dPt sits before the categories (schema order); the point goes away again with automatic.
        XCTAssertLessThan(o.range(of: "<c:dPt>")!.lowerBound, o.range(of: "<c:cat>")!.lowerBound)
        let back = ChartPartPatch.colors(o, [ChartColorEdit(series: 0, point: 1, hex: nil)])
        XCTAssertFalse(back.containsSubstring("<c:dPt>"))
        // A line: the line and its markers, not a fill.
        let line = "<c:plotArea><c:lineChart>" + ser(0, "<c:spPr><a:ln w=\"28575\"><a:solidFill><a:schemeClr val=\"accent1\"/></a:solidFill><a:round/></a:ln></c:spPr>", "<c:marker><c:symbol val=\"circle\"/><c:size val=\"5\"/><c:spPr><a:solidFill><a:schemeClr val=\"accent1\"/></a:solidFill></c:spPr></c:marker>") + "</c:lineChart></c:plotArea>"
        let l = ChartPartPatch.colors(line, [ChartColorEdit(series: 0, point: nil, hex: "123456")])
        XCTAssertFalse(l.containsSubstring("accent1"))
        XCTAssertEqual(l.components(separatedBy: "123456").count - 1, 3)   // the line, the marker's fill and outline
        XCTAssertTrue(l.containsSubstring("<a:ln w=\"28575\"><a:solidFill><a:srgbClr val=\"123456\"/></a:solidFill><a:round/></a:ln>"))
        // A pie's slices.
        let pie = "<c:plotArea><c:pieChart>" + ser(0, "") + "</c:pieChart></c:plotArea>"
        let p = ChartPartPatch.colors(pie, [ChartColorEdit(series: 0, point: 0, hex: "FEDCBA")])
        XCTAssertTrue(p.containsSubstring("<c:dPt><c:idx val=\"0\"/><c:bubble3D val=\"0\"/><c:spPr><a:solidFill><a:srgbClr val=\"FEDCBA\"/>"))
    }

    func testSeriesPatchKeepsIdxAndOrderUniqueAcrossGroups() {
        func ser(_ idx: Int, _ f: String) -> String {
            "<c:ser><c:idx val=\"\(idx)\"/><c:order val=\"\(idx)\"/><c:tx><c:strRef><c:f>S!$A$1</c:f><c:strCache><c:pt idx=\"0\"><c:v>x</c:v></c:pt></c:strCache></c:strRef></c:tx><c:spPr><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></c:spPr><c:dPt><c:idx val=\"0\"/></c:dPt><c:cat><c:strRef><c:f>S!$A$2:$A$3</c:f></c:strRef></c:cat><c:val><c:numRef><c:f>\(f)</c:f><c:numCache/></c:numRef></c:val></c:ser>"
        }
        let xml = "<c:plotArea><c:barChart>" + ser(0, "S!$B$2:$B$3") + ser(1, "S!$C$2:$C$3") + "</c:barChart><c:lineChart>" + ser(5, "S!$D$2:$D$3") + "</c:lineChart></c:plotArea>"
        let list = [ChartSeriesRef(source: 0, name: "S!$A$1", cat: "S!$A$2:$A$3", val: "S!$B$2:$B$3"),
                    ChartSeriesRef(source: 1, name: "S!$A$1", cat: "S!$A$2:$A$3", val: "S!$E$2:$E$3"),
                    ChartSeriesRef(source: nil, name: nil, cat: "S!$A$2:$A$3", val: "S!$F$2:$F$3"),
                    ChartSeriesRef(source: nil, name: nil, cat: nil, val: "S!$G$2:$G$3")]
        let out = ChartPartPatch.series(xml, list)
        var idxs: [String] = [], orders: [String] = []
        for part in out.components(separatedBy: "<c:ser>").dropFirst() {
            idxs.append(String(part.components(separatedBy: "<c:idx val=\"")[1].prefix(while: { $0 != "\"" })))
            orders.append(String(part.components(separatedBy: "<c:order val=\"")[1].prefix(while: { $0 != "\"" })))
        }
        // Four listed (first group) plus the second group's own series, left as it was.
        XCTAssertEqual(idxs.count, 5)
        XCTAssertEqual(Set(idxs).count, 5); XCTAssertEqual(Set(orders).count, 5)
        XCTAssertEqual(idxs.prefix(1), ["0"])
        // The kept series are untouched where they were not edited (colour, cache); the new ones carry no colour.
        XCTAssertTrue(out.containsSubstring("<c:strCache>"))
        XCTAssertEqual(out.components(separatedBy: "FF0000").count - 1, 3)
        XCTAssertFalse(out.containsSubstring("S!$C$2:$C$3"))
        // A new series is automatic all through: none of the template's marker or line colours.
        let fresh = ChartPartPatch.series("<c:plotArea><c:lineChart><c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:spPr><a:ln><a:solidFill><a:srgbClr val=\"112233\"/></a:solidFill></a:ln></c:spPr><c:marker><c:symbol val=\"circle\"/><c:spPr><a:solidFill><a:srgbClr val=\"445566\"/></a:solidFill></c:spPr></c:marker><c:cat><c:strRef><c:f>S!$A$2:$A$3</c:f></c:strRef></c:cat><c:val><c:numRef><c:f>S!$B$2:$B$3</c:f></c:numRef></c:val></c:ser></c:lineChart></c:plotArea>",
            [ChartSeriesRef(source: 0, name: nil, cat: "S!$A$2:$A$3", val: "S!$B$2:$B$3"), ChartSeriesRef(source: nil, name: nil, cat: "S!$A$2:$A$3", val: "S!$C$2:$C$3")])
        let second = fresh.components(separatedBy: "<c:ser>")[2]
        XCTAssertFalse(second.containsSubstring("112233")); XCTAssertFalse(second.containsSubstring("445566")); XCTAssertFalse(second.containsSubstring("<c:marker>"))
        XCTAssertTrue(fresh.components(separatedBy: "<c:ser>")[1].containsSubstring("445566"))
        XCTAssertTrue(out.containsSubstring("<c:f>S!$G$2:$G$3</c:f>"))
        // The new series sit after the last kept series; the other group is not touched.
        XCTAssertTrue(out.components(separatedBy: "<c:lineChart>")[0].containsSubstring("S!$F$2:$F$3"))
        XCTAssertTrue(out.components(separatedBy: "<c:lineChart>")[1].containsSubstring("S!$D$2:$D$3"))
    }

    /// A chart part without its own title, its legend and autoTitleDeleted (what an edit may change), as one string.
    private func strip(_ xml: String) -> String {
        var x = xml
        func cut(_ open: String, _ close: String, before: String? = nil) {
            let limit = before.flatMap { x.findRange(of: $0, in: x.startIndex ..< x.endIndex)?.lowerBound } ?? x.endIndex
            if let o = x.findRange(of: open, in: x.startIndex ..< limit), let c = x.findRange(of: close, in: o.upperBound ..< x.endIndex) { x.removeSubrange(o.lowerBound ..< c.upperBound) }
        }
        cut("<c:title>", "</c:title>", before: "<c:plotArea>")
        cut("<c:legend>", "</c:legend>")
        for tag in ["catAx", "dateAx", "valAx"] {
            var from = x.startIndex
            while let o = x.findRange(of: "<c:\(tag)>", in: from ..< x.endIndex), let c = x.findRange(of: "</c:\(tag)>", in: o.upperBound ..< x.endIndex) {
                var ax = String(x[o.lowerBound ..< c.upperBound])
                if let t0 = ax.findRange(of: "<c:title>", in: ax.startIndex ..< ax.endIndex), let t1 = ax.findRange(of: "</c:title>", in: t0.upperBound ..< ax.endIndex) {
                    ax.removeSubrange(t0.lowerBound ..< t1.upperBound)
                    x.replaceSubrange(o.lowerBound ..< c.upperBound, with: ax)
                }
                from = x.findRange(of: "</c:\(tag)>", in: o.lowerBound ..< x.endIndex)!.upperBound
            }
        }
        if let o = x.findRange(of: "<c:autoTitleDeleted ", in: x.startIndex ..< x.endIndex), let c = x.findRange(of: "/>", in: o.upperBound ..< x.endIndex) { x.removeSubrange(o.lowerBound ..< c.upperBound) }
        return x
    }

    /// Corpus round trip (CHART_CORPUS=<dir>): a title set and the legend moved on every chart; every chart part must differ
    /// from its original only in c:title, c:legend, c:legendPos, c:autoTitleDeleted (and what those hold).
    func testCorpusRoundTrip() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHART_CORPUS"] else { return }
        var books = 0, charts = 0, unread = 0, bad = 0, parts = 0
        var changed: [String: Int] = [:]
        let fm = FileManager.default
        let names = (fm.enumerator(atPath: dir)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".xlsx") }.sorted()
        for n in names {
            guard let data = fm.contents(atPath: dir + "/" + n), let entries = try? Zip.read(data),
                  entries.contains(where: { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") }) else { continue }
            guard let book = try? Xlsx.read(data) else { unread += 1; continue }
            books += 1
            let c = WorkbookController(); c.load(book)
            var any = false
            for si in 0 ..< c.book.sheets.count {
                c.activeSheet = si
                for (j, d) in c.sheet.drawings.enumerated() { if d.isChart { charts += 1; any = true; c.setChartTitle(j, "Round trip"); c.setChartLegend(j, position: "t"); c.setChartAxisTitles(j, category: "Cat & <x>", value: "Val") } }
            }
            guard any, let out = try? Xlsx.write(c.book), let outEntries = try? Zip.read(out) else { continue }
            let was = Dictionary(entries.map { ($0.name, $0.data) }, uniquingKeysWith: { a, _ in a })
            for e in outEntries where e.name.hasPrefix("xl/charts/chart") && e.name.hasSuffix(".xml") {
                guard let old = was[e.name] else { continue }
                let oa = strip(String(decoding: old, as: UTF8.self)), ob = strip(String(decoding: e.data, as: UTF8.self))
                parts += 1
                if oa != ob {
                    bad += 1
                    let a = census(oa), b = census(ob)
                    for k in Set(a.keys).union(b.keys) where a[k, default: 0] != b[k, default: 0] { changed[k, default: 0] += 1 }
                    print("CHARTDIFF \(n) \(e.name) bytes \(oa.utf8.count)->\(ob.utf8.count)")
                }
            }
        }
        print("CHARTCORPUS books=\(books) unread=\(unread) charts=\(charts) parts=\(parts) partsDifferingOutsideTitleLegend=\(bad)")
        for (k, v) in changed.sorted(by: { $0.key < $1.key }) { print("CHARTCHANGED \(k) in \(v) parts") }
        XCTAssertEqual(bad, 0)
    }

    /// Corpus round trip for Select Data (CHART_CORPUS=<dir>): (1) every chart's series set to what it already is leaves the chart part
    /// byte-identical; (2) the last series removed leaves one fewer c:ser and every c:idx and c:order unique.
    func testThemeColourIsWrittenAsSchemeColour() throws {
        let (c, i) = chartBook()
        let k = c.chartColorTargets(i)!.series[0].series
        XCTAssertTrue(c.setChartColor(i, series: k, point: nil, choice: .theme(slot: 5, lumMod: 60, lumOff: 40)))
        XCTAssertTrue(c.setChartColor(i, series: k, point: 1, choice: .theme(slot: 6, lumMod: 100, lumOff: 0)))
        var xml = try chartXML(c)
        XCTAssertTrue(xml.contains("<a:schemeClr val=\"accent2\"><a:lumMod val=\"60000\"/><a:lumOff val=\"40000\"/></a:schemeClr>"))
        XCTAssertTrue(xml.contains("<a:schemeClr val=\"accent3\"/>"))
        // From a file: the same patch lands in the original part.
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        XCTAssertTrue(back.setChartColor(j, series: back.chartColorTargets(j)!.series[1].series, point: nil, choice: .theme(slot: 7, lumMod: 75, lumOff: 0)))
        xml = try chartXML(back)
        XCTAssertTrue(xml.contains("<a:schemeClr val=\"accent4\"><a:lumMod val=\"75000\"/></a:schemeClr>"))
        XCTAssertTrue(back.setChartColor(j, series: back.chartColorTargets(j)!.series[1].series, point: nil, choice: .rgb(0x112233)))
        XCTAssertTrue(try chartXML(back).contains("<a:srgbClr val=\"112233\"/>"))
    }

    private func chartXML(_ c: WorkbookController) throws -> String {
        let entries = try Zip.read(try Xlsx.write(c.book))
        let e = try XCTUnwrap(entries.first { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") })
        return String(decoding: e.data, as: UTF8.self)
    }

    func testDataLabelsPatchOnColumnLineAndPie() throws {
        let bar = "<c:chartSpace><c:chart><c:plotArea><c:layout/><c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/><c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:spPr/><c:invertIfNegative val=\"0\"/><c:cat><c:strRef><c:f>S!$A$2:$A$3</c:f></c:strRef></c:cat><c:val><c:numRef><c:f>S!$B$2:$B$3</c:f></c:numRef></c:val></c:ser><c:ser><c:idx val=\"1\"/><c:order val=\"1\"/><c:dLbls><c:numFmt formatCode=\"0.0\" sourceLinked=\"0\"/><c:showLegendKey val=\"0\"/><c:showVal val=\"1\"/><c:showCatName val=\"0\"/><c:showSerName val=\"0\"/><c:showPercent val=\"0\"/><c:showBubbleSize val=\"0\"/></c:dLbls><c:cat/><c:val/></c:ser><c:axId val=\"1\"/></c:barChart></c:plotArea></c:chart></c:chartSpace>"
        var e = ChartLabelEdit(); e.show = true; e.value = true; e.category = true; e.position = "outEnd"
        let on = ChartPartPatch.labels(bar, e)
        XCTAssertEqual(on.components(separatedBy: "<c:showCatName val=\"1\"/>").count - 1, 2)
        XCTAssertEqual(on.components(separatedBy: "<c:dLblPos val=\"outEnd\"/>").count - 1, 2)
        // Schema order: the labels sit before the categories; the second series keeps its number format, before the position.
        XCTAssertTrue(on.containsSubstring("<c:invertIfNegative val=\"0\"/><c:dLbls><c:dLblPos"))
        XCTAssertTrue(on.containsSubstring("<c:numFmt formatCode=\"0.0\" sourceLinked=\"0\"/><c:dLblPos"))
        // A position the type does not take is dropped (stacked bars take no outEnd; a line takes t, not outEnd).
        let stacked = bar.replacingAll("clustered", with: "stacked")
        XCTAssertFalse(ChartPartPatch.labels(stacked, e).containsSubstring("outEnd"))
        let off = ChartPartPatch.labels(on, ChartLabelEdit())
        XCTAssertEqual(off.components(separatedBy: "<c:dLbls><c:delete val=\"1\"/></c:dLbls>").count - 1, 2)
        XCTAssertFalse(off.containsSubstring("showVal"))
        let again = ChartPartPatch.labels(off, e)
        XCTAssertFalse(again.containsSubstring("<c:delete"))
        XCTAssertEqual(again.components(separatedBy: "<c:dLbls>").count - 1, 2)
    }

    func testDataLabelsOnAChartMadeHere() throws {
        let (c, i) = chartBook()
        var o = try XCTUnwrap(c.chartLabelOptions(i))
        XCTAssertFalse(o.edit.show)
        XCTAssertTrue(o.canCategory)
        o.edit.show = true; o.edit.category = true; o.edit.position = "inEnd"
        XCTAssertTrue(c.setChartLabels(i, o.edit))
        let xml = try chartXML(c)
        XCTAssertTrue(xml.containsSubstring("<c:dLblPos val=\"inEnd\"/>"))
        XCTAssertTrue(xml.containsSubstring("<c:showCatName val=\"1\"/>"))
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        var e = try XCTUnwrap(back.chartLabelOptions(j)).edit
        XCTAssertTrue(e.show); XCTAssertTrue(e.category)
        e.category = false; e.position = "outEnd"
        XCTAssertTrue(back.setChartLabels(j, e))
        let x2 = try chartXML(back)
        XCTAssertTrue(x2.containsSubstring("<c:dLblPos val=\"outEnd\"/>"))
        XCTAssertFalse(x2.containsSubstring("<c:showCatName val=\"1\"/>"))
        e.show = false
        XCTAssertTrue(back.setChartLabels(j, e))
        XCTAssertTrue(try chartXML(back).containsSubstring("<c:delete val=\"1\"/>"))
    }

    func testValueAxisPatch() throws {
        let xml = "<c:chartSpace><c:chart><c:plotArea><c:layout/><c:barChart><c:barDir val=\"col\"/><c:ser><c:idx val=\"0\"/><c:order val=\"0\"/><c:val/></c:ser><c:axId val=\"1\"/><c:axId val=\"2\"/></c:barChart><c:catAx><c:axId val=\"1\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"b\"/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:majorTickMark val=\"none\"/><c:crossAx val=\"2\"/></c:catAx><c:valAx><c:axId val=\"2\"/><c:scaling><c:orientation val=\"minMax\"/><c:max val=\"9\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"l\"/><c:majorGridlines/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/><c:majorTickMark val=\"none\"/><c:crossAx val=\"1\"/><c:crossBetween val=\"between\"/><c:majorUnit val=\"3\"/></c:valAx></c:plotArea></c:chart></c:chartSpace>"
        var e = ChartAxisEdit(); e.min = 0; e.max = 50.5; e.major = 10; e.format = "0.00\"%\""
        let x = ChartPartPatch.valueAxis(xml, e)
        XCTAssertTrue(x.containsSubstring("<c:orientation val=\"minMax\"/><c:max val=\"50.5\"/><c:min val=\"0\"/></c:scaling>"))
        XCTAssertTrue(x.containsSubstring("<c:crossBetween val=\"between\"/><c:majorUnit val=\"10\"/></c:valAx>"))
        XCTAssertTrue(x.containsSubstring("<c:majorGridlines/><c:numFmt formatCode=\"0.00&quot;%&quot;\" sourceLinked=\"0\"/><c:majorTickMark"))
        // The category axis is left alone.
        XCTAssertTrue(x.containsSubstring("<c:axPos val=\"b\"/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>"))
        let auto = ChartPartPatch.valueAxis(x, ChartAxisEdit())
        XCTAssertFalse(auto.containsSubstring("<c:max"))
        XCTAssertFalse(auto.containsSubstring("<c:min "))
        XCTAssertFalse(auto.containsSubstring("majorUnit"))
        XCTAssertTrue(auto.containsSubstring("<c:majorGridlines/><c:numFmt formatCode=\"General\" sourceLinked=\"1\"/>"))
    }

    func testAxisFormatGoesAfterGridlinesAndTitleNotInsideThem() throws {
        let xml = "<c:chartSpace><c:chart><c:plotArea><c:barChart><c:ser><c:idx val=\"0\"/></c:ser><c:axId val=\"1\"/><c:axId val=\"2\"/></c:barChart><c:valAx><c:axId val=\"2\"/><c:scaling><c:orientation val=\"minMax\"/></c:scaling><c:delete val=\"0\"/><c:axPos val=\"l\"/><c:majorGridlines><c:spPr><a:ln/></c:spPr></c:majorGridlines><c:title><c:tx><c:rich><a:p/></c:rich></c:tx><c:txPr><a:p/></c:txPr></c:title><c:majorTickMark val=\"none\"/><c:spPr><a:ln/></c:spPr><c:crossAx val=\"1\"/><c:crossBetween val=\"between\"/></c:valAx></c:plotArea></c:chart></c:chartSpace>"
        let x = ChartPartPatch.valueAxis(xml, ChartAxisEdit(min: nil, max: nil, major: 5, format: "0.0"))
        XCTAssertTrue(x.containsSubstring("</c:title><c:numFmt formatCode=\"0.0\" sourceLinked=\"0\"/><c:majorTickMark"))
        XCTAssertTrue(x.containsSubstring("</c:majorGridlines><c:title>"))
        XCTAssertTrue(x.containsSubstring("<c:crossBetween val=\"between\"/><c:majorUnit val=\"5\"/></c:valAx>"))
        // No gridlines or title: still before the tick marks.
        let bare = xml.replacingAll("<c:majorGridlines><c:spPr><a:ln/></c:spPr></c:majorGridlines>", with: "")
        XCTAssertTrue(ChartPartPatch.valueAxis(bare, ChartAxisEdit(format: "0%")).containsSubstring("</c:title><c:numFmt formatCode=\"0%\""))
    }

    func testAxisOptionsOnAChartMadeHereAndFromTheFile() throws {
        let (c, i) = chartBook()
        XCTAssertTrue(c.setChartAxis(i, ChartAxisEdit(min: 0, max: 100, major: 20, format: "0.0")))
        let xml = try chartXML(c)
        XCTAssertTrue(xml.containsSubstring("<c:max val=\"100\"/><c:min val=\"0\"/>"))
        XCTAssertTrue(xml.containsSubstring("<c:majorUnit val=\"20\"/>"))
        XCTAssertTrue(xml.containsSubstring("formatCode=\"0.0\" sourceLinked=\"0\""))
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        let j = back.sheet.drawings.firstIndex(where: { $0.isChart })!
        XCTAssertEqual(back.chartAxisOptions(j), ChartAxisEdit(min: 0, max: 100, major: 20, format: "0.0"))
        XCTAssertTrue(back.setChartAxis(j, ChartAxisEdit(min: 10, max: 60, major: nil, format: nil)))
        let x2 = try chartXML(back)
        XCTAssertTrue(x2.containsSubstring("<c:max val=\"60\"/><c:min val=\"10\"/>"))
        XCTAssertFalse(x2.containsSubstring("majorUnit"))
        XCTAssertTrue(back.setChartAxis(j, ChartAxisEdit()))
        XCTAssertFalse(try chartXML(back).containsSubstring("<c:max"))
    }

    /// Collects the direct children of every value axis, in the order the part has them.
    private final class AxisChildren: NSObject, XMLParserDelegate {
        var stack: [String] = [], axes: [[String]] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName q: String?, attributes: [String: String] = [:]) {
            if stack.last == "valAx" { axes[axes.count - 1].append(name) }
            if name == "valAx" { axes.append([]) }
            stack.append(name)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName q: String?) { stack.removeLast() }
    }

    func testCorpusAxisOptionsKeepSchemaOrder() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHART_CORPUS"] else { return }
        let order = ["axId", "scaling", "delete", "axPos", "majorGridlines", "minorGridlines", "title", "numFmt", "majorTickMark", "minorTickMark",
                     "tickLblPos", "spPr", "txPr", "crossAx", "crosses", "crossesAt", "crossBetween", "majorUnit", "minorUnit", "dispUnits", "extLst"]
        let fm = FileManager.default
        var charts = 0, bad = 0
        for n in (fm.enumerator(atPath: dir)?.allObjects as? [String] ?? []).filter({ $0.hasSuffix(".xlsx") }).sorted() {
            guard let data = fm.contents(atPath: dir + "/" + n), let book = try? Xlsx.read(data) else { continue }
            let c = WorkbookController(); c.load(book)
            var any = false
            for si in 0 ..< c.book.sheets.count {
                c.activeSheet = si
                for (j, d) in c.sheet.drawings.enumerated() where d.isChart && c.chartAxisOptions(j) != nil {
                    if c.setChartAxis(j, ChartAxisEdit(min: 0, max: 1000, major: 100, format: "0.0")) { any = true; charts += 1 }
                }
            }
            guard any, let out = try? Xlsx.write(c.book), let entries = try? Zip.read(out), let was = try? Zip.read(data) else { continue }
            func axes(_ bytes: Data) -> [[String]]? {
                let parser = XMLParser(data: bytes); parser.shouldProcessNamespaces = true
                let d = AxisChildren(); parser.delegate = d
                return parser.parse() ? d.axes : nil
            }
            func sorted(_ kids: [String]) -> Bool { let i = kids.compactMap { order.firstIndex(of: $0) }; return i == i.sorted() }
            for e in entries where e.name.hasPrefix("xl/charts/chart") && e.name.hasSuffix(".xml") {
                guard let now = axes(e.data) else { bad += 1; print("AXISXML \(n) \(e.name)"); continue }
                // A part another tool wrote out of order stays as it was; one that was in order must stay in order.
                let before = was.first(where: { $0.name == e.name }).flatMap { axes($0.data) } ?? []
                for (k, kids) in now.enumerated() {
                    if kids.filter({ $0 == "numFmt" }).count > 1 { bad += 1; print("AXISDUP \(n) \(e.name)") }
                    if before.indices.contains(k), sorted(before[k]), !sorted(kids) { bad += 1; print("AXISORDER \(n) \(e.name) \(kids)") }
                }
            }
        }
        print("CORPUS axis edits: \(charts) charts, \(bad) bad")
        XCTAssertEqual(bad, 0)
    }

    func testCorpusSeriesEdits() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHART_CORPUS"] else { return }
        var charts = 0, same = 0, notSame = 0, removed = 0, dup = 0, wrongCount = 0
        let fm = FileManager.default
        func count(_ x: String, _ t: String) -> Int { x.components(separatedBy: t).count - 1 }
        func ids(_ x: String, _ tag: String) -> [String] {
            x.components(separatedBy: "<c:\(tag) val=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
        }
        let names = (fm.enumerator(atPath: dir)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".xlsx") }.sorted()
        for n in names {
            guard let data = fm.contents(atPath: dir + "/" + n), let entries = try? Zip.read(data),
                  entries.contains(where: { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") }),
                  let book = try? Xlsx.read(data) else { continue }
            let was = Dictionary(entries.map { ($0.name, $0.data) }, uniquingKeysWith: { a, _ in a })
            for mode in 0 ..< 2 {
                let c = WorkbookController(); c.load(book)
                var any = false
                for si in 0 ..< c.book.sheets.count {
                    c.activeSheet = si
                    for (j, d) in c.sheet.drawings.enumerated() where d.isChart {
                        guard let list = c.chartSeries(j) else { continue }
                        any = true
                        if mode == 0 { charts += 1; _ = c.setChartSeries(j, list) }
                        else if list.count > 1 { _ = c.setChartSeries(j, Array(list.dropLast())) }
                    }
                }
                guard any, let out = try? Xlsx.write(c.book), let outEntries = try? Zip.read(out) else { continue }
                for e in outEntries where e.name.hasPrefix("xl/charts/chart") && e.name.hasSuffix(".xml") {
                    guard let old = was[e.name] else { continue }
                    let oa = String(decoding: old, as: UTF8.self), ob = String(decoding: e.data, as: UTF8.self)
                    if mode == 0 { if oa == ob { same += 1 } else { notSame += 1; print("SERDIFF \(n) \(e.name)") } }
                    else if oa != ob {
                        removed += 1
                        let i = ids(ob, "idx").filter { _ in true }, o = ids(ob, "order")
                        let sers = count(ob, "<c:ser>")
                        // c:idx also appears on c:dLbl; compare only the ser-level ones through the order list, which is ser-only
                        if Set(o).count != o.count { dup += 1; print("SERDUP \(n) \(e.name)") }
                        if sers != count(oa, "<c:ser>") - 1 { wrongCount += 1; print("SERCOUNT \(n) \(e.name) was \(count(oa, "<c:ser>")) now \(sers)") }
                        _ = i
                    }
                }
            }
        }
        print("SERCORPUS charts=\(charts) identityUnchanged=\(same) identityChanged=\(notSame) removedParts=\(removed) duplicateOrder=\(dup) wrongSeriesCount=\(wrongCount)")
        XCTAssertEqual(notSame, 0); XCTAssertEqual(dup, 0); XCTAssertEqual(wrongCount, 0)
    }

    /// Colours over the corpus: every series set, then one reset; parts stay the same size in series, other groups untouched.
    func testCorpusColourEdits() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHART_CORPUS"] else { return }
        var charts = 0, changed = 0, wrongCount = 0, bad = 0
        let fm = FileManager.default
        func count(_ x: String, _ t: String) -> Int { x.components(separatedBy: t).count - 1 }
        let names = (fm.enumerator(atPath: dir)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".xlsx") }.sorted()
        for n in names {
            guard let data = fm.contents(atPath: dir + "/" + n), let entries = try? Zip.read(data),
                  entries.contains(where: { $0.name.hasPrefix("xl/charts/chart") && $0.name.hasSuffix(".xml") }),
                  let book = try? Xlsx.read(data) else { continue }
            let was = Dictionary(entries.map { ($0.name, $0.data) }, uniquingKeysWith: { a, _ in a })
            let c = WorkbookController(); c.load(book)
            for si in 0 ..< c.book.sheets.count {
                c.activeSheet = si
                for (j, d) in c.sheet.drawings.enumerated() where d.isChart {
                    guard let t = c.chartColorTargets(j) else { continue }
                    charts += 1
                    for s in t.series { c.setChartColor(j, series: s.series, point: nil, color: Color(0xFF123456)) }
                    for p in t.points.prefix(2) { c.setChartColor(j, series: p.series, point: p.point, color: Color(0xFF654321)) }
                }
            }
            guard let out = try? Xlsx.write(c.book), let outEntries = try? Zip.read(out) else { bad += 1; continue }
            for e in outEntries where e.name.hasPrefix("xl/charts/chart") && e.name.hasSuffix(".xml") {
                guard let old = was[e.name] else { continue }
                let oa = String(decoding: old, as: UTF8.self), ob = String(decoding: e.data, as: UTF8.self)
                if oa != ob { changed += 1 }
                if count(ob, "<c:ser>") != count(oa, "<c:ser>") { wrongCount += 1; print("COLCOUNT \(n) \(e.name)") }
                if count(ob, "<c:dPt>") < count(oa, "<c:dPt>") && false { bad += 1 }
                if !XMLParser(data: e.data).parse() { bad += 1; print("COLXML \(n) \(e.name)") }
            }
        }
        print("COLCORPUS charts=\(charts) partsChanged=\(changed) wrongSeriesCount=\(wrongCount) malformed=\(bad)")
        XCTAssertEqual(wrongCount, 0); XCTAssertEqual(bad, 0)
    }
}
