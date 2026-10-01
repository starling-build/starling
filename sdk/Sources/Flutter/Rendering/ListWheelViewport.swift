// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// List wheel viewport rendering types.
///
/// Renders children on a cylindrical wheel, providing the visual effect of a
/// vertical scrolling picker (e.g. iOS-style date/time pickers).
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/list_wheel_viewport.dart`

import FlutterSwiftBridge
import Foundation

// MARK: - ListWheelChildManager

/// A delegate used by `RenderListWheelViewport` to manage its children.
///
/// `RenderListWheelViewport` during layout will ask the delegate to create
/// children that are visible in the viewport and remove those that are not.
///
/// **Dart Source:** `list_wheel_viewport.dart:27-55`
public protocol ListWheelChildManager: AnyObject {

    /// The maximum number of children that can be provided to
    /// `RenderListWheelViewport`.
    ///
    /// If non-nil, the children will have index in the range
    /// `[0, childCount - 1]`.
    ///
    /// If nil, then there's no explicit limits to the range of the children
    /// except that it has to be contiguous. If `childExistsAt` for a certain
    /// index returns false, that index is already past the limit.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:37`
    var childCount: Int? { get }

    /// Checks whether the delegate is able to provide a child widget at the given
    /// index.
    ///
    /// This function is not about whether the child at the given index is
    /// attached to the `RenderListWheelViewport` or not.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:44`
    func childExistsAt(_ index: Int) -> Bool

    /// Creates a new child at the given index and updates it to the child list
    /// of `RenderListWheelViewport`. If no child corresponds to `index`, then do
    /// nothing.
    ///
    /// It is possible to create children with negative indices.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:51`
    func createChild(_ index: Int, after: RenderBox?)

    /// Removes the child element corresponding with the given RenderBox.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:54`
    func removeChild(_ child: RenderBox)
}

// MARK: - ListWheelParentData

/// `ParentData` for use with `RenderListWheelViewport`.
///
/// **Dart Source:** `list_wheel_viewport.dart:58-74`
public class ListWheelParentData: ContainerBoxParentData<RenderBox> {

    /// Index of this child in its parent's child list.
    ///
    /// This must be maintained by the `ListWheelChildManager`.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:63`
    public var index: Int?

    /// Transform applied to this child during painting.
    ///
    /// Can be used to find the local bounds of this child in the viewport,
    /// and then use it, for example, in hit testing.
    ///
    /// May be nil if child was laid out, but not painted
    /// by the parent, but normally this shouldn't happen,
    /// because `RenderListWheelViewport` paints all of the
    /// children it has laid out.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:73`
    public var transform: Matrix4?
}

// MARK: - RenderListWheelViewport

/// Render, onto a wheel, a bigger sequential set of objects inside this viewport.
///
/// Takes a scrollable set of fixed sized `RenderBox`es and renders them
/// sequentially from top down on a vertical scrolling axis.
///
/// It starts with the first scrollable item in the center of the main axis
/// and ends with the last scrollable item in the center of the main axis. This
/// is in contrast to typical lists that start with the first scrollable item
/// at the start of the main axis and ends with the last scrollable item at the
/// end of the main axis.
///
/// Instead of rendering its children on a flat plane, it renders them
/// as if each child is broken into its own plane and that plane is
/// perpendicularly fixed onto a cylinder which rotates along the scrolling
/// axis.
///
/// **Dart Source:** `list_wheel_viewport.dart:147-1168`
open class RenderListWheelViewport: RenderBox, RenderAbstractViewport {

    // MARK: - Static Constants

    /// An arbitrary but aesthetically reasonable default value for `diameterRatio`.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:193`
    public static let defaultDiameterRatio: Double = 2.0

    /// An arbitrary but aesthetically reasonable default value for `perspective`.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:196`
    public static let defaultPerspective: Double = 0.003

    /// An error message to show when the provided `diameterRatio` is zero.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:199-202`
    public static let diameterRatioZeroMessage: String =
        "You can't set a diameterRatio "
        + "of 0 or of a negative number. It would imply a cylinder of 0 in diameter "
        + "in which case nothing will be drawn."

    /// An error message to show when the `perspective` value is too high.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:205-208`
    public static let perspectiveTooHighMessage: String =
        "A perspective too high will "
        + "be clipped in the z-axis and therefore not renderable. Value must be "
        + "between 0 and 0.01."

    /// An error message to show when `clipBehavior` and `renderChildrenOutsideViewport`
    /// are set to conflicting values.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:212-214`
    public static let clipBehaviorAndRenderChildrenOutsideViewportConflict: String =
        "Cannot renderChildrenOutsideViewport and clip since children "
        + "rendered outside will be clipped anyway."

    // MARK: - Initializer

    /// Creates a `RenderListWheelViewport` which renders children on a wheel.
    ///
    /// Optional arguments have reasonable defaults.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:153-190`
    public init(
        childManager: ListWheelChildManager,
        offset: ViewportOffset,
        diameterRatio: Double = defaultDiameterRatio,
        perspective: Double = defaultPerspective,
        offAxisFraction: Double = 0,
        useMagnifier: Bool = false,
        magnification: Double = 1,
        overAndUnderCenterOpacity: Double = 1,
        itemExtent: Double,
        squeeze: Double = 1,
        renderChildrenOutsideViewport: Bool = false,
        clipBehavior: Clip = .none,
        children: [RenderBox]? = nil
    ) {
        assert(diameterRatio > 0, Self.diameterRatioZeroMessage)
        assert(perspective > 0)
        assert(perspective <= 0.01, Self.perspectiveTooHighMessage)
        assert(magnification > 0)
        assert(overAndUnderCenterOpacity >= 0 && overAndUnderCenterOpacity <= 1)
        assert(squeeze > 0)
        assert(itemExtent > 0)
        assert(
            !renderChildrenOutsideViewport || clipBehavior == .none,
            Self.clipBehaviorAndRenderChildrenOutsideViewportConflict
        )
        self.childManager = childManager
        self._offset = offset
        self._diameterRatio = diameterRatio
        self._perspective = perspective
        self._offAxisFraction = offAxisFraction
        self._useMagnifier = useMagnifier
        self._magnification = magnification
        self._overAndUnderCenterOpacity = overAndUnderCenterOpacity
        self._itemExtent = itemExtent
        self._squeeze = squeeze
        self._renderChildrenOutsideViewport = renderChildrenOutsideViewport
        self._clipBehavior = clipBehavior
        super.init()
        addAll(children)
    }

    // MARK: - Container child management (ContainerRenderObjectMixin<RenderBox, ListWheelParentData>)

    /// The first child in the child list.
    ///
    /// **Dart Source:** object.dart:4222 (ContainerRenderObjectMixin)
    public private(set) var firstChild: RenderBox?

    /// The last child in the child list.
    ///
    /// **Dart Source:** object.dart:4223 (ContainerRenderObjectMixin)
    public private(set) var lastChild: RenderBox?

    /// The number of children.
    ///
    /// **Dart Source:** object.dart:4226 (ContainerRenderObjectMixin)
    public private(set) var childCount: Int = 0

    /// Returns the next sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4393 (ContainerRenderObjectMixin)
    public func childAfter(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as! ListWheelParentData
        return parentData.nextSibling
    }

    /// **Dart Source:** `ContainerRenderObjectMixin.visitChildren`
    open override func visitChildren(_ visitor: RenderObjectVisitor) {
        var child = firstChild
        while let current = child {
            visitor(current)
            child = childAfter(current)
        }
    }

    /// Returns the previous sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4399 (ContainerRenderObjectMixin)
    public func childBefore(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as! ListWheelParentData
        return parentData.previousSibling
    }

    /// Inserts a child into the linked list.
    ///
    /// **Dart Source:** object.dart:4234-4268 (ContainerRenderObjectMixin._insertIntoChildList)
    private func _insertIntoChildList(_ child: RenderBox, after: RenderBox? = nil) {
        let childParentData = child.parentData as! ListWheelParentData
        childCount += 1
        assert(childCount > 0)
        if let after = after {
            let afterParentData = after.parentData as! ListWheelParentData
            childParentData.nextSibling = afterParentData.nextSibling
            if let nextSibling = afterParentData.nextSibling {
                let nextParentData = nextSibling.parentData as! ListWheelParentData
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
                let firstParentData = first.parentData as! ListWheelParentData
                firstParentData.previousSibling = child
            }
            firstChild = child
            lastChild = lastChild ?? child
        }
    }

    /// Removes a child from the linked list.
    ///
    /// **Dart Source:** object.dart:4271-4295 (ContainerRenderObjectMixin._removeFromChildList)
    private func _removeFromChildList(_ child: RenderBox) {
        let childParentData = child.parentData as! ListWheelParentData
        if childParentData.previousSibling == nil {
            firstChild = childParentData.nextSibling
        } else {
            let previousParentData =
                childParentData.previousSibling!.parentData as! ListWheelParentData
            previousParentData.nextSibling = childParentData.nextSibling
        }
        if childParentData.nextSibling == nil {
            lastChild = childParentData.previousSibling
        } else {
            let nextParentData =
                childParentData.nextSibling!.parentData as! ListWheelParentData
            nextParentData.previousSibling = childParentData.previousSibling
        }
        childParentData.previousSibling = nil
        childParentData.nextSibling = nil
        childCount -= 1
    }

    /// Adds a child to the child list, optionally after the given child.
    ///
    /// **Dart Source:** object.dart:4310-4323 (ContainerRenderObjectMixin.insert)
    public func insert(_ child: RenderBox, after: RenderBox? = nil) {
        adoptChild(child)
        _insertIntoChildList(child, after: after)
    }

    /// Appends all the given children to the end of the child list.
    ///
    /// **Dart Source:** object.dart:4325-4341 (ContainerRenderObjectMixin.addAll)
    public func addAll(_ children: [RenderBox]?) {
        children?.forEach { insert($0, after: lastChild) }
    }

    /// Removes a child from the child list.
    ///
    /// **Dart Source:** object.dart:4343-4353 (ContainerRenderObjectMixin.remove)
    public func remove(_ child: RenderBox) {
        _removeFromChildList(child)
        dropChild(child)
    }

    // MARK: - Child Manager

    /// The delegate that manages the children of this object.
    ///
    /// This delegate must maintain the `ListWheelParentData.index` value.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:219`
    public let childManager: ListWheelChildManager

    // MARK: - Properties

    /// The associated ViewportOffset object for the viewport describing the part
    /// of the content inside that's visible.
    ///
    /// The `ViewportOffset.pixels` value determines the scroll offset that the
    /// viewport uses to select which part of its content to display. As the user
    /// scrolls the viewport, this value changes, which changes the content that
    /// is displayed.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:228-242`
    public var offset: ViewportOffset {
        get { _offset }
        set {
            if newValue === _offset { return }
            if attached {
                _offset.removeListeners(owner: self)
            }
            _offset = newValue
            if attached {
                _offset.addListener(_hasScrolled, owner: self)
            }
            markNeedsLayout()
        }
    }
    private var _offset: ViewportOffset

    /// A ratio between the diameter of the cylinder and the viewport's size
    /// in the main axis.
    ///
    /// Must be a positive number.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:272-282`
    public var diameterRatio: Double {
        get { _diameterRatio }
        set {
            assert(newValue > 0, Self.diameterRatioZeroMessage)
            if newValue == _diameterRatio { return }
            _diameterRatio = newValue
            markNeedsPaint()
            markNeedsSemanticsUpdate()
        }
    }
    private var _diameterRatio: Double

    /// Perspective of the cylindrical projection.
    ///
    /// A number between 0 and 0.01 where 0 means looking at the cylinder from
    /// infinitely far with an infinitely small field of view and 1 means looking
    /// at the cylinder from infinitely close with an infinitely large field of
    /// view (which cannot be rendered).
    ///
    /// Must be a positive number no greater than 0.01.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:298-309`
    public var perspective: Double {
        get { _perspective }
        set {
            assert(newValue > 0)
            assert(newValue <= 0.01, Self.perspectiveTooHighMessage)
            if newValue == _perspective { return }
            _perspective = newValue
            markNeedsPaint()
            markNeedsSemanticsUpdate()
        }
    }
    private var _perspective: Double

    /// How much the wheel is horizontally off-center, as a fraction of its width.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:336-344`
    public var offAxisFraction: Double {
        get { _offAxisFraction }
        set {
            if newValue == _offAxisFraction { return }
            _offAxisFraction = newValue
            markNeedsPaint()
        }
    }
    private var _offAxisFraction: Double

    /// Whether to use the magnifier for the center item of the wheel.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:349-357`
    public var useMagnifier: Bool {
        get { _useMagnifier }
        set {
            if newValue == _useMagnifier { return }
            _useMagnifier = newValue
            markNeedsPaint()
        }
    }
    private var _useMagnifier: Bool

    /// The zoomed-in rate of the magnifier, if it is used.
    ///
    /// The default value is 1.0, which will not change anything.
    /// If the value is > 1.0, the center item will be zoomed in by that rate, and
    /// it will also be rendered as flat, not cylindrical like the rest of the list.
    /// The item will be zoomed out if magnification < 1.0.
    ///
    /// Must be positive.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:369-378`
    public var magnification: Double {
        get { _magnification }
        set {
            assert(newValue > 0)
            if newValue == _magnification { return }
            _magnification = newValue
            markNeedsPaint()
        }
    }
    private var _magnification: Double

    /// The opacity value that will be applied to the wheel that appears below and
    /// above the magnifier.
    ///
    /// The default value is 1.0, which will not change anything.
    ///
    /// Must be greater than or equal to 0, and less than or equal to 1.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:389-397`
    public var overAndUnderCenterOpacity: Double {
        get { _overAndUnderCenterOpacity }
        set {
            assert(newValue >= 0 && newValue <= 1)
            if newValue == _overAndUnderCenterOpacity { return }
            _overAndUnderCenterOpacity = newValue
            markNeedsPaint()
        }
    }
    private var _overAndUnderCenterOpacity: Double

    /// The size of the children along the main axis. Children `RenderBox`es will
    /// be given the `BoxConstraints` of this exact size.
    ///
    /// Must be a positive number.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:405-414`
    public var itemExtent: Double {
        get { _itemExtent }
        set {
            assert(newValue > 0)
            if newValue == _itemExtent { return }
            _itemExtent = newValue
            markNeedsLayout()
        }
    }
    private var _itemExtent: Double

    /// The angular compactness of the children on the wheel.
    ///
    /// This denotes a ratio of the number of children on the wheel vs the number
    /// of children that would fit on a flat list of equivalent size, assuming
    /// `diameterRatio` of 1.
    ///
    /// Must be a positive number. Defaults to 1.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:436-446`
    public var squeeze: Double {
        get { _squeeze }
        set {
            assert(newValue > 0)
            if newValue == _squeeze { return }
            _squeeze = newValue
            markNeedsLayout()
            markNeedsSemanticsUpdate()
        }
    }
    private var _squeeze: Double

    /// Whether to paint children inside the viewport only.
    ///
    /// If false, every child will be painted. However the `Scrollable` is still
    /// the size of the viewport and detects gestures inside only.
    ///
    /// Defaults to false. Cannot be true if `clipBehavior` is not `Clip.none`
    /// since children outside the viewport will be clipped, and therefore cannot
    /// render children outside the viewport.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:458-471`
    public var renderChildrenOutsideViewport: Bool {
        get { _renderChildrenOutsideViewport }
        set {
            assert(
                !newValue || clipBehavior == .none,
                Self.clipBehaviorAndRenderChildrenOutsideViewportConflict
            )
            if newValue == _renderChildrenOutsideViewport { return }
            _renderChildrenOutsideViewport = newValue
            markNeedsLayout()
            markNeedsSemanticsUpdate()
        }
    }
    private var _renderChildrenOutsideViewport: Bool

    /// Clip behavior for the viewport.
    ///
    /// Defaults to `Clip.none`.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:476-484`
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

    // MARK: - Semantics update

    /// Mark this render object as needing a semantics update.
    ///
    /// Stub - will be fully implemented in a later subtask.
    open func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with pipeline owner
    }

    // MARK: - Scroll Notification

    /// **Dart Source:** `list_wheel_viewport.dart:486-489`
    private func _hasScrolled() {
        markNeedsLayout()
        markNeedsSemanticsUpdate()
    }

    // MARK: - Setup Parent Data

    /// **Dart Source:** `list_wheel_viewport.dart:492-496`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is ListWheelParentData) {
            child.parentData = ListWheelParentData()
        }
    }

    // MARK: - Attach / Detach

    /// **Dart Source:** `list_wheel_viewport.dart:499-502`
    open override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _offset.addListener(_hasScrolled, owner: self)
    }

    /// **Dart Source:** `list_wheel_viewport.dart:504-508`
    open override func detach() {
        _offset.removeListeners(owner: self)
        super.detach()
    }

    // MARK: - Repaint Boundary

    /// **Dart Source:** `list_wheel_viewport.dart:511`
    open override var isRepaintBoundary: Bool { true }

    // MARK: - Viewport Geometry Helpers

    /// Main axis length in the untransformed plane.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:514-517`
    private var _viewportExtent: Double {
        assert(hasSize)
        return size.height
    }

    /// Main axis scroll extent in the scrollable layout coordinates that puts
    /// the first item in the center.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:521-527`
    private var _minEstimatedScrollExtent: Double {
        assert(hasSize)
        if childManager.childCount == nil {
            return -.infinity
        }
        return 0.0
    }

    /// Main axis scroll extent in the scrollable layout coordinates that puts
    /// the last item in the center.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:531-538`
    private var _maxEstimatedScrollExtent: Double {
        assert(hasSize)
        if childManager.childCount == nil {
            return .infinity
        }
        return max(0.0, Double(childManager.childCount! - 1) * _itemExtent)
    }

    /// Scroll extent distance in the untransformed plane between the center
    /// position in the viewport and the top position in the viewport.
    ///
    /// It's also the distance in the untransformed plane that children's painting
    /// is offset by with respect to those children's `BoxParentData.offset`.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:545-549`
    private var _topScrollMarginExtent: Double {
        assert(hasSize)
        return -size.height / 2.0 + _itemExtent / 2.0
    }

    /// Transforms a scrollable layout coordinates' y position to the
    /// untransformed plane's viewport painting coordinates' y position given
    /// the current scroll offset.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:554-556`
    private func _getUntransformedPaintingCoordinateY(_ layoutCoordinateY: Double) -> Double {
        return layoutCoordinateY - _topScrollMarginExtent - offset.pixels
    }

    /// Given the `_diameterRatio`, return the largest absolute angle of the item
    /// at the edge of the portion of the visible cylinder.
    ///
    /// For a `_diameterRatio` of 1 or less than 1 (i.e. the viewport is bigger
    /// than the cylinder diameter), this value reaches and clips at pi / 2.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:566-571`
    private var _maxVisibleRadian: Double {
        if _diameterRatio < 1.0 {
            return .pi / 2.0
        }
        return asin(1.0 / _diameterRatio)
    }

    // MARK: - Intrinsic Dimensions

    /// **Dart Source:** `list_wheel_viewport.dart:573-581`
    private func _getIntrinsicCrossAxis(_ childSize: ChildSizingFunction) -> Double {
        var extent: Double = 0.0
        var child = firstChild
        while child != nil {
            extent = max(extent, childSize(child!))
            child = childAfter(child!)
        }
        return extent
    }

    /// **Dart Source:** `list_wheel_viewport.dart:584-586`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        return _getIntrinsicCrossAxis { $0.getMinIntrinsicWidth(height) }
    }

    /// **Dart Source:** `list_wheel_viewport.dart:589-591`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        return _getIntrinsicCrossAxis { $0.getMaxIntrinsicWidth(height) }
    }

    /// **Dart Source:** `list_wheel_viewport.dart:594-599`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        if childManager.childCount == nil { return 0.0 }
        return Double(childManager.childCount!) * _itemExtent
    }

    /// **Dart Source:** `list_wheel_viewport.dart:602-607`
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        if childManager.childCount == nil { return 0.0 }
        return Double(childManager.childCount!) * _itemExtent
    }

    // MARK: - Sized By Parent

    /// **Dart Source:** `list_wheel_viewport.dart:610`
    open override var sizedByParent: Bool { true }

    /// **Dart Source:** `list_wheel_viewport.dart:614-616`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }

    // MARK: - Index Utilities

    /// Gets the index of a child by looking at its `parentData`.
    ///
    /// This relies on the `childManager` maintaining `ListWheelParentData.index`.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:621-625`
    public func indexOf(_ child: RenderBox) -> Int {
        let childParentData = child.parentData! as! ListWheelParentData
        assert(childParentData.index != nil)
        return childParentData.index!
    }

    /// Returns the index of the child at the given offset.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:628`
    public func scrollOffsetToIndex(_ scrollOffset: Double) -> Int {
        return Int(floor(scrollOffset / itemExtent))
    }

    /// Returns the scroll offset of the child with the given index.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:631`
    public func indexToScrollOffset(_ index: Int) -> Double {
        return Double(index) * itemExtent
    }

    // MARK: - Child Creation / Destruction

    /// Calls the given callback during layout.
    ///
    /// This is a simplified version that just invokes the callback with the
    /// current box constraints.
    ///
    /// **Dart Source:** via `RenderObject.invokeLayoutCallback`
    public func invokeLayoutCallback(_ callback: (BoxConstraints) -> Void) {
        callback(boxConstraints)
    }

    /// **Dart Source:** `list_wheel_viewport.dart:633-637`
    private func _createChild(_ index: Int, after: RenderBox? = nil) {
        invokeLayoutCallback { [self] (_: BoxConstraints) in
            childManager.createChild(index, after: after)
        }
    }

    /// **Dart Source:** `list_wheel_viewport.dart:639-644`
    private func _destroyChild(_ child: RenderBox) {
        invokeLayoutCallback { [self] (_: BoxConstraints) in
            childManager.removeChild(child)
        }
    }

    /// **Dart Source:** `list_wheel_viewport.dart:646-653`
    private func _layoutChild(_ child: RenderBox, _ constraints: BoxConstraints, _ index: Int) {
        child.layout(constraints, parentUsesSize: true)
        let childParentData = child.parentData! as! ListWheelParentData
        // Centers the child horizontally.
        let crossPosition = size.width / 2.0 - child.size.width / 2.0
        childParentData.offset = Offset(crossPosition, indexToScrollOffset(index))
    }

    // MARK: - Layout

    /// Performs layout based on how `childManager` provides children.
    ///
    /// From the current scroll offset, the minimum index and maximum index that
    /// is visible in the viewport can be calculated. The index range of the
    /// currently active children can also be acquired by looking directly at
    /// the current child list. This function has to modify the current index
    /// range to match the target index range by removing children that are no
    /// longer visible and creating those that are visible but not yet provided
    /// by `childManager`.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:665-787`
    open override func performLayout() {
        offset.applyViewportDimension(_viewportExtent)
        // Apply the content dimensions first if it has exact dimensions in case it
        // changes the scroll offset which determines what should be shown.
        if childManager.childCount != nil {
            offset.applyContentDimensions(_minEstimatedScrollExtent, _maxEstimatedScrollExtent)
        }

        // The height, in pixel, that children will be visible and might be laid out
        // and painted.
        var visibleHeight = size.height * _squeeze
        // If renderChildrenOutsideViewport is true, we spawn extra children by
        // doubling the visibility range, those that are in the backside of the
        // cylinder won't be painted anyway.
        if renderChildrenOutsideViewport {
            visibleHeight *= 2
        }

        let firstVisibleOffset = offset.pixels + _itemExtent / 2 - visibleHeight / 2
        let lastVisibleOffset = firstVisibleOffset + visibleHeight

        // The index range that we want to spawn children.
        var targetFirstIndex = scrollOffsetToIndex(firstVisibleOffset)
        var targetLastIndex = scrollOffsetToIndex(lastVisibleOffset)
        // Because we exclude lastVisibleOffset, if there's a new child starting at
        // that offset, it is removed.
        if Double(targetLastIndex) * _itemExtent == lastVisibleOffset {
            targetLastIndex -= 1
        }

        // Validates the target index range.
        while !childManager.childExistsAt(targetFirstIndex) && targetFirstIndex <= targetLastIndex {
            targetFirstIndex += 1
        }
        while !childManager.childExistsAt(targetLastIndex) && targetFirstIndex <= targetLastIndex {
            targetLastIndex -= 1
        }

        // If it turns out there's no children to layout, we remove old children and
        // return.
        if targetFirstIndex > targetLastIndex {
            while firstChild != nil {
                _destroyChild(firstChild!)
            }
            return
        }

        // Case when there is no intersection between target range and current range.
        if childCount > 0 &&
            (indexOf(firstChild!) > targetLastIndex || indexOf(lastChild!) < targetFirstIndex) {
            while firstChild != nil {
                _destroyChild(firstChild!)
            }
        }

        let childConstraints = boxConstraints.copyWith(
            minWidth: 0.0,
            minHeight: _itemExtent,
            maxHeight: _itemExtent
        )
        // If there is no child at this stage, we add the first one that is in
        // target range.
        if childCount == 0 {
            _createChild(targetFirstIndex)
            _layoutChild(firstChild!, childConstraints, targetFirstIndex)
        }

        var currentFirstIndex = indexOf(firstChild!)
        var currentLastIndex = indexOf(lastChild!)

        // Remove all unnecessary children by shortening the current child list.
        while currentFirstIndex < targetFirstIndex {
            _destroyChild(firstChild!)
            currentFirstIndex += 1
        }
        while currentLastIndex > targetLastIndex {
            _destroyChild(lastChild!)
            currentLastIndex -= 1
        }

        // Relayout all active children.
        var child = firstChild
        var index = currentFirstIndex
        while child != nil {
            _layoutChild(child!, childConstraints, index)
            index += 1
            child = childAfter(child!)
        }

        // Spawning new children that are actually visible but not in child list yet.
        while currentFirstIndex > targetFirstIndex {
            _createChild(currentFirstIndex - 1)
            currentFirstIndex -= 1
            _layoutChild(firstChild!, childConstraints, currentFirstIndex)
        }
        while currentLastIndex < targetLastIndex {
            _createChild(currentLastIndex + 1, after: lastChild)
            currentLastIndex += 1
            _layoutChild(lastChild!, childConstraints, currentLastIndex)
        }

        // Applying content dimensions based on how the childManager builds widgets.
        let minScrollExtent = childManager.childExistsAt(targetFirstIndex - 1)
            ? _minEstimatedScrollExtent
            : indexToScrollOffset(targetFirstIndex)
        let maxScrollExtent = childManager.childExistsAt(targetLastIndex + 1)
            ? _maxEstimatedScrollExtent
            : indexToScrollOffset(targetLastIndex)
        offset.applyContentDimensions(minScrollExtent, maxScrollExtent)
    }

    // MARK: - Clip Layer

    /// **Dart Source:** `list_wheel_viewport.dart:814`
    private let _clipRectLayer = LayerHandle<ClipRectLayer>()

    /// **Dart Source:** `list_wheel_viewport.dart:823`
    private let _childOpacityLayerHandler = LayerHandle<OpacityLayer>()

    /// **Dart Source:** `list_wheel_viewport.dart:789-793`
    private func _shouldClipAtCurrentOffset() -> Bool {
        let highestUntransformedPaintY = _getUntransformedPaintingCoordinateY(0.0)
        return highestUntransformedPaintY < 0.0
            || size.height < highestUntransformedPaintY + _maxEstimatedScrollExtent + _itemExtent
    }

    // MARK: - Paint

    /// **Dart Source:** `list_wheel_viewport.dart:796-812`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        if childCount > 0 {
            if _shouldClipAtCurrentOffset() && clipBehavior != .none {
                _clipRectLayer.layer = context.pushClipRect(
                    needsCompositing,
                    offset,
                    Offset.zero & size,
                    _paintVisibleChildren,
                    clipBehavior: clipBehavior,
                    oldLayer: _clipRectLayer.layer
                )
            } else {
                _clipRectLayer.layer = nil
                _paintVisibleChildren(context, offset)
            }
        }
    }

    // MARK: - Dispose

    /// **Dart Source:** `list_wheel_viewport.dart:817-821`
    open override func dispose() {
        _clipRectLayer.layer = nil
        _childOpacityLayerHandler.layer = nil
        super.dispose()
    }

    // MARK: - Paint Helpers

    /// Paints all children visible in the current viewport.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:826-843`
    private func _paintVisibleChildren(_ context: PaintingContext, _ offset: Offset) {
        // The magnifier cannot be turned off if the opacity is less than 1.0.
        if overAndUnderCenterOpacity >= 1 {
            _paintAllChildren(context, offset)
            return
        }

        // In order to reduce the number of opacity layers, we first paint all
        // partially opaque children, then finally paint the fully opaque children.
        _childOpacityLayerHandler.layer = context.pushOpacity(
            offset,
            Int((overAndUnderCenterOpacity * 255).rounded()),
            { (context: PaintingContext, offset: Offset) in
                self._paintAllChildren(context, offset, center: false)
            }
        )
        _paintAllChildren(context, offset, center: true)
    }

    /// **Dart Source:** `list_wheel_viewport.dart:845-852`
    private func _paintAllChildren(_ context: PaintingContext, _ offset: Offset, center: Bool? = nil) {
        var childToPaint = firstChild
        while childToPaint != nil {
            let childParentData = childToPaint!.parentData! as! ListWheelParentData
            _paintTransformedChild(
                childToPaint!,
                context,
                offset,
                childParentData.offset,
                center: center
            )
            childToPaint = childAfter(childToPaint!)
        }
    }

    /// Takes in a child with a scrollable layout offset and paints it in the
    /// transformed cylindrical space viewport painting coordinates.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:859-908`
    private func _paintTransformedChild(
        _ child: RenderBox,
        _ context: PaintingContext,
        _ offset: Offset,
        _ layoutOffset: Offset,
        center: Bool?
    ) {
        let untransformedPaintingCoordinates =
            offset + Offset(layoutOffset.dx, _getUntransformedPaintingCoordinateY(layoutOffset.dy))

        // Get child's center as a fraction of the viewport's height.
        let fractionalY =
            (untransformedPaintingCoordinates.dy + _itemExtent / 2.0) / size.height
        let angle = -(fractionalY - 0.5) * 2.0 * _maxVisibleRadian / squeeze
        // Don't paint the backside of the cylinder when
        // renderChildrenOutsideViewport is true.
        if angle > .pi / 2.0 || angle < -.pi / 2.0 || angle.isNaN {
            return
        }

        let transform = MatrixUtils.createCylindricalProjectionTransform(
            radius: size.height * _diameterRatio / 2.0,
            angle: angle,
            perspective: _perspective
        )

        // Offset that helps painting everything in the center (e.g. angle = 0).
        let offsetToCenter = Offset(
            untransformedPaintingCoordinates.dx,
            -_topScrollMarginExtent
        )

        let shouldApplyOffCenterDim = overAndUnderCenterOpacity < 1
        if useMagnifier || shouldApplyOffCenterDim {
            _paintChildWithMagnifier(
                context,
                offset,
                child,
                transform,
                offsetToCenter,
                untransformedPaintingCoordinates,
                center: center
            )
        } else {
            assert(center == nil)
            _paintChildCylindrically(context, offset, child, transform, offsetToCenter)
        }
    }

    /// Paint child with the magnifier active - the child will be rendered
    /// differently if it intersects with the magnifier.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:923-989`
    private func _paintChildWithMagnifier(
        _ context: PaintingContext,
        _ offset: Offset,
        _ child: RenderBox,
        _ cylindricalTransform: Matrix4,
        _ offsetToCenter: Offset,
        _ untransformedPaintingCoordinates: Offset,
        center: Bool?
    ) {
        let magnifierTopLinePosition = size.height / 2 - _itemExtent * _magnification / 2
        let magnifierBottomLinePosition = size.height / 2 + _itemExtent * _magnification / 2

        let isAfterMagnifierTopLine =
            untransformedPaintingCoordinates.dy >=
            magnifierTopLinePosition - _itemExtent * _magnification
        let isBeforeMagnifierBottomLine =
            untransformedPaintingCoordinates.dy <= magnifierBottomLinePosition

        let centerRect = Rect.fromLTWH(
            0.0,
            magnifierTopLinePosition,
            size.width,
            _itemExtent * _magnification
        )
        let topHalfRect = Rect.fromLTWH(0.0, 0.0, size.width, magnifierTopLinePosition)
        let bottomHalfRect = Rect.fromLTWH(
            0.0,
            magnifierBottomLinePosition,
            size.width,
            magnifierTopLinePosition
        )
        // Some part of the child is in the center magnifier.
        let inCenter = isAfterMagnifierTopLine && isBeforeMagnifierBottomLine

        if (center == nil || center == true) && inCenter {
            // Clipping the part in the center.
            context.pushClipRect(needsCompositing, offset, centerRect, {
                (context: PaintingContext, offset: Offset) in
                context.pushTransform(needsCompositing, offset, self._magnifyTransform(), {
                    (context: PaintingContext, offset: Offset) in
                    context.paintChild(child, offset + untransformedPaintingCoordinates)
                })
            })
        }

        // Clipping the part in either the top-half or bottom-half of the wheel.
        if (center == nil || center == false) && inCenter {
            context.pushClipRect(
                needsCompositing,
                offset,
                untransformedPaintingCoordinates.dy <= magnifierTopLinePosition
                    ? topHalfRect
                    : bottomHalfRect,
                { (context: PaintingContext, offset: Offset) in
                    self._paintChildCylindrically(context, offset, child, cylindricalTransform, offsetToCenter)
                }
            )
        }

        if (center == nil || center == false) && !inCenter {
            _paintChildCylindrically(context, offset, child, cylindricalTransform, offsetToCenter)
        }
    }

    /// Paint the child cylindrically at given offset.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:992-1023`
    private func _paintChildCylindrically(
        _ context: PaintingContext,
        _ offset: Offset,
        _ child: RenderBox,
        _ cylindricalTransform: Matrix4,
        _ offsetToCenter: Offset
    ) {
        let paintOriginOffset = offset + offsetToCenter

        // Paint child cylindrically, without overAndUnderCenterOpacity.
        context.pushTransform(
            needsCompositing,
            offset,
            _centerOriginTransform(cylindricalTransform),
            { (context: PaintingContext, offset: Offset) in
                // Paint everything in the center (e.g. angle = 0), then transform.
                context.paintChild(child, paintOriginOffset)
            }
        )

        let childParentData = child.parentData! as! ListWheelParentData
        // Save the final transform that accounts both for the offset and cylindrical transform.
        var transform = _centerOriginTransform(cylindricalTransform)
        transform.translate(paintOriginOffset.dx, paintOriginOffset.dy, 0)
        childParentData.transform = transform
    }

    // MARK: - Transform Helpers

    /// Return the Matrix4 transformation that would zoom in content in the
    /// magnified area.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:1027-1032`
    private func _magnifyTransform() -> Matrix4 {
        let tx = size.width * (-_offAxisFraction + 0.5)
        let ty = size.height / 2
        var result = Matrix4.identity()
        result.translate(tx, ty, 0)
        result.scale(_magnification, _magnification, _magnification)
        result.translate(-tx, -ty, 0)
        return result
    }

    /// Apply incoming transformation with the transformation's origin at the
    /// viewport's center or horizontally off to the side based on offAxisFraction.
    ///
    /// **Dart Source:** `list_wheel_viewport.dart:1036-1053`
    private func _centerOriginTransform(_ originalMatrix: Matrix4) -> Matrix4 {
        var result = Matrix4.identity()
        let centerOriginTranslation = Alignment.center.alongSize(size)
        result.translate(
            centerOriginTranslation.dx * (-_offAxisFraction * 2 + 1),
            centerOriginTranslation.dy,
            0
        )
        result.multiply(originalMatrix)
        result.translate(
            -centerOriginTranslation.dx * (-_offAxisFraction * 2 + 1),
            -centerOriginTranslation.dy,
            0
        )
        return result
    }

    // MARK: - Debug Hit Test Validation

    /// **Dart Source:** `list_wheel_viewport.dart:1055-1060`
    private static func _debugAssertValidHitTestOffsets(
        _ context: String,
        _ offset1: Offset,
        _ offset2: Offset
    ) -> Bool {
        if offset1 != offset2 {
            fatalError("\(context) - hit test expected values didn't match: \(offset1) != \(offset2)")
        }
        return true
    }

    // MARK: - Paint Transform

    /// **Dart Source:** `list_wheel_viewport.dart:1063-1069`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        let parentData = child.parentData! as! ListWheelParentData
        if let paintTransform = parentData.transform {
            transform.multiply(paintTransform)
        }
    }

    /// **Dart Source:** `list_wheel_viewport.dart:1072-1077`
    open func describeApproximatePaintClip(_ child: RenderObject) -> Rect? {
        if _shouldClipAtCurrentOffset() {
            return Offset.zero & size
        }
        return nil
    }

    // MARK: - Hit Testing

    /// **Dart Source:** `list_wheel_viewport.dart:1080-1118`
    open override func hitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool {
        var child = lastChild
        while child != nil {
            let childParentData = child!.parentData! as! ListWheelParentData
            let paintTransform = childParentData.transform
            // Skip not painted children
            if paintTransform != nil {
                let isHit = result.addWithPaintTransform(
                    transform: paintTransform,
                    position: position,
                    hitTest: { (result: BoxHitTestResult, transformed: Offset) -> Bool in
                        assert({
                            let inverted = Matrix4.tryInvert(
                                PointerEvent.removePerspectiveTransform(paintTransform!)
                            )
                            if inverted == nil {
                                return Self._debugAssertValidHitTestOffsets(
                                    "Null inverted transform",
                                    transformed,
                                    position
                                )
                            }
                            return Self._debugAssertValidHitTestOffsets(
                                "MatrixUtils.transformPoint",
                                transformed,
                                MatrixUtils.transformPoint(inverted!, position)
                            )
                        }())
                        return child!.hitTest(result, position: transformed)
                    }
                )
                if isHit {
                    return true
                }
            }
            child = childParentData.previousSibling
        }
        return false
    }

    // MARK: - RenderAbstractViewport

    /// **Dart Source:** `list_wheel_viewport.dart:1121-1146`
    open func getOffsetToReveal(
        _ target: RenderObject,
        _ alignment: Double,
        rect: Rect? = nil,
        axis: Axis? = nil
    ) -> RevealedOffset {
        // `target` is only fully revealed when in the selected/center position.
        // Therefore, this method always returns the offset that shows `target` in
        // the center position, which is the same offset for all `alignment` values.
        let rect = rect ?? target.paintBounds

        // `child` will be the last RenderObject before the viewport when walking
        // up from `target`.
        var child: RenderObject = target
        while child.parent !== self {
            child = child.parent!
        }

        let parentData = child.parentData! as! ListWheelParentData
        let targetOffset = parentData.offset.dy  // the so-called "centerPosition"

        let transform = target.getTransformTo(child)
        let bounds = MatrixUtils.transformRect(transform, rect)
        let targetRect = bounds.translate(0.0, (size.height - itemExtent) / 2)

        return RevealedOffset(offset: targetOffset, rect: targetRect)
    }

    // MARK: - Show On Screen

    /// **Dart Source:** `list_wheel_viewport.dart:1149-1167`
    open func showOnScreen(
        descendant: RenderObject? = nil,
        rect: Rect? = nil,
        duration: Duration = .zero,
        curve: any Curve = Curves.ease
    ) {
        if let descendant = descendant {
            // Shows the descendant in the selected/center position.
            let revealedOffset = getOffsetToReveal(descendant, 0.5, rect: rect)
            // In the Dart source, non-zero duration calls offset.animateTo.
            // We use jumpTo as a fallback until animation infrastructure is
            // fully migrated, matching the pattern in RenderViewportBase.
            offset.jumpTo(revealedOffset.offset)
            let newRect = revealedOffset.rect
            // In the full implementation, would call super.showOnScreen(rect: newRect, ...)
            _ = newRect
        }
        // In the full implementation, would call super.showOnScreen(rect: rect, ...)
    }
}
