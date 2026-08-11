// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// MARK: - Type-erasure protocol for ParentDataWidget

/// Internal protocol to type-erase `ParentDataWidget<T>` so that
/// `RenderObjectElement._updateParentData` can call `applyParentData`
/// without knowing the concrete generic parameter.
///
/// Swift's invariant generics prevent casting `ParentDataWidget<SomeSubclass>`
/// to `ParentDataWidget<ParentData>`. This protocol sidesteps that limitation.
private protocol _AnyParentDataWidget {
    func applyParentData(_ renderObject: RenderObject)
}
extension ParentDataWidget: _AnyParentDataWidget {}

// MARK: - Render Object Host Protocols

/// Protocol for render objects that host a single child (RenderObjectWithChildMixin pattern).
///
/// Render objects conforming to this protocol can have their `child` property
/// set by `SingleChildRenderObjectElement` during the widget->render tree wiring.
public protocol SingleChildRenderObjectHost: AnyObject {
    var child: RenderBox? { get set }
}

/// Protocol for render objects that host multiple children (ContainerRenderObjectMixin pattern).
///
/// Render objects conforming to this protocol can have children inserted,
/// removed, and moved by `MultiChildRenderObjectElement`.
public protocol ContainerRenderObjectHost: AnyObject {
    func insert(_ child: RenderBox, after: RenderBox?)
    func remove(_ child: RenderBox)
    func move(_ child: RenderBox, after: RenderBox?)
}

/// Sliver flavour of `SingleChildRenderObjectHost`
/// (RenderObjectWithChildMixin&lt;RenderSliver&gt; pattern): sliver wrappers such as
/// `RenderProxySliver` and `RenderSliverEdgeInsetsPadding`, whose child is a
/// `RenderSliver` rather than a `RenderBox`.
public protocol SingleChildSliverHost: AnyObject {
    var child: RenderSliver? { get set }
}

/// Sliver flavour of `ContainerRenderObjectHost`: render objects whose child
/// list holds `RenderSliver`s — the viewports (`RenderViewportBase`), whose
/// children are the slivers a scroll view composes.
public protocol SliverContainerRenderObjectHost: AnyObject {
    func insert(_ child: RenderSliver, after: RenderSliver?)
    func remove(_ child: RenderSliver)
}

// MARK: - RenderObjectElement

/// An `Element` that uses a `RenderObjectWidget` as its configuration.
///
/// `RenderObjectElement` is the bridge between the widget tree and the render
/// tree. It creates, updates, and disposes `RenderObject` instances based on
/// the `RenderObjectWidget` configuration.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6289`
open class RenderObjectElement: Element {
    /// The underlying `RenderObject` for this element.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6332`
    public internal(set) var renderObject: RenderObject?

    /// The nearest ancestor `RenderObjectElement`.
    ///
    /// Used by `attachRenderObject` and `detachRenderObject` to insert/remove
    /// the render object from the render tree.
    ///
    /// `weak`: this is an up-pointer to an ancestor, and ancestors already own
    /// their descendants through `_child`/`_children`. Upstream only clears it
    /// on the element whose render object is detached — interior elements of a
    /// dropped subtree keep theirs set, which Dart's GC tolerates and ARC does
    /// not: with a strong reference every dropped subtree containing a
    /// RenderObjectElement cycled through its render ancestor and leaked.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6614`
    internal weak var _ancestorRenderObjectElement: RenderObjectElement?

    /// Whether this element is in the process of building.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6295`
    internal var _debugDoingBuild = false

    /// Creates an element for the given `RenderObjectWidget`.
    public override init(_ widget: Widget) {
        super.init(widget)
    }

    // MARK: - Debug

    public override var debugDoingBuild: Bool { _debugDoingBuild }

    // MARK: - Lifecycle

    /// Called when this element is added to the tree.
    ///
    /// Creates the render object via `createRenderObject`, attaches it to
    /// the render tree, and clears the dirty flag.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6338`
    open override func mount(_ parent: Element?, _ newSlot: Any?) {
        super.mount(parent, newSlot)
        _debugDoingBuild = true
        renderObject = (widget as! RenderObjectWidget).createRenderObject(self)
        _debugDoingBuild = false
        attachRenderObject(newSlot)
        super.performRebuild() // clears the "dirty" flag
    }

    /// Called when the widget for this element changes.
    ///
    /// Updates the render object configuration via `_performRebuild`.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6374`
    open override func update(_ newWidget: Widget) {
        super.update(newWidget)
        _performRebuild()
    }

    /// Rebuilds this element by updating the render object.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6378`
    open override func performRebuild() {
        _performRebuild()
    }

    /// Internal rebuild: updates the render object and clears the dirty flag.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6383`
    private func _performRebuild() {
        _debugDoingBuild = true
        (widget as! RenderObjectWidget).updateRenderObject(self, renderObject: renderObject!)
        _debugDoingBuild = false
        super.performRebuild() // clears dirty flag
    }

    /// Called when this element is permanently removed from the tree.
    ///
    /// Notifies the old widget via `didUnmountRenderObject`, then disposes
    /// the render object.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6414`
    open override func unmount() {
        let oldWidget = widget as! RenderObjectWidget
        super.unmount()
        oldWidget.didUnmountRenderObject(renderObject!)
        renderObject?.dispose()
        renderObject = nil
    }

    // MARK: - Render Object

    /// Returns this element's render object.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6329`
    open override func findRenderObject() -> RenderObject? {
        return renderObject
    }

    // MARK: - Parent Data

    /// Applies parent data from the given widget to this element's render object.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6438`
    internal func _updateParentData(_ widget: Widget) {
        if let pdw = widget as? _AnyParentDataWidget {
            pdw.applyParentData(renderObject!)
        }
    }

    // MARK: - Ancestor Traversal

    /// Walks up the element tree to find the nearest `RenderObjectElement` ancestor.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6618`
    internal func _findAncestorRenderObjectElement() -> RenderObjectElement? {
        var ancestor = _parent
        while ancestor != nil && !(ancestor is RenderObjectElement) {
            ancestor = ancestor?._parent
        }
        return ancestor as? RenderObjectElement
    }

    // MARK: - Attach / Detach Render Object

    /// Inserts this element's render object into the render tree.
    ///
    /// Finds the nearest ancestor `RenderObjectElement` and calls its
    /// `insertRenderObjectChild` method. Also walks up to find any
    /// `ParentDataWidget` ancestors and applies their parent data.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6631`
    open override func attachRenderObject(_ newSlot: Any?) {
        _slot = newSlot
        _ancestorRenderObjectElement = _findAncestorRenderObjectElement()
        _ancestorRenderObjectElement?.insertRenderObjectChild(renderObject!, newSlot)

        // Walk up to find and apply ParentDataWidget ancestors.
        var ancestor = _parent
        while ancestor != nil && !(ancestor is RenderObjectElement) {
            if let pdw = ancestor?.widget as? _AnyParentDataWidget {
                pdw.applyParentData(renderObject!)
            }
            ancestor = ancestor?._parent
        }
    }

    /// Removes this element's render object from the render tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6659`
    open override func detachRenderObject() {
        if let ancestor = _ancestorRenderObjectElement {
            ancestor.removeRenderObjectChild(renderObject!, _slot)
            _ancestorRenderObjectElement = nil
        }
        _slot = nil
    }

    // MARK: - Child Render Object Management

    /// Insert the given child into the child list at the given slot.
    ///
    /// Subclasses must override to insert the child's render object into
    /// the render tree at the appropriate position.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6469`
    open func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        // Subclasses must override
    }

    /// Move the given child to the given slot.
    ///
    /// Subclasses must override to move the child's render object within
    /// the render tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6498`
    open func moveRenderObjectChild(
        _ child: RenderObject, _ oldSlot: Any?, _ newSlot: Any?
    ) {
        // Subclasses must override
    }

    /// Remove the given child from the child list.
    ///
    /// Subclasses must override to remove the child's render object from
    /// the render tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6525`
    open func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        // Subclasses must override
    }
}

// MARK: - RenderTreeRootElement

/// An abstract element for the root of a render tree.
///
/// The root element does not have an ancestor `RenderObjectElement`,
/// so `attachRenderObject` and `detachRenderObject` simply manage the slot
/// without inserting into a parent render object.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6673`
open class RenderTreeRootElement: RenderObjectElement {
    /// Creates an element for the root of a render tree.
    public override init(_ widget: Widget) {
        super.init(widget)
    }

    /// At the root, there is no ancestor render object to insert into.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6678`
    open override func attachRenderObject(_ newSlot: Any?) {
        _slot = newSlot
    }

    /// At the root, there is no ancestor render object to detach from.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6684`
    open override func detachRenderObject() {
        _slot = nil
    }
}

// MARK: - LeafRenderObjectElement

/// An `Element` that uses a `LeafRenderObjectWidget` as its configuration.
///
/// The element has no children. Attempts to insert children will trigger
/// an assertion failure.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7270`
open class LeafRenderObjectElement: RenderObjectElement {
    /// Creates an element for the given widget.
    public init(_ widget: LeafRenderObjectWidget) {
        super.init(widget)
    }

    /// Leaf elements have no children to forget.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7274`
    open override func forgetChild(_ child: Element) {
        assertionFailure("LeafRenderObjectElement has no children")
        super.forgetChild(child)
    }

    /// Leaf elements cannot have render object children inserted.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7281`
    open override func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        assertionFailure("LeafRenderObjectElement cannot have render object children")
    }

    /// Leaf elements cannot move render object children.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7286`
    open override func moveRenderObjectChild(
        _ child: RenderObject, _ oldSlot: Any?, _ newSlot: Any?
    ) {
        assertionFailure("LeafRenderObjectElement cannot move render object children")
    }

    /// Leaf elements cannot remove render object children.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7291`
    open override func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        assertionFailure("LeafRenderObjectElement cannot remove render object children")
    }
}

// MARK: - SingleChildRenderObjectElement

/// An `Element` that uses a `SingleChildRenderObjectWidget` as its configuration.
///
/// The element has at most one child.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7304`
open class SingleChildRenderObjectElement: RenderObjectElement {
    /// Creates an element for the given widget.
    public init(_ widget: SingleChildRenderObjectWidget) {
        super.init(widget)
    }

    /// The child element.
    internal var _child: Element?

    // MARK: - Visiting

    /// Visits the single child, if it exists.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7310`
    open override func visitChildElements(_ visitor: (Element) -> Void) {
        if let child = _child {
            visitor(child)
        }
    }

    // MARK: - Child Management

    /// Removes the reference to the child from this element.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7316`
    open override func forgetChild(_ child: Element) {
        assert(child === _child)
        _child = nil
        super.forgetChild(child)
    }

    // MARK: - Lifecycle

    /// Mounts this element, creating and attaching the render object,
    /// then inflating or updating the child.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7323`
    open override func mount(_ parent: Element?, _ newSlot: Any?) {
        super.mount(parent, newSlot)
        _child = updateChild(
            _child,
            newWidget: (widget as! SingleChildRenderObjectWidget).child,
            newSlot: nil
        )
    }

    /// Updates this element with a new widget, then updates the child.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7330`
    open override func update(_ newWidget: Widget) {
        super.update(newWidget)
        _child = updateChild(
            _child,
            newWidget: (widget as! SingleChildRenderObjectWidget).child,
            newSlot: nil
        )
    }

    // MARK: - Render Object Child Management

    /// Inserts the child render object into this element's render object.
    ///
    /// Casts `renderObject` to `SingleChildRenderObjectHost` and sets its
    /// `child` property to the given child.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7337`
    open override func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        if let ro = renderObject as? SingleChildSliverHost {
            ro.child = (child as! RenderSliver)
            return
        }
        let ro = renderObject as! SingleChildRenderObjectHost
        ro.child = child as? RenderBox
    }

    /// Single-child elements do not support moving render object children.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7343`
    open override func moveRenderObjectChild(
        _ child: RenderObject, _ oldSlot: Any?, _ newSlot: Any?
    ) {
        assertionFailure("SingleChildRenderObjectElement cannot move its child")
    }

    /// Removes the child render object from this element's render object.
    ///
    /// Casts `renderObject` to `SingleChildRenderObjectHost` and sets its
    /// `child` property to nil.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7349`
    open override func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        if let ro = renderObject as? SingleChildSliverHost {
            assert(ro.child === child as? RenderSliver)
            ro.child = nil
            return
        }
        let ro = renderObject as! SingleChildRenderObjectHost
        assert(ro.child === child as? RenderBox)
        ro.child = nil
    }
}

// MARK: - MultiChildRenderObjectElement

/// An `Element` that uses a `MultiChildRenderObjectWidget` as its configuration.
///
/// Uses the `updateChildren` diff algorithm to efficiently manage a list
/// of child elements.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7363`
open class MultiChildRenderObjectElement: RenderObjectElement {
    /// Creates an element for the given widget.
    public init(_ widget: MultiChildRenderObjectWidget) {
        super.init(widget)
    }

    /// The children of this element.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7367`
    internal var _children: [Element] = []

    /// Children that have been forgotten (removed via `forgetChild`) but not
    /// yet cleaned up. Uses `ObjectIdentifier` for identity-based lookup.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7368`
    internal var _forgottenChildren: Set<ObjectIdentifier> = []

    // MARK: - Render Object Child Management

    /// Inserts the child render object at the given slot.
    ///
    /// Casts `renderObject` to `ContainerRenderObjectHost` and calls
    /// `insert(child, after:)` using the previous sibling from the slot.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7372`
    open override func insertRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        let indexedSlot = slot as? IndexedSlot<Element?>
        if let ro = renderObject as? SliverContainerRenderObjectHost {
            let after = indexedSlot?.value?.findRenderObject() as? RenderSliver
            ro.insert(child as! RenderSliver, after: after)
            return
        }
        let ro = renderObject as! ContainerRenderObjectHost
        let after = indexedSlot?.value?.findRenderObject() as? RenderBox
        ro.insert(child as! RenderBox, after: after)
    }

    /// Moves the child render object to a new slot.
    ///
    /// Casts `renderObject` to `ContainerRenderObjectHost` and calls
    /// `move(child, after:)` using the previous sibling from the new slot.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7379`
    open override func moveRenderObjectChild(
        _ child: RenderObject, _ oldSlot: Any?, _ newSlot: Any?
    ) {
        let indexedSlot = newSlot as? IndexedSlot<Element?>
        if let ro = renderObject as? SliverContainerRenderObjectHost {
            // Viewports carry no dedicated move; remove + insert reorders the
            // child list (at the cost of a detach/attach cycle, which is fine
            // for the between-frames reordering this is called for).
            let after = indexedSlot?.value?.findRenderObject() as? RenderSliver
            let sliver = child as! RenderSliver
            ro.remove(sliver)
            ro.insert(sliver, after: after)
            return
        }
        let ro = renderObject as! ContainerRenderObjectHost
        let after = indexedSlot?.value?.findRenderObject() as? RenderBox
        ro.move(child as! RenderBox, after: after)
    }

    /// Removes the child render object from this element's render object.
    ///
    /// Casts `renderObject` to `ContainerRenderObjectHost` and calls
    /// `remove(child)`.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7386`
    open override func removeRenderObjectChild(_ child: RenderObject, _ slot: Any?) {
        if let ro = renderObject as? SliverContainerRenderObjectHost {
            ro.remove(child as! RenderSliver)
            return
        }
        let ro = renderObject as! ContainerRenderObjectHost
        ro.remove(child as! RenderBox)
    }

    // MARK: - Visiting

    /// Visits each child element, skipping forgotten children.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7392`
    open override func visitChildElements(_ visitor: (Element) -> Void) {
        for child in _children {
            if !_forgottenChildren.contains(ObjectIdentifier(child)) {
                visitor(child)
            }
        }
    }

    // MARK: - Child Management

    /// Marks a child as forgotten so it is skipped during visits.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7401`
    open override func forgetChild(_ child: Element) {
        _forgottenChildren.insert(ObjectIdentifier(child))
        super.forgetChild(child)
    }

    // MARK: - Lifecycle

    /// Mounts this element, inflating all children from the widget's child list.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7407`
    open override func mount(_ parent: Element?, _ newSlot: Any?) {
        super.mount(parent, newSlot)
        let multiChildWidget = widget as! MultiChildRenderObjectWidget
        let children = Array<Element>(
            repeating: _NullElement.instance,
            count: multiChildWidget.children.count
        )
        _children = children
        var previousChild: Element?
        for i in 0..<multiChildWidget.children.count {
            let newChild = inflateWidget(
                multiChildWidget.children[i],
                IndexedSlot<Element?>(value: previousChild, index: i)
            )
            _children[i] = newChild
            previousChild = newChild
        }
    }

    /// Updates this element, diffing the old and new child lists using
    /// `updateChildren`.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7423`
    open override func update(_ newWidget: Widget) {
        super.update(newWidget)
        let multiChildWidget = widget as! MultiChildRenderObjectWidget
        _children = updateChildren(
            _children,
            multiChildWidget.children,
            forgottenChildren: _forgottenChildren
        )
        _forgottenChildren.removeAll()
    }
}

// MARK: - IndexedSlot

/// A value for `Element.slot` used by `MultiChildRenderObjectElement`.
///
/// Combines an index (the child's position in the parent's child list) with
/// a reference to the previous sibling element. This is used to determine
/// where to insert render object children.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7450`
public struct IndexedSlot<T> {
    /// The value stored in this slot (typically the previous sibling element).
    public let value: T

    /// The index of the child in the parent's child list.
    public let index: Int

    /// Creates an indexed slot.
    public init(value: T, index: Int) {
        self.value = value
        self.index = index
    }
}

// MARK: - RootElementMixin

/// Marker protocol for the element at the root of the tree.
///
/// Only an element at the root of the tree should conform to this protocol.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7414`
public protocol RootElementMixin: AnyObject {
}
