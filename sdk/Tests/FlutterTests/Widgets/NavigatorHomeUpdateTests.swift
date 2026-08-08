// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Testing
@testable import Flutter

// MARK: - Test Helpers

/// An identifiable leaf with a plain Element and no render object, so it can
/// sit below the Navigator without any layout infrastructure.
private class HomeLabel: Widget {
    let text: String

    init(text: String) {
        self.text = text
        super.init(key: nil)
    }

    override func createElement() -> Element {
        return Element(self)
    }
}

/// A different widget type, so `Widget.canUpdate(HomeLabel, SwappedLabel)`
/// is false and the home element must be remounted rather than updated.
private class SwappedLabel: Widget {
    let text: String

    init(text: String) {
        self.text = text
        super.init(key: nil)
    }

    override func createElement() -> Element {
        return Element(self)
    }
}

/// Lets the test reach the host's State to drive setState from outside.
private final class HostStateBox {
    weak var state: HostState?
}

/// The stateful host ABOVE the Navigator — the shape of the frozen-subtree
/// bug: ScreenShellApp kept a stateful root above MacosApp, whose setState
/// re-ran build() but never reconciled below the Navigator's initial route.
private class HostWidget: StatefulWidget {
    let box: HostStateBox
    let makeChild: (Int) -> Widget

    init(box: HostStateBox, makeChild: @escaping (Int) -> Widget) {
        self.box = box
        self.makeChild = makeChild
        super.init(key: nil)
    }

    override func createState() -> State<StatefulWidget> {
        return HostState()
    }
}

private class HostState: State<StatefulWidget> {
    var count = 0

    private var host: HostWidget {
        return widget as! HostWidget
    }

    override func initState() {
        super.initState()
        host.box.state = self
    }

    override func build(_ context: any BuildContext) -> Widget {
        return host.makeChild(count)
    }
}

/// A root element that provides a BuildOwner to the tree
/// (the BuildContextTests pattern).
private class NavTestRootWidget: SingleChildRenderObjectWidget {
    init() {
        super.init(key: nil, child: nil)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderObject()
    }
}

private class NavTestRootElement: RenderObjectElement {
    let buildOwner: BuildOwner

    init(owner: BuildOwner = BuildOwner()) {
        self.buildOwner = owner
        super.init(NavTestRootWidget())
    }

    func setup() {
        self.owner = buildOwner
        _lifecycleState = .active
        renderObject = RenderObject()
    }

    override func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {}
    override func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {}
}

/// Depth-first search for the single widget of the given type in the tree.
private func findWidget<T: Widget>(_ type: T.Type, in root: Element) -> T? {
    var found: T?
    func visit(_ element: Element) {
        if let w = element.widget as? T {
            found = w
        }
        element.visitChildElements(visit)
    }
    visit(root)
    return found
}

/// Mounts a HostWidget tree under a fresh root, returning the pieces the
/// tests drive. The walk starts at the host element: the hand-assembled root
/// never records the child that `mount` attaches under it, so
/// `visitChildElements` from the root would visit nothing.
private func pumpHost(
    _ makeChild: @escaping (Int) -> Widget
) -> (host: Element, owner: BuildOwner, box: HostStateBox) {
    let owner = BuildOwner()
    let root = NavTestRootElement(owner: owner)
    root.setup()
    let box = HostStateBox()
    let hostElement = HostWidget(box: box, makeChild: makeChild).createElement()
    hostElement.mount(root, nil)
    return (hostElement, owner, box)
}

// MARK: - Navigator Home Update Tests

@Suite("NavigatorHomeUpdate")
struct NavigatorHomeUpdateTests {

    @Test("setState above Navigator reaches the home subtree")
    func setStateAboveNavigator_updatesHome() {
        let (host, owner, box) = pumpHost { count in
            Navigator(home: HomeLabel(text: "count: \(count)"))
        }

        #expect(findWidget(HomeLabel.self, in: host)?.text == "count: 0")

        box.state!.setState { box.state!.count = 1 }
        owner.buildScopeWithCallback(host)

        #expect(findWidget(HomeLabel.self, in: host)?.text == "count: 1")
    }

    @Test("setState above MacosApp reaches the home subtree")
    func setStateAboveMacosApp_updatesHome() {
        // The exact repro shape from ScreenShellApp: a stateful root above
        // MacosApp whose counter must reach the content below the Navigator
        // that MacosApp wraps around its home.
        let (host, owner, box) = pumpHost { count in
            MacosApp(home: HomeLabel(text: "taps: \(count)"))
        }

        #expect(findWidget(HomeLabel.self, in: host)?.text == "taps: 0")

        box.state!.setState { box.state!.count = 3 }
        owner.buildScopeWithCallback(host)

        #expect(findWidget(HomeLabel.self, in: host)?.text == "taps: 3")
    }

    @Test("home changing widget type remounts the subtree")
    func homeTypeChange_remounts() {
        let (host, owner, box) = pumpHost { count in
            Navigator(
                home: count == 0
                    ? HomeLabel(text: "before") as Widget
                    : SwappedLabel(text: "after")
            )
        }

        #expect(findWidget(HomeLabel.self, in: host) != nil)
        #expect(findWidget(SwappedLabel.self, in: host) == nil)

        box.state!.setState { box.state!.count = 1 }
        owner.buildScopeWithCallback(host)

        #expect(findWidget(HomeLabel.self, in: host) == nil)
        #expect(findWidget(SwappedLabel.self, in: host)?.text == "after")
    }
}
