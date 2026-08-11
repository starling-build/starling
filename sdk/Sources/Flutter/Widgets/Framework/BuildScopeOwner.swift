// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridge

// MARK: - BuildScope

/// A scope for tracking dirty elements that need to be rebuilt.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:2684`
public final class BuildScope {
    /// The dirty elements in this scope.
    internal var _dirtyElements: [Element] = []

    /// Whether we are actively rebuilding the widget tree.
    internal var _building = false

    /// Whether the dirty list needs sorting.
    internal var _dirtyElementsNeedsResorting: Bool?

    /// Whether this scope is actively scheduling builds.
    internal var _scheduledFlushDirtyElements = false

    /// Creates a build scope.
    public init() {}

    /// Whether there are dirty elements that need to be rebuilt.
    public var dirty: Bool {
        return !_dirtyElements.isEmpty
    }

    /// Schedule the given element to be rebuilt.
    internal func _scheduleBuildFor(_ element: Element) {
        if !_scheduledFlushDirtyElements && onBuildScheduled != nil {
            _scheduledFlushDirtyElements = true
            onBuildScheduled?()
        }
        _dirtyElements.append(element)
    }

    /// Callback invoked when a build is scheduled.
    internal var onBuildScheduled: (() -> Void)?
}

// MARK: - BuildOwner

/// Manager class for the build process of the widget tree.
///
/// Tracks which widgets need rebuilding, and handles other tasks that apply
/// to widget trees as a whole, such as managing the inactive element list
/// for the tree and triggering the "reassemble" command when necessary during
/// hot reload when debugging.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:2960`
public class BuildOwner {
    /// Creates a build owner.
    public init(onBuildScheduled: (() -> Void)? = nil) {
        self.onBuildScheduled = onBuildScheduled
    }

    /// Called on each build pass when the first buildable element is marked dirty.
    public var onBuildScheduled: (() -> Void)?

    /// The focus manager for this build owner.
    public var focusManager: FocusManager = FocusManager()

    /// The global key registry, mapping `ObjectIdentifier` of GlobalKey instances
    /// to the Element currently using that key.
    internal var _globalKeyRegistry: [ObjectIdentifier: Element] = [:]

    /// The inactive elements managed by this build owner.
    internal let _inactiveElements = _InactiveElements()

    /// Whether the build owner is currently in a state where calling `setState`
    /// would be illegal.
    internal var _debugStateLocked = false

    /// Whether we are currently in `buildScope`.
    internal var _debugBuilding = false

    /// The element that is currently being rebuilt.
    internal var _debugCurrentBuildTarget: Element?

    /// The default `BuildScope` for this owner.
    public let buildScope = BuildScope()

    // MARK: - Global Key Registration

    /// Register a global key with the given element.
    internal func _registerGlobalKey(_ key: any Key, _ element: Element) {
        _globalKeyRegistry[ObjectIdentifier(key as AnyObject)] = element
    }

    /// Unregister a global key.
    internal func _unregisterGlobalKey(_ key: any Key, _ element: Element) {
        if _globalKeyRegistry[ObjectIdentifier(key as AnyObject)] === element {
            _globalKeyRegistry.removeValue(forKey: ObjectIdentifier(key as AnyObject))
        }
    }

    // MARK: - Build Management

    /// Adds an element to the dirty elements list so that it will be rebuilt
    /// when `buildScope` is called.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3099`
    public func scheduleBuildFor(_ element: Element) {
        assert(!_debugStateLocked)
        element._inDirtyList = true
        buildScope._dirtyElements.append(element)
        if !buildScope._scheduledFlushDirtyElements {
            onBuildScheduled?()
        }
    }

    /// Establishes a scope for updating the widget tree, and calls the given
    /// `callback`, if any. Then, rebuilds any elements that have been marked
    /// dirty during the scope.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3135`
    public func buildScopeWithCallback(
        _ context: Element,
        callback: (() -> Void)? = nil
    ) {
        if callback == nil && buildScope._dirtyElements.isEmpty {
            return
        }
        _debugBuilding = true
        buildScope._building = true

        callback?()

        // Sort dirty elements by depth
        buildScope._dirtyElements.sort { $0.depth < $1.depth }

        var dirtyCount = buildScope._dirtyElements.count
        var index = 0
        while index < dirtyCount {
            let element = buildScope._dirtyElements[index]
            if element._dirty {
                element.rebuild()
            }
            index += 1
            if dirtyCount < buildScope._dirtyElements.count {
                // More elements were dirtied during rebuild
                buildScope._dirtyElements.sort { $0.depth < $1.depth }
                dirtyCount = buildScope._dirtyElements.count
            }
        }

        for element in buildScope._dirtyElements {
            element._inDirtyList = false
        }
        buildScope._dirtyElements.removeAll()
        buildScope._building = false
        _debugBuilding = false
    }

    /// Ensures callbacks are called within a locked state where `setState` is
    /// disallowed. Used during finalization to prevent new state changes.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3040`
    public func lockState(_ callback: () -> Void) {
        let previousLocked = _debugStateLocked
        _debugStateLocked = true
        callback()
        _debugStateLocked = previousLocked
    }

    /// Complete the element lifecycle for elements that have been deactivated.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3283`
    public func finalizeTree() {
        lockState {
            _inactiveElements._unmountAll()
        }
    }

    /// Cause the entire subtree rooted at the given `Element` to be entirely
    /// rebuilt.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3323`
    public func reassemble(_ root: Element) {
        root.reassemble()
    }
}

// MARK: - _InactiveElements

/// Manages a set of deactivated elements, calling `unmount` on them when
/// they are permanently removed.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:2893`
internal final class _InactiveElements {
    /// The set of elements that have been deactivated and are awaiting
    /// permanent removal.
    var _elements: Set<ObjectIdentifier> = []

    /// Mapping from ObjectIdentifier back to the actual Element.
    var _elementMap: [ObjectIdentifier: Element] = [:]

    /// Add an element to the inactive set.
    func add(_ element: Element) {
        let id = ObjectIdentifier(element)
        if _elements.insert(id).inserted {
            _elementMap[id] = element
        }
    }

    /// Remove an element from the inactive set.
    @discardableResult
    func remove(_ element: Element) -> Bool {
        let id = ObjectIdentifier(element)
        if _elements.remove(id) != nil {
            _elementMap.removeValue(forKey: id)
            return true
        }
        return false
    }

    /// Unmount all inactive elements.
    func _unmountAll() {
        // Sort by depth (deepest first) to unmount children before parents
        let sorted = _elementMap.values.sorted { $0.depth > $1.depth }
        for element in sorted {
            _unmount(element)
        }
        _elements.removeAll()
        _elementMap.removeAll()
    }

    /// Recursively unmount `element` and everything below it, children first.
    ///
    /// The recursion is upstream behaviour (`_InactiveElements._unmount` in
    /// framework.dart) and it was missing here: only the deactivated subtree
    /// ROOT was unmounted, so no descendant ever saw `unmount()` — which
    /// meant `RenderObjectElement.unmount`'s `renderObject.dispose()` never
    /// ran for anything inside a dropped subtree, and a `RenderParagraph`'s
    /// engine-side paragraph outlived its row. Measured on the terminal's
    /// styled-dump probe: ~90 RenderParagraphs created, ZERO disposed.
    private func _unmount(_ element: Element) {
        element.visitChildElements { child in
            _unmount(child)
        }
        element.unmount()
    }
}

// MARK: - _NotificationNode

/// A node in the notification dispatch linked list.
///
/// Each element maintains a reference to its notification node, which links
/// to the parent's notification node, allowing efficient notification dispatch.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:3456`
internal final class _NotificationNode {
    /// The parent node in the notification chain.
    weak var parent: _NotificationNode?

    /// The element associated with this notification node, if it is a
    /// `NotifiableElementMixin`.
    weak var current: (any NotifiableElementMixin)?

    /// Creates a notification node.
    init(parent: _NotificationNode?, current: (any NotifiableElementMixin)?) {
        self.parent = parent
        self.current = current
    }

    /// Dispatch a notification through the chain.
    func dispatchNotification(_ notification: Notification) {
        if let current = current {
            if current.onNotification(notification) {
                return  // Notification was handled
            }
        }
        parent?.dispatchNotification(notification)
    }
}
