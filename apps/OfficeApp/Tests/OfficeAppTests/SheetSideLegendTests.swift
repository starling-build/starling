import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A sheet chart's right legend whose name is too long for one line (Excel's prints of lab xl-legw, 12 column charts
/// 180 to 588 pt wide with COM positions): the name wraps at a third of the chart, the legend box is its longest line
/// plus 16 pt but at most a third of the chart plus 3 pt, the box ends 10.84 pt inside the chart's right edge, and the
/// plot's inside ends about 11 pt before the box (w15h20L, 384 x 213.75: box 243..374, plot inside ends at 232.0).
final class SheetSideLegendTests: XCTestCase {
    private let longName = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum viverra, diam sed sollicitudin sagittis, ipsum augue sagittis nisl, in iaculis dolor urna in risus."

    private func chart() throws -> Chart {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>
        <c:ser><c:idx val="0"/><c:order val="0"/><c:tx><c:v>\(longName)</c:v></c:tx><c:val><c:numRef><c:numCache><c:ptCount val="1"/><c:pt idx="0"><c:v>10</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>
        <c:axId val="1"/><c:axId val="2"/></c:barChart><c:catAx><c:axId val="1"/><c:axPos val="b"/><c:crossAx val="2"/></c:catAx><c:valAx><c:axId val="2"/><c:axPos val="l"/><c:crossAx val="1"/></c:valAx>
        </c:plotArea><c:legend><c:legendPos val="r"/><c:overlay val="0"/><c:txPr><a:bodyPr/><a:p><a:pPr><a:defRPr sz="900"/></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr></c:legend></c:chart></c:chartSpace>
        """
        var c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        c.onSheet = true
        c.plotFill = Color(0xFFD9D9D9)
        return c
    }

    func testALongRightLegendNameWrapsInABoxCappedAtAThirdOfTheChart() throws {
        let c = try chart()
        XCTAssertEqual(c.legendPosition, "r")
        let canvas = LegendSpyCanvas()
        ChartPainter.paint(c, canvas, Rect.fromLTWH(0, 0, 384, 213.75), pxPerPt: 1, theme: DeckTheme())
        let plotRight = try XCTUnwrap(canvas.plotRight, "the plot keeps its room beside the legend")
        let textLeft = try XCTUnwrap(canvas.texts.filter { $0.dx > 200 }.map(\.dx).min())
        // The box is at most a third of the chart plus 3 pt wide and ends 10.84 pt inside it; the name starts 16.4 pt into it.
        let cap: Double = 384.0 / 3 + 3, boxRight: Double = 384 - 10.84
        XCTAssertGreaterThanOrEqual(textLeft, boxRight - cap + 16.4 - 0.01)
        XCTAssertLessThan(textLeft, boxRight - 60)
        // The plot stops short of the legend, a gap of the key and its spacing, not the name's full one-line width.
        XCTAssertGreaterThan(plotRight, 200)
        XCTAssertLessThan(plotRight, textLeft - 20)
    }
}

/// Records the plot's fill (D9D9D9) and where every paragraph is drawn.
private final class LegendSpyCanvas: Canvas {
    var plotRight: Double?
    var texts: [Offset] = []
    func save() {}
    func saveLayer(_ bounds: Rect?, _ paint: Paint) {}
    func restore() {}
    func restoreToCount(_ count: Int) {}
    func getSaveCount() -> Int { 1 }
    func translate(_ dx: Double, _ dy: Double) {}
    func scale(_ sx: Double, _ sy: Double?) {}
    func rotate(_ radians: Double) {}
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
    func drawRect(_ rect: Rect, _ paint: Paint) { if "\(paint.color)" == "\(Color(0xFFD9D9D9))", plotRight == nil { plotRight = rect.right } }
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
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) { texts.append(offset) }
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}
