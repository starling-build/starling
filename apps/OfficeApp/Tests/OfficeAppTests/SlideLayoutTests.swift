import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// S-LA-1: a slide can move to any layout the file carries, and Reset puts the layout's frames back.
final class SlideLayoutTests: XCTestCase {
    private func corpus(_ name: String) throws -> Data {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/\(name)"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("\(name) not in the corpus cache") }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }
    private func load(_ data: Data) throws -> DeckController {
        let (state, theme, package) = try Pptx.read(data)
        let d = DeckController()
        d.load(state, theme: theme, package: package)
        return d
    }

    private func roundTrip(_ d: DeckController) throws -> DeckController {
        try load(try Pptx.write(d))
    }
    private func placeholders(_ d: DeckController, _ i: Int) -> [SlideShape] { d.slides[i].shapes.filter { $0.role != nil } }

    func testSwitchToAFileLayoutSurvivesSaveAndReset() throws {
        let d = try load(try corpus("45545_Comment.pptx"))
        let layouts = d.fileLayouts
        XCTAssertGreaterThanOrEqual(layouts.count, 5)
        let current = d.slides[0].layoutPart
        guard let target = layouts.first(where: { $0.part != current && $0.type == "titleOnly" }) ?? layouts.first(where: { $0.part != current })
        else { return XCTFail("no other layout") }
        let titleText = placeholders(d, 0).first { $0.role == .title || $0.role == .ctrTitle }?.text?.document.paragraphs.map { $0.text }.joined(separator: "\n") ?? ""
        XCTAssertFalse(titleText.isEmpty)
        let notes = d.slides[0].notes.document
        let count = d.slides.count
        XCTAssertTrue(d.applyFileLayout(target.part, to: 0))
        XCTAssertEqual(d.slides[0].layoutPart, target.part)
        // The title keeps its text; its frame is the layout's.
        let title = placeholders(d, 0).first { $0.role == .title || $0.role == .ctrTitle }
        XCTAssertEqual(title?.text?.document.paragraphs.map { $0.text }.joined(separator: "\n"), titleText)
        let frame = title!.frame
        // Undo puts the old layout back.
        d.undo()
        XCTAssertEqual(d.slides[0].layoutPart, current)
        XCTAssertTrue(d.applyFileLayout(target.part, to: 0))
        // Save and reopen.
        let again = try roundTrip(d)
        XCTAssertEqual(again.slides.count, count)
        XCTAssertEqual(again.slides[0].layoutPart, target.part)
        let t2 = placeholders(again, 0).first { $0.role == .title || $0.role == .ctrTitle }
        XCTAssertEqual(t2?.text?.document.paragraphs.map { $0.text }.joined(separator: "\n"), titleText)
        XCTAssertEqual(t2!.frame.left, frame.left, accuracy: 0.6)
        XCTAssertEqual(t2!.frame.top, frame.top, accuracy: 0.6)
        XCTAssertEqual(again.slides[0].notes.document.paragraphs.map { $0.text }.joined(separator: "\n"), notes.paragraphs.map { $0.text }.joined(separator: "\n"))
        XCTAssertEqual(again.fileLayouts.count, layouts.count)
        // Reset: move the title away, then put it back on the layout's frame.
        again.select(0); again.selectShapes([t2!]); again.nudgeSelection(dx: 40, dy: 30)
        XCTAssertNotEqual(t2!.frame.left, frame.left, accuracy: 0.6)
        XCTAssertTrue(again.applyFileLayout(target.part, to: 0))
        if let out = ProcessInfo.processInfo.environment["LAYOUT_CHECK_OUT"] { try Pptx.write(again).write(to: URL(fileURLWithPath: out)) }
        let t3 = placeholders(again, 0).first { $0.role == .title || $0.role == .ctrTitle }
        XCTAssertEqual(t3!.frame.left, frame.left, accuracy: 0.6)
        XCTAssertEqual(t3?.text?.document.paragraphs.map { $0.text }.joined(separator: "\n"), titleText)
    }
}

/// The Layout menu in the headless Slides shell.
final class SlideLayoutUITests: XCTestCase {
    func testLayoutMenuListsTheFilesLayoutsAndResetRestoresFrames() throws {
        let path = "/data/corpus-cache/test/corpus/pptx/decks/45545_Comment.pptx"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("deck not in the corpus cache") }
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: path, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1400, 800))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let before = deck.currentSlide.layoutPart
        XCTAssertTrue(ui.tap(text: "Layout"))
        let others = deck.fileLayouts.filter { $0.part != before }
        let n = try XCTUnwrap(others.first).index
        XCTAssertTrue(ui.has(id: "slides.layout.\(n)"))
        XCTAssertTrue(ui.tap(id: "slides.layout.\(n)"))
        XCTAssertEqual(deck.currentSlide.layoutPart, deck.fileLayouts[n].part)
        func titleShape() -> SlideShape? { deck.currentSlide.shapes.first { $0.role == .title || $0.role == .ctrTitle } }
        let title = try XCTUnwrap(titleShape())
        let left = title.frame.left
        deck.selectShapes([title]); deck.nudgeSelection(dx: 50, dy: 0)
        XCTAssertTrue(ui.tap(text: "Layout"))
        XCTAssertTrue(ui.tap(id: "slides.reset"))
        let again = try XCTUnwrap(titleShape())
        XCTAssertEqual(again.frame.left, left, accuracy: 0.6)
    }
}
