// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridge

/// An object that can produce a value of type `T` given an `Animation<Double>`
/// as input.
///
/// Typically, the values of the input animation are nominally in the range 0.0
/// to 1.0. In principle, however, any value could be provided.
///
/// The main subclass of `Animatable` is `Tween`.
///
/// **Dart Source:** `packages/flutter/lib/src/animation/tween.dart:34-100`
open class Animatable<T> {
    public init() {}

    /// Returns the value of the object at point `t`.
    ///
    /// The value of `t` is nominally a fraction in the range 0.0 to 1.0, though
    /// in practice it may extend outside this range.
    ///
    /// **Dart Source:** `tween.dart:57`
    open func transform(_ t: Double) -> T {
        fatalError("Subclass must override transform")
    }

    /// The current value of this object for the given animation.
    ///
    /// This function is implemented by deferring to `transform`. Subclasses that
    /// want to provide custom behavior should override `transform`, not
    /// `evaluate`.
    ///
    /// **Dart Source:** `tween.dart:71`
    open func evaluate(_ animation: Animation<Double>) -> T {
        return transform(animation.value)
    }

    /// Returns a new `Animation` that is driven by the given animation but that
    /// takes on values determined by this object.
    ///
    /// **Dart Source:** `tween.dart:83-85`
    public func animate(_ parent: Animation<Double>) -> Animation<T> {
        return AnimatedEvaluation<T>(parent, self)
    }

    /// Returns a new `Animatable` whose value is determined by first evaluating
    /// the given parent and then evaluating this object at the result.
    ///
    /// This allows `Tween`s to be chained before obtaining an `Animation`,
    /// without allocating an `Animation` for the intermediate result.
    ///
    /// **Dart Source:** `tween.dart:97-99`
    public func chain(_ parent: Animatable<Double>) -> Animatable<T> {
        return ChainedEvaluation<T>(parent, self)
    }

    /// Create a new `Animatable` from the provided callback.
    ///
    /// **Dart Source:** `tween.dart:45`
    public static func fromCallback(_ callback: @escaping AnimatableCallback<T>) -> Animatable<T> {
        return CallbackAnimatable<T>(callback)
    }
}

// MARK: - AnimatableCallback

/// A typedef used by `Animatable.fromCallback` to create an `Animatable`
/// from a callback.
///
/// **Dart Source:** `tween.dart:25`
public typealias AnimatableCallback<T> = (Double) -> T

// MARK: - CallbackAnimatable

/// A concrete subclass of `Animatable` used by `Animatable.fromCallback`.
///
/// **Dart Source:** `tween.dart:103-112`
/// **Original Name:** `_CallbackAnimatable`
class CallbackAnimatable<T>: Animatable<T> {
    init(_ callback: @escaping AnimatableCallback<T>) {
        self._callback = callback
    }

    private let _callback: AnimatableCallback<T>

    /// **Dart Source:** `tween.dart:109-111`
    override func transform(_ t: Double) -> T {
        return _callback(t)
    }
}

// MARK: - ChainedEvaluation

/// An `Animatable` that chains two animatables together.
///
/// First evaluates `_parent` to get a Double, then evaluates `_evaluatable`
/// at that Double value.
///
/// **Dart Source:** `tween.dart:136-151`
/// **Original Name:** `_ChainedEvaluation`
class ChainedEvaluation<T>: Animatable<T> {
    init(_ parent: Animatable<Double>, _ evaluatable: Animatable<T>) {
        self._parent = parent
        self._evaluatable = evaluatable
    }

    private let _parent: Animatable<Double>
    private let _evaluatable: Animatable<T>

    /// **Dart Source:** `tween.dart:143-145`
    override func transform(_ t: Double) -> T {
        return _evaluatable.transform(_parent.transform(t))
    }
}

// MARK: - AnimatedEvaluation

/// An animation that is driven by a parent `Animation<Double>` and an
/// `Animatable<T>` that maps values.
///
/// **Dart Source:** `tween.dart:114-134`
/// **Original Name:** `_AnimatedEvaluation`
///
/// DIFFERENCE FROM DART: Internal visibility instead of file-private.
/// REASON: Swift does not have file-private classes that span multiple files.
class AnimatedEvaluation<T>: Animation<T> {
    init(_ parent: Animation<Double>, _ evaluatable: Animatable<T>) {
        self._parent = parent
        self._evaluatable = evaluatable
    }

    private let _parent: Animation<Double>
    private let _evaluatable: Animatable<T>

    /// **Dart Source:** `tween.dart:123`
    override var value: T { _evaluatable.evaluate(_parent) }

    /// **Dart Source:** `tween.dart:118`
    override var status: AnimationStatus { _parent.status }

    override func addListener(_ listener: @escaping VoidCallback) {
        _parent.addListener(listener)
    }

    override func removeListener(_ listener: @escaping VoidCallback) {
        _parent.removeListener(listener)
    }

    override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _parent.addListener(listener, owner: owner)
    }

    override func removeListeners(owner: AnyObject) {
        _parent.removeListeners(owner: owner)
    }

    override func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        _parent.addStatusListener(listener)
    }

    override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        _parent.removeStatusListener(listener)
    }

    /// **Dart Source:** `tween.dart:126-128`
    override var description: String {
        return "\(_parent)\u{27A9}\(_evaluatable)\u{27A9}\(value)"
    }

    /// **Dart Source:** `tween.dart:131-133`
    override func toStringDetails() -> String {
        return "\(super.toStringDetails()) \(_evaluatable)"
    }
}
