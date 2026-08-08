import Glibc
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// MARK: - Widget

/// Describes the configuration for an `Element`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:312`
open class Widget {
    /// The key for this widget.
    public let key: (any Key)?

    /// Creates a widget.
    public init(key: (any Key)? = nil) {
        self.key = key
    }

    /// Creates the element that manages this widget.
    open func createElement() -> Element {
        fatalError("Subclasses must override createElement()")
    }

    /// Whether the `newWidget` can be used to update an `Element` that currently
    /// has the `oldWidget` as its configuration.
    ///
    /// An element can be updated if the new widget has the same runtime type
    /// and key as the old widget.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:488`
    public static func canUpdate(_ oldWidget: Widget, _ newWidget: Widget) -> Bool {
        let verdict = type(of: oldWidget) == type(of: newWidget)
            && _equalKeys(oldWidget.key, newWidget.key)
        if oldWidget is RichText, let e = getenv("STARLING_TEXT_DEBUG"),
           (e.pointee == 49 || e.pointee == 50) {
            let msg = verdict ? "[canUpdate RichText] true\n"
                              : "[canUpdate RichText] FALSE\n"
            _ = msg.withCString { write(2, $0, strlen($0)) }
        }
        return verdict
    }

    /// Returns a one-line detailed description of the widget.
    open func toStringShort() -> String {
        if let key = key {
            return "\(objectRuntimeType(self, "Widget"))-[\(key)]"
        }
        return objectRuntimeType(self, "Widget")
    }

    /// Compare two optional Key values for equality using AnyHashable type erasure.
    private static func _equalKeys(_ a: (any Key)?, _ b: (any Key)?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case (let a?, let b?):
            return _toAnyHashable(a) == _toAnyHashable(b)
        default:
            return false
        }
    }

    /// Type-erase a Key to AnyHashable for comparison.
    private static func _toAnyHashable<T: Key>(_ key: T) -> AnyHashable {
        return AnyHashable(key)
    }
}

// MARK: - StatelessWidget

/// A widget that does not require mutable state.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:614`
open class StatelessWidget: Widget {
    /// Creates a stateless widget.
    public override init(key: (any Key)? = nil) {
        super.init(key: key)
    }

    /// Describes the part of the user interface represented by this widget.
    open func build(_ context: any BuildContext) -> Widget {
        fatalError("Subclasses must override build()")
    }

    open override func createElement() -> Element {
        return StatelessElement(self)
    }
}

// MARK: - StatefulWidget

/// A widget that has mutable state.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:771`
open class StatefulWidget: Widget {
    /// Creates a stateful widget.
    public override init(key: (any Key)? = nil) {
        super.init(key: key)
    }

    /// Creates the mutable state for this widget at a given location in the tree.
    open func createState() -> State<StatefulWidget> {
        fatalError("Subclasses must override createState()")
    }

    open override func createElement() -> Element {
        return StatefulElement(self)
    }
}

// MARK: - _StateLifecycle

/// Tracks the lifecycle of `State` objects.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:907`
internal enum _StateLifecycle {
    /// The state has been created. `State.initState` is called at this point.
    case created

    /// `State.initState` has been called but the `State` object has not yet
    /// been built for the first time. `State.didChangeDependencies` is called
    /// at this point.
    case initialized

    /// The `State` object has been built at least once and
    /// `State.dispose` has not yet been called.
    case ready

    /// `State.dispose` has been called and the `State` object is no longer
    /// able to build.
    case defunct
}

// MARK: - StateSetter

/// Signature of callbacks that can be called with `setState`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:913`
public typealias StateSetter = (@escaping () -> Void) -> Void

// MARK: - State

/// The logic and internal state for a `StatefulWidget`.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:916`
open class State<T: StatefulWidget> {
    /// The current configuration.
    public internal(set) var widget: T?

    /// The location in the tree where this widget builds.
    public internal(set) weak var context: (any BuildContext)?

    /// Whether this state object is currently in a tree.
    public internal(set) var mounted: Bool = false

    /// The current lifecycle stage of this state.
    internal var _debugLifecycleState: _StateLifecycle = .created

    /// Creates a state object.
    public init() {}

    // MARK: - Lifecycle Methods

    /// Called when this object is inserted into the tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1088`
    open func initState() {
        assert(_debugLifecycleState == .created)
    }

    /// Called whenever the widget configuration changes.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1124`
    open func didUpdateWidget(_ oldWidget: T) {}

    /// Notify the framework that the internal state of this object has changed.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1175`
    open func setState(_ fn: () -> Void) {
        fn()
        if let element = context as? Element {
            element.markNeedsBuild()
        }
    }

    /// Called when this object is removed from the tree.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1264`
    open func deactivate() {}

    /// Called when this object is reinserted into the tree after having been
    /// removed via `deactivate`.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1288`
    open func activate() {}

    /// Called when this object is removed from the tree permanently.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1333`
    open func dispose() {
        assert(_debugLifecycleState == .ready || _debugLifecycleState == .created)
        _debugLifecycleState = .defunct
    }

    /// Describes the part of the user interface represented by this widget.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1392`
    open func build(_ context: any BuildContext) -> Widget {
        fatalError("Subclasses must override build()")
    }

    /// Called when a dependency of this `State` object changes.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1439`
    open func didChangeDependencies() {}

    /// Called whenever the application is reassembled during debugging,
    /// for example during hot reload.
    ///
    /// **Dart Source:** `packages/flutter/lib/src/widgets/framework.dart:1379`
    open func reassemble() {}
}
