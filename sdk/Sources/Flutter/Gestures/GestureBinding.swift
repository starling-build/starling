// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Gesture binding — connects pointer events from the engine to the gesture
/// subsystem (hit testing, routing, arena, resampling).
///
/// **Dart Source:** `packages/flutter/lib/src/gestures/binding.dart`
/// **Lines:** 1-639

import FlutterSwiftBridge
import Foundation

// MARK: - Type Aliases

/// Callback used when sample time changes in the resampler.
///
/// **Dart Source:** `binding.dart:38`
/// **Original:** `typedef _HandleSampleTimeChangedCallback = void Function();`
internal typealias HandleSampleTimeChangedCallback = () -> Void

// MARK: - SamplingClock

/// Class that implements the clock used for sampling.
///
/// Returns current time and stopwatch instances. Override in tests
/// to synchronize with `FakeAsync`.
///
/// **Dart Source:** `binding.dart:41-53`
open class SamplingClock {

    public init() {}

    /// Returns current time.
    ///
    /// **Dart Source:** `binding.dart:43`
    open func now() -> Date {
        return Date()
    }

    /// Returns a new stopwatch that uses the current time as reported by `this`.
    ///
    /// See also:
    ///
    ///   * `GestureBinding.debugSamplingClock`, which is used in tests and
    ///     debug builds to observe `FakeAsync`.
    ///
    /// **Dart Source:** `binding.dart:51`
    ///
    /// DIFFERENCE FROM DART: Returns `ContinuousClock.Instant` pair for elapsed
    /// measurement since Swift does not have a built-in `Stopwatch` type.
    /// We use a simple `GestureStopwatch` wrapper instead.
    open func stopwatch() -> GestureStopwatch {
        return GestureStopwatch()
    }
}

// MARK: - GestureStopwatch

/// A simple stopwatch replacement for Dart's `Stopwatch` class.
///
/// Uses `ContinuousClock` for monotonic time measurement.
///
/// DIFFERENCE FROM DART: Swift does not have a built-in `Stopwatch` class.
/// This provides the subset of the Dart Stopwatch API used by the resampler.
public class GestureStopwatch {

    public init() {}

    private var _startTime: ContinuousClock.Instant?
    private var _elapsed: Swift.Duration = .zero
    private var _isRunning: Bool = false

    /// Starts the stopwatch.
    public func start() {
        if !_isRunning {
            _startTime = ContinuousClock.now
            _isRunning = true
        }
    }

    /// Stops the stopwatch.
    public func stop() {
        if _isRunning, let startTime = _startTime {
            _elapsed += ContinuousClock.now - startTime
            _isRunning = false
            _startTime = nil
        }
    }

    /// Resets the stopwatch to zero elapsed time.
    public func reset() {
        _elapsed = .zero
        if _isRunning {
            _startTime = ContinuousClock.now
        }
    }

    /// The elapsed time in microseconds.
    public var elapsedMicroseconds: Int64 {
        let total: Swift.Duration
        if _isRunning, let startTime = _startTime {
            total = _elapsed + (ContinuousClock.now - startTime)
        } else {
            total = _elapsed
        }
        let components = total.components
        return Int64(components.seconds) * 1_000_000
            + components.attoseconds / 1_000_000_000_000
    }

    /// Whether the stopwatch is currently running.
    public var isRunning: Bool { _isRunning }
}

// MARK: - GestureResampler (internal)

/// Handles resampling of touch events for multiple pointer devices.
///
/// The `samplingInterval` is used to determine the approximate next
/// time for resampling.
///
/// **Dart Source:** `binding.dart:62-216`
/// **Original Name:** `_Resampler`
///
/// DIFFERENCE FROM DART: Renamed from `_Resampler` to `GestureResampler` with
/// `internal` access. REASON: Swift does not support file-private classes that
/// need to be referenced across types within the same module.
internal class GestureResampler {

    /// Creates a resampler with the given callbacks and sampling interval.
    ///
    /// **Dart Source:** `binding.dart:63`
    init(
        _ handlePointerEvent: @escaping HandleEventCallback,
        _ handleSampleTimeChanged: @escaping HandleSampleTimeChangedCallback,
        _ samplingInterval: Duration
    ) {
        self._handlePointerEvent = handlePointerEvent
        self._handleSampleTimeChanged = handleSampleTimeChanged
        self._samplingInterval = samplingInterval
    }

    // MARK: - Private State

    /// Resamplers used to filter incoming pointer events.
    ///
    /// **Dart Source:** `binding.dart:66`
    private var _resamplers: [Int: PointerEventResampler] = [:]

    /// Flag to track if a frame callback has been scheduled.
    ///
    /// **Dart Source:** `binding.dart:69`
    private var _frameCallbackScheduled: Bool = false

    /// Last frame time for resampling.
    ///
    /// **Dart Source:** `binding.dart:72`
    private var _frameTime: Duration = .zero

    /// Time since `_frameTime` was updated.
    ///
    /// **Dart Source:** `binding.dart:75`
    private var _frameTimeAge: GestureStopwatch = GestureStopwatch()

    /// Last sample time and time stamp of last event.
    /// Only used for debugPrint of resampling margin.
    ///
    /// **Dart Source:** `binding.dart:81-82`
    private var _lastSampleTime: Duration = .zero
    private var _lastEventTime: Duration = .zero

    /// Callback used to handle pointer events.
    ///
    /// **Dart Source:** `binding.dart:85`
    private let _handlePointerEvent: HandleEventCallback

    /// Callback used to handle sample time changes.
    ///
    /// **Dart Source:** `binding.dart:88`
    private let _handleSampleTimeChanged: HandleSampleTimeChangedCallback

    /// Interval used for sampling.
    ///
    /// **Dart Source:** `binding.dart:91`
    private let _samplingInterval: Duration

    /// Timer used to schedule resampling.
    ///
    /// **Dart Source:** `binding.dart:94`
    ///
    /// DIFFERENCE FROM DART: Uses Foundation `Timer` instead of `dart:async` `Timer`.
    private var _timer: Timer?

    // MARK: - Internal API

    /// Add `event` for resampling or dispatch it directly if
    /// not a touch event.
    ///
    /// **Dart Source:** `binding.dart:98-112`
    func addOrDispatch(_ event: PointerEvent) {
        // Add touch event to resampler or dispatch pointer event directly.
        if event.kind == .touch {
            // Save last event time for debugPrint of resampling margin.
            _lastEventTime = event.timeStamp

            let resampler: PointerEventResampler
            if let existing = _resamplers[event.device] {
                resampler = existing
            } else {
                let newResampler = PointerEventResampler()
                _resamplers[event.device] = newResampler
                resampler = newResampler
            }
            resampler.addEvent(event)
        } else {
            _handlePointerEvent(event)
        }
    }

    /// Sample and dispatch events.
    ///
    /// The `samplingOffset` is relative to the current frame time, which
    /// can be in the past when we're not actively resampling.
    ///
    /// The `samplingClock` is the clock used to determine frame time age.
    ///
    /// **Dart Source:** `binding.dart:120-193`
    func sample(_ samplingOffset: Duration, _ clock: SamplingClock) {
        // TODO: SchedulerBinding integration — currently we don't have access to
        // SchedulerBinding.instance.currentSystemFrameTimeStamp or
        // addPostFrameCallback. Frame-time synchronization is approximated using
        // the stopwatch approach only.

        // Initialize `_frameTime` if needed. This will be used for periodic
        // sampling when frame callbacks are not received.
        if _frameTime == .zero {
            let nowMs = Int64(clock.now().timeIntervalSince1970 * 1000)
            _frameTime = .milliseconds(nowMs)
            _frameTimeAge = clock.stopwatch()
            _frameTimeAge.start()
        }

        // Schedule periodic resampling if `_timer` is not already active.
        if _timer == nil || !_timer!.isValid {
            let interval = _durationToSeconds(_samplingInterval)
            nonisolated(unsafe) let weakSelf = self
            _timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                weakSelf._onSampleTimeChanged()
            }
        }

        // Calculate the effective frame time by taking the number
        // of sampling intervals since last time `_frameTime` was
        // updated into account. This allows us to advance sample
        // time without having to receive frame callbacks.
        let samplingIntervalUs = _durationToMicroseconds(_samplingInterval)
        let elapsedIntervals = _frameTimeAge.elapsedMicroseconds / samplingIntervalUs
        let elapsedUs = elapsedIntervals * samplingIntervalUs
        let frameTime = _frameTime + .microseconds(elapsedUs)

        // Determine sample time by adding the offset to the current
        // frame time. This is expected to be in the past and not
        // result in any dispatched events unless we're actively
        // resampling events.
        let sampleTime = frameTime + samplingOffset

        // Determine next sample time by adding the sampling interval
        // to the current sample time.
        let nextSampleTime = sampleTime + _samplingInterval

        // Iterate over active resamplers and sample pointer events for
        // current sample time.
        for resampler in _resamplers.values {
            resampler.sample(sampleTime: sampleTime, nextSampleTime: nextSampleTime, callback: _handlePointerEvent)
        }

        // Remove inactive resamplers.
        _resamplers = _resamplers.filter { (_, resampler) in
            resampler.hasPendingEvents || resampler.isDown
        }

        // Save last sample time for debugPrint of resampling margin.
        _lastSampleTime = sampleTime

        // Early out if another call to `sample` isn't needed.
        if _resamplers.isEmpty {
            _timer?.invalidate()
            _timer = nil
            return
        }

        // Schedule a frame callback if another call to `sample` is needed.
        if !_frameCallbackScheduled {
            _frameCallbackScheduled = true
            // TODO: SchedulerBinding integration — use addPostFrameCallback when available.
            // For now, the timer-based approach handles resampling without frame callbacks.
            // When SchedulerBinding is migrated, this should be:
            //   scheduler.addPostFrameCallback { _ in
            //       self._frameCallbackScheduled = false
            //       self._frameTime = scheduler.currentSystemFrameTimeStamp
            //       self._frameTimeAge.reset()
            //       self._timer?.invalidate()
            //       self._timer = Timer.scheduledTimer(...)
            //       self._onSampleTimeChanged()
            //   }
        }
    }

    /// Stop all resampling and dispatch any queued events.
    ///
    /// **Dart Source:** `binding.dart:197-204`
    func stop() {
        for resampler in _resamplers.values {
            resampler.stop(callback: _handlePointerEvent)
        }
        _resamplers.removeAll()
        _frameTime = .zero
        _timer?.invalidate()
        _timer = nil
    }

    // MARK: - Private Helpers

    /// Called when the sample time changes (timer fires).
    ///
    /// **Dart Source:** `binding.dart:206-215`
    private func _onSampleTimeChanged() {
        assert({
            if debugPrintResamplingMargin {
                let resamplingMargin = _lastEventTime - _lastSampleTime
                debugPrint("\(resamplingMargin)", nil)
            }
            return true
        }())
        _handleSampleTimeChanged()
    }

    /// Converts a `Duration` to microseconds.
    private func _durationToMicroseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return Int64(components.seconds) * 1_000_000
            + components.attoseconds / 1_000_000_000_000
    }

    /// Converts a `Duration` to `TimeInterval` (seconds) for Foundation `Timer`.
    private func _durationToSeconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000.0
    }
}

// MARK: - Constants

/// The default sampling offset.
///
/// Sampling offset is relative to presentation time. If we produce frames
/// 16.667 ms before presentation and input rate is ~60hz, worst case latency
/// is 33.334 ms. This however assumes zero latency from the input driver.
/// 4.666 ms margin is added for this.
///
/// **Dart Source:** `binding.dart:224`
internal let _defaultSamplingOffset: Duration = .milliseconds(-38)

/// The sampling interval.
///
/// Sampling interval is used to determine the approximate time for subsequent
/// sampling. This is used to sample events when frame callbacks are not
/// being received and decide if early processing of up and removed events
/// is appropriate. 16667 us for 60hz sampling interval.
///
/// **Dart Source:** `binding.dart:232`
internal let _samplingInterval: Duration = .microseconds(16667)

// MARK: - GestureBinding

/// A binding for the gesture subsystem.
///
/// ## Lifecycle of pointer events and the gesture arena
///
/// ### `PointerDownEvent`
///
/// When a `PointerDownEvent` is received by the `GestureBinding` (from
/// `PlatformDispatcher.onPointerDataPacket`, as interpreted by the
/// `PointerEventConverter`), a `hitTestInView` is performed to determine which
/// `HitTestTarget` nodes are affected. (Other bindings are expected to
/// implement `hitTestInView` to defer to `HitTestable` objects. For example, the
/// rendering layer defers to the `RenderView` and the rest of the render object
/// hierarchy.)
///
/// The affected nodes then are given the event to handle (`dispatchEvent` calls
/// `HitTestTarget.handleEvent` for each affected node). If any have relevant
/// `GestureRecognizer`s, they provide the event to them using
/// `GestureRecognizer.addPointer`. This typically causes the recognizer to
/// register with the `PointerRouter` to receive notifications regarding the
/// pointer in question.
///
/// Once the hit test and dispatching logic is complete, the event is then
/// passed to the aforementioned `PointerRouter`, which passes it to any objects
/// that have registered interest in that event.
///
/// Finally, the `gestureArena` is closed for the given pointer
/// (`GestureArenaManager.close`), which begins the process of selecting a
/// gesture to win that pointer.
///
/// ### Other events
///
/// A pointer that is `PointerEvent.down` may send further events, such as
/// `PointerMoveEvent`, `PointerUpEvent`, or `PointerCancelEvent`. These are
/// sent to the same `HitTestTarget` nodes as were found when the
/// `PointerDownEvent` was received (even if they have since been disposed; it is
/// the responsibility of those objects to be aware of that possibility).
///
/// Then, the events are routed to any still-registered entrants in the
/// `PointerRouter`'s table for that pointer.
///
/// When a `PointerUpEvent` is received, the `GestureArenaManager.sweep` method
/// is invoked to force the gesture arena logic to terminate if necessary.
///
/// **Dart Source:** `binding.dart:276-607`
///
/// DIFFERENCE FROM DART: Dart uses `mixin GestureBinding on BindingBase
/// implements HitTestable, HitTestDispatcher, HitTestTarget`. Swift does not
/// support mixins. This is implemented as an open class that extends
/// `BindingBase` and conforms to `HitTestable`, `HitTestDispatcher`, and
/// `HitTestTarget`.
open class GestureBinding: BindingBase, HitTestable, HitTestDispatcher, HitTestTarget {

    // MARK: - Singleton

    /// The singleton instance of this object.
    ///
    /// Provides access to the features exposed by this binding. The binding must
    /// be initialized before using this getter; this is typically done by calling
    /// `runApp` or `WidgetsFlutterBinding.ensureInitialized`.
    ///
    /// **Dart Source:** `binding.dart:289-290`
    public static var instance: GestureBinding {
        return BindingBase.checkInstance(_instance)
    }
    nonisolated(unsafe) private static var _instance: GestureBinding?

    // MARK: - Initialization

    /// **Dart Source:** `binding.dart:278-282`
    public override init() {
        super.init()
    }

    open override func initInstances() {
        super.initInstances()
        GestureBinding._instance = self
        platformDispatcher.onPointerDataPacket = { [weak self] packet in
            self?._handlePointerDataPacket(packet)
        }
    }

    // MARK: - Unlocked

    /// Called when events get unlocked. Flushes any queued pointer events.
    ///
    /// **Dart Source:** `binding.dart:293-296`
    open override func unlocked() {
        super.unlocked()
        _flushPointerEventQueue()
    }

    // MARK: - Pointer Event Queue

    /// Pending pointer events waiting to be dispatched.
    ///
    /// **Dart Source:** `binding.dart:298`
    ///
    /// DIFFERENCE FROM DART: Uses `[PointerEvent]` (Swift Array) instead of
    /// `Queue<PointerEvent>`. REASON: Swift does not have a built-in `Queue`
    /// type; Array with `removeFirst()` provides equivalent FIFO semantics.
    private var _pendingPointerEvents: [PointerEvent] = []

    /// Handles incoming pointer data from the engine.
    ///
    /// Converts pointer data to logical pixels so that e.g. the touch slop can be
    /// defined in a device-independent manner.
    ///
    /// **Dart Source:** `binding.dart:300-320`
    /// DIFFERENCE FROM DART: Dart wraps this in a try/catch. In Swift,
    /// `PointerEventConverter.expand` is non-throwing, so no try/catch is needed.
    /// If errors need to be reported in the future, the expand method should be
    /// made throwing.
    private func _handlePointerDataPacket(_ packet: PointerDataPacket) {
        // We convert pointer data to logical pixels so that e.g. the touch slop
        // can be defined in a device-independent manner.
        let events = PointerEventConverter.expand(
            packet.data,
            devicePixelRatioForView: _devicePixelRatioForView
        )
        _pendingPointerEvents.append(contentsOf: events)
        if !locked {
            _flushPointerEventQueue()
        }
    }

    /// Returns the device pixel ratio for the view with the given `viewId`,
    /// or `nil` if no such view exists.
    ///
    /// **Dart Source:** `binding.dart:322-324`
    private func _devicePixelRatioForView(_ viewId: Int) -> Double? {
        return platformDispatcher.view(id: viewId)?.devicePixelRatio
    }

    /// Dispatch a `PointerCancelEvent` for the given pointer soon.
    ///
    /// The pointer event will be dispatched before the next pointer event and
    /// before the end of the microtask but not within this function call.
    ///
    /// **Dart Source:** `binding.dart:330-335`
    ///
    /// DIFFERENCE FROM DART: Uses `DispatchQueue.main.async` instead of
    /// `scheduleMicrotask`. REASON: Swift does not have Dart's microtask queue;
    /// dispatching asynchronously on the main queue is the closest equivalent.
    public func cancelPointer(_ pointer: Int) {
        if _pendingPointerEvents.isEmpty && !locked {
            nonisolated(unsafe) let weakSelf = self
            DispatchQueue.main.async {
                weakSelf._flushPointerEventQueue()
            }
        }
        _pendingPointerEvents.insert(PointerCancelEvent(pointer: pointer), at: 0)
    }

    /// Flushes the pointer event queue by dispatching all pending events.
    ///
    /// **Dart Source:** `binding.dart:337-343`
    private func _flushPointerEventQueue() {
        assert(!locked)

        while !_pendingPointerEvents.isEmpty {
            handlePointerEvent(_pendingPointerEvents.removeFirst())
        }
    }

    // MARK: - Public Services

    /// A router that routes all pointer events received from the engine.
    ///
    /// **Dart Source:** `binding.dart:346`
    public let pointerRouter: PointerRouter = PointerRouter()

    /// The gesture arenas used for disambiguating the meaning of sequences of
    /// pointer events.
    ///
    /// **Dart Source:** `binding.dart:350`
    public let gestureArena: GestureArenaManager = GestureArenaManager()

    /// The resolver used for determining which widget handles a
    /// `PointerSignalEvent`.
    ///
    /// **Dart Source:** `binding.dart:354`
    public let pointerSignalResolver: PointerSignalResolver = PointerSignalResolver()

    // MARK: - Hit Test State

    /// State for all pointers which are currently down.
    ///
    /// This map caches the hit test result done when the pointer goes down
    /// (`PointerDownEvent` and `PointerPanZoomStartEvent`). This hit test result
    /// will be used throughout the entire pointer interaction; that is, the
    /// pointer is seen as pointing to the same place even if it has moved away
    /// until pointer goes up (`PointerUpEvent` and `PointerPanZoomEndEvent`).
    /// This matches the expected gesture interaction with a button, and allows
    /// devices that don't support hovering to perform as few hit tests as
    /// possible.
    ///
    /// On the other hand, hovering requires hit testing on almost every frame.
    /// This is handled in `RendererBinding` and `MouseTracker`, and will ignore
    /// the results cached here.
    ///
    /// **Dart Source:** `binding.dart:370`
    private var _hitTests: [Int: HitTestResult] = [:]

    // MARK: - Pointer Event Handling

    /// Dispatch an event to the targets found by a hit test on its position.
    ///
    /// This method sends the given event to `dispatchEvent` based on event types:
    ///
    ///  * `PointerDownEvent`s and `PointerSignalEvent`s are dispatched to the
    ///    result of a new `hitTestInView`.
    ///  * `PointerUpEvent`s and `PointerMoveEvent`s are dispatched to the result
    ///    of hit test of the preceding `PointerDownEvent`s.
    ///  * `PointerHoverEvent`s, `PointerAddedEvent`s, and `PointerRemovedEvent`s
    ///    are dispatched without a hit test result.
    ///
    /// **Dart Source:** `binding.dart:382-395`
    public func handlePointerEvent(_ event: PointerEvent) {
        assert(!locked)

        if resamplingEnabled {
            _resampler.addOrDispatch(event)
            _resampler.sample(samplingOffset, samplingClock)
            return
        }

        // Stop resampler if resampling is not enabled. This is a no-op if
        // resampling was never enabled.
        _resampler.stop()
        _handlePointerEventImmediately(event)
    }

    /// Immediately processes a pointer event by performing hit testing and
    /// dispatching.
    ///
    /// **Dart Source:** `binding.dart:397-439`
    private func _handlePointerEventImmediately(_ event: PointerEvent) {
        LastPointerKind.note(event)
        var hitTestResult: HitTestResult? = nil
        if event is PointerDownEvent
            || event is PointerSignalEvent
            || event is PointerHoverEvent
            || event is PointerPanZoomStartEvent
        {
            assert(
                !_hitTests.keys.contains(event.pointer),
                "Pointer of \(event) unexpectedly has a HitTestResult associated with it."
            )
            hitTestResult = HitTestResult()
            hitTestInView(result: hitTestResult!, position: event.position, viewId: event.viewId)
            if event is PointerDownEvent || event is PointerPanZoomStartEvent {
                _hitTests[event.pointer] = hitTestResult
            }
            assert({
                if debugPrintHitTestResults {
                    debugPrint("\(event): \(hitTestResult!)", nil)
                }
                return true
            }())
        } else if event is PointerUpEvent
            || event is PointerCancelEvent
            || event is PointerPanZoomEndEvent
        {
            hitTestResult = _hitTests.removeValue(forKey: event.pointer)
        } else if event.down || event is PointerPanZoomUpdateEvent {
            // Because events that occur with the pointer down (like
            // PointerMoveEvents) should be dispatched to the same place that their
            // initial PointerDownEvent was, we want to re-use the path we found when
            // the pointer went down, rather than do hit detection each time we get
            // such an event.
            hitTestResult = _hitTests[event.pointer]
        }
        assert({
            if debugPrintMouseHoverEvents && event is PointerHoverEvent {
                debugPrint("\(event)", nil)
            }
            return true
        }())
        if hitTestResult != nil || event is PointerAddedEvent || event is PointerRemovedEvent {
            _dispatchEvent(event, hitTestResult: hitTestResult)
        }
    }

    // MARK: - HitTestable

    /// Determine which `HitTestTarget` objects are located at a given position in
    /// the specified view.
    ///
    /// **Dart Source:** `binding.dart:443-446`
    open func hitTestInView(result: HitTestResult, position: Offset, viewId: Int) {
        result.add(HitTestEntry(AnyHitTestTarget(self)))
    }

    // NOTE: The deprecated `hitTest(result:position:)` method (Dart lines 448-455)
    // is intentionally omitted per the migration guide's deprecation policy.

    // MARK: - HitTestDispatcher

    /// Dispatch an event to `pointerRouter` and the path of a hit test result.
    ///
    /// This overload satisfies the `HitTestDispatcher` protocol requirement
    /// with a non-optional `HitTestResult`. Delegates to the optional variant.
    ///
    /// **Dart Source:** `binding.dart:467-524`
    public func dispatchEvent(_ event: PointerEvent, result: HitTestResult) {
        _dispatchEvent(event, hitTestResult: result)
    }

    /// Dispatch an event to `pointerRouter` and the path of a hit test result.
    ///
    /// The `event` is routed to `pointerRouter`. If the `hitTestResult` is not
    /// nil, the event is also sent to every `HitTestTarget` in the entries of the
    /// given `HitTestResult`. Any exceptions from the handlers are caught.
    ///
    /// The `hitTestResult` argument may only be nil for `PointerAddedEvent`s or
    /// `PointerRemovedEvent`s.
    ///
    /// **Dart Source:** `binding.dart:467-524`
    ///
    /// DIFFERENCE FROM DART: The Dart source uses `@pragma('vm:notify-debugger-on-exception')`.
    /// This is a Dart VM hint and has no Swift equivalent; it is omitted.
    ///
    /// DIFFERENCE FROM DART: Dart's `PointerRouter.route` and `HitTestTarget.handleEvent`
    /// can throw, and the Dart code wraps calls in try/catch. In Swift, these methods are
    /// non-throwing, so no try/catch is needed. Errors in callbacks will propagate as
    /// runtime faults.
    open func _dispatchEvent(_ event: PointerEvent, hitTestResult: HitTestResult?) {
        assert(!locked)
        // No hit test information implies that this is a PointerAddedEvent or
        // PointerRemovedEvent. These events are specially routed here; other
        // events will be routed through the `handleEvent` below.
        if hitTestResult == nil {
            assert(event is PointerAddedEvent || event is PointerRemovedEvent)
            pointerRouter.route(event)
            return
        }
        for entry in hitTestResult!.path {
            entry.target.handleEvent(event.transformed(entry.transform), entry: entry)
        }
    }

    // MARK: - HitTestTarget

    /// Handles a pointer event by routing it and managing the gesture arena.
    ///
    /// **Dart Source:** `binding.dart:527-536`
    public func handleEvent(_ event: PointerEvent, entry: HitTestEntry<AnyHitTestTarget>) {
        pointerRouter.route(event)
        if event is PointerDownEvent || event is PointerPanZoomStartEvent {
            gestureArena.close(event.pointer)
        } else if event is PointerUpEvent || event is PointerPanZoomEndEvent {
            gestureArena.sweep(event.pointer)
        } else if event is PointerSignalEvent {
            pointerSignalResolver.resolve(event: event)
        }
    }

    // MARK: - Reset

    /// Reset states of `GestureBinding`.
    ///
    /// This clears the hit test records.
    ///
    /// This is typically called between tests.
    ///
    /// **Dart Source:** `binding.dart:544-546`
    public func resetGestureBinding() {
        _hitTests.removeAll()
    }

    // MARK: - Resampling

    /// Called when sample time changes. Triggers resampling or stops it.
    ///
    /// **Dart Source:** `binding.dart:548-556`
    private func _handleSampleTimeChanged() {
        if !locked {
            if resamplingEnabled {
                _resampler.sample(samplingOffset, samplingClock)
            } else {
                _resampler.stop()
            }
        }
    }

    /// Overrides the sampling clock for debugging and testing.
    ///
    /// This value is ignored in non-debug builds.
    ///
    /// **Dart Source:** `binding.dart:562`
    open var debugSamplingClock: SamplingClock? { nil }

    /// Provides access to the current `Date` and `GestureStopwatch` objects for
    /// sampling.
    ///
    /// Overridden by `debugSamplingClock` for debug builds and testing. Using
    /// this object under test will maintain synchronization with `FakeAsync`.
    ///
    /// **Dart Source:** `binding.dart:569-579`
    public var samplingClock: SamplingClock {
        var value = SamplingClock()
        assert({
            if let debugValue = debugSamplingClock {
                value = debugValue
            }
            return true
        }())
        return value
    }

    /// Resampler used to filter incoming pointer events when resampling
    /// is enabled.
    ///
    /// **Dart Source:** `binding.dart:583-587`
    private lazy var _resampler: GestureResampler = GestureResampler(
        _handlePointerEventImmediately,
        _handleSampleTimeChanged,
        _samplingInterval
    )

    /// Enable pointer event resampling for touch devices by setting
    /// this to true.
    ///
    /// Resampling results in smoother touch event processing at the
    /// cost of some added latency. Devices with low frequency sensors
    /// or when the frequency is not a multiple of the display frequency
    /// (e.g., 120Hz input and 90Hz display) benefit from this.
    ///
    /// This is typically set during application initialization but
    /// can be adjusted dynamically in case the application only
    /// wants resampling for some period of time.
    ///
    /// **Dart Source:** `binding.dart:600`
    public var resamplingEnabled: Bool = false

    /// Offset relative to current frame time that should be used for
    /// resampling. The `samplingOffset` is expected to be negative.
    /// Non-negative `samplingOffset` is allowed but will effectively
    /// disable resampling.
    ///
    /// **Dart Source:** `binding.dart:606`
    public var samplingOffset: Duration = _defaultSamplingOffset
}

// MARK: - FlutterErrorDetailsForPointerEventDispatcher

/// Variant of `FlutterErrorDetails` with extra fields for the gesture
/// library's binding's pointer event dispatcher (`GestureBinding.dispatchEvent`).
///
/// **Dart Source:** `binding.dart:611-639`
///
/// DIFFERENCE FROM DART: In Dart, this extends `FlutterErrorDetails`. In Swift,
/// `FlutterErrorDetails` is a `final class` and cannot be subclassed. This class
/// wraps a `FlutterErrorDetails` instance via composition and exposes the
/// additional `event` and `hitTestEntry` properties.
public final class FlutterErrorDetailsForPointerEventDispatcher {

    /// Creates a `FlutterErrorDetailsForPointerEventDispatcher` with the given
    /// arguments setting the object's properties.
    ///
    /// The gesture library calls this constructor when catching an exception
    /// that will subsequently be reported using `FlutterError.onError`.
    ///
    /// **Dart Source:** `binding.dart:617-626`
    public init(
        exception: Any,
        stack: String? = nil,
        library: String? = nil,
        context: (any DiagnosticsNodeProtocol)? = nil,
        event: PointerEvent? = nil,
        hitTestEntry: HitTestEntry<AnyHitTestTarget>? = nil,
        informationCollector: InformationCollector? = nil,
        silent: Bool = false
    ) {
        self.details = FlutterErrorDetails(
            exception: exception,
            stack: stack,
            library: library,
            context: context,
            informationCollector: informationCollector,
            silent: silent
        )
        self.event = event
        self.hitTestEntry = hitTestEntry
    }

    /// The underlying `FlutterErrorDetails`.
    public let details: FlutterErrorDetails

    /// The pointer event that was being routed when the exception was raised.
    ///
    /// **Dart Source:** `binding.dart:629`
    public let event: PointerEvent?

    /// The hit test result entry for the object whose handleEvent method threw
    /// the exception. May be nil if no hit test entry is associated with the
    /// event (e.g. `PointerHoverEvent`s, `PointerAddedEvent`s, and
    /// `PointerRemovedEvent`s).
    ///
    /// The target object itself is given by the `HitTestEntry.target` property of
    /// the hitTestEntry object.
    ///
    /// **Dart Source:** `binding.dart:638`
    public let hitTestEntry: HitTestEntry<AnyHitTestTarget>?
}
