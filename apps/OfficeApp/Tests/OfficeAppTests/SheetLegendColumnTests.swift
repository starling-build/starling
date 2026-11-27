import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A sheet line chart's legend placed in a box of its own, one entry to a row: Excel's print of ja-7d50affe6a (three such
/// legends, 8 and 9 pt) sets the entries as one column, keys at one x, each entry's first line at the top of its even slot,
/// and draws Excel's 19.2 pt line key.
final class SheetLegendColumnTests: XCTestCase {
    private func chart(legend: String? = nil, names: [String]? = nil) throws -> Chart {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func ser(_ i: Int, _ name: String) -> String {
            "<c:ser><c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/><c:tx><c:v>\(name)</c:v></c:tx><c:val><c:numRef><c:numCache><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>1</c:v></c:pt><c:pt idx=\"1\"><c:v>\(i + 2)</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>"
        }
        let xml = """
        <c:chartSpace \(ns)><c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:lineChart><c:grouping val="standard"/>
        \((names ?? ["The shorter name of the three, on its own", "A much longer name than the first, wider than half the box", "A middling name, still too wide to share"]).enumerated().map { ser($0.offset, $0.element) }.joined())
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

extension SheetLegendColumnTests {
    /// An automatic legend at the bottom too wide for one row stands as a grid, not as centred rows: lab xl-legb, Excel's print of
    /// "Sales", "North region", "North region 2" in a 180 x 200 pt frame sets two columns 77.5 pt apart and the rows 16.9 apart
    /// (1.2213 x the size + 5.88), where ours centred each row of the flow and set them one text line apart.
    func testAnAutomaticBottomLegendTooWideForARowStandsAsAGrid() throws {
        let canvas = KeySpyCanvas()
        canvas.minY = 0.6 * 200; canvas.minLength = 10
        let legend = "<c:legend><c:legendPos val=\"b\"/><c:overlay val=\"0\"/></c:legend>"
        ChartPainter.paint(try chart(legend: legend, names: ["Sales", "North region", "North region 2"]), canvas, Rect.fromLTWH(0, 0, 180, 200), pxPerPt: 0.75, theme: DeckTheme())
        let keys = canvas.keys.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        XCTAssertEqual(keys.count, 3)
        guard keys.count == 3 else { return }
        XCTAssertEqual(keys[0].y, keys[1].y, accuracy: 0.01, "two entries in the first row")
        XCTAssertEqual(keys[2].x, keys[0].x, accuracy: 0.01, "the third under the first, in a column")
        XCTAssertGreaterThan(keys[1].x - keys[0].x, 40, "a second column")
        XCTAssertEqual(keys[2].y - keys[0].y, 1.2213 * 7.5 + 5.88, accuracy: 0.05, "Excel's row pitch: the line and 5.88 pt (16.9 at 9 pt; 10 pt here, at 0.75)")
    }
}

extension SheetLegendColumnTests {
    /// A row in a box the file places takes the side column's 21.2 pt key room, not the automatic row's 24.8: Excel's print of
    /// de-418ab5a23d's line chart (367 pt wide) sets "Section 1" to "Section 6" three to a row of its 0.55-wide box, keys 67.6 apart.
    /// (The box here is narrowed to 0.42 for the test face's narrower names: three entries fit it with 21.2 each, not with 24.8.)
    func testAPlacedSheetRowOfLineKeysKeepsThreeEntriesToARow() throws {
        let canvas = KeySpyCanvas()
        canvas.minY = 0.8 * 355; canvas.minLength = 10
        let legend = "<c:legend><c:legendPos val=\"b\"/><c:layout><c:manualLayout><c:xMode val=\"edge\"/><c:yMode val=\"edge\"/><c:x val=\"0.0309\"/><c:y val=\"0.8399\"/><c:w val=\"0.42\"/><c:h val=\"0.0922\"/></c:manualLayout></c:layout><c:overlay val=\"0\"/></c:legend>"
        ChartPainter.paint(try chart(legend: legend, names: (1...6).map { "Section \($0)" }), canvas, Rect.fromLTWH(0, 0, 367.2, 355.3), pxPerPt: 0.75, theme: DeckTheme())
        XCTAssertEqual(canvas.keys.count, 6)
        XCTAssertEqual(Set(canvas.keys.map { ($0.y * 10).rounded() }).count, 2, "two rows of three")
        for key in canvas.keys { XCTAssertEqual(key.length, 19.2, accuracy: 0.05) }
    }

    /// A line chart with a second line group on a value axis at the right: Excel's print of chart-axis_title_rotated draws the
    /// group's entry with the same 19.2 pt key at the same x as the others, and ends the plot where the 7 pt keys left ours
    /// (180.9): the axis's labels and title already stand off the legend, so the line key takes no more of the plot.
    func testASecondAxisLineEntryTakesTheLineKeyAndThePlotKeepsItsRoom() throws {
        let ns = "xmlns:c=\"http://schemas.openxmlformats.org/drawingml/2006/chart\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
        func ser(_ i: Int) -> String {
            "<c:ser><c:idx val=\"\(i)\"/><c:order val=\"\(i)\"/><c:tx><c:v>col\(i + 1)</c:v></c:tx><c:marker><c:symbol val=\"none\"/></c:marker><c:val><c:numRef><c:numCache><c:ptCount val=\"2\"/><c:pt idx=\"0\"><c:v>1</c:v></c:pt><c:pt idx=\"1\"><c:v>\(i + 2)</c:v></c:pt></c:numCache></c:numRef></c:val></c:ser>"
        }
        func xml(second: Bool) -> String {
            let group2 = second
                ? "<c:lineChart><c:grouping val=\"standard\"/>\(ser(2))<c:axId val=\"3\"/><c:axId val=\"4\"/></c:lineChart>"
                : ""
            let axes2 = second
                ? "<c:catAx><c:axId val=\"3\"/><c:delete val=\"1\"/><c:axPos val=\"b\"/><c:crossAx val=\"4\"/></c:catAx><c:valAx><c:axId val=\"4\"/><c:axPos val=\"r\"/><c:crossAx val=\"3\"/><c:crosses val=\"max\"/></c:valAx>"
                : ""
            return """
            <c:chartSpace \(ns)><c:chart><c:autoTitleDeleted val="1"/><c:plotArea><c:lineChart><c:grouping val="standard"/>\(ser(0))\(ser(1))\(second ? "" : ser(2))
            <c:axId val="1"/><c:axId val="2"/></c:lineChart>\(group2)<c:catAx><c:axId val="1"/><c:axPos val="b"/><c:crossAx val="2"/></c:catAx><c:valAx><c:axId val="2"/><c:axPos val="l"/><c:crossAx val="1"/></c:valAx>\(axes2)</c:plotArea>
            <c:legend><c:legendPos val="r"/><c:overlay val="0"/></c:legend></c:chart></c:chartSpace>
            """
        }
        func paint(second: Bool) throws -> KeySpyCanvas {
            var c = try XCTUnwrap(ChartXML.read(XCTUnwrap(XNode.parse(Data(xml(second: second).utf8))), color: { _ in nil }))
            c.onSheet = true
            if second { XCTAssertNotNil(c.secondValueAxis) }
            let canvas = KeySpyCanvas()
            canvas.minY = 0; canvas.minLength = 5
            ChartPainter.paint(c, canvas, Rect.fromLTWH(0, 0, 382, 208.5), pxPerPt: 0.75, theme: DeckTheme())
            canvas.keys = canvas.keys.filter { $0.x > 250 }
            return canvas
        }
        let two = try paint(second: true), one = try paint(second: false)
        XCTAssertEqual(two.keys.count, 3)
        for key in two.keys {
            XCTAssertEqual(key.length, 19.2, accuracy: 0.05, "the second group's entry has the line key too")
            XCTAssertEqual(key.x, two.keys[0].x, accuracy: 0.01)
        }
        // Without the second axis the column takes the line key's 21.2 pt where the 7 pt key and 4 pt gap stood (10.2 more);
        // with it the plot gives up only the axis's own room: the plot ends further from the keys by that room, not by it and 10.2.
        let oneGap = try XCTUnwrap(one.keys.map(\.x).min()) - one.gridRight
        let twoGap = try XCTUnwrap(two.keys.map(\.x).min()) - two.gridRight
        XCTAssertLessThan(twoGap - oneGap, 10.2 - 1, "the line key's extra room is not taken twice")
    }
}

/// Records the short horizontal strokes (legend keys).
private final class KeySpyCanvas: Canvas {
    var keys: [(x: Double, y: Double, length: Double)] = []
    var gridRight = 0.0
    var minY = 0.6 * 207, minLength = 0.0
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
        if w < 30, w >= minLength, p1.dy > minY || p1.dx > 400 { keys.append((min(p1.dx, p2.dx), p1.dy, w)) }
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
