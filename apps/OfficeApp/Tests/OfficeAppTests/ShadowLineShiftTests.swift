import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp
@testable import OfficeText

/// The shadow's line shift reads the span tree by hand: InlineSpan.visitChildren traps on a span that does not
/// override it (batch G's first gate died on Slides decks with "Subclasses must override visitChildren").
final class ShadowLineShiftTests: XCTestCase {
    private final class BareSpan: InlineSpan {}   // overrides nothing, as a Slides run's span does

    func testASpanThatDoesNotOverrideVisitChildrenIsAskedNothing() {
        XCTAssertEqual(RichLayout._shadowLineShift(BareSpan(), at: 0), 0)
        let tree = TextSpan(text: "ab", children: [BareSpan()])
        XCTAssertEqual(RichLayout._shadowLineShift(tree, at: 1), 0)
    }

    func testTheShiftOfTheRunHoldingTheOffsetIsFound() {
        let shifted = TextStyle(baselineShift: 3, debugLabel: "x shadow-line")
        let tree = TextSpan(text: "ab", children: [TextSpan(text: "cd", style: shifted), TextSpan(text: "ef")])
        XCTAssertEqual(RichLayout._shadowLineShift(tree, at: 3), 3)
        XCTAssertEqual(RichLayout._shadowLineShift(tree, at: 1), 0)
        XCTAssertEqual(RichLayout._shadowLineShift(tree, at: 5), 0)
    }
}
