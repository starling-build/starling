// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Flutter
import FlutterSwiftBridge

/// `CommandBarFlyout`'s display-mode rules, which are what make it a
/// context menu rather than a toolbar: collapsed shows the primary row
/// alone with a "see more" ellipsis, expanded shows both, a flyout with
/// only secondary commands is a plain menu with neither row nor ellipsis,
/// and `alwaysExpanded` takes the ellipsis away.
final class CommandBarFlyoutTests: XCTestCase {

    // MARK: The element harness
    //
    // The same hand-assembled root `FluentAppMountTests` uses: a build
    // owner and a render object that accepts any child, so a widget can be
    // inflated without a view or an engine.

    private final class RootElement: RenderObjectElement {
        let buildOwner = BuildOwner()
        init() { super.init(_RootWidget()) }
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

    private func mount(_ widget: Widget) -> [Element] {
        let root = RootElement()
        root.setup()
        let element = FluentTheme(data: FluentThemeData.light(), child: widget).createElement()
        root.buildOwner.buildScopeWithCallback(root) {
            element.mount(root, nil)
        }
        var out: [Element] = []
        func walk(_ e: Element) {
            out.append(e)
            e.visitChildElements(walk)
        }
        walk(element)
        return out
    }

    /// One tile per secondary command that is actually showing.
    private func menuTiles(_ tree: [Element]) -> Int {
        tree.filter { $0.widget is FlyoutListTile }.count
    }

    /// The "see more" ellipsis, or the chevron it becomes when expanded.
    private func seeMore(_ tree: [Element]) -> FluentGlyphKind? {
        for e in tree {
            if let g = e.widget as? FluentGlyph, g.kind == .more || g.kind == .chevronUp {
                return g.kind
            }
        }
        return nil
    }

    private func commands(_ names: [String]) -> [CommandBarItem] {
        names.map { CommandBarButton(label: Text($0), onPressed: {}) }
    }

    func testSecondaryOnlyIsAPlainMenu() {
        let tree = mount(CommandBarFlyout(secondaryCommands: commands(["Copy", "Print"])))
        XCTAssertEqual(menuTiles(tree), 2, "both commands show as menu items")
        XCTAssertNil(seeMore(tree), "nothing to expand into, so no see-more button")
    }

    func testCollapsedHidesTheSecondaryCommands() {
        let tree = mount(CommandBarFlyout(
            primaryCommands: commands(["Cut"]),
            secondaryCommands: commands(["Properties"]),
            initiallyExpanded: false))
        XCTAssertEqual(menuTiles(tree), 0, "collapsed shows the row alone")
        XCTAssertEqual(seeMore(tree), .more, "and offers the ellipsis to reach the rest")
    }

    func testExpandedShowsBoth() {
        let tree = mount(CommandBarFlyout(
            primaryCommands: commands(["Cut"]),
            secondaryCommands: commands(["Open", "Properties"]),
            initiallyExpanded: true))
        XCTAssertEqual(menuTiles(tree), 2, "expanded shows the menu under the row")
        XCTAssertEqual(seeMore(tree), .chevronUp, "and the ellipsis becomes the fold-up")
    }

    func testAlwaysExpandedDropsTheSeeMoreButton() {
        let tree = mount(CommandBarFlyout(
            primaryCommands: commands(["Cut"]),
            secondaryCommands: commands(["Properties"]),
            initiallyExpanded: false,
            alwaysExpanded: true))
        XCTAssertEqual(menuTiles(tree), 1, "always expanded ignores the collapsed request")
        XCTAssertNil(seeMore(tree), "and the user cannot fold it away")
    }

    func testInvokingACommandDismissesTheFlyout() {
        var dismissed = 0
        var pressed = 0
        let item = CommandBarButton(label: Text("Copy"), onPressed: { pressed += 1 })
        _ = mount(CommandBarFlyout(secondaryCommands: [item],
                                   onDismiss: { dismissed += 1 }))
        item._invoke?()
        XCTAssertEqual(pressed, 1, "the command ran")
        XCTAssertEqual(dismissed, 1, "and the flyout went away with it")
    }

    func testADisabledCommandDoesNothing() {
        let item = CommandBarButton(label: Text("Paste"), onPressed: nil)
        _ = mount(CommandBarFlyout(secondaryCommands: [item], onDismiss: {
            XCTFail("a disabled command must not dismiss the flyout")
        }))
        XCTAssertNil(item._invoke, "a disabled command has no press to make")
    }
}
