// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Listener helper classes for animation infrastructure.
///
/// **Dart Source:** `packages/flutter/lib/src/animation/listener_helpers.dart`

import FlutterSwiftBridge

// MARK: - AnimationLazyListenerMixin

/// A class that helps listen to another object only when this object has
/// registered listeners.
///
/// This class provides implementations of `didRegisterListener` and
/// `didUnregisterListener`, and therefore can be used in conjunction with
/// classes that require these methods, `AnimationLocalListenersMixin` and
/// `AnimationLocalStatusListenersMixin`.
///
/// **Dart Source:** `listener_helpers.dart:18-63`
/// **Original Kind:** `mixin`
///
/// DIFFERENCE FROM DART: Dart mixin converted to Swift open class.
/// REASON: Swift does not have mixins with stored properties.
open class AnimationLazyListenerMixin {
    public init() {}

    private var _listenerCounter: Int = 0

    /// Calls `didStartListening` every time a registration of a listener causes
    /// an empty list of listeners to become non-empty.
    ///
    /// **Dart Source:** `listener_helpers.dart:30-36`
    open func didRegisterListener() {
        assert(_listenerCounter >= 0)
        if _listenerCounter == 0 {
            didStartListening()
        }
        _listenerCounter += 1
    }

    /// Calls `didStopListening` when an only remaining listener is unregistered,
    /// thus making the list empty.
    ///
    /// **Dart Source:** `listener_helpers.dart:45-51`
    open func didUnregisterListener() {
        assert(_listenerCounter >= 1)
        _listenerCounter -= 1
        if _listenerCounter == 0 {
            didStopListening()
        }
    }

    /// Called when the number of listeners changes from zero to one.
    ///
    /// **Dart Source:** `listener_helpers.dart:55`
    open func didStartListening() {
        fatalError("Subclass must override didStartListening")
    }

    /// Called when the number of listeners changes from one to zero.
    ///
    /// **Dart Source:** `listener_helpers.dart:59`
    open func didStopListening() {
        fatalError("Subclass must override didStopListening")
    }

    /// Whether there are any listeners.
    ///
    /// **Dart Source:** `listener_helpers.dart:62`
    public var isListening: Bool { _listenerCounter > 0 }
}

// MARK: - AnimationEagerListenerMixin

/// A class that replaces the `didRegisterListener`/`didUnregisterListener`
/// contract with a dispose contract.
///
/// This class provides implementations of `didRegisterListener` and
/// `didUnregisterListener` as no-ops, and provides a `dispose()` method for
/// cleanup.
///
/// **Dart Source:** `listener_helpers.dart:71-84`
/// **Original Kind:** `mixin`
///
/// DIFFERENCE FROM DART: Dart mixin converted to Swift open class.
/// REASON: Swift does not have mixins with stored properties.
open class AnimationEagerListenerMixin {
    public init() {}

    /// This implementation ignores listener registrations.
    ///
    /// **Dart Source:** `listener_helpers.dart:73-74`
    open func didRegisterListener() {}

    /// This implementation ignores listener registrations.
    ///
    /// **Dart Source:** `listener_helpers.dart:77-78`
    open func didUnregisterListener() {}

    /// Release the resources used by this object. The object is no longer usable
    /// after this method is called.
    ///
    /// **Dart Source:** `listener_helpers.dart:82-83`
    open func dispose() {}
}

// MARK: - AnimationLocalListenersMixin

/// A class that implements the `addListener`/`removeListener` protocol and
/// notifies all the registered listeners when `notifyListeners` is called.
///
/// This class requires that the subclass provide methods `didRegisterListener`
/// and `didUnregisterListener`. Implementations of these methods can be obtained
/// by subclassing `AnimationLazyListenerMixin` or `AnimationEagerListenerMixin`.
///
/// **Dart Source:** `listener_helpers.dart:92-175`
/// **Original Kind:** `mixin`
///
/// DIFFERENCE FROM DART: Dart mixin converted to Swift open class.
/// REASON: Swift does not have mixins with stored properties.
///
/// DIFFERENCE FROM DART: Uses a `ListenerList` instead of
/// `HashedObserverList`; unkeyed removal pops the last unkeyed listener,
/// keyed removal is exact. See `ListenerList`.
open class AnimationLocalListenersMixin {
    public init() {}

    private var _listeners = ListenerList()

    /// Called immediately before a listener is added via `addListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:100`
    open func didRegisterListener() {
        fatalError("Subclass must override didRegisterListener")
    }

    /// Called immediately after a listener is removed via `removeListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:107`
    open func didUnregisterListener() {
        fatalError("Subclass must override didUnregisterListener")
    }

    /// Calls the listener every time the value of the animation changes.
    ///
    /// Listeners can be removed with `removeListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:112-115`
    public func addListener(_ listener: @escaping VoidCallback) {
        didRegisterListener()
        _listeners.append(listener)
    }

    /// Stop calling the listener every time the value of the animation changes.
    ///
    /// Listeners can be added with `addListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:120-125`
    ///
    /// DIFFERENCE FROM DART: removes the last unkeyed listener; see
    /// `ListenerList`.
    public func removeListener(_ listener: @escaping VoidCallback) {
        if _listeners.removeLast() {
            didUnregisterListener()
        }
    }

    /// Keyed registration; see `Listenable.addListener(_:owner:)`.
    public func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        didRegisterListener()
        _listeners.append(listener, owner: owner)
    }

    /// Keyed removal; see `Listenable.removeListeners(owner:)`.
    public func removeListeners(owner: AnyObject) {
        for _ in 0..<_listeners.remove(owner: owner) {
            didUnregisterListener()
        }
    }

    /// Removes all listeners added with `addListener`.
    ///
    /// This method is typically called from the `dispose` method.
    /// Calling this method will not trigger `didUnregisterListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:134-136`
    public func clearListeners() {
        _listeners.removeAll()
    }

    /// Calls all the listeners.
    ///
    /// If listeners are added or removed during this function, the modifications
    /// will not change which listeners are called during this iteration.
    ///
    /// **Dart Source:** `listener_helpers.dart:144-174`
    public func notifyListeners() {
        let localListeners = _listeners
        for listener in localListeners {
            listener()
        }
    }
}

// MARK: - AnimationLocalStatusListenersMixin

/// A class that implements the `addStatusListener`/`removeStatusListener`
/// protocol and notifies all the registered listeners when
/// `notifyStatusListeners` is called.
///
/// This class requires that the subclass provide methods `didRegisterListener`
/// and `didUnregisterListener`. Implementations of these methods can be obtained
/// by subclassing `AnimationLazyListenerMixin` or `AnimationEagerListenerMixin`.
///
/// **Dart Source:** `listener_helpers.dart:184-268`
/// **Original Kind:** `mixin`
///
/// DIFFERENCE FROM DART: Dart mixin converted to Swift open class.
/// REASON: Swift does not have mixins with stored properties.
///
/// DIFFERENCE FROM DART: Uses array-based listener list instead of
/// `ObserverList`. Listener removal removes from the end (last added).
/// REASON: Swift closures do not support equality comparison.
open class AnimationLocalStatusListenersMixin {
    public init() {}

    private var _statusListeners: [AnimationStatusListener] = []

    /// Called immediately before a status listener is added via `addStatusListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:193`
    open func didRegisterListener() {
        fatalError("Subclass must override didRegisterListener")
    }

    /// Called immediately after a status listener is removed via `removeStatusListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:200`
    open func didUnregisterListener() {
        fatalError("Subclass must override didUnregisterListener")
    }

    /// Calls listener every time the status of the animation changes.
    ///
    /// Listeners can be removed with `removeStatusListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:205-208`
    public func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        didRegisterListener()
        _statusListeners.append(listener)
    }

    /// Stops calling the listener every time the status of the animation changes.
    ///
    /// Listeners can be added with `addStatusListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:213-218`
    ///
    /// DIFFERENCE FROM DART: Removes from the end since Swift closures
    /// don't support equality. Caller should pass the same closure reference.
    /// REASON: Swift closures are not Equatable.
    public func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        if !_statusListeners.isEmpty {
            _statusListeners.removeLast()
            didUnregisterListener()
        }
    }

    /// Removes all listeners added with `addStatusListener`.
    ///
    /// This method is typically called from the `dispose` method.
    /// Calling this method will not trigger `didUnregisterListener`.
    ///
    /// **Dart Source:** `listener_helpers.dart:227-229`
    public func clearStatusListeners() {
        _statusListeners.removeAll()
    }

    /// Calls all the status listeners.
    ///
    /// If listeners are added or removed during this function, the modifications
    /// will not change which listeners are called during this iteration.
    ///
    /// **Dart Source:** `listener_helpers.dart:237-267`
    public func notifyStatusListeners(_ status: AnimationStatus) {
        let localListeners = _statusListeners
        for listener in localListeners {
            listener(status)
        }
    }
}
