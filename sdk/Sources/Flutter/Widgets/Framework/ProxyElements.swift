// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// MARK: - ProxyElement

/// An `Element` that uses a `ProxyWidget` as its configuration.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6138`
open class ProxyElement: ComponentElement {
    /// Creates an element for a proxy widget.
    public override init(_ widget: Widget) {
        super.init(widget)
    }

    open override func build() -> Widget {
        return (widget as! ProxyWidget).child
    }

    /// Called during `update` after the widget has been changed, to notify
    /// subclasses that the widget has been updated.
    ///
    /// By default, calls `notifyClients`. Subclasses (e.g., `InheritedElement`)
    /// can override to add conditional logic before notifying.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6162`
    open func updated(_ oldWidget: ProxyWidget) {
        notifyClients(oldWidget)
    }

    /// Notify other objects that the widget associated with this element has changed.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6170`
    open func notifyClients(_ oldWidget: ProxyWidget) {
        // Subclasses override this to notify dependents.
    }

    /// Called when the widget for this element changes.
    ///
    /// Saves the old widget, calls `super.update` to set the new widget,
    /// then calls `updated(oldWidget)` and forces a rebuild.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6148`
    open override func update(_ newWidget: Widget) {
        let oldWidget = widget as! ProxyWidget
        super.update(newWidget)
        updated(oldWidget)
        // Note: super.update (ComponentElement) already sets _dirty and calls rebuild()
    }
}

// MARK: - ParentDataElement

/// An `Element` that uses a `ParentDataWidget` as its configuration.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6174`
open class ParentDataElement<T: ParentData>: ProxyElement {
    /// Creates an element that uses the given widget as its configuration.
    public init(_ widget: ParentDataWidget<T>) {
        super.init(widget)
    }

    /// Walks the child subtree, applying the given `ParentDataWidget`'s parent
    /// data to each `RenderObjectElement`'s render object.
    ///
    /// If a child is a `RenderObjectElement`, we call `applyParentData` on its
    /// render object directly. Otherwise, we recurse through `visitChildElements`.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6178`
    private func _applyParentData(_ widget: ParentDataWidget<T>) {
        func applyParentDataToChild(_ child: Element) {
            if let renderObjectElement = child as? RenderObjectElement {
                if let renderObj = renderObjectElement.renderObject {
                    widget.applyParentData(renderObj)
                }
            } else {
                child.visitChildElements(applyParentDataToChild)
            }
        }
        visitChildElements(applyParentDataToChild)
    }

    /// Apply the parent data from the given widget out of turn (i.e., not
    /// during a normal widget update).
    ///
    /// This is used when parent data needs to be applied eagerly, outside of
    /// the normal build/update cycle. The new widget must have the same child
    /// as the current widget.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6188`
    open func applyWidgetOutOfTurn(_ newWidget: ParentDataWidget<T>) {
        _applyParentData(newWidget)
    }

    /// Notifies clients by applying the current widget's parent data to all
    /// descendant render objects.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6194`
    open override func notifyClients(_ oldWidget: ProxyWidget) {
        _applyParentData(widget as! ParentDataWidget<T>)
    }
}

// MARK: - InheritedElement

/// An `Element` that uses an `InheritedWidget` as its configuration.
///
/// This element maintains a map of dependents (elements that have registered
/// themselves as depending on this inherited widget). When the inherited widget
/// changes and `updateShouldNotify` returns true, all dependents are notified.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6208`
open class InheritedElement: ProxyElement {
    public init(_ widget: InheritedWidget) {
        super.init(widget)
    }

    /// One dependent registration. The element reference is `weak`, and that
    /// is load bearing: an InheritedElement is long-lived (the app's theme
    /// lives as long as the app), and upstream relies on `deactivate()`
    /// unregistering every dependent — which requires recursive deactivation
    /// this port does not do. With a strong reference here, every element
    /// that ever depended on an inherited widget was pinned by the live
    /// theme after its subtree was dropped, together with its widget and the
    /// widget's whole span tree — measured at ~5 MB per styled dump in the
    /// terminal (heaptrack: 34.5 MB of TextSpans over 7 passes, all rooted
    /// in dead-but-retained Text elements). Weak registration is the ARC
    /// equivalent of Dart's collectable back-reference: a freed dependent
    /// simply reads nil and is purged on the next notify.
    internal final class _DependentEntry {
        weak var element: Element?
        var value: AnyObject?
        init(_ element: Element, _ value: AnyObject?) {
            self.element = element
            self.value = value
        }
    }

    /// The set of dependents, mapping element identity to the (weakly held)
    /// element and an optional dependency value.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6211`
    internal var _dependents: [ObjectIdentifier: _DependentEntry] = [:]

    // MARK: - Inheritance

    /// Overrides the default inheritance update to register this element in
    /// the inherited elements map under its widget's runtime type.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6215`
    internal override func _updateInheritance() {
        let incomingWidgets = _parent?._inheritedElements ?? .empty
        _inheritedElements = incomingWidgets.putting(
            typeIdentifier: ObjectIdentifier(type(of: widget)),
            self
        )
    }

    // MARK: - Dependency Management

    /// Returns the dependencies value for the given dependent.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6221`
    open func getDependencies(_ dependent: Element) -> AnyObject? {
        return _dependents[ObjectIdentifier(dependent)]?.value
    }

    /// Sets the dependencies value for the given dependent.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6225`
    open func setDependencies(_ dependent: Element, _ value: AnyObject?) {
        _dependents[ObjectIdentifier(dependent)] = _DependentEntry(dependent, value)
    }

    /// Called when a dependent is added or updated.
    ///
    /// By default, stores `nil` as the dependency value.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6229`
    open func updateDependencies(_ dependent: Element, aspect: AnyHashable?) {
        setDependencies(dependent, nil)
    }

    /// Called to notify a dependent that the inherited value has changed.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6233`
    open func notifyDependent(_ oldWidget: InheritedWidget, _ dependent: Element) {
        dependent.didChangeDependencies()
    }

    /// Removes a dependent from this element's set of dependents.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6237`
    open func removeDependent(_ dependent: Element) {
        _dependents.removeValue(forKey: ObjectIdentifier(dependent))
    }

    // MARK: - Update & Notify

    /// Called after the widget has been updated. Only notifies clients (via
    /// `super.updated`, which calls `notifyClients`) if the new widget's
    /// `updateShouldNotify` returns `true` for the old widget.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6241`
    open override func updated(_ oldWidget: ProxyWidget) {
        if (widget as! InheritedWidget).updateShouldNotify(oldWidget as! InheritedWidget) {
            super.updated(oldWidget)
        }
    }

    /// Notifies all dependents that the inherited value may have changed.
    ///
    /// Iterates over every dependent element and calls `notifyDependent` for
    /// each one, which by default calls `didChangeDependencies()` on the
    /// dependent.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:6249`
    open override func notifyClients(_ oldWidget: ProxyWidget) {
        let oldInherited = oldWidget as! InheritedWidget
        // Purge entries whose dependent has been freed (weak ref reads nil),
        // so the registration map cannot grow without bound either.
        var dead: [ObjectIdentifier] = []
        for (id, entry) in _dependents {
            if let element = entry.element {
                notifyDependent(oldInherited, element)
            } else {
                dead.append(id)
            }
        }
        for id in dead { _dependents.removeValue(forKey: id) }
    }
}
