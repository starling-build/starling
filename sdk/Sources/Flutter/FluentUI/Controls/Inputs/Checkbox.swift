// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/inputs/checkbox.dart

import FlutterSwiftBridge

// MARK: - Checkbox

/// A check box is used to select or deselect action items.
///
/// It can be used for a single item or for a list of multiple items that a user
/// can choose from. The control has three selection states: unselected (`false`),
/// selected (`true`), and indeterminate (`nil`). Use the indeterminate state
/// when a collection of sub-choices have both unselected and selected states.
public class Checkbox: StatelessWidget {
    /// Whether the checkbox is checked or not.
    /// If `nil`, the checkbox is in its third (indeterminate) state.
    public let checked: Bool?

    /// Called when the value of the checkbox should change.
    /// If nil, the checkbox is considered disabled.
    public let onChanged: ((Bool?) -> Void)?

    /// The style applied to the checkbox.
    public let style: CheckboxThemeData?

    /// The content displayed to the right of the checkbox.
    public let content: Widget?

    public init(
        key: (any Key)? = nil,
        checked: Bool?,
        onChanged: ((Bool?) -> Void)?,
        style: CheckboxThemeData? = nil,
        content: Widget? = nil
    ) {
        self.checked = checked
        self.onChanged = onChanged
        self.style = style
        self.content = content
        super.init(key: key)
    }

    public override func build(_ context: any BuildContext) -> Widget {
        let resolvedStyle = CheckboxTheme.of(context).merge(style)
        let size: Double = 20.0

        return HoverButton(
            builder: { [self] context, states in
                // Resolve decoration based on state
                let decoration: BoxDecoration? = {
                    if checked == nil {
                        return resolvedStyle.thirdstateDecoration?.resolve(states)
                    } else if checked! {
                        return resolvedStyle.checkedDecoration?.resolve(states)
                    } else {
                        return resolvedStyle.uncheckedDecoration?.resolve(states)
                    }
                }()

                // Build the check icon / dash content
                let iconContent: Widget
                if checked == nil {
                    // Indeterminate dash
                    let dashColor = resolvedStyle.thirdstateIconColor?.resolve(states)
                        ?? resolvedStyle.checkedIconColor?.resolve(states)
                        ?? FluentTheme.of(context).inactiveColor
                    iconContent = Center(
                        child: SizedBox(
                            width: 8,
                            height: 1.4,
                            child: ColoredBox(color: dashColor)
                        )
                    )
                } else {
                    // Checkmark (or transparent when unchecked)
                    let iconColor: Color = {
                        if checked! {
                            return resolvedStyle.checkedIconColor?.resolve(states)
                                ?? FluentTheme.of(context).activeColor
                        } else {
                            return resolvedStyle.uncheckedIconColor?.resolve(states)
                                ?? Color(0x00000000)
                        }
                    }()
                    // Painted, not a glyph: U+2713 is not in Selawik (or in
                    // most UI fonts), and a missing glyph draws as nothing --
                    // a checked box that is just a filled square.
                    iconContent = checked!
                        ? Center(child: CustomPaint(
                            painter: _CheckMarkPainter(color: iconColor),
                            size: Size(12, 12)))
                        : SizedBox(width: 12, height: 12)
                }

                // Build the checkbox box
                var child: Widget = _CheckboxBox(
                    decoration: decoration ?? BoxDecoration(),
                    size: size,
                    child: iconContent
                )

                // Add content label if provided
                if let labelContent = content {
                    let foregroundColor = resolvedStyle.foregroundColor?.resolve(states)
                    let inheritedStyle = DefaultTextStyle.of(context).style
                    let mergedStyle = inheritedStyle.merge(TextStyle(color: foregroundColor))
                    child = Row(
                        mainAxisSize: .min,
                        children: [
                            child,
                            SizedBox(width: 8),
                            DefaultTextStyle(
                                style: mergedStyle,
                                child: labelContent
                            ),
                        ]
                    )
                }

                return FocusBorder(
                    child: child,
                    focused: states.isFocused,
                    renderOutside: true
                )
            },
            onPressed: onChanged == nil
                ? nil
                : { [checked, onChanged] in
                    onChanged?(checked == nil ? nil : !(checked!))
                }
        )
    }
}

// MARK: - _CheckboxBox

/// Internal widget that renders the checkbox's decorated box with fixed size.
class _CheckboxBox: SingleChildRenderObjectWidget {
    let decoration: BoxDecoration
    let boxSize: Double

    init(
        key: (any Key)? = nil,
        decoration: BoxDecoration,
        size: Double,
        child: Widget? = nil
    ) {
        self.decoration = decoration
        self.boxSize = size
        super.init(key: key, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return _RenderCheckboxBox(decoration: decoration, fixedSize: boxSize)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! _RenderCheckboxBox
        ro.decoration = decoration
        ro.fixedSize = boxSize
    }
}

class _RenderCheckboxBox: RenderDecoratedBox {
    var fixedSize: Double {
        didSet {
            if fixedSize != oldValue { markNeedsLayout() }
        }
    }

    init(decoration: BoxDecoration, fixedSize: Double) {
        self.fixedSize = fixedSize
        super.init(decoration: decoration)
    }

    override func performLayout() {
        size = Size(fixedSize, fixedSize)
        if let child = child as? RenderBox {
            child.layout(BoxConstraints.tight(Size(fixedSize, fixedSize)), parentUsesSize: false)
        }
    }
}

// MARK: - CheckboxTheme

/// An inherited theme that controls how descendant Checkboxes look.
public class CheckboxTheme: InheritedTheme {
    /// The theme data for the checkbox theme.
    public let data: CheckboxThemeData

    public init(key: (any Key)? = nil, data: CheckboxThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest CheckboxThemeData which encloses the given context.
    public static func of(_ context: any BuildContext) -> CheckboxThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(CheckboxTheme.self)
        return CheckboxThemeData.standard(theme).merge(inherited?.data)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? CheckboxTheme else { return true }
        return data !== old.data
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return CheckboxTheme(data: data, child: child)
    }
}

// MARK: - CheckboxThemeData

/// Theme data for Checkbox widgets.
public class CheckboxThemeData {
    /// The decoration of the checkbox when it's checked.
    public let checkedDecoration: (any WidgetStateProperty<BoxDecoration?>)?

    /// The decoration of the checkbox when it's unchecked.
    public let uncheckedDecoration: (any WidgetStateProperty<BoxDecoration?>)?

    /// The decoration of the checkbox when it's in its third state.
    public let thirdstateDecoration: (any WidgetStateProperty<BoxDecoration?>)?

    /// The color of the icon when the checkbox is checked.
    public let checkedIconColor: (any WidgetStateProperty<Color?>)?

    /// The color of the icon when the checkbox is unchecked.
    public let uncheckedIconColor: (any WidgetStateProperty<Color?>)?

    /// The color of the icon when the checkbox is in its third state.
    public let thirdstateIconColor: (any WidgetStateProperty<Color?>)?

    /// The color of the content/foreground text.
    public let foregroundColor: (any WidgetStateProperty<Color?>)?

    /// The padding around the checkbox.
    public let padding: EdgeInsets?

    /// The margin around the checkbox.
    public let margin: EdgeInsets?

    public init(
        checkedDecoration: (any WidgetStateProperty<BoxDecoration?>)? = nil,
        uncheckedDecoration: (any WidgetStateProperty<BoxDecoration?>)? = nil,
        thirdstateDecoration: (any WidgetStateProperty<BoxDecoration?>)? = nil,
        checkedIconColor: (any WidgetStateProperty<Color?>)? = nil,
        uncheckedIconColor: (any WidgetStateProperty<Color?>)? = nil,
        thirdstateIconColor: (any WidgetStateProperty<Color?>)? = nil,
        foregroundColor: (any WidgetStateProperty<Color?>)? = nil,
        padding: EdgeInsets? = nil,
        margin: EdgeInsets? = nil
    ) {
        self.checkedDecoration = checkedDecoration
        self.uncheckedDecoration = uncheckedDecoration
        self.thirdstateDecoration = thirdstateDecoration
        self.checkedIconColor = checkedIconColor
        self.uncheckedIconColor = uncheckedIconColor
        self.thirdstateIconColor = thirdstateIconColor
        self.foregroundColor = foregroundColor
        self.padding = padding
        self.margin = margin
    }

    /// Creates the standard CheckboxThemeData based on the given theme.
    public static func standard(_ theme: FluentThemeData) -> CheckboxThemeData {
        let radius = BorderRadius.circular(4)
        return CheckboxThemeData(
            checkedDecoration: WidgetStatePropertyHelper.resolveWith({ states -> BoxDecoration? in
                BoxDecoration(
                    color: checkedInputColor(theme, states),
                    border: Border.all(
                        color: states.isDisabled
                            ? theme.resources.controlStrongStrokeColorDisabled
                            : checkedInputColor(theme, states)
                    ),
                    borderRadius: radius
                )
            }),
            uncheckedDecoration: WidgetStatePropertyHelper.resolveWith({ states -> BoxDecoration? in
                BoxDecoration(
                    color: Set<WidgetState>.forStates(
                        states,
                        disabled: theme.resources.controlAltFillColorDisabled,
                        none: theme.resources.controlAltFillColorSecondary,
                        pressed: theme.resources.controlAltFillColorQuarternary,
                        hovering: theme.resources.controlAltFillColorTertiary
                    ),
                    border: Border.all(
                        color: states.isDisabled || states.isPressed
                            ? theme.resources.controlStrongStrokeColorDisabled
                            : theme.resources.controlStrongStrokeColorDefault
                    ),
                    borderRadius: radius
                )
            }),
            thirdstateDecoration: WidgetStatePropertyHelper.resolveWith({ states -> BoxDecoration? in
                BoxDecoration(
                    color: checkedInputColor(theme, states),
                    border: Border.all(
                        color: states.isDisabled
                            ? theme.resources.controlStrongStrokeColorDisabled
                            : checkedInputColor(theme, states)
                    ),
                    borderRadius: radius
                )
            }),
            checkedIconColor: WidgetStatePropertyHelper.resolveWith({ states -> Color? in
                filledButtonForegroundColor(theme, states)
            }),
            uncheckedIconColor: WidgetStatePropertyAll<Color?>(Color(0x00000000)),
            foregroundColor: WidgetStatePropertyHelper.resolveWith({ states -> Color? in
                states.isDisabled ? theme.resources.textFillColorDisabled : nil
            })
        )
    }

    /// Merge this theme data with another, with the other taking precedence.
    public func merge(_ other: CheckboxThemeData?) -> CheckboxThemeData {
        guard let other = other else { return self }
        return CheckboxThemeData(
            checkedDecoration: other.checkedDecoration ?? checkedDecoration,
            uncheckedDecoration: other.uncheckedDecoration ?? uncheckedDecoration,
            thirdstateDecoration: other.thirdstateDecoration ?? thirdstateDecoration,
            checkedIconColor: other.checkedIconColor ?? checkedIconColor,
            uncheckedIconColor: other.uncheckedIconColor ?? uncheckedIconColor,
            thirdstateIconColor: other.thirdstateIconColor ?? thirdstateIconColor,
            foregroundColor: other.foregroundColor ?? foregroundColor,
            padding: other.padding ?? padding,
            margin: other.margin ?? margin
        )
    }
}

// MARK: - Shared color helpers (used by Checkbox, RadioButton, ToggleSwitch)

/// Returns the background color for checked input controls (checkbox, radio, toggle).
/// Equivalent to `ButtonThemeData.checkedInputColor` / `FilledButton.backgroundColor`.
func checkedInputColor(_ theme: FluentThemeData, _ states: Set<WidgetState>) -> Color {
    if states.isDisabled {
        return theme.resources.accentFillColorDisabled
    } else if states.isPressed {
        return theme.accentColor.tertiaryBrushFor(theme.brightness)
    } else if states.isHovered {
        return theme.accentColor.secondaryBrushFor(theme.brightness)
    } else {
        return theme.accentColor.defaultBrushFor(theme.brightness)
    }
}

/// Returns the foreground color for filled buttons / checked icon color.
/// Equivalent to `FilledButton.foregroundColor`.
func filledButtonForegroundColor(_ theme: FluentThemeData, _ states: Set<WidgetState>) -> Color {
    let res = theme.resources
    if states.isPressed {
        return res.textOnAccentFillColorSecondary
    } else if states.isHovered {
        return res.textOnAccentFillColorPrimary
    } else if states.isDisabled {
        return res.textOnAccentFillColorDisabled
    }
    return res.textOnAccentFillColorPrimary
}


// MARK: - _CheckMarkPainter

/// WinUI's check mark: a stroked polyline in the box's unit square, round
/// caps and joins, the ink at the control's stroke width.
private final class _CheckMarkPainter: CustomPainter {
    let color: Color

    init(color: Color) {
        self.color = color
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let paint = Paint()
        paint.color = color
        paint.style = .stroke
        paint.strokeWidth = max(1.5, size.width * 0.14)
        paint.strokeCap = .round
        paint.strokeJoin = .round
        let path = Path()
        path.moveTo(size.width * 0.18, size.height * 0.52)
        path.lineTo(size.width * 0.42, size.height * 0.76)
        path.lineTo(size.width * 0.84, size.height * 0.28)
        canvas.drawPath(path, paint)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        (oldDelegate as? _CheckMarkPainter)?.color != color
    }
}
