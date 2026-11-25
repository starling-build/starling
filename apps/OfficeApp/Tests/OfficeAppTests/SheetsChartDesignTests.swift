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
        XCTAssertLessThanOrEqual(f.x + f.width, setup.printableWidth)
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
}
