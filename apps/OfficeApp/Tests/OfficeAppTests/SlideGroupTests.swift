import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-AR-4: group and ungroup.
final class SlideGroupTests: XCTestCase {
    private func deckWithThree() -> (DeckController, [SlideShape]) {
        let deck = DeckController()
        _ = deck.addShape(.rect); _ = deck.addShape(.rect)
        return (deck, deck.currentSlide.shapes)
    }

    func testGroupUngroupAndUndo() {
        let (deck, s) = deckWithThree()
        XCTAssertGreaterThanOrEqual(s.count, 3)
        deck.selectShapes([s[0], s[2]])
        XCTAssertTrue(deck.canGroup)
        deck.groupSelection()
        XCTAssertNotNil(s[0].group)
        XCTAssertEqual(s[0].group?.key, s[2].group?.key)
        let idx = deck.currentSlide.shapes.firstIndex { $0 === s[0] }!
        XCTAssertTrue(deck.currentSlide.shapes[idx + 1] === s[2] || deck.currentSlide.shapes[idx - 1] === s[2], "members sit together")
        XCTAssertTrue(deck.canUngroup)
        deck.ungroupSelection()
        XCTAssertNil(s[0].group); XCTAssertNil(s[2].group)
        deck.undo()
        XCTAssertNotNil(s[0].group, "undo brings the group back")
    }

    func testDuplicateGivesTheCopiesAGroupOfTheirOwn() {
        let (deck, s) = deckWithThree()
        deck.selectShapes([s[0], s[1]]); deck.groupSelection()
        deck.duplicateSelection()
        let copies = deck.selection
        XCTAssertEqual(copies.count, 2)
        XCTAssertNotNil(copies[0].group)
        XCTAssertNotEqual(copies[0].group?.key, s[0].group?.key)
        XCTAssertEqual(copies[0].group?.key, copies[1].group?.key)
    }

    func testAClickSelectsTheGroupAndASecondClickTheMember() throws {
        let (deck, s) = deckWithThree()
        deck.selectShapes([s[0], s[1]]); deck.groupSelection()
        deck.selectShapes([])
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { [] }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let st = try XCTUnwrap(ui.state(SlideCanvasState.self))
        // Aim at a point that only s[0] covers.
        let p = st.screenPoint(s[0].frame.center)
        ui.tap(at: p)
        XCTAssertEqual(deck.selection.count, 2, "first click takes the whole group")
        ui.tap(at: p)
        XCTAssertEqual(deck.selection.count, 1, "second click takes the member")
    }

    func testANewGroupSurvivesSaving() throws {
        let (deck, s) = deckWithThree()
        deck.selectShapes([s[0], s[1]]); deck.groupSelection()
        let (state, _, _) = try Pptx.read(Pptx.write(deck))
        let shapes = state.slides[0].shapes
        let grouped = shapes.filter { $0.group != nil }
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].group?.key, grouped[1].group?.key)
    }

    /// Writes the file for the PowerPoint check: two shapes grouped, one other left alone, a copy of the group.
    func testWritesThePowerPointCheckFile() throws {
        let (deck, s) = deckWithThree()
        s[0].frame = Rect.fromLTWH(50, 50, 200, 100); s[1].frame = Rect.fromLTWH(300, 120, 200, 100)
        deck.selectShapes([s[0], s[1]]); deck.groupSelection(); deck.duplicateSelection()
        let dir = "/data/s/amd-6/ui-check"
        guard FileManager.default.fileExists(atPath: dir) else { return }
        try Pptx.write(deck).write(to: URL(fileURLWithPath: dir + "/group.pptx"))
    }
}
