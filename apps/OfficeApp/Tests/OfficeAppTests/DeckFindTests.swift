import XCTest
import Flutter
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
