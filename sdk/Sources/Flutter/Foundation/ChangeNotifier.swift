// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Change notification protocols and classes.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/change_notifier.dart`

import FlutterSwiftBridge

// MARK: - Listenable

/// An object that maintains a list of listeners.
///
/// The listeners are typically used to notify clients that the object has been
/// updated.
///
/// There are two variants of this interface:
///
///  * `ValueListenable`, an interface that augments the `Listenable` interface
///    with the concept of a _current value_.
///
///  * `Animation`, an interface that augments the `ValueListenable` interface
///    to add the concept of direction (forward or reverse).
///
/// Many classes in the Flutter API use or implement these interfaces. The
/// following subclasses are especially relevant:
///
///  * `ChangeNotifier`, which can be subclassed or mixed in to create objects
///    that implement the `Listenable` interface.
///
///  * `ValueNotifier`, a class that holds a single value and notifies listeners
///    when the value changes.
///
/// See also:
///
///  * `AnimatedBuilder`, a widget that uses a builder callback to rebuild
///    whenever a given `Listenable` triggers its notifications.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/change_notifier.dart`
/// **Lines:** 62-82
public protocol Listenable {
    /// Register a closure to be called when the object notifies its listeners.
    ///
    /// **Dart Source:** `change_notifier.dart:76-77`
    func addListener(_ listener: @escaping VoidCallback)

    /// Remove a previously registered closure from the list of closures that the
    /// object notifies.
    ///
    /// **Dart Source:** `change_notifier.dart:79-81`
    ///
    /// DIFFERENCE FROM DART: Dart removes the listener whose identity matches.
    /// Swift closures have no usable identity (see `ListenerList`), so this
    /// removes the most recently added *unkeyed* listener — exact when the
    /// object has one such listener, which is the common case, and wrong
    /// otherwise. Code that may share a notifier with anyone else registers
    /// with `addListener(_:owner:)` and removes with `removeListeners(owner:)`.
    func removeListener(_ listener: @escaping VoidCallback)

    /// Register a closure under an owner's identity, so that
    /// `removeListeners(owner:)` can later remove exactly it.
    ///
    /// DIFFERENCE FROM DART: no counterpart. Dart identifies a listener by the
    /// closure itself; Swift cannot, so the owner (typically the render object
    /// or state that registered it) stands in for the closure's identity.
    func addListener(_ listener: @escaping VoidCallback, owner: AnyObject)

    /// Remove every listener registered under `owner` by
    /// `addListener(_:owner:)`. Unkeyed listeners are untouched.
    func removeListeners(owner: AnyObject)
}

extension Listenable {
    /// Fallback for a `Listenable` with no store of its own: registers
    /// unkeyed. Every framework `Listenable` that stores or forwards
    /// listeners overrides both keyed methods; a conformer that does not
    /// keeps its keyed listeners forever (a leak, never a wrong removal).
    public func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        addListener(listener)
    }

    public func removeListeners(owner: AnyObject) {}
}

// MARK: - ListenerList

/// The listener store behind every framework `Listenable` that keeps its own
/// listeners (`ChangeNotifier`, the animation stores, `SystemFontsNotifier`).
///
/// Swift closures carry no identity: reading the same stored closure twice
/// yields two thunks with different function pointers, so `removeListener(_:)`
/// cannot find "the closure that was added" — the port's original stores
/// popped the last listener instead, which is right only while a notifier has
/// a single listener. Once render objects detach for real (every dropped
/// subtree, not only the root), an animation shared between a `FadeTransition`
/// and its `RenderAnimatedOpacity` would lose whichever listener was added
/// last. This store therefore keeps an optional owner identity per entry:
/// keyed entries are removed by owner, exactly; the unkeyed pop never touches
/// them.
public struct ListenerList: Sequence {
    private struct Entry {
        let owner: ObjectIdentifier?
        let call: VoidCallback
    }

    private var _entries: [Entry] = []

    public init() {}

    public var isEmpty: Bool { _entries.isEmpty }
    public var count: Int { _entries.count }

    /// Add an unkeyed listener.
    public mutating func append(_ listener: @escaping VoidCallback) {
        _entries.append(Entry(owner: nil, call: listener))
    }

    /// Add a listener under `owner`'s identity.
    public mutating func append(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _entries.append(Entry(owner: ObjectIdentifier(owner), call: listener))
    }

    /// Remove the most recently added unkeyed listener, if any. This is the
    /// whole of what `removeListener(_:)` can do; see the type comment.
    @discardableResult
    public mutating func removeLast() -> Bool {
        guard let index = _entries.lastIndex(where: { $0.owner == nil }) else {
            return false
        }
        _entries.remove(at: index)
        return true
    }

    /// Remove every listener registered under `owner`; returns how many.
    @discardableResult
    public mutating func remove(owner: AnyObject) -> Int {
        let id = ObjectIdentifier(owner)
        let before = _entries.count
        _entries.removeAll { $0.owner == id }
        return before - _entries.count
    }

    public mutating func removeAll() {
        _entries.removeAll()
    }

    /// Iterates a snapshot of the callbacks in registration order, so a
    /// listener that adds or removes listeners while being notified does not
    /// disturb the iteration.
    public func makeIterator() -> IndexingIterator<[VoidCallback]> {
        _entries.map { $0.call }.makeIterator()
    }
}

// MARK: - ValueListenable

/// An interface for subclasses of `Listenable` that expose a value.
///
/// This interface is implemented by `ValueNotifier<T>` and `Animation<T>`, and
/// allows other APIs to accept either of those implementations interchangeably.
///
/// See also:
///
///  * `ValueListenableBuilder`, a widget that uses a builder callback to
///    rebuild whenever a `ValueListenable` object triggers its notifications.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/change_notifier.dart`
/// **Lines:** 84-107
public protocol ValueListenable: Listenable {
    associatedtype Value

    /// The current value of the object. When the value changes, the callbacks
    /// registered with `addListener` will be invoked.
    ///
    /// **Dart Source:** `change_notifier.dart:104-106`
    var value: Value { get }
}

// MARK: - ChangeNotifier

/// A class that can be extended or mixed in to provide change notification.
///
/// Listeners live in a `ListenerList`: unkeyed ones are removed last-in
/// first-out by `removeListener(_:)`, keyed ones exactly by
/// `removeListeners(owner:)`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/change_notifier.dart`
/// **Lines:** 137-352
/// **Original Name:** `ChangeNotifier`
///
/// DIFFERENCE FROM DART: Dart's `ChangeNotifier` is a `mixin class`; Swift uses
/// a regular `class` since Swift does not have mixins.
/// REASON: Swift `class` with `Listenable` conformance is the closest equivalent.
open class ChangeNotifier: Listenable {

  public init() {}

  /// **Dart Source:** `change_notifier.dart:171-173`
  private var _listeners = ListenerList()

  /// Whether any listeners are currently registered.
  ///
  /// **Dart Source:** `change_notifier.dart:199`
  /// **Original:** `bool get hasListeners => _count > 0;`
  public var hasListeners: Bool { !_listeners.isEmpty }

  /// Whether `dispose` has been called.
  private var _debugDisposed: Bool = false

  /// Register a closure to be called when the object changes.
  ///
  /// **Dart Source:** `change_notifier.dart:217-247`
  /// **Original:** `void addListener(VoidCallback listener)`
  public func addListener(_ listener: @escaping VoidCallback) {
    assert(!_debugDisposed, "A \(type(of: self)) was used after being disposed.\nOnce you have called dispose() on a \(type(of: self)), it can no longer be used.")
    _listeners.append(listener)
  }

  /// Remove a previously registered closure from the list of closures that
  /// the object notifies.
  ///
  /// **Dart Source:** `change_notifier.dart:263-302`
  /// **Original:** `void removeListener(VoidCallback listener)`
  ///
  /// DIFFERENCE FROM DART: removes the most recently added unkeyed listener,
  /// not the matching one — see `ListenerList` for why there is no matching
  /// one. Register with `addListener(_:owner:)` when the notifier may have
  /// other listeners.
  public func removeListener(_ listener: @escaping VoidCallback) {
    _listeners.removeLast()
  }

  /// Register a closure under `owner`'s identity; see `Listenable`.
  public func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
    assert(!_debugDisposed, "A \(type(of: self)) was used after being disposed.\nOnce you have called dispose() on a \(type(of: self)), it can no longer be used.")
    _listeners.append(listener, owner: owner)
  }

  /// Remove every listener registered under `owner`.
  public func removeListeners(owner: AnyObject) {
    _listeners.remove(owner: owner)
  }

  /// Discards any resources used by the object. After this is called, the
  /// object is not in a usable state and should be discarded (calls to
  /// `addListener` will throw after the object is disposed).
  ///
  /// This method should only be called by the object's owner.
  ///
  /// **Dart Source:** `change_notifier.dart:316-330`
  /// **Original:** `void dispose()`
  open func dispose() {
    assert({
      _debugDisposed = true
      return true
    }())
    _listeners.removeAll()
  }

  /// Call all the registered listeners.
  ///
  /// Call this method whenever the object changes, to notify any clients the
  /// object may have changed. Listeners that are added during this iteration
  /// will not be visited. Listeners that are removed during this iteration will
  /// not be visited after they are removed.
  ///
  /// **Dart Source:** `change_notifier.dart:343-351`
  /// **Original:** `void notifyListeners()`
  public func notifyListeners() {
    if _listeners.isEmpty {
      return
    }
    // Take a snapshot to avoid issues if listeners modify the list.
    let localListeners = _listeners
    for listener in localListeners {
      listener()
    }
  }
}
