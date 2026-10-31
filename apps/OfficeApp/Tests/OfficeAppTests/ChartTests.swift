import XCTest
import Flutter
import OfficeText
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
            if type.isPie { back.series = Array(back.series.prefix(1)) }
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
        // 8.2 plus headroom: up the page 0 to 9 by ones (line-chart's), across
        // it 0 to 10 by twos (bar-chart's), as PowerPoint draws them.
        XCTAssertEqual(ChartPainter.scale(0, 8.2).hi, 9)
        XCTAssertEqual(ChartPainter.scale(0, 8.2).step, 1)
        XCTAssertEqual(ChartPainter.scale(0, 8.2, intervals: 8).hi, 10)
        XCTAssertEqual(ChartPainter.scale(0, 8.2, intervals: 8).step, 2)
        // Up to ten steps up the page: 435,043 runs to 500,000 by 50,000 in
        // Word's print of zh-2a241df1 (nine steps made it 100,000).
        XCTAssertEqual(ChartPainter.scale(0, 435_043).step, 50_000)
        XCTAssertEqual(ChartPainter.scale(0, 435_043).hi, 500_000)
        XCTAssertEqual(ChartPainter.label(2.5, percent: false), "2.5")
        XCTAssertEqual(ChartPainter.label(0.3, percent: true), "30%")
    }

    /// Bounds the file fixes are the axis's, its step ten intervals at
    /// most (0 to 1 by 0.1); they survive the chart's own XML.
    func testFixedBoundsAreTheAxis() throws {
        let s = ChartPainter.fixedScale(auto: ChartPainter.scale(0, 1.02), min: 0, max: 1, step: nil)
        XCTAssertEqual(s.lo, 0); XCTAssertEqual(s.hi, 1); XCTAssertEqual(s.step, 0.1, accuracy: 1e-12)
        let open = ChartPainter.fixedScale(auto: ChartPainter.scale(0, 550), min: 300, max: nil, step: nil)
        XCTAssertEqual(open.lo, 300); XCTAssertEqual(open.hi, 600, "the open end the automatic one")
        XCTAssertEqual(ChartPainter.fixedScale(auto: ChartPainter.scale(0, 5), min: nil, max: nil, step: 2.5).hi, 7.5)
        var c = Chart.sample(.column)
        c.valueMin = 0; c.valueMax = 1; c.valueStep = 0.25
        XCTAssertEqual(try reread(c), c)
    }

    /// chartex's stock chart: its series' lines none, Close marked by 3pt
    /// dots, and high-low lines in the text's dark grey, 0.75pt.
    func testAStockChartsHighLowLinesAndHiddenLinesAreRead() throws {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func ser(_ i: Int, _ name: String, marker: String) -> String {
            "<c:ser><c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/><c:tx><c:v>\(name)</c:v></c:tx><c:spPr><a:ln w=\"19050\"><a:noFill/></a:ln></c:spPr>\(marker)"
                + "<c:val><c:numRef><c:numCache><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>\(10 * (i + 1))</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>"
        }
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:plotArea><c:stockChart>
        \(ser(0, "High", marker: "<c:marker><c:symbol val=\"none\"/></c:marker>"))\(ser(1, "Low", marker: "<c:marker><c:symbol val=\"none\"/></c:marker>"))
        \(ser(2, "Close", marker: "<c:marker><c:symbol val=\"dot\"/><c:size val=\"3\"/></c:marker>"))
        <c:hiLowLines><c:spPr><a:ln w="9525"><a:solidFill><a:srgbClr val="404040"/></a:solidFill></a:ln></c:spPr></c:hiLowLines>
        <c:axId val="1"/><c:axId val="2"/></c:stockChart><c:dateAx><c:axId val="1"/><c:axPos val="b"/></c:dateAx><c:valAx><c:axId val="2"/><c:axPos val="l"/></c:valAx>
        </c:plotArea></c:chart></c:chartSpace>
        """
        let c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in Color(0xFF404040) }))
        XCTAssertEqual(c.type, .line)
        XCTAssertEqual(c.series.map(\.lineHidden), [true, true, true])
        XCTAssertEqual(c.series.map(\.marker), ["none", "none", "dot"])
        XCTAssertEqual(c.series[2].markerSize, 3)
        XCTAssertEqual(c.highLowLines, HighLowLines(color: Color(0xFF404040), width: 0.75))
    }

    /// zh-547fc43c's charts: the unit over the columns is the category
    /// axis's title, placed at the chart's top left and read across; the
    /// line of rates over them shows its values, one moved.
    func testAPlacedAxisTitleAndALinesValuesAreRead() throws {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func val(_ a: String, _ b: String) -> String {
            "<c:val><c:numRef><c:numCache><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>\(a)</c:v></c:pt><c:pt idx=\"1\"><c:v>\(b)</c:v></c:pt></c:numCache></c:numRef></c:val>"
        }
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:plotArea>
        <c:barChart><c:barDir val="col"/><c:ser><c:idx val="0"/><c:order val="0"/>\(val("28.4", "28.8"))</c:ser><c:axId val="1"/><c:axId val="2"/></c:barChart>
        <c:lineChart><c:ser><c:idx val="1"/><c:order val="1"/><c:dLbls><c:dLbl><c:idx val="1"/><c:layout><c:manualLayout><c:x val="0.028"/><c:y val="0.05"/></c:manualLayout></c:layout><c:showVal val="1"/></c:dLbl>
        <c:txPr><a:bodyPr/><a:p><a:pPr><a:defRPr sz="1000"/></a:pPr></a:p></c:txPr><c:dLblPos val="t"/><c:showVal val="1"/></c:dLbls>\(val("2.9", "4.7"))</c:ser><c:axId val="1"/><c:axId val="2"/></c:lineChart>
        <c:catAx><c:axId val="1"/><c:delete val="0"/><c:axPos val="b"/><c:title><c:tx><c:rich><a:bodyPr rot="0" vert="horz"/><a:p><a:r><a:rPr sz="1000"/><a:t>亿元</a:t></a:r></a:p></c:rich></c:tx>
        <c:layout><c:manualLayout><c:xMode val="edge"/><c:yMode val="edge"/><c:x val="0.0147"/><c:y val="0.0369"/></c:manualLayout></c:layout><c:overlay val="0"/></c:title><c:crossAx val="2"/></c:catAx>
        <c:valAx><c:axId val="2"/><c:delete val="0"/><c:axPos val="l"/><c:crossAx val="1"/></c:valAx></c:plotArea></c:chart></c:chartSpace>
        """
        let c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        XCTAssertEqual(c.categoryAxisTitle, "亿元")
        XCTAssertEqual(c.categoryAxisTitleAt, PlacedAxisTitle(at: Offset(0.0147, 0.0369), size: 10))
        XCTAssertNil(c.valueAxisTitleAt)
        let line = try XCTUnwrap(c.lineSeries.first)
        XCTAssertTrue(line.valueLabels)
        XCTAssertEqual(line.labelNudges, [1: Offset(0.028, 0.05)])
        XCTAssertEqual(line.labelSize, 10)
    }

    /// What an old chart states about its look: slices' own colours, a
    /// plot's fill and place, axes deleted, no gridlines, its labels'
    /// number format — and no title from a series with no name.
    func testAChartsOwnLookIsRead() throws {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        let val = "<c:val><c:numRef><c:numCache><c:formatCode>0</c:formatCode><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>79.63</c:v></c:pt><c:pt idx=\"1\"><c:v>4</c:v></c:pt></c:numCache></c:numRef></c:val>"
        let bar = """
        <c:chartSpace \(ns)><c:chart><c:plotArea><c:layout><c:manualLayout><c:layoutTarget val="inner"/><c:xMode val="edge"/><c:yMode val="edge"/><c:x val="0.1"/><c:y val="0.2"/><c:w val="0.8"/><c:h val="0.7"/></c:manualLayout></c:layout>
        <c:barChart><c:barDir val="col"/><c:ser><c:idx val="0"/><c:order val="0"/><c:dLbls><c:showVal val="1"/></c:dLbls>\(val)</c:ser></c:barChart>
        <c:catAx><c:delete val="1"/><c:axPos val="b"/></c:catAx><c:valAx><c:delete val="1"/><c:axPos val="l"/></c:valAx>
        <c:spPr><a:solidFill><a:srgbClr val="D9D9D9"/></a:solidFill></c:spPr></c:plotArea></c:chart></c:chartSpace>
        """
        let c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(bar.utf8))), color: { _ in Color(0xFFD9D9D9) }))
        XCTAssertNil(c.title, "a series with no name gives no title")
        XCTAssertEqual(c.plotLayout, Rect.fromLTWH(0.1, 0.2, 0.8, 0.7))
        XCTAssertTrue(c.plotLayoutInner)
        XCTAssertTrue(c.valueAxisDeleted && c.categoryAxisDeleted)
        XCTAssertFalse(c.valueGrid)
        XCTAssertEqual(c.plotFill, Color(0xFFD9D9D9))
        XCTAssertEqual(ChartPainter.dataLabel(c, 79.63), "80")
        let pie = """
        <c:chartSpace \(ns)><c:chart><c:plotArea><c:pieChart><c:ser><c:idx val="0"/><c:order val="0"/>
        <c:dPt><c:idx val="0"/><c:spPr><a:solidFill><a:srgbClr val="5B9BD5"/></a:solidFill></c:spPr></c:dPt>
        <c:dPt><c:idx val="1"/><c:spPr><a:solidFill><a:schemeClr val="accent2"/></a:solidFill></c:spPr></c:dPt>\(val)</c:ser></c:pieChart></c:plotArea></c:chart></c:chartSpace>
        """
        let p = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(pie.utf8))), color: { _ in Color(0xFF5B9BD5) }))
        XCTAssertEqual(p.pointColors, [0: Color(0xFF5B9BD5)], "the theme's own cycle keeps following the theme")
        XCTAssertTrue(ChartXML.chartSpace(p).contains("<c:dPt><c:idx val=\"0\"/><c:bubble3D val=\"0\"/><c:spPr><a:solidFill><a:srgbClr val=\"5B9BD5\"/>"),
                      "written back as its own colour")
    }

    /// A chart's own text size is its labels' and legend's, and an
    /// unsized title's is 1.2 of it, bold where nothing says otherwise.
    func testTheChartsTextSizeSetsItsText() throws {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:title><c:overlay val="0"/></c:title><c:plotArea><c:barChart><c:barDir val="bar"/>
        <c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:v>Sales</c:v></c:tx><c:val><c:numRef><c:numCache><c:ptCount val="1"/><c:pt idx="0"><c:v>8</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>
        </c:barChart></c:plotArea></c:chart><c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1800"/></a:pPr></a:p></c:txPr></c:chartSpace>
        """
        let c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        XCTAssertEqual(c.textSize, 18)
        XCTAssertNil(c.titleSize, "the title's own size is unsaid: 1.2 of the chart's when drawn")
        XCTAssertTrue(c.titleBold)
        XCTAssertEqual(try reread(c).textSize, 18, "written back")
    }

    /// A monochrome style shades its series from one accent — the cooper
    /// deck's style 12 is accent 2, four series shaded and tinted out from
    /// the middle — and survives the chart's own XML.
    func testAMonochromeStyleShadesOneAccent() throws {
        var c = Chart.sample(.column)
        c.style = 12
        XCTAssertEqual(c.monochromeAccent, 2)
        let maroon = Color(0xFF9F2936)
        let accents = [Color(0xFFF07F09), maroon, Color(0xFFFFFFFF), Color(0xFF000000), Color(0xFFF6C0AA), Color(0xFF902430)]
        let four = (0 ..< 4).map { Chart.monochrome($0, of: 4, maroon) }
        XCTAssertEqual(four[0], Color(0xFF7C1E28), "PowerPoint's (124, 30, 40)")
        XCTAssertEqual(four[3], Color(0xFFCFB0B1), "PowerPoint's (207, 176, 177)")
        XCTAssertEqual(c.color(series: 0, accents: accents), Chart.monochrome(0, of: c.series.count, maroon))
        let back = try reread(c)
        XCTAssertEqual(back.style, 12)
        XCTAssertNil(back.series[0].color, "no fill of its own: the style colours it")
        var plain = Chart.sample(.column)
        plain.style = 2
        XCTAssertNil(plain.monochromeAccent)
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

    /// A chartex box-and-whisker chart reads as its samples by category,
    /// its quartiles Excel's exclusive ones: chartex's first box runs
    /// -24 to 23.5 about -7 in Word's print.
    func testABoxAndWhiskerChartIsItsSamples() {
        let xml = """
        <cx:chartSpace xmlns:cx="http://schemas.microsoft.com/office/drawing/2014/chartex" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><cx:chartData><cx:data id="0"><cx:strDim type="cat"><cx:lvl ptCount="10"><cx:pt idx="0">A</cx:pt><cx:pt idx="1">A</cx:pt><cx:pt idx="2">A</cx:pt><cx:pt idx="3">A</cx:pt><cx:pt idx="4">A</cx:pt><cx:pt idx="5">A</cx:pt><cx:pt idx="6">A</cx:pt><cx:pt idx="7">A</cx:pt><cx:pt idx="8">A</cx:pt><cx:pt idx="9">B</cx:pt></cx:lvl></cx:strDim><cx:numDim type="val"><cx:lvl ptCount="10"><cx:pt idx="0">-7</cx:pt><cx:pt idx="1">-10</cx:pt><cx:pt idx="2">-28</cx:pt><cx:pt idx="3">47</cx:pt><cx:pt idx="4">11</cx:pt><cx:pt idx="5">-24</cx:pt><cx:pt idx="6">-24</cx:pt><cx:pt idx="7">36</cx:pt><cx:pt idx="8">10</cx:pt><cx:pt idx="9">5</cx:pt></cx:lvl></cx:numDim></cx:data></cx:chartData><cx:chart><cx:title><cx:tx><cx:rich><a:p><a:r><a:t>boxes</a:t></a:r></a:p></cx:rich></cx:tx></cx:title><cx:plotArea><cx:plotAreaRegion><cx:series layoutId="boxWhisker"><cx:tx><cx:txData><cx:v>S1</cx:v></cx:txData></cx:tx><cx:dataId val="0"/><cx:layoutPr><cx:statistics quartileMethod="exclusive"/></cx:layoutPr></cx:series></cx:plotAreaRegion><cx:axis id="0"><cx:catScaling gapWidth="1"/></cx:axis></cx:plotArea></cx:chart></cx:chartSpace>
        """
        guard let c = ChartXML.readBoxWhisker(XNode.parse(Data(xml.utf8))!) else { return XCTFail("not read") }
        XCTAssertEqual(c.title, "boxes")
        XCTAssertEqual(c.categories, ["A", "B"])
        XCTAssertEqual(c.series.map(\.name), ["S1"])
        XCTAssertEqual(c.boxes?[0][1], [5])
        let a = c.boxes![0][0]
        XCTAssertEqual(ChartXML.quartile(a, 0.25, inclusive: false), -24)
        XCTAssertEqual(ChartXML.quartile(a, 0.5, inclusive: false), -7)
        XCTAssertEqual(ChartXML.quartile(a, 0.75, inclusive: false), 23.5)
        XCTAssertFalse(c.legend)
        let funnel = xml.replacingOccurrences(of: "boxWhisker", with: "funnel")
        XCTAssertNil(ChartXML.readBoxWhisker(XNode.parse(Data(funnel.utf8))!), "another chartex kind keeps its picture")
    }

    /// A chart this app cannot draw reads as nothing, so the frame keeps
    /// its own picture. (Every single kind is drawn since surfaces were,
    /// 5c5d43a4; an area under a line is a combination still left alone.)
    func testAKindThisAppCannotDrawIsKept() {
        let ser = "<c:ser><c:val><c:numLit><c:ptCount val=\"1\"/><c:pt idx=\"0\"><c:v>1</c:v></c:pt></c:numLit></c:val></c:ser><c:axId val=\"1\"/><c:axId val=\"2\"/>"
        let combo = "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart><c:plotArea><c:areaChart>\(ser)</c:areaChart><c:lineChart>\(ser)</c:lineChart></c:plotArea></c:chart></c:chartSpace>"
        XCTAssertNil(ChartXML.read(XNode.parse(Data(combo.utf8))!, color: { _ in nil }))
        XCTAssertNotNil(ChartXML.read(XNode.parse(Data(combo.replacingOccurrences(of: "<c:lineChart>\(ser)</c:lineChart>", with: "").utf8))!, color: { _ in nil }), "the area alone is drawn")
    }

    /// Columns with a line over them on the same axes are one chart: the
    /// line's series kept beside the columns', with its marks, and written
    /// back as a line chart on those axes.
    func testAColumnAndLineCombinationIsAChart() throws {
        let combo = "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><c:chart><c:plotArea><c:barChart><c:barDir val=\"col\"/><c:ser><c:val><c:numLit><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>5</c:v></c:pt><c:pt idx=\"1\"><c:v>6</c:v></c:pt></c:numLit></c:val></c:ser><c:axId val=\"1\"/><c:axId val=\"2\"/></c:barChart><c:lineChart><c:ser><c:tx><c:v>Then</c:v></c:tx><c:spPr><a:ln><a:noFill/></a:ln></c:spPr><c:marker><c:symbol val=\"circle\"/><c:size val=\"8\"/></c:marker><c:dPt><c:idx val=\"1\"/><c:marker><c:symbol val=\"none\"/></c:marker></c:dPt><c:val><c:numLit><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>3</c:v></c:pt><c:pt idx=\"1\"><c:v>9</c:v></c:pt></c:numLit></c:val></c:ser><c:axId val=\"1\"/><c:axId val=\"2\"/></c:lineChart></c:plotArea></c:chart></c:chartSpace>"
        let c = try XCTUnwrap(ChartXML.read(XNode.parse(Data(combo.utf8))!, color: { _ in nil }))
        XCTAssertEqual(c.type, .column)
        XCTAssertEqual(c.lineSeries.count, 1)
        XCTAssertEqual(c.lineSeries[0].values, [3, 9])
        XCTAssertEqual(c.lineSeries[0].marker, "circle")
        XCTAssertEqual(c.lineSeries[0].markerSize, 8)
        XCTAssertTrue(c.lineSeries[0].lineHidden)
        XCTAssertEqual(c.lineSeries[0].unmarked, [1])
        XCTAssertNil(c.title, "two series: no title from a name")
        let back = try reread(c)
        XCTAssertEqual(back.lineSeries.map(\.values), c.lineSeries.map(\.values))
        XCTAssertEqual(back.lineSeries.first?.unmarked, [1])
    }

    /// A radar chart is read and drawn: its style, and its series' lines
    /// not taken for outlines.
    func testARadarChartIsAChart() throws {
        let radar = "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><c:chart><c:plotArea><c:radarChart><c:radarStyle val=\"filled\"/><c:ser><c:spPr><a:ln w=\"28575\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></a:ln></c:spPr><c:val><c:numLit><c:ptCount val=\"3\"/><c:pt idx=\"0\"><c:v>1</c:v></c:pt><c:pt idx=\"1\"><c:v>2</c:v></c:pt><c:pt idx=\"2\"><c:v>3</c:v></c:pt></c:numLit></c:val></c:ser></c:radarChart></c:plotArea></c:chart></c:chartSpace>"
        let c = try XCTUnwrap(ChartXML.read(XNode.parse(Data(radar.utf8))!, color: { _ in Color(0xFFFF0000) }))
        XCTAssertEqual(c.type, .radar)
        XCTAssertTrue(c.radarFilled)
        XCTAssertNil(c.series[0].outline)
        XCTAssertTrue(c.plainText, "no colour given: the theme's text colour")
    }

    func testADoughnutIsAPieWithAHole() throws {
        let doughnut = "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\"><c:chart><c:plotArea><c:doughnutChart><c:varyColors val=\"1\"/><c:ser><c:val><c:numLit><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>1</c:v></c:pt><c:pt idx=\"1\"><c:v>3</c:v></c:pt></c:numLit></c:val></c:ser><c:firstSliceAng val=\"0\"/><c:holeSize val=\"75\"/></c:doughnutChart></c:plotArea></c:chart></c:chartSpace>"
        let c = try XCTUnwrap(ChartXML.read(XNode.parse(Data(doughnut.utf8))!, color: { _ in nil }))
        XCTAssertEqual(c.type, .doughnut)
        XCTAssertEqual(c.holeSize, 75)
        XCTAssertFalse(c.type.hasAxes)
        let xml = ChartXML.chartSpace(c)
        XCTAssertTrue(xml.contains("<c:doughnutChart>") && xml.contains("<c:holeSize val=\"75\"/>"))
        XCTAssertEqual(try reread(c), c)
    }
    func testAPiePointsOwnLabelTextIsRead() throws {
        // zh-61aaad09's pie writes its labels out, "109646, 15.85%": Word
        // prints them as they stand, where ours drew the percent alone, "16%".
        let pie = "<c:chartSpace xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\"><c:chart><c:plotArea><c:pieChart><c:varyColors val=\"1\"/><c:ser><c:dLbls><c:dLbl><c:idx val=\"0\"/><c:tx><c:rich><a:bodyPr/><a:p><a:r><a:t>109646, 15.85%</a:t></a:r></a:p></c:rich></c:tx><c:dLblPos val=\"bestFit\"/><c:showVal val=\"1\"/><c:showPercent val=\"1\"/></c:dLbl><c:showVal val=\"0\"/><c:showPercent val=\"0\"/></c:dLbls><c:val><c:numLit><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>109646</c:v></c:pt><c:pt idx=\"1\"><c:v>582054</c:v></c:pt></c:numLit></c:val></c:ser></c:pieChart></c:plotArea></c:chart></c:chartSpace>"
        let c = try XCTUnwrap(ChartXML.read(XNode.parse(Data(pie.utf8))!, color: { _ in nil }))
        XCTAssertEqual(c.pieLabels?.texts[0], "109646, 15.85%")
        XCTAssertNil(c.pieLabels?.texts[1])
    }

}
