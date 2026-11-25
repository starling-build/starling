import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlideThumbSelectionTests: XCTestCase {
    private func deckOf(_ n: Int) -> DeckController {
        let deck = DeckController()
        while deck.slides.count < n { deck.addSlide() }
        return deck
    }

    func testRangeToggleDeleteHideMoveAndUndo() {
        let deck = deckOf(6)
        let ids = deck.slides.map(\.id)
        deck.selectSlide(1)
        deck.selectSlide(3, extend: true)
        XCTAssertEqual(deck.selectedSlides, [1, 2, 3])
        deck.selectSlide(5, toggle: true)
        XCTAssertEqual(deck.selectedSlides, [1, 2, 3, 5])
        deck.selectSlide(2, toggle: true)
        XCTAssertEqual(deck.selectedSlides, [1, 3, 5])
        // Hide all three, one undo step; again shows them.
        let before = deck.revision
        deck.toggleHiddenSelected()
        XCTAssertEqual(deck.slides.filter(\.hidden).count, 3)
        deck.undo()
        XCTAssertEqual(deck.slides.filter(\.hidden).count, 0)
        XCTAssertNotEqual(before, -1)
        // Move the block to the front, in order.
        deck.moveSelectedSlides(to: 0)
        XCTAssertEqual(deck.slides.map(\.id).prefix(3), [ids[1], ids[3], ids[5]][...])
        deck.undo()
        XCTAssertEqual(deck.slides.map(\.id), ids)
        // Delete the pick: three left, one undo step brings them back.
        deck.selectSlide(1); deck.selectSlide(3, toggle: true)
        deck.deleteSelectedSlides()
        XCTAssertEqual(deck.slides.count, 4)
        deck.undo()
        XCTAssertEqual(deck.slides.map(\.id), ids)
    }

    func testCopyCutPasteSlides() {
        let deck = deckOf(4)
        let ids = deck.slides.map(\.id)
        deck.selectSlide(0); deck.selectSlide(1, extend: true)
        deck.copySlides()
        deck.selectSlide(3)
        deck.pasteSlides()
        XCTAssertEqual(deck.slides.count, 6)
        XCTAssertEqual(Set(deck.slides.map(\.id)).count, 6)
        XCTAssertEqual(deck.selectedSlides, [4, 5])
        XCTAssertEqual(Array(deck.slides.map(\.id).prefix(4)), ids)
        // Cut takes them out; undo puts them back.
        deck.cutSlides()
        XCTAssertEqual(deck.slides.count, 4)
        deck.undo()
        XCTAssertEqual(deck.slides.count, 6)
        // The deck never ends up empty.
        deck.selectAllSlides()
        deck.deleteSelectedSlides()
        XCTAssertEqual(deck.slides.count, 1)
    }

    func testThumbnailClicksPickAndMenuHides() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        guard deck.slides.count > 1 else { throw XCTSkip("one-slide deck") }
        XCTAssertTrue(ui.tap(id: "slide.thumb.1"))
        XCTAssertEqual(deck.current, 1)
        XCTAssertEqual(deck.selectedSlides, [1])
        deck.selectSlide(0, extend: true)
        ui.pump()
        XCTAssertEqual(deck.selectedSlides, [0, 1])
        deck.toggleHiddenSelected()
        XCTAssertTrue(deck.slides[0].hidden && deck.slides[1].hidden)
    }

    func testSorterDragReordersOneSlideAndAGroup() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        let session = try XCTUnwrap(ui.state(SlidesShellState.self)?.session)
        let deck = try XCTUnwrap(session.deck)
        while deck.slides.count < 4 { _ = deck.addSlide() }
        session.onSlidesView?(true); ui.pump()
        let ids = deck.slides.map(\.id)
        let a = try XCTUnwrap(ui.centre(id: "slide.sorter.0")), b = try XCTUnwrap(ui.centre(id: "slide.sorter.2"))
        // Drag the first tile onto the third's place: it lands at index 2.
        ui.drag(from: a, to: b); ui.pump()
        XCTAssertEqual(Array(deck.slides.map(\.id).prefix(4)), [ids[1], ids[2], ids[0], ids[3]])
        XCTAssertTrue(session.slidesSorter)
        deck.undo()
        XCTAssertEqual(deck.slides.map(\.id), ids)
    }
}
