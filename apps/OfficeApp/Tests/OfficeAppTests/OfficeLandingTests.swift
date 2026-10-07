import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class OfficeLandingTests: XCTestCase {
    func testWideAndPortraitAreEditableSixSlideDecks() throws {
        for portrait in [false, true] {
            let deck = OfficeLandingDeck.make(portrait: portrait)
            let bytes = try Pptx.write(deck)
            let (state, theme, package) = try Pptx.read(bytes)
            let reopened = DeckController()
            reopened.load(state, theme: theme, package: package)
            XCTAssertEqual(reopened.slides.count, 6)
            for (original, loaded) in zip(deck.slides.flatMap(\.shapes), reopened.slides.flatMap(\.shapes)) {
                if original.preset != nil { XCTAssertEqual(original.fill, loaded.fill, original.name) }
            }
            XCTAssertEqual(reopened.slideSize, Size(portrait ? 450 : 1280, 720))
            let words = reopened.slides.flatMap(\.shapes).compactMap { $0.text?.document.plainText() }.joined(separator: "\n")
            for required in ["Big ideas.", "Write something", "Your office.", "Open code.", "MEET SLIDES", "MEET SHEETS", "XLSX", "PPTX"] {
                XCTAssertTrue(words.contains(required), required)
            }
            XCTAssertTrue(reopened.slides.allSatisfy { $0.shapes.contains { $0.text != nil } })
        }
    }
}
