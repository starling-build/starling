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
