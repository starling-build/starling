import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A sheet line chart's legend placed in a box of its own, one entry to a row: Excel's print of ja-7d50affe6a (three such
/// legends, 8 and 9 pt) sets the entries as one column, keys at one x, each entry's first line at the top of its even slot,
/// and draws Excel's 19.2 pt line key.
final class SheetLegendColumnTests: XCTestCase {
    private func chart(legend: String? = nil) throws -> Chart {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func ser(_ i: Int, _ name: String) -> String {
            "<c:ser><c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/><c:tx><c:v>\(name)</c:v></c:tx><c:val><c:numRef><c:numCache><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>1</c:v></c:pt><c:pt idx=\"1\"><c:v>\(i + 2)</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>"
        }
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:lineChart><c:grouping val="standard"/>
        \(ser(0, "The shorter name of the three, on its own"))\(ser(1, "A much longer name than the first, wider than half the box"))\(ser(2, "A middling name, still too wide to share"))
        <c:axId val="1"/><c:axId val="2"/></c:lineChart><c:catAx><c:axId val="1"/><c:axPos val="b"/><c:crossAx val="2"/></c:catAx><c:valAx><c:axId val="2"/><c:axPos val="l"/><c:crossAx val="1"/></c:valAx></c:plotArea>
        \(legend ?? "<c:legend><c:legendPos val=\"b\"/><c:layout><c:manualLayout><c:xMode val=\"edge\"/><c:yMode val=\"edge\"/><c:x val=\"0.0157\"/><c:y val=\"0.6885\"/><c:w val=\"0.96\"/><c:h val=\"0.307\"/></c:manualLayout></c:layout><c:overlay val=\"0\"/></c:legend>")
        </c:chart></c:chartSpace>
        """
        var c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml.utf8))), color: { _ in nil }))
        c.onSheet = true
        return c
    }

    func testAPlacedLegendStandsAsOneColumnOnEvenSlots() throws {
        let canvas = KeySpyCanvas()
        let frame = Rect.fromLTWH(0, 0, 334, 207)
        ChartPainter.paint(try chart(), canvas, frame, pxPerPt: 0.75, theme: DeckTheme())
        let keys = canvas.keys.sorted { $0.y < $1.y }
        XCTAssertEqual(keys.count, 3)
        guard keys.count == 3 else { return }
        for key in keys { XCTAssertEqual(key.length, 19.2, accuracy: 0.05, "Excel's line key") }
        XCTAssertEqual(keys[1].x, keys[0].x, accuracy: 0.01, "keys at one x")
        XCTAssertEqual(keys[2].x, keys[0].x, accuracy: 0.01, "keys at one x")
        let boxTop = 0.6885 * 207, slot = 0.307 * 207 / 3
        XCTAssertEqual(keys[1].y - keys[0].y, slot, accuracy: 0.01)
        XCTAssertEqual(keys[2].y - keys[1].y, slot, accuracy: 0.01)
        XCTAssertLessThan(keys[0].y - boxTop, slot / 2 - 1, "the first line at the top of its slot, not in its middle")
    }

    /// Beside the plot the column takes the whole line key: Excel's print of WithChart ends the plot's gridlines 15.6 pt
    /// before the keys (382.7, keys from 398.3); the 7 pt key's room left ours 8.8 short of them.
    func testASideColumnLeavesThePlotRoomForTheLineKey() throws {
        let canvas = KeySpyCanvas()
        let legend = "<c:legend><c:legendPos val=\"r\"/><c:overlay val=\"0\"/></c:legend>"
        ChartPainter.paint(try chart(legend: legend), canvas, Rect.fromLTWH(0, 0, 900, 207), pxPerPt: 0.75, theme: DeckTheme())
        let keyX = try XCTUnwrap(canvas.keys.map { $0.x }.min())
        XCTAssertEqual(keyX - canvas.gridRight, 15.6, accuracy: 0.6)
    }
}

/// Records the short horizontal strokes (legend keys).
private final class KeySpyCanvas: Canvas {
    var keys: [(x: Double, y: Double, length: Double)] = []
    var gridRight = 0.0
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
        guard p1.dy == p2.dy else { return }
        let w = abs(p2.dx - p1.dx)
        if w < 30, p1.dy > 0.6 * 207 || p1.dx > 400 { keys.append((min(p1.dx, p2.dx), p1.dy, w)) }
        if w > 100 { gridRight = max(gridRight, p1.dx, p2.dx) }
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
