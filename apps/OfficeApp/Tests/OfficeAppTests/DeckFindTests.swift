import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class DeckFindTests: XCTestCase {
    func testMatchesInReadingOrderAcrossShapesTablesAndNotes() {
        let deck = SlidesSample.make()
        let m = deck.matches("s")
        XCTAssertFalse(m.isEmpty)
        for (a, b) in zip(m, m.dropFirst()) {
            XCTAssertTrue(a.isBefore(b.slide, b.stop, b.selection.start), "sorted")
        }
        // Case-insensitive, and the table's cells and the notes are searched.
        XCTAssertEqual(deck.matches("WRITER").map(\.slide), [1, 7], "a bullet, then the table header")
        let notes = deck.matches("numbers")
        XCTAssertEqual(notes.count, 1)
        XCTAssertNil(notes[0].shapeId, "found in slide 1's notes")
    }

    func testReplaceEverywhereIsOneUndoStep() {
        let deck = SlidesSample.make()
        XCTAssertEqual(deck.replaceEverywhere("yes", with: "no"), 2)
        XCTAssertTrue(deck.matches("yes").isEmpty)
        XCTAssertEqual(deck.matches("no").filter { $0.slide == 7 }.count, 2)
        deck.undo()
        XCTAssertEqual(deck.matches("yes").count, 2)
        XCTAssertEqual(deck.replaceEverywhere("absent", with: "x"), 0)
    }
}

final class DeckFindPatternTests: XCTestCase {
    func testPatternOptionsReachTheDeckSearch() throws {
        let deck = SlidesSample.make()
        let plain = try TextPattern("writer", FindOptions())
        let cased = try TextPattern("writer", FindOptions(matchCase: true))
        XCTAssertEqual(deck.matches(plain).map(\.slide), deck.matches("WRITER").map(\.slide))
        XCTAssertTrue(deck.matches(cased).count < deck.matches(plain).count, "match case narrows the search")
        let wild = try TextPattern("y?s", FindOptions(mode: .wildcards))
        XCTAssertFalse(deck.matches(wild).isEmpty)
    }

    func testPatternReplaceEverywhereIsOneUndoStep() throws {
        let deck = SlidesSample.make()
        let p = try TextPattern("yes", FindOptions())
        let before = deck.matches(p).count
        XCTAssertGreaterThan(before, 0)
        XCTAssertEqual(deck.replaceEverywhere(p, with: "no"), before)
        XCTAssertTrue(deck.matches(p).isEmpty)
        deck.undo()
        XCTAssertEqual(deck.matches(p).count, before)
    }

    func testFindDialogAndSymbolPickerOpenFromTheShell() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        let session = try XCTUnwrap(ui.state(SlidesShellState.self)?.session)
        XCTAssertFalse(ui.has(text: "Find Previous"))
        session.onFind?(true); ui.pump()
        XCTAssertTrue(ui.has(text: "Find Previous"), "the shared dialog is up")
    }
}
