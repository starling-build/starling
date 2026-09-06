// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import Flutter
import FlutterSwiftBridge

/// A fade is an OPACITY LAYER in the scene, not a paint-or-skip switch.
/// `RenderAnimatedOpacity` once painted its child straight for every
/// non-zero alpha, which made every `FadeTransition` a one-frame blink.
final class RenderAnimatedOpacityPaintTests: XCTestCase {

    private func paint(opacity: Double) -> ContainerLayer {
        let child = RenderConstrainedBox(
            additionalConstraints: BoxConstraints.tight(Size(10, 10)))
        let box = RenderAnimatedOpacity(
            opacity: AlwaysStoppedAnimation(opacity), child: child)
        box.layout(BoxConstraints.tight(Size(10, 10)))
        let root = ContainerLayer()
        let context = PaintingContext(root, Rect.fromLTWH(0, 0, 10, 10))
        box.paint(context, .zero)
        context.stopRecordingIfNeeded()
        return root
    }

    private func opacityLayer(in root: ContainerLayer) -> OpacityLayer? {
        var layer = root.firstChild
        while let l = layer {
            if let o = l as? OpacityLayer { return o }
            layer = l.nextSibling
        }
        return nil
    }

    func testPartialAlphaPaintsThroughAnOpacityLayer() {
        let root = paint(opacity: 0.5)
        let layer = opacityLayer(in: root)
        XCTAssertNotNil(layer, "a half-transparent child must paint into an OpacityLayer")
        if let alpha = layer?.alpha {
            XCTAssertTrue((127...128).contains(alpha), "alpha \(alpha) is not half")
        }
    }

    func testFullAlphaPaintsDirectly() {
        XCTAssertNil(opacityLayer(in: paint(opacity: 1.0)),
                     "an opaque child needs no opacity layer")
    }

    func testZeroAlphaPaintsNothing() {
        XCTAssertNil(paint(opacity: 0.0).firstChild, "alpha 0 paints nothing at all")
    }
}
