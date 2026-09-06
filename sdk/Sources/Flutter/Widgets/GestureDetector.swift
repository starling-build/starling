// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// GestureDetector widget — detects gestures described by the given
/// gesture recognizer factories, and RawGestureDetector which provides
/// the low-level plumbing.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/gesture_detector.dart`

import FlutterSwiftBridge

// MARK: - GestureRecognizerFactory

/// Factory for creating gesture recognizers that delegate to callbacks.
///
/// Used by `RawGestureDetector` to create and update gesture recognizers.
///
/// **Dart Source:** `gesture_detector.dart:27-56`
public class GestureRecognizerFactory<T: GestureRecognizer> {
    /// Creates a `GestureRecognizerFactory` with the given callbacks.
    public init(
        constructor: @escaping () -> T,
        initializer: @escaping (T) -> Void
    ) {
        self._constructor = constructor
        self._initializer = initializer
    }

    private let _constructor: () -> T
    private let _initializer: (T) -> Void

    /// Creates a new instance of the gesture recognizer.
    public func constructor() -> T {
        return _constructor()
    }

    /// Configures the gesture recognizer with callbacks and settings.
    public func initializer(_ recognizer: T) {
        _initializer(recognizer)
    }
}

// MARK: - GestureRecognizerFactoryWithHandlers (type-erased wrapper)

/// Type-erased wrapper around `GestureRecognizerFactory` so that
/// `RawGestureDetector` can store a heterogeneous dictionary of factories.
public class AnyGestureRecognizerFactory {
    private let _construct: () -> GestureRecognizer
    private let _initialize: (GestureRecognizer) -> Void
    fileprivate let _type: ObjectIdentifier

    public init<T: GestureRecognizer>(_ factory: GestureRecognizerFactory<T>) {
        self._type = ObjectIdentifier(T.self)
        self._construct = { factory.constructor() }
        self._initialize = { recognizer in
            factory.initializer(recognizer as! T)
        }
    }

    func construct() -> GestureRecognizer {
        return _construct()
    }

    func initialize(_ recognizer: GestureRecognizer) {
        _initialize(recognizer)
    }
}

// MARK: - RawGestureDetector

/// A widget that detects gestures described by the given gesture factories.
///
/// For common gestures, use `GestureDetector`. `RawGestureDetector`
/// is useful primarily for advanced cases where direct control over
/// recognizer lifecycle is needed.
///
/// **Dart Source:** `gesture_detector.dart:334-580`
public class RawGestureDetector: StatefulWidget {
    /// The gesture factories to use for recognizing gestures.
    ///
    /// Each key in the dictionary is the `ObjectIdentifier` of the recognizer
    /// type, and each value is the factory that creates/configures that
    /// recognizer.
    public let gestures: [ObjectIdentifier: AnyGestureRecognizerFactory]

    /// How this gesture detector should behave during hit testing.
    public let behavior: HitTestBehavior?

    /// Whether to exclude the gestures from semantics.
    public let excludeFromSemantics: Bool

    /// The child widget.
    public let child: Widget?

    public init(
        key: (any Key)? = nil,
        gestures: [ObjectIdentifier: AnyGestureRecognizerFactory] = [:],
        behavior: HitTestBehavior? = nil,
        excludeFromSemantics: Bool = false,
        child: Widget? = nil
    ) {
        self.gestures = gestures
        self.behavior = behavior
        self.excludeFromSemantics = excludeFromSemantics
        self.child = child
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return RawGestureDetectorState()
    }
}

// MARK: - RawGestureDetectorState

/// The state for a `RawGestureDetector`.
///
/// Manages the lifecycle of gesture recognizers: creation, updating callbacks,
/// routing pointer-down events, and disposal.
///
/// **Dart Source:** `gesture_detector.dart:407-580`
public class RawGestureDetectorState: State<StatefulWidget> {
    /// Active recognizers keyed by their type's `ObjectIdentifier`.
    private var _recognizers: [ObjectIdentifier: GestureRecognizer] = [:]

    private var rawGestureDetector: RawGestureDetector {
        return widget as! RawGestureDetector
    }

    public override func initState() {
        super.initState()
        _syncAll(rawGestureDetector.gestures)
    }

    public override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        _syncAll(rawGestureDetector.gestures)
    }

    /// Dispose of all recognizers when the state is removed.
    public override func dispose() {
        for recognizer in _recognizers.values {
            recognizer.dispose()
        }
        _recognizers.removeAll()
        super.dispose()
    }

    /// Synchronize the active recognizers with the given factory map.
    ///
    /// - Reuses existing recognizers when the type matches.
    /// - Creates new recognizers for new types.
    /// - Disposes recognizers whose type is no longer present.
    ///
    /// **Dart Source:** `gesture_detector.dart:435-456`
    private func _syncAll(_ gestures: [ObjectIdentifier: AnyGestureRecognizerFactory]) {
        let oldRecognizers = _recognizers
        _recognizers = [:]

        for (type, factory) in gestures {
            if let existing = oldRecognizers[type] {
                // Reuse existing recognizer, just re-initialize callbacks.
                factory.initialize(existing)
                _recognizers[type] = existing
            } else {
                // Create a new recognizer.
                let recognizer = factory.construct()
                factory.initialize(recognizer)
                _recognizers[type] = recognizer
            }
        }

        // Dispose recognizers that are no longer needed.
        for (type, recognizer) in oldRecognizers {
            if _recognizers[type] == nil {
                recognizer.dispose()
            }
        }
    }

    /// Called when a pointer-down event occurs within this widget's bounds.
    ///
    /// Adds the event to each active recognizer, which enters them into the
    /// gesture arena.
    ///
    /// **Dart Source:** `gesture_detector.dart:467-473`
    private func _handlePointerDown(_ event: PointerDownEvent) {
        for recognizer in _recognizers.values {
            recognizer.addPointer(event)
        }
    }

    /// Called when a pointer-pan-zoom-start event occurs within this widget's bounds.
    ///
    /// **Dart Source:** `gesture_detector.dart:475-481`
    private func _handlePointerPanZoomStart(_ event: PointerPanZoomStartEvent) {
        for recognizer in _recognizers.values {
            recognizer.addPointerPanZoom(event)
        }
    }

    public override func build(_ context: any BuildContext) -> Widget {
        var result: Widget
        if let child = rawGestureDetector.child {
            result = child
        } else {
            // Even with no child we need something to attach the listener to.
            result = SizedBox(width: nil, height: nil)
        }

        return Listener(
            onPointerDown: _handlePointerDown,
            onPointerPanZoomStart: _handlePointerPanZoomStart,
            behavior: rawGestureDetector.behavior ?? .deferToChild,
            child: result
        )
    }
}

// MARK: - GestureDetector

/// A widget that detects gestures.
///
/// Attempts to recognize gestures that correspond to its non-nil callbacks.
///
/// If this widget has a child, it defers to that child for its sizing behavior.
/// If it does not have a child, it grows to fit the parent instead.
///
/// By default a `GestureDetector` with an invisible child ignores touches;
/// this behavior can be controlled with `behavior`.
///
/// `GestureDetector` also listens for accessibility events and maps
/// them to the callbacks. To ignore accessibility events, set
/// `excludeFromSemantics` to true.
///
/// **Dart Source:** `gesture_detector.dart:58-330`
public class GestureDetector: StatelessWidget {

    // MARK: - Tap callbacks

    /// A pointer that might cause a tap with a primary button has contacted the
    /// screen at a particular location.
    public let onTapDown: ((TapDownDetails) -> Void)?

    /// A pointer that will trigger a tap with a primary button has stopped
    /// contacting the screen at a particular location.
    public let onTapUp: ((TapUpDetails) -> Void)?

    /// A tap with a primary button has occurred.
    public let onTap: (() -> Void)?

    /// The pointer that previously triggered `onTapDown` will not end up
    /// causing a tap.
    public let onTapCancel: (() -> Void)?

    // MARK: - Secondary tap callbacks

    /// A tap with a secondary button has occurred.
    public let onSecondaryTap: (() -> Void)?

    /// A pointer that might cause a tap with a secondary button has contacted the
    /// screen at a particular location.
    public let onSecondaryTapDown: ((TapDownDetails) -> Void)?

    /// A pointer that will trigger a tap with a secondary button has stopped
    /// contacting the screen at a particular location.
    public let onSecondaryTapUp: ((TapUpDetails) -> Void)?

    /// The pointer that previously triggered `onSecondaryTapDown` will not end up
    /// causing a tap.
    public let onSecondaryTapCancel: (() -> Void)?

    // MARK: - Tertiary tap callbacks

    /// A pointer that might cause a tap with a tertiary button has contacted the
    /// screen at a particular location.
    public let onTertiaryTapDown: ((TapDownDetails) -> Void)?

    /// A pointer that will trigger a tap with a tertiary button has stopped
    /// contacting the screen at a particular location.
    public let onTertiaryTapUp: ((TapUpDetails) -> Void)?

    /// The pointer that previously triggered `onTertiaryTapDown` will not end up
    /// causing a tap.
    public let onTertiaryTapCancel: (() -> Void)?

    // MARK: - Double tap callbacks

    /// The user has tapped the screen with a primary button at the same location
    /// twice in quick succession.
    public let onDoubleTap: (() -> Void)?

    /// A pointer that might cause a double tap has contacted the screen at a
    /// particular location.
    public let onDoubleTapDown: ((TapDownDetails) -> Void)?

    /// The pointer that previously triggered `onDoubleTapDown` will not end up
    /// causing a double tap.
    public let onDoubleTapCancel: (() -> Void)?

    // MARK: - Long press callbacks

    /// Called when a pointer has contacted the screen at a particular location
    /// with a primary button, which might be the start of a long-press.
    public let onLongPressDown: ((LongPressDownDetails) -> Void)?

    /// A pointer that previously triggered `onLongPressDown` will not end up
    /// causing a long-press.
    public let onLongPressCancel: (() -> Void)?

    /// Called when a long press gesture with a primary button has been recognized.
    public let onLongPress: (() -> Void)?

    /// Called when a long press gesture with a primary button has been recognized.
    /// Includes details about the position.
    public let onLongPressStart: ((LongPressStartDetails) -> Void)?

    /// A pointer has been drag-moved after a long press with a primary button.
    public let onLongPressMoveUpdate: ((LongPressMoveUpdateDetails) -> Void)?

    /// A pointer that has triggered a long press with a primary button has
    /// stopped contacting the screen.
    public let onLongPressEnd: ((LongPressEndDetails) -> Void)?

    /// A pointer that has triggered a long press with a primary button has
    /// stopped contacting the screen (without position details).
    public let onLongPressUp: (() -> Void)?

    // MARK: - Vertical drag callbacks

    /// A pointer has contacted the screen and might begin to move vertically.
    public let onVerticalDragDown: ((DragDownDetails) -> Void)?

    /// A pointer has contacted the screen and has begun to move vertically.
    public let onVerticalDragStart: ((DragStartDetails) -> Void)?

    /// A pointer that is in contact with the screen and moving vertically has
    /// moved in the vertical direction.
    public let onVerticalDragUpdate: ((DragUpdateDetails) -> Void)?

    /// A pointer that was previously in contact with the screen and moving
    /// vertically is no longer in contact with the screen and was moving at a
    /// specific velocity when it stopped contacting the screen.
    public let onVerticalDragEnd: ((DragEndDetails) -> Void)?

    /// The pointer that previously triggered `onVerticalDragDown` did not
    /// complete.
    public let onVerticalDragCancel: (() -> Void)?

    // MARK: - Horizontal drag callbacks

    /// A pointer has contacted the screen and might begin to move horizontally.
    public let onHorizontalDragDown: ((DragDownDetails) -> Void)?

    /// A pointer has contacted the screen and has begun to move horizontally.
    public let onHorizontalDragStart: ((DragStartDetails) -> Void)?

    /// A pointer that is in contact with the screen and moving horizontally has
    /// moved in the horizontal direction.
    public let onHorizontalDragUpdate: ((DragUpdateDetails) -> Void)?

    /// A pointer that was previously in contact with the screen and moving
    /// horizontally is no longer in contact with the screen and was moving at a
    /// specific velocity when it stopped contacting the screen.
    public let onHorizontalDragEnd: ((DragEndDetails) -> Void)?

    /// The pointer that previously triggered `onHorizontalDragDown` did not
    /// complete.
    public let onHorizontalDragCancel: (() -> Void)?

    // MARK: - Pan callbacks

    /// A pointer has contacted the screen and might begin to move.
    public let onPanDown: ((DragDownDetails) -> Void)?

    /// A pointer has contacted the screen and has begun to move.
    public let onPanStart: ((DragStartDetails) -> Void)?

    /// A pointer that is in contact with the screen and moving has moved again.
    public let onPanUpdate: ((DragUpdateDetails) -> Void)?

    /// A pointer that was previously in contact with the screen and moving
    /// is no longer in contact with the screen and was moving at a specific
    /// velocity when it stopped contacting the screen.
    public let onPanEnd: ((DragEndDetails) -> Void)?

    /// The pointer that previously triggered `onPanDown` did not complete.
    public let onPanCancel: (() -> Void)?

    // MARK: - Scale callbacks

    /// The pointers in contact with the screen have established a focal point
    /// and initial scale of 1.0.
    public let onScaleStart: ((ScaleStartDetails) -> Void)?

    /// The pointers in contact with the screen have indicated a new focal point
    /// and/or scale.
    public let onScaleUpdate: ((ScaleUpdateDetails) -> Void)?

    /// The pointers are no longer in contact with the screen.
    public let onScaleEnd: ((ScaleEndDetails) -> Void)?

    // MARK: - Force press callbacks

    /// The pointer is in contact with the screen and has pressed with sufficient
    /// force to initiate a force press. The amount of force is at least
    /// `ForcePressGestureRecognizer.startPressure`.
    public let onForcePressStart: ((ForcePressDetails) -> Void)?

    /// The pointer is in contact with the screen and has pressed with the maximum
    /// force. The amount of force is at least
    /// `ForcePressGestureRecognizer.peakPressure`.
    public let onForcePressPeak: ((ForcePressDetails) -> Void)?

    /// A pointer is in contact with the screen, has previously passed the
    /// `ForcePressGestureRecognizer.startPressure` and is either moving on the
    /// plane of the screen, pressing the screen with varying forces or both
    /// simultaneously.
    public let onForcePressUpdate: ((ForcePressDetails) -> Void)?

    /// The pointer is no longer in contact with the screen.
    public let onForcePressEnd: ((ForcePressDetails) -> Void)?

    // MARK: - Configuration

    /// How this gesture detector should behave during hit testing.
    ///
    /// This defaults to `HitTestBehavior.deferToChild` if `child` is not nil
    /// and `HitTestBehavior.translucent` if child is nil.
    public let behavior: HitTestBehavior?

    /// Whether to exclude these gestures from the semantics tree. For
    /// example, the long-press gesture for showing a tooltip is usually
    /// excluded because the tooltip itself is included in the semantics
    /// tree directly and so having a gesture to show it would result in
    /// duplication of information.
    public let excludeFromSemantics: Bool

    /// Determines the way that drag start behavior is handled.
    public let dragStartBehavior: DragStartBehavior

    /// Optional set of allowed pointer device kinds for recognizers.
    public let supportedDevices: Set<PointerDeviceKind>?

    /// The child widget.
    public let child: Widget?

    // MARK: - Initializer

    public init(
        key: (any Key)? = nil,
        // Tap
        onTapDown: ((TapDownDetails) -> Void)? = nil,
        onTapUp: ((TapUpDetails) -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        onTapCancel: (() -> Void)? = nil,
        // Secondary tap
        onSecondaryTap: (() -> Void)? = nil,
        onSecondaryTapDown: ((TapDownDetails) -> Void)? = nil,
        onSecondaryTapUp: ((TapUpDetails) -> Void)? = nil,
        onSecondaryTapCancel: (() -> Void)? = nil,
        // Tertiary tap
        onTertiaryTapDown: ((TapDownDetails) -> Void)? = nil,
        onTertiaryTapUp: ((TapUpDetails) -> Void)? = nil,
        onTertiaryTapCancel: (() -> Void)? = nil,
        // Double tap
        onDoubleTap: (() -> Void)? = nil,
        onDoubleTapDown: ((TapDownDetails) -> Void)? = nil,
        onDoubleTapCancel: (() -> Void)? = nil,
        // Long press
        onLongPressDown: ((LongPressDownDetails) -> Void)? = nil,
        onLongPressCancel: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        onLongPressStart: ((LongPressStartDetails) -> Void)? = nil,
        onLongPressMoveUpdate: ((LongPressMoveUpdateDetails) -> Void)? = nil,
        onLongPressEnd: ((LongPressEndDetails) -> Void)? = nil,
        onLongPressUp: (() -> Void)? = nil,
        // Vertical drag
        onVerticalDragDown: ((DragDownDetails) -> Void)? = nil,
        onVerticalDragStart: ((DragStartDetails) -> Void)? = nil,
        onVerticalDragUpdate: ((DragUpdateDetails) -> Void)? = nil,
        onVerticalDragEnd: ((DragEndDetails) -> Void)? = nil,
        onVerticalDragCancel: (() -> Void)? = nil,
        // Horizontal drag
        onHorizontalDragDown: ((DragDownDetails) -> Void)? = nil,
        onHorizontalDragStart: ((DragStartDetails) -> Void)? = nil,
        onHorizontalDragUpdate: ((DragUpdateDetails) -> Void)? = nil,
        onHorizontalDragEnd: ((DragEndDetails) -> Void)? = nil,
        onHorizontalDragCancel: (() -> Void)? = nil,
        // Pan
        onPanDown: ((DragDownDetails) -> Void)? = nil,
        onPanStart: ((DragStartDetails) -> Void)? = nil,
        onPanUpdate: ((DragUpdateDetails) -> Void)? = nil,
        onPanEnd: ((DragEndDetails) -> Void)? = nil,
        onPanCancel: (() -> Void)? = nil,
        // Scale
        onScaleStart: ((ScaleStartDetails) -> Void)? = nil,
        onScaleUpdate: ((ScaleUpdateDetails) -> Void)? = nil,
        onScaleEnd: ((ScaleEndDetails) -> Void)? = nil,
        // Force press
        onForcePressStart: ((ForcePressDetails) -> Void)? = nil,
        onForcePressPeak: ((ForcePressDetails) -> Void)? = nil,
        onForcePressUpdate: ((ForcePressDetails) -> Void)? = nil,
        onForcePressEnd: ((ForcePressDetails) -> Void)? = nil,
        // Configuration
        behavior: HitTestBehavior? = nil,
        excludeFromSemantics: Bool = false,
        dragStartBehavior: DragStartBehavior = .start,
        supportedDevices: Set<PointerDeviceKind>? = nil,
        child: Widget? = nil
    ) {
        // Validate: pan and scale cannot coexist.
        assert(
            (onPanDown == nil && onPanStart == nil && onPanUpdate == nil && onPanEnd == nil && onPanCancel == nil)
            || (onScaleStart == nil && onScaleUpdate == nil && onScaleEnd == nil),
            "Pan and scale are mutually exclusive: having both a pan gesture and a scale gesture is redundant; scale is a superset of pan. Just use the scale gesture."
        )
        // Validate: horizontal/vertical drag and pan cannot coexist.
        assert(
            (onHorizontalDragDown == nil && onHorizontalDragStart == nil && onHorizontalDragUpdate == nil
             && onHorizontalDragEnd == nil && onHorizontalDragCancel == nil)
            || (onPanDown == nil && onPanStart == nil && onPanUpdate == nil && onPanEnd == nil && onPanCancel == nil),
            "Horizontal drag and pan are mutually exclusive: if the pan gesture is set, do not also set horizontal drag gestures."
        )
        assert(
            (onVerticalDragDown == nil && onVerticalDragStart == nil && onVerticalDragUpdate == nil
             && onVerticalDragEnd == nil && onVerticalDragCancel == nil)
            || (onPanDown == nil && onPanStart == nil && onPanUpdate == nil && onPanEnd == nil && onPanCancel == nil),
            "Vertical drag and pan are mutually exclusive: if the pan gesture is set, do not also set vertical drag gestures."
        )

        self.onTapDown = onTapDown
        self.onTapUp = onTapUp
        self.onTap = onTap
        self.onTapCancel = onTapCancel
        self.onSecondaryTap = onSecondaryTap
        self.onSecondaryTapDown = onSecondaryTapDown
        self.onSecondaryTapUp = onSecondaryTapUp
        self.onSecondaryTapCancel = onSecondaryTapCancel
        self.onTertiaryTapDown = onTertiaryTapDown
        self.onTertiaryTapUp = onTertiaryTapUp
        self.onTertiaryTapCancel = onTertiaryTapCancel
        self.onDoubleTap = onDoubleTap
        self.onDoubleTapDown = onDoubleTapDown
        self.onDoubleTapCancel = onDoubleTapCancel
        self.onLongPressDown = onLongPressDown
        self.onLongPressCancel = onLongPressCancel
        self.onLongPress = onLongPress
        self.onLongPressStart = onLongPressStart
        self.onLongPressMoveUpdate = onLongPressMoveUpdate
        self.onLongPressEnd = onLongPressEnd
        self.onLongPressUp = onLongPressUp
        self.onVerticalDragDown = onVerticalDragDown
        self.onVerticalDragStart = onVerticalDragStart
        self.onVerticalDragUpdate = onVerticalDragUpdate
        self.onVerticalDragEnd = onVerticalDragEnd
        self.onVerticalDragCancel = onVerticalDragCancel
        self.onHorizontalDragDown = onHorizontalDragDown
        self.onHorizontalDragStart = onHorizontalDragStart
        self.onHorizontalDragUpdate = onHorizontalDragUpdate
        self.onHorizontalDragEnd = onHorizontalDragEnd
        self.onHorizontalDragCancel = onHorizontalDragCancel
        self.onPanDown = onPanDown
        self.onPanStart = onPanStart
        self.onPanUpdate = onPanUpdate
        self.onPanEnd = onPanEnd
        self.onPanCancel = onPanCancel
        self.onScaleStart = onScaleStart
        self.onScaleUpdate = onScaleUpdate
        self.onScaleEnd = onScaleEnd
        self.onForcePressStart = onForcePressStart
        self.onForcePressPeak = onForcePressPeak
        self.onForcePressUpdate = onForcePressUpdate
        self.onForcePressEnd = onForcePressEnd
        self.behavior = behavior
        self.excludeFromSemantics = excludeFromSemantics
        self.dragStartBehavior = dragStartBehavior
        self.supportedDevices = supportedDevices
        self.child = child
        super.init(key: key)
    }

    // MARK: - Build

    /// Builds the gesture detector by collecting gesture recognizer factories
    /// and wrapping the child in a `RawGestureDetector`.
    ///
    /// **Dart Source:** `gesture_detector.dart:251-327`
    public override func build(_ context: any BuildContext) -> Widget {
        var gestures = [ObjectIdentifier: AnyGestureRecognizerFactory]()

        // -- Tap --
        if onTapDown != nil || onTapUp != nil || onTap != nil || onTapCancel != nil
            || onSecondaryTap != nil || onSecondaryTapDown != nil || onSecondaryTapUp != nil
            || onSecondaryTapCancel != nil
            || onTertiaryTapDown != nil || onTertiaryTapUp != nil || onTertiaryTapCancel != nil
        {
            gestures[ObjectIdentifier(TapGestureRecognizer.self)] = AnyGestureRecognizerFactory(
                GestureRecognizerFactory<TapGestureRecognizer>(
                    constructor: {
                        TapGestureRecognizer(debugOwner: self)
                    },
                    initializer: { [self] recognizer in
                        recognizer.onTapDown = onTapDown
                        recognizer.onTapUp = onTapUp
                        recognizer.onTap = onTap
                        recognizer.onTapCancel = onTapCancel
                        recognizer.onSecondaryTap = onSecondaryTap
                        recognizer.onSecondaryTapDown = onSecondaryTapDown
                        recognizer.onSecondaryTapUp = onSecondaryTapUp
                        recognizer.onSecondaryTapCancel = onSecondaryTapCancel
                        recognizer.onTertiaryTapDown = onTertiaryTapDown
                        recognizer.onTertiaryTapUp = onTertiaryTapUp
                        recognizer.onTertiaryTapCancel = onTertiaryTapCancel
                        recognizer.supportedDevices = supportedDevices
                    }
                )
            )
        }

        // -- Double Tap --
        if onDoubleTap != nil || onDoubleTapDown != nil || onDoubleTapCancel != nil {
            gestures[ObjectIdentifier(DoubleTapGestureRecognizer.self)] = AnyGestureRecognizerFactory(
                GestureRecognizerFactory<DoubleTapGestureRecognizer>(
                    constructor: {
                        DoubleTapGestureRecognizer(debugOwner: self)
                    },
                    initializer: { [self] recognizer in
                        recognizer.onDoubleTapDown = onDoubleTapDown
                        recognizer.onDoubleTap = onDoubleTap
                        recognizer.onDoubleTapCancel = onDoubleTapCancel
                        recognizer.supportedDevices = supportedDevices
                    }
                )
            )
        }

        // -- Long Press --
        if onLongPressDown != nil || onLongPressCancel != nil || onLongPress != nil
            || onLongPressStart != nil || onLongPressMoveUpdate != nil
            || onLongPressEnd != nil || onLongPressUp != nil
        {
            gestures[ObjectIdentifier(LongPressGestureRecognizer.self)] = AnyGestureRecognizerFactory(
                GestureRecognizerFactory<LongPressGestureRecognizer>(
                    constructor: {
                        LongPressGestureRecognizer(debugOwner: self)
                    },
                    initializer: { [self] recognizer in
                        recognizer.onLongPressDown = onLongPressDown
                        recognizer.onLongPressCancel = onLongPressCancel
                        recognizer.onLongPress = onLongPress
                        recognizer.onLongPressStart = onLongPressStart
                        recognizer.onLongPressMoveUpdate = onLongPressMoveUpdate
                        recognizer.onLongPressEnd = onLongPressEnd
                        recognizer.onLongPressUp = onLongPressUp
                        recognizer.supportedDevices = supportedDevices
                    }
                )
            )
        }

        // -- Vertical Drag --
        if onVerticalDragDown != nil || onVerticalDragStart != nil
            || onVerticalDragUpdate != nil || onVerticalDragEnd != nil
            || onVerticalDragCancel != nil
        {
            gestures[ObjectIdentifier(VerticalDragGestureRecognizer.self)] = AnyGestureRecognizerFactory(
                GestureRecognizerFactory<VerticalDragGestureRecognizer>(
                    constructor: {
                        VerticalDragGestureRecognizer(debugOwner: self)
                    },
                    initializer: { [self] recognizer in
                        recognizer.onDown = onVerticalDragDown
                        recognizer.onStart = onVerticalDragStart
                        recognizer.onUpdate = onVerticalDragUpdate
                        recognizer.onEnd = onVerticalDragEnd
                        recognizer.onCancel = onVerticalDragCancel
                        recognizer.dragStartBehavior = dragStartBehavior
                        recognizer.supportedDevices = supportedDevices
                    }
                )
            )
        }

        // -- Horizontal Drag --
        if onHorizontalDragDown != nil || onHorizontalDragStart != nil
            || onHorizontalDragUpdate != nil || onHorizontalDragEnd != nil
            || onHorizontalDragCancel != nil
        {
            gestures[ObjectIdentifier(HorizontalDragGestureRecognizer.self)] = AnyGestureRecognizerFactory(
                GestureRecognizerFactory<HorizontalDragGestureRecognizer>(
                    constructor: {
                        HorizontalDragGestureRecognizer(debugOwner: self)
                    },
                    initializer: { [self] recognizer in
                        recognizer.onDown = onHorizontalDragDown
                        recognizer.onStart = onHorizontalDragStart
                        recognizer.onUpdate = onHorizontalDragUpdate
                        recognizer.onEnd = onHorizontalDragEnd
                        recognizer.onCancel = onHorizontalDragCancel
                        recognizer.dragStartBehavior = dragStartBehavior
                        recognizer.supportedDevices = supportedDevices
                    }
                )
            )
        }

        // -- Pan --
        if onPanDown != nil || onPanStart != nil || onPanUpdate != nil
            || onPanEnd != nil || onPanCancel != nil
        {
            gestures[ObjectIdentifier(PanGestureRecognizer.self)] = AnyGestureRecognizerFactory(
                GestureRecognizerFactory<PanGestureRecognizer>(
                    constructor: {
                        PanGestureRecognizer(debugOwner: self)
                    },
                    initializer: { [self] recognizer in
                        recognizer.onDown = onPanDown
                        recognizer.onStart = onPanStart
                        recognizer.onUpdate = onPanUpdate
                        recognizer.onEnd = onPanEnd
                        recognizer.onCancel = onPanCancel
                        recognizer.dragStartBehavior = dragStartBehavior
                        recognizer.supportedDevices = supportedDevices
                    }
                )
            )
        }

        // -- Scale --
        if onScaleStart != nil || onScaleUpdate != nil || onScaleEnd != nil {
            gestures[ObjectIdentifier(ScaleGestureRecognizer.self)] = AnyGestureRecognizerFactory(
                GestureRecognizerFactory<ScaleGestureRecognizer>(
                    constructor: {
                        ScaleGestureRecognizer(debugOwner: self)
                    },
                    initializer: { [self] recognizer in
                        recognizer.onStart = onScaleStart
                        recognizer.onUpdate = onScaleUpdate
                        recognizer.onEnd = onScaleEnd
                        recognizer.dragStartBehavior = dragStartBehavior
                        recognizer.supportedDevices = supportedDevices
                    }
                )
            )
        }

        // -- Force Press --
        if onForcePressStart != nil || onForcePressPeak != nil
            || onForcePressUpdate != nil || onForcePressEnd != nil
        {
            gestures[ObjectIdentifier(ForcePressGestureRecognizer.self)] = AnyGestureRecognizerFactory(
                GestureRecognizerFactory<ForcePressGestureRecognizer>(
                    constructor: {
                        ForcePressGestureRecognizer(debugOwner: self)
                    },
                    initializer: { [self] recognizer in
                        recognizer.onStart = onForcePressStart
                        recognizer.onPeak = onForcePressPeak
                        recognizer.onUpdate = onForcePressUpdate
                        recognizer.onEnd = onForcePressEnd
                        recognizer.supportedDevices = supportedDevices
                    }
                )
            )
        }

        let raw = RawGestureDetector(
            gestures: gestures,
            behavior: behavior ?? (child != nil ? .deferToChild : .translucent),
            excludeFromSemantics: excludeFromSemantics,
            child: child
        )
        // Annotate tap/long-press as semantics actions (Murmuration P3):
        // the agent semantics endpoint discovers them in the tree and
        // perform_action invokes the very same callbacks. Hit-testing is
        // untouched (the handler defers to its child).
        if excludeFromSemantics || (onTap == nil && onLongPress == nil) {
            return raw
        }
        return _GestureSemantics(onTap: onTap, onLongPress: onLongPress, child: raw)
    }
}

// MARK: - _GestureSemantics

/// Wraps a gesture detector's subtree in a `RenderSemanticsGestureHandler`
/// carrying the detector's tap/long-press callbacks.
///
/// **Dart Source:** `gesture_detector.dart` (_GestureSemantics), simplified:
/// callbacks are mirrored directly instead of going through the recognizers'
/// semantics delegates. Module-internal rather than private: `HoverButton`
/// presses on raw pointer events and wraps itself in this so every Fluent
/// control is a tappable node in the agent semantics tree too.
final class _GestureSemantics: SingleChildRenderObjectWidget {
    let onTapCallback: (() -> Void)?
    let onLongPressCallback: (() -> Void)?

    init(onTap: (() -> Void)?, onLongPress: (() -> Void)?, child: Widget?) {
        self.onTapCallback = onTap
        self.onLongPressCallback = onLongPress
        super.init(child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderSemanticsGestureHandler(
            onTap: onTapCallback,
            onLongPress: onLongPressCallback
        )
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        guard let handler = renderObject as? RenderSemanticsGestureHandler else { return }
        handler.onTap = onTapCallback
        handler.onLongPress = onLongPressCallback
    }
}
