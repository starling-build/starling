import XCTest
@testable import Flutter

/// runView(id:) registers the widget tree of one non-implicit view (docs/plans/ipad-multi-window.md, step 3).
final class RunViewTests: XCTestCase {
    override func tearDown() { viewContentBuilders = [:]; super.tearDown() }

    func testRunViewRegistersABuilderForThatViewOnly() {
        XCTAssertNil(viewContentBuilders[7])
        runView(id: 7) { SizedBox(width: 1, height: 1) }
        XCTAssertNotNil(viewContentBuilders[7])
        XCTAssertNil(viewContentBuilders[8])
        XCTAssertTrue(viewContentBuilders[7]!() is SizedBox)
    }
}
