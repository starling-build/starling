// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/inputs/slider.dart

import FlutterSwiftBridge

// MARK: - Slider

/// A slider lets the user select from a range of values by moving a thumb
/// control along a track.
///
/// Use a slider when you want users to set a value from a continuous range,
/// like volume, brightness, or zoom level.
public class Slider: StatefulWidget {
    /// The currently selected value for this slider.
    public let value: Double

    /// Called during a drag when the user is selecting a new value.
    /// If nil, the slider will be displayed as disabled.
    public let onChanged: ((Double) -> Void)?

    /// Called when the user starts selecting a new value.
    public let onChangeStart: ((Double) -> Void)?

    /// Called when the user is done selecting a new value.
    public let onChangeEnd: ((Double) -> Void)?

    /// The minimum value the user can select. Defaults to 0.
    public let min: Double

    /// The maximum value the user can select. Defaults to 100.
    public let max: Double

    /// The number of discrete divisions. If nil, the slider is continuous.
    public let divisions: Int?

    /// A label to show above the slider thumb.
    public let label: String?

    /// The style used in this slider.
    public let style: SliderThemeData?

    public init(
        key: (any Key)? = nil,
        value: Double,
        onChanged: ((Double) -> Void)?,
        onChangeStart: ((Double) -> Void)? = nil,
        onChangeEnd: ((Double) -> Void)? = nil,
        min: Double = 0.0,
        max: Double = 100.0,
        divisions: Int? = nil,
        label: String? = nil,
        style: SliderThemeData? = nil
    ) {
        self.value = value
        self.onChanged = onChanged
        self.onChangeStart = onChangeStart
        self.onChangeEnd = onChangeEnd
        self.min = min
        self.max = max
        self.divisions = divisions
        self.label = label
        self.style = style
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _SliderState()
    }
}

// MARK: - _SliderState

class _SliderState: State<StatefulWidget> {
    private var slider: Slider {
        return widget as! Slider
    }

    private var isDisabled: Bool {
        return slider.onChanged == nil
    }

    /// Whether a drag is currently in progress.
    private var isDragging: Bool = false

    override func build(_ context: any BuildContext) -> Widget {
        let resolvedStyle = SliderTheme.of(context).merge(slider.style)

        let sliderHeight: Double = 32.0
        let thumbRadius: Double = 10.0

        return HoverButton(
            builder: { [self] context, states in
                let activeColor = resolvedStyle.activeColor?.resolve(states)
                    ?? checkedInputColor(FluentTheme.of(context), states)
                let inactiveColor = resolvedStyle.inactiveColor?.resolve(states)
                    ?? FluentTheme.of(context).resources.controlStrongFillColorDefault
                let thumbColor = resolvedStyle.thumbColor?.resolve(states)
                    ?? checkedInputColor(FluentTheme.of(context), states)
                let trackHeight = resolvedStyle.trackHeight?.resolve(states) ?? 4.0

                let painter = _SliderPainter(
                    value: slider.value,
                    min: slider.min,
                    max: slider.max,
                    divisions: slider.divisions,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    thumbColor: thumbColor,
                    trackHeight: trackHeight,
                    thumbRadius: thumbRadius,
                    borderColor: FluentTheme.of(context).resources.controlSolidFillColorDefault,
                    isDisabled: isDisabled,
                    isHovered: states.isHovered,
                    isPressed: isDragging || states.isPressed
                )

                let child: Widget = Listener(
                    onPointerDown: { [self] event in
                        if isDisabled { return }
                        isDragging = true
                        slider.onChangeStart?(slider.value)
                        _updateFromPosition(event.localPosition)
                    },
                    onPointerMove: { [self] event in
                        if isDisabled || !isDragging { return }
                        _updateFromPosition(event.localPosition)
                    },
                    onPointerUp: { [self] event in
                        if isDisabled { return }
                        isDragging = false
                        slider.onChangeEnd?(slider.value)
                        setState {}
                    },
                    behavior: .opaque,
                    child: CustomPaint(
                        painter: painter,
                        size: Size(0, sliderHeight),
                        child: SizedBox(height: sliderHeight)
                    )
                )

                return FocusBorder(
                    child: child,
                    focused: states.isFocused
                )
            },
            onPressed: isDisabled ? nil : {},
            semanticLabel: slider.label ?? "Slider",
            onArrow: { [self] dx, dy in
                guard !isDisabled else { return false }
                let d = dx != 0 ? dx : -dy
                if d == 0 { return false }
                let range = slider.max - slider.min
                let step = slider.divisions.map { range / Double(Swift.max($0, 1)) } ?? range / 20
                slider.onChanged?((slider.value + Double(d) * step).clamped(to: slider.min...slider.max))
                return true
            }
        )
    }

    private func _updateFromPosition(_ localPosition: Offset) {
        // localPosition is relative to the Listener's render object.
        // The track uses thumbRadius as padding on each side.
        // Get the actual width from the render tree (available after layout).
        let trackPadding: Double = 10.0
        let width = context?.size?.width ?? 300.0
        let trackWidth = width - 2 * trackPadding
        let fraction = ((localPosition.dx - trackPadding) / trackWidth).clamped(to: 0.0...1.0)

        var newValue = slider.min + fraction * (slider.max - slider.min)

        // Snap to divisions if set
        if let divisions = slider.divisions, divisions > 0 {
            let step = (slider.max - slider.min) / Double(divisions)
            newValue = (newValue / step).rounded() * step
        }

        newValue = newValue.clamped(to: slider.min...slider.max)
        slider.onChanged?(newValue)
    }
}

// MARK: - Double.clamped

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - _SliderPainter

/// Custom painter that draws the slider track and thumb.
class _SliderPainter: CustomPainter {
    let value: Double
    let min: Double
    let max: Double
    let divisions: Int?
    let activeColor: Color
    let inactiveColor: Color
    let thumbColor: Color
    let trackHeight: Double
    let thumbRadius: Double
    let borderColor: Color
    let isDisabled: Bool
    let isHovered: Bool
    let isPressed: Bool

    init(
        value: Double,
        min: Double,
        max: Double,
        divisions: Int?,
        activeColor: Color,
        inactiveColor: Color,
        thumbColor: Color,
        trackHeight: Double,
        thumbRadius: Double,
        borderColor: Color,
        isDisabled: Bool,
        isHovered: Bool,
        isPressed: Bool
    ) {
        self.value = value
        self.min = min
        self.max = max
        self.divisions = divisions
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.thumbColor = thumbColor
        self.trackHeight = trackHeight
        self.thumbRadius = thumbRadius
        self.borderColor = borderColor
        self.isDisabled = isDisabled
        self.isHovered = isHovered
        self.isPressed = isPressed
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let trackPadding: Double = thumbRadius
        let trackLeft = trackPadding
        let trackRight = size.width - trackPadding
        let trackWidth = trackRight - trackLeft
        let centerY = size.height / 2.0

        // Compute the fraction for the current value
        let range = max - min
        let fraction: Double = range > 0 ? (value - min) / range : 0
        let thumbX = trackLeft + fraction * trackWidth

        // Draw inactive track (full width)
        let inactivePaint = Paint()
        inactivePaint.color = inactiveColor
        inactivePaint.strokeWidth = trackHeight
        inactivePaint.strokeCap = .round
        inactivePaint.style = .stroke

        canvas.drawLine(
            Offset(trackLeft, centerY),
            Offset(trackRight, centerY),
            inactivePaint
        )

        // Draw active track (from left to thumb)
        if fraction > 0 {
            let activePaint = Paint()
            activePaint.color = activeColor
            activePaint.strokeWidth = trackHeight
            activePaint.strokeCap = .round
            activePaint.style = .stroke

            canvas.drawLine(
                Offset(trackLeft, centerY),
                Offset(thumbX, centerY),
                activePaint
            )
        }

        // Draw division ticks if divisions is set
        if let divisions = divisions, divisions > 0 {
            let tickPaint = Paint()
            tickPaint.color = borderColor
            tickPaint.style = .fill
            let tickRadius: Double = 2.0

            for i in 0...divisions {
                let tickFraction = Double(i) / Double(divisions)
                let tickX = trackLeft + tickFraction * trackWidth
                canvas.drawCircle(Offset(tickX, centerY), tickRadius, tickPaint)
            }
        }

        // Draw thumb border (outer circle)
        let borderPaint = Paint()
        borderPaint.color = borderColor
        borderPaint.style = .fill
        canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, borderPaint)

        // Draw thumb inner circle
        let innerRadius: Double
        if isPressed {
            innerRadius = thumbRadius * 0.45
        } else if isHovered {
            innerRadius = thumbRadius * 0.66
        } else {
            innerRadius = thumbRadius * 0.5
        }

        let thumbPaint = Paint()
        thumbPaint.color = thumbColor
        thumbPaint.style = .fill
        canvas.drawCircle(Offset(thumbX, centerY), innerRadius, thumbPaint)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? _SliderPainter else { return true }
        return value != old.value
            || min != old.min
            || max != old.max
            || divisions != old.divisions
            || activeColor != old.activeColor
            || inactiveColor != old.inactiveColor
            || thumbColor != old.thumbColor
            || trackHeight != old.trackHeight
            || isDisabled != old.isDisabled
            || isHovered != old.isHovered
            || isPressed != old.isPressed
    }
}

// MARK: - SliderTheme

/// An inherited theme that controls how descendant Sliders look.
public class SliderTheme: InheritedTheme {
    /// The theme data for the slider theme.
    public let data: SliderThemeData

    public init(key: (any Key)? = nil, data: SliderThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest SliderThemeData which encloses the given context.
    public static func of(_ context: any BuildContext) -> SliderThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(SliderTheme.self)
        return SliderThemeData.standard(theme).merge(inherited?.data)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? SliderTheme else { return true }
        return data !== old.data
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return SliderTheme(data: data, child: child)
    }
}

// MARK: - SliderThemeData

/// Theme data for Slider widgets.
public class SliderThemeData {
    /// The color of the slider thumb.
    public let thumbColor: (any WidgetStateProperty<Color?>)?

    /// The color of the active (filled) portion of the track.
    public let activeColor: (any WidgetStateProperty<Color?>)?

    /// The color of the inactive (unfilled) portion of the track.
    public let inactiveColor: (any WidgetStateProperty<Color?>)?

    /// The height of the slider track.
    public let trackHeight: (any WidgetStateProperty<Double?>)?

    /// The margin around the slider.
    public let margin: EdgeInsets?

    /// The color of the label background.
    public let labelBackgroundColor: Color?

    /// The color of the label text.
    public let labelForegroundColor: Color?

    public init(
        thumbColor: (any WidgetStateProperty<Color?>)? = nil,
        activeColor: (any WidgetStateProperty<Color?>)? = nil,
        inactiveColor: (any WidgetStateProperty<Color?>)? = nil,
        trackHeight: (any WidgetStateProperty<Double?>)? = nil,
        margin: EdgeInsets? = nil,
        labelBackgroundColor: Color? = nil,
        labelForegroundColor: Color? = nil
    ) {
        self.thumbColor = thumbColor
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.trackHeight = trackHeight
        self.margin = margin
        self.labelBackgroundColor = labelBackgroundColor
        self.labelForegroundColor = labelForegroundColor
    }

    /// Creates the standard SliderThemeData based on the given theme.
    public static func standard(_ theme: FluentThemeData) -> SliderThemeData {
        return SliderThemeData(
            thumbColor: WidgetStatePropertyHelper.resolveWith({ states -> Color? in
                checkedInputColor(theme, states)
            }),
            activeColor: WidgetStatePropertyHelper.resolveWith({ states -> Color? in
                checkedInputColor(theme, states)
            }),
            inactiveColor: WidgetStatePropertyHelper.resolveWith({ states -> Color? in
                if states.isDisabled {
                    return theme.resources.controlStrongFillColorDisabled
                }
                return theme.resources.controlStrongFillColorDefault
            }),
            trackHeight: WidgetStatePropertyHelper.all(3.75 as Double?),
            margin: EdgeInsets(),
            labelBackgroundColor: theme.resources.controlSolidFillColorDefault,
            labelForegroundColor: theme.resources.textFillColorPrimary
        )
    }

    /// Merge this theme data with another, with the other taking precedence.
    public func merge(_ other: SliderThemeData?) -> SliderThemeData {
        guard let other = other else { return self }
        return SliderThemeData(
            thumbColor: other.thumbColor ?? thumbColor,
            activeColor: other.activeColor ?? activeColor,
            inactiveColor: other.inactiveColor ?? inactiveColor,
            trackHeight: other.trackHeight ?? trackHeight,
            margin: other.margin ?? margin,
            labelBackgroundColor: other.labelBackgroundColor ?? labelBackgroundColor,
            labelForegroundColor: other.labelForegroundColor ?? labelForegroundColor
        )
    }
}
