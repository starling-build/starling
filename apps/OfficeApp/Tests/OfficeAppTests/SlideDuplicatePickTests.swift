import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// S-SL-1: Duplicate Slide copies every picked slide (Ctrl+D or the thumbnail menu), and Ctrl+M adds a slide.
final class SlideDuplicatePickTests: XCTestCase {
    private func titled(_ n: Int) -> DeckController {
        let deck = DeckController()
        while deck.slides.count < n { deck.addSlide() }
        for i in deck.slides.indices {
            deck.selectSlide(i)
            let box = deck.addTextBox(at: Rect.fromLTWH(20, 20, 200, 40))
            box.text?.load(RichDocument(paragraphs: [RichParagraph(text: "S\(i)")]))
        }
        return deck
    }

    private func names(_ deck: DeckController) -> [String] {
        deck.slides.map { s in s.shapes.compactMap { $0.text?.document.plainText() }.filter { !$0.isEmpty }.first ?? "" }
    }

    func testDuplicatePicksCopiesThemAllAfterTheLastOneUndoAndSave() throws {
        let deck = titled(4)
        deck.selectSlide(0)
        deck.selectSlide(2, toggle: true)
        XCTAssertEqual(deck.selectedSlides, [0, 2])
        deck.duplicateSelectedSlides()
        XCTAssertEqual(names(deck), ["S0", "S1", "S2", "S0", "S2", "S3"])
        XCTAssertEqual(deck.selectedSlides, [3, 4], "the copies become the pick")
        XCTAssertEqual(Set(deck.slides.map(\.id)).count, 6, "copies get their own ids")
        // Saved and read back in that order.
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        XCTAssertEqual(state.slides.map { s in s.shapes.compactMap { $0.text?.plainText() }.filter { !$0.isEmpty }.first ?? "" },
                       ["S0", "S1", "S2", "S0", "S2", "S3"])
        // One undo step.
        deck.undo()
        XCTAssertEqual(names(deck), ["S0", "S1", "S2", "S3"])
        // One picked slide: a copy right after it.
        deck.selectSlide(1)
        deck.duplicateSelectedSlides()
        XCTAssertEqual(names(deck), ["S0", "S1", "S1", "S2", "S3"])
        XCTAssertEqual(deck.current, 2)
    }

    func testCtrlDAndCtrlMInTheShell() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "T"),
                              size: Size(1280, 800))
        let state = try XCTUnwrap(ui.state(SlidesShellState.self))
        let deck = try XCTUnwrap(state.session.deck)
        func chord(_ k: UInt32) -> Bool {
            state._shortcut(KeyData(timeStamp: 0, type: .down, physical: 0, logical: Int64(k), character: nil, synthesized: false),
                            .primary)
        }
        let n = deck.slides.count
        XCTAssertTrue(chord(0x6D)) // Ctrl+M
        XCTAssertEqual(deck.slides.count, n + 1)
        deck.selectSlide(0, extend: true)
        let picked = deck.selectedSlides.count
        XCTAssertTrue(chord(0x64)) // Ctrl+D
        XCTAssertEqual(deck.slides.count, n + 1 + picked)
        deck.undo()
        XCTAssertEqual(deck.slides.count, n + 1)
    }
}
