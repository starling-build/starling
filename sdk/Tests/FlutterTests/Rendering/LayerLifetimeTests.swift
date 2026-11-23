// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// A dropped layer tree is freed.
///
/// Dart's GC reclaims a cycle; ARC never does. `Layer._parent`, `Layer._owner` and a
/// layer's `_parentHandle` all pointed back up (or at the layer itself), so a removed
/// view's whole layer tree outlived it - 2 layers per view on the iPad's second-surface
/// spike. These pin that a tree with nothing holding it is gone.

import XCTest
@testable import Flutter
import FlutterSwiftBridge

final class LayerLifetimeTests: XCTestCase {
    func testADroppedLayerTreeIsFreed() {
        weak var root: ContainerLayer?
        weak var child: ContainerLayer?
        weak var grandchild: ContainerLayer?
        autoreleasepool {
            let r = ContainerLayer()
            let c = ContainerLayer()
            let g = ContainerLayer()
            r.append(c)
            c.append(g)
            root = r
            child = c
            grandchild = g
            XCTAssertTrue(g.parent === c)
        }
        XCTAssertNil(root, "the root must be freed once nothing holds it")
        XCTAssertNil(child, "a child must not be held by its own parent handle")
        XCTAssertNil(grandchild)
    }

    func testAnOwnerThatHoldsItsRootLayerIsNotAKeptCycle() {
        // A RenderView holds its root layer and is that layer's `owner`.
        final class Owner { var root: ContainerLayer? }
        weak var owner: Owner?
        weak var layer: ContainerLayer?
        autoreleasepool {
            let o = Owner()
            let l = ContainerLayer()
            o.root = l
            l.attach(o)
            owner = o
            layer = l
        }
        XCTAssertNil(owner, "the layer's owner back-reference must not keep the owner alive")
        XCTAssertNil(layer)
    }

    func testARemovedChildIsStillFreedAndLeavesNoParent() {
        let root = ContainerLayer()
        weak var child: ContainerLayer?
        autoreleasepool {
            let c = ContainerLayer()
            root.append(c)
            child = c
            c.remove()
            XCTAssertNil(c.parent)
        }
        XCTAssertNil(child)
        XCTAssertNil(root.firstChild)
    }
}
