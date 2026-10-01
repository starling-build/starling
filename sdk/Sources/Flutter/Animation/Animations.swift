// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Constant and proxy animation types.
///
/// **Dart Source:** `packages/flutter/lib/src/animation/animations.dart`

import FlutterSwiftBridge

// MARK: - _AlwaysCompleteAnimation

/// An animation that is always complete.
///
/// This is a private implementation class for ``kAlwaysCompleteAnimation``.
///
/// **Dart Source:** `animations.dart:24-47`
/// **Original Name:** `_AlwaysCompleteAnimation`
class AlwaysCompleteAnimation: Animation<Double> {

    override func addListener(_ listener: @escaping VoidCallback) {}

    override func removeListener(_ listener: @escaping VoidCallback) {}

    override func addStatusListener(_ listener: @escaping AnimationStatusListener) {}

    override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {}

    /// **Dart Source:** `animations.dart:40`
    override var status: AnimationStatus { .completed }

    /// **Dart Source:** `animations.dart:43`
    override var value: Double { 1.0 }

    /// **Dart Source:** `animations.dart:46`
    override var description: String { "kAlwaysCompleteAnimation" }
}

/// An animation that is always complete.
///
/// Using this constant involves less overhead than building an
/// `AnimationController` with an initial value of 1.0. This is useful when an
/// API expects an animation but you don't actually want to animate anything.
///
/// **Dart Source:** `animations.dart:54`
nonisolated(unsafe) public let kAlwaysCompleteAnimation: Animation<Double> = AlwaysCompleteAnimation()

// MARK: - _AlwaysDismissedAnimation

/// An animation that is always dismissed.
///
/// This is a private implementation class for ``kAlwaysDismissedAnimation``.
///
/// **Dart Source:** `animations.dart:56-79`
/// **Original Name:** `_AlwaysDismissedAnimation`
class AlwaysDismissedAnimation: Animation<Double> {

    override func addListener(_ listener: @escaping VoidCallback) {}

    override func removeListener(_ listener: @escaping VoidCallback) {}

    override func addStatusListener(_ listener: @escaping AnimationStatusListener) {}

    override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {}

    /// **Dart Source:** `animations.dart:72`
    override var status: AnimationStatus { .dismissed }

    /// **Dart Source:** `animations.dart:75`
    override var value: Double { 0.0 }

    /// **Dart Source:** `animations.dart:78`
    override var description: String { "kAlwaysDismissedAnimation" }
}

/// An animation that is always dismissed.
///
/// Using this constant involves less overhead than building an
/// `AnimationController` with an initial value of 0.0. This is useful when an
/// API expects an animation but you don't actually want to animate anything.
///
/// **Dart Source:** `animations.dart:86`
nonisolated(unsafe) public let kAlwaysDismissedAnimation: Animation<Double> = AlwaysDismissedAnimation()

// MARK: - AlwaysStoppedAnimation

/// An animation that is always stopped at a given value.
///
/// The ``status`` is always ``AnimationStatus/forward``.
///
/// Since the ``value`` and ``status`` of an `AlwaysStoppedAnimation` can never
/// change, the listeners can never be called. It is therefore safe to reuse
/// an `AlwaysStoppedAnimation` instance in multiple places.
///
/// **Dart Source:** `animations.dart:88-123`
/// **Original Name:** `AlwaysStoppedAnimation<T>`
public class AlwaysStoppedAnimation<T>: Animation<T> {
    /// Creates an `AlwaysStoppedAnimation` with the given value.
    ///
    /// **Dart Source:** `animations.dart:99`
    public init(_ value: T) {
        self._value = value
    }

    private let _value: T

    /// **Dart Source:** `animations.dart:102`
    public override var value: T { _value }

    /// **Dart Source:** `animations.dart:105`
    public override func addListener(_ listener: @escaping VoidCallback) {}

    /// **Dart Source:** `animations.dart:108`
    public override func removeListener(_ listener: @escaping VoidCallback) {}

    /// **Dart Source:** `animations.dart:111`
    public override func addStatusListener(_ listener: @escaping AnimationStatusListener) {}

    /// **Dart Source:** `animations.dart:114`
    public override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {}

    /// **Dart Source:** `animations.dart:117`
    public override var status: AnimationStatus { .forward }

    /// **Dart Source:** `animations.dart:120-122`
    public override func toStringDetails() -> String {
        return "\(super.toStringDetails()) \(_value); paused"
    }
}

// MARK: - AnimationWithParentMixin

/// Implements most of the `Animation` interface by deferring its behavior to a
/// given ``parent`` animation.
///
/// To implement an `Animation` that is driven by a parent, it is only necessary
/// to conform to this protocol, implement ``parent``, and implement `value`.
///
/// In Dart, this is a mixin. In Swift, we use a protocol with default
/// implementations in an extension.
///
/// **Dart Source:** `animations.dart:125-166`
/// **Original Name:** `AnimationWithParentMixin<T>`
///
/// DIFFERENCE FROM DART: Protocol instead of mixin.
/// REASON: Swift does not have mixins; protocols with extensions provide
/// equivalent behavior for forwarding methods.
public protocol AnimationWithParentMixin: AnyObject {
    associatedtype ParentValue

    /// The animation whose value this animation will proxy.
    ///
    /// This animation must remain the same for the lifetime of this object. If
    /// you wish to proxy a different animation at different times, consider using
    /// `ProxyAnimation`.
    ///
    /// **Dart Source:** `animations.dart:139`
    var parent: Animation<ParentValue> { get }

    /// Calls the listener every time the value of the animation changes.
    ///
    /// **Dart Source:** `animations.dart:146`
    func addListener(_ listener: @escaping VoidCallback)

    /// Stop calling the listener every time the value of the animation changes.
    ///
    /// **Dart Source:** `animations.dart:151`
    func removeListener(_ listener: @escaping VoidCallback)

    /// Calls listener every time the status of the animation changes.
    ///
    /// **Dart Source:** `animations.dart:156`
    func addStatusListener(_ listener: @escaping AnimationStatusListener)

    /// Stops calling the listener every time the status of the animation changes.
    ///
    /// **Dart Source:** `animations.dart:161-162`
    func removeStatusListener(_ listener: @escaping AnimationStatusListener)

    /// The current status of this animation.
    ///
    /// **Dart Source:** `animations.dart:165`
    var status: AnimationStatus { get }
}

extension AnimationWithParentMixin {
    /// **Dart Source:** `animations.dart:146`
    public func addListener(_ listener: @escaping VoidCallback) {
        parent.addListener(listener)
    }

    /// **Dart Source:** `animations.dart:151`
    public func removeListener(_ listener: @escaping VoidCallback) {
        parent.removeListener(listener)
    }

    /// **Dart Source:** `animations.dart:156`
    public func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        parent.addStatusListener(listener)
    }

    /// **Dart Source:** `animations.dart:161-162`
    public func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        parent.removeStatusListener(listener)
    }

    /// **Dart Source:** `animations.dart:165`
    public var status: AnimationStatus {
        parent.status
    }
}

// MARK: - ProxyAnimation

/// An animation that is a proxy for another animation.
///
/// A proxy animation is useful because the parent animation can be mutated. For
/// example, one object can create a proxy animation, hand the proxy to another
/// object, and then later change the animation from which the proxy receives
/// its value.
///
/// **Dart Source:** `animations.dart:174-256`
///
/// DIFFERENCE FROM DART: Dart uses multiple mixins (AnimationLazyListenerMixin,
/// AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin). Swift
/// embeds the listener management directly since it cannot use multiple inheritance.
/// REASON: Swift does not have mixins.
public class ProxyAnimation: Animation<Double> {
    /// Creates a proxy animation.
    ///
    /// If the animation argument is omitted, the proxy animation will have the
    /// status ``AnimationStatus/dismissed`` and a value of 0.0.
    ///
    /// **Dart Source:** `animations.dart:183-189`
    public init(_ animation: Animation<Double>? = nil) {
        _parent = animation
        if _parent == nil {
            _status = .dismissed
            _value = 0.0
        }
    }

    private var _status: AnimationStatus?
    private var _value: Double?

    // Embedded lazy listener state (from AnimationLazyListenerMixin)
    private var _listenerCounter: Int = 0

    // Embedded local listeners (from AnimationLocalListenersMixin)
    private var _listeners = ListenerList()

    // Embedded local status listeners (from AnimationLocalStatusListenersMixin)
    private var _statusListeners: [AnimationStatusListener] = []

    /// Whether there are any listeners.
    ///
    /// **Dart Source:** `listener_helpers.dart:62`
    public var isListening: Bool { _listenerCounter > 0 }

    private func _didRegisterListener() {
        assert(_listenerCounter >= 0)
        if _listenerCounter == 0 {
            didStartListening()
        }
        _listenerCounter += 1
    }

    private func _didUnregisterListener() {
        assert(_listenerCounter >= 1)
        _listenerCounter -= 1
        if _listenerCounter == 0 {
            didStopListening()
        }
    }

    /// Calls all the registered value listeners.
    public func notifyListeners() {
        let localListeners = _listeners
        for listener in localListeners {
            listener()
        }
    }

    /// Calls all the registered status listeners.
    public func notifyStatusListeners(_ status: AnimationStatus) {
        let localListeners = _statusListeners
        for listener in localListeners {
            listener(status)
        }
    }

    /// The animation whose value this animation will proxy.
    ///
    /// This value is mutable. When mutated, the listeners on the proxy animation
    /// will be transparently updated to be listening to the new parent animation.
    ///
    /// **Dart Source:** `animations.dart:198`
    public var parent: Animation<Double>? {
        get { _parent }
        set {
            if newValue === _parent {
                return
            }
            if _parent != nil {
                _status = _parent!.status
                _value = _parent!.value
                if isListening {
                    didStopListening()
                }
            }
            _parent = newValue
            if _parent != nil {
                if isListening {
                    didStartListening()
                }
                if _value != _parent!.value {
                    notifyListeners()
                }
                if _status != _parent!.status {
                    notifyStatusListeners(_parent!.status)
                }
                _status = nil
                _value = nil
            }
        }
    }
    private var _parent: Animation<Double>?

    /// **Dart Source:** `animations.dart:228-233`
    func didStartListening() {
        if _parent != nil {
            _parent!.addListener(notifyListeners)
            _parent!.addStatusListener(notifyStatusListeners)
        }
    }

    /// **Dart Source:** `animations.dart:236-241`
    func didStopListening() {
        if _parent != nil {
            _parent!.removeListener(notifyListeners)
            _parent!.removeStatusListener(notifyStatusListeners)
        }
    }

    /// **Dart Source:** `animations.dart:244`
    public override var status: AnimationStatus { _parent != nil ? _parent!.status : _status! }

    /// **Dart Source:** `animations.dart:247`
    public override var value: Double { _parent != nil ? _parent!.value : _value! }

    /// **Dart Source:** `animations.dart:146` (from AnimationLocalListenersMixin)
    public override func addListener(_ listener: @escaping VoidCallback) {
        _didRegisterListener()
        _listeners.append(listener)
    }

    /// **Dart Source:** `animations.dart:151` (from AnimationLocalListenersMixin)
    public override func removeListener(_ listener: @escaping VoidCallback) {
        if _listeners.removeLast() {
            _didUnregisterListener()
        }
    }

    public override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _didRegisterListener()
        _listeners.append(listener, owner: owner)
    }

    public override func removeListeners(owner: AnyObject) {
        for _ in 0..<_listeners.remove(owner: owner) {
            _didUnregisterListener()
        }
    }

    /// **Dart Source:** `animations.dart:156` (from AnimationLocalStatusListenersMixin)
    public override func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        _didRegisterListener()
        _statusListeners.append(listener)
    }

    /// **Dart Source:** `animations.dart:161` (from AnimationLocalStatusListenersMixin)
    public override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        if !_statusListeners.isEmpty {
            _statusListeners.removeLast()
            _didUnregisterListener()
        }
    }

    /// **Dart Source:** `animations.dart:250-255`
    public override var description: String {
        if parent == nil {
            return "\(describeIdentity(self))(nil; \(super.toStringDetails()) \(String(format: "%.3f", value)))"
        }
        return "\(parent!)\u{27A9}\(describeIdentity(self))"
    }
}

// MARK: - ReverseAnimation

/// An animation that is the reverse of another animation.
///
/// If the parent animation is running forward from 0.0 to 1.0, this animation
/// is running in reverse from 1.0 to 0.0.
///
/// Using a ``ReverseAnimation`` is different from using a `Tween` with a
/// `begin` of 1.0 and an `end` of 0.0 because the tween does not change the
/// status or direction of the animation.
///
/// **Dart Source:** `animations.dart:273-326`
///
/// DIFFERENCE FROM DART: Dart uses mixins AnimationLazyListenerMixin and
/// AnimationLocalStatusListenersMixin. Swift embeds the functionality directly.
/// REASON: Swift does not have mixins.
public class ReverseAnimation: Animation<Double> {
    /// Creates a reverse animation.
    ///
    /// **Dart Source:** `animations.dart:276`
    public init(_ parent: Animation<Double>) {
        self.parent = parent
    }

    /// The animation whose value and direction this animation is reversing.
    ///
    /// **Dart Source:** `animations.dart:279`
    public let parent: Animation<Double>

    // Embedded lazy listener state
    private var _listenerCounter: Int = 0

    // Embedded status listeners
    private var _statusListeners: [AnimationStatusListener] = []

    private var isListening: Bool { _listenerCounter > 0 }

    private func _didRegisterListener() {
        assert(_listenerCounter >= 0)
        if _listenerCounter == 0 {
            didStartListening()
        }
        _listenerCounter += 1
    }

    private func _didUnregisterListener() {
        assert(_listenerCounter >= 1)
        _listenerCounter -= 1
        if _listenerCounter == 0 {
            didStopListening()
        }
    }

    /// Calls all the registered status listeners.
    func notifyStatusListeners(_ status: AnimationStatus) {
        let localListeners = _statusListeners
        for listener in localListeners {
            listener(status)
        }
    }

    /// **Dart Source:** `animations.dart:282-285`
    public override func addListener(_ listener: @escaping VoidCallback) {
        _didRegisterListener()
        parent.addListener(listener)
    }

    /// **Dart Source:** `animations.dart:288-291`
    public override func removeListener(_ listener: @escaping VoidCallback) {
        parent.removeListener(listener)
        _didUnregisterListener()
    }

    public override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _didRegisterListener()
        parent.addListener(listener, owner: owner)
    }

    public override func removeListeners(owner: AnyObject) {
        parent.removeListeners(owner: owner)
        _didUnregisterListener()
    }

    /// **Dart Source:** `animations.dart:294-296`
    func didStartListening() {
        parent.addStatusListener(_statusChangeHandler)
    }

    /// **Dart Source:** `animations.dart:299-301`
    func didStopListening() {
        parent.removeStatusListener(_statusChangeHandler)
    }

    /// **Dart Source:** `animations.dart:303-305`
    private func _statusChangeHandler(_ status: AnimationStatus) {
        notifyStatusListeners(_reverseStatus(status))
    }

    /// **Dart Source:** `animations.dart:308`
    public override var status: AnimationStatus { _reverseStatus(parent.status) }

    /// **Dart Source:** `animations.dart:311`
    public override var value: Double { 1.0 - parent.value }

    /// **Dart Source:** `animations.dart:313-320`
    private func _reverseStatus(_ status: AnimationStatus) -> AnimationStatus {
        switch status {
        case .forward: return .reverse
        case .reverse: return .forward
        case .completed: return .dismissed
        case .dismissed: return .completed
        }
    }

    /// **Dart Source:** `animations.dart:205-208` (from AnimationLocalStatusListenersMixin)
    public override func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        _didRegisterListener()
        _statusListeners.append(listener)
    }

    /// **Dart Source:** `animations.dart:213-218` (from AnimationLocalStatusListenersMixin)
    public override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        if !_statusListeners.isEmpty {
            _statusListeners.removeLast()
            _didUnregisterListener()
        }
    }

    /// **Dart Source:** `animations.dart:322-325`
    public override var description: String {
        return "\(parent)\u{27AA}\(describeIdentity(self))"
    }
}

// MARK: - CurvedAnimation

/// An animation that applies a curve to another animation.
///
/// ``CurvedAnimation`` is useful when you want to apply a non-linear `Curve` to
/// an animation object, especially if you want different curves when the
/// animation is going forward vs when it is going backward.
///
/// By default, the ``reverseCurve`` matches the forward ``curve``.
///
/// **Dart Source:** `animations.dart:379-471`
///
/// DIFFERENCE FROM DART: Dart uses `AnimationWithParentMixin<double>` mixin.
/// Swift conforms to the protocol and provides its own listener delegation.
/// REASON: Swift does not have mixins; conforming to the protocol provides
/// the same forwarding behavior.
public class CurvedAnimation: Animation<Double>, AnimationWithParentMixin {
    public typealias ParentValue = Double

    /// Creates a curved animation.
    ///
    /// **Dart Source:** `animations.dart:381-385`
    public init(parent: Animation<Double>, curve: any Curve, reverseCurve: (any Curve)? = nil) {
        self.parent = parent
        self.curve = curve
        self.reverseCurve = reverseCurve
        super.init()
        _updateCurveDirection(parent.status)
        parent.addStatusListener(_updateCurveDirection)
    }

    /// The animation to which this animation applies a curve.
    ///
    /// **Dart Source:** `animations.dart:389`
    public let parent: Animation<Double>

    /// The curve to use in the forward direction.
    ///
    /// **Dart Source:** `animations.dart:392`
    public var curve: any Curve

    /// The curve to use in the reverse direction.
    ///
    /// If the parent animation changes direction without first reaching the
    /// ``AnimationStatus/completed`` or ``AnimationStatus/dismissed`` status, the
    /// ``CurvedAnimation`` stays on the same curve (albeit in the opposite
    /// direction) to avoid visual discontinuities.
    ///
    /// If this field is nil, uses ``curve`` in both directions.
    ///
    /// **Dart Source:** `animations.dart:407`
    public var reverseCurve: (any Curve)?

    /// The direction used to select the current curve.
    ///
    /// **Dart Source:** `animations.dart:414`
    private var _curveDirection: AnimationStatus?

    /// True if this CurvedAnimation has been disposed.
    ///
    /// **Dart Source:** `animations.dart:417`
    public var isDisposed: Bool = false

    /// **Dart Source:** `animations.dart:419-421`
    private func _updateCurveDirection(_ status: AnimationStatus) {
        _curveDirection = status.isAnimating ? (_curveDirection ?? status) : nil
    }

    /// **Dart Source:** `animations.dart:423-425`
    private var _useForwardCurve: Bool {
        return reverseCurve == nil || (_curveDirection ?? parent.status) != .reverse
    }

    // MARK: AnimationWithParentMixin forwarding overrides
    // These must be explicit overrides because Swift protocol extension methods
    // do not override class methods from the superclass.

    public override func addListener(_ listener: @escaping VoidCallback) {
        parent.addListener(listener)
    }

    public override func removeListener(_ listener: @escaping VoidCallback) {
        parent.removeListener(listener)
    }

    public override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        parent.addListener(listener, owner: owner)
    }

    public override func removeListeners(owner: AnyObject) {
        parent.removeListeners(owner: owner)
    }

    public override func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        parent.addStatusListener(listener)
    }

    public override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        parent.removeStatusListener(listener)
    }

    public override var status: AnimationStatus { parent.status }

    /// Cleans up any listeners added by this CurvedAnimation.
    ///
    /// **Dart Source:** `animations.dart:428-432`
    public func dispose() {
        isDisposed = true
        parent.removeStatusListener(_updateCurveDirection)
    }

    /// **Dart Source:** `animations.dart:435-459`
    public override var value: Double {
        let activeCurve: (any Curve)? = _useForwardCurve ? curve : reverseCurve

        let t = parent.value
        if activeCurve == nil {
            return t
        }
        if t == 0.0 || t == 1.0 {
            assert({
                let transformedValue = activeCurve!.transform(t)
                let roundedTransformedValue = transformedValue.rounded()
                if roundedTransformedValue != t {
                    fatalError(
                        "Invalid curve endpoint at \(t).\n"
                        + "Curves must map 0.0 to near zero and 1.0 to near one but "
                        + "\(type(of: activeCurve!)) mapped \(t) to \(transformedValue), which "
                        + "is near \(roundedTransformedValue)."
                    )
                }
                return true
            }())
            return t
        }
        return activeCurve!.transform(t)
    }

    /// **Dart Source:** `animations.dart:462-470`
    public override var description: String {
        if reverseCurve == nil {
            return "\(parent)\u{27A9}\(curve)"
        }
        if _useForwardCurve {
            return "\(parent)\u{27A9}\(curve)\u{2092}\u{2099}/\(reverseCurve!)"
        }
        return "\(parent)\u{27A9}\(curve)/\(reverseCurve!)\u{2092}\u{2099}"
    }
}

// MARK: - TrainHoppingMode

/// Internal enum for TrainHoppingAnimation mode.
///
/// **Dart Source:** `animations.dart:473`
/// **Original Name:** `_TrainHoppingMode`
enum TrainHoppingMode {
    case minimize
    case maximize
}

// MARK: - TrainHoppingAnimation

/// This animation starts by proxying one animation, but when the value of that
/// animation crosses the value of the second (either because the second is
/// going in the opposite direction, or because the one overtakes the other),
/// the animation hops over to proxying the second animation.
///
/// When the ``TrainHoppingAnimation`` starts proxying the second animation
/// instead of the first, the ``onSwitchedTrain`` callback is called.
///
/// Since this object must track the two animations even when it has no
/// listeners of its own, instead of shutting down when all its listeners are
/// removed, it exposes a ``dispose()`` method. Call this method to shut this
/// object down.
///
/// **Dart Source:** `animations.dart:493-612`
///
/// DIFFERENCE FROM DART: Dart uses mixins AnimationEagerListenerMixin,
/// AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin. Swift
/// embeds the functionality directly.
/// REASON: Swift does not have mixins.
public class TrainHoppingAnimation: Animation<Double> {
    /// Creates a train-hopping animation.
    ///
    /// The current train argument must not be nil but the next train argument
    /// can be nil. If the next train is nil, then this object will just proxy
    /// the first animation and never hop.
    ///
    /// **Dart Source:** `animations.dart:503-524`
    public init(
        _ currentTrain: Animation<Double>,
        _ nextTrain: Animation<Double>?,
        onSwitchedTrain: VoidCallback? = nil
    ) {
        self._currentTrain = currentTrain
        self._nextTrain = nextTrain
        self.onSwitchedTrain = onSwitchedTrain

        if _nextTrain != nil {
            if _currentTrain!.value == _nextTrain!.value {
                _currentTrain = _nextTrain
                _nextTrain = nil
            } else if _currentTrain!.value > _nextTrain!.value {
                _mode = .maximize
            } else {
                assert(_currentTrain!.value < _nextTrain!.value)
                _mode = .minimize
            }
        }
        super.init()
        _currentTrain!.addStatusListener(_statusChangeHandler)
        _currentTrain!.addListener(_valueChangeHandler)
        _nextTrain?.addListener(_valueChangeHandler)
        assert(_mode != nil || _nextTrain == nil)
    }

    // Embedded local listeners (from AnimationLocalListenersMixin)
    private var _listeners = ListenerList()

    // Embedded local status listeners (from AnimationLocalStatusListenersMixin)
    private var _statusListeners: [AnimationStatusListener] = []

    /// Calls all the registered value listeners.
    func notifyListeners() {
        let localListeners = _listeners
        for listener in localListeners {
            listener()
        }
    }

    /// Calls all the registered status listeners.
    func notifyStatusListeners(_ status: AnimationStatus) {
        let localListeners = _statusListeners
        for listener in localListeners {
            listener(status)
        }
    }

    /// Removes all value listeners.
    func clearListeners() {
        _listeners.removeAll()
    }

    /// Removes all status listeners.
    func clearStatusListeners() {
        _statusListeners.removeAll()
    }

    /// The animation that is currently driving this animation.
    ///
    /// **Dart Source:** `animations.dart:530`
    public var currentTrain: Animation<Double>? { _currentTrain }
    private var _currentTrain: Animation<Double>?
    private var _nextTrain: Animation<Double>?
    private var _mode: TrainHoppingMode?

    /// Called when this animation switches to be driven by the second animation.
    ///
    /// **Dart Source:** `animations.dart:540`
    public var onSwitchedTrain: VoidCallback?

    /// **Dart Source:** `animations.dart:542-550`
    private var _lastStatus: AnimationStatus?
    private func _statusChangeHandler(_ status: AnimationStatus) {
        assert(_currentTrain != nil)
        if status != _lastStatus {
            notifyListeners()
            _lastStatus = status
        }
        assert(_lastStatus != nil)
    }

    /// **Dart Source:** `animations.dart:553`
    public override var status: AnimationStatus { _currentTrain!.status }

    /// **Dart Source:** `animations.dart:555-584`
    private var _lastValue: Double?
    private func _valueChangeHandler() {
        assert(_currentTrain != nil)
        var hop = false
        if _nextTrain != nil {
            assert(_mode != nil)
            switch _mode! {
            case .minimize:
                hop = _nextTrain!.value <= _currentTrain!.value
            case .maximize:
                hop = _nextTrain!.value >= _currentTrain!.value
            }
            if hop {
                _currentTrain!.removeStatusListener(_statusChangeHandler)
                _currentTrain!.removeListener(_valueChangeHandler)
                _currentTrain = _nextTrain
                _nextTrain = nil
                _currentTrain!.addStatusListener(_statusChangeHandler)
                _statusChangeHandler(_currentTrain!.status)
            }
        }
        let newValue = value
        if newValue != _lastValue {
            notifyListeners()
            _lastValue = newValue
        }
        assert(_lastValue != nil)
        if hop && onSwitchedTrain != nil {
            onSwitchedTrain!()
        }
    }

    /// **Dart Source:** `animations.dart:587`
    public override var value: Double { _currentTrain!.value }

    /// Frees all the resources used by this performance.
    /// After this is called, this object is no longer usable.
    ///
    /// **Dart Source:** `animations.dart:592-603`
    public func dispose() {
        assert(_currentTrain != nil)
        _currentTrain!.removeStatusListener(_statusChangeHandler)
        _currentTrain!.removeListener(_valueChangeHandler)
        _currentTrain = nil
        _nextTrain?.removeListener(_valueChangeHandler)
        _nextTrain = nil
        clearListeners()
        clearStatusListeners()
    }

    /// **Dart Source:** `animations.dart:105-108` (from AnimationLocalListenersMixin)
    public override func addListener(_ listener: @escaping VoidCallback) {
        _listeners.append(listener)
    }

    /// **Dart Source:** `animations.dart:120-125` (from AnimationLocalListenersMixin)
    public override func removeListener(_ listener: @escaping VoidCallback) {
        _listeners.removeLast()
    }

    public override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _listeners.append(listener, owner: owner)
    }

    public override func removeListeners(owner: AnyObject) {
        _listeners.remove(owner: owner)
    }

    /// **Dart Source:** `animations.dart:205-208` (from AnimationLocalStatusListenersMixin)
    public override func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        _statusListeners.append(listener)
    }

    /// **Dart Source:** `animations.dart:213-218` (from AnimationLocalStatusListenersMixin)
    public override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        if !_statusListeners.isEmpty {
            _statusListeners.removeLast()
        }
    }

    /// **Dart Source:** `animations.dart:606-611`
    public override var description: String {
        if _nextTrain != nil {
            return "\(currentTrain!)\u{27A9}\(describeIdentity(self))(next: \(_nextTrain!))"
        }
        return "\(currentTrain!)\u{27A9}\(describeIdentity(self))(no next)"
    }
}

// MARK: - CompoundAnimation

/// An interface for combining multiple Animations. Subclasses need only
/// implement the `value` getter to control how the child animations are
/// combined. Can be chained to combine more than 2 animations.
///
/// By default, the ``status`` of a ``CompoundAnimation`` is the status of the
/// ``next`` animation if ``next`` is moving, and the status of the ``first``
/// animation otherwise.
///
/// **Dart Source:** `animations.dart:624-684`
///
/// DIFFERENCE FROM DART: Dart uses mixins AnimationLazyListenerMixin,
/// AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin. Swift
/// embeds the functionality directly.
/// REASON: Swift does not have mixins.
open class CompoundAnimation<T: Equatable>: Animation<T> {
    /// Creates a ``CompoundAnimation``.
    ///
    /// Either argument can be a ``CompoundAnimation`` itself to combine
    /// multiple animations.
    ///
    /// **Dart Source:** `animations.dart:632`
    public init(first: Animation<T>, next: Animation<T>) {
        self.first = first
        self.next = next
    }

    /// The first sub-animation. Its status takes precedence if neither are
    /// animating.
    ///
    /// **Dart Source:** `animations.dart:636`
    public let first: Animation<T>

    /// The second sub-animation.
    ///
    /// **Dart Source:** `animations.dart:639`
    public let next: Animation<T>

    // Embedded lazy listener state
    private var _listenerCounter: Int = 0

    // Embedded local listeners
    private var _listeners = ListenerList()

    // Embedded local status listeners
    private var _statusListeners: [AnimationStatusListener] = []

    private var isListening: Bool { _listenerCounter > 0 }

    private func _didRegisterListener() {
        assert(_listenerCounter >= 0)
        if _listenerCounter == 0 {
            didStartListening()
        }
        _listenerCounter += 1
    }

    private func _didUnregisterListener() {
        assert(_listenerCounter >= 1)
        _listenerCounter -= 1
        if _listenerCounter == 0 {
            didStopListening()
        }
    }

    /// Calls all the registered value listeners.
    func notifyListeners() {
        let localListeners = _listeners
        for listener in localListeners {
            listener()
        }
    }

    /// Calls all the registered status listeners.
    func notifyStatusListeners(_ status: AnimationStatus) {
        let localListeners = _statusListeners
        for listener in localListeners {
            listener(status)
        }
    }

    /// **Dart Source:** `animations.dart:642-647`
    func didStartListening() {
        first.addListener(_maybeNotifyListeners)
        first.addStatusListener(_maybeNotifyStatusListeners)
        next.addListener(_maybeNotifyListeners)
        next.addStatusListener(_maybeNotifyStatusListeners)
    }

    /// **Dart Source:** `animations.dart:650-655`
    func didStopListening() {
        first.removeListener(_maybeNotifyListeners)
        first.removeStatusListener(_maybeNotifyStatusListeners)
        next.removeListener(_maybeNotifyListeners)
        next.removeStatusListener(_maybeNotifyStatusListeners)
    }

    /// Gets the status of this animation based on the ``first`` and ``next`` status.
    ///
    /// The default is that if the ``next`` animation is moving, use its status.
    /// Otherwise, default to ``first``.
    ///
    /// **Dart Source:** `animations.dart:662`
    public override var status: AnimationStatus {
        next.status.isAnimating ? next.status : first.status
    }

    /// **Dart Source:** `animations.dart:665-667`
    public override var description: String {
        return "\(describeIdentity(self))(\(first), \(next))"
    }

    /// **Dart Source:** `animations.dart:669-675`
    private var _lastStatus: AnimationStatus?
    private func _maybeNotifyStatusListeners(_ status: AnimationStatus) {
        if self.status != _lastStatus {
            _lastStatus = self.status
            notifyStatusListeners(self.status)
        }
    }

    /// **Dart Source:** `animations.dart:677-683`
    private var _lastValue: T?
    private func _maybeNotifyListeners() {
        if value != _lastValue {
            _lastValue = value
            notifyListeners()
        }
    }

    /// **Dart Source:** (from AnimationLocalListenersMixin)
    public override func addListener(_ listener: @escaping VoidCallback) {
        _didRegisterListener()
        _listeners.append(listener)
    }

    /// **Dart Source:** (from AnimationLocalListenersMixin)
    public override func removeListener(_ listener: @escaping VoidCallback) {
        if _listeners.removeLast() {
            _didUnregisterListener()
        }
    }

    public override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        _didRegisterListener()
        _listeners.append(listener, owner: owner)
    }

    public override func removeListeners(owner: AnyObject) {
        for _ in 0..<_listeners.remove(owner: owner) {
            _didUnregisterListener()
        }
    }

    /// **Dart Source:** (from AnimationLocalStatusListenersMixin)
    public override func addStatusListener(_ listener: @escaping AnimationStatusListener) {
        _didRegisterListener()
        _statusListeners.append(listener)
    }

    /// **Dart Source:** (from AnimationLocalStatusListenersMixin)
    public override func removeStatusListener(_ listener: @escaping AnimationStatusListener) {
        if !_statusListeners.isEmpty {
            _statusListeners.removeLast()
            _didUnregisterListener()
        }
    }
}

// MARK: - AnimationMean

/// An animation of `Double`s that tracks the mean of two other animations.
///
/// The ``status`` of this animation is the status of the `next` animation if
/// it is moving, and the `first` animation otherwise.
///
/// The ``value`` of this animation is the `Double` that represents the mean
/// value of the values of the `first` and `next` animations.
///
/// **Dart Source:** `animations.dart:693-700`
public class AnimationMean: CompoundAnimation<Double> {
    /// Creates an animation that tracks the mean of two other animations.
    ///
    /// **Dart Source:** `animations.dart:695-696`
    public init(left: Animation<Double>, right: Animation<Double>) {
        super.init(first: left, next: right)
    }

    /// **Dart Source:** `animations.dart:699`
    public override var value: Double { (first.value + next.value) / 2.0 }
}

// MARK: - AnimationMax

/// An animation that tracks the maximum of two other animations.
///
/// The ``value`` of this animation is the maximum of the values of
/// ``first`` and ``next``.
///
/// **Dart Source:** `animations.dart:706-715`
///
/// DIFFERENCE FROM DART: Dart constrains `T extends num`. Swift uses
/// `T: Comparable & Numeric` for the same constraint since `num` doesn't
/// exist in Swift. However, since the Dart code uses `math.max`, we only
/// need Comparable.
/// REASON: Swift does not have a `num` type.
public class AnimationMax<T: Comparable & Equatable>: CompoundAnimation<T> {
    /// Creates an ``AnimationMax``.
    ///
    /// **Dart Source:** `animations.dart:711`
    public init(_ first: Animation<T>, _ next: Animation<T>) {
        super.init(first: first, next: next)
    }

    /// **Dart Source:** `animations.dart:714`
    public override var value: T { max(first.value, next.value) }
}

// MARK: - AnimationMin

/// An animation that tracks the minimum of two other animations.
///
/// The ``value`` of this animation is the minimum of the values of
/// ``first`` and ``next``.
///
/// **Dart Source:** `animations.dart:721-730`
///
/// DIFFERENCE FROM DART: Same as ``AnimationMax``, uses `Comparable` constraint.
/// REASON: Swift does not have a `num` type.
public class AnimationMin<T: Comparable & Equatable>: CompoundAnimation<T> {
    /// Creates an ``AnimationMin``.
    ///
    /// **Dart Source:** `animations.dart:726`
    public init(_ first: Animation<T>, _ next: Animation<T>) {
        super.init(first: first, next: next)
    }

    /// **Dart Source:** `animations.dart:729`
    public override var value: T { min(first.value, next.value) }
}
