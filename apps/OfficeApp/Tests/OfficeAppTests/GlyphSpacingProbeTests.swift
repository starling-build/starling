// The 14pt menu glyph-spacing bug, narrowed: paragraph layout is not it.
// Widths of one string in the menu item's merged style scale linearly
// across 12–16pt (2026-09-30, headless), so whatever stretches the
// letters on screen happens after layout — rasterization or the face
// the running app resolves — and needs a screenshot to chase further.

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class GlyphSpacingProbeTests: XCTestCase {
    func testWidthsScaleLinearlyAcrossSizes() {
        _ = OfficeFonts.register()
        let text = "Heading 1 AaBb Normal"
        var perPoint: [Double] = []
        for size in [12.0, 13.0, 13.5, 14.0, 14.5, 15.0, 16.0] {
            let style = Flutter.TextStyle(color: Color(0xFF000000), fontSize: size, fontWeight: .normal,
                                          height: 20.0 / 14.0, fontFamily: OfficeFonts.sans)
            let tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: 10000)
            perPoint.append(tp.width / size)
            tp.dispose()
        }
        let base = perPoint[0]
        for v in perPoint { XCTAssertEqual(v, base, accuracy: base * 0.005) }
    }
}
