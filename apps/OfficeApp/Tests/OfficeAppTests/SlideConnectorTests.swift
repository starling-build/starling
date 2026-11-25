import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-SH-3: a line glued to a shape follows it.
final class SlideConnectorTests: XCTestCase {
    private func twoBoxesAndALine() -> (DeckController, SlideShape, SlideShape, SlideShape) {
        let deck = DeckController()
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(100, 100, 100, 60)
        let b = deck.addShape(.rect); b.frame = Rect.fromLTWH(400, 300, 100, 60)
        let l = deck.addShape(.line); l.frame = Rect.fromLTWH(0, 0, 10, 10)
        return (deck, a, b, l)
    }

    func testSitesAreOnTheSides() {
        let (_, a, _, _) = twoBoxesAndALine()
        XCTAssertEqual(a.connectionSite(0)?.dx ?? 0, 150, accuracy: 0.01)   // top
        XCTAssertEqual(a.connectionSite(0)?.dy ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(a.connectionSite(3)?.dx ?? 0, 200, accuracy: 0.01)   // right
        XCTAssertEqual(a.connectionSite(3)?.dy ?? 0, 130, accuracy: 0.01)
    }

    func testAGluedEndFollowsItsShape() {
        let (deck, a, b, l) = twoBoxesAndALine()
        deck.connect(l, start: true, to: a, site: 3)
        deck.connect(l, start: false, to: b, site: 1)
        XCTAssertEqual(l.lineStart.dx, 200, accuracy: 0.01)
        XCTAssertEqual(l.lineEndPoint.dx, 400, accuracy: 0.01)
        deck.selectShapes([b]); deck.nudgeSelection(dx: 50, dy: 20)
        XCTAssertEqual(l.lineEndPoint.dx, 450, accuracy: 0.01)
        XCTAssertEqual(l.lineEndPoint.dy, 350, accuracy: 0.01)
        XCTAssertEqual(l.lineStart.dx, 200, accuracy: 0.01)
        deck.undo()
        XCTAssertEqual(l.lineEndPoint.dx, 400, accuracy: 0.01)
    }

    func testMovingTheLineAloneUnglues() {
        let (deck, a, b, l) = twoBoxesAndALine()
        deck.connect(l, start: true, to: a, site: 3); deck.connect(l, start: false, to: b, site: 1)
        deck.selectShapes([l]); deck.nudgeSelection(dx: 5, dy: 0)
        XCTAssertNil(l.connStart); XCTAssertNil(l.connEnd)
    }

    func testDraggingAnEndNearASiteGluesIt() {
        let (deck, a, _, l) = twoBoxesAndALine()
        deck.dragLineEnd(l, handle: 1, frame: Rect.fromLTRB(0, 0, 203, 131), snap: true)
        XCTAssertEqual(l.connEnd, ShapeConn(shape: a.id, site: 3))
        XCTAssertEqual(l.lineEndPoint.dx, 200, accuracy: 0.01)
        deck.dragLineEnd(l, handle: 1, frame: Rect.fromLTRB(0, 0, 260, 131), snap: true)
        XCTAssertNil(l.connEnd)
    }

    func testDeletingTheShapeUnglues() {
        let (deck, a, b, l) = twoBoxesAndALine()
        deck.connect(l, start: false, to: b, site: 1)
        deck.selectShapes([b]); deck.deleteSelection()
        XCTAssertNil(l.connEnd); _ = a
    }

    func testGluedEndsSurviveSaving() throws {
        let (deck, a, b, l) = twoBoxesAndALine()
        deck.connect(l, start: true, to: a, site: 3); deck.connect(l, start: false, to: b, site: 1)
        let data = try Pptx.write(deck)
        let (state, theme, pkg) = try Pptx.read(data)
        let again = DeckController(); again.load(state, theme: theme, package: pkg)
        let shapes = again.currentSlide.shapes
        let ln = try XCTUnwrap(shapes.last(where: { $0.preset?.isLine == true }))
        let sa = try XCTUnwrap(shapes.first(where: { $0.preset?.rawValue == "rect" }))
        XCTAssertEqual(ln.connStart, ShapeConn(shape: sa.id, site: 3))
        XCTAssertNotNil(ln.connEnd)
        // Moving the box on the reopened deck still drags the line.
        again.selectShapes([shapes.filter({ $0.preset?.rawValue == "rect" }).last!])
        again.nudgeSelection(dx: 0, dy: 40)
        XCTAssertEqual(ln.lineEndPoint.dy, 370, accuracy: 0.01)
        // And a second save keeps the glue.
        let (st2, th2, pk2) = try Pptx.read(Pptx.write(again))
        let third = DeckController(); third.load(st2, theme: th2, package: pk2)
        XCTAssertNotNil(third.currentSlide.shapes.last(where: { $0.connStart != nil }))
    }

    /// On the canvas: dragging a selected line's end handle onto a box's side glues it, and moving the box then drags the end.
    func testDraggingTheHandleOnTheCanvasGluesTheEnd() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(300, 100, 120, 80)
        let l = deck.addShape(.line); l.frame = Rect.fromLTRB(100, 300, 200, 300)
        deck.selectShapes([l])
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { [] }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let state = try XCTUnwrap(ui.state(SlideCanvasState.self))
        // The line's end to a point 4 points short of the box's left side, middle.
        ui.drag(from: state.screenPoint(Offset(200, 300)), to: state.screenPoint(Offset(296, 140)), steps: 6, kind: .mouse)
        XCTAssertEqual(l.connEnd, ShapeConn(shape: a.id, site: 1))
        XCTAssertEqual(l.lineEndPoint.dx, 300, accuracy: 0.01)
        XCTAssertEqual(l.lineEndPoint.dy, 140, accuracy: 0.01)
        deck.selectShapes([a]); deck.nudgeSelection(dx: 0, dy: 30)
        XCTAssertEqual(l.lineEndPoint.dy, 170, accuracy: 0.01)
    }

    func testWritesThePowerPointCheckFile() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(60, 60, 160, 90)
        let b = deck.addShape(.ellipse); b.frame = Rect.fromLTWH(420, 280, 160, 90)
        let c = deck.addShape(ShapePreset(rawValue: "diamond")); c.frame = Rect.fromLTWH(120, 330, 160, 100)
        for (s, from, fs, to, ts) in [(0, a, 3, b, 2), (1, b, 4, c, 3)] {
            let l = deck.addShape(.line); _ = s
            deck.selectShapes([l]); deck.setOutlineWidth(2.5); deck.setLineEnd(start: false, kind: "triangle")
            deck.connect(l, start: true, to: from, site: fs); deck.connect(l, start: false, to: to, site: ts)
        }
        // The file as a user would leave it: the ellipse then moved.
        deck.selectShapes([b]); deck.nudgeSelection(dx: 30, dy: -40)
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/connectors.pptx"))
    }
}
