import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-AR-1: Shift or Ctrl+click adds a shape to the selection or takes it out; a marquee with Shift adds.
final class SlideSelectionTests: XCTestCase {
    func testTogglingAndAddingToTheSelection() {
        let deck = DeckController()
        let a = deck.currentSlide.shapes[0], b = deck.currentSlide.shapes[1]
        deck.selectShapes([a])
        deck.toggleSelected(b)
        XCTAssertTrue(deck.selection.first === a && deck.selection.last === b, "joins, in click order")
        deck.toggleSelected(a)
        XCTAssertEqual(deck.selection.count, 1)
        XCTAssertTrue(deck.selection[0] === b, "leaves")
        deck.addToSelection([a, b])
        XCTAssertEqual(deck.selection.count, 2, "no shape twice")
    }

    /// The canvas on screen: a plain click selects one shape, a Shift click adds the other, a second Shift click removes it.
    func testShiftClickOnTheCanvasAddsAndRemoves() throws {
        let deck = DeckController()
        let a = deck.currentSlide.shapes[0], b = deck.currentSlide.shapes[1]
        var mods: KeyModifiers = []
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { mods }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        // Slide points to screen: the canvas centres the slide, so find the scale from where a title is hit.
        // The canvas learns its size in a post-frame callback.
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let state = try XCTUnwrap(ui.state(SlideCanvasState.self))
        func at(_ s: SlideShape) -> Offset { state.screenPoint(s.frame.center) }
        ui.tap(at: at(a))
        XCTAssertTrue(deck.selection.count == 1 && deck.selection[0] === a, "plain click selects one")
        ui.tap(at: at(b))
        XCTAssertTrue(deck.selection.count == 1 && deck.selection[0] === b, "plain click on the second shape")
        ui.tap(at: at(a))
        mods = [.shift]
        ui.tap(at: at(b))
        XCTAssertEqual(deck.selection.count, 2, "shift+click adds")
        ui.tap(at: at(b))
        XCTAssertTrue(deck.selection.count == 1 && deck.selection[0] === a, "shift+click again removes")
        mods = [.control]
        ui.tap(at: at(b))
        XCTAssertEqual(deck.selection.count, 2, "ctrl+click adds too")
    }
}

/// S-AR-1b: the Selection Pane lists the slide's shapes front first; its eye hides a shape and its arrows reorder.
final class SelectionPaneTests: XCTestCase {
    func testPaneHidesAndReordersAndUndoes() throws {
        let deck = DeckController()
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SelectionPane(deck: deck, onClose: {}), title: "Test"))
        ui.pump()
        let shapes = deck.currentSlide.shapes
        XCTAssertGreaterThanOrEqual(shapes.count, 2)
        let first = shapes[0]
        XCTAssertTrue(ui.tap(id: "selpane.eye.0"))
        XCTAssertTrue(first.invisible, "the eye hides the shape")
        deck.undo()
        XCTAssertFalse(first.invisible, "one undo step")
        XCTAssertTrue(ui.tap(id: "selpane.front.0"))
        XCTAssertTrue(deck.currentSlide.shapes[1] === first, "Bring forward moves it one step up the stack")
        XCTAssertTrue(ui.tap(id: "selpane.back.1"))
        XCTAssertTrue(deck.currentSlide.shapes[0] === first, "Send backward moves it back")
        XCTAssertTrue(ui.tap(id: "selpane.row.0"))
        XCTAssertTrue(deck.isSelected(first), "a row selects its shape")
    }
}

/// S-AR-2: modifier keys on drags, flip, rotate, nudge.
final class SlideArrangeTests: XCTestCase {
    private func shapes() -> (DeckController, SlideShape, SlideShape) {
        let deck = DeckController()
        deck.addShape(.rect); deck.addShape(.rect)
        let s = deck.currentSlide.shapes
        let a = s[s.count - 2], b = s[s.count - 1]
        a.frame = Rect.fromLTWH(100, 400, 80, 40)
        b.frame = Rect.fromLTWH(300, 400, 80, 40)
        return (deck, a, b)
    }

    func testFlipMirrorsAboutTheSelectionCentreAndUndoes() {
        let (deck, a, b) = shapes()
        a.rotation = 30
        deck.selectShapes([a, b])
        deck.flipSelection(horizontal: true)
        XCTAssertEqual(a.frame.left, 300, accuracy: 0.01)
        XCTAssertEqual(b.frame.left, 100, accuracy: 0.01)
        XCTAssertTrue(a.flipH && b.flipH && !a.flipV)
        XCTAssertEqual(a.rotation, 330, accuracy: 0.01)
        deck.flipSelection(horizontal: false)
        XCTAssertTrue(a.flipV)
        deck.undo(); deck.undo()
        XCTAssertFalse(a.flipH)
        XCTAssertEqual(a.frame.left, 100, accuracy: 0.01)
    }

    func testRotateTurnsEachShapeAndSwingsAGroupAboutItsCentre() {
        let (deck, a, b) = shapes()
        deck.selectShapes([a])
        deck.rotateSelection(by: -90)
        XCTAssertEqual(a.rotation, 270, accuracy: 0.01)
        XCTAssertEqual(a.frame.left, 100, accuracy: 0.01, "a lone shape turns in place")
        deck.selectShapes([a, b])
        let before = a.frame.center
        deck.rotateSelection(by: 90)
        XCTAssertEqual(a.rotation, 0, accuracy: 0.01)
        XCTAssertEqual(b.rotation, 90, accuracy: 0.01)
        XCTAssertNotEqual(a.frame.center.dy, before.dy, "the pair swings about its centre")
        XCTAssertEqual(a.frame.center.dx, b.frame.center.dx, accuracy: 0.01)
    }

    func testResizeKeepsAspectOrGrowsFromTheCentre() {
        let f = Rect.fromLTWH(100, 100, 80, 40)
        let k = SlideCanvasState.resizedFrame(f, rotation: 0, handle: 4, delta: Offset(40, 0), keepAspect: true)
        XCTAssertEqual(k.width / k.height, 2, accuracy: 0.001)
        let c = SlideCanvasState.resizedFrame(f, rotation: 0, handle: 4, delta: Offset(10, 5), fromCentre: true)
        XCTAssertEqual(c.center.dx, f.center.dx, accuracy: 0.001)
        XCTAssertEqual(c.width, 100, accuracy: 0.001)
        XCTAssertEqual(c.height, 50, accuracy: 0.001)
    }

    func testPptxKeepsFlipAndTurn() throws {
        let (deck, a, _) = shapes()
        deck.selectShapes([a])
        deck.flipSelection(horizontal: true)
        deck.rotateSelection(by: 90)
        let data = try Pptx.write(deck)
        let (state, _, _) = try Pptx.read(data)
        let r = try XCTUnwrap(state.slides[0].shapes.first { abs($0.frame.center.dx - a.frame.center.dx) < 0.5 && $0.flipH })
        XCTAssertEqual(r.rotation, a.rotation, accuracy: 0.01)
        try FileManager.default.createDirectory(atPath: "/data/s/amd-6/ui-check", withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: "/data/s/amd-6/ui-check/flip-rotate.pptx"))
    }

    /// Drags on the canvas with modifier keys held: Shift keeps one axis, Ctrl drags a copy.
    func testShiftLocksAxisAndCtrlDragsACopy() throws {
        let (deck, a, b) = shapes()
        var mods: KeyModifiers = []
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { mods }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let state = try XCTUnwrap(ui.state(SlideCanvasState.self))
        var pointer = 100
        func drag(from: Offset, to: Offset) {
            pointer += 1
            var hit = HitTestResult()
            _ = ui.renderView.hitTest(hit, position: from)
            func send(_ e: PointerEvent) {
                for entry in hit.path { entry.target.handleEvent(e.transformed(entry.transform), entry: entry) }
            }
            send(PointerDownEvent(pointer: pointer, position: from, buttons: kPrimaryButton))
            send(PointerMoveEvent(pointer: pointer, position: to, buttons: kPrimaryButton))
            send(PointerUpEvent(pointer: pointer, position: to))
            ui.pump()
        }
        let start = state.screenPoint(a.frame.center)
        let origin = a.frame
        mods = [.shift]
        drag(from: start, to: Offset(start.dx + 60, start.dy + 10))
        XCTAssertEqual(a.frame.top, origin.top, accuracy: 0.01, "Shift holds the drag to its longer axis")
        XCTAssertGreaterThan(a.frame.left, origin.left + 10)
        deck.selectShapes([b])
        ui.pump()
        let count = deck.currentSlide.shapes.count
        let bOrigin = b.frame
        mods = [.control]
        let s2 = state.screenPoint(b.frame.center)
        drag(from: s2, to: Offset(s2.dx + 60, s2.dy + 60))
        XCTAssertEqual(deck.currentSlide.shapes.count, count + 1, "Ctrl+drag leaves a copy behind")
        XCTAssertEqual(b.frame.left, bOrigin.left, accuracy: 0.01, "the original stays")
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.count, count, "one undo takes the copy back")
    }
}
