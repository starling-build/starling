import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class ChartTests: XCTestCase {
    private func reread(_ c: Chart) throws -> Chart {
        let node = try XCTUnwrap(XNode.parse(Data(ChartXML.chartSpace(c).utf8)))
        return try XCTUnwrap(ChartXML.read(node, color: { _ in nil }))
    }

    func testEveryKindSurvivesItsOwnXML() throws {
        for type in ChartType.allCases {
            var c = Chart.sample(type)
            c.dataLabels = true
            c.legend = type != .scatter
            if type.hasAxes {
                c.valueAxisTitle = "Units"
                c.categoryAxisTitle = "Quarter"
            }
            var back = try reread(c)
            if type == .pie { back.series = Array(back.series.prefix(1)) }
            XCTAssertEqual(back, c, "\(type)")
        }
    }

    func testStackingAndBlanks() throws {
        var c = Chart.sample(.column)
        c.stacked = true
        c.percent = true
        c.series[1].values[2] = nil
        XCTAssertEqual(try reread(c), c)
    }

    func testTheWorkbookHoldsTheTable() throws {
        let book = PptxPackage(try Zip.read(try ChartXML.workbook(Chart.sample(.column))))
        let sheet = String(data: try XCTUnwrap(book.parts["xl/worksheets/sheet1.xml"]), encoding: .utf8)!
        XCTAssertTrue(sheet.contains("<c r=\"B1\" t=\"inlineStr\"><is><t xml:space=\"preserve\">Series 1</t>"))
        XCTAssertTrue(sheet.contains("<c r=\"A5\" t=\"inlineStr\"><is><t xml:space=\"preserve\">Category 4</t>"))
        XCTAssertTrue(sheet.contains("<c r=\"D5\"><v>5</v></c>"))
        XCTAssertNotNil(book.parts["xl/workbook.xml"])
    }

    func testAxisScaleIsRound() {
        let s = ChartPainter.scale(0, 5)
        XCTAssertEqual(s.lo, 0); XCTAssertEqual(s.hi, 6); XCTAssertEqual(s.step, 1)
        XCTAssertEqual(ChartPainter.scale(0, 8.2).hi, 10, "8.2 plus headroom: 0 to 10 in twos")
        XCTAssertEqual(ChartPainter.label(2.5, percent: false), "2.5")
        XCTAssertEqual(ChartPainter.label(0.3, percent: true), "30%")
    }

    func testCellTypingIsOneUndoStep() {
        let deck = SlidesSample.make()
        let shape = deck.slides.flatMap(\.shapes).first { $0.chart != nil }!
        let before = shape.chart!
        var c = before
        for text in ["7", "7.", "7.5"] {
            c.series[0].values[0] = Double(text)
            deck.setChart(shape, c, coalesce: "cell 0:0")
        }
        XCTAssertEqual(shape.chart?.series[0].values[0], 7.5)
        deck.undo()
        XCTAssertEqual(shape.chart, before)
    }

    func testDeckRoundTripAndKeepingUnlessEdited() throws {
        let deck = SlidesSample.make()
        let data = try Pptx.write(deck)
        var package = PptxPackage(try Zip.read(data))
        // Mark the written chart part: kept, the mark survives a save.
        let part = try XCTUnwrap(package.parts.keys.first { $0.hasPrefix("ppt/charts/") && $0.hasSuffix(".xml") })
        let xml = String(data: package.parts[part]!, encoding: .utf8)!
        package.parts[part] = Data(xml.replacingOccurrences(of: "<c:roundedCorners val=\"0\"/>",
                                                            with: "<c:roundedCorners val=\"0\"/><c:style val=\"42\"/>").utf8)
        var entries: [ZipEntry] = []
        for (k, v) in package.parts { entries.append(ZipEntry(name: k, data: v)) }
        var (state, theme, pkg) = try Pptx.read(try Zip.write(entries))
        let s = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.chart != nil } })
        let i = state.slides[s].shapes.firstIndex { $0.chart != nil }!
        XCTAssertEqual(state.slides[s].shapes[i].chart, Chart.sample(.column))

        func charts(_ state: DeckState) throws -> [String: String] {
            let out = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            var found: [String: String] = [:]
            for (k, v) in out.parts where k.hasPrefix("ppt/charts/") && k.hasSuffix(".xml") {
                found[k] = String(data: v, encoding: .utf8)
            }
            return found
        }
        let kept = try charts(state)
        XCTAssertEqual(kept.count, 1)
        XCTAssertTrue(kept.values.first!.contains("<c:style val=\"42\"/>"), "unedited: the part as read")

        var edited = state.slides[s].shapes[i].chart!
        edited.series[0].values[0] = 9
        state.slides[s].shapes[i].kind = .chart(edited)
        let fresh = try charts(state)
        XCTAssertEqual(fresh.count, 1)
        XCTAssertFalse(fresh.values.first!.contains("<c:style val=\"42\"/>"), "edited: our own part")
        XCTAssertTrue(fresh.values.first!.contains("<c:v>9</c:v>"))
    }

    func testAKindThisAppCannotDrawIsKept() {
        let doughnut = "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart><c:plotArea><c:doughnutChart><c:ser><c:val><c:numLit><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>1</c:v></c:pt></c:numLit></c:val></c:ser></c:doughnutChart></c:plotArea></c:chart></c:chartSpace>"
        XCTAssertNil(ChartXML.read(XNode.parse(Data(doughnut.utf8))!, color: { _ in nil }))
    }
}
