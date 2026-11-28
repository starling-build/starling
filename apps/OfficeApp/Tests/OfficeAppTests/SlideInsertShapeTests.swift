import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-SH-1: the shape gallery and drawing a shape by dragging.
final class SlideInsertShapeTests: XCTestCase {
    func testTheGalleryHasPowerPointsNineGroups() {
        XCTAssertEqual(ShapeGallery.groups.map(\.name), ["Lines", "Rectangles", "Basic Shapes", "Block Arrows",
            "Equation Shapes", "Flowchart", "Stars and Banners", "Callouts", "Action Buttons"])
        XCTAssertTrue(ShapeGallery.groups.allSatisfy { !$0.presets.isEmpty })
    }

    func testEveryGalleryShapeInsertsAndSurvivesSaving() throws {
        let deck = DeckController()
        var names: [String] = []
        for g in ShapeGallery.groups { for p in g.presets {
            let s = deck.placeInsert(p, from: Offset(50, 50), to: Offset(250, 170), keepProportions: false)
            names.append(p.rawValue == "straightConnector1" ? "line" : p.rawValue); XCTAssertEqual(s.frame.width, 200, accuracy: 0.01)
            _ = deck.addSlide()
        } }
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        var back: [String] = []
        for sl in state.slides { for sh in sl.shapes { if case .geometry(let p) = sh.kind { back.append(p.rawValue) } } }
        XCTAssertEqual(back, names)
    }

    func testAClickDropsAnInchSquareAndUndoRemovesIt() {
        let deck = DeckController()
        let n = deck.currentSlide.shapes.count
        let s = deck.placeInsert(.rect, from: Offset(100, 100), to: Offset(101, 100), keepProportions: false)
        XCTAssertEqual(s.frame, Rect.fromLTWH(100, 100, 72, 72))
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.count, n)
    }

    func testShiftKeepsASquareAndLinesAreUnfilled() {
        let deck = DeckController()
        let s = deck.placeInsert(.ellipse, from: Offset(100, 100), to: Offset(300, 150), keepProportions: true)
        XCTAssertEqual(s.frame.width, s.frame.height, accuracy: 0.01)
        let l = deck.placeInsert(.line, from: Offset(0, 0), to: Offset(200, 20), keepProportions: false)
        XCTAssertNil(l.fill)
        let a = deck.placeInsert(ShapePreset(rawValue: "straightConnector1"), from: Offset(0, 0), to: Offset(100, 0), keepProportions: false)
        XCTAssertEqual(a.tailEnd?.kind, "triangle")
    }

    func testDrawingOnTheCanvasMakesTheShapeWhereTheMouseWent() throws {
        let deck = DeckController()
        let n = deck.currentSlide.shapes.count
        deck.beginInsert(.ellipse)
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { [] }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let state = try XCTUnwrap(ui.state(SlideCanvasState.self))
        ui.drag(from: state.screenPoint(Offset(100, 100)), to: state.screenPoint(Offset(340, 220)), steps: 6, kind: .mouse)
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1)
        let s = try XCTUnwrap(deck.currentSlide.shapes.last)
        XCTAssertEqual(s.frame.left, 100, accuracy: 1); XCTAssertEqual(s.frame.width, 240, accuracy: 1)
        XCTAssertEqual(s.frame.height, 120, accuracy: 1)
        XCTAssertNil(deck.pendingInsert)
    }

    func testWritesThePowerPointCheckFile() throws {
        let deck = DeckController()
        var i = 0
        for g in ShapeGallery.groups { for p in g.presets {
            let col = Double(i % 8), row = Double((i / 8) % 5)
            _ = deck.placeInsert(p, from: Offset(30 + col * 112, 30 + row * 100), to: Offset(110 + col * 112, 100 + row * 100), keepProportions: false)
            i += 1
            if i % 40 == 0 { _ = deck.addSlide() }
        } }
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/shapes.pptx"))
    }
}

final class SlideShapeGridUITests: XCTestCase {
    /// Home > Shapes is one grid panel that fits a small window; a click on an icon picks that shape.
    func testShapesGalleryIsOneGridThatFitsTheWindow() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1200, 700))
        let session = try XCTUnwrap(ui.state(SlidesShellState.self)?.session)
        var picked: [String] = []
        session.onInsertShape = { picked.append($0.rawValue) }
        XCTAssertTrue(ui.tap(tip: "Insert a shape"))
        let grid = try XCTUnwrap(ui.elements().first { ($0.widget.key as? ValueKey<String>)?.value == "shape-grid-panel" }?
            .findRenderObject() as? RenderBox)
        let top = grid.localToGlobal(Offset(0, 0)).dy
        XCTAssertLessThanOrEqual(top + grid.size.height, 700)
        XCTAssertTrue(ui.has(tip: "Smiley Face"))
        XCTAssertTrue(ui.tap(id: "shape-grid-smileyFace"))
        XCTAssertEqual(picked, ["smileyFace"])
        XCTAssertFalse(ui.has(id: "shape-grid-smileyFace"))
    }
}
