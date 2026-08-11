// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridge

// MARK: - _ElementLifecycle

/// Tracks the lifecycle of an `Element`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3541`
internal enum _ElementLifecycle {
    case initial
    case active
    case inactive
    case defunct
}

// MARK: - InheritedElementMap

/// An immutable-style map from `InheritedWidget` type to `InheritedElement`.
///
/// This replaces the Dart `PersistentHashMap<Type, InheritedElement>`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart`
internal struct InheritedElementMap: @unchecked Sendable {
    private var storage: [ObjectIdentifier: InheritedElement]

    nonisolated(unsafe) static let empty = InheritedElementMap(storage: [:])

    init(storage: [ObjectIdentifier: InheritedElement] = [:]) {
        self.storage = storage
    }

    /// Returns a new map with the given type mapped to the given element.
    func putting<T: InheritedWidget>(_ type: T.Type, _ element: InheritedElement) -> InheritedElementMap {
        var copy = storage
        copy[ObjectIdentifier(type)] = element
        return InheritedElementMap(storage: copy)
    }

    /// Returns the element for the given inherited widget type.
    subscript<T: InheritedWidget>(_ type: T.Type) -> InheritedElement? {
        return storage[ObjectIdentifier(type)]
    }

    /// Returns a new map with the given type identifier mapped to the given element.
    ///
    /// This variant accepts a runtime `ObjectIdentifier` directly, which is
    /// needed when the concrete `InheritedWidget` type is only known at runtime
    /// (e.g., inside `InheritedElement._updateInheritance`).
    func putting(typeIdentifier: ObjectIdentifier, _ element: InheritedElement) -> InheritedElementMap {
        var copy = storage
        copy[typeIdentifier] = element
        return InheritedElementMap(storage: copy)
    }

    /// Returns the element for the given type identifier.
    subscript(id: ObjectIdentifier) -> InheritedElement? {
        return storage[id]
    }
}

// MARK: - Element

/// An instantiation of a `Widget` at a particular location in the tree.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3557`
open class Element: BuildContext {
    /// The widget that created this element.
    public internal(set) var widget: Widget

    /// Creates an element with the given widget.
    public init(_ widget: Widget) {
        self.widget = widget
    }

    // MARK: - Tree Structure

    /// The parent of this element in the tree.
    ///
    /// `weak`, deliberately diverging from Dart, and load bearing. Parents
    /// hold their children strongly (`_child`/`_children`), so a strong
    /// back-pointer here made every parent↔child pair a retain cycle — under
    /// ARC the whole element tree was one cycle cluster, and any subtree that
    /// was replaced or deactivated leaked wholesale: its elements, their
    /// render objects, and everything those own (TextPainters, engine-side
    /// paragraphs). `deactivateChild` nils `_parent` only on the subtree
    /// root; every interior edge stayed cyclic. This is what grew the
    /// terminal ~20 MB per styled dump, one dropped row-set at a time
    /// (docs/perf/terminal-vs-ghostty-2026-08-04/). Dart's GC collects such
    /// cycles, so upstream can use a plain field; ARC cannot. Ownership of
    /// elements flows strictly downward, exactly as `RenderObject.parent`
    /// (also weak) already models on the render side.
    internal weak var _parent: Element?

    /// The slot in which this element is placed by its parent.
    internal var _slot: Any?

    /// The depth of this element in the tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3655`
    public internal(set) var depth: Int = 0

    /// The build owner for this element.
    public internal(set) var owner: BuildOwner?

    /// The lifecycle state of this element.
    internal var _lifecycleState: _ElementLifecycle = .initial

    // MARK: - Build State

    /// Whether this element is marked as needing to be rebuilt.
    internal var _dirty: Bool = true

    /// Whether this element has been added to the dirty list.
    internal var _inDirtyList: Bool = false

    // MARK: - Notification

    /// The notification node for this element.
    internal var _notificationTree: _NotificationNode?

    // MARK: - Inherited Widgets

    /// The inherited elements that this element depends on.
    internal var _inheritedElements: InheritedElementMap?

    /// The set of inherited elements that this element has registered
    /// dependencies with.
    internal var _dependencies: Set<ObjectIdentifier>?

    /// Whether this element had unsatisfied dependencies.
    internal var _hadUnsatisfiedDependencies = false

    // MARK: - Debug

    /// Whether this element has been built at least once.
    internal var _debugBuiltOnce = false

    /// Whether the widget is currently updating the widget or render tree.
    public var debugDoingBuild: Bool { false }

    /// Whether this element is currently mounted in the tree.
    public var mounted: Bool {
        return _lifecycleState == .active
    }

    // MARK: - Lifecycle

    /// Called when this element is added to the tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4067`
    open func mount(_ parent: Element?, _ newSlot: Any?) {
        _parent = parent
        _slot = newSlot
        _lifecycleState = .active
        if let parent = parent {
            depth = parent.depth + 1
            owner = parent.owner
            _updateInheritance()
            attachNotificationTree()
        }
        // Register global keys so GlobalKey.currentState / currentContext
        // resolve (mirrors framework.dart Element.mount; unmount() does the
        // matching unregister).
        if let key = widget.key, key is AnyGlobalKey {
            owner?._registerGlobalKey(key, self)
        }
    }

    /// Called when the widget for this element changes.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4119`
    open func update(_ newWidget: Widget) {
        widget = newWidget
    }

    /// Transition from the "inactive" to the "active" lifecycle state.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4201`
    open func activate() {
        _lifecycleState = .active
        _dependencies?.removeAll()
        _hadUnsatisfiedDependencies = false
        _dirty = true
    }

    /// Transition from the "active" to the "inactive" lifecycle state.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4248`
    open func deactivate() {
        if let deps = _dependencies {
            for depId in deps {
                // Clean up dependency registrations
            }
        }
        _inheritedElements = nil
        _lifecycleState = .inactive
    }

    /// Called when this element is permanently removed from the tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:5197`
    open func unmount() {
        // Unregister global key
        if let key = widget.key, key is AnyObject {
            owner?._unregisterGlobalKey(key, self)
        }
        _lifecycleState = .defunct
    }

    /// Called whenever the application is reassembled during debugging.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4284`
    open func reassemble() {
        markNeedsBuild()
        visitChildElements { child in
            child.reassemble()
        }
    }

    // MARK: - Build

    /// Cause this element to rebuild.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4818`
    open func rebuild() {
        if !_dirty || _lifecycleState != .active {
            return
        }
        performRebuild()
        _debugBuiltOnce = true
    }

    /// Called by `rebuild` to actually perform the rebuild.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4857`
    open func performRebuild() {
        _dirty = false
    }

    /// Mark this element as needing to be rebuilt.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4908`
    open func markNeedsBuild() {
        if _lifecycleState != .active {
            return
        }
        if _dirty {
            return
        }
        _dirty = true
        owner?.scheduleBuildFor(self)
    }

    // MARK: - Child Management

    /// Add a new child element for the given widget at the given slot,
    /// updating an existing child if possible.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3770`
    open func updateChild(_ child: Element?, newWidget: Widget?, newSlot: Any?) -> Element? {
        if newWidget == nil {
            if let child = child {
                deactivateChild(child)
            }
            return nil
        }
        if let child = child {
            if child.widget === newWidget! {
                // Same widget, just update the slot
                if child._slot as AnyObject? !== newSlot as AnyObject? {
                    updateSlotForChild(child, newSlot)
                }
                return child
            }
            if Widget.canUpdate(child.widget, newWidget!) {
                if child._slot as AnyObject? !== newSlot as AnyObject? {
                    updateSlotForChild(child, newSlot)
                }
                child.update(newWidget!)
                child._dirty = true
                child.rebuild()
                return child
            }
            deactivateChild(child)
        }
        return inflateWidget(newWidget!, newSlot)
    }

    /// Update the slot of the given child.
    ///
    /// Walks the child element tree until a `RenderObjectElement` is found,
    /// then calls `moveRenderObjectChild` on its ancestor so the render tree
    /// reflects the new ordering.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3869`
    internal func updateSlotForChild(_ child: Element, _ newSlot: Any?) {
        func visit(_ element: Element) {
            let oldSlot = element._slot
            element._slot = newSlot
            if let roElement = element as? RenderObjectElement {
                roElement._ancestorRenderObjectElement?.moveRenderObjectChild(
                    roElement.renderObject!, oldSlot, newSlot
                )
            } else {
                element.visitChildElements { visit($0) }
            }
        }
        visit(child)
    }

    /// Create a new element for the given widget and add it as a child.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3904`
    open func inflateWidget(_ newWidget: Widget, _ newSlot: Any?) -> Element {
        let newChild = newWidget.createElement()
        newChild.mount(self, newSlot)
        return newChild
    }

    /// Move the given child to the inactive list.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3949`
    open func deactivateChild(_ child: Element) {
        child._parent = nil
        child.detachRenderObject()
        child.deactivate()
        owner?._inactiveElements.add(child)
    }

    /// Remove the given child from this element's child list.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3990`
    open func forgetChild(_ child: Element) {
        // Subclasses should override to remove from their child list.
    }

    /// Updates the children of this element to match the given list of widgets.
    ///
    /// This is the core multi-child diffing algorithm. It attempts to minimize
    /// the number of elements that need to be created or destroyed by reusing
    /// existing elements that match widgets by key or type.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4125`
    open func updateChildren(
        _ oldChildren: [Element],
        _ newWidgets: [Widget],
        forgottenChildren: Set<ObjectIdentifier>? = nil
    ) -> [Element] {
        // Helper: returns nil if the child has been forgotten, otherwise the child.
        func replaceWithNullIfForgotten(_ child: Element) -> Element? {
            if let forgotten = forgottenChildren, forgotten.contains(ObjectIdentifier(child)) {
                return nil
            }
            return child
        }

        // Helper: produce a slot value for the given index and previous child.
        func slotFor(_ newChildIndex: Int, _ previousChild: Element?) -> Any? {
            return IndexedSlot<Element?>(value: previousChild, index: newChildIndex)
        }

        var newChildrenTop = 0
        var oldChildrenTop = 0
        var newChildrenBottom = newWidgets.count - 1
        var oldChildrenBottom = oldChildren.count - 1

        var newChildren = [Element](repeating: _NullElement.instance, count: newWidgets.count)
        var previousChild: Element?

        // 1. Scan from the top, syncing matching widgets.
        while (oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom) {
            let oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenTop])
            let newWidget = newWidgets[newChildrenTop]
            if oldChild == nil || !Widget.canUpdate(oldChild!.widget, newWidget) {
                break
            }
            let newChild = updateChild(oldChild, newWidget: newWidget, newSlot: slotFor(newChildrenTop, previousChild))!
            newChildren[newChildrenTop] = newChild
            previousChild = newChild
            newChildrenTop += 1
            oldChildrenTop += 1
        }

        // 2. Scan from the bottom (without syncing), to find matching tail.
        while (oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom) {
            let oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenBottom])
            let newWidget = newWidgets[newChildrenBottom]
            if oldChild == nil || !Widget.canUpdate(oldChild!.widget, newWidget) {
                break
            }
            oldChildrenBottom -= 1
            newChildrenBottom -= 1
        }

        // 3. Scan the old children in the middle range.
        //    Build a key map for keyed children, deactivate non-keyed ones.
        let haveOldChildren = oldChildrenTop <= oldChildrenBottom
        var oldKeyedChildren: [AnyHashable: Element] = [:]
        if haveOldChildren {
            while oldChildrenTop <= oldChildrenBottom {
                let oldChild = replaceWithNullIfForgotten(oldChildren[oldChildrenTop])
                if let oldChild = oldChild {
                    if let key = oldChild.widget.key {
                        oldKeyedChildren[AnyHashable(key)] = oldChild
                    } else {
                        deactivateChild(oldChild)
                    }
                }
                oldChildrenTop += 1
            }
        }

        // 4. Update the middle range of the new list.
        while newChildrenTop <= newChildrenBottom {
            var oldChild: Element?
            let newWidget = newWidgets[newChildrenTop]
            if haveOldChildren {
                if let key = newWidget.key {
                    oldChild = oldKeyedChildren[AnyHashable(key)]
                    if let child = oldChild {
                        if Widget.canUpdate(child.widget, newWidget) {
                            oldKeyedChildren.removeValue(forKey: AnyHashable(key))
                        } else {
                            oldChild = nil
                        }
                    }
                }
            }
            let newChild = updateChild(oldChild, newWidget: newWidget, newSlot: slotFor(newChildrenTop, previousChild))!
            newChildren[newChildrenTop] = newChild
            previousChild = newChild
            newChildrenTop += 1
        }

        // 5. Sync the bottom widgets (scanned in step 2 but not yet updated).
        //    Reset bottom indices and walk forward through the remaining range.
        newChildrenBottom = newWidgets.count - 1
        oldChildrenBottom = oldChildren.count - 1
        while (oldChildrenTop <= oldChildrenBottom) && (newChildrenTop <= newChildrenBottom) {
            let oldChild = oldChildren[oldChildrenTop]
            let newWidget = newWidgets[newChildrenTop]
            let newChild = updateChild(oldChild, newWidget: newWidget, newSlot: slotFor(newChildrenTop, previousChild))!
            newChildren[newChildrenTop] = newChild
            previousChild = newChild
            newChildrenTop += 1
            oldChildrenTop += 1
        }

        // 6. Clean up remaining keyed old children that weren't reused.
        if haveOldChildren && !oldKeyedChildren.isEmpty {
            for (_, oldChild) in oldKeyedChildren {
                if let forgotten = forgottenChildren, forgotten.contains(ObjectIdentifier(oldChild)) {
                    continue
                }
                deactivateChild(oldChild)
            }
        }

        return newChildren
    }

    // MARK: - Dispatch Notification

    /// Dispatch a notification up the tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4705`
    open func dispatchNotification(_ notification: Notification) {
        _notificationTree?.dispatchNotification(notification)
    }

    /// Attach the notification tree from the parent.
    internal func attachNotificationTree() {
        if let self_ = self as? NotifiableElementMixin {
            _notificationTree = _NotificationNode(
                parent: _parent?._notificationTree,
                current: self_
            )
        } else {
            _notificationTree = _parent?._notificationTree
        }
    }

    // MARK: - Inherited Widgets

    /// Returns the nearest ancestor `InheritedWidget` of the exact type `T`,
    /// and registers this element as a dependent.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4450`
    open func dependOnInheritedWidgetOfExactType<T: InheritedWidget>(_ type: T.Type) -> T? {
        let ancestor = _inheritedElements?[T.self]
        if let ancestor = ancestor {
            return dependOnInheritedElement(ancestor) as? T
        }
        _hadUnsatisfiedDependencies = true
        return nil
    }

    /// Returns the `InheritedElement` for the nearest widget of the exact
    /// type `T`.
    open func getElementForInheritedWidgetOfExactType<T: InheritedWidget>(_ type: T.Type) -> InheritedElement? {
        return _inheritedElements?[T.self]
    }

    /// Registers this build context with `ancestor`.
    open func dependOnInheritedElement(_ ancestor: InheritedElement, aspect: AnyHashable? = nil) -> InheritedWidget {
        if _dependencies == nil {
            _dependencies = Set<ObjectIdentifier>()
        }
        _dependencies!.insert(ObjectIdentifier(ancestor))
        ancestor.updateDependencies(self, aspect: aspect)
        return ancestor.widget as! InheritedWidget
    }

    /// Update the inherited element map for this element.
    internal func _updateInheritance() {
        _inheritedElements = _parent?._inheritedElements ?? .empty
    }

    /// Called when a dependency changes.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4589`
    open func didChangeDependencies() {
        markNeedsBuild()
    }

    // MARK: - Ancestor Queries

    /// Walks the ancestor chain, calling `visitor` for each ancestor.
    open func visitAncestorElements(_ visitor: (Element) -> Bool) {
        var ancestor = _parent
        while let a = ancestor {
            if !visitor(a) {
                return
            }
            ancestor = a._parent
        }
    }

    /// Returns the nearest ancestor widget of the given type.
    open func findAncestorWidgetOfExactType<T: Widget>(_ type: T.Type) -> T? {
        var ancestor = _parent
        while let a = ancestor {
            if let w = a.widget as? T {
                return w
            }
            ancestor = a._parent
        }
        return nil
    }

    /// Returns the `State` object of the nearest ancestor `StatefulWidget`.
    open func findAncestorStateOfType<T: AnyObject>(_ type: T.Type) -> T? {
        var ancestor = _parent
        while let a = ancestor {
            if let statefulElement = a as? StatefulElement {
                if let state = statefulElement.state as? T {
                    return state
                }
            }
            ancestor = a._parent
        }
        return nil
    }

    /// Returns the `State` object of the furthest ancestor `StatefulWidget`.
    open func findRootAncestorStateOfType<T: AnyObject>(_ type: T.Type) -> T? {
        var result: T?
        var ancestor = _parent
        while let a = ancestor {
            if let statefulElement = a as? StatefulElement {
                if let state = statefulElement.state as? T {
                    result = state
                }
            }
            ancestor = a._parent
        }
        return result
    }

    /// Returns the `RenderObject` of the nearest ancestor `RenderObjectWidget`.
    open func findAncestorRenderObjectOfType<T: RenderObject>(_ type: T.Type) -> T? {
        var ancestor = _parent
        while let a = ancestor {
            if let roElement = a as? RenderObjectElement {
                if let ro = roElement.renderObject as? T {
                    return ro
                }
            }
            ancestor = a._parent
        }
        return nil
    }

    /// Returns the nearest `RenderObject` associated with this element.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4421`
    open func findRenderObject() -> RenderObject? {
        return nil
    }

    // MARK: - Attach / Detach Render Object (base)

    /// Attaches this element's render object to the render tree.
    ///
    /// The base implementation recursively calls `attachRenderObject` on all
    /// children. `RenderObjectElement` overrides this to actually insert the
    /// render object into the render tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4330`
    open func attachRenderObject(_ newSlot: Any?) {
        visitChildElements { child in
            child.attachRenderObject(newSlot)
        }
        _slot = newSlot
    }

    /// Detaches this element's render object from the render tree.
    ///
    /// The base implementation recursively calls `detachRenderObject` on all
    /// children. `RenderObjectElement` overrides this to actually remove the
    /// render object from the render tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4345`
    open func detachRenderObject() {
        visitChildElements { child in
            child.detachRenderObject()
        }
        _slot = nil
    }

    /// The size of the render object associated with this element.
    public var size: Size? {
        if let renderObject = findRenderObject() as? RenderBox {
            return renderObject.size
        }
        return nil
    }

    /// Calls the argument for each child element.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:4596`
    open func visitChildElements(_ visitor: (Element) -> Void) {
        // Subclasses must override to visit their children.
    }

    // MARK: - Description

    /// Returns a description of this element.
    open func describeElement(_ name: String) -> String {
        return "\(name): \(widget.toStringShort())"
    }

    /// Returns a description of the widget.
    open func describeWidget(_ name: String) -> String {
        return "\(name): \(widget.toStringShort())"
    }

    /// Returns a description of the ownership chain.
    open func describeOwnershipChain(_ name: String) -> String {
        return "\(name): \(debugGetCreatorChain(10))"
    }

    /// Returns a string representing the creator chain.
    public func debugGetCreatorChain(_ limit: Int) -> String {
        var chain: [String] = []
        var node: Element? = self
        while let n = node, chain.count < limit {
            chain.append(n.widget.toStringShort())
            node = n._parent
        }
        if node != nil {
            chain.append("...")
        }
        return chain.joined(separator: " \u{2190} ")
    }
}

// MARK: - RenderBox Size Access

/// Forward declaration for RenderBox.size access.
/// RenderBox is defined in the Rendering module.
internal extension RenderObject {
    /// Cast self to RenderBox and get the size, if available.
    var _asRenderBox: RenderBox? {
        return self as? RenderBox
    }
}

// MARK: - _SentinelWidget / _NullElement

/// Internal sentinel widget used by `_NullElement`.
///
/// This is the Swift equivalent of `_NullWidget` in the Dart framework source,
/// renamed to avoid collision with other `_NullWidget` types in the codebase.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7467`
internal class _SentinelWidget: Widget {
    override init(key: (any Key)? = nil) {
        super.init(key: nil)
    }

    override func createElement() -> Element {
        fatalError("_SentinelWidget should never be inflated")
    }
}

/// Internal sentinel element used as a placeholder in `updateChildren`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7462`
internal class _NullElement: Element {
    nonisolated(unsafe) static let instance = _NullElement()

    init() {
        super.init(_SentinelWidget())
    }
}

// MARK: - DebugCreator

/// A class attached to `RenderObject.debugCreator` to provide improved
/// error messages by linking render objects back to the creating element.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:7477`
public class DebugCreator: CustomStringConvertible {
    /// The element that created the associated render object.
    public let element: Element

    /// Creates a debug creator with the given element.
    public init(_ element: Element) {
        self.element = element
    }

    public var description: String {
        return element.debugGetCreatorChain(12)
    }
}
