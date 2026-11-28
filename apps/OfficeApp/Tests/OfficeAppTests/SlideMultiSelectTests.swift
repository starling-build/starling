import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

/// S-AR-1: a selection of several shapes (Cmd+A, Shift+click, a marquee) shows every selected shape's handles, as
/// PowerPoint does, not the single-shape handles of one of them.
final class SlideMultiSelectTests: XCTestCase {
    private func handles(_ ui: WidgetTester) -> [String] {
        ui.elements().compactMap { e -> String? in
            guard let k = e.widget.key as? ValueKey<String>, k.value.hasPrefix("multi-handle-") else { return nil }
            return k.value
        }
    }

    func testEverySelectedShapeShowsItsHandlesAndOneShapeHasItsOwnAgain() throws {
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light),
                                        home: SlidesShell(initialPath: nil, onSwitch: { _, _ in }), title: "Test"),
                              size: Size(1440, 932))
        let deck = try XCTUnwrap(ui.state(SlidesShellState.self)?.session.deck)
        deck.currentSlide.shapes.removeAll()
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(100, 100, 120, 60)
        let b = deck.addShape(.ellipse); b.frame = Rect.fromLTWH(300, 200, 80, 80)
        let c = deck.addShape(.line); c.frame = Rect.fromLTWH(500, 300, 100, 0)
        deck.selectShapes([a]); ui.pump()
        XCTAssertEqual(handles(ui), [], "one shape keeps its own grabbable handles")
        // Cmd+A (Ctrl+A here) from the deck selects all three.
        _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: .down, physical: 0, logical: 0xFFE3, character: nil, synthesized: false))
        for t in [KeyEventType.down, .up] {
            _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: t, physical: 0, logical: 0x61, character: t == .down ? "a" : nil, synthesized: false))
        }
        _ = FocusManager.instance.dispatchKeyData(KeyData(timeStamp: 0, type: .up, physical: 0, logical: 0xFFE3, character: nil, synthesized: false))
        ui.pump()
        XCTAssertEqual(deck.selection.count, 3)
        let h = handles(ui)
        XCTAssertEqual(h.count, 8 + 8 + 2, "eight on each box, one at each end of the line")
        deck.selectShapes([b]); ui.pump()
        XCTAssertEqual(handles(ui), [])
    }

    private func canvas(_ deck: DeckController, modifiers: KeyModifiers) throws -> (WidgetTester, SlideCanvasState) {
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { modifiers }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        return (ui, try XCTUnwrap(ui.state(SlideCanvasState.self)))
    }

    private func assertFrame(_ r: Rect, _ l: Double, _ t: Double, _ w: Double, _ h: Double, _ what: String,
                             line: UInt = #line) {
        for (a, b) in [(r.left, l), (r.top, t), (r.width, w), (r.height, h)] {
            XCTAssertEqual(a, b, accuracy: 0.5, "\(what): \(r)", line: line)
        }
    }

    /// Dragging one shape's handle in a multi-selection resizes every selected shape: each takes the dragged shape's
    /// width and height factors about its own opposite handle, as PowerPoint does, and one undo takes it all back.
    func testDraggingAHandleOfAMultiSelectionResizesEveryShape() throws {
        let deck = DeckController()
        deck.currentSlide.shapes.removeAll()
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(100, 100, 200, 100)
        let b = deck.addShape(.ellipse); b.frame = Rect.fromLTWH(400, 300, 100, 50)
        deck.selectShapes([a, b])
        let (ui, state) = try canvas(deck, modifiers: [.alt])      // Alt: no snapping, so the numbers are exact
        // a's bottom-right handle, from (300, 200) to (400, 250): a grows by 1.5 both ways.
        ui.drag(from: state.screenPoint(Offset(300, 200)), to: state.screenPoint(Offset(400, 250)), steps: 6, kind: .mouse)
        ui.pump()
        assertFrame(a.frame, 100, 100, 300, 150, "the dragged shape follows the pointer")
        assertFrame(b.frame, 400, 300, 150, 75, "the other shape scales by 1.5 about its own top-left")
        XCTAssertEqual(deck.selection.count, 2, "the selection stays")
        // A left-edge handle of b: only widths change, each about its own right edge.
        ui.drag(from: state.screenPoint(Offset(400, 337.5)), to: state.screenPoint(Offset(475, 337.5)), steps: 6, kind: .mouse)
        ui.pump()
        assertFrame(b.frame, 475, 300, 75, 75, "b's left edge follows the pointer")
        assertFrame(a.frame, 250, 100, 150, 150, "a halves its width about its right edge")
        deck.undo()
        assertFrame(a.frame, 100, 100, 300, 150, "one undo per drag")
        assertFrame(b.frame, 400, 300, 150, 75, "one undo per drag")
    }

    /// Pure geometry: a turned shape keeps its own opposite corner on the slide; Ctrl scales about each centre.
    func testScaledTogetherKeepsEachAnchor() {
        let deck = DeckController()
        let a = deck.addShape(.rect); a.frame = Rect.fromLTWH(0, 0, 100, 100)
        let b = deck.addShape(.rect); b.frame = Rect.fromLTWH(200, 200, 40, 20); b.rotation = 90
        let r = Rect.fromLTWH(0, 0, 200, 100)
        let out = SlideCanvasState.scaledTogether([(a, a.frame), (b, b.frame)], lead: a, leadFrame: a.frame, to: r, handle: 3)
        let nb = out[1].1
        XCTAssertEqual(nb.width, 80, accuracy: 1e-9); XCTAssertEqual(nb.height, 20, accuracy: 1e-9)
        // b's left-edge middle, turned with b, stays where it was on the slide.
        let v = SlideCanvasState.rotate(Offset(-20, 0), 90)
        let anchorBefore = Offset(220 + v.dx, 210 + v.dy)
        let after = SlideCanvasState.rotate(Offset(-nb.width / 2, 0), 90)
        XCTAssertEqual(nb.center.dx + after.dx, anchorBefore.dx, accuracy: 1e-9)
        XCTAssertEqual(nb.center.dy + after.dy, anchorBefore.dy, accuracy: 1e-9)
        let c = SlideCanvasState.scaledTogether([(a, a.frame), (b, b.frame)], lead: a, leadFrame: a.frame, to: r,
                                               handle: 3, fromCentre: true)[1].1
        XCTAssertEqual(c.center.dx, 220, accuracy: 1e-9); XCTAssertEqual(c.center.dy, 210, accuracy: 1e-9)
        XCTAssertEqual(c.width, 80, accuracy: 1e-9)
    }
}
