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

    private func runFont(_ latin: String, _ charset: String) throws -> String? {
        let xml = "<a:rPr xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" lang=\"ko-KR\"><a:latin typeface=\"\(latin)\" charset=\"\(charset)\"/><a:ea typeface=\"\(latin)\" charset=\"\(charset)\"/></a:rPr>"
        let node = try XCTUnwrap(XNode.parse(Data(xml.utf8)))
        return LevelStyle.run(node, ColorContext(theme: PptxTheme(nil))).font
    }

    /// A Latin face PowerPoint's machine lacks, declared Shift-JIS (-128), prints its Latin in Yu Gothic (ko-00b895c634's 함초롬돋움);
    /// declared Hangul (-127) it stays (Malgun's Latin), and an installed family's weight (나눔고딕 ExtraBold, NanumGothic Bold) stays too.
    func testAMissingShiftJisFaceSetsItsLatinInYuGothic() throws {
        XCTAssertEqual(try runFont("함초롬돋움", "-128"), "Yu Gothic")
        XCTAssertEqual(try runFont("함초롬돋움", "-127"), "함초롬돋움")
        XCTAssertEqual(try runFont("나눔고딕 ExtraBold", "-128"), "나눔고딕 ExtraBold")
        XCTAssertEqual(try runFont("Arial", "-128"), "Arial")
    }
}
