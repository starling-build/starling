import XCTest
import Flutter
import OfficeText
@testable import OfficeApp

/// The slide canvas as a screen reader sees it: the slide, then each shape with its name and text, in order.
final class SlidesAccessibilityTests: XCTestCase {
    func testSlideAndShapesAreNodesInReadingOrderAndATapSelects() throws {
        let deck = DeckController()
        let shapes = deck.currentSlide.shapes
        XCTAssertGreaterThan(shapes.count, 1)
        let canvas = SlideCanvas(deck: deck, cache: SlideTextCache(), active: nil, onEdit: { _ in },
                                 onShortcut: { _, _ in false }, modifiers: { [] }, spellChecker: nil)
        let ui = WidgetTester(FluentApp(theme: OfficeAppearance.theme(.light), home: canvas, title: "Test"))
        for _ in 0 ..< 3 { ui.pump(); for cb in FrameCallbackScheduler.shared.takePostFrameCallbacks() { cb(.zero) } }
        ui.pump()
        let nodes = SemanticsSnapshot.build(from: try XCTUnwrap(ui.elements().first))
        XCTAssertTrue(nodes.contains { $0.label == "Slide 1 of \(deck.slides.count)" })
        let names = shapes.map { SlidesAccessibility.label(of: $0) }
        let seen = nodes.map { $0.label }.filter { names.contains($0) }
        XCTAssertEqual(seen, names, "every shape is a node, in the slide's own order")
        let first = try XCTUnwrap(nodes.first { $0.label == names[0] })
        XCTAssertEqual(first.value, SlidesAccessibility.text(of: shapes[0]))
        XCTAssertTrue(first.canTap)
        let second = try XCTUnwrap(nodes.first { $0.label == names[1] })
        second.tap?()
        XCTAssertTrue(deck.selection.count == 1 && deck.selection[0] === shapes[1])
    }
}
