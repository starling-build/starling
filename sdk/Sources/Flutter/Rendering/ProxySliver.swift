// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Proxy sliver render objects that pass layout, painting, and hit testing
/// to a single sliver child.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/proxy_sliver.dart`

import FlutterSwiftBridge

// MARK: - RenderProxySliver

/// A base class for sliver render objects that resemble their children.
///
/// A proxy sliver has a single child and mimics all the properties of
/// that child by calling through to the child for each function in the render
/// sliver protocol. For example, a proxy sliver determines its geometry by
/// asking its sliver child to layout with the same constraints and then
/// matching the geometry.
///
/// A proxy sliver isn't useful on its own because you might as well just
/// replace the proxy sliver with its child. However, `RenderProxySliver` is a
/// useful base class for render objects that wish to mimic most, but not all,
/// of the properties of their sliver child.
///
/// In Dart, `RenderProxySliver` extends `RenderSliver` and mixes in
/// `RenderObjectWithChildMixin<RenderSliver>`. In Swift, since generic mixins
/// are not supported, the single-child management and proxy behavior are
/// implemented directly on the class.
///
/// **Dart Source:** proxy_sliver.dart:34-100
open class RenderProxySliver: RenderSliver {

    // MARK: - Initializer

    /// Creates a proxy render sliver.
    ///
    /// Proxy render slivers aren't created directly because they proxy
    /// the render sliver protocol to their sliver `child`. Instead, use one of
    /// the subclasses.
    ///
    /// **Dart Source:** proxy_sliver.dart:41-43
    public init(child: RenderSliver? = nil) {
        super.init()
        self.child = child
    }

    // MARK: - Child Management (RenderObjectWithChildMixin pattern)

    /// The single child of this render object.
    ///
    /// In Dart, `RenderProxySliver` uses `RenderObjectWithChildMixin<RenderSliver>`
    /// to manage its single child. In Swift, since generic mixins are not
    /// supported, the child property is implemented directly.
    ///
    /// **Dart Source:** proxy_sliver.dart:35 (via RenderObjectWithChildMixin)
    public var child: RenderSliver? {
        get { _child }
        set {
            if let oldChild = _child {
                oldChild.parentData = nil
            }
            _child = newValue
            if let newChild = _child {
                setupParentData(newChild)
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

    // MARK: - Semantics

    /// Returns the semantic bounds of this sliver.
    ///
    /// If a child is present, returns the child's semantic bounds.
    /// Otherwise, falls back to the superclass implementation.
    ///
    /// **Dart Source:** proxy_sliver.dart:46-51
    open override var semanticBounds: Rect {
        if let child = child {
            return child.semanticBounds
        }
        return super.semanticBounds
    }

    // MARK: - Parent Data

    /// Sets up `SliverPhysicalParentData` for the given child.
    ///
    /// **Dart Source:** proxy_sliver.dart:54-58
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverPhysicalParentData) {
            child.parentData = SliverPhysicalParentData()
        }
    }

    // MARK: - Layout

    /// Performs layout by delegating to the child.
    ///
    /// Lays out the child with the same constraints (passing
    /// `parentUsesSize: true`) and takes on the child's geometry.
    ///
    /// **Dart Source:** proxy_sliver.dart:61-65
    open override func performLayout() {
        assert(child != nil)
        child!.layout(constraints, parentUsesSize: true)
        geometry = child!.geometry
    }

    // MARK: - Painting

    /// Paints the child at the given offset.
    ///
    /// If there is no child, this is a no-op.
    ///
    /// **Dart Source:** proxy_sliver.dart:68-72
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if let child = child {
            context.paintChild(child, offset)
        }
    }

    // MARK: - Hit Testing

    /// Hit tests the children at the given position.
    ///
    /// Returns true if the child is non-nil, has a positive hit test extent,
    /// and reports a hit.
    ///
    /// **Dart Source:** proxy_sliver.dart:75-87
    open override func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        guard let child = child,
              let geometry = child.geometry,
              geometry.hitTestExtent > 0
        else {
            return false
        }
        return child.hitTest(
            result,
            mainAxisPosition: mainAxisPosition,
            crossAxisPosition: crossAxisPosition
        )
    }

    // MARK: - Child Position

    /// Returns the distance from the leading visible edge of this sliver to
    /// the leading visible edge of the child.
    ///
    /// For a proxy sliver, this is always 0.0 since the child occupies the
    /// same position.
    ///
    /// **Dart Source:** proxy_sliver.dart:90-93
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        assert(child === self.child)
        return 0.0
    }

    // MARK: - Paint Transform

    /// Applies the paint transform for the child.
    ///
    /// Uses `SliverPhysicalParentData.applyPaintTransform` to apply the
    /// child's paint offset.
    ///
    /// **Dart Source:** proxy_sliver.dart:96-99
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        let childParentData = child.parentData as! SliverPhysicalParentData
        childParentData.applyPaintTransform(&transform)
    }
}

// MARK: - RenderSliverOpacity

/// Makes its sliver child partially transparent.
///
/// This class paints its sliver child into an intermediate buffer and then
/// blends the sliver child back into the scene, partially transparent.
///
/// For values of opacity other than 0.0 and 1.0, this class is relatively
/// expensive, because it requires painting the sliver child into an intermediate
/// buffer. For the value 0.0, the sliver child is not painted at all.
/// For the value 1.0, the sliver child is painted immediately without an
/// intermediate buffer.
///
/// **Dart Source:** proxy_sliver.dart:112-209
open class RenderSliverOpacity: RenderProxySliver {

    // MARK: - Initializer

    /// Creates a partially transparent render object.
    ///
    /// The `opacity` argument must be between 0.0 and 1.0, inclusive.
    ///
    /// **Dart Source:** proxy_sliver.dart:116-125
    public init(
        opacity: Double = 1.0,
        alwaysIncludeSemantics: Bool = false,
        sliver: RenderSliver? = nil
    ) {
        assert(opacity >= 0.0 && opacity <= 1.0)
        _opacity = opacity
        _alwaysIncludeSemantics = alwaysIncludeSemantics
        _alpha = Color.getAlphaFromOpacity(opacity)
        super.init(child: sliver)
    }

    // MARK: - Compositing

    /// Whether this render object always needs compositing.
    ///
    /// Returns true when the child is non-nil and alpha is greater than 0,
    /// meaning the opacity layer is needed for compositing.
    ///
    /// **Dart Source:** proxy_sliver.dart:128
    open override var alwaysNeedsCompositing: Bool {
        return child != nil && _alpha > 0
    }

    // MARK: - Alpha

    /// The computed alpha value (0-255) corresponding to the current opacity.
    ///
    /// **Dart Source:** proxy_sliver.dart:130
    private var _alpha: Int

    // MARK: - Opacity

    /// The fraction to scale the child's alpha value.
    ///
    /// An opacity of 1.0 is fully opaque. An opacity of 0.0 is fully transparent
    /// (i.e., invisible).
    ///
    /// Values 1.0 and 0.0 are painted with a fast path. Other values
    /// require painting the child into an intermediate buffer, which is
    /// expensive.
    ///
    /// **Dart Source:** proxy_sliver.dart:139-157
    public var opacity: Double {
        get { _opacity }
        set {
            assert(newValue >= 0.0 && newValue <= 1.0)
            if _opacity == newValue {
                return
            }
            let didNeedCompositing = alwaysNeedsCompositing
            let wasVisible = _alpha != 0
            _opacity = newValue
            _alpha = Color.getAlphaFromOpacity(_opacity)
            if didNeedCompositing != alwaysNeedsCompositing {
                markNeedsCompositingBitsUpdate()
            }
            markNeedsPaint()
            if wasVisible != (_alpha != 0) && !alwaysIncludeSemantics {
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _opacity: Double

    // MARK: - Always Include Semantics

    /// Whether child semantics are included regardless of the opacity.
    ///
    /// If false, semantics are excluded when `opacity` is 0.0.
    ///
    /// Defaults to false.
    ///
    /// **Dart Source:** proxy_sliver.dart:164-172
    public var alwaysIncludeSemantics: Bool {
        get { _alwaysIncludeSemantics }
        set {
            if newValue == _alwaysIncludeSemantics {
                return
            }
            _alwaysIncludeSemantics = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _alwaysIncludeSemantics: Bool

    // MARK: - Paint

    /// Paints the child with the current opacity.
    ///
    /// If the child is nil, or the child's geometry is not visible, no
    /// painting occurs. If alpha is 0, the layer is set to nil and painting
    /// is skipped. Otherwise, an `OpacityLayer` is pushed via the context.
    ///
    /// **Dart Source:** proxy_sliver.dart:174-189
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if let child = child, child.geometry?.visible == true {
            if _alpha == 0 {
                // No need to keep the layer. We'll create a new one if necessary.
                layer = nil
                return
            }
            assert(needsCompositing)
            layer = context.pushOpacity(offset, _alpha, super.paint, oldLayer: layer as? OpacityLayer)
        }
    }

    // MARK: - Semantics

    /// Visits children for semantics purposes.
    ///
    /// Skips children when fully transparent (alpha == 0) unless
    /// `alwaysIncludeSemantics` is true.
    ///
    /// **Dart Source:** proxy_sliver.dart:192-196
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        if let child = child, (_alpha != 0 || alwaysIncludeSemantics) {
            visitor(child)
        }
    }

    // MARK: - Compositing Bits (stub methods)

    /// Marks the compositing bits as needing an update.
    ///
    /// This is called when `alwaysNeedsCompositing` may have changed.
    ///
    /// **Dart Source:** `object.dart:3047-3068`
    open override func markNeedsCompositingBitsUpdate() {
        // TODO: Full implementation with PipelineOwner
    }

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    // MARK: - Layer

    /// The composited layer associated with this render object.
    ///
    /// **Dart Source:** `object.dart:3138-3218`
    public var layer: Layer?

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** proxy_sliver.dart:199-209
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DoubleProperty("opacity", opacity))
        properties.add(
            FlagProperty(
                "alwaysIncludeSemantics",
                value: alwaysIncludeSemantics,
                ifTrue: "alwaysIncludeSemantics"
            )
        )
    }
}

// MARK: - RenderSliverIgnorePointer

/// A render object that is invisible during hit testing.
///
/// When `ignoring` is true, this render object (and its subtree) is invisible
/// to hit testing. It still consumes space during layout and paints its sliver
/// child as usual. It just cannot be the target of located events, because its
/// render object returns false from `hitTest`.
///
/// **Dart Source:** proxy_sliver.dart:227-320
open class RenderSliverIgnorePointer: RenderProxySliver {

    // MARK: - Initializer

    /// Creates a render object that is invisible to hit testing.
    ///
    /// **Dart Source:** proxy_sliver.dart:229-240
    public init(
        sliver: RenderSliver? = nil,
        ignoring: Bool = true,
        ignoringSemantics: Bool? = nil
    ) {
        _ignoring = ignoring
        _ignoringSemantics = ignoringSemantics
        super.init(child: sliver)
    }

    // MARK: - Ignoring

    /// Whether this render object is ignored during hit testing.
    ///
    /// Regardless of whether this render object is ignored during hit testing, it
    /// will still consume space during layout and be visible during painting.
    ///
    /// **Dart Source:** proxy_sliver.dart:248-258
    public var ignoring: Bool {
        get { _ignoring }
        set {
            if newValue == _ignoring {
                return
            }
            _ignoring = newValue
            if ignoringSemantics == nil {
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _ignoring: Bool

    // MARK: - Ignoring Semantics

    /// Whether the semantics of this render object is ignored when compiling the
    /// semantics tree.
    ///
    /// **Dart Source:** proxy_sliver.dart:268-276
    @available(*, deprecated, message: "Create a custom sliver ignore pointer widget instead.")
    public var ignoringSemantics: Bool? {
        get { _ignoringSemantics }
        set {
            if newValue == _ignoringSemantics {
                return
            }
            _ignoringSemantics = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _ignoringSemantics: Bool?

    // MARK: - Hit Test

    /// Determines the set of render objects located at the given position.
    ///
    /// Returns false when `ignoring` is true, otherwise delegates to super.
    ///
    /// **Dart Source:** proxy_sliver.dart:278-290
    public override func hitTest(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        return !ignoring
            && super.hitTest(
                result,
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition
            )
    }

    // MARK: - Semantics

    /// Visits children for semantics purposes.
    ///
    /// If `ignoringSemantics` is true, skips visiting children entirely.
    ///
    /// **Dart Source:** proxy_sliver.dart:293-298
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        if _ignoringSemantics ?? false {
            return
        }
        if let child = child {
            visitor(child)
        }
    }

    /// Describes the semantics configuration of this render object.
    ///
    /// Blocks user actions when `ignoring` is true and `ignoringSemantics` is
    /// nil or true.
    ///
    /// **Dart Source:** proxy_sliver.dart:301-306
    open override func describeSemanticsConfiguration(_ config: SemanticsConfiguration) {
        config.isBlockingUserActions = ignoring && (_ignoringSemantics ?? true)
    }

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** proxy_sliver.dart:309-319
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DiagnosticsProperty<Bool>("ignoring", ignoring))
        properties.add(
            DiagnosticsProperty<Bool?>(
                "ignoringSemantics",
                _ignoringSemantics,
                description: _ignoringSemantics == nil ? nil : "implicitly \(_ignoringSemantics!)"
            )
        )
    }
}

// MARK: - RenderSliverOffstage

/// Lays the sliver child out as if it was in the tree, but without painting
/// anything, without making the sliver child available for hit testing, and
/// without taking any room in the parent.
///
/// **Dart Source:** proxy_sliver.dart:325-423
open class RenderSliverOffstage: RenderProxySliver {

    // MARK: - Initializer

    /// Creates an offstage render object.
    ///
    /// **Dart Source:** proxy_sliver.dart:327-329
    public init(offstage: Bool = true, sliver: RenderSliver? = nil) {
        _offstage = offstage
        super.init(child: sliver)
    }

    // MARK: - Offstage

    /// Whether the sliver child is hidden from the rest of the tree.
    ///
    /// If true, the sliver child is laid out as if it was in the tree, but
    /// without painting anything, without making the sliver child available for
    /// hit testing, and without taking any room in the parent.
    ///
    /// If false, the sliver child is included in the tree as normal.
    ///
    /// **Dart Source:** proxy_sliver.dart:338-347
    public var offstage: Bool {
        get { _offstage }
        set {
            if newValue == _offstage {
                return
            }
            _offstage = newValue
            markNeedsLayout()
        }
    }
    private var _offstage: Bool

    // MARK: - Layout

    /// Performs layout by delegating to the child.
    ///
    /// When offstage, sets geometry to `SliverGeometry.zero`.
    /// When not offstage, proxies the child's geometry.
    ///
    /// **Dart Source:** proxy_sliver.dart:350-358
    open override func performLayout() {
        assert(child != nil)
        child!.layout(constraints, parentUsesSize: true)
        if !offstage {
            geometry = child!.geometry
        } else {
            geometry = .zero
        }
    }

    // MARK: - Hit Test

    /// Determines the set of render objects located at the given position.
    ///
    /// Returns false when offstage, otherwise delegates to super.
    ///
    /// **Dart Source:** proxy_sliver.dart:361-372
    public override func hitTest(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        return !offstage
            && super.hitTest(
                result,
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition
            )
    }

    /// Hit tests children, returning false when offstage.
    ///
    /// **Dart Source:** proxy_sliver.dart:375-388
    open override func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        if offstage {
            return false
        }
        return super.hitTestChildren(
            result,
            mainAxisPosition: mainAxisPosition,
            crossAxisPosition: crossAxisPosition
        )
    }

    // MARK: - Paint

    /// Paints the child, unless offstage.
    ///
    /// **Dart Source:** proxy_sliver.dart:391-396
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if offstage {
            return
        }
        context.paintChild(child!, offset)
    }

    // MARK: - Semantics

    /// Visits children for semantics purposes.
    ///
    /// When offstage, children are not visited for semantics.
    ///
    /// **Dart Source:** proxy_sliver.dart:399-404
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        if offstage {
            return
        }
        if let child = child {
            visitor(child)
        }
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** proxy_sliver.dart:407-410
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DiagnosticsProperty<Bool>("offstage", offstage))
    }

    /// Describes the children of this node for debugging purposes.
    ///
    /// In Dart, this calls `child.toDiagnosticsNode()` with the appropriate
    /// `DiagnosticsTreeStyle`. Since `RenderSliver` does not yet conform to
    /// `DiagnosticableTree` in Swift, this returns string descriptions.
    ///
    /// **Dart Source:** proxy_sliver.dart:413-423
    open func debugDescribeChildren() -> [String] {
        guard child != nil else {
            return []
        }
        let style = offstage ? "offstage" : "sparse"
        return ["child (style: \(style))"]
    }
}

// MARK: - RenderSliverAnimatedOpacity

/// Makes its sliver child partially transparent, driven from an `Animation`.
///
/// This is a variant of `RenderSliverOpacity` that uses an `Animation<Double>`
/// rather than a `Double` to control the opacity.
///
/// In Dart, this class extends `RenderProxySliver` and mixes in
/// `RenderAnimatedOpacityMixin<RenderSliver>`. In Swift, since generic mixins
/// are not supported, the animated opacity behavior is implemented directly
/// on this class (following the same pattern as `RenderAnimatedOpacity` for boxes).
///
/// **Dart Source:** proxy_sliver.dart:430-442
open class RenderSliverAnimatedOpacity: RenderProxySliver {

    // MARK: - Initializer

    /// Creates a partially transparent render object driven by an animation.
    ///
    /// **Dart Source:** proxy_sliver.dart:433-441
    public init(
        opacity: Animation<Double>,
        alwaysIncludeSemantics: Bool = false,
        sliver: RenderSliver? = nil
    ) {
        _opacity = opacity
        _alwaysIncludeSemantics = alwaysIncludeSemantics
        super.init(child: sliver)
        _updateOpacity()
    }

    // MARK: - Opacity Animation

    /// The animation that drives this render object's opacity.
    ///
    /// An opacity of 1.0 is fully opaque. An opacity of 0.0 is fully transparent
    /// (i.e., invisible).
    ///
    /// **Dart Source:** proxy_sliver.dart:438 (via RenderAnimatedOpacityMixin)
    public var opacity: Animation<Double> {
        get { _opacity }
        set {
            if _opacity === newValue {
                return
            }
            if attached {
                _opacity.removeListeners(owner: self)
            }
            _opacity = newValue
            if attached {
                _opacity.addListener(_updateOpacityCallback, owner: self)
            }
            _updateOpacity()
        }
    }
    private var _opacity: Animation<Double>

    // MARK: - Always Include Semantics

    /// Whether child semantics are included regardless of the opacity.
    ///
    /// **Dart Source:** proxy_sliver.dart:439 (via RenderAnimatedOpacityMixin)
    public var alwaysIncludeSemantics: Bool {
        get { _alwaysIncludeSemantics }
        set {
            if newValue == _alwaysIncludeSemantics {
                return
            }
            _alwaysIncludeSemantics = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _alwaysIncludeSemantics: Bool

    // MARK: - Alpha State

    /// The computed alpha value (0-255), or nil if not yet calculated.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    private var _animatedAlpha: Int?

    /// Whether this render object is currently a repaint boundary.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    private var _currentlyIsRepaintBoundary: Bool?

    // MARK: - Opacity Callback

    /// Callback wrapper for the opacity update listener.
    private lazy var _updateOpacityCallback: VoidCallback = { [weak self] in
        self?._updateOpacity()
    }

    /// Updates the opacity based on the current animation value.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    private func _updateOpacity() {
        let oldAlpha = _animatedAlpha
        _animatedAlpha = Color.getAlphaFromOpacity(_opacity.value)
        if oldAlpha != _animatedAlpha {
            let wasRepaintBoundary = _currentlyIsRepaintBoundary
            _currentlyIsRepaintBoundary = (_animatedAlpha ?? 0) > 0
            if child != nil && wasRepaintBoundary != _currentlyIsRepaintBoundary {
                markNeedsCompositingBitsUpdate()
            }
            markNeedsPaint()
            if oldAlpha == 0 || _animatedAlpha == 0 {
                markNeedsSemanticsUpdate()
            }
        }
    }

    // MARK: - Attached State

    /// Called when the object is attached to a pipeline owner.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    open override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _opacity.addListener(_updateOpacityCallback, owner: self)
        _updateOpacity()
    }

    /// Called when the object is detached from its pipeline owner.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    open override func detach() {
        _opacity.removeListeners(owner: self)
        super.detach()
    }

    // MARK: - Repaint Boundary

    /// Whether this render object is a repaint boundary.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    open override var isRepaintBoundary: Bool {
        return child != nil && (_currentlyIsRepaintBoundary ?? false)
    }

    // MARK: - Paint

    /// Paints the child with the animated opacity.
    ///
    /// If alpha is 0, painting is skipped entirely.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if _animatedAlpha == 0 {
            return
        }
        super.paint(context, offset)
    }

    // MARK: - Semantics

    /// Visits children for semantics purposes.
    ///
    /// Skips children when fully transparent unless `alwaysIncludeSemantics`
    /// is true.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        if let child = child, (_animatedAlpha != 0 || alwaysIncludeSemantics) {
            visitor(child)
        }
    }

    // MARK: - Compositing Bits (stub methods)

    /// Marks the compositing bits as needing an update.
    ///
    /// **Dart Source:** `object.dart:3047-3068`
    open override func markNeedsCompositingBitsUpdate() {
        // TODO: Full implementation with PipelineOwner
    }

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    /// The composited layer associated with this render object.
    ///
    /// **Dart Source:** `object.dart:3138-3218`
    public var layer: Layer?

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** via RenderAnimatedOpacityMixin
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(
            DiagnosticsProperty<Animation<Double>>(
                "opacity",
                _opacity
            )
        )
        properties.add(
            FlagProperty(
                "alwaysIncludeSemantics",
                value: alwaysIncludeSemantics,
                ifTrue: "alwaysIncludeSemantics"
            )
        )
    }
}

// MARK: - RenderSliverConstrainedCrossAxis

/// Applies a cross-axis constraint to its sliver child.
///
/// This render object takes a `maxExtent` parameter and uses the smaller of
/// `maxExtent` and the parent's `SliverConstraints.crossAxisExtent` as the
/// cross axis extent of the `SliverConstraints` passed to the sliver child.
///
/// **Dart Source:** proxy_sliver.dart:449-483
open class RenderSliverConstrainedCrossAxis: RenderProxySliver {

    // MARK: - Initializer

    /// Creates a render object that constrains the cross axis extent of its
    /// sliver child.
    ///
    /// The `maxExtent` parameter must be nonnegative.
    ///
    /// **Dart Source:** proxy_sliver.dart:453-455
    public init(maxExtent: Double) {
        assert(maxExtent >= 0.0)
        _maxExtent = maxExtent
        super.init()
    }

    // MARK: - Max Extent

    /// The cross axis extent to apply to the sliver child.
    ///
    /// This value must be nonnegative.
    ///
    /// **Dart Source:** proxy_sliver.dart:460-468
    public var maxExtent: Double {
        get { _maxExtent }
        set {
            if _maxExtent == newValue {
                return
            }
            _maxExtent = newValue
            markNeedsLayout()
        }
    }
    private var _maxExtent: Double

    // MARK: - Layout

    /// Performs layout by constraining the child's cross axis extent.
    ///
    /// Uses the smaller of `maxExtent` and the parent's cross axis extent.
    ///
    /// **Dart Source:** proxy_sliver.dart:471-482
    open override func performLayout() {
        assert(child != nil)
        assert(maxExtent >= 0.0)
        child!.layout(
            sliverConstraints.copyWith(
                crossAxisExtent: min(_maxExtent, sliverConstraints.crossAxisExtent)
            ),
            parentUsesSize: true
        )
        let childLayoutGeometry = child!.geometry!
        geometry = childLayoutGeometry.copyWith(
            crossAxisExtent: min(_maxExtent, sliverConstraints.crossAxisExtent)
        )
    }
}

// MARK: - RenderSliverSemanticsAnnotations

/// Add annotations to the `SemanticsNode` for this subtree.
///
/// This is a STUB implementation. In Dart, this class extends `RenderProxySliver`
/// and mixes in `SemanticsAnnotationsMixin`. Since `SemanticsAnnotationsMixin`
/// has not yet been fully migrated to Swift, this stub holds the key structural
/// properties and delegates to `describeSemanticsConfiguration`.
///
/// **Dart Source:** proxy_sliver.dart:486-510
open class RenderSliverSemanticsAnnotations: RenderProxySliver {

    // MARK: - Initializer

    /// Creates a render object that attaches a semantic annotation.
    ///
    /// **Dart Source:** proxy_sliver.dart:490-509
    public init(
        child: RenderSliver? = nil,
        container: Bool = false,
        explicitChildNodes: Bool = false,
        excludeSemantics: Bool = false,
        blockUserActions: Bool = false
    ) {
        self._container = container
        self._explicitChildNodes = explicitChildNodes
        self._excludeSemantics = excludeSemantics
        self._blockUserActions = blockUserActions
        super.init(child: child)
    }

    // MARK: - Properties

    /// Whether this render object introduces a new semantic boundary.
    ///
    /// When true, the semantics of this render object and its subtree are
    /// reported as a separate node in the semantics tree.
    public var container: Bool {
        get { _container }
        set {
            if _container == newValue { return }
            _container = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _container: Bool

    /// Whether to force children into separate semantic nodes.
    public var explicitChildNodes: Bool {
        get { _explicitChildNodes }
        set {
            if _explicitChildNodes == newValue { return }
            _explicitChildNodes = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _explicitChildNodes: Bool

    /// Whether to exclude the semantics of this subtree.
    public var excludeSemantics: Bool {
        get { _excludeSemantics }
        set {
            if _excludeSemantics == newValue { return }
            _excludeSemantics = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _excludeSemantics: Bool

    /// Whether to block user actions for this semantics subtree.
    public var blockUserActions: Bool {
        get { _blockUserActions }
        set {
            if _blockUserActions == newValue { return }
            _blockUserActions = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _blockUserActions: Bool

    // MARK: - Semantics

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    /// TODO: Override `describeSemanticsConfiguration` when
    /// `SemanticsConfiguration` integration on RenderObject base is available.
    /// The full implementation reads `SemanticsProperties` and configures
    /// container, explicitChildNodes, excludeSemantics, blockUserActions, etc.
}

// MARK: - SingleChildSliverHost Conformance

extension RenderProxySliver: SingleChildSliverHost {}
