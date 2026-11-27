import XCTest
import OfficeText
@testable import OfficeApp

/// Faces PowerPoint's machine has and ours lacks set their Cyrillic at the Windows face's own widths, not the stand-in's.
final class SlideFaceWidthsTests: XCTestCase {
    /// Georgia's Cyrillic: ru-a8d8851396's Russian lines wrapped late at the serif stand-in's narrower letters.
    func testGeorgiaSetsCyrillicAtItsOwnWidths() throws {
        let f = try XCTUnwrap(SlideFonts.face("Georgia", false))
        XCTAssertEqual(try XCTUnwrap(f.otherAdvances?[0x0434]), try XCTUnwrap(OfficeFonts.georgiaCyrillicAdvances[0x0434]))
        XCTAssertEqual(try XCTUnwrap(f.boldOtherAdvances?[0x0434]), try XCTUnwrap(OfficeFonts.georgiaBoldCyrillicAdvances[0x0434]))
    }

    /// Trebuchet MS's Cyrillic, all four cuts (U+0410: Regular 0.5942, Bold 0.6372 em on Windows): ru-a8d8851396's title wrapped mid-word.
    func testTrebuchetSetsCyrillicAtItsOwnWidths() throws {
        let f = try XCTUnwrap(SlideFonts.face("Trebuchet MS", false))
        XCTAssertEqual(try XCTUnwrap(f.otherAdvances?[0x0410]), 0.5942, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(f.boldOtherAdvances?[0x0410]), 0.6372, accuracy: 1e-4)
        XCTAssertNotNil(f.italicOtherAdvances?[0x0410])
        XCTAssertNotNil(f.boldItalicOtherAdvances?[0x0410])
    }
}
