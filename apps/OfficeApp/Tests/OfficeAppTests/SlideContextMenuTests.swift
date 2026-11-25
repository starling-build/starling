import XCTest
import Flutter
import FlutterSwiftBridge
import OfficeText
@testable import OfficeApp

/// S-CM-1: the right-click menus on the slide and on the thumbnails.
final class SlideContextMenuTests: XCTestCase {
    private func shell() throws -> (WidgetTester, DeckController, SlideCanvasState) {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1280, 800))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        let canvas = try XCTUnwrap(ui.state(SlideCanvasState.self))
        return (ui, deck, canvas)
    }

    private func settle(_ ui: WidgetTester) {
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
    }

    func testRightClickOnAShapeSelectsItAndItsMenuActs() throws {
        let (ui, deck, canvas) = try shell()
        let a = deck.currentSlide.shapes[0]
        let before = deck.currentSlide.shapes.count
        // A point of the shape no other shape covers: the title's height depends on the platform's font (188 pt on macOS, so
        // its centre sat on the stack of shapes below it), and a click on a covered point selects the one on top.
        var spot = a.frame.center
        search: for y in stride(from: a.frame.top + 2, to: a.frame.bottom - 2, by: 2) {
            for x in stride(from: a.frame.left + 2, to: a.frame.right - 2, by: 8)
            where !deck.currentSlide.shapes.dropFirst().contains(where: { $0.frame.contains(Offset(x, y)) }) {
                spot = Offset(x, y)
                break search
            }
        }
        ui.tap(at: canvas.screenPoint(spot), buttons: kSecondaryMouseButton)
        XCTAssertTrue(deck.selection.count == 1 && deck.selection[0] === a, "right-click selects the shape")
        settle(ui)
        XCTAssertTrue(ui.has(text: "Align Bottom"), "the shape menu is open")
        XCTAssertTrue(ui.tap(text: "Align Bottom"))
        settle(ui)
        XCTAssertEqual(a.frame.bottom, deck.slideSize.height, accuracy: 0.01)
        XCTAssertFalse(ui.has(text: "Align Bottom"), "choosing a row closes the menu")
        _ = before
    }

    func testRightClickOnTheEmptySlideOffersSelectAllAndPaste() throws {
        let (ui, deck, canvas) = try shell()
        deck.selectShapes([deck.currentSlide.shapes[0]])
        func count(_ label: String) -> Int {
            ui.elements().filter { ($0.widget as? Text)?.data == label }.count
        }
        let before = count("Paste")
        ui.tap(at: canvas.screenPoint(Offset(-8, -8)), buttons: kSecondaryMouseButton)
        settle(ui)
        XCTAssertTrue(deck.selection.isEmpty, "a click on the empty slide clears the selection")
        XCTAssertEqual(count("Paste"), before + 1, "the slide menu is open")
        // The menu is the topmost layer, so its row is the last "Select All" in the tree.
        let row = try XCTUnwrap(ui.elements().last { ($0.widget as? Text)?.data == "Select All" })
        let box = try XCTUnwrap(row.findRenderObject() as? RenderBox)
        ui.tap(at: box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2)))
        settle(ui)
        XCTAssertEqual(deck.selection.count, deck.currentSlide.shapes.count)
    }

    func testTheShapeMenuGroupsAndUngroups() throws {
        let (ui, deck, canvas) = try shell()
        let a = deck.addShape(.rect), b = deck.addShape(.rect)
        a.frame = Rect.fromLTWH(20, 440, 200, 60); b.frame = Rect.fromLTWH(300, 440, 200, 60)
        deck.selectShapes([a, b])
        settle(ui)
        func tapLast(_ label: String) throws {
            let row = try XCTUnwrap(ui.elements().last { ($0.widget as? Text)?.data == label })
            let box = try XCTUnwrap(row.findRenderObject() as? RenderBox)
            ui.tap(at: box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2)))
            settle(ui)
        }
        ui.tap(at: canvas.screenPoint(a.frame.center), buttons: kSecondaryMouseButton)
        settle(ui)
        XCTAssertTrue(ui.has(text: "Align Left"), "menu open: \(ui.texts().suffix(25))")
        try tapLast("Group")
        XCTAssertNotNil(a.group); XCTAssertEqual(a.group?.key, b.group?.key)
        ui.tap(at: canvas.screenPoint(a.frame.center), buttons: kSecondaryMouseButton)
        settle(ui)
        try tapLast("Ungroup")
        XCTAssertNil(a.group)
    }

    /// S-AR-2: the shape menu flips and turns the selection.
    func testTheShapeMenuFlipsAndRotates() throws {
        let (ui, deck, canvas) = try shell()
        let a = deck.addShape(.rect)
        a.frame = Rect.fromLTWH(100, 440, 80, 40)
        deck.selectShapes([a])
        settle(ui)
        func tapLast(_ label: String) throws {
            let row = try XCTUnwrap(ui.elements().last { ($0.widget as? Text)?.data == label })
            let box = try XCTUnwrap(row.findRenderObject() as? RenderBox)
            ui.tap(at: box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2)))
            settle(ui)
        }
        ui.tap(at: canvas.screenPoint(a.frame.center), buttons: kSecondaryMouseButton)
        settle(ui)
        try tapLast("Flip Horizontal")
        XCTAssertTrue(a.flipH)
        ui.tap(at: canvas.screenPoint(a.frame.center), buttons: kSecondaryMouseButton)
        settle(ui)
        try tapLast("Rotate Right 90°")
        XCTAssertEqual(a.rotation, 90, accuracy: 0.01)
    }
}
