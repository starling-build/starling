// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import FlutterSwiftBridge
import Foundation

// =============================================================================
// MARK: - MouseAnnotation

/// An identity-hashed box around any `MouseTrackerAnnotationProtocol`, so
/// the tracker's dictionaries can be keyed by the RENDER OBJECTS that carry
/// annotations (`RenderMouseRegion`), not only by the plain
/// `MouseTrackerAnnotation` class. The two grew up separately: the tracker
/// hit-tested for the class while every MouseRegion in every widget tree
/// conformed to the protocol -- so the cast always failed, the annotation
/// set was always empty, and enter/exit never fired anywhere. The
/// forwarders keep the dispatch sites reading exactly as Dart's do.
public struct MouseAnnotation: Hashable {
    public let object: any MouseTrackerAnnotationProtocol

    public init(_ object: any MouseTrackerAnnotationProtocol) {
        self.object = object
    }

    public static func == (lhs: MouseAnnotation, rhs: MouseAnnotation) -> Bool {
        lhs.object === rhs.object
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(object))
    }

    var cursor: MouseCursor { object.cursor }
    var validForMouseTracker: Bool { object.validForMouseTracker }
    var onEnter: ((PointerEnterEvent) -> Void)? { object.onEnter }
    var onExit: ((PointerExitEvent) -> Void)? { object.onExit }
}

// MARK: - Stub: MouseTrackerAnnotation
// =============================================================================

/// Placeholder for `MouseTrackerAnnotation` from `services/mouse_tracking.dart`.
///
/// In Dart, `MouseTrackerAnnotation` is a class used to annotate regions that
/// are interested in mouse movements. It is used as a dictionary key with
/// reference (identity) equality. The full implementation will be provided
/// when `mouse_tracking.dart` is migrated.
///
/// **Dart Source:** mouse_tracking.dart:49
///
/// - TODO: Replace with full `MouseTrackerAnnotation` migration from
///   `services/mouse_tracking.dart`.
public class MouseTrackerAnnotation: Hashable, MouseTrackerAnnotationProtocol {

    /// Creates an immutable `MouseTrackerAnnotation`.
    ///
    /// **Dart Source:** mouse_tracking.dart:51
    public init(
        onEnter: ((PointerEnterEvent) -> Void)? = nil,
        onExit: ((PointerExitEvent) -> Void)? = nil,
        cursor: MouseCursor = MouseCursor.defer_,
        validForMouseTracker: Bool = true
    ) {
        self.onEnter = onEnter
        self.onExit = onExit
        self.cursor = cursor
        self.validForMouseTracker = validForMouseTracker
    }

    /// Triggered when a mouse pointer has entered the region and
    /// `validForMouseTracker` is true.
    ///
    /// **Dart Source:** mouse_tracking.dart:70
    public let onEnter: ((PointerEnterEvent) -> Void)?

    /// Triggered when a mouse pointer has exited the region and
    /// `validForMouseTracker` is true.
    ///
    /// **Dart Source:** mouse_tracking.dart:85
    public let onExit: ((PointerExitEvent) -> Void)?

    /// The mouse cursor for mouse pointers that are hovering over the region.
    ///
    /// **Dart Source:** mouse_tracking.dart:99
    public let cursor: MouseCursor

    /// Whether this is included when `MouseTracker` collects the list of
    /// annotations.
    ///
    /// **Dart Source:** mouse_tracking.dart:111
    public let validForMouseTracker: Bool

    public static func == (lhs: MouseTrackerAnnotation, rhs: MouseTrackerAnnotation) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// =============================================================================
// MARK: - Stub: MouseCursor
// =============================================================================

/// Placeholder for `MouseCursor` from `services/mouse_cursor.dart`.
///
/// In Dart, `MouseCursor` is an abstract class representing a mouse cursor.
/// The full implementation will be provided when `mouse_cursor.dart` is
/// migrated.
///
/// **Dart Source:** mouse_cursor.dart:188
///
/// - TODO: Replace with full `MouseCursor` migration from
///   `services/mouse_cursor.dart`.
public class MouseCursor: @unchecked Sendable {
    public init() {}

    /// A special cursor that defers the choice of cursor to the next region
    /// behind it in hit-test order.
    ///
    /// **Dart Source:** mouse_cursor.dart:251
    public static let defer_ = MouseCursor()
}

// =============================================================================
// MARK: - Stub: SystemMouseCursors
// =============================================================================

/// Placeholder for `SystemMouseCursors` from `services/mouse_cursor.dart`.
///
/// **Dart Source:** mouse_cursor.dart:333
///
/// - TODO: Replace with full `SystemMouseCursors` migration.
public enum SystemMouseCursors {
    /// The `basic` system cursor (default arrow).
    ///
    /// **Dart Source:** mouse_cursor.dart:343
    public static let basic = MouseCursor()
}

// =============================================================================
// MARK: - Stub: MouseCursorManager
// =============================================================================

/// Placeholder for `MouseCursorManager` from `services/mouse_cursor.dart`.
///
/// In Dart, `MouseCursorManager` manages cursor state for pointer devices.
/// The full implementation will be provided when `mouse_cursor.dart` is
/// migrated.
///
/// **Dart Source:** mouse_cursor.dart:21
///
/// - TODO: Replace with full `MouseCursorManager` migration from
///   `services/mouse_cursor.dart`.
public class MouseCursorManager {
    /// Creates a `MouseCursorManager` with the given fallback cursor.
    ///
    /// **Dart Source:** mouse_cursor.dart:26
    public init(_ fallbackMouseCursor: MouseCursor) {
        self.fallbackMouseCursor = fallbackMouseCursor
    }

    /// The mouse cursor to use if all cursor candidates choose to defer.
    ///
    /// **Dart Source:** mouse_cursor.dart:33
    public let fallbackMouseCursor: MouseCursor

    /// Returns the active mouse cursor for a device.
    ///
    /// Only valid when asserts are enabled. In release builds, always returns
    /// nil.
    ///
    /// **Dart Source:** mouse_cursor.dart:42
    public func debugDeviceActiveCursor(_ device: Int) -> MouseCursor? {
        // Stub: full implementation depends on MouseCursorSession
        return nil
    }

    /// Handles the changes that cause a pointer device to have a new list of
    /// mouse cursor candidates.
    ///
    /// **Dart Source:** mouse_cursor.dart:61
    public func handleDeviceCursorUpdate(
        _ device: Int,
        _ triggeringEvent: PointerEvent?,
        _ cursorCandidates: [MouseCursor]
    ) {
        // Stub: full implementation depends on MouseCursorSession
    }
}

// =============================================================================
// MARK: - MouseTrackerHitTest
// =============================================================================

/// Signature for hit testing at the given offset for the specified view.
///
/// It is used by the `MouseTracker` to fetch annotations for the mouse
/// position.
///
/// **Dart Source:** mouse_tracker.dart:22
public typealias MouseTrackerHitTest = (_ offset: Offset, _ viewId: Int) -> HitTestResult

// =============================================================================
// MARK: - MouseState
// =============================================================================

/// Various states of a connected mouse device used by `MouseTracker`.
///
/// This class tracks the annotations and latest event for a single mouse
/// device. It is internal to the mouse tracking system.
///
/// **Dart Source:** mouse_tracker.dart:25
fileprivate class MouseState {

    /// Creates a mouse state with the given initial event.
    ///
    /// **Dart Source:** mouse_tracker.dart:26
    init(initialEvent: PointerEvent) {
        _latestEvent = initialEvent
    }

    // MARK: - Annotations

    /// The list of annotations that contains this device.
    ///
    /// **Dart Source:** mouse_tracker.dart:29
    var annotations: [MouseAnnotation: Matrix4] {
        return _annotations
    }

    /// **Dart Source:** mouse_tracker.dart:30
    private var _annotations: [MouseAnnotation: Matrix4] = [:]

    /// Replaces the current annotations with the given value and returns the
    /// previous annotations.
    ///
    /// **Dart Source:** mouse_tracker.dart:32
    func replaceAnnotations(_ value: [MouseAnnotation: Matrix4]) -> [MouseAnnotation: Matrix4] {
        let previous = _annotations
        _annotations = value
        return previous
    }

    // MARK: - Latest Event

    /// The most recently processed mouse event observed from this device.
    ///
    /// **Dart Source:** mouse_tracker.dart:41
    var latestEvent: PointerEvent {
        return _latestEvent
    }

    /// **Dart Source:** mouse_tracker.dart:42
    private var _latestEvent: PointerEvent

    /// Replaces the latest event with the given value and returns the
    /// previous event.
    ///
    /// Asserts that the new event's device matches the current event's device.
    ///
    /// **Dart Source:** mouse_tracker.dart:44
    func replaceLatestEvent(_ value: PointerEvent) -> PointerEvent {
        assert(value.device == _latestEvent.device)
        let previous = _latestEvent
        _latestEvent = value
        return previous
    }

    // MARK: - Device

    /// The device identifier for this mouse state.
    ///
    /// **Dart Source:** mouse_tracker.dart:51
    var device: Int {
        return latestEvent.device
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** mouse_tracker.dart:53
    var description: String {
        let describeLatestEvent = "latestEvent: \(describeIdentity(latestEvent))"
        let describeAnnotationsStr = "annotations: [list of \(annotations.count)]"
        return "\(describeIdentity(self))(\(describeLatestEvent), \(describeAnnotationsStr))"
    }
}

// =============================================================================
// MARK: - MouseTrackerUpdateDetails
// =============================================================================

/// The information in `MouseTracker._handleDeviceUpdate` to provide the details
/// of an update of a mouse device.
///
/// This struct contains the information needed to handle the update that might
/// change the state of a mouse device, or the `MouseTrackerAnnotation`s that
/// the mouse device is hovering.
///
/// **Dart Source:** mouse_tracker.dart:67
fileprivate struct MouseTrackerUpdateDetails {

    // MARK: - Private Initializer

    /// Private memberwise initializer used by the factory methods.
    private init(
        lastAnnotations: [MouseAnnotation: Matrix4],
        nextAnnotations: [MouseAnnotation: Matrix4],
        previousEvent: PointerEvent?,
        triggeringEvent: PointerEvent?
    ) {
        self.lastAnnotations = lastAnnotations
        self.nextAnnotations = nextAnnotations
        self.previousEvent = previousEvent
        self.triggeringEvent = triggeringEvent
    }

    // MARK: - Factory Initializers

    /// When device update is triggered by a new frame.
    ///
    /// All parameters are required.
    ///
    /// **Dart Source:** mouse_tracker.dart:72
    static func byNewFrame(
        lastAnnotations: [MouseAnnotation: Matrix4],
        nextAnnotations: [MouseAnnotation: Matrix4],
        previousEvent: PointerEvent
    ) -> MouseTrackerUpdateDetails {
        return MouseTrackerUpdateDetails(
            lastAnnotations: lastAnnotations,
            nextAnnotations: nextAnnotations,
            previousEvent: previousEvent,
            triggeringEvent: nil
        )
    }

    /// When device update is triggered by a pointer event.
    ///
    /// The `lastAnnotations`, `nextAnnotations`, and `triggeringEvent` are
    /// required.
    ///
    /// **Dart Source:** mouse_tracker.dart:82
    static func byPointerEvent(
        lastAnnotations: [MouseAnnotation: Matrix4],
        nextAnnotations: [MouseAnnotation: Matrix4],
        previousEvent: PointerEvent? = nil,
        triggeringEvent: PointerEvent
    ) -> MouseTrackerUpdateDetails {
        return MouseTrackerUpdateDetails(
            lastAnnotations: lastAnnotations,
            nextAnnotations: nextAnnotations,
            previousEvent: previousEvent,
            triggeringEvent: triggeringEvent
        )
    }

    // MARK: - Properties

    /// The annotations that the device is hovering before the update.
    ///
    /// It is never nil.
    ///
    /// **Dart Source:** mouse_tracker.dart:92
    let lastAnnotations: [MouseAnnotation: Matrix4]

    /// The annotations that the device is hovering after the update.
    ///
    /// It is never nil.
    ///
    /// **Dart Source:** mouse_tracker.dart:97
    let nextAnnotations: [MouseAnnotation: Matrix4]

    /// The last event that the device observed before the update.
    ///
    /// If the update is triggered by a frame, the `previousEvent` is never nil,
    /// since the pointer must have been added before.
    ///
    /// If the update is triggered by a pointer event, the `previousEvent` is not
    /// nil except for cases where the event is the first event observed by the
    /// pointer (which is not necessarily a `PointerAddedEvent`).
    ///
    /// **Dart Source:** mouse_tracker.dart:107
    let previousEvent: PointerEvent?

    /// The event that triggered this update.
    ///
    /// It is non-nil if and only if the update is triggered by a pointer event.
    ///
    /// **Dart Source:** mouse_tracker.dart:112
    let triggeringEvent: PointerEvent?

    // MARK: - Computed Properties

    /// The pointing device of this update.
    ///
    /// **Dart Source:** mouse_tracker.dart:115
    var device: Int {
        let result = (previousEvent ?? triggeringEvent)!.device
        return result
    }

    /// The last event that the device observed after the update.
    ///
    /// The `latestEvent` is never nil.
    ///
    /// **Dart Source:** mouse_tracker.dart:123
    var latestEvent: PointerEvent {
        let result = triggeringEvent ?? previousEvent!
        return result
    }
}

// =============================================================================
// MARK: - MouseTracker
// =============================================================================

/// Tracks the relationship between mouse devices and annotations, and
/// triggers mouse-related callbacks and cursor changes.
///
/// The `MouseTracker` tracks the state of connected mouse devices and the
/// `MouseTrackerAnnotation`s that each device is hovering over. It dispatches
/// `PointerEnterEvent` and `PointerExitEvent` as annotations are entered and
/// exited, and manages mouse cursor updates via `MouseCursorManager`.
///
/// This class extends `ChangeNotifier` and notifies listeners when the
/// `mouseIsConnected` value changes (i.e., when the first mouse connects or
/// the last mouse disconnects).
///
/// **Dart Source:** mouse_tracker.dart:160
public class MouseTracker: ChangeNotifier {

    // MARK: - Initializer

    /// Creates a mouse tracker.
    ///
    /// The `hitTestInView` callback is used to find the render objects at a
    /// given position in a specific view. It is typically provided by the
    /// `RendererBinding`.
    ///
    /// **Dart Source:** mouse_tracker.dart:166
    public init(_ hitTestInView: @escaping MouseTrackerHitTest) {
        _hitTestInView = hitTestInView
    }

    // MARK: - Private State

    /// The hit test callback provided at construction time.
    ///
    /// **Dart Source:** mouse_tracker.dart:168
    private let _hitTestInView: MouseTrackerHitTest

    /// Manages mouse cursor state for pointer devices.
    ///
    /// **Dart Source:** mouse_tracker.dart:170
    private let _mouseCursorMixin = MouseCursorManager(SystemMouseCursors.basic)

    /// Tracks the state of connected mouse devices.
    ///
    /// It is the source of truth for the list of connected mouse devices, and
    /// consists of two parts:
    ///
    ///  - The mouse devices that are connected.
    ///  - In which annotations each device is contained.
    ///
    /// **Dart Source:** mouse_tracker.dart:179
    private var _mouseStates: [Int: MouseState] = [:]

    /// Debug flag set during device updates.
    ///
    /// **Dart Source:** mouse_tracker.dart:193
    private var _debugDuringDeviceUpdate = false

    // MARK: - Public Properties

    /// Whether or not at least one mouse is connected and has produced events.
    ///
    /// **Dart Source:** mouse_tracker.dart:285
    public var mouseIsConnected: Bool {
        return !_mouseStates.isEmpty
    }

    // MARK: - Public Methods

    /// Perform a device update for one device according to the given new event.
    ///
    /// The `updateWithEvent` is typically called by `RendererBinding` during the
    /// handler of a pointer event. All pointer events should call this method,
    /// and let `MouseTracker` filter which to react to.
    ///
    /// The `hitTestResult` serves as an optional optimization, and is the hit
    /// test result already performed by `RendererBinding` for other gestures. It
    /// can be nil, but when it's not nil, it should be identical to the result
    /// from directly calling `hitTestInView` given in the constructor (which
    /// means that it should not use the cached result for `PointerMoveEvent`).
    ///
    /// The `updateWithEvent` is one of the two ways of updating mouse
    /// states, the other one being `updateAllDevices`.
    ///
    /// **Dart Source:** mouse_tracker.dart:301
    public func updateWithEvent(_ event: PointerEvent, hitTestResult: HitTestResult?) {
        if event.kind != .mouse && event.kind != .stylus {
            return
        }
        if event is PointerSignalEvent {
            return
        }
        let result: HitTestResult
        if event is PointerRemovedEvent {
            result = HitTestResult()
        } else {
            result = hitTestResult ?? _hitTestInView(event.position, event.viewId)
        }
        let device = event.device
        let existingState = _mouseStates[device]
        if !MouseTracker._shouldMarkStateDirty(existingState, event: event) {
            return
        }

        _monitorMouseConnection {
            self._deviceUpdatePhase {
                // Update mouseState to the latest devices that have not been removed,
                // so that mouseIsConnected, which is decided by _mouseStates, is
                // correct during the callbacks.
                if existingState == nil {
                    if event is PointerRemovedEvent {
                        return
                    }
                    self._mouseStates[device] = MouseState(initialEvent: event)
                } else {
                    assert(!(event is PointerAddedEvent))
                    if event is PointerRemovedEvent {
                        self._mouseStates.removeValue(forKey: event.device)
                    }
                }
                let targetState = self._mouseStates[device] ?? existingState!

                let lastEvent = targetState.replaceLatestEvent(event)
                let nextAnnotations: [MouseAnnotation: Matrix4]
                if event is PointerRemovedEvent {
                    nextAnnotations = [:]
                } else {
                    nextAnnotations = self._hitTestInViewResultToAnnotations(result)
                }
                let lastAnnotations = targetState.replaceAnnotations(nextAnnotations)

                self._handleDeviceUpdate(
                    MouseTrackerUpdateDetails.byPointerEvent(
                        lastAnnotations: lastAnnotations,
                        nextAnnotations: nextAnnotations,
                        previousEvent: lastEvent,
                        triggeringEvent: event
                    )
                )
            }
        }
    }

    /// Perform a device update for all detected devices.
    ///
    /// The `updateAllDevices` is typically called during the post frame phase,
    /// indicating a frame has passed and all objects have potentially moved. For
    /// each connected device, the `updateAllDevices` will make a hit test on the
    /// device's last seen position, and check if necessary changes need to be
    /// made.
    ///
    /// The `updateAllDevices` is one of the two ways of updating mouse
    /// states, the other one being `updateWithEvent`.
    ///
    /// **Dart Source:** mouse_tracker.dart:366
    public func updateAllDevices() {
        _deviceUpdatePhase {
            for dirtyState in self._mouseStates.values {
                let lastEvent = dirtyState.latestEvent
                let nextAnnotations = self._findAnnotations(dirtyState)
                let lastAnnotations = dirtyState.replaceAnnotations(nextAnnotations)

                self._handleDeviceUpdate(
                    MouseTrackerUpdateDetails.byNewFrame(
                        lastAnnotations: lastAnnotations,
                        nextAnnotations: nextAnnotations,
                        previousEvent: lastEvent
                    )
                )
            }
        }
    }

    /// Returns the active mouse cursor for a device.
    ///
    /// The return value is the last `MouseCursor` activated onto this device,
    /// even if the activation failed.
    ///
    /// This function is only active when asserts are enabled. In release builds,
    /// it always returns nil.
    ///
    /// **Dart Source:** mouse_tracker.dart:394
    public func debugDeviceActiveCursor(_ device: Int) -> MouseCursor? {
        return _mouseCursorMixin.debugDeviceActiveCursor(device)
    }

    // MARK: - Private Helper Methods

    /// Wraps any procedure that might change `mouseIsConnected`.
    ///
    /// This method records `mouseIsConnected`, runs `task`, and calls
    /// `notifyListeners` at the end if the `mouseIsConnected` has changed.
    ///
    /// **Dart Source:** mouse_tracker.dart:185
    private func _monitorMouseConnection(_ task: () -> Void) {
        let mouseWasConnected = mouseIsConnected
        task()
        if mouseWasConnected != mouseIsConnected {
            notifyListeners()
        }
    }

    /// Wraps any procedure that might call `_handleDeviceUpdate`.
    ///
    /// In debug mode, this method uses `_debugDuringDeviceUpdate` to prevent
    /// `_deviceUpdatePhase` being recursively called.
    ///
    /// **Dart Source:** mouse_tracker.dart:198
    private func _deviceUpdatePhase(_ task: () -> Void) {
        assert(!_debugDuringDeviceUpdate)
        assert({
            _debugDuringDeviceUpdate = true
            return true
        }())
        task()
        assert({
            _debugDuringDeviceUpdate = false
            return true
        }())
    }

    /// Whether an observed event might update a device.
    ///
    /// Returns `false` for `PointerSignalEvent` (does not affect hover).
    /// Returns `true` for `PointerAddedEvent`, `PointerRemovedEvent`, or
    /// when the position has changed.
    ///
    /// **Dart Source:** mouse_tracker.dart:212
    private static func _shouldMarkStateDirty(_ state: MouseState?, event: PointerEvent) -> Bool {
        guard let state = state else {
            return true
        }
        let lastEvent = state.latestEvent
        assert(event.device == lastEvent.device)
        // An Added can only follow a Removed, and a Removed can only be followed
        // by an Added.
        assert((event is PointerAddedEvent) == (lastEvent is PointerRemovedEvent))

        // Ignore events that are unrelated to mouse tracking.
        if event is PointerSignalEvent {
            return false
        }
        return lastEvent is PointerAddedEvent
            || event is PointerRemovedEvent
            || lastEvent.position != event.position
    }

    /// Extracts `MouseTrackerAnnotation`s from a hit test result, along with
    /// their respective global transform matrices.
    ///
    /// **Dart Source:** mouse_tracker.dart:231
    private func _hitTestInViewResultToAnnotations(_ result: HitTestResult) -> [MouseAnnotation: Matrix4] {
        var annotations: [MouseAnnotation: Matrix4] = [:]
        for entry in result.path {
            // Hit path targets arrive boxed in AnyHitTestTarget -- look
            // through the box, or the cast below can never succeed.
            let target = (entry.target as? AnyHitTestTarget)?.base ?? entry.target
            if let annotation = target as? (any MouseTrackerAnnotationProtocol) {
                annotations[MouseAnnotation(annotation)] = entry.transform!
            }
        }
        return annotations
    }

    /// Finds the annotations that are hovered by the device of the `state`,
    /// and their respective global transform matrices.
    ///
    /// If the device is not connected or not a mouse, an empty dictionary is
    /// returned without calling `hitTest`.
    ///
    /// **Dart Source:** mouse_tracker.dart:247
    private func _findAnnotations(_ state: MouseState) -> [MouseAnnotation: Matrix4] {
        let globalPosition = state.latestEvent.position
        let device = state.device
        let viewId = state.latestEvent.viewId
        if _mouseStates[device] == nil {
            return [:]
        }

        return _hitTestInViewResultToAnnotations(_hitTestInView(globalPosition, viewId))
    }

    /// A callback that is called on the update of a device.
    ///
    /// An event (not necessarily a pointer event) that might change the
    /// relationship between mouse devices and `MouseTrackerAnnotation`s is
    /// called a _device update_. This method should be called at each such
    /// update.
    ///
    /// The update can be caused by two kinds of triggers:
    ///
    ///  - Triggered by the addition, movement, or removal of a pointer. Such
    ///    calls occur during the handler of the event, indicated by
    ///    `details.triggeringEvent` being non-nil.
    ///  - Triggered by the appearance, movement, or disappearance of an
    ///    annotation. Such calls occur after each new frame, during the
    ///    post-frame callbacks, indicated by `details.triggeringEvent` being nil.
    ///
    /// Calls of this method must be wrapped in `_deviceUpdatePhase`.
    ///
    /// **Dart Source:** mouse_tracker.dart:274
    private func _handleDeviceUpdate(_ details: MouseTrackerUpdateDetails) {
        assert(_debugDuringDeviceUpdate)
        MouseTracker._handleDeviceUpdateMouseEvents(details)
        _mouseCursorMixin.handleDeviceCursorUpdate(
            details.device,
            details.triggeringEvent,
            Array(details.nextAnnotations.keys.map { $0.cursor })
        )
    }

    /// Handles device update and dispatches mouse event callbacks.
    ///
    /// Sends exit events to annotations that were in `lastAnnotations` but not
    /// in `nextAnnotations`, in hit-test order. Sends enter events to
    /// annotations that are in `nextAnnotations` but not in `lastAnnotations`,
    /// in reverse hit-test order.
    ///
    /// **Dart Source:** mouse_tracker.dart:399
    private static func _handleDeviceUpdateMouseEvents(_ details: MouseTrackerUpdateDetails) {
        let latestEvent = details.latestEvent

        let lastAnnotations = details.lastAnnotations
        let nextAnnotations = details.nextAnnotations

        // Order is important for mouse event callbacks. The
        // _hitTestInViewResultToAnnotations returns annotations in the visual order
        // from front to back, called the "hit-test order". The algorithm here is
        // explained in https://github.com/flutter/flutter/issues/41420

        // Send exit events to annotations that are in last but not in next, in
        // hit-test order.
        let baseExitEvent = PointerExitEvent.fromMouseEvent(latestEvent)
        for (annotation, _) in lastAnnotations {
            if annotation.validForMouseTracker && nextAnnotations[annotation] == nil {
                annotation.onExit?(baseExitEvent.transformed(lastAnnotations[annotation]))
            }
        }

        // Send enter events to annotations that are not in last but in next, in
        // reverse hit-test order.
        let enteringAnnotations = nextAnnotations.keys.filter { annotation in
            lastAnnotations[annotation] == nil
        }
        let baseEnterEvent = PointerEnterEvent.fromMouseEvent(latestEvent)
        for annotation in enteringAnnotations.reversed() {
            if annotation.validForMouseTracker {
                annotation.onEnter?(baseEnterEvent.transformed(nextAnnotations[annotation]))
            }
        }
    }
}
