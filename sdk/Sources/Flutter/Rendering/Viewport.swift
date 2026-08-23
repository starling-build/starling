// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Viewport layout model types.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/viewport.dart`

import FlutterSwiftBridge

// MARK: - CacheExtentStyle

/// The unit of measurement for a viewport's `cacheExtent`.
///
/// **Dart Source:** `viewport.dart:27-33`
public enum CacheExtentStyle: Sendable {
    /// Treat the `cacheExtent` as logical pixels.
    ///
    /// **Dart Source:** `viewport.dart:29`
    case pixel

    /// Treat the `cacheExtent` as a multiplier of the main axis extent.
    ///
    /// **Dart Source:** `viewport.dart:32`
    case viewport
}

// MARK: - SliverPaintOrder

/// Specifies an order in which to paint the slivers of a viewport.
///
/// The slivers of a `ScrollView` are the list returned by
/// `ScrollView.buildSlivers`. Whichever order the slivers are painted in,
/// they will be hit-tested in the opposite order.
///
/// **Dart Source:** `viewport.dart:36-69`
public enum SliverPaintOrder: Sendable {
    /// The first sliver paints on top, and the last sliver on bottom.
    ///
    /// This is the default order.
    ///
    /// **Dart Source:** `viewport.dart:60`
    case firstIsTop

    /// The last sliver paints on top, and the first sliver on bottom.
    ///
    /// **Dart Source:** `viewport.dart:68`
    case lastIsTop
}

// MARK: - RevealedOffset

/// Return value for `RenderAbstractViewport.getOffsetToReveal`.
///
/// It indicates the `offset` required to reveal an element in a viewport and
/// the `rect` position said element would have in the viewport at that
/// `offset`.
///
/// **Dart Source:** `viewport.dart:183-280`
public struct RevealedOffset: CustomStringConvertible {

    /// Instantiates a return value for `RenderAbstractViewport.getOffsetToReveal`.
    ///
    /// **Dart Source:** `viewport.dart:190`
    public init(offset: Double, rect: Rect) {
        self.offset = offset
        self.rect = rect
    }

    /// Offset for the viewport to reveal a specific element in the viewport.
    ///
    /// **Dart Source:** `viewport.dart:198`
    public let offset: Double

    /// The `Rect` in the outer coordinate system of the viewport at which the
    /// to-be-revealed element would be located if the viewport's offset is set
    /// to `offset`.
    ///
    /// **Dart Source:** `viewport.dart:224`
    public let rect: Rect

    /// Determines which provided leading or trailing edge of the viewport, as
    /// `RevealedOffset`s, will be used for `RenderViewportBase.showInViewport`
    /// accounting for the size and already visible portion of the `RenderObject`
    /// that is being revealed.
    ///
    /// If the target `RenderObject` is already fully visible, this will return
    /// nil.
    ///
    /// **Dart Source:** `viewport.dart:236-274`
    public static func clampOffset(
        leadingEdgeOffset: RevealedOffset,
        trailingEdgeOffset: RevealedOffset,
        currentOffset: Double
    ) -> RevealedOffset? {
        let inverted = leadingEdgeOffset.offset < trailingEdgeOffset.offset
        let smaller: RevealedOffset
        let larger: RevealedOffset
        if inverted {
            smaller = leadingEdgeOffset
            larger = trailingEdgeOffset
        } else {
            smaller = trailingEdgeOffset
            larger = leadingEdgeOffset
        }
        if currentOffset > larger.offset {
            return larger
        } else if currentOffset < smaller.offset {
            return smaller
        } else {
            return nil
        }
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `viewport.dart:277-279`
    public var description: String {
        "RevealedOffset(offset: \(offset), rect: \(rect))"
    }
}

// MARK: - RenderAbstractViewport

/// An interface for render objects that are bigger on the inside.
///
/// Some render objects, such as `RenderViewport`, present a portion of their
/// content, which can be controlled by a `ViewportOffset`. This interface lets
/// the framework recognize such render objects and interact with them without
/// having specific knowledge of all the various types of viewports.
///
/// **Dart Source:** `viewport.dart:77-181`
///
/// DIFFERENCE FROM DART: Dart uses `abstract interface class`; Swift uses a
/// protocol since Swift does not have abstract interface classes.
/// REASON: Swift protocols serve the same purpose as Dart interface classes.
public protocol RenderAbstractViewport: AnyObject {

    /// Returns the offset that would be needed to reveal the `target`
    /// `RenderObject`.
    ///
    /// The optional `rect` parameter describes which area of that `target` object
    /// should be revealed in the viewport. If `rect` is nil, the entire
    /// `target` `RenderObject` (as defined by its `paintBounds`) will be revealed.
    ///
    /// The `alignment` argument describes where the target should be positioned
    /// after applying the returned offset. If `alignment` is 0.0, the child must
    /// be positioned as close to the leading edge of the viewport as possible. If
    /// `alignment` is 1.0, the child must be positioned as close to the trailing
    /// edge of the viewport as possible.
    ///
    /// **Dart Source:** `viewport.dart:127-171`
    func getOffsetToReveal(
        _ target: RenderObject,
        _ alignment: Double,
        rect: Rect?,
        axis: Axis?
    ) -> RevealedOffset
}

/// Extension to provide static methods for `RenderAbstractViewport`.
///
/// **Dart Source:** `viewport.dart:77-181`
public enum RenderAbstractViewportUtils {

    /// The default value for the cache extent of the viewport.
    ///
    /// This default assumes `CacheExtentStyle.pixel`.
    ///
    /// **Dart Source:** `viewport.dart:180`
    public static let defaultCacheExtent: Double = 250.0

    /// Returns the `RenderAbstractViewport` that most tightly encloses the given
    /// render object.
    ///
    /// If the object does not have a `RenderAbstractViewport` as an ancestor,
    /// this function returns nil.
    ///
    /// **Dart Source:** `viewport.dart:88-96`
    public static func maybeOf(_ object: RenderObject?) -> (any RenderAbstractViewport)? {
        var current: RenderObject? = object
        while current != nil {
            if let viewport = current as? (any RenderAbstractViewport) {
                return viewport
            }
            current = current?.parent
        }
        return nil
    }

    /// Returns the `RenderAbstractViewport` that most tightly encloses the given
    /// render object.
    ///
    /// If the object does not have a `RenderAbstractViewport` as an ancestor,
    /// this function will assert in debug mode, and throw an exception in release
    /// mode.
    ///
    /// **Dart Source:** `viewport.dart:109-125`
    public static func of(_ object: RenderObject?) -> any RenderAbstractViewport {
        let viewport = maybeOf(object)
        assert({
            if viewport == nil {
                fatalError(
                    "RenderAbstractViewport.of() was called with a render object that was "
                    + "not a descendant of a RenderAbstractViewport.\n"
                    + "No RenderAbstractViewport render object ancestor could be found starting "
                    + "from the object that was passed to RenderAbstractViewport.of().\n"
                    + "The render object where the viewport search started was:\n"
                    + "  \(String(describing: object))"
                )
            }
            return true
        }())
        return viewport!
    }
}

// MARK: - RenderViewportBase

/// A base class for render objects that are bigger on the inside.
///
/// This render object provides the shared code for render objects that host
/// `RenderSliver` render objects inside a `RenderBox`. The viewport establishes
/// an `axisDirection`, which orients the sliver's coordinate system, which is
/// based on scroll offsets rather than Cartesian coordinates.
///
/// The viewport also listens to an `offset`, which determines the
/// `SliverConstraints.scrollOffset` input to the sliver layout protocol.
///
/// Subclasses typically override `performLayout` and call
/// `layoutChildSequence`, perhaps multiple times.
///
/// **Dart Source:** `viewport.dart:282-1372`
///
/// DIFFERENCE FROM DART: Dart uses a generic `abstract class RenderViewportBase<ParentDataClass>`;
/// Swift uses a non-generic open class since Swift does not support generic
/// class inheritance patterns the same way.
/// REASON: Swift cannot mix in generic traits. Subclasses specify their
/// parent data type directly.
open class RenderViewportBase: RenderBox, RenderAbstractViewport {

    // MARK: - Initializer

    /// Initializes fields for subclasses.
    ///
    /// The `cacheExtent`, if nil, defaults to `RenderAbstractViewportUtils.defaultCacheExtent`.
    ///
    /// The `cacheExtent` must be specified if `cacheExtentStyle` is not
    /// `CacheExtentStyle.pixel`.
    ///
    /// **Dart Source:** `viewport.dart:310-326`
    public init(
        axisDirection: AxisDirection = .down,
        crossAxisDirection: AxisDirection,
        offset: ViewportOffset,
        cacheExtent: Double? = nil,
        cacheExtentStyle: CacheExtentStyle = .pixel,
        paintOrder: SliverPaintOrder = .firstIsTop,
        clipBehavior: Clip = .hardEdge
    ) {
        assert(
            axisDirectionToAxis(axisDirection) != axisDirectionToAxis(crossAxisDirection),
            "axisDirection and crossAxisDirection must be on different axes"
        )
        assert(
            cacheExtent != nil || cacheExtentStyle == .pixel,
            "cacheExtent must be specified when cacheExtentStyle is not .pixel"
        )
        self._axisDirection = axisDirection
        self._crossAxisDirection = crossAxisDirection
        self._offset = offset
        self._cacheExtent = cacheExtent ?? RenderAbstractViewportUtils.defaultCacheExtent
        self._cacheExtentStyle = cacheExtentStyle
        self._paintOrder = paintOrder
        self._clipBehavior = clipBehavior
        super.init()
        // Registered HERE, unconditionally — not in attach(). attach() never
        // runs for an interior render object in this framework (it does not
        // recurse; see markNeedsPaint's note), so an attach-gated listener
        // meant the viewport NEVER heard its ScrollPosition: wheel scrolling
        // moved the offset, notified, and nothing re-laid-out — the listing
        // sat frozen while pixels advanced. _RenderSingleChildViewport
        // (SingleChildScrollView) registers in init for the same reason.
        // Weak, so a replaced viewport (Files keys its ListView by view
        // mode) does not keep a dead render tree alive through a
        // long-lived controller's position.
        _offset.addListener(_offsetChanged)
    }

    /// The one listener this viewport hangs on its offset — stored so the
    /// offset SETTER can re-register it on a new position. Never removed:
    /// removeListener in this port is identity-blind (it pops the LAST
    /// listener, whoever registered it), so unhooking here could strip a
    /// sibling's registration instead; the weak self makes a stale
    /// registration a no-op.
    private lazy var _offsetChanged: VoidCallback = { [weak self] in
        self?.markNeedsLayout()
    }

    // MARK: - Container child management (ContainerRenderObjectMixin<RenderSliver>)

    /// The first child in the child list.
    ///
    /// **Dart Source:** object.dart:4222
    public internal(set) var firstChild: RenderSliver?

    /// The last child in the child list.
    ///
    /// **Dart Source:** object.dart:4223
    public internal(set) var lastChild: RenderSliver?

    /// The number of children.
    ///
    /// **Dart Source:** object.dart:4226
    public internal(set) var childCount: Int = 0

    /// Returns the next sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4393
    open func childAfter(_ child: RenderSliver) -> RenderSliver? {
        let parentData = child.parentData as! SliverPhysicalContainerParentData
        return parentData.nextSibling
    }

    /// Returns the previous sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4399
    open func childBefore(_ child: RenderSliver) -> RenderSliver? {
        let parentData = child.parentData as! SliverPhysicalContainerParentData
        return parentData.previousSibling
    }

    /// Inserts a child into the linked list.
    ///
    /// **Dart Source:** object.dart:4234-4268
    private func _insertIntoChildList(_ child: RenderSliver, after: RenderSliver? = nil) {
        let childParentData = child.parentData as! SliverPhysicalContainerParentData
        childCount += 1
        assert(childCount > 0)
        if let after = after {
            let afterParentData = after.parentData as! SliverPhysicalContainerParentData
            childParentData.nextSibling = afterParentData.nextSibling
            if let nextSibling = afterParentData.nextSibling {
                let nextParentData = nextSibling.parentData as! SliverPhysicalContainerParentData
                nextParentData.previousSibling = child
            }
            afterParentData.nextSibling = child
            childParentData.previousSibling = after
            if after === lastChild {
                lastChild = child
            }
        } else {
            childParentData.nextSibling = firstChild
            if let first = firstChild {
                let firstParentData = first.parentData as! SliverPhysicalContainerParentData
                firstParentData.previousSibling = child
            }
            firstChild = child
            lastChild = lastChild ?? child
        }
    }

    /// Removes a child from the linked list.
    ///
    /// **Dart Source:** object.dart:4271-4295
    private func _removeFromChildList(_ child: RenderSliver) {
        let childParentData = child.parentData as! SliverPhysicalContainerParentData
        if childParentData.previousSibling == nil {
            firstChild = childParentData.nextSibling
        } else {
            let previousParentData =
                childParentData.previousSibling!.parentData as! SliverPhysicalContainerParentData
            previousParentData.nextSibling = childParentData.nextSibling
        }
        if childParentData.nextSibling == nil {
            lastChild = childParentData.previousSibling
        } else {
            let nextParentData =
                childParentData.nextSibling!.parentData as! SliverPhysicalContainerParentData
            nextParentData.previousSibling = childParentData.previousSibling
        }
        childParentData.previousSibling = nil
        childParentData.nextSibling = nil
        childCount -= 1
    }

    /// Adds a child to the child list, optionally after the given child.
    ///
    /// **Dart Source:** object.dart:4310-4323
    open func insert(_ child: RenderSliver, after: RenderSliver? = nil) {
        adoptChild(child)
        _insertIntoChildList(child, after: after)
    }

    /// Appends all the given children to the end of the child list.
    ///
    /// **Dart Source:** object.dart:4325-4341
    open func addAll(_ children: [RenderSliver]?) {
        children?.forEach { insert($0, after: lastChild) }
    }

    /// Removes a child from the child list.
    ///
    /// **Dart Source:** object.dart:4343-4353
    open func remove(_ child: RenderSliver) {
        _removeFromChildList(child)
        dropChild(child)
    }

    // MARK: - Semantics

    /// Report the semantics of this node, for example for accessibility purposes.
    ///
    /// `RenderViewportBase` adds `RenderViewport.useTwoPaneSemantics` to the
    /// provided `SemanticsConfiguration` to support children using
    /// `RenderViewport.excludeFromScrolling`.
    ///
    /// **Dart Source:** `viewport.dart:344-348`
    open override func describeSemanticsConfiguration(_ config: SemanticsConfiguration) {
        config.addTagForChildren(RenderViewport.useTwoPaneSemantics)
    }

    /// **Dart Source:** `viewport.dart:351-359`
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        for child in childrenInPaintOrder {
            if let geometry = child.geometry,
               geometry.visible || geometry.cacheExtent > 0.0 || child.ensureSemantics {
                visitor(child)
            }
        }
    }

    // MARK: - Properties

    /// The direction in which the `SliverConstraints.scrollOffset` increases.
    ///
    /// **Dart Source:** `viewport.dart:367-375`
    public var axisDirection: AxisDirection {
        get { _axisDirection }
        set {
            if newValue == _axisDirection { return }
            _axisDirection = newValue
            markNeedsLayout()
        }
    }
    private var _axisDirection: AxisDirection

    /// The direction in which children should be laid out in the cross axis.
    ///
    /// **Dart Source:** `viewport.dart:383-391`
    public var crossAxisDirection: AxisDirection {
        get { _crossAxisDirection }
        set {
            if newValue == _crossAxisDirection { return }
            _crossAxisDirection = newValue
            markNeedsLayout()
        }
    }
    private var _crossAxisDirection: AxisDirection

    /// The axis along which the viewport scrolls.
    ///
    /// **Dart Source:** `viewport.dart:397`
    public var axis: Axis {
        axisDirectionToAxis(axisDirection)
    }

    /// Which part of the content inside the viewport should be visible.
    ///
    /// **Dart Source:** `viewport.dart:405-422`
    public var offset: ViewportOffset {
        get { _offset }
        set {
            if newValue === _offset { return }
            // No removeListener on the old offset — see _offsetChanged. The
            // old position either dies with its Scrollable (listener dies
            // with it) or fires a weak no-op.
            _offset = newValue
            _offset.addListener(_offsetChanged)
            markNeedsLayout()
        }
    }
    private var _offset: ViewportOffset

    /// The viewport has an area before and after the visible area to cache items
    /// that are about to become visible when the user scrolls.
    ///
    /// **Dart Source:** `viewport.dart:456-465`
    public var cacheExtent: Double? {
        get { _cacheExtent }
        set {
            let value = newValue ?? RenderAbstractViewportUtils.defaultCacheExtent
            if value == _cacheExtent { return }
            _cacheExtent = value
            markNeedsLayout()
        }
    }
    internal var _cacheExtent: Double

    /// This value is set during layout based on the `CacheExtentStyle`.
    ///
    /// **Dart Source:** `viewport.dart:472`
    internal var _calculatedCacheExtent: Double?

    /// Controls how the `cacheExtent` is interpreted.
    ///
    /// **Dart Source:** `viewport.dart:489-497`
    public var cacheExtentStyle: CacheExtentStyle {
        get { _cacheExtentStyle }
        set {
            if newValue == _cacheExtentStyle { return }
            _cacheExtentStyle = newValue
            markNeedsLayout()
        }
    }
    private var _cacheExtentStyle: CacheExtentStyle

    /// The order in which to paint the slivers;
    /// equivalently, the order in which to arrange them in the z-direction.
    ///
    /// **Dart Source:** `viewport.dart:514-522`
    public var paintOrder: SliverPaintOrder {
        get { _paintOrder }
        set {
            if newValue != _paintOrder {
                _paintOrder = newValue
                markNeedsPaint()
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _paintOrder: SliverPaintOrder

    /// Clip behavior for the viewport.
    ///
    /// Defaults to `Clip.hardEdge`.
    ///
    /// **Dart Source:** `viewport.dart:527-535`
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
    private var _clipBehavior: Clip = .hardEdge

    // MARK: - Attach / Detach
    //
    // Upstream adds/removes the offset listener here. In this framework
    // attach() only ever reaches the ROOT render object, so the listener
    // lives on _offsetChanged (init + offset setter) instead — an
    // attach-gated registration silently never happened for a viewport,
    // and wheel scrolling repainted nothing. detach() must NOT
    // removeListener either: removal is identity-blind here and would pop
    // whichever listener registered last.

    // MARK: - Semantics update

    /// Mark this render object as needing a semantics update.
    ///
    /// Stub - will be fully implemented in a later subtask.
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with pipeline owner
    }

    // MARK: - Intrinsic Dimensions

    /// Throws an exception saying that the object does not support returning
    /// intrinsic dimensions if, in debug mode, we are not in the
    /// `RenderObject.debugCheckingIntrinsics` mode.
    ///
    /// **Dart Source:** `viewport.dart:557-577`
    open func debugThrowIfNotCheckingIntrinsics() -> Bool {
        // In the full implementation, this checks RenderObject.debugCheckingIntrinsics.
        // That static property is not yet migrated, so this is a simplified stub.
        return true
    }

    /// **Dart Source:** `viewport.dart:579-583`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        assert(debugThrowIfNotCheckingIntrinsics())
        return 0.0
    }

    /// **Dart Source:** `viewport.dart:585-589`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        assert(debugThrowIfNotCheckingIntrinsics())
        return 0.0
    }

    /// **Dart Source:** `viewport.dart:591-595`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        assert(debugThrowIfNotCheckingIntrinsics())
        return 0.0
    }

    /// **Dart Source:** `viewport.dart:597-601`
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        assert(debugThrowIfNotCheckingIntrinsics())
        return 0.0
    }

    // MARK: - Repaint Boundary

    /// **Dart Source:** `viewport.dart:603-604` — where this is `true`.
    ///
    /// DIFFERENCE FROM DART: this port has no interior repaint-boundary
    /// layers (`RenderObject._layer` exists only on the `RenderView` root),
    /// so a boundary child is never painted at all — see the KNOWN GAP note
    /// on `PaintingContext._compositeChild`. Painting the viewport inline
    /// costs a full-window repaint on scroll but actually renders; same
    /// resolution as `TextureBox.isRepaintBoundary` (792f90f).
    open override var isRepaintBoundary: Bool { false }

    // MARK: - layoutChildSequence

    /// Determines the size and position of some of the children of the viewport.
    ///
    /// This function is the workhorse of `performLayout` implementations in
    /// subclasses.
    ///
    /// Layout starts with `child`, proceeds according to the `advance` callback,
    /// and stops once `advance` returns nil.
    ///
    /// Returns the first non-zero `SliverGeometry.scrollOffsetCorrection`
    /// encountered, if any. Otherwise returns 0.0.
    ///
    /// **Dart Source:** `viewport.dart:637-735`
    open func layoutChildSequence(
        child: RenderSliver?,
        scrollOffset: Double,
        overlap: Double,
        layoutOffset: Double,
        remainingPaintExtent: Double,
        mainAxisExtent: Double,
        crossAxisExtent: Double,
        growthDirection: GrowthDirection,
        advance: (_ child: RenderSliver) -> RenderSliver?,
        remainingCacheExtent: Double,
        cacheOrigin: Double
    ) -> Double {
        assert(scrollOffset.isFinite)
        assert(scrollOffset >= 0.0)
        let initialLayoutOffset = layoutOffset
        let adjustedUserScrollDirection = applyGrowthDirectionToScrollDirection(
            offset.userScrollDirection,
            growthDirection
        )
        var maxPaintOffset = layoutOffset + overlap
        var precedingScrollExtent: Double = 0.0

        var scrollOffset = scrollOffset
        var layoutOffset = layoutOffset
        var remainingCacheExtent = remainingCacheExtent
        var cacheOrigin = cacheOrigin
        var child = child

        while child != nil {
            let sliverScrollOffset = scrollOffset <= 0.0 ? 0.0 : scrollOffset
            let correctedCacheOrigin = max(cacheOrigin, -sliverScrollOffset)
            let cacheExtentCorrection = cacheOrigin - correctedCacheOrigin

            assert(sliverScrollOffset >= Swift.abs(correctedCacheOrigin))
            assert(correctedCacheOrigin <= 0.0)
            assert(sliverScrollOffset >= 0.0)
            assert(cacheExtentCorrection <= 0.0)

            child!.layout(
                SliverConstraints(
                    axisDirection: axisDirection,
                    growthDirection: growthDirection,
                    userScrollDirection: adjustedUserScrollDirection,
                    scrollOffset: sliverScrollOffset,
                    precedingScrollExtent: precedingScrollExtent,
                    overlap: maxPaintOffset - layoutOffset,
                    remainingPaintExtent: max(
                        0.0,
                        remainingPaintExtent - layoutOffset + initialLayoutOffset
                    ),
                    crossAxisExtent: crossAxisExtent,
                    crossAxisDirection: crossAxisDirection,
                    viewportMainAxisExtent: mainAxisExtent,
                    remainingCacheExtent: max(0.0, remainingCacheExtent + cacheExtentCorrection),
                    cacheOrigin: correctedCacheOrigin
                ),
                parentUsesSize: true
            )

            let childLayoutGeometry = child!.geometry!
            assert(childLayoutGeometry.debugAssertIsValid())

            // If there is a correction to apply, we'll have to start over.
            if childLayoutGeometry.scrollOffsetCorrection != nil {
                return childLayoutGeometry.scrollOffsetCorrection!
            }

            // We use the child's paint origin in our coordinate system as the
            // layoutOffset we store in the child's parent data.
            let effectiveLayoutOffset = layoutOffset + childLayoutGeometry.paintOrigin

            // `effectiveLayoutOffset` becomes meaningless once we moved past the trailing edge
            // because `childLayoutGeometry.layoutExtent` is zero.
            if childLayoutGeometry.visible || scrollOffset > 0 {
                updateChildLayoutOffset(child!, effectiveLayoutOffset, growthDirection)
            } else {
                updateChildLayoutOffset(child!, -scrollOffset + initialLayoutOffset, growthDirection)
            }

            maxPaintOffset = max(
                effectiveLayoutOffset + childLayoutGeometry.paintExtent,
                maxPaintOffset
            )
            scrollOffset -= childLayoutGeometry.scrollExtent
            precedingScrollExtent += childLayoutGeometry.scrollExtent
            layoutOffset += childLayoutGeometry.layoutExtent
            if childLayoutGeometry.cacheExtent != 0.0 {
                remainingCacheExtent -= childLayoutGeometry.cacheExtent - cacheExtentCorrection
                cacheOrigin = min(correctedCacheOrigin + childLayoutGeometry.cacheExtent, 0.0)
            }

            updateOutOfBandData(growthDirection, childLayoutGeometry)

            // move on to the next child
            child = advance(child!)
        }

        // we made it without a correction, whee!
        return 0.0
    }

    // MARK: - Clip Description

    /// **Dart Source:** `viewport.dart:738-787`
    open func describeApproximatePaintClip(_ child: RenderSliver) -> Rect? {
        if child.ensureSemantics && !(child.geometry!.visible || child.geometry!.cacheExtent > 0.0) {
            return nil
        }

        switch clipBehavior {
        case .none:
            return nil
        case .hardEdge, .antiAlias, .antiAliasWithSaveLayer:
            break
        }

        let viewportClip = Offset.zero & size
        if child.sliverConstraints.overlap == 0 || !child.sliverConstraints.viewportMainAxisExtent.isFinite {
            return viewportClip
        }

        var left = viewportClip.left
        var right = viewportClip.right
        var top = viewportClip.top
        var bottom = viewportClip.bottom
        let startOfOverlap =
            child.sliverConstraints.viewportMainAxisExtent - child.sliverConstraints.remainingPaintExtent
        let overlapCorrection = startOfOverlap + child.sliverConstraints.overlap
        switch applyGrowthDirectionToAxisDirection(axisDirection, child.sliverConstraints.growthDirection) {
        case .down:
            top += overlapCorrection
        case .up:
            bottom -= overlapCorrection
        case .right:
            left += overlapCorrection
        case .left:
            right -= overlapCorrection
        }
        return Rect.fromLTRB(left, top, right, bottom)
    }

    /// **Dart Source:** `viewport.dart:790-818`
    open func describeSemanticsClip(_ child: RenderSliver?) -> Rect? {
        if let child = child,
           child.ensureSemantics && !(child.geometry!.visible || child.geometry!.cacheExtent > 0.0) {
            return nil
        }
        guard let cacheExtent = _calculatedCacheExtent else {
            return semanticBounds
        }
        switch axis {
        case .vertical:
            return Rect.fromLTRB(
                semanticBounds.left,
                semanticBounds.top - cacheExtent,
                semanticBounds.right,
                semanticBounds.bottom + cacheExtent
            )
        case .horizontal:
            return Rect.fromLTRB(
                semanticBounds.left - cacheExtent,
                semanticBounds.top,
                semanticBounds.right + cacheExtent,
                semanticBounds.bottom
            )
        }
    }

    /// The semantic bounds of this render object.
    ///
    /// For a viewport, this is the same as the paint bounds.
    open var semanticBounds: Rect {
        Offset.zero & size
    }

    // MARK: - Paint

    /// The clip rect layer handle for clipping children.
    ///
    /// **Dart Source:** `viewport.dart:840`
    private var _clipRectLayer = LayerHandle<ClipRectLayer>()

    /// **Dart Source:** `viewport.dart:820-838`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if firstChild == nil {
            return
        }
        if hasVisualOverflow && clipBehavior != .none {
            _clipRectLayer.layer = context.pushClipRect(
                needsCompositing,
                offset,
                Offset.zero & size,
                _paintContents,
                clipBehavior: clipBehavior,
                oldLayer: _clipRectLayer.layer
            )
        } else {
            _clipRectLayer.layer = nil
            _paintContents(context, offset)
        }
    }

    /// **Dart Source:** `viewport.dart:842-846`
    open override func dispose() {
        _clipRectLayer.layer = nil
        super.dispose()
    }

    /// **Dart Source:** `viewport.dart:848-854`
    private func _paintContents(_ context: PaintingContext, _ offset: Offset) {
        for child in childrenInPaintOrder {
            if child.geometry!.visible {
                context.paintChild(child, offset + paintOffsetOf(child))
            }
        }
    }

    // MARK: - Hit Testing

    /// **Dart Source:** `viewport.dart:878-906`
    open override func hitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool {
        let (mainAxisPosition, crossAxisPosition): (Double, Double) = {
            switch axis {
            case .vertical: return (position.dy, position.dx)
            case .horizontal: return (position.dx, position.dy)
            }
        }()
        let sliverResult = SliverHitTestResult(wrapping: result)
        for child in childrenInHitTestOrder {
            if !child.geometry!.visible {
                continue
            }
            var transform = Matrix4.identity()
            applyPaintTransform(child, &transform) // must be invertible
            let isHit = result.addWithOutOfBandPosition(
                paintTransform: transform,
                hitTest: { (result: BoxHitTestResult) -> Bool in
                    return child.hitTest(
                        sliverResult,
                        mainAxisPosition: computeChildMainAxisPosition(child, mainAxisPosition),
                        crossAxisPosition: crossAxisPosition
                    )
                }
            )
            if isHit {
                return true
            }
        }
        return false
    }

    // MARK: - getOffsetToReveal

    /// **Dart Source:** `viewport.dart:909-1082`
    open func getOffsetToReveal(
        _ target: RenderObject,
        _ alignment: Double,
        rect: Rect? = nil,
        axis: Axis? = nil
    ) -> RevealedOffset {
        // One dimensional viewport has only one axis, override if it was
        // provided/may be mismatched.
        let axis = self.axis

        var leadingScrollOffset: Double = 0.0
        var child: RenderObject = target
        var pivot: RenderBox? = nil
        var onlySlivers = target is RenderSliver
        while child.parent !== self {
            let parent = child.parent!
            if child is RenderBox {
                pivot = child as? RenderBox
            }
            if parent is RenderSliver {
                leadingScrollOffset += (parent as! RenderSliver).childScrollOffset(child)!
            } else {
                onlySlivers = false
                leadingScrollOffset = 0.0
            }
            child = parent
        }

        var rect = rect
        let rectLocal: Rect
        let pivotExtent: Double
        let growthDirection: GrowthDirection

        if let pivot = pivot {
            assert(pivot.parent != nil)
            assert(pivot.parent !== self)
            assert(pivot !== self)
            assert(pivot.parent is RenderSliver)
            let pivotParent = pivot.parent! as! RenderSliver
            growthDirection = pivotParent.sliverConstraints.growthDirection
            switch axis {
            case .horizontal:
                pivotExtent = pivot.size.width
            case .vertical:
                pivotExtent = pivot.size.height
            }
            rect = rect ?? target.paintBounds
            rectLocal = MatrixUtils.transformRect(target.getTransformTo(pivot), rect!)
        } else if onlySlivers {
            let targetSliver = target as! RenderSliver
            growthDirection = targetSliver.sliverConstraints.growthDirection
            pivotExtent = targetSliver.geometry!.scrollExtent
            if rect == nil {
                switch axis {
                case .horizontal:
                    rect = Rect.fromLTWH(
                        0, 0,
                        targetSliver.geometry!.scrollExtent,
                        targetSliver.sliverConstraints.crossAxisExtent
                    )
                case .vertical:
                    rect = Rect.fromLTWH(
                        0, 0,
                        targetSliver.sliverConstraints.crossAxisExtent,
                        targetSliver.geometry!.scrollExtent
                    )
                }
            }
            rectLocal = rect!
        } else {
            assert(rect != nil)
            return RevealedOffset(offset: offset.pixels, rect: rect!)
        }

        assert(child.parent === self)
        assert(child is RenderSliver)
        let sliver = child as! RenderSliver

        switch applyGrowthDirectionToAxisDirection(axisDirection, growthDirection) {
        case .up:
            leadingScrollOffset += pivotExtent - rectLocal.bottom
        case .left:
            leadingScrollOffset += pivotExtent - rectLocal.right
        case .right:
            leadingScrollOffset += rectLocal.left
        case .down:
            leadingScrollOffset += rectLocal.top
        }

        let isPinned =
            sliver.geometry!.maxScrollObstructionExtent > 0 && leadingScrollOffset >= 0

        leadingScrollOffset = scrollOffsetOf(sliver, leadingScrollOffset)

        let transform = target.getTransformTo(self)
        var targetRect = MatrixUtils.transformRect(transform, rect!)
        let extentOfPinnedSlivers = maxScrollObstructionExtentBefore(sliver)

        switch sliver.sliverConstraints.growthDirection {
        case .forward:
            if isPinned && alignment <= 0 {
                return RevealedOffset(offset: .infinity, rect: targetRect)
            }
            leadingScrollOffset -= extentOfPinnedSlivers
        case .reverse:
            if isPinned && alignment >= 1 {
                return RevealedOffset(offset: -.infinity, rect: targetRect)
            }
            switch axis {
            case .vertical:
                leadingScrollOffset -= targetRect.height
            case .horizontal:
                leadingScrollOffset -= targetRect.width
            }
        }

        let mainAxisExtentDifference: Double
        switch axis {
        case .horizontal:
            mainAxisExtentDifference = size.width - extentOfPinnedSlivers - rectLocal.width
        case .vertical:
            mainAxisExtentDifference = size.height - extentOfPinnedSlivers - rectLocal.height
        }

        let targetOffset = leadingScrollOffset - mainAxisExtentDifference * alignment
        let offsetDifference = offset.pixels - targetOffset

        switch axisDirection {
        case .up:
            targetRect = targetRect.translate(0.0, -offsetDifference)
        case .down:
            targetRect = targetRect.translate(0.0, offsetDifference)
        case .left:
            targetRect = targetRect.translate(-offsetDifference, 0.0)
        case .right:
            targetRect = targetRect.translate(offsetDifference, 0.0)
        }

        return RevealedOffset(offset: targetOffset, rect: targetRect)
    }

    // MARK: - computeAbsolutePaintOffset

    /// The offset at which the given `child` should be painted.
    ///
    /// The returned offset is from the top left corner of the inside of the
    /// viewport to the top left corner of the paint coordinate system of the
    /// `child`.
    ///
    /// **Dart Source:** `viewport.dart:1094-1108`
    open func computeAbsolutePaintOffset(
        _ child: RenderSliver,
        _ layoutOffset: Double,
        _ growthDirection: GrowthDirection
    ) -> Offset {
        assert(hasSize)
        assert(child.geometry != nil)
        switch applyGrowthDirectionToAxisDirection(axisDirection, growthDirection) {
        case .up:
            return Offset(0.0, size.height - layoutOffset - child.geometry!.paintExtent)
        case .left:
            return Offset(size.width - layoutOffset - child.geometry!.paintExtent, 0.0)
        case .right:
            return Offset(layoutOffset, 0.0)
        case .down:
            return Offset(0.0, layoutOffset)
        }
    }

    // MARK: - Debug

    /// **Dart Source:** `viewport.dart:1110-1116`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(DiagnosticsProperty<AxisDirection>("axisDirection", axisDirection))
        properties.add(DiagnosticsProperty<AxisDirection>("crossAxisDirection", crossAxisDirection))
        properties.add(DiagnosticsProperty<ViewportOffset>("offset", offset))
    }

    /// **Dart Source:** `viewport.dart:1118-1136`
    open func debugDescribeChildren() -> [DiagnosticsNode] {
        // In the full implementation, this iterates through children and calls
        // toDiagnosticsNode on each. RenderObject does not yet conform to
        // Diagnosticable, so this returns an empty list for now.
        return []
    }

    // MARK: - Abstract API (to be overridden by subclasses)

    /// Whether the contents of this viewport would paint outside the bounds of
    /// the viewport if `paint` did not clip.
    ///
    /// **Dart Source:** `viewport.dart:1151`
    open var hasVisualOverflow: Bool {
        fatalError("Subclasses of RenderViewportBase must override hasVisualOverflow")
    }

    /// Called during `layoutChildSequence` for each child.
    ///
    /// Typically used by subclasses to update any out-of-band data, such as the
    /// max scroll extent, for each child.
    ///
    /// **Dart Source:** `viewport.dart:1158`
    open func updateOutOfBandData(_ growthDirection: GrowthDirection, _ childLayoutGeometry: SliverGeometry) {
        fatalError("Subclasses of RenderViewportBase must override updateOutOfBandData")
    }

    /// Called during `layoutChildSequence` to store the layout offset for the
    /// given child.
    ///
    /// **Dart Source:** `viewport.dart:1168-1172`
    open func updateChildLayoutOffset(
        _ child: RenderSliver,
        _ layoutOffset: Double,
        _ growthDirection: GrowthDirection
    ) {
        fatalError("Subclasses of RenderViewportBase must override updateChildLayoutOffset")
    }

    /// The offset at which the given `child` should be painted.
    ///
    /// **Dart Source:** `viewport.dart:1186`
    open func paintOffsetOf(_ child: RenderSliver) -> Offset {
        fatalError("Subclasses of RenderViewportBase must override paintOffsetOf")
    }

    /// Returns the scroll offset within the viewport for the given
    /// `scrollOffsetWithinChild` within the given `child`.
    ///
    /// **Dart Source:** `viewport.dart:1195`
    open func scrollOffsetOf(_ child: RenderSliver, _ scrollOffsetWithinChild: Double) -> Double {
        fatalError("Subclasses of RenderViewportBase must override scrollOffsetOf")
    }

    /// Returns the total scroll obstruction extent of all slivers in the viewport
    /// before `child`.
    ///
    /// **Dart Source:** `viewport.dart:1204`
    open func maxScrollObstructionExtentBefore(_ child: RenderSliver) -> Double {
        fatalError("Subclasses of RenderViewportBase must override maxScrollObstructionExtentBefore")
    }

    /// Converts the `parentMainAxisPosition` into the child's coordinate system.
    ///
    /// **Dart Source:** `viewport.dart:1223`
    open func computeChildMainAxisPosition(_ child: RenderSliver, _ parentMainAxisPosition: Double) -> Double {
        fatalError("Subclasses of RenderViewportBase must override computeChildMainAxisPosition")
    }

    /// The index of the first child of the viewport relative to the center child.
    ///
    /// **Dart Source:** `viewport.dart:1230`
    open var indexOfFirstChild: Int {
        fatalError("Subclasses of RenderViewportBase must override indexOfFirstChild")
    }

    /// A short string to identify the child with the given index.
    ///
    /// **Dart Source:** `viewport.dart:1236`
    open func labelForChild(_ index: Int) -> String {
        fatalError("Subclasses of RenderViewportBase must override labelForChild")
    }

    // MARK: - Children iteration

    /// Provides an iterable that walks the children of the viewport, in the order
    /// that they should be painted.
    ///
    /// **Dart Source:** `viewport.dart:1243-1248`
    open var childrenInPaintOrder: [RenderSliver] {
        switch paintOrder {
        case .firstIsTop: return _childrenLastToFirst
        case .lastIsTop: return _childrenFirstToLast
        }
    }

    /// Provides an iterable that walks the children of the viewport, in the order
    /// that hit-testing should use.
    ///
    /// **Dart Source:** `viewport.dart:1255-1260`
    open var childrenInHitTestOrder: [RenderSliver] {
        switch paintOrder {
        case .firstIsTop: return _childrenFirstToLast
        case .lastIsTop: return _childrenLastToFirst
        }
    }

    /// **Dart Source:** `viewport.dart:1262-1270`
    private var _childrenLastToFirst: [RenderSliver] {
        var children: [RenderSliver] = []
        var child = lastChild
        while child != nil {
            children.append(child!)
            child = childBefore(child!)
        }
        return children
    }

    /// **Dart Source:** `viewport.dart:1272-1280`
    private var _childrenFirstToLast: [RenderSliver] {
        var children: [RenderSliver] = []
        var child = firstChild
        while child != nil {
            children.append(child!)
            child = childAfter(child!)
        }
        return children
    }

    // MARK: - showOnScreen

    /// **Dart Source:** `viewport.dart:1282-1307`
    open func showOnScreen(
        descendant: RenderObject? = nil,
        rect: Rect? = nil,
        duration: Duration = .zero,
        curve: any Curve = Curves.ease
    ) {
        if !offset.allowImplicitScrolling {
            // Cannot scroll implicitly; delegate to super (no-op stub here).
            return
        }

        let newRect = RenderViewportBase.showInViewport(
            descendant: descendant,
            rect: rect,
            viewport: self,
            offset: offset,
            duration: duration,
            curve: curve
        )
        // In the full implementation, would call super.showOnScreen(rect: newRect, ...)
        _ = newRect
    }

    /// Make (a portion of) the given `descendant` of the given `viewport` fully
    /// visible in the `viewport` by manipulating the provided `ViewportOffset`
    /// `offset`.
    ///
    /// The returned `Rect` describes the new location of `descendant` or `rect`
    /// in the viewport after it has been revealed.
    ///
    /// If `descendant` is nil, this is a no-op and `rect` is returned.
    ///
    /// **Dart Source:** `viewport.dart:1334-1371`
    public static func showInViewport(
        descendant: RenderObject? = nil,
        rect: Rect? = nil,
        viewport: any RenderAbstractViewport,
        offset: ViewportOffset,
        duration: Duration = .zero,
        curve: any Curve = Curves.ease
    ) -> Rect? {
        guard let descendant = descendant else {
            return rect
        }
        let leadingEdgeOffset = viewport.getOffsetToReveal(
            descendant,
            0.0,
            rect: rect,
            axis: nil
        )
        let trailingEdgeOffset = viewport.getOffsetToReveal(
            descendant,
            1.0,
            rect: rect,
            axis: nil
        )
        let currentOffset = offset.pixels
        let targetOffset = RevealedOffset.clampOffset(
            leadingEdgeOffset: leadingEdgeOffset,
            trailingEdgeOffset: trailingEdgeOffset,
            currentOffset: currentOffset
        )
        if targetOffset == nil {
            // `descendant` is already fully shown on screen.
            assert(viewport is RenderObject)
            let viewportObj = viewport as! RenderObject
            let transform = descendant.getTransformTo(viewportObj.parent)
            return MatrixUtils.transformRect(transform, rect ?? descendant.paintBounds)
        }

        // In the Dart source, moveTo may animate. For zero duration, jumpTo is
        // called synchronously. We use jumpTo directly here to avoid Sendable
        // issues with Task closures; animation support will be added when the
        // scheduler is fully migrated.
        if duration == .zero {
            offset.jumpTo(targetOffset!.offset)
        } else {
            // For non-zero duration, use jumpTo as a fallback until animation
            // infrastructure is fully migrated.
            offset.jumpTo(targetOffset!.offset)
        }
        return targetOffset!.rect
    }
}

// MARK: - RenderViewport

/// A render object that is bigger on the inside.
///
/// `RenderViewport` is the visual workhorse of the scrolling machinery. It
/// displays a subset of its children according to its own dimensions and the
/// given `offset`. As the offset varies, different children are visible through
/// the viewport.
///
/// `RenderViewport` hosts a bidirectional list of slivers in a single shared
/// `Axis`, anchored on a `center` sliver, which is placed at the zero scroll
/// offset. The center widget is displayed in the viewport according to the
/// `anchor` property.
///
/// Slivers that are earlier in the child list than `center` are displayed in
/// reverse order in the reverse `axisDirection` starting from the `center`.
///
/// `RenderViewport` cannot contain `RenderBox` children directly. Instead, use
/// a `RenderSliverList`, `RenderSliverFixedExtentList`, `RenderSliverGrid`, or
/// a `RenderSliverToBoxAdapter`, for example.
///
/// **Dart Source:** `viewport.dart:1374-1829`
open class RenderViewport: RenderViewportBase {

    // MARK: - Initializer

    /// Creates a viewport for `RenderSliver` objects.
    ///
    /// If the `center` is not specified, then the first child in the `children`
    /// list, if any, is used.
    ///
    /// **Dart Source:** `viewport.dart:1416-1435`
    public init(
        axisDirection: AxisDirection = .down,
        crossAxisDirection: AxisDirection,
        offset: ViewportOffset,
        anchor: Double = 0.0,
        children: [RenderSliver]? = nil,
        center: RenderSliver? = nil,
        cacheExtent: Double? = nil,
        cacheExtentStyle: CacheExtentStyle = .pixel,
        paintOrder: SliverPaintOrder = .firstIsTop,
        clipBehavior: Clip = .hardEdge
    ) {
        assert(anchor >= 0.0 && anchor <= 1.0)
        assert(cacheExtentStyle != .viewport || cacheExtent != nil)
        self._anchor = anchor
        self._center = center
        super.init(
            axisDirection: axisDirection,
            crossAxisDirection: crossAxisDirection,
            offset: offset,
            cacheExtent: cacheExtent,
            cacheExtentStyle: cacheExtentStyle,
            paintOrder: paintOrder,
            clipBehavior: clipBehavior
        )
        addAll(children)
        if center == nil && firstChild != nil {
            _center = firstChild
        }
    }

    // MARK: - Semantic Tags

    /// If a `RenderAbstractViewport` overrides
    /// `describeSemanticsConfiguration` to add the `SemanticsTag`
    /// `useTwoPaneSemantics` to its `SemanticsConfiguration`, two semantics nodes
    /// will be used to represent the viewport with its associated scrolling
    /// actions in the semantics tree.
    ///
    /// **Dart Source:** `viewport.dart:1455`
    public static let useTwoPaneSemantics = SemanticsTag("RenderViewport.twoPane")

    /// When a top-level `SemanticsNode` below a `RenderAbstractViewport` is
    /// tagged with `excludeFromScrolling` it will not be part of the scrolling
    /// area for semantic purposes.
    ///
    /// **Dart Source:** `viewport.dart:1470-1472`
    public static let excludeFromScrolling = SemanticsTag(
        "RenderViewport.excludeFromScrolling"
    )

    // MARK: - Setup Parent Data

    /// **Dart Source:** `viewport.dart:1475-1479`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverPhysicalContainerParentData) {
            child.parentData = SliverPhysicalContainerParentData()
        }
    }

    // MARK: - Anchor

    /// The relative position of the zero scroll offset.
    ///
    /// For example, if `anchor` is 0.5 and the `axisDirection` is
    /// `AxisDirection.down` or `AxisDirection.up`, then the zero scroll offset is
    /// vertically centered within the viewport.
    ///
    /// **Dart Source:** `viewport.dart:1490-1499`
    public var anchor: Double {
        get { _anchor }
        set {
            assert(newValue >= 0.0 && newValue <= 1.0)
            if newValue == _anchor { return }
            _anchor = newValue
            markNeedsLayout()
        }
    }
    private var _anchor: Double

    // MARK: - Center

    /// The first child in the `GrowthDirection.forward` growth direction.
    ///
    /// This child that will be at the position defined by `anchor` when the
    /// `ViewportOffset.pixels` of `offset` is `0`.
    ///
    /// **Dart Source:** `viewport.dart:1516-1524`
    public var center: RenderSliver? {
        // Defaults to the first sliver: children arrive through the element
        // tree after construction (MultiChildRenderObjectElement.mount), so an
        // explicit center can only be wired by whoever also owns the child
        // list. Dart's ViewportElement resolves the center to the first child
        // in exactly the same way when Viewport.center is null.
        get { _center ?? firstChild }
        set {
            if newValue === _center { return }
            _center = newValue
            markNeedsLayout()
        }
    }
    private var _center: RenderSliver?

    // MARK: - sizedByParent

    /// **Dart Source:** `viewport.dart:1527`
    open override var sizedByParent: Bool { true }

    // MARK: - computeDryLayout

    /// **Dart Source:** `viewport.dart:1531-1534`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }

    // MARK: - performLayout

    private static let _maxLayoutCyclesPerChild = 10

    // Out-of-band data computed during layout.
    private var _minScrollExtent: Double = 0.0
    private var _maxScrollExtent: Double = 0.0
    private var _hasVisualOverflow: Bool = false

    /// **Dart Source:** `viewport.dart:1544-1616`
    open override func performLayout() {
        // Ignore the return value of applyViewportDimension because we are
        // doing a layout regardless.
        switch axis {
        case .vertical:
            offset.applyViewportDimension(size.height)
        case .horizontal:
            offset.applyViewportDimension(size.width)
        }

        if center == nil {
            assert(firstChild == nil)
            _minScrollExtent = 0.0
            _maxScrollExtent = 0.0
            _hasVisualOverflow = false
            offset.applyContentDimensions(0.0, 0.0)
            return
        }
        assert(center!.parent === self)

        let mainAxisExtent: Double
        let crossAxisExtent: Double
        switch axis {
        case .vertical:
            mainAxisExtent = size.height
            crossAxisExtent = size.width
        case .horizontal:
            mainAxisExtent = size.width
            crossAxisExtent = size.height
        }

        let centerOffsetAdjustment = center!.centerOffsetAdjustment
        let maxLayoutCycles = RenderViewport._maxLayoutCyclesPerChild * childCount

        var correction: Double
        var count = 0
        repeat {
            correction = _attemptLayout(
                mainAxisExtent,
                crossAxisExtent,
                offset.pixels + centerOffsetAdjustment
            )
            if correction != 0.0 {
                offset.correctBy(correction)
            } else {
                if offset.applyContentDimensions(
                    min(0.0, _minScrollExtent + mainAxisExtent * anchor),
                    max(0.0, _maxScrollExtent - mainAxisExtent * (1.0 - anchor))
                ) {
                    break
                }
            }
            count += 1
        } while count < maxLayoutCycles
        assert({
            if count >= maxLayoutCycles {
                assert(count != 1)
                fatalError(
                    "A RenderViewport exceeded its maximum number of layout cycles.\n"
                    + "RenderViewport render objects, during layout, can retry if either their "
                    + "slivers or their ViewportOffset decide that the offset should be corrected "
                    + "to take into account information collected during that layout.\n"
                    + "In the case of this RenderViewport object, however, this happened \(count) "
                    + "times and still there was no consensus on the scroll offset. This usually "
                    + "indicates a bug."
                )
            }
            return true
        }())
    }

    /// **Dart Source:** `viewport.dart:1618-1699`
    private func _attemptLayout(
        _ mainAxisExtent: Double,
        _ crossAxisExtent: Double,
        _ correctedOffset: Double
    ) -> Double {
        assert(!mainAxisExtent.isNaN)
        assert(mainAxisExtent >= 0.0)
        assert(crossAxisExtent.isFinite)
        assert(crossAxisExtent >= 0.0)
        assert(correctedOffset.isFinite)
        _minScrollExtent = 0.0
        _maxScrollExtent = 0.0
        _hasVisualOverflow = false

        let centerOffset = mainAxisExtent * anchor - correctedOffset
        let reverseDirectionRemainingPaintExtent = clampDouble(
            centerOffset, 0.0, mainAxisExtent
        )
        let forwardDirectionRemainingPaintExtent = clampDouble(
            mainAxisExtent - centerOffset, 0.0, mainAxisExtent
        )

        _calculatedCacheExtent = {
            switch cacheExtentStyle {
            case .pixel: return cacheExtent
            case .viewport: return mainAxisExtent * _cacheExtent
            }
        }()

        let fullCacheExtent = mainAxisExtent + 2 * _calculatedCacheExtent!
        let centerCacheOffset = centerOffset + _calculatedCacheExtent!
        let reverseDirectionRemainingCacheExtent = clampDouble(
            centerCacheOffset, 0.0, fullCacheExtent
        )
        let forwardDirectionRemainingCacheExtent = clampDouble(
            fullCacheExtent - centerCacheOffset, 0.0, fullCacheExtent
        )

        let leadingNegativeChild = childBefore(center!)

        if let leadingNegativeChild = leadingNegativeChild {
            // negative scroll offsets
            let result = layoutChildSequence(
                child: leadingNegativeChild,
                scrollOffset: max(mainAxisExtent, centerOffset) - mainAxisExtent,
                overlap: 0.0,
                layoutOffset: forwardDirectionRemainingPaintExtent,
                remainingPaintExtent: reverseDirectionRemainingPaintExtent,
                mainAxisExtent: mainAxisExtent,
                crossAxisExtent: crossAxisExtent,
                growthDirection: .reverse,
                advance: childBefore,
                remainingCacheExtent: reverseDirectionRemainingCacheExtent,
                cacheOrigin: clampDouble(mainAxisExtent - centerOffset, -_calculatedCacheExtent!, 0.0)
            )
            if result != 0.0 {
                return -result
            }
        }

        // positive scroll offsets
        return layoutChildSequence(
            child: center,
            scrollOffset: max(0.0, -centerOffset),
            overlap: leadingNegativeChild == nil ? min(0.0, -centerOffset) : 0.0,
            layoutOffset: centerOffset >= mainAxisExtent
                ? centerOffset
                : reverseDirectionRemainingPaintExtent,
            remainingPaintExtent: forwardDirectionRemainingPaintExtent,
            mainAxisExtent: mainAxisExtent,
            crossAxisExtent: crossAxisExtent,
            growthDirection: .forward,
            advance: childAfter,
            remainingCacheExtent: forwardDirectionRemainingCacheExtent,
            cacheOrigin: clampDouble(centerOffset, -_calculatedCacheExtent!, 0.0)
        )
    }

    // MARK: - Abstract Overrides

    /// **Dart Source:** `viewport.dart:1702`
    open override var hasVisualOverflow: Bool { _hasVisualOverflow }

    /// **Dart Source:** `viewport.dart:1704-1715`
    open override func updateOutOfBandData(
        _ growthDirection: GrowthDirection,
        _ childLayoutGeometry: SliverGeometry
    ) {
        switch growthDirection {
        case .forward:
            _maxScrollExtent += childLayoutGeometry.scrollExtent
        case .reverse:
            _minScrollExtent -= childLayoutGeometry.scrollExtent
        }
        if childLayoutGeometry.hasVisualOverflow {
            _hasVisualOverflow = true
        }
    }

    /// **Dart Source:** `viewport.dart:1717-1725`
    open override func updateChildLayoutOffset(
        _ child: RenderSliver,
        _ layoutOffset: Double,
        _ growthDirection: GrowthDirection
    ) {
        let childParentData = child.parentData! as! SliverPhysicalParentData
        childParentData.paintOffset = computeAbsolutePaintOffset(child, layoutOffset, growthDirection)
    }

    /// **Dart Source:** `viewport.dart:1727-1731`
    open override func paintOffsetOf(_ child: RenderSliver) -> Offset {
        let childParentData = child.parentData! as! SliverPhysicalParentData
        return childParentData.paintOffset
    }

    /// **Dart Source:** `viewport.dart:1733-1755`
    open override func scrollOffsetOf(_ child: RenderSliver, _ scrollOffsetWithinChild: Double) -> Double {
        assert(child.parent === self)
        let growthDirection = child.sliverConstraints.growthDirection
        switch growthDirection {
        case .forward:
            var scrollOffsetToChild: Double = 0.0
            var current: RenderSliver? = center
            while current !== child {
                scrollOffsetToChild += current!.geometry!.scrollExtent
                current = childAfter(current!)
            }
            return scrollOffsetToChild + scrollOffsetWithinChild
        case .reverse:
            var scrollOffsetToChild: Double = 0.0
            var current: RenderSliver? = childBefore(center!)
            while current !== child {
                scrollOffsetToChild -= current!.geometry!.scrollExtent
                current = childBefore(current!)
            }
            return scrollOffsetToChild - scrollOffsetWithinChild
        }
    }

    /// **Dart Source:** `viewport.dart:1757-1779`
    open override func maxScrollObstructionExtentBefore(_ child: RenderSliver) -> Double {
        assert(child.parent === self)
        let growthDirection = child.sliverConstraints.growthDirection
        switch growthDirection {
        case .forward:
            var pinnedExtent: Double = 0.0
            var current: RenderSliver? = center
            while current !== child {
                pinnedExtent += current!.geometry!.maxScrollObstructionExtent
                current = childAfter(current!)
            }
            return pinnedExtent
        case .reverse:
            var pinnedExtent: Double = 0.0
            var current: RenderSliver? = childBefore(center!)
            while current !== child {
                pinnedExtent += current!.geometry!.maxScrollObstructionExtent
                current = childBefore(current!)
            }
            return pinnedExtent
        }
    }

    /// **Dart Source:** `viewport.dart:1782-1786`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        // Hit test logic relies on this always providing an invertible matrix.
        let childParentData = child.parentData! as! SliverPhysicalParentData
        childParentData.applyPaintTransform(&transform)
    }

    /// **Dart Source:** `viewport.dart:1789-1800`
    open override func computeChildMainAxisPosition(
        _ child: RenderSliver,
        _ parentMainAxisPosition: Double
    ) -> Double {
        let paintOffset = (child.parentData! as! SliverPhysicalParentData).paintOffset
        switch applyGrowthDirectionToAxisDirection(
            child.sliverConstraints.axisDirection,
            child.sliverConstraints.growthDirection
        ) {
        case .down:
            return parentMainAxisPosition - paintOffset.dy
        case .right:
            return parentMainAxisPosition - paintOffset.dx
        case .up:
            return child.geometry!.paintExtent - (parentMainAxisPosition - paintOffset.dy)
        case .left:
            return child.geometry!.paintExtent - (parentMainAxisPosition - paintOffset.dx)
        }
    }

    /// **Dart Source:** `viewport.dart:1802-1814`
    open override var indexOfFirstChild: Int {
        assert(center != nil)
        assert(center!.parent === self)
        assert(firstChild != nil)
        var count = 0
        var child: RenderSliver? = center
        while child !== firstChild {
            count -= 1
            child = childBefore(child!)
        }
        return count
    }

    /// **Dart Source:** `viewport.dart:1816-1822`
    open override func labelForChild(_ index: Int) -> String {
        if index == 0 {
            return "center child"
        }
        return "child \(index)"
    }

    /// **Dart Source:** `viewport.dart:1825-1828`
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DoubleProperty("anchor", anchor))
    }
}

// MARK: - RenderShrinkWrappingViewport

/// A render object that is bigger on the inside and shrink wraps its children
/// in the main axis.
///
/// `RenderShrinkWrappingViewport` displays a subset of its children according
/// to its own dimensions and the given `offset`. As the offset varies, different
/// children are visible through the viewport.
///
/// `RenderShrinkWrappingViewport` differs from `RenderViewport` in that
/// `RenderViewport` expands to fill the main axis whereas
/// `RenderShrinkWrappingViewport` sizes itself to match its children in the
/// main axis.
///
/// `RenderShrinkWrappingViewport` cannot contain `RenderBox` children directly.
/// Instead, use a `RenderSliverList`, `RenderSliverFixedExtentList`,
/// `RenderSliverGrid`, or a `RenderSliverToBoxAdapter`, for example.
///
/// **Dart Source:** `viewport.dart:1856-2111`
open class RenderShrinkWrappingViewport: RenderViewportBase {

    // MARK: - Initializer

    /// Creates a viewport (for `RenderSliver` objects) that shrink-wraps its
    /// contents.
    ///
    /// **Dart Source:** `viewport.dart:1862-1871`
    public init(
        axisDirection: AxisDirection = .down,
        crossAxisDirection: AxisDirection,
        offset: ViewportOffset,
        paintOrder: SliverPaintOrder = .firstIsTop,
        clipBehavior: Clip = .hardEdge,
        children: [RenderSliver]? = nil
    ) {
        super.init(
            axisDirection: axisDirection,
            crossAxisDirection: crossAxisDirection,
            offset: offset,
            paintOrder: paintOrder,
            clipBehavior: clipBehavior
        )
        addAll(children)
    }

    // MARK: - Setup Parent Data

    /// **Dart Source:** `viewport.dart:1873-1878`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverLogicalContainerParentData) {
            child.parentData = SliverLogicalContainerParentData()
        }
    }

    // MARK: - Linked-list overrides for SliverLogicalContainerParentData

    /// Returns the next sibling of the given child using logical parent data.
    open override func childAfter(_ child: RenderSliver) -> RenderSliver? {
        let parentData = child.parentData as! SliverLogicalContainerParentData
        return parentData.nextSibling
    }

    /// Returns the previous sibling of the given child using logical parent data.
    open override func childBefore(_ child: RenderSliver) -> RenderSliver? {
        let parentData = child.parentData as! SliverLogicalContainerParentData
        return parentData.previousSibling
    }

    /// Inserts a child into the logical linked list.
    private func _insertIntoChildListLogical(
        _ child: RenderSliver, after: RenderSliver? = nil
    ) {
        let childParentData = child.parentData as! SliverLogicalContainerParentData
        childCount += 1
        assert(childCount > 0)
        if let after = after {
            let afterParentData = after.parentData as! SliverLogicalContainerParentData
            childParentData.nextSibling = afterParentData.nextSibling
            if let nextSibling = afterParentData.nextSibling {
                let nextParentData =
                    nextSibling.parentData as! SliverLogicalContainerParentData
                nextParentData.previousSibling = child
            }
            afterParentData.nextSibling = child
            childParentData.previousSibling = after
            if after === lastChild {
                lastChild = child
            }
        } else {
            childParentData.nextSibling = firstChild
            if let first = firstChild {
                let firstParentData =
                    first.parentData as! SliverLogicalContainerParentData
                firstParentData.previousSibling = child
            }
            firstChild = child
            lastChild = lastChild ?? child
        }
    }

    /// Removes a child from the logical linked list.
    private func _removeFromChildListLogical(_ child: RenderSliver) {
        let childParentData = child.parentData as! SliverLogicalContainerParentData
        if childParentData.previousSibling == nil {
            firstChild = childParentData.nextSibling
        } else {
            let previousParentData =
                childParentData.previousSibling!.parentData
                    as! SliverLogicalContainerParentData
            previousParentData.nextSibling = childParentData.nextSibling
        }
        if childParentData.nextSibling == nil {
            lastChild = childParentData.previousSibling
        } else {
            let nextParentData =
                childParentData.nextSibling!.parentData
                    as! SliverLogicalContainerParentData
            nextParentData.previousSibling = childParentData.previousSibling
        }
        childParentData.previousSibling = nil
        childParentData.nextSibling = nil
        childCount -= 1
    }

    open override func insert(_ child: RenderSliver, after: RenderSliver? = nil) {
        adoptChild(child)
        _insertIntoChildListLogical(child, after: after)
    }

    open override func remove(_ child: RenderSliver) {
        _removeFromChildListLogical(child)
        dropChild(child)
    }

    // MARK: - Intrinsics

    /// **Dart Source:** `viewport.dart:1881-1900`
    open override func debugThrowIfNotCheckingIntrinsics() -> Bool {
        // In the full implementation, this checks RenderObject.debugCheckingIntrinsics.
        // That static property is not yet migrated, so this is a simplified stub.
        return true
    }

    // MARK: - Layout

    // Out-of-band data computed during layout.
    private var _maxScrollExtent: Double = 0.0
    private var _shrinkWrapExtent: Double = 0.0
    private var _hasVisualOverflow: Bool = false

    /// **Dart Source:** `viewport.dart:1937-1986`
    open override func performLayout() {
        let constraints = self.boxConstraints
        if firstChild == nil {
            // Shrinkwrapping viewport only requires the cross axis to be bounded.
            let newSize: Size
            switch axis {
            case .vertical:
                newSize = Size(constraints.maxWidth, constraints.minHeight)
            case .horizontal:
                newSize = Size(constraints.minWidth, constraints.maxHeight)
            }
            size = newSize
            offset.applyViewportDimension(0.0)
            _maxScrollExtent = 0.0
            _shrinkWrapExtent = 0.0
            _hasVisualOverflow = false
            offset.applyContentDimensions(0.0, 0.0)
            return
        }

        let mainAxisExtent: Double
        let crossAxisExtent: Double
        switch axis {
        case .vertical:
            mainAxisExtent = constraints.maxHeight
            crossAxisExtent = constraints.maxWidth
        case .horizontal:
            mainAxisExtent = constraints.maxWidth
            crossAxisExtent = constraints.maxHeight
        }

        var correction: Double
        var effectiveExtent: Double = 0.0
        while true {
            correction = _attemptLayout(mainAxisExtent, crossAxisExtent, offset.pixels)
            if correction != 0.0 {
                offset.correctBy(correction)
            } else {
                switch axis {
                case .vertical:
                    effectiveExtent = constraints.constrainHeight(_shrinkWrapExtent)
                case .horizontal:
                    effectiveExtent = constraints.constrainWidth(_shrinkWrapExtent)
                }
                let didAcceptViewportDimension = offset.applyViewportDimension(effectiveExtent)
                let didAcceptContentDimension = offset.applyContentDimensions(
                    0.0,
                    max(0.0, _maxScrollExtent - effectiveExtent)
                )
                if didAcceptViewportDimension && didAcceptContentDimension {
                    break
                }
            }
        }
        switch axis {
        case .vertical:
            size = constraints.constrainDimensions(crossAxisExtent, effectiveExtent)
        case .horizontal:
            size = constraints.constrainDimensions(effectiveExtent, crossAxisExtent)
        }
    }

    /// **Dart Source:** `viewport.dart:1988-2023`
    private func _attemptLayout(
        _ mainAxisExtent: Double,
        _ crossAxisExtent: Double,
        _ correctedOffset: Double
    ) -> Double {
        assert(!mainAxisExtent.isNaN)
        assert(mainAxisExtent >= 0.0)
        assert(crossAxisExtent.isFinite)
        assert(crossAxisExtent >= 0.0)
        assert(correctedOffset.isFinite)
        _maxScrollExtent = 0.0
        _shrinkWrapExtent = 0.0
        _hasVisualOverflow = correctedOffset < 0.0
        _calculatedCacheExtent = {
            switch cacheExtentStyle {
            case .pixel: return cacheExtent
            case .viewport: return mainAxisExtent * _cacheExtent
            }
        }()

        return layoutChildSequence(
            child: firstChild,
            scrollOffset: max(0.0, correctedOffset),
            overlap: min(0.0, correctedOffset),
            layoutOffset: max(0.0, -correctedOffset),
            remainingPaintExtent: mainAxisExtent + min(0.0, correctedOffset),
            mainAxisExtent: mainAxisExtent,
            crossAxisExtent: crossAxisExtent,
            growthDirection: .forward,
            advance: childAfter,
            remainingCacheExtent: mainAxisExtent + 2 * _calculatedCacheExtent!,
            cacheOrigin: -_calculatedCacheExtent!
        )
    }

    // MARK: - Abstract Overrides

    /// **Dart Source:** `viewport.dart:2026`
    open override var hasVisualOverflow: Bool { _hasVisualOverflow }

    /// **Dart Source:** `viewport.dart:2028-2036`
    open override func updateOutOfBandData(
        _ growthDirection: GrowthDirection,
        _ childLayoutGeometry: SliverGeometry
    ) {
        assert(growthDirection == .forward)
        _maxScrollExtent += childLayoutGeometry.scrollExtent
        if childLayoutGeometry.hasVisualOverflow {
            _hasVisualOverflow = true
        }
        _shrinkWrapExtent += childLayoutGeometry.maxPaintExtent
    }

    /// **Dart Source:** `viewport.dart:2038-2047`
    open override func updateChildLayoutOffset(
        _ child: RenderSliver,
        _ layoutOffset: Double,
        _ growthDirection: GrowthDirection
    ) {
        assert(growthDirection == .forward)
        let childParentData = child.parentData! as! SliverLogicalParentData
        childParentData.layoutOffset = layoutOffset
    }

    /// **Dart Source:** `viewport.dart:2049-2057`
    open override func paintOffsetOf(_ child: RenderSliver) -> Offset {
        let childParentData = child.parentData! as! SliverLogicalParentData
        return computeAbsolutePaintOffset(
            child,
            childParentData.layoutOffset!,
            .forward
        )
    }

    /// **Dart Source:** `viewport.dart:2059-2070`
    open override func scrollOffsetOf(_ child: RenderSliver, _ scrollOffsetWithinChild: Double) -> Double {
        assert(child.parent === self)
        assert(child.sliverConstraints.growthDirection == .forward)
        var scrollOffsetToChild: Double = 0.0
        var current: RenderSliver? = firstChild
        while current !== child {
            scrollOffsetToChild += current!.geometry!.scrollExtent
            current = childAfter(current!)
        }
        return scrollOffsetToChild + scrollOffsetWithinChild
    }

    /// **Dart Source:** `viewport.dart:2072-2083`
    open override func maxScrollObstructionExtentBefore(_ child: RenderSliver) -> Double {
        assert(child.parent === self)
        assert(child.sliverConstraints.growthDirection == .forward)
        var pinnedExtent: Double = 0.0
        var current: RenderSliver? = firstChild
        while current !== child {
            pinnedExtent += current!.geometry!.maxScrollObstructionExtent
            current = childAfter(current!)
        }
        return pinnedExtent
    }

    /// **Dart Source:** `viewport.dart:2085-2090`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        // Hit test logic relies on this always providing an invertible matrix.
        let offset = paintOffsetOf(child as! RenderSliver)
        transform = Matrix4.translationValues(offset.dx, offset.dy, 0) * transform
    }

    /// **Dart Source:** `viewport.dart:2092-2104`
    open override func computeChildMainAxisPosition(
        _ child: RenderSliver,
        _ parentMainAxisPosition: Double
    ) -> Double {
        assert(hasSize)
        let layoutOffset = (child.parentData! as! SliverLogicalParentData).layoutOffset!
        switch applyGrowthDirectionToAxisDirection(
            child.sliverConstraints.axisDirection,
            child.sliverConstraints.growthDirection
        ) {
        case .down, .right:
            return parentMainAxisPosition - layoutOffset
        case .up:
            return size.height - parentMainAxisPosition - layoutOffset
        case .left:
            return size.width - parentMainAxisPosition - layoutOffset
        }
    }

    /// **Dart Source:** `viewport.dart:2107`
    open override var indexOfFirstChild: Int { 0 }

    /// **Dart Source:** `viewport.dart:2110`
    open override func labelForChild(_ index: Int) -> String {
        "child \(index)"
    }
}

// MARK: - SliverContainerRenderObjectHost Conformance

/// Lets `MultiChildRenderObjectElement` manage a viewport's sliver children
/// (the widget layer's `_FullViewport` / `_ShrinkWrapViewport`).
extension RenderViewportBase: SliverContainerRenderObjectHost {}
