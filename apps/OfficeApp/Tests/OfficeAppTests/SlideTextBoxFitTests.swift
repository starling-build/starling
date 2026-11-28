import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A new plain text box sizes itself to its text (spAutoFit), as PowerPoint's text boxes do: Keep Text Only into a
/// narrow place wraps and the box grows to hold every line, and typing more grows it again.
final class SlideTextBoxFitTests: XCTestCase {
    func testPastedTextBoxTakesTheHeightItsWrappedTextNeeds() throws {
        let deck = DeckController()
        let words = "Keep text only into a narrow box wraps onto several lines"
        let box = deck.addTextBox(text: words, at: Rect.fromLTWH(40, 40, 100, 30))
        let fitted = try XCTUnwrap(SlideTextCache.fittedHeight(box))
        XCTAssertEqual(box.frame.height, fitted)
        // Several lines at the box's size, plus its insets: taller than one line would need.
        let size = try XCTUnwrap(box.textTheme?.fontSize)
        XCTAssertGreaterThan(box.frame.height, 3 * size)
        XCTAssertEqual(box.frame.width, 100)
        XCTAssertTrue(DeckController.resizesToText(box))
        // Saved, it says it sizes to its text.
        let pkg = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let slide = String(decoding: try XCTUnwrap(pkg.parts["ppt/slides/slide1.xml"]), as: UTF8.self)
        XCTAssertTrue(slide.containsSubstring("<a:spAutoFit/>"), slide)
    }

    func testOneLineStaysOneLineHigh() throws {
        let deck = DeckController()
        let box = deck.addTextBox(text: "Short", at: nil)
        let size = try XCTUnwrap(box.textTheme?.fontSize)
        XCTAssertLessThan(box.frame.height, 2 * size + 7.2)
        XCTAssertGreaterThan(box.frame.height, size)
    }

    func testTypingMoreGrowsTheBoxInTheEditor() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, startBlank: true, onSwitch: { _, _ in }), title: "T"),
                              size: Size(1440, 932))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let box = deck.addTextBox(text: "One", at: Rect.fromLTWH(40, 40, 120, 30))
        ui.pump()
        let before = box.frame.height
        let text = try XCTUnwrap(box.text)
        var doc = text.document
        doc.paragraphs.append(contentsOf: (0 ..< 3).map { _ in RichParagraph(text: "another line", style: doc.paragraphs[0].style) })
        text.load(doc)
        ui.pump()
        XCTAssertGreaterThan(box.frame.height, before + 2 * (box.textTheme?.fontSize ?? 18))
        XCTAssertEqual(box.frame.height, SlideTextCache.fittedHeight(box))
    }
}
