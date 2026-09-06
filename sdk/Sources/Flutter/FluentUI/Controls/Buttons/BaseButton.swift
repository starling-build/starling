// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/buttons/base.dart

import FlutterSwiftBridge

// MARK: - BaseButton

/// A base widget for all Fluent UI button types.
///
/// Wraps `HoverButton` for interaction tracking and resolves styles from
/// three sources (widget style > theme style > default style).
///
/// Subclasses must override `defaultStyleOf(_:)` and `themeStyleOf(_:)`.
open class BaseButton: StatefulWidget {

    /// Called when the button is tapped or otherwise activated.
    public let onPressed: (() -> Void)?

    /// Called when a pointer-down event occurs on this button.
    public let onTapDown: (() -> Void)?

    /// Called when a pointer-up event occurs on this button.
    public let onTapUp: (() -> Void)?

    /// Called when the button is long-pressed.
    public let onLongPress: (() -> Void)?

    /// Customizes this button's appearance.
    public let style: ButtonStyle?

    /// Whether this button can be focused.
    public let focusable: Bool

    /// Whether to autofocus this button.
    public let autofocus: Bool

    /// Typically the button's label (usually a `Text` widget).
    public let child: Widget

    /// Creates a base button.
    public init(
        key: (any Key)? = nil,
        onPressed: (() -> Void)? = nil,
        onLongPress: (() -> Void)? = nil,
        onTapDown: (() -> Void)? = nil,
        onTapUp: (() -> Void)? = nil,
        style: ButtonStyle? = nil,
        focusable: Bool = true,
        autofocus: Bool = false,
        child: Widget
    ) {
        self.onPressed = onPressed
        self.onLongPress = onLongPress
        self.onTapDown = onTapDown
        self.onTapUp = onTapUp
        self.style = style
        self.focusable = focusable
        self.autofocus = autofocus
        self.child = child
        super.init(key: key)
    }

    /// Whether the button is enabled.
    ///
    /// Buttons are disabled by default. To enable a button, set `onPressed`,
    /// `onLongPress`, `onTapDown`, or `onTapUp` to a non-null value.
    public var enabled: Bool {
        onPressed != nil
            || onLongPress != nil
            || onTapDown != nil
            || onTapUp != nil
    }

    /// Returns the default style for this button type based on the context.
    ///
    /// Subclasses must override this method.
    open func defaultStyleOf(_ context: any BuildContext) -> ButtonStyle {
        fatalError("Subclasses must override defaultStyleOf(_:)")
    }

    /// Returns the theme style for this button type, if defined.
    ///
    /// Subclasses must override this method.
    open func themeStyleOf(_ context: any BuildContext) -> ButtonStyle? {
        return nil
    }

    public override func createState() -> State<StatefulWidget> {
        return _BaseButtonState()
    }
}

// MARK: - _BaseButtonState

class _BaseButtonState: State<StatefulWidget> {

    private var baseButton: BaseButton {
        return widget as! BaseButton
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let widget = baseButton

        let widgetStyle = widget.style
        let themeStyle = widget.themeStyleOf(context)
        let defaultStyle = widget.defaultStyleOf(context)

        // Helper to get the effective value from widget > theme > default style chain.
        func effectiveValue<T>(_ getProperty: (ButtonStyle?) -> T?) -> T? {
            return getProperty(widgetStyle) ?? getProperty(themeStyle) ?? getProperty(defaultStyle)
        }

        return HoverButton(
            builder: { [widget] context, states in
                // Resolve a WidgetStateProperty<V?> from the style chain.
                // V is the non-optional inner type (e.g. Color, Double, TextStyle).
                // Returns the first non-nil resolved value from widget > theme > default.
                func resolveColor(_ getProperty: (ButtonStyle?) -> (any WidgetStateProperty<Color?>)?) -> Color? {
                    if let v = getProperty(widgetStyle)?.resolve(states) { return v }
                    if let v = getProperty(themeStyle)?.resolve(states) { return v }
                    if let v = getProperty(defaultStyle)?.resolve(states) { return v }
                    return nil
                }
                func resolveDouble(_ getProperty: (ButtonStyle?) -> (any WidgetStateProperty<Double?>)?) -> Double? {
                    if let v = getProperty(widgetStyle)?.resolve(states) { return v }
                    if let v = getProperty(themeStyle)?.resolve(states) { return v }
                    if let v = getProperty(defaultStyle)?.resolve(states) { return v }
                    return nil
                }
                func resolveTextStyle(_ getProperty: (ButtonStyle?) -> (any WidgetStateProperty<TextStyle?>)?) -> TextStyle? {
                    if let v = getProperty(widgetStyle)?.resolve(states) { return v }
                    if let v = getProperty(themeStyle)?.resolve(states) { return v }
                    if let v = getProperty(defaultStyle)?.resolve(states) { return v }
                    return nil
                }
                func resolvePadding(_ getProperty: (ButtonStyle?) -> (any WidgetStateProperty<EdgeInsets?>)?) -> EdgeInsets? {
                    if let v = getProperty(widgetStyle)?.resolve(states) { return v }
                    if let v = getProperty(themeStyle)?.resolve(states) { return v }
                    if let v = getProperty(defaultStyle)?.resolve(states) { return v }
                    return nil
                }
                func resolveShape(_ getProperty: (ButtonStyle?) -> (any WidgetStateProperty<(any ShapeBorder)?>)?) -> (any ShapeBorder)? {
                    if let v = getProperty(widgetStyle)?.resolve(states) { return v }
                    if let v = getProperty(themeStyle)?.resolve(states) { return v }
                    if let v = getProperty(defaultStyle)?.resolve(states) { return v }
                    return nil
                }

                let resolvedElevation: Double = resolveDouble({ $0?.elevation }) ?? 0.0
                let resolvedTextStyle: TextStyle? = theme.typography.body?.merge(
                    resolveTextStyle({ $0?.textStyle })
                )
                let resolvedBackgroundColor: Color? = resolveColor({ $0?.backgroundColor })
                let resolvedForegroundColor: Color? = resolveColor({ $0?.foregroundColor })
                let resolvedShadowColor: Color? = resolveColor({ $0?.shadowColor })
                let resolvedPadding: EdgeInsets = resolvePadding({ $0?.padding }) ?? EdgeInsets.zero
                let resolvedShape: (any ShapeBorder)? = resolveShape({ $0?.shape })
                let iconSize: Double = resolveDouble({ $0?.iconSize }) ?? 14.0

                // Extract BorderRadius and BorderSide from shape for
                // BoxDecoration and PhysicalModel.
                var borderRadius: BorderRadius = .zero
                var borderSide: BorderSide? = nil
                if let rrb = resolvedShape as? RoundedRectangleBorder {
                    if let br = rrb.borderRadius as? BorderRadius {
                        borderRadius = br
                    }
                    if rrb.side.width > 0 {
                        borderSide = rrb.side
                    }
                }

                // Build the decoration (BoxDecoration for proper lerp/animation)
                let decoration: BoxDecoration = BoxDecoration(
                    color: resolvedBackgroundColor,
                    border: borderSide.map {
                        Border.all(color: $0.color, width: $0.width)
                    },
                    borderRadius: borderRadius
                )

                // Inner content: text with foreground color applied
                let textStyleForChild = (resolvedTextStyle ?? TextStyle()).copyWith(
                    color: resolvedForegroundColor
                )

                let innerChild: Widget = Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: widget.child
                )

                // Wrap with DefaultTextStyle
                let styledChild: Widget = DefaultTextStyle(
                    style: DefaultTextStyle.of(context).style.merge(textStyleForChild),
                    child: innerChild
                )

                // Wrap with IconTheme
                // A style that names no foreground (IconButton at rest) keeps
                // the enclosing theme's icon ink -- white in the dark theme --
                // rather than handing `Icon` a nil it fills with black.
                let iconThemedChild: Widget = IconTheme(
                    data: IconThemeData(
                        size: iconSize,
                        color: resolvedForegroundColor ?? IconTheme.of(context).color
                    ),
                    child: styledChild
                )

                // Wrap with animated decoration and padding for smooth
                // press/hover transitions.
                let decoratedChild: Widget = AnimatedContainer(
                    padding: resolvedPadding,
                    decoration: decoration,
                    curve: Curves.easeInOut,
                    duration: theme.fastAnimationDuration,
                    child: iconThemedChild
                )

                // Wrap with PhysicalModel for elevation/shadow
                let result: Widget = PhysicalModel(
                    borderRadius: borderRadius,
                    elevation: resolvedElevation,
                    color: Color(0x00000000), // transparent
                    shadowColor: resolvedShadowColor ?? Color(0xFF000000),
                    child: decoratedChild
                )

                return FocusBorder(
                    child: result,
                    focused: states.isFocused
                )
            },
            onPressed: widget.onPressed,
            onLongPress: widget.onLongPress,
            onTapDown: widget.onTapDown,
            onTapUp: widget.onTapUp
        )
    }
}

// MARK: - _ButtonDecoratedBox

/// A simple widget that paints a `ShapeDecoration` around its child.
///
/// Uses `RenderDecoratedBox` directly (same approach as `_DecoratedBoxWidget`
/// in FocusBorder, but for `ShapeDecoration`).
class _ButtonDecoratedBox: SingleChildRenderObjectWidget {
    let decoration: ShapeDecoration

    init(
        key: (any Key)? = nil,
        decoration: ShapeDecoration,
        child: Widget? = nil
    ) {
        self.decoration = decoration
        super.init(key: key, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderDecoratedBox(decoration: decoration)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderDecoratedBox
        ro.decoration = decoration
    }
}
