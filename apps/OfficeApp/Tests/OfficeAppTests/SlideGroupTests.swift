import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-AR-4: group and ungroup.
final class SlideGroupTests: XCTestCase {
    private func deckWithThree() -> (DeckController, [SlideShape]) {
        let deck = DeckController()
        _ = deck.addShape(.rect); _ = deck.addShape(.rect); _ = deck.addShape(.rect)
        return (deck, deck.currentSlide.shapes.filter { $0.role == nil })
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

    /// Regroup: after Ungroup and an edit, one former member selected brings the whole group back, name and all.
    func testRegroupBringsTheGroupBack() {
        let (deck, s) = deckWithThree()
        deck.selectShapes([s[0], s[1], s[2]]); deck.groupSelection()
        let name = s[0].group?.name
        deck.ungroupSelection()
        deck.selectShapes([s[1]])
        deck.setSize(width: 50, height: 50)
        XCTAssertTrue(deck.canRegroup)
        deck.regroupSelection()
        XCTAssertEqual(Set(s.map { $0.group?.key }).count, 1)
        XCTAssertNotNil(s[0].group)
        XCTAssertEqual(s[2].group?.name, name, "the group keeps its name")
        XCTAssertEqual(deck.selection.count, 3)
        XCTAssertFalse(deck.canRegroup)
        deck.undo()
        XCTAssertNil(s[0].group)
        XCTAssertTrue(deck.canRegroup, "undo puts back what Regroup needs")
    }

    func testRegroupNeedsTwoFormerMembersStillFree() {
        let (deck, s) = deckWithThree()
        deck.selectShapes([s[0], s[1]]); deck.groupSelection()
        deck.ungroupSelection()
        deck.selectShapes([s[1], s[2]]); deck.groupSelection()
        deck.selectShapes([s[0]])
        XCTAssertFalse(deck.canRegroup, "the other member is in a new group")
        deck.regroupSelection()
        XCTAssertNil(s[0].group)
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

    func testCopiesGetFreshNamesAndPlaceholdersRefuseGrouping() {
        let (deck, s) = deckWithThree()
        let placeholders = deck.currentSlide.shapes.filter { $0.role != nil }
        if placeholders.count >= 2 {
            deck.selectShapes(Array(placeholders.prefix(2)))
            XCTAssertFalse(deck.canGroup)
            XCTAssertNotNil(deck.groupRefusal)
        }
        let plain = deck.currentSlide.shapes.filter { $0.role == nil }
        XCTAssertGreaterThanOrEqual(plain.count, 2)
        deck.selectShapes(Array(plain.prefix(2))); deck.groupSelection()
        let before = Set(deck.currentSlide.shapes.map(\.name))
        deck.duplicateSelection()
        for c in deck.selection { XCTAssertFalse(before.contains(c.name), "\(c.name) is new") }
        XCTAssertNotEqual(deck.selection[0].group?.name, plain[0].group?.name)
        deck.copyShapes(); deck.pasteShapes()
        XCTAssertEqual(Set(deck.currentSlide.shapes.map(\.name)).count, deck.currentSlide.shapes.count, "no two shapes share a name")
        _ = s
    }

    func testAClickSelectsTheGroupAndASecondClickTheMember() throws {
        let (deck, s) = deckWithThree()
        s[0].frame = Rect.fromLTWH(50, 50, 200, 100); s[1].frame = Rect.fromLTWH(300, 300, 200, 100)
        s[2].frame = Rect.fromLTWH(600, 50, 100, 100)
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
