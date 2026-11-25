import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Presenter view in the slide show: slide count, next slide, notes (with a type size), the timer, black screen, and the grid of every slide.
final class SlidePresenterTests: XCTestCase {
    private func presenter() throws -> (WidgetTester, SlideShowState, DeckController) {
        let deck = DeckController()
        _ = deck.addSlide()
        _ = deck.addSlide()
        deck.select(0)
        deck.currentSlide.notes.insertText("Say hello first")
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlideShowView(deck: deck, images: SlideTextCache(), start: 0, presenter: true, onEnd: {}), title: "Test"),
                              size: Size(1600, 900))
        return (ui, try XCTUnwrap(ui.state(SlideShowState.self)), deck)
    }

    func testPresenterShowsCountNotesAndNext() throws {
        let (ui, state, _) = try presenter()
        XCTAssertTrue(ui.has(text: "Slide 1 of 3"))
        XCTAssertTrue(ui.has(text: "Say hello first"))
        XCTAssertTrue(ui.has(text: "Next slide"))
        ui.tap(text: "Next slide  ▶"); ui.pump()
        XCTAssertEqual(state._at, 1)
        XCTAssertTrue(ui.has(text: "Slide 2 of 3"))
        XCTAssertTrue(ui.has(text: "No notes for this slide."))
    }

    func testNotesSizeBlackAndSeeAllSlides() throws {
        let (ui, state, _) = try presenter()
        XCTAssertEqual(state._notesSize, 22)
        ui.tap(text: "A+"); ui.pump()
        XCTAssertEqual(state._notesSize, 24)
        ui.tap(text: "A−"); ui.tap(text: "A−"); ui.pump()
        XCTAssertEqual(state._notesSize, 20)
        ui.tap(text: "Black"); ui.pump()
        XCTAssertTrue(ui.has(text: "Unblack"))
        ui.tap(text: "Unblack"); ui.pump()
        XCTAssertFalse(state._seeAll)
        ui.tap(text: "See all slides"); ui.pump()
        XCTAssertTrue(state._seeAll)
        XCTAssertTrue(ui.has(text: "Hide slides"))
        // A thumbnail's number jumps to that slide and closes the grid.
        let spot = try XCTUnwrap(ui.centre(ofText: "3"))
        ui.click(at: Offset(spot.dx, spot.dy - 30)); ui.pump()
        XCTAssertFalse(state._seeAll)
        XCTAssertEqual(state._at, 2)
    }
}
