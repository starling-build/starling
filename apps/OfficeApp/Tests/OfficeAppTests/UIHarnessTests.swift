import XCTest
import Flutter

/// The headless harness itself: a tree is built with no window, a control is found by its label and tapped.
final class UIHarnessTests: XCTestCase {
    func testTappingALabelReachesItsHandler() {
        var taps = 0
        let ui = WidgetTester(
            Directionality(textDirection: .ltr, child: Center(child: GestureDetector(onTap: { taps += 1 }, child: Text("Apply")))))
        XCTAssertTrue(ui.has(text: "Apply"))
        XCTAssertFalse(ui.has(text: "Cancel"))
        XCTAssertTrue(ui.tap(text: "Apply"))
        XCTAssertEqual(taps, 1)
        XCTAssertFalse(ui.tap(text: "Cancel"))
        XCTAssertEqual(taps, 1)
    }
}
