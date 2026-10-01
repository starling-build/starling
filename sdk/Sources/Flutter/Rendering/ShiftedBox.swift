// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// One-child-layout render boxes that provide control over the child's position.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/shifted_box.dart`

import FlutterSwiftBridge

// MARK: - BoxConstraintsTransform

/// Signature for a function that transforms a `BoxConstraints` to another
/// `BoxConstraints`.
///
/// Used by `RenderConstraintsTransformBox` and `ConstraintsTransformBox`.
/// Typically the caller requires the returned `BoxConstraints` to be
/// `BoxConstraints.isNormalized`.
///
/// **Dart Source:** `shifted_box.dart:28`
public typealias BoxConstraintsTransform = (BoxConstraints) -> BoxConstraints

// MARK: - RenderShiftedBox

/// Abstract class for one-child-layout render boxes that provide control over
/// the child's position.
///
/// In Dart, `RenderShiftedBox` extends `RenderBox` and mixes in
/// `RenderObjectWithChildMixin<RenderBox>`. In Swift, since generic mixins are
/// not supported, the single-child management is implemented directly on the
/// class (same pattern as `RenderProxyBox`).
///
/// **Dart Source:** `shifted_box.dart:32-101`
open class RenderShiftedBox: RenderBox {

    // MARK: - Initializer

    /// Initializes the `child` property for subclasses.
    ///
    /// **Dart Source:** `shifted_box.dart:34-36`
    public init(child: RenderBox? = nil) {
        super.init()
        self.child = child
    }

    // MARK: - Child Management (RenderObjectWithChildMixin pattern)

    /// The single child of this render object.
    ///
    /// In Dart, `RenderShiftedBox` uses `RenderObjectWithChildMixin<RenderBox>`
    /// to manage its single child. In Swift, since generic mixins are not
    /// supported, the child property is implemented directly.
    ///
    /// **Dart Source:** `shifted_box.dart:32` (via RenderObjectWithChildMixin)
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

    /// **Dart Source:** `RenderObjectWithChildMixin.visitChildren`
    open override func visitChildren(_ visitor: RenderObjectVisitor) {
        if let child = _child {
            visitor(child)
        }
    }

    /// Sets up `ParentData` for the given child.
    ///
    /// `RenderShiftedBox` uses `BoxParentData` (which has an `offset` property)
    /// because shifted boxes position their child at a specific offset.
    ///
    /// **Dart Source:** `shifted_box.dart:32` (via RenderBox.setupParentData)
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is BoxParentData) {
            child.parentData = BoxParentData()
        }
    }

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width by delegating to the child.
    ///
    /// Returns the child's minimum intrinsic width, or 0.0 if there is no child.
    ///
    /// **Dart Source:** `shifted_box.dart:39-41`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        return child?.getMinIntrinsicWidth(height) ?? 0.0
    }

    /// Computes the maximum intrinsic width by delegating to the child.
    ///
    /// Returns the child's maximum intrinsic width, or 0.0 if there is no child.
    ///
    /// **Dart Source:** `shifted_box.dart:44-46`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        return child?.getMaxIntrinsicWidth(height) ?? 0.0
    }

    /// Computes the minimum intrinsic height by delegating to the child.
    ///
    /// Returns the child's minimum intrinsic height, or 0.0 if there is no child.
    ///
    /// **Dart Source:** `shifted_box.dart:49-51`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        return child?.getMinIntrinsicHeight(width) ?? 0.0
    }

    /// Computes the maximum intrinsic height by delegating to the child.
    ///
    /// Returns the child's maximum intrinsic height, or 0.0 if there is no child.
    ///
    /// **Dart Source:** `shifted_box.dart:54-56`
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        return child?.getMaxIntrinsicHeight(width) ?? 0.0
    }

    // MARK: - Baseline

    /// Computes the distance to the actual baseline by delegating to the child,
    /// adjusting for the child's offset.
    ///
    /// If there is a child, queries the child's distance to the actual baseline
    /// and adds the child's `BoxParentData.offset.dy` to account for the child's
    /// position within this render object.
    ///
    /// **Dart Source:** `shifted_box.dart:59-74`
    open override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        let child = self.child
        assert(!debugNeedsLayout)
        if let child = child {
            assert(!child.debugNeedsLayout)
            var result = child.getDistanceToActualBaseline(baseline)
            let childParentData = child.parentData as! BoxParentData
            if result != nil {
                result! += childParentData.offset.dy
            }
            return result
        } else {
            return super.computeDistanceToActualBaseline(baseline)
        }
    }

    // MARK: - Painting

    /// Paints the child at its `BoxParentData` offset.
    ///
    /// If there is no child, this is a no-op.
    ///
    /// **Dart Source:** `shifted_box.dart:77-83`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if let child = child {
            let childParentData = child.parentData as! BoxParentData
            context.paintChild(child, childParentData.offset + offset)
        }
    }

    // MARK: - Hit Testing

    /// Tests whether any children are hit at the given position.
    ///
    /// Uses `BoxHitTestResult.addWithPaintOffset` to account for the child's
    /// offset from `BoxParentData`.
    ///
    /// **Dart Source:** `shifted_box.dart:86-100`
    open override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        if let child = child {
            let childParentData = child.parentData as! BoxParentData
            return result.addWithPaintOffset(
                offset: childParentData.offset,
                position: position,
                hitTest: { (result: BoxHitTestResult, transformed: Offset) -> Bool in
                    return child.hitTest(result, position: transformed)
                }
            )
        }
        return false
    }
}

// MARK: - RenderPadding

/// Insets its child by the given padding.
///
/// When passing layout constraints to its child, padding shrinks the
/// constraints by the given padding, causing the child to layout at a smaller
/// size. Padding then sizes itself to its child's size, inflated by the
/// padding, effectively creating empty space around the child.
///
/// **Dart Source:** `shifted_box.dart:109-271`
public class RenderPadding: RenderShiftedBox {

    // MARK: - Initializer

    /// Creates a render object that insets its child.
    ///
    /// The `padding` argument must have non-negative insets.
    ///
    /// **Dart Source:** `shifted_box.dart:113-120`
    public init(
        padding: any EdgeInsetsGeometry,
        textDirection: TextDirection? = nil,
        child: RenderBox? = nil
    ) {
        assert(padding.isNonNegative)
        _padding = padding
        _textDirection = textDirection
        super.init(child: child)
    }

    // MARK: - Resolved Padding Cache

    /// The cached resolved padding, or nil if not yet resolved.
    ///
    /// **Dart Source:** `shifted_box.dart:122`
    private var _resolvedPaddingCache: EdgeInsets?

    /// The resolved padding value.
    ///
    /// Lazily resolves `padding` using `textDirection` and caches the result.
    ///
    /// **Dart Source:** `shifted_box.dart:123-127`
    private var _resolvedPadding: EdgeInsets {
        let returnValue = _resolvedPaddingCache ?? padding.resolve(textDirection)
        if _resolvedPaddingCache == nil {
            _resolvedPaddingCache = returnValue
        }
        assert(returnValue.isNonNegative)
        return returnValue
    }

    /// Invalidates the resolved padding cache and marks layout as dirty.
    ///
    /// **Dart Source:** `shifted_box.dart:129-132`
    private func _markNeedResolution() {
        _resolvedPaddingCache = nil
        markNeedsLayout()
    }

    // MARK: - Padding Property

    /// The amount to pad the child in each dimension.
    ///
    /// If this is set to an `EdgeInsetsDirectional` object, then `textDirection`
    /// must not be nil.
    ///
    /// **Dart Source:** `shifted_box.dart:138-147`
    public var padding: any EdgeInsetsGeometry {
        get { _padding }
        set {
            assert(newValue.isNonNegative)
            if _padding == newValue {
                return
            }
            _padding = newValue
            _markNeedResolution()
        }
    }
    private var _padding: any EdgeInsetsGeometry

    // MARK: - Text Direction Property

    /// The text direction with which to resolve `padding`.
    ///
    /// This may be changed to nil, but only after the `padding` has been changed
    /// to a value that does not depend on the direction.
    ///
    /// **Dart Source:** `shifted_box.dart:153-161`
    public var textDirection: TextDirection? {
        get { _textDirection }
        set {
            if _textDirection == newValue {
                return
            }
            _textDirection = newValue
            _markNeedResolution()
        }
    }
    private var _textDirection: TextDirection?

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width, adding resolved horizontal padding.
    ///
    /// **Dart Source:** `shifted_box.dart:164-172`
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let padding = _resolvedPadding
        if let child = child {
            // Relies on Double.infinity absorption.
            return child.getMinIntrinsicWidth(max(0.0, height - padding.vertical))
                + padding.horizontal
        }
        return padding.horizontal
    }

    /// Computes the maximum intrinsic width, adding resolved horizontal padding.
    ///
    /// **Dart Source:** `shifted_box.dart:175-183`
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let padding = _resolvedPadding
        if let child = child {
            // Relies on Double.infinity absorption.
            return child.getMaxIntrinsicWidth(max(0.0, height - padding.vertical))
                + padding.horizontal
        }
        return padding.horizontal
    }

    /// Computes the minimum intrinsic height, adding resolved vertical padding.
    ///
    /// **Dart Source:** `shifted_box.dart:186-194`
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        let padding = _resolvedPadding
        if let child = child {
            // Relies on Double.infinity absorption.
            return child.getMinIntrinsicHeight(max(0.0, width - padding.horizontal))
                + padding.vertical
        }
        return padding.vertical
    }

    /// Computes the maximum intrinsic height, adding resolved vertical padding.
    ///
    /// **Dart Source:** `shifted_box.dart:197-205`
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        let padding = _resolvedPadding
        if let child = child {
            // Relies on Double.infinity absorption.
            return child.getMaxIntrinsicHeight(max(0.0, width - padding.horizontal))
                + padding.vertical
        }
        return padding.vertical
    }

    // MARK: - Layout

    /// Computes the dry layout size, accounting for padding.
    ///
    /// **Dart Source:** `shifted_box.dart:209-219`
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        let padding = _resolvedPadding
        if child == nil {
            return constraints.constrain(Size(padding.horizontal, padding.vertical))
        }
        let innerConstraints = constraints.deflate(padding)
        let childSize = child!.getDryLayout(innerConstraints)
        return constraints.constrain(
            Size(padding.horizontal + childSize.width, padding.vertical + childSize.height)
        )
    }

    /// Computes the dry baseline, accounting for padding.
    ///
    /// **Dart Source:** `shifted_box.dart:222-232`
    public override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = self.child else {
            return nil
        }
        let padding = _resolvedPadding
        let innerConstraints = constraints.deflate(padding)
        let result =
            BaselineOffset(child.getDryBaseline(innerConstraints, baseline).offset) + padding.top
        return result.offset
    }

    /// Performs layout, resolving padding, constraining the child with deflated
    /// constraints, and setting the child's offset.
    ///
    /// **Dart Source:** `shifted_box.dart:235-249`
    public override func performLayout() {
        let constraints = self.boxConstraints
        let padding = _resolvedPadding
        if child == nil {
            size = constraints.constrain(Size(padding.horizontal, padding.vertical))
            return
        }
        let innerConstraints = constraints.deflate(padding)
        child!.layout(innerConstraints, parentUsesSize: true)
        let childParentData = child!.parentData as! BoxParentData
        childParentData.offset = Offset(padding.left, padding.top)
        size = constraints.constrain(
            Size(
                padding.horizontal + child!.size.width,
                padding.vertical + child!.size.height
            )
        )
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `shifted_box.dart:266-270`
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<String>(
                "padding",
                String(describing: padding)
            )
        )
        properties.add(
            EnumProperty<TextDirection>(
                "textDirection",
                textDirection,
                defaultValue: nil
            )
        )
    }
}

// MARK: - RenderAligningShiftedBox

/// Abstract class for one-child-layout render boxes that use an
/// `AlignmentGeometry` to align their children.
///
/// **Dart Source:** `shifted_box.dart:275-366`
open class RenderAligningShiftedBox: RenderShiftedBox {

    // MARK: - Initializer

    /// Initializes member variables for subclasses.
    ///
    /// The `textDirection` must be non-nil if the `alignment` is
    /// direction-sensitive.
    ///
    /// **Dart Source:** `shifted_box.dart:280-286`
    public init(
        alignment: any AlignmentGeometry = Alignment.center,
        textDirection: TextDirection? = nil,
        child: RenderBox? = nil
    ) {
        _alignment = alignment
        _textDirection = textDirection
        super.init(child: child)
    }

    // MARK: - Resolved Alignment

    /// The `Alignment` to use for aligning the child.
    ///
    /// This is the `alignment` resolved against `textDirection`. Subclasses should
    /// use `resolvedAlignment` instead of `alignment` directly, for computing the
    /// child's offset.
    ///
    /// The `performLayout` method will be called when the value changes.
    ///
    /// **Dart Source:** `shifted_box.dart:296-297`
    public var resolvedAlignment: Alignment {
        if let resolved = _resolvedAlignment {
            return resolved
        }
        let resolved = alignment.resolve(textDirection)
        _resolvedAlignment = resolved
        return resolved
    }
    private var _resolvedAlignment: Alignment?

    /// Invalidates the resolved alignment cache and marks layout as dirty.
    ///
    /// **Dart Source:** `shifted_box.dart:299-302`
    private func _markNeedResolution() {
        _resolvedAlignment = nil
        markNeedsLayout()
    }

    // MARK: - Alignment Property

    /// How to align the child.
    ///
    /// The x and y values of the alignment control the horizontal and vertical
    /// alignment, respectively. An x value of -1.0 means that the left edge of
    /// the child is aligned with the left edge of the parent whereas an x value
    /// of 1.0 means that the right edge of the child is aligned with the right
    /// edge of the parent. Other values interpolate (and extrapolate) linearly.
    /// For example, a value of 0.0 means that the center of the child is aligned
    /// with the center of the parent.
    ///
    /// If this is set to an `AlignmentDirectional` object, then
    /// `textDirection` must not be nil.
    ///
    /// **Dart Source:** `shifted_box.dart:316-326`
    public var alignment: any AlignmentGeometry {
        get { _alignment }
        set {
            if _alignment == newValue {
                return
            }
            _alignment = newValue
            _markNeedResolution()
        }
    }
    private var _alignment: any AlignmentGeometry

    // MARK: - Text Direction Property

    /// The text direction with which to resolve `alignment`.
    ///
    /// This may be changed to nil, but only after `alignment` has been changed
    /// to a value that does not depend on the direction.
    ///
    /// **Dart Source:** `shifted_box.dart:332-340`
    public var textDirection: TextDirection? {
        get { _textDirection }
        set {
            if _textDirection == newValue {
                return
            }
            _textDirection = newValue
            _markNeedResolution()
        }
    }
    private var _textDirection: TextDirection?

    // MARK: - Align Child

    /// Apply the current `alignment` to the `child`.
    ///
    /// Subclasses should call this method if they have a child, to have
    /// this class perform the actual alignment. If there is no child,
    /// do not call this method.
    ///
    /// This method must be called after the child has been laid out and
    /// this object's own size has been set.
    ///
    /// **Dart Source:** `shifted_box.dart:351-358`
    public func alignChild() {
        assert(child != nil)
        assert(!child!.debugNeedsLayout)
        assert(child!.hasSize)
        assert(hasSize)
        let childParentData = child!.parentData as! BoxParentData
        childParentData.offset = resolvedAlignment.alongOffset(
            Offset(size.width - child!.size.width, size.height - child!.size.height)
        )
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `shifted_box.dart:361-365`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(
            DiagnosticsProperty<String>(
                "alignment",
                String(describing: alignment)
            )
        )
        properties.add(
            EnumProperty<TextDirection>(
                "textDirection",
                textDirection,
                defaultValue: nil
            )
        )
    }
}

// MARK: - RenderPositionedBox

/// Positions its child using an `AlignmentGeometry`.
///
/// For example, to align a box at the bottom right, you would pass this box a
/// tight constraint that is bigger than the child's natural size,
/// with an alignment of `Alignment.bottomRight`.
///
/// By default, sizes to be as big as possible in both axes. If either axis is
/// unconstrained, then in that direction it will be sized to fit the child's
/// dimensions. Using `widthFactor` and `heightFactor` you can force this latter
/// behavior in all cases.
///
/// **Dart Source:** `shifted_box.dart:378-543`
public class RenderPositionedBox: RenderAligningShiftedBox {

    // MARK: - Initializer

    /// Creates a render object that positions its child.
    ///
    /// **Dart Source:** `shifted_box.dart:380-389`
    public init(
        child: RenderBox? = nil,
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        alignment: any AlignmentGeometry = Alignment.center,
        textDirection: TextDirection? = nil
    ) {
        assert(widthFactor == nil || widthFactor! >= 0.0)
        assert(heightFactor == nil || heightFactor! >= 0.0)
        _widthFactor = widthFactor
        _heightFactor = heightFactor
        super.init(alignment: alignment, textDirection: textDirection, child: child)
    }

    // MARK: - Width Factor Property

    /// If non-nil, sets its width to the child's width multiplied by this factor.
    ///
    /// Can be both greater and less than 1.0 but must be positive.
    ///
    /// **Dart Source:** `shifted_box.dart:394-403`
    public var widthFactor: Double? {
        get { _widthFactor }
        set {
            assert(newValue == nil || newValue! >= 0.0)
            if _widthFactor == newValue {
                return
            }
            _widthFactor = newValue
            markNeedsLayout()
        }
    }
    private var _widthFactor: Double?

    // MARK: - Height Factor Property

    /// If non-nil, sets its height to the child's height multiplied by this factor.
    ///
    /// Can be both greater and less than 1.0 but must be positive.
    ///
    /// **Dart Source:** `shifted_box.dart:408-417`
    public var heightFactor: Double? {
        get { _heightFactor }
        set {
            assert(newValue == nil || newValue! >= 0.0)
            if _heightFactor == newValue {
                return
            }
            _heightFactor = newValue
            markNeedsLayout()
        }
    }
    private var _heightFactor: Double?

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width, applying widthFactor.
    ///
    /// **Dart Source:** `shifted_box.dart:420-422`
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        return super.computeMinIntrinsicWidth(height) * (_widthFactor ?? 1)
    }

    /// Computes the maximum intrinsic width, applying widthFactor.
    ///
    /// **Dart Source:** `shifted_box.dart:425-427`
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        return super.computeMaxIntrinsicWidth(height) * (_widthFactor ?? 1)
    }

    /// Computes the minimum intrinsic height, applying heightFactor.
    ///
    /// **Dart Source:** `shifted_box.dart:430-432`
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        return super.computeMinIntrinsicHeight(width) * (_heightFactor ?? 1)
    }

    /// Computes the maximum intrinsic height, applying heightFactor.
    ///
    /// **Dart Source:** `shifted_box.dart:435-437`
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        return super.computeMaxIntrinsicHeight(width) * (_heightFactor ?? 1)
    }

    // MARK: - Layout

    /// Computes the dry layout size.
    ///
    /// If factors are given, uses them; otherwise shrinkWrap or use
    /// `constraints.biggest`.
    ///
    /// **Dart Source:** `shifted_box.dart:441-456`
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        let shrinkWrapWidth =
            _widthFactor != nil || constraints.maxWidth == .infinity
        let shrinkWrapHeight =
            _heightFactor != nil || constraints.maxHeight == .infinity
        if let child = child {
            let childSize = child.getDryLayout(constraints.loosen())
            return constraints.constrain(
                Size(
                    shrinkWrapWidth
                        ? childSize.width * (_widthFactor ?? 1.0)
                        : .infinity,
                    shrinkWrapHeight
                        ? childSize.height * (_heightFactor ?? 1.0)
                        : .infinity
                )
            )
        }
        return constraints.constrain(
            Size(
                shrinkWrapWidth ? 0.0 : .infinity,
                shrinkWrapHeight ? 0.0 : .infinity
            )
        )
    }

    /// Performs layout: layout child, compute own size, then call `alignChild()`.
    ///
    /// **Dart Source:** `shifted_box.dart:459-478`
    public override func performLayout() {
        let constraints = self.boxConstraints
        let shrinkWrapWidth =
            _widthFactor != nil || constraints.maxWidth == .infinity
        let shrinkWrapHeight =
            _heightFactor != nil || constraints.maxHeight == .infinity

        if let child = child {
            child.layout(constraints.loosen(), parentUsesSize: true)
            size = constraints.constrain(
                Size(
                    shrinkWrapWidth
                        ? child.size.width * (_widthFactor ?? 1.0)
                        : .infinity,
                    shrinkWrapHeight
                        ? child.size.height * (_heightFactor ?? 1.0)
                        : .infinity
                )
            )
            alignChild()
        } else {
            size = constraints.constrain(
                Size(
                    shrinkWrapWidth ? 0.0 : .infinity,
                    shrinkWrapHeight ? 0.0 : .infinity
                )
            )
        }
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** `shifted_box.dart:538-542`
    public override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DoubleProperty("widthFactor", _widthFactor, ifNull: "expand"))
        properties.add(DoubleProperty("heightFactor", _heightFactor, ifNull: "expand"))
    }
}

// MARK: - OverflowBoxFit

/// How much space should be occupied by the `OverflowBox` if there is no
/// overflow.
///
/// **Dart Source:** shifted_box.dart:547
public enum OverflowBoxFit: Sendable {
    /// The widget will size itself to be as large as the parent allows.
    case max

    /// The widget will follow the child's size.
    ///
    /// More specifically, the render object will size itself to match the size of
    /// its child within the constraints of its parent, or as small as the
    /// parent allows if no child is set.
    case deferToChild
}

// MARK: - RenderConstrainedOverflowBox

/// A render object that imposes different constraints on its child than it gets
/// from its parent, possibly allowing the child to overflow the parent.
///
/// A render overflow box proxies most functions in the render box protocol to
/// its child, except that when laying out its child, it passes constraints
/// based on the minWidth, maxWidth, minHeight, and maxHeight fields instead of
/// just passing the parent's constraints in. Specifically, it overrides any of
/// the equivalent fields on the constraints given by the parent with the
/// constraints given by these fields for each such field that is not nil. It
/// then sizes itself based on the parent's constraints' maxWidth and maxHeight,
/// ignoring the child's dimensions.
///
/// **Dart Source:** shifted_box.dart:589
public class RenderConstrainedOverflowBox: RenderAligningShiftedBox {

    // MARK: - Initializer

    /// Creates a render object that lets its child overflow itself.
    ///
    /// **Dart Source:** shifted_box.dart:591-604
    public init(
        child: RenderBox? = nil,
        minWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        maxHeight: Double? = nil,
        fit: OverflowBoxFit = .max,
        alignment: any AlignmentGeometry = Alignment.center,
        textDirection: TextDirection? = nil
    ) {
        _minWidth = minWidth
        _maxWidth = maxWidth
        _minHeight = minHeight
        _maxHeight = maxHeight
        _fit = fit
        super.init(alignment: alignment, textDirection: textDirection, child: child)
    }

    // MARK: - Min Width Property

    /// The minimum width constraint to give the child. Set this to nil (the
    /// default) to use the constraint from the parent instead.
    ///
    /// **Dart Source:** shifted_box.dart:608-616
    public var minWidth: Double? {
        get { _minWidth }
        set {
            if _minWidth == newValue {
                return
            }
            _minWidth = newValue
            markNeedsLayout()
        }
    }
    private var _minWidth: Double?

    // MARK: - Max Width Property

    /// The maximum width constraint to give the child. Set this to nil (the
    /// default) to use the constraint from the parent instead.
    ///
    /// **Dart Source:** shifted_box.dart:620-628
    public var maxWidth: Double? {
        get { _maxWidth }
        set {
            if _maxWidth == newValue {
                return
            }
            _maxWidth = newValue
            markNeedsLayout()
        }
    }
    private var _maxWidth: Double?

    // MARK: - Min Height Property

    /// The minimum height constraint to give the child. Set this to nil (the
    /// default) to use the constraint from the parent instead.
    ///
    /// **Dart Source:** shifted_box.dart:632-640
    public var minHeight: Double? {
        get { _minHeight }
        set {
            if _minHeight == newValue {
                return
            }
            _minHeight = newValue
            markNeedsLayout()
        }
    }
    private var _minHeight: Double?

    // MARK: - Max Height Property

    /// The maximum height constraint to give the child. Set this to nil (the
    /// default) to use the constraint from the parent instead.
    ///
    /// **Dart Source:** shifted_box.dart:644-652
    public var maxHeight: Double? {
        get { _maxHeight }
        set {
            if _maxHeight == newValue {
                return
            }
            _maxHeight = newValue
            markNeedsLayout()
        }
    }
    private var _maxHeight: Double?

    // MARK: - Fit Property

    /// The way to size the render object.
    ///
    /// This only affects the scenario when the child does not indeed overflow.
    /// If set to `OverflowBoxFit.deferToChild`, the render object will size
    /// itself to match the size of its child within the constraints of its
    /// parent, or as small as the parent allows if no child is set.
    /// If set to `OverflowBoxFit.max` (the default), the
    /// render object will size itself to be as large as the parent allows.
    ///
    /// **Dart Source:** shifted_box.dart:662-670
    public var fit: OverflowBoxFit {
        get { _fit }
        set {
            if _fit == newValue {
                return
            }
            _fit = newValue
            // In Dart this calls markNeedsLayoutForSizedByParentChange() since
            // sizedByParent depends on fit. Using markNeedsLayout() as the
            // pipeline owner system is not fully implemented.
            markNeedsLayout()
        }
    }
    private var _fit: OverflowBoxFit

    // MARK: - Inner Constraints

    /// Transforms parent constraints by applying optional min/max overrides.
    ///
    /// **Dart Source:** shifted_box.dart:672-679
    private func _getInnerConstraints(_ constraints: BoxConstraints) -> BoxConstraints {
        return BoxConstraints(
            minWidth: _minWidth ?? constraints.minWidth,
            maxWidth: _maxWidth ?? constraints.maxWidth,
            minHeight: _minHeight ?? constraints.minHeight,
            maxHeight: _maxHeight ?? constraints.maxHeight
        )
    }

    // MARK: - Sized By Parent

    /// Whether this render object's size depends only on the constraints.
    ///
    /// When `fit` is `.max`, the box always sizes to constraints.biggest, so it
    /// is sized by the parent. When `fit` is `.deferToChild`, the size depends
    /// on the child, so it is not sized by the parent.
    ///
    /// **Dart Source:** shifted_box.dart:682-687
    public override var sizedByParent: Bool {
        switch fit {
        case .max:
            return true
        case .deferToChild:
            return false
        }
    }

    // MARK: - Layout

    /// Computes the dry layout size.
    ///
    /// When `fit` is `.max`, returns `constraints.biggest`.
    /// When `fit` is `.deferToChild`, returns the child's dry layout size
    /// constrained to the parent constraints, or `constraints.smallest` if
    /// there is no child.
    ///
    /// **Dart Source:** shifted_box.dart:691-696
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        switch fit {
        case .max:
            return constraints.biggest
        case .deferToChild:
            if let child = child {
                return constraints.constrain(child.getDryLayout(constraints))
            }
            return constraints.smallest
        }
    }

    /// Computes the dry baseline offset.
    ///
    /// **Dart Source:** shifted_box.dart:699-712
    public override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = self.child else {
            return nil
        }
        let childConstraints = _getInnerConstraints(constraints)
        let result = child.getDryBaseline(childConstraints, baseline)
        guard let resultValue = result.offset else {
            return nil
        }
        let childSize = child.getDryLayout(childConstraints)
        let mySize = getDryLayout(constraints)
        let alignmentOffset = resolvedAlignment.alongOffset(
            Offset(mySize.width - childSize.width, mySize.height - childSize.height)
        )
        return resultValue + alignmentOffset.dy
    }

    /// Performs layout, applying inner constraints to the child and sizing
    /// according to `fit`.
    ///
    /// **Dart Source:** shifted_box.dart:715-733
    public override func performLayout() {
        let constraints = self.boxConstraints
        if let child = child {
            child.layout(_getInnerConstraints(constraints), parentUsesSize: true)
            switch fit {
            case .max:
                assert(sizedByParent)
            case .deferToChild:
                size = constraints.constrain(child.size)
            }
            alignChild()
        } else {
            switch fit {
            case .max:
                assert(sizedByParent)
            case .deferToChild:
                size = constraints.smallest
            }
        }
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** shifted_box.dart:736-747
    public override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(
            DoubleProperty("minWidth", minWidth, ifNull: "use parent minWidth constraint")
        )
        properties.add(
            DoubleProperty("maxWidth", maxWidth, ifNull: "use parent maxWidth constraint")
        )
        properties.add(
            DoubleProperty("minHeight", minHeight, ifNull: "use parent minHeight constraint")
        )
        properties.add(
            DoubleProperty("maxHeight", maxHeight, ifNull: "use parent maxHeight constraint")
        )
    }
}

// MARK: - RenderSizedOverflowBox

/// A render box of a given size that lets its child overflow.
///
/// The child is positioned according to `alignment`. The box sizes itself to
/// `requestedSize`, constrained by the incoming constraints. It then passes
/// its original constraints through to its child, which it allows to overflow.
///
/// **Dart Source:** shifted_box.dart:997
public class RenderSizedOverflowBox: RenderAligningShiftedBox {

    // MARK: - Initializer

    /// Creates a render box of a given size that lets its child overflow.
    ///
    /// **Dart Source:** shifted_box.dart:1002-1007
    public init(
        child: RenderBox? = nil,
        requestedSize: Size,
        alignment: any AlignmentGeometry = Alignment.center,
        textDirection: TextDirection? = nil
    ) {
        _requestedSize = requestedSize
        super.init(alignment: alignment, textDirection: textDirection, child: child)
    }

    // MARK: - Requested Size Property

    /// The size this render box should attempt to be.
    ///
    /// **Dart Source:** shifted_box.dart:1010-1018
    public var requestedSize: Size {
        get { _requestedSize }
        set {
            if _requestedSize == newValue {
                return
            }
            _requestedSize = newValue
            markNeedsLayout()
        }
    }
    private var _requestedSize: Size

    // MARK: - Intrinsic Dimensions

    /// Returns the requested width as the minimum intrinsic width.
    ///
    /// **Dart Source:** shifted_box.dart:1021-1023
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        return _requestedSize.width
    }

    /// Returns the requested width as the maximum intrinsic width.
    ///
    /// **Dart Source:** shifted_box.dart:1026-1028
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        return _requestedSize.width
    }

    /// Returns the requested height as the minimum intrinsic height.
    ///
    /// **Dart Source:** shifted_box.dart:1031-1033
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        return _requestedSize.height
    }

    /// Returns the requested height as the maximum intrinsic height.
    ///
    /// **Dart Source:** shifted_box.dart:1036-1038
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        return _requestedSize.height
    }

    // MARK: - Baseline

    /// Computes the distance to the actual baseline by delegating to the child.
    ///
    /// **Dart Source:** shifted_box.dart:1041-1044
    public override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        return child?.getDistanceToActualBaseline(baseline)
            ?? super.computeDistanceToActualBaseline(baseline)
    }

    /// Computes the dry baseline offset.
    ///
    /// **Dart Source:** shifted_box.dart:1047-1059
    public override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = self.child else {
            return nil
        }
        let result = child.getDryBaseline(constraints, baseline)
        guard let resultValue = result.offset else {
            return nil
        }
        let childSize = child.getDryLayout(constraints)
        let mySize = getDryLayout(constraints)
        let alignmentOffset = resolvedAlignment.alongOffset(
            Offset(mySize.width - childSize.width, mySize.height - childSize.height)
        )
        return resultValue + alignmentOffset.dy
    }

    // MARK: - Layout

    /// Computes the dry layout size by constraining the requested size.
    ///
    /// **Dart Source:** shifted_box.dart:1063-1065
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return constraints.constrain(_requestedSize)
    }

    /// Performs layout: sizes to constrained requestedSize, then layouts and
    /// aligns child with the original constraints.
    ///
    /// **Dart Source:** shifted_box.dart:1068-1074
    public override func performLayout() {
        let constraints = self.boxConstraints
        size = constraints.constrain(_requestedSize)
        if let child = child {
            child.layout(constraints, parentUsesSize: true)
            alignChild()
        }
    }
}

// MARK: - RenderFractionallySizedOverflowBox

/// Sizes its child to a fraction of the total available space.
///
/// For both its width and height, this render object imposes a tight
/// constraint on its child that is a multiple (typically less than 1.0) of the
/// maximum constraint it received from its parent on that axis. If the factor
/// for a given axis is nil, then the constraints from the parent are just
/// passed through instead.
///
/// It then tries to size itself to the size of its child. Where this is not
/// possible (e.g. if the constraints from the parent are themselves tight), the
/// child is aligned according to `alignment`.
///
/// **Dart Source:** shifted_box.dart:1088
public class RenderFractionallySizedOverflowBox: RenderAligningShiftedBox {

    // MARK: - Initializer

    /// Creates a render box that sizes its child to a fraction of the total
    /// available space.
    ///
    /// If non-nil, the `widthFactor` and `heightFactor` arguments must be
    /// non-negative.
    ///
    /// **Dart Source:** shifted_box.dart:1096-1106
    public init(
        child: RenderBox? = nil,
        widthFactor: Double? = nil,
        heightFactor: Double? = nil,
        alignment: any AlignmentGeometry = Alignment.center,
        textDirection: TextDirection? = nil
    ) {
        assert(widthFactor == nil || widthFactor! >= 0.0)
        assert(heightFactor == nil || heightFactor! >= 0.0)
        _widthFactor = widthFactor
        _heightFactor = heightFactor
        super.init(alignment: alignment, textDirection: textDirection, child: child)
    }

    // MARK: - Width Factor Property

    /// If non-nil, the factor of the incoming width to use.
    ///
    /// If non-nil, the child is given a tight width constraint that is the max
    /// incoming width constraint multiplied by this factor. If nil, the child is
    /// given the incoming width constraints.
    ///
    /// **Dart Source:** shifted_box.dart:1113-1122
    public var widthFactor: Double? {
        get { _widthFactor }
        set {
            assert(newValue == nil || newValue! >= 0.0)
            if _widthFactor == newValue {
                return
            }
            _widthFactor = newValue
            markNeedsLayout()
        }
    }
    private var _widthFactor: Double?

    // MARK: - Height Factor Property

    /// If non-nil, the factor of the incoming height to use.
    ///
    /// If non-nil, the child is given a tight height constraint that is the max
    /// incoming height constraint multiplied by this factor. If nil, the child is
    /// given the incoming height constraints.
    ///
    /// **Dart Source:** shifted_box.dart:1129-1138
    public var heightFactor: Double? {
        get { _heightFactor }
        set {
            assert(newValue == nil || newValue! >= 0.0)
            if _heightFactor == newValue {
                return
            }
            _heightFactor = newValue
            markNeedsLayout()
        }
    }
    private var _heightFactor: Double?

    // MARK: - Inner Constraints

    /// Transforms parent constraints by multiplying factors against max values.
    ///
    /// When a factor is non-nil, both min and max for that axis are set to the
    /// product of the factor and the parent's max constraint. When a factor is
    /// nil, the parent's constraints are passed through for that axis.
    ///
    /// **Dart Source:** shifted_box.dart:1140-1161
    private func _getInnerConstraints(_ constraints: BoxConstraints) -> BoxConstraints {
        var minWidth = constraints.minWidth
        var maxWidth = constraints.maxWidth
        if let wf = _widthFactor {
            let width = maxWidth * wf
            minWidth = width
            maxWidth = width
        }
        var minHeight = constraints.minHeight
        var maxHeight = constraints.maxHeight
        if let hf = _heightFactor {
            let height = maxHeight * hf
            minHeight = height
            maxHeight = height
        }
        return BoxConstraints(
            minWidth: minWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
    }

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width, adjusting for height and width
    /// factors.
    ///
    /// **Dart Source:** shifted_box.dart:1164-1174
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let result: Double
        if let child = child {
            // Relies on Double.infinity absorption
            result = child.getMinIntrinsicWidth(height * (_heightFactor ?? 1.0))
        } else {
            result = super.computeMinIntrinsicWidth(height)
        }
        assert(result.isFinite)
        return result / (_widthFactor ?? 1.0)
    }

    /// Computes the maximum intrinsic width, adjusting for height and width
    /// factors.
    ///
    /// **Dart Source:** shifted_box.dart:1177-1187
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let result: Double
        if let child = child {
            // Relies on Double.infinity absorption
            result = child.getMaxIntrinsicWidth(height * (_heightFactor ?? 1.0))
        } else {
            result = super.computeMaxIntrinsicWidth(height)
        }
        assert(result.isFinite)
        return result / (_widthFactor ?? 1.0)
    }

    /// Computes the minimum intrinsic height, adjusting for width and height
    /// factors.
    ///
    /// **Dart Source:** shifted_box.dart:1190-1200
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        let result: Double
        if let child = child {
            // Relies on Double.infinity absorption
            result = child.getMinIntrinsicHeight(width * (_widthFactor ?? 1.0))
        } else {
            result = super.computeMinIntrinsicHeight(width)
        }
        assert(result.isFinite)
        return result / (_heightFactor ?? 1.0)
    }

    /// Computes the maximum intrinsic height, adjusting for width and height
    /// factors.
    ///
    /// **Dart Source:** shifted_box.dart:1203-1213
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        let result: Double
        if let child = child {
            // Relies on Double.infinity absorption
            result = child.getMaxIntrinsicHeight(width * (_widthFactor ?? 1.0))
        } else {
            result = super.computeMaxIntrinsicHeight(width)
        }
        assert(result.isFinite)
        return result / (_heightFactor ?? 1.0)
    }

    // MARK: - Layout

    /// Computes the dry layout size.
    ///
    /// If child exists, sizes the child with inner constraints and constrains the
    /// result. Otherwise, constrains a zero-size box with the inner constraints.
    ///
    /// **Dart Source:** shifted_box.dart:1217-1223
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        if let child = child {
            let childSize = child.getDryLayout(_getInnerConstraints(constraints))
            return constraints.constrain(childSize)
        }
        return constraints.constrain(
            _getInnerConstraints(constraints).constrain(Size.zero)
        )
    }

    /// Computes the dry baseline offset.
    ///
    /// **Dart Source:** shifted_box.dart:1226-1239
    public override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = self.child else {
            return nil
        }
        let childConstraints = _getInnerConstraints(constraints)
        let result = child.getDryBaseline(childConstraints, baseline)
        guard let resultValue = result.offset else {
            return nil
        }
        let childSize = child.getDryLayout(childConstraints)
        let mySize = getDryLayout(constraints)
        let alignmentOffset = resolvedAlignment.alongOffset(
            Offset(mySize.width - childSize.width, mySize.height - childSize.height)
        )
        return resultValue + alignmentOffset.dy
    }

    /// Performs layout: applies inner constraints to the child, sizes self, then
    /// aligns the child.
    ///
    /// **Dart Source:** shifted_box.dart:1242-1250
    public override func performLayout() {
        let constraints = self.boxConstraints
        if let child = child {
            child.layout(_getInnerConstraints(constraints), parentUsesSize: true)
            size = constraints.constrain(child.size)
            alignChild()
        } else {
            size = constraints.constrain(
                _getInnerConstraints(constraints).constrain(Size.zero)
            )
        }
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** shifted_box.dart:1253-1257
    public override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(
            DoubleProperty("widthFactor", _widthFactor, ifNull: "pass-through")
        )
        properties.add(
            DoubleProperty("heightFactor", _heightFactor, ifNull: "pass-through")
        )
    }
}

// MARK: - RenderConstraintsTransformBox

/// A render object that takes an arbitrary `BoxConstraintsTransform` function
/// and applies it to the constraints passed to the child.
///
/// This can cause overflow if the transformed constraints result in a child
/// larger than the parent. The child is positioned using `alignment`.
///
/// **Dart Source:** `shifted_box.dart:789-981`
public class RenderConstraintsTransformBox: RenderAligningShiftedBox, DebugOverflowIndicator {

    // MARK: - Initializer

    /// Creates a render box that sizes itself to the child and modifies the
    /// constraints before passing it down to that child.
    ///
    /// **Dart Source:** `shifted_box.dart:793-800`
    public init(
        alignment: any AlignmentGeometry = Alignment.center,
        textDirection: TextDirection? = nil,
        constraintsTransform: @escaping BoxConstraintsTransform,
        child: RenderBox? = nil,
        clipBehavior: Clip = .none
    ) {
        _constraintsTransform = constraintsTransform
        _clipBehavior = clipBehavior
        super.init(alignment: alignment, textDirection: textDirection, child: child)
    }

    // MARK: - DebugOverflowIndicator Conformance

    /// Whether a report should be generated the next time overflow is detected.
    ///
    /// **Dart Source:** `debug_overflow_indicator.dart:127`
    public var _overflowReportNeeded: Bool = true

    /// Cached text painters for the overflow labels, one per side.
    ///
    /// **Dart Source:** `debug_overflow_indicator.dart:111-115`
    public var _indicatorLabel: [TextPainter] = createOverflowIndicatorLabels()

    // MARK: - Constraints Transform Property

    /// The function used to transform the incoming constraints before passing
    /// them to the child.
    ///
    /// **Dart Source:** `shifted_box.dart:803-817`
    public var constraintsTransform: BoxConstraintsTransform {
        get { _constraintsTransform }
        set {
            if _constraintsTransform as AnyObject === newValue as AnyObject {
                return
            }
            _constraintsTransform = newValue
            // The RenderObject only needs layout if the new transform maps the
            // current `constraints` to a different value, or the render object
            // has never been laid out before.
            let needsLayout =
                _childConstraintsCache == nil
                || _childConstraintsCache != newValue(boxConstraints)
            if needsLayout {
                markNeedsLayout()
            }
        }
    }
    private var _constraintsTransform: BoxConstraintsTransform

    // MARK: - Clip Behavior Property

    /// How to clip overflow.
    ///
    /// Defaults to `Clip.none`.
    ///
    /// **Dart Source:** `shifted_box.dart:824-832`
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if newValue != _clipBehavior {
                _clipBehavior = newValue
                markNeedsPaint()
                // TODO: Call markNeedsSemanticsUpdate() once semantics is available.
            }
        }
    }
    private var _clipBehavior: Clip

    // MARK: - Child Constraints

    /// Cached child constraints from the most recent layout pass.
    ///
    /// **Dart Source:** `shifted_box.dart:889`
    private var _childConstraintsCache: BoxConstraints?

    /// Computes the child constraints by applying `constraintsTransform` to the
    /// parent constraints.
    ///
    /// **Dart Source:** `shifted_box.dart:889` (derived from performLayout usage)
    private var _childConstraints: BoxConstraints {
        let result = constraintsTransform(boxConstraints)
        assert(result.isNormalized, "\(result) is not normalized")
        return result
    }

    // MARK: - Intrinsic Dimensions

    /// Computes the minimum intrinsic width by transforming constraints and
    /// delegating to the child.
    ///
    /// **Dart Source:** `shifted_box.dart:849-853`
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        return super.computeMinIntrinsicWidth(
            constraintsTransform(BoxConstraints(maxHeight: height)).maxHeight
        )
    }

    /// Computes the maximum intrinsic width by transforming constraints and
    /// delegating to the child.
    ///
    /// **Dart Source:** `shifted_box.dart:856-860`
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        return super.computeMaxIntrinsicWidth(
            constraintsTransform(BoxConstraints(maxHeight: height)).maxHeight
        )
    }

    /// Computes the minimum intrinsic height by transforming constraints and
    /// delegating to the child.
    ///
    /// **Dart Source:** `shifted_box.dart:835-839`
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        return super.computeMinIntrinsicHeight(
            constraintsTransform(BoxConstraints(maxWidth: width)).maxWidth
        )
    }

    /// Computes the maximum intrinsic height by transforming constraints and
    /// delegating to the child.
    ///
    /// **Dart Source:** `shifted_box.dart:842-846`
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        return super.computeMaxIntrinsicHeight(
            constraintsTransform(BoxConstraints(maxWidth: width)).maxWidth
        )
    }

    // MARK: - Layout

    /// Computes the dry layout size by transforming constraints and delegating
    /// to the child.
    ///
    /// **Dart Source:** `shifted_box.dart:864-867`
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        let childSize = child?.getDryLayout(constraintsTransform(constraints))
        return childSize == nil
            ? constraints.smallest
            : constraints.constrain(childSize!)
    }

    /// Computes the dry baseline offset.
    ///
    /// **Dart Source:** `shifted_box.dart:870-883`
    public override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = self.child else {
            return nil
        }
        let childConstraints = constraintsTransform(constraints)
        let result = child.getDryBaseline(childConstraints, baseline)
        guard let resultValue = result.offset else {
            return nil
        }
        let childSize = child.getDryLayout(childConstraints)
        let mySize = getDryLayout(constraints)
        return resultValue + resolvedAlignment.alongOffset(mySize - childSize).dy
    }

    // MARK: - Overflow Tracking

    /// The container rect for overflow checking.
    ///
    /// **Dart Source:** `shifted_box.dart:885`
    private var _overflowContainerRect: Rect = Rect.zero

    /// The child rect for overflow checking.
    ///
    /// **Dart Source:** `shifted_box.dart:886`
    private var _overflowChildRect: Rect = Rect.zero

    /// Whether the child is currently overflowing the container.
    ///
    /// **Dart Source:** `shifted_box.dart:887`
    private var _isOverflowing: Bool = false

    /// Performs layout: applies the transformed constraints to the child, sizes
    /// self, positions child using alignment, and checks for overflow.
    ///
    /// **Dart Source:** `shifted_box.dart:892-911`
    public override func performLayout() {
        let constraints = self.boxConstraints
        let child = self.child
        if let child = child {
            let childConstraints = constraintsTransform(constraints)
            assert(childConstraints.isNormalized, "\(childConstraints) is not normalized")
            _childConstraintsCache = childConstraints
            child.layout(childConstraints, parentUsesSize: true)
            size = constraints.constrain(child.size)
            alignChild()
            let childParentData = child.parentData as! BoxParentData
            _overflowContainerRect = Offset.zero & size
            _overflowChildRect = childParentData.offset & child.size
        } else {
            size = constraints.smallest
            _overflowContainerRect = Rect.zero
            _overflowChildRect = Rect.zero
        }
        _isOverflowing = RelativeRect.fromRect(
            _overflowContainerRect,
            _overflowChildRect
        ).hasInsets
    }

    // MARK: - Painting

    /// Paints the child, clipping if overflow exists and clip behavior is set.
    ///
    /// Also paints overflow indicators in debug mode when `clipBehavior` is `.none`.
    ///
    /// **Dart Source:** `shifted_box.dart:914-948`
    public override func paint(_ context: PaintingContext, _ offset: Offset) {
        if child == nil {
            return
        }

        if !_isOverflowing {
            super.paint(context, offset)
            return
        }

        // We have overflow and the clipBehavior isn't none. Clip it.
        if clipBehavior != .none {
            _clipRectLayer.layer = context.pushClipRect(
                needsCompositing,
                offset,
                Offset.zero & size,
                { (context: PaintingContext, offset: Offset) in
                    super.paint(context, offset)
                },
                clipBehavior: clipBehavior,
                oldLayer: _clipRectLayer.layer
            )
        } else {
            super.paint(context, offset)
        }

        // Display the overflow indicator if clipBehavior is Clip.none.
        assert({
            if size.isEmpty {
                return true
            }
            switch clipBehavior {
            case .none:
                paintOverflowIndicator(
                    context,
                    offset,
                    _overflowContainerRect,
                    _overflowChildRect
                )
            case .hardEdge, .antiAlias, .antiAliasWithSaveLayer:
                break
            }
            return true
        }())
    }

    /// Layer handle for clipping when overflow occurs.
    ///
    /// **Dart Source:** `shifted_box.dart:951`
    private let _clipRectLayer = LayerHandle<ClipRectLayer>()

    // MARK: - Dispose

    /// Releases the clip rect layer.
    ///
    /// **Dart Source:** `shifted_box.dart:954-957`
    public override func dispose() {
        _clipRectLayer.layer = nil
        super.dispose()
    }

    // MARK: - Hit Testing

    /// Tests whether any children are hit at the given position.
    ///
    /// If the child is overflowing and a clip is active, positions outside the
    /// clip rect return false.
    ///
    /// **Dart Source:** (derived from overflow hit testing pattern)
    public override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        if _isOverflowing && clipBehavior != .none {
            let clipRect = Offset.zero & size
            if !clipRect.contains(position) {
                return false
            }
        }
        return super.hitTestChildren(result, position: position)
    }

    // MARK: - Reassemble

    /// Resets the overflow report flag so that overflow is reported again after
    /// a hot reload.
    ///
    /// **Dart Source:** (derived from DebugOverflowIndicatorMixin pattern)
    public func reassemble() {
        _overflowReportNeeded = true
        // TODO: Call super.reassemble() once reassemble is available on RenderObject.
    }
}

// MARK: - SingleChildLayoutDelegate

/// A delegate for use with `RenderCustomSingleChildLayoutBox`.
///
/// The delegate can determine the layout constraints for the child and can
/// decide where to position the child. The delegate can also determine the size
/// of the parent, but the size of the parent cannot depend on the size of the
/// child.
///
/// **Dart Source:** shifted_box.dart:1286-1338
open class SingleChildLayoutDelegate {

    /// The listenable that, when notified, triggers a relayout.
    ///
    /// **Dart Source:** shifted_box.dart:1290-1292
    internal let _relayout: (any Listenable)?

    /// Creates a layout delegate.
    ///
    /// The layout will update whenever `relayout` notifies its listeners.
    ///
    /// **Dart Source:** shifted_box.dart:1290
    public init(relayout: (any Listenable)? = nil) {
        self._relayout = relayout
    }

    /// The size of this object given the incoming constraints.
    ///
    /// Defaults to the biggest size that satisfies the given constraints.
    ///
    /// **Dart Source:** shifted_box.dart:1297
    open func getSize(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }

    /// The constraints for the child given the incoming constraints.
    ///
    /// During layout, the child is given the layout constraints returned by this
    /// function. The child is required to pick a size for itself that satisfies
    /// these constraints.
    ///
    /// Defaults to the given constraints.
    ///
    /// **Dart Source:** shifted_box.dart:1306
    open func getConstraintsForChild(_ constraints: BoxConstraints) -> BoxConstraints {
        return constraints
    }

    /// The position where the child should be placed.
    ///
    /// The `size` argument is the size of the parent, which might be different
    /// from the value returned by `getSize` if that size doesn't satisfy the
    /// constraints passed to `getSize`. The `childSize` argument is the size of
    /// the child, which will satisfy the constraints returned by
    /// `getConstraintsForChild`.
    ///
    /// Defaults to positioning the child in the upper left corner of the parent.
    ///
    /// **Dart Source:** shifted_box.dart:1317
    open func getPositionForChild(_ size: Size, _ childSize: Size) -> Offset {
        return .zero
    }

    /// Called whenever a new instance of the custom layout delegate class is
    /// provided to the `RenderCustomSingleChildLayoutBox` object, or any time
    /// that a new `CustomSingleChildLayout` object is created with a new instance
    /// of the custom layout delegate class.
    ///
    /// If the new instance represents different information than the old
    /// instance, then the method should return true, otherwise it should return
    /// false.
    ///
    /// **Dart Source:** shifted_box.dart:1338
    open func shouldRelayout(_ oldDelegate: SingleChildLayoutDelegate) -> Bool {
        fatalError("Subclasses must override shouldRelayout")
    }
}

// MARK: - RenderCustomSingleChildLayoutBox

/// Defers the layout of its single child to a delegate.
///
/// The delegate can determine the layout constraints for the child and can
/// decide where to position the child. The delegate can also determine the size
/// of the parent, but the size of the parent cannot depend on the size of the
/// child.
///
/// **Dart Source:** shifted_box.dart:1347-1472
public class RenderCustomSingleChildLayoutBox: RenderShiftedBox {

    // MARK: - Initializer

    /// Creates a render box that defers its layout to a delegate.
    ///
    /// **Dart Source:** shifted_box.dart:1351-1353
    public init(child: RenderBox? = nil, delegate: SingleChildLayoutDelegate) {
        _delegate = delegate
        super.init(child: child)
    }

    // MARK: - Callback

    /// Stored closure for listener add/remove identity.
    ///
    /// We store this so that the same closure identity is used when adding
    /// and removing the listener.
    private lazy var _markNeedsLayoutCallback: VoidCallback = { [weak self] in
        self?.markNeedsLayout()
    }

    // MARK: - Delegate Property

    /// A delegate that controls this object's layout.
    ///
    /// **Dart Source:** shifted_box.dart:1355-1372
    public var delegate: SingleChildLayoutDelegate {
        get { _delegate }
        set {
            if _delegate === newValue {
                return
            }
            let oldDelegate = _delegate
            if type(of: newValue) != type(of: oldDelegate)
                || newValue.shouldRelayout(oldDelegate)
            {
                markNeedsLayout()
            }
            _delegate = newValue
            if attached {
                oldDelegate._relayout?.removeListeners(owner: self)
                newValue._relayout?.addListener(_markNeedsLayoutCallback, owner: self)
            }
        }
    }
    private var _delegate: SingleChildLayoutDelegate

    // MARK: - Attach / Detach

    /// Attaches this render object to a pipeline owner.
    ///
    /// Adds a listener to the delegate's `_relayout` listenable so that layout
    /// is marked dirty whenever the listenable notifies.
    ///
    /// **Dart Source:** shifted_box.dart:1374-1378
    public override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _delegate._relayout?.addListener(_markNeedsLayoutCallback, owner: self)
    }

    /// Detaches this render object from its pipeline owner.
    ///
    /// Removes the listener from the delegate's `_relayout` listenable.
    ///
    /// **Dart Source:** shifted_box.dart:1380-1384
    public override func detach() {
        _delegate._relayout?.removeListeners(owner: self)
        super.detach()
    }

    // MARK: - Size Helper

    /// Returns the size constrained by the delegate's `getSize`.
    ///
    /// **Dart Source:** shifted_box.dart:1386-1388
    private func _getSize(_ constraints: BoxConstraints) -> Size {
        return constraints.constrain(_delegate.getSize(constraints))
    }

    // MARK: - Intrinsic Dimensions

    // TODO(ianh): It's a bit dubious to be using the getSize function from the
    // delegate to figure out the intrinsic dimensions. We really should either
    // not support intrinsics, or we should expose intrinsic delegate callbacks
    // and throw if they're not implemented.

    /// Computes the minimum intrinsic width for the given height.
    ///
    /// **Dart Source:** shifted_box.dart:1395-1401
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let width = _getSize(.tightForFinite(height: height)).width
        if width.isFinite {
            return width
        }
        return 0.0
    }

    /// Computes the maximum intrinsic width for the given height.
    ///
    /// **Dart Source:** shifted_box.dart:1404-1410
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let width = _getSize(.tightForFinite(height: height)).width
        if width.isFinite {
            return width
        }
        return 0.0
    }

    /// Computes the minimum intrinsic height for the given width.
    ///
    /// **Dart Source:** shifted_box.dart:1413-1419
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        let height = _getSize(.tightForFinite(width: width)).height
        if height.isFinite {
            return height
        }
        return 0.0
    }

    /// Computes the maximum intrinsic height for the given width.
    ///
    /// **Dart Source:** shifted_box.dart:1422-1428
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        let height = _getSize(.tightForFinite(width: width)).height
        if height.isFinite {
            return height
        }
        return 0.0
    }

    // MARK: - Layout

    /// Computes the dry layout size by delegating to the delegate's `getSize`.
    ///
    /// **Dart Source:** shifted_box.dart:1432-1434
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _getSize(constraints)
    }

    /// Computes the dry baseline by delegating to the delegate for constraints
    /// and position.
    ///
    /// **Dart Source:** shifted_box.dart:1437-1456
    public override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = self.child else {
            return nil
        }
        let childConstraints = delegate.getConstraintsForChild(constraints)
        let result = child.getDryBaseline(childConstraints, baseline)
        guard let resultValue = result.offset else {
            return nil
        }
        let childSize: Size
        if childConstraints.isTight {
            childSize = childConstraints.smallest
        } else {
            childSize = child.getDryLayout(childConstraints)
        }
        return resultValue
            + delegate.getPositionForChild(_getSize(constraints), childSize).dy
    }

    /// Performs layout by delegating to the delegate for constraints and
    /// positioning.
    ///
    /// **Dart Source:** shifted_box.dart:1458-1472
    public override func performLayout() {
        let constraints = self.boxConstraints
        size = _getSize(constraints)
        if let child = child {
            let childConstraints = delegate.getConstraintsForChild(constraints)
            assert(childConstraints.debugAssertIsValid(isAppliedConstraint: true))
            child.layout(childConstraints, parentUsesSize: !childConstraints.isTight)
            let childParentData = child.parentData as! BoxParentData
            childParentData.offset = delegate.getPositionForChild(
                size,
                childConstraints.isTight ? childConstraints.smallest : child.size
            )
        }
    }
}

// MARK: - RenderBaseline

/// Shifts the child down such that the child's baseline (or the bottom of the
/// child, if the child has no baseline) is `baseline` logical pixels below the
/// top of this box, then sizes this box to contain the child.
///
/// If `baseline` is less than the distance from the top of the child to the
/// baseline of the child, then the child will overflow the top of the box.
/// This is typically not desirable, in particular, that part of the child will
/// not be found when doing hit tests, so the user cannot interact with that
/// part of the child.
///
/// This box will be sized so that its bottom is coincident with the bottom of
/// the child. This means if this box shifts the child down, there will be space
/// between the top of this box and the top of the child, but there is never
/// space between the bottom of the child and the bottom of the box.
///
/// **Dart Source:** shifted_box.dart:1490-1575
public class RenderBaseline: RenderShiftedBox {

    // MARK: - Initializer

    /// Creates a `RenderBaseline` object.
    ///
    /// **Dart Source:** shifted_box.dart:1492-1495
    public init(
        child: RenderBox? = nil,
        baseline: Double,
        baselineType: TextBaseline
    ) {
        _baseline = baseline
        _baselineType = baselineType
        super.init(child: child)
    }

    // MARK: - Baseline Property

    /// The number of logical pixels from the top of this box at which to
    /// position the child's baseline.
    ///
    /// **Dart Source:** shifted_box.dart:1499-1507
    public var baseline: Double {
        get { _baseline }
        set {
            if _baseline == newValue {
                return
            }
            _baseline = newValue
            markNeedsLayout()
        }
    }
    private var _baseline: Double

    // MARK: - Baseline Type Property

    /// The type of baseline to use for positioning the child.
    ///
    /// **Dart Source:** shifted_box.dart:1510-1518
    public var baselineType: TextBaseline {
        get { _baselineType }
        set {
            if _baselineType == newValue {
                return
            }
            _baselineType = newValue
            markNeedsLayout()
        }
    }
    private var _baselineType: TextBaseline

    // MARK: - Size Computation Helper

    /// Computes the child size and the vertical offset (`top`) needed to place
    /// the child so that its baseline aligns with the desired `baseline` value.
    ///
    /// **Dart Source:** shifted_box.dart:1520-1535
    private func _computeSizes(
        _ constraints: BoxConstraints,
        _ layoutChild: ChildLayouter,
        _ getBaseline: ChildBaselineGetter
    ) -> (size: Size, top: Double) {
        guard let child = self.child else {
            return (size: constraints.smallest, top: 0)
        }
        let childConstraints = constraints.loosen()
        let childSize = layoutChild(child, childConstraints)
        let childBaseline = getBaseline(child, childConstraints, baselineType) ?? childSize.height
        let top = baseline - childBaseline
        return (
            size: constraints.constrain(Size(childSize.width, top + childSize.height)),
            top: top
        )
    }

    // MARK: - Layout

    /// Computes the dry layout size.
    ///
    /// **Dart Source:** shifted_box.dart:1539-1545
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _computeSizes(
            constraints,
            ChildLayoutHelper.dryLayoutChild,
            ChildLayoutHelper.getDryBaseline
        ).size
    }

    /// Computes the dry baseline.
    ///
    /// For the matching baseline type, returns the child's baseline adjusted by
    /// the difference between this object's `baseline` and the child's baseline
    /// of the configured `baselineType`. Returns nil if the child has no baseline.
    ///
    /// **Dart Source:** shifted_box.dart:1548-1556
    public override func computeDryBaseline(
        _ constraints: BoxConstraints,
        _ baseline: TextBaseline
    ) -> Double? {
        guard let child = self.child else {
            return nil
        }
        let loosened = constraints.loosen()
        let result1 = child.getDryBaseline(loosened, baseline)
        let result2 = child.getDryBaseline(loosened, baselineType)
        guard let result1Value = result1.offset, let result2Value = result2.offset else {
            return nil
        }
        return self.baseline + result1Value - result2Value
    }

    /// Performs layout: lays out the child, queries the actual baseline, and
    /// positions the child so that its baseline is at the desired distance from
    /// the top.
    ///
    /// **Dart Source:** shifted_box.dart:1558-1567
    public override func performLayout() {
        let constraints = self.boxConstraints
        let result = _computeSizes(
            constraints,
            ChildLayoutHelper.layoutChild,
            ChildLayoutHelper.getBaseline
        )
        self.size = result.size
        (child?.parentData as? BoxParentData)?.offset = Offset(0.0, result.top)
    }

    // MARK: - Debug

    /// Fills the given properties builder with debugging information.
    ///
    /// **Dart Source:** shifted_box.dart:1570-1574
    public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(DoubleProperty("baseline", baseline))
        properties.add(
            EnumProperty<TextBaseline>("baselineType", baselineType)
        )
    }
}

// MARK: - SingleChildRenderObjectHost Conformance

extension RenderShiftedBox: SingleChildRenderObjectHost {}
