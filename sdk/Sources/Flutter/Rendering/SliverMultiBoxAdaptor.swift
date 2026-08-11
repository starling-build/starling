// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Sliver multi-box adaptor types for managing lazily-created box children
/// in a sliver.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/sliver_multi_box_adaptor.dart`

import FlutterSwiftBridge

// MARK: - RenderSliverBoxChildManager

/// A delegate used by `RenderSliverMultiBoxAdaptor` to manage its children.
///
/// `RenderSliverMultiBoxAdaptor` objects reify their children lazily to avoid
/// spending resources on children that are not visible in the viewport. This
/// delegate lets these objects create and remove children as well as estimate
/// the total scroll offset extent occupied by the full child list.
///
/// **Dart Source:** `sliver_multi_box_adaptor.dart:25-137`
public protocol RenderSliverBoxChildManager: AnyObject {

    /// Called during layout when a new child is needed. The child should be
    /// inserted into the child list in the appropriate position, after the
    /// `after` child (at the start of the list if `after` is nil). Its index and
    /// scroll offsets will automatically be set appropriately.
    ///
    /// The `index` argument gives the index of the child to show. It is possible
    /// for negative indices to be requested.
    ///
    /// If no child corresponds to `index`, then do nothing.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:51`
    func createChild(_ index: Int, after: RenderBox?)

    /// Remove the given child from the child list.
    ///
    /// Called by `RenderSliverMultiBoxAdaptor.collectGarbage`, which itself is
    /// called from `RenderSliverMultiBoxAdaptor`'s `performLayout`.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:62`
    func removeChild(_ child: RenderBox)

    /// Called to estimate the total scrollable extents of this object.
    ///
    /// Must return the total distance from the start of the child with the
    /// earliest possible index to the end of the child with the last possible
    /// index.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:69-75`
    func estimateMaxScrollOffset(
        _ constraints: SliverConstraints,
        firstIndex: Int?,
        lastIndex: Int?,
        leadingScrollOffset: Double?,
        trailingScrollOffset: Double?
    ) -> Double

    /// Called to obtain a precise measure of the total number of children.
    ///
    /// Must return the number that is one greater than the greatest `index` for
    /// which `createChild` will actually create a child.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:87`
    var childCount: Int { get }

    /// The best available estimate of `childCount`, or nil if no estimate
    /// is available.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:98`
    var estimatedChildCount: Int? { get }

    /// Called during `RenderSliverMultiBoxAdaptor.adoptChild` or
    /// `RenderSliverMultiBoxAdaptor.move`.
    ///
    /// Subclasses must ensure that the `SliverMultiBoxAdaptorParentData.index`
    /// field of the child's `RenderObject.parentData` accurately reflects the
    /// child's index in the child list after this function returns.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:106`
    func didAdoptChild(_ child: RenderBox)

    /// Called during layout to indicate whether this object provided insufficient
    /// children for the `RenderSliverMultiBoxAdaptor` to fill the
    /// `SliverConstraints.remainingPaintExtent`.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:119`
    func setDidUnderflow(_ value: Bool)

    /// Called at the beginning of layout to indicate that layout is about to
    /// occur.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:123`
    func didStartLayout()

    /// Called at the end of layout to indicate that layout is now complete.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:126`
    func didFinishLayout()

    /// In debug mode, asserts that this manager is not expecting any
    /// modifications to the `RenderSliverMultiBoxAdaptor`'s child list.
    ///
    /// This function always returns true.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:136`
    func debugAssertChildListLocked() -> Bool
}

/// Default implementations for `RenderSliverBoxChildManager`.
extension RenderSliverBoxChildManager {

    /// **Dart Source:** `sliver_multi_box_adaptor.dart:98`
    public var estimatedChildCount: Int? { nil }

    /// **Dart Source:** `sliver_multi_box_adaptor.dart:123`
    public func didStartLayout() {}

    /// **Dart Source:** `sliver_multi_box_adaptor.dart:126`
    public func didFinishLayout() {}

    /// **Dart Source:** `sliver_multi_box_adaptor.dart:136`
    public func debugAssertChildListLocked() -> Bool { true }
}

// MARK: - KeepAliveParentDataMixin

/// Protocol for parent data that supports keeping a child alive even when
/// it is no longer visible.
///
/// In Dart this is a mixin `KeepAliveParentDataMixin` on `ParentData`.
///
/// **Dart Source:** `sliver_multi_box_adaptor.dart:140-147`
public protocol KeepAliveParentDataMixin: AnyObject {

    /// Whether to keep the child alive even when it is no longer visible.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:142`
    var keepAlive: Bool { get set }

    /// Whether the widget is currently being kept alive, i.e. has `keepAlive`
    /// set to true and is offscreen.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:146`
    var keptAlive: Bool { get }
}

// MARK: - RenderSliverWithKeepAliveMixin

/// Protocol to dissociate `KeepAlive` from `RenderSliverMultiBoxAdaptor`.
///
/// Types conforming to this protocol must ensure `setupParentData` uses
/// a parentData class that conforms to `KeepAliveParentDataMixin`.
///
/// In Dart this is a mixin on `RenderSliver`.
///
/// **Dart Source:** `sliver_multi_box_adaptor.dart:153-160`
public protocol RenderSliverWithKeepAliveMixin: AnyObject {
    func setupParentData(_ child: RenderObject)
}

// MARK: - SliverMultiBoxAdaptorParentData

/// Parent data structure used by `RenderSliverMultiBoxAdaptor`.
///
/// Combines `SliverLogicalParentData` with `ContainerParentDataProtocol`
/// for linked-list child management and `KeepAliveParentDataMixin` for
/// keep-alive support.
///
/// **Dart Source:** `sliver_multi_box_adaptor.dart:163-174`
public class SliverMultiBoxAdaptorParentData: SliverLogicalParentData,
    ContainerParentDataProtocol, KeepAliveParentDataMixin
{
    public typealias ChildType = RenderBox

    /// The previous sibling in the parent's child list.
    ///
    /// `weak`: see ContainerBoxParentData.previousSibling — a strong
    /// back-pointer makes adjacent children a retain cycle under ARC.
    ///
    /// **Dart Source:** via `ContainerParentDataMixin<RenderBox>`
    public weak var previousSibling: RenderBox?

    /// The next sibling in the parent's child list.
    ///
    /// **Dart Source:** via `ContainerParentDataMixin<RenderBox>`
    public var nextSibling: RenderBox?

    /// The index of this child according to the `RenderSliverBoxChildManager`.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:166`
    public var index: Int?

    /// Whether to keep the child alive even when it is no longer visible.
    ///
    /// **Dart Source:** via `KeepAliveParentDataMixin`
    public var keepAlive: Bool = false

    /// Whether the widget is currently being kept alive, i.e. has `keepAlive`
    /// set to true and is offscreen.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:169-170`
    public var keptAlive: Bool { _keptAlive }

    /// Internal backing for `keptAlive`.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:170`
    internal var _keptAlive: Bool = false

    /// **Dart Source:** `sliver_multi_box_adaptor.dart:173`
    public override var description: String {
        "index=\(index.map { String($0) } ?? "nil"); \(keepAlive ? "keepAlive; " : "")\(super.description)"
    }
}

// MARK: - RenderSliverMultiBoxAdaptor

/// A sliver with multiple box children.
///
/// `RenderSliverMultiBoxAdaptor` is a base class for slivers that have multiple
/// box children. The children are managed by a `RenderSliverBoxChildManager`,
/// which lets subclasses create children lazily during layout. Typically
/// subclasses will create only those children that are actually needed to fill
/// the `SliverConstraints.remainingPaintExtent`.
///
/// The contract for adding and removing children from this render object is
/// more strict than for normal render objects:
///
/// * Children can be removed except during a layout pass if they have already
///   been laid out during that layout pass.
/// * Children cannot be added except during a call to `childManager`, and
///   then only if there is no child corresponding to that index (or the child
///   corresponding to that index was first removed).
///
/// In Dart, this class extends `RenderSliver` with the mixins
/// `ContainerRenderObjectMixin<RenderBox, SliverMultiBoxAdaptorParentData>`,
/// `RenderSliverHelpers`, and `RenderSliverWithKeepAliveMixin`.
/// In Swift, `ContainerRenderObjectMixin` is implemented inline (linked-list
/// pattern), and `RenderSliverHelpers` / `RenderSliverWithKeepAliveMixin` are
/// adopted as protocol conformances.
///
/// **Dart Source:** `sliver_multi_box_adaptor.dart:201-819`
open class RenderSliverMultiBoxAdaptor: RenderSliver,
    RenderSliverHelpers, RenderSliverWithKeepAliveMixin
{

    // =========================================================================
    // MARK: - Initializer
    // =========================================================================

    /// Creates a sliver with multiple box children.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:207-213`
    public init(childManager: RenderSliverBoxChildManager) {
        self._childManager = childManager
        super.init()
    }

    // =========================================================================
    // MARK: - Parent Data
    // =========================================================================

    /// Sets up `SliverMultiBoxAdaptorParentData` for the given child.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:216-219`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is SliverMultiBoxAdaptorParentData) {
            child.parentData = SliverMultiBoxAdaptorParentData()
        }
    }

    // =========================================================================
    // MARK: - Child Manager
    // =========================================================================

    /// The delegate that manages the children of this object.
    ///
    /// Rather than having a concrete list of children, a
    /// `RenderSliverMultiBoxAdaptor` uses a `RenderSliverBoxChildManager` to
    /// create children during layout in order to fill the
    /// `SliverConstraints.remainingPaintExtent`.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:229-230`
    public var childManager: RenderSliverBoxChildManager { _childManager }
    private let _childManager: RenderSliverBoxChildManager

    // =========================================================================
    // MARK: - Keep-Alive Bucket
    // =========================================================================

    /// The nodes being kept alive despite not being visible.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:233`
    private var _keepAliveBucket: [Int: RenderBox] = [:]

    // =========================================================================
    // MARK: - Debug Child Integrity
    // =========================================================================

    /// Indicates whether integrity check is enabled.
    ///
    /// Setting this property to true will immediately perform an integrity check.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:245-253`
    public var debugChildIntegrityEnabled: Bool {
        get { _debugChildIntegrityEnabled }
        set {
            assert({
                _debugChildIntegrityEnabled = newValue
                return _debugVerifyChildOrder()
            }())
        }
    }
    private var _debugChildIntegrityEnabled: Bool = true

    /// Verify that the child list index is in strictly increasing order.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:270-281`
    private func _debugVerifyChildOrder() -> Bool {
        if _debugChildIntegrityEnabled {
            var child = firstChild
            while child != nil {
                let currentIndex = indexOf(child!)
                let next = childAfter(child!)
                if let next = next {
                    assert(indexOf(next) > currentIndex)
                }
                child = next
            }
        }
        return true
    }

    private func _debugAssertChildListLocked() -> Bool {
        return childManager.debugAssertChildListLocked()
    }

    // =========================================================================
    // MARK: - Container Child Management (ContainerRenderObjectMixin pattern)
    // =========================================================================

    /// The first child in the child list.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public private(set) var firstChild: RenderBox?

    /// The last child in the child list.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public private(set) var lastChild: RenderBox?

    /// The number of children in the child list.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public private(set) var childCount: Int = 0

    /// Returns the next sibling of the given child.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public func childAfter(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as! SliverMultiBoxAdaptorParentData
        return parentData.nextSibling
    }

    /// Returns the previous sibling of the given child.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public func childBefore(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as! SliverMultiBoxAdaptorParentData
        return parentData.previousSibling
    }

    /// Inserts a child into the linked list.
    ///
    /// **Dart Source:** `object.dart:4234-4268` (ContainerRenderObjectMixin._insertIntoChildList)
    private func _insertIntoChildList(_ child: RenderBox, after: RenderBox? = nil) {
        let childParentData = child.parentData as! SliverMultiBoxAdaptorParentData
        childCount += 1
        assert(childCount > 0)
        if let after = after {
            let afterParentData = after.parentData as! SliverMultiBoxAdaptorParentData
            childParentData.nextSibling = afterParentData.nextSibling
            if let nextSibling = afterParentData.nextSibling {
                let nextParentData = nextSibling.parentData as! SliverMultiBoxAdaptorParentData
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
                let firstParentData = first.parentData as! SliverMultiBoxAdaptorParentData
                firstParentData.previousSibling = child
            }
            firstChild = child
            lastChild = lastChild ?? child
        }
    }

    /// Removes a child from the linked list.
    ///
    /// **Dart Source:** `object.dart:4271-4295` (ContainerRenderObjectMixin._removeFromChildList)
    private func _removeFromChildList(_ child: RenderBox) {
        let childParentData = child.parentData as! SliverMultiBoxAdaptorParentData
        if childParentData.previousSibling == nil {
            firstChild = childParentData.nextSibling
        } else {
            let previousParentData =
                childParentData.previousSibling!.parentData as! SliverMultiBoxAdaptorParentData
            previousParentData.nextSibling = childParentData.nextSibling
        }
        if childParentData.nextSibling == nil {
            lastChild = childParentData.previousSibling
        } else {
            let nextParentData =
                childParentData.nextSibling!.parentData as! SliverMultiBoxAdaptorParentData
            nextParentData.previousSibling = childParentData.previousSibling
        }
        childParentData.previousSibling = nil
        childParentData.nextSibling = nil
        childCount -= 1
    }

    /// Adds a child to the child list, optionally after the given child.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:284-289`
    public func insert(_ child: RenderBox, after: RenderBox? = nil) {
        assert(!_keepAliveBucket.values.contains(where: { $0 === child }))
        setupParentData(child)
        child.parent = self
        adoptChild(child)
        _insertIntoChildList(child, after: after)
        assert(firstChild != nil)
        assert(_debugVerifyChildOrder())
    }

    /// Moves a child in the child list, handling keep-alive scenarios.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:292-333`
    public func move(_ child: RenderBox, after: RenderBox? = nil) {
        let childParentData = child.parentData! as! SliverMultiBoxAdaptorParentData
        if !childParentData.keptAlive {
            _removeFromChildList(child)
            _insertIntoChildList(child, after: after)
            childManager.didAdoptChild(child)
            markNeedsLayout()
        } else {
            // If the child in the bucket is the current child, remove it.
            if _keepAliveBucket[childParentData.index!] === child {
                _keepAliveBucket.removeValue(forKey: childParentData.index!)
            }
            // Update the slot and reinsert back to _keepAliveBucket in the new slot.
            childManager.didAdoptChild(child)
            _keepAliveBucket[childParentData.index!] = child
        }
    }

    /// Removes a child from the child list.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:336-350`
    public func remove(_ child: RenderBox) {
        let childParentData = child.parentData! as! SliverMultiBoxAdaptorParentData
        if !childParentData._keptAlive {
            _removeFromChildList(child)
            dropChild(child)
            return
        }
        assert(_keepAliveBucket[childParentData.index!] === child)
        _keepAliveBucket.removeValue(forKey: childParentData.index!)
        dropChild(child)
    }

    /// Removes all children from the child list and the keep-alive bucket.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:353-357`
    public func removeAll() {
        var child = firstChild
        while let current = child {
            let next = childAfter(current)
            _removeFromChildList(current)
            dropChild(current)
            child = next
        }
        firstChild = nil
        lastChild = nil
        childCount = 0
        for keptAliveChild in _keepAliveBucket.values {
            dropChild(keptAliveChild)
        }
        _keepAliveBucket.removeAll()
    }

    // =========================================================================
    // MARK: - Adopt / Drop Child
    // =========================================================================

    /// Sets up parent data and parent reference for a child.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:256-263`
    public override func adoptChild(_ child: RenderObject) {
        super.adoptChild(child)
        let childParentData = child.parentData! as! SliverMultiBoxAdaptorParentData
        if !childParentData._keptAlive {
            childManager.didAdoptChild(child as! RenderBox)
        }
    }

    /// Removes a child's parent association.
    ///
    /// **Dart Source:** via `RenderObject.dropChild`
    public override func dropChild(_ child: RenderObject) {
        super.dropChild(child)
    }

    /// Increments the depth of the given child.
    ///
    /// **Dart Source:** via `RenderObject.redepthChild`
    public func redepthChild(_ child: RenderObject) {
        // In the full framework, this adjusts the depth field.
    }

    // =========================================================================
    // MARK: - Create / Destroy or Cache Child
    // =========================================================================

    /// Creates a child at the given index, or obtains it from the keep-alive
    /// bucket if available.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:359-375`
    private func _createOrObtainChild(_ index: Int, after: RenderBox?) {
        invokeLayoutCallback { [self] (_: SliverConstraints) in
            if _keepAliveBucket.keys.contains(index) {
                let child = _keepAliveBucket.removeValue(forKey: index)!
                let childParentData = child.parentData! as! SliverMultiBoxAdaptorParentData
                assert(childParentData._keptAlive)
                dropChild(child)
                child.parentData = childParentData
                insert(child, after: after)
                childParentData._keptAlive = false
            } else {
                _childManager.createChild(index, after: after)
            }
        }
    }

    /// Destroys the given child, or caches it in the keep-alive bucket.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:377-392`
    private func _destroyOrCacheChild(_ child: RenderBox) {
        let childParentData = child.parentData! as! SliverMultiBoxAdaptorParentData
        if childParentData.keepAlive {
            assert(!childParentData._keptAlive)
            remove(child)
            _keepAliveBucket[childParentData.index!] = child
            child.parentData = childParentData
            adoptChild(child)
            childParentData._keptAlive = true
        } else {
            assert(child.parent === self)
            _childManager.removeChild(child)
            assert(child.parent == nil)
        }
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

    // =========================================================================
    // MARK: - Attach / Detach
    // =========================================================================

    /// Called when the object is attached to a pipeline owner.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:395-399`
    open override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        for child in _keepAliveBucket.values {
            child.attach(owner)
        }
    }

    /// Called when the object is detached from its pipeline owner.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:402-406`
    open override func detach() {
        super.detach()
        for child in _keepAliveBucket.values {
            child.detach()
        }
    }

    // =========================================================================
    // MARK: - Redepth / Visit Children
    // =========================================================================

    /// Adjusts the depth of all children including those in the keep-alive
    /// bucket.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:409-412`
    public func redepthChildren() {
        var child = firstChild
        while let current = child {
            redepthChild(current)
            child = childAfter(current)
        }
        _keepAliveBucket.values.forEach(redepthChild)
    }

    /// Visits all children including those in the keep-alive bucket.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:415-418`
    public func visitChildren(_ visitor: RenderObjectVisitor) {
        var child = firstChild
        while let current = child {
            visitor(current)
            child = childAfter(current)
        }
        _keepAliveBucket.values.forEach(visitor)
    }

    /// Visits only the children that are visible (not those in the keep-alive
    /// bucket).
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:421-424`
    public func visitChildrenForSemantics(_ visitor: RenderObjectVisitor) {
        var child = firstChild
        while let current = child {
            visitor(current)
            child = childAfter(current)
        }
        // Do not visit children in _keepAliveBucket.
    }

    // =========================================================================
    // MARK: - Semantic Bounds
    // =========================================================================

    /// The semantic bounds of this sliver.
    ///
    /// If the sliver is not visible but has a first child with a size, reports
    /// the bounds of the first child. This is necessary for accessibility
    /// technologies to reach this sliver even when it is outside the current
    /// viewport and cache extent.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:429-438`
    open override var semanticBounds: Rect {
        if let geo = geometry, !geo.visible, let first = firstChild, first.hasSize {
            return first.paintBounds
        }
        return super.semanticBounds
    }

    // =========================================================================
    // MARK: - Add / Insert Children
    // =========================================================================

    /// Called during layout to create and add the child with the given index and
    /// scroll offset.
    ///
    /// Returns false if there was no cached child and `createChild` did not add
    /// any child, otherwise returns true.
    ///
    /// Does not layout the new child.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:457-471`
    public func addInitialChild(index: Int = 0, layoutOffset: Double = 0.0) -> Bool {
        assert(_debugAssertChildListLocked())
        assert(firstChild == nil)
        _createOrObtainChild(index, after: nil)
        if let first = firstChild {
            assert(first === lastChild)
            assert(indexOf(first) == index)
            let firstChildParentData =
                first.parentData! as! SliverMultiBoxAdaptorParentData
            firstChildParentData.layoutOffset = layoutOffset
            return true
        }
        childManager.setDidUnderflow(true)
        return false
    }

    /// Called during layout to create, add, and layout the child before
    /// `firstChild`.
    ///
    /// Returns the new child or nil if no child was obtained.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:487-500`
    public func insertAndLayoutLeadingChild(
        _ childConstraints: BoxConstraints,
        parentUsesSize: Bool = false
    ) -> RenderBox? {
        assert(_debugAssertChildListLocked())
        let index = indexOf(firstChild!) - 1
        _createOrObtainChild(index, after: nil)
        if indexOf(firstChild!) == index {
            firstChild!.layout(childConstraints, parentUsesSize: parentUsesSize)
            return firstChild
        }
        childManager.setDidUnderflow(true)
        return nil
    }

    /// Called during layout to create, add, and layout the child after
    /// the given child.
    ///
    /// Returns the new child. It is the responsibility of the caller to configure
    /// the child's scroll offset.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:515-531`
    public func insertAndLayoutChild(
        _ childConstraints: BoxConstraints,
        after: RenderBox,
        parentUsesSize: Bool = false
    ) -> RenderBox? {
        assert(_debugAssertChildListLocked())
        let index = indexOf(after) + 1
        _createOrObtainChild(index, after: after)
        let child = childAfter(after)
        if let child = child, indexOf(child) == index {
            child.layout(childConstraints, parentUsesSize: parentUsesSize)
            return child
        }
        childManager.setDidUnderflow(true)
        return nil
    }

    // =========================================================================
    // MARK: - Garbage Collection
    // =========================================================================

    /// Returns the number of children preceding the `firstIndex` that need to
    /// be garbage collected.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:544-552`
    public func calculateLeadingGarbage(firstIndex: Int) -> Int {
        var walker = firstChild
        var leadingGarbage = 0
        while let w = walker, indexOf(w) < firstIndex {
            leadingGarbage += 1
            walker = childAfter(w)
        }
        return leadingGarbage
    }

    /// Returns the number of children following the `lastIndex` that need to be
    /// garbage collected.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:565-573`
    public func calculateTrailingGarbage(lastIndex: Int) -> Int {
        var walker = lastChild
        var trailingGarbage = 0
        while let w = walker, indexOf(w) > lastIndex {
            trailingGarbage += 1
            walker = childBefore(w)
        }
        return trailingGarbage
    }

    /// Called after layout with the number of children that can be garbage
    /// collected at the head and tail of the child list.
    ///
    /// Children whose `SliverMultiBoxAdaptorParentData.keepAlive` property is
    /// set to true will be removed to a cache instead of being dropped.
    ///
    /// This method also collects any children that were previously kept alive but
    /// are now no longer necessary. As such, it should be called every time
    /// `performLayout` is run, even if the arguments are both zero.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:592-623`
    public func collectGarbage(_ leadingGarbage: Int, _ trailingGarbage: Int) {
        assert(_debugAssertChildListLocked())
        assert(childCount >= leadingGarbage + trailingGarbage)
        invokeLayoutCallback { [self] (_: SliverConstraints) in
            var leading = leadingGarbage
            var trailing = trailingGarbage
            while leading > 0 {
                _destroyOrCacheChild(firstChild!)
                leading -= 1
            }
            while trailing > 0 {
                _destroyOrCacheChild(lastChild!)
                trailing -= 1
            }
            // Ask the child manager to remove the children that are no longer being
            // kept alive. (This should cause _keepAliveBucket to change, so we have
            // to prepare our list ahead of time.)
            let childrenToRemove = _keepAliveBucket.values.filter { child in
                let childParentData = child.parentData! as! SliverMultiBoxAdaptorParentData
                return !childParentData.keepAlive
            }
            for child in childrenToRemove {
                _childManager.removeChild(child)
            }
        }
    }

    // =========================================================================
    // MARK: - Index / Extent Queries
    // =========================================================================

    /// Returns the index of the given child, as given by the
    /// `SliverMultiBoxAdaptorParentData.index` field of the child's `parentData`.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:627-632`
    public func indexOf(_ child: RenderBox) -> Int {
        let childParentData = child.parentData! as! SliverMultiBoxAdaptorParentData
        assert(childParentData.index != nil)
        return childParentData.index!
    }

    /// Returns the dimension of the given child in the main axis, as given by
    /// the child's `RenderBox.size` property. This is only valid after layout.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:637-643`
    public func paintExtentOf(_ child: RenderBox) -> Double {
        assert(child.hasSize)
        switch sliverConstraints.axis {
        case .horizontal:
            return child.size.width
        case .vertical:
            return child.size.height
        }
    }

    // =========================================================================
    // MARK: - Hit Testing
    // =========================================================================

    /// **Dart Source:** `sliver_multi_box_adaptor.dart:646-665`
    open override func hitTestChildren(
        _ result: SliverHitTestResult,
        mainAxisPosition: Double,
        crossAxisPosition: Double
    ) -> Bool {
        var child = lastChild
        let boxResult = BoxHitTestResult(wrapping: result)
        while let current = child {
            if hitTestBoxChild(
                boxResult,
                current,
                mainAxisPosition: mainAxisPosition,
                crossAxisPosition: crossAxisPosition
            ) {
                return true
            }
            child = childBefore(current)
        }
        return false
    }

    // =========================================================================
    // MARK: - Child Position Methods
    // =========================================================================

    /// Returns the distance from the leading visible edge of the sliver to the
    /// side of the given child closest to that edge.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:668-669`
    open override func childMainAxisPosition(_ child: RenderObject) -> Double {
        return childScrollOffset(child)! - sliverConstraints.scrollOffset
    }

    /// Returns the scroll offset for the leading edge of the given child.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:672-677`
    open override func childScrollOffset(_ child: RenderObject) -> Double? {
        assert(child.parent === self)
        let childParentData = child.parentData! as! SliverMultiBoxAdaptorParentData
        return childParentData.layoutOffset
    }

    // =========================================================================
    // MARK: - Paint Tracking
    // =========================================================================

    /// Whether this render object paints the given child.
    ///
    /// Returns false for children that are kept alive but not visible.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:681-685`
    open func paintsChild(_ child: RenderBox) -> Bool {
        let childParentData = child.parentData as? SliverMultiBoxAdaptorParentData
        return childParentData?.index != nil
            && !_keepAliveBucket.keys.contains(childParentData!.index!)
    }

    // =========================================================================
    // MARK: - Paint Transform
    // =========================================================================

    /// Applies the paint transform for the given child.
    ///
    /// If the child is not painted (e.g. kept alive but off-screen), the
    /// transform is set to zero.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:688-701`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        if !paintsChild(child as! RenderBox) {
            // This can happen if some child asks for the global transform even though
            // they are not getting painted. Set transform to zero since
            // applyPaintTransformForBoxChild would end up throwing.
            transform = Matrix4.zero()
        } else {
            applyPaintTransformForBoxChild(child as! RenderBox, &transform)
        }
    }

    // =========================================================================
    // MARK: - Paint
    // =========================================================================

    /// Paints this render object and its visible children.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:704-758`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        guard firstChild != nil else { return }

        // offset is to the top-left corner, regardless of our axis direction.
        // originOffset gives us the delta from the real origin to the origin in the axis direction.
        let mainAxisUnit: Offset
        let crossAxisUnit: Offset
        let originOffset: Offset
        let addExtent: Bool

        switch applyGrowthDirectionToAxisDirection(
            sliverConstraints.axisDirection,
            sliverConstraints.growthDirection
        ) {
        case .up:
            mainAxisUnit = Offset(0.0, -1.0)
            crossAxisUnit = Offset(1.0, 0.0)
            originOffset = offset + Offset(0.0, geometry!.paintExtent)
            addExtent = true
        case .right:
            mainAxisUnit = Offset(1.0, 0.0)
            crossAxisUnit = Offset(0.0, 1.0)
            originOffset = offset
            addExtent = false
        case .down:
            mainAxisUnit = Offset(0.0, 1.0)
            crossAxisUnit = Offset(1.0, 0.0)
            originOffset = offset
            addExtent = false
        case .left:
            mainAxisUnit = Offset(-1.0, 0.0)
            crossAxisUnit = Offset(0.0, 1.0)
            originOffset = offset + Offset(geometry!.paintExtent, 0.0)
            addExtent = true
        }

        var child = firstChild
        while let current = child {
            let mainAxisDelta = childMainAxisPosition(current)
            let crossAxisDelta = childCrossAxisPosition(current)
            var childOffset = Offset(
                originOffset.dx + mainAxisUnit.dx * mainAxisDelta + crossAxisUnit.dx * crossAxisDelta,
                originOffset.dy + mainAxisUnit.dy * mainAxisDelta + crossAxisUnit.dy * crossAxisDelta
            )
            if addExtent {
                childOffset = childOffset + Offset(
                    mainAxisUnit.dx * paintExtentOf(current),
                    mainAxisUnit.dy * paintExtentOf(current)
                )
            }

            // If the child's visible interval does not intersect the paint extent
            // interval, it's hidden.
            if mainAxisDelta < sliverConstraints.remainingPaintExtent
                && mainAxisDelta + paintExtentOf(current) > 0
            {
                context.paintChild(current, childOffset)
            }

            child = childAfter(current)
        }
    }

    // =========================================================================
    // MARK: - Debug
    // =========================================================================

    /// Asserts that the reified child list is not empty and has a contiguous
    /// sequence of indices.
    ///
    /// Always returns true.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:776-789`
    public func debugAssertChildListIsNonEmptyAndContiguous() -> Bool {
        assert({
            assert(firstChild != nil)
            var index = indexOf(firstChild!)
            var child = childAfter(firstChild!)
            while let current = child {
                index += 1
                assert(indexOf(current) == index)
                child = childAfter(current)
            }
            return true
        }())
        return true
    }

    /// Adds debug properties.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:761-770`
    open override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)
        if let first = firstChild {
            properties.add(
                DiagnosticsNode.message(
                    "currently live children: \(indexOf(first)) to \(indexOf(lastChild!))"
                )
            )
        } else {
            properties.add(
                DiagnosticsNode.message("no children current live")
            )
        }
    }

    /// Describes the children for debug output, including kept-alive children.
    ///
    /// **Dart Source:** `sliver_multi_box_adaptor.dart:792-818`
    public func debugDescribeChildren() -> [DiagnosticsNode] {
        var children: [DiagnosticsNode] = []
        if let first = firstChild {
            var child: RenderBox? = first
            while true {
                let childParentData = child!.parentData! as! SliverMultiBoxAdaptorParentData
                children.append(
                    DiagnosticsNode.message(
                        "child with index \(childParentData.index ?? -1)"
                    )
                )
                if child === lastChild {
                    break
                }
                child = childParentData.nextSibling
            }
        }
        if !_keepAliveBucket.isEmpty {
            let indices = _keepAliveBucket.keys.sorted()
            for index in indices {
                children.append(
                    DiagnosticsNode.message(
                        "child with index \(index) (kept alive but not laid out)",
                        style: .offstage
                    )
                )
            }
        }
        return children
    }
}
