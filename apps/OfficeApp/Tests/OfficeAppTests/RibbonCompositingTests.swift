import XCTest
import Flutter
import FlutterSwiftBridge

/// Ribbon menu targets must remain visible inside the horizontal viewport.
final class RibbonCompositingTests: XCTestCase {
    private final class RecordingContext: PaintingContext {
        var bounds: Rect?
        var childOffset: Offset?

        override func pushLayer(_ childLayer: ContainerLayer,
                                _ painter: PaintingContextCallback,
                                _ offset: Offset,
                                childPaintBounds: Rect? = nil) {
            bounds = childPaintBounds ?? estimatedBounds
            childOffset = offset
        }
    }

    func testMenuTargetRecordsWithinItsLocalBoundsInsideOffsetViewport() {
        let target = RenderLeaderLayer(link: LayerLink())
        target.layout(BoxConstraints.tight(Size(140, 28)))
        let context = RecordingContext(ContainerLayer(), Rect.fromLTRB(0, 96, 1200, 200))
        target.paint(context, Offset(180, 102))

        // A picture recorded against the viewport's y=96 bounds discards the
        // entire control at local y=0...28, although its hit target still works.
        XCTAssertEqual(context.childOffset, .zero)
        XCTAssertEqual(context.bounds, Rect.fromLTRB(0, 0, 140, 28))
        XCTAssertTrue(context.bounds?.contains(Offset(70, 14)) == true)
    }
}
