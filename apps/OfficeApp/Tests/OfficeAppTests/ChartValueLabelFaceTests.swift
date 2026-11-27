import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Where Excel sets a sheet chart's value-axis labels: in the face the axis's own txPr names, with the baseline its face's
/// measured drop below the gridline (Excel's print of lab axislbl: Arial 0.3233 em, the same at 9, 18 and 36 pt, grey or black).
final class ChartValueLabelFaceTests: XCTestCase {
    private func paint(face: String) throws -> LabelSpyCanvas {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        let pts = [10, 60, 35].enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\($0.element)</c:v></c:pt>" }.joined()
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>
        <c:ser><c:idx val="0"/><c:order val="0"/><c:val><c:numRef><c:numCache><c:ptCount val="3"/>\(pts)</c:numCache></c:numRef></c:val></c:ser>
        <c:axId val="1"/><c:axId val="2"/></c:barChart><c:catAx><c:axId val="1"/><c:axPos val="b"/><c:crossAx val="2"/></c:catAx>
        <c:valAx><c:axId val="2"/><c:scaling><c:orientation val="minMax"/><c:max val="100"/><c:min val="0"/></c:scaling><c:axPos val="l"/><c:majorGridlines/><c:majorUnit val="25"/>
        <c:txPr><a:bodyPr/><a:p><a:pPr><a:defRPr sz="1800"><a:latin typeface="\(face)"/></a:defRPr></a:pPr><a:endParaRPr lang="en-US"/></a:p></c:txPr><c:crossAx val="1"/></c:valAx>
        </c:plotArea></c:chart></c:chartSpace>
        """
        var c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        c.onSheet = true
        let canvas = LabelSpyCanvas()
        ChartPainter.paint(c, canvas, Rect.fromLTWH(0, 0, 400, 300), pxPerPt: 1, theme: DeckTheme())
        return canvas
    }

    /// The value labels: the first five paragraphs, "0" to "100" up the axis.
    private func labels(_ s: LabelSpyCanvas) -> [Offset] { Array(s.texts.prefix(5).map(\.at)) }

    /// Each label's baseline stands 0.3233 x 18 pt below its gridline. Our engine paints a line's baseline at its ascent
    /// rounded; the spy's paragraphs report no metrics, so the ascent is taken from the same text laid out here.
    func testAnArialValueAxisStandsItsBaselinesArialsDropBelowTheGridlines() throws {
        let s = try paint(face: "Arial")
        let grid = Array(s.lines.prefix(5))
        XCTAssertEqual(grid.count, 5)
        let tp = TextPainter(text: TextSpan(text: "100", style: Flutter.TextStyle(fontSize: 18, fontFamily: OfficeFonts.substitute("Arial"))), textDirection: .ltr)
        tp.layout()
        let ascent = try XCTUnwrap(tp.computeLineMetrics().first).ascent.rounded()
        for (y, at) in zip(grid, labels(s)) { XCTAssertEqual(at.dy + ascent, y + 0.3233 * 18, accuracy: 0.02) }
    }

    /// The labels are set in the face the axis names: right-aligned, "0" starts 2 digits further right than "100",
    /// 2 x 0.556 x 18 = 20.0 pt in Arial (Liberation Sans), where the default Calibri's would be 18.3.
    func testTheValueAxisIsSetInTheFaceItsTxPrNames() throws {
        let xs = labels(try paint(face: "Arial")).map(\.dx)
        XCTAssertEqual(xs.first! - xs.last!, 2 * 0.556 * 18, accuracy: 0.2)
    }
}

/// Records the long level lines (the gridlines) and every paragraph with where it was drawn.
private final class LabelSpyCanvas: Canvas {
    var lines: [Double] = []
    var texts: [(paragraph: any Paragraph, at: Offset)] = []
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
    func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) { if abs(p1.dy - p2.dy) < 0.01, abs(p1.dx - p2.dx) > 100 { lines.append(p1.dy) } }
    func drawPaint(_ paint: Paint) {}
    func drawRect(_ rect: Rect, _ paint: Paint) {}
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
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) { texts.append((paragraph, offset)) }
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}
