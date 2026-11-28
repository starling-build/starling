import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// The Shape Format tab: shown while a shape, placeholder or text box is selected (a picture gets Picture
/// Format instead), and its commands act on the selection in one undo step.
final class SlideShapeFormatTests: XCTestCase {
    private func shell() throws -> (WidgetTester, DeckController) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(2000, 800))
        return (ui, try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck))
    }

    func testWhichSelectionsShowTheTab() throws {
        let deck = DeckController()
        let title = try XCTUnwrap(deck.currentSlide.shapes.first { if case .placeholder = $0.kind { return true }; return false })
        XCTAssertFalse(deck.selectionHasShape)
        deck.selectShapes([title]); XCTAssertTrue(deck.selectionHasShape, "a placeholder")
        let box = deck.addShape(.rect); deck.selectShapes([box]); XCTAssertTrue(deck.selectionHasShape, "a drawn shape")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==")!
        let pic = deck.addPicture(ImageAttachment(data: png, width: 1, height: 1), naturalSize: Size(100, 100))
        deck.selectShapes([pic]); XCTAssertFalse(deck.selectionHasShape, "a picture has Picture Format")
    }

    func testSelectingAPlaceholderShowsShapeFormatAndDeselectingReturnsHome() throws {
        let (ui, deck) = try shell()
        XCTAssertFalse(ui.has(text: "Shape Format"))
        let title = try XCTUnwrap(deck.currentSlide.shapes.first)
        deck.selectShapes([title]); ui.pump()
        XCTAssertTrue(ui.tap(text: "Shape Format")); ui.pump()
        XCTAssertTrue(ui.has(text: "Shape Styles"))
        XCTAssertTrue(ui.has(text: "Bring Forward"))
        deck.selectShapes([]); ui.pump()
        XCTAssertFalse(ui.has(text: "Shape Format"))
        XCTAssertFalse(ui.has(text: "Shape Styles"), "the ribbon went back to Home")
    }

    func testTheSizeBoxAndArrangeButtonsUndoInOneStepAndSave() throws {
        let (ui, deck) = try shell()
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(100, 100, 120, 60)
        let b = deck.addShape(.rect); b.frame = Rect.fromLTWH(150, 120, 120, 60)
        deck.selectShapes([b]); ui.pump()
        XCTAssertTrue(ui.tap(text: "Shape Format")); ui.pump()
        XCTAssertTrue(ui.has(text: "60 pt"), "the height box shows the shape's height")
        XCTAssertTrue(ui.tap(tip: "Increase")); ui.pump()   // the first spinner is Height
        XCTAssertEqual(b.frame.height, 66)
        XCTAssertEqual(b.frame.width, 120)
        deck.undo(); ui.pump()
        XCTAssertEqual(b.frame.height, 60)
        XCTAssertTrue(deck.selection.first === b, "undo keeps the shape selected")
        XCTAssertTrue(ui.has(text: "Shape Styles"), "and the Shape Format tab stays open")
        let below = try XCTUnwrap(deck.currentSlide.shapes.firstIndex { $0 === b })
        XCTAssertTrue(ui.tap(text: "Send Backward")); ui.pump()
        XCTAssertEqual(deck.currentSlide.shapes.firstIndex { $0 === b }, below - 1)
        XCTAssertTrue(ui.tap(tip: "Increase")); ui.pump()
        let (state, theme, pkg) = try Pptx.read(try Pptx.write(deck))
        let again = DeckController(); again.load(state, theme: theme, package: pkg)
        let rects = again.slides[0].shapes.filter { $0.preset == .rect }
        XCTAssertEqual(rects.map(\.frame.left), [150, 100], "b now sits under a")
        XCTAssertEqual(rects[0].frame.height, 66, accuracy: 0.01)
    }
}
