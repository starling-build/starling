import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// S-AR-3: Arrange > Align > Distribute Horizontally / Vertically, and the Align to Slide / Align Selected Objects choice.
final class SlideDistributeTests: XCTestCase {
    private func three(_ deck: DeckController) -> [SlideShape] {
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(100, 100, 50, 40)
        let b = deck.addShape(.rect); b.frame = Rect.fromLTWH(170, 200, 80, 40)
        let c = deck.addShape(.rect); c.frame = Rect.fromLTWH(500, 300, 60, 40)
        return [a, b, c]
    }

    func testDistributingAmongTheSelectionKeepsTheOuterShapesAndEvensTheGaps() {
        let deck = DeckController()
        let (s) = three(deck)
        deck.selectShapes([s[2], s[0], s[1]])   // selection order does not matter: left to right does
        XCTAssertTrue(deck.canDistribute)
        deck.distribute(horizontal: true)
        XCTAssertEqual(s[0].frame.left, 100)
        XCTAssertEqual(s[2].frame.left, 500)
        // 460 pt from 100 to 560, 190 pt of shapes: two gaps of 135.
        XCTAssertEqual(s[1].frame.left, 285, accuracy: 1e-9)
        XCTAssertEqual(s[1].frame.top, 200, "a horizontal distribute leaves the heights")
        deck.undo()
        XCTAssertEqual(s[1].frame.left, 170)
    }

    func testDistributingVerticallyOrdersByTheMiddles() {
        let deck = DeckController()
        let s = three(deck)
        s[1].frame = Rect.fromLTWH(170, 120, 80, 200)   // tall: its middle (220) is still between the others' (120, 320)
        deck.selectShapes(s)
        deck.distribute(horizontal: false)
        // 100 to 340 is 240 pt, 280 pt of shapes: the gaps are -20 each (the shapes overlap evenly).
        XCTAssertEqual(s[0].frame.top, 100)
        XCTAssertEqual(s[1].frame.top, 120, accuracy: 1e-9)
        XCTAssertEqual(s[2].frame.top, 300, accuracy: 1e-9)
    }

    func testTwoSelectedShapesCannotDistributeAmongThemselvesButCanAcrossTheSlide() {
        let deck = DeckController()
        let s = three(deck)
        deck.selectShapes([s[0], s[1]])
        XCTAssertFalse(deck.canDistribute)
        deck.distribute(horizontal: true)
        XCTAssertEqual(s[0].frame.left, 100, "nothing moves")
        deck.setAlignToSlide(true)
        XCTAssertTrue(deck.canDistribute)
        deck.distribute(horizontal: true)
        XCTAssertEqual(s[0].frame.left, 0)
        XCTAssertEqual(s[1].frame.right, deck.slideSize.width, accuracy: 1e-9)
    }

    func testOneShapeDistributesToTheMiddleOfTheSlide() {
        let deck = DeckController()
        let s = three(deck)
        deck.selectShapes([s[0]])
        XCTAssertTrue(deck.alignsBySlide)
        deck.distribute(horizontal: true)
        XCTAssertEqual(s[0].frame.center.dx, deck.slideSize.width / 2, accuracy: 1e-9)
    }

    func testAlignToSlideMovesSeveralShapesToTheSlidesEdge() {
        let deck = DeckController()
        let s = three(deck)
        deck.selectShapes(s)
        deck.align(.right)
        XCTAssertEqual(s[0].frame.right, 560, "among themselves: the rightmost edge")
        deck.undo()
        deck.selectShapes(s)   // (undo leaves nothing selected)
        deck.setAlignToSlide(true)
        deck.align(.right)
        for x in s { XCTAssertEqual(x.frame.right, deck.slideSize.width, accuracy: 1e-9) }
        deck.setAlignToSlide(false)
        XCTAssertFalse(deck.alignsBySlide)
    }

    func testADistributedSlideSavesAndReopensWithTheNewPlaces() throws {
        let deck = DeckController()
        let s = three(deck)
        deck.selectShapes(s); deck.distribute(horizontal: true)
        let (state, theme, pkg) = try Pptx.read(try Pptx.write(deck))
        let again = DeckController(); again.load(state, theme: theme, package: pkg)
        let lefts = again.slides[0].shapes.filter { $0.preset == .rect }.map(\.frame.left).sorted()
        XCTAssertEqual(lefts.count, 3)
        for (a, b) in zip(lefts, [100.0, 285, 500]) { XCTAssertEqual(a, b, accuracy: 0.01) }
    }

    func testTheArrangeMenuDistributesAndSwitchesToTheSlide() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(2000, 800))   // (wide enough that the Arrange menu is not folded into the Drawing group)
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let s = three(deck)
        deck.selectShapes(s); ui.pump()
        XCTAssertTrue(ui.tap(text: "Arrange")); ui.pump()
        XCTAssertTrue(ui.has(text: "✓ Align Selected Objects"))
        XCTAssertTrue(ui.tap(text: "Distribute Horizontally")); ui.pump()
        XCTAssertEqual(s[1].frame.left, 285, accuracy: 1e-9)
        XCTAssertTrue(ui.tap(text: "Arrange")); ui.pump()
        XCTAssertTrue(ui.tap(text: "Align to Slide")); ui.pump()
        XCTAssertTrue(deck.alignToSlide)
        XCTAssertTrue(ui.tap(text: "Arrange")); ui.pump()
        XCTAssertTrue(ui.has(text: "✓ Align to Slide"))
        XCTAssertTrue(ui.tap(text: "Align Left")); ui.pump()
        for x in s { XCTAssertEqual(x.frame.left, 0) }
    }
}
