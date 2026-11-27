import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// A finger in the slide show (iPad): a tap and a swipe to the left go on, a swipe to the right goes back, and a hold raises
/// Back / End Show / Next, because a finger has no Escape, no right button and no arrow keys. A mouse keeps its own ways.
final class SlideShowTouchTests: XCTestCase {
    private func show(slides: Int = 4, onEnd: @escaping () -> Void = {}) throws -> (WidgetTester, SlideShowState) {
        let deck = DeckController()
        for _ in 1 ..< slides { _ = deck.addSlide() }
        deck.select(0)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlideShowView(deck: deck, images: SlideTextCache(), start: 0, onEnd: onEnd), title: "Test"),
                              size: Size(deck.slideSize.width, deck.slideSize.height))
        return (ui, try XCTUnwrap(ui.state(SlideShowState.self)))
    }

    func testTheStepAFingerTakesFollowsItsTravel() {
        let o = Offset(300, 200)
        XCTAssertEqual(SlideShowState.touchStep(from: o, to: o), .tap)
        XCTAssertEqual(SlideShowState.touchStep(from: o, to: Offset(305, 204)), .tap, "a finger drifts a little in a tap")
        XCTAssertEqual(SlideShowState.touchStep(from: o, to: Offset(200, 210)), .next, "a swipe to the left goes on")
        XCTAssertEqual(SlideShowState.touchStep(from: o, to: Offset(400, 190)), .previous, "a swipe to the right goes back")
        XCTAssertEqual(SlideShowState.touchStep(from: o, to: Offset(310, 340)), .none, "a drag downwards is neither")
        XCTAssertEqual(SlideShowState.touchStep(from: o, to: Offset(330, 200)), .none, "a short drag is neither")
    }

    func testATapGoesOnAndSwipesGoBothWays() throws {
        let (ui, state) = try show()
        ui.tap(at: Offset(50, 50), kind: .touch)
        XCTAssertEqual(state._at, 1, "a tap goes on")
        ui.drag(from: Offset(400, 300), to: Offset(150, 300), kind: .touch)
        XCTAssertEqual(state._at, 2, "a swipe to the left goes on")
        ui.drag(from: Offset(150, 300), to: Offset(400, 300), kind: .touch)
        XCTAssertEqual(state._at, 1, "a swipe to the right goes back; it used to go on, as the press alone decided")
        ui.drag(from: Offset(150, 300), to: Offset(400, 300), kind: .touch)
        XCTAssertEqual(state._at, 0)
    }

    func testAHoldRaisesTheControlsAndEndShowEndsTheShow() throws {
        var ended = false
        let (ui, state) = try show { ended = true }
        ui.tap(at: Offset(50, 50), kind: .touch)
        XCTAssertEqual(state._at, 1)
        XCTAssertFalse(state._controlsShown)
        ui.drag(from: Offset(50, 50), to: Offset(50, 50), steps: 0, kind: .touch, whileHeld: {
            RunLoop.current.run(until: Date().addingTimeInterval(TouchMenuTrigger.holdDelay + 0.3))
        })
        XCTAssertTrue(state._controlsShown, "a finger held still raises the controls")
        XCTAssertEqual(state._at, 1, "lifting the finger that raised them does not also go on")
        XCTAssertTrue(ui.has(text: "End Show"))
        ui.tap(text: "Back"); ui.pump()
        XCTAssertEqual(state._at, 0, "Back goes back one slide")
        XCTAssertTrue(state._controlsShown)
        ui.tap(text: "Next"); ui.pump()
        XCTAssertEqual(state._at, 1)
        ui.tap(text: "End Show"); ui.pump()
        XCTAssertTrue(ended, "End Show leaves the show without a keyboard")
    }

    func testATouchAwayFromTheControlsPutsThemAwayWithoutGoingOn() throws {
        let (ui, state) = try show()
        ui.drag(from: Offset(50, 50), to: Offset(50, 50), steps: 0, kind: .touch, whileHeld: {
            RunLoop.current.run(until: Date().addingTimeInterval(TouchMenuTrigger.holdDelay + 0.3))
        })
        XCTAssertTrue(state._controlsShown)
        ui.tap(at: Offset(50, 50), kind: .touch)
        XCTAssertFalse(state._controlsShown)
        XCTAssertEqual(state._at, 0, "the touch that puts them away is not a step")
        ui.tap(at: Offset(50, 50), kind: .touch)
        XCTAssertEqual(state._at, 1, "and the next one is")
    }

    func testAMouseKeepsItsWays() throws {
        let (ui, state) = try show()
        ui.tap(at: Offset(50, 50), kind: .mouse)
        XCTAssertEqual(state._at, 1, "a click goes on at the press")
        ui.tap(at: Offset(50, 50), buttons: kSecondaryMouseButton, kind: .mouse)
        XCTAssertEqual(state._at, 0, "a right click goes back")
        XCTAssertFalse(state._controlsShown)
    }
}
