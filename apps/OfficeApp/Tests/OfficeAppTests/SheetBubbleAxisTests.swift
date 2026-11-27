import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A sheet bubble chart's axes reach a fifth of their data's spread past each end, out to the next tick, with no headroom:
/// Excel's prints of lab bubble1 (338 by 149 pt plots) and chart-bubble_chart_simple.
final class SheetBubbleAxisTests: XCTestCase {
    private func chart(x: [Double]?, y: [Double]?, sizes: [Double]?) throws -> Chart {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func list(_ tag: String, _ v: [Double]?) -> String {
            guard let v else { return "" }
            let pts = v.enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\($0.element)</c:v></c:pt>" }.joined()
            return "<c:\(tag)><c:numRef><c:numCache><c:ptCount val=\"\(v.count)\"/>\(pts)</c:numCache></c:numRef></c:\(tag)>"
        }
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:bubbleChart><c:varyColors val="0"/>
        <c:ser><c:idx val="0"/><c:order val="0"/>\(list("xVal", x))\(list("yVal", y))\(list("bubbleSize", sizes))</c:ser>
        <c:axId val="1"/><c:axId val="2"/></c:bubbleChart>
        <c:valAx><c:axId val="1"/><c:axPos val="b"/><c:majorGridlines/><c:crossAx val="2"/></c:valAx>
        <c:valAx><c:axId val="2"/><c:axPos val="l"/><c:majorGridlines/><c:crossAx val="1"/></c:valAx></c:plotArea>
        </c:chart></c:chartSpace>
        """
        var c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        c.onSheet = true
        return c
    }

    private func grid(_ c: Chart) -> (across: Int, down: Int) {
        let canvas = GridSpyCanvas()
        ChartPainter.paint(c, canvas, Rect.fromLTWH(0, 0, 360, 216), pxPerPt: 0.75, theme: DeckTheme())
        return (Set(canvas.across.map { ($0 * 10).rounded() }).count, Set(canvas.down.map { ($0 * 10).rounded() }).count)
    }

    /// x and y = -3 to 4 both stand -5 to 6 by 1: twelve lines each way (the 5% headroom gave -4 to 5 on y, the scatter x
    /// axis' ten-step cap -6 to 6 by 2 on x).
    func testTheAxesReachAFifthOfTheSpreadPastTheData() throws {
        let v: [Double] = [-3, -1, 0, 2, 4]
        let g = grid(try chart(x: v, y: v, sizes: [10, 20, 30, 40, 50]))
        XCTAssertEqual(g.across, 12, "y -5 to 6 by 1")
        XCTAssertEqual(g.down, 12, "x -5 to 6 by 1")
    }

    /// One x value, 1: 0 to 1.2 by 0.2, seven lines down.
    func testOneValueReachesAFifthOfItselfPast() throws {
        XCTAssertEqual(grid(try chart(x: [1], y: [0], sizes: [1])).down, 7)
    }

    /// Sizes alone: no discs, but the frame and both axes, y -0.2 to 1.4 by 0.2 (nine lines), x = 1 to 5 on 0 to 6.
    func testSizesAloneStillStandTheAxes() throws {
        let g = grid(try chart(x: nil, y: nil, sizes: [10, 20, 30, 40, 50]))
        XCTAssertEqual(g.across, 9, "y -0.2 to 1.4 by 0.2")
        XCTAssertEqual(g.down, 7, "x 0 to 6 by 1")
    }
}

/// Records long horizontal and vertical strokes (gridlines) by their position.
private final class GridSpyCanvas: Canvas {
    var across: [Double] = []
    var down: [Double] = []
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
    func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) {
        if p1.dy == p2.dy, abs(p2.dx - p1.dx) > 100 { across.append(p1.dy) }
        if p1.dx == p2.dx, abs(p2.dy - p1.dy) > 50 { down.append(p1.dx) }
    }
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
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) {}
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}
