// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A render object that rotates its child by an integral number of quarter turns.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/rotated_box.dart`

import FlutterSwiftBridge

// MARK: - Private Constants

/// The number of radians in a quarter turn (90 degrees).
///
/// **Dart Source:** rotated_box.dart:17
private let kQuarterTurnsInRadians: Double = Double.pi / 2.0

// MARK: - TransformLayer Stub

/// A composited layer that applies a transform (matrix) to its children.
///
/// This is a minimal stub for forward reference. The full implementation
/// will be provided in a later subtask when the full Layer hierarchy is
/// migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `TransformLayer`
public class TransformLayer: ContainerLayer {

    /// Creates a transform layer.
    ///
    /// **Dart Source:** `layer.dart:2038-2047`
    public init(transform: Matrix4? = nil, offset: Offset = .zero) {
        self._transform = transform
        self._offset = offset
        super.init()
    }

    /// The matrix to apply before compositing.
    ///
    /// **Dart Source:** `layer.dart:2055`
    public var transform: Matrix4? {
        get { _transform }
        set {
            _transform = newValue
            markNeedsAddToScene()
        }
    }
    private var _transform: Matrix4?

    /// The offset to apply before compositing.
    ///
    /// **Dart Source:** `layer.dart:2071`
    public var offset: Offset {
        get { _offset }
        set {
            if _offset == newValue { return }
            _offset = newValue
            markNeedsAddToScene()
        }
    }
    private var _offset: Offset

    /// Uploads this layer to the engine.
    ///
    /// **Dart Source:** `layer.dart:2087-2109`
    public override func addToScene(_ builder: any SceneBuilder) {
        assert(_transform != nil)
        var effectiveTransform = _transform!
        if _offset != Offset.zero {
            let translation = Matrix4.translationValues(_offset.dx, _offset.dy, 0)
            effectiveTransform = translation * effectiveTransform
        }
        engineLayer = builder.pushTransform(
            effectiveTransform.storage,
            oldLayer: _engineLayer as? TransformEngineLayer
        )
        addChildrenToScene(builder)
        builder.pop()
    }

    public override func applyTransform(_ child: Layer?, _ transform: inout Matrix4) {
        guard let t = _transform else { return }
        var effectiveTransform = t
        if _offset != Offset.zero {
            effectiveTransform = Matrix4.translationValues(_offset.dx, _offset.dy, 0) * effectiveTransform
        }
        transform = transform * effectiveTransform
    }
}

// MARK: - RenderRotatedBox

/// Rotates its child by an integral number of quarter turns.
///
/// Unlike `RenderTransform`, which applies a transform just prior to painting,
/// this object applies its rotation prior to layout, which means the entire
/// rotated box consumes only as much space as required by the rotated child.
///
/// **Dart Source:** rotated_box.dart:24-151
public class RenderRotatedBox: RenderBox {

    // MARK: - Initializer

    /// Creates a rotated render box.
    ///
    /// **Dart Source:** rotated_box.dart:26-28
    public init(quarterTurns: Int, child: RenderBox? = nil) {
        self._quarterTurns = quarterTurns
        super.init()
        self.child = child
    }

    // MARK: - Child Management (RenderObjectWithChildMixin pattern)

    /// The single child of this render object.
    ///
    /// In Dart, `RenderRotatedBox` uses `RenderObjectWithChildMixin<RenderBox>`
    /// to manage its single child. In Swift, since generic mixins are not
    /// supported, the child property is implemented directly.
    ///
    /// **Dart Source:** rotated_box.dart:24 (via RenderObjectWithChildMixin)
    public var child: RenderBox? {
        get { _child }
        set {
            if _child != nil {
                // dropChild equivalent: clear parent reference
                _child!.parentData = nil
            }
            _child = newValue
            if _child != nil {
                // adoptChild equivalent: set up parent data and parent reference
                setupParentData(_child!)
            }
            markNeedsLayout()
        }
    }
    private var _child: RenderBox?

    // MARK: - Quarter Turns Property

    /// The number of clockwise quarter turns the child should be rotated.
    ///
    /// **Dart Source:** rotated_box.dart:31-39
    public var quarterTurns: Int {
        get { _quarterTurns }
        set {
            if _quarterTurns == newValue {
                return
            }
            _quarterTurns = newValue
            markNeedsLayout()
        }
    }

    /// **Dart Source:** rotated_box.dart:32
    private var _quarterTurns: Int

    // MARK: - Private Computed Properties

    /// Whether the rotation causes the child to be laid out vertically
    /// (i.e., an odd number of quarter turns).
    ///
    /// **Dart Source:** rotated_box.dart:41
    private var _isVertical: Bool {
        quarterTurns % 2 != 0
    }

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width.
    ///
    /// When vertical, swaps to use the child's minimum intrinsic height instead.
    ///
    /// **Dart Source:** rotated_box.dart:44-49
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        return _isVertical
            ? child.getMinIntrinsicHeight(height)
            : child.getMinIntrinsicWidth(height)
    }

    /// Computes the maximum intrinsic width.
    ///
    /// When vertical, swaps to use the child's maximum intrinsic height instead.
    ///
    /// **Dart Source:** rotated_box.dart:52-57
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        return _isVertical
            ? child.getMaxIntrinsicHeight(height)
            : child.getMaxIntrinsicWidth(height)
    }

    /// Computes the minimum intrinsic height.
    ///
    /// When vertical, swaps to use the child's minimum intrinsic width instead.
    ///
    /// **Dart Source:** rotated_box.dart:60-65
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        return _isVertical
            ? child.getMinIntrinsicWidth(width)
            : child.getMinIntrinsicHeight(width)
    }

    /// Computes the maximum intrinsic height.
    ///
    /// When vertical, swaps to use the child's maximum intrinsic width instead.
    ///
    /// **Dart Source:** rotated_box.dart:68-73
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        return _isVertical
            ? child.getMaxIntrinsicWidth(width)
            : child.getMaxIntrinsicHeight(width)
    }

    // MARK: - Paint Transform

    /// The transform matrix computed during layout, used for painting and
    /// hit testing the child.
    ///
    /// **Dart Source:** rotated_box.dart:75
    private var _paintTransform: Matrix4?

    // MARK: - Dry Layout

    /// Computes the dry layout size for the given constraints.
    ///
    /// Flips constraints when vertical, and swaps the resulting child size
    /// dimensions accordingly.
    ///
    /// **Dart Source:** rotated_box.dart:79-85
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        guard let child = child else {
            return constraints.smallest
        }
        let childSize = child.getDryLayout(
            _isVertical ? constraints.flipped : constraints
        )
        return _isVertical
            ? Size(childSize.height, childSize.width)
            : childSize
    }

    // MARK: - Layout

    /// Performs layout by laying out the child with potentially flipped
    /// constraints, computing the size, and building the paint transform
    /// matrix.
    ///
    /// The paint transform translates to the center of this box, rotates
    /// by the appropriate angle, then translates back by half the child's
    /// size.
    ///
    /// **Dart Source:** rotated_box.dart:88-100
    public override func performLayout() {
        _paintTransform = nil
        if let child = child {
            child.layout(
                _isVertical ? boxConstraints.flipped : boxConstraints,
                parentUsesSize: true
            )
            size = _isVertical
                ? Size(child.size.height, child.size.width)
                : child.size
            // Build the paint transform:
            //   1. Translate to center of this box
            //   2. Rotate by quarterTurns * 90 degrees
            //   3. Translate back by half the child's size
            var transform = Matrix4.identity()
            transform.translate(size.width / 2.0, size.height / 2.0)
            transform.rotateZ(kQuarterTurnsInRadians * Double(quarterTurns % 4))
            transform.translate(-child.size.width / 2.0, -child.size.height / 2.0)
            _paintTransform = transform
        } else {
            size = boxConstraints.smallest
        }
    }

    // MARK: - Hit Testing

    /// Hit tests children using the paint transform.
    ///
    /// Uses `result.addWithPaintTransform` to apply the rotation transform
    /// before delegating to the child's hit test.
    ///
    /// **Dart Source:** rotated_box.dart:103-115
    public override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        assert(_paintTransform != nil || debugNeedsLayout || child == nil)
        guard let child = child, let paintTransform = _paintTransform else {
            return false
        }
        return result.addWithPaintTransform(
            transform: paintTransform,
            position: position,
            hitTest: { result, position in
                return child.hitTest(result, position: position)
            }
        )
    }

    // MARK: - Painting

    /// Private helper that paints the child at the given offset.
    ///
    /// **Dart Source:** rotated_box.dart:117-119
    private func _paintChild(_ context: PaintingContext, _ offset: Offset) {
        // context.paintChild(child!, offset)
        // TODO: PaintingContext.paintChild not yet available in stub.
        _ = context
        _ = offset
    }

    /// Paints the rotated child using pushTransform.
    ///
    /// When a child is present, uses `context.pushTransform` with the
    /// `_paintTransform` matrix to paint the child in its rotated position.
    /// The transform layer is cached in `_transformLayer` for reuse.
    ///
    /// **Dart Source:** rotated_box.dart:122-134
    public override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child != nil {
            // TODO: Full implementation requires PaintingContext.pushTransform
            // _transformLayer.layer = context.pushTransform(
            //     needsCompositing,
            //     offset,
            //     _paintTransform!,
            //     _paintChild,
            //     oldLayer: _transformLayer.layer,
            // )
        } else {
            _transformLayer.layer = nil
        }
    }

    // MARK: - Transform Layer

    /// A handle to the `TransformLayer` used for painting.
    ///
    /// This layer is reused across frames to avoid unnecessary layer creation.
    ///
    /// **Dart Source:** rotated_box.dart:136
    private let _transformLayer: LayerHandle<TransformLayer> = LayerHandle<TransformLayer>()

    // MARK: - Disposal

    /// Releases the transform layer resources.
    ///
    /// Clears the `_transformLayer` handle and calls super's dispose.
    ///
    /// **Dart Source:** rotated_box.dart:139-142
    public override func dispose() {
        _transformLayer.layer = nil
        super.dispose()
    }

    // MARK: - Paint Transform Application

    /// Multiplies the given transform by this render object's paint transform.
    ///
    /// This is called by the framework to convert coordinates between this
    /// render object and its child.
    ///
    /// **Dart Source:** rotated_box.dart:145-150
    public override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        if let paintTransform = _paintTransform {
            transform = transform * paintTransform
        }
        super.applyPaintTransform(child, &transform)
    }
}
