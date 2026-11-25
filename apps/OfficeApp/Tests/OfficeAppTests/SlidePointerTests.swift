import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// Real pointer events (ui.click / ui.drag) through the slide canvas, for features that only had controller tests.
final class SlidePointerTests: XCTestCase {
    private func canvas(_ deck: DeckController, edited: @escaping (SlideShape?) -> Void = { _ in },
                        mods: @escaping () -> KeyModifiers = { [] }) throws -> (WidgetTester, SlideCanvasState) {
        let c = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: edited,
                            onShortcut: { _, _ in false }, modifiers: mods, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: c, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        return (ui, try XCTUnwrap(ui.state(SlideCanvasState.self)))
    }

    func testShiftDraggingALineEndHoldsA45DegreeStep() throws {
        let deck = DeckController()
        let line = deck.addShape(.line)
        line.frame = Rect.fromLTWH(200, 200, 200, 0)
        deck.selectShapes([line])
        var mods: KeyModifiers = []
        let (ui, state) = try canvas(deck, mods: { mods })
        mods = [.shift]
        let end = state.screenPoint(Offset(400, 200))
        // About 33 degrees off flat: nearer 45 than 0.
        ui.drag(from: end, to: Offset(end.dx + 10, end.dy + 140), modifiers: [.shift])
        let f = line.frame
        XCTAssertEqual(abs(f.right - f.left), abs(f.bottom - f.top), accuracy: 0.5, "the line stands at 45 degrees")
        XCTAssertGreaterThan(abs(f.bottom - f.top), 10)
    }

    func testTheMiddleOfASelectedTextBoxEditsAndItsEdgeDrags() throws {
        let deck = DeckController()
        let box = deck.addTextBox(at: Rect.fromLTWH(200, 200, 300, 100))
        var entered: SlideShape?
        let (ui, state) = try canvas(deck, edited: { entered = $0 })
        // The edge band drags the box.
        let edge = state.screenPoint(Offset(box.frame.left + 1, box.frame.center.dy))
        let before = box.frame
        ui.drag(from: edge, to: Offset(edge.dx + 50, edge.dy + 30))
        XCTAssertGreaterThan(box.frame.left, before.left + 5, "dragging the edge moves the box")
        XCTAssertNil(entered)
        // A click in the middle of the selected box starts typing.
        ui.click(at: state.screenPoint(box.frame.center))
        XCTAssertTrue(entered === box, "the middle enters the text")
    }

    func testCtrlDragOnTheCanvasLeavesACopy() throws {
        let deck = DeckController()
        let a = deck.addShape(.rect)
        deck.selectShapes([a])
        var mods: KeyModifiers = []
        let (ui, state) = try canvas(deck, mods: { mods })
        mods = [.control]
        let n = deck.currentSlide.shapes.count
        let p = state.screenPoint(a.frame.center)
        let origin = a.frame
        ui.drag(from: p, to: Offset(p.dx + 60, p.dy + 40), modifiers: [.control])
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1, "a copy is left behind")
        XCTAssertEqual(a.frame.left, origin.left, accuracy: 0.01, "the original stays")
    }
}
