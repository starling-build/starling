// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/utils/hover_button.dart

import FlutterSwiftBridge

// MARK: - WidgetStateWidgetBuilder

/// A builder function that creates a widget based on the current `Set<WidgetState>`.
public typealias WidgetStateWidgetBuilder = (any BuildContext, Set<WidgetState>) -> Widget

// MARK: - HoverButtonInherited

/// An inherited widget that provides access to `HoverButton` interaction states.
public class HoverButtonInherited: InheritedWidget {
    /// The current interaction states of the button.
    public let states: Set<WidgetState>

    /// Creates a hover button inherited widget.
    public init(key: (any Key)? = nil, states: Set<WidgetState>, child: Widget) {
        self.states = states
        super.init(key: key, child: child)
    }

    /// Returns the closest `HoverButtonInherited` ancestor.
    /// Crashes if no ancestor is found.
    public static func of(_ context: any BuildContext) -> HoverButtonInherited {
        return context.dependOnInheritedWidgetOfExactType(HoverButtonInherited.self)!
    }

    /// Returns the closest `HoverButtonInherited` ancestor, if any.
    public static func maybeOf(_ context: any BuildContext) -> HoverButtonInherited? {
        return context.dependOnInheritedWidgetOfExactType(HoverButtonInherited.self)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? HoverButtonInherited else { return true }
        return states != old.states
    }
}

// MARK: - HoverButton

/// Base widget for any widget that requires input — tracks hover, press, and
/// (eventually) focus states and rebuilds via a builder callback.
///
/// This is the most critical infrastructure widget in Fluent UI: nearly every
/// interactive widget wraps `HoverButton`.
///
/// Because `GestureDetector` is not yet available, pointer down/up detection
/// uses the `Listener` widget. Focus support is deferred (stubs only).
public class HoverButton: StatefulWidget {
    /// The builder for the button content based on the current states.
    public let builder: WidgetStateWidgetBuilder

    /// Called when the button is pressed (pointer down then up within bounds).
    public let onPressed: (() -> Void)?

    /// Called when a long press gesture is detected (not yet supported — placeholder).
    public let onLongPress: (() -> Void)?

    /// Called when a pointer-down event occurs on this button.
    public let onTapDown: (() -> Void)?

    /// Called when a pointer-up event occurs on this button.
    public let onTapUp: (() -> Void)?

    /// Called when a pointer enters the button area.
    public let onPointerEnter: PointerEnterEventListener?

    /// Called when a pointer exits the button area.
    public let onPointerExit: PointerExitEventListener?

    /// Called when the button focus changes (deferred — focus system is incomplete).
    public let onFocusChange: ((Bool) -> Void)?

    /// The margin created around this button.
    public let margin: EdgeInsets?

    /// The mouse cursor for this button.
    public let cursor: MouseCursor?

    /// The semantic label for accessibility.
    public let semanticLabel: String?

    /// Whether the hover button should always be considered enabled,
    /// even if `onPressed` is nil.
    public let forceEnabled: Bool

    /// How this widget should behave during hit testing.
    public let hitTestBehavior: HitTestBehavior

    public init(
        key: (any Key)? = nil,
        builder: @escaping WidgetStateWidgetBuilder,
        onPressed: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        onTapDown: (() -> Void)? = nil,
        onTapUp: (() -> Void)? = nil,
        onPointerEnter: PointerEnterEventListener? = nil,
        onPointerExit: PointerExitEventListener? = nil,
        onFocusChange: ((Bool) -> Void)? = nil,
        margin: EdgeInsets? = nil,
        cursor: MouseCursor? = nil,
        semanticLabel: String? = nil,
        forceEnabled: Bool = false,
        hitTestBehavior: HitTestBehavior = .opaque
    ) {
        self.builder = builder
        self.onPressed = onPressed
        self.onLongPress = onLongPress
        self.onTapDown = onTapDown
        self.onTapUp = onTapUp
        self.onPointerEnter = onPointerEnter
        self.onPointerExit = onPointerExit
        self.onFocusChange = onFocusChange
        self.margin = margin
        self.cursor = cursor
        self.semanticLabel = semanticLabel
        self.forceEnabled = forceEnabled
        self.hitTestBehavior = hitTestBehavior
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return HoverButtonState()
    }

    /// Returns the closest `HoverButtonInherited` ancestor.
    public static func of(_ context: any BuildContext) -> HoverButtonInherited {
        return HoverButtonInherited.of(context)
    }

    /// Returns the closest `HoverButtonInherited` ancestor, if any.
    public static func maybeOf(_ context: any BuildContext) -> HoverButtonInherited? {
        return HoverButtonInherited.maybeOf(context)
    }
}

// MARK: - HoverButtonState

class HoverButtonState: State<StatefulWidget> {
    private var _hovering = false
    private var _pressing = false
    // Focus tracking deferred — always false for now.
    private var _shouldShowFocus = false

    private var hoverButton: HoverButton {
        return widget as! HoverButton
    }

    private var enabled: Bool {
        let w = hoverButton
        return w.forceEnabled
            || w.onPressed != nil
            || w.onTapUp != nil
            || w.onTapDown != nil
            || w.onLongPress != nil
    }

    private var states: Set<WidgetState> {
        if !enabled { return [.disabled] }
        var s = Set<WidgetState>()
        if _pressing { s.insert(.pressed) }
        if _hovering { s.insert(.hovered) }
        if _shouldShowFocus { s.insert(.focused) }
        return s
    }

    override func build(_ context: any BuildContext) -> Widget {
        let widget = hoverButton

        // Core content from builder
        var w: Widget = widget.builder(context, states)

        // Wrap with Listener for pointer-down / pointer-up (press detection)
        // on raw pointer events. A press is the PRIMARY button only, as a
        // `GestureDetector.onTap` is: it used to fire `onPressed` on any
        // release whatever the button, so a right-click on a Start tile
        // launched the app instead of opening its menu. And it fires only
        // for a release that follows a press that started here.
        w = Listener(
            onPointerDown: { [weak self] event in
                guard let self = self, self.enabled,
                      event.buttons & kPrimaryButton != 0 else { return }
                self.setState { self._pressing = true }
                widget.onTapDown?()
            },
            onPointerUp: { [weak self] _ in
                guard let self = self, self.enabled, self._pressing else { return }
                widget.onTapUp?()
                widget.onPressed?()
                self.setState { self._pressing = false }
            },
            onPointerCancel: { [weak self] _ in
                guard let self = self else { return }
                self.setState { self._pressing = false }
            },
            behavior: widget.hitTestBehavior,
            child: w
        )

        // Wrap with MouseRegion for hover detection
        w = MouseRegion(
            onEnter: { [weak self] event in
                guard let self = self, self.mounted else { return }
                self.setState { self._hovering = true }
                widget.onPointerEnter?(event)
            },
            onExit: { [weak self] event in
                guard let self = self, self.mounted else { return }
                self.setState { self._hovering = false }
                widget.onPointerExit?(event)
            },
            cursor: widget.cursor ?? MouseCursor.defer_,
            child: w
        )

        // A tap action in the semantics tree, as GestureDetector gives its
        // subtree: pressing on raw pointer events is invisible to the agent
        // endpoint, and without this every Fluent control — pane items,
        // buttons, rows — was a label with no way to tap it.
        if enabled, widget.onPressed != nil || widget.onLongPress != nil {
            w = _GestureSemantics(onTap: widget.onPressed, onLongPress: widget.onLongPress, child: w)
        }

        // Wrap with Padding if margin is specified
        if let margin = widget.margin {
            w = Padding(padding: margin, child: w)
        }

        // Wrap with HoverButtonInherited to expose states to descendants
        return HoverButtonInherited(states: states, child: w)
    }
}

// MARK: - WidgetState Set Extension

extension Set where Element == WidgetState {
    /// Whether the set contains `WidgetState.focused`.
    public var isFocused: Bool { contains(.focused) }

    /// Whether the set contains `WidgetState.disabled`.
    public var isDisabled: Bool { contains(.disabled) }

    /// Whether the set contains `WidgetState.pressed`.
    public var isPressed: Bool { contains(.pressed) }

    /// Whether the set contains `WidgetState.hovered`.
    public var isHovered: Bool { contains(.hovered) }

    /// Whether the set is empty (default / none state).
    public var isNone: Bool { isEmpty }

    /// Whether the set contains any of the given states.
    public func isAnyOf(_ states: any Sequence<WidgetState>) -> Bool {
        for state in states {
            if contains(state) { return true }
        }
        return false
    }

    /// Whether the set contains all of the given states.
    public func isAllOf(_ states: any Sequence<WidgetState>) -> Bool {
        for state in states {
            if !contains(state) { return false }
        }
        return true
    }

    /// Returns a value based on priority ordering of widget states.
    public static func forStates<T>(
        _ states: Set<WidgetState>,
        disabled: T,
        none: T,
        pressed: T? = nil,
        hovering: T? = nil,
        focused: T? = nil
    ) -> T {
        if states.contains(.disabled) { return disabled }
        if let pressed = pressed, states.contains(.pressed) { return pressed }
        if let hovering = hovering, states.contains(.hovered) { return hovering }
        if states.contains(.focused) { return focused ?? pressed ?? none }
        return none
    }
}
