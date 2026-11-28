import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// A see-through slide background sits on white, as PowerPoint and its slide show draw it, not on whatever is
/// behind the slide (the editor's dark canvas made a 50% transparent red read 77 where PowerPoint shows 255,128,128).
final class SlideBackgroundOnWhiteTests: XCTestCase {
    private func pixel(_ fill: SlideFill, under backdrop: Color) throws -> [UInt8] {
        let slide = Slide(id: 1, layout: .blank, shapes: [], notes: RichDocumentController())
        slide.background = fill
        let painter = SlidePainter(slide: slide, theme: DeckTheme.presets[0], slideSize: Size(96, 54), revision: 0,
                                   cache: SlideTextCache(), placeholders: false)
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, 96, 54))
        let behind = Paint(); behind.color = backdrop
        canvas.drawRect(Rect.fromLTWH(0, 0, 96, 54), behind)
        painter.paint(canvas, Size(96, 54))
        let image = try XCTUnwrap(recorder.endRecording().toImageSync(width: 96, height: 54))
        let rgba = [UInt8](try image.toByteData(format: .rawRgba))
        let at = (27 * 96 + 48) * 4
        return Array(rgba[at ..< at + 3])
    }

    func testHalfTransparentRedReadsAsRedOverWhite() throws {
        var f = SlideFill()
        f.color = FormatBackgroundPaneState.transparent(Color(0xFFFF0000), 50)
        for backdrop in [Color(0xFF202020), Color(0xFF000000), Color(0xFFFFFFFF)] {
            let p = try pixel(f, under: backdrop)
            XCTAssertEqual(Int(p[0]), 255, accuracy: 2, "\(p)")
            XCTAssertEqual(Int(p[1]), 128, accuracy: 3, "\(p)")
            XCTAssertEqual(Int(p[2]), 128, accuracy: 3, "\(p)")
        }
    }

    func testAnOpaqueBackgroundIsUnchanged() throws {
        var f = SlideFill()
        f.color = Color(0xFF336699)
        XCTAssertEqual(try pixel(f, under: Color(0xFF000000)), [0x33, 0x66, 0x99])
    }
}
