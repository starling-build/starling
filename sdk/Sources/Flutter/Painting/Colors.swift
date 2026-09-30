// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// HSV/HSL color types, ColorSwatch, and ColorProperty.
///
/// **Dart Source:** `packages/flutter/lib/src/painting/colors.dart`

import FlutterSwiftBridge

// MARK: - Private Helper Functions

/// Dart-compatible modulo operation that always returns a non-negative result
/// when the divisor is positive. Swift's `truncatingRemainder` can return
/// negative values, but Dart's `%` operator does not.
private func _dartModulo(_ a: Double, _ n: Double) -> Double {
    var result = a.truncatingRemainder(dividingBy: n)
    if result < 0 { result += n }
    return result
}

/// Computes the hue component from RGB values.
///
/// **Dart Source:** `colors.dart:13-28`
private func _getHue(
    _ red: Double,
    _ green: Double,
    _ blue: Double,
    _ max: Double,
    _ delta: Double
) -> Double {
    var hue: Double
    if max == 0.0 {
        hue = 0.0
    } else if max == red {
        // Dart's `%` always returns non-negative for positive divisor.
        // Swift's truncatingRemainder can be negative, so we add 6 to ensure positive.
        var remainder = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        if remainder < 0 { remainder += 6 }
        hue = 60.0 * remainder
    } else if max == green {
        hue = 60.0 * (((blue - red) / delta) + 2)
    } else if max == blue {
        hue = 60.0 * (((red - green) / delta) + 4)
    } else {
        hue = 0.0
    }

    // Set hue to 0.0 when red == green == blue.
    if hue.isNaN {
        hue = 0.0
    }
    return hue
}

/// Converts hue-based color components to an RGB `Color`.
///
/// **Dart Source:** `colors.dart:30-45`
private func _colorFromHue(
    alpha: Double,
    hue: Double,
    chroma: Double,
    secondary: Double,
    match: Double
) -> Color {
    let red: Double
    let green: Double
    let blue: Double
    switch hue {
    case ..<60.0:
        (red, green, blue) = (chroma, secondary, 0.0)
    case ..<120.0:
        (red, green, blue) = (secondary, chroma, 0.0)
    case ..<180.0:
        (red, green, blue) = (0.0, chroma, secondary)
    case ..<240.0:
        (red, green, blue) = (0.0, secondary, chroma)
    case ..<300.0:
        (red, green, blue) = (secondary, 0.0, chroma)
    default:
        (red, green, blue) = (chroma, 0.0, secondary)
    }
    return Color(
        argb: Int((alpha * 0xFF).rounded()),
        Int(((red + match) * 0xFF).rounded()),
        Int(((green + match) * 0xFF).rounded()),
        Int(((blue + match) * 0xFF).rounded())
    )
}

// MARK: - HSVColor

/// A color represented using alpha, hue, saturation, and value.
///
/// **Dart Source:** `colors.dart:68-213`
///
/// An `HSVColor` is represented in a parameter space that's based on human
/// perception of color in pigments (e.g. paint and printer's ink). The
/// representation is useful for some color computations (e.g. rotating the hue
/// through the colors), because interpolation and picking of colors as red,
/// green, and blue channels doesn't always produce intuitive results.
///
/// See also:
///
///  - `HSLColor`, a color that uses a color space based on human perception of
///    colored light.
///  - [HSV and HSL](https://en.wikipedia.org/wiki/HSL_and_HSV) Wikipedia
///    article, which this implementation is based upon.
public struct HSVColor: Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// Alpha, from 0.0 to 1.0. Describes the transparency of the color.
    /// A value of 0.0 is fully transparent, and 1.0 is fully opaque.
    ///
    /// **Dart Source:** `colors.dart:103-105`
    public let alpha: Double

    /// Hue, from 0.0 to 360.0. Describes which color of the spectrum is
    /// represented. A value of 0.0 represents red, as does 360.0.
    ///
    /// **Dart Source:** `colors.dart:107-111`
    public let hue: Double

    /// Saturation, from 0.0 to 1.0. Describes how colorful the color is.
    /// 0.0 implies a shade of grey, and 1.0 implies a color as vibrant as
    /// that hue gets.
    ///
    /// **Dart Source:** `colors.dart:113-117`
    public let saturation: Double

    /// Value, from 0.0 to 1.0. Describes how bright a color is.
    /// A value of 0.0 indicates black, and 1.0 indicates full intensity color.
    ///
    /// **Dart Source:** `colors.dart:119-123`
    public let value: Double

    // MARK: - Initializer

    /// Creates an HSV color.
    ///
    /// **Dart Source:** `colors.dart:73-81`
    ///
    /// All the arguments must be in their respective ranges. See the fields for
    /// each parameter for a description of their ranges.
    public static func fromAHSV(
        _ alpha: Double,
        _ hue: Double,
        _ saturation: Double,
        _ value: Double
    ) -> HSVColor {
        assert(alpha >= 0.0 && alpha <= 1.0, "alpha must be in range 0.0...1.0")
        assert(hue >= 0.0 && hue <= 360.0, "hue must be in range 0.0...360.0")
        assert(saturation >= 0.0 && saturation <= 1.0, "saturation must be in range 0.0...1.0")
        assert(value >= 0.0 && value <= 1.0, "value must be in range 0.0...1.0")
        return HSVColor(alpha: alpha, hue: hue, saturation: saturation, value: value)
    }

    /// Private memberwise initializer.
    private init(alpha: Double, hue: Double, saturation: Double, value: Double) {
        self.alpha = alpha
        self.hue = hue
        self.saturation = saturation
        self.value = value
    }

    // MARK: - Factory Methods

    /// Creates an `HSVColor` from an RGB `Color`.
    ///
    /// **Dart Source:** `colors.dart:87-101`
    ///
    /// This method does not necessarily round-trip with `toColor` because
    /// of floating point imprecision.
    public static func fromColor(_ color: Color) -> HSVColor {
        let red = color.r
        let green = color.g
        let blue = color.b

        let maxVal = max(red, max(green, blue))
        let minVal = min(red, min(green, blue))
        let delta = maxVal - minVal

        let alpha = color.a
        let hue = _getHue(red, green, blue, maxVal, delta)
        let saturation = maxVal == 0.0 ? 0.0 : delta / maxVal

        return HSVColor.fromAHSV(alpha, hue, saturation, maxVal)
    }

    // MARK: - Copy Methods

    /// Returns a copy of this color with the `alpha` parameter replaced with the
    /// given value.
    ///
    /// **Dart Source:** `colors.dart:127-129`
    public func withAlpha(_ alpha: Double) -> HSVColor {
        return HSVColor.fromAHSV(alpha, hue, saturation, value)
    }

    /// Returns a copy of this color with the `hue` parameter replaced with the
    /// given value.
    ///
    /// **Dart Source:** `colors.dart:133-135`
    public func withHue(_ hue: Double) -> HSVColor {
        return HSVColor.fromAHSV(alpha, hue, saturation, value)
    }

    /// Returns a copy of this color with the `saturation` parameter replaced with
    /// the given value.
    ///
    /// **Dart Source:** `colors.dart:139-141`
    public func withSaturation(_ saturation: Double) -> HSVColor {
        return HSVColor.fromAHSV(alpha, hue, saturation, value)
    }

    /// Returns a copy of this color with the `value` parameter replaced with the
    /// given value.
    ///
    /// **Dart Source:** `colors.dart:145-147`
    public func withValue(_ value: Double) -> HSVColor {
        return HSVColor.fromAHSV(alpha, hue, saturation, value)
    }

    // MARK: - Conversion

    /// Returns this color in RGB.
    ///
    /// **Dart Source:** `colors.dart:150-156`
    public func toColor() -> Color {
        let chroma = saturation * value
        let secondary = chroma * (1.0 - Swift.abs(((hue / 60.0).truncatingRemainder(dividingBy: 2.0)) - 1.0))
        let match = value - chroma

        return _colorFromHue(alpha: alpha, hue: hue, chroma: chroma, secondary: secondary, match: match)
    }

    // MARK: - Private Methods

    /// Scales the alpha value by the given factor.
    ///
    /// **Dart Source:** `colors.dart:158-160`
    private func _scaleAlpha(_ factor: Double) -> HSVColor {
        return withAlpha(alpha * factor)
    }

    // MARK: - Static Methods

    /// Linearly interpolate between two HSVColors.
    ///
    /// **Dart Source:** `colors.dart:178-194`
    ///
    /// The colors are interpolated by interpolating the alpha, hue,
    /// saturation, and value channels separately, which usually leads to a
    /// more pleasing effect than `Color.lerp`.
    ///
    /// If either color is nil, this function linearly interpolates from a
    /// transparent instance of the other color.
    ///
    /// Values outside of the valid range for each channel will be clamped.
    public static func lerp(_ a: HSVColor?, _ b: HSVColor?, _ t: Double) -> HSVColor? {
        if a == b {
            return a
        }
        if a == nil {
            return b!._scaleAlpha(t)
        }
        if b == nil {
            return a!._scaleAlpha(1.0 - t)
        }
        return HSVColor.fromAHSV(
            clampDouble(lerpDouble(a!.alpha, b!.alpha, t)!, 0.0, 1.0),
            _dartModulo(lerpDouble(a!.hue, b!.hue, t)!, 360.0),
            clampDouble(lerpDouble(a!.saturation, b!.saturation, t)!, 0.0, 1.0),
            clampDouble(lerpDouble(a!.value, b!.value, t)!, 0.0, 1.0)
        )
    }

    // MARK: - Equatable

    /// Compares two HSVColors for equality.
    ///
    /// **Dart Source:** `colors.dart:196-206`
    public static func == (lhs: HSVColor, rhs: HSVColor) -> Bool {
        return lhs.alpha == rhs.alpha &&
               lhs.hue == rhs.hue &&
               lhs.saturation == rhs.saturation &&
               lhs.value == rhs.value
    }

    // MARK: - Hashable

    /// **Dart Source:** `colors.dart:209`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(alpha)
        hasher.combine(hue)
        hasher.combine(saturation)
        hasher.combine(value)
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this HSV color.
    ///
    /// **Dart Source:** `colors.dart:212`
    public var description: String {
        "HSVColor(\(alpha), \(hue), \(saturation), \(value))"
    }
}

// MARK: - HSLColor

/// A color represented using alpha, hue, saturation, and lightness.
///
/// **Dart Source:** `colors.dart:236-397`
///
/// An `HSLColor` is represented in a parameter space that's based on human
/// perception of colored light. The representation is useful for some color
/// computations (e.g., combining colors of light), because interpolation and
/// picking of colors as red, green, and blue channels doesn't always produce
/// intuitive results.
///
/// See also:
///
///  - `HSVColor`, a color that uses a color space based on human perception of
///    pigments (e.g. paint and printer's ink).
///  - [HSV and HSL](https://en.wikipedia.org/wiki/HSL_and_HSV) Wikipedia
///    article, which this implementation is based upon.
public struct HSLColor: Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// Alpha, from 0.0 to 1.0. Describes the transparency of the color.
    /// A value of 0.0 is fully transparent, and 1.0 is fully opaque.
    ///
    /// **Dart Source:** `colors.dart:274-276`
    public let alpha: Double

    /// Hue, from 0.0 to 360.0. Describes which color of the spectrum is
    /// represented. A value of 0.0 represents red, as does 360.0.
    ///
    /// **Dart Source:** `colors.dart:278-282`
    public let hue: Double

    /// Saturation, from 0.0 to 1.0. Describes how colorful the color is.
    /// 0.0 implies a shade of grey, and 1.0 implies a color as vibrant as
    /// that hue gets.
    ///
    /// **Dart Source:** `colors.dart:284-288`
    public let saturation: Double

    /// Lightness, from 0.0 to 1.0. Describes how bright a color is.
    /// A value of 0.0 indicates black, and 1.0 indicates white.
    ///
    /// **Dart Source:** `colors.dart:290-296`
    public let lightness: Double

    // MARK: - Initializer

    /// Creates an HSL color.
    ///
    /// **Dart Source:** `colors.dart:241-249`
    ///
    /// All the arguments must be in their respective ranges. See the fields for
    /// each parameter for a description of their ranges.
    public static func fromAHSL(
        _ alpha: Double,
        _ hue: Double,
        _ saturation: Double,
        _ lightness: Double
    ) -> HSLColor {
        assert(alpha >= 0.0 && alpha <= 1.0, "alpha must be in range 0.0...1.0")
        assert(hue >= 0.0 && hue <= 360.0, "hue must be in range 0.0...360.0")
        assert(saturation >= 0.0 && saturation <= 1.0, "saturation must be in range 0.0...1.0")
        assert(lightness >= 0.0 && lightness <= 1.0, "lightness must be in range 0.0...1.0")
        return HSLColor(alpha: alpha, hue: hue, saturation: saturation, lightness: lightness)
    }

    /// Private memberwise initializer.
    private init(alpha: Double, hue: Double, saturation: Double, lightness: Double) {
        self.alpha = alpha
        self.hue = hue
        self.saturation = saturation
        self.lightness = lightness
    }

    // MARK: - Factory Methods

    /// Creates an `HSLColor` from an RGB `Color`.
    ///
    /// **Dart Source:** `colors.dart:255-272`
    ///
    /// This method does not necessarily round-trip with `toColor` because
    /// of floating point imprecision.
    public static func fromColor(_ color: Color) -> HSLColor {
        let red = color.r
        let green = color.g
        let blue = color.b

        let maxVal = max(red, max(green, blue))
        let minVal = min(red, min(green, blue))
        let delta = maxVal - minVal

        let alpha = color.a
        let hue = _getHue(red, green, blue, maxVal, delta)
        let lightness = (maxVal + minVal) / 2.0
        // Saturation can exceed 1.0 with rounding errors, so clamp it.
        let saturation = minVal == maxVal
            ? 0.0
            : clampDouble(delta / (1.0 - Swift.abs(2.0 * lightness - 1.0)), 0.0, 1.0)
        return HSLColor.fromAHSL(alpha, hue, saturation, lightness)
    }

    // MARK: - Copy Methods

    /// Returns a copy of this color with the `alpha` parameter replaced with the
    /// given value.
    ///
    /// **Dart Source:** `colors.dart:300-302`
    public func withAlpha(_ alpha: Double) -> HSLColor {
        return HSLColor.fromAHSL(alpha, hue, saturation, lightness)
    }

    /// Returns a copy of this color with the `hue` parameter replaced with the
    /// given value.
    ///
    /// **Dart Source:** `colors.dart:306-308`
    public func withHue(_ hue: Double) -> HSLColor {
        return HSLColor.fromAHSL(alpha, hue, saturation, lightness)
    }

    /// Returns a copy of this color with the `saturation` parameter replaced with
    /// the given value.
    ///
    /// **Dart Source:** `colors.dart:312-314`
    public func withSaturation(_ saturation: Double) -> HSLColor {
        return HSLColor.fromAHSL(alpha, hue, saturation, lightness)
    }

    /// Returns a copy of this color with the `lightness` parameter replaced with
    /// the given value.
    ///
    /// **Dart Source:** `colors.dart:318-320`
    public func withLightness(_ lightness: Double) -> HSLColor {
        return HSLColor.fromAHSL(alpha, hue, saturation, lightness)
    }

    // MARK: - Conversion

    /// Returns this HSL color in RGB.
    ///
    /// **Dart Source:** `colors.dart:323-329`
    public func toColor() -> Color {
        let chroma = (1.0 - Swift.abs(2.0 * lightness - 1.0)) * saturation
        let secondary = chroma * (1.0 - Swift.abs(((hue / 60.0).truncatingRemainder(dividingBy: 2.0)) - 1.0))
        let match = lightness - chroma / 2.0

        return _colorFromHue(alpha: alpha, hue: hue, chroma: chroma, secondary: secondary, match: match)
    }

    // MARK: - Private Methods

    /// Scales the alpha value by the given factor.
    ///
    /// **Dart Source:** `colors.dart:331-333`
    private func _scaleAlpha(_ factor: Double) -> HSLColor {
        return withAlpha(alpha * factor)
    }

    // MARK: - Static Methods

    /// Linearly interpolate between two HSLColors.
    ///
    /// **Dart Source:** `colors.dart:361-377`
    ///
    /// The colors are interpolated by interpolating the alpha, hue,
    /// saturation, and lightness channels separately, which usually leads to
    /// a more pleasing effect than `Color.lerp`.
    ///
    /// If either color is nil, this function linearly interpolates from a
    /// transparent instance of the other color.
    ///
    /// Values outside of the valid range for each channel will be clamped.
    public static func lerp(_ a: HSLColor?, _ b: HSLColor?, _ t: Double) -> HSLColor? {
        if a == b {
            return a
        }
        if a == nil {
            return b!._scaleAlpha(t)
        }
        if b == nil {
            return a!._scaleAlpha(1.0 - t)
        }
        return HSLColor.fromAHSL(
            clampDouble(lerpDouble(a!.alpha, b!.alpha, t)!, 0.0, 1.0),
            _dartModulo(lerpDouble(a!.hue, b!.hue, t)!, 360.0),
            clampDouble(lerpDouble(a!.saturation, b!.saturation, t)!, 0.0, 1.0),
            clampDouble(lerpDouble(a!.lightness, b!.lightness, t)!, 0.0, 1.0)
        )
    }

    // MARK: - Equatable

    /// Compares two HSLColors for equality.
    ///
    /// **Dart Source:** `colors.dart:379-389`
    public static func == (lhs: HSLColor, rhs: HSLColor) -> Bool {
        return lhs.alpha == rhs.alpha &&
               lhs.hue == rhs.hue &&
               lhs.saturation == rhs.saturation &&
               lhs.lightness == rhs.lightness
    }

    // MARK: - Hashable

    /// **Dart Source:** `colors.dart:392`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(alpha)
        hasher.combine(hue)
        hasher.combine(saturation)
        hasher.combine(lightness)
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this HSL color.
    ///
    /// **Dart Source:** `colors.dart:395-396`
    public var description: String {
        "HSLColor(\(alpha), \(hue), \(saturation), \(lightness))"
    }
}

/// Integer-based color lerp matching old Dart Color.lerp behavior.
/// Uses truncation (Int conversion) rather than rounding, consistent with
/// how Dart's Color.lerp historically operated on integer ARGB channels.
///
/// **Dart Source:** `colors.dart:466-487` (used internally by ColorSwatch.lerp)
private func _lerpColorARGB32(_ a: Color?, _ b: Color?, _ t: Double) -> Color? {
    if b == nil {
        if a == nil {
            return nil
        }
        let factor = 1.0 - t
        let alphaInt = Int(clampDouble(Double(a!.toARGB32() >> 24 & 0xFF) * factor, 0, 255))
        let redInt = a!.toARGB32() >> 16 & 0xFF
        let greenInt = a!.toARGB32() >> 8 & 0xFF
        let blueInt = a!.toARGB32() & 0xFF
        return Color(argb: alphaInt, redInt, greenInt, blueInt)
    }
    if a == nil {
        let alphaInt = Int(clampDouble(Double(b!.toARGB32() >> 24 & 0xFF) * t, 0, 255))
        let redInt = b!.toARGB32() >> 16 & 0xFF
        let greenInt = b!.toARGB32() >> 8 & 0xFF
        let blueInt = b!.toARGB32() & 0xFF
        return Color(argb: alphaInt, redInt, greenInt, blueInt)
    }
    let aVal = a!.toARGB32()
    let bVal = b!.toARGB32()
    let alphaA = Double(aVal >> 24 & 0xFF)
    let alphaB = Double(bVal >> 24 & 0xFF)
    let redA = Double(aVal >> 16 & 0xFF)
    let redB = Double(bVal >> 16 & 0xFF)
    let greenA = Double(aVal >> 8 & 0xFF)
    let greenB = Double(bVal >> 8 & 0xFF)
    let blueA = Double(aVal & 0xFF)
    let blueB = Double(bVal & 0xFF)
    return Color(
        argb: Int(clampDouble(lerpDouble(alphaA, alphaB, t)!, 0, 255)),
        Int(clampDouble(lerpDouble(redA, redB, t)!, 0, 255)),
        Int(clampDouble(lerpDouble(greenA, greenB, t)!, 0, 255)),
        Int(clampDouble(lerpDouble(blueA, blueB, t)!, 0, 255))
    )
}

// MARK: - ColorSwatch

/// A color that has a small table of related colors called a "swatch".
///
/// **Dart Source:** `colors.dart:410-488`
///
/// The table is accessed by key values of type `T`.
///
/// Note: In Dart, `ColorSwatch<T>` extends `Color`. In Swift, since we cannot
/// subclass structs, we store the primary color value and provide access to
/// the primary color through a computed property.
public struct ColorSwatch<T: Hashable>: Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// The 32-bit ARGB value of the primary color in this swatch.
    ///
    /// **Dart Source:** `colors.dart:417`
    public let value: Int

    /// The swatch dictionary mapping keys to colors.
    ///
    /// **Dart Source:** `colors.dart:419-420`
    private let _swatch: [T: Color]

    // MARK: - Initializer

    /// Creates a color swatch with the given primary value and swatch map.
    ///
    /// **Dart Source:** `colors.dart:417`
    ///
    /// The `primary` argument should be the 32 bit ARGB value of one of the
    /// values in the swatch, as would be passed to the `Color` constructor.
    // Int64, not Int: 0xFF…… does not fit a 32-bit Int (wasm32).
    public init(_ primary: Int64, _ swatch: [T: Color]) {
        self.value = Int(truncatingIfNeeded: primary)
        self._swatch = swatch
    }

    // MARK: - Computed Properties

    /// The primary `Color` of this swatch, constructed from `value`.
    public var color: Color {
        Color(value)
    }

    /// Returns the valid keys for accessing the swatch via subscript.
    ///
    /// **Dart Source:** `colors.dart:426`
    public var keys: Dictionary<T, Color>.Keys {
        _swatch.keys
    }

    // MARK: - Subscript

    /// Returns an element of the swatch table.
    ///
    /// **Dart Source:** `colors.dart:423`
    public subscript(key: T) -> Color? {
        _swatch[key]
    }

    // MARK: - Static Methods

    /// Linearly interpolate between two `ColorSwatch`es.
    ///
    /// **Dart Source:** `colors.dart:466-487`
    ///
    /// It delegates to `Color.lerp` to interpolate the different colors of the
    /// swatch.
    ///
    /// If either color is nil, this function linearly interpolates from a
    /// transparent instance of the other color.
    public static func lerp(_ a: ColorSwatch<T>?, _ b: ColorSwatch<T>?, _ t: Double) -> ColorSwatch<T>? {
        if a == b {
            return a
        }
        let swatch: [T: Color]
        if b == nil {
            swatch = a!._swatch.reduce(into: [T: Color]()) { result, entry in
                result[entry.key] = _lerpColorARGB32(entry.value, nil, t)!
            }
        } else if a == nil {
            swatch = b!._swatch.reduce(into: [T: Color]()) { result, entry in
                result[entry.key] = _lerpColorARGB32(nil, entry.value, t)!
            }
        } else {
            swatch = a!._swatch.reduce(into: [T: Color]()) { result, entry in
                result[entry.key] = _lerpColorARGB32(entry.value, b![entry.key], t)!
            }
        }
        let lerpedColor = _lerpColorARGB32(
            a != nil ? a!.color : nil,
            b != nil ? b!.color : nil,
            t
        )!
        return ColorSwatch<T>(Int64(lerpedColor.toARGB32()), swatch)
    }

    // MARK: - Equatable

    /// Compares two ColorSwatches for equality.
    ///
    /// **Dart Source:** `colors.dart:429-437`
    public static func == (lhs: ColorSwatch<T>, rhs: ColorSwatch<T>) -> Bool {
        return lhs.value == rhs.value && lhs._swatch == rhs._swatch
    }

    // MARK: - Hashable

    /// **Dart Source:** `colors.dart:440`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(_swatch)
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this color swatch.
    ///
    /// **Dart Source:** `colors.dart:443-444`
    public var description: String {
        "ColorSwatch(primary value: \(Color(value)))"
    }
}

// MARK: - ColorProperty

/// `DiagnosticsProperty` that has a `Color` as value.
///
/// **Dart Source:** `colors.dart:491-515`
public class ColorProperty: DiagnosticsProperty<Color> {

    /// Create a diagnostics property for `Color`.
    ///
    /// **Dart Source:** `colors.dart:493-500`
    public init(
        _ name: String,
        _ value: Color?,
        showName: Bool = true,
        defaultValue: Any? = nil,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            name,
            value,
            showName: showName,
            defaultValue: defaultValue,
            style: style,
            level: level
        )
    }

    /// Converts this property to a JSON map, including color value properties.
    ///
    /// **Dart Source:** `colors.dart:502-514`
    public override func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        #if !DEBUG
        return [:]
        #else
        var json = super.toJsonMap(delegate: delegate)
        if let colorValue = typedValue {
            json["valueProperties"] = [
                "alpha": Int((colorValue.a * 255.0).rounded()),
                "red": Int((colorValue.r * 255.0).rounded()),
                "green": Int((colorValue.g * 255.0).rounded()),
                "blue": Int((colorValue.b * 255.0).rounded()),
            ] as [String: Any]
        }
        return json
        #endif
    }
}
