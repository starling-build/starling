import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// The UI harness's pointer helpers: click, double click and drag move real pointer events through the app.
final class PointerHelperTests: XCTestCase {
    private func canvas(_ deck: DeckController, mods: @escaping () -> KeyModifiers = { [] }) throws -> (WidgetTester, SlideCanvasState) {
        let c = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                            onShortcut: { _, _ in false }, modifiers: mods, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: c, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        return (ui, try XCTUnwrap(ui.state(SlideCanvasState.self)))
    }

    func testDraggingAShapeMovesIt() throws {
        let deck = DeckController()
        let a = deck.currentSlide.shapes[0]
        let (ui, state) = try canvas(deck)
        let before = a.frame
        // The middle of a text box edits; the frame's edge band grips and drags it.
        let from = state.screenPoint(Offset(a.frame.left + 1, a.frame.center.dy))
        ui.click(at: from)
        XCTAssertTrue(deck.selection.first === a, "click selects")
        ui.drag(from: from, to: Offset(from.dx + 60, from.dy + 40))
        let now = deck.currentSlide.shapes[0].frame
        XCTAssertGreaterThan(now.left, before.left, "moved right")
    }

    func testDoubleClickIsTwoClicks() throws {
        let deck = DeckController()
        let a = deck.currentSlide.shapes[0]
        let (ui, state) = try canvas(deck)
        ui.doubleClick(at: state.screenPoint(a.frame.center))
        XCTAssertTrue(deck.selection.first === a)
    }
}
