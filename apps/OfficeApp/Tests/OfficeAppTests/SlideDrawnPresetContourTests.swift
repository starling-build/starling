import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A shape drawn in the app paints every contour its preset strokes, as its gallery icon does:
/// a Smiley Face drawn from Insert > Shapes showed its eyes and outline but no mouth.
final class SlideDrawnPresetContourTests: XCTestCase {
    func testADrawnSmileyStrokesItsMouth() {
        let deck = DeckController()
        let s = deck.addShape(ShapePreset(rawValue: "smileyFace"))
        s.frame = Rect.fromLTWH(0, 0, 200, 200)
        let spy = StrokeSpyCanvas()
        SlidePainter.paintShape(s, spy, pxPerPt: 1, cache: SlideTextCache(), theme: deck.theme, text: false)

        // The icon's geometry: every contour it strokes, the mouth among them (stroked, not filled).
        let icon = PresetGeometry.geometry("smileyFace", width: 200 * Pptx.emu, height: 200 * Pptx.emu)!
        XCTAssertTrue(icon.subpaths.contains { $0.stroke && !$0.fill }, "the preset's mouth is a stroke-only contour")
        XCTAssertGreaterThanOrEqual(spy.strokes.count, icon.subpaths.filter(\.stroke).count, "each stroked contour is drawn")
        // The mouth: a stroke within the lower half, narrower than the face.
        let mouth = spy.strokes.first { $0.top > 100 && $0.width < 150 }
        XCTAssertNotNil(mouth, "the mouth is stroked: \(spy.strokes)")
    }

    func testADrawnRoundedRectangleStillTakesItsCornersAtTheNewSize() {
        let deck = DeckController()
        let s = deck.addShape(.roundRect)
        s.frame = Rect.fromLTWH(0, 0, 400, 100)
        let spy = StrokeSpyCanvas()
        SlidePainter.paintShape(s, spy, pxPerPt: 1, cache: SlideTextCache(), theme: deck.theme, text: false)
        XCTAssertEqual(spy.strokes.count, 1)
        XCTAssertEqual(spy.strokes.first?.width ?? 0, 400, accuracy: 0.5, "the outline spans the frame as it is now")
    }
}

/// Records the bounds of every stroked path.
private final class StrokeSpyCanvas: Canvas {
    var strokes: [Rect] = []
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
    func drawRect(_ rect: Rect, _ paint: Paint) { if paint.style == .stroke { strokes.append(rect) } }
    func drawRRect(_ rrect: RRect, _ paint: Paint) {}
    func drawDRRect(_ outer: RRect, _ inner: RRect, _ paint: Paint) {}
    func drawRSuperellipse(_ rsuperellipse: RSuperellipse, _ paint: Paint) {}
    func drawOval(_ rect: Rect, _ paint: Paint) {}
    func drawCircle(_ c: Offset, _ radius: Double, _ paint: Paint) {}
    func drawArc(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint) {}
    func drawPath(_ path: Path, _ paint: Paint) { if paint.style == .stroke { strokes.append(path.getBounds()) } }
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
