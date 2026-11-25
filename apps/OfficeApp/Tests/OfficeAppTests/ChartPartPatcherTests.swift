import XCTest
@testable import OfficeApp

/// S-CH-1: editing a chart that came from a file changes only what was edited in its own part.
final class ChartPartPatcherTests: XCTestCase {
    private func part(_ c: Chart) -> String {
        ChartXML.chartSpace(c).replacingOccurrences(of: "<c:chart>", with: "<c:style val=\"42\"/><c:chart>")
    }
    private func readBack(_ xml: String) -> Chart? {
        guard let n = XNode.parse(Data(xml.utf8)) else { return nil }
        return ChartXML.read(ChartXML.canonical(n), color: { _ in nil })
    }

    func testTitleLegendAndDataPatchKeepsTheRest() throws {
        var old = Chart.sample(.column)
        old.title = "Sales"
        let xml = part(old)
        XCTAssertTrue(xml.contains("<c:style val=\"42\"/>"))
        var new = old
        new.title = "Revenue"
        new.legend = true; new.legendPosition = "r"
        new.categories = ["A", "B", "C", "D", "E"]
        new.series = [ChartSeries(name: "One", values: [1, 2, 3, 4, 5]), ChartSeries(name: "Two", values: [5, 4, nil, 2, 1]),
                      ChartSeries(name: "Three", values: [2, 2, 2, 2, 2])]
        let r = try XCTUnwrap(ChartPartPatcher.patch(xml, old: old, new: new))
        XCTAssertFalse(r.writes.isEmpty)
        XCTAssertTrue(r.xml.contains("<c:style val=\"42\"/>"), "what the user did not touch stays")
        let back = try XCTUnwrap(readBack(r.xml))
        XCTAssertEqual(back.title, "Revenue")
        XCTAssertEqual(back.legendPosition, "r")
        XCTAssertEqual(back.categories, new.categories)
        XCTAssertEqual(back.series.map(\.name), ["One", "Two", "Three"])
        XCTAssertEqual(back.series[1].values, [5, 4, nil, 2, 1])
        XCTAssertEqual(back.type, .column)
        // Fewer series, no title, no legend.
        var less = new
        less.title = nil; less.legend = false
        less.series = [new.series[0]]
        let r2 = try XCTUnwrap(ChartPartPatcher.patch(r.xml, old: new, new: less))
        let b2 = try XCTUnwrap(readBack(r2.xml))
        XCTAssertNil(b2.title)
        XCTAssertFalse(b2.legend)
        XCTAssertEqual(b2.series.count, 1)
        XCTAssertTrue(r2.xml.contains("<c:style val=\"42\"/>"))
    }

    func testTypeChangeKeepsTheDataAndTheRest() throws {
        let old = Chart.sample(.column)
        let xml = part(old)
        for type in [ChartType.bar, .line, .area, .pie, .doughnut, .scatter, .radar] {
            var new = old; new.type = type
            let r = try XCTUnwrap(ChartPartPatcher.patch(xml, old: old, new: new), "\(type)")
            XCTAssertTrue(r.xml.contains("<c:style val=\"42\"/>"))
            let back = try XCTUnwrap(readBack(r.xml), "\(type) reads")
            XCTAssertEqual(back.type, type)
            XCTAssertEqual(back.series[0].values, old.series[0].values, "\(type)")
            // And back again (a pie kept one series, so the others' cells are gone: that one is written fresh).
            if type.isPie { continue }
            let again = try XCTUnwrap(ChartPartPatcher.patch(r.xml, old: new, new: old))
            XCTAssertEqual(readBack(again.xml)?.type, .column)
        }
    }

    /// A pie turned into a column chart gets new axes; they say "no minor ticks" outright, as PowerPoint's own do.
    func testNewAxesStateTheirTickMarks() throws {
        let old = Chart.sample(.pie)
        var new = old; new.type = .column
        let r = try XCTUnwrap(ChartPartPatcher.patch(part(old), old: old, new: new))
        for axis in ["c:catAx", "c:valAx"] {
            let a = try XCTUnwrap(r.xml.range(of: "<\(axis)>"))
            let body = String(r.xml[a.upperBound...].prefix { _ in true })
            let end = try XCTUnwrap(body.range(of: "</\(axis)>"))
            let text = String(body[..<end.lowerBound])
            XCTAssertTrue(text.contains("<c:minorTickMark val=\"none\"/>"), axis)
            XCTAssertTrue(text.contains("<c:majorTickMark val=\"out\"/>"), axis)
            XCTAssertTrue(text.contains("<c:tickLblPos val=\"nextTo\"/>"), axis)
            XCTAssertLessThan(try XCTUnwrap(text.range(of: "<c:tickLblPos")).lowerBound, try XCTUnwrap(text.range(of: "<c:crossAx")).lowerBound)
        }
    }

    /// The deck path: a chart read from a file, edited, saved: one chart part (patched), one workbook, the new data.
    func testEditedFileChartSavesThroughItsOwnPart() throws {
        let deck = DeckController()
        deck.slides[0].shapes.removeAll()
        deck.addChart(.column)
        var (state, theme, package) = try Pptx.read(Pptx.write(deck))
        // Something of the file's own that this app does not model.
        let key = try XCTUnwrap(package.parts.keys.first { $0.hasPrefix("ppt/charts/") && $0.hasSuffix(".xml") && !$0.contains("_rels") })
        var xml = try XCTUnwrap(String(data: package.parts[key] ?? Data(), encoding: .utf8))
        let at = try XCTUnwrap(xml.range(of: "<c:chart>"))
        xml.replaceSubrange(at, with: "<c:style val=\"42\"/><c:chart>")
        package.parts[key] = Data(xml.utf8)
        let file = DeckController(); file.load(state, theme: theme, package: package)
        let shape = try XCTUnwrap(file.currentSlide.shapes.first { $0.chart != nil })
        var c = try XCTUnwrap(shape.chart)
        c.title = "Edited"; c.categories = ["x", "y"]; c.series = [ChartSeries(name: "S", values: [7, 8])]
        file.setChart(shape, c)
        let (back, backTheme, out) = try Pptx.read(Pptx.write(file))
        let got = DeckController(); got.load(back, theme: backTheme, package: out)
        let g = try XCTUnwrap(got.currentSlide.shapes.first { $0.chart != nil }?.chart)
        XCTAssertEqual(g.title, "Edited")
        XCTAssertEqual(g.categories, ["x", "y"])
        XCTAssertEqual(g.series[0].values, [7, 8])
        let parts = out.parts.keys.filter { $0.hasPrefix("ppt/charts/") && $0.hasSuffix(".xml") && !$0.contains("_rels") }
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(out.parts.keys.filter { $0.hasPrefix("ppt/embeddings/") }.count, 1)
        let text = String(data: out.parts[parts[0]] ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("<c:style val=\"42\"/>"), "the file's own styling is kept")
    }

    private func ser(_ idx: Int, _ col: String, _ name: String, _ vals: [Int]) -> String {
        let pts = vals.enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\($0.element)</c:v></c:pt>" }.joined()
        return "<c:ser><c:idx val=\"\(idx)\"/><c:order val=\"\(idx)\"/><c:tx><c:strRef><c:f>'資料'!$\(col)$1</c:f><c:strCache><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>\(name)</c:v></c:pt></c:strCache></c:strRef></c:tx><c:spPr><a:ln w=\"9525\"/></c:spPr><c:cat><c:strRef><c:f>'資料'!$A$2:$A$3</c:f><c:strCache><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>a</c:v></c:pt><c:pt idx=\"1\"><c:v>b</c:v></c:pt></c:strCache></c:strRef></c:cat><c:val><c:numRef><c:f>'資料'!$\(col)$2:$\(col)$3</c:f><c:numCache><c:formatCode>General</c:formatCode><c:ptCount val=\"2\"/>\(pts)</c:numCache></c:numRef></c:val></c:ser>"
    }

    /// A chart as PowerPoint writes it: two chart groups, a worksheet with its own name, a legend and a title.
    private var twoGroupPart: String {
        "<?xml version=\"1.0\"?><c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><c:chart><c:title><c:tx><c:rich><a:bodyPr/><a:p><a:r><a:rPr lang=\"en-US\" sz=\"2000\"/><a:t>T</a:t></a:r></a:p></c:rich></c:tx><c:overlay val=\"0\"/></c:title><c:autoTitleDeleted val=\"0\"/><c:plotArea><c:lineChart><c:grouping val=\"standard\"/>"
            + ser(0, "B", "S0", [1, 2]) + "<c:axId val=\"1\"/><c:axId val=\"2\"/></c:lineChart><c:lineChart><c:grouping val=\"standard\"/>"
            + ser(1, "C", "S1", [3, 4]) + "<c:axId val=\"3\"/><c:axId val=\"4\"/></c:lineChart><c:catAx><c:axId val=\"1\"/><c:axPos val=\"b\"/><c:crossAx val=\"2\"/></c:catAx><c:valAx><c:axId val=\"2\"/><c:axPos val=\"l\"/><c:crossAx val=\"1\"/></c:valAx><c:valAx><c:axId val=\"4\"/><c:axPos val=\"r\"/><c:crossAx val=\"3\"/></c:valAx><c:catAx><c:axId val=\"3\"/><c:delete val=\"1\"/><c:axPos val=\"b\"/><c:crossAx val=\"4\"/></c:catAx></c:plotArea><c:legend><c:legendPos val=\"b\"/></c:legend></c:chart></c:chartSpace>"
    }

    func testDataEditKeepsIdsSheetNameAndTheOtherSeries() throws {
        let xml = twoGroupPart
        let old = try XCTUnwrap(readBack(xml))
        var new = old
        new.categories = old.categories + ["c"]
        new.series = old.series.map { var x = $0; x.values.append(9); return x }
        let r = try XCTUnwrap(ChartPartPatcher.patch(xml, old: old, new: new))
        XCTAssertTrue(r.xml.contains("'資料'!$B$2:$B$4"), "the file's own sheet and cells")
        XCTAssertFalse(r.xml.contains("Sheet1"))
        XCTAssertEqual(r.xml.components(separatedBy: "<c:idx val=\"0\"/>").count, 2)
        XCTAssertEqual(r.xml.components(separatedBy: "<c:idx val=\"1\"/>").count, 2)
        XCTAssertTrue(r.xml.contains("<c:legend>") && r.xml.contains("sz=\"2000\""), "legend and title stay")
        XCTAssertTrue(r.writes.allSatisfy { $0.sheet == "資料" })
    }

    func testDataEditKeepsAnUnnamedSeriesUnnamed() throws {
        let named = twoGroupPart
        var xml = named
        while let a = xml.range(of: "<c:tx>"), let b = xml.range(of: "</c:tx>", range: a.upperBound ..< xml.endIndex) {
            xml.removeSubrange(a.lowerBound ..< b.upperBound)
        }
        let old = try XCTUnwrap(readBack(xml))
        var new = old
        new.categories = old.categories + ["c"]
        new.series = old.series.map { var x = $0; x.values.append(9); return x }
        let r = try XCTUnwrap(ChartPartPatcher.patch(xml, old: old, new: new))
        XCTAssertFalse(r.xml.contains("<c:tx>"), "no name invented for a series the file left unnamed")
        // A name the user typed is written.
        new.series[0].name = "Sales"
        let r2 = try XCTUnwrap(ChartPartPatcher.patch(xml, old: old, new: new))
        XCTAssertTrue(r2.xml.contains("Sales"))
    }

    func testNewTitleCarriesItsHostDefaultStyle() throws {
        let bare = "<c:chartSpace><c:chart><c:autoTitleDeleted val=\"1\"/><c:plotArea><c:barChart/></c:plotArea></c:chart></c:chartSpace>"
        let ppt = ChartPartPatch.title(bare, .set("T"), style: .powerPoint)
        XCTAssertTrue(ppt.contains("<a:defRPr sz=\"1862\" b=\"0\""), "PowerPoint: 18.6 pt regular")
        XCTAssertTrue(ppt.contains("<a:lumMod val=\"65000\"/><a:lumOff val=\"35000\"/>"), "tx1 at 65 %")
        let xl = ChartPartPatch.title(bare, .set("T"))
        XCTAssertTrue(xl.contains("<a:defRPr sz=\"1400\" b=\"0\""), "Excel: 14 pt regular")
        XCTAssertTrue(ppt.contains("<a:t>T</a:t>") && ppt.contains("autoTitleDeleted val=\"0\""))
        // An existing title keeps its own look.
        let own = "<c:chartSpace><c:chart><c:title><c:tx><c:rich><a:p><a:r><a:rPr sz=\"3000\"/><a:t>Old</a:t></a:r></a:p></c:rich></c:tx></c:title><c:plotArea><c:barChart/></c:plotArea></c:chart></c:chartSpace>"
        let kept = ChartPartPatch.title(own, .set("New"), style: .powerPoint)
        XCTAssertTrue(kept.contains("sz=\"3000\"") && !kept.contains("1862"))
    }

    func testTypeChangeKeepsIdsCellsAndTheSecondAxis() throws {
        var xml = twoGroupPart
        xml = xml.replacingOccurrences(of: "<c:lineChart>", with: "<c:barChart><c:barDir val=\"col\"/>", options: [], range: xml.range(of: "<c:lineChart>"))
        xml = xml.replacingOccurrences(of: "</c:lineChart>", with: "</c:barChart>", options: [], range: xml.range(of: "</c:lineChart>"))
        var old = try XCTUnwrap(readBack(xml))
        old.type = .column
        var new = old; new.type = .line
        let r = try XCTUnwrap(ChartPartPatcher.patch(xml, old: old, new: new))
        XCTAssertTrue(r.writes.isEmpty, "a type change leaves the workbook alone")
        XCTAssertTrue(r.xml.contains("'資料'!$B$2:$B$3"))
        XCTAssertTrue(r.xml.contains("<c:legend>"))
        XCTAssertEqual(r.xml.components(separatedBy: "<c:idx val=\"1\"/>").count, 2)
        XCTAssertTrue(r.xml.contains("<c:axId val=\"4\"/><c:axPos val=\"r\"/>") || r.xml.contains("<c:axPos val=\"r\"/>"), "the second value axis stays at the right")
    }

    func testWorkbookEditKeepsASecondSheetAndAFormula() throws {
        let book = Workbook(sheets: [Worksheet(name: "資料"), Worksheet(name: "Notes")])
        book.sheets[0].cells[CellAddress(row: 0, col: 1)] = Cell(input: "S0", value: .text("S0"))
        book.sheets[0].cells[CellAddress(row: 1, col: 1)] = Cell(input: "1", value: .number(1))
        book.sheets[1].cells[CellAddress(row: 0, col: 0)] = Cell(input: "7", value: .number(7))
        book.sheets[1].cells[CellAddress(row: 1, col: 0)] = Cell(input: "=A1*2")
        let data = try Xlsx.write(book)
        let writes = [ChartPartPatcher.CellWrite(sheet: "資料", row: 1, col: 1, value: .number(5)),
                      ChartPartPatcher.CellWrite(sheet: "資料", row: 2, col: 1, value: .number(6))]
        let out = try XCTUnwrap(ChartPartPatcher.apply(writes, to: data))
        let back = try Xlsx.read(out)
        XCTAssertEqual(back.sheets.map(\.name), ["資料", "Notes"])
        XCTAssertEqual(back.sheets[0].cells[CellAddress(row: 1, col: 1)]?.value, .number(5))
        XCTAssertEqual(back.sheets[0].cells[CellAddress(row: 2, col: 1)]?.value, .number(6))
        XCTAssertEqual(back.sheets[1].cells[CellAddress(row: 1, col: 0)]?.input, "=A1*2", "the formula is still a formula")
        XCTAssertEqual(back.sheets[1].cells[CellAddress(row: 0, col: 0)]?.value, .number(7))
    }
}
