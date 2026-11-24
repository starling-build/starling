import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlideNotesPageTests: XCTestCase {
    func testNotesPageViewToggles() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        XCTAssertFalse(deck.notesPageView)
        let revision = deck.revision
        XCTAssertTrue(ui.tap(id: "view.notesPage.status"))
        XCTAssertTrue(deck.notesPageView)
        ui.pump()
        // Looking at a page is not an edit.
        XCTAssertEqual(deck.revision, revision)
        XCTAssertTrue(ui.tap(tip: "Normal"))
        XCTAssertFalse(deck.notesPageView)
    }
}
