import XCTest
import Flutter
@testable import OfficeText
@testable import OfficeApp

/// The browser loads some faces on first use, after the first document was
/// measured. A theme must then forget every measurement of a face, not just
/// its line height: the first deck the browser opened kept the stand-in's
/// baseline, and its Times New Roman lines sat 0.0082 em high.
final class RichThemeFontChangeTests: XCTestCase {
    func testAFontChangeForgetsEveryFaceMeasurement() {
        _ = OfficeFonts.register()
        let theme = RichTextTheme(fontFamily: OfficeFonts.serif, fontSize: 12)
        _ = theme.naturalLineHeight(family: OfficeFonts.serif, bold: false, italic: false)
        _ = theme.descentShare(family: OfficeFonts.serif, bold: false, italic: false)
        _ = theme.faceAscentDescent(family: OfficeFonts.serif, bold: false, italic: false)
        XCTAssertGreaterThanOrEqual(theme.faceMetricsHeld, 3)
        SystemFontsNotifier.shared.notifyListeners()
        XCTAssertEqual(theme.faceMetricsHeld, 0, "height, ascent and descent are all measured again")
    }
}
