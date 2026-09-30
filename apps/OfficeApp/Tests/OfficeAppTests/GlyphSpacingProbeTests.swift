// Guard from the 14pt menu glyph bug: widths of one string across sizes
// scale linearly. Layout was never the culprit — the stretch came from
// the engine's rasterizer painting a bridge-loaded typeface from another
// font's glyph strike, because the bridge's copy of Skia handed out the
// same typeface IDs as the engine's (fixed in the bridge, 2026-09-30).
// This stays as the layout half of that guarantee; the paint half needs
// a screen (OFFICE_STYLE_PREVIEW_CAP=14 and the styles menu).

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeApp

final class GlyphSpacingProbeTests: XCTestCase {
    private func widths(_ make: (Double) -> Flutter.TextStyle) -> [Double] {
        let text = "Heading 1 AaBb Normal"
        return [12.0, 13.0, 13.5, 14.0, 14.5, 15.0, 16.0].map { size in
            let tp = TextPainter(text: TextSpan(text: text, style: make(size)), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: 10000)
            defer { tp.dispose() }
            return tp.width / size
        }
    }

    func testWidthsScaleLinearlyAcrossSizes() {
        _ = OfficeFonts.register()
        let bare = widths { size in
            Flutter.TextStyle(color: Color(0xFF000000), fontSize: size, fontWeight: .normal,
                              height: 20.0 / 14.0, fontFamily: OfficeFonts.sans)
        }
        for v in bare { XCTAssertEqual(v, bare[0], accuracy: bare[0] * 0.005) }
        let body = Typography.fromBrightness(brightness: .light).body!
        let merged = widths { size in
            body.merge(Flutter.TextStyle(color: Color(0xFF2F5496), fontSize: size, fontWeight: .bold,
                                         fontStyle: .normal, fontFamily: OfficeFonts.sans))
        }
        print("PROBE merged per-point widths:", merged)
        for v in merged { XCTAssertEqual(v, merged[0], accuracy: merged[0] * 0.005) }
        // The tile's own wrap: DefaultTextStyle(color, fontSize: 14) merged
        // with the preview; per-glyph advances at 14.0 vs 14.01.
        for size in [14.0, 14.01] {
            let style = Flutter.TextStyle(color: Color(0xFF000000), fontSize: 14)
                .merge(Flutter.TextStyle(color: Color(0xFF2F5496), fontSize: size, fontWeight: .bold,
                                         fontStyle: .normal, fontFamily: OfficeFonts.sans))
            let tp = TextPainter(text: TextSpan(text: "Title", style: style), textDirection: .ltr)
            tp.layout(minWidth: 500, maxWidth: 500)
            let boxes = (0 ..< 5).map { i in tp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first.map { $0.right - $0.left } ?? -1 }
            print("PROBE tile-merge size \(size): width=\(tp.width) glyphs=\(boxes)")
            tp.dispose()
        }
    }
}
