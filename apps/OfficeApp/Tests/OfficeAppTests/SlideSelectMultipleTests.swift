import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// "Select Multiple": the touch stand-in for holding Shift or Ctrl on the slide canvas (a tap adds a shape to the selection or
/// takes it out).
final class SlideSelectMultipleTests: XCTestCase {
    private func canvas(_ deck: DeckController,
                        menu: ((Offset, SlideShape?) -> Void)? = nil) throws -> (WidgetTester, SlideCanvasState) {
        let c = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                            onShortcut: { _, _ in false }, spellChecker: nil, onContextMenu: menu)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: c, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        return (ui, try XCTUnwrap(ui.state(SlideCanvasState.self)))
    }

    private func twoShapes(_ deck: DeckController) -> (SlideShape, SlideShape) {
        let a = deck.addShape(.rect), b = deck.addShape(.rect)
        a.frame = Rect.fromLTWH(100, 100, 150, 100)
        b.frame = Rect.fromLTWH(400, 300, 150, 100)
        deck.selectShapes([])
        return (a, b)
    }

    func testSelectMultipleMakesATouchTapAddAndRemove() throws {
        let deck = DeckController()
        let (a, b) = twoShapes(deck)
        let (ui, state) = try canvas(deck)
        deck.setSelectMultiple(true)
        ui.tap(at: state.screenPoint(a.frame.center), kind: .touch)
        ui.tap(at: state.screenPoint(b.frame.center), kind: .touch)
        XCTAssertEqual(deck.selection.count, 2, "the second tap adds, it does not replace")
        ui.tap(at: state.screenPoint(a.frame.center), kind: .touch)
        XCTAssertTrue(deck.selection.count == 1 && deck.isSelected(b), "a tap on a selected shape takes it out")
    }

    func testWithoutTheModeATouchTapReplacesTheSelection() throws {
        let deck = DeckController()
        let (a, b) = twoShapes(deck)
        let (ui, state) = try canvas(deck)
        ui.tap(at: state.screenPoint(a.frame.center), kind: .touch)
        ui.tap(at: state.screenPoint(b.frame.center), kind: .touch)
        XCTAssertTrue(deck.selection.count == 1 && deck.isSelected(b))
    }

    func testTheModeKeepsTheSelectionWhenTheEmptySlideIsTapped() throws {
        let deck = DeckController()
        let (a, _) = twoShapes(deck)
        let (ui, state) = try canvas(deck)
        deck.setSelectMultiple(true)
        ui.tap(at: state.screenPoint(a.frame.center), kind: .touch)
        ui.tap(at: state.screenPoint(Offset(300, 500)), kind: .touch)
        XCTAssertEqual(deck.selection.count, 1, "an empty tap does not clear the selection while Select Multiple is on")
        deck.setSelectMultiple(false)
        ui.tap(at: state.screenPoint(Offset(300, 500)), kind: .touch)
        XCTAssertTrue(deck.selection.isEmpty, "and clears it again when it is off")
    }
}
