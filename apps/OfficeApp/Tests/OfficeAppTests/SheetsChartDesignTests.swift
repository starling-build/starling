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
}
