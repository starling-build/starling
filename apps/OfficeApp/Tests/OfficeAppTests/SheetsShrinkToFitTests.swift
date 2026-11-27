import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// X-FM-4 Shrink to fit: a cell's text too wide for it is drawn smaller to fit
/// on one line, read from and written to the file's `shrinkToFit`, and set from
/// the Format Cells dialog's Alignment tab.
final class SheetsShrinkToFitTests: XCTestCase {
    private func drawn(_ c: WorkbookController) -> [Double] {
        let g = SheetGridState(headless: c)
        g.printing = true
        let canvas = ShrinkSpyCanvas()
        g._paintRegion(canvas, rows: [0], cols: [0, 1, 2], clip: Rect.fromLTWH(-1000, -1000, 5000, 5000),
                       ws: c.sheet, book: c.book, merges: [], covered: [],
                       colors: .init(ink: Color(0xFF000000), paper: Color(0xFFFFFFFF), grid: Color(0xFF000000), showGrid: false))
        return canvas.widths
    }
    private func drawnHeights(_ c: WorkbookController) -> [Double] {
        _ = drawn(c); return ShrinkSpyCanvas.lastHeights
    }

    func testTooWideTextIsDrawnWithinItsCell() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "A heading that is far too long for one default column")])
        let col = SheetGridState(headless: c).cols.size(0)
        XCTAssertGreaterThan(try XCTUnwrap(drawn(c).max()), col)   // (it spills over B and C)
        c.setStyle({ $0.shrink = true }, range: CellRange("A1")!)
        XCTAssertLessThanOrEqual(try XCTUnwrap(drawn(c).max()), col)
    }

    func testTooWideNumberShowsItsDigitsNotHashes() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "123456789012345")])
        c.setStyle({ $0.numberFormat = "0" }, range: CellRange("A1")!)   // (General would fall back to 1.23E+14)
        let col = SheetGridState(headless: c).cols.size(0)
        let hashes = try XCTUnwrap(drawnHeights(c).max())   // (#### across the cell, at the full size)
        c.setStyle({ $0.shrink = true }, range: CellRange("A1")!)
        XCTAssertLessThanOrEqual(try XCTUnwrap(drawn(c).max()), col)
        XCTAssertLessThan(try XCTUnwrap(drawnHeights(c).max()), hashes * 0.9)   // the digits, in a smaller size
    }

    func testAWrappedCellWrapsInsteadOfShrinking() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "wrap me onto several lines please")])
        c.setStyle({ $0.wrap = true }, range: CellRange("A1")!)
        let wrapped = drawn(c)
        c.setStyle({ $0.shrink = true }, range: CellRange("A1")!)
        XCTAssertEqual(drawn(c), wrapped)
    }

    func testShrinkSurvivesAnXlsxRoundTrip() throws {
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "long text here"), (CellAddress("B1")!, "plain")])
        c.setStyle({ $0.shrink = true }, range: CellRange("A1")!)
        let back = WorkbookController(); back.load(try Xlsx.read(try Xlsx.write(c.book)))
        XCTAssertTrue(back.style(at: CellAddress("A1")!).shrink)
        XCTAssertFalse(back.style(at: CellAddress("B1")!).shrink)
    }

    func testFormatCellsDialogSetsShrinkAndUndoTakesItBack() {
        var got: CellFormatEdit?
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
            home: FormatCellsDialog(start: CellFormatEdit.Values(.plain), onApply: { got = $0 }, onClose: {}), title: "Test"), size: Size(1280, 800))
        addTeardownBlock { ui.replace(with: SizedBox(width: 1, height: 1)) }
        XCTAssertTrue(ui.tap(text: "Alignment"))
        XCTAssertTrue(ui.tap(id: "fc-shrink"))
        ui.press(.enter)
        XCTAssertEqual(got?.shrink, .set(true))
        XCTAssertEqual(got?.wrap, .keep)
        let c = WorkbookController()
        c.setInputs([(CellAddress("A1")!, "x")])
        c.formatCells(got ?? CellFormatEdit())
        XCTAssertTrue(c.style(at: CellAddress("A1")!).shrink)
        c.undo()
        XCTAssertFalse(c.style(at: CellAddress("A1")!).shrink)
    }
}

private final class ShrinkSpyCanvas: Canvas {
    var widths: [Double] = []
    static var lastHeights: [Double] = []
    init() { Self.lastHeights = [] }
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
    func getTransform() -> [Double] { [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1] }
    func clipRect(_ rect: Rect, clipOp: ClipOp, doAntiAlias: Bool) {}
    func clipRRect(_ rrect: RRect, doAntiAlias: Bool) {}
    func clipRSuperellipse(_ rsuperellipse: RSuperellipse, doAntiAlias: Bool) {}
    func clipPath(_ path: Path, doAntiAlias: Bool) {}
    func getLocalClipBounds() -> Rect { Rect.fromLTWH(0, 0, 1e6, 1e6) }
    func getDestinationClipBounds() -> Rect { Rect.fromLTWH(0, 0, 1e6, 1e6) }
    func drawColor(_ color: Color, _ blendMode: BlendMode) {}
    func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) {}
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
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) { widths.append(paragraph.longestLine); Self.lastHeights.append(paragraph.height) }
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}
