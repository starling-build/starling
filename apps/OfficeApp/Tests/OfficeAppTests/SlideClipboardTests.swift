import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class SlideClipboardTests: XCTestCase {
    func testRibbonCopyCutPasteActOnShapesAndPastesCascade() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let first = try XCTUnwrap(deck.currentSlide.shapes.first)
        let n = deck.currentSlide.shapes.count
        let left = first.frame.left
        deck.selectShapes([first]); ui.pump()
        XCTAssertTrue(ui.tap(tip: "Copy") || ui.tap(text: "Copy"))
        XCTAssertTrue(deck.canPasteShapes)
        XCTAssertTrue(ui.tap(text: "Paste"))
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1)
        let one = try XCTUnwrap(deck.selection.first)
        XCTAssertEqual(one.frame.left, left + 18, accuracy: 0.01)
        XCTAssertTrue(ui.tap(text: "Paste"))
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 2)
        XCTAssertEqual(try XCTUnwrap(deck.selection.first).frame.left, left + 36, accuracy: 0.01)
        // Cut is one undo step.
        deck.selectShapes([first]); ui.pump()
        XCTAssertTrue(ui.tap(text: "Cut"))
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1)
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 2)
    }
}
