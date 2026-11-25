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
        XCTAssertTrue(r.workbook)
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
            // And back again.
            let again = try XCTUnwrap(ChartPartPatcher.patch(r.xml, old: new, new: old))
            XCTAssertEqual(readBack(again.xml)?.type, .column)
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
}
