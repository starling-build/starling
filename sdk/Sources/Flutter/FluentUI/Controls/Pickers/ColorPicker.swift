// Ported from: fluent_ui/lib/src/controls/pickers/color_picker/color_picker.dart
//
// Simplified ColorPicker — no text editing. Uses CustomPaint for the color
// spectrum and value/alpha sliders. Drag interaction via Listener.

import FlutterSwiftBridge

// MARK: - ColorPickerThemeData

/// Theme data for the color picker.
public struct ColorPickerThemeData: Equatable {
    /// The width/height of the color spectrum area.
    public let spectrumSize: Double

    /// The height of the sliders.
    public let sliderHeight: Double

    /// The size of the thumb indicator on the spectrum.
    public let thumbRadius: Double

    public init(
        spectrumSize: Double = 256,
        sliderHeight: Double = 16,
        thumbRadius: Double = 8
    ) {
        self.spectrumSize = spectrumSize
        self.sliderHeight = sliderHeight
        self.thumbRadius = thumbRadius
    }

    public static func == (lhs: ColorPickerThemeData, rhs: ColorPickerThemeData) -> Bool {
        return lhs.spectrumSize == rhs.spectrumSize
            && lhs.sliderHeight == rhs.sliderHeight
            && lhs.thumbRadius == rhs.thumbRadius
    }
}

// MARK: - ColorPickerTheme

/// An InheritedWidget that provides ColorPickerThemeData to descendants.
public class ColorPickerTheme: InheritedWidget {
    public let data: ColorPickerThemeData

    public init(
        key: (any Key)? = nil,
        data: ColorPickerThemeData,
        child: Widget
    ) {
        self.data = data
        super.init(key: key, child: child)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        let old = oldWidget as! ColorPickerTheme
        return data != old.data
    }

    public static func of(_ context: any BuildContext) -> ColorPickerThemeData {
        let inherited = context.dependOnInheritedWidgetOfExactType(ColorPickerTheme.self) as? ColorPickerTheme
        return inherited?.data ?? ColorPickerThemeData()
    }
}

// MARK: - ColorPicker

/// A control for selecting colors from a spectrum.
///
/// Displays a 2D hue/saturation spectrum, a value slider, and optionally an
/// alpha slider. The current color is shown as a preview swatch. Hex and RGB
/// values are displayed as read-only text.
public class ColorPicker: StatefulWidget {
    /// The current color value.
    public let color: Color

    /// Called when the color changes.
    public let onChanged: ((Color) -> Void)?

    /// Whether the alpha channel slider is enabled.
    public let isAlphaEnabled: Bool

    /// Whether the color spectrum is visible.
    public let isColorSpectrumVisible: Bool

    /// Whether the value slider is visible.
    public let isColorSliderVisible: Bool

    /// Whether the "more" button is visible (simplified: always false).
    public let isMoreButtonVisible: Bool

    /// Creates a color picker.
    public init(
        key: (any Key)? = nil,
        color: Color,
        onChanged: ((Color) -> Void)? = nil,
        isAlphaEnabled: Bool = false,
        isColorSpectrumVisible: Bool = true,
        isColorSliderVisible: Bool = true,
        isMoreButtonVisible: Bool = false
    ) {
        self.color = color
        self.onChanged = onChanged
        self.isAlphaEnabled = isAlphaEnabled
        self.isColorSpectrumVisible = isColorSpectrumVisible
        self.isColorSliderVisible = isColorSliderVisible
        self.isMoreButtonVisible = isMoreButtonVisible
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _ColorPickerState()
    }
}

// MARK: - _ColorPickerState

class _ColorPickerState: State<StatefulWidget> {
    private var picker: ColorPicker {
        return widget as! ColorPicker
    }

    /// Internal HSV representation.
    private var _hue: Double = 0        // 0..360
    private var _saturation: Double = 1  // 0..1
    private var _value: Double = 1       // 0..1
    private var _alpha: Double = 1       // 0..1

    override func initState() {
        super.initState()
        _syncFromColor(picker.color)
    }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        let oldPicker = oldWidget as! ColorPicker
        if oldPicker.color != picker.color {
            _syncFromColor(picker.color)
        }
    }

    private func _syncFromColor(_ color: Color) {
        let hsv = HSVColor.fromColor(color)
        _hue = hsv.hue
        _saturation = hsv.saturation
        _value = hsv.value
        _alpha = color.a
    }

    private func _currentColor() -> Color {
        let hsv = HSVColor.fromAHSV(_alpha, _hue, _saturation, _value)
        return hsv.toColor()
    }

    private func _notifyChange() {
        picker.onChanged?(_currentColor())
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let pickerTheme = ColorPickerTheme.of(context)
        let spectrumSize = pickerTheme.spectrumSize

        var columnChildren: [Widget] = []

        // Color spectrum
        if picker.isColorSpectrumVisible {
            columnChildren.append(
                _buildSpectrumAndPreview(context, spectrumSize: spectrumSize)
            )
        }

        // Value slider
        if picker.isColorSliderVisible {
            columnChildren.append(SizedBox(height: 16))
            columnChildren.append(
                _buildValueSlider(context, width: spectrumSize, height: pickerTheme.sliderHeight)
            )
        }

        // Alpha slider
        if picker.isAlphaEnabled {
            columnChildren.append(SizedBox(height: 16))
            columnChildren.append(
                _buildAlphaSlider(context, width: spectrumSize, height: pickerTheme.sliderHeight)
            )
        }

        // Hex / RGB display
        columnChildren.append(SizedBox(height: 16))
        columnChildren.append(_buildColorInfo(context))

        return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: columnChildren
        )
    }

    // MARK: - Spectrum + Preview

    private func _buildSpectrumAndPreview(_ context: any BuildContext, spectrumSize: Double) -> Widget {
        let theme = FluentTheme.of(context)
        let previewSize: Double = 44
        let spacing: Double = 12

        let spectrum: Widget = SizedBox(
            width: spectrumSize,
            height: spectrumSize,
            child: _ColorSpectrumWidget(
                hue: _hue,
                saturation: _saturation,
                value: _value,
                onChanged: { [self] h, s in
                    setState {
                        _hue = h
                        _saturation = s
                    }
                    _notifyChange()
                }
            )
        )

        // Preview swatch
        let currentColor = _currentColor()
        let preview: Widget = SizedBox(
            width: previewSize,
            height: spectrumSize,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: currentColor,
                    border: Border.all(
                        color: theme.resources.dividerStrokeColorDefault,
                        width: 2
                    ),
                    borderRadius: BorderRadius.circular(4)
                )
            )
        )

        return Row(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
                spectrum,
                SizedBox(width: spacing),
                preview,
            ]
        )
    }

    // MARK: - Value Slider

    private func _buildValueSlider(_ context: any BuildContext, width: Double, height: Double) -> Widget {
        return SizedBox(
            width: width,
            height: height,
            child: _ColorSliderWidget(
                gradientColors: [
                    Color(0xFF000000),
                    HSVColor.fromAHSV(1, _hue, _saturation, 1).toColor(),
                ],
                currentPosition: _value,
                onChanged: { [self] v in
                    setState {
                        _value = v
                    }
                    _notifyChange()
                }
            )
        )
    }

    // MARK: - Alpha Slider

    private func _buildAlphaSlider(_ context: any BuildContext, width: Double, height: Double) -> Widget {
        let baseColor = HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor()

        return SizedBox(
            width: width,
            height: height,
            child: _ColorSliderWidget(
                gradientColors: [
                    baseColor.withValues(alpha: 0),
                    baseColor.withValues(alpha: 1),
                ],
                currentPosition: _alpha,
                onChanged: { [self] a in
                    setState {
                        _alpha = a
                    }
                    _notifyChange()
                }
            )
        )
    }

    // MARK: - Color Info

    private func _buildColorInfo(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let color = _currentColor()

        let rInt = Int((color.r * 255).rounded())
        let gInt = Int((color.g * 255).rounded())
        let bInt = Int((color.b * 255).rounded())
        let aInt = Int((color.a * 255).rounded())

        // One component per call: the web build's String(format:) takes a
        // single argument (Flutter/Foundation/WebSupport.swift).
        let hex = { (v: Int) in String(format: "%02X", v) }
        let hexString = "#" + (picker.isAlphaEnabled ? hex(aInt) : "")
            + hex(rInt) + hex(gInt) + hex(bInt)

        let textColor = theme.resources.textFillColorSecondary
        let labelStyle = TextStyle(color: textColor, fontSize: 12)
        let valueStyle = TextStyle(
            color: theme.resources.textFillColorPrimary,
            fontSize: 12
        )

        var infoChildren: [Widget] = [
            Row(
                children: [
                    Text("Hex: ", style: labelStyle),
                    Text(hexString, style: valueStyle),
                ]
            ),
            SizedBox(height: 4),
            Row(
                children: [
                    Text("RGB: ", style: labelStyle),
                    Text("\(rInt), \(gInt), \(bInt)", style: valueStyle),
                ]
            ),
            SizedBox(height: 4),
            Row(
                children: [
                    Text("HSV: ", style: labelStyle),
                    Text(
                        "\(Int(_hue.rounded()))\u{00B0}, "
                            + "\(Int((_saturation * 100).rounded()))%, "
                            + "\(Int((_value * 100).rounded()))%",
                        style: valueStyle
                    ),
                ]
            ),
        ]

        if picker.isAlphaEnabled {
            infoChildren.append(SizedBox(height: 4))
            infoChildren.append(
                Row(
                    children: [
                        Text("Alpha: ", style: labelStyle),
                        Text("\(Int((_alpha * 100).rounded()))%", style: valueStyle),
                    ]
                )
            )
        }

        return Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: infoChildren
        )
    }
}

// MARK: - _ColorSpectrumWidget

/// A 2D hue (x-axis) / saturation (y-axis) color spectrum rendered with
/// CustomPaint. A thumb indicator shows the current selection. Supports drag.
private class _ColorSpectrumWidget: StatefulWidget {
    let hue: Double
    let saturation: Double
    let value: Double
    let onChanged: (Double, Double) -> Void

    init(
        key: (any Key)? = nil,
        hue: Double,
        saturation: Double,
        value: Double,
        onChanged: @escaping (Double, Double) -> Void
    ) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
        self.onChanged = onChanged
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _ColorSpectrumWidgetState()
    }
}

class _ColorSpectrumWidgetState: State<StatefulWidget> {
    private var spectrum: _ColorSpectrumWidget {
        return widget as! _ColorSpectrumWidget
    }

    override func build(_ context: any BuildContext) -> Widget {
        let painter = _SpectrumPainter(
            hue: spectrum.hue,
            saturation: spectrum.saturation,
            value: spectrum.value
        )

        return Listener(
            onPointerDown: { [self] event in
                _handlePointer(event.position, context)
            },
            onPointerMove: { [self] event in
                _handlePointer(event.position, context)
            },
            behavior: .opaque,
            child: CustomPaint(
                painter: painter,
                size: .zero
            )
        )
    }

    private func _handlePointer(_ globalPosition: Offset, _ context: any BuildContext) {
        guard let renderBox = context.findRenderObject() as? RenderBox else { return }
        let localPos = renderBox.globalToLocal(globalPosition)
        let size = renderBox.size

        let hue = _clampDouble(localPos.dx / size.width, 0, 1) * 360
        let sat = 1.0 - _clampDouble(localPos.dy / size.height, 0, 1)

        spectrum.onChanged(hue, sat)
    }
}

// MARK: - _SpectrumPainter

/// Draws a hue (x) / saturation (y) gradient, plus a circular thumb at the
/// current position.
private class _SpectrumPainter: CustomPainter {
    let hue: Double
    let saturation: Double
    let value: Double

    init(hue: Double, saturation: Double, value: Double) {
        self.hue = hue
        self.saturation = saturation
        self.value = value
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let width = size.width
        let height = size.height

        // Draw horizontal hue stripes blended with vertical saturation.
        // We approximate by drawing vertical slices (columns).
        let steps = Int(min(width, 180))
        guard steps > 0 else { return }
        let sliceWidth = width / Double(steps)

        for i in 0..<steps {
            let hueVal = Double(i) / Double(steps) * 360.0
            let x = Double(i) * sliceWidth

            // Top (full saturation) to bottom (zero saturation) gradient
            let topColor = HSVColor.fromAHSV(1, hueVal, 1, 1).toColor()
            let bottomColor = HSVColor.fromAHSV(1, hueVal, 0, 1).toColor()

            let gradient = Gradient(
                linear: Offset(x, 0),
                to: Offset(x, height),
                colors: [topColor, bottomColor]
            )

            let slicePaint = Paint()
            slicePaint.shader = gradient
            canvas.drawRect(
                Rect.fromLTWH(x, 0, sliceWidth + 1, height),
                slicePaint
            )
        }

        // Draw border
        let borderPaint = Paint()
        borderPaint.color = Color(0x33000000)
        borderPaint.style = .stroke
        borderPaint.strokeWidth = 1
        canvas.drawRect(Rect.fromLTWH(0, 0, width, height), borderPaint)

        // Draw thumb
        let thumbX = (hue / 360.0) * width
        let thumbY = (1.0 - saturation) * height

        // Outer ring (white)
        let outerPaint = Paint()
        outerPaint.color = Color(0xFFFFFFFF)
        outerPaint.style = .stroke
        outerPaint.strokeWidth = 3
        canvas.drawCircle(Offset(thumbX, thumbY), 8, outerPaint)

        // Inner ring (dark)
        let innerPaint = Paint()
        innerPaint.color = Color(0xFF333333)
        innerPaint.style = .stroke
        innerPaint.strokeWidth = 1
        canvas.drawCircle(Offset(thumbX, thumbY), 8, innerPaint)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? _SpectrumPainter else { return true }
        return old.hue != hue || old.saturation != saturation || old.value != value
    }
}

// MARK: - _ColorSliderWidget

/// A horizontal slider with a gradient background. Drag interaction via Listener.
private class _ColorSliderWidget: StatefulWidget {
    let gradientColors: [Color]
    let currentPosition: Double  // 0..1
    let onChanged: (Double) -> Void

    init(
        key: (any Key)? = nil,
        gradientColors: [Color],
        currentPosition: Double,
        onChanged: @escaping (Double) -> Void
    ) {
        self.gradientColors = gradientColors
        self.currentPosition = currentPosition
        self.onChanged = onChanged
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> {
        return _ColorSliderWidgetState()
    }
}

class _ColorSliderWidgetState: State<StatefulWidget> {
    private var colorSlider: _ColorSliderWidget {
        return widget as! _ColorSliderWidget
    }

    override func build(_ context: any BuildContext) -> Widget {
        let painter = _ColorSliderPainter(
            gradientColors: colorSlider.gradientColors,
            position: colorSlider.currentPosition
        )

        return Listener(
            onPointerDown: { [self] event in
                _handlePointer(event.position, context)
            },
            onPointerMove: { [self] event in
                _handlePointer(event.position, context)
            },
            behavior: .opaque,
            child: CustomPaint(
                painter: painter,
                size: .zero
            )
        )
    }

    private func _handlePointer(_ globalPosition: Offset, _ context: any BuildContext) {
        guard let renderBox = context.findRenderObject() as? RenderBox else { return }
        let localPos = renderBox.globalToLocal(globalPosition)
        let size = renderBox.size

        let fraction = _clampDouble(localPos.dx / size.width, 0, 1)
        colorSlider.onChanged(fraction)
    }
}

// MARK: - _ColorSliderPainter

/// Draws a horizontal gradient bar with a circular thumb.
private class _ColorSliderPainter: CustomPainter {
    let gradientColors: [Color]
    let position: Double  // 0..1

    init(gradientColors: [Color], position: Double) {
        self.gradientColors = gradientColors
        self.position = position
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let width = size.width
        let height = size.height
        let cornerRadius: Double = 6

        // Draw gradient background
        let bgRect = Rect.fromLTWH(0, 0, width, height)
        let gradient = Gradient(
            linear: Offset(0, 0),
            to: Offset(width, 0),
            colors: gradientColors
        )

        let bgPaint = Paint()
        bgPaint.shader = gradient
        canvas.drawRRect(
            RRect(fromRectAndRadius: bgRect, Radius(circular: cornerRadius)),
            bgPaint
        )

        // Border
        let borderPaint = Paint()
        borderPaint.color = Color(0x33000000)
        borderPaint.style = .stroke
        borderPaint.strokeWidth = 1
        canvas.drawRRect(
            RRect(fromRectAndRadius: bgRect, Radius(circular: cornerRadius)),
            borderPaint
        )

        // Thumb
        let thumbX = position * width
        let thumbY = height / 2

        let thumbOuterPaint = Paint()
        thumbOuterPaint.color = Color(0xFFFFFFFF)
        thumbOuterPaint.style = .fill
        canvas.drawCircle(Offset(thumbX, thumbY), 8, thumbOuterPaint)

        let thumbBorderPaint = Paint()
        thumbBorderPaint.color = Color(0xFF666666)
        thumbBorderPaint.style = .stroke
        thumbBorderPaint.strokeWidth = 1.5
        canvas.drawCircle(Offset(thumbX, thumbY), 8, thumbBorderPaint)

        // Inner filled circle with the color at this position
        let colorAtPos: Color
        if gradientColors.count >= 2 {
            let t = position
            let startColor = gradientColors[0]
            let endColor = gradientColors[gradientColors.count - 1]
            colorAtPos = Color(
                alpha: startColor.a + (endColor.a - startColor.a) * t,
                red: startColor.r + (endColor.r - startColor.r) * t,
                green: startColor.g + (endColor.g - startColor.g) * t,
                blue: startColor.b + (endColor.b - startColor.b) * t
            )
        } else {
            colorAtPos = gradientColors.first ?? Color(0xFF000000)
        }

        let innerPaint = Paint()
        innerPaint.color = colorAtPos
        canvas.drawCircle(Offset(thumbX, thumbY), 5, innerPaint)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? _ColorSliderPainter else { return true }
        return old.position != position || old.gradientColors != gradientColors
    }
}

// MARK: - Private helper

/// Clamp a double value to [minVal, maxVal].
private func _clampDouble(_ value: Double, _ minVal: Double, _ maxVal: Double) -> Double {
    return Swift.min(Swift.max(value, minVal), maxVal)
}
