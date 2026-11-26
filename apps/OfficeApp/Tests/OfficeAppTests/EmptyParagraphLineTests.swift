import XCTest
import Flutter
@testable import OfficeApp

/// The native engine measures an empty paragraph in its own default text
/// style, not the painter's: the paragraph's family and size never reach it,
/// so the line is txt's 14 px in DejaVu Sans (1901 + 483 units of 2048,
/// 16.297 px), whatever the style says. The browser's paragraph builder pins
/// the same line (FlutterSwiftBridgeWeb's engineDefaultLineHeight), so an
/// empty chart label takes the same room in both: 123233_charts' plot stood
/// 7 pt lower in the browser when it measured the label's own 8 pt face.
final class EmptyParagraphLineTests: XCTestCase {
    func testAnEmptyParagraphIsTheEngineDefaultLine() {
        let line = 14.0 * (1901.0 + 483.0) / 2048.0
        for family in ["Liberation Sans", "Carlito"] {
            for size in [8.0, 20.0] {
                let style = Flutter.TextStyle(fontSize: size, fontFamily: family)
                for span in [TextSpan(children: [], style: style), TextSpan(text: "", style: style)] {
                    let painter = TextPainter(text: span, textDirection: .ltr)
                    painter.layout()
                    XCTAssertEqual(painter.height, line.rounded(), accuracy: 1e-6, "\(family) \(size)")
                    painter.dispose()
                }
            }
        }
    }
}
