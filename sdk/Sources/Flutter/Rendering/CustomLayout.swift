// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Custom multi-child layout delegate and parent data types.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/custom_layout.dart`

import FlutterSwiftBridge

// MARK: - MultiChildLayoutParentData

/// `ParentData` used by `RenderCustomMultiChildLayoutBox`.
///
/// Each child of a `RenderCustomMultiChildLayoutBox` must be wrapped in a
/// `LayoutId` widget to assign the id that identifies it to the delegate.
///
/// **Dart Source:** custom_layout.dart:17-24
public class MultiChildLayoutParentData: ContainerBoxParentData<RenderBox> {

    /// An object representing the identity of this child.
    ///
    /// **Dart Source:** custom_layout.dart:20
    public var id: AnyHashable?

    /// A string representation of this parent data.
    ///
    /// **Dart Source:** custom_layout.dart:22-23
    public override var description: String {
        "\(super.description); id=\(id as Any)"
    }
}

// MARK: - MultiChildLayoutDelegate

/// A delegate that controls the layout of multiple children.
///
/// Used with `CustomMultiChildLayout` (in the widgets library) and
/// `RenderCustomMultiChildLayoutBox` (in the rendering library).
///
/// Delegates must be idempotent. Specifically, if two delegates are equal, then
/// they must produce the same layout. To change the layout, replace the
/// delegate with a different instance whose `shouldRelayout` returns true when
/// given the previous instance.
///
/// Override `getSize` to control the overall size of the layout. The size of
/// the layout cannot depend on layout properties of the children.
///
/// Override `performLayout` to size and position the children. An
/// implementation of `performLayout` must call `layoutChild` exactly once for
/// each child, but it may call `layoutChild` on children in an arbitrary order.
///
/// Override `shouldRelayout` to determine when the layout of the children needs
/// to be recomputed when the delegate changes.
///
/// The most efficient way to trigger a relayout is to supply a `relayout`
/// argument to the constructor of the `MultiChildLayoutDelegate`. The custom
/// layout will listen to this value and relayout whenever the `Listenable`
/// notifies its listeners, such as when an `Animation` ticks.
///
/// Each child must be wrapped in a `LayoutId` widget to assign the id that
/// identifies it to the delegate. The `LayoutId.id` needs to be unique among
/// the children that the `CustomMultiChildLayout` manages.
///
/// **Dart Source:** custom_layout.dart:122-308
open class MultiChildLayoutDelegate {

    /// Creates a layout delegate.
    ///
    /// The layout will update whenever `relayout` notifies its listeners.
    ///
    /// **Dart Source:** custom_layout.dart:126
    public init(relayout: (any Listenable)? = nil) {
        self._relayout = relayout
    }

    /// The listenable that triggers relayout.
    ///
    /// **Dart Source:** custom_layout.dart:128
    private let _relayout: (any Listenable)?

    /// The relayout listenable, exposed for use by the render object.
    ///
    /// **Dart Source:** custom_layout.dart:128
    public var relayout: (any Listenable)? { _relayout }

    /// Map from child id to the corresponding `RenderBox`.
    ///
    /// This is set up by `_callPerformLayout` before `performLayout` is called,
    /// and cleared afterwards.
    ///
    /// **Dart Source:** custom_layout.dart:130
    private var _idToChild: [AnyHashable: RenderBox]?

    /// Debug-only set of children that still need to be laid out.
    ///
    /// **Dart Source:** custom_layout.dart:131
    private var _debugChildrenNeedingLayout: Set<ObjectIdentifier>?

    // MARK: - hasChild

    /// True if a non-null `LayoutChild` was provided for the specified id.
    ///
    /// Call this from the `performLayout` method to determine which children
    /// are available, if the child list might vary.
    ///
    /// This method cannot be called from `getSize` as the size is not allowed
    /// to depend on the children.
    ///
    /// **Dart Source:** custom_layout.dart:133-140
    public func hasChild(_ childId: AnyHashable) -> Bool {
        return _idToChild![childId] != nil
    }

    // MARK: - layoutChild

    /// Ask the child to update its layout within the limits specified by
    /// the constraints parameter. The child's size is returned.
    ///
    /// Call this from your `performLayout` function to lay out each
    /// child. Every child must be laid out using this function exactly
    /// once each time the `performLayout` function is called.
    ///
    /// **Dart Source:** custom_layout.dart:148-182
    public func layoutChild(_ childId: AnyHashable, _ constraints: BoxConstraints) -> Size {
        let child: RenderBox? = _idToChild![childId]
        assert({
            if child == nil {
                fatalError(
                    "The \(self) custom multichild layout delegate tried to lay out a non-existent child.\n"
                    + "There is no child with the id \"\(childId)\"."
                )
            }
            if let debugSet = _debugChildrenNeedingLayout,
               !debugSet.contains(ObjectIdentifier(child!)) {
                fatalError(
                    "The \(self) custom multichild layout delegate tried to lay out the child with id \"\(childId)\" more than once.\n"
                    + "Each child must be laid out exactly once."
                )
            }
            assert(constraints.debugAssertIsValid(isAppliedConstraint: true))
            return true
        }())
        assert({
            _debugChildrenNeedingLayout?.remove(ObjectIdentifier(child!))
            return true
        }())
        child!.layout(constraints, parentUsesSize: true)
        return child!.size
    }

    // MARK: - positionChild

    /// Specify the child's origin relative to this origin.
    ///
    /// Call this from your `performLayout` function to position each
    /// child. If you do not call this for a child, its position will
    /// remain unchanged. Children initially have their position set to
    /// (0,0), i.e. the top left of the `RenderCustomMultiChildLayoutBox`.
    ///
    /// **Dart Source:** custom_layout.dart:190-204
    public func positionChild(_ childId: AnyHashable, _ offset: Offset) {
        let child: RenderBox? = _idToChild![childId]
        assert({
            if child == nil {
                fatalError(
                    "The \(self) custom multichild layout delegate tried to position out a non-existent child:\n"
                    + "There is no child with the id \"\(childId)\"."
                )
            }
            return true
        }())
        let childParentData = child!.parentData! as! MultiChildLayoutParentData
        childParentData.offset = offset
    }

    // MARK: - _callPerformLayout

    /// Internal method that sets up `_idToChild`, calls `performLayout`, and
    /// cleans up.
    ///
    /// A particular layout delegate could be called reentrantly, e.g. if it is
    /// used by both a parent and a child. So, we must restore the `_idToChild`
    /// map when we return.
    ///
    /// **Dart Source:** custom_layout.dart:212-274
    internal func _callPerformLayout(size: Size, firstChild: RenderBox?) {
        let previousIdToChild = _idToChild

        var debugPreviousChildrenNeedingLayout: Set<ObjectIdentifier>?
        assert({
            debugPreviousChildrenNeedingLayout = _debugChildrenNeedingLayout
            _debugChildrenNeedingLayout = Set<ObjectIdentifier>()
            return true
        }())

        defer {
            _idToChild = previousIdToChild
            assert({
                _debugChildrenNeedingLayout = debugPreviousChildrenNeedingLayout
                return true
            }())
        }

        _idToChild = [AnyHashable: RenderBox]()
        var child: RenderBox? = firstChild
        while let currentChild = child {
            let childParentData = currentChild.parentData! as! MultiChildLayoutParentData
            assert({
                if childParentData.id == nil {
                    fatalError(
                        "Every child of a RenderCustomMultiChildLayoutBox must have an ID in its parent data."
                    )
                }
                return true
            }())
            _idToChild![childParentData.id!] = currentChild
            assert({
                _debugChildrenNeedingLayout!.insert(ObjectIdentifier(currentChild))
                return true
            }())
            child = childParentData.nextSibling
        }

        performLayout(size)

        assert({
            if !_debugChildrenNeedingLayout!.isEmpty {
                fatalError(
                    "Each child must be laid out exactly once.\n"
                    + "The \(self) custom multichild layout delegate forgot to lay out "
                    + "\(_debugChildrenNeedingLayout!.count) "
                    + "\(_debugChildrenNeedingLayout!.count > 1 ? "children" : "child")."
                )
            }
            return true
        }())
    }

    // MARK: - getSize

    /// Override this method to return the size of this object given the
    /// incoming constraints.
    ///
    /// The size cannot reflect the sizes of the children. If this layout has a
    /// fixed width or height the returned size can reflect that; the size will be
    /// constrained to the given constraints.
    ///
    /// By default, attempts to size the box to the biggest size
    /// possible given the constraints.
    ///
    /// **Dart Source:** custom_layout.dart:276-285
    open func getSize(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }

    // MARK: - performLayout

    /// Override this method to lay out and position all children given this
    /// widget's size.
    ///
    /// This method must call `layoutChild` for each child. It should also specify
    /// the final position of each child with `positionChild`.
    ///
    /// **Dart Source:** custom_layout.dart:287-292
    open func performLayout(_ size: Size) {
        fatalError("Subclasses of MultiChildLayoutDelegate must override performLayout(_:)")
    }

    // MARK: - shouldRelayout

    /// Override this method to return true when the children need to be
    /// laid out.
    ///
    /// This should compare the fields of the current delegate and the given
    /// `oldDelegate` and return true if the fields are such that the layout would
    /// be different.
    ///
    /// **Dart Source:** custom_layout.dart:294-300
    open func shouldRelayout(_ oldDelegate: MultiChildLayoutDelegate) -> Bool {
        fatalError("Subclasses of MultiChildLayoutDelegate must override shouldRelayout(_:)")
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this delegate.
    ///
    /// By default, returns the runtime type of the class.
    ///
    /// **Dart Source:** custom_layout.dart:302-307
    public var description: String {
        objectRuntimeType(self, "MultiChildLayoutDelegate")
    }
}

// MARK: - RenderCustomMultiChildLayoutBox

/// A render object that uses a `MultiChildLayoutDelegate` to size and
/// position multiple box children.
///
/// In Dart this class extends `RenderBox` and mixes in
/// `ContainerRenderObjectMixin<RenderBox, MultiChildLayoutParentData>` and
/// `RenderBoxContainerDefaultsMixin<RenderBox, MultiChildLayoutParentData>`.
///
/// Since Swift does not support generic mixins, the container management
/// (linked-list child pointers) is implemented inline, and the class
/// conforms to `RenderBoxContainerDefaults` for default paint and
/// hit-testing behavior.
///
/// **Dart Source:** custom_layout.dart:316-432
public class RenderCustomMultiChildLayoutBox: RenderBox, RenderBoxContainerDefaults {
    public typealias ChildType = RenderBox

    // MARK: - Container child management (ContainerRenderObjectMixin)

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
        let parentData = child.parentData as! MultiChildLayoutParentData
        return parentData.nextSibling
    }

    /// Returns the previous sibling of the given child.
    ///
    /// **Dart Source:** object.dart:4399 (ContainerRenderObjectMixin)
    public func childBefore(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as! MultiChildLayoutParentData
        return parentData.previousSibling
    }

    /// Inserts a child into the linked list.
    ///
    /// **Dart Source:** object.dart:4234-4268 (ContainerRenderObjectMixin._insertIntoChildList)
    private func _insertIntoChildList(_ child: RenderBox, after: RenderBox? = nil) {
        let childParentData = child.parentData as! MultiChildLayoutParentData
        childCount += 1
        assert(childCount > 0)
        if let after = after {
            let afterParentData = after.parentData as! MultiChildLayoutParentData
            if afterParentData.nextSibling == nil {
                // Inserting at the end — update lastChild
                childParentData.previousSibling = after
                afterParentData.nextSibling = child
                lastChild = child
            } else {
                // Inserting in the middle
                childParentData.nextSibling = afterParentData.nextSibling
                childParentData.previousSibling = after
                let nextParentData = afterParentData.nextSibling!.parentData as! MultiChildLayoutParentData
                nextParentData.previousSibling = child
                afterParentData.nextSibling = child
            }
        } else {
            childParentData.nextSibling = firstChild
            if let first = firstChild {
                let firstParentData = first.parentData as! MultiChildLayoutParentData
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
        let childParentData = child.parentData as! MultiChildLayoutParentData
        if childParentData.previousSibling == nil {
            // child is firstChild
            firstChild = childParentData.nextSibling
        } else {
            let previousParentData = childParentData.previousSibling!.parentData as! MultiChildLayoutParentData
            previousParentData.nextSibling = childParentData.nextSibling
        }
        if childParentData.nextSibling == nil {
            // child is lastChild
            lastChild = childParentData.previousSibling
        } else {
            let nextParentData = childParentData.nextSibling!.parentData as! MultiChildLayoutParentData
            nextParentData.previousSibling = childParentData.previousSibling
        }
        childParentData.previousSibling = nil
        childParentData.nextSibling = nil
        childCount -= 1
    }

    /// Adds a child to the end of the child list.
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

    // MARK: - Stored property for markNeedsLayout closure

    /// A closure wrapper around `markNeedsLayout` that can be used as a
    /// `VoidCallback` for `Listenable.addListener` / `removeListener`.
    ///
    /// We store this so that the same closure identity is used when adding
    /// and removing the listener.
    private lazy var _markNeedsLayoutCallback: VoidCallback = { [weak self] in
        self?.markNeedsLayout()
    }

    // MARK: - Initializer

    /// Creates a render object that customizes the layout of multiple children.
    ///
    /// **Dart Source:** custom_layout.dart:321-326
    public init(children: [RenderBox]? = nil, delegate: MultiChildLayoutDelegate) {
        self._delegate = delegate
        super.init()
        addAll(children)
    }

    // MARK: - setupParentData

    /// Ensures the child has `MultiChildLayoutParentData`.
    ///
    /// If the child's `parentData` is not already a `MultiChildLayoutParentData`,
    /// replaces it.
    ///
    /// **Dart Source:** custom_layout.dart:329-333
    public override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is MultiChildLayoutParentData) {
            child.parentData = MultiChildLayoutParentData()
        }
    }

    // MARK: - delegate

    /// The delegate that controls the layout of the children.
    ///
    /// **Dart Source:** custom_layout.dart:336-337
    public var delegate: MultiChildLayoutDelegate {
        get { _delegate }
        set {
            if _delegate === newValue {
                return
            }
            let oldDelegate = _delegate
            if type(of: newValue) != type(of: oldDelegate) || newValue.shouldRelayout(oldDelegate) {
                markNeedsLayout()
            }
            _delegate = newValue
            if attached {
                oldDelegate.relayout?.removeListeners(owner: self)
                newValue.relayout?.addListener(_markNeedsLayoutCallback, owner: self)
            }
        }
    }

    /// The backing storage for the delegate.
    ///
    /// **Dart Source:** custom_layout.dart:337
    private var _delegate: MultiChildLayoutDelegate

    // MARK: - attach / detach

    /// Attaches this render object to a pipeline owner.
    ///
    /// Adds a listener to the delegate's `_relayout` listenable so that layout
    /// is marked dirty whenever the listenable notifies.
    ///
    /// **Dart Source:** custom_layout.dart:355-358
    public override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _delegate.relayout?.addListener(_markNeedsLayoutCallback, owner: self)
    }

    /// Detaches this render object from its pipeline owner.
    ///
    /// Removes the listener from the delegate's `_relayout` listenable.
    ///
    /// **Dart Source:** custom_layout.dart:361-364
    public override func detach() {
        _delegate.relayout?.removeListeners(owner: self)
        super.detach()
    }

    // MARK: - _getSize

    /// Returns the size that satisfies both the constraints and the delegate's
    /// desired size.
    ///
    /// **Dart Source:** custom_layout.dart:366-369
    private func _getSize(_ constraints: BoxConstraints) -> Size {
        assert(constraints.debugAssertIsValid())
        return constraints.constrain(_delegate.getSize(constraints))
    }

    // MARK: - Intrinsic Dimensions

    // TODO(ianh): It's a bit dubious to be using the getSize function from the
    // delegate to figure out the intrinsic dimensions. We really should either
    // not support intrinsics, or we should expose intrinsic delegate callbacks
    // and throw if they're not implemented.

    /// Computes the minimum intrinsic width for the given height.
    ///
    /// **Dart Source:** custom_layout.dart:376-382
    public override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let width = _getSize(.tightForFinite(height: height)).width
        if width.isFinite {
            return width
        }
        return 0.0
    }

    /// Computes the maximum intrinsic width for the given height.
    ///
    /// **Dart Source:** custom_layout.dart:385-391
    public override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let width = _getSize(.tightForFinite(height: height)).width
        if width.isFinite {
            return width
        }
        return 0.0
    }

    /// Computes the minimum intrinsic height for the given width.
    ///
    /// **Dart Source:** custom_layout.dart:394-400
    public override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        let height = _getSize(.tightForFinite(width: width)).height
        if height.isFinite {
            return height
        }
        return 0.0
    }

    /// Computes the maximum intrinsic height for the given width.
    ///
    /// **Dart Source:** custom_layout.dart:403-409
    public override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        let height = _getSize(.tightForFinite(width: width)).height
        if height.isFinite {
            return height
        }
        return 0.0
    }

    // MARK: - Dry Layout

    /// Computes the dry layout size for the given constraints.
    ///
    /// **Dart Source:** custom_layout.dart:412-415
    public override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return _getSize(constraints)
    }

    // MARK: - performLayout

    /// Performs layout by setting the size and delegating child layout to
    /// the delegate.
    ///
    /// **Dart Source:** custom_layout.dart:418-421
    public override func performLayout() {
        size = _getSize(boxConstraints)
        delegate._callPerformLayout(size: size, firstChild: firstChild)
    }

    // MARK: - Paint

    /// Paints each child at its offset using `defaultPaint`.
    ///
    /// **Dart Source:** custom_layout.dart:424-426
    public override func paint(_ context: PaintingContext, _ offset: Offset) {
        defaultPaint(context, offset)
    }

    // MARK: - Hit Testing

    /// Hit tests children using `defaultHitTestChildren`.
    ///
    /// **Dart Source:** custom_layout.dart:429-431
    public override func hitTestChildren(
        _ result: BoxHitTestResult,
        position: Offset
    ) -> Bool {
        return defaultHitTestChildren(result, position: position)
    }
}

// MARK: - ContainerRenderObjectHost Conformance

extension RenderCustomMultiChildLayoutBox: ContainerRenderObjectHost {
    /// Reorders a child that is already ours.
    ///
    /// Relinks the child in place rather than going through `remove`/`insert`:
    /// those drop and re-adopt, `dropChild` clears the parent data, and
    /// `setupParentData` then hands back a blank `MultiChildLayoutParentData` —
    /// so a reordered child would lose the `LayoutId` id the delegate looks it
    /// up by and trip the "child without ID" assertion on the next layout.
    /// Same shape as `RenderStack.move`.
    ///
    /// **Dart Source:** object.dart:4448-4460 (ContainerRenderObjectMixin.move)
    public func move(_ child: RenderBox, after: RenderBox?) {
        guard let childParentData = child.parentData as? MultiChildLayoutParentData else { return }
        if childParentData.previousSibling === after { return }
        _removeFromChildList(child)
        _insertIntoChildList(child, after: after)
        markNeedsLayout()
    }
}
