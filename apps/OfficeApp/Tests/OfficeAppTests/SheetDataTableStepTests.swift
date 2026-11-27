import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A sheet chart's data table does not shorten the value axis' step: Excel's print of chart-ChartDataTable (a line chart, data
/// 1 to 4, a three-row table and a legend under it in a 175.5 pt frame) runs its axis 0 to 4.5 by halves up an 80 pt plot.
final class SheetDataTableStepTests: XCTestCase {
    func testTheTableLeavesTheStepAsTheFrameGivesIt() throws {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func ser(_ i: Int, _ v: [Int]) -> String {
            let pts = v.enumerated().map { "<c:pt idx=\"\($0.offset)\"><c:v>\($0.element)</c:v></c:pt>" }.joined()
            return "<c:ser><c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/><c:cat><c:strRef><c:strCache><c:ptCount val=\"3\"/><c:pt idx=\"0\"><c:v>A</c:v></c:pt><c:pt idx=\"1\"><c:v>B</c:v></c:pt><c:pt idx=\"2\"><c:v>C</c:v></c:pt></c:strCache></c:strRef></c:cat><c:val><c:numRef><c:numCache><c:ptCount val=\"3\"/>\(pts)</c:numCache></c:numRef></c:val></c:ser>"
        }
        let nine = "<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz=\"900\"/></a:pPr></a:p></c:txPr>"
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:lineChart><c:grouping val="standard"/>
        \(ser(0, [1, 3, 4]))\(ser(1, [2, 4, 2]))\(ser(2, [3, 2, 2]))<c:axId val="1"/><c:axId val="2"/></c:lineChart>
        <c:catAx><c:axId val="1"/><c:axPos val="b"/>\(nine)<c:crossAx val="2"/></c:catAx>
        <c:valAx><c:axId val="2"/><c:axPos val="l"/><c:majorGridlines/>\(nine)<c:crossAx val="1"/></c:valAx>
        <c:dTable><c:showHorzBorder val="1"/><c:showVertBorder val="1"/><c:showOutline val="1"/><c:showKeys val="1"/>\(nine)</c:dTable></c:plotArea>
        <c:legend><c:legendPos val="b"/><c:overlay val="0"/>\(nine)</c:legend></c:chart></c:chartSpace>
        """
        var c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        c.onSheet = true
        let canvas = TableGridSpyCanvas()
        ChartPainter.paint(c, canvas, Rect.fromLTWH(0, 0, 196.9 * 0.75, 175.5 * 0.75), pxPerPt: 0.75, theme: DeckTheme())
        // (The gridlines are the evenly spaced run from the top; the table's rules follow under it.)
        let ys = Set(canvas.across.map { ($0 * 10).rounded() / 10 }).sorted()
        var n = min(2, ys.count)
        while n < ys.count, abs((ys[n] - ys[n - 1]) - (ys[1] - ys[0])) < 0.2 { n += 1 }
        // (Ten lines, 0 to 4.5; the table's rule made it six, 0 to 5 by ones.)
        XCTAssertEqual(n, 10, "\(ys)")
    }
}

private final class TableGridSpyCanvas: Canvas {
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
        if p1.dy == p2.dy, abs(p2.dx - p1.dx) > 60 { across.append(p1.dy) }
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
