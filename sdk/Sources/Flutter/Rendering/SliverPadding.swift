// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Sliver padding render objects.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/sliver_padding.dart`

import FlutterSwiftBridge

// =============================================================================
// MARK: - RenderSliverEdgeInsetsPadding
// =============================================================================

/// Insets a `RenderSliver` by applying `resolvedPadding` on each side.
///
/// A `RenderSliverEdgeInsetsPadding` subclass wraps the
/// `SliverGeometry.layoutExtent` of its child. Any incoming
/// `SliverConstraints.overlap` is ignored and not passed on to the child.
///
/// Applying padding in the main extent of the viewport to slivers that have
/// scroll effects is likely to have undesired effects. For example, wrapping a
/// `SliverPersistentHeader` with `pinned:true` will cause only the appbar to
/// stay pinned while the padding will scroll away.
///
/// In Dart, `RenderSliverEdgeInsetsPadding` extends `RenderSliver` and mixes
/// in `RenderObjectWithChildMixin<RenderSliver>`. In Swift, since generic
/// mixins are not supported, the single-child management is implemented
/// directly on the class.
///
/// **Dart Source:** `sliver_padding.dart:27-299`
open class RenderSliverEdgeInsetsPadding: RenderSliver {

    // MARK: - Child Management (RenderObjectWithChildMixin pattern)

    /// The single child of this render sliver.
    ///
    /// In Dart, `RenderSliverEdgeInsetsPadding` uses
    /// `RenderObjectWithChildMixin<RenderSliver>` to manage its single child.
    /// In Swift, the child property is implemented directly.
    ///
    /// **Dart Source:** `sliver_padding.dart:27` (via RenderObjectWithChildMixin)
    public var child: RenderSliver? {
        get { _child }
        set {
            if let oldChild = _child {
                oldChild.parent = nil
                oldChild.parentData = nil
            }
            _child = newValue
            if let newChild = _child {
                setupParentData(newChild)
                newChild.parent = self
            }
            markNeedsLayout()
        }
    }
    private var _child: RenderSliver?

    /// **Dart Source:** `RenderObjectWithChildMixin.visitChildren`
    open override func visitChildren(_ visitor: RenderObjectVisitor) {
        if let child = _child {
            visitor(child)
        }
    }

    // MARK: - Resolved Padding

    /// The amount to pad the child in each dimension.
    ///
    /// The offsets are specified in terms of visual edges, left, top, right, and
    /// bottom. These values are not affected by the `TextDirection`.
    ///
    /// Must not be nil or contain negative values when `performLayout` is called.
    ///
    /// **Dart Source:** `sliver_padding.dart:35`
    open var resolvedPadding: EdgeInsets? { nil }

    // MARK: - Directional Padding Properties

    /// The padding in the scroll direction on the side nearest the 0.0 scroll
    /// direction.
    ///
    /// Only valid after layout has started, since before layout the render object
    /// doesn't know what direction it will be laid out in.
    ///
    /// **Dart Source:** `sliver_padding.dart:41-52`
    public var beforePadding: Double {
        assert(resolvedPadding != nil)
        switch applyGrowthDirectionToAxisDirection(
            sliverConstraints.axisDirection,
            sliverConstraints.growthDirection
        ) {
        case .up:
            return resolvedPadding!.bottom
        case .right:
            return resolvedPadding!.left
        case .down:
            return resolvedPadding!.top
        case .left:
            return resolvedPadding!.right
        }
    }

    /// The padding in the scroll direction on the side furthest from the 0.0
    /// scroll offset.
    ///
    /// Only valid after layout has started, since before layout the render object
    /// doesn't know what direction it will be laid out in.
    ///
    /// **Dart Source:** `sliver_padding.dart:58-69`
    public var afterPadding: Double {
        assert(resolvedPadding != nil)
        switch applyGrowthDirectionToAxisDirection(
            sliverConstraints.axisDirection,
            sliverConstraints.growthDirection
        ) {
        case .up:
            return resolvedPadding!.top
        case .right:
            return resolvedPadding!.right
        case .down:
            return resolvedPadding!.bottom
        case .left:
            return resolvedPadding!.left
        }
    }

    /// The total padding in the `SliverConstraints.axisDirection`. (In other
    /// words, for a vertical downwards-growing list, the sum of the padding on
    /// the top and bottom.)
    ///
    /// Only valid after layout has started, since before layout the render object
    /// doesn't know what direction it will be laid out in.
    ///
    /// **Dart Source:** `sliver_padding.dart:77-80`
    public var mainAxisPadding: Double {
        assert(resolvedPadding != nil)
        return resolvedPadding!.along(sliverConstraints.axis)
    }

    /// The total padding in the cross-axis direction. (In other words, for a
    /// vertical downwards-growing list, the sum of the padding on the left and
    /// right.)
    ///
    /// Only valid after layout has started, since before layout the render object
    /// doesn't know what direction it will be laid out in.
    ///
    /// **Dart Source:** `sliver_padding.dart:88-94`
    public var crossAxisPadding: Double {
        assert(resolvedPadding != nil)
        switch sliverConstraints.axis {
        case .horizontal:
            return resolvedPadding!.vertical
        case .vertical:
            return resolvedPadding!.horizontal
        }
    }

    // MARK: - Parent Data

    /// Sets up `SliverPhysicalParentData` for the given child.
    ///
    /// **Dart Source:** `sliver_padding.dart:97-101`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverPhysicalParentData) {
            child.parentData = SliverPhysicalParentData()
        }
    }

    // MARK: - Layout

    /// Performs the layout of this sliver padding.
    ///
    /// This is the most complex part of the sliver padding implementation.
    /// It computes the before/after/main/cross padding amounts based on axis
    /// direction and growth direction, deflates constraints by padding, lays
    /// out the child with deflated constraints, adjusts the child's geometry
    /// by padding amounts, and sets parent data paint offset.
    ///
    /// **Dart Source:** `sliver_padding.dart:104-215`
    open override func performLayout() {
        let constraints = self.sliverConstraints

        func paintOffset(from: Double, to: Double) -> Double {
            calculatePaintOffset(constraints, from: from, to: to)
        }
        func cacheOffset(from: Double, to: Double) -> Double {
            calculateCacheOffset(constraints, from: from, to: to)
        }

        assert(self.resolvedPadding != nil)
        let resolvedPadding = self.resolvedPadding!
        let beforePadding = self.beforePadding
        let afterPadding = self.afterPadding
        let mainAxisPadding = self.mainAxisPadding
        let crossAxisPadding = self.crossAxisPadding

        if child == nil {
            let paintExtent = paintOffset(from: 0.0, to: mainAxisPadding)
            let cacheExtent = cacheOffset(from: 0.0, to: mainAxisPadding)
            geometry = SliverGeometry(
                scrollExtent: mainAxisPadding,
                paintExtent: min(paintExtent, constraints.remainingPaintExtent),
                maxPaintExtent: mainAxisPadding,
                cacheExtent: cacheExtent
            )
            return
        }

        let beforePaddingPaintExtent = paintOffset(from: 0.0, to: beforePadding)
        var overlap = constraints.overlap
        if overlap > 0 {
            overlap = max(0.0, constraints.overlap - beforePaddingPaintExtent)
        }

        child!.layout(
            constraints.copyWith(
                scrollOffset: max(0.0, constraints.scrollOffset - beforePadding),
                precedingScrollExtent: beforePadding + constraints.precedingScrollExtent,
                overlap: overlap,
                remainingPaintExtent:
                    constraints.remainingPaintExtent - paintOffset(from: 0.0, to: beforePadding),
                crossAxisExtent: max(0.0, constraints.crossAxisExtent - crossAxisPadding),
                remainingCacheExtent:
                    constraints.remainingCacheExtent - cacheOffset(from: 0.0, to: beforePadding),
                cacheOrigin: min(0.0, constraints.cacheOrigin + beforePadding)
            ),
            parentUsesSize: true
        )

        let childLayoutGeometry = child!.geometry!
        if childLayoutGeometry.scrollOffsetCorrection != nil {
            geometry = SliverGeometry(
                scrollOffsetCorrection: childLayoutGeometry.scrollOffsetCorrection
            )
            return
        }

        let scrollExtent = childLayoutGeometry.scrollExtent
        let beforePaddingCacheExtent = cacheOffset(from: 0.0, to: beforePadding)
        let afterPaddingCacheExtent = cacheOffset(
            from: beforePadding + scrollExtent,
            to: mainAxisPadding + scrollExtent
        )
        let afterPaddingPaintExtent = paintOffset(
            from: beforePadding + scrollExtent,
            to: mainAxisPadding + scrollExtent
        )
        let mainAxisPaddingCacheExtent = beforePaddingCacheExtent + afterPaddingCacheExtent
        let mainAxisPaddingPaintExtent = beforePaddingPaintExtent + afterPaddingPaintExtent
        let paintExtent = min(
            beforePaddingPaintExtent
                + max(
                    childLayoutGeometry.paintExtent,
                    childLayoutGeometry.layoutExtent + afterPaddingPaintExtent
                ),
            constraints.remainingPaintExtent
        )

        geometry = SliverGeometry(
            scrollExtent: mainAxisPadding + scrollExtent,
            paintExtent: paintExtent,
            paintOrigin: childLayoutGeometry.paintOrigin,
            layoutExtent: min(
                mainAxisPaddingPaintExtent + childLayoutGeometry.layoutExtent,
                paintExtent
            ),
            maxPaintExtent: mainAxisPadding + childLayoutGeometry.maxPaintExtent,
            hitTestExtent: max(
                mainAxisPaddingPaintExtent + childLayoutGeometry.paintExtent,
                beforePaddingPaintExtent + childLayoutGeometry.hitTestExtent
            ),
            hasVisualOverflow: childLayoutGeometry.hasVisualOverflow,
            cacheExtent: min(
                mainAxisPaddingCacheExtent + childLayoutGeometry.cacheExtent,
                constraints.remainingCacheExtent
            )
        )

        let calculatedOffset: Double = {
            switch applyGrowthDirectionToAxisDirection(
                constraints.axisDirection,
                constraints.growthDirection
            ) {
            case .up:
                return paintOffset(
                    from: resolvedPadding.bottom + scrollExtent,
                    to: resolvedPadding.vertical + scrollExtent
                )
            case .left:
                return paintOffset(
                    from: resolvedPadding.right + scrollExtent,
                    to: resolvedPadding.horizontal + scrollExtent
                )
            case .right:
                return paintOffset(from: 0.0, to: resolvedPadding.left)
            case .down:
                return paintOffset(from: 0.0, to: resolvedPadding.top)
            }
        }()

        let childParentData = child!.parentData! as! SliverPhysicalParentData
        switch constraints.axis {
        case .horizontal:
            childParentData.paintOffset = Offset(calculatedOffset, resolvedPadding.top)
        case .vertical:
            childParentData.paintOffset = Offset(resolvedPadding.left, calculatedOffset)
        }

        assert(beforePadding == self.beforePadding)
        assert(afterPadding == self.afterPadding)
        assert(mainAxisPadding == self.mainAxisPadding)
        assert(crossAxisPadding == self.crossAxisPadding)
    }

    // MARK: - Hit Testing

    /// Hit tests the children of this sliver, adjusting positions by the
    /// paint offset.
    ///
    /// **Dart Source:** `sliver_padding.dart:218-236`
    open override func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        if let child = child, child.geometry!.hitTestExtent > 0.0 {
            let childParentData = child.parentData! as! SliverPhysicalParentData
            return result.addWithAxisOffset(
                paintOffset: childParentData.paintOffset,
                mainAxisOffset: childMainAxisPosition(child),
                crossAxisOffset: childCrossAxisPosition(child),
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition,
                hitTest: child.hitTest
            )
        }
        return false
    }

    // MARK: - Child Position Methods

    /// Returns the main axis position of the child relative to this sliver's
    /// visible leading edge.
    ///
    /// **Dart Source:** `sliver_padding.dart:239-242`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        assert(child === self.child)
        return calculatePaintOffset(sliverConstraints, from: 0.0, to: beforePadding)
    }

    /// Returns the cross axis position of the child.
    ///
    /// **Dart Source:** `sliver_padding.dart:245-252`
    open override func childCrossAxisPosition(_ child: RenderObject) -> Double {
        assert(child === self.child)
        assert(resolvedPadding != nil)
        switch sliverConstraints.axis {
        case .horizontal:
            return resolvedPadding!.top
        case .vertical:
            return resolvedPadding!.left
        }
    }

    /// Returns the scroll offset for the leading edge of the given child.
    ///
    /// **Dart Source:** `sliver_padding.dart:255-258`
    open override func childScrollOffset(_ child: RenderObject) -> Double? {
        assert(child.parent === self)
        return beforePadding
    }

    // MARK: - Paint Transform

    /// Applies the paint transform for a child using its parent data paint
    /// offset.
    ///
    /// **Dart Source:** `sliver_padding.dart:261-265`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        assert(child === self.child)
        let childParentData = child.parentData! as! SliverPhysicalParentData
        childParentData.applyPaintTransform(&transform)
    }

    // MARK: - Painting

    /// Paints the child at its paint offset if it is visible.
    ///
    /// **Dart Source:** `sliver_padding.dart:268-274`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if let child = child, child.geometry!.visible {
            let childParentData = child.parentData! as! SliverPhysicalParentData
            context.paintChild(child, offset + childParentData.paintOffset)
        }
    }

    // MARK: - Debug Paint

    /// Draws debug visualizations for the padding around the child.
    ///
    /// **Dart Source:** `sliver_padding.dart:277-298`
    open override func debugPaint(_ context: PaintingContext, _ offset: Offset) {
        super.debugPaint(context, offset)
        assert({
            if debugPaintSizeEnabled {
                let parentSize = getAbsoluteSize()
                let outerRect = Rect.fromLTWH(
                    offset.dx, offset.dy,
                    parentSize.width, parentSize.height
                )
                var innerRect: Rect? = nil
                if let child = child {
                    let childSize = child.getAbsoluteSize()
                    let childParentData = child.parentData! as! SliverPhysicalParentData
                    innerRect = Rect.fromLTWH(
                        offset.dx + childParentData.paintOffset.dx,
                        offset.dy + childParentData.paintOffset.dy,
                        childSize.width,
                        childSize.height
                    )
                    assert(innerRect!.top >= outerRect.top)
                    assert(innerRect!.left >= outerRect.left)
                    assert(innerRect!.right <= outerRect.right)
                    assert(innerRect!.bottom <= outerRect.bottom)
                }
                debugPaintPadding(context.canvas, outerRect, innerRect)
            }
            return true
        }())
    }
}

// =============================================================================
// MARK: - RenderSliverPadding
// =============================================================================

/// Insets a `RenderSliver`, applying padding on each side.
///
/// A `RenderSliverPadding` object wraps the `SliverGeometry.layoutExtent` of
/// its child. Any incoming `SliverConstraints.overlap` is ignored and not
/// passed on to the child.
///
/// Applying padding in the main extent of the viewport to slivers that have
/// scroll effects is likely to have undesired effects. For example, wrapping a
/// `SliverPersistentHeader` with `pinned:true` will cause only the appbar to
/// stay pinned while the padding will scroll away.
///
/// **Dart Source:** `sliver_padding.dart:308-380`
open class RenderSliverPadding: RenderSliverEdgeInsetsPadding {

    // MARK: - Initializer

    /// Creates a render object that insets its child in a viewport.
    ///
    /// The `padding` argument must have non-negative insets.
    ///
    /// **Dart Source:** `sliver_padding.dart:312-320`
    public init(
        padding: any EdgeInsetsGeometry,
        textDirection: TextDirection? = nil,
        child: RenderSliver? = nil
    ) {
        assert(padding.isNonNegative)
        self._padding = padding
        self._textDirection = textDirection
        super.init()
        self.child = child
    }

    // MARK: - Resolved Padding

    /// The resolved padding, computed from `padding` and `textDirection`.
    ///
    /// **Dart Source:** `sliver_padding.dart:323-324`
    open override var resolvedPadding: EdgeInsets? { _resolvedPadding }
    private var _resolvedPadding: EdgeInsets?

    /// Resolves the padding using the current text direction, if not already
    /// resolved.
    ///
    /// **Dart Source:** `sliver_padding.dart:326-332`
    private func _resolve() {
        if _resolvedPadding != nil {
            return
        }
        _resolvedPadding = _padding.resolve(_textDirection)
        assert(_resolvedPadding!.isNonNegative)
    }

    /// Marks the resolved padding as needing re-resolution, and marks this
    /// render object as needing layout.
    ///
    /// **Dart Source:** `sliver_padding.dart:334-337`
    private func _markNeedsResolution() {
        _resolvedPadding = nil
        markNeedsLayout()
    }

    // MARK: - Padding Property

    /// The amount to pad the child in each dimension.
    ///
    /// If this is set to an `EdgeInsetsDirectional` object, then `textDirection`
    /// must not be nil.
    ///
    /// **Dart Source:** `sliver_padding.dart:343-352`
    public var padding: any EdgeInsetsGeometry {
        get { _padding }
        set {
            assert(newValue.isNonNegative)
            if _padding == newValue { return }
            _padding = newValue
            _markNeedsResolution()
        }
    }
    private var _padding: any EdgeInsetsGeometry

    // MARK: - Text Direction Property

    /// The text direction with which to resolve `padding`.
    ///
    /// This may be changed to nil, but only after the `padding` has been changed
    /// to a value that does not depend on the direction.
    ///
    /// **Dart Source:** `sliver_padding.dart:358-366`
    public var textDirection: TextDirection? {
        get { _textDirection }
        set {
            if _textDirection == newValue { return }
            _textDirection = newValue
            _markNeedsResolution()
        }
    }
    private var _textDirection: TextDirection?

    // MARK: - Layout Override

    /// Resolves the padding before performing layout.
    ///
    /// **Dart Source:** `sliver_padding.dart:369-372`
    open override func performLayout() {
        _resolve()
        super.performLayout()
    }

    // MARK: - Debug

    /// Fills diagnostic properties for debugging.
    ///
    /// **Dart Source:** `sliver_padding.dart:375-379`
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(
            DiagnosticsProperty<any EdgeInsetsGeometry>("padding", padding)
        )
        properties.add(
            EnumProperty<TextDirection>("textDirection", textDirection, defaultValue: nil)
        )
    }
}

// MARK: - SingleChildSliverHost Conformance

extension RenderSliverEdgeInsetsPadding: SingleChildSliverHost {}
