import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-SH-5: shape effects (shadow, glow, reflection, soft edges, bevel).
final class SlideShapeEffectsTests: XCTestCase {
    private func reload(_ deck: DeckController) throws -> DeckController {
        let (state, theme, pkg) = try Pptx.read(Pptx.write(deck))
        let again = DeckController(); again.load(state, theme: theme, package: pkg)
        return again
    }

    private func newShape() -> (DeckController, SlideShape) {
        let deck = DeckController()
        let s = deck.addShape(.rect)
        deck.selectShapes([s])
        return (deck, s)
    }

    func testEachEffectIsOneUndoStep() {
        let (deck, s) = newShape()
        deck.setGlow(radius: 8, color: Color(0x66FF0000)); XCTAssertEqual(s.glowRadius, 8)
        deck.setSoftEdge(5); XCTAssertEqual(s.softEdge, 5)
        deck.setBevel(ShapeBevel(width: 6, height: 6, preset: "angle")); XCTAssertEqual(s.bevel?.preset, "angle")
        deck.undo(); XCTAssertNil(s.bevel)
        deck.undo(); XCTAssertNil(s.softEdge)
        deck.undo(); XCTAssertNil(s.glowRadius)
    }

    func testAllFiveSurviveSaving() throws {
        let (deck, s) = newShape()
        deck.setShadow(ShapeEffectPresets.shadow(angle: 45))
        deck.setGlow(radius: 11, color: ShapeEffectPresets.glowColor(Color(0xFF4472C4)))
        deck.setReflection(ShapeEffectPresets.reflection(dist: 4, endPos: 0.55, startAlpha: 0.5))
        deck.setSoftEdge(10)
        deck.setBevel(ShapeBevel(width: 6, height: 6, preset: "coolSlant"))
        let b = try XCTUnwrap(try reload(deck).currentSlide.shapes.last)
        XCTAssertNotNil(b.shadow); XCTAssertEqual(b.glowRadius ?? 0, 11, accuracy: 0.01)
        XCTAssertEqual(b.reflection?.dist ?? 0, 4, accuracy: 0.01)
        XCTAssertEqual(b.reflection?.endPos ?? 0, 0.55, accuracy: 0.001)
        XCTAssertEqual(b.softEdge ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(b.bevel?.preset, "coolSlant")
        _ = s
    }

    func testChangingTheShadowKeepsAFileShapesBevelAndGlow() throws {
        let (deck, _) = newShape()
        deck.setGlow(radius: 8, color: Color(0x66FF0000))
        deck.setBevel(ShapeBevel(width: 6, height: 6, preset: "circle"))
        let again = try reload(deck)
        let s = try XCTUnwrap(again.currentSlide.shapes.last)
        again.selectShapes([s])
        again.setShadow(ShapeEffectPresets.shadow(angle: 90))
        let b = try XCTUnwrap(try reload(again).currentSlide.shapes.last)
        XCTAssertNotNil(b.shadow); XCTAssertEqual(b.glowRadius ?? 0, 8, accuracy: 0.01)
        XCTAssertEqual(b.bevel?.preset, "circle")
    }

    func testNoEffectsClearsAllAndSwapsOnlyTheBevelOnAFileShape() throws {
        let (deck, _) = newShape()
        deck.setSoftEdge(5); deck.setBevel(ShapeBevel(width: 6, height: 6, preset: "circle"))
        let again = try reload(deck)
        let s = try XCTUnwrap(again.currentSlide.shapes.last)
        again.selectShapes([s])
        again.setBevel(ShapeBevel(width: 6, height: 6, preset: "divot"))
        var b = try XCTUnwrap(try reload(again).currentSlide.shapes.last)
        XCTAssertEqual(b.bevel?.preset, "divot"); XCTAssertEqual(b.softEdge ?? 0, 5, accuracy: 0.01)
        again.clearEffects()
        b = try XCTUnwrap(try reload(again).currentSlide.shapes.last)
        XCTAssertNil(b.bevel); XCTAssertNil(b.softEdge); XCTAssertNil(b.glowRadius); XCTAssertNil(b.shadow)
    }

    func testTheRibbonMenuAppliesAShadowGlowAndBevel() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let s = deck.addShape(.rect); deck.selectShapes([s]); ui.pump()
        XCTAssertTrue(ui.tap(text: "Shape Effects"))
        XCTAssertTrue(ui.tap(text: "Shadow")); ui.pump(); XCTAssertTrue(ui.tap(text: "Offset: Bottom Right"))
        XCTAssertNotNil(s.shadow)
        ui.pump(); if !ui.has(text: "Bevel") { XCTAssertTrue(ui.tap(text: "Shape Effects")); ui.pump() }
        XCTAssertTrue(ui.tap(text: "Bevel")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Slope"))
        XCTAssertEqual(s.bevel?.preset, "slope")
    }

    func testWritesThePowerPointCheckFile() throws {
        let deck = DeckController()
        var i = 0.0
        func put(_ name: String, _ f: (DeckController) -> Void) {
            let s = deck.addShape(.roundRect)
            let x = 60 + i.truncatingRemainder(dividingBy: 4) * 220, y = 60 + (i / 4).rounded(.down) * 150; s.frame = Rect.fromLTWH(x, y, 180, 110)
            s.name = name; deck.selectShapes([s]); f(deck); i += 1
        }
        for (k, sh) in ShapeEffectPresets.shadows.enumerated() where k % 3 == 0 { put(sh.name) { $0.setShadow(ShapeEffectPresets.shadow(angle: sh.angle)) } }
        for g in ShapeEffectPresets.glowSizes { put("Glow \(g)") { $0.setGlow(radius: g, color: ShapeEffectPresets.glowColor($0.theme.accents[2])) } }
        for r in [ShapeEffectPresets.reflections[0], ShapeEffectPresets.reflections[4], ShapeEffectPresets.reflections[8]] {
            put(r.name) { $0.setReflection(ShapeEffectPresets.reflection(dist: r.dist, endPos: r.endPos, startAlpha: r.startAlpha)) } }
        for r in ShapeEffectPresets.softEdgeSizes { put("Soft \(r)") { $0.setSoftEdge(r) } }
        for b in ShapeEffectPresets.bevels { put("Bevel \(b.name)") { $0.setBevel(ShapeBevel(width: 6, height: 6, preset: b.preset)) } }
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/effects.pptx"))
    }
}
