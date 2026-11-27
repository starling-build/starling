import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Where Excel puts a sheet chart's plot when its title is placed by hand or tilted (Excel 2026-11-22 prints:
/// chart-axis-label-rotation, chart-tdf124817, chart-chart-area-style-background, chart-title_manual_layout).
final class ChartTitlePlotTests: XCTestCase {
    private func chart(titleLayout: String, rot: String = "") throws -> Chart {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:title><c:tx><c:rich><a:bodyPr\(rot)/><a:p><a:r><a:t>Sales by year</a:t></a:r></a:p></c:rich></c:tx>\(titleLayout)<c:overlay val="0"/></c:title>
        <c:autoTitleDeleted val="0"/><c:plotArea><c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>
        <c:ser><c:idx val="0"/><c:order val="0"/><c:val><c:numRef><c:numCache><c:ptCount val="3"/><c:pt idx="0"><c:v>1</c:v></c:pt><c:pt idx="1"><c:v>3</c:v></c:pt><c:pt idx="2"><c:v>2</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>
        <c:axId val="1"/><c:axId val="2"/></c:barChart><c:catAx><c:axId val="1"/><c:axPos val="b"/><c:crossAx val="2"/></c:catAx><c:valAx><c:axId val="2"/><c:axPos val="l"/><c:crossAx val="1"/></c:valAx>
        <c:spPr><a:solidFill><a:srgbClr val="D9D9D9"/></a:solidFill></c:spPr></c:plotArea></c:chart></c:chartSpace>
        """
        var c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        c.onSheet = true
        c.plotFill = Color(0xFFD9D9D9)
        return c
    }

    private func paint(_ c: Chart) -> PlotSpyCanvas {
        let canvas = PlotSpyCanvas()
        ChartPainter.paint(c, canvas, Rect.fromLTWH(0, 0, 360, 216), pxPerPt: 1, theme: DeckTheme())
        return canvas
    }

    /// A title placed by hand (its own x, y) still leaves the plot where an automatic title would: Excel lays the
    /// plot out for the title's own spot and only then moves the title.
    func testAPlacedTitleLeavesThePlotWhereAnAutomaticTitleWould() throws {
        let auto = try XCTUnwrap(paint(chart(titleLayout: "")).plotTop)
        let placed = try XCTUnwrap(paint(chart(titleLayout: "<c:layout><c:manualLayout><c:xMode val=\"edge\"/><c:yMode val=\"edge\"/><c:x val=\"0.6\"/><c:y val=\"0.3\"/></c:manualLayout></c:layout>")).plotTop)
        XCTAssertEqual(placed, auto, accuracy: 0.01)
    }

    /// A tilted title (`a:bodyPr rot`) is drawn turned, and the plot gives way to the turned box's height.
    func testATiltedTitleIsDrawnTurnedAndReservesItsTurnedHeight() throws {
        let flat = paint(try chart(titleLayout: ""))
        let tilted = paint(try chart(titleLayout: "", rot: " rot=\"-1800000\""))
        XCTAssertEqual(tilted.turns.first ?? 0, -.pi / 6, accuracy: 1e-9)
        XCTAssertTrue(flat.turns.isEmpty)
        let flatTop = try XCTUnwrap(flat.plotTop), tiltedTop = try XCTUnwrap(tilted.plotTop)
        XCTAssertGreaterThan(tiltedTop, flatTop + 10, "a 30° title over 'Sales by year' stands much taller than a flat one")
    }
}

/// Records the plot's fill (D9D9D9) and every turn.
private final class PlotSpyCanvas: Canvas {
    var plotTop: Double?
    var turns: [Double] = []
    func save() {}
    func saveLayer(_ bounds: Rect?, _ paint: Paint) {}
    func restore() {}
    func restoreToCount(_ count: Int) {}
    func getSaveCount() -> Int { 1 }
    func translate(_ dx: Double, _ dy: Double) {}
    func scale(_ sx: Double, _ sy: Double?) {}
    func rotate(_ radians: Double) { turns.append(radians) }
    func skew(_ sx: Double, _ sy: Double) {}
    func transform(_ matrix4: [Double]) {}
    func getTransform() -> [Double] { [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] }
    func clipRect(_ rect: Rect, clipOp: ClipOp, doAntiAlias: Bool) {}
    func clipRRect(_ rrect: RRect, doAntiAlias: Bool) {}
    func clipRSuperellipse(_ rsuperellipse: RSuperellipse, doAntiAlias: Bool) {}
    func clipPath(_ path: Path, doAntiAlias: Bool) {}
    func getLocalClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func getDestinationClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func drawColor(_ color: Color, _ blendMode: BlendMode) {}
    func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) {}
    func drawPaint(_ paint: Paint) {}
    func drawRect(_ rect: Rect, _ paint: Paint) { if "\(paint.color)" == "\(Color(0xFFD9D9D9))", plotTop == nil { plotTop = rect.top } }
    func drawRRect(_ rrect: RRect, _ paint: Paint) {}
    func drawDRRect(_ outer: RRect, _ inner: RRect, _ paint: Paint) {}
    func drawRSuperellipse(_ rsuperellipse: RSuperellipse, _ paint: Paint) {}
    func drawOval(_ rect: Rect, _ paint: Paint) {}
    func drawCircle(_ c: Offset, _ radius: Double, _ paint: Paint) {}
    func drawArc(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint) {}
    func drawPath(_ path: Path, _ paint: Paint) {}
    func drawImage(_ image: Image, _ offset: Offset, _ paint: Paint) {}
    func drawImageRect(_ image: Image, _ src: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawImageNine(_ image: Image, _ center: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawPicture(_ picture: any FlutterSwiftBridge.Picture) {}
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) {}
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}
