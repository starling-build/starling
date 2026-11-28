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

    /// A double-click on a name types a new one (Enter keeps it, one undo step); Hide All and Show All act on the slide.
    func testPaneRenamesAndHidesAll() throws {
        let deck = DeckController()
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SelectionPane(deck: deck, onClose: {}), title: "Test"))
        ui.pump()
        let first = deck.currentSlide.shapes[0]
        let old = first.name
        XCTAssertTrue(ui.tap(id: "selpane.row.0"))
        XCTAssertFalse(ui.has(id: "selpane.rename.0"), "one click selects, it does not rename")
        XCTAssertTrue(ui.tap(id: "selpane.row.0"))
        ui.pump()
        XCTAssertTrue(ui.has(id: "selpane.rename.0"), "a double-click opens the name for typing")
        ui.type("Logo")
        ui.press(.enter)
        ui.pump()
        XCTAssertEqual(first.name, "Logo", "the old name was selected, so typing replaced it")
        XCTAssertFalse(ui.has(id: "selpane.rename.0"))
        deck.undo()
        XCTAssertEqual(first.name, old, "one undo step")
        XCTAssertFalse(deck.renameShape(first, "   "), "a blank name is refused")
        XCTAssertEqual(first.name, old)
        XCTAssertTrue(ui.tap(id: "selpane.hideAll"))
        XCTAssertTrue(deck.currentSlide.shapes.allSatisfy(\.invisible), "Hide All hides every shape")
        XCTAssertTrue(deck.selection.isEmpty)
        XCTAssertTrue(ui.tap(id: "selpane.showAll"))
        XCTAssertTrue(deck.currentSlide.shapes.allSatisfy { !$0.invisible }, "Show All shows them again")
        deck.undo()
        XCTAssertTrue(deck.currentSlide.shapes.allSatisfy(\.invisible), "each is one undo step")
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
        // (A copy for a person to open, where the AMD box keeps them; the other tests write theirs the same way, only if the
        // folder is there: a Mac has no /data, and creating it failed the test on "volume is read only".)
        let dir = "/data/s/amd-6/ui-check"
        if FileManager.default.fileExists(atPath: dir) { try data.write(to: URL(fileURLWithPath: dir + "/flip-rotate.pptx")) }
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

    func testShiftHoldsALineEndToA45DegreeStep() {
        let f = Rect.fromLTRB(100, 100, 300, 200)
        let h = SlideCanvasState.lineEndSnapped(f, handle: 1, delta: Offset(10, 20))
        XCTAssertEqual(h.right - h.left, h.bottom - h.top, accuracy: 0.01, "29.7 degrees goes to 45")
        XCTAssertEqual(h.left, 100); XCTAssertEqual(h.top, 100)
        let flat = SlideCanvasState.lineEndSnapped(Rect.fromLTRB(0, 0, 100, 0), handle: 1, delta: Offset(0, 10))
        XCTAssertEqual(flat.bottom, 0, accuracy: 0.01, "a nearly flat line goes flat")
        XCTAssertEqual(flat.right, 100.5, accuracy: 0.6, "length kept")
        let diag = SlideCanvasState.lineEndSnapped(Rect.fromLTRB(0, 0, 100, 0), handle: 1, delta: Offset(-30, 80))
        XCTAssertEqual(diag.right - diag.left, diag.bottom - diag.top, accuracy: 0.01, "steep line goes to 45 degrees")
        let top = SlideCanvasState.lineEndSnapped(Rect.fromLTRB(0, 0, 100, 100), handle: 0, delta: Offset(30, 20))
        XCTAssertEqual(top.right - top.left, 100 - top.top, accuracy: 0.01)
    }

    func testShiftOnAnEdgeHandleKeepsTheProportions() {
        let f = Rect.fromLTWH(100, 100, 200, 100)
        // Handle 3 is the right edge: drag it 40 right; the height grows 20, half each way.
        let r = SlideCanvasState.resizedFrame(f, rotation: 0, handle: 3, delta: Offset(40, 0), keepAspect: true)
        XCTAssertEqual(r.width, 240, accuracy: 0.01)
        XCTAssertEqual(r.height, 120, accuracy: 0.01)
        XCTAssertEqual(r.left, 100, accuracy: 0.01)
        XCTAssertEqual(r.center.dy, f.center.dy, accuracy: 0.01)
    }

    /// A shape with its aspect lock on keeps its proportions when a corner is dragged.
    func testCornerDragHonoursTheAspectLock() throws {
        let (deck, a, _) = shapes()
        a.frame = Rect.fromLTWH(100, 100, 200, 100); a.aspectLock = true
        deck.selectShapes([a])
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { [] }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let state = try XCTUnwrap(ui.state(SlideCanvasState.self))
        let from = state.screenPoint(Offset(a.frame.right, a.frame.bottom))
        ui.drag(from: from, to: Offset(from.dx + 80, from.dy + 5))
        XCTAssertEqual(a.frame.width / a.frame.height, 2, accuracy: 0.01, "the corner drag held 2:1")
        XCTAssertGreaterThan(a.frame.width, 250)
        a.aspectLock = false
        let from2 = state.screenPoint(Offset(a.frame.right, a.frame.bottom))
        ui.drag(from: from2, to: Offset(from2.dx + 80, from2.dy + 5))
        XCTAssertNotEqual(a.frame.width / a.frame.height, 2, accuracy: 0.05, "unlocked, it goes free")
    }
}
