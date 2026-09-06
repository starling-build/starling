// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Proxy box render objects that pass layout, painting, and hit testing
/// to a single child.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/proxy_box.dart`

import FlutterSwiftBridge

// MARK: - RenderProxyBox

/// A render object that passes layout, painting, and hit testing to its
/// single child.
///
/// A proxy box has a single child and mimics all the properties of that
/// child by calling through to the child for each function in the render box
/// protocol. For example, a proxy box determines its size by asking its child
/// to layout with the same constraints and then matching the size.
///
/// A proxy box isn't useful on its own because you might as well just replace
/// the proxy box with its child. However, `RenderProxyBox` is a useful base
/// class for render objects that wish to mimic most, but not all, of the
/// properties of their child.
///
/// In Dart, `RenderProxyBox` extends `RenderBox` and mixes in
/// `RenderObjectWithChildMixin<RenderBox>` and `RenderProxyBoxMixin<RenderBox>`.
/// In Swift, since generic mixins are not supported, the single-child
/// management and proxy behavior are implemented directly on the class.
///
/// **Dart Source:** proxy_box.dart:43-53
open class RenderProxyBox: RenderBox {

    // MARK: - Initializer

    /// Creates a proxy render box.
    ///
    /// Proxy render boxes are rarely created directly because they proxy
    /// the render box protocol to `child`. Instead, consider using one of
    /// the subclasses.
    ///
    /// **Dart Source:** proxy_box.dart:50-52
    public init(child: RenderBox? = nil) {
        super.init()
        self.child = child
    }

    // MARK: - Child Management (RenderObjectWithChildMixin pattern)

    /// The single child of this render object.
    ///
    /// In Dart, `RenderProxyBox` uses `RenderObjectWithChildMixin<RenderBox>`
    /// to manage its single child. In Swift, since generic mixins are not
    /// supported, the child property is implemented directly.
    ///
    /// **Dart Source:** proxy_box.dart:44 (via RenderObjectWithChildMixin)
    public var child: RenderBox? {
        get { _child }
        set {
            if let oldChild = _child {
                dropChild(oldChild)
            }
            _child = newValue
            if let newChild = _child {
                adoptChild(newChild)
            }
        }
    }
    private var _child: RenderBox?

    // MARK: - RenderProxyBoxMixin Behavior

    /// Sets up `ParentData` for the given child.
    ///
    /// The Dart `RenderProxyBoxMixin` uses plain `ParentData` rather than
    /// `BoxParentData`, since proxy boxes do not actually use the offset
    /// field in `BoxParentData`.
    ///
    /// **Dart Source:** proxy_box.dart:66-72
    open override func setupParentData(_ child: RenderObject) {
        // We don't actually use the offset argument in BoxParentData, so let's
        // avoid allocating it at all.
        if child.parentData == nil {
            child.parentData = ParentData()
        }
    }

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width by delegating to the child.
    ///
    /// Returns the child's minimum intrinsic width, or 0.0 if there is no child.
    ///
    /// **Dart Source:** proxy_box.dart:75-77
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        return child?.getMinIntrinsicWidth(height) ?? 0.0
    }

    /// Computes the maximum intrinsic width by delegating to the child.
    ///
    /// Returns the child's maximum intrinsic width, or 0.0 if there is no child.
    ///
    /// **Dart Source:** proxy_box.dart:80-82
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        return child?.getMaxIntrinsicWidth(height) ?? 0.0
    }

    /// Computes the minimum intrinsic height by delegating to the child.
    ///
    /// Returns the child's minimum intrinsic height, or 0.0 if there is no child.
    ///
    /// **Dart Source:** proxy_box.dart:85-87
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        return child?.getMinIntrinsicHeight(width) ?? 0.0
    }

    /// Computes the maximum intrinsic height by delegating to the child.
    ///
    /// Returns the child's maximum intrinsic height, or 0.0 if there is no child.
    ///
    /// **Dart Source:** proxy_box.dart:90-92
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        return child?.getMaxIntrinsicHeight(width) ?? 0.0
    }

    // MARK: - Baseline

    /// Computes the distance to the actual baseline by delegating to the child.
    ///
    /// Returns the child's distance to actual baseline, or falls back to
    /// the superclass implementation if there is no child.
    ///
    /// **Dart Source:** proxy_box.dart:95-98
    open override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        return child?.getDistanceToActualBaseline(baseline)
            ?? super.computeDistanceToActualBaseline(baseline)
    }

    /// Computes the dry baseline by delegating to the child.
    ///
    /// Returns the child's dry baseline for the given constraints and baseline
    /// type, or nil if there is no child.
    ///
    /// **Dart Source:** proxy_box.dart:101-104
    open override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        return child?.getDryBaseline(constraints, baseline).offset
    }

    // MARK: - Dry Layout

    /// Computes the dry layout size by delegating to the child.
    ///
    /// Returns the child's dry layout size for the given constraints, or
    /// `computeSizeForNoChild(constraints)` if there is no child.
    ///
    /// **Dart Source:** proxy_box.dart:107-109
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return child?.getDryLayout(constraints) ?? computeSizeForNoChild(constraints)
    }

    // MARK: - Layout

    /// Performs layout by delegating to the child.
    ///
    /// If a child is present, lays it out with the same constraints (passing
    /// `parentUsesSize: true`) and takes on the child's size. If there is no
    /// child, sizes to `computeSizeForNoChild(constraints)`.
    ///
    /// **Dart Source:** proxy_box.dart:113-118
    open override func performLayout() {
        if let child = child {
            child.layout(boxConstraints, parentUsesSize: true)
            size = child.size
        } else {
            size = computeSizeForNoChild(boxConstraints)
        }
    }

    /// Calculates the size this `RenderProxyBox` would have under the given
    /// `BoxConstraints` for the case where it does not have a child.
    ///
    /// By default, returns `constraints.smallest`.
    ///
    /// **Dart Source:** proxy_box.dart:122-124
    open func computeSizeForNoChild(_ constraints: BoxConstraints) -> Size {
        return constraints.smallest
    }

    // MARK: - Hit Testing

    /// Hit tests the child at the given position.
    ///
    /// Delegates to the child's `hitTest` method, or returns false if there is
    /// no child.
    ///
    /// **Dart Source:** proxy_box.dart:127-129
    open override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        return child?.hitTest(result, position: position) ?? false
    }

    // MARK: - Paint Transform

    /// Applies the paint transform for the child.
    ///
    /// For a proxy box, the child is at the same position as the parent, so this
    /// is a no-op (identity transform).
    ///
    /// **Dart Source:** proxy_box.dart:132
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        // Identity transform: child is at same position as parent.
    }

    // MARK: - Painting

    /// Paints the child at the given offset.
    ///
    /// If there is no child, this is a no-op.
    ///
    /// **Dart Source:** proxy_box.dart:134-141
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if let child = child {
            context.paintChild(child, offset)
        }
    }
}

// MARK: - HitTestBehavior

/// How to behave during hit tests.
///
/// **Dart Source:** proxy_box.dart:144-158
public enum HitTestBehavior: Sendable {
    /// Targets that defer to their children receive events within their bounds
    /// only if one of their children is hit by the hit test.
    ///
    /// **Dart Source:** proxy_box.dart:148
    case deferToChild

    /// Opaque targets can be hit by hit tests, causing them to both receive
    /// events within their bounds and prevent targets visually behind them from
    /// also receiving events.
    ///
    /// **Dart Source:** proxy_box.dart:153
    case opaque

    /// Translucent targets both receive events within their bounds and permit
    /// targets visually behind them to also receive events.
    ///
    /// **Dart Source:** proxy_box.dart:157
    case translucent
}

// MARK: - RenderProxyBoxWithHitTestBehavior

/// A `RenderProxyBox` subclass that allows you to customize the
/// hit-testing behavior.
///
/// **Dart Source:** proxy_box.dart:162-199
open class RenderProxyBoxWithHitTestBehavior: RenderProxyBox {

    /// Initializes the proxy box with a customizable hit-test behavior.
    ///
    /// By default, the `behavior` is `HitTestBehavior.deferToChild`.
    ///
    /// **Dart Source:** proxy_box.dart:166-169
    public init(behavior: HitTestBehavior = .deferToChild, child: RenderBox? = nil) {
        self.behavior = behavior
        super.init(child: child)
    }

    /// How to behave during hit testing when deciding how the hit test propagates
    /// to children and whether to consider targets behind this one.
    ///
    /// Defaults to `HitTestBehavior.deferToChild`.
    ///
    /// See `HitTestBehavior` for the allowed values and their meanings.
    ///
    /// **Dart Source:** proxy_box.dart:177
    public var behavior: HitTestBehavior

    /// Determines the set of render objects located at the given position.
    ///
    /// Unlike the standard `RenderBox.hitTest`, this implementation supports
    /// the three hit-test behaviors defined by `HitTestBehavior`:
    ///
    ///   - `.deferToChild`: Only hits if a child reports a hit.
    ///   - `.opaque`: Always hits if within bounds (blocks targets behind).
    ///   - `.translucent`: Always adds a hit entry if within bounds (but still
    ///     reports the actual hit result from children).
    ///
    /// **Dart Source:** proxy_box.dart:180-189
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        var hitTarget = false
        if size.contains(position) {
            hitTarget = hitTestChildren(result, position: position) || hitTestSelf(position)
            if hitTarget || behavior == .translucent {
                result.add(BoxHitTestEntry(AnyHitTestTarget(self), position))
            }
        }
        return hitTarget
    }

    /// Returns whether this render object itself should be considered hit.
    ///
    /// Returns true when the behavior is `.opaque`, meaning this target absorbs
    /// hit tests even if no children were hit.
    ///
    /// **Dart Source:** proxy_box.dart:192
    open override func hitTestSelf(_ position: Offset) -> Bool {
        return behavior == .opaque
    }
}

// MARK: - ShaderMaskLayer Stub

/// A composited layer that applies a shader-based mask to its children.
///
/// This is a minimal stub for forward reference. The full implementation
/// will be provided in a later subtask when the full Layer hierarchy is
/// migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `ShaderMaskLayer`
public class ShaderMaskLayer: ContainerLayer {

    /// Creates a shader mask layer.
    ///
    /// **Dart Source:** `layer.dart`
    public override init() {
        super.init()
    }

    /// The shader to use as a mask.
    ///
    /// **Dart Source:** `layer.dart`
    public var shader: Shader?

    /// The rectangle within which to apply the mask.
    ///
    /// **Dart Source:** `layer.dart`
    public var maskRect: Rect?

    /// The blend mode to use when applying the shader mask.
    ///
    /// **Dart Source:** `layer.dart`
    public var blendMode: BlendMode = .srcOver
}

// MARK: - BackdropFilterLayer

/// A composited layer that applies an image filter to the existing painted
/// content beneath it, and then paints its children on top.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `BackdropFilterLayer`
public class BackdropFilterLayer: ContainerLayer {

    public override init() {
        super.init()
    }

    /// The image filter to apply to the existing painted content.
    public var filter: (any ImageFilter)? {
        didSet { markNeedsAddToScene() }
    }

    /// The blend mode to use when applying the filtered backdrop.
    public var blendMode: BlendMode = .srcOver {
        didSet { markNeedsAddToScene() }
    }

    /// The backdrop key for this filter.
    public var backdropKey: AnyHashable?

    public override func addToScene(_ builder: any SceneBuilder) {
        if let filter = filter {
            engineLayer = builder.pushBackdropFilter(
                filter,
                blendMode: blendMode,
                oldLayer: _engineLayer as? BackdropFilterEngineLayer,
                backdropId: nil
            )
            addChildrenToScene(builder)
            builder.pop()
        } else {
            addChildrenToScene(builder)
        }
    }
}

// MARK: - RenderOpacity

/// Makes its child partially transparent.
///
/// The opacity is applied by blending the child with a 0x00 (fully transparent)
/// background. An opacity of `1.0` is fully opaque, and an opacity of `0.0` is
/// fully transparent (the child is not visible at all).
///
/// RenderOpacity paints its child into an intermediate buffer and then blends
/// the child back into the scene partially transparent. For values of opacity
/// other than 0.0 and 1.0, this class is relatively expensive because it
/// requires painting the child into an intermediate buffer. For the value 0.0,
/// the child is not painted at all. For the value 1.0, the child is
/// painted without an intermediate buffer.
///
/// **Dart Source:** `proxy_box.dart:869`
open class RenderOpacity: RenderProxyBox {

    /// Creates a partially transparent render object.
    ///
    /// The `opacity` argument must be between 0.0 and 1.0, inclusive.
    ///
    /// **Dart Source:** `proxy_box.dart:873-878`
    public init(opacity: Double = 1.0, alwaysIncludeSemantics: Bool = false, child: RenderBox? = nil) {
        assert(opacity >= 0.0 && opacity <= 1.0)
        _opacity = opacity
        _alwaysIncludeSemantics = alwaysIncludeSemantics
        _alpha = Color.getAlphaFromOpacity(opacity)
        super.init(child: child)
    }

    // MARK: - Compositing

    /// Whether this render object always needs compositing.
    ///
    /// Returns true when the child is non-nil and alpha is greater than 0,
    /// meaning the opacity layer is needed for compositing.
    ///
    /// **Dart Source:** `proxy_box.dart:881`
    open override var alwaysNeedsCompositing: Bool {
        return child != nil && _alpha > 0
    }

    /// Whether this render object is a repaint boundary.
    ///
    /// **Dart Source:** `proxy_box.dart:884`
    open override var isRepaintBoundary: Bool {
        return false
    }

    // MARK: - Alpha

    /// The computed alpha value (0-255) corresponding to the current opacity.
    ///
    /// **Dart Source:** `proxy_box.dart:886`
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
    /// **Dart Source:** `proxy_box.dart:896-914`
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
            markNeedsCompositedLayerUpdate()
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
    /// **Dart Source:** `proxy_box.dart:921-929`
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

    /// Returns whether the child is actually painted (alpha > 0).
    ///
    /// **Dart Source:** `proxy_box.dart:932-935`
    open func paintsChild(_ child: RenderBox) -> Bool {
        return _alpha > 0
    }

    /// Updates the composited opacity layer.
    ///
    /// Creates a new `OpacityLayer` if the old one is nil, and sets the alpha.
    ///
    /// **Dart Source:** `proxy_box.dart:938-942`
    open func updateCompositedLayer(oldLayer: OpacityLayer?) -> OpacityLayer {
        let layer = oldLayer ?? OpacityLayer()
        layer.alpha = _alpha
        return layer
    }

    /// Paints the child with the current opacity.
    ///
    /// If the child is nil or alpha is 0, painting is skipped entirely.
    /// Otherwise delegates to the super implementation which handles
    /// composited layer painting.
    ///
    /// **Dart Source:** `proxy_box.dart:945-950`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child == nil || _alpha == 0 {
            return
        }
        if _alpha == 255 {
            context.paintChild(child!, offset)
            return
        }
        // Use pushOpacity (compositing layer) instead of canvas.saveLayer
        // to avoid offscreen FBOs without stencil buffer on DRM/VMware.
        _ = context.pushOpacity(offset, _alpha, { ctx, off in
            ctx.paintChild(self.child!, off)
        })
    }

    // MARK: - Semantics

    /// Visits children for semantics purposes.
    ///
    /// Skips children when fully transparent (alpha == 0) unless
    /// `alwaysIncludeSemantics` is true.
    ///
    /// **Dart Source:** `proxy_box.dart:953-957`
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

    /// Marks the composited layer as needing an update.
    ///
    /// Called when properties of the composited layer have changed but the
    /// compositing structure itself hasn't changed.
    ///
    /// **Dart Source:** `object.dart:3106-3133`
    open func markNeedsCompositedLayerUpdate() {
        markNeedsPaint()
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
    /// **Dart Source:** `proxy_box.dart:960-970`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
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

// MARK: - RenderAnimatedOpacityProtocol

/// Protocol that defines the animated opacity behavior.
///
/// In Dart, `RenderAnimatedOpacityMixin` is a mixin on
/// `RenderObjectWithChildMixin<T>`. In Swift, mixins are not supported,
/// so this is implemented as a protocol with default implementations
/// provided via an extension.
///
/// **Dart Source:** `proxy_box.dart:978`
public protocol RenderAnimatedOpacityProtocol: AnyObject {

    /// The animation that drives this render object's opacity.
    ///
    /// An opacity of 1.0 is fully opaque. An opacity of 0.0 is fully transparent
    /// (i.e., invisible).
    ///
    /// **Dart Source:** `proxy_box.dart:1002-1016`
    var opacity: Animation<Double> { get set }

    /// Whether child semantics are included regardless of the opacity.
    ///
    /// **Dart Source:** `proxy_box.dart:1026-1034`
    var alwaysIncludeSemantics: Bool { get set }

    /// The computed alpha value, or nil if not yet calculated.
    ///
    /// **Dart Source:** `proxy_box.dart:979`
    var animatedAlpha: Int? { get set }

    /// Whether this render object is currently a repaint boundary.
    ///
    /// **Dart Source:** `proxy_box.dart:983`
    var currentlyIsRepaintBoundary: Bool? { get set }

    /// The child render object, if any.
    var child: RenderBox? { get }

    /// Whether this render object is attached to a pipeline owner.
    var attached: Bool { get }

    /// Marks this render object as needing to be repainted.
    func markNeedsPaint()

    /// Marks the compositing bits as needing an update.
    func markNeedsCompositingBitsUpdate()

    /// Marks the composited layer as needing an update.
    func markNeedsCompositedLayerUpdate()

    /// Marks the semantics tree as needing an update.
    func markNeedsSemanticsUpdate()
}

/// Default implementations for `RenderAnimatedOpacityProtocol`.
///
/// **Dart Source:** `proxy_box.dart:978-1098`
extension RenderAnimatedOpacityProtocol {

    /// Whether this render object is a repaint boundary.
    ///
    /// **Dart Source:** `proxy_box.dart:982`
    public var isRepaintBoundary: Bool {
        return child != nil && (currentlyIsRepaintBoundary ?? false)
    }

    /// Whether this render object always needs compositing.
    ///
    /// Returns true when the child exists and alpha is non-zero.
    ///
    /// **Dart Source:** `proxy_box.dart:981` (implied by isRepaintBoundary)
    public var animatedAlwaysNeedsCompositing: Bool {
        return child != nil && (animatedAlpha ?? 0) > 0
    }

    /// Updates the composited opacity layer.
    ///
    /// **Dart Source:** `proxy_box.dart:986-990`
    public func updateCompositedLayer(oldLayer: OpacityLayer?) -> OpacityLayer {
        let updatedLayer = oldLayer ?? OpacityLayer()
        updatedLayer.alpha = animatedAlpha
        return updatedLayer
    }

    /// Updates the opacity based on the current animation value.
    ///
    /// **Dart Source:** `proxy_box.dart:1049-1063`
    public func _updateOpacity() {
        let oldAlpha = animatedAlpha
        animatedAlpha = Color.getAlphaFromOpacity(opacity.value)
        if oldAlpha != animatedAlpha {
            let wasRepaintBoundary = currentlyIsRepaintBoundary
            currentlyIsRepaintBoundary = (animatedAlpha ?? 0) > 0
            if child != nil && wasRepaintBoundary != currentlyIsRepaintBoundary {
                markNeedsCompositingBitsUpdate()
            }
            markNeedsCompositedLayerUpdate()
            if oldAlpha == 0 || animatedAlpha == 0 {
                markNeedsSemanticsUpdate()
            }
        }
    }

    /// Returns whether the child is actually painted (opacity > 0).
    ///
    /// **Dart Source:** `proxy_box.dart:1066-1069`
    public func paintsChild(_ child: RenderBox) -> Bool {
        return opacity.value > 0
    }
}

// MARK: - RenderAnimatedOpacity

/// Makes its child partially transparent, driven from an `Animation`.
///
/// This is a variant of `RenderOpacity` that uses an `Animation<Double>` rather
/// than a `Double` to control the opacity.
///
/// **Dart Source:** `proxy_box.dart:1104-1114`
open class RenderAnimatedOpacity: RenderProxyBox, RenderAnimatedOpacityProtocol {

    /// Creates a partially transparent render object driven by an animation.
    ///
    /// **Dart Source:** `proxy_box.dart:1106-1113`
    public init(
        opacity: Animation<Double>,
        alwaysIncludeSemantics: Bool = false,
        child: RenderBox? = nil
    ) {
        _opacity = opacity
        _alwaysIncludeSemantics = alwaysIncludeSemantics
        super.init(child: child)
        _updateOpacity()
    }

    // MARK: - RenderAnimatedOpacityProtocol

    /// The animation that drives this render object's opacity.
    ///
    /// **Dart Source:** `proxy_box.dart:1002-1016`
    public var opacity: Animation<Double> {
        get { _opacity }
        set {
            if _opacity === newValue {
                return
            }
            if attached {
                _opacity.removeListener(_updateOpacityCallback)
            }
            _opacity = newValue
            if attached {
                _opacity.addListener(_updateOpacityCallback)
            }
            _updateOpacity()
        }
    }
    private var _opacity: Animation<Double>

    /// Whether child semantics are included regardless of the opacity.
    ///
    /// **Dart Source:** `proxy_box.dart:1026-1034`
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

    /// The computed alpha value.
    ///
    /// **Dart Source:** `proxy_box.dart:979`
    public var animatedAlpha: Int?

    /// Whether this is currently a repaint boundary.
    ///
    /// **Dart Source:** `proxy_box.dart:983`
    public var currentlyIsRepaintBoundary: Bool?

    /// Callback wrapper for the opacity update listener.
    private lazy var _updateOpacityCallback: VoidCallback = { [weak self] in
        self?._updateOpacity()
    }

    // MARK: - Attached State

    /// Called when the object is attached to a pipeline owner.
    ///
    /// **Dart Source:** `proxy_box.dart:1037-1041`
    open override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _opacity.addListener(_updateOpacityCallback)
        _updateOpacity()
    }

    /// Called when the object is detached from its pipeline owner.
    ///
    /// **Dart Source:** `proxy_box.dart:1044-1047`
    open override func detach() {
        _opacity.removeListener(_updateOpacityCallback)
        super.detach()
    }

    // MARK: - Repaint Boundary

    /// Whether this render object is a repaint boundary.
    ///
    /// **Dart Source:** `proxy_box.dart:982`
    open override var isRepaintBoundary: Bool {
        return child != nil && (currentlyIsRepaintBoundary ?? false)
    }

    // MARK: - Compositing Bits (stub methods)

    /// Marks the compositing bits as needing an update.
    ///
    /// **Dart Source:** `object.dart:3047-3068`
    open override func markNeedsCompositingBitsUpdate() {
        // TODO: Full implementation with PipelineOwner
    }

    /// Marks the composited layer as needing an update.
    ///
    /// **Dart Source:** `object.dart:3106-3133`
    open func markNeedsCompositedLayerUpdate() {
        markNeedsPaint()
    }

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    // MARK: - Paint

    /// Paints the child with the animated opacity.
    ///
    /// If alpha is 0, painting is skipped entirely.
    ///
    /// **Dart Source:** `proxy_box.dart:1072-1077`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if animatedAlpha == 0 {
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
    /// **Dart Source:** `proxy_box.dart:1080-1084`
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        if let child = child, (animatedAlpha != 0 || alwaysIncludeSemantics) {
            visitor(child)
        }
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `proxy_box.dart:1087-1097`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<Animation<Double>>(
                "opacity",
                opacity
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

// MARK: - ShaderCallback

/// Signature for a function that creates a `Shader` for a given `Rect`.
///
/// Used by `RenderShaderMask` and the `ShaderMask` widget.
///
/// **Dart Source:** `proxy_box.dart:1119`
public typealias ShaderCallback = (Rect) -> Shader

// MARK: - RenderShaderMask

/// Applies a mask generated by a `Shader` to its child.
///
/// For example, `RenderShaderMask` can be used to gradually fade out the edge
/// of a child by using a linear gradient mask.
///
/// **Dart Source:** `proxy_box.dart:1125`
open class RenderShaderMask: RenderProxyBox {

    /// Creates a render object that applies a mask generated by a `Shader`
    /// to its child.
    ///
    /// **Dart Source:** `proxy_box.dart:1127-1133`
    public init(
        child: RenderBox? = nil,
        shaderCallback: @escaping ShaderCallback,
        blendMode: BlendMode = .modulate
    ) {
        _shaderCallback = shaderCallback
        _blendMode = blendMode
        super.init(child: child)
    }

    // MARK: - Layer

    /// The layer handle for the shader mask compositing layer.
    ///
    /// **Dart Source:** `proxy_box.dart:1136`
    private var _shaderMaskLayer = LayerHandle<ShaderMaskLayer>()

    // MARK: - Shader Callback

    /// Called to create the `Shader` that generates the mask.
    ///
    /// The shader callback is called with the current size of the child so that
    /// it can customize the shader to the size and location of the child.
    ///
    /// The rectangle will always be at the origin when called by
    /// `RenderShaderMask`.
    ///
    /// **Dart Source:** `proxy_box.dart:1147-1155`
    public var shaderCallback: ShaderCallback {
        get { _shaderCallback }
        set {
            // Note: Function comparison is not possible in Swift the same way
            // as Dart; always update.
            _shaderCallback = newValue
            markNeedsPaint()
        }
    }
    private var _shaderCallback: ShaderCallback

    // MARK: - Blend Mode

    /// The `BlendMode` to use when applying the shader to the child.
    ///
    /// The default, `.modulate`, is useful for applying an alpha blend
    /// to the child. Other blend modes can be used to create other effects.
    ///
    /// **Dart Source:** `proxy_box.dart:1161-1169`
    public var blendMode: BlendMode {
        get { _blendMode }
        set {
            if _blendMode == newValue {
                return
            }
            _blendMode = newValue
            markNeedsPaint()
        }
    }
    private var _blendMode: BlendMode

    // MARK: - Compositing

    /// Whether this render object always needs compositing.
    ///
    /// Returns true when there is a child, since the shader mask must be
    /// applied via a compositing layer.
    ///
    /// **Dart Source:** `proxy_box.dart:1172`
    open override var alwaysNeedsCompositing: Bool {
        return child != nil
    }

    // MARK: - Paint

    /// Paints the child with the shader mask applied.
    ///
    /// Uses a `ShaderMaskLayer` to composite the shader mask effect.
    ///
    /// **Dart Source:** `proxy_box.dart:1175-1191`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child != nil {
            let maskLayer = _shaderMaskLayer.layer ?? ShaderMaskLayer()
            maskLayer.shader = _shaderCallback(Offset.zero & size)
            maskLayer.maskRect = offset & size
            maskLayer.blendMode = _blendMode
            _shaderMaskLayer.layer = maskLayer
            // context.pushLayer would be called here in a full implementation
            super.paint(context, offset)
        } else {
            _shaderMaskLayer.layer = nil
        }
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the shader mask layer handle.
    open override func dispose() {
        _shaderMaskLayer.layer = nil
        super.dispose()
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** (implied by pattern)
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<BlendMode>(
                "blendMode",
                blendMode
            )
        )
    }
}

// MARK: - RenderBackdropFilter

/// Applies a filter to the existing painted content and then paints its child.
///
/// This effect is relatively expensive, especially if the filter is non-local,
/// such as a blur.
///
/// **Dart Source:** `proxy_box.dart:1198`
open class RenderBackdropFilter: RenderProxyBox {

    /// Creates a backdrop filter.
    ///
    /// The `blendMode` argument defaults to `.srcOver`.
    ///
    /// **Dart Source:** `proxy_box.dart:1202-1212`
    public init(
        child: RenderBox? = nil,
        filter: any ImageFilter,
        blendMode: BlendMode = .srcOver,
        enabled: Bool = true
    ) {
        _filter = filter
        _enabled = enabled
        _blendMode = blendMode
        super.init(child: child)
    }

    // MARK: - Layer

    /// The layer handle for the backdrop filter compositing layer.
    private var _backdropFilterLayer = LayerHandle<BackdropFilterLayer>()

    // MARK: - Enabled

    /// Whether or not the backdrop filter operation will be applied to the child.
    ///
    /// **Dart Source:** `proxy_box.dart:1218-1226`
    public var enabled: Bool {
        get { _enabled }
        set {
            if _enabled == newValue {
                return
            }
            _enabled = newValue
            markNeedsPaint()
        }
    }
    private var _enabled: Bool

    // MARK: - Filter

    /// The image filter to apply to the existing painted content before painting
    /// the child.
    ///
    /// For example, consider using `ImageFilter.blur` to create a backdrop
    /// blur effect.
    ///
    /// **Dart Source:** `proxy_box.dart:1233-1241`
    public var filter: any ImageFilter {
        get { _filter }
        set {
            if _filter.hashValue == newValue.hashValue {
                return
            }
            _filter = newValue
            markNeedsPaint()
        }
    }
    private var _filter: any ImageFilter

    // MARK: - Blend Mode

    /// The blend mode to use to apply the filtered background content onto the
    /// background surface.
    ///
    /// **Dart Source:** `proxy_box.dart:1247-1255`
    public var blendMode: BlendMode {
        get { _blendMode }
        set {
            if _blendMode == newValue {
                return
            }
            _blendMode = newValue
            markNeedsPaint()
        }
    }
    private var _blendMode: BlendMode

    // MARK: - Compositing

    /// Whether this render object always needs compositing.
    ///
    /// Returns true when there is a child, since the backdrop filter must be
    /// applied via a compositing layer.
    ///
    /// **Dart Source:** `proxy_box.dart:1272`
    open override var alwaysNeedsCompositing: Bool {
        return child != nil
    }

    // MARK: - Paint

    /// Paints the child with the backdrop filter applied.
    ///
    /// When `enabled` is false, delegates directly to super. When the child
    /// exists, uses a `BackdropFilterLayer` to composite the filter effect.
    ///
    /// **Dart Source:** `proxy_box.dart:1275-1295`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if !_enabled {
            super.paint(context, offset)
            return
        }

        if child != nil {
            let filterLayer = _backdropFilterLayer.layer ?? BackdropFilterLayer()
            filterLayer.filter = _filter
            filterLayer.blendMode = _blendMode
            _backdropFilterLayer.layer = filterLayer
            context.pushLayer(filterLayer, { (ctx, off) in
                ctx.paintChild(self.child!, off)
            }, offset)
        } else {
            _backdropFilterLayer.layer = nil
        }
    }

    // MARK: - Semantics

    /// Visits children for semantics purposes.
    ///
    /// When the filter is enabled, children are still visited since
    /// backdrop filter affects content beneath, not the children themselves.
    ///
    /// **Dart Source:** (implied by pattern)
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        if let child = child {
            visitor(child)
        }
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the backdrop filter layer handle.
    open override func dispose() {
        _backdropFilterLayer.layer = nil
        super.dispose()
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** (implied by pattern)
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<any ImageFilter>(
                "filter",
                filter
            )
        )
        properties.add(
            DiagnosticsProperty<BlendMode>(
                "blendMode",
                blendMode
            )
        )
        properties.add(
            DiagnosticsProperty<Bool>(
                "enabled",
                enabled
            )
        )
    }
}

// MARK: - RenderConstrainedBox

/// A render box that constrains its child using additional constraints.
///
/// For example, if you wanted `child` to have a minimum height of 50.0 logical
/// pixels, you could use `BoxConstraints(minHeight: 50.0)` as the
/// `additionalConstraints`.
///
/// **Dart Source:** `proxy_box.dart:211`
open class RenderConstrainedBox: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render box that constrains its child.
    ///
    /// The `additionalConstraints` argument must be valid.
    ///
    /// **Dart Source:** `proxy_box.dart:215-218`
    public init(child: RenderBox? = nil, additionalConstraints: BoxConstraints) {
        _additionalConstraints = additionalConstraints
        super.init(child: child)
    }

    // MARK: - Properties

    /// Additional constraints to apply to `child` during layout.
    ///
    /// **Dart Source:** `proxy_box.dart:221-230`
    public var additionalConstraints: BoxConstraints {
        get { _additionalConstraints }
        set {
            if _additionalConstraints == newValue {
                return
            }
            _additionalConstraints = newValue
            markNeedsLayout()
        }
    }
    private var _additionalConstraints: BoxConstraints

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width, enforcing additional constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:233-243`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        if _additionalConstraints.hasBoundedWidth && _additionalConstraints.hasTightWidth {
            return _additionalConstraints.minWidth
        }
        let width = super.computeMinIntrinsicWidth(height)
        if !_additionalConstraints.hasInfiniteWidth {
            return _additionalConstraints.constrainWidth(width)
        }
        return width
    }

    /// Computes the maximum intrinsic width, enforcing additional constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:246-256`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        if _additionalConstraints.hasBoundedWidth && _additionalConstraints.hasTightWidth {
            return _additionalConstraints.minWidth
        }
        let width = super.computeMaxIntrinsicWidth(height)
        if !_additionalConstraints.hasInfiniteWidth {
            return _additionalConstraints.constrainWidth(width)
        }
        return width
    }

    /// Computes the minimum intrinsic height, enforcing additional constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:259-269`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        if _additionalConstraints.hasBoundedHeight && _additionalConstraints.hasTightHeight {
            return _additionalConstraints.minHeight
        }
        let height = super.computeMinIntrinsicHeight(width)
        if !_additionalConstraints.hasInfiniteHeight {
            return _additionalConstraints.constrainHeight(height)
        }
        return height
    }

    /// Computes the maximum intrinsic height, enforcing additional constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:272-282`
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        if _additionalConstraints.hasBoundedHeight && _additionalConstraints.hasTightHeight {
            return _additionalConstraints.minHeight
        }
        let height = super.computeMaxIntrinsicHeight(width)
        if !_additionalConstraints.hasInfiniteHeight {
            return _additionalConstraints.constrainHeight(height)
        }
        return height
    }

    // MARK: - Baseline

    /// Computes the dry baseline, enforcing additional constraints on the child.
    ///
    /// **Dart Source:** `proxy_box.dart:285-287`
    open override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        return child?.getDryBaseline(_additionalConstraints.enforce(constraints), baseline).offset
    }

    // MARK: - Layout

    /// Performs layout by enforcing additional constraints on the child.
    ///
    /// **Dart Source:** `proxy_box.dart:290-298`
    open override func performLayout() {
        let constraints = boxConstraints
        let effectiveConstraints = _additionalConstraints.enforce(constraints)
        if let child = child {
            child.layout(effectiveConstraints, parentUsesSize: true)
            size = child.size
        } else {
            size = effectiveConstraints.constrain(Size.zero)
        }
    }

    /// Computes the dry layout size, enforcing additional constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:302-305`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return child?.getDryLayout(_additionalConstraints.enforce(constraints))
            ?? _additionalConstraints.enforce(constraints).constrain(Size.zero)
    }

    // MARK: - Diagnostics

    /// Adds `additionalConstraints` to the diagnostics properties.
    ///
    /// **Dart Source:** `proxy_box.dart:321-326`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(
            DiagnosticsProperty<String>(
                "additionalConstraints",
                String(describing: additionalConstraints)
            )
        )
    }
}

// MARK: - RenderLimitedBox

/// Constrains the child's `maxWidth` and `maxHeight` if they're otherwise
/// unconstrained.
///
/// This has the effect of giving the child a natural dimension in unbounded
/// environments. For example, by providing a `maxHeight` to a widget that
/// normally tries to be as big as possible, the widget will normally size
/// itself to fit its parent, but when placed in a vertical list, it will take
/// on the given height.
///
/// **Dart Source:** `proxy_box.dart:341`
open class RenderLimitedBox: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render box that imposes a maximum width or maximum height on
    /// its child if the child is otherwise unconstrained.
    ///
    /// The `maxWidth` and `maxHeight` arguments must be non-negative.
    ///
    /// **Dart Source:** `proxy_box.dart:347-355`
    public init(
        child: RenderBox? = nil,
        maxWidth: Double = .infinity,
        maxHeight: Double = .infinity
    ) {
        assert(maxWidth >= 0.0)
        assert(maxHeight >= 0.0)
        _maxWidth = maxWidth
        _maxHeight = maxHeight
        super.init(child: child)
    }

    // MARK: - Properties

    /// The value to use for maxWidth if the incoming maxWidth constraint is
    /// infinite.
    ///
    /// **Dart Source:** `proxy_box.dart:358-367`
    public var maxWidth: Double {
        get { _maxWidth }
        set {
            assert(newValue >= 0.0)
            if _maxWidth == newValue {
                return
            }
            _maxWidth = newValue
            markNeedsLayout()
        }
    }
    private var _maxWidth: Double

    /// The value to use for maxHeight if the incoming maxHeight constraint is
    /// infinite.
    ///
    /// **Dart Source:** `proxy_box.dart:370-379`
    public var maxHeight: Double {
        get { _maxHeight }
        set {
            assert(newValue >= 0.0)
            if _maxHeight == newValue {
                return
            }
            _maxHeight = newValue
            markNeedsLayout()
        }
    }
    private var _maxHeight: Double

    // MARK: - Private Helpers

    /// Limits unconstrained dimensions by applying `maxWidth` / `maxHeight`.
    ///
    /// **Dart Source:** `proxy_box.dart:381-392`
    private func _limitConstraints(_ constraints: BoxConstraints) -> BoxConstraints {
        return BoxConstraints(
            minWidth: constraints.minWidth,
            maxWidth: constraints.hasBoundedWidth
                ? constraints.maxWidth
                : constraints.constrainWidth(maxWidth),
            minHeight: constraints.minHeight,
            maxHeight: constraints.hasBoundedHeight
                ? constraints.maxHeight
                : constraints.constrainHeight(maxHeight)
        )
    }

    /// Computes the size using the given `layoutChild` closure, applying
    /// limited constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:394-400`
    private func _computeSize(
        constraints: BoxConstraints,
        layoutChild: ChildLayouter
    ) -> Size {
        if let child = child {
            let childSize = layoutChild(child, _limitConstraints(constraints))
            return constraints.constrain(childSize)
        }
        return _limitConstraints(constraints).constrain(Size.zero)
    }

    // MARK: - Layout

    /// Computes the dry layout size using limited constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:404-406`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _computeSize(
            constraints: constraints,
            layoutChild: ChildLayoutHelper.dryLayoutChild
        )
    }

    /// Performs layout using limited constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:409-411`
    open override func performLayout() {
        size = _computeSize(
            constraints: boxConstraints,
            layoutChild: ChildLayoutHelper.layoutChild
        )
    }

    // MARK: - Diagnostics

    /// Adds `maxWidth` and `maxHeight` to the diagnostics properties.
    ///
    /// **Dart Source:** `proxy_box.dart:414-418`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(DoubleProperty("maxWidth", maxWidth, defaultValue: Double.infinity))
        properties.add(DoubleProperty("maxHeight", maxHeight, defaultValue: Double.infinity))
    }
}

// MARK: - RenderAspectRatio

/// Attempts to size the child to a specific aspect ratio.
///
/// The render object first tries the largest width permitted by the layout
/// constraints. The height of the render object is determined by applying the
/// given aspect ratio to the width, expressed as a ratio of width to height.
///
/// For example, a 16:9 width:height aspect ratio would have a value of
/// 16.0/9.0. If the maximum width is infinite, the initial width is determined
/// by applying the aspect ratio to the maximum height.
///
/// **Dart Source:** `proxy_box.dart:447`
open class RenderAspectRatio: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object with a specific aspect ratio.
    ///
    /// The `aspectRatio` argument must be a finite, positive value.
    ///
    /// **Dart Source:** `proxy_box.dart:451-455`
    public init(child: RenderBox? = nil, aspectRatio: Double) {
        assert(aspectRatio > 0.0)
        assert(aspectRatio.isFinite)
        _aspectRatio = aspectRatio
        super.init(child: child)
    }

    // MARK: - Properties

    /// The aspect ratio to attempt to use.
    ///
    /// The aspect ratio is expressed as a ratio of width to height. For example,
    /// a 16:9 width:height aspect ratio would have a value of 16.0/9.0.
    ///
    /// **Dart Source:** `proxy_box.dart:461-471`
    public var aspectRatio: Double {
        get { _aspectRatio }
        set {
            assert(newValue > 0.0)
            assert(newValue.isFinite)
            if _aspectRatio == newValue {
                return
            }
            _aspectRatio = newValue
            markNeedsLayout()
        }
    }
    private var _aspectRatio: Double

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width for the given aspect ratio.
    ///
    /// **Dart Source:** `proxy_box.dart:474-479`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        if height.isFinite {
            return height * _aspectRatio
        }
        return child?.getMinIntrinsicWidth(height) ?? 0.0
    }

    /// Computes the maximum intrinsic width for the given aspect ratio.
    ///
    /// **Dart Source:** `proxy_box.dart:482-487`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        if height.isFinite {
            return height * _aspectRatio
        }
        return child?.getMaxIntrinsicWidth(height) ?? 0.0
    }

    /// Computes the minimum intrinsic height for the given aspect ratio.
    ///
    /// **Dart Source:** `proxy_box.dart:490-495`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        if width.isFinite {
            return width / _aspectRatio
        }
        return child?.getMinIntrinsicHeight(width) ?? 0.0
    }

    /// Computes the maximum intrinsic height for the given aspect ratio.
    ///
    /// **Dart Source:** `proxy_box.dart:498-503`
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        if width.isFinite {
            return width / _aspectRatio
        }
        return child?.getMaxIntrinsicHeight(width) ?? 0.0
    }

    // MARK: - Private Helpers

    /// Applies the aspect ratio to the given constraints, iteratively fitting
    /// within the constraints while maintaining the aspect ratio.
    ///
    /// **Dart Source:** `proxy_box.dart:505-563`
    private func _applyAspectRatio(_ constraints: BoxConstraints) -> Size {
        if constraints.isTight {
            return constraints.smallest
        }

        var width = constraints.maxWidth
        var height: Double

        // We default to picking the height based on the width, but if the width
        // would be infinite, that's not sensible so we try to infer the height
        // from the width.
        if width.isFinite {
            height = width / _aspectRatio
        } else {
            height = constraints.maxHeight
            width = height * _aspectRatio
        }

        // Similar to RenderImage, we iteratively attempt to fit within the given
        // constraints while maintaining the given aspect ratio. The order of
        // applying the constraints is also biased towards inferring the height
        // from the width.

        if width > constraints.maxWidth {
            width = constraints.maxWidth
            height = width / _aspectRatio
        }

        if height > constraints.maxHeight {
            height = constraints.maxHeight
            width = height * _aspectRatio
        }

        if width < constraints.minWidth {
            width = constraints.minWidth
            height = width / _aspectRatio
        }

        if height < constraints.minHeight {
            height = constraints.minHeight
            width = height * _aspectRatio
        }

        return constraints.constrain(Size(width, height))
    }

    // MARK: - Layout

    /// Computes the dry layout size using the aspect ratio.
    ///
    /// **Dart Source:** `proxy_box.dart:567-569`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _applyAspectRatio(constraints)
    }

    /// Computes the dry baseline, using tight constraints derived from the
    /// dry layout size.
    ///
    /// **Dart Source:** `proxy_box.dart:572-574`
    open override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        return super.computeDryBaseline(
            BoxConstraints.tight(getDryLayout(constraints)),
            baseline
        )
    }

    /// Performs layout by applying the aspect ratio and laying out the child
    /// with tight constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:577-580`
    open override func performLayout() {
        size = getDryLayout(boxConstraints)
        child?.layout(BoxConstraints.tight(size))
    }

    // MARK: - Diagnostics

    /// Adds `aspectRatio` to the diagnostics properties.
    ///
    /// **Dart Source:** `proxy_box.dart:583-586`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(DoubleProperty("aspectRatio", aspectRatio))
    }
}

// MARK: - RenderIntrinsicWidth

/// Sizes its child to the child's maximum intrinsic width.
///
/// This class is useful, for example, when unlimited width is available and
/// you would like a child that would otherwise attempt to expand infinitely to
/// instead size itself to a more reasonable width.
///
/// If `stepWidth` is non-nil, the child's width will be snapped to a multiple
/// of the `stepWidth`. Similarly, if `stepHeight` is non-nil, the child's
/// height will be snapped to a multiple of the `stepHeight`.
///
/// This class is relatively expensive, because it adds a speculative layout
/// pass before the final layout phase. Avoid using it where possible.
///
/// **Dart Source:** `proxy_box.dart:621`
open class RenderIntrinsicWidth: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that sizes itself to its child's intrinsic width.
    ///
    /// If `stepWidth` is non-nil it must be > 0.0. Similarly if `stepHeight` is
    /// non-nil it must be > 0.0.
    ///
    /// **Dart Source:** `proxy_box.dart:626-631`
    public init(stepWidth: Double? = nil, stepHeight: Double? = nil, child: RenderBox? = nil) {
        assert(stepWidth == nil || stepWidth! > 0.0)
        assert(stepHeight == nil || stepHeight! > 0.0)
        _stepWidth = stepWidth
        _stepHeight = stepHeight
        super.init(child: child)
    }

    // MARK: - Properties

    /// If non-nil, force the child's width to be a multiple of this value.
    ///
    /// This value must be nil or > 0.0.
    ///
    /// **Dart Source:** `proxy_box.dart:636-645`
    public var stepWidth: Double? {
        get { _stepWidth }
        set {
            assert(newValue == nil || newValue! > 0.0)
            if _stepWidth == newValue {
                return
            }
            _stepWidth = newValue
            markNeedsLayout()
        }
    }
    private var _stepWidth: Double?

    /// If non-nil, force the child's height to be a multiple of this value.
    ///
    /// This value must be nil or > 0.0.
    ///
    /// **Dart Source:** `proxy_box.dart:650-659`
    public var stepHeight: Double? {
        get { _stepHeight }
        set {
            assert(newValue == nil || newValue! > 0.0)
            if _stepHeight == newValue {
                return
            }
            _stepHeight = newValue
            markNeedsLayout()
        }
    }
    private var _stepHeight: Double?

    // MARK: - Private Helpers

    /// Applies the step by rounding the input up to the nearest multiple of
    /// `step`. If `step` is nil, returns the input unchanged.
    ///
    /// **Dart Source:** `proxy_box.dart:661-667`
    private static func _applyStep(_ input: Double, _ step: Double?) -> Double {
        if let step = step {
            return (input / step).rounded(.up) * step
        }
        return input
    }

    // MARK: - Intrinsic Dimensions

    /// Returns the maximum intrinsic width (min == max for intrinsic width sizing).
    ///
    /// **Dart Source:** `proxy_box.dart:670-672`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        return getMaxIntrinsicWidth(height)
    }

    /// Computes the maximum intrinsic width, applying the step.
    ///
    /// **Dart Source:** `proxy_box.dart:675-681`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        let width = child.getMaxIntrinsicWidth(height)
        return RenderIntrinsicWidth._applyStep(width, _stepWidth)
    }

    /// Computes the minimum intrinsic height, applying the step.
    ///
    /// **Dart Source:** `proxy_box.dart:684-694`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        var w = width
        if !w.isFinite {
            w = getMaxIntrinsicWidth(.infinity)
        }
        let height = child.getMinIntrinsicHeight(w)
        return RenderIntrinsicWidth._applyStep(height, _stepHeight)
    }

    /// Computes the maximum intrinsic height, applying the step.
    ///
    /// **Dart Source:** `proxy_box.dart:697-707`
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        var w = width
        if !w.isFinite {
            w = getMaxIntrinsicWidth(.infinity)
        }
        let height = child.getMaxIntrinsicHeight(w)
        return RenderIntrinsicWidth._applyStep(height, _stepHeight)
    }

    // MARK: - Private Layout Helpers

    /// Computes the child constraints by tightening width and/or height to
    /// the stepped intrinsic values.
    ///
    /// **Dart Source:** `proxy_box.dart:709-718`
    private func _childConstraints(_ child: RenderBox, _ constraints: BoxConstraints) -> BoxConstraints {
        return constraints.tighten(
            width: constraints.hasTightWidth
                ? nil
                : RenderIntrinsicWidth._applyStep(
                    child.getMaxIntrinsicWidth(constraints.maxHeight), _stepWidth
                ),
            height: stepHeight == nil
                ? nil
                : RenderIntrinsicWidth._applyStep(
                    child.getMaxIntrinsicHeight(constraints.maxWidth), _stepHeight
                )
        )
    }

    /// Computes the size using the given `layoutChild` closure.
    ///
    /// **Dart Source:** `proxy_box.dart:720-725`
    private func _computeSize(
        layoutChild: ChildLayouter,
        constraints: BoxConstraints
    ) -> Size {
        guard let child = child else {
            return constraints.smallest
        }
        return layoutChild(child, _childConstraints(child, constraints))
    }

    // MARK: - Layout

    /// Computes the dry layout size.
    ///
    /// **Dart Source:** `proxy_box.dart:729-731`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _computeSize(
            layoutChild: ChildLayoutHelper.dryLayoutChild,
            constraints: constraints
        )
    }

    /// Computes the dry baseline using the child constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:734-737`
    open override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = child else {
            return nil
        }
        return child.getDryBaseline(_childConstraints(child, constraints), baseline).offset
    }

    /// Performs layout using the stepped intrinsic width constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:740-742`
    open override func performLayout() {
        size = _computeSize(
            layoutChild: ChildLayoutHelper.layoutChild,
            constraints: boxConstraints
        )
    }

    // MARK: - Diagnostics

    /// Adds `stepWidth` and `stepHeight` to the diagnostics properties.
    ///
    /// **Dart Source:** `proxy_box.dart:745-749`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(DoubleProperty("stepWidth", stepWidth))
        properties.add(DoubleProperty("stepHeight", stepHeight))
    }
}

// MARK: - RenderIntrinsicHeight

/// Sizes its child to the child's intrinsic height.
///
/// This class is useful, for example, when unlimited height is available and
/// you would like a child that would otherwise attempt to expand infinitely to
/// instead size itself to a more reasonable height.
///
/// This class is relatively expensive, because it adds a speculative layout
/// pass before the final layout phase. Avoid using it where possible.
///
/// **Dart Source:** `proxy_box.dart:780`
open class RenderIntrinsicHeight: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that sizes itself to its child's intrinsic height.
    ///
    /// **Dart Source:** `proxy_box.dart:782`
    public override init(child: RenderBox? = nil) {
        super.init(child: child)
    }

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width, resolving infinite heights using
    /// the child's max intrinsic height.
    ///
    /// **Dart Source:** `proxy_box.dart:785-794`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        var h = height
        if !h.isFinite {
            h = child.getMaxIntrinsicHeight(.infinity)
        }
        return child.getMinIntrinsicWidth(h)
    }

    /// Computes the maximum intrinsic width, resolving infinite heights using
    /// the child's max intrinsic height.
    ///
    /// **Dart Source:** `proxy_box.dart:797-806`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        guard let child = child else {
            return 0.0
        }
        var h = height
        if !h.isFinite {
            h = child.getMaxIntrinsicHeight(.infinity)
        }
        return child.getMaxIntrinsicWidth(h)
    }

    /// Returns the maximum intrinsic height (min == max for intrinsic height sizing).
    ///
    /// **Dart Source:** `proxy_box.dart:809-811`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        return getMaxIntrinsicHeight(width)
    }

    // MARK: - Private Layout Helpers

    /// Computes the child constraints by tightening height to the child's
    /// max intrinsic height if not already tight.
    ///
    /// **Dart Source:** `proxy_box.dart:813-817`
    private func _childConstraints(_ child: RenderBox, _ constraints: BoxConstraints) -> BoxConstraints {
        return constraints.hasTightHeight
            ? constraints
            : constraints.tighten(height: child.getMaxIntrinsicHeight(constraints.maxWidth))
    }

    /// Computes the size using the given `layoutChild` closure.
    ///
    /// **Dart Source:** `proxy_box.dart:819-824`
    private func _computeSize(
        layoutChild: ChildLayouter,
        constraints: BoxConstraints
    ) -> Size {
        guard let child = child else {
            return constraints.smallest
        }
        return layoutChild(child, _childConstraints(child, constraints))
    }

    // MARK: - Layout

    /// Computes the dry layout size.
    ///
    /// **Dart Source:** `proxy_box.dart:828-830`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _computeSize(
            layoutChild: ChildLayoutHelper.dryLayoutChild,
            constraints: constraints
        )
    }

    /// Computes the dry baseline using the child constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:833-836`
    open override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = child else {
            return nil
        }
        return child.getDryBaseline(_childConstraints(child, constraints), baseline).offset
    }

    /// Performs layout using the intrinsic height constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:839-841`
    open override func performLayout() {
        size = _computeSize(
            layoutChild: ChildLayoutHelper.layoutChild,
            constraints: boxConstraints
        )
    }
}

// MARK: - RenderIgnoreBaseline

/// Excludes the child from baseline computations in the parent.
///
/// **Dart Source:** `proxy_box.dart:845`
open class RenderIgnoreBaseline: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that causes the parent to ignore the child for
    /// baseline computations.
    ///
    /// **Dart Source:** `proxy_box.dart:847`
    public override init(child: RenderBox? = nil) {
        super.init(child: child)
    }

    // MARK: - Baseline

    /// Always returns nil, excluding this subtree from baseline computations.
    ///
    /// **Dart Source:** `proxy_box.dart:850-852`
    open override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        return nil
    }

    /// Always returns nil, excluding this subtree from dry baseline computations.
    ///
    /// **Dart Source:** `proxy_box.dart:855-857`
    open override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        return nil
    }
}

// MARK: - CustomClipper

/// An interface for providing custom clips.
///
/// This class is used by a number of clip widgets (e.g., `ClipRect` and
/// `ClipRRect`).
///
/// The `getClip` method is called whenever the custom clip needs to be updated.
///
/// The `shouldReclip` method is called when a new instance of the class
/// is provided, to check if the new instance actually represents different
/// information.
///
/// The most efficient way to update the clip provided by this class is:
///
/// 1. Supply a `reclip` argument to the constructor of the `CustomClipper`,
///    which specifies a `Listenable` that notifies when the clip should be
///    recalculated.
///
/// **Dart Source:** `proxy_box.dart:1321`
open class CustomClipper<T>: Listenable {

    /// Creates a custom clipper.
    ///
    /// The clipper will update its clip whenever `reclip` notifies its listeners.
    ///
    /// **Dart Source:** `proxy_box.dart:1325`
    public init(reclip: (any Listenable)? = nil) {
        _reclip = reclip
    }

    /// The listenable that triggers reclipping.
    ///
    /// **Dart Source:** `proxy_box.dart:1327`
    private let _reclip: (any Listenable)?

    /// Register a closure to be notified when it is time to reclip.
    ///
    /// The `CustomClipper` implementation merely forwards to the same method on
    /// the `Listenable` provided to the constructor in the `reclip` argument, if
    /// it was not nil.
    ///
    /// **Dart Source:** `proxy_box.dart:1334-1335`
    public func addListener(_ listener: @escaping VoidCallback) {
        _reclip?.addListener(listener)
    }

    /// Remove a previously registered closure from the list of closures that the
    /// object notifies when it is time to reclip.
    ///
    /// The `CustomClipper` implementation merely forwards to the same method on
    /// the `Listenable` provided to the constructor in the `reclip` argument, if
    /// it was not nil.
    ///
    /// **Dart Source:** `proxy_box.dart:1343-1344`
    public func removeListener(_ listener: @escaping VoidCallback) {
        _reclip?.removeListener(listener)
    }

    /// Returns a description of the clip given that the render object being
    /// clipped is of the given size.
    ///
    /// **Dart Source:** `proxy_box.dart:1348`
    open func getClip(_ size: Size) -> T {
        fatalError("Subclasses of CustomClipper must override getClip")
    }

    /// Returns an approximation of the clip returned by `getClip`, as
    /// an axis-aligned Rect. This is used by the semantics layer to
    /// determine whether widgets should be excluded.
    ///
    /// By default, this returns a rectangle that is the same size as
    /// the RenderObject. If `getClip` returns a shape that is roughly the
    /// same size as the RenderObject (e.g. it's a rounded rectangle
    /// with very small arcs in the corners), then this may be adequate.
    ///
    /// **Dart Source:** `proxy_box.dart:1358`
    open func getApproximateClipRect(_ size: Size) -> Rect {
        return Offset.zero & size
    }

    /// Called whenever a new instance of the custom clipper delegate class is
    /// provided to the clip object, or any time that a new clip object is created
    /// with a new instance of the custom clipper delegate class (which amounts to
    /// the same thing, because the latter is implemented in terms of the former).
    ///
    /// If the new instance represents different information than the old
    /// instance, then the method should return true, otherwise it should return
    /// false.
    ///
    /// If the method returns false, then the `getClip` call might be optimized
    /// away.
    ///
    /// **Dart Source:** `proxy_box.dart:1375`
    open func shouldReclip(_ oldClipper: CustomClipper<T>) -> Bool {
        fatalError("Subclasses of CustomClipper must override shouldReclip")
    }
}

// MARK: - ShapeBorderClipper

/// A `CustomClipper` that clips to the outer path of a `ShapeBorder`.
///
/// **Dart Source:** `proxy_box.dart:1382`
open class ShapeBorderClipper: CustomClipper<Path> {

    /// Creates a `ShapeBorder` clipper.
    ///
    /// The `textDirection` argument must be provided non-nil if `shape`
    /// has a text direction dependency (for example if it is expressed in terms
    /// of "start" and "end" instead of "left" and "right"). It may be nil if
    /// the border will not need the text direction to paint itself.
    ///
    /// **Dart Source:** `proxy_box.dart:1389`
    public init(shape: any ShapeBorder, textDirection: TextDirection? = nil) {
        self.shape = shape
        self.textDirection = textDirection
        super.init()
    }

    /// The shape border whose outer path this clipper clips to.
    ///
    /// **Dart Source:** `proxy_box.dart:1392`
    public let shape: any ShapeBorder

    /// The text direction to use for getting the outer path for `shape`.
    ///
    /// `ShapeBorder`s can depend on the text direction (e.g having a "dent"
    /// towards the start of the shape).
    ///
    /// **Dart Source:** `proxy_box.dart:1398`
    public let textDirection: TextDirection?

    /// Returns the outer path of `shape` as the clip.
    ///
    /// **Dart Source:** `proxy_box.dart:1401-1404`
    open override func getClip(_ size: Size) -> Path {
        return shape.getOuterPath(Offset.zero & size, textDirection: textDirection)
    }

    /// **Dart Source:** `proxy_box.dart:1407-1413`
    open override func shouldReclip(_ oldClipper: CustomClipper<Path>) -> Bool {
        guard let typedOldClipper = oldClipper as? ShapeBorderClipper else {
            return true
        }
        return typedOldClipper.shape.description != shape.description
            || typedOldClipper.textDirection != textDirection
    }
}

// MARK: - RenderCustomClip

/// Base class for render objects that clip their children using a custom clip.
///
/// In Dart this is the private `_RenderCustomClip<T>`. In Swift it is made
/// internal (usable within the module) so that subclasses can extend it.
///
/// **Dart Source:** `proxy_box.dart:1416`
open class RenderCustomClip<T>: RenderProxyBox {

    /// Creates a custom clip render object.
    ///
    /// **Dart Source:** `proxy_box.dart:1417-1423`
    public init(
        child: RenderBox? = nil,
        clipper: CustomClipper<T>? = nil,
        clipBehavior: Clip = .antiAlias
    ) {
        _clipper = clipper
        _clipBehavior = clipBehavior
        super.init(child: child)
    }

    // MARK: - Clipper

    /// If non-nil, determines which clip to use on the child.
    ///
    /// **Dart Source:** `proxy_box.dart:1426-1445`
    public var clipper: CustomClipper<T>? {
        get { _clipper }
        set {
            if _clipper === newValue {
                return
            }
            let oldClipper = _clipper
            _clipper = newValue
            if newValue == nil
                || oldClipper == nil
                || type(of: newValue!) != type(of: oldClipper!)
                || newValue!.shouldReclip(oldClipper!)
            {
                _markNeedsClip()
            }
            if attached {
                oldClipper?.removeListener(_markNeedsClipCallback)
                newValue?.addListener(_markNeedsClipCallback)
            }
        }
    }
    internal var _clipper: CustomClipper<T>?

    // MARK: - Clip Callback

    /// Callback wrapper for the clip update listener.
    private lazy var _markNeedsClipCallback: VoidCallback = { [weak self] in
        self?._markNeedsClip()
    }

    // MARK: - Attach / Detach

    /// Called when the object is attached to a pipeline owner.
    ///
    /// **Dart Source:** `proxy_box.dart:1448-1451`
    open override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _clipper?.addListener(_markNeedsClipCallback)
    }

    /// Called when the object is detached from its pipeline owner.
    ///
    /// **Dart Source:** `proxy_box.dart:1454-1457`
    open override func detach() {
        _clipper?.removeListener(_markNeedsClipCallback)
        super.detach()
    }

    // MARK: - Mark Needs Clip

    /// Marks the clip as needing to be recalculated.
    ///
    /// **Dart Source:** `proxy_box.dart:1459-1463`
    internal func _markNeedsClip() {
        _clip = nil
        markNeedsPaint()
        markNeedsSemanticsUpdate()
    }

    // MARK: - Default Clip

    /// The default clip when no custom clipper is provided.
    ///
    /// Subclasses must override this to provide the default clip shape.
    ///
    /// **Dart Source:** `proxy_box.dart:1465`
    open var defaultClip: T {
        fatalError("Subclasses of RenderCustomClip must override defaultClip")
    }

    /// The cached clip value.
    ///
    /// **Dart Source:** `proxy_box.dart:1466`
    internal var _clip: T?

    // MARK: - Clip Behavior

    /// Controls how the clip region is applied.
    ///
    /// **Dart Source:** `proxy_box.dart:1468-1476`
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if newValue != _clipBehavior {
                _clipBehavior = newValue
                markNeedsPaint()
            }
        }
    }
    private var _clipBehavior: Clip

    // MARK: - Layout

    /// Performs layout and invalidates the clip if the size changed.
    ///
    /// **Dart Source:** `proxy_box.dart:1478-1485`
    open override func performLayout() {
        let oldSize = hasSize ? size : nil
        super.performLayout()
        if oldSize != size {
            _clip = nil
        }
    }

    // MARK: - Update Clip

    /// Updates the cached clip, computing it from the clipper or using the default.
    ///
    /// **Dart Source:** `proxy_box.dart:1487-1489`
    internal func _updateClip() {
        if _clip == nil {
            _clip = _clipper?.getClip(size) ?? defaultClip
        }
    }

    // MARK: - Describe Approximate Paint Clip

    /// Returns a rectangle describing the approximate visible region of the child.
    ///
    /// **Dart Source:** `proxy_box.dart:1492-1501`
    open func describeApproximatePaintClip(_ child: RenderObject) -> Rect? {
        switch clipBehavior {
        case .none:
            return nil
        case .hardEdge, .antiAlias, .antiAliasWithSaveLayer:
            return _clipper?.getApproximateClipRect(size) ?? Offset.zero & size
        }
    }

    // MARK: - Semantics Update (stub)

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// **Dart Source:** `proxy_box.dart:1535-1539`
    open override func dispose() {
        super.dispose()
    }
}

// MARK: - RenderClipRect

/// Clips its child using a rectangle.
///
/// By default, `RenderClipRect` prevents its child from painting outside its
/// bounds, but the size and location of the clip rect can be customized using a
/// custom `clipper`.
///
/// **Dart Source:** `proxy_box.dart:1547`
open class RenderClipRect: RenderCustomClip<Rect> {

    /// Creates a rectangular clip.
    ///
    /// If `clipper` is nil, the clip will match the layout size and position of
    /// the child.
    ///
    /// If `clipBehavior` is `.none`, no clipping will be applied.
    ///
    /// **Dart Source:** `proxy_box.dart:1554`
    public override init(
        child: RenderBox? = nil,
        clipper: CustomClipper<Rect>? = nil,
        clipBehavior: Clip = .antiAlias
    ) {
        super.init(child: child, clipper: clipper, clipBehavior: clipBehavior)
    }

    // MARK: - Layer Handle

    /// The layer handle for the clip rect compositing layer.
    private var _clipRectLayer = LayerHandle<ClipRectLayer>()

    // MARK: - Default Clip

    /// Returns the default clip rect matching the render object's size.
    ///
    /// **Dart Source:** `proxy_box.dart:1557`
    open override var defaultClip: Rect {
        return Offset.zero & size
    }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position.
    ///
    /// When a custom clipper is set, hit testing is restricted to the clip region.
    ///
    /// **Dart Source:** `proxy_box.dart:1560-1568`
    open override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        if _clipper != nil {
            _updateClip()
            if !_clip!.contains(position) {
                return false
            }
        }
        return super.hitTest(result, position: position)
    }

    // MARK: - Paint

    /// Paints the child with the rectangular clip applied.
    ///
    /// Uses a `ClipRectLayer` to composite the clip effect.
    ///
    /// **Dart Source:** `proxy_box.dart:1572-1591`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child != nil {
            if clipBehavior != .none {
                _updateClip()
                _clipRectLayer.layer = context.pushClipRect(
                    needsCompositing,
                    offset,
                    _clip!,
                    { context, offset in
                        super.paint(context, offset)
                    },
                    clipBehavior: clipBehavior,
                    oldLayer: _clipRectLayer.layer
                )
            } else {
                context.paintChild(child!, offset)
                _clipRectLayer.layer = nil
            }
        } else {
            _clipRectLayer.layer = nil
        }
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the clip rect layer handle.
    open override func dispose() {
        _clipRectLayer.layer = nil
        super.dispose()
    }
}

// MARK: - RenderClipRRect

/// Clips its child using a rounded rectangle.
///
/// By default, `RenderClipRRect` uses its own bounds as the base rectangle for
/// the clip, but the size and location of the clip can be customized using a
/// custom `clipper`.
///
/// **Dart Source:** `proxy_box.dart:1616`
open class RenderClipRRect: RenderCustomClip<RRect> {

    /// Creates a rounded-rectangular clip.
    ///
    /// The `borderRadius` defaults to `BorderRadius.zero`, i.e. a rectangle with
    /// right-angled corners.
    ///
    /// If `clipper` is non-nil, then `borderRadius` is ignored.
    ///
    /// If `clipBehavior` is `.none`, no clipping will be applied.
    ///
    /// **Dart Source:** `proxy_box.dart:1625-1632`
    public init(
        child: RenderBox? = nil,
        borderRadius: BorderRadiusGeometry = BorderRadius.zero,
        clipper: CustomClipper<RRect>? = nil,
        clipBehavior: Clip = .antiAlias,
        textDirection: TextDirection? = nil
    ) {
        _borderRadius = borderRadius
        _textDirection = textDirection
        super.init(child: child, clipper: clipper, clipBehavior: clipBehavior)
    }

    // MARK: - Layer Handle

    /// The layer handle for the clip rounded rect compositing layer.
    private var _clipRRectLayer = LayerHandle<ClipRRectLayer>()

    // MARK: - Border Radius

    /// The border radius of the rounded corners.
    ///
    /// Values are clamped so that horizontal and vertical radii sums do not
    /// exceed width/height.
    ///
    /// This value is ignored if `clipper` is non-nil.
    ///
    /// **Dart Source:** `proxy_box.dart:1640-1648`
    public var borderRadius: BorderRadiusGeometry {
        get { _borderRadius }
        set {
            if _borderRadius == newValue {
                return
            }
            _borderRadius = newValue
            _markNeedsClip()
        }
    }
    private var _borderRadius: BorderRadiusGeometry

    // MARK: - Text Direction

    /// The text direction with which to resolve `borderRadius`.
    ///
    /// **Dart Source:** `proxy_box.dart:1651-1659`
    public var textDirection: TextDirection? {
        get { _textDirection }
        set {
            if _textDirection == newValue {
                return
            }
            _textDirection = newValue
            _markNeedsClip()
        }
    }
    private var _textDirection: TextDirection?

    // MARK: - Default Clip

    /// Returns the default clip rounded rect from the border radius and size.
    ///
    /// **Dart Source:** `proxy_box.dart:1662`
    open override var defaultClip: RRect {
        return _borderRadius.resolve(textDirection).toRRect(Offset.zero & size)
    }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position.
    ///
    /// When a custom clipper is set, hit testing is restricted to the clip region.
    ///
    /// **Dart Source:** `proxy_box.dart:1665-1673`
    open override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        if _clipper != nil {
            _updateClip()
            if !_clip!.contains(position) {
                return false
            }
        }
        return super.hitTest(result, position: position)
    }

    // MARK: - Paint

    /// Paints the child with the rounded-rectangular clip applied.
    ///
    /// Uses a `ClipRRectLayer` to composite the clip effect.
    ///
    /// **Dart Source:** `proxy_box.dart:1677-1697`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child != nil {
            if clipBehavior != .none {
                _updateClip()
                _clipRRectLayer.layer = context.pushClipRRect(
                    needsCompositing,
                    offset,
                    _clip!.outerRect,
                    _clip!,
                    { context, offset in
                        super.paint(context, offset)
                    },
                    clipBehavior: clipBehavior,
                    oldLayer: _clipRRectLayer.layer
                )
            } else {
                context.paintChild(child!, offset)
                _clipRRectLayer.layer = nil
            }
        } else {
            _clipRRectLayer.layer = nil
        }
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the clip rounded rect layer handle.
    open override func dispose() {
        _clipRRectLayer.layer = nil
        super.dispose()
    }
}

// MARK: - RenderClipOval

/// Clips its child using an oval.
///
/// By default, inscribes an axis-aligned oval into its layout dimensions and
/// prevents its child from painting outside that oval, but the size and
/// location of the clip oval can be customized using a custom `clipper`.
///
/// **Dart Source:** `proxy_box.dart:1829`
open class RenderClipOval: RenderCustomClip<Rect> {

    /// Creates an oval-shaped clip.
    ///
    /// If `clipper` is nil, the oval will be inscribed into the layout size and
    /// position of the child.
    ///
    /// If `clipBehavior` is `.none`, no clipping will be applied.
    ///
    /// **Dart Source:** `proxy_box.dart:1836`
    public override init(
        child: RenderBox? = nil,
        clipper: CustomClipper<Rect>? = nil,
        clipBehavior: Clip = .antiAlias
    ) {
        super.init(child: child, clipper: clipper, clipBehavior: clipBehavior)
    }

    // MARK: - Layer Handle

    /// The layer handle for the clip path compositing layer (used for oval clipping).
    private var _clipPathLayer = LayerHandle<ClipPathLayer>()

    // MARK: - Cached Oval Path

    /// The cached rect for which the oval path was computed.
    ///
    /// **Dart Source:** `proxy_box.dart:1838`
    private var _cachedRect: Rect?

    /// The cached oval path.
    ///
    /// **Dart Source:** `proxy_box.dart:1839`
    private var _cachedPath: Path?

    /// Returns a cached oval path for the given rect.
    ///
    /// **Dart Source:** `proxy_box.dart:1841-1847`
    private func _getClipPath(_ rect: Rect) -> Path {
        if rect != _cachedRect || _cachedPath == nil {
            _cachedRect = rect
            let path = Path()
            path.addOval(rect)
            _cachedPath = path
        }
        return _cachedPath!
    }

    // MARK: - Default Clip

    /// Returns the default clip rect matching the render object's size.
    ///
    /// **Dart Source:** `proxy_box.dart:1850`
    open override var defaultClip: Rect {
        return Offset.zero & size
    }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position.
    ///
    /// Uses an ellipse-based containment check rather than a path containment
    /// check, which is more efficient.
    ///
    /// **Dart Source:** `proxy_box.dart:1853-1867`
    open override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        _updateClip()
        let center = _clip!.center
        // Convert the position to an offset from the center of the unit circle
        let offset = Offset(
            (position.dx - center.dx) / _clip!.width,
            (position.dy - center.dy) / _clip!.height
        )
        // Check if the point is outside the unit circle
        if offset.distanceSquared > 0.25 {
            // x^2 + y^2 > r^2
            return false
        }
        return super.hitTest(result, position: position)
    }

    // MARK: - Paint

    /// Paints the child with the oval clip applied.
    ///
    /// Uses a `ClipPathLayer` to composite the clip effect.
    ///
    /// **Dart Source:** `proxy_box.dart:1871-1891`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child != nil {
            if clipBehavior != .none {
                _updateClip()
                _clipPathLayer.layer = context.pushClipPath(
                    needsCompositing,
                    offset,
                    _clip!,
                    _getClipPath(_clip!),
                    { context, offset in
                        super.paint(context, offset)
                    },
                    clipBehavior: clipBehavior,
                    oldLayer: _clipPathLayer.layer
                )
            } else {
                context.paintChild(child!, offset)
                _clipPathLayer.layer = nil
            }
        } else {
            _clipPathLayer.layer = nil
        }
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the clip path layer handle.
    open override func dispose() {
        _clipPathLayer.layer = nil
        super.dispose()
    }
}

// MARK: - RenderClipPath

/// Clips its child using a path.
///
/// Takes a delegate whose primary method returns a path that should
/// be used to prevent the child from painting outside the path.
///
/// Clipping to a path is expensive. Certain shapes have more
/// optimized render objects:
///
///  - To clip to a rectangle, consider `RenderClipRect`.
///  - To clip to an oval or circle, consider `RenderClipOval`.
///  - To clip to a rounded rectangle, consider `RenderClipRRect`.
///
/// **Dart Source:** `proxy_box.dart:1926`
open class RenderClipPath: RenderCustomClip<Path> {

    /// Creates a path clip.
    ///
    /// If `clipper` is nil, the clip will be a rectangle that matches the layout
    /// size and location of the child. However, rather than use this default,
    /// consider using a `RenderClipRect`, which can achieve the same effect more
    /// efficiently.
    ///
    /// If `clipBehavior` is `.none`, no clipping will be applied.
    ///
    /// **Dart Source:** `proxy_box.dart:1935`
    public override init(
        child: RenderBox? = nil,
        clipper: CustomClipper<Path>? = nil,
        clipBehavior: Clip = .antiAlias
    ) {
        super.init(child: child, clipper: clipper, clipBehavior: clipBehavior)
    }

    // MARK: - Layer Handle

    /// The layer handle for the clip path compositing layer.
    private var _clipPathLayer = LayerHandle<ClipPathLayer>()

    // MARK: - Default Clip

    /// Returns the default clip path as a rectangle matching the render object's size.
    ///
    /// **Dart Source:** `proxy_box.dart:1938`
    open override var defaultClip: Path {
        let path = Path()
        path.addRect(Offset.zero & size)
        return path
    }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position.
    ///
    /// When a custom clipper is set, hit testing is restricted to the clip region.
    ///
    /// **Dart Source:** `proxy_box.dart:1941-1949`
    open override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        if _clipper != nil {
            _updateClip()
            if !_clip!.contains(position) {
                return false
            }
        }
        return super.hitTest(result, position: position)
    }

    // MARK: - Paint

    /// Paints the child with the path clip applied.
    ///
    /// Uses a `ClipPathLayer` to composite the clip effect.
    ///
    /// **Dart Source:** `proxy_box.dart:1953-1973`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child != nil {
            if clipBehavior != .none {
                _updateClip()
                _clipPathLayer.layer = context.pushClipPath(
                    needsCompositing,
                    offset,
                    Offset.zero & size,
                    _clip!,
                    { context, offset in
                        super.paint(context, offset)
                    },
                    clipBehavior: clipBehavior,
                    oldLayer: _clipPathLayer.layer
                )
            } else {
                context.paintChild(child!, offset)
                _clipPathLayer.layer = nil
            }
        } else {
            _clipPathLayer.layer = nil
        }
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the clip path layer handle.
    open override func dispose() {
        _clipPathLayer.layer = nil
        super.dispose()
    }
}

// MARK: - PhysicalModelLayer Stub

/// A composited layer that draws a physical model (shadow + clip).
///
/// This is a minimal stub for forward reference. The full implementation
/// will be provided in a later subtask when the full Layer hierarchy is
/// migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/layer.dart`
/// **Original Name:** `PhysicalModelLayer`
public class PhysicalModelLayer: ContainerLayer {

    /// Creates a physical model layer.
    ///
    /// **Dart Source:** `layer.dart`
    public override init() {
        super.init()
    }

    /// The clip path for this physical model.
    ///
    /// **Dart Source:** `layer.dart`
    public var clipPath: Path?

    /// The elevation of this physical model.
    ///
    /// **Dart Source:** `layer.dart`
    public var elevation: Double = 0.0

    /// The background color of this physical model.
    ///
    /// **Dart Source:** `layer.dart`
    public var color: Color = Color(0xFF000000)

    /// The shadow color of this physical model.
    ///
    /// **Dart Source:** `layer.dart`
    public var shadowColor: Color = Color(0xFF000000)
}

// MARK: - _RenderPhysicalModelBase

/// A physical model layer casts a shadow based on its elevation.
///
/// The concrete implementations `RenderPhysicalModel` and `RenderPhysicalShape`
/// determine the actual shape of the physical model.
///
/// In Dart, this is a private abstract class `_RenderPhysicalModelBase<T>`
/// extending `_RenderCustomClip<T>`. In Swift, since generic class hierarchies
/// have limitations, we model the clip management directly within the base class.
///
/// **Dart Source:** `proxy_box.dart:1994`
open class RenderPhysicalModelBase<T>: RenderProxyBox {

    /// The `elevation` parameter must be non-negative.
    ///
    /// **Dart Source:** `proxy_box.dart:1996-2006`
    public init(
        child: RenderBox? = nil,
        elevation: Double,
        color: Color,
        shadowColor: Color,
        clipBehavior: Clip = .none,
        clipper: CustomClipper<T>? = nil
    ) {
        assert(elevation >= 0.0)
        _elevation = elevation
        _color = color
        _shadowColor = shadowColor
        _clipBehavior = clipBehavior
        _clipper = clipper
        super.init(child: child)
    }

    // MARK: - Clip Management

    /// The custom clipper for this physical model, if any.
    ///
    /// **Dart Source:** `proxy_box.dart:1426` (via `_RenderCustomClip`)
    public var clipper: CustomClipper<T>? {
        get { _clipper }
        set {
            if _clipper === newValue {
                return
            }
            let oldClipper = _clipper
            _clipper = newValue
            if newValue == nil ||
                oldClipper == nil ||
                type(of: newValue!) != type(of: oldClipper!) ||
                newValue!.shouldReclip(oldClipper!) {
                _markNeedsClip()
            }
            if attached {
                oldClipper?.removeListener(_markNeedsClipCallback)
                newValue?.addListener(_markNeedsClipCallback)
            }
        }
    }
    private var _clipper: CustomClipper<T>?

    /// The cached clip value.
    ///
    /// **Dart Source:** `proxy_box.dart:1466`
    internal var _clip: T?

    /// How to clip the child.
    ///
    /// **Dart Source:** `proxy_box.dart:1468-1476`
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if newValue != _clipBehavior {
                _clipBehavior = newValue
                markNeedsPaint()
            }
        }
    }
    private var _clipBehavior: Clip

    /// Marks the clip as needing to be recalculated.
    ///
    /// **Dart Source:** `proxy_box.dart:1459-1463`
    internal func _markNeedsClip() {
        _clip = nil
        markNeedsPaint()
        markNeedsSemanticsUpdate()
    }

    /// Callback wrapper for the clip listener.
    private lazy var _markNeedsClipCallback: VoidCallback = { [weak self] in
        self?._markNeedsClip()
    }

    /// Updates the clip using the clipper or the default clip.
    ///
    /// Subclasses must provide `defaultClip` for this to work.
    ///
    /// **Dart Source:** `proxy_box.dart:1487-1489`
    internal func _updateClip() {
        // Subclasses must override this or provide _clip
    }

    // MARK: - Layout

    /// Performs layout, invalidating the clip if size changed.
    ///
    /// **Dart Source:** `proxy_box.dart:1479-1485`
    open override func performLayout() {
        let oldSize = hasSize ? size : nil
        super.performLayout()
        if oldSize != size {
            _clip = nil
        }
    }

    // MARK: - Attach / Detach

    /// Called when the object is attached to a pipeline owner.
    ///
    /// **Dart Source:** `proxy_box.dart:1448-1451`
    open override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _clipper?.addListener(_markNeedsClipCallback)
    }

    /// Called when the object is detached from its pipeline owner.
    ///
    /// **Dart Source:** `proxy_box.dart:1454-1457`
    open override func detach() {
        _clipper?.removeListener(_markNeedsClipCallback)
        super.detach()
    }

    // MARK: - Elevation

    /// The z-coordinate relative to the parent at which to place this material.
    ///
    /// The value is non-negative.
    ///
    /// **Dart Source:** `proxy_box.dart:2014-2027`
    public var elevation: Double {
        get { _elevation }
        set {
            assert(newValue >= 0.0)
            if _elevation == newValue {
                return
            }
            let didNeedCompositing = alwaysNeedsCompositing
            _elevation = newValue
            if didNeedCompositing != alwaysNeedsCompositing {
                markNeedsCompositingBitsUpdate()
            }
            markNeedsPaint()
        }
    }
    private var _elevation: Double

    /// Whether this render object always needs compositing.
    ///
    /// Returns true when elevation is greater than 0.
    open override var alwaysNeedsCompositing: Bool {
        return _elevation != 0.0
    }

    // MARK: - Shadow Color

    /// The shadow color.
    ///
    /// **Dart Source:** `proxy_box.dart:2030-2038`
    public var shadowColor: Color {
        get { _shadowColor }
        set {
            if _shadowColor == newValue {
                return
            }
            _shadowColor = newValue
            markNeedsPaint()
        }
    }
    private var _shadowColor: Color

    // MARK: - Color

    /// The background color.
    ///
    /// **Dart Source:** `proxy_box.dart:2041-2049`
    public var color: Color {
        get { _color }
        set {
            if _color == newValue {
                return
            }
            _color = newValue
            markNeedsPaint()
        }
    }
    private var _color: Color

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

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `proxy_box.dart:2051-2057`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(DoubleProperty("elevation", elevation))
        properties.add(DiagnosticsProperty<Color>("color", color))
        properties.add(DiagnosticsProperty<Color>("shadowColor", shadowColor))
    }
}

// MARK: - RenderPhysicalModel

/// Creates a physical model layer that clips its child to a rounded
/// rectangle.
///
/// A physical model layer casts a shadow based on its `elevation`.
///
/// **Dart Source:** `proxy_box.dart:2064`
open class RenderPhysicalModel: RenderPhysicalModelBase<RRect> {

    /// Creates a rounded-rectangular clip.
    ///
    /// The `color` is required.
    ///
    /// The `elevation` parameter must be non-negative.
    ///
    /// **Dart Source:** `proxy_box.dart:2070-2080`
    public init(
        child: RenderBox? = nil,
        shape: BoxShape = .rectangle,
        clipBehavior: Clip = .none,
        borderRadius: BorderRadius? = nil,
        elevation: Double = 0.0,
        color: Color,
        shadowColor: Color = Color(0xFF000000)
    ) {
        assert(elevation >= 0.0)
        _shape = shape
        _borderRadius = borderRadius
        super.init(
            child: child,
            elevation: elevation,
            color: color,
            shadowColor: shadowColor,
            clipBehavior: clipBehavior
        )
    }

    // MARK: - Layer Handle

    /// The layer handle for the physical model compositing layer.
    private var _physicalModelLayer = LayerHandle<PhysicalModelLayer>()

    // MARK: - Shape

    /// The shape of the layer.
    ///
    /// Defaults to `BoxShape.rectangle`. The `borderRadius` affects the corners
    /// of the rectangle.
    ///
    /// **Dart Source:** `proxy_box.dart:2086-2094`
    public var shape: BoxShape {
        get { _shape }
        set {
            if _shape == newValue {
                return
            }
            _shape = newValue
            _markNeedsClip()
        }
    }
    private var _shape: BoxShape

    // MARK: - Border Radius

    /// The border radius of the rounded corners.
    ///
    /// Values are clamped so that horizontal and vertical radii sums do not
    /// exceed width/height.
    ///
    /// This property is ignored if the `shape` is not `BoxShape.rectangle`.
    ///
    /// The value nil is treated like `BorderRadius.zero`.
    ///
    /// **Dart Source:** `proxy_box.dart:2104-2112`
    public var borderRadius: BorderRadius? {
        get { _borderRadius }
        set {
            if _borderRadius == newValue {
                return
            }
            _borderRadius = newValue
            _markNeedsClip()
        }
    }
    private var _borderRadius: BorderRadius?

    // MARK: - Default Clip

    /// The default clip when no custom clipper is provided.
    ///
    /// **Dart Source:** `proxy_box.dart:2115-2122`
    private var _defaultClip: RRect {
        assert(hasSize)
        let rect = Offset.zero & size
        switch _shape {
        case .rectangle:
            return (borderRadius ?? .zero).toRRect(rect)
        case .circle:
            return RRect(fromRectXY: rect, rect.width / 2, rect.height / 2)
        }
    }

    // MARK: - Update Clip

    /// Updates the cached clip value.
    ///
    /// **Dart Source:** `proxy_box.dart:1487-1489`
    internal override func _updateClip() {
        if _clip == nil {
            if let clipper = clipper {
                _clip = clipper.getClip(size)
            } else {
                _clip = _defaultClip
            }
        }
    }

    // MARK: - Hit Test

    /// Determines whether the given position hits this physical model.
    ///
    /// **Dart Source:** `proxy_box.dart:2125-2134`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        if clipper != nil {
            _updateClip()
            if let clip = _clip, !clip.contains(position) {
                return false
            }
        }
        return super.hitTest(result, position: position)
    }

    // MARK: - Paint

    /// Paints the physical model with shadow and clip.
    ///
    /// **Dart Source:** `proxy_box.dart:2137-2194`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child == nil {
            _physicalModelLayer.layer = nil
            return
        }

        _updateClip()
        guard let clip = _clip else { return }
        let offsetRRect = clip.shift(offset)
        let offsetRRectAsPath = Path()
        offsetRRectAsPath.addRRect(offsetRRect)

        let canvas = context.canvas
        if elevation != 0.0 {
            canvas.drawShadow(
                offsetRRectAsPath,
                shadowColor,
                elevation,
                color.a < 1.0
            )
        }

        let usesSaveLayer = clipBehavior == .antiAliasWithSaveLayer
        if !usesSaveLayer {
            let paint = Paint()
            paint.color = color
            canvas.drawRRect(offsetRRect, paint)
        }

        // In a full implementation, context.pushClipRRect would be used here.
        // For now, delegate to super.paint.
        if usesSaveLayer {
            let paint = Paint()
            paint.color = color
            canvas.drawPaint(paint)
        }
        super.paint(context, offset)
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the physical model layer handle.
    open override func dispose() {
        _physicalModelLayer.layer = nil
        super.dispose()
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `proxy_box.dart:2197-2201`
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DiagnosticsProperty<BoxShape>("shape", shape))
        properties.add(DiagnosticsProperty<BorderRadius?>("borderRadius", borderRadius))
    }
}

// MARK: - RenderPhysicalShape

/// Creates a physical shape layer that clips its child to a `Path`.
///
/// A physical shape layer casts a shadow based on its `elevation`.
///
/// See also:
///
///  - `RenderPhysicalModel`, which is optimized for rounded rectangles and
///    circles.
///
/// **Dart Source:** `proxy_box.dart:2212`
open class RenderPhysicalShape: RenderPhysicalModelBase<Path> {

    /// Creates an arbitrary shape clip.
    ///
    /// The `color` and `clipper` parameters are required.
    ///
    /// The `elevation` parameter must be non-negative.
    ///
    /// **Dart Source:** `proxy_box.dart:2218-2225`
    public init(
        child: RenderBox? = nil,
        clipper: CustomClipper<Path>,
        clipBehavior: Clip = .none,
        elevation: Double = 0.0,
        color: Color,
        shadowColor: Color = Color(0xFF000000)
    ) {
        assert(elevation >= 0.0)
        super.init(
            child: child,
            elevation: elevation,
            color: color,
            shadowColor: shadowColor,
            clipBehavior: clipBehavior,
            clipper: clipper
        )
    }

    // MARK: - Layer Handle

    /// The layer handle for the physical model compositing layer.
    private var _physicalShapeLayer = LayerHandle<PhysicalModelLayer>()

    // MARK: - Default Clip

    /// The default clip when no custom clipper is provided.
    ///
    /// **Dart Source:** `proxy_box.dart:2228`
    private var _defaultClip: Path {
        let path = Path()
        path.addRect(Offset.zero & size)
        return path
    }

    // MARK: - Update Clip

    /// Updates the cached clip value.
    ///
    /// **Dart Source:** `proxy_box.dart:1487-1489`
    internal override func _updateClip() {
        if _clip == nil {
            if let clipper = clipper {
                _clip = clipper.getClip(size)
            } else {
                _clip = _defaultClip
            }
        }
    }

    // MARK: - Hit Test

    /// Determines whether the given position hits this physical shape.
    ///
    /// **Dart Source:** `proxy_box.dart:2231-2240`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        if clipper != nil {
            _updateClip()
            if let clip = _clip, !clip.contains(position) {
                return false
            }
        }
        return super.hitTest(result, position: position)
    }

    // MARK: - Paint

    /// Paints the physical shape with shadow and clip.
    ///
    /// **Dart Source:** `proxy_box.dart:2243-2299`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child == nil {
            _physicalShapeLayer.layer = nil
            return
        }

        _updateClip()
        guard let clip = _clip else { return }
        let offsetPath = clip.shift(offset)

        let canvas = context.canvas
        if elevation != 0.0 {
            canvas.drawShadow(
                offsetPath,
                shadowColor,
                elevation,
                color.a < 1.0
            )
        }

        let usesSaveLayer = clipBehavior == .antiAliasWithSaveLayer
        if !usesSaveLayer {
            let paint = Paint()
            paint.color = color
            canvas.drawPath(offsetPath, paint)
        }

        // In a full implementation, context.pushClipPath would be used here.
        // For now, delegate to super.paint.
        if usesSaveLayer {
            let paint = Paint()
            paint.color = color
            canvas.drawPaint(paint)
        }
        super.paint(context, offset)
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// Clears the physical shape layer handle.
    open override func dispose() {
        _physicalShapeLayer.layer = nil
        super.dispose()
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `proxy_box.dart:2301-2305`
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DiagnosticsProperty<CustomClipper<Path>?>("clipper", clipper))
    }
}

// MARK: - DecorationPosition

/// Where to paint a box decoration.
///
/// **Dart Source:** `proxy_box.dart:2309-2315`
public enum DecorationPosition: Sendable {

    /// Paint the box decoration behind the children.
    ///
    /// **Dart Source:** `proxy_box.dart:2311`
    case background

    /// Paint the box decoration in front of the children.
    ///
    /// **Dart Source:** `proxy_box.dart:2314`
    case foreground
}

// MARK: - RenderDecoratedBox

/// Paints a `Decoration` either before or after its child paints.
///
/// **Dart Source:** `proxy_box.dart:2318`
open class RenderDecoratedBox: RenderProxyBox {

    /// Creates a decorated box.
    ///
    /// The `decoration`, `position`, and `configuration` arguments must not be
    /// nil. By default the decoration paints behind the child.
    ///
    /// The `ImageConfiguration` will be passed to the decoration (with the size
    /// filled in) to let it resolve images.
    ///
    /// **Dart Source:** `proxy_box.dart:2326-2334`
    public init(
        decoration: any Decoration,
        position: DecorationPosition = .background,
        configuration: ImageConfiguration = .empty,
        child: RenderBox? = nil
    ) {
        _decoration = decoration
        _position = position
        _configuration = configuration
        super.init(child: child)
    }

    // MARK: - Painter

    /// The box painter created by the decoration.
    ///
    /// **Dart Source:** `proxy_box.dart:2336`
    private var _painter: BoxPainter?

    // MARK: - Decoration

    /// What decoration to paint.
    ///
    /// Commonly a `BoxDecoration`.
    ///
    /// **Dart Source:** `proxy_box.dart:2341-2351`
    public var decoration: any Decoration {
        get { _decoration }
        set {
            _painter?.dispose()
            _painter = nil
            _decoration = newValue
            markNeedsPaint()
        }
    }
    private var _decoration: any Decoration

    // MARK: - Position

    /// Whether to paint the box decoration behind or in front of the child.
    ///
    /// **Dart Source:** `proxy_box.dart:2354-2362`
    public var position: DecorationPosition {
        get { _position }
        set {
            if newValue == _position {
                return
            }
            _position = newValue
            markNeedsPaint()
        }
    }
    private var _position: DecorationPosition

    // MARK: - Configuration

    /// The settings to pass to the decoration when painting, so that it can
    /// resolve images appropriately.
    ///
    /// The `ImageConfiguration.textDirection` field is also used by
    /// direction-sensitive `Decoration`s for painting and hit-testing.
    ///
    /// **Dart Source:** `proxy_box.dart:2370-2378`
    public var configuration: ImageConfiguration {
        get { _configuration }
        set {
            if newValue == _configuration {
                return
            }
            _configuration = newValue
            markNeedsPaint()
        }
    }
    private var _configuration: ImageConfiguration

    // MARK: - Detach

    /// Called when the object is detached from its pipeline owner.
    ///
    /// Disposes the painter so that we resubscribe to change notifications
    /// when re-attached. This ensures, for example, that animated GIFs
    /// continue animating when a DecoratedBox gets moved around the tree
    /// due to GlobalKey reparenting.
    ///
    /// **Dart Source:** `proxy_box.dart:2381-2391`
    open override func detach() {
        _painter?.dispose()
        _painter = nil
        super.detach()
        markNeedsPaint()
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    ///
    /// **Dart Source:** `proxy_box.dart:2394-2397`
    open override func dispose() {
        _painter?.dispose()
        super.dispose()
    }

    // MARK: - Baseline

    /// Computes the distance to the actual baseline, accounting for
    /// decoration padding.
    ///
    /// **Dart Source:** `proxy_box.dart` (via RenderProxyBox)
    open override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        return child?.getDistanceToActualBaseline(baseline)
            ?? super.computeDistanceToActualBaseline(baseline)
    }

    // MARK: - Hit Test

    /// Returns whether this render object itself should be considered hit.
    ///
    /// Tests if the point is within the decoration shape.
    ///
    /// **Dart Source:** `proxy_box.dart:2400-2402`
    open override func hitTestSelf(_ position: Offset) -> Bool {
        return _decoration.hitTest(size, position, textDirection: configuration.textDirection)
    }

    // MARK: - Paint

    /// Paints the decoration and child.
    ///
    /// Paints the background decoration before the child, and the foreground
    /// decoration after the child.
    ///
    /// **Dart Source:** `proxy_box.dart:2405-2451`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if _painter == nil {
            _painter = _decoration.createBoxPainter(markNeedsPaint)
        }
        let filledConfiguration = configuration.copyWith(size: size)
        if _position == .background {
            _painter!.paint(context.canvas, offset, filledConfiguration)
            if _decoration.isComplex {
                context.setIsComplexHint()
            }
        }
        super.paint(context, offset)
        if _position == .foreground {
            _painter!.paint(context.canvas, offset, filledConfiguration)
            if _decoration.isComplex {
                context.setIsComplexHint()
            }
        }
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `proxy_box.dart:2454-2458`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<String>(
                "decoration",
                String(describing: decoration)
            )
        )
        properties.add(
            DiagnosticsProperty<ImageConfiguration>(
                "configuration",
                configuration
            )
        )
    }
}

// MARK: - RenderTransform

/// Applies a transformation matrix before painting its child.
///
/// This render object applies an arbitrary matrix transform to its child during
/// painting. The transform can include rotation, scaling, translation, and
/// perspective effects. An optional `origin` and `alignment` can be specified
/// to control the center of the transformation.
///
/// **Dart Source:** `proxy_box.dart:2462`
open class RenderTransform: RenderProxyBox {

    /// Creates a render object that transforms its child.
    ///
    /// **Dart Source:** `proxy_box.dart:2464-2478`
    public init(
        transform: Matrix4,
        origin: Offset? = nil,
        alignment: (any AlignmentGeometry)? = nil,
        textDirection: TextDirection? = nil,
        transformHitTests: Bool = true,
        filterQuality: FilterQuality? = nil,
        child: RenderBox? = nil
    ) {
        self.transformHitTests = transformHitTests
        _filterQuality = filterQuality
        super.init(child: child)
        self.transform = transform
        self.alignment = alignment
        self.textDirection = textDirection
        self.origin = origin
    }

    // MARK: - Origin

    /// The origin of the coordinate system (relative to the upper left corner of
    /// this render object) in which to apply the matrix.
    ///
    /// Setting an origin is equivalent to conjugating the transform matrix by a
    /// translation. This property is provided just for convenience.
    ///
    /// **Dart Source:** `proxy_box.dart:2485-2494`
    public var origin: Offset? {
        get { _origin }
        set {
            if _origin == newValue {
                return
            }
            _origin = newValue
            markNeedsPaint()
            markNeedsSemanticsUpdate()
        }
    }
    private var _origin: Offset?

    // MARK: - Alignment

    /// The alignment of the origin, relative to the size of the box.
    ///
    /// This is equivalent to setting an origin based on the size of the box.
    /// If it is specified at the same time as an offset, both are applied.
    ///
    /// **Dart Source:** `proxy_box.dart:2507-2516`
    public var alignment: (any AlignmentGeometry)? {
        get { _alignment }
        set {
            if let lhs = _alignment, let rhs = newValue, AnyHashable(lhs) == AnyHashable(rhs) {
                return
            }
            if _alignment == nil && newValue == nil {
                return
            }
            _alignment = newValue
            markNeedsPaint()
            markNeedsSemanticsUpdate()
        }
    }
    private var _alignment: (any AlignmentGeometry)?

    // MARK: - Text Direction

    /// The text direction with which to resolve `alignment`.
    ///
    /// This may be changed to nil, but only after `alignment` has been changed
    /// to a value that does not depend on the direction.
    ///
    /// **Dart Source:** `proxy_box.dart:2522-2531`
    public var textDirection: TextDirection? {
        get { _textDirection }
        set {
            if _textDirection == newValue {
                return
            }
            _textDirection = newValue
            markNeedsPaint()
            markNeedsSemanticsUpdate()
        }
    }
    private var _textDirection: TextDirection?

    // MARK: - Compositing

    /// Whether this render object always needs compositing.
    ///
    /// Returns true when the child is non-nil and a filter quality is set.
    ///
    /// **Dart Source:** `proxy_box.dart:2534`
    open override var alwaysNeedsCompositing: Bool {
        return child != nil && _filterQuality != nil
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

    // MARK: - Transform Hit Tests

    /// When set to true, hit tests are performed based on the position of the
    /// child as it is painted. When set to false, hit tests are performed
    /// ignoring the transformation.
    ///
    /// `applyPaintTransform`, and therefore `localToGlobal` and `globalToLocal`,
    /// always honor the transformation, regardless of the value of this property.
    ///
    /// **Dart Source:** `proxy_box.dart:2542`
    public var transformHitTests: Bool

    // MARK: - Transform

    /// Backing storage for the transform matrix.
    private var _transform: Matrix4?

    /// The matrix to transform the child by during painting. The provided value
    /// is copied on assignment.
    ///
    /// There is no getter for `transform`, because `Matrix4` is mutable, and
    /// mutations outside of the control of the render object could not reliably
    /// be reflected in the rendering.
    ///
    /// **Dart Source:** `proxy_box.dart:2553-2560`
    public var transform: Matrix4 {
        // Write-only in Dart; in Swift we provide a setter.
        get { _transform ?? Matrix4.identity() }
        set {
            if _transform == newValue {
                return
            }
            _transform = Matrix4.copy(newValue)
            markNeedsPaint()
            markNeedsSemanticsUpdate()
        }
    }

    // MARK: - Filter Quality

    /// The filter quality with which to apply the transform as a bitmap operation.
    ///
    /// **Dart Source:** `proxy_box.dart:2565-2577`
    public var filterQuality: FilterQuality? {
        get { _filterQuality }
        set {
            if _filterQuality == newValue {
                return
            }
            let didNeedCompositing = alwaysNeedsCompositing
            _filterQuality = newValue
            if didNeedCompositing != alwaysNeedsCompositing {
                markNeedsCompositingBitsUpdate()
            }
            markNeedsPaint()
        }
    }
    private var _filterQuality: FilterQuality?

    // MARK: - Transform Mutations

    /// Sets the transform to the identity matrix.
    ///
    /// **Dart Source:** `proxy_box.dart:2580-2584`
    public func setIdentity() {
        _transform!.setIdentity()
        markNeedsPaint()
        markNeedsSemanticsUpdate()
    }

    /// Concatenates a rotation about the x axis into the transform.
    ///
    /// **Dart Source:** `proxy_box.dart:2587-2591`
    public func rotateX(_ radians: Double) {
        _transform!.rotateX(radians)
        markNeedsPaint()
        markNeedsSemanticsUpdate()
    }

    /// Concatenates a rotation about the y axis into the transform.
    ///
    /// **Dart Source:** `proxy_box.dart:2594-2598`
    public func rotateY(_ radians: Double) {
        _transform!.rotateY(radians)
        markNeedsPaint()
        markNeedsSemanticsUpdate()
    }

    /// Concatenates a rotation about the z axis into the transform.
    ///
    /// **Dart Source:** `proxy_box.dart:2601-2605`
    public func rotateZ(_ radians: Double) {
        _transform!.rotateZ(radians)
        markNeedsPaint()
        markNeedsSemanticsUpdate()
    }

    /// Concatenates a translation by (x, y, z) into the transform.
    ///
    /// **Dart Source:** `proxy_box.dart:2608-2612`
    public func translateTransform(_ x: Double, _ y: Double = 0.0, _ z: Double = 0.0) {
        _transform!.translate(x, y, z)
        markNeedsPaint()
        markNeedsSemanticsUpdate()
    }

    /// Concatenates a scale into the transform.
    ///
    /// **Dart Source:** `proxy_box.dart:2615-2619`
    public func scaleTransform(_ x: Double, _ y: Double? = nil, _ z: Double? = nil) {
        _transform!.scale(x, y ?? x, z ?? x)
        markNeedsPaint()
        markNeedsSemanticsUpdate()
    }

    // MARK: - Effective Transform

    /// Computes the effective transform matrix, combining the base transform
    /// with origin and alignment adjustments.
    ///
    /// **Dart Source:** `proxy_box.dart:2621-2643`
    private var _effectiveTransform: Matrix4? {
        let resolvedAlignment = alignment?.resolve(textDirection)
        if _origin == nil && resolvedAlignment == nil {
            return _transform
        }
        var result = Matrix4.identity()
        if let origin = _origin {
            result.translate(origin.dx, origin.dy)
        }
        var translation: Offset?
        if let resolvedAlignment = resolvedAlignment {
            translation = resolvedAlignment.alongSize(size)
            result.translate(translation!.dx, translation!.dy)
        }
        result.multiply(_transform!)
        if let resolvedAlignment = resolvedAlignment {
            result.translate(-translation!.dx, -translation!.dy)
        }
        if let origin = _origin {
            result.translate(-origin.dx, -origin.dy)
        }
        return result
    }

    // MARK: - Layer Handle

    /// The layer handle for the transform compositing layer.
    private var _transformLayer = LayerHandle<TransformLayer>()

    // MARK: - Hit Testing

    /// Hit tests at the given position.
    ///
    /// `RenderTransform` objects don't check if they are themselves hit, because
    /// it's confusing to think about how the untransformed size and the child's
    /// transformed position interact.
    ///
    /// **Dart Source:** `proxy_box.dart:2646-2652`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        return hitTestChildren(result, position: position)
    }

    /// Hit tests children, optionally applying the transform for position mapping.
    ///
    /// **Dart Source:** `proxy_box.dart:2655-2664`
    open override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        assert(!transformHitTests || _effectiveTransform != nil)
        return result.addWithPaintTransform(
            transform: transformHitTests ? _effectiveTransform : nil,
            position: position,
            hitTest: { result, position in
                return super.hitTestChildren(result, position: position)
            }
        )
    }

    // MARK: - Paint

    /// Paints the child with the transform applied.
    ///
    /// If `filterQuality` is nil, uses `pushTransform` for compositing. If set,
    /// uses an image filter layer for bitmap-level filtering.
    ///
    /// **Dart Source:** `proxy_box.dart:2667-2711`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child != nil {
            let transform = _effectiveTransform!
            let superPaint: PaintingContextCallback = { context, offset in
                super.paint(context, offset)
            }
            if filterQuality == nil {
                let childOffset = MatrixUtils.getAsTranslation(transform)
                if childOffset == nil {
                    // If the matrix is singular the children would be compressed to a line
                    // or single point, instead short-circuit and paint nothing.
                    let det = transform.determinant()
                    if det == 0 || !det.isFinite {
                        _transformLayer.layer = nil
                        return
                    }
                    _transformLayer.layer = context.pushTransform(
                        needsCompositing,
                        offset,
                        transform,
                        superPaint,
                        oldLayer: _transformLayer.layer
                    )
                } else {
                    super.paint(context, offset + childOffset!)
                    _transformLayer.layer = nil
                }
            } else {
                // When filterQuality is set, apply the transform as an image filter.
                // This is a simplified version; full ImageFilterLayer support is deferred.
                var effectiveTransform = Matrix4.translationValues(offset.dx, offset.dy, 0.0)
                effectiveTransform.multiply(transform)
                effectiveTransform.translate(-offset.dx, -offset.dy)
                // TODO: Full ImageFilterLayer support in a later subtask.
                // For now, fall back to pushTransform.
                _transformLayer.layer = context.pushTransform(
                    needsCompositing,
                    offset,
                    transform,
                    superPaint,
                    oldLayer: _transformLayer.layer
                )
            }
        }
    }

    // MARK: - Paint Transform

    /// Applies the paint transform to the child.
    ///
    /// **Dart Source:** `proxy_box.dart:2714-2716`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        transform.multiply(_effectiveTransform!)
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    open override func dispose() {
        _transformLayer.layer = nil
        super.dispose()
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `proxy_box.dart:2719-2726`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<String>("transform matrix", String(describing: _transform))
        )
        properties.add(
            DiagnosticsProperty<String>("origin", String(describing: origin))
        )
        properties.add(
            DiagnosticsProperty<String>("alignment", String(describing: alignment))
        )
        properties.add(
            DiagnosticsProperty<String>("textDirection", String(describing: textDirection))
        )
        properties.add(
            DiagnosticsProperty<Bool>("transformHitTests", transformHitTests)
        )
    }
}

// MARK: - RenderFittedBox

/// Scales and positions its child within itself according to `fit`.
///
/// Applies a `BoxFit` algorithm to scale its child and position it according
/// to `alignment`. If the child overflows the source rect, it can be clipped
/// according to `clipBehavior`.
///
/// **Dart Source:** `proxy_box.dart:2730`
open class RenderFittedBox: RenderProxyBox {

    /// Scales and positions its child within itself.
    ///
    /// **Dart Source:** `proxy_box.dart:2732-2742`
    public init(
        fit: BoxFit = .contain,
        alignment: any AlignmentGeometry = Alignment.center,
        textDirection: TextDirection? = nil,
        child: RenderBox? = nil,
        clipBehavior: Clip = .none
    ) {
        _fit = fit
        _alignment = alignment
        _textDirection = textDirection
        _clipBehavior = clipBehavior
        super.init(child: child)
    }

    // MARK: - Resolution

    /// Resolves the alignment to a concrete `Alignment` using `textDirection`.
    ///
    /// **Dart Source:** `proxy_box.dart:2744-2745`
    private func _resolve() -> Alignment {
        if _resolvedAlignment == nil {
            _resolvedAlignment = alignment.resolve(textDirection)
        }
        return _resolvedAlignment!
    }
    private var _resolvedAlignment: Alignment?

    /// Invalidates the resolved alignment and marks paint as needed.
    ///
    /// **Dart Source:** `proxy_box.dart:2747-2750`
    private func _markNeedResolution() {
        _resolvedAlignment = nil
        markNeedsPaint()
    }

    /// Returns whether the given fit affects layout (only `scaleDown` does).
    ///
    /// **Dart Source:** `proxy_box.dart:2752-2764`
    private func _fitAffectsLayout(_ fit: BoxFit) -> Bool {
        switch fit {
        case .scaleDown:
            return true
        case .contain, .cover, .fill, .fitHeight, .fitWidth, .none:
            return false
        }
    }

    // MARK: - Fit

    /// How to inscribe the child into the space allocated during layout.
    ///
    /// **Dart Source:** `proxy_box.dart:2767-2781`
    public var fit: BoxFit {
        get { _fit }
        set {
            if _fit == newValue {
                return
            }
            let lastFit = _fit
            _fit = newValue
            if _fitAffectsLayout(lastFit) || _fitAffectsLayout(newValue) {
                markNeedsLayout()
            } else {
                _clearPaintData()
                markNeedsPaint()
            }
        }
    }
    private var _fit: BoxFit

    // MARK: - Alignment

    /// How to align the child within its parent's bounds.
    ///
    /// If this is set to an `AlignmentDirectional` object, then
    /// `textDirection` must not be nil.
    ///
    /// **Dart Source:** `proxy_box.dart:2791-2800`
    public var alignment: any AlignmentGeometry {
        get { _alignment }
        set {
            if AnyHashable(_alignment) == AnyHashable(newValue) {
                return
            }
            _alignment = newValue
            _clearPaintData()
            _markNeedResolution()
        }
    }
    private var _alignment: any AlignmentGeometry

    // MARK: - Text Direction

    /// The text direction with which to resolve `alignment`.
    ///
    /// **Dart Source:** `proxy_box.dart:2806-2815`
    public var textDirection: TextDirection? {
        get { _textDirection }
        set {
            if _textDirection == newValue {
                return
            }
            _textDirection = newValue
            _clearPaintData()
            _markNeedResolution()
        }
    }
    private var _textDirection: TextDirection?

    // MARK: - Layout

    /// Computes the dry layout for the fitted box.
    ///
    /// **Dart Source:** `proxy_box.dart:2821-2842`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        if let child = child {
            let childSize = child.getDryLayout(BoxConstraints())
            switch fit {
            case .scaleDown:
                let sizeConstraints = constraints.loosen()
                let unconstrainedSize = sizeConstraints
                    .constrainSizeAndAttemptToPreserveAspectRatio(childSize)
                return constraints.constrain(unconstrainedSize)
            case .contain, .cover, .fill, .fitHeight, .fitWidth, .none:
                return constraints.constrainSizeAndAttemptToPreserveAspectRatio(childSize)
            }
        } else {
            return constraints.smallest
        }
    }

    /// Performs the layout of the fitted box.
    ///
    /// **Dart Source:** `proxy_box.dart:2845-2866`
    open override func performLayout() {
        if let child = child {
            child.layout(BoxConstraints(), parentUsesSize: true)
            let bc = boxConstraints
            switch fit {
            case .scaleDown:
                let sizeConstraints = bc.loosen()
                let unconstrainedSize = sizeConstraints
                    .constrainSizeAndAttemptToPreserveAspectRatio(child.size)
                size = bc.constrain(unconstrainedSize)
            case .contain, .cover, .fill, .fitHeight, .fitWidth, .none:
                size = bc.constrainSizeAndAttemptToPreserveAspectRatio(child.size)
            }
            _clearPaintData()
        } else {
            size = boxConstraints.smallest
        }
    }

    // MARK: - Compositing Bits (stub methods)

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    // MARK: - Paint Data

    /// Whether there is visual overflow (child extends beyond the fitted area).
    private var _hasVisualOverflow: Bool?

    /// The computed transform to apply to the child during painting.
    private var _fittedTransform: Matrix4?

    // MARK: - Clip Behavior

    /// Clip behavior for this fitted box.
    ///
    /// Defaults to `.none`.
    ///
    /// **Dart Source:** `proxy_box.dart:2874-2882`
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if newValue != _clipBehavior {
                _clipBehavior = newValue
                markNeedsPaint()
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _clipBehavior: Clip

    /// Clears cached paint data.
    ///
    /// **Dart Source:** `proxy_box.dart:2884-2887`
    private func _clearPaintData() {
        _hasVisualOverflow = nil
        _fittedTransform = nil
    }

    /// Updates the cached paint data (transform and overflow).
    ///
    /// **Dart Source:** `proxy_box.dart:2889-2916`
    private func _updatePaintData() {
        if _fittedTransform != nil {
            return
        }

        if child == nil {
            _hasVisualOverflow = false
            _fittedTransform = Matrix4.identity()
        } else {
            let resolvedAlignment = _resolve()
            let childSize = child!.size
            let sizes = applyBoxFit(_fit, childSize, size)
            let scaleX = sizes.destination.width / sizes.source.width
            let scaleY = sizes.destination.height / sizes.source.height
            let sourceRect = resolvedAlignment.inscribe(sizes.source, Offset.zero & childSize)
            let destinationRect = resolvedAlignment.inscribe(
                sizes.destination,
                Offset.zero & size
            )
            _hasVisualOverflow =
                sourceRect.width < childSize.width || sourceRect.height < childSize.height
            assert(scaleX.isFinite && scaleY.isFinite)
            _fittedTransform = Matrix4.translationValues(
                destinationRect.left, destinationRect.top, 0.0
            )
            _fittedTransform!.scale(scaleX, scaleY, 1.0)
            _fittedTransform!.translate(-sourceRect.left, -sourceRect.top)
            assert(_fittedTransform!.storage.allSatisfy { $0.isFinite })
        }
    }

    // MARK: - Layer Handles

    /// The layer handle for the transform compositing layer.
    private var _transformLayer = LayerHandle<TransformLayer>()

    /// The layer handle for the clip rect compositing layer.
    private var _clipRectLayer = LayerHandle<ClipRectLayer>()

    /// Paints the child with transform, returning the transform layer if created.
    ///
    /// The `superPaint` callback is used to call the superclass paint method,
    /// working around Swift's restriction on using `super` in closures.
    ///
    /// **Dart Source:** `proxy_box.dart:2918-2932`
    @discardableResult
    private func _paintChildWithTransform(
        _ context: PaintingContext, _ offset: Offset,
        superPaint: PaintingContextCallback
    ) -> TransformLayer? {
        let childOffset = MatrixUtils.getAsTranslation(_fittedTransform!)
        if childOffset == nil {
            return context.pushTransform(
                needsCompositing,
                offset,
                _fittedTransform!,
                superPaint,
                oldLayer: _transformLayer.layer
            )
        } else {
            superPaint(context, offset + childOffset!)
        }
        return nil
    }

    // MARK: - Paint

    /// Paints the child with fit transform, optionally clipping.
    ///
    /// **Dart Source:** `proxy_box.dart:2934-2953`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child == nil || size.isEmpty || child!.size.isEmpty {
            return
        }
        _updatePaintData()
        assert(child != nil)
        let superPaint: PaintingContextCallback = { context, offset in
            super.paint(context, offset)
        }
        if _hasVisualOverflow! && clipBehavior != .none {
            _clipRectLayer.layer = context.pushClipRect(
                needsCompositing,
                offset,
                Offset.zero & size,
                { [self] context, offset in
                    _transformLayer.layer = _paintChildWithTransform(
                        context, offset, superPaint: superPaint
                    )
                },
                clipBehavior: clipBehavior,
                oldLayer: _clipRectLayer.layer
            )
        } else {
            _clipRectLayer.layer = nil
            _transformLayer.layer = _paintChildWithTransform(
                context, offset, superPaint: superPaint
            )
        }
    }

    // MARK: - Hit Testing

    /// Hit tests children with the fitted transform applied.
    ///
    /// **Dart Source:** `proxy_box.dart:2956-2968`
    open override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        if size.isEmpty || (child?.size.isEmpty ?? false) {
            return false
        }
        _updatePaintData()
        return result.addWithPaintTransform(
            transform: _fittedTransform,
            position: position,
            hitTest: { result, position in
                return super.hitTestChildren(result, position: position)
            }
        )
    }

    /// Returns whether the child is actually painted.
    ///
    /// **Dart Source:** `proxy_box.dart:2971-2974`
    open func paintsChild(_ child: RenderBox) -> Bool {
        assert(child.parent === self)
        return !size.isEmpty && !child.size.isEmpty
    }

    // MARK: - Paint Transform

    /// Applies the fitted paint transform to the child.
    ///
    /// **Dart Source:** `proxy_box.dart:2977-2984`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        if !paintsChild(child as! RenderBox) {
            transform.setZero()
        } else {
            _updatePaintData()
            transform.multiply(_fittedTransform!)
        }
    }

    // MARK: - Dispose

    /// Releases resources held by this render object.
    open override func dispose() {
        _transformLayer.layer = nil
        _clipRectLayer.layer = nil
        super.dispose()
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `proxy_box.dart:2987-2992`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<String>("fit", String(describing: fit))
        )
        properties.add(
            DiagnosticsProperty<String>("alignment", String(describing: alignment))
        )
        properties.add(
            DiagnosticsProperty<String>("textDirection", String(describing: textDirection))
        )
    }
}

// MARK: - RenderFractionalTranslation

/// Applies a translation transformation before painting its child.
///
/// The translation is expressed as an `Offset` scaled to the child's size. For
/// example, an `Offset` with a `dx` of 0.25 will result in a horizontal
/// translation of one quarter the width of the child.
///
/// Hit tests will only be detected inside the bounds of the
/// `RenderFractionalTranslation`, even if the contents are offset such that
/// they overflow.
///
/// **Dart Source:** `proxy_box.dart:3004`
open class RenderFractionalTranslation: RenderProxyBox {

    /// Creates a render object that translates its child's painting.
    ///
    /// **Dart Source:** `proxy_box.dart:3006-3011`
    public init(
        translation: Offset,
        transformHitTests: Bool = true,
        child: RenderBox? = nil
    ) {
        _translation = translation
        self.transformHitTests = transformHitTests
        super.init(child: child)
    }

    // MARK: - Translation

    /// The translation to apply to the child, scaled to the child's size.
    ///
    /// For example, an `Offset` with a `dx` of 0.25 will result in a horizontal
    /// translation of one quarter the width of the child.
    ///
    /// **Dart Source:** `proxy_box.dart:3017-3026`
    public var translation: Offset {
        get { _translation }
        set {
            if _translation == newValue {
                return
            }
            _translation = newValue
            markNeedsPaint()
            markNeedsSemanticsUpdate()
        }
    }
    private var _translation: Offset

    // MARK: - Compositing Bits (stub methods)

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    // MARK: - Hit Testing

    /// Hit tests at the given position.
    ///
    /// `RenderFractionalTranslation` objects don't check if they are themselves
    /// hit, because it's confusing to think about how the untransformed size and
    /// the child's transformed position interact.
    ///
    /// **Dart Source:** `proxy_box.dart:3029-3035`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        return hitTestChildren(result, position: position)
    }

    /// When set to true, hit tests are performed based on the position of the
    /// child as it is painted. When set to false, hit tests are performed
    /// ignoring the transformation.
    ///
    /// `applyPaintTransform`, and therefore `localToGlobal` and `globalToLocal`,
    /// always honor the transformation, regardless of the value of this property.
    ///
    /// **Dart Source:** `proxy_box.dart:3043`
    public var transformHitTests: Bool

    /// Hit tests children with the fractional translation offset applied.
    ///
    /// **Dart Source:** `proxy_box.dart:3046-3057`
    open override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        assert(!debugNeedsLayout)
        return result.addWithPaintOffset(
            offset: transformHitTests
                ? Offset(translation.dx * size.width, translation.dy * size.height)
                : nil,
            position: position,
            hitTest: { result, position in
                return super.hitTestChildren(result, position: position)
            }
        )
    }

    // MARK: - Paint

    /// Paints the child with the fractional translation offset applied.
    ///
    /// **Dart Source:** `proxy_box.dart:3060-3068`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        assert(!debugNeedsLayout)
        if child != nil {
            super.paint(
                context,
                Offset(
                    offset.dx + translation.dx * size.width,
                    offset.dy + translation.dy * size.height
                )
            )
        }
    }

    // MARK: - Paint Transform

    /// Applies the fractional translation paint transform to the child.
    ///
    /// **Dart Source:** `proxy_box.dart:3071-3073`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        transform.translate(translation.dx * size.width, translation.dy * size.height)
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `proxy_box.dart:3076-3080`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<String>("translation", String(describing: translation))
        )
        properties.add(
            DiagnosticsProperty<Bool>("transformHitTests", transformHitTests)
        )
    }
}

// =============================================================================
// MARK: - Pointer Event Listener Typealiases
// =============================================================================

/// Signature for listening to `PointerDownEvent` events.
///
/// Used by `Listener` and `RenderPointerListener`.
///
/// **Dart Source:** `proxy_box.dart:3086`
public typealias PointerDownEventListener = (PointerDownEvent) -> Void

/// Signature for listening to `PointerMoveEvent` events.
///
/// Used by `Listener` and `RenderPointerListener`.
///
/// **Dart Source:** `proxy_box.dart:3091`
public typealias PointerMoveEventListener = (PointerMoveEvent) -> Void

/// Signature for listening to `PointerUpEvent` events.
///
/// Used by `Listener` and `RenderPointerListener`.
///
/// **Dart Source:** `proxy_box.dart:3096`
public typealias PointerUpEventListener = (PointerUpEvent) -> Void

/// Signature for listening to `PointerCancelEvent` events.
///
/// Used by `Listener` and `RenderPointerListener`.
///
/// **Dart Source:** `proxy_box.dart:3101`
public typealias PointerCancelEventListener = (PointerCancelEvent) -> Void

/// Signature for listening to `PointerPanZoomStartEvent` events.
///
/// Used by `Listener` and `RenderPointerListener`.
///
/// **Dart Source:** `proxy_box.dart:3106`
public typealias PointerPanZoomStartEventListener = (PointerPanZoomStartEvent) -> Void

/// Signature for listening to `PointerPanZoomUpdateEvent` events.
///
/// Used by `Listener` and `RenderPointerListener`.
///
/// **Dart Source:** `proxy_box.dart:3111`
public typealias PointerPanZoomUpdateEventListener = (PointerPanZoomUpdateEvent) -> Void

/// Signature for listening to `PointerPanZoomEndEvent` events.
///
/// Used by `Listener` and `RenderPointerListener`.
///
/// **Dart Source:** `proxy_box.dart:3116`
public typealias PointerPanZoomEndEventListener = (PointerPanZoomEndEvent) -> Void

/// Signature for listening to `PointerSignalEvent` events.
///
/// Used by `Listener` and `RenderPointerListener`.
///
/// **Dart Source:** `proxy_box.dart:3121`
public typealias PointerSignalEventListener = (PointerSignalEvent) -> Void

/// Signature for listening to `PointerHoverEvent` events.
///
/// Used by `MouseTrackerAnnotation`, `MouseRegion` and `RenderMouseRegion`.
///
/// **Dart Source:** `mouse_tracking.dart:32`
public typealias PointerHoverEventListener = (PointerHoverEvent) -> Void

/// Signature for listening to `PointerEnterEvent` events.
///
/// Used by `MouseTrackerAnnotation`, `MouseRegion` and `RenderMouseRegion`.
///
/// **Dart Source:** `mouse_tracking.dart:22`
public typealias PointerEnterEventListener = (PointerEnterEvent) -> Void

/// Signature for listening to `PointerExitEvent` events.
///
/// Used by `MouseTrackerAnnotation`, `MouseRegion` and `RenderMouseRegion`.
///
/// **Dart Source:** `mouse_tracking.dart:27`
public typealias PointerExitEventListener = (PointerExitEvent) -> Void

// =============================================================================
// MARK: - RenderPointerListener
// =============================================================================

/// Calls callbacks in response to common pointer events.
///
/// It responds to events that can construct gestures, such as when the
/// pointer is pressed and moved, and then released or canceled.
///
/// It does not respond to events that are exclusive to mouse, such as when the
/// mouse enters and exits a region without pressing any buttons. For
/// these events, use `RenderMouseRegion`.
///
/// If it has a child, defers to the child for sizing behavior.
///
/// If it does not have a child, grows to fit the parent-provided constraints.
///
/// **Dart Source:** `proxy_box.dart:3135-3223`
open class RenderPointerListener: RenderProxyBoxWithHitTestBehavior {

    /// Creates a render object that forwards pointer events to callbacks.
    ///
    /// The `behavior` argument defaults to `HitTestBehavior.deferToChild`.
    ///
    /// **Dart Source:** `proxy_box.dart:3139-3151`
    public init(
        onPointerDown: PointerDownEventListener? = nil,
        onPointerMove: PointerMoveEventListener? = nil,
        onPointerUp: PointerUpEventListener? = nil,
        onPointerHover: PointerHoverEventListener? = nil,
        onPointerCancel: PointerCancelEventListener? = nil,
        onPointerPanZoomStart: PointerPanZoomStartEventListener? = nil,
        onPointerPanZoomUpdate: PointerPanZoomUpdateEventListener? = nil,
        onPointerPanZoomEnd: PointerPanZoomEndEventListener? = nil,
        onPointerSignal: PointerSignalEventListener? = nil,
        behavior: HitTestBehavior = .deferToChild,
        child: RenderBox? = nil
    ) {
        self.onPointerDown = onPointerDown
        self.onPointerMove = onPointerMove
        self.onPointerUp = onPointerUp
        self.onPointerHover = onPointerHover
        self.onPointerCancel = onPointerCancel
        self.onPointerPanZoomStart = onPointerPanZoomStart
        self.onPointerPanZoomUpdate = onPointerPanZoomUpdate
        self.onPointerPanZoomEnd = onPointerPanZoomEnd
        self.onPointerSignal = onPointerSignal
        super.init(behavior: behavior, child: child)
    }

    /// Called when a pointer comes into contact with the screen (for touch
    /// pointers), or has its button pressed (for mouse pointers) at this widget's
    /// location.
    ///
    /// **Dart Source:** `proxy_box.dart:3156`
    public var onPointerDown: PointerDownEventListener?

    /// Called when a pointer that triggered an `onPointerDown` changes position.
    ///
    /// **Dart Source:** `proxy_box.dart:3159`
    public var onPointerMove: PointerMoveEventListener?

    /// Called when a pointer that triggered an `onPointerDown` is no longer in
    /// contact with the screen.
    ///
    /// **Dart Source:** `proxy_box.dart:3163`
    public var onPointerUp: PointerUpEventListener?

    /// Called when a pointer that has not triggered an `onPointerDown` changes
    /// position.
    ///
    /// **Dart Source:** `proxy_box.dart:3166`
    public var onPointerHover: PointerHoverEventListener?

    /// Called when the input from a pointer that triggered an `onPointerDown` is
    /// no longer directed towards this receiver.
    ///
    /// **Dart Source:** `proxy_box.dart:3170`
    public var onPointerCancel: PointerCancelEventListener?

    /// Called when a pan/zoom begins such as from a trackpad gesture.
    ///
    /// **Dart Source:** `proxy_box.dart:3173`
    public var onPointerPanZoomStart: PointerPanZoomStartEventListener?

    /// Called when a pan/zoom is updated.
    ///
    /// **Dart Source:** `proxy_box.dart:3176`
    public var onPointerPanZoomUpdate: PointerPanZoomUpdateEventListener?

    /// Called when a pan/zoom finishes.
    ///
    /// **Dart Source:** `proxy_box.dart:3179`
    public var onPointerPanZoomEnd: PointerPanZoomEndEventListener?

    /// Called when a pointer signal occurs over this object.
    ///
    /// **Dart Source:** `proxy_box.dart:3182`
    public var onPointerSignal: PointerSignalEventListener?

    // MARK: - Layout

    /// Computes the size when there is no child.
    ///
    /// Returns the biggest size allowed by the constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:3185-3187`
    open override func computeSizeForNoChild(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }

    // MARK: - Event Handling

    /// Handles a pointer event by dispatching to the appropriate callback.
    ///
    /// Uses pattern matching on the event type to call the corresponding
    /// callback if it is non-nil.
    ///
    /// **Dart Source:** `proxy_box.dart:3190-3204`
    open override func handleEvent(_ event: PointerEvent, entry: HitTestEntry<AnyHitTestTarget>) {
        if let event = event as? PointerDownEvent {
            onPointerDown?(event)
        } else if let event = event as? PointerMoveEvent {
            onPointerMove?(event)
        } else if let event = event as? PointerUpEvent {
            onPointerUp?(event)
        } else if let event = event as? PointerHoverEvent {
            onPointerHover?(event)
        } else if let event = event as? PointerCancelEvent {
            onPointerCancel?(event)
        } else if let event = event as? PointerPanZoomStartEvent {
            onPointerPanZoomStart?(event)
        } else if let event = event as? PointerPanZoomUpdateEvent {
            onPointerPanZoomUpdate?(event)
        } else if let event = event as? PointerPanZoomEndEvent {
            onPointerPanZoomEnd?(event)
        } else if let event = event as? PointerSignalEvent {
            onPointerSignal?(event)
        }
    }
}

// =============================================================================
// MARK: - MouseTrackerAnnotationProtocol
// =============================================================================

/// Protocol representing the interface of `MouseTrackerAnnotation`.
///
/// In Dart, `MouseTrackerAnnotation` is a mixin that classes like
/// `RenderMouseRegion` implement. In Swift, since we cannot use multiple
/// inheritance, this protocol captures the annotation interface so that
/// render objects can conform to it while still inheriting from their
/// render object base class.
///
/// **Dart Source:** `mouse_tracking.dart:49`
public protocol MouseTrackerAnnotationProtocol: AnyObject {
    /// Triggered when a mouse pointer has entered the region.
    var onEnter: PointerEnterEventListener? { get }

    /// Triggered when a mouse pointer has exited the region.
    var onExit: PointerExitEventListener? { get }

    /// The mouse cursor for mouse pointers that are hovering over the region.
    var cursor: MouseCursor { get }

    /// Whether this is included when `MouseTracker` collects the list of
    /// annotations.
    var validForMouseTracker: Bool { get }
}

// =============================================================================
// MARK: - RenderMouseRegion
// =============================================================================

/// Calls callbacks in response to pointer events that are exclusive to mice.
///
/// It responds to events that are related to hovering, i.e. when the mouse
/// enters, exits (with or without pressing buttons), or moves over a region
/// without pressing buttons.
///
/// It does not respond to common events that construct gestures, such as when
/// the pointer is pressed, moved, then released or canceled. For these events,
/// use `RenderPointerListener`.
///
/// If it has a child, it defers to the child for sizing behavior.
///
/// If it does not have a child, it grows to fit the parent-provided constraints.
///
/// **Dart Source:** `proxy_box.dart:3243-3384`
open class RenderMouseRegion: RenderProxyBoxWithHitTestBehavior, MouseTrackerAnnotationProtocol {

    /// Creates a render object that forwards pointer events to callbacks.
    ///
    /// All parameters are optional. By default this method creates an opaque
    /// mouse region with no callbacks and cursor being `MouseCursor.defer_`.
    ///
    /// **Dart Source:** `proxy_box.dart:3249-3261`
    public init(
        onEnter: PointerEnterEventListener? = nil,
        onHover: PointerHoverEventListener? = nil,
        onExit: PointerExitEventListener? = nil,
        cursor: MouseCursor = MouseCursor.defer_,
        validForMouseTracker: Bool = true,
        opaque: Bool = true,
        child: RenderBox? = nil,
        hitTestBehavior: HitTestBehavior? = .opaque
    ) {
        self._onEnter = onEnter
        self.onHover = onHover
        self._onExit = onExit
        self._cursor = cursor
        self._validForMouseTracker = validForMouseTracker
        self._opaque = opaque
        super.init(behavior: hitTestBehavior ?? .opaque, child: child)
    }

    // MARK: - Hit Testing

    /// Determines the set of render objects located at the given position.
    ///
    /// Returns the result of the super implementation ANDed with `_opaque`,
    /// so that an opaque region will always report a hit if within bounds.
    ///
    /// **Dart Source:** `proxy_box.dart:3264-3266`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        return super.hitTest(result, position: position) && _opaque
    }

    // MARK: - Event Handling

    /// Handles a pointer event.
    ///
    /// Calls `onHover` when a `PointerHoverEvent` is received.
    ///
    /// **Dart Source:** `proxy_box.dart:3269-3274`
    open override func handleEvent(_ event: PointerEvent, entry: HitTestEntry<AnyHitTestTarget>) {
        if let hoverEvent = event as? PointerHoverEvent {
            onHover?(hoverEvent)
        }
    }

    // MARK: - Opaque

    /// Whether this object should prevent `RenderMouseRegion`s visually behind it
    /// from detecting the pointer, thus affecting how their `onHover`, `onEnter`,
    /// and `onExit` behave.
    ///
    /// If `opaque` is true, this object will absorb the mouse pointer and
    /// prevent this object's siblings (or any other objects that are not
    /// ancestors or descendants of this object) from detecting the mouse
    /// pointer even when the pointer is within their areas.
    ///
    /// If `opaque` is false, this object will not affect how `RenderMouseRegion`s
    /// behind it behave, which will detect the mouse pointer as long as the
    /// pointer is within their areas.
    ///
    /// This defaults to true.
    ///
    /// **Dart Source:** `proxy_box.dart:3290-3298`
    public var opaque: Bool {
        get { _opaque }
        set {
            if _opaque != newValue {
                _opaque = newValue
                // Trigger MouseTracker's device update to recalculate mouse states.
                markNeedsPaint()
            }
        }
    }
    private var _opaque: Bool

    // MARK: - Hit Test Behavior

    /// How to behave during hit testing.
    ///
    /// This defaults to `HitTestBehavior.opaque` if nil.
    ///
    /// **Dart Source:** `proxy_box.dart:3303-3311`
    public var hitTestBehavior: HitTestBehavior? {
        get { behavior }
        set {
            let newBehavior = newValue ?? .opaque
            if behavior != newBehavior {
                behavior = newBehavior
                // Trigger MouseTracker's device update to recalculate mouse states.
                markNeedsPaint()
            }
        }
    }

    // MARK: - MouseTrackerAnnotationProtocol

    /// Triggered when a mouse pointer has entered the region and
    /// `validForMouseTracker` is true.
    ///
    /// **Dart Source:** `proxy_box.dart:3314`
    public var onEnter: PointerEnterEventListener? {
        get { _onEnter }
        set { _onEnter = newValue }
    }
    private var _onEnter: PointerEnterEventListener?

    /// Triggered when a pointer has moved onto or within the region without
    /// buttons pressed.
    ///
    /// This callback is not triggered by the movement of the object.
    ///
    /// **Dart Source:** `proxy_box.dart:3320`
    public var onHover: PointerHoverEventListener?

    /// Triggered when a mouse pointer has exited the region and
    /// `validForMouseTracker` is true.
    ///
    /// **Dart Source:** `proxy_box.dart:3323`
    public var onExit: PointerExitEventListener? {
        get { _onExit }
        set { _onExit = newValue }
    }
    private var _onExit: PointerExitEventListener?

    /// The mouse cursor for mouse pointers that are hovering over the region.
    ///
    /// When a mouse pointer is hovering over the region, this cursor will be
    /// used. Defaults to `MouseCursor.defer_`.
    ///
    /// **Dart Source:** `proxy_box.dart:3326-3335`
    public var cursor: MouseCursor {
        get { _cursor }
        set {
            if _cursor !== newValue {
                _cursor = newValue
                // A repaint is needed in order to trigger a device update of
                // MouseTracker so that this new value can be found.
                markNeedsPaint()
            }
        }
    }
    private var _cursor: MouseCursor

    /// Whether this is included when `MouseTracker` collects the list of
    /// annotations.
    ///
    /// **Dart Source:** `proxy_box.dart:3338-3339`
    public var validForMouseTracker: Bool {
        get { _validForMouseTracker }
    }
    private var _validForMouseTracker: Bool

    // MARK: - Attach / Detach

    /// Called when the render object is attached to a pipeline owner.
    ///
    /// Sets `validForMouseTracker` to true.
    ///
    /// **Dart Source:** `proxy_box.dart:3342-3345`
    open override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _validForMouseTracker = true
    }

    /// Called when the render object is detached from a pipeline owner.
    ///
    /// Sets `validForMouseTracker` to false to prevent callbacks from being
    /// called during mouse event dispatching when the render object is detached.
    ///
    /// **Dart Source:** `proxy_box.dart:3348-3354`
    open override func detach() {
        // It's possible that the renderObject be detached during mouse events
        // dispatching, set the validForMouseTracker false to prevent
        // the callbacks from being called.
        _validForMouseTracker = false
        super.detach()
    }

    // MARK: - Layout

    /// Computes the size when there is no child.
    ///
    /// Returns the biggest size allowed by the constraints.
    ///
    /// **Dart Source:** `proxy_box.dart:3357-3359`
    open override func computeSizeForNoChild(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }
}

// MARK: - RenderRepaintBoundary

/// A render object that creates a separate display list for its child.
///
/// Useful for optimizing performance when a subtree repaints at different
/// times than its parent. When `isRepaintBoundary` is true, the framework
/// automatically creates an `OffsetLayer` for this render object, so that
/// when it is marked dirty for paint, only this object needs to be repainted,
/// not its parent.
///
/// **Dart Source:** `proxy_box.dart:3411-3648`
open class RenderRepaintBoundary: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a repaint boundary around the given child.
    ///
    /// **Dart Source:** `proxy_box.dart:3412-3413`
    public override init(child: RenderBox? = nil) {
        super.init(child: child)
    }

    // MARK: - Repaint Boundary

    /// Always returns `true` because this render object creates a separate
    /// display list for its child.
    ///
    /// **Dart Source:** `proxy_box.dart:3415-3416`
    open override var isRepaintBoundary: Bool { true }

    // MARK: - Image Capture

    /// Captures an image of the current state of this render object and its
    /// children.
    ///
    /// The returned image has uncompressed raw RGBA bytes in the dimensions
    /// of the render object, multiplied by the `pixelRatio`.
    ///
    /// To use this method, the render object must have gone through the paint
    /// phase (i.e., `debugNeedsPaint` must be false).
    ///
    /// The `pixelRatio` describes the scale between the logical pixels and the
    /// size of the output image. It is independent of the device pixel ratio,
    /// so specifying 1.0 (the default) will give you a 1:1 mapping between
    /// logical pixels and the output pixels in the image.
    ///
    /// - Parameter pixelRatio: The ratio of image pixels to logical pixels.
    ///   Defaults to 1.0.
    ///
    /// **Dart Source:** `proxy_box.dart:3477-3481`
    public func toImage(pixelRatio: Double = 1.0) {
        // TODO: Implement when OffsetLayer.toImage is available.
        // In Dart, this casts layer to OffsetLayer and calls toImage.
        fatalError("toImage is not yet implemented")
    }

    /// Captures an image of the current state of this render object and its
    /// children synchronously.
    ///
    /// - Parameter pixelRatio: The ratio of image pixels to logical pixels.
    ///   Defaults to 1.0.
    ///
    /// **Dart Source:** `proxy_box.dart:3543-3547`
    public func toImageSync(pixelRatio: Double = 1.0) {
        // TODO: Implement when OffsetLayer.toImageSync is available.
        fatalError("toImageSync is not yet implemented")
    }

    // MARK: - Debug Metrics

    /// The number of times that this render object repainted at the same time as
    /// its parent. Repaint boundaries are only useful when the parent and child
    /// paint at different times. When both paint at the same time, the repaint
    /// boundary is redundant, and may actually be making performance worse.
    ///
    /// Can be reset using `debugResetMetrics()`. See `debugAsymmetricPaintCount`
    /// for the corresponding count of times where only the parent or only the
    /// child painted.
    ///
    /// **Dart Source:** `proxy_box.dart:3560-3561`
    public var debugSymmetricPaintCount: Int = 0

    /// The number of times that either this render object repainted without the
    /// parent being painted, or the parent repainted without this object being
    /// painted. When a repaint boundary is used at a seam in the render tree
    /// where the parent tends to repaint at entirely different times than the
    /// child, it can improve performance by reducing the number of paint
    /// operations that have to be recorded each frame.
    ///
    /// Can be reset using `debugResetMetrics()`. See `debugSymmetricPaintCount`
    /// for the corresponding count of times where both the parent and the child
    /// painted together.
    ///
    /// **Dart Source:** `proxy_box.dart:3576-3577`
    public var debugAsymmetricPaintCount: Int = 0

    /// Resets the `debugSymmetricPaintCount` and `debugAsymmetricPaintCount`
    /// counts to zero.
    ///
    /// **Dart Source:** `proxy_box.dart:3583-3589`
    public func debugResetMetrics() {
        debugSymmetricPaintCount = 0
        debugAsymmetricPaintCount = 0
    }

    // MARK: - Offscreen Buffer

    /// The pixel ratio to use when painting offscreen.
    ///
    /// This is a hint for the rendering system about the resolution of the
    /// offscreen buffer.
    ///
    /// **Dart Source:** `proxy_box.dart` (implied by repaint boundary usage)
    public var offscreenBufferPixelRatio: Double = 1.0
}

// MARK: - RenderIgnorePointer

/// A render object that is invisible during hit testing.
///
/// When `ignoring` is true, this render object (and its subtree) is invisible
/// to hit testing. It still consumes space during layout and paints its child
/// as usual. It just cannot be the target of located events, because its render
/// object returns false from `hitTest`.
///
/// See also:
///
///  - `RenderAbsorbPointer`, which takes the pointer events but prevents any
///    nodes in the subtree from seeing them.
///
/// **Dart Source:** `proxy_box.dart:3670-3754`
open class RenderIgnorePointer: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that is invisible to hit testing.
    ///
    /// **Dart Source:** `proxy_box.dart:3671-3682`
    public init(child: RenderBox? = nil, ignoring: Bool = true) {
        _ignoring = ignoring
        super.init(child: child)
    }

    // MARK: - Properties

    /// Whether this render object is ignored during hit testing.
    ///
    /// Regardless of whether this render object is ignored during hit testing,
    /// it will still consume space during layout and be visible during painting.
    ///
    /// **Dart Source:** `proxy_box.dart:3690-3700`
    public var ignoring: Bool {
        get { _ignoring }
        set {
            if newValue == _ignoring {
                return
            }
            _ignoring = newValue
            markNeedsPaint()
        }
    }
    private var _ignoring: Bool

    // MARK: - Hit Testing

    /// Returns false when `ignoring` is true, preventing this render object
    /// and its subtree from receiving pointer events.
    ///
    /// **Dart Source:** `proxy_box.dart:3721-3724`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        return !ignoring && super.hitTest(result, position: position)
    }
}

// MARK: - RenderOffstage

/// Lays the child out as if it was in the tree, but without painting anything,
/// without making the child available for hit testing, and without taking any
/// room in the parent.
///
/// When `offstage` is true, the child is laid out but the render object
/// reports a zero size, does not paint, and does not hit test.
///
/// **Dart Source:** `proxy_box.dart:3759-3897`
open class RenderOffstage: RenderProxyBox {

    // MARK: - Initializer

    /// Creates an offstage render object.
    ///
    /// **Dart Source:** `proxy_box.dart:3760-3761`
    public init(offstage: Bool = true, child: RenderBox? = nil) {
        _offstage = offstage
        super.init(child: child)
    }

    // MARK: - Properties

    /// Whether the child is hidden from the rest of the tree.
    ///
    /// If true, the child is laid out as if it was in the tree, but without
    /// painting anything, without making the child available for hit testing,
    /// and without taking any room in the parent.
    ///
    /// If false, the child is included in the tree as normal.
    ///
    /// **Dart Source:** `proxy_box.dart:3770-3778`
    public var offstage: Bool {
        get { _offstage }
        set {
            if newValue == _offstage {
                return
            }
            _offstage = newValue
            // In Dart this calls markNeedsLayoutForSizedByParentChange() since
            // sizedByParent depends on offstage. Using markNeedsLayout() as the
            // pipeline owner system is not fully implemented.
            markNeedsLayout()
        }
    }
    private var _offstage: Bool

    // MARK: - Intrinsic Dimensions

    /// Returns 0 when offstage; otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3781-3786`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        if offstage {
            return 0.0
        }
        return super.computeMinIntrinsicWidth(height)
    }

    /// Returns 0 when offstage; otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3789-3794`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        if offstage {
            return 0.0
        }
        return super.computeMaxIntrinsicWidth(height)
    }

    /// Returns 0 when offstage; otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3797-3802`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        if offstage {
            return 0.0
        }
        return super.computeMinIntrinsicHeight(width)
    }

    /// Returns 0 when offstage; otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3805-3810`
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        if offstage {
            return 0.0
        }
        return super.computeMaxIntrinsicHeight(width)
    }

    // MARK: - Baseline

    /// Returns nil when offstage; otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3813-3818`
    open override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        if offstage {
            return nil
        }
        return super.computeDistanceToActualBaseline(baseline)
    }

    /// Returns nil when offstage; otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3824-3826`
    open override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        return offstage ? nil : super.computeDryBaseline(constraints, baseline)
    }

    // MARK: - Sized By Parent

    /// When offstage, this render object is sized by its parent (returns
    /// the smallest size from constraints, which is typically zero).
    ///
    /// **Dart Source:** `proxy_box.dart:3821`
    open override var sizedByParent: Bool { offstage }

    // MARK: - Dry Layout

    /// Returns the smallest size when offstage; otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3830-3835`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        if offstage {
            return constraints.smallest
        }
        return super.computeDryLayout(constraints)
    }

    // MARK: - Layout

    /// When offstage, performs resize as the size is determined by the parent.
    ///
    /// **Dart Source:** `proxy_box.dart:3838-3841`
    open override func performResize() {
        assert(offstage)
        super.performResize()
    }

    /// When offstage, lays out the child with the current constraints but does
    /// not use the child's size. When not offstage, delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3844-3850`
    open override func performLayout() {
        if offstage {
            child?.layout(boxConstraints)
        } else {
            super.performLayout()
        }
    }

    // MARK: - Hit Testing

    /// Returns false when offstage, preventing this render object and its
    /// subtree from receiving pointer events.
    ///
    /// **Dart Source:** `proxy_box.dart:3853-3855`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        return !offstage && super.hitTest(result, position: position)
    }

    // MARK: - Painting

    /// Returns whether the child is actually painted (not offstage).
    ///
    /// **Dart Source:** `proxy_box.dart:3858-3861`
    open func paintsChild(_ child: RenderBox) -> Bool {
        assert(child.parent === self)
        return !offstage
    }

    /// When offstage, does not paint. Otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3864-3869`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if offstage {
            return
        }
        super.paint(context, offset)
    }
}

// MARK: - RenderAbsorbPointer

/// A render object that absorbs pointers during hit testing.
///
/// When `absorbing` is true, this render object prevents its subtree from
/// receiving pointer events by terminating hit testing at itself. It still
/// consumes space during layout and paints its child as usual. It just prevents
/// its children from being the target of located events, because its render
/// object returns true from `hitTest`.
///
/// See also:
///
///  - `RenderIgnorePointer`, which has the opposite effect: removing the
///    subtree from consideration entirely for the purposes of hit testing.
///
/// **Dart Source:** `proxy_box.dart:3920-4006`
open class RenderAbsorbPointer: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that absorbs pointers during hit testing.
    ///
    /// **Dart Source:** `proxy_box.dart:3921-3932`
    public init(child: RenderBox? = nil, absorbing: Bool = true) {
        _absorbing = absorbing
        super.init(child: child)
    }

    // MARK: - Properties

    /// Whether this render object absorbs pointers during hit testing.
    ///
    /// Regardless of whether this render object absorbs pointers during hit
    /// testing, it will still consume space during layout and be visible during
    /// painting.
    ///
    /// **Dart Source:** `proxy_box.dart:3941-3951`
    public var absorbing: Bool {
        get { _absorbing }
        set {
            if newValue == _absorbing {
                return
            }
            _absorbing = newValue
            markNeedsPaint()
        }
    }
    private var _absorbing: Bool

    // MARK: - Hit Testing

    /// When absorbing, returns true if the position is within bounds
    /// (absorbing all pointer events). Otherwise delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:3974-3976`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        return absorbing
            ? size.contains(position)
            : super.hitTest(result, position: position)
    }
}

// MARK: - RenderMetaData

/// Holds opaque metadata in the render tree.
///
/// Useful for decorating the render tree with information that will be consumed
/// later. For example, you could store information in the render tree that will
/// be used when the user interacts with the render tree but has no visual
/// impact prior to the interaction.
///
/// **Dart Source:** `proxy_box.dart:4014-4028`
open class RenderMetaData: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that holds opaque metadata.
    ///
    /// **Dart Source:** `proxy_box.dart:4017-4018`
    public init(metaData: Any? = nil, child: RenderBox? = nil) {
        self.metaData = metaData
        super.init(child: child)
    }

    // MARK: - Properties

    /// Opaque metadata ignored by the render tree.
    ///
    /// **Dart Source:** `proxy_box.dart:4021`
    public var metaData: Any?
}

// MARK: - RenderSemanticsGestureHandler

/// Handles semantics gesture callbacks (onTap, onLongPress,
/// onHorizontalDragUpdate, onVerticalDragUpdate) for accessibility.
///
/// This is a STUB implementation. The full version translates semantic
/// scroll/drag actions into gesture callbacks and configures the
/// `SemanticsConfiguration` accordingly. Because the full semantics gesture
/// pipeline depends on types not yet migrated (`describeSemanticsConfiguration`
/// override, `DragUpdateDetails` creation from semantic scroll actions, etc.),
/// only the property surface is provided here.
///
/// **Dart Source:** `proxy_box.dart:4032-4231`
open class RenderSemanticsGestureHandler: RenderProxyBoxWithHitTestBehavior {

    // MARK: - Initializer

    /// Creates a render object that listens for specific semantic gestures.
    ///
    /// **Dart Source:** `proxy_box.dart:4034-4045`
    public init(
        child: RenderBox? = nil,
        onTap: GestureTapCallback? = nil,
        onLongPress: GestureLongPressCallback? = nil,
        onHorizontalDragUpdate: GestureDragUpdateCallback? = nil,
        onVerticalDragUpdate: GestureDragUpdateCallback? = nil,
        scrollFactor: Double = 0.8,
        behavior: HitTestBehavior = .deferToChild
    ) {
        self._onTap = onTap
        self._onLongPress = onLongPress
        self._onHorizontalDragUpdate = onHorizontalDragUpdate
        self._onVerticalDragUpdate = onVerticalDragUpdate
        self.scrollFactor = scrollFactor
        super.init(behavior: behavior, child: child)
    }

    // MARK: - Properties

    /// If non-nil, the set of actions to allow. Other actions will be omitted,
    /// even if their callback is provided.
    ///
    /// **Dart Source:** `proxy_box.dart:4060-4068`
    public var validActions: Set<SemanticsAction>? {
        get { _validActions }
        set {
            if _validActions == newValue { return }
            _validActions = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _validActions: Set<SemanticsAction>?

    /// Called when the user taps on the render object.
    ///
    /// **Dart Source:** `proxy_box.dart:4071-4082`
    public var onTap: GestureTapCallback? {
        get { _onTap }
        set {
            let hadHandler = _onTap != nil
            _onTap = newValue
            if (newValue != nil) != hadHandler {
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _onTap: GestureTapCallback?

    /// Called when the user presses on the render object for a long period of time.
    ///
    /// **Dart Source:** `proxy_box.dart:4085-4096`
    public var onLongPress: GestureLongPressCallback? {
        get { _onLongPress }
        set {
            let hadHandler = _onLongPress != nil
            _onLongPress = newValue
            if (newValue != nil) != hadHandler {
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _onLongPress: GestureLongPressCallback?

    /// Called when the user scrolls to the left or to the right.
    ///
    /// **Dart Source:** `proxy_box.dart:4099-4110`
    public var onHorizontalDragUpdate: GestureDragUpdateCallback? {
        get { _onHorizontalDragUpdate }
        set {
            let hadHandler = _onHorizontalDragUpdate != nil
            _onHorizontalDragUpdate = newValue
            if (newValue != nil) != hadHandler {
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _onHorizontalDragUpdate: GestureDragUpdateCallback?

    /// Called when the user scrolls up or down.
    ///
    /// **Dart Source:** `proxy_box.dart:4113-4124`
    public var onVerticalDragUpdate: GestureDragUpdateCallback? {
        get { _onVerticalDragUpdate }
        set {
            let hadHandler = _onVerticalDragUpdate != nil
            _onVerticalDragUpdate = newValue
            if (newValue != nil) != hadHandler {
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _onVerticalDragUpdate: GestureDragUpdateCallback?

    /// The fraction of the dimension of this render box to use when
    /// scrolling. For example, if this is 0.8 and the box is 200 pixels
    /// wide, then when a left-scroll action is received from the
    /// accessibility system, it will translate into a 160 pixel
    /// leftwards drag.
    ///
    /// **Dart Source:** `proxy_box.dart:4131`
    public var scrollFactor: Double

    // MARK: - Semantics Configuration

    /// Describes the semantics configuration for this gesture handler:
    /// tap/long-press callbacks become semantics actions (the agent
    /// endpoint's `perform_action` invokes exactly these). The drag/scroll
    /// translation of the Dart original is still unported.
    ///
    /// **Dart Source:** `proxy_box.dart:4134-4159`
    open override func describeSemanticsConfiguration(_ config: SemanticsConfiguration) {
        super.describeSemanticsConfiguration(config)
        if let onTap, _isValidAction(.tap) {
            config.onTap = onTap
        }
        if let onLongPress, _isValidAction(.longPress) {
            config.onLongPress = onLongPress
        }
    }

    /// Whether a given `SemanticsAction` is valid for this handler.
    ///
    /// **Dart Source:** `proxy_box.dart:4161-4163`
    private func _isValidAction(_ action: SemanticsAction) -> Bool {
        return _validActions == nil || _validActions!.contains(action)
    }

    // MARK: - Semantics

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }
}

// MARK: - RenderSemanticsAnnotations

/// Attaches semantic annotation properties to its child.
///
/// This is a STUB implementation. The full version uses `SemanticsProperties`
/// and `SemanticsAnnotationsMixin` to configure the semantics tree. Since
/// `SemanticsProperties` has not yet been migrated to Swift, this stub holds
/// the key structural properties and marks semantics as needing an update when
/// they change.
///
/// **Dart Source:** `proxy_box.dart:4234-4258`
open class RenderSemanticsAnnotations: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that attaches a semantic annotation.
    ///
    /// **Dart Source:** `proxy_box.dart:4238-4257`
    ///
    /// TODO: Accept `SemanticsProperties` when the type is available.
    public init(
        child: RenderBox? = nil,
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

// MARK: - RenderBlockSemantics

/// Causes the semantics of all earlier render objects below the same semantic
/// boundary to be dropped.
///
/// This is useful in a stack where an opaque mask should prevent interactions
/// with the render objects painted below the mask.
///
/// **Dart Source:** `proxy_box.dart:4265-4295`
open class RenderBlockSemantics: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that blocks semantics for nodes below it
    /// in paint order.
    ///
    /// **Dart Source:** `proxy_box.dart:4268-4270`
    public init(child: RenderBox? = nil, blocking: Bool = true) {
        self._blocking = blocking
        super.init(child: child)
    }

    // MARK: - Properties

    /// Whether this render object is blocking semantics of previously painted
    /// `RenderObject`s below a common semantics boundary from the semantic tree.
    ///
    /// **Dart Source:** `proxy_box.dart:4274-4282`
    public var blocking: Bool {
        get { _blocking }
        set {
            if newValue == _blocking { return }
            _blocking = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _blocking: Bool

    // MARK: - Semantics

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    /// Describes the semantics configuration for blocking semantics.
    ///
    /// **Dart Source:** `proxy_box.dart:4285-4288`
    ///
    /// TODO: Call `super.describeSemanticsConfiguration(config)` when the
    /// base class method is available.
    open override func describeSemanticsConfiguration(_ config: SemanticsConfiguration) {
        config.isBlockingSemanticsOfPreviouslyPaintedNodes = blocking
    }

    // MARK: - Debug

    /// **Dart Source:** `proxy_box.dart:4291-4294`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(
            DiagnosticsProperty<Bool>("blocking", blocking)
        )
    }
}

// MARK: - RenderMergeSemantics

/// Causes the semantics of all descendants to be merged into this
/// node such that the entire subtree becomes a single leaf in the
/// semantics tree.
///
/// Useful for combining the semantics of multiple render objects that
/// form part of a single conceptual widget, e.g. a checkbox, a label,
/// and the gesture detector that goes with them.
///
/// **Dart Source:** `proxy_box.dart:4304-4315`
open class RenderMergeSemantics: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that merges the semantics from its descendants.
    ///
    /// **Dart Source:** `proxy_box.dart:4306`
    public override init(child: RenderBox? = nil) {
        super.init(child: child)
    }

    // MARK: - Semantics

    /// Describes the semantics configuration for merging semantics.
    ///
    /// Sets `isSemanticBoundary` to true and `isMergingSemanticsOfDescendants`
    /// to true so that the entire subtree becomes a single leaf in the
    /// semantics tree.
    ///
    /// **Dart Source:** `proxy_box.dart:4309-4314`
    ///
    /// TODO: Call `super.describeSemanticsConfiguration(config)` when the
    /// base class method is available.
    open override func describeSemanticsConfiguration(_ config: SemanticsConfiguration) {
        config.isSemanticBoundary = true
        config.isMergingSemanticsOfDescendants = true
    }
}

// MARK: - RenderExcludeSemantics

/// Excludes this subtree from the semantic tree.
///
/// When `excluding` is true, this render object (and its subtree) is excluded
/// from the semantic tree.
///
/// Useful e.g. for hiding text that is redundant with other text next
/// to it (e.g. text included only for the visual effect).
///
/// **Dart Source:** `proxy_box.dart:4324-4354`
open class RenderExcludeSemantics: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that ignores the semantics of its subtree.
    ///
    /// **Dart Source:** `proxy_box.dart:4326-4328`
    public init(child: RenderBox? = nil, excluding: Bool = true) {
        self._excluding = excluding
        super.init(child: child)
    }

    // MARK: - Properties

    /// Whether this render object is excluded from the semantic tree.
    ///
    /// **Dart Source:** `proxy_box.dart:4331-4339`
    public var excluding: Bool {
        get { _excluding }
        set {
            if newValue == _excluding { return }
            _excluding = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _excluding: Bool

    // MARK: - Semantics

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    /// When excluding, skips visiting children for semantics.
    ///
    /// **Dart Source:** `proxy_box.dart:4342-4347`
    ///
    /// DIFFERENCE FROM DART: Not an override because `visitChildrenForSemantics`
    /// is not yet declared on the `RenderProxyBox` base class.
    /// REASON: The base `RenderObject.visitChildrenForSemantics` has not been
    /// migrated as a virtual method yet.
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        if excluding { return }
        // When not excluding, visit child normally
        if let child = child {
            visitor(child)
        }
    }

    // MARK: - Debug

    /// **Dart Source:** `proxy_box.dart:4350-4353`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(
            DiagnosticsProperty<Bool>("excluding", excluding)
        )
    }
}

// MARK: - RenderIndexedSemantics

/// A render object that annotates semantics with an index.
///
/// Certain widgets will automatically provide a child index for building
/// semantics. For example, the `ScrollView` uses the index of the first
/// visible child semantics node to determine the
/// `SemanticsConfiguration.scrollIndex`.
///
/// See also:
///
///  - `CustomScrollView`, for an explanation of scroll semantics.
///
/// **Dart Source:** `proxy_box.dart:4366-4392`
open class RenderIndexedSemantics: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that annotates the child semantics with an index.
    ///
    /// **Dart Source:** `proxy_box.dart:4368`
    public init(child: RenderBox? = nil, index: Int) {
        self._index = index
        super.init(child: child)
    }

    // MARK: - Properties

    /// The index used to annotate child semantics.
    ///
    /// **Dart Source:** `proxy_box.dart:4371-4379`
    public var index: Int {
        get { _index }
        set {
            if newValue == _index { return }
            _index = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _index: Int

    // MARK: - Semantics

    /// Marks the semantics tree as needing an update.
    ///
    /// **Dart Source:** `object.dart:3600-3640`
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with semantics owner
    }

    /// Describes the semantics configuration for indexed semantics.
    ///
    /// Sets `indexInParent` on the configuration to the current `index`.
    ///
    /// **Dart Source:** `proxy_box.dart:4382-4385`
    ///
    /// TODO: Call `super.describeSemanticsConfiguration(config)` when the
    /// base class method is available.
    open override func describeSemanticsConfiguration(_ config: SemanticsConfiguration) {
        config.indexInParent = index
    }

    // MARK: - Debug

    /// **Dart Source:** `proxy_box.dart:4388-4391`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(
            DiagnosticsProperty<Int>("index", index)
        )
    }
}
// MARK: - RenderLeaderLayer

/// Render object that uses a `LeaderLayer`.
///
/// A `RenderLeaderLayer` is typically paired with one or more
/// `RenderFollowerLayer`s via a shared `LayerLink`. The leader controls
/// the transform that the followers apply to themselves.
///
/// **Dart Source:** `proxy_box.dart:4400-4460`
open class RenderLeaderLayer: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that uses a `LeaderLayer`.
    ///
    /// **Dart Source:** `proxy_box.dart:4402`
    public init(link: LayerLink, child: RenderBox? = nil) {
        self._link = link
        super.init(child: child)
    }

    // MARK: - Properties

    /// The link object that connects this `RenderLeaderLayer` with one or more
    /// `RenderFollowerLayer`s.
    ///
    /// The object must not be associated with another `RenderLeaderLayer` that
    /// is also being painted.
    ///
    /// **Dart Source:** `proxy_box.dart:4409-4421`
    public var link: LayerLink {
        get { _link }
        set {
            if newValue === _link {
                return
            }
            _link.leaderSize = nil
            _link = newValue
            if _previousLayoutSize != nil {
                _link.leaderSize = _previousLayoutSize
            }
            markNeedsPaint()
        }
    }
    private var _link: LayerLink

    // MARK: - Compositing

    /// This render object always needs compositing because it creates a
    /// `LeaderLayer`.
    ///
    /// **Dart Source:** `proxy_box.dart:4424`
    open override var alwaysNeedsCompositing: Bool { true }

    // MARK: - Layout

    /// The latest size of this render box, computed during the previous layout
    /// pass. It should always be equal to `size`, but can be accessed even when
    /// `debugDoingThisResize` and `debugDoingThisLayout` are false.
    ///
    /// **Dart Source:** `proxy_box.dart:4429`
    private var _previousLayoutSize: Size?

    /// Lays out the child and records the size on the link.
    ///
    /// **Dart Source:** `proxy_box.dart:4432-4436`
    open override func performLayout() {
        super.performLayout()
        _previousLayoutSize = size
        link.leaderSize = size
    }

    // MARK: - Layer Handle

    /// Layer handle for the `LeaderLayer` used during painting.
    ///
    /// **Dart Source:** `proxy_box.dart:4439` (implicit)
    private var _layerHandle = LayerHandle<LeaderLayer>()

    // MARK: - Painting

    /// Paints the child within a `LeaderLayer`.
    ///
    /// **Dart Source:** `proxy_box.dart:4439-4453`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if _layerHandle.layer == nil {
            _layerHandle.layer = LeaderLayer(link: link, offset: offset)
        } else {
            let leaderLayer = _layerHandle.layer!
            leaderLayer.link = link
            leaderLayer.offset = offset
        }
        // The child paints at the layer's origin, and the layer carries the
        // offset. That is Dart's contract too, but Dart's painting contexts are
        // bounded in the nearest repaint boundary's LOCAL space, so (0, 0) is
        // always inside them; this port has no interior boundaries and every
        // context is bounded in absolute coordinates, so a leader anywhere but
        // the top-left corner would hand its child a picture whose cull rect
        // it lies entirely outside of -- and the engine drops ops outside the
        // cull rect at record time. Nothing was drawn, with no error: every
        // flyout target (drop-down, combo box, date picker) was blank. Bound
        // the child's picture generously, as the follower already does.
        context.pushLayer(_layerHandle.layer!, { ctx, off in
            super.paint(ctx, off)
        }, .zero, childPaintBounds: Rect.fromLTRB(-1e9, -1e9, 1e9, 1e9))
    }

    // MARK: - Disposal

    /// Cleans up the layer handle.
    ///
    /// **Dart Source:** `proxy_box.dart:4455` (implicit)
    open override func dispose() {
        _layerHandle.layer = nil
        super.dispose()
    }

    // MARK: - Diagnostics

    /// **Dart Source:** `proxy_box.dart:4456-4459`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(DiagnosticsProperty<LayerLink>("link", link))
    }
}

// MARK: - RenderFollowerLayer

/// Transform the child so that its origin is `offset` from the origin of the
/// `RenderLeaderLayer` with the same `LayerLink`.
///
/// The `RenderLeaderLayer` in question must be earlier in the paint order.
///
/// Hit testing on descendants of this render object will only work if the
/// target position is within the box that this render object's parent considers
/// to be hittable.
///
/// See also:
///
///  * `FollowerLayer`, the layer that this render object creates.
///
/// **Dart Source:** `proxy_box.dart:4475-4678`
open class RenderFollowerLayer: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a render object that uses a `FollowerLayer`.
    ///
    /// **Dart Source:** `proxy_box.dart:4477-4489`
    public init(
        link: LayerLink,
        showWhenUnlinked: Bool = true,
        offset: Offset = .zero,
        leaderAnchor: Alignment = .topLeft,
        followerAnchor: Alignment = .topLeft,
        child: RenderBox? = nil
    ) {
        self._link = link
        self._showWhenUnlinked = showWhenUnlinked
        self._offset = offset
        self._leaderAnchor = leaderAnchor
        self._followerAnchor = followerAnchor
        super.init(child: child)
    }

    // MARK: - Properties

    /// The link object that connects this `RenderFollowerLayer` with a
    /// `RenderLeaderLayer` earlier in the paint order.
    ///
    /// **Dart Source:** `proxy_box.dart:4493-4501`
    public var link: LayerLink {
        get { _link }
        set {
            if newValue === _link {
                return
            }
            _link = newValue
            markNeedsPaint()
        }
    }
    private var _link: LayerLink

    /// Whether to show the render object's contents when there is no
    /// corresponding `RenderLeaderLayer` with the same `link`.
    ///
    /// When the render object is linked, the child is positioned such that it
    /// has the same global position as the linked `RenderLeaderLayer`.
    ///
    /// When the render object is not linked, then: if `showWhenUnlinked` is
    /// true, the child is visible and not repositioned; if it is false, then
    /// the child is hidden, and its hit testing is also disabled.
    ///
    /// **Dart Source:** `proxy_box.dart:4512-4520`
    public var showWhenUnlinked: Bool {
        get { _showWhenUnlinked }
        set {
            if _showWhenUnlinked == newValue {
                return
            }
            _showWhenUnlinked = newValue
            markNeedsPaint()
        }
    }
    private var _showWhenUnlinked: Bool

    /// The offset to apply to the origin of the linked `RenderLeaderLayer`
    /// to obtain this render object's origin.
    ///
    /// **Dart Source:** `proxy_box.dart:4524-4532`
    public var offset: Offset {
        get { _offset }
        set {
            if _offset == newValue {
                return
            }
            _offset = newValue
            markNeedsPaint()
        }
    }
    private var _offset: Offset

    /// The anchor point on the linked `RenderLeaderLayer` that
    /// `followerAnchor` will line up with.
    ///
    /// Defaults to `Alignment.topLeft`.
    ///
    /// **Dart Source:** `proxy_box.dart:4548-4556`
    public var leaderAnchor: Alignment {
        get { _leaderAnchor }
        set {
            if _leaderAnchor == newValue {
                return
            }
            _leaderAnchor = newValue
            markNeedsPaint()
        }
    }
    private var _leaderAnchor: Alignment

    /// The anchor point on this `RenderFollowerLayer` that will line up with
    /// `leaderAnchor` on the linked `RenderLeaderLayer`.
    ///
    /// Defaults to `Alignment.topLeft`.
    ///
    /// **Dart Source:** `proxy_box.dart:4564-4572`
    public var followerAnchor: Alignment {
        get { _followerAnchor }
        set {
            if _followerAnchor == newValue {
                return
            }
            _followerAnchor = newValue
            markNeedsPaint()
        }
    }
    private var _followerAnchor: Alignment

    // MARK: - Detach

    /// Clears the follower layer when detaching from the render tree.
    ///
    /// **Dart Source:** `proxy_box.dart:4575-4578`
    open override func detach() {
        _followerLayer = nil
        super.detach()
    }

    // MARK: - Compositing

    /// This render object always needs compositing because it creates a
    /// `FollowerLayer`.
    ///
    /// **Dart Source:** `proxy_box.dart:4581`
    open override var alwaysNeedsCompositing: Bool { true }

    // MARK: - Layer

    /// The follower layer used during painting.
    ///
    /// **Dart Source:** `proxy_box.dart:4584-4585`
    private var _followerLayer: FollowerLayer?

    /// Returns the transform that was used in the last composition phase, if
    /// any.
    ///
    /// If the `FollowerLayer` has not yet been created, was never composited,
    /// or was unable to determine the transform (see
    /// `FollowerLayer.getLastTransform`), this returns the identity matrix.
    ///
    /// **Dart Source:** `proxy_box.dart:4593-4595`
    public func getCurrentTransform() -> Matrix4 {
        return _followerLayer?.getLastTransform() ?? Matrix4.identity()
    }

    // MARK: - Hit Testing

    /// Disables hit testing when the leader is unlinked and
    /// `showWhenUnlinked` is false.
    ///
    /// **Dart Source:** `proxy_box.dart:4598-4608`
    public override func hitTest(_ result: BoxHitTestResult, position: Offset) -> Bool {
        // Disables the hit testing if this render object is hidden.
        if link.leader == nil && !showWhenUnlinked {
            return false
        }
        // RenderFollowerLayer objects don't check if they are
        // themselves hit, because it's confusing to think about
        // how the untransformed size and the child's transformed
        // position interact.
        return hitTestChildren(result, position: position)
    }

    /// Transforms the hit test position using the current transform and
    /// delegates to super.
    ///
    /// **Dart Source:** `proxy_box.dart:4611-4619`
    public override func hitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool {
        return result.addWithPaintTransform(
            transform: getCurrentTransform(),
            position: position,
            hitTest: { result, position in
                return super.hitTestChildren(result, position: position)
            }
        )
    }

    // MARK: - Layout

    /// `sizedByParent` returns false — size depends on the child.
    ///
    /// **Dart Source:** implied from proxy box default
    open override var sizedByParent: Bool { false }

    // MARK: - Painting

    /// Paints the child within a `FollowerLayer`.
    ///
    /// **Dart Source:** `proxy_box.dart:4622-4663`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        let leaderSize = link.leaderSize
        assert(
            leaderSize != nil || link.leader == nil || leaderAnchor == .topLeft,
            "\(link): layer is linked to \(String(describing: link.leader)) but a valid leaderSize is not set. "
            + "leaderSize is required when leaderAnchor is not Alignment.topLeft "
            + "(current value is \(leaderAnchor))."
        )
        let effectiveLinkedOffset: Offset
        if let leaderSize = leaderSize {
            effectiveLinkedOffset = leaderAnchor.alongSize(leaderSize) - followerAnchor.alongSize(size) + self.offset
        } else {
            effectiveLinkedOffset = self.offset
        }
        if _followerLayer == nil {
            _followerLayer = FollowerLayer(
                link: link,
                showWhenUnlinked: showWhenUnlinked,
                unlinkedOffset: offset,
                linkedOffset: effectiveLinkedOffset
            )
        } else {
            _followerLayer!.link = link
            _followerLayer!.showWhenUnlinked = showWhenUnlinked
            _followerLayer!.unlinkedOffset = offset
            _followerLayer!.linkedOffset = effectiveLinkedOffset
        }
        context.pushLayer(
            _followerLayer!,
            { ctx, off in super.paint(ctx, off) },
            .zero,
            childPaintBounds: Rect.fromLTRB(
                -.infinity,
                -.infinity,
                .infinity,
                .infinity
            )
        )
    }

    // MARK: - Paint Transform

    /// Applies the follower layer transform to the given child's transform.
    ///
    /// **Dart Source:** `proxy_box.dart:4666-4668`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        transform = transform * getCurrentTransform()
    }

    // MARK: - Diagnostics

    /// **Dart Source:** `proxy_box.dart:4671-4677`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // super.debugFillProperties(properties) — not yet available on RenderObject stub.
        properties.add(DiagnosticsProperty<LayerLink>("link", link))
        properties.add(DiagnosticsProperty<Bool>("showWhenUnlinked", showWhenUnlinked))
        properties.add(DiagnosticsProperty<Offset>("offset", offset))
        properties.add(DiagnosticsProperty<Matrix4>("current transform matrix", getCurrentTransform()))
    }
}

// MARK: - RenderAnnotatedRegion

/// Render object which inserts an `AnnotatedRegionLayer` into the layer tree.
///
/// See also:
///
///  * `Layer.find`, for an example of how this value is retrieved.
///  * `AnnotatedRegionLayer`, the layer this render object creates.
///
/// **Dart Source:** `proxy_box.dart:4686-4744`
open class RenderAnnotatedRegion<T>: RenderProxyBox {

    // MARK: - Initializer

    /// Creates a new `RenderAnnotatedRegion` to insert `value` into the
    /// layer tree.
    ///
    /// If `sized` is true, the layer is provided with the size of this render
    /// object to clip the results of `Layer.find`.
    ///
    /// **Dart Source:** `proxy_box.dart:4694-4698`
    public init(value: T, sized: Bool, child: RenderBox? = nil) {
        self._value = value
        self._sized = sized
        self._layerHandle = LayerHandle<AnnotatedRegionLayer<T>>()
        super.init(child: child)
    }

    // MARK: - Properties

    /// A value which can be retrieved using `Layer.find`.
    ///
    /// **Dart Source:** `proxy_box.dart:4701-4709`
    public var value: T {
        get { _value }
        set {
            // Note: Cannot use == for generic T, always update.
            _value = newValue
            markNeedsPaint()
        }
    }
    private var _value: T

    /// Whether the render object will pass its `size` to the
    /// `AnnotatedRegionLayer`.
    ///
    /// **Dart Source:** `proxy_box.dart:4712-4720`
    public var sized: Bool {
        get { _sized }
        set {
            if _sized == newValue {
                return
            }
            _sized = newValue
            markNeedsPaint()
        }
    }
    private var _sized: Bool

    /// Layer handle for the annotated region layer.
    ///
    /// **Dart Source:** `proxy_box.dart:4722`
    private var _layerHandle: LayerHandle<AnnotatedRegionLayer<T>>

    // MARK: - Compositing

    /// This render object always needs compositing because it creates an
    /// `AnnotatedRegionLayer`.
    ///
    /// **Dart Source:** `proxy_box.dart:4725`
    open override var alwaysNeedsCompositing: Bool { true }

    // MARK: - Painting

    /// Paints the child within an `AnnotatedRegionLayer`.
    ///
    /// Annotated region layers are not retained because they do not create
    /// engine layers.
    ///
    /// **Dart Source:** `proxy_box.dart:4728-4737`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        let layer = AnnotatedRegionLayer<T>(
            value,
            size: sized ? size : nil,
            offset: sized ? offset : nil
        )
        _layerHandle.layer = layer
        context.pushLayer(layer, { ctx, off in
            super.paint(ctx, off)
        }, offset)
    }

    // MARK: - Disposal

    /// Cleans up the layer handle.
    ///
    /// **Dart Source:** `proxy_box.dart:4740-4743`
    open override func dispose() {
        _layerHandle.layer = nil
        super.dispose()
    }
}

// MARK: - SingleChildRenderObjectHost Conformance

extension RenderProxyBox: SingleChildRenderObjectHost {}
