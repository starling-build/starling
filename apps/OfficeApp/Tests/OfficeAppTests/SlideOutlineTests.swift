import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
import OfficeText

final class SlideOutlineTests: XCTestCase {
    private func deckWith(_ rows: [(String, [String])]) -> DeckController {
        let deck = DeckController()
        while deck.slides.count < rows.count { _ = deck.addSlide() }
        for (i, row) in rows.enumerated() {
            let slide = deck.slides[i]
            let title = slide.shapes.first { $0.role == .title || $0.role == .ctrTitle }!
            title.text!.insertText(row.0)
            if let body = slide.shapes.first(where: { $0.role == .body || $0.role == .subTitle }) {
                body.text!.insertText(row.1.joined(separator: "\n"))
            }
        }
        return deck
    }

    func testEntriesListTitleAndBody() {
        let deck = deckWith([("One", ["a", "b"]), ("Two", [])])
        let e = deck.outlineEntries
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0].title, "One")
        XCTAssertEqual(e[0].body.map(\.text), ["a", "b"])
        XCTAssertEqual(e[0].body.map(\.level), [1, 1])
    }

    func testDocumentRoundTrip() {
        let entries = [OutlineEntry(title: "One", body: [OutlineLine(level: 1, text: "a"), OutlineLine(level: 2, text: "deep")]),
                       OutlineEntry(title: "Two")]
        XCTAssertEqual(Outline.entries(from: Outline.document(entries)), entries)
    }

    func testEditingOneTitleKeepsTheOtherSlides() {
        let deck = deckWith([("One", ["a"]), ("Two", ["b"]), ("Three", ["c"])])
        let ids = deck.slides.map(\.id)
        var e = deck.outlineEntries
        e[1].title = "Two!"
        deck.applyOutline(e)
        XCTAssertEqual(deck.slides.map(\.id), ids)
        XCTAssertEqual(deck.outlineEntries[1].title, "Two!")
    }

    func testANewTitleLineMakesANewSlideAndDeletingOneRemovesIt() {
        let deck = deckWith([("One", ["a"]), ("Two", ["b"])])
        let ids = deck.slides.map(\.id)
        var e = deck.outlineEntries
        e.insert(OutlineEntry(title: "Between", body: [OutlineLine(level: 1, text: "x")]), at: 1)
        deck.applyOutline(e)
        XCTAssertEqual(deck.slides.count, 3)
        XCTAssertEqual(deck.slides[0].id, ids[0]); XCTAssertEqual(deck.slides[2].id, ids[1])
        XCTAssertEqual(deck.outlineEntries[1], OutlineEntry(title: "Between", body: [OutlineLine(level: 1, text: "x")]))
        e.remove(at: 0)
        deck.applyOutline(e)
        XCTAssertEqual(deck.slides.map(\.id).last, ids[1])
        XCTAssertEqual(deck.slides.count, 2)
    }

    func testBodyLevelsReachTheSlideAndOneUndoStepRestores() {
        let deck = deckWith([("One", ["a", "b"])])
        var e = deck.outlineEntries
        e[0].body[1].level = 2
        deck.applyOutline(e)
        e[0].body[1].text = "bb"
        deck.applyOutline(e)   // more typing: the same undo step
        XCTAssertEqual(deck.outlineEntries[0].body.map(\.level), [1, 2])
        deck.undo()
        XCTAssertEqual(deck.outlineEntries[0].body.map(\.text), ["a", "b"])
        XCTAssertEqual(deck.outlineEntries[0].body.map(\.level), [1, 1])
    }

    func testOutlineViewReplacesTheThumbnailRailAndShowsTheTitles() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        let session = try XCTUnwrap(ui.state(SlidesShellState.self)?.session)
        let deck = try XCTUnwrap(session.deck)
        XCTAssertFalse(ui.has(id: "outline.pane"))
        _ = Outline.entries(from: Outline.document(deck.outlineEntries))
        session.onSlidesOutline?(); ui.pump()
        XCTAssertTrue(ui.has(id: "outline.pane"))
        XCTAssertTrue(session.slidesOutline)
        session.onSlidesOutline?(); ui.pump()
        XCTAssertFalse(ui.has(id: "outline.pane"))
    }
}
