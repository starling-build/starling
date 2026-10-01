// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// AnimationController and related types.
///
/// **Dart Source:** `packages/flutter/lib/src/animation/animation_controller.dart`

import FlutterSwiftBridge
import Foundation

// MARK: - AnimationDirection

/// The direction in which an animation is running.
///
/// **Dart Source:** `animation_controller.dart:32-38`
/// **Original Name:** `_AnimationDirection`
///
/// DIFFERENCE FROM DART: Internal visibility instead of file-private.
/// REASON: Swift does not have file-private enums; internal is the closest equivalent.
enum AnimationDirection {
    /// The animation is running from beginning to end.
    ///
    /// **Dart Source:** `animation_controller.dart:34`
    case forward

    /// The animation is running backwards, from end to beginning.
    ///
    /// **Dart Source:** `animation_controller.dart:37`
    case reverse
}

// MARK: - Fling Constants

/// The spring description used for fling animations.
///
/// **Dart Source:** `animation_controller.dart:40-43`
/// **Original Name:** `_kFlingSpringDescription`
nonisolated(unsafe) let kFlingSpringDescription = SpringDescription(mass: 1.0, stiffness: 500.0, ratio: 1.0)

/// The tolerance used for fling animations.
///
/// **Dart Source:** `animation_controller.dart:45`
/// **Original Name:** `_kFlingTolerance`
nonisolated(unsafe) let kFlingTolerance = Tolerance(distance: 0.01, velocity: .infinity)

// MARK: - AnimationBehavior

/// Configures how an ``AnimationController`` behaves when animations are
/// disabled.
///
/// When `AccessibilityFeatures.disableAnimations` is true, the device is asking
/// Flutter to reduce or disable animations as much as possible. To honor this,
/// we reduce the duration and the corresponding number of frames for
/// animations. This enum is used to allow certain ``AnimationController``s to opt
/// out of this behavior.
///
/// For example, the ``AnimationController`` which controls the physics simulation
/// for a scrollable list will have ``AnimationBehavior/preserve``, so that when
/// a user attempts to scroll it does not jump to the end/beginning too quickly.
///
/// **Dart Source:** `animation_controller.dart:59-70`
public enum AnimationBehavior {
    /// The ``AnimationController`` will reduce its duration when
    /// `AccessibilityFeatures.disableAnimations` is true.
    ///
    /// **Dart Source:** `animation_controller.dart:62`
    case normal

    /// The ``AnimationController`` will preserve its behavior.
    ///
    /// This is the default for repeating animations in order to prevent them from
    /// flashing rapidly on the screen if the widget does not take the
    /// `AccessibilityFeatures.disableAnimations` flag into account.
    ///
    /// **Dart Source:** `animation_controller.dart:69`
    case preserve
}

// MARK: - InterpolationSimulation

/// A simulation that interpolates between two values over a given duration
/// using a curve.
///
/// **Dart Source:** `animation_controller.dart:977-1005`
/// **Original Name:** `_InterpolationSimulation`
///
/// DIFFERENCE FROM DART: Internal visibility instead of file-private.
/// REASON: Swift does not have file-private classes in the same way as Dart.
class InterpolationSimulation: Simulation {
    /// **Dart Source:** `animation_controller.dart:978-980`
    init(_ begin: Double, _ end: Double, _ duration: Duration, _ curve: any Curve, _ scale: Double) {
        let components = duration.components
        let microseconds = components.seconds * 1_000_000 + components.attoseconds / 1_000_000_000_000
        assert(microseconds > 0)
        self._durationInSeconds = (Double(microseconds) * scale) / 1_000_000.0
        self._begin = begin
        self._end = end
        self._curve = curve
        super.init()
    }

    /// **Dart Source:** `animation_controller.dart:982`
    private let _durationInSeconds: Double

    /// **Dart Source:** `animation_controller.dart:983`
    private let _begin: Double

    /// **Dart Source:** `animation_controller.dart:984`
    private let _end: Double

    /// **Dart Source:** `animation_controller.dart:985`
    private let _curve: any Curve

    /// **Dart Source:** `animation_controller.dart:988-995`
    override func x(_ timeInSeconds: Double) -> Double {
        let t = clampDouble(timeInSeconds / _durationInSeconds, 0.0, 1.0)
        switch t {
        case 0.0: return _begin
        case 1.0: return _end
        default: return _begin + (_end - _begin) * _curve.transform(t)
        }
    }

    /// **Dart Source:** `animation_controller.dart:998-1001`
    override func dx(_ timeInSeconds: Double) -> Double {
        let epsilon = tolerance.time
        return (x(timeInSeconds + epsilon) - x(timeInSeconds - epsilon)) / (2 * epsilon)
    }

    /// **Dart Source:** `animation_controller.dart:1004`
    override func isDone(_ timeInSeconds: Double) -> Bool {
        return timeInSeconds > _durationInSeconds
    }
}

// MARK: - DirectionSetter

/// Callback used by ``RepeatingSimulation`` to set the animation direction.
///
/// **Dart Source:** `animation_controller.dart:1007`
/// **Original Name:** `_DirectionSetter`
typealias DirectionSetter = (AnimationDirection) -> Void

// MARK: - RepeatingSimulation

/// A simulation that repeats (and optionally reverses) over a period.
///
/// **Dart Source:** `animation_controller.dart:1009-1065`
/// **Original Name:** `_RepeatingSimulation`
///
/// DIFFERENCE FROM DART: Internal visibility instead of file-private.
/// REASON: Swift does not have file-private classes in the same way as Dart.
class RepeatingSimulation: Simulation {
    /// **Dart Source:** `animation_controller.dart:1010-1026`
    init(
        _ initialValue: Double,
        min: Double,
        max: Double,
        reverse: Bool,
        period: Duration,
        directionSetter: @escaping DirectionSetter,
        count: Int?
    ) {
        assert(count == nil || count! > 0, "Count shall be greater than zero if not null")
        let components = period.components
        let microseconds = components.seconds * 1_000_000 + components.attoseconds / 1_000_000_000_000
        self._periodInSeconds = Double(microseconds) / 1_000_000.0
        self.min = min
        self.max = max
        self.reverse = reverse
        self.count = count
        self.directionSetter = directionSetter
        if max == min {
            self._initialT = 0.0
        } else {
            self._initialT = ((clampDouble(initialValue, min, max) - min) / (max - min)) * self._periodInSeconds
        }
        super.init()
        assert(_periodInSeconds > 0.0)
        assert(_initialT >= 0.0)
    }

    /// **Dart Source:** `animation_controller.dart:1028`
    let min: Double

    /// **Dart Source:** `animation_controller.dart:1029`
    let max: Double

    /// **Dart Source:** `animation_controller.dart:1030`
    let reverse: Bool

    /// **Dart Source:** `animation_controller.dart:1031`
    let count: Int?

    /// **Dart Source:** `animation_controller.dart:1032`
    let directionSetter: DirectionSetter

    /// **Dart Source:** `animation_controller.dart:1034`
    private let _periodInSeconds: Double

    /// **Dart Source:** `animation_controller.dart:1035`
    private let _initialT: Double

    /// **Dart Source:** `animation_controller.dart:1037`
    private lazy var _exitTimeInSeconds: Double = Double(count!) * _periodInSeconds - _initialT

    /// **Dart Source:** `animation_controller.dart:1040-1053`
    override func x(_ timeInSeconds: Double) -> Double {
        assert(timeInSeconds >= 0.0)

        let totalTimeInSeconds = timeInSeconds + _initialT
        let t = (totalTimeInSeconds / _periodInSeconds).truncatingRemainder(dividingBy: 1.0)
        let isPlayingReverse = Int(totalTimeInSeconds / _periodInSeconds) % 2 == 1

        if reverse && isPlayingReverse {
            directionSetter(.reverse)
            return lerpDouble(max, min, t)!
        } else {
            directionSetter(.forward)
            return lerpDouble(min, max, t)!
        }
    }

    /// **Dart Source:** `animation_controller.dart:1057`
    override func dx(_ timeInSeconds: Double) -> Double {
        return (max - min) / _periodInSeconds
    }

    /// **Dart Source:** `animation_controller.dart:1060-1064`
    override func isDone(_ timeInSeconds: Double) -> Bool {
        return count != nil && (timeInSeconds >= _exitTimeInSeconds)
    }
}

// MARK: - SemanticsBinding Stub

/// Stub for SemanticsBinding which is not yet migrated.
///
/// DIFFERENCE FROM DART: Stub providing `disableAnimations` as `false`.
/// REASON: SemanticsBinding depends on the binding infrastructure not yet migrated.
enum SemanticsBinding {
    static let instance = SemanticsBindingInstance()
}

struct SemanticsBindingInstance {
    /// Whether animations should be disabled.
    ///
    /// Always returns `false` in the stub implementation.
    var disableAnimations: Bool { false }
}

// MARK: - Duration Helpers

/// Helper to convert a `Duration` to microseconds as a Double.
///
/// DIFFERENCE FROM DART: Swift's Duration uses components (seconds + attoseconds).
/// REASON: Dart Duration has `inMicroseconds` directly.
private func durationToMicroseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000_000 + components.attoseconds / 1_000_000_000_000
}

/// Helper to multiply a Duration by a Double fraction.
///
/// DIFFERENCE FROM DART: Dart supports `Duration * double` directly.
/// REASON: Swift Duration does not have a `*` operator for Double.
private func durationMultiplied(_ duration: Duration, by factor: Double) -> Duration {
    let microseconds = durationToMicroseconds(duration)
    let resultMicroseconds = Int64(Double(microseconds) * factor)
    return Duration.microseconds(resultMicroseconds)
}

// MARK: - AnimationController

/// A controller for an animation.
///
/// This class lets you perform tasks such as:
///
/// * Play an animation ``forward`` or in ``reverse``, or ``stop`` an animation.
/// * Set the animation to a specific ``value``.
/// * Define the ``upperBound`` and ``lowerBound`` values of an animation.
/// * Create a ``fling`` animation effect using a physics simulation.
///
/// By default, an ``AnimationController`` linearly produces values that range
/// from 0.0 to 1.0, during a given duration. The animation controller generates
/// a new value whenever the device running your app is ready to display a new
/// frame (typically, this rate is around 60 values per second).
///
/// **Dart Source:** `animation_controller.dart:221-975`
///
/// DIFFERENCE FROM DART: Combines behaviors of `AnimationEagerListenerMixin`,
/// `AnimationLocalListenersMixin`, and `AnimationLocalStatusListenersMixin`
/// directly in the class, since Swift does not support multiple inheritance via mixins.
/// REASON: Dart uses `with` for mixin composition; Swift requires single inheritance.
///
/// DIFFERENCE FROM DART: `SemanticsBinding.instance.disableAnimations` is stubbed
/// to always return `false`.
/// REASON: SemanticsBinding is not yet migrated.
public class AnimationController: Animation<Double> {

    /// Creates an animation controller.
    ///
    /// * `value` is the initial value of the animation. It defaults to the lower
    ///   bound.
    ///
    /// * `duration` is the length of time this animation should last.
    ///
    /// * `debugLabel` is a string to help identify this animation during
    ///   debugging (used by `description`).
    ///
    /// * `lowerBound` is the smallest value this animation can obtain and the
    ///   value at which this animation is deemed to be dismissed.
    ///
    /// * `upperBound` is the largest value this animation can obtain and the
    ///   value at which this animation is deemed to be completed.
    ///
    /// * `vsync` is the required `TickerProvider` for the current context.
    ///
    /// **Dart Source:** `animation_controller.dart:245-259`
    public init(
        value: Double? = nil,
        duration: Duration? = nil,
        reverseDuration: Duration? = nil,
        debugLabel: String? = nil,
        lowerBound: Double = 0.0,
        upperBound: Double = 1.0,
        animationBehavior: AnimationBehavior = .normal,
        vsync: TickerProvider
    ) {
        assert(upperBound >= lowerBound)
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.debugLabel = debugLabel
        self.animationBehavior = animationBehavior
        self.duration = duration
        self.reverseDuration = reverseDuration
        self._direction = .forward
        self._value = 0.0 // Placeholder, set properly below
        self._status = .dismissed // Placeholder, set properly below
        super.init()
        _ticker = vsync.createTicker(_tick)
        _internalSetValue(value ?? lowerBound)
    }

    /// Creates an animation controller with no upper or lower bound for its
    /// value.
    ///
    /// * `value` is the initial value of the animation.
    ///
    /// * `duration` is the length of time this animation should last.
    ///
    /// * `debugLabel` is a string to help identify this animation during
    ///   debugging (used by `description`).
    ///
    /// * `vsync` is the required `TickerProvider` for the current context.
    ///
    /// This constructor is most useful for animations that will be driven using a
    /// physics simulation, especially when the physics simulation has no
    /// pre-determined bounds.
    ///
    /// **Dart Source:** `animation_controller.dart:278-291`
    public init(
        unboundedValue value: Double,
        duration: Duration? = nil,
        reverseDuration: Duration? = nil,
        debugLabel: String? = nil,
        vsync: TickerProvider,
        animationBehavior: AnimationBehavior = .preserve
    ) {
        self.lowerBound = -.infinity
        self.upperBound = .infinity
        self.debugLabel = debugLabel
        self.animationBehavior = animationBehavior
        self.duration = duration
        self.reverseDuration = reverseDuration
        self._direction = .forward
        self._value = 0.0 // Placeholder, set properly below
        self._status = .dismissed // Placeholder, set properly below
        super.init()
        _ticker = vsync.createTicker(_tick)
        _internalSetValue(value)
    }

    // MARK: - Properties

    /// The value at which this animation is deemed to be dismissed.
    ///
    /// **Dart Source:** `animation_controller.dart:294`
    public let lowerBound: Double

    /// The value at which this animation is deemed to be completed.
    ///
    /// **Dart Source:** `animation_controller.dart:297`
    public let upperBound: Double

    /// A label that is used in the `description` output. Intended to aid with
    /// identifying animation controller instances in debug output.
    ///
    /// **Dart Source:** `animation_controller.dart:301`
    public let debugLabel: String?

    /// The behavior of the controller when `AccessibilityFeatures.disableAnimations`
    /// is true.
    ///
    /// **Dart Source:** `animation_controller.dart:309`
    public let animationBehavior: AnimationBehavior

    /// Returns an `Animation<Double>` for this animation controller, so that a
    /// pointer to this object can be passed around without allowing users of that
    /// pointer to mutate the `AnimationController` state.
    ///
    /// **Dart Source:** `animation_controller.dart:314`
    public var view: Animation<Double> { self }

    /// The length of time this animation should last.
    ///
    /// If `reverseDuration` is specified, then `duration` is only used when going
    /// forward. Otherwise, it specifies the duration going in both directions.
    ///
    /// **Dart Source:** `animation_controller.dart:320`
    public var duration: Duration?

    /// The length of time this animation should last when going in reverse.
    ///
    /// The value of `duration` is used if `reverseDuration` is not specified or
    /// set to null.
    ///
    /// **Dart Source:** `animation_controller.dart:326`
    public var reverseDuration: Duration?

    /// **Dart Source:** `animation_controller.dart:328`
    private var _ticker: Ticker?

    /// Recreates the `Ticker` with the new `TickerProvider`.
    ///
    /// **Dart Source:** `animation_controller.dart:331-335`
    public func resync(_ vsync: TickerProvider) {
        let oldTicker = _ticker!
        _ticker = vsync.createTicker(_tick)
        _ticker!.absorbTicker(oldTicker)
    }

    /// **Dart Source:** `animation_controller.dart:337`
    private var _simulation: Simulation?

    // MARK: - Value

    /// The current value of the animation.
    ///
    /// Setting this value notifies all the listeners that the value
    /// changed.
    ///
    /// Setting this value also stops the controller if it is currently
    /// running; if this happens, it also notifies all the status
    /// listeners.
    ///
    /// **Dart Source:** `animation_controller.dart:348`
    public override var value: Double {
        get { _value }
        set {
            stop()
            _internalSetValue(newValue)
            notifyListeners()
            _checkStatusChanged()
        }
    }
    private var _value: Double

    /// Sets the controller's value to `lowerBound`, stopping the animation (if
    /// in progress), and resetting to its beginning point, or dismissed state.
    ///
    /// **Dart Source:** `animation_controller.dart:393-395`
    public func reset() {
        value = lowerBound
    }

    /// The rate of change of `value` per second.
    ///
    /// If `isAnimating` is false, then `value` is not changing and the rate of
    /// change is zero.
    ///
    /// **Dart Source:** `animation_controller.dart:401-408`
    public var velocity: Double {
        if !isAnimating {
            return 0.0
        }
        let elapsedMicroseconds = durationToMicroseconds(_lastElapsedDuration!)
        return _simulation!.dx(Double(elapsedMicroseconds) / 1_000_000.0)
    }

    /// **Dart Source:** `animation_controller.dart:410-422`
    private func _internalSetValue(_ newValue: Double) {
        _value = clampDouble(newValue, lowerBound, upperBound)
        if _value == lowerBound {
            _status = .dismissed
        } else if _value == upperBound {
            _status = .completed
        } else {
            switch _direction {
            case .forward: _status = .forward
            case .reverse: _status = .reverse
            }
        }
    }

    /// The amount of time that has passed between the time the animation started
    /// and the most recent tick of the animation.
    ///
    /// If the controller is not animating, the last elapsed duration is nil.
    ///
    /// **Dart Source:** `animation_controller.dart:428-429`
    public var lastElapsedDuration: Duration? { _lastElapsedDuration }
    private var _lastElapsedDuration: Duration?

    /// Whether this animation is currently animating in either the forward or
    /// reverse direction.
    ///
    /// **Dart Source:** `animation_controller.dart:442`
    public override var isAnimating: Bool { _ticker != nil && _ticker!.isActive }

    /// **Dart Source:** `animation_controller.dart:444`
    private var _direction: AnimationDirection

    /// **Dart Source:** `animation_controller.dart:447-448`
    public override var status: AnimationStatus { _status }
    private var _status: AnimationStatus

    // MARK: - Control Methods

    /// Starts running this animation forwards (towards the end).
    ///
    /// Returns a `TickerFuture` that completes when the animation is complete.
    ///
    /// **Dart Source:** `animation_controller.dart:464-485`
    @discardableResult
    public func forward(from: Double? = nil) -> TickerFuture {
        assert(duration != nil,
            "AnimationController.forward() called with no default duration.\n"
            + "The \"duration\" property should be set, either in the constructor or later, before "
            + "calling the forward() function.")
        assert(_ticker != nil,
            "AnimationController.forward() called after AnimationController.dispose()\n"
            + "AnimationController methods should not be used after calling dispose.")
        _direction = .forward
        if let from = from {
            value = from
        }
        return _animateToInternal(upperBound)
    }

    /// Starts running this animation in reverse (towards the beginning).
    ///
    /// Returns a `TickerFuture` that completes when the animation is dismissed.
    ///
    /// **Dart Source:** `animation_controller.dart:501-522`
    @discardableResult
    public func reverse(from: Double? = nil) -> TickerFuture {
        assert(duration != nil || reverseDuration != nil,
            "AnimationController.reverse() called with no default duration or reverseDuration.\n"
            + "The \"duration\" or \"reverseDuration\" property should be set, either in the constructor or later, before "
            + "calling the reverse() function.")
        assert(_ticker != nil,
            "AnimationController.reverse() called after AnimationController.dispose()\n"
            + "AnimationController methods should not be used after calling dispose.")
        _direction = .reverse
        if let from = from {
            value = from
        }
        return _animateToInternal(lowerBound)
    }

    /// Toggles the direction of this animation, based on whether it
    /// `isForwardOrCompleted`.
    ///
    /// **Dart Source:** `animation_controller.dart:536-564`
    @discardableResult
    public func toggle(from: Double? = nil) -> TickerFuture {
        assert({
            var dur = duration
            if isForwardOrCompleted {
                dur = dur ?? reverseDuration
            }
            return dur != nil
        }(),
            "AnimationController.toggle() called with no default duration.\n"
            + "The \"duration\" property should be set, either in the constructor or later, before "
            + "calling the toggle() function.")
        assert(_ticker != nil,
            "AnimationController.toggle() called after AnimationController.dispose()\n"
            + "AnimationController methods should not be used after calling dispose.")
        _direction = isForwardOrCompleted ? .reverse : .forward
        if let from = from {
            value = from
        }
        let target: Double
        switch _direction {
        case .forward: target = upperBound
        case .reverse: target = lowerBound
        }
        return _animateToInternal(target)
    }

    /// Drives the animation from its current value to the given target, "forward".
    ///
    /// Returns a `TickerFuture` that completes when the animation is complete.
    ///
    /// **Dart Source:** `animation_controller.dart:582-601`
    @discardableResult
    public func animateTo(_ target: Double, duration: Duration? = nil, curve: any Curve = Curves.linear) -> TickerFuture {
        assert(self.duration != nil || duration != nil,
            "AnimationController.animateTo() called with no explicit duration and no default duration.\n"
            + "Either the \"duration\" argument to the animateTo() method should be provided, or the "
            + "\"duration\" property should be set, either in the constructor or later, before "
            + "calling the animateTo() function.")
        assert(_ticker != nil,
            "AnimationController.animateTo() called after AnimationController.dispose()\n"
            + "AnimationController methods should not be used after calling dispose.")
        _direction = .forward
        return _animateToInternal(target, duration: duration, curve: curve)
    }

    /// Drives the animation from its current value to the given target, "backward".
    ///
    /// Returns a `TickerFuture` that completes when the animation is complete.
    ///
    /// **Dart Source:** `animation_controller.dart:619-638`
    @discardableResult
    public func animateBack(_ target: Double, duration: Duration? = nil, curve: any Curve = Curves.linear) -> TickerFuture {
        assert(self.duration != nil || reverseDuration != nil || duration != nil,
            "AnimationController.animateBack() called with no explicit duration and no default duration or reverseDuration.\n"
            + "Either the \"duration\" argument to the animateBack() method should be provided, or the "
            + "\"duration\" or \"reverseDuration\" property should be set, either in the constructor or later, before "
            + "calling the animateBack() function.")
        assert(_ticker != nil,
            "AnimationController.animateBack() called after AnimationController.dispose()\n"
            + "AnimationController methods should not be used after calling dispose.")
        _direction = .reverse
        return _animateToInternal(target, duration: duration, curve: curve)
    }

    /// **Dart Source:** `animation_controller.dart:640-690`
    private func _animateToInternal(
        _ target: Double,
        duration: Duration? = nil,
        curve: any Curve = Curves.linear
    ) -> TickerFuture {
        let scale: Double
        switch animationBehavior {
        case .normal where SemanticsBinding.instance.disableAnimations:
            scale = 0.05
        case .normal, .preserve:
            scale = 1.0
        }

        var simulationDuration = duration
        if simulationDuration == nil {
            assert(!(self.duration == nil && _direction == .forward))
            assert(!(self.duration == nil && _direction == .reverse && reverseDuration == nil))
            let range = upperBound - lowerBound
            let remainingFraction = range.isFinite ? Swift.abs(target - _value) / range : 1.0
            let directionDuration: Duration =
                (_direction == .reverse && reverseDuration != nil)
                ? reverseDuration!
                : self.duration!
            simulationDuration = durationMultiplied(directionDuration, by: remainingFraction)
        } else if target == value {
            simulationDuration = .zero
        }

        stop()

        if simulationDuration == .zero {
            if value != target {
                _value = clampDouble(target, lowerBound, upperBound)
                notifyListeners()
            }
            _status = (_direction == .forward)
                ? .completed
                : .dismissed
            _checkStatusChanged()
            return TickerFuture.complete()
        }
        assert(simulationDuration! > .zero)
        assert(!isAnimating)
        return _startSimulation(
            InterpolationSimulation(_value, target, simulationDuration!, curve, scale)
        )
    }

    /// Starts running this animation in the forward direction, and
    /// restarts the animation when it completes.
    ///
    /// **Dart Source:** `animation_controller.dart:717-745`
    @discardableResult
    public func `repeat`(
        min: Double? = nil,
        max: Double? = nil,
        reverse: Bool = false,
        period: Duration? = nil,
        count: Int? = nil
    ) -> TickerFuture {
        let min = min ?? lowerBound
        let max = max ?? upperBound
        let period = period ?? duration
        assert(period != nil,
            "AnimationController.repeat() called without an explicit period and with no default Duration.\n"
            + "Either the \"period\" argument to the repeat() method should be provided, or the "
            + "\"duration\" property should be set, either in the constructor or later, before "
            + "calling the repeat() function.")
        assert(max >= min)
        assert(max <= upperBound && min >= lowerBound)
        assert(count == nil || count! > 0, "Count shall be greater than zero if not null")
        stop()
        return _startSimulation(
            RepeatingSimulation(
                _value,
                min: min,
                max: max,
                reverse: reverse,
                period: period!,
                directionSetter: _directionSetter,
                count: count
            )
        )
    }

    /// **Dart Source:** `animation_controller.dart:747-753`
    private func _directionSetter(_ direction: AnimationDirection) {
        _direction = direction
        _status = (_direction == .forward)
            ? .forward
            : .reverse
        _checkStatusChanged()
    }

    /// Drives the animation with a spring (within `lowerBound` and `upperBound`)
    /// and initial velocity.
    ///
    /// If velocity is positive, the animation will complete, otherwise it will
    /// dismiss.
    ///
    /// **Dart Source:** `animation_controller.dart:777-808`
    @discardableResult
    public func fling(
        velocity: Double = 1.0,
        springDescription: SpringDescription? = nil,
        animationBehavior: AnimationBehavior? = nil
    ) -> TickerFuture {
        let springDesc = springDescription ?? kFlingSpringDescription
        _direction = velocity < 0.0 ? .reverse : .forward
        let target = velocity < 0.0
            ? lowerBound - kFlingTolerance.distance
            : upperBound + kFlingTolerance.distance
        let behavior = animationBehavior ?? self.animationBehavior
        let scale: Double
        switch behavior {
        case .normal where SemanticsBinding.instance.disableAnimations:
            scale = 200.0
        case .normal, .preserve:
            scale = 1.0
        }
        let simulation = SpringSimulation(
            springDesc,
            value,
            target,
            velocity * scale
        )
        simulation.tolerance = kFlingTolerance
        assert(simulation.type != .underDamped,
            "The specified spring simulation is of type SpringType.underDamped.\n"
            + "An underdamped spring results in oscillation rather than a fling. "
            + "Consider specifying a different springDescription, or use animateWith() "
            + "with an explicit SpringSimulation if an underdamped spring is intentional.")
        stop()
        return _startSimulation(simulation)
    }

    /// Drives the animation according to the given simulation.
    ///
    /// The `status` is always `AnimationStatus.forward` for the entire duration
    /// of the simulation.
    ///
    /// **Dart Source:** `animation_controller.dart:831-840`
    @discardableResult
    public func animateWith(_ simulation: Simulation) -> TickerFuture {
        assert(_ticker != nil,
            "AnimationController.animateWith() called after AnimationController.dispose()\n"
            + "AnimationController methods should not be used after calling dispose.")
        stop()
        _direction = .forward
        return _startSimulation(simulation)
    }

    /// Drives the animation according to the given simulation with a `status` of
    /// `AnimationStatus.reverse`.
    ///
    /// **Dart Source:** `animation_controller.dart:854-863`
    @discardableResult
    public func animateBackWith(_ simulation: Simulation) -> TickerFuture {
        assert(_ticker != nil,
            "AnimationController.animateBackWith() called after AnimationController.dispose()\n"
            + "AnimationController methods should not be used after calling dispose.")
        stop()
        _direction = .reverse
        return _startSimulation(simulation)
    }

    /// **Dart Source:** `animation_controller.dart:865-876`
    private func _startSimulation(_ simulation: Simulation) -> TickerFuture {
        assert(!isAnimating)
        _simulation = simulation
        _lastElapsedDuration = .zero
        _value = clampDouble(simulation.x(0.0), lowerBound, upperBound)
        let result = _ticker!.start()
        _status = (_direction == .forward)
            ? .forward
            : .reverse
        _checkStatusChanged()
        return result
    }

    /// Stops running this animation.
    ///
    /// This does not trigger any notifications. The animation stops in its
    /// current state.
    ///
    /// **Dart Source:** `animation_controller.dart:895-904`
    public func stop(canceled: Bool = true) {
        assert(_ticker != nil,
            "AnimationController.stop() called after AnimationController.dispose()\n"
            + "AnimationController methods should not be used after calling dispose.")
        _simulation = nil
        _lastElapsedDuration = nil
        _ticker!.stop(canceled: canceled)
    }

    /// Release the resources used by this object. The object is no longer usable
    /// after this method is called.
    ///
    /// **Dart Source:** `animation_controller.dart:913-934`
    public func dispose() {
        assert(_ticker != nil,
            "AnimationController.dispose() called more than once.\n"
            + "A given AnimationController cannot be disposed more than once.")
        _ticker!.dispose()
        _ticker = nil
        clearStatusListeners()
        clearListeners()
    }

    // MARK: - Status Change Tracking

    /// **Dart Source:** `animation_controller.dart:936`
    private var _lastReportedStatus: AnimationStatus = .dismissed

    /// **Dart Source:** `animation_controller.dart:937-943`
    private func _checkStatusChanged() {
        let newStatus = status
        if _lastReportedStatus != newStatus {
            _lastReportedStatus = newStatus
            notifyStatusListeners(newStatus)
        }
    }

    // MARK: - Tick Handler

    /// **Dart Source:** `animation_controller.dart:945-958`
    private func _tick(_ elapsed: Duration) {
        _lastElapsedDuration = elapsed
        let elapsedMicroseconds = durationToMicroseconds(elapsed)
        let elapsedInSeconds = Double(elapsedMicroseconds) / 1_000_000.0
        assert(elapsedInSeconds >= 0.0)
        let simX = _simulation!.x(elapsedInSeconds)
        _value = clampDouble(simX, lowerBound, upperBound)
        if _simulation!.isDone(elapsedInSeconds) {
            _status = (_direction == .forward)
                ? .completed
                : .dismissed
            stop(canceled: false)
        }
        notifyListeners()
        _checkStatusChanged()
    }

    // MARK: - String Representation

    /// **Dart Source:** `animation_controller.dart:962-974`
    public override func toStringDetails() -> String {
        let paused = isAnimating ? "" : "; paused"
        let ticker: String
        if _ticker == nil {
            ticker = "; DISPOSED"
        } else if _ticker!.muted {
            ticker = "; silenced"
        } else {
            ticker = ""
        }
        var label = ""
        if let debugLabel = debugLabel {
            label = "; for \(debugLabel)"
        }
        let more = "\(super.toStringDetails()) \(String(format: "%.3f", _value))"
        return "\(more)\(paused)\(ticker)\(label)"
    }

    // MARK: - Listener Management (Mixin Composition)

    // DIFFERENCE FROM DART: In Dart, AnimationController uses three mixins:
    // AnimationEagerListenerMixin, AnimationLocalListenersMixin, and
    // AnimationLocalStatusListenersMixin. In Swift, we embed this behavior
    // directly since Swift only supports single inheritance.
    // REASON: Swift does not have Dart-style mixins.

    // AnimationEagerListenerMixin behavior (no-op register/unregister)
    private func didRegisterListener() {}
    private func didUnregisterListener() {}

    // AnimationLocalListenersMixin behavior
    private var _listeners = ListenerList()

    /// Calls the listener every time the value of the animation changes.
    ///
    /// **Dart Source:** (via `AnimationLocalListenersMixin`) `listener_helpers.dart:112-115`
    public override func addListener(_ listener: @escaping VoidCallback) {
        didRegisterListener()
        _listeners.append(listener)
    }

    /// Stop calling the listener every time the value of the animation changes.
    ///
    /// **Dart Source:** (via `AnimationLocalListenersMixin`) `listener_helpers.dart:120-125`
    public override func removeListener(_ listener: @escaping VoidCallback) {
        if _listeners.removeLast() {
            didUnregisterListener()
        }
    }

    public override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        didRegisterListener()
        _listeners.append(listener, owner: owner)
    }

    public override func removeListeners(owner: AnyObject) {
        for _ in 0..<_listeners.remove(owner: owner) {
            didUnregisterListener()
        }
    }

    /// Removes all listeners added with `addListener`.
    ///
    /// **Dart Source:** (via `AnimationLocalListenersMixin`) `listener_helpers.dart:134-136`
    public func clearListeners() {
        _listeners.removeAll()
    }

    /// Calls all the listeners.
    ///
    /// **Dart Source:** (via `AnimationLocalListenersMixin`) `listener_helpers.dart:144-174`
    public func notifyListeners() {
        let localListeners = _listeners
        for listener in localListeners {
            listener()
        }
    }

    // AnimationLocalStatusListenersMixin behavior
    private var _statusListeners: [AnimationStatusListener] = []

    /// Calls listener every time the status of the animation changes.
    ///
    /// **Dart Source:** (via `AnimationLocalStatusListenersMixin`) `listener_helpers.dart:205-208`
    public override func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        didRegisterListener()
        _statusListeners.append(listener)
    }

    /// Stops calling the listener every time the status of the animation changes.
    ///
    /// **Dart Source:** (via `AnimationLocalStatusListenersMixin`) `listener_helpers.dart:213-218`
    public override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        if !_statusListeners.isEmpty {
            _statusListeners.removeLast()
            didUnregisterListener()
        }
    }

    /// Removes all status listeners added with `addStatusListener`.
    ///
    /// **Dart Source:** (via `AnimationLocalStatusListenersMixin`) `listener_helpers.dart:227-229`
    public func clearStatusListeners() {
        _statusListeners.removeAll()
    }

    /// Calls all the status listeners.
    ///
    /// **Dart Source:** (via `AnimationLocalStatusListenersMixin`) `listener_helpers.dart:237-267`
    public func notifyStatusListeners(_ status: AnimationStatus) {
        let localListeners = _statusListeners
        for listener in localListeners {
            listener(status)
        }
    }
}
