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
        XCTAssertTrue(ui.tap(text: "Paste")); drain(ui)
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1)
        let one = try XCTUnwrap(deck.selection.first)
        XCTAssertEqual(one.frame.left, left + 18, accuracy: 0.01)
        XCTAssertTrue(ui.tap(text: "Paste")); drain(ui)
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 2)
        XCTAssertEqual(try XCTUnwrap(deck.selection.first).frame.left, left + 36, accuracy: 0.01)
        // Cut is one undo step.
        deck.selectShapes([first]); ui.pump()
        XCTAssertTrue(ui.tap(text: "Cut"))
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1)
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 2)
    }

    private func ctrlV(_ ui: WidgetTester) {
        let main: Int64 = KeyModifiers.primary == .meta ? 0xFFE7 : 0xFFE3
        for (t, k) in [(KeyEventType.down, main), (.down, 0x76), (.up, 0x76), (.up, main)] {
            _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: t, physical: 0, logical: k, character: nil, synthesized: false))
        }
        ui.pump()
    }

    /// The clipboard's paste is read asynchronously and lands on the main queue.
    private func drain(_ ui: WidgetTester) {
        for _ in 0 ..< 3 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)); ui.pump() }
    }

    /// S-ED-1 step 2: a copy of shapes puts their text, a PNG of them and this deck's token on the system
    /// clipboard; Ctrl+V on the slide pastes the shapes back while the token is there, one undo step each.
    func testCopyPutsTextPictureAndShapesOnTheClipboard() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let withText = try XCTUnwrap(deck.currentSlide.shapes.first { !($0.text?.document.plainText() ?? "").isEmpty })
        let n = deck.currentSlide.shapes.count
        deck.selectShapes([withText]); ui.pump()
        XCTAssertTrue(deck.copyShapes())
        var got: ClipboardData?
        Clipboard.getData(Clipboard.kAll) { got = $0 }
        let data = try XCTUnwrap(got)
        XCTAssertEqual(data.text, withText.text?.document.plainText())
        let png = try XCTUnwrap(data.png)
        XCTAssertNotNil(ImageAttachment.pngPixelSize(png))
        XCTAssertNotNil(data.custom[DeckController.shapesMime])
        XCTAssertEqual(deck.pasteChoice(for: data), .shapes)
        // Through the keyboard, as a user pastes.
        deck.selectShapes([]); ui.pump()
        ctrlV(ui); drain(ui)
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1)
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.count, n)
    }

    /// Something copied since (here plain text, as from another app) wins over the deck's old shapes, and a picture
    /// copied elsewhere pastes as a picture shape.
    func testPasteFollowsWhatTheClipboardHoldsNow() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let first = try XCTUnwrap(deck.currentSlide.shapes.first)
        let n = deck.currentSlide.shapes.count
        deck.selectShapes([first]); ui.pump()
        XCTAssertTrue(deck.copyShapes())
        let picture = try XCTUnwrap(deck.selectionPng())
        Clipboard.setData(ClipboardData(text: "from elsewhere"))
        deck.selectShapes([]); ui.pump()
        ctrlV(ui); drain(ui)
        XCTAssertEqual(deck.currentSlide.shapes.count, n, "plain text with nothing being edited adds no shape")
        // Another deck's copy (a token not ours) and a picture alone both paste the picture.
        let foreign = ClipboardData(text: "words", png: picture, custom: [DeckController.shapesMime: Data("slides:x:1".utf8)])
        XCTAssertEqual(deck.pasteChoice(for: foreign), .picture(picture))
        XCTAssertEqual(deck.pasteChoice(for: ClipboardData(text: nil, png: picture)), .picture(picture))
        XCTAssertEqual(deck.pasteChoice(for: ClipboardData(text: "words", png: picture)), .text("words"))
        Clipboard.setData(ClipboardData(text: nil, png: picture))
        ctrlV(ui); drain(ui)
        XCTAssertEqual(deck.currentSlide.shapes.count, n + 1)
        let pasted = try XCTUnwrap(deck.selection.first)
        guard case .picture = pasted.kind else { return XCTFail("not a picture: \(pasted.kind)") }
        deck.undo()
        XCTAssertEqual(deck.currentSlide.shapes.count, n)
    }
}
