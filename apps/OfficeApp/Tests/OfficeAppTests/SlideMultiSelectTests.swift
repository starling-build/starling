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
        // Select All through the shell's own shortcut table, with the platform's primary key (Cmd on a Mac, Ctrl elsewhere;
        // a bare Ctrl+A key event selects nothing on the Mac).
        let state = try XCTUnwrap(ui.state(SlidesShellState.self))
        XCTAssertTrue(state._shortcut(KeyData(timeStamp: 0, type: .down, physical: 0, logical: 0x61, character: nil, synthesized: false), .primary))
        ui.pump()
        XCTAssertEqual(deck.selection.count, 3)
        let h = handles(ui)
        XCTAssertEqual(h.count, 8 + 8 + 2, "eight on each box, one at each end of the line")
        deck.selectShapes([b]); ui.pump()
        XCTAssertEqual(handles(ui), [])
    }
}
