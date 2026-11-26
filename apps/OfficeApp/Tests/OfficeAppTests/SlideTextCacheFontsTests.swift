import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A font that arrives after a slide was laid out (the browser loads some
/// faces on first use) must not leave the old lines in the cache: the PDF
/// export waits for the fonts, then draws from this cache.
final class SlideTextCacheFontsTests: XCTestCase {
    func testAFontChangeLaysTheTextOutAgain() {
        _ = OfficeFonts.register()
        let deck = SlidesSample.make()
        let body = deck.slides[1].shapes.first { $0.role == .body }!
        let cache = SlideTextCache()
        let first = cache.layout(body, pxPerPt: 1)
        XCTAssertNotNil(first)
        XCTAssertTrue(first === cache.layout(body, pxPerPt: 1), "unchanged text is reused")
        SystemFontsNotifier.shared.notifyListeners()
        let after = cache.layout(body, pxPerPt: 1)
        XCTAssertNotNil(after)
        XCTAssertFalse(first === after, "fonts changed: laid out again")
        XCTAssertTrue(after === cache.layout(body, pxPerPt: 1), "and reused after that")
    }
}
