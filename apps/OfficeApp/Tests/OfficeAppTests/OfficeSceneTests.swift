import XCTest
import Flutter
import FlutterSwiftBridge
@testable import Flutter
@testable import OfficeApp

/// OfficeScene (docs/plans/ipad-multi-window.md, step 4): the host hooks belong to a window, not to the process.
/// Before, they were statics on OfficeHost, so a second window's toolbar and Open panel replaced the first's.
final class OfficeSceneTests: XCTestCase {

    private final class Leaf: LeafRenderObjectWidget {
        override func createRenderObject(_ context: any BuildContext) -> RenderObject { LeafBox() }
    }
    private final class LeafBox: RenderBox, SingleChildRenderObjectHost { var child: RenderBox? }
    private final class RootWidget: SingleChildRenderObjectWidget {
        init() { super.init(key: nil, child: nil) }
        override func createRenderObject(_ context: any BuildContext) -> RenderObject { LeafBox() }
    }
    private final class Root: RenderObjectElement {
        init() { super.init(RootWidget()); owner = BuildOwner(); _lifecycleState = .active; renderObject = RenderObject() }
        override func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {}
        override func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {}
    }

    /// The element of a `Leaf` mounted under `tree`.
    private func leafElement(under tree: Widget) -> Element {
        let top = tree.createElement()
        top.mount(Root(), nil)
        var e: Element = top
        while let c = (e as? ComponentElement)?._child ?? (e as? SingleChildRenderObjectElement)?._child { e = c }
        return e
    }

    func testTreeFindsTheNearestScene() {
        let outer = OfficeScene(), inner = OfficeScene()
        let leaf = leafElement(under: OfficeSceneScope(scene: outer, child: OfficeSceneScope(scene: inner, child: Leaf())))
        XCTAssertTrue(OfficeScene.of(leaf) === inner)
    }

    func testTwoWindowsHaveTwoScenes() {
        let a = OfficeScene(), b = OfficeScene()
        let la = leafElement(under: OfficeSceneScope(scene: a, child: Leaf()))
        let lb = leafElement(under: OfficeSceneScope(scene: b, child: Leaf()))
        XCTAssertTrue(OfficeScene.of(la) === a)
        XCTAssertTrue(OfficeScene.of(lb) === b)
    }

    func testNoScopeMeansTheMainScene() {
        XCTAssertTrue(OfficeScene.of(leafElement(under: Leaf())) === OfficeScene.main)
        XCTAssertTrue(OfficeScene.of(nil) === OfficeScene.main)
    }

    func testToolbarOfOneSceneDoesNotTouchTheOther() {
        let a = OfficeScene(), b = OfficeScene()
        var aSaw: [Int] = [], bSaw: [Int] = []
        a.toolbarChanged = { aSaw.append($0?.count ?? -1) }
        b.toolbarChanged = { bSaw.append($0?.count ?? -1) }
        let editorA = NSObject(), editorB = NSObject()
        let button = OfficeHost.ToolbarButton(id: "x", title: "X", symbol: "bold") {}
        a.publishToolbar([button], owner: editorA)
        b.publishToolbar([button, button], owner: editorB)
        XCTAssertEqual(aSaw, [1])
        XCTAssertEqual(bSaw, [2])
        // B's editor going away withdraws B's bar and leaves A's alone.
        b.publishToolbar(nil, owner: editorB)
        XCTAssertEqual(bSaw, [2, -1])
        XCTAssertEqual(aSaw, [1])
    }

    func testAWithdrawalCountsOnlyFromTheEditorThatPublishedLastInThatScene() {
        let a = OfficeScene()
        var seen: [Int] = []
        a.toolbarChanged = { seen.append($0?.count ?? -1) }
        let old = NSObject(), new = NSObject()
        let button = OfficeHost.ToolbarButton(id: "x", title: "X", symbol: "bold") {}
        a.publishToolbar([button], owner: old)
        a.publishToolbar([button, button], owner: new)   // the replacement mounts first
        a.publishToolbar(nil, owner: old)                // then the old one is disposed
        XCTAssertEqual(seen, [1, 2], "the old editor's dispose must not wipe the new one's bar")
    }
}
