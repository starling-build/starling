import XCTest
import FlutterSwiftBridge
@testable import Flutter

final class TransformHitTestTests: XCTestCase {
    private func hits(_ angle: Double, alignment: Alignment?, at p: Offset) -> Bool {
        let leaf = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(Size(100, 50)))
        let listener = RenderPointerListener(behavior: .opaque, child: leaf)
        let t = RenderTransform(transform: Matrix4.rotationZ(angle), alignment: alignment, child: listener)
        t.layout(BoxConstraints.tight(Size(100, 50)), parentUsesSize: true)
        let result = BoxHitTestResult()
        return t.hitTest(result, position: p)
    }

    func testZeroRotationHitsLikeNoTransform() {
        XCTAssertTrue(hits(0, alignment: nil, at: Offset(50, 25)))
        XCTAssertTrue(hits(0, alignment: Alignment.center, at: Offset(50, 25)), "about the centre")
        XCTAssertTrue(hits(0, alignment: Alignment.center, at: Offset(5, 5)))
        XCTAssertFalse(hits(0, alignment: Alignment.center, at: Offset(150, 25)))
    }

    func testQuarterTurnAboutTheCentre() {
        // 100x50 turned a quarter about (50,25) covers x 25...75, y -25...75.
        XCTAssertTrue(hits(.pi / 2, alignment: Alignment.center, at: Offset(50, 70)))
        XCTAssertFalse(hits(.pi / 2, alignment: Alignment.center, at: Offset(5, 25)))
    }
}

final class GlobalTransformTests: XCTestCase {
    /// "Global" is logical pixels: the root's own transform (the device
    /// pixel ratio, on a RenderView) is not part of it.
    func testGlobalExcludesTheRootsOwnTransform() {
        let leaf = RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(Size(10, 10)))
        let inner = RenderTransform(transform: Matrix4.translationValues(30, 40, 0), child: leaf)
        let root = RenderTransform(transform: Matrix4.diagonal3Values(2, 2, 1), child: inner)
        root.layout(BoxConstraints.tight(Size(200, 200)))
        XCTAssertEqual(leaf.localToGlobal(Offset(1, 2)), Offset(31, 42))
        XCTAssertEqual(leaf.globalToLocal(Offset(31, 42)), Offset(1, 2))
        XCTAssertEqual(leaf.localToGlobal(Offset(1, 2), ancestor: root), Offset(62, 84),
                       "an explicit ancestor still includes its transform")
        XCTAssertEqual(root.localToGlobal(Offset(5, 5)), Offset(5, 5), "the root is global itself")
    }
}
