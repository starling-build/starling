// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Sliver group render objects for cross-axis and main-axis grouping.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/sliver_group.dart`

import FlutterSwiftBridge

// =============================================================================
// MARK: - RenderSliverCrossAxisGroup
// =============================================================================

/// A sliver that places multiple sliver children in a linear array along the
/// cross axis.
///
/// Since the extent of the viewport in the cross axis direction is finite,
/// this extent will be divided up and allocated to the children slivers.
///
/// The algorithm for dividing up the cross axis extent is as follows.
/// Every widget has a `SliverPhysicalParentData.crossAxisFlex` value
/// associated with them. First, lay out all of the slivers with flex of 0 or
/// nil, in which case the slivers themselves will figure out how much cross
/// axis extent to take up. For example, `SliverConstrainedCrossAxis` is an
/// example of a widget which sets its own flex to 0. Then
/// `RenderSliverCrossAxisGroup` will divide up the remaining space to all the
/// remaining children proportionally to each child's flex factor. By default,
/// children of `SliverCrossAxisGroup` are setup to have a flex factor of 1,
/// but a different flex factor can be specified via the
/// `SliverCrossAxisExpanded` widgets.
///
/// In Dart, `RenderSliverCrossAxisGroup` extends `RenderSliver` and mixes in
/// `ContainerRenderObjectMixin<RenderSliver, SliverPhysicalContainerParentData>`.
/// In Swift, the container child management is implemented directly on the
/// class.
///
/// **Dart Source:** `sliver_group.dart:32-178`
open class RenderSliverCrossAxisGroup: RenderSliver {

    // MARK: - Container child management (ContainerRenderObjectMixin)

    /// The first child in the child list.
    ///
    /// **Dart Source:** object.dart:4222 (ContainerRenderObjectMixin)
    public private(set) var firstChild: RenderSliver?

    /// The last child in the child list.
    ///
    /// **Dart Source:** object.dart:4223 (ContainerRenderObjectMixin)
    public private(set) var lastChild: RenderSliver?

    /// The number of children.
    ///
    /// **Dart Source:** object.dart:4226 (ContainerRenderObjectMixin)
    public private(set) var childCount: Int = 0

    /// Returns the next sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4393 (ContainerRenderObjectMixin)
    public func childAfter(_ child: RenderSliver) -> RenderSliver? {
        let parentData = child.parentData as! SliverPhysicalContainerParentData
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
    public func childBefore(_ child: RenderSliver) -> RenderSliver? {
        let parentData = child.parentData as! SliverPhysicalContainerParentData
        return parentData.previousSibling
    }

    /// Inserts a child into the linked list.
    ///
    /// **Dart Source:** object.dart:4234-4268 (ContainerRenderObjectMixin._insertIntoChildList)
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
    /// **Dart Source:** object.dart:4271-4295 (ContainerRenderObjectMixin._removeFromChildList)
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
    /// **Dart Source:** object.dart:4310-4323 (ContainerRenderObjectMixin.insert)
    public func insert(_ child: RenderSliver, after: RenderSliver? = nil) {
        setupParentData(child)
        child.parent = self
        _insertIntoChildList(child, after: after)
    }

    /// Appends all the given children to the end of the child list.
    ///
    /// **Dart Source:** object.dart:4325-4341 (ContainerRenderObjectMixin.addAll)
    public func addAll(_ children: [RenderSliver]?) {
        children?.forEach { insert($0, after: lastChild) }
    }

    /// Removes a child from the child list.
    ///
    /// **Dart Source:** object.dart:4343-4353 (ContainerRenderObjectMixin.remove)
    public func remove(_ child: RenderSliver) {
        child.parent = nil
        _removeFromChildList(child)
    }

    // MARK: - Parent Data

    /// Sets up `SliverPhysicalContainerParentData` for the given child and
    /// assigns a default `crossAxisFlex` of 1.
    ///
    /// **Dart Source:** `sliver_group.dart:34-40`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverPhysicalContainerParentData) {
            child.parentData = SliverPhysicalContainerParentData()
            (child.parentData! as! SliverPhysicalParentData).crossAxisFlex = 1
        }
    }

    // MARK: - Child Position Methods

    /// Returns the main axis position of the child.
    ///
    /// For a cross-axis group, all children start at the same main axis
    /// position (0.0).
    ///
    /// **Dart Source:** `sliver_group.dart:42-43`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        return 0.0
    }

    /// Returns the cross axis position of the child from its paint offset.
    ///
    /// **Dart Source:** `sliver_group.dart:45-52`
    open override func childCrossAxisPosition(_ child: RenderObject) -> Double {
        let paintOffset = (child.parentData! as! SliverPhysicalParentData).paintOffset
        switch sliverConstraints.axis {
        case .vertical:
            return paintOffset.dx
        case .horizontal:
            return paintOffset.dy
        }
    }

    // MARK: - Layout

    /// Performs the layout by dividing cross-axis space among children.
    ///
    /// First, lays out all children with flex == 0 or nil, which determine
    /// their own cross-axis extent. Then divides the remaining space
    /// proportionally among flexible children. Finally, corrects paint offsets
    /// for children that would paint outside the group bounds.
    ///
    /// **Dart Source:** `sliver_group.dart:54-133`
    open override func performLayout() {
        let constraints = self.sliverConstraints
        let crossAxisExtent = constraints.crossAxisExtent
        assert(crossAxisExtent.isFinite)

        // First, layout each child with flex == 0 or nil.
        var totalFlex = 0
        var remainingExtent = crossAxisExtent
        var child = firstChild
        while let currentChild = child {
            let childParentData = currentChild.parentData! as! SliverPhysicalParentData
            let flex = childParentData.crossAxisFlex ?? 0
            if flex == 0 {
                // If flex is 0 or nil, then the child sliver must provide their own crossAxisExtent.
                assert(_assertOutOfExtent(remainingExtent))
                currentChild.layout(
                    constraints.copyWith(crossAxisExtent: remainingExtent),
                    parentUsesSize: true
                )
                let childCrossAxisExtent = currentChild.geometry!.crossAxisExtent
                assert(childCrossAxisExtent != nil)
                remainingExtent = max(0.0, remainingExtent - childCrossAxisExtent!)
            } else {
                totalFlex += flex
            }
            child = childAfter(currentChild)
        }
        let extentPerFlexValue = totalFlex > 0 ? remainingExtent / Double(totalFlex) : 0.0

        child = firstChild

        // At this point, all slivers with constrained cross axis should already be laid out.
        // Layout the rest and keep track of the child geometry with greatest scrollExtent.
        geometry = SliverGeometry.zero
        while let currentChild = child {
            let childParentData = currentChild.parentData! as! SliverPhysicalParentData
            let flex = childParentData.crossAxisFlex ?? 0
            if flex != 0 {
                let childExtent = extentPerFlexValue * Double(flex)
                assert(_assertOutOfExtent(childExtent))
                currentChild.layout(
                    constraints.copyWith(crossAxisExtent: childExtent),
                    parentUsesSize: true
                )
            }
            let childLayoutGeometry = currentChild.geometry!
            if geometry!.scrollExtent < childLayoutGeometry.scrollExtent {
                geometry = childLayoutGeometry
            }
            child = childAfter(currentChild)
        }

        // Go back and correct any slivers using a negative paint offset if it tries
        // to paint outside the bounds of the sliver group.
        child = firstChild
        var offset = 0.0
        while let currentChild = child {
            let childParentData = currentChild.parentData! as! SliverPhysicalParentData
            let childLayoutGeometry = currentChild.geometry!
            let extentRemaining = geometry!.scrollExtent - constraints.scrollOffset
            let paintCorrection = childLayoutGeometry.paintExtent > extentRemaining
                ? childLayoutGeometry.paintExtent - extentRemaining
                : 0.0
            let childExtent =
                currentChild.geometry!.crossAxisExtent
                ?? extentPerFlexValue * Double(childParentData.crossAxisFlex ?? 0)
            // Set child parent data.
            switch constraints.axis {
            case .vertical:
                childParentData.paintOffset = Offset(offset, -paintCorrection)
            case .horizontal:
                childParentData.paintOffset = Offset(-paintCorrection, offset)
            }
            offset += childExtent
            child = childAfter(currentChild)
        }
    }

    // MARK: - Painting

    /// Paints all visible children at their paint offsets.
    ///
    /// **Dart Source:** `sliver_group.dart:135-147`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        var child = firstChild
        while let currentChild = child {
            if currentChild.geometry!.visible {
                let childParentData = currentChild.parentData! as! SliverPhysicalParentData
                context.paintChild(currentChild, offset + childParentData.paintOffset)
            }
            child = childAfter(currentChild)
        }
    }

    // MARK: - Paint Transform

    /// Applies the paint transform for a child using its parent data paint
    /// offset.
    ///
    /// **Dart Source:** `sliver_group.dart:149-153`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        let childParentData = child.parentData! as! SliverPhysicalParentData
        childParentData.applyPaintTransform(&transform)
    }

    // MARK: - Hit Testing

    /// Hit tests children in reverse paint order (last to first).
    ///
    /// **Dart Source:** `sliver_group.dart:155-178`
    open override func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        var child = lastChild
        while let currentChild = child {
            let paintOffset = (currentChild.parentData! as! SliverPhysicalParentData).paintOffset
            let isHit = result.addWithAxisOffset(
                paintOffset: paintOffset,
                mainAxisOffset: childMainAxisPosition(currentChild),
                crossAxisOffset: childCrossAxisPosition(currentChild),
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition,
                hitTest: currentChild.hitTest
            )
            if isHit {
                return true
            }
            child = childBefore(currentChild)
        }
        return false
    }
}

// =============================================================================
// MARK: - _assertOutOfExtent
// =============================================================================

/// Asserts that the given extent is positive. Throws a `FlutterError` if the
/// extent has been exhausted, indicating that a `SliverCrossAxisGroup` ran out
/// of cross-axis space before all children could be laid out.
///
/// **Dart Source:** `sliver_group.dart:181-198`
@discardableResult
private func _assertOutOfExtent(_ extent: Double) -> Bool {
    if extent <= 0.0 {
        let error = FlutterError(fromParts: [
            ErrorSummary(
                "SliverCrossAxisGroup ran out of extent before child could be laid out."
            ),
            ErrorDescription(
                "SliverCrossAxisGroup lays out any slivers with a constrained cross "
                + "axis before laying out those which expand. In this case, cross axis "
                + "extent was used up before the next sliver could be laid out."
            ),
            ErrorHint(
                "Make sure that the total amount of extent allocated by constrained "
                + "child slivers does not exceed the cross axis extent that is available "
                + "for the SliverCrossAxisGroup."
            ),
        ])
        fatalError("\(error)")
    }
    return true
}

// =============================================================================
// MARK: - RenderSliverMainAxisGroup
// =============================================================================

/// A sliver that places multiple sliver children in a linear array along the
/// main axis.
///
/// The layout algorithm lays out slivers one by one. If the sliver is at the
/// top of the viewport or above the top, then we pass in a nonzero
/// `SliverConstraints.scrollOffset` to inform the sliver at what point along
/// the main axis we should start layout. For the slivers that come after it,
/// we compute the amount of space taken up so far to be used as the
/// `SliverPhysicalParentData.paintOffset` and the
/// `SliverConstraints.remainingPaintExtent` to be passed in as a constraint.
///
/// Finally, this sliver will also ensure that all child slivers are painted
/// within the total scroll extent of the group by adjusting the child's
/// `SliverPhysicalParentData.paintOffset` as necessary. This can happen for
/// slivers such as `SliverPersistentHeader` which, when pinned, positions
/// itself at the top of the `Viewport` regardless of the scroll offset.
///
/// In Dart, `RenderSliverMainAxisGroup` extends `RenderSliver` and mixes in
/// `ContainerRenderObjectMixin<RenderSliver, SliverPhysicalContainerParentData>`.
/// In Swift, the container child management is implemented directly on the
/// class.
///
/// **Dart Source:** `sliver_group.dart:215-486`
open class RenderSliverMainAxisGroup: RenderSliver {

    // MARK: - Container child management (ContainerRenderObjectMixin)

    /// The first child in the child list.
    ///
    /// **Dart Source:** object.dart:4222 (ContainerRenderObjectMixin)
    public private(set) var firstChild: RenderSliver?

    /// The last child in the child list.
    ///
    /// **Dart Source:** object.dart:4223 (ContainerRenderObjectMixin)
    public private(set) var lastChild: RenderSliver?

    /// The number of children.
    ///
    /// **Dart Source:** object.dart:4226 (ContainerRenderObjectMixin)
    public private(set) var childCount: Int = 0

    /// Returns the next sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4393 (ContainerRenderObjectMixin)
    public func childAfter(_ child: RenderSliver) -> RenderSliver? {
        let parentData = child.parentData as! SliverPhysicalContainerParentData
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
    public func childBefore(_ child: RenderSliver) -> RenderSliver? {
        let parentData = child.parentData as! SliverPhysicalContainerParentData
        return parentData.previousSibling
    }

    /// Inserts a child into the linked list.
    ///
    /// **Dart Source:** object.dart:4234-4268 (ContainerRenderObjectMixin._insertIntoChildList)
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
    /// **Dart Source:** object.dart:4271-4295 (ContainerRenderObjectMixin._removeFromChildList)
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
    /// **Dart Source:** object.dart:4310-4323 (ContainerRenderObjectMixin.insert)
    public func insert(_ child: RenderSliver, after: RenderSliver? = nil) {
        setupParentData(child)
        child.parent = self
        _insertIntoChildList(child, after: after)
    }

    /// Appends all the given children to the end of the child list.
    ///
    /// **Dart Source:** object.dart:4325-4341 (ContainerRenderObjectMixin.addAll)
    public func addAll(_ children: [RenderSliver]?) {
        children?.forEach { insert($0, after: lastChild) }
    }

    /// Removes a child from the child list.
    ///
    /// **Dart Source:** object.dart:4343-4353 (ContainerRenderObjectMixin.remove)
    public func remove(_ child: RenderSliver) {
        child.parent = nil
        _removeFromChildList(child)
    }

    // MARK: - Parent Data

    /// Sets up `SliverPhysicalContainerParentData` for the given child.
    ///
    /// **Dart Source:** `sliver_group.dart:217-222`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverPhysicalContainerParentData) {
            child.parentData = SliverPhysicalContainerParentData()
        }
    }

    // MARK: - Child Scroll Offset

    /// Returns the scroll offset for the given child within this group.
    ///
    /// Computes the total scroll extent of all children before the given child,
    /// adjusted by the extent of any pinned slivers before it.
    ///
    /// **Dart Source:** `sliver_group.dart:224-248`
    open override func childScrollOffset(_ child: RenderObject) -> Double? {
        assert(child.parent === self)
        assert(child is RenderSliver)
        let extentOfPinnedSlivers = _maxScrollObstructionExtentBefore(child as! RenderSliver)
        let growthDirection = sliverConstraints.growthDirection
        switch growthDirection {
        case .forward:
            var childScrollOffset = 0.0
            var current = childBefore(child as! RenderSliver)
            while let c = current {
                childScrollOffset += c.geometry!.scrollExtent
                current = childBefore(c)
            }
            return childScrollOffset - extentOfPinnedSlivers
        case .reverse:
            var childScrollOffset = 0.0
            var current = childAfter(child as! RenderSliver)
            while let c = current {
                childScrollOffset -= c.geometry!.scrollExtent
                current = childAfter(c)
            }
            return childScrollOffset - extentOfPinnedSlivers
        }
    }

    /// Computes the maximum scroll obstruction extent of all slivers before
    /// the given child.
    ///
    /// **Dart Source:** `sliver_group.dart:250-270`
    private func _maxScrollObstructionExtentBefore(_ child: RenderSliver) -> Double {
        let growthDirection = child.sliverConstraints.growthDirection
        switch growthDirection {
        case .forward:
            var pinnedExtent = 0.0
            var current: RenderSliver? = firstChild
            while current !== child {
                pinnedExtent += current!.geometry!.maxScrollObstructionExtent
                current = childAfter(current!)
            }
            return pinnedExtent
        case .reverse:
            var pinnedExtent = 0.0
            var current: RenderSliver? = lastChild
            while current !== child {
                pinnedExtent += current!.geometry!.maxScrollObstructionExtent
                current = childBefore(current!)
            }
            return pinnedExtent
        }
    }

    // MARK: - Child Position Methods

    /// Returns the main axis position of the child from its paint offset.
    ///
    /// For up/left axis directions, the position is computed relative to
    /// the end of the parent's paint extent.
    ///
    /// **Dart Source:** `sliver_group.dart:272-286`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        let childSliver = child as! RenderSliver
        let childParentData = child.parentData! as! SliverPhysicalParentData
        switch applyGrowthDirectionToAxisDirection(
            childSliver.sliverConstraints.axisDirection,
            childSliver.sliverConstraints.growthDirection
        ) {
        case .down:
            return childParentData.paintOffset.dy
        case .right:
            return childParentData.paintOffset.dx
        case .up:
            return geometry!.paintExtent - childSliver.geometry!.paintExtent
                - childParentData.paintOffset.dy
        case .left:
            return geometry!.paintExtent - childSliver.geometry!.paintExtent
                - childParentData.paintOffset.dx
        }
    }

    /// Returns the cross axis position of the child.
    ///
    /// For a main-axis group, all children share the same cross axis position
    /// (0.0).
    ///
    /// **Dart Source:** `sliver_group.dart:288-289`
    open override func childCrossAxisPosition(_ child: RenderObject) -> Double {
        return 0.0
    }

    // MARK: - Layout

    /// Performs the sequential layout of children along the main axis.
    ///
    /// Lays out each child in order (forward or reverse depending on growth
    /// direction), computing scroll offsets, paint offsets, and remaining
    /// paint/cache extents for each child. Handles scroll offset corrections,
    /// adjusts paint offsets for children that paint outside the group bounds,
    /// and finally adjusts paint offsets based on the resolved axis direction.
    ///
    /// **Dart Source:** `sliver_group.dart:291-426`
    open override func performLayout() {
        let constraints = self.sliverConstraints
        var scrollOffset = 0.0
        var layoutOffset = 0.0
        var maxPaintExtent = 0.0
        var paintOffset = constraints.overlap
        var maxScrollObstructionExtent = 0.0

        let leadingChild: RenderSliver?
        let advance: (RenderSliver) -> RenderSliver?
        switch constraints.growthDirection {
        case .forward:
            leadingChild = firstChild
            advance = childAfter
        case .reverse:
            leadingChild = lastChild
            advance = childBefore
        }

        var child = leadingChild
        while let currentChild = child {
            let beforeOffsetPaintExtent = calculatePaintOffset(
                constraints,
                from: 0.0,
                to: scrollOffset
            )
            currentChild.layout(
                constraints.copyWith(
                    scrollOffset: max(0.0, constraints.scrollOffset - scrollOffset),
                    precedingScrollExtent: scrollOffset + constraints.precedingScrollExtent,
                    overlap: max(
                        0.0,
                        RenderSliverMainAxisGroup._fixPrecisionError(
                            paintOffset - beforeOffsetPaintExtent
                        )
                    ),
                    remainingPaintExtent: RenderSliverMainAxisGroup._fixPrecisionError(
                        constraints.remainingPaintExtent - beforeOffsetPaintExtent
                    ),
                    remainingCacheExtent: RenderSliverMainAxisGroup._fixPrecisionError(
                        constraints.remainingCacheExtent
                            - calculateCacheOffset(constraints, from: 0.0, to: scrollOffset)
                    ),
                    cacheOrigin: min(0.0, constraints.cacheOrigin + scrollOffset)
                ),
                parentUsesSize: true
            )

            let childLayoutGeometry = currentChild.geometry!

            if let scrollOffsetCorrection = childLayoutGeometry.scrollOffsetCorrection {
                geometry = SliverGeometry(scrollOffsetCorrection: scrollOffsetCorrection)
                return
            }

            assert(childLayoutGeometry.debugAssertIsValid())

            let childPaintOffset = layoutOffset + childLayoutGeometry.paintOrigin
            let childParentData = currentChild.parentData! as! SliverPhysicalParentData
            switch constraints.axis {
            case .vertical:
                childParentData.paintOffset = Offset(0.0, childPaintOffset)
            case .horizontal:
                childParentData.paintOffset = Offset(childPaintOffset, 0.0)
            }
            scrollOffset += childLayoutGeometry.scrollExtent
            layoutOffset += childLayoutGeometry.layoutExtent
            maxPaintExtent += childLayoutGeometry.maxPaintExtent
            maxScrollObstructionExtent += childLayoutGeometry.maxScrollObstructionExtent
            paintOffset = max(childPaintOffset + childLayoutGeometry.paintExtent, paintOffset)
            child = advance(currentChild)
            assert({
                if child != nil && maxPaintExtent.isInfinite {
                    let error = FlutterError(
                        "Unreachable sliver found, you may have a sliver following "
                        + "a sliver with an infinite extent. "
                    )
                    fatalError("\(error)")
                }
                return true
            }())
        }

        let remainingExtent = max(0.0, scrollOffset - constraints.scrollOffset)
        // If the children's paint extent exceeds the remaining scroll extent of the
        // RenderSliverMainAxisGroup, they need to be corrected.
        if paintOffset > remainingExtent {
            let paintCorrection = paintOffset - remainingExtent
            paintOffset = remainingExtent
            child = firstChild
            while let currentChild = child {
                let childLayoutGeometry = currentChild.geometry!
                let childIsTooLarge = childLayoutGeometry.paintExtent > remainingExtent
                let pinnedHeadersOverflow = maxScrollObstructionExtent > remainingExtent
                let childIsPinnedHeader = childLayoutGeometry.maxScrollObstructionExtent > 0
                if childIsTooLarge || (pinnedHeadersOverflow && childIsPinnedHeader) {
                    let childParentData =
                        currentChild.parentData! as! SliverPhysicalParentData
                    switch constraints.axis {
                    case .vertical:
                        childParentData.paintOffset = Offset(
                            0.0,
                            childParentData.paintOffset.dy - paintCorrection
                        )
                    case .horizontal:
                        childParentData.paintOffset = Offset(
                            childParentData.paintOffset.dx - paintCorrection,
                            0.0
                        )
                    }
                }
                child = childAfter(currentChild)
            }
        }

        let cacheExtent = calculateCacheOffset(
            constraints,
            from: min(constraints.scrollOffset, 0),
            to: scrollOffset
        )
        let paintExtent = clampDouble(paintOffset, 0, constraints.remainingPaintExtent)

        geometry = SliverGeometry(
            scrollExtent: scrollOffset,
            paintExtent: paintExtent,
            maxPaintExtent: maxPaintExtent,
            hasVisualOverflow:
                scrollOffset > constraints.remainingPaintExtent
                || constraints.scrollOffset > 0.0,
            cacheExtent: cacheExtent
        )

        // Update the children's paintOffset based on the direction again, which
        // must be done after obtaining the `paintExtent`.
        child = leadingChild
        while let currentChild = child {
            let childParentData = currentChild.parentData! as! SliverPhysicalParentData
            switch applyGrowthDirectionToAxisDirection(
                constraints.axisDirection,
                constraints.growthDirection
            ) {
            case .up:
                childParentData.paintOffset = Offset(
                    0.0,
                    paintExtent - childParentData.paintOffset.dy
                        - currentChild.geometry!.paintExtent
                )
            case .left:
                childParentData.paintOffset = Offset(
                    paintExtent - childParentData.paintOffset.dx
                        - currentChild.geometry!.paintExtent,
                    0.0
                )
            case .right, .down:
                break // paintOffset stays as is
            }
            child = advance(currentChild)
        }
    }

    // MARK: - Painting

    /// Paints all visible children in reverse order (last to first).
    ///
    /// **Dart Source:** `sliver_group.dart:428-439`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        var child = lastChild
        while let currentChild = child {
            if currentChild.geometry!.visible {
                let childParentData = currentChild.parentData! as! SliverPhysicalParentData
                context.paintChild(currentChild, offset + childParentData.paintOffset)
            }
            child = childBefore(currentChild)
        }
    }

    // MARK: - Paint Transform

    /// Applies the paint transform for a child using its parent data paint
    /// offset.
    ///
    /// **Dart Source:** `sliver_group.dart:441-445`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        let childParentData = child.parentData! as! SliverPhysicalParentData
        childParentData.applyPaintTransform(&transform)
    }

    // MARK: - Hit Testing

    /// Hit tests children in forward order (first to last).
    ///
    /// **Dart Source:** `sliver_group.dart:447-470`
    open override func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        var child = firstChild
        while let currentChild = child {
            let paintOffset = (currentChild.parentData! as! SliverPhysicalParentData).paintOffset
            let isHit = result.addWithAxisOffset(
                paintOffset: paintOffset,
                mainAxisOffset: childMainAxisPosition(currentChild),
                crossAxisOffset: childCrossAxisPosition(currentChild),
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition,
                hitTest: currentChild.hitTest
            )
            if isHit {
                return true
            }
            child = childAfter(currentChild)
        }
        return false
    }

    // MARK: - Semantics

    /// Visits children for semantics, including those that are visible,
    /// have cache extent, or ensure semantics.
    ///
    /// **Dart Source:** `sliver_group.dart:472-481`
    open func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        var child = firstChild
        while let currentChild = child {
            if currentChild.geometry!.visible
                || currentChild.geometry!.cacheExtent > 0.0
                || currentChild.ensureSemantics
            {
                visitor(currentChild)
            }
            child = childAfter(currentChild)
        }
    }

    // MARK: - Precision Fix

    /// Fixes floating-point precision errors by rounding near-zero values to
    /// exactly zero.
    ///
    /// **Dart Source:** `sliver_group.dart:483-485`
    private static func _fixPrecisionError(_ number: Double) -> Double {
        return Swift.abs(number) < precisionErrorTolerance ? 0.0 : number
    }
}
