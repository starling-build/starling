import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// Reroute Connectors: a glued line moves to the pair of sites that makes it shortest.
final class SlideRerouteTests: XCTestCase {
    private func pair() -> (DeckController, SlideShape, SlideShape, SlideShape) {
        let deck = DeckController()
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(60, 100, 100, 60)
        let b = deck.addShape(.rect); b.frame = Rect.fromLTWH(400, 200, 100, 60)
        let l = deck.addShape(.line); l.frame = Rect.fromLTWH(110, 100, 340, 160)
        deck.connect(l, start: true, to: a, site: 0)   // top of A
        deck.connect(l, start: false, to: b, site: 2)  // bottom of B
        return (deck, a, b, l)
    }

    func testBothEndsPickTheNearestSitesAndUndoRestores() {
        let (deck, a, b, l) = pair()
        deck.selectShapes([l])
        deck.rerouteConnectors()
        XCTAssertEqual(l.connStart, ShapeConn(shape: a.id, site: 3))   // right of A
        XCTAssertEqual(l.connEnd, ShapeConn(shape: b.id, site: 1))     // left of B
        XCTAssertEqual(l.lineStart.dx, 160, accuracy: 0.01); XCTAssertEqual(l.lineEndPoint.dx, 400, accuracy: 0.01)
        deck.undo()
        XCTAssertEqual(l.connStart, ShapeConn(shape: a.id, site: 0)); XCTAssertEqual(l.connEnd, ShapeConn(shape: b.id, site: 2))
    }

    func testWithNothingSelectedEveryGluedLineOnTheSlideIsRerouted() {
        let (deck, a, _, l) = pair()
        deck.selectShapes([])
        XCTAssertEqual(deck.reroutableLines.count, 1)
        deck.rerouteConnectors()
        XCTAssertEqual(l.connStart, ShapeConn(shape: a.id, site: 3))
    }

    func testARerouteThatChangesNothingMakesNoUndoStep() {
        let (deck, _, _, l) = pair()
        deck.selectShapes([l]); deck.rerouteConnectors()
        let before = l.frame
        deck.rerouteConnectors(); deck.undo()   // the second call did nothing, so this undoes the first
        XCTAssertNotEqual(l.frame, before)
    }

    func testAnEndGluedOneSideKeepsTheFreeEnd() {
        let (deck, a, _, l) = pair()
        l.connEnd = nil
        deck.selectShapes([l]); deck.rerouteConnectors()
        XCTAssertEqual(l.connStart, ShapeConn(shape: a.id, site: 3))
        XCTAssertEqual(l.lineEndPoint.dx, 450, accuracy: 0.01)
    }

    func testTheArrangeMenuHasRerouteConnectors() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(2000, 800))   // (wide enough that the Arrange menu is not folded into the Drawing group)
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(60, 100, 100, 60)
        let b = deck.addShape(.rect); b.frame = Rect.fromLTWH(400, 200, 100, 60)
        let l = deck.addShape(.line); l.frame = Rect.fromLTWH(110, 100, 340, 160)
        deck.connect(l, start: true, to: a, site: 0); deck.connect(l, start: false, to: b, site: 2)
        deck.selectShapes([l]); ui.pump()
        XCTAssertTrue(ui.tap(text: "Arrange")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Reroute Connectors"))
        XCTAssertEqual(l.connStart, ShapeConn(shape: a.id, site: 3))
    }
}
