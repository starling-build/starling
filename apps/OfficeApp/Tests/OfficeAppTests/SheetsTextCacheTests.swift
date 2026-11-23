import XCTest
@testable import OfficeApp

final class SheetsTextCacheTests: XCTestCase {
    /// A painter fetched before the cache evicts (it holds 4000) must stay usable:
    /// a wide number re-lays out as ### after taking its first painter, and a
    /// page of 4000+ distinct cells hits the eviction at exactly that moment.
    func testPainterSurvivesEviction() {
        let texts = _TextCache()
        let style = GridTextStyle(family: "Arial", size: 11, color: 0xFF000000)
        let first = texts.painter("held", style)
        for i in 0..<4100 { _ = texts.painter("cell \(i)", style) }
        XCTAssertGreaterThan(first.width, 0)
    }
}
