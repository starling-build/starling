import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class DeckControllerTests: XCTestCase {
    private func type(_ text: String, into shape: SlideShape?) {
        shape?.text?.insertText(text)
    }

    func testNewDeckIsOneTitleSlideAtWidescreen() {
        let deck = DeckController()
        XCTAssertEqual(deck.slides.count, 1)
        XCTAssertEqual(deck.currentSlide.layout, .titleSlide)
        XCTAssertEqual(deck.slideSize, Size(960, 540))
        XCTAssertEqual(deck.currentSlide.shapes.map(\.role), [.ctrTitle, .subTitle])
    }

    func testNewSlideFollowsPowerPointsChoiceOfLayout() {
        let deck = DeckController()
        deck.addSlide()
        XCTAssertEqual(deck.currentSlide.layout, .titleAndContent, "after a title slide")
        deck.applyLayout(.twoContent, to: deck.current)
        deck.addSlide()
        XCTAssertEqual(deck.currentSlide.layout, .twoContent, "otherwise the current layout repeats")
        XCTAssertEqual(deck.current, 2)
    }

    func testApplyLayoutCarriesTextByRole() {
        let deck = DeckController()
        deck.addSlide(.titleAndContent)
        let slide = deck.currentSlide
        type("Agenda", into: slide.shapes.first { $0.role == .title })
        type("First point", into: slide.shapes.first { $0.role == .body })
        deck.applyLayout(.twoContent, to: deck.current)
        XCTAssertEqual(slide.titleText, "Agenda")
        let bodies = slide.shapes.filter { $0.role == .body }
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0].text?.document.plainText(), "First point")
        XCTAssertTrue(bodies[1].isEmptyText)
        // To Title Only: the body has no slot, so it stays as it was.
        deck.applyLayout(.titleOnly, to: deck.current)
        XCTAssertEqual(slide.titleText, "Agenda")
        XCTAssertTrue(slide.shapes.contains { $0.text?.document.plainText() == "First point" })
        XCTAssertEqual(slide.shapes.filter { $0.isEmptyText }.count, 0, "empty leftovers are dropped")
    }

    func testDuplicateIsDeepAndDeleteKeepsOneSlide() {
        let deck = DeckController()
        type("Original", into: deck.currentSlide.shapes.first)
        deck.duplicateSlide(0)
        XCTAssertEqual(deck.slides.count, 2)
        XCTAssertEqual(deck.current, 1)
        type(" changed", into: deck.currentSlide.shapes.first)
        XCTAssertEqual(deck.slides[0].titleText, "Original", "the copy has its own text")
        deck.deleteSlide(1)
        deck.deleteSlide(0)
        XCTAssertEqual(deck.slides.count, 1, "the last slide cannot be deleted")
    }

    func testMoveAndHide() {
        let deck = DeckController()
        let first = deck.currentSlide
        deck.addSlide()
        deck.addSlide()
        deck.moveSlide(0, to: 2)
        XCTAssertTrue(deck.slides[2] === first)
        XCTAssertEqual(deck.current, 2)
        deck.toggleHidden(2)
        XCTAssertTrue(first.hidden)
    }

    func testSlideSizeScalesShapes() {
        let deck = DeckController()
        let title = deck.currentSlide.shapes[0]
        let before = title.frame
        deck.setSlideSize(Size(720, 540))
        XCTAssertEqual(title.frame.left, before.left * 0.75, accuracy: 0.001)
        XCTAssertEqual(title.frame.width, before.width * 0.75, accuracy: 0.001)
        XCTAssertEqual(title.frame.top, before.top, accuracy: 0.001)
        deck.addSlide()
        let body = deck.currentSlide.shapes.first { $0.role == .body }!
        XCTAssertLessThanOrEqual(body.frame.right, 720, "new slides are laid out for the new size")
    }

    func testTypingMovesTheRevisionAndCaretMovesDoNot() {
        let deck = DeckController()
        let title = deck.currentSlide.shapes[0].text!
        title.insertText("Hello")
        let r = deck.revision
        title.moveTo(.start, extend: false)
        XCTAssertEqual(deck.revision, r, "a caret move is not an edit")
        title.insertText("x")
        XCTAssertGreaterThan(deck.revision, r)
    }

    func testAnchoredTextSitsAtTheBottomOfTheTitle() {
        _ = OfficeFonts.register()
        let deck = DeckController()
        let title = deck.currentSlide.shapes[0]
        title.text?.insertText("Quarterly review")
        let cache = SlideTextCache()
        let px = 1.0
        let top = cache.textTop(title, pxPerPt: px)
        let h = cache.layout(title, pxPerPt: px)!.totalHeight
        XCTAssertEqual(top + h, (title.frame.height - title.insets.bottom) * px, accuracy: 0.5)
    }
}
