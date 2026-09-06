// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Flutter
import FlutterSwiftBridge

/// `FluentApp` + `ScaffoldPage` mounts as a plain element tree.
///
/// For a long stretch the desktop's rule was "apps are macOS-only", because
/// a `FluentApp` scaffold trapped on mount as a DMA-BUF child — a
/// `RenderObjectElement` insert cast in the scaffold. The mount below is
/// the same element inflation that path performs, with a bare render
/// object for a root, so a regression fails here in the fast tier rather
/// than as a dead child window on the desktop.
final class FluentAppMountTests: XCTestCase {

    /// A root that owns a BuildOwner and accepts any render child.
    private final class RootElement: RenderObjectElement {
        let buildOwner = BuildOwner()
        init() {
            super.init(_RootWidget())
        }
        func setup() {
            owner = buildOwner
            _lifecycleState = .active
            renderObject = RenderObject()
        }
        override func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {}
        override func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {}
    }

    private final class _RootWidget: RenderObjectWidget {
        override func createRenderObject(_ context: any BuildContext) -> RenderObject { RenderObject() }
        override func createElement() -> Element { fatalError("mounted by hand") }
    }

    private func mount(_ widget: Widget) -> Element {
        let root = RootElement()
        root.setup()
        let element = widget.createElement()
        root.buildOwner.buildScopeWithCallback(root) {
            element.mount(root, nil)
        }
        return element
    }

    private func descendants(of element: Element) -> [Element] {
        var out: [Element] = []
        func walk(_ e: Element) {
            out.append(e)
            e.visitChildElements(walk)
        }
        walk(element)
        return out
    }

    func testFluentAppWithScaffoldPageMounts() {
        let page = ScaffoldPage(
            header: PageHeader(title: Text("Title")),
            content: Column(crossAxisAlignment: .start) {
                Text("body")
                Button(onPressed: {}, child: Text("Press"))
            })
        let element = mount(FluentApp(theme: FluentThemeData.light(), home: page))
        let tree = descendants(of: element)
        XCTAssertTrue(tree.contains { $0.widget is ScaffoldPage }, "the scaffold is in the tree")
        XCTAssertTrue(tree.contains { $0.widget is Button }, "and its content mounted under it")
    }

    func testScaffoldPageStretchesItsColumn() {
        // The page fills its width and lays out from the left; a centred
        // column would float the content in the middle of the window.
        let element = mount(FluentApp(home: ScaffoldPage(content: Text("body"))))
        let columns = descendants(of: element).compactMap { $0.widget as? Column }
        let stretched = columns.filter { $0.crossAxisAlignment == .stretch }
        XCTAssertFalse(stretched.isEmpty, "ScaffoldPage's column must stretch")
    }

    func testStarlingAppInstallsBothThemes() {
        let element = mount(StarlingApp(title: "t", home: ScaffoldPage(content: Text("body"))))
        let tree = descendants(of: element)
        XCTAssertTrue(tree.contains { $0.widget is AnimatedFluentTheme }, "a Fluent theme for the Fluent controls")
        XCTAssertTrue(tree.contains { $0.widget is AnimatedMacosTheme }, "a macOS theme for the Macos* controls")
        XCTAssertTrue(tree.contains { $0.widget is Navigator }, "one Navigator for both")
        XCTAssertTrue(tree.contains { $0.widget is ScaffoldPage }, "and the page under it")
    }

    func testStarlingAppRebuildKeepsHomeState() {
        // A style or appearance push is a rebuild the app's state lives
        // through — the widget types above `home` never change.
        let element = mount(StarlingApp(home: ScaffoldPage(content: Text("body"))))
        let before = descendants(of: element).first { $0.widget is ScaffoldPage }
        guard let state = (element as? StatefulElement)?.state as? _StarlingAppState else {
            return XCTFail("root is the StarlingApp state")
        }
        element.owner?.buildScopeWithCallback(element) { state.setState {} }
        let after = descendants(of: element).first { $0.widget is ScaffoldPage }
        XCTAssertNotNil(before); XCTAssertNotNil(after)
        XCTAssertTrue(before === after, "the page's element survives a root rebuild")
    }
}
