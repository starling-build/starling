// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Sliver persistent header types.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/sliver_persistent_header.dart`

import FlutterSwiftBridge

// MARK: - Helper: _trim

/// Trims the specified edges of the given `Rect`, so that they do not
/// exceed the given values.
///
/// **Dart Source:** `sliver_persistent_header.dart:23-29`
private func _trim(
    _ original: Rect?,
    top: Double = -.infinity,
    right: Double = .infinity,
    bottom: Double = .infinity,
    left: Double = -.infinity
) -> Rect? {
    original?.intersect(Rect.fromLTRB(left, top, right, bottom))
}

// MARK: - OverScrollHeaderStretchConfiguration

/// Specifies how a stretched header is to trigger an `AsyncCallback`.
///
/// See also:
///
///  - `SliverAppBar`, which creates a header that can be stretched into an
///    overscroll area and trigger a callback function.
///
/// **Dart Source:** `sliver_persistent_header.dart:37-48`
public class OverScrollHeaderStretchConfiguration: @unchecked Sendable {
    /// Creates an object that specifies how a stretched header may activate an
    /// `AsyncCallback`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:40`
    public init(
        stretchTriggerOffset: Double = 100.0,
        onStretchTrigger: (@Sendable () async -> Void)? = nil
    ) {
        self.stretchTriggerOffset = stretchTriggerOffset
        self.onStretchTrigger = onStretchTrigger
    }

    /// The offset of overscroll required to trigger the `onStretchTrigger`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:43`
    public let stretchTriggerOffset: Double

    /// The callback function to be executed when a user over-scrolls to the
    /// offset specified by `stretchTriggerOffset`.
    ///
    /// DIFFERENCE FROM DART: Callback is `@Sendable` to satisfy Swift 6 concurrency.
    /// REASON: Swift 6 strict concurrency requires `@Sendable` for closures used across isolation boundaries.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:47`
    public let onStretchTrigger: (@Sendable () async -> Void)?
}

// MARK: - PersistentHeaderShowOnScreenConfiguration

/// Specifies how a pinned header or a floating header should react to
/// `RenderObject.showOnScreen` calls.
///
/// **Dart Source:** `sliver_persistent_header.dart:55-102`
public struct PersistentHeaderShowOnScreenConfiguration {
    /// Creates an object that specifies how a pinned or floating persistent header
    /// should behave in response to `showOnScreen` calls.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:58-61`
    public init(
        minShowOnScreenExtent: Double = -.infinity,
        maxShowOnScreenExtent: Double = .infinity
    ) {
        assert(minShowOnScreenExtent <= maxShowOnScreenExtent)
        self.minShowOnScreenExtent = minShowOnScreenExtent
        self.maxShowOnScreenExtent = maxShowOnScreenExtent
    }

    /// The smallest the floating header can expand to in the main axis direction,
    /// in response to a `showOnScreen` call, in addition to its
    /// `RenderSliverPersistentHeader.minExtent`.
    ///
    /// Defaults to `Double.negativeInfinity`, must be less than or equal to
    /// `maxShowOnScreenExtent`. Has no effect unless the persistent header is a
    /// floating header.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:81`
    public let minShowOnScreenExtent: Double

    /// The biggest the floating header can expand to in the main axis direction,
    /// in response to a `showOnScreen` call, in addition to its
    /// `RenderSliverPersistentHeader.maxExtent`.
    ///
    /// Defaults to `Double.infinity`, must be greater than or equal to
    /// `minShowOnScreenExtent`. Has no effect unless the persistent header is a
    /// floating header.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:101`
    public let maxShowOnScreenExtent: Double
}

// MARK: - FloatingHeaderSnapConfiguration

/// Specifies how a floating header is to be "snapped" (animated) into or out
/// of view.
///
/// See also:
///
///  - `RenderSliverFloatingPersistentHeader.maybeStartSnapAnimation` and
///    `RenderSliverFloatingPersistentHeader.maybeStopSnapAnimation`, which
///    start or stop the floating header's animation.
///  - `SliverAppBar`, which creates a header that can be pinned, floating,
///    and snapped into view via the corresponding parameters.
///
/// **Dart Source:** `sliver_persistent_header.dart:485-498`
public class FloatingHeaderSnapConfiguration {
    /// Creates an object that specifies how a floating header is to be "snapped"
    /// (animated) into or out of view.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:488-491`
    public init(
        curve: any Curve = Curves.ease,
        duration: Duration = .milliseconds(300)
    ) {
        self.curve = curve
        self.duration = duration
    }

    /// The snap animation curve.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:494`
    public let curve: any Curve

    /// The snap animation's duration.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:497`
    public let duration: Duration
}

// MARK: - RenderSliverPersistentHeader

/// A base class for slivers that have a `RenderBox` child which scrolls
/// normally, except that when it hits the leading edge (typically the top) of
/// the viewport, it shrinks to a minimum size (`minExtent`).
///
/// This class primarily provides helpers for managing the child, in particular:
///
///  - `layoutChild`, which applies min and max extents and a scroll offset to
///    lay out the child. This is normally called from `performLayout`.
///
///  - `childExtent`, to convert the child's box layout dimensions to the sliver
///    geometry model.
///
///  - hit testing, painting, and other details of the sliver protocol.
///
/// Subclasses must implement `performLayout`, `minExtent`, and `maxExtent`, and
/// typically also will implement `updateChild`.
///
/// DIFFERENCE FROM DART: In Dart this extends `RenderSliver` with
/// `RenderObjectWithChildMixin<RenderBox>` and `RenderSliverHelpers` mixins.
/// In Swift, single-child management is integrated directly (same pattern as
/// `RenderSliverSingleBoxAdapter`), and `RenderSliverHelpers` is adopted as a
/// protocol conformance.
/// REASON: Swift does not support Dart-style mixins.
///
/// **Dart Source:** `sliver_persistent_header.dart:120-345`
open class RenderSliverPersistentHeader: RenderSliver, RenderSliverHelpers {

    // MARK: - Initializer

    /// Creates a sliver that changes its size when scrolled to the start of the
    /// viewport.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:126-128`
    public init(
        child: RenderBox? = nil,
        stretchConfiguration: OverScrollHeaderStretchConfiguration? = nil
    ) {
        self.stretchConfiguration = stretchConfiguration
        super.init()
        self.child = child
    }

    // MARK: - Child Management (RenderObjectWithChildMixin pattern)

    /// The single child of this render object.
    ///
    /// DIFFERENCE FROM DART: In Dart, `RenderObjectWithChildMixin<RenderBox>` is
    /// used. In Swift, the child property is implemented directly.
    /// REASON: Swift does not support generic mixins.
    ///
    /// **Dart Source:** via `RenderObjectWithChildMixin`
    public var child: RenderBox? {
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
    private var _child: RenderBox?

    /// **Dart Source:** `RenderObjectWithChildMixin.visitChildren`
    open override func visitChildren(_ visitor: RenderObjectVisitor) {
        if let child = _child {
            visitor(child)
        }
    }

    // MARK: - Parent Data

    /// Sets up `SliverPhysicalParentData` for the given child.
    ///
    /// **Dart Source:** via standard sliver parent data setup
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverPhysicalParentData) {
            child.parentData = SliverPhysicalParentData()
        }
    }

    // MARK: - Properties

    /// Backing storage for tracking the last stretch offset.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:130`
    private var _lastStretchOffset: Double = 0.0

    /// The biggest that this render object can become, in the main axis direction.
    ///
    /// This value should not be based on the child. If it changes, call
    /// `markNeedsLayout`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:137`
    open var maxExtent: Double {
        fatalError("Subclasses of RenderSliverPersistentHeader must override maxExtent")
    }

    /// The smallest that this render object can become, in the main axis direction.
    ///
    /// If this is based on the intrinsic dimensions of the child, the child
    /// should be measured during `updateChild` and the value cached and returned
    /// here.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:145`
    open var minExtent: Double {
        fatalError("Subclasses of RenderSliverPersistentHeader must override minExtent")
    }

    /// The dimension of the child in the main axis.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:148-157`
    public var childExtent: Double {
        guard let child = child else {
            return 0.0
        }
        assert(child.hasSize)
        switch sliverConstraints.axis {
        case .vertical:
            return child.size.height
        case .horizontal:
            return child.size.width
        }
    }

    /// Whether the child needs to be updated before the next layout.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:159`
    private var _needsUpdateChild: Bool = true

    /// The most recent `shrinkOffset` passed to `updateChild`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:162-163`
    public var lastShrinkOffset: Double { _lastShrinkOffset }
    private var _lastShrinkOffset: Double = 0.0

    /// The most recent `overlapsContent` passed to `updateChild`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:166-167`
    public var lastOverlapsContent: Bool { _lastOverlapsContent }
    private var _lastOverlapsContent: Bool = false

    /// Defines the parameters used to execute an `AsyncCallback` when a
    /// stretching header over-scrolls.
    ///
    /// If `stretchConfiguration` is nil then callback is not triggered.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:178`
    public var stretchConfiguration: OverScrollHeaderStretchConfiguration?

    // MARK: - Update Child

    /// Update the child render object if necessary.
    ///
    /// Called before the first layout, any time `markNeedsLayout` is called, and
    /// any time the scroll offset changes. The `shrinkOffset` is the difference
    /// between the `maxExtent` and the current size.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:201`
    open func updateChild(_ shrinkOffset: Double, _ overlapsContent: Bool) {}

    // MARK: - Mark Needs Layout

    /// Marks this render object as needing layout, and flags `_needsUpdateChild`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:203-209`
    open override func markNeedsLayout() {
        _needsUpdateChild = true
        super.markNeedsLayout()
    }

    // MARK: - Layout Child

    /// Lays out the `child`.
    ///
    /// This is called by `performLayout`. It applies the given `scrollOffset`
    /// (which need not match the offset given by the constraints) and the
    /// `maxExtent` (which need not match the value returned by the `maxExtent`
    /// getter).
    ///
    /// The `overlapsContent` argument is passed to `updateChild`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:220-262`
    public func layoutChild(_ scrollOffset: Double, _ maxExtent: Double, overlapsContent: Bool = false) {
        let shrinkOffset = min(scrollOffset, maxExtent)
        if _needsUpdateChild
            || _lastShrinkOffset != shrinkOffset
            || _lastOverlapsContent != overlapsContent
        {
            invokeLayoutCallback { [self] (_: SliverConstraints) in
                updateChild(shrinkOffset, overlapsContent)
            }
            _lastShrinkOffset = shrinkOffset
            _lastOverlapsContent = overlapsContent
            _needsUpdateChild = false
        }
        assert(minExtent <= maxExtent,
            "The maxExtent for this \(type(of: self)) is less than its minExtent.")
        var stretchOffset = 0.0
        if stretchConfiguration != nil && sliverConstraints.scrollOffset == 0.0 {
            stretchOffset += Swift.abs(sliverConstraints.overlap)
        }

        child?.layout(
            sliverConstraints.asBoxConstraints(
                maxExtent: max(minExtent, maxExtent - shrinkOffset) + stretchOffset
            ),
            parentUsesSize: true
        )

        if stretchConfiguration != nil
            && stretchConfiguration!.onStretchTrigger != nil
            && stretchOffset >= stretchConfiguration!.stretchTriggerOffset
            && _lastStretchOffset <= stretchConfiguration!.stretchTriggerOffset
        {
            _fireStretchTrigger(stretchConfiguration!.onStretchTrigger!)
        }
        _lastStretchOffset = stretchOffset
    }

    /// Calls the given callback during layout.
    ///
    /// This is a simplified version that just invokes the callback with the
    /// current sliver constraints.
    ///
    /// **Dart Source:** via `RenderObject.invokeLayoutCallback`
    public func invokeLayoutCallback(_ callback: (SliverConstraints) -> Void) {
        callback(sliverConstraints)
    }

    /// Fires the stretch trigger callback asynchronously.
    ///
    /// DIFFERENCE FROM DART: In Dart, calling an async function without `await`
    /// creates a fire-and-forget Future. In Swift 6, we must use a `Task` and
    /// handle `@Sendable` requirements.
    /// REASON: Swift 6 strict concurrency requires explicit handling of Sendable.
    private func _fireStretchTrigger(_ callback: @escaping @Sendable () async -> Void) {
        Task { await callback() }
    }

    // MARK: - Child Main Axis Position

    /// Returns the distance from the leading visible edge of the sliver to the
    /// side of the child closest to that edge, in the scroll axis direction.
    ///
    /// This must be implemented by `RenderSliverPersistentHeader` subclasses.
    ///
    /// If there is no child, this should return 0.0.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:285`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        return super.childMainAxisPosition(child)
    }

    // MARK: - Hit Testing

    /// **Dart Source:** `sliver_persistent_header.dart:287-303`
    open override func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        assert(geometry!.hitTestExtent > 0.0)
        if let child = child {
            return hitTestBoxChild(
                BoxHitTestResult(wrapping: result),
                child,
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition
            )
        }
        return false
    }

    // MARK: - Paint Transform

    /// **Dart Source:** `sliver_persistent_header.dart:305-309`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        assert(child === self.child)
        applyPaintTransformForBoxChild(child as! RenderBox, &transform)
    }

    // MARK: - Paint

    /// **Dart Source:** `sliver_persistent_header.dart:311-331`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        guard let child = child, geometry!.visible else { return }
        var adjustedOffset = offset
        switch applyGrowthDirectionToAxisDirection(
            sliverConstraints.axisDirection,
            sliverConstraints.growthDirection
        ) {
        case .up:
            adjustedOffset = adjustedOffset + Offset(
                0.0,
                geometry!.paintExtent - childMainAxisPosition(child) - childExtent
            )
        case .left:
            adjustedOffset = adjustedOffset + Offset(
                geometry!.paintExtent - childMainAxisPosition(child) - childExtent,
                0.0
            )
        case .right:
            adjustedOffset = adjustedOffset + Offset(childMainAxisPosition(child), 0.0)
        case .down:
            adjustedOffset = adjustedOffset + Offset(0.0, childMainAxisPosition(child))
        }
        context.paintChild(child, adjustedOffset)
    }

    // MARK: - Debug

    /// **Dart Source:** `sliver_persistent_header.dart:339-344`
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DoubleProperty("maxExtent", maxExtent))
        properties.add(DoubleProperty("child position", child != nil ? childMainAxisPosition(child!) : 0.0))
    }
}

// MARK: - RenderSliverScrollingPersistentHeader

/// A sliver with a `RenderBox` child which scrolls normally, except that when
/// it hits the leading edge (typically the top) of the viewport, it shrinks to
/// a minimum size before continuing to scroll.
///
/// This sliver makes no effort to avoid overlapping other content.
///
/// **Dart Source:** `sliver_persistent_header.dart:352-397`
open class RenderSliverScrollingPersistentHeader: RenderSliverPersistentHeader {

    /// Creates a sliver that shrinks when it hits the start of the viewport, then
    /// scrolls off.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:355`
    public override init(
        child: RenderBox? = nil,
        stretchConfiguration: OverScrollHeaderStretchConfiguration? = nil
    ) {
        super.init(child: child, stretchConfiguration: stretchConfiguration)
    }

    // Distance from our leading edge to the child's leading edge, in the axis
    // direction. Negative if we're scrolled off the top.
    private var _childPosition: Double?

    /// Updates `geometry`, and returns the new value for `childMainAxisPosition`.
    ///
    /// This is used by `performLayout`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:365-383`
    open func updateGeometry() -> Double {
        var stretchOffset = 0.0
        if stretchConfiguration != nil {
            stretchOffset += Swift.abs(sliverConstraints.overlap)
        }
        let maxExtent = self.maxExtent
        let paintExtent = maxExtent - sliverConstraints.scrollOffset
        let cacheExtent = calculateCacheOffset(sliverConstraints, from: 0.0, to: maxExtent)

        geometry = SliverGeometry(
            scrollExtent: maxExtent,
            paintExtent: clampDouble(paintExtent, 0.0, sliverConstraints.remainingPaintExtent),
            paintOrigin: min(sliverConstraints.overlap, 0.0),
            maxPaintExtent: maxExtent + stretchOffset,
            hasVisualOverflow: true,  // Conservatively say we do have overflow to avoid complexity.
            cacheExtent: cacheExtent
        )
        return stretchOffset > 0 ? 0.0 : min(0.0, paintExtent - childExtent)
    }

    /// **Dart Source:** `sliver_persistent_header.dart:385-389`
    open override func performLayout() {
        layoutChild(sliverConstraints.scrollOffset, maxExtent)
        _childPosition = updateGeometry()
    }

    /// **Dart Source:** `sliver_persistent_header.dart:391-396`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        assert(child === self.child)
        assert(_childPosition != nil)
        return _childPosition!
    }
}

// MARK: - RenderSliverPinnedPersistentHeader

/// A sliver with a `RenderBox` child which never scrolls off the viewport in
/// the positive scroll direction, and which first scrolls on at a full size but
/// then shrinks as the viewport continues to scroll.
///
/// This sliver avoids overlapping other earlier slivers where possible.
///
/// **Dart Source:** `sliver_persistent_header.dart:404-473`
open class RenderSliverPinnedPersistentHeader: RenderSliverPersistentHeader {

    /// Creates a sliver that shrinks when it hits the start of the viewport, then
    /// stays pinned there.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:407-411`
    public init(
        child: RenderBox? = nil,
        stretchConfiguration: OverScrollHeaderStretchConfiguration? = nil,
        showOnScreenConfiguration: PersistentHeaderShowOnScreenConfiguration? = PersistentHeaderShowOnScreenConfiguration()
    ) {
        self.showOnScreenConfiguration = showOnScreenConfiguration
        super.init(child: child, stretchConfiguration: stretchConfiguration)
    }

    /// Specifies the persistent header's behavior when `showOnScreen` is called.
    ///
    /// If set to nil, the persistent header will delegate the `showOnScreen` call
    /// to its parent `RenderObject`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:417`
    public var showOnScreenConfiguration: PersistentHeaderShowOnScreenConfiguration?

    /// **Dart Source:** `sliver_persistent_header.dart:419-445`
    open override func performLayout() {
        let constraints = self.sliverConstraints
        let maxExtent = self.maxExtent
        let overlapsContent = constraints.overlap > 0.0
        layoutChild(constraints.scrollOffset, maxExtent, overlapsContent: overlapsContent)
        let effectiveRemainingPaintExtent = max(
            0,
            constraints.remainingPaintExtent - constraints.overlap
        )
        let layoutExtent = clampDouble(
            maxExtent - constraints.scrollOffset,
            0.0,
            effectiveRemainingPaintExtent
        )
        let stretchOffset = stretchConfiguration != nil ? Swift.abs(constraints.overlap) : 0.0
        geometry = SliverGeometry(
            scrollExtent: maxExtent,
            paintExtent: min(childExtent, effectiveRemainingPaintExtent),
            paintOrigin: constraints.overlap,
            layoutExtent: layoutExtent,
            maxPaintExtent: maxExtent + stretchOffset,
            maxScrollObstructionExtent: minExtent,
            hasVisualOverflow: true,  // Conservatively say we do have overflow to avoid complexity.
            cacheExtent: layoutExtent > 0.0 ? -constraints.cacheOrigin + layoutExtent : layoutExtent
        )
    }

    /// **Dart Source:** `sliver_persistent_header.dart:448`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double { 0.0 }

    /// **Dart Source:** `sliver_persistent_header.dart:450-472`
    ///
    /// DIFFERENCE FROM DART: `showOnScreen` is not yet available on the base
    /// `RenderObject` in this Swift port. This method is provided as a stub that
    /// can be connected once the full `showOnScreen` infrastructure is migrated.
    /// REASON: The `showOnScreen` method depends on viewport infrastructure not
    /// yet ported.
    open func showOnScreen(
        descendant: RenderObject? = nil,
        rect: Rect? = nil,
        duration: Duration = .zero,
        curve: any Curve = Curves.ease
    ) {
        let localBounds: Rect? = if let descendant = descendant {
            MatrixUtils.transformRect(descendant.getTransformTo(self), rect ?? descendant.paintBounds)
        } else {
            rect
        }

        let newRect: Rect?
        switch applyGrowthDirectionToAxisDirection(
            sliverConstraints.axisDirection,
            sliverConstraints.growthDirection
        ) {
        case .up:
            newRect = _trim(localBounds, bottom: childExtent)
        case .left:
            newRect = _trim(localBounds, right: childExtent)
        case .right:
            newRect = _trim(localBounds, left: 0)
        case .down:
            newRect = _trim(localBounds, top: 0)
        }

        // In the full Dart implementation, this calls:
        // super.showOnScreen(descendant: self, rect: newRect, duration: duration, curve: curve)
        // This will be connected once the showOnScreen infrastructure is available.
        _ = newRect
    }
}

// MARK: - RenderSliverFloatingPersistentHeader

/// A sliver with a `RenderBox` child which shrinks and scrolls like a
/// `RenderSliverScrollingPersistentHeader`, but immediately comes back when the
/// user scrolls in the reverse direction.
///
/// See also:
///
///  - `RenderSliverFloatingPinnedPersistentHeader`, which is similar but sticks
///    to the start of the viewport rather than scrolling off.
///
/// **Dart Source:** `sliver_persistent_header.dart:508-787`
open class RenderSliverFloatingPersistentHeader: RenderSliverPersistentHeader {

    /// Creates a sliver that shrinks when it hits the start of the viewport, then
    /// scrolls off, and comes back immediately when the user reverses the scroll
    /// direction.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:512-518`
    public init(
        child: RenderBox? = nil,
        vsync: TickerProvider? = nil,
        snapConfiguration: FloatingHeaderSnapConfiguration? = nil,
        stretchConfiguration: OverScrollHeaderStretchConfiguration? = nil,
        showOnScreenConfiguration: PersistentHeaderShowOnScreenConfiguration?
    ) {
        self._vsync = vsync
        self.snapConfiguration = snapConfiguration
        self.showOnScreenConfiguration = showOnScreenConfiguration
        super.init(child: child, stretchConfiguration: stretchConfiguration)
    }

    /// **Dart Source:** `sliver_persistent_header.dart:520`
    private var _controller: AnimationController?

    /// **Dart Source:** `sliver_persistent_header.dart:521`
    private var _animation: Animation<Double>?

    /// **Dart Source:** `sliver_persistent_header.dart:522`
    private var _lastActualScrollOffset: Double?

    /// **Dart Source:** `sliver_persistent_header.dart:523`
    internal var _effectiveScrollOffset: Double?

    // Important for pointer scrolling, which does not have the same concept of
    // a hold and release scroll movement, like dragging.
    // This keeps track of the last ScrollDirection when scrolling started.
    /// **Dart Source:** `sliver_persistent_header.dart:527`
    private var _lastStartedScrollDirection: ScrollDirection?

    // Distance from our leading edge to the child's leading edge, in the axis
    // direction. Negative if we're scrolled off the top.
    /// **Dart Source:** `sliver_persistent_header.dart:531`
    private var _childPosition: Double?

    // MARK: - Detach

    /// **Dart Source:** `sliver_persistent_header.dart:533-538`
    open override func detach() {
        _controller?.dispose()
        _controller = nil  // lazily recreated if we're reattached.
        super.detach()
    }

    // MARK: - Vsync

    /// A `TickerProvider` to use when animating the scroll position.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:541-554`
    public var vsync: TickerProvider? {
        get { _vsync }
        set {
            _vsync = newValue
            if newValue == nil {
                _controller?.dispose()
                _controller = nil
            } else {
                _controller?.resync(newValue!)
            }
        }
    }
    private var _vsync: TickerProvider?

    /// Defines the parameters used to snap (animate) the floating header in and
    /// out of view.
    ///
    /// If `snapConfiguration` is nil then the floating header does not snap.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:568`
    public var snapConfiguration: FloatingHeaderSnapConfiguration?

    /// Specifies how the persistent header reacts to `showOnScreen` calls.
    ///
    /// If set to nil, the persistent header will delegate the `showOnScreen` call
    /// to its parent `RenderObject`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:574`
    public var showOnScreenConfiguration: PersistentHeaderShowOnScreenConfiguration?

    // MARK: - Update Geometry

    /// Updates `geometry`, and returns the new value for `childMainAxisPosition`.
    ///
    /// This is used by `performLayout`.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:580-597`
    open func updateGeometry() -> Double {
        var stretchOffset = 0.0
        if stretchConfiguration != nil {
            stretchOffset += Swift.abs(sliverConstraints.overlap)
        }
        let maxExtent = self.maxExtent
        let paintExtent = maxExtent - _effectiveScrollOffset!
        let layoutExtent = maxExtent - sliverConstraints.scrollOffset
        geometry = SliverGeometry(
            scrollExtent: maxExtent,
            paintExtent: clampDouble(paintExtent, 0.0, sliverConstraints.remainingPaintExtent),
            paintOrigin: min(sliverConstraints.overlap, 0.0),
            layoutExtent: clampDouble(layoutExtent, 0.0, sliverConstraints.remainingPaintExtent),
            maxPaintExtent: maxExtent + stretchOffset,
            hasVisualOverflow: true  // Conservatively say we do have overflow to avoid complexity.
        )
        return stretchOffset > 0 ? 0.0 : min(0.0, paintExtent - childExtent)
    }

    // MARK: - Animation

    /// **Dart Source:** `sliver_persistent_header.dart:599-614`
    private func _updateAnimation(_ duration: Duration, _ endValue: Double, _ curve: any Curve) {
        assert(vsync != nil, "vsync must not be nil if the floating header changes size animatedly.")

        if _controller == nil {
            _controller = AnimationController(duration: duration, vsync: vsync!)
            _controller!.addListener { [weak self] in
                guard let self = self else { return }
                if self._effectiveScrollOffset == self._animation?.value {
                    return
                }
                self._effectiveScrollOffset = self._animation?.value
                self.markNeedsLayout()
            }
        }
        let effectiveController = _controller!

        _animation = effectiveController.drive(
            DoubleTween(begin: _effectiveScrollOffset!, end: endValue)
                .chain(CurveTween(curve: curve))
        )
    }

    /// Update the last known ScrollDirection when scrolling began.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:618-619`
    public func updateScrollStartDirection(_ direction: ScrollDirection) {
        _lastStartedScrollDirection = direction
    }

    /// If the header isn't already fully exposed, then scroll it into view.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:622-641`
    public func maybeStartSnapAnimation(_ direction: ScrollDirection) {
        guard let snap = snapConfiguration else {
            return
        }
        if direction == .forward && _effectiveScrollOffset! <= 0.0 {
            return
        }
        if direction == .reverse && _effectiveScrollOffset! >= maxExtent {
            return
        }

        _updateAnimation(
            snap.duration,
            direction == .forward ? 0.0 : maxExtent,
            snap.curve
        )
        _controller?.forward(from: 0.0)
    }

    /// If a header snap animation or a `showOnScreen` expand animation is underway
    /// then stop it.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:645-647`
    public func maybeStopSnapAnimation(_ direction: ScrollDirection) {
        _controller?.stop()
    }

    // MARK: - Perform Layout

    /// **Dart Source:** `sliver_persistent_header.dart:649-689`
    open override func performLayout() {
        let constraints = self.sliverConstraints
        let maxExtent = self.maxExtent
        if _lastActualScrollOffset != nil  // We've laid out at least once to get an initial position
            && ((constraints.scrollOffset < _lastActualScrollOffset!)  // we are scrolling back, so should reveal
                || (_effectiveScrollOffset! < maxExtent))  // some part is visible, so should shrink or reveal
        {
            var delta = _lastActualScrollOffset! - constraints.scrollOffset

            let allowFloatingExpansion =
                constraints.userScrollDirection == .forward
                || (_lastStartedScrollDirection != nil
                    && _lastStartedScrollDirection == .forward)
            if allowFloatingExpansion {
                if _effectiveScrollOffset! > maxExtent {
                    // We're scrolled off-screen, but should reveal, so pretend we're just at the limit.
                    _effectiveScrollOffset = maxExtent
                }
            } else {
                if delta > 0.0 {
                    // Disallow the expansion. (But allow shrinking, i.e. delta < 0.0 is fine.)
                    delta = 0.0
                }
            }
            _effectiveScrollOffset = clampDouble(
                _effectiveScrollOffset! - delta,
                0.0,
                constraints.scrollOffset
            )
        } else {
            _effectiveScrollOffset = constraints.scrollOffset
        }
        let overlapsContent = _effectiveScrollOffset! < constraints.scrollOffset

        layoutChild(_effectiveScrollOffset!, maxExtent, overlapsContent: overlapsContent)
        _childPosition = updateGeometry()
        _lastActualScrollOffset = constraints.scrollOffset
    }

    // MARK: - Show On Screen

    /// **Dart Source:** `sliver_persistent_header.dart:691-774`
    ///
    /// DIFFERENCE FROM DART: `showOnScreen` is not yet available on the base
    /// `RenderObject` in this Swift port. This method is provided with the core
    /// logic and will be fully connected once the viewport infrastructure is migrated.
    /// REASON: The `showOnScreen` method depends on viewport infrastructure not
    /// yet ported.
    open func showOnScreen(
        descendant: RenderObject? = nil,
        rect: Rect? = nil,
        duration: Duration = .zero,
        curve: any Curve = Curves.ease
    ) {
        guard let showOnScreen = showOnScreenConfiguration else {
            // In full implementation: super.showOnScreen(descendant: descendant, rect: rect, duration: duration, curve: curve)
            return
        }

        assert(child != nil || descendant == nil)

        let childBounds: Rect? = if let descendant = descendant {
            MatrixUtils.transformRect(
                descendant.getTransformTo(child),
                rect ?? descendant.paintBounds
            )
        } else {
            rect
        }

        var targetExtent: Double
        var targetRect: Rect?
        switch applyGrowthDirectionToAxisDirection(
            sliverConstraints.axisDirection,
            sliverConstraints.growthDirection
        ) {
        case .up:
            targetExtent = childExtent - (childBounds?.top ?? 0)
            targetRect = _trim(childBounds, bottom: childExtent)
        case .right:
            targetExtent = childBounds?.right ?? childExtent
            targetRect = _trim(childBounds, left: 0)
        case .down:
            targetExtent = childBounds?.bottom ?? childExtent
            targetRect = _trim(childBounds, top: 0)
        case .left:
            targetExtent = childExtent - (childBounds?.left ?? 0)
            targetRect = _trim(childBounds, right: childExtent)
        }

        // A stretch header can have a bigger childExtent than maxExtent.
        let effectiveMaxExtent = max(childExtent, maxExtent)

        targetExtent = clampDouble(
            clampDouble(
                targetExtent,
                showOnScreen.minShowOnScreenExtent,
                showOnScreen.maxShowOnScreenExtent
            ),
            // Clamp the value back to the valid range after applying additional
            // constraints. Contracting is not allowed.
            childExtent,
            effectiveMaxExtent
        )

        // Expands the header if needed, with animation.
        if targetExtent > childExtent && _controller?.status != .forward {
            let targetScrollOffset = maxExtent - targetExtent
            assert(
                vsync != nil,
                "vsync must not be nil if the floating header changes size animatedly."
            )
            _updateAnimation(duration, targetScrollOffset, curve)
            _controller?.forward(from: 0.0)
        }

        // In the full Dart implementation, this calls:
        // super.showOnScreen(descendant: descendant == nil ? self : child, rect: targetRect, duration: duration, curve: curve)
        _ = targetRect
    }

    // MARK: - Child Main Axis Position

    /// **Dart Source:** `sliver_persistent_header.dart:776-780`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        assert(child === self.child)
        return _childPosition ?? 0.0
    }

    // MARK: - Debug

    /// **Dart Source:** `sliver_persistent_header.dart:782-787`
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        properties.add(DoubleProperty("effective scroll offset", _effectiveScrollOffset))
    }
}

// MARK: - RenderSliverFloatingPinnedPersistentHeader

/// A sliver with a `RenderBox` child which shrinks and then remains pinned to
/// the start of the viewport like a `RenderSliverPinnedPersistentHeader`, but
/// immediately grows when the user scrolls in the reverse direction.
///
/// See also:
///
///  - `RenderSliverFloatingPersistentHeader`, which is similar but scrolls off
///    the top rather than sticking to it.
///
/// **Dart Source:** `sliver_persistent_header.dart:797-836`
open class RenderSliverFloatingPinnedPersistentHeader: RenderSliverFloatingPersistentHeader {

    /// Creates a sliver that shrinks when it hits the start of the viewport, then
    /// stays pinned there, and grows immediately when the user reverses the
    /// scroll direction.
    ///
    /// **Dart Source:** `sliver_persistent_header.dart:802-808`
    public override init(
        child: RenderBox? = nil,
        vsync: TickerProvider? = nil,
        snapConfiguration: FloatingHeaderSnapConfiguration? = nil,
        stretchConfiguration: OverScrollHeaderStretchConfiguration? = nil,
        showOnScreenConfiguration: PersistentHeaderShowOnScreenConfiguration?
    ) {
        super.init(
            child: child,
            vsync: vsync,
            snapConfiguration: snapConfiguration,
            stretchConfiguration: stretchConfiguration,
            showOnScreenConfiguration: showOnScreenConfiguration
        )
    }

    /// **Dart Source:** `sliver_persistent_header.dart:810-836`
    open override func updateGeometry() -> Double {
        let minExtent = self.minExtent
        let minAllowedExtent = sliverConstraints.remainingPaintExtent > minExtent
            ? minExtent
            : sliverConstraints.remainingPaintExtent
        let maxExtent = self.maxExtent
        let paintExtent = maxExtent - _effectiveScrollOffset!
        let clampedPaintExtent = clampDouble(
            paintExtent,
            minAllowedExtent,
            sliverConstraints.remainingPaintExtent
        )
        let layoutExtent = maxExtent - sliverConstraints.scrollOffset
        let stretchOffset = stretchConfiguration != nil ? Swift.abs(sliverConstraints.overlap) : 0.0
        geometry = SliverGeometry(
            scrollExtent: maxExtent,
            paintExtent: clampedPaintExtent,
            paintOrigin: min(sliverConstraints.overlap, 0.0),
            layoutExtent: clampDouble(layoutExtent, 0.0, clampedPaintExtent),
            maxPaintExtent: maxExtent + stretchOffset,
            maxScrollObstructionExtent: minExtent,
            hasVisualOverflow: true  // Conservatively say we do have overflow to avoid complexity.
        )
        return 0.0
    }
}
