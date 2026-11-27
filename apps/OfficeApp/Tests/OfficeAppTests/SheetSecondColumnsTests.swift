import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Two column groups, the second on a value axis of its own at the right: Excel's print of chart-testSecondaryAxis lays each
/// group across the whole slot, the second's columns over the first's, on a 0 to 4.5 scale of its own (ours set them side by
/// side on the left axis' 0 to 10, no right axis).
final class SheetSecondColumnsTests: XCTestCase {
    func testTheSecondGroupStandsOverTheFirstOnItsOwnScale() throws {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func group(_ i: Int, _ v: [Double], _ ax: (Int, Int)) -> String {
            let pts = v.enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\($0.element)</c:v></c:pt>" }.joined()
            return "<c:barChart><c:barDir val=\"col\"/><c:grouping val=\"clustered\"/><c:ser><c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/><c:val><c:numRef><c:numCache><c:ptCount val=\"3\"/>\(pts)</c:numCache></c:numRef></c:val></c:ser><c:gapWidth val=\"219\"/><c:overlap val=\"-27\"/><c:axId val=\"\(ax.0)\"/><c:axId val=\"\(ax.1)\"/></c:barChart>"
        }
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:autoTitleDeleted val="1"/><c:plotArea>\(group(0, [1, 7, 9], (1, 2)))\(group(1, [2, 4, 1], (3, 4)))
        <c:catAx><c:axId val="1"/><c:axPos val="b"/><c:crossAx val="2"/></c:catAx><c:valAx><c:axId val="2"/><c:axPos val="l"/><c:crossAx val="1"/></c:valAx>
        <c:valAx><c:axId val="4"/><c:axPos val="r"/><c:crossAx val="3"/><c:crosses val="max"/></c:valAx><c:catAx><c:axId val="3"/><c:delete val="1"/><c:axPos val="b"/><c:crossAx val="4"/></c:catAx></c:plotArea>
        </c:chart></c:chartSpace>
        """
        var c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        c.onSheet = true
        let canvas = ColumnSpyCanvas()
        ChartPainter.paint(c, canvas, Rect.fromLTWH(0, 0, 360, 216), pxPerPt: 0.75, theme: DeckTheme())
        XCTAssertEqual(canvas.columns.count, 6)
        guard canvas.columns.count == 6 else { return }
        let first = canvas.columns[0], second = canvas.columns[1]
        XCTAssertEqual(second.left, first.left, accuracy: 0.01, "the second group's column over the first's")
        XCTAssertEqual(second.width, first.width, accuracy: 0.01)
        // 1 of 10 against 2 of 4.5: the second column 4.44 times the first's height.
        XCTAssertEqual(second.height / first.height, 2 / 4.5 * 10, accuracy: 0.05)
    }
}

private final class ColumnSpyCanvas: Canvas {
    var columns: [Rect] = []
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
    func drawRect(_ rect: Rect, _ paint: Paint) { if rect.width > 5, rect.width < 100, rect.height > 1 { columns.append(rect) } }
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
