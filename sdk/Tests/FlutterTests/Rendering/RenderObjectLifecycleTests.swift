import XCTest
import FlutterSwiftBridge
@testable import Flutter

/// `attach`/`detach` recurse and `adoptChild`/`dropChild` drive them, so an
/// interior node's attach-gated setup runs — the lifecycle upstream relies on
/// and this port skipped until 2026-09.
final class RenderObjectLifecycleTests: XCTestCase {

    /// A childless proxy box is the simplest leaf there is.
    private func Leaf() -> RenderProxyBox { RenderProxyBox() }

    private final class Painter: CustomPainter {
        override func paint(_ canvas: any Canvas, _ size: Size) {}
        override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool { false }
    }

    func testAttachReachesEveryInteriorNode() {
        let leaf = Leaf()
        let flex = RenderFlex()
        flex.insert(leaf)
        let inner = RenderProxyBox(child: flex)
        let outer = RenderProxyBox(child: inner)

        XCTAssertFalse(leaf.attached)
        let owner = PipelineOwner()
        outer.attach(owner)
        XCTAssertTrue(inner.attached)
        XCTAssertTrue(flex.attached)
        XCTAssertTrue(leaf.attached)

        outer.detach()
        XCTAssertFalse(inner.attached)
        XCTAssertFalse(flex.attached)
        XCTAssertFalse(leaf.attached)
    }

    func testAdoptIntoAttachedTreeAttachesTheSubtreeAndDropDetachesIt() {
        let owner = PipelineOwner()
        let root = RenderProxyBox()
        root.attach(owner)

        let leaf = Leaf()
        let mid = RenderProxyBox(child: leaf)   // built detached
        XCTAssertFalse(mid.attached)
        root.child = mid                        // adoptChild
        XCTAssertTrue(mid.attached)
        XCTAssertTrue(leaf.attached)

        root.child = nil                        // dropChild
        XCTAssertFalse(mid.attached)
        XCTAssertFalse(leaf.attached)
    }

    func testDepthFollowsAdoption() {
        let leaf = Leaf()
        let mid = RenderProxyBox(child: leaf)
        let root = RenderProxyBox(child: mid)
        XCTAssertEqual(root.depth, 0)
        XCTAssertEqual(mid.depth, 1)
        XCTAssertEqual(leaf.depth, 2)

        // Re-parenting a built subtree deeper redepths the whole of it.
        let deeper = RenderProxyBox()
        let top = RenderProxyBox(child: deeper)
        root.child = nil
        deeper.child = mid
        XCTAssertEqual(top.depth, 0)
        XCTAssertEqual(deeper.depth, 1)
        XCTAssertEqual(mid.depth, 2)
        XCTAssertEqual(leaf.depth, 3)
    }

    func testCustomPaintSubscribesOnAttachAndUnsubscribesOnDrop() {
        let repaint = ChangeNotifier()
        let painter = Painter(repaint: repaint)
        let paint = RenderCustomPaint(painter: painter)
        XCTAssertFalse(repaint.hasListeners, "subscribing belongs to attach, not init")

        let owner = PipelineOwner()
        let root = RenderProxyBox()
        root.attach(owner)
        root.child = paint
        XCTAssertTrue(repaint.hasListeners)

        root.child = nil
        XCTAssertFalse(repaint.hasListeners)
    }

    func testDroppingOneSubscriberLeavesTheOthersListener() {
        // Two render objects on one repaint notifier: dropping the first
        // must not take the second's listener with it (the LIFO stub did).
        let repaint = ChangeNotifier()
        let first = RenderCustomPaint(painter: Painter(repaint: repaint))
        let second = RenderCustomPaint(painter: Painter(repaint: repaint))
        let flex = RenderFlex()
        flex.insert(first)
        flex.insert(second, after: first)
        flex.attach(PipelineOwner())

        flex.remove(first)
        XCTAssertTrue(repaint.hasListeners)
        flex.remove(second)
        XCTAssertFalse(repaint.hasListeners)
    }

    func testVisitChildrenCoversTheContainerShapes() {
        let a = Leaf(), b = Leaf()
        let flex = RenderFlex()
        flex.insert(a)
        flex.insert(b, after: a)
        var seen: [RenderObject] = []
        flex.visitChildren { seen.append($0) }
        XCTAssertEqual(seen.count, 2)
        XCTAssertTrue(seen[0] === a && seen[1] === b)

        let proxy = RenderProxyBox(child: flex)
        seen = []
        proxy.visitChildren { seen.append($0) }
        XCTAssertTrue(seen.count == 1 && seen[0] === flex)
    }
}
