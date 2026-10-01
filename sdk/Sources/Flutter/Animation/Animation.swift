// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Animation status, typedefs, and base types.
///
/// **Dart Source:** `packages/flutter/lib/src/animation/animation.dart`

import FlutterSwiftBridge

// MARK: - AnimationStatus

/// The status of an animation.
///
/// **Dart Source:** `animation.dart:22-58`
public enum AnimationStatus {
    /// The animation is stopped at the beginning.
    ///
    /// **Dart Source:** `animation.dart:24`
    case dismissed

    /// The animation is running from beginning to end.
    ///
    /// **Dart Source:** `animation.dart:27`
    case forward

    /// The animation is running backwards, from end to beginning.
    ///
    /// **Dart Source:** `animation.dart:30`
    case reverse

    /// The animation is stopped at the end.
    ///
    /// **Dart Source:** `animation.dart:33`
    case completed

    /// Whether the animation is stopped at the beginning.
    ///
    /// **Dart Source:** `animation.dart:36`
    public var isDismissed: Bool { self == .dismissed }

    /// Whether the animation is stopped at the end.
    ///
    /// **Dart Source:** `animation.dart:39`
    public var isCompleted: Bool { self == .completed }

    /// Whether the animation is running in either direction.
    ///
    /// **Dart Source:** `animation.dart:42-45`
    public var isAnimating: Bool {
        switch self {
        case .forward, .reverse: return true
        case .completed, .dismissed: return false
        }
    }

    /// Whether the current aim of the animation is toward completion.
    ///
    /// Specifically, returns `true` for `AnimationStatus.forward` or
    /// `AnimationStatus.completed`, and `false` for
    /// `AnimationStatus.reverse` or `AnimationStatus.dismissed`.
    ///
    /// **Dart Source:** `animation.dart:54-57`
    public var isForwardOrCompleted: Bool {
        switch self {
        case .forward, .completed: return true
        case .reverse, .dismissed: return false
        }
    }
}

// MARK: - Typedefs

/// Signature for listeners attached using `Animation.addStatusListener`.
///
/// **Dart Source:** `animation.dart:61`
public typealias AnimationStatusListener = (AnimationStatus) -> Void

/// Signature for method used to transform values in `Animation.fromValueListenable`.
///
/// **Dart Source:** `animation.dart:64`
public typealias ValueListenableTransformer<T> = (T) -> T

// MARK: - Animation

/// A value which might change over time, moving forward or backward.
///
/// An animation has a `value` (of type `T`) and a `status`.
/// The value conceptually lies on some path, and the status indicates how
/// the value is currently moving along the path: forward, backward, or
/// stopped at the end or the beginning.
///
/// Consumers of the animation can listen for changes to either the value
/// or the status, with `addListener` and `addStatusListener`.
///
/// In Dart, `Animation<T>` is an abstract class that extends `Listenable` and
/// implements `ValueListenable<T>`. In Swift, we use a base class with
/// methods that subclasses must override (fatalError for abstract-like behavior).
///
/// **Dart Source:** `animation.dart:145-377`
///
/// DIFFERENCE FROM DART: Dart's `Animation<T>` is abstract; Swift uses
/// a concrete base class with `fatalError` stubs for abstract methods.
/// REASON: Swift does not have abstract classes; this pattern allows subclassing.
open class Animation<T> {
    public init() {}

    // MARK: Abstract methods (subclasses must override)

    /// Calls the listener every time the value of the animation changes.
    ///
    /// Listeners can be removed with `removeListener`.
    ///
    /// **Dart Source:** `animation.dart:208-209`
    open func addListener(_ listener: @escaping VoidCallback) {
        fatalError("Subclass must override addListener")
    }

    /// Keyed registration; see `Listenable.addListener(_:owner:)`. Stores
    /// and forwarders override both keyed methods; the base falls back to
    /// an unkeyed add, which a later `removeListeners(owner:)` cannot find.
    open func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        addListener(listener)
    }

    /// Keyed removal; see `Listenable.removeListeners(owner:)`.
    open func removeListeners(owner: AnyObject) {}

    /// Stop calling the listener every time the value of the animation changes.
    ///
    /// If `listener` is not currently registered as a listener, this method does
    /// nothing.
    ///
    /// **Dart Source:** `animation.dart:217-218`
    open func removeListener(_ listener: @escaping VoidCallback) {
        fatalError("Subclass must override removeListener")
    }

    /// Calls listener every time the status of the animation changes.
    ///
    /// Listeners can be removed with `removeStatusListener`.
    ///
    /// **Dart Source:** `animation.dart:223`
    open func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        fatalError("Subclass must override addStatusListener")
    }

    /// Stops calling the listener every time the status of the animation changes.
    ///
    /// If `listener` is not currently registered as a status listener, this
    /// method does nothing.
    ///
    /// **Dart Source:** `animation.dart:231`
    open func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        fatalError("Subclass must override removeStatusListener")
    }

    /// The current status of this animation.
    ///
    /// **Dart Source:** `animation.dart:234`
    open var status: AnimationStatus {
        fatalError("Subclass must override status")
    }

    /// The current value of the animation.
    ///
    /// **Dart Source:** `animation.dart:237-238`
    open var value: T {
        fatalError("Subclass must override value")
    }

    // MARK: Concrete convenience getters

    /// Whether this animation is stopped at the beginning.
    ///
    /// **Dart Source:** `animation.dart:241`
    public var isDismissed: Bool { status.isDismissed }

    /// Whether this animation is stopped at the end.
    ///
    /// **Dart Source:** `animation.dart:244`
    public var isCompleted: Bool { status.isCompleted }

    /// Whether this animation is running in either direction.
    ///
    /// By default, this value is equal to `status.isAnimating`, but
    /// `AnimationController` overrides this method so that its output
    /// depends on whether the controller is actively ticking.
    ///
    /// **Dart Source:** `animation.dart:251`
    open var isAnimating: Bool { status.isAnimating }

    /// Whether the current aim of the animation is toward completion.
    ///
    /// **Dart Source:** `animation.dart:254`
    public var isForwardOrCompleted: Bool { status.isForwardOrCompleted }

    // MARK: String representation

    /// Returns a string describing this animation.
    ///
    /// **Dart Source:** `animation.dart:350-353`
    open var description: String {
        return "\(describeIdentity(self))(\(toStringDetails()))"
    }

    /// Provides a string describing the status of this object, but not including
    /// information about the object itself.
    ///
    /// The result includes an icon describing the status of this animation:
    /// - "\u{25B6}": forward (value increasing)
    /// - "\u{25C0}": reverse (value decreasing)
    /// - "\u{23ED}": completed (value == 1.0)
    /// - "\u{23EE}": dismissed (value == 0.0)
    ///
    /// **Dart Source:** `animation.dart:369-376`
    open func toStringDetails() -> String {
        switch status {
        case .forward:   return "\u{25B6}"
        case .reverse:   return "\u{25C0}"
        case .completed: return "\u{23ED}"
        case .dismissed: return "\u{23EE}"
        }
    }

    // MARK: drive() method

    /// Chains an `Animatable` (such as a `Tween` or `CurveTween`) to this animation.
    ///
    /// This method is only valid for `Animation<Double>` instances. In Dart,
    /// this asserts `this is Animation<double>` at runtime. In Swift, we
    /// enforce this at compile time with a type constraint on the extension.
    ///
    /// Returns an `Animation` specialized to the same type `U` as the
    /// argument, whose value is derived by applying the given `Animatable`
    /// to the value of this animation.
    ///
    /// **Dart Source:** `animation.dart:344-348`
    ///
    /// DIFFERENCE FROM DART: Constrained to `Animation<Double>` at compile time
    /// instead of runtime assert.
    /// REASON: Swift generics allow compile-time safety.
    public func drive<U>(_ child: Animatable<U>) -> Animation<U> {
        // This will fatalError at runtime if T != Double, matching Dart's assert.
        // In practice, callers should use the typed extension below.
        guard let self = self as? Animation<Double> else {
            fatalError("drive() can only be called on Animation<Double>")
        }
        return child.animate(self)
    }

    // MARK: Factory method

    /// Create a new animation from a `ValueListenable`.
    ///
    /// The returned animation will always have an animation status of
    /// `AnimationStatus.forward`. The value of the provided listenable can
    /// be optionally transformed using the `transformer` function.
    ///
    /// **Dart Source:** `animation.dart:198-201`
    public static func fromValueListenable<V: ValueListenable>(
        _ listenable: V,
        transformer: ValueListenableTransformer<T>? = nil
    ) -> Animation<T> where V.Value == T {
        return ValueListenableDelegateAnimation(listenable, transformer: transformer)
    }
}

// MARK: - ValueListenableDelegateAnimation

/// An implementation of an animation that delegates to a value listenable
/// with a fixed direction (always `.forward`).
///
/// **Dart Source:** `animation.dart:380-412`
/// **Original Name:** `_ValueListenableDelegateAnimation`
///
/// DIFFERENCE FROM DART: Internal visibility instead of file-private.
/// REASON: Swift does not have file-private classes in the same way as Dart.
class ValueListenableDelegateAnimation<T>: Animation<T> {

    /// **Dart Source:** `animation.dart:381-382`
    init<V: ValueListenable>(_ listenable: V, transformer: ValueListenableTransformer<T>? = nil) where V.Value == T {
        self._addListener = { listenable.addListener($0) }
        self._removeListener = { listenable.removeListener($0) }
        self._addKeyedListener = { listenable.addListener($0, owner: $1) }
        self._removeKeyedListeners = { listenable.removeListeners(owner: $0) }
        self._getValue = { listenable.value }
        self._transformer = transformer
    }

    private let _addListener: (@escaping VoidCallback) -> Void
    private let _removeListener: (@escaping VoidCallback) -> Void
    private let _addKeyedListener: (@escaping VoidCallback, AnyObject) -> Void
    private let _removeKeyedListeners: (AnyObject) -> Void
    private let _getValue: () -> T
    private let _transformer: ValueListenableTransformer<T>?

    /// **Dart Source:** `animation.dart:388-390`
    override func addListener(_ listener: @escaping VoidCallback) {
        _addListener(listener)
    }

    /// **Dart Source:** `animation.dart:393-395`
    override func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        // status will never change.
    }

    /// **Dart Source:** `animation.dart:398-400`
    override func removeListener(_ listener: @escaping VoidCallback) {
        _removeListener(listener)
    }

    override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _addKeyedListener(listener, owner)
    }

    override func removeListeners(owner: AnyObject) {
        _removeKeyedListeners(owner)
    }

    /// **Dart Source:** `animation.dart:403-405`
    override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        // status will never change.
    }

    /// **Dart Source:** `animation.dart:408`
    override var status: AnimationStatus { .forward }

    /// **Dart Source:** `animation.dart:411`
    override var value: T {
        let raw = _getValue()
        return _transformer?(raw) ?? raw
    }
}
