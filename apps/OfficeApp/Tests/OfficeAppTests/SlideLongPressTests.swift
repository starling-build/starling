import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// A finger held still on a shape or the empty slide opens the menu a right click does (the touch stand-in for it).
final class SlideLongPressTests: XCTestCase {
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

    func testALongPressOnAShapeOpensItsMenuAndDoesNotMoveIt() throws {
        let deck = DeckController()
        let (a, _) = twoShapes(deck)
        var opened: [(SlideShape?)] = []
        let (ui, state) = try canvas(deck) { _, shape in opened.append(shape) }
        let origin = a.frame
        let p = state.screenPoint(a.frame.center)
        ui.drag(from: p, to: p, steps: 0, kind: .touch, whileHeld: { RunLoop.main.run(until: Date().addingTimeInterval(0.8)) })
        XCTAssertEqual(opened.count, 1)
        XCTAssertTrue(opened.first.flatMap { $0 } === a, "the menu is the shape's")
        XCTAssertTrue(deck.isSelected(a), "the pressed shape is selected for the menu")
        XCTAssertEqual(a.frame.left, origin.left, accuracy: 0.01)
    }

    func testALongPressOnTheEmptySlideOpensTheSlideMenu() throws {
        let deck = DeckController()
        _ = twoShapes(deck)
        var opened: [(SlideShape?)] = []
        let (ui, state) = try canvas(deck) { _, shape in opened.append(shape) }
        let p = state.screenPoint(Offset(300, 500))
        ui.drag(from: p, to: p, steps: 0, kind: .touch, whileHeld: { RunLoop.main.run(until: Date().addingTimeInterval(0.8)) })
        XCTAssertEqual(opened.count, 1)
        if let first = opened.first { XCTAssertNil(first) }
    }

    func testAQuickTapAndADragOpenNoMenu() throws {
        let deck = DeckController()
        let (a, _) = twoShapes(deck)
        var opened = 0
        let (ui, state) = try canvas(deck) { _, _ in opened += 1 }
        let p = state.screenPoint(a.frame.center)
        ui.tap(at: p, kind: .touch)
        ui.drag(from: p, to: Offset(p.dx + 80, p.dy + 40), kind: .touch)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(opened, 0, "a stale long-press timer must not fire after the finger lifted")
    }

    func testAMouseHoldOpensNoMenu() throws {
        let deck = DeckController()
        let (a, _) = twoShapes(deck)
        var opened = 0
        let (ui, state) = try canvas(deck) { _, _ in opened += 1 }
        let p = state.screenPoint(a.frame.center)
        ui.drag(from: p, to: p, steps: 0, kind: .mouse, whileHeld: { RunLoop.main.run(until: Date().addingTimeInterval(0.8)) })
        XCTAssertEqual(opened, 0, "holding a mouse button is not a long press")
    }
}
