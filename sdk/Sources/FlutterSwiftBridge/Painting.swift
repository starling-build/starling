// Painting.swift
// Flutter Swift Bridge
//
// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`

import Foundation
import FlutterSwiftBridgeCxx

// MARK: - Color

/// An immutable color value in ARGB format.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:60-511`
/// **Original Name:** `Color`
///
/// Consider the light teal of the Flutter logo. It is fully opaque, with a red `r` channel
/// value of `0.2588` (or `0x42` or `66` as an 8-bit value), a green `g` channel value of
/// `0.6471` (or `0xA5` or `165` as an 8-bit value), and a blue `b` channel value of
/// `0.9608` (or `0xF5` or `245` as an 8-bit value).
///
/// Here are some ways it could be constructed:
///
/// ```swift
/// let c1 = Color(from: 1.0, red: 0.2588, green: 0.6471, blue: 0.9608)
/// let c2 = Color(0xFF42A5F5)
/// let c3 = Color(argb: 0xFF, 0x42, 0xA5, 0xF5)
/// let c4 = Color(argb: 255, 66, 165, 245)
/// let c5 = Color(rgbo: 66, 165, 245, 1.0)
/// ```
///
/// `Color`'s color components are stored as floating-point values. Care should be taken
/// if one does not want the literal equality provided by `==` operator.
///
/// See also:
///
///  * `Colors` in Flutter's material library, which defines the colors found in the
///    Material Design specification.
public struct Color: Hashable, Sendable {
    /// The alpha channel of this color.
    ///
    /// **Dart Source:** `painting.dart:202-203`
    public let a: Double

    /// The red channel of this color.
    ///
    /// **Dart Source:** `painting.dart:205-206`
    public let r: Double

    /// The green channel of this color.
    ///
    /// **Dart Source:** `painting.dart:208-209`
    public let g: Double

    /// The blue channel of this color.
    ///
    /// **Dart Source:** `painting.dart:211-212`
    public let b: Double

    /// The color space of this color.
    ///
    /// **Dart Source:** `painting.dart:214-215`
    public let colorSpace: ColorSpace

    // MARK: - Initializers

    /// Construct an sRGB color from the lower 32 bits of an Int.
    ///
    /// **Dart Source:** `painting.dart:105-129`
    /// **Original:** `Color(int value)`
    ///
    /// The bits are interpreted as follows:
    ///
    /// * Bits 24-31 are the alpha value.
    /// * Bits 16-23 are the red value.
    /// * Bits 8-15 are the green value.
    /// * Bits 0-7 are the blue value.
    ///
    /// In other words, if AA is the alpha value in hex, RR the red value in hex,
    /// GG the green value in hex, and BB the blue value in hex, a color can be
    /// expressed as `Color(0xAARRGGBB)`.
    public init(_ value: Int) {
        self.init(
            argbComponents: value >> 24,
            value >> 16,
            value >> 8,
            value,
            colorSpace: .sRGB
        )
    }

    /// Construct a color with floating-point color components.
    ///
    /// **Dart Source:** `painting.dart:131-158`
    /// **Original:** `Color.from(...)`
    ///
    /// Color components allows arbitrary bit depths for color components to be
    /// supported. The values are interpreted relative to the `ColorSpace` argument.
    public init(
        alpha: Double,
        red: Double,
        green: Double,
        blue: Double,
        colorSpace: ColorSpace = .sRGB
    ) {
        self.a = alpha
        self.r = red
        self.g = green
        self.b = blue
        self.colorSpace = colorSpace
    }

    /// Construct an sRGB color from the lower 8 bits of four integers.
    ///
    /// **Dart Source:** `painting.dart:160-174`
    /// **Original:** `Color.fromARGB(int a, int r, int g, int b)`
    ///
    /// * `a` is the alpha value, with 0 being transparent and 255 being fully opaque.
    /// * `r` is red, from 0 to 255.
    /// * `g` is green, from 0 to 255.
    /// * `b` is blue, from 0 to 255.
    ///
    /// Out of range values are brought into range using modulo 255.
    public init(argb a: Int, _ r: Int, _ g: Int, _ b: Int) {
        self.init(argbComponents: a, r, g, b, colorSpace: .sRGB)
    }

    /// Create an sRGB color from red, green, blue, and opacity, similar to `rgba()` in CSS.
    ///
    /// **Dart Source:** `painting.dart:179-194`
    /// **Original:** `Color.fromRGBO(int r, int g, int b, double opacity)`
    ///
    /// * `r` is red, from 0 to 255.
    /// * `g` is green, from 0 to 255.
    /// * `b` is blue, from 0 to 255.
    /// * `opacity` is alpha channel of this color as a double, with 0.0 being
    ///   transparent and 1.0 being fully opaque.
    ///
    /// Out of range values are brought into range using modulo 255.
    public init(rgbo r: Int, _ g: Int, _ b: Int, _ opacity: Double) {
        self.init(rgboComponents: r, g, b, opacity, colorSpace: .sRGB)
    }

    // MARK: - Private Initializers

    /// Private initializer from ARGB components.
    ///
    /// **Dart Source:** `painting.dart:176-177`
    /// **Original:** `Color._fromARGBC(...)`
    private init(argbComponents alpha: Int, _ red: Int, _ green: Int, _ blue: Int, colorSpace: ColorSpace) {
        self.init(
            rgboComponents: red,
            green,
            blue,
            Double(alpha & 0xff) / 255,
            colorSpace: colorSpace
        )
    }

    /// Private initializer from RGBO components.
    ///
    /// **Dart Source:** `painting.dart:196-200`
    /// **Original:** `Color._fromRGBOC(...)`
    private init(rgboComponents r: Int, _ g: Int, _ b: Int, _ opacity: Double, colorSpace: ColorSpace) {
        self.a = opacity
        self.r = Double(r & 0xff) / 255
        self.g = Double(g & 0xff) / 255
        self.b = Double(b & 0xff) / 255
        self.colorSpace = colorSpace
    }

    // MARK: - Private Helpers

    /// Converts a floating point color component to an 8-bit integer.
    ///
    /// **Dart Source:** `painting.dart:217-219`
    /// **Original:** `static int _floatToInt8(double x)`
    private static func floatToInt8(_ x: Double) -> Int {
        return max(0, min(255, Int((x * 255.0).rounded())))
    }

    // MARK: - Computed Properties

    /// A 32 bit value representing this color.
    ///
    /// **Dart Source:** `painting.dart:221-226`
    /// **Original:** `int get value`
    ///
    /// This getter is deprecated. Use component accessors like `.r` or `.g`, or
    /// `toARGB32()` for an explicit conversion.
    @available(*, deprecated, message: "Use component accessors like .r or .g, or toARGB32() for an explicit conversion")
    public var value: Int {
        return toARGB32()
    }

    /// Returns a 32-bit value representing this color.
    ///
    /// **Dart Source:** `painting.dart:228-260`
    /// **Original:** `int toARGB32()`
    ///
    /// The returned value is compatible with the default constructor (`Color(_:)`)
    /// but does _not_ guarantee to result in the same color due to imprecisions
    /// in numeric conversions.
    ///
    /// The bits are assigned as follows:
    ///
    /// * Bits 24-31 represents the `a` channel as an 8-bit unsigned integer.
    /// * Bits 16-23 represents the `r` channel as an 8-bit unsigned integer.
    /// * Bits 8-15 represents the `g` channel as an 8-bit unsigned integer.
    /// * Bits 0-7 represents the `b` channel as an 8-bit unsigned integer.
    public func toARGB32() -> Int {
        return Self.floatToInt8(a) << 24 |
            Self.floatToInt8(r) << 16 |
            Self.floatToInt8(g) << 8 |
            Self.floatToInt8(b) << 0
    }

    /// The alpha channel of this color in an 8 bit value.
    ///
    /// **Dart Source:** `painting.dart:262-267`
    /// **Original:** `int get alpha`
    ///
    /// A value of 0 means this color is fully transparent. A value of 255 means
    /// this color is fully opaque.
    @available(*, deprecated, message: "Use (*.a * 255.0).rounded().clamped(to: 0...255)")
    public var alpha: Int {
        return (0xff000000 & value) >> 24
    }

    /// The alpha channel of this color as a double.
    ///
    /// **Dart Source:** `painting.dart:269-274`
    /// **Original:** `double get opacity`
    ///
    /// A value of 0.0 means this color is fully transparent. A value of 1.0 means
    /// this color is fully opaque.
    @available(*, deprecated, message: "Use .a")
    public var opacity: Double {
        return Double(alpha) / 0xFF
    }

    /// The red channel of this color in an 8 bit value.
    ///
    /// **Dart Source:** `painting.dart:276-278`
    /// **Original:** `int get red`
    @available(*, deprecated, message: "Use (*.r * 255.0).rounded().clamped(to: 0...255)")
    public var red: Int {
        return (0x00ff0000 & value) >> 16
    }

    /// The green channel of this color in an 8 bit value.
    ///
    /// **Dart Source:** `painting.dart:280-282`
    /// **Original:** `int get green`
    @available(*, deprecated, message: "Use (*.g * 255.0).rounded().clamped(to: 0...255)")
    public var green: Int {
        return (0x0000ff00 & value) >> 8
    }

    /// The blue channel of this color in an 8 bit value.
    ///
    /// **Dart Source:** `painting.dart:284-286`
    /// **Original:** `int get blue`
    @available(*, deprecated, message: "Use (*.b * 255.0).rounded().clamped(to: 0...255)")
    public var blue: Int {
        return (0x000000ff & value) >> 0
    }

    // MARK: - Methods

    /// Returns a new color with the provided components updated.
    ///
    /// **Dart Source:** `painting.dart:288-326`
    /// **Original:** `Color withValues(...)`
    ///
    /// Each component (`alpha`, `red`, `green`, `blue`) represents a floating-point value.
    ///
    /// If `colorSpace` is provided, and is different than the current color space,
    /// the component values are updated before transforming them to the provided `ColorSpace`.
    public func withValues(
        alpha: Double? = nil,
        red: Double? = nil,
        green: Double? = nil,
        blue: Double? = nil,
        colorSpace: ColorSpace? = nil
    ) -> Color {
        var updatedComponents: Color? = nil
        if alpha != nil || red != nil || green != nil || blue != nil {
            updatedComponents = Color(
                alpha: alpha ?? a,
                red: red ?? r,
                green: green ?? g,
                blue: blue ?? b,
                colorSpace: self.colorSpace
            )
        }
        if let targetColorSpace = colorSpace, targetColorSpace != self.colorSpace {
            let transform = ColorTransform.getColorTransform(from: self.colorSpace, to: targetColorSpace)
            return transform.transform(color: updatedComponents ?? self, resultColorSpace: targetColorSpace)
        } else {
            return updatedComponents ?? self
        }
    }

    /// Returns a new color that matches this color with the alpha channel
    /// replaced with `a` (which ranges from 0 to 255).
    ///
    /// **Dart Source:** `painting.dart:328-334`
    /// **Original:** `Color withAlpha(int a)`
    ///
    /// Out of range values will have unexpected effects.
    public func withAlpha(_ a: Int) -> Color {
        return Color(argb: a, red, green, blue)
    }

    /// Returns a new color that matches this color with the alpha channel
    /// replaced with the given `opacity` (which ranges from 0.0 to 1.0).
    ///
    /// **Dart Source:** `painting.dart:336-344`
    /// **Original:** `Color withOpacity(double opacity)`
    ///
    /// Out of range values will have unexpected effects.
    @available(*, deprecated, message: "Use .withValues() to avoid precision loss.")
    public func withOpacity(_ opacity: Double) -> Color {
        assert(opacity >= 0.0 && opacity <= 1.0)
        return withAlpha(Int((255.0 * opacity).rounded()))
    }

    /// Returns a new color that matches this color with the red channel replaced
    /// with `r` (which ranges from 0 to 255).
    ///
    /// **Dart Source:** `painting.dart:346-352`
    /// **Original:** `Color withRed(int r)`
    ///
    /// Out of range values will have unexpected effects.
    public func withRed(_ r: Int) -> Color {
        return Color(argb: alpha, r, green, blue)
    }

    /// Returns a new color that matches this color with the green channel
    /// replaced with `g` (which ranges from 0 to 255).
    ///
    /// **Dart Source:** `painting.dart:354-360`
    /// **Original:** `Color withGreen(int g)`
    ///
    /// Out of range values will have unexpected effects.
    public func withGreen(_ g: Int) -> Color {
        return Color(argb: alpha, red, g, blue)
    }

    /// Returns a new color that matches this color with the blue channel replaced
    /// with `b` (which ranges from 0 to 255).
    ///
    /// **Dart Source:** `painting.dart:362-368`
    /// **Original:** `Color withBlue(int b)`
    ///
    /// Out of range values will have unexpected effects.
    public func withBlue(_ b: Int) -> Color {
        return Color(argb: alpha, red, green, b)
    }

    /// Returns a brightness value between 0 for darkest and 1 for lightest.
    ///
    /// **Dart Source:** `painting.dart:378-391`
    /// **Original:** `double computeLuminance()`
    ///
    /// Represents the relative luminance of the color. This value is computationally
    /// expensive to calculate.
    ///
    /// See https://en.wikipedia.org/wiki/Relative_luminance.
    public func computeLuminance() -> Double {
        assert(colorSpace != .extendedSRGB)
        // See <https://www.w3.org/TR/WCAG20/#relativeluminancedef>
        let R = Self.linearizeColorComponent(r)
        let G = Self.linearizeColorComponent(g)
        let B = Self.linearizeColorComponent(b)
        return 0.2126 * R + 0.7152 * G + 0.0722 * B
    }

    /// Linearizes a color component for luminance calculation.
    ///
    /// **Dart Source:** `painting.dart:370-376`
    /// **Original:** `static double _linearizeColorComponent(double component)`
    ///
    /// See https://www.w3.org/TR/WCAG20/#relativeluminancedef
    private static func linearizeColorComponent(_ component: Double) -> Double {
        if component <= 0.03928 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    // MARK: - Static Methods

    /// Linearly interpolate between two colors.
    ///
    /// **Dart Source:** `painting.dart:393-438`
    /// **Original:** `static Color? lerp(Color? x, Color? y, double t)`
    ///
    /// This is intended to be fast but as a result may be ugly. Consider
    /// `HSVColor` or writing custom logic for interpolating colors.
    ///
    /// If either color is nil, this function linearly interpolates from a
    /// transparent instance of the other color.
    ///
    /// The `t` argument represents position on the timeline, with 0.0 meaning
    /// that the interpolation has not started, returning `a` (or something
    /// equivalent to `a`), 1.0 meaning that the interpolation has finished,
    /// returning `b` (or something equivalent to `b`), and values in between
    /// meaning that the interpolation is at the relevant point on the timeline
    /// between `a` and `b`. The interpolation can be extrapolated beyond 0.0 and
    /// 1.0. Each channel will be clamped to the range 0 to 1.
    public static func lerp(_ x: Color?, _ y: Color?, _ t: Double) -> Color? {
        assert(x?.colorSpace != .extendedSRGB)
        assert(y?.colorSpace != .extendedSRGB)
        if y == nil {
            if x == nil {
                return nil
            } else {
                return scaleAlpha(x!, 1.0 - t)
            }
        } else {
            if x == nil {
                return scaleAlpha(y!, t)
            } else {
                assert(x!.colorSpace == y!.colorSpace)
                return Color(
                    alpha: clampDouble(_lerpDouble(x!.a, y!.a, t), 0, 1),
                    red: clampDouble(_lerpDouble(x!.r, y!.r, t), 0, 1),
                    green: clampDouble(_lerpDouble(x!.g, y!.g, t), 0, 1),
                    blue: clampDouble(_lerpDouble(x!.b, y!.b, t), 0, 1),
                    colorSpace: x!.colorSpace
                )
            }
        }
    }

    /// Combine the foreground color as a transparent color over top
    /// of a background color, and return the resulting combined color.
    ///
    /// **Dart Source:** `painting.dart:440-480`
    /// **Original:** `static Color alphaBlend(Color foreground, Color background)`
    ///
    /// This uses standard alpha blending ("SRC over DST") rules to produce a
    /// blended color from two colors.
    public static func alphaBlend(foreground: Color, background: Color) -> Color {
        assert(foreground.colorSpace == background.colorSpace)
        assert(foreground.colorSpace != .extendedSRGB)
        let alpha = foreground.a
        if alpha == 0 {
            // Foreground completely transparent.
            return background
        }
        let invAlpha = 1 - alpha
        var backAlpha = background.a
        if backAlpha == 1 {
            // Opaque background case
            return Color(
                alpha: 1,
                red: alpha * foreground.r + invAlpha * background.r,
                green: alpha * foreground.g + invAlpha * background.g,
                blue: alpha * foreground.b + invAlpha * background.b,
                colorSpace: foreground.colorSpace
            )
        } else {
            // General case
            backAlpha = backAlpha * invAlpha
            let outAlpha = alpha + backAlpha
            assert(outAlpha != 0)
            return Color(
                alpha: outAlpha,
                red: (foreground.r * alpha + background.r * backAlpha) / outAlpha,
                green: (foreground.g * alpha + background.g * backAlpha) / outAlpha,
                blue: (foreground.b * alpha + background.b * backAlpha) / outAlpha,
                colorSpace: foreground.colorSpace
            )
        }
    }

    /// Returns an alpha value representative of the provided `opacity` value.
    ///
    /// **Dart Source:** `painting.dart:482-487`
    /// **Original:** `static int getAlphaFromOpacity(double opacity)`
    public static func getAlphaFromOpacity(_ opacity: Double) -> Int {
        return Int((clampDouble(opacity, 0.0, 1.0) * 255).rounded())
    }

    // MARK: - CustomStringConvertible

    /// Returns a string representation of this color.
    ///
    /// **Dart Source:** `painting.dart:508-510`
    /// **Original:** `String toString()`
    public var description: String {
        return "Color(alpha: \(String(format: "%.4f", a)), red: \(String(format: "%.4f", r)), green: \(String(format: "%.4f", g)), blue: \(String(format: "%.4f", b)), colorSpace: \(colorSpace))"
    }
}

// MARK: - Color Helper Functions

/// Scales the alpha channel of a color by the given factor.
///
/// **Dart Source:** `painting.dart:56-58`
/// **Original:** `Color _scaleAlpha(Color x, double factor)`
private func scaleAlpha(_ x: Color, _ factor: Double) -> Color {
    return x.withValues(alpha: clampDouble(x.a * factor, 0, 1))
}

// MARK: - ColorTransform

/// Protocol for color space transformations.
///
/// **Dart Source:** `painting.dart:3835-3837`
/// **Original:** `abstract class _ColorTransform`
private protocol ColorTransformProtocol {
    func transform(color: Color, resultColorSpace: ColorSpace) -> Color
}

/// Namespace for color transform implementations.
///
/// **Dart Source:** `painting.dart:3835-3941`
private enum ColorTransform {
    /// Identity transform that returns the color unchanged.
    ///
    /// **Dart Source:** `painting.dart:3839-3843`
    /// **Original:** `class _IdentityColorTransform`
    struct Identity: ColorTransformProtocol {
        func transform(color: Color, resultColorSpace: ColorSpace) -> Color {
            return color
        }
    }

    /// Transform that clamps color components to [0, 1] after applying a child transform.
    ///
    /// **Dart Source:** `painting.dart:3845-3858`
    /// **Original:** `class _ClampTransform`
    struct Clamp: ColorTransformProtocol {
        let child: ColorTransformProtocol

        func transform(color: Color, resultColorSpace: ColorSpace) -> Color {
            let transformed = child.transform(color: color, resultColorSpace: resultColorSpace)
            return Color(
                alpha: clampDouble(transformed.a, 0, 1),
                red: clampDouble(transformed.r, 0, 1),
                green: clampDouble(transformed.g, 0, 1),
                blue: clampDouble(transformed.b, 0, 1),
                colorSpace: resultColorSpace
            )
        }
    }

    /// Matrix-based color transform.
    ///
    /// **Dart Source:** `painting.dart:3860-3876`
    /// **Original:** `class _MatrixColorTransform`
    struct Matrix: ColorTransformProtocol {
        /// Row-major matrix values.
        let values: [Double]

        func transform(color: Color, resultColorSpace: ColorSpace) -> Color {
            return Color(
                alpha: color.a,
                red: values[0] * color.r + values[1] * color.g + values[2] * color.b + values[3],
                green: values[4] * color.r + values[5] * color.g + values[6] * color.b + values[7],
                blue: values[8] * color.r + values[9] * color.g + values[10] * color.b + values[11],
                colorSpace: resultColorSpace
            )
        }
    }

    // MARK: - Transformation Matrices

    /// sRGB to Display P3 transformation matrix.
    ///
    /// **Dart Source:** `painting.dart:3898-3904`
    private static let srgbToP3 = Matrix(values: [
        0.808052267214446, 0.220292047628890, -0.139648846160100,
        0.145738111193222,
        0.096480880462996, 0.916386732581291, -0.086093928394828,
        0.089490172325882,
        -0.127099563510240, -0.068983484963878, 0.735426667591299, 0.233655661600230,
    ])

    /// Display P3 to sRGB transformation matrix.
    ///
    /// **Dart Source:** `painting.dart:3905-3911`
    private static let p3ToSrgb = Matrix(values: [
        1.306671048092539, -0.298061942172353, 0.213228303487995,
        -0.213580156254466,
        -0.117390025596251, 1.127722006101976, 0.109727644608938,
        -0.109450321455370,
        0.214813187718391, 0.054268702864647, 1.406898424029350, -0.364892765879631,
    ])

    /// Gets the appropriate color transform between two color spaces.
    ///
    /// **Dart Source:** `painting.dart:3878-3941`
    /// **Original:** `_ColorTransform _getColorTransform(ColorSpace source, ColorSpace destination)`
    static func getColorTransform(from source: ColorSpace, to destination: ColorSpace) -> ColorTransformProtocol {
        switch source {
        case .sRGB:
            switch destination {
            case .sRGB:
                return Identity()
            case .extendedSRGB:
                return Identity()
            case .displayP3:
                return srgbToP3
            }
        case .extendedSRGB:
            switch destination {
            case .sRGB:
                return Clamp(child: Identity())
            case .extendedSRGB:
                return Identity()
            case .displayP3:
                return Clamp(child: srgbToP3)
            }
        case .displayP3:
            switch destination {
            case .sRGB:
                return Clamp(child: p3ToSrgb)
            case .extendedSRGB:
                return p3ToSrgb
            case .displayP3:
                return Identity()
            }
        }
    }
}

// MARK: - Color Extension for CustomStringConvertible

extension Color: CustomStringConvertible {}

// MARK: - BlendMode

/// Algorithms to use when painting on the canvas.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:513-986`
/// **Original Name:** `BlendMode`
///
/// When drawing a shape or image onto a canvas, different algorithms can be
/// used to blend the pixels. The different values of `BlendMode` specify
/// different such algorithms.
///
/// Each algorithm has two inputs, the _source_, which is the image being drawn,
/// and the _destination_, which is the image into which the source image is
/// being composited. The destination is often thought of as the _background_.
/// The source and destination both have four color channels, the red, green,
/// blue, and alpha channels. These are typically represented as numbers in the
/// range 0.0 to 1.0. The output of the algorithm also has these same four
/// channels, with values computed from the source and destination.
///
/// ## Application to the Canvas API
///
/// When using `Canvas.saveLayer` and `Canvas.restore`, the blend mode of the
/// `Paint` given to the `Canvas.saveLayer` will be applied when
/// `Canvas.restore` is called. Each call to `Canvas.saveLayer` introduces a new
/// layer onto which shapes and images are painted; when `Canvas.restore` is
/// called, that layer is then composited onto the parent layer, with the source
/// being the most-recently-drawn shapes and images, and the destination being
/// the parent layer. (For the first `Canvas.saveLayer` call, the parent layer
/// is the canvas itself.)
///
/// See also:
///
///  * `Paint.blendMode`, which uses `BlendMode` to define the compositing
///    strategy.
public enum BlendMode: Int {
    // This list comes from Skia's SkXfermode.h and the values (order) should be
    // kept in sync.
    // See: https://skia.org/docs/user/api/skpaint_overview/#SkXfermode

    /// Drop both the source and destination images, leaving nothing.
    ///
    /// **Dart Source:** `painting.dart:567-572`
    ///
    /// This corresponds to the "clear" Porter-Duff operator.
    case clear

    /// Drop the destination image, only paint the source image.
    ///
    /// **Dart Source:** `painting.dart:574-582`
    ///
    /// Conceptually, the destination is first cleared, then the source image is
    /// painted.
    ///
    /// This corresponds to the "Copy" Porter-Duff operator.
    case src

    /// Drop the source image, only paint the destination image.
    ///
    /// **Dart Source:** `painting.dart:584-592`
    ///
    /// Conceptually, the source image is discarded, leaving the destination
    /// untouched.
    ///
    /// This corresponds to the "Destination" Porter-Duff operator.
    case dst

    /// Composite the source image over the destination image.
    ///
    /// **Dart Source:** `painting.dart:594-604`
    ///
    /// This is the default value. It represents the most intuitive case, where
    /// shapes are painted on top of what is below, with transparent areas showing
    /// the destination layer.
    ///
    /// This corresponds to the "Source over Destination" Porter-Duff operator,
    /// also known as the Painter's Algorithm.
    case srcOver

    /// Composite the source image under the destination image.
    ///
    /// **Dart Source:** `painting.dart:606-616`
    ///
    /// This is the opposite of `srcOver`.
    ///
    /// This corresponds to the "Destination over Source" Porter-Duff operator.
    ///
    /// This is useful when the source image should have been painted before the
    /// destination image, but could not be.
    case dstOver

    /// Show the source image, but only where the two images overlap. The
    /// destination image is not rendered, it is treated merely as a mask. The
    /// color channels of the destination are ignored, only the opacity has an
    /// effect.
    ///
    /// **Dart Source:** `painting.dart:618-632`
    ///
    /// To show the destination image instead, consider `dstIn`.
    ///
    /// To reverse the semantic of the mask (only showing the source where the
    /// destination is absent, rather than where it is present), consider
    /// `srcOut`.
    ///
    /// This corresponds to the "Source in Destination" Porter-Duff operator.
    case srcIn

    /// Show the destination image, but only where the two images overlap. The
    /// source image is not rendered, it is treated merely as a mask. The color
    /// channels of the source are ignored, only the opacity has an effect.
    ///
    /// **Dart Source:** `painting.dart:634-646`
    ///
    /// To show the source image instead, consider `srcIn`.
    ///
    /// To reverse the semantic of the mask (only showing the source where the
    /// destination is present, rather than where it is absent), consider `dstOut`.
    ///
    /// This corresponds to the "Destination in Source" Porter-Duff operator.
    case dstIn

    /// Show the source image, but only where the two images do not overlap. The
    /// destination image is not rendered, it is treated merely as a mask. The color
    /// channels of the destination are ignored, only the opacity has an effect.
    ///
    /// **Dart Source:** `painting.dart:648-660`
    ///
    /// To show the destination image instead, consider `dstOut`.
    ///
    /// To reverse the semantic of the mask (only showing the source where the
    /// destination is present, rather than where it is absent), consider `srcIn`.
    ///
    /// This corresponds to the "Source out Destination" Porter-Duff operator.
    case srcOut

    /// Show the destination image, but only where the two images do not overlap. The
    /// source image is not rendered, it is treated merely as a mask. The color
    /// channels of the source are ignored, only the opacity has an effect.
    ///
    /// **Dart Source:** `painting.dart:662-674`
    ///
    /// To show the source image instead, consider `srcOut`.
    ///
    /// To reverse the semantic of the mask (only showing the destination where the
    /// source is present, rather than where it is absent), consider `dstIn`.
    ///
    /// This corresponds to the "Destination out Source" Porter-Duff operator.
    case dstOut

    /// Composite the source image over the destination image, but only where it
    /// overlaps the destination.
    ///
    /// **Dart Source:** `painting.dart:676-689`
    ///
    /// This corresponds to the "Source atop Destination" Porter-Duff operator.
    ///
    /// This is essentially the `srcOver` operator, but with the output's opacity
    /// channel being set to that of the destination image instead of being a
    /// combination of both image's opacity channels.
    ///
    /// For a variant with the destination on top instead of the source, see
    /// `dstATop`.
    case srcATop

    /// Composite the destination image over the source image, but only where it
    /// overlaps the source.
    ///
    /// **Dart Source:** `painting.dart:691-704`
    ///
    /// This corresponds to the "Destination atop Source" Porter-Duff operator.
    ///
    /// This is essentially the `dstOver` operator, but with the output's opacity
    /// channel being set to that of the source image instead of being a
    /// combination of both image's opacity channels.
    ///
    /// For a variant with the source on top instead of the destination, see
    /// `srcATop`.
    case dstATop

    /// Apply a bitwise `xor` operator to the source and destination images. This
    /// leaves transparency where they would overlap.
    ///
    /// **Dart Source:** `painting.dart:706-712`
    ///
    /// This corresponds to the "Source xor Destination" Porter-Duff operator.
    case xor

    /// Sum the components of the source and destination images.
    ///
    /// **Dart Source:** `painting.dart:714-729`
    ///
    /// Transparency in a pixel of one of the images reduces the contribution of
    /// that image to the corresponding output pixel, as if the color of that
    /// pixel in that image was darker.
    ///
    /// This corresponds to the "Source plus Destination" Porter-Duff operator.
    ///
    /// This is the right blend mode for cross-fading between two images. Consider
    /// two images A and B, and an interpolation time variable _t_ (from 0.0 to
    /// 1.0). To cross fade between them, A should be drawn with opacity 1.0 - _t_
    /// into a new layer using `BlendMode.srcOver`, and B should be drawn on top
    /// of it, at opacity _t_, into the same layer, using `BlendMode.plus`.
    case plus

    /// Multiply the color components of the source and destination images.
    ///
    /// **Dart Source:** `painting.dart:731-750`
    ///
    /// This can only result in the same or darker colors (multiplying by white,
    /// 1.0, results in no change; multiplying by black, 0.0, results in black).
    ///
    /// When compositing two opaque images, this has similar effect to overlapping
    /// two transparencies on a projector.
    ///
    /// For a variant that also multiplies the alpha channel, consider `multiply`.
    ///
    /// See also:
    ///
    ///  * `screen`, which does a similar computation but inverted.
    ///  * `overlay`, which combines `modulate` and `screen` to favor the
    ///    destination image.
    ///  * `hardLight`, which combines `modulate` and `screen` to favor the
    ///    source image.
    case modulate

    // Following blend modes are defined in the CSS Compositing standard.

    /// Multiply the inverse of the components of the source and destination
    /// images, and inverse the result.
    ///
    /// **Dart Source:** `painting.dart:754-782`
    ///
    /// Inverting the components means that a fully saturated channel (opaque
    /// white) is treated as the value 0.0, and values normally treated as 0.0
    /// (black, transparent) are treated as 1.0.
    ///
    /// This is essentially the same as `modulate` blend mode, but with the values
    /// of the colors inverted before the multiplication and the result being
    /// inverted back before rendering.
    ///
    /// This can only result in the same or lighter colors (multiplying by black,
    /// 1.0, results in no change; multiplying by white, 0.0, results in white).
    /// Similarly, in the alpha channel, it can only result in more opaque colors.
    ///
    /// This has similar effect to two projectors displaying their images on the
    /// same screen simultaneously.
    ///
    /// See also:
    ///
    ///  * `modulate`, which does a similar computation but without inverting the
    ///    values.
    ///  * `overlay`, which combines `modulate` and `screen` to favor the
    ///    destination image.
    ///  * `hardLight`, which combines `modulate` and `screen` to favor the
    ///    source image.
    case screen // The last coeff mode.

    /// Multiply the components of the source and destination images after
    /// adjusting them to favor the destination.
    ///
    /// **Dart Source:** `painting.dart:783-803`
    ///
    /// Specifically, if the destination value is smaller, this multiplies it with
    /// the source value, whereas is the source value is smaller, it multiplies
    /// the inverse of the source value with the inverse of the destination value,
    /// then inverts the result.
    ///
    /// Inverting the components means that a fully saturated channel (opaque
    /// white) is treated as the value 0.0, and values normally treated as 0.0
    /// (black, transparent) are treated as 1.0.
    ///
    /// See also:
    ///
    ///  * `modulate`, which always multiplies the values.
    ///  * `screen`, which always multiplies the inverses of the values.
    ///  * `hardLight`, which is similar to `overlay` but favors the source image
    ///    instead of the destination image.
    case overlay

    /// Composite the source and destination image by choosing the lowest value
    /// from each color channel.
    ///
    /// **Dart Source:** `painting.dart:805-812`
    ///
    /// The opacity of the output image is computed in the same way as for
    /// `srcOver`.
    case darken

    /// Composite the source and destination image by choosing the highest value
    /// from each color channel.
    ///
    /// **Dart Source:** `painting.dart:814-821`
    ///
    /// The opacity of the output image is computed in the same way as for
    /// `srcOver`.
    case lighten

    /// Divide the destination by the inverse of the source.
    ///
    /// **Dart Source:** `painting.dart:823-830`
    ///
    /// Inverting the components means that a fully saturated channel (opaque
    /// white) is treated as the value 0.0, and values normally treated as 0.0
    /// (black, transparent) are treated as 1.0.
    case colorDodge

    /// Divide the inverse of the destination by the source, and inverse the result.
    ///
    /// **Dart Source:** `painting.dart:832-839`
    ///
    /// Inverting the components means that a fully saturated channel (opaque
    /// white) is treated as the value 0.0, and values normally treated as 0.0
    /// (black, transparent) are treated as 1.0.
    case colorBurn

    /// Multiply the components of the source and destination images after
    /// adjusting them to favor the source.
    ///
    /// **Dart Source:** `painting.dart:841-861`
    ///
    /// Specifically, if the source value is smaller, this multiplies it with the
    /// destination value, whereas is the destination value is smaller, it
    /// multiplies the inverse of the destination value with the inverse of the
    /// source value, then inverts the result.
    ///
    /// Inverting the components means that a fully saturated channel (opaque
    /// white) is treated as the value 0.0, and values normally treated as 0.0
    /// (black, transparent) are treated as 1.0.
    ///
    /// See also:
    ///
    ///  * `modulate`, which always multiplies the values.
    ///  * `screen`, which always multiplies the inverses of the values.
    ///  * `overlay`, which is similar to `hardLight` but favors the destination
    ///    image instead of the source image.
    case hardLight

    /// Use `colorDodge` for source values below 0.5 and `colorBurn` for source
    /// values above 0.5.
    ///
    /// **Dart Source:** `painting.dart:863-873`
    ///
    /// This results in a similar but softer effect than `overlay`.
    ///
    /// See also:
    ///
    ///  * `color`, which is a more subtle tinting effect.
    case softLight

    /// Subtract the smaller value from the bigger value for each channel.
    ///
    /// **Dart Source:** `painting.dart:875-886`
    ///
    /// Compositing black has no effect; compositing white inverts the colors of
    /// the other image.
    ///
    /// The opacity of the output image is computed in the same way as for
    /// `srcOver`.
    ///
    /// The effect is similar to `exclusion` but harsher.
    case difference

    /// Subtract double the product of the two images from the sum of the two
    /// images.
    ///
    /// **Dart Source:** `painting.dart:888-900`
    ///
    /// Compositing black has no effect; compositing white inverts the colors of
    /// the other image.
    ///
    /// The opacity of the output image is computed in the same way as for
    /// `srcOver`.
    ///
    /// The effect is similar to `difference` but softer.
    case exclusion

    /// Multiply the components of the source and destination images, including
    /// the alpha channel.
    ///
    /// **Dart Source:** `painting.dart:902-916`
    ///
    /// This can only result in the same or darker colors (multiplying by white,
    /// 1.0, results in no change; multiplying by black, 0.0, results in black).
    ///
    /// Since the alpha channel is also multiplied, a fully-transparent pixel
    /// (opacity 0.0) in one image results in a fully transparent pixel in the
    /// output. This is similar to `dstIn`, but with the colors combined.
    ///
    /// For a variant that multiplies the colors but does not multiply the alpha
    /// channel, consider `modulate`.
    case multiply // The last separable mode.

    /// Take the hue of the source image, and the saturation and luminosity of the
    /// destination image.
    ///
    /// **Dart Source:** `painting.dart:917-934`
    ///
    /// The effect is to tint the destination image with the source image.
    ///
    /// The opacity of the output image is computed in the same way as for
    /// `srcOver`. Regions that are entirely transparent in the source image take
    /// their hue from the destination.
    ///
    /// See also:
    ///
    ///  * `color`, which is a similar but stronger effect as it also applies the
    ///    saturation of the source image.
    ///  * `HSVColor`, which allows colors to be expressed using Hue rather than
    ///    the red/green/blue channels of `Color`.
    case hue

    /// Take the saturation of the source image, and the hue and luminosity of the
    /// destination image.
    ///
    /// **Dart Source:** `painting.dart:936-950`
    ///
    /// The opacity of the output image is computed in the same way as for
    /// `srcOver`. Regions that are entirely transparent in the source image take
    /// their saturation from the destination.
    ///
    /// See also:
    ///
    ///  * `color`, which also applies the hue of the source image.
    ///  * `luminosity`, which applies the luminosity of the source image to the
    ///    destination.
    case saturation

    /// Take the hue and saturation of the source image, and the luminosity of the
    /// destination image.
    ///
    /// **Dart Source:** `painting.dart:952-968`
    ///
    /// The effect is to tint the destination image with the source image.
    ///
    /// The opacity of the output image is computed in the same way as for
    /// `srcOver`. Regions that are entirely transparent in the source image take
    /// their hue and saturation from the destination.
    ///
    /// See also:
    ///
    ///  * `hue`, which is a similar but weaker effect.
    ///  * `softLight`, which is a similar tinting effect but also tints white.
    ///  * `saturation`, which only applies the saturation of the source image.
    case color

    /// Take the luminosity of the source image, and the hue and saturation of the
    /// destination image.
    ///
    /// **Dart Source:** `painting.dart:970-985`
    ///
    /// The opacity of the output image is computed in the same way as for
    /// `srcOver`. Regions that are entirely transparent in the source image take
    /// their luminosity from the destination.
    ///
    /// See also:
    ///
    ///  * `saturation`, which applies the saturation of the source image to the
    ///    destination.
    ///  * `ImageFilter.blur`, which can be used with `BackdropFilter` for a
    ///    related effect.
    case luminosity
}

// MARK: - FilterQuality

/// Quality levels for image sampling in `ImageFilter` and `Shader` objects that sample
/// images and for `Canvas` operations that render images.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:988-1064`
/// **Original Name:** `FilterQuality`
///
/// When scaling up typically the quality is lowest at `none`, higher at `low` and `medium`,
/// and for very large scale factors (over 10x) the highest at `high`.
///
/// When scaling down, `medium` provides the best quality especially when scaling an
/// image to less than half its size or for animating the scale factor between such
/// reductions. Otherwise, `low` and `high` provide similar effects for reductions of
/// between 50% and 100% but the image may lose detail and have dropouts below 50%.
///
/// To get high quality when scaling images up and down, or when the scale is
/// unknown, `medium` is typically a good balanced choice.
///
/// See also:
///
///  * `Paint.filterQuality`, which is used to pass `FilterQuality` to the
///    engine while using drawImage calls on a `Canvas`.
///  * `ImageShader`.
///  * `ImageFilter.matrix`.
///  * `Canvas.drawImage`.
///  * `Canvas.drawImageRect`.
///  * `Canvas.drawImageNine`.
///  * `Canvas.drawAtlas`.
public enum FilterQuality: Int {
    // This list and the values (order) should be kept in sync with the equivalent list
    // in lib/ui/painting/image_filter.cc

    /// The fastest filtering method, albeit also the lowest quality.
    ///
    /// **Dart Source:** `painting.dart:1022-1026`
    ///
    /// This value results in a "Nearest Neighbor" algorithm which just
    /// repeats or eliminates pixels as an image is scaled up or down.
    case none

    /// Better quality than `none`, faster than `medium`.
    ///
    /// **Dart Source:** `painting.dart:1028-1032`
    ///
    /// This value results in a "Bilinear" algorithm which smoothly
    /// interpolates between pixels in an image.
    case low

    /// The best all around filtering method that is only worse than `high`
    /// at extremely large scale factors.
    ///
    /// **Dart Source:** `painting.dart:1034-1048`
    ///
    /// This value improves upon the "Bilinear" algorithm specified by `low`
    /// by utilizing a Mipmap that pre-computes high quality lower resolutions
    /// of the image at half (and quarter and eighth, etc.) sizes and then
    /// blends between those to prevent loss of detail at small scale sizes.
    ///
    /// See also:
    ///
    ///  * `FilterQuality` class-level documentation that goes into detail about
    ///    relative qualities of the constant values.
    case medium

    /// Best possible quality when scaling up images by scale factors larger than
    /// 5-10x.
    ///
    /// **Dart Source:** `painting.dart:1050-1063`
    ///
    /// When images are scaled down, this can be worse than `medium` for scales
    /// smaller than 0.5x, or when animating the scale factor.
    ///
    /// This option is also the slowest.
    ///
    /// This value results in a standard "Bicubic" algorithm which uses a 3rd order
    /// equation to smooth the abrupt transitions between pixels while preserving
    /// some of the sense of an edge and avoiding sharp peaks in the result.
    ///
    /// See also:
    ///
    ///  * `FilterQuality` class-level documentation that goes into detail about
    ///    relative qualities of the constant values.
    case high
}

// MARK: - StrokeCap

/// Styles to use for line endings.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1066-1106`
/// **Original Name:** `StrokeCap`
///
/// See also:
///
///  * `Paint.strokeCap` for how this value is used.
///  * `StrokeJoin` for the different kinds of line segment joins.
public enum StrokeCap: Int {
    // These enum values must be kept in sync with DlStrokeCap.

    /// Begin and end contours with a flat edge and no extension.
    ///
    /// **Dart Source:** `painting.dart:1074-1081`
    ///
    /// A butt cap ends line segments with a square end that stops at the end of
    /// the line segment.
    ///
    /// Compare to the `square` cap, which has the same shape, but extends past
    /// the end of the line by half a stroke width.
    case butt

    /// Begin and end contours with a semi-circle extension.
    ///
    /// **Dart Source:** `painting.dart:1083-1091`
    ///
    /// A round cap adds a rounded end to the line segment that protrudes
    /// by one half of the thickness of the line (which is the radius of the cap)
    /// past the end of the segment.
    ///
    /// The cap is colored in the diagram above to highlight it: in normal use it
    /// is the same color as the line.
    case round

    /// Begin and end contours with a half square extension. This is
    /// similar to extending each contour by half the stroke width (as
    /// given by `Paint.strokeWidth`).
    ///
    /// **Dart Source:** `painting.dart:1093-1105`
    ///
    /// A square cap has a square end that effectively extends the line length
    /// by half of the stroke width.
    ///
    /// The cap is colored in the diagram above to highlight it: in normal use it
    /// is the same color as the line.
    ///
    /// Compare to the `butt` cap, which has the same shape, but doesn't extend
    /// past the end of the line.
    case square
}

// MARK: - StrokeJoin

/// Styles to use for line segment joins.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1108-1164`
/// **Original Name:** `StrokeJoin`
///
/// This only affects line joins for polygons drawn by `Canvas.drawPath` and
/// rectangles, not points drawn as lines with `Canvas.drawPoints`.
///
/// See also:
///
///  * `Paint.strokeJoin` and `Paint.strokeMiterLimit` for how this value is
///    used.
///  * `StrokeCap` for the different kinds of line endings.
public enum StrokeJoin: Int {
    // These enum values must be kept in sync with DlStrokeJoin.

    /// Joins between line segments form sharp corners.
    ///
    /// **Dart Source:** `painting.dart:1120-1134`
    ///
    /// The center of the line segment is colored in the diagram above to
    /// highlight the join, but in normal usage the join is the same color as the
    /// line.
    ///
    /// See also:
    ///
    ///   * `Paint.strokeJoin`, used to set the line segment join style to this
    ///     value.
    ///   * `Paint.strokeMiterLimit`, used to define when a miter is drawn instead
    ///     of a bevel when the join is set to this value.
    case miter

    /// Joins between line segments are semi-circular.
    ///
    /// **Dart Source:** `painting.dart:1136-1148`
    ///
    /// The center of the line segment is colored in the diagram above to
    /// highlight the join, but in normal usage the join is the same color as the
    /// line.
    ///
    /// See also:
    ///
    ///   * `Paint.strokeJoin`, used to set the line segment join style to this
    ///     value.
    case round

    /// Joins between line segments connect the corners of the butt ends of the
    /// line segments to give a beveled appearance.
    ///
    /// **Dart Source:** `painting.dart:1150-1163`
    ///
    /// The center of the line segment is colored in the diagram above to
    /// highlight the join, but in normal usage the join is the same color as the
    /// line.
    ///
    /// See also:
    ///
    ///   * `Paint.strokeJoin`, used to set the line segment join style to this
    ///     value.
    case bevel
}

// MARK: - PaintingStyle

/// Strategies for painting shapes and paths on a canvas.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1166-1184`
/// **Original Name:** `PaintingStyle`
///
/// See also:
///
///  * `Paint.style`, which uses `PaintingStyle` to define whether shapes are filled
///    or stroked when drawn.
public enum PaintingStyle: Int {
    // These enum values must be kept in sync with DlDrawStyle.
    // This list comes from dl_paint.h and the values (order) should be kept in sync.

    /// Apply the `Paint` to the inside of the shape.
    ///
    /// **Dart Source:** `painting.dart:1174-1177`
    ///
    /// For example, when applied to the `Canvas.drawCircle` call, this results
    /// in a disc of the given size being painted.
    case fill

    /// Apply the `Paint` to the edge of the shape.
    ///
    /// **Dart Source:** `painting.dart:1179-1183`
    ///
    /// For example, when applied to the `Canvas.drawCircle` call, this results
    /// in a hoop of the given size being painted. The line drawn on the edge will
    /// be the width given by the `Paint.strokeWidth` property.
    case stroke
}

// MARK: - Clip

/// Different ways to clip content.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1186-1265`
/// **Original Name:** `Clip`
///
/// See also:
///
///  * `Paint.isAntiAlias`, the anti-aliasing switch for general draw operations.
public enum Clip: Int {
    /// No clip at all.
    ///
    /// **Dart Source:** `painting.dart:1192-1203`
    ///
    /// This is the default option for most widgets: if the content does not
    /// overflow the widget boundary, don't pay any performance cost for clipping.
    ///
    /// If the content does overflow, consider the following `Clip` options:
    ///
    ///  * `hardEdge`, which is the fastest clipping, but with lower fidelity.
    ///  * `antiAlias`, which is a little slower than `hardEdge`, but with smoothed edges.
    ///  * `antiAliasWithSaveLayer`, which is much slower than `antiAlias`, and should
    ///    rarely be used.
    case none

    /// Clip, but do not apply anti-aliasing.
    ///
    /// **Dart Source:** `painting.dart:1205-1219`
    ///
    /// This mode enables clipping, but curves and non-axis-aligned straight lines will be
    /// jagged as no effort is made to anti-alias.
    ///
    /// Faster than other clipping modes, but slower than `none`.
    ///
    /// This is a reasonable choice when clipping is needed, if the container is an axis-
    /// aligned rectangle or an axis-aligned rounded rectangle with very small corner radii.
    ///
    /// See also:
    ///
    ///  * `antiAlias`, recommended when clipping is needed and the shape is not
    ///    an axis-aligned rectangle.
    case hardEdge

    /// Clip with anti-aliasing.
    ///
    /// **Dart Source:** `painting.dart:1221-1239`
    ///
    /// This mode has anti-aliased clipping edges, which reduces jagged edges when
    /// the clip shape itself has edges that are diagonal, curved, or otherwise
    /// not axis-aligned.
    ///
    /// This is much faster than `antiAliasWithSaveLayer`, but slower than `hardEdge`.
    ///
    /// Unlike `hardEdge` and `antiAliasWithSaveLayer`, this clipping can have
    /// bleeding edge artifacts
    /// (Skia Fiddle example: https://fiddle.skia.org/c/21cb4c2b2515996b537f36e7819288ae).
    ///
    /// See also:
    ///
    ///  * `hardEdge`, which is faster, but with lower fidelity.
    ///  * `antiAliasWithSaveLayer`, which is much slower, but avoids bleeding
    ///    edge artifacts.
    ///  * `Paint.isAntiAlias`, which is the anti-aliasing switch for general draw operations.
    case antiAlias

    /// Clip with anti-aliasing and `saveLayer` immediately following the clip.
    ///
    /// **Dart Source:** `painting.dart:1241-1264`
    ///
    /// This mode not only clips with anti-aliasing, but also allocates an offscreen
    /// buffer. All subsequent paints are carried out on that buffer before finally
    /// being clipped and composited back.
    ///
    /// This is very slow. It has no bleeding edge artifacts, unlike `antiAlias`,
    /// but it changes the semantics as it introduces an offscreen buffer.
    /// For example, see this
    /// Skia Fiddle without saveLayer: https://fiddle.skia.org/c/83ed46ceadaf90f36a4df3b98cbe1c35
    /// and this
    /// Skia Fiddle with saveLayer: https://fiddle.skia.org/c/704acfa049a7e99fbe685232c45d1582
    ///
    /// Use this mode only if necessary. For example, if you have an
    /// image overlaid on a very different background color. In these
    /// cases, consider if you can avoid overlaying multiple colors in one
    /// location (e.g. by having the background color only present where the image is
    /// absent). If possible, prefer `antiAlias` as it is much faster.
    ///
    /// See also:
    ///
    ///  * `antiAlias`, which is much faster, and has similar clipping results.
    ///  * `Canvas.saveLayer`.
    case antiAliasWithSaveLayer
}

// MARK: - ImageByteFormat

/// The format in which image bytes should be returned when using
/// `Image.toByteData`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1829-1893`
/// **Original Name:** `ImageByteFormat`
///
/// We do not expect to add more encoding formats to the ImageByteFormat enum,
/// considering the binary size of the engine after LTO optimization. You can
/// use the third-party pure dart image library to encode other formats.
/// See: https://github.com/flutter/flutter/issues/16635 for more details.
public enum ImageByteFormat: Int {
    /// Raw RGBA format.
    ///
    /// **Dart Source:** `painting.dart:1836-1839`
    ///
    /// Unencoded bytes, in RGBA row-primary form with premultiplied alpha, 8 bits per channel.
    case rawRgba

    /// Raw straight RGBA format.
    ///
    /// **Dart Source:** `painting.dart:1841-1844`
    ///
    /// Unencoded bytes, in RGBA row-primary form with straight alpha, 8 bits per channel.
    case rawStraightRgba

    /// Raw unmodified format.
    ///
    /// **Dart Source:** `painting.dart:1846-1850`
    ///
    /// Unencoded bytes, in the image's existing format. For example, a grayscale
    /// image may use a single 8-bit channel for each pixel.
    case rawUnmodified

    /// Raw extended range RGBA format.
    ///
    /// **Dart Source:** `painting.dart:1852-1875`
    ///
    /// Unencoded bytes, in RGBA row-primary form with straight alpha, 32 bit
    /// float (IEEE 754 binary32) per channel.
    ///
    /// Example usage:
    ///
    /// ```swift
    /// import Foundation
    ///
    /// func getFirstPixel(image: Image) async -> [String: Double] {
    ///     let data = try await image.toByteData(format: .rawExtendedRgba128)!
    ///     let floats = data.withUnsafeBytes { $0.bindMemory(to: Float32.self) }
    ///     return [
    ///         "r": Double(floats[0]),
    ///         "g": Double(floats[1]),
    ///         "b": Double(floats[2]),
    ///         "a": Double(floats[3]),
    ///     ]
    /// }
    /// ```
    case rawExtendedRgba128

    /// PNG format.
    ///
    /// **Dart Source:** `painting.dart:1877-1892`
    ///
    /// A loss-less compression format for images. This format is well suited for
    /// images with hard edges, such as screenshots or sprites, and images with
    /// text. Transparency is supported. The PNG format supports images up to
    /// 2,147,483,647 pixels in either dimension, though in practice available
    /// memory provides a more immediate limitation on maximum image size.
    ///
    /// PNG images normally use the `.png` file extension and the `image/png` MIME
    /// type.
    ///
    /// See also:
    ///
    ///  * https://en.wikipedia.org/wiki/Portable_Network_Graphics, the Wikipedia page on PNG.
    ///  * https://tools.ietf.org/rfc/rfc2083.txt, the PNG standard.
    case png
}

// MARK: - ColorSpace

/// The color space describes the colors that are available to an `Image`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1770-1803`
/// **Original Name:** `ColorSpace`
///
/// This value can help decide which `ImageByteFormat` to use with
/// `Image.toByteData`. Images that are in the `extendedSRGB` color space
/// should use something like `ImageByteFormat.rawExtendedRgba128` so that
/// colors outside of the sRGB gamut aren't lost.
///
/// This is also the result of `Image.colorSpace`.
///
/// See also: https://en.wikipedia.org/wiki/Color_space
public enum ColorSpace: Int, Sendable {
    /// The sRGB color space.
    ///
    /// **Dart Source:** `painting.dart:1781-1787`
    ///
    /// You may know this as the standard color space for the web or the color
    /// space of non-wide-gamut Flutter apps.
    ///
    /// See also: https://en.wikipedia.org/wiki/SRGB
    case sRGB

    /// A color space that is backwards compatible with sRGB but can represent
    /// colors outside of that gamut with values outside of [0..1].
    ///
    /// **Dart Source:** `painting.dart:1789-1793`
    ///
    /// In order to see the extended values an `ImageByteFormat` like
    /// `ImageByteFormat.rawExtendedRgba128` must be used.
    case extendedSRGB

    /// The Display P3 color space.
    ///
    /// **Dart Source:** `painting.dart:1795-1802`
    ///
    /// This is a wide gamut color space that has broad hardware support. It's
    /// supported on platforms with wide gamut displays. When used on a platform
    /// that doesn't support Display P3, the colors will be clamped to sRGB.
    ///
    /// See also: https://en.wikipedia.org/wiki/DCI-P3
    case displayP3
}

// MARK: - PathFillType

/// Determines the winding rule that decides how the interior of a `Path` is
/// calculated.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2723-2745`
/// **Original Name:** `PathFillType`
///
/// This enum is used by the `Path.fillType` property.
public enum PathFillType: Int {
    /// The interior is defined by a non-zero sum of signed edge crossings.
    ///
    /// **Dart Source:** `painting.dart:2728-2736`
    ///
    /// For a given point, the point is considered to be on the inside of the path
    /// if a line drawn from the point to infinity crosses lines going clockwise
    /// around the point a different number of times than it crosses lines going
    /// counter-clockwise around that point.
    ///
    /// See: https://en.wikipedia.org/wiki/Nonzero-rule
    case nonZero

    /// The interior is defined by an odd number of edge crossings.
    ///
    /// **Dart Source:** `painting.dart:2738-2744`
    ///
    /// For a given point, the point is considered to be on the inside of the path
    /// if a line drawn from the point to infinity crosses an odd number of lines.
    ///
    /// See: https://en.wikipedia.org/wiki/Even-odd_rule
    case evenOdd
}

// MARK: - PathOperation

/// Strategies for combining paths.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2747-2805`
/// **Original Name:** `PathOperation`
///
/// See also:
///
///  * `Path.combine`, which uses this enum to decide how to combine two paths.
// Must be kept in sync with SkPathOp
public enum PathOperation: Int {
    /// Subtract the second path from the first path.
    ///
    /// **Dart Source:** `painting.dart:2754-2764`
    ///
    /// For example, if the two paths are overlapping circles of equal diameter
    /// but differing centers, the result would be a crescent portion of the
    /// first circle that was not overlapped by the second circle.
    ///
    /// See also:
    ///
    ///  * `reverseDifference`, which is the same but subtracting the first path
    ///    from the second.
    case difference

    /// Create a new path that is the intersection of the two paths, leaving the
    /// overlapping pieces of the path.
    ///
    /// **Dart Source:** `painting.dart:2766-2775`
    ///
    /// For example, if the two paths are overlapping circles of equal diameter
    /// but differing centers, the result would be only the overlapping portion
    /// of the two circles.
    ///
    /// See also:
    ///  * `xor`, which is the inverse of this operation
    case intersect

    /// Create a new path that is the union (inclusive-or) of the two paths.
    ///
    /// **Dart Source:** `painting.dart:2777-2782`
    ///
    /// For example, if the two paths are overlapping circles of equal diameter
    /// but differing centers, the result would be a figure-eight like shape
    /// matching the outer boundaries of both circles.
    case union

    /// Create a new path that is the exclusive-or of the two paths, leaving
    /// everything but the overlapping pieces of the path.
    ///
    /// **Dart Source:** `painting.dart:2784-2792`
    ///
    /// For example, if the two paths are overlapping circles of equal diameter
    /// but differing centers, the figure-eight like shape less the overlapping parts
    ///
    /// See also:
    ///  * `intersect`, which is the inverse of this operation
    case xor

    /// Subtract the first path from the second path.
    ///
    /// **Dart Source:** `painting.dart:2794-2804`
    ///
    /// For example, if the two paths are overlapping circles of equal diameter
    /// but differing centers, the result would be a crescent portion of the
    /// second circle that was not overlapped by the first circle.
    ///
    /// See also:
    ///
    ///  * `difference`, which is the same but subtracting the second path
    ///    from the first.
    case reverseDifference
}

// MARK: - PixelFormat

/// The format of pixel data given to `decodeImageFromPixels`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1895-1912`
/// **Original Name:** `PixelFormat`
public enum PixelFormat: Int {
    /// Each pixel is 32 bits, with the highest 8 bits encoding red, the next 8
    /// bits encoding green, the next 8 bits encoding blue, and the lowest 8 bits
    /// encoding alpha. Premultiplied alpha is used.
    ///
    /// **Dart Source:** `painting.dart:1897-1900`
    case rgba8888

    /// Each pixel is 32 bits, with the highest 8 bits encoding blue, the next 8
    /// bits encoding green, the next 8 bits encoding red, and the lowest 8 bits
    /// encoding alpha. Premultiplied alpha is used.
    ///
    /// **Dart Source:** `painting.dart:1902-1905`
    case bgra8888

    /// Each pixel is 128 bits, where each color component is a 32 bit float that
    /// is normalized across the sRGB gamut. The first float is the red
    /// component, followed by: green, blue and alpha. Premultiplied alpha isn't
    /// used, matching `ImageByteFormat.rawExtendedRgba128`.
    ///
    /// **Dart Source:** `painting.dart:1907-1911`
    case rgbaFloat32
}

// MARK: - BlurStyle

/// Styles to use for blurs in `MaskFilter` objects.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:3765-3787`
/// **Original Name:** `BlurStyle`
///
/// These enum values must be kept in sync with DlBlurStyle.
public enum BlurStyle: Int {
    // These mirror DlBlurStyle and must be kept in sync.

    /// Fuzzy inside and outside. This is useful for painting shadows that are
    /// offset from the shape that ostensibly is casting the shadow.
    ///
    /// **Dart Source:** `painting.dart:3770-3772`
    case normal

    /// Solid inside, fuzzy outside. This corresponds to drawing the shape, and
    /// additionally drawing the blur. This can make objects appear brighter,
    /// maybe even as if they were fluorescent.
    ///
    /// **Dart Source:** `painting.dart:3774-3777`
    case solid

    /// Nothing inside, fuzzy outside. This is useful for painting shadows for
    /// partially transparent shapes, when they are painted separately but without
    /// an offset, so that the shadow doesn't paint below the shape.
    ///
    /// **Dart Source:** `painting.dart:3779-3782`
    case outer

    /// Fuzzy inside, nothing outside. This can make shapes appear to be lit from
    /// within.
    ///
    /// **Dart Source:** `painting.dart:3784-3786`
    case inner
}

// MARK: - TileMode

/// Defines how to handle areas outside the defined bounds of a gradient or image filter.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:4649-4759`
/// **Original Name:** `TileMode`
///
/// ## For Gradients
///
/// Gradients are defined with some specific bounds creating an inner area and an outer area,
/// and `TileMode` controls how colors are determined for areas outside these bounds:
///
/// - **Linear gradients**: The inner area is the area between two points
///   (typically referred to as `start` and `end` in the gradient API), or more precisely,
///   it's the area between the parallel lines that are orthogonal to the line drawn between
///   the two points. Colors outside this area are determined by the `TileMode`.
///
/// - **Radial gradients**: The inner area is the disc defined by a center and radius.
///   Colors outside this disc are determined by the `TileMode`.
///
/// - **Sweep gradients**: The inner area is the angular sector between `startAngle`
///   and `endAngle`. Colors outside this sector are determined by the `TileMode`.
///
/// ## For Image Filters
///
/// When applying filters (like blur) that sample colors from outside an image's bounds,
/// `TileMode` defines how those out-of-bounds samples are determined:
///
/// - It controls what color values are used when the filter needs to sample
///   from areas outside the original image.
/// - This is particularly important for effects like blurring near image edges.
///
/// See also:
///
///  * `Gradient`, the superclass for `LinearGradient` and `RadialGradient`.
///  * `ImageFilter.blur`, an ImageFilter that may sometimes need to read samples
///    from outside an image to combine with the pixels near the edge of the image.
// These enum values must be kept in sync with DlTileMode.
public enum TileMode: Int {
    /// Samples beyond the edge are clamped to the nearest color in the defined inner area.
    ///
    /// **Dart Source:** `painting.dart:4690-4705`
    ///
    /// For gradients, this means the region outside the inner area is painted with
    /// the color at the end of the color stop list closest to that region.
    ///
    /// For sweep gradients specifically, the entire area outside the angular sector
    /// defined by `startAngle` and `endAngle` will be painted with the color at the
    /// end of the color stop list closest to that region.
    ///
    /// An image filter will substitute the nearest edge pixel for any samples taken from
    /// outside its source image.
    case clamp

    /// Samples beyond the edge are repeated from the far end of the defined area.
    ///
    /// **Dart Source:** `painting.dart:4707-4722`
    ///
    /// For a gradient, this technique is as if the stop points from 0.0 to 1.0 were then
    /// repeated from 1.0 to 2.0, 2.0 to 3.0, and so forth (and for linear gradients, similarly
    /// from -1.0 to 0.0, -2.0 to -1.0, etc).
    ///
    /// For sweep gradients, the gradient pattern is repeated in the same direction
    /// (clockwise) for angles beyond `endAngle` and before `startAngle`.
    ///
    /// An image filter will treat its source image as if it were tiled across the enlarged
    /// sample space from which it reads, each tile in the same orientation as the base image.
    case repeated

    /// Samples beyond the edge are mirrored back and forth across the defined area.
    ///
    /// **Dart Source:** `painting.dart:4724-4741`
    ///
    /// For a gradient, this technique is as if the stop points from 0.0 to 1.0 were then
    /// repeated backwards from 2.0 to 1.0, then forwards from 2.0 to 3.0, then backwards
    /// again from 4.0 to 3.0, and so forth (and for linear gradients, similarly in the
    /// negative direction).
    ///
    /// For sweep gradients, the gradient pattern is mirrored back and forth as the angle
    /// increases beyond `endAngle` or decreases below `startAngle`.
    ///
    /// An image filter will treat its source image as tiled in an alternating forwards and
    /// backwards or upwards and downwards direction across the sample space from which
    /// it is reading.
    case mirror

    /// Samples beyond the edge are treated as transparent black.
    ///
    /// **Dart Source:** `painting.dart:4743-4758`
    ///
    /// A gradient will render transparency over any region that is outside the circle of a
    /// radial gradient, outside the parallel lines that define the inner area of a linear
    /// gradient, or outside the angular sector of a sweep gradient.
    ///
    /// For sweep gradients, only the sector between `startAngle` and `endAngle` will be
    /// painted; all other areas will be transparent.
    ///
    /// An image filter will substitute transparent black for any sample it must read from
    /// outside its source image.
    case decal
}

// MARK: - VertexMode

/// Defines how a list of points is interpreted when drawing a set of triangles.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:5390-5408`
/// **Original Name:** `VertexMode`
///
/// Used by `Canvas.drawVertices`.
///
/// These enum values must be kept in sync with DlVertexMode.
public enum VertexMode: Int {
    /// Draw each sequence of three points as the vertices of a triangle.
    ///
    /// **Dart Source:** `painting.dart:5395-5396`
    case triangles

    /// Draw each sliding window of three points as the vertices of a triangle.
    ///
    /// **Dart Source:** `painting.dart:5398-5399`
    case triangleStrip

    /// Draw the first point and each sliding window of two points as the vertices
    /// of a triangle.
    ///
    /// **Dart Source:** `painting.dart:5401-5407`
    ///
    /// This mode is not natively supported by most backends, and is instead
    /// implemented by unrolling the points into the equivalent
    /// `VertexMode.triangles`, which is generally more efficient.
    case triangleFan
}

// MARK: - PointMode

/// Defines how a list of points is interpreted when drawing a set of points.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:5659-5688`
/// **Original Name:** `PointMode`
///
/// Used by `Canvas.drawPoints` and `Canvas.drawRawPoints`.
///
/// These enum values must be kept in sync with DlPointMode.
public enum PointMode: Int {
    /// Draw each point separately.
    ///
    /// **Dart Source:** `painting.dart:5664-5673`
    ///
    /// If the `Paint.strokeCap` is `StrokeCap.round`, then each point is drawn
    /// as a circle with the diameter of the `Paint.strokeWidth`, filled as
    /// described by the `Paint` (ignoring `Paint.style`).
    ///
    /// Otherwise, each point is drawn as an axis-aligned square with sides of
    /// length `Paint.strokeWidth`, filled as described by the `Paint` (ignoring
    /// `Paint.style`).
    case points

    /// Draw each sequence of two points as a line segment.
    ///
    /// **Dart Source:** `painting.dart:5675-5681`
    ///
    /// If the number of points is odd, then the last point is ignored.
    ///
    /// The lines are stroked as described by the `Paint` (ignoring
    /// `Paint.style`).
    case lines

    /// Draw the entire sequence of points as one line.
    ///
    /// **Dart Source:** `painting.dart:5683-5687`
    ///
    /// The lines are stroked as described by the `Paint` (ignoring
    /// `Paint.style`).
    case polygon
}

// MARK: - ClipOp

/// Defines how a new clip region should be merged with the existing clip
/// region.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:5690-5700`
/// **Original Name:** `ClipOp`
///
/// Used by `Canvas.clipRect`.
public enum ClipOp: Int {
    /// Subtract the new region from the existing region.
    ///
    /// **Dart Source:** `painting.dart:5695-5696`
    case difference

    /// Intersect the new region from the existing region.
    ///
    /// **Dart Source:** `painting.dart:5698-5699`
    case intersect
}

// MARK: - MaskFilter

/// A mask filter to apply to shapes as they are painted. A mask filter is a
/// function that takes a bitmap of color pixels, and returns another bitmap of
/// color pixels.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:3789-3833`
/// **Original Name:** `MaskFilter`
///
/// Instances of this class are used with `Paint.maskFilter` on `Paint` objects.
public struct MaskFilter: Hashable, CustomStringConvertible {
    // MARK: - Private Fields

    /// The blur style.
    ///
    /// **Dart Source:** `painting.dart:3815`
    /// **Original:** `final BlurStyle _style;`
    private let style: BlurStyle

    /// The sigma value for the blur.
    ///
    /// **Dart Source:** `painting.dart:3816`
    /// **Original:** `final double _sigma;`
    private let sigma: Double

    // MARK: - Internal Constants

    /// The type of MaskFilter class to create for flutter::DisplayList.
    /// These constants must be kept in sync with MaskFilterType in paint.cc.
    ///
    /// **Dart Source:** `painting.dart:3820`
    /// **Original:** `static const int _TypeNone = 0;`
    static let typeNone: Int = 0

    /// **Dart Source:** `painting.dart:3821`
    /// **Original:** `static const int _TypeBlur = 1;`
    static let typeBlur: Int = 1

    // MARK: - Initializers

    /// Creates a mask filter that takes the shape being drawn and blurs it.
    ///
    /// **Dart Source:** `painting.dart:3795-3813`
    /// **Original:** `const MaskFilter.blur(this._style, this._sigma)`
    ///
    /// This is commonly used to approximate shadows.
    ///
    /// The `style` argument controls the kind of effect to draw; see `BlurStyle`.
    ///
    /// The `sigma` argument controls the size of the effect. It is the standard
    /// deviation of the Gaussian blur to apply. The value must be greater than
    /// zero. The sigma corresponds to very roughly half the radius of the effect
    /// in pixels.
    ///
    /// A blur is an expensive operation and should therefore be used sparingly.
    ///
    /// See also:
    ///
    ///  * `Canvas.drawShadow`, which is a more efficient way to draw shadows.
    public init(blur style: BlurStyle, _ sigma: Double) {
        self.style = style
        self.sigma = sigma
    }

    // MARK: - Internal Accessors

    /// Returns the blur style for internal use.
    ///
    /// **Note:** This accessor is provided for internal use by Paint and other classes.
    internal var blurStyle: BlurStyle {
        return style
    }

    /// Returns the sigma value for internal use.
    ///
    /// **Note:** This accessor is provided for internal use by Paint and other classes.
    internal var blurSigma: Double {
        return sigma
    }

    // MARK: - Hashable

    /// The hash code for this mask filter.
    ///
    /// **Dart Source:** `painting.dart:3828-3829`
    /// **Original:** `int get hashCode => Object.hash(_style, _sigma);`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(style)
        hasher.combine(sigma)
    }

    // MARK: - Equatable

    /// Compares two mask filters for equality.
    ///
    /// **Dart Source:** `painting.dart:3823-3826`
    /// **Original:** `bool operator ==(Object other) { ... }`
    public static func == (lhs: MaskFilter, rhs: MaskFilter) -> Bool {
        return lhs.style == rhs.style && lhs.sigma == rhs.sigma
    }

    // MARK: - CustomStringConvertible

    /// Returns a string representation of this mask filter.
    ///
    /// **Dart Source:** `painting.dart:3831-3832`
    /// **Original:** `String toString() => 'MaskFilter.blur($_style, ${_sigma.toStringAsFixed(1)})';`
    public var description: String {
        return "MaskFilter.blur(\(style), \(String(format: "%.1f", sigma)))"
    }
}

// MARK: - Shadow

/// A single shadow.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7505-7699`
/// **Original Name:** `Shadow`
///
/// Multiple shadows are stacked together in a `TextStyle`.
public struct Shadow: Hashable, CustomStringConvertible {
    // MARK: - Static Constants

    /// Default color value (opaque black).
    ///
    /// **Dart Source:** `painting.dart:7525`
    /// **Original:** `static const int _kColorDefault = 0xFF000000;`
    private static let kColorDefault: Int = 0xFF000000

    /// Bytes per shadow in encoding.
    ///
    /// **Dart Source:** `painting.dart:7527`
    /// **Original:** `static const int _kBytesPerShadow = 16;`
    internal static let kBytesPerShadow: Int = 16

    /// Color offset in shadow encoding.
    ///
    /// **Dart Source:** `painting.dart:7528`
    /// **Original:** `static const int _kColorOffset = 0 << 2;`
    internal static let kColorOffset: Int = 0 << 2

    /// X offset in shadow encoding.
    ///
    /// **Dart Source:** `painting.dart:7529`
    /// **Original:** `static const int _kXOffset = 1 << 2;`
    internal static let kXOffset: Int = 1 << 2

    /// Y offset in shadow encoding.
    ///
    /// **Dart Source:** `painting.dart:7530`
    /// **Original:** `static const int _kYOffset = 2 << 2;`
    internal static let kYOffset: Int = 2 << 2

    /// Blur offset in shadow encoding.
    ///
    /// **Dart Source:** `painting.dart:7531`
    /// **Original:** `static const int _kBlurOffset = 3 << 2;`
    internal static let kBlurOffset: Int = 3 << 2

    // MARK: - Properties

    /// Color that the shadow will be drawn with.
    ///
    /// **Dart Source:** `painting.dart:7533-7537`
    /// **Original:** `final Color color;`
    ///
    /// The shadows are shapes composited directly over the base canvas, and do not
    /// represent optical occlusion.
    public let color: Color

    /// The displacement of the shadow from the casting element.
    ///
    /// **Dart Source:** `painting.dart:7539-7544`
    /// **Original:** `final Offset offset;`
    ///
    /// Positive x/y offsets will shift the shadow to the right and down, while
    /// negative offsets shift the shadow to the left and up. The offsets are
    /// relative to the position of the element that is casting it.
    public let offset: Offset

    /// The standard deviation of the Gaussian to convolve with the shadow's shape.
    ///
    /// **Dart Source:** `painting.dart:7546-7547`
    /// **Original:** `final double blurRadius;`
    public let blurRadius: Double

    // MARK: - Initializers

    /// Construct a shadow.
    ///
    /// **Dart Source:** `painting.dart:7519-7523`
    /// **Original:** `const Shadow({...})`
    ///
    /// The default shadow is a black shadow with zero offset and zero blur.
    /// Default shadows should be completely covered by the casting element,
    /// and not be visible.
    ///
    /// Transparency should be adjusted through the `color` alpha.
    ///
    /// Shadow order matters due to compositing multiple translucent objects not
    /// being commutative.
    public init(
        color: Color = Color(0xFF000000),  // kColorDefault: opaque black
        offset: Offset = .zero,
        blurRadius: Double = 0.0
    ) {
        assert(blurRadius >= 0.0, "Text shadow blur radius should be non-negative.")
        self.color = color
        self.offset = offset
        self.blurRadius = blurRadius
    }

    // MARK: - Static Methods

    /// Converts a blur radius in pixels to sigmas.
    ///
    /// **Dart Source:** `painting.dart:7549-7557`
    /// **Original:** `static double convertRadiusToSigma(double radius)`
    ///
    /// See the sigma argument to `MaskFilter.blur`.
    ///
    /// See SkBlurMask::ConvertRadiusToSigma().
    /// https://github.com/google/skia/blob/bb5b77db51d2e149ee66db284903572a5aac09be/src/effects/SkBlurMask.cpp#L23
    public static func convertRadiusToSigma(_ radius: Double) -> Double {
        return radius > 0 ? radius * 0.57735 + 0.5 : 0
    }

    // MARK: - Computed Properties

    /// The `blurRadius` in sigmas instead of logical pixels.
    ///
    /// **Dart Source:** `painting.dart:7559-7562`
    /// **Original:** `double get blurSigma => convertRadiusToSigma(blurRadius);`
    ///
    /// See the sigma argument to `MaskFilter.blur`.
    public var blurSigma: Double {
        return Shadow.convertRadiusToSigma(blurRadius)
    }

    // MARK: - Methods

    /// Create the `Paint` object that corresponds to this shadow description.
    ///
    /// **Dart Source:** `painting.dart:7564-7578`
    /// **Original:** `Paint toPaint() {...}`
    ///
    /// The `offset` is not represented in the `Paint` object.
    /// To honor this as well, the shape should be translated by `offset` before
    /// being filled using this `Paint`.
    ///
    /// This class does not provide a way to disable shadows to avoid
    /// inconsistencies in shadow blur rendering, primarily as a method of
    /// reducing test flakiness. `toPaint` should be overridden in subclasses to
    /// provide this functionality.
    ///
    /// DIFFERENCE FROM DART: Returns a dictionary instead of Paint since Paint class is not yet ported.
    /// REASON: Paint depends on many other types that are migrated later in the plan.
    /// This method can be updated once Paint is available.
    public func toPaintComponents() -> (color: Color, maskFilter: MaskFilter) {
        return (color: color, maskFilter: MaskFilter(blur: .normal, blurSigma))
    }

    /// Returns a new shadow with its `offset` and `blurRadius` scaled by the given
    /// factor.
    ///
    /// **Dart Source:** `painting.dart:7580-7584`
    /// **Original:** `Shadow scale(double factor)`
    public func scale(_ factor: Double) -> Shadow {
        return Shadow(
            color: color,
            offset: offset * factor,
            blurRadius: blurRadius * factor
        )
    }

    /// Linearly interpolate between two shadows.
    ///
    /// **Dart Source:** `painting.dart:7586-7623`
    /// **Original:** `static Shadow? lerp(Shadow? a, Shadow? b, double t)`
    ///
    /// If either shadow is nil, this function linearly interpolates from
    /// a shadow that matches the other shadow in color but has a zero
    /// offset and a zero blurRadius.
    ///
    /// The `t` argument represents position on the timeline, with 0.0 meaning
    /// that the interpolation has not started, returning `a` (or something
    /// equivalent to `a`), 1.0 meaning that the interpolation has finished,
    /// returning `b` (or something equivalent to `b`), and values in between
    /// meaning that the interpolation is at the relevant point on the timeline
    /// between `a` and `b`. The interpolation can be extrapolated beyond 0.0 and
    /// 1.0, so negative values and values greater than 1.0 are valid (and can
    /// easily be generated by curves such as `Curves.elasticInOut`).
    ///
    /// Values for `t` are usually obtained from an `Animation<Double>`, such as
    /// an `AnimationController`.
    public static func lerp(_ a: Shadow?, _ b: Shadow?, _ t: Double) -> Shadow? {
        if b == nil {
            if a == nil {
                return nil
            } else {
                return a!.scale(1.0 - t)
            }
        } else {
            if a == nil {
                return b!.scale(t)
            } else {
                return Shadow(
                    color: Color.lerp(a!.color, b!.color, t)!,
                    offset: Offset.lerp(a!.offset, b!.offset, t)!,
                    blurRadius: _lerpDouble(a!.blurRadius, b!.blurRadius, t)
                )
            }
        }
    }

    /// Linearly interpolate between two lists of shadows.
    ///
    /// **Dart Source:** `painting.dart:7625-7648`
    /// **Original:** `static List<Shadow>? lerpList(List<Shadow>? a, List<Shadow>? b, double t)`
    ///
    /// If the lists differ in length, excess items are lerped with nil.
    ///
    /// The `t` argument represents position on the timeline, with 0.0 meaning
    /// that the interpolation has not started, returning `a` (or something
    /// equivalent to `a`), 1.0 meaning that the interpolation has finished,
    /// returning `b` (or something equivalent to `b`), and values in between
    /// meaning that the interpolation is at the relevant point on the timeline
    /// between `a` and `b`. The interpolation can be extrapolated beyond 0.0 and
    /// 1.0, so negative values and values greater than 1.0 are valid (and can
    /// easily be generated by curves such as `Curves.elasticInOut`).
    ///
    /// Values for `t` are usually obtained from an `Animation<Double>`, such as
    /// an `AnimationController`.
    public static func lerpList(_ a: [Shadow]?, _ b: [Shadow]?, _ t: Double) -> [Shadow]? {
        if a == nil && b == nil {
            return nil
        }
        let aList = a ?? []
        let bList = b ?? []
        var result: [Shadow] = []
        let commonLength = min(aList.count, bList.count)
        for i in 0..<commonLength {
            result.append(Shadow.lerp(aList[i], bList[i], t)!)
        }
        for i in commonLength..<aList.count {
            result.append(aList[i].scale(1.0 - t))
        }
        for i in commonLength..<bList.count {
            result.append(bList[i].scale(t))
        }
        return result
    }

    // MARK: - Equatable

    /// Compares two shadows for equality.
    ///
    /// **Dart Source:** `painting.dart:7650-7659`
    /// **Original:** `bool operator ==(Object other)`
    public static func == (lhs: Shadow, rhs: Shadow) -> Bool {
        if lhs.color != rhs.color { return false }
        if lhs.offset != rhs.offset { return false }
        if lhs.blurRadius != rhs.blurRadius { return false }
        return true
    }

    // MARK: - Hashable

    /// The hash code for this shadow.
    ///
    /// **Dart Source:** `painting.dart:7661-7662`
    /// **Original:** `int get hashCode => Object.hash(color, offset, blurRadius);`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(color)
        hasher.combine(offset)
        hasher.combine(blurRadius)
    }

    // MARK: - CustomStringConvertible

    /// Returns a string representation of this shadow.
    ///
    /// **Dart Source:** `painting.dart:7697-7698`
    /// **Original:** `String toString() => 'TextShadow($color, $offset, $blurRadius)';`
    public var description: String {
        return "TextShadow(\(color), \(offset), \(blurRadius))"
    }
}

// MARK: - Tangent

/// The geometric description of a tangent: the angle at a point.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:3496-3540`
/// **Original Name:** `Tangent`
///
/// See also:
///
///  * `PathMetric.getTangentForOffset`, which returns the tangent of an offset along a path.
public struct Tangent {
    // MARK: - Fields

    /// Position of the tangent.
    ///
    /// **Dart Source:** `painting.dart:3514-3518`
    /// **Original:** `final Offset position;`
    ///
    /// When used with `PathMetric.getTangentForOffset`, this represents the precise
    /// position that the given offset along the path corresponds to.
    public let position: Offset

    /// The vector of the curve at `position`.
    ///
    /// **Dart Source:** `painting.dart:3520-3525`
    /// **Original:** `final Offset vector;`
    ///
    /// When used with `PathMetric.getTangentForOffset`, this is the vector of the
    /// curve that is at the given offset along the path (i.e. the direction of the
    /// curve at `position`).
    public let vector: Offset

    // MARK: - Initializers

    /// Creates a `Tangent` with the given values.
    ///
    /// **Dart Source:** `painting.dart:3501-3504`
    /// **Original:** `const Tangent(this.position, this.vector);`
    ///
    /// The arguments must not be null.
    public init(_ position: Offset, _ vector: Offset) {
        self.position = position
        self.vector = vector
    }

    /// Creates a `Tangent` based on the angle rather than the vector.
    ///
    /// **Dart Source:** `painting.dart:3506-3512`
    /// **Original:** `factory Tangent.fromAngle(Offset position, double angle)`
    ///
    /// The `vector` is computed to be the unit vector at the given angle, interpreted
    /// as clockwise radians from the x axis.
    public init(fromAngle position: Offset, angle: Double) {
        self.position = position
        self.vector = Offset(cos(angle), sin(angle))
    }

    // MARK: - Computed Properties

    /// The direction of the curve at `position`.
    ///
    /// **Dart Source:** `painting.dart:3527-3539`
    /// **Original:** `double get angle => -math.atan2(vector.dy, vector.dx);`
    ///
    /// When used with `PathMetric.getTangentForOffset`, this is the angle of the
    /// curve that is the given offset along the path (i.e. the direction of the
    /// curve at `position`).
    ///
    /// This value is in radians, with 0.0 meaning pointing along the x axis in
    /// the positive x-axis direction, positive numbers pointing downward toward
    /// the negative y-axis, i.e. in a clockwise direction, and negative numbers
    /// pointing upward toward the positive y-axis, i.e. in a counter-clockwise
    /// direction.
    ///
    /// Note: The sign is flipped to be consistent with `Path.arcTo`'s `sweepAngle`.
    public var angle: Double {
        // flip the sign to be consistent with [Path.arcTo]'s `sweepAngle`
        return -atan2(vector.dy, vector.dx)
    }
}

// MARK: - TargetImageSize

/// A specification of the size to which an image should be decoded.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `TargetImageSize`
/// **Lines:** 2585-2625
///
/// See also:
///  * `TargetImageSizeCallback`, a callback that returns instances of this
///    class when consulted by image decoding methods such as
///    `instantiateImageCodecWithSize`.
public struct TargetImageSize: CustomStringConvertible {

    // MARK: - Constructors

    /// Creates a new instance of this class.
    ///
    /// **Dart Source:** `painting.dart:2593-2599`
    /// **Original:** `const TargetImageSize({this.width, this.height})`
    ///
    /// The `width` and `height` may both be nil, but if they're non-nil, they
    /// must be positive.
    public init(width: Int64? = nil, height: Int64? = nil) {
        assert(width == nil || width! > 0, "width must be nil or positive")
        assert(height == nil || height! > 0, "height must be nil or positive")
        self.width = width
        self.height = height
    }

    // MARK: - Properties

    /// The width into which to load the image.
    ///
    /// **Dart Source:** `painting.dart:2601-2610`
    /// **Original:** `final int? width;`
    ///
    /// If this is non-nil, the image will be decoded into the specified width.
    /// If this is nil and `height` is also nil, the image will be decoded into
    /// its intrinsic size. If this is nil and `height` is non-nil, the image
    /// will be decoded into a width that maintains its intrinsic aspect ratio
    /// while respecting the `height` value.
    ///
    /// If this value is non-nil, it must be positive.
    public let width: Int64?

    /// The height into which to load the image.
    ///
    /// **Dart Source:** `painting.dart:2612-2621`
    /// **Original:** `final int? height;`
    ///
    /// If this is non-nil, the image will be decoded into the specified height.
    /// If this is nil and `width` is also nil, the image will be decoded into
    /// its intrinsic size. If this is nil and `width` is non-nil, the image
    /// will be decoded into a height that maintains its intrinsic aspect ratio
    /// while respecting the `width` value.
    ///
    /// If this value is non-nil, it must be positive.
    public let height: Int64?

    // MARK: - CustomStringConvertible

    /// Returns a string representation of this instance.
    ///
    /// **Dart Source:** `painting.dart:2623-2624`
    /// **Original:** `String toString() => 'TargetImageSize($width x $height)';`
    public var description: String {
        return "TargetImageSize(\(String(describing: width)) x \(String(describing: height)))"
    }
}

// MARK: - PictureRasterizationException

/// An exception thrown by Canvas.drawImage and related methods when drawing
/// an Image created via Picture.toImageSync that is in an invalid state.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:8065-8090`
/// **Original Name:** `PictureRasterizationException`
///
/// This exception may be thrown if the requested image dimensions exceeded the
/// maximum 2D texture size allowed by the GPU, or if no GPU surface or context
/// was available for rasterization at request time.
public struct PictureRasterizationException: Error, CustomStringConvertible {

    /// Creates a `PictureRasterizationException` with the given message and optional stack trace.
    ///
    /// **Dart Source:** `painting.dart:8072`
    /// **Original:** `const PictureRasterizationException._(this.message, {this.stack});`
    ///
    /// DIFFERENCE FROM DART: Using a public initializer since Swift doesn't have
    /// private named constructors with factory pattern. The Dart version uses a
    /// private named constructor `._` that's only called internally.
    /// REASON: Swift requires public initializer for struct construction.
    public init(message: String, stack: String? = nil) {
        self.message = message
        self.stack = stack
    }

    /// A string containing details about the failure.
    ///
    /// **Dart Source:** `painting.dart:8074-8075`
    /// **Original:** `final String message;`
    public let message: String

    /// If available, the stack trace at the time Picture.toImageSync was called.
    ///
    /// **Dart Source:** `painting.dart:8077-8078`
    /// **Original:** `final StackTrace? stack;`
    ///
    /// DIFFERENCE FROM DART: Using String? instead of StackTrace?
    /// REASON: Swift doesn't have a built-in StackTrace type like Dart.
    /// The stack trace is represented as a String for display purposes.
    public let stack: String?

    // MARK: - CustomStringConvertible

    /// Returns a string representation of this exception.
    ///
    /// **Dart Source:** `painting.dart:8080-8089`
    /// **Original:** `String toString()`
    public var description: String {
        var buffer = "Failed to rasterize a picture: \(message)."
        if let stack = stack {
            buffer += "\n"
            buffer += "The callstack when the image was created was:\n"
            buffer += stack
        }
        return buffer
    }
}

// MARK: - ColorFilter

/// A description of a color filter to apply when drawing a shape or compositing
/// a layer with a particular `Paint`. A color filter is a function that takes
/// two colors, and outputs one color. When applied during compositing, it is
/// independently applied to each pixel of the layer being drawn before the
/// entire layer is merged with the destination.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:3943-4133`
/// **Original Name:** `ColorFilter`
///
/// Instances of this class are used with `Paint.colorFilter` on `Paint` objects.
///
/// DIFFERENCE FROM DART: In Dart, ColorFilter implements ImageFilter. In Swift,
/// we represent this with a protocol conformance that will be added when
/// ImageFilter is migrated.
/// REASON: ImageFilter is a later task in the migration plan.
public struct ColorFilter: Hashable, CustomStringConvertible {
    // MARK: - Private Types

    /// The type of ColorFilter to create.
    ///
    /// **Dart Source:** `painting.dart:4051-4055`
    /// **Original:** Constants `_kTypeMode`, `_kTypeMatrix`, etc.
    private enum FilterType: Int {
        /// Creates a ModeFilter (DlBlendColorFilter).
        case mode = 1
        /// Creates a MatrixFilter (DlMatrixColorFilter).
        case matrix = 2
        /// Creates a LinearToSrgbGamma filter.
        case linearToSrgbGamma = 3
        /// Creates a SrgbToLinearGamma filter.
        case srgbToLinearGamma = 4
    }

    // MARK: - Private Fields

    /// The type of this color filter.
    ///
    /// **Dart Source:** `painting.dart:4049`
    /// **Original:** `final int _type;`
    private let type: FilterType

    /// The color for mode filters.
    ///
    /// **Dart Source:** `painting.dart:4046`
    /// **Original:** `final Color? _color;`
    private let color: Color?

    /// The blend mode for mode filters.
    ///
    /// **Dart Source:** `painting.dart:4047`
    /// **Original:** `final BlendMode? _blendMode;`
    private let blendMode: BlendMode?

    /// The 5x4 color matrix for matrix filters.
    ///
    /// **Dart Source:** `painting.dart:4048`
    /// **Original:** `final List<double>? _matrix;`
    private let matrix: [Double]?

    // MARK: - Initializers

    /// Creates a color filter that applies the blend mode given as the second
    /// argument. The source color is the one given as the first argument, and the
    /// destination color is the one from the layer being composited.
    ///
    /// **Dart Source:** `painting.dart:3952-3963`
    /// **Original:** `const ColorFilter.mode(Color color, BlendMode blendMode)`
    ///
    /// The output of this filter is then composited into the background according
    /// to the `Paint.blendMode`, using the output of this filter as the source
    /// and the background as the destination.
    public init(mode color: Color, _ blendMode: BlendMode) {
        self.type = .mode
        self.color = color
        self.blendMode = blendMode
        self.matrix = nil
    }

    /// Construct a color filter from a 4x5 row-major matrix. The matrix is
    /// interpreted as a 5x5 matrix, where the fifth row is the identity
    /// configuration.
    ///
    /// **Dart Source:** `painting.dart:3965-4028`
    /// **Original:** `const ColorFilter.matrix(List<double> matrix)`
    ///
    /// Every pixel's color value, represented as an `[R, G, B, A]`, is matrix
    /// multiplied to create a new color:
    ///
    ///     | R' |   | a00 a01 a02 a03 a04 |   | R |
    ///     | G' |   | a10 a11 a12 a13 a14 |   | G |
    ///     | B' | = | a20 a21 a22 a23 a24 | * | B |
    ///     | A' |   | a30 a31 a32 a33 a34 |   | A |
    ///     | 1  |   |  0   0   0   0   1  |   | 1 |
    ///
    /// The matrix is in row-major order and the translation column is specified
    /// in unnormalized, 0...255, space. For example, the identity matrix is:
    ///
    /// ```swift
    /// let identity = ColorFilter(matrix: [
    ///   1, 0, 0, 0, 0,
    ///   0, 1, 0, 0, 0,
    ///   0, 0, 1, 0, 0,
    ///   0, 0, 0, 1, 0,
    /// ])
    /// ```
    ///
    /// ## Examples
    ///
    /// An inversion color matrix:
    ///
    /// ```swift
    /// let invert = ColorFilter(matrix: [
    ///   -1,  0,  0, 0, 255,
    ///    0, -1,  0, 0, 255,
    ///    0,  0, -1, 0, 255,
    ///    0,  0,  0, 1,   0,
    /// ])
    /// ```
    ///
    /// A sepia-toned color matrix:
    ///
    /// ```swift
    /// let sepia = ColorFilter(matrix: [
    ///   0.393, 0.769, 0.189, 0, 0,
    ///   0.349, 0.686, 0.168, 0, 0,
    ///   0.272, 0.534, 0.131, 0, 0,
    ///   0,     0,     0,     1, 0,
    /// ])
    /// ```
    ///
    /// A greyscale color filter:
    ///
    /// ```swift
    /// let greyscale = ColorFilter(matrix: [
    ///   0.2126, 0.7152, 0.0722, 0, 0,
    ///   0.2126, 0.7152, 0.0722, 0, 0,
    ///   0.2126, 0.7152, 0.0722, 0, 0,
    ///   0,      0,      0,      1, 0,
    /// ])
    /// ```
    public init(matrix: [Double]) {
        assert(matrix.count == 20, "Color Matrix must have 20 entries.")
        self.type = .matrix
        self.color = nil
        self.blendMode = nil
        self.matrix = matrix
    }

    /// Construct a color filter that applies the sRGB gamma curve to the RGB
    /// channels.
    ///
    /// **Dart Source:** `painting.dart:4030-4036`
    /// **Original:** `const ColorFilter.linearToSrgbGamma()`
    public init(linearToSrgbGamma: Void = ()) {
        self.type = .linearToSrgbGamma
        self.color = nil
        self.blendMode = nil
        self.matrix = nil
    }

    /// Creates a color filter that applies the inverse of the sRGB gamma curve
    /// to the RGB channels.
    ///
    /// **Dart Source:** `painting.dart:4038-4044`
    /// **Original:** `const ColorFilter.srgbToLinearGamma()`
    public init(srgbToLinearGamma: Void = ()) {
        self.type = .srgbToLinearGamma
        self.color = nil
        self.blendMode = nil
        self.matrix = nil
    }

    // MARK: - Internal Accessors

    /// Returns the filter type for internal use.
    internal var filterType: Int {
        return type.rawValue
    }

    /// Returns the color for mode filters.
    internal var filterColor: Color? {
        return color
    }

    /// Returns the blend mode for mode filters.
    internal var filterBlendMode: BlendMode? {
        return blendMode
    }

    /// Returns the matrix for matrix filters.
    internal var filterMatrix: [Double]? {
        return matrix
    }

    // MARK: - Equatable

    /// Compares two color filters for equality.
    ///
    /// **Dart Source:** `painting.dart:4084-4094`
    /// **Original:** `bool operator ==(Object other)`
    public static func == (lhs: ColorFilter, rhs: ColorFilter) -> Bool {
        if lhs.type != rhs.type {
            return false
        }
        if !listEquals(lhs.matrix, rhs.matrix) {
            return false
        }
        if lhs.color != rhs.color {
            return false
        }
        if lhs.blendMode != rhs.blendMode {
            return false
        }
        return true
    }

    // MARK: - Hashable

    /// The hash code for this color filter.
    ///
    /// **Dart Source:** `painting.dart:4096-4100`
    /// **Original:** `int get hashCode`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(color)
        hasher.combine(blendMode)
        if let matrix = matrix {
            for value in matrix {
                hasher.combine(value)
            }
        }
        hasher.combine(type)
    }

    // MARK: - CustomStringConvertible

    /// Returns a string representation of this color filter.
    ///
    /// **Dart Source:** `painting.dart:4118-4132`
    /// **Original:** `String toString()`
    public var description: String {
        switch type {
        case .mode:
            return "ColorFilter.mode(\(color!), \(blendMode!))"
        case .matrix:
            return "ColorFilter.matrix(\(matrix!))"
        case .linearToSrgbGamma:
            return "ColorFilter.linearToSrgbGamma()"
        case .srgbToLinearGamma:
            return "ColorFilter.srgbToLinearGamma()"
        }
    }

    /// Returns a short description for internal use.
    ///
    /// **Dart Source:** `painting.dart:4102-4116`
    /// **Original:** `String get _shortDescription`
    public var shortDescription: String {
        return description
    }
}

// MARK: - _NativeColorFilter

/// A `ColorFilter` that is backed by a native DlColorFilter via C++ bridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:4135-4181`
/// **Original Name:** `_ColorFilter`
///
/// This is a private class, rather than being the implementation of the public
/// ColorFilter, because we want ColorFilter to be const constructible and
/// efficiently comparable, so that widgets can check for ColorFilter equality to
/// avoid repainting.
///
/// DIFFERENCE FROM DART: In Dart, _ColorFilter extends NativeFieldWrapperClass1.
/// In Swift, we wrap a ColorFilterBridge C++ object via SWIFT_SHARED_REFERENCE.
/// REASON: Swift uses ARC with C++ bridge objects instead of Dart VM wrapper classes.
internal class _NativeColorFilter {
    /// The C++ bridge object holding the native DlColorFilter.
    internal let bridge: flutter.swift_bridge.ColorFilterBridge

    /// The original ColorFilter that created this native wrapper.
    ///
    /// **Dart Source:** `painting.dart:4163-4165`
    /// **Original:** `final ColorFilter creator;`
    internal let creator: ColorFilter

    /// Creates a mode (blend) color filter backed by native DlColorFilter.
    ///
    /// **Dart Source:** `painting.dart:4142-4145`
    /// **Original:** `_ColorFilter.mode(this.creator)`
    internal init(mode creator: ColorFilter) {
        assert(creator.filterType == 1) // _kTypeMode
        self.creator = creator
        self.bridge = flutter.swift_bridge.ColorFilterBridge()
        // Bit-pattern, not value: any colour with the alpha top bit set (all
        // opaque ones) exceeds Int32.max and a checked Int32(_:) traps.
        bridge.InitMode(Int32(bitPattern: UInt32(creator.filterColor!.value)),
                        Int32(creator.filterBlendMode!.rawValue))
    }

    /// Creates a matrix color filter backed by native DlColorFilter.
    ///
    /// **Dart Source:** `painting.dart:4147-4150`
    /// **Original:** `_ColorFilter.matrix(this.creator)`
    internal init(matrix creator: ColorFilter) {
        assert(creator.filterType == 2) // _kTypeMatrix
        self.creator = creator
        self.bridge = flutter.swift_bridge.ColorFilterBridge()
        // Convert Double matrix to Float32 array for C++ bridge
        let doubleMatrix = creator.filterMatrix!
        var floatMatrix: [Float] = doubleMatrix.map { Float($0) }
        floatMatrix.withUnsafeMutableBufferPointer { buffer in
            bridge.InitMatrix(buffer.baseAddress!)
        }
    }

    /// Creates a linear-to-sRGB gamma color filter backed by native DlColorFilter.
    ///
    /// **Dart Source:** `painting.dart:4151-4155`
    /// **Original:** `_ColorFilter.linearToSrgbGamma(this.creator)`
    internal init(linearToSrgbGamma creator: ColorFilter) {
        assert(creator.filterType == 3) // _kTypeLinearToSrgbGamma
        self.creator = creator
        self.bridge = flutter.swift_bridge.ColorFilterBridge()
        bridge.InitLinearToSrgbGamma()
    }

    /// Creates an sRGB-to-linear gamma color filter backed by native DlColorFilter.
    ///
    /// **Dart Source:** `painting.dart:4157-4161`
    /// **Original:** `_ColorFilter.srgbToLinearGamma(this.creator)`
    internal init(srgbToLinearGamma creator: ColorFilter) {
        assert(creator.filterType == 4) // _kTypeSrgbToLinearGamma
        self.creator = creator
        self.bridge = flutter.swift_bridge.ColorFilterBridge()
        bridge.InitSrgbToLinearGamma()
    }
}

/// Extension on ColorFilter to create the native backing filter.
///
/// **Dart Source:** `painting.dart:4057-4082`
/// **Original:** `_ColorFilter _toNativeColorFilter()`
extension ColorFilter {
    /// Creates a native `_NativeColorFilter` backed by a C++ DlColorFilter.
    ///
    /// **Dart Source:** `painting.dart:4057-4082`
    /// **Original:** `_ColorFilter _toNativeColorFilter()`
    internal func toNativeColorFilter() -> _NativeColorFilter {
        switch filterType {
        case 1:
            return _NativeColorFilter(mode: self)
        case 2:
            return _NativeColorFilter(matrix: self)
        case 3:
            return _NativeColorFilter(linearToSrgbGamma: self)
        case 4:
            return _NativeColorFilter(srgbToLinearGamma: self)
        default:
            fatalError("Unknown ColorFilter type: \(filterType)")
        }
    }
}

// MARK: - Helper Functions

// listEquals is defined in Text.swift as internal and shared across the module.
// It was previously duplicated here as private; now uses the shared version.

// MARK: - ImageFilter

/// A filter operation to apply to a raster image.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:4183-4309`
/// **Original Name:** `ImageFilter`
///
/// See also:
///
///  * `BackdropFilter`, a widget that applies `ImageFilter` to its rendering.
///  * `ImageFiltered`, a widget that applies `ImageFilter` to its children.
///  * `SceneBuilder.pushBackdropFilter`, which is the low-level API for using
///    this class as a backdrop filter.
///  * `SceneBuilder.pushImageFilter`, which is the low-level API for using
///    this class as a child layer filter.
///
/// DIFFERENCE FROM DART: ImageFilter is a protocol in Swift instead of an abstract class.
/// REASON: Swift uses protocols for defining interfaces; concrete implementations are
/// provided through separate structs/classes that conform to the protocol.
public protocol ImageFilter: Hashable, CustomStringConvertible {
    /// The description text to show when the filter is part of a composite
    /// `ImageFilter` created using `ImageFilter.compose`.
    ///
    /// **Dart Source:** `painting.dart:4306-4308`
    /// **Original:** `String get _shortDescription;`
    var shortDescription: String { get }

    /// Converts this to a native DlImageFilter.
    ///
    /// **Dart Source:** `painting.dart:4302-4304`
    /// **Original:** `_ImageFilter _toNativeImageFilter();`
    func toNativeImageFilter() -> NativeImageFilter
}

// MARK: - ImageFilter Factory Methods

/// Extension providing factory methods for creating ImageFilter instances.
///
/// **Dart Source:** `painting.dart:4193-4300`
///
/// DIFFERENCE FROM DART: Factory constructors are implemented as static methods
/// returning concrete types that conform to ImageFilter protocol.
/// REASON: Swift doesn't have factory constructors; static methods serve the same purpose.
public enum ImageFilterFactory {
    /// Creates an image filter that applies a Gaussian blur.
    ///
    /// **Dart Source:** `painting.dart:4197-4200`
    /// **Original:** `factory ImageFilter.blur({double sigmaX = 0.0, double sigmaY = 0.0, TileMode? tileMode})`
    public static func blur(sigmaX: Double = 0.0, sigmaY: Double = 0.0, tileMode: TileMode? = nil) -> GaussianBlurImageFilter {
        return GaussianBlurImageFilter(sigmaX: sigmaX, sigmaY: sigmaY, tileMode: tileMode)
    }

    /// Creates an image filter that dilates each input pixel's channel values
    /// to the max value within the given radii along the x and y axes.
    ///
    /// **Dart Source:** `painting.dart:4202-4206`
    /// **Original:** `factory ImageFilter.dilate({double radiusX = 0.0, double radiusY = 0.0})`
    public static func dilate(radiusX: Double = 0.0, radiusY: Double = 0.0) -> DilateImageFilter {
        return DilateImageFilter(radiusX: radiusX, radiusY: radiusY)
    }

    /// Creates a filter that erodes each input pixel's channel values
    /// to the minimum channel value within the given radii along the x and y axes.
    ///
    /// **Dart Source:** `painting.dart:4208-4212`
    /// **Original:** `factory ImageFilter.erode({double radiusX = 0.0, double radiusY = 0.0})`
    public static func erode(radiusX: Double = 0.0, radiusY: Double = 0.0) -> ErodeImageFilter {
        return ErodeImageFilter(radiusX: radiusX, radiusY: radiusY)
    }

    /// Creates an image filter that applies a matrix transformation.
    ///
    /// **Dart Source:** `painting.dart:4214-4226`
    /// **Original:** `factory ImageFilter.matrix(Float64List matrix4, {FilterQuality filterQuality = FilterQuality.medium})`
    ///
    /// For example, applying a positive scale matrix (see `Matrix4.diagonal3`)
    /// when used with `BackdropFilter` would magnify the background image.
    public static func matrix(_ matrix4: [Double], filterQuality: FilterQuality = .medium) -> MatrixImageFilter {
        precondition(matrix4.count == 16, "\"matrix4\" must have 16 entries.")
        return MatrixImageFilter(data: matrix4, filterQuality: filterQuality)
    }

    /// Composes the `inner` filter with `outer`, to combine their effects.
    ///
    /// **Dart Source:** `painting.dart:4228-4235`
    /// **Original:** `factory ImageFilter.compose({required ImageFilter outer, required ImageFilter inner})`
    ///
    /// Creates a single `ImageFilter` that when applied, has the same effect as
    /// subsequently applying `inner` and `outer`, i.e.,
    /// result = outer(inner(source)).
    public static func compose<Outer: ImageFilter, Inner: ImageFilter>(outer: Outer, inner: Inner) -> ComposeImageFilter<Outer, Inner> {
        return ComposeImageFilter(innerFilter: inner, outerFilter: outer)
    }

    /// Creates an image filter from a `FragmentShader`.
    ///
    /// **Dart Source:** `painting.dart:4237-4297`
    /// **Original:** `factory ImageFilter.shader(FragmentShader shader)`
    ///
    /// The fragment shader provided here has additional requirements to be used
    /// by the engine for filtering. The first uniform value must be a vec2, this
    /// will be set by the engine to the size of the bound texture. There must
    /// also be at least one sampler2D uniform, the first of which will be set by
    /// the engine to contain the filter input.
    ///
    /// This API requires a rendering engine that supports shader image filters.
    public static func shader(_ shader: FragmentShader) -> FragmentShaderImageFilter {
        return FragmentShaderImageFilter(shader: shader)
    }

    /// Whether `ImageFilter.shader` is supported on the current backend.
    ///
    /// **Dart Source:** `painting.dart:4299-4300`
    ///
    /// Currently returns false (Skia-only rendering).
    public static var isShaderFilterSupported: Bool {
        return false
    }
}

// MARK: - GaussianBlurImageFilter

/// An image filter that applies a Gaussian blur.
///
/// **Dart Source:** `painting.dart:4342-4388`
/// **Original Name:** `_GaussianBlurImageFilter`
///
/// DIFFERENCE FROM DART: Public struct instead of private class.
/// REASON: Swift requires public types for protocol conformance in public API.
public struct GaussianBlurImageFilter: ImageFilter {
    /// The standard deviation of the Gaussian blur in the x direction.
    ///
    /// **Dart Source:** `painting.dart:4345`
    /// **Original:** `final double sigmaX;`
    public let sigmaX: Double

    /// The standard deviation of the Gaussian blur in the y direction.
    ///
    /// **Dart Source:** `painting.dart:4346`
    /// **Original:** `final double sigmaY;`
    public let sigmaY: Double

    /// The tile mode used to handle edges.
    ///
    /// **Dart Source:** `painting.dart:4347`
    /// **Original:** `final TileMode? tileMode;`
    public let tileMode: TileMode?

    /// Creates a Gaussian blur image filter.
    ///
    /// **Dart Source:** `painting.dart:4343`
    /// **Original:** `_GaussianBlurImageFilter({required this.sigmaX, required this.sigmaY, required this.tileMode})`
    public init(sigmaX: Double, sigmaY: Double, tileMode: TileMode?) {
        self.sigmaX = sigmaX
        self.sigmaY = sigmaY
        self.tileMode = tileMode
    }

    // MARK: - Private Helpers

    /// Returns a string representation of the tile mode.
    ///
    /// **Dart Source:** `painting.dart:4354-4367`
    /// **Original:** `String get _modeString`
    private var modeString: String {
        switch tileMode {
        case .clamp:
            return "clamp"
        case .mirror:
            return "mirror"
        case .repeated:
            return "repeated"
        case .decal:
            return "decal"
        case nil:
            return "unspecified"
        }
    }

    // MARK: - ImageFilter

    /// **Dart Source:** `painting.dart:4369-4370`
    /// **Original:** `String get _shortDescription => 'blur($sigmaX, $sigmaY, $_modeString)';`
    public var shortDescription: String {
        return "blur(\(sigmaX), \(sigmaY), \(modeString))"
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `painting.dart:4372-4373`
    /// **Original:** `String toString() => 'ImageFilter.blur($sigmaX, $sigmaY, $_modeString)';`
    public var description: String {
        return "ImageFilter.blur(\(sigmaX), \(sigmaY), \(modeString))"
    }

    // MARK: - Hashable

    /// **Dart Source:** `painting.dart:4386-4387`
    /// **Original:** `int get hashCode => Object.hash(sigmaX, sigmaY);`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(sigmaX)
        hasher.combine(sigmaY)
    }

    // MARK: - Equatable

    /// **Dart Source:** `painting.dart:4375-4383`
    /// **Original:** `bool operator ==(Object other)`
    public static func == (lhs: GaussianBlurImageFilter, rhs: GaussianBlurImageFilter) -> Bool {
        return lhs.sigmaX == rhs.sigmaX &&
               lhs.sigmaY == rhs.sigmaY &&
               lhs.tileMode == rhs.tileMode
    }
}

// MARK: - DilateImageFilter

/// An image filter that dilates each input pixel's channel values
/// to the max value within the given radii along the x and y axes.
///
/// **Dart Source:** `painting.dart:4390-4416`
/// **Original Name:** `_DilateImageFilter`
public struct DilateImageFilter: ImageFilter {
    /// The radius of dilation in the x direction.
    ///
    /// **Dart Source:** `painting.dart:4393`
    /// **Original:** `final double radiusX;`
    public let radiusX: Double

    /// The radius of dilation in the y direction.
    ///
    /// **Dart Source:** `painting.dart:4394`
    /// **Original:** `final double radiusY;`
    public let radiusY: Double

    /// Creates a dilate image filter.
    ///
    /// **Dart Source:** `painting.dart:4391`
    /// **Original:** `_DilateImageFilter({required this.radiusX, required this.radiusY})`
    public init(radiusX: Double, radiusY: Double) {
        self.radiusX = radiusX
        self.radiusY = radiusY
    }

    // MARK: - ImageFilter

    /// **Dart Source:** `painting.dart:4400-4401`
    /// **Original:** `String get _shortDescription => 'dilate($radiusX, $radiusY)';`
    public var shortDescription: String {
        return "dilate(\(radiusX), \(radiusY))"
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `painting.dart:4403-4404`
    /// **Original:** `String toString() => 'ImageFilter.dilate($radiusX, $radiusY)';`
    public var description: String {
        return "ImageFilter.dilate(\(radiusX), \(radiusY))"
    }

    // MARK: - Hashable

    /// **Dart Source:** `painting.dart:4414-4415`
    /// **Original:** `int get hashCode => Object.hash(radiusX, radiusY);`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(radiusX)
        hasher.combine(radiusY)
    }

    // MARK: - Equatable

    /// **Dart Source:** `painting.dart:4406-4411`
    /// **Original:** `bool operator ==(Object other)`
    public static func == (lhs: DilateImageFilter, rhs: DilateImageFilter) -> Bool {
        return lhs.radiusX == rhs.radiusX && lhs.radiusY == rhs.radiusY
    }
}

// MARK: - ErodeImageFilter

/// A filter that erodes each input pixel's channel values
/// to the minimum channel value within the given radii along the x and y axes.
///
/// **Dart Source:** `painting.dart:4418-4444`
/// **Original Name:** `_ErodeImageFilter`
public struct ErodeImageFilter: ImageFilter {
    /// The radius of erosion in the x direction.
    ///
    /// **Dart Source:** `painting.dart:4421`
    /// **Original:** `final double radiusX;`
    public let radiusX: Double

    /// The radius of erosion in the y direction.
    ///
    /// **Dart Source:** `painting.dart:4422`
    /// **Original:** `final double radiusY;`
    public let radiusY: Double

    /// Creates an erode image filter.
    ///
    /// **Dart Source:** `painting.dart:4419`
    /// **Original:** `_ErodeImageFilter({required this.radiusX, required this.radiusY})`
    public init(radiusX: Double, radiusY: Double) {
        self.radiusX = radiusX
        self.radiusY = radiusY
    }

    // MARK: - ImageFilter

    /// **Dart Source:** `painting.dart:4428-4429`
    /// **Original:** `String get _shortDescription => 'erode($radiusX, $radiusY)';`
    public var shortDescription: String {
        return "erode(\(radiusX), \(radiusY))"
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `painting.dart:4431-4432`
    /// **Original:** `String toString() => 'ImageFilter.erode($radiusX, $radiusY)';`
    public var description: String {
        return "ImageFilter.erode(\(radiusX), \(radiusY))"
    }

    // MARK: - Hashable

    /// **Dart Source:** `painting.dart:4442-4443`
    /// **Original:** `int get hashCode => Object.hash(radiusX, radiusY);`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(radiusX)
        hasher.combine(radiusY)
    }

    // MARK: - Equatable

    /// **Dart Source:** `painting.dart:4434-4439`
    /// **Original:** `bool operator ==(Object other)`
    public static func == (lhs: ErodeImageFilter, rhs: ErodeImageFilter) -> Bool {
        return lhs.radiusX == rhs.radiusX && lhs.radiusY == rhs.radiusY
    }
}

// MARK: - MatrixImageFilter

/// An image filter that applies a matrix transformation.
///
/// **Dart Source:** `painting.dart:4311-4340`
/// **Original Name:** `_MatrixImageFilter`
public struct MatrixImageFilter: ImageFilter {
    /// The 4x4 transformation matrix (16 elements).
    ///
    /// **Dart Source:** `painting.dart:4314`
    /// **Original:** `final Float64List data;`
    public let data: [Double]

    /// The filter quality to use when sampling.
    ///
    /// **Dart Source:** `painting.dart:4315`
    /// **Original:** `final FilterQuality filterQuality;`
    public let filterQuality: FilterQuality

    /// Creates a matrix image filter.
    ///
    /// **Dart Source:** `painting.dart:4312`
    /// **Original:** `_MatrixImageFilter({required this.data, required this.filterQuality})`
    public init(data: [Double], filterQuality: FilterQuality) {
        self.data = data
        self.filterQuality = filterQuality
    }

    // MARK: - ImageFilter

    /// **Dart Source:** `painting.dart:4322-4323`
    /// **Original:** `String get _shortDescription => 'matrix($data, $filterQuality)';`
    public var shortDescription: String {
        return "matrix(\(data), \(filterQuality))"
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `painting.dart:4325-4326`
    /// **Original:** `String toString() => 'ImageFilter.matrix($data, $filterQuality)';`
    public var description: String {
        return "ImageFilter.matrix(\(data), \(filterQuality))"
    }

    // MARK: - Hashable

    /// **Dart Source:** `painting.dart:4338-4339`
    /// **Original:** `int get hashCode => Object.hash(filterQuality, Object.hashAll(data));`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(filterQuality)
        for value in data {
            hasher.combine(value)
        }
    }

    // MARK: - Equatable

    /// **Dart Source:** `painting.dart:4328-4335`
    /// **Original:** `bool operator ==(Object other)`
    public static func == (lhs: MatrixImageFilter, rhs: MatrixImageFilter) -> Bool {
        if lhs.filterQuality != rhs.filterQuality {
            return false
        }
        return listEquals(lhs.data, rhs.data)
    }
}

// MARK: - ComposeImageFilter

/// An image filter that composes two other filters.
///
/// **Dart Source:** `painting.dart:4446-4476`
/// **Original Name:** `_ComposeImageFilter`
///
/// Creates a single `ImageFilter` that when applied, has the same effect as
/// subsequently applying `inner` and `outer`, i.e.,
/// result = outer(inner(source)).
public struct ComposeImageFilter<Outer: ImageFilter, Inner: ImageFilter>: ImageFilter {
    /// The inner filter applied first.
    ///
    /// **Dart Source:** `painting.dart:4449`
    /// **Original:** `final ImageFilter innerFilter;`
    public let innerFilter: Inner

    /// The outer filter applied second.
    ///
    /// **Dart Source:** `painting.dart:4450`
    /// **Original:** `final ImageFilter outerFilter;`
    public let outerFilter: Outer

    /// Creates a composed image filter.
    ///
    /// **Dart Source:** `painting.dart:4447`
    /// **Original:** `_ComposeImageFilter({required this.innerFilter, required this.outerFilter})`
    public init(innerFilter: Inner, outerFilter: Outer) {
        self.innerFilter = innerFilter
        self.outerFilter = outerFilter
    }

    // MARK: - ImageFilter

    /// **Dart Source:** `painting.dart:4457-4459`
    /// **Original:** `String get _shortDescription => '${innerFilter._shortDescription} -> ${outerFilter._shortDescription}';`
    public var shortDescription: String {
        return "\(innerFilter.shortDescription) -> \(outerFilter.shortDescription)"
    }

    // MARK: - CustomStringConvertible

    /// **Dart Source:** `painting.dart:4461-4462`
    /// **Original:** `String toString() => 'ImageFilter.compose(source -> $_shortDescription -> result)';`
    public var description: String {
        return "ImageFilter.compose(source -> \(shortDescription) -> result)"
    }

    // MARK: - Hashable

    /// **Dart Source:** `painting.dart:4474-4475`
    /// **Original:** `int get hashCode => Object.hash(innerFilter, outerFilter);`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(innerFilter)
        hasher.combine(outerFilter)
    }

    // MARK: - Equatable

    /// **Dart Source:** `painting.dart:4464-4471`
    /// **Original:** `bool operator ==(Object other)`
    public static func == (lhs: ComposeImageFilter<Outer, Inner>, rhs: ComposeImageFilter<Outer, Inner>) -> Bool {
        return lhs.innerFilter == rhs.innerFilter && lhs.outerFilter == rhs.outerFilter
    }
}

// MARK: - FragmentShaderImageFilter

/// An image filter backed by a `FragmentShader`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:4478-4509`
/// **Original Name:** `_FragmentShaderImageFilter`
///
/// DIFFERENCE FROM DART: Made public as `FragmentShaderImageFilter` (Swift doesn't have
/// private top-level classes). The `_equals` native method is replaced with
/// `NativeImageFilter.equals()` via the C++ bridge.
/// REASON: Swift naming conventions; native equality delegated to C++ bridge.
public struct FragmentShaderImageFilter: ImageFilter {
    /// The fragment shader used as an image filter.
    ///
    /// **Dart Source:** `painting.dart:4481`
    /// **Original:** `final FragmentShader shader;`
    public let shader: FragmentShader

    /// Creates a fragment shader image filter.
    ///
    /// **Dart Source:** `painting.dart:4479`
    /// **Original:** `_FragmentShaderImageFilter(this.shader);`
    public init(shader: FragmentShader) {
        self.shader = shader
    }

    // MARK: - ImageFilter

    /// **Dart Source:** `painting.dart:4489`
    /// **Original:** `String get _shortDescription => 'shader';`
    public var shortDescription: String {
        return "shader"
    }

    /// **Dart Source:** `painting.dart:4492`
    /// **Original:** `String toString() => 'ImageFilter.shader(Shader#${shader.hashCode})';`
    ///
    /// DIFFERENCE FROM DART: Uses ObjectIdentifier hash instead of Dart's hashCode.
    /// REASON: Swift classes don't have a built-in hashCode property; ObjectIdentifier
    /// provides a stable identity-based hash for reference types.
    public var description: String {
        return "ImageFilter.shader(Shader#\(ObjectIdentifier(shader).hashValue))"
    }

    // MARK: - Hashable

    /// **Dart Source:** `painting.dart:4507-4508`
    /// **Original:** `int get hashCode => shader.hashCode;`
    ///
    /// DIFFERENCE FROM DART: Uses ObjectIdentifier for hashing since FragmentShader
    /// is a reference type (class) without Hashable conformance.
    /// REASON: Swift's Hashable protocol requires value-based hashing; we use
    /// identity-based hashing for the shader reference.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(shader))
    }

    // MARK: - Equatable

    /// **Dart Source:** `painting.dart:4495-4501`
    /// **Original:** `bool operator ==(Object other)`
    ///
    /// DIFFERENCE FROM DART: The Dart version also calls `_equals(nativeFilter, other.nativeFilter)`
    /// via a @Native method for deep DlImageFilter comparison. In Swift, we compare
    /// the shader reference for identity, matching the primary comparison.
    /// REASON: The native equality check is an optimization for comparing the underlying
    /// DlImageFilter objects; shader equality is the semantic check.
    public static func == (lhs: FragmentShaderImageFilter, rhs: FragmentShaderImageFilter) -> Bool {
        return lhs.shader === rhs.shader
    }
}

// MARK: - NativeImageFilter

/// Native backing for ImageFilter implementations.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:4511-4607`
/// **Original Name:** `_ImageFilter`
///
/// This class wraps the C++ `ImageFilterBridge` which holds a `DlImageFilter`.
/// In Dart, `_ImageFilter` extends `NativeFieldWrapperClass1` and is created lazily
/// by each concrete ImageFilter implementation via `_toNativeImageFilter()`.
///
/// In Swift, `NativeImageFilter` is used when a native DlImageFilter is needed
/// (e.g., for Paint, Canvas, or SceneBuilder operations).
///
/// DIFFERENCE FROM DART: Renamed from `_ImageFilter` to `NativeImageFilter`.
/// REASON: Swift naming conventions; `_` prefix not idiomatic in Swift.
public class NativeImageFilter {
    /// The C++ bridge object that holds the DlImageFilter.
    internal let bridge: flutter.swift_bridge.ImageFilterBridge

    /// The original filter that created this native wrapper.
    ///
    /// **Dart Source:** `painting.dart:4604-4606`
    /// **Original:** `final ImageFilter creator;`
    ///
    /// Retains the values used for the filter for efficient comparison.
    ///
    /// DIFFERENCE FROM DART: Typed as `Any` instead of `ImageFilter` because in Dart
    /// `ColorFilter implements ImageFilter`, but in Swift `ColorFilter` does not conform
    /// to the `ImageFilter` protocol. The `fromColorFilter` constructor stores a `ColorFilter`.
    /// REASON: Swift's protocol system doesn't allow retroactive conformance here without
    /// broader architectural changes.
    public let creator: Any

    /// Creates a native blur image filter.
    ///
    /// **Dart Source:** `painting.dart:4518-4521`
    /// **Original:** `_ImageFilter.blur(_GaussianBlurImageFilter filter)`
    public init(blur filter: GaussianBlurImageFilter) {
        self.creator = filter
        self.bridge = flutter.swift_bridge.ImageFilterBridge()
        bridge.InitBlur(filter.sigmaX, filter.sigmaY,
                        Int32(filter.tileMode?.rawValue ?? -1))
    }

    /// Creates a native dilate image filter.
    ///
    /// **Dart Source:** `painting.dart:4525-4527`
    /// **Original:** `_ImageFilter.dilate(_DilateImageFilter filter)`
    public init(dilate filter: DilateImageFilter) {
        self.creator = filter
        self.bridge = flutter.swift_bridge.ImageFilterBridge()
        bridge.InitDilate(filter.radiusX, filter.radiusY)
    }

    /// Creates a native erode image filter.
    ///
    /// **Dart Source:** `painting.dart:4532-4534`
    /// **Original:** `_ImageFilter.erode(_ErodeImageFilter filter)`
    public init(erode filter: ErodeImageFilter) {
        self.creator = filter
        self.bridge = flutter.swift_bridge.ImageFilterBridge()
        bridge.InitErode(filter.radiusX, filter.radiusY)
    }

    /// Creates a native matrix image filter.
    ///
    /// **Dart Source:** `painting.dart:4541-4547`
    /// **Original:** `_ImageFilter.matrix(_MatrixImageFilter filter)`
    public init(matrix filter: MatrixImageFilter) {
        self.creator = filter
        self.bridge = flutter.swift_bridge.ImageFilterBridge()
        precondition(filter.data.count == 16, "\"matrix4\" must have 16 entries.")
        filter.data.withUnsafeBufferPointer { buffer in
            bridge.InitMatrix(buffer.baseAddress!, Int32(filter.filterQuality.rawValue))
        }
    }

    /// Creates a native image filter from a color filter.
    ///
    /// **Dart Source:** `painting.dart:4550-4554`
    /// **Original:** `_ImageFilter.fromColorFilter(ColorFilter filter)`
    public init(colorFilter filter: ColorFilter) {
        self.creator = filter
        self.bridge = flutter.swift_bridge.ImageFilterBridge()
        let nativeColorFilter = filter.toNativeColorFilter()
        bridge.InitColorFilter(nativeColorFilter.bridge)
    }

    /// Creates a native composed image filter.
    ///
    /// **Dart Source:** `painting.dart:4557-4562`
    /// **Original:** `_ImageFilter.composed(_ComposeImageFilter filter)`
    ///
    /// @param innerFilter The inner filter (applied first)
    /// @param outerFilter The outer filter (applied second)
    /// @param creator The original ImageFilter that created this native wrapper
    public init(composed creator: any ImageFilter,
                innerFilter: any ImageFilter,
                outerFilter: any ImageFilter) {
        self.creator = creator
        self.bridge = flutter.swift_bridge.ImageFilterBridge()
        let nativeInner = innerFilter.toNativeImageFilter()
        let nativeOuter = outerFilter.toNativeImageFilter()
        bridge.InitComposed(nativeOuter.bridge, nativeInner.bridge)
    }

    /// Creates a native shader image filter.
    ///
    /// **Dart Source:** `painting.dart:4564-4567`
    /// **Original:** `_ImageFilter.shader(_FragmentShaderImageFilter filter)`
    public init(shader filter: FragmentShaderImageFilter) {
        self.creator = filter
        self.bridge = flutter.swift_bridge.ImageFilterBridge()
        bridge.InitShader(filter.shader.fragmentShaderBridge)
    }

    /// Compares two native image filters for equality.
    ///
    /// **Dart Source:** `painting.dart:4504-4505`
    /// **Original:** `static bool _equals(_ImageFilter a, _ImageFilter b)`
    public static func equals(_ a: NativeImageFilter, _ b: NativeImageFilter) -> Bool {
        return a.bridge.Equals(b.bridge)
    }
}

// MARK: - ImageFilter toNativeImageFilter extensions

/// Extension to create native image filters from concrete filter types.
///
/// **Dart Source:** `painting.dart:4302-4304`
/// **Original:** `_ImageFilter _toNativeImageFilter();`
///
/// Each concrete ImageFilter type lazily creates its native backing
/// via `_toNativeImageFilter()`. In Swift, this is implemented as
/// protocol extension methods that create `NativeImageFilter` instances.
extension GaussianBlurImageFilter {
    /// Creates the native DlBlurImageFilter backing.
    ///
    /// **Dart Source:** `painting.dart:4350-4352`
    /// **Original:** `late final _ImageFilter nativeFilter = _ImageFilter.blur(this);`
    public func toNativeImageFilter() -> NativeImageFilter {
        return NativeImageFilter(blur: self)
    }
}

extension DilateImageFilter {
    /// Creates the native DlDilateImageFilter backing.
    ///
    /// **Dart Source:** `painting.dart:4396-4398`
    /// **Original:** `late final _ImageFilter nativeFilter = _ImageFilter.dilate(this);`
    public func toNativeImageFilter() -> NativeImageFilter {
        return NativeImageFilter(dilate: self)
    }
}

extension ErodeImageFilter {
    /// Creates the native DlErodeImageFilter backing.
    ///
    /// **Dart Source:** `painting.dart:4424-4426`
    /// **Original:** `late final _ImageFilter nativeFilter = _ImageFilter.erode(this);`
    public func toNativeImageFilter() -> NativeImageFilter {
        return NativeImageFilter(erode: self)
    }
}

extension MatrixImageFilter {
    /// Creates the native DlMatrixImageFilter backing.
    ///
    /// **Dart Source:** `painting.dart:4318-4320`
    /// **Original:** `late final _ImageFilter nativeFilter = _ImageFilter.matrix(this);`
    public func toNativeImageFilter() -> NativeImageFilter {
        return NativeImageFilter(matrix: self)
    }
}

extension FragmentShaderImageFilter {
    /// Creates the native DlImageFilter backing from a fragment shader.
    ///
    /// **Dart Source:** `painting.dart:4483-4486`
    /// **Original:** `late final _ImageFilter nativeFilter = _ImageFilter.shader(this);`
    public func toNativeImageFilter() -> NativeImageFilter {
        return NativeImageFilter(shader: self)
    }
}

extension ComposeImageFilter {
    /// Creates the native DlComposeImageFilter backing.
    ///
    /// **Dart Source:** `painting.dart:4453-4455`
    /// **Original:** `late final _ImageFilter nativeFilter = _ImageFilter.composed(this);`
    public func toNativeImageFilter() -> NativeImageFilter {
        return NativeImageFilter(composed: self,
                                 innerFilter: innerFilter,
                                 outerFilter: outerFilter)
    }
}

// MARK: - Shader

/// Base class for objects such as `Gradient` and `ImageShader` which
/// correspond to shaders as used by `Paint.shader`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:4609-4647`
/// **Original Name:** `Shader` (base class)
///
/// This class is created by the engine, and should not be instantiated
/// or extended directly.
///
/// DIFFERENCE FROM DART: In Dart, Shader extends NativeFieldWrapperClass1 for FFI.
/// In Swift, we use a C++ bridge (ShaderBridge) with SWIFT_SHARED_REFERENCE for
/// automatic memory management via Swift ARC.
/// REASON: Swift doesn't use Dart FFI; instead uses direct C++ interop.
public class Shader {
    /// The C++ bridge object that handles native shader operations.
    ///
    /// This bridge provides dispose tracking for the shader.
    /// Subclasses (Gradient, ImageShader, FragmentShader) will hold additional
    /// C++ objects for their specific shader implementations.
    internal let bridge: flutter.swift_bridge.ShaderBridge

    /// Creates a base Shader.
    ///
    /// Note: This initializer creates a new ShaderBridge. Subclasses should
    /// call this initializer and may also create additional bridge objects
    /// for their specific shader implementations.
    internal init() {
        self.bridge = flutter.swift_bridge.ShaderBridge()
    }

    /// Whether `dispose()` has been called.
    ///
    /// **Dart Source:** `painting.dart:4619-4629`
    /// **Original:** `bool get debugDisposed`
    ///
    /// This must only be used when asserts are enabled. Otherwise, it will throw.
    ///
    /// DIFFERENCE FROM DART: In Dart, this property throws in release mode.
    /// In Swift, it always returns the value since we don't have the same
    /// debug/release assert pattern.
    /// REASON: Swift's assert() works differently than Dart's.
    public var debugDisposed: Bool {
        return bridge.DebugDisposed()
    }

    /// Release the resources used by this object. The object is no longer usable
    /// after this method is called.
    ///
    /// **Dart Source:** `painting.dart:4631-4646`
    /// **Original:** `void dispose()`
    ///
    /// The underlying memory allocated by this object will be retained beyond
    /// this call if it is still needed by another object that has not been
    /// disposed. For example, a `Picture` that has not been disposed that
    /// refers to an `ImageShader` may keep its underlying resources alive.
    ///
    /// Classes that override this method must call `super.dispose()`.
    ///
    /// DIFFERENCE FROM DART: Dart's dispose() uses assert() to check for
    /// double-dispose in debug mode only. Swift's implementation always
    /// sets the disposed flag.
    /// REASON: Swift ARC handles memory management differently.
    public func dispose() {
        bridge.Dispose()
    }
}

// MARK: - Gradient

/// A shader (as used by `Paint.shader`) that renders a color gradient.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:4808-5113`
/// **Original Name:** `Gradient`
///
/// There are several types of gradients, represented by the various
/// static factory methods on this class:
/// - `Gradient.linear`: Creates a linear gradient from one point to another.
/// - `Gradient.radial`: Creates a radial gradient centered at a point.
/// - `Gradient.sweep`: Creates a sweep (angular) gradient around a center point.
///
/// DIFFERENCE FROM DART: In Dart, Gradient extends Shader and uses @Native methods.
/// In Swift, we use a separate GradientBridge for the gradient-specific functionality
/// while still inheriting from Shader.
/// REASON: Swift's C++ interop requires explicit bridge classes.
public class Gradient: Shader {
    /// The C++ bridge object that handles gradient-specific operations.
    internal let gradientBridge: flutter.swift_bridge.GradientBridge

    // MARK: - Linear Gradient

    /// Creates a linear gradient from `from` to `to`.
    ///
    /// **Dart Source:** `painting.dart:4844-4863`
    /// **Original:** `Gradient.linear(...)`
    ///
    /// If `colorStops` is provided, `colorStops[i]` is a number from 0.0 to 1.0
    /// that specifies where `colors[i]` begins in the gradient. If `colorStops` is
    /// not provided, then only two stops, at 0.0 and 1.0, are implied (and
    /// `colors` must therefore only have two entries).
    ///
    /// The behavior before `from` and after `to` is described by the `tileMode`
    /// argument. For details, see the `TileMode` enum.
    ///
    /// If `matrix4` is provided, the gradient fill will be transformed by the
    /// specified 4x4 matrix relative to the local coordinate system. `matrix4` must
    /// be a column-major matrix packed into a list of 16 values.
    ///
    /// - Parameters:
    ///   - from: The start point of the gradient.
    ///   - to: The end point of the gradient.
    ///   - colors: The colors the gradient should obtain at each of the stops.
    ///   - colorStops: A list of values from 0.0 to 1.0 that denote fractions along the gradient.
    ///   - tileMode: How this gradient should tile the plane beyond the region before `from` and after `to`.
    ///   - matrix4: Optional 4x4 transformation matrix (16 values, column-major).
    public init(
        linear from: Offset,
        to: Offset,
        colors: [Color],
        colorStops: [Double]? = nil,
        tileMode: TileMode = .clamp,
        matrix4: [Double]? = nil
    ) {
        assert(!from.dx.isNaN && !from.dy.isNaN, "Offset argument contained a NaN value.")
        assert(!to.dx.isNaN && !to.dy.isNaN, "Offset argument contained a NaN value.")
        assert(matrix4 == nil || (matrix4!.count == 16 && matrix4!.allSatisfy { $0.isFinite }),
               "Matrix4 must have 16 finite entries.")

        Self.validateColorStops(colors: colors, colorStops: colorStops)

        // Create the bridge first and capture in local variable to avoid capturing self
        let bridge = flutter.swift_bridge.GradientBridge()
        self.gradientBridge = bridge

        // Encode colors as wide color (ARGB floats in extendedSRGB)
        let colorsBuffer = Self.encodeWideColorList(colors)

        // Encode color stops as Float32
        let stopsBuffer: [Float]? = colorStops?.map { Float($0) }

        // Call the C++ bridge (using local variable to avoid capturing self)
        colorsBuffer.withUnsafeBufferPointer { colorsPtr in
            if let stopsBuffer = stopsBuffer {
                stopsBuffer.withUnsafeBufferPointer { stopsPtr in
                    if let matrix4 = matrix4 {
                        matrix4.withUnsafeBufferPointer { matrixPtr in
                            bridge.InitLinear(
                                from.dx, from.dy,
                                to.dx, to.dy,
                                colorsPtr.baseAddress,
                                Int32(colors.count),
                                stopsPtr.baseAddress,
                                Int32(stopsBuffer.count),
                                Int32(tileMode.rawValue),
                                matrixPtr.baseAddress
                            )
                        }
                    } else {
                        bridge.InitLinear(
                            from.dx, from.dy,
                            to.dx, to.dy,
                            colorsPtr.baseAddress,
                            Int32(colors.count),
                            stopsPtr.baseAddress,
                            Int32(stopsBuffer.count),
                            Int32(tileMode.rawValue),
                            nil
                        )
                    }
                }
            } else {
                if let matrix4 = matrix4 {
                    matrix4.withUnsafeBufferPointer { matrixPtr in
                        bridge.InitLinear(
                            from.dx, from.dy,
                            to.dx, to.dy,
                            colorsPtr.baseAddress,
                            Int32(colors.count),
                            nil,
                            0,
                            Int32(tileMode.rawValue),
                            matrixPtr.baseAddress
                        )
                    }
                } else {
                    bridge.InitLinear(
                        from.dx, from.dy,
                        to.dx, to.dy,
                        colorsPtr.baseAddress,
                        Int32(colors.count),
                        nil,
                        0,
                        Int32(tileMode.rawValue),
                        nil
                    )
                }
            }
        }

        super.init()
    }

    // MARK: - Radial Gradient

    /// Creates a radial gradient centered at `center` that ends at `radius` distance from the center.
    ///
    /// **Dart Source:** `painting.dart:4899-4948`
    /// **Original:** `Gradient.radial(...)`
    ///
    /// If `colorStops` is provided, `colorStops[i]` is a number from 0.0 to 1.0
    /// that specifies where `colors[i]` begins in the gradient. If `colorStops` is
    /// not provided, then only two stops, at 0.0 and 1.0, are implied (and
    /// `colors` must therefore only have two entries).
    ///
    /// The behavior before and after the radius is described by the `tileMode` argument.
    ///
    /// If `focal` is provided and not equal to `center` and `focalRadius` is
    /// provided and not equal to 0.0, the generated shader will be a two point
    /// conical radial gradient, with `focal` being the center of the focal
    /// circle and `focalRadius` being the radius of that circle.
    ///
    /// - Parameters:
    ///   - center: The center of the gradient.
    ///   - radius: The radius of the gradient.
    ///   - colors: The colors the gradient should obtain at each of the stops.
    ///   - colorStops: A list of values from 0.0 to 1.0 that denote fractions along the gradient.
    ///   - tileMode: How this gradient should tile the plane beyond the region defined by the radius.
    ///   - matrix4: Optional 4x4 transformation matrix.
    ///   - focal: The focal point for a two-point conical gradient.
    ///   - focalRadius: The radius at the focal point.
    public init(
        radial center: Offset,
        radius: Double,
        colors: [Color],
        colorStops: [Double]? = nil,
        tileMode: TileMode = .clamp,
        matrix4: [Double]? = nil,
        focal: Offset? = nil,
        focalRadius: Double = 0.0
    ) {
        assert(!center.dx.isNaN && !center.dy.isNaN, "Offset argument contained a NaN value.")
        assert(matrix4 == nil || (matrix4!.count == 16 && matrix4!.allSatisfy { $0.isFinite }),
               "Matrix4 must have 16 finite entries.")

        Self.validateColorStops(colors: colors, colorStops: colorStops)

        // Create the bridge first and capture in local variable to avoid capturing self
        let bridge = flutter.swift_bridge.GradientBridge()
        self.gradientBridge = bridge

        let colorsBuffer = Self.encodeWideColorList(colors)
        let stopsBuffer: [Float]? = colorStops?.map { Float($0) }

        // If focal is nil or focal radius is nil, this should be treated as a regular radial gradient
        // If focal == center and the focal radius is 0.0, it's still a regular radial gradient
        if focal == nil || (focal == center && focalRadius == 0.0) {
            colorsBuffer.withUnsafeBufferPointer { colorsPtr in
                if let stopsBuffer = stopsBuffer {
                    stopsBuffer.withUnsafeBufferPointer { stopsPtr in
                        if let matrix4 = matrix4 {
                            matrix4.withUnsafeBufferPointer { matrixPtr in
                                bridge.InitRadial(
                                    center.dx, center.dy, radius,
                                    colorsPtr.baseAddress,
                                    Int32(colors.count),
                                    stopsPtr.baseAddress,
                                    Int32(stopsBuffer.count),
                                    Int32(tileMode.rawValue),
                                    matrixPtr.baseAddress
                                )
                            }
                        } else {
                            bridge.InitRadial(
                                center.dx, center.dy, radius,
                                colorsPtr.baseAddress,
                                Int32(colors.count),
                                stopsPtr.baseAddress,
                                Int32(stopsBuffer.count),
                                Int32(tileMode.rawValue),
                                nil
                            )
                        }
                    }
                } else {
                    if let matrix4 = matrix4 {
                        matrix4.withUnsafeBufferPointer { matrixPtr in
                            bridge.InitRadial(
                                center.dx, center.dy, radius,
                                colorsPtr.baseAddress,
                                Int32(colors.count),
                                nil, 0,
                                Int32(tileMode.rawValue),
                                matrixPtr.baseAddress
                            )
                        }
                    } else {
                        bridge.InitRadial(
                            center.dx, center.dy, radius,
                            colorsPtr.baseAddress,
                            Int32(colors.count),
                            nil, 0,
                            Int32(tileMode.rawValue),
                            nil
                        )
                    }
                }
            }
        } else {
            // Two-point conical gradient
            let focalPoint = focal!
            assert(center != Offset.zero || focalPoint != Offset.zero,
                   "At least one of center or focal must not be Offset.zero")

            colorsBuffer.withUnsafeBufferPointer { colorsPtr in
                if let stopsBuffer = stopsBuffer {
                    stopsBuffer.withUnsafeBufferPointer { stopsPtr in
                        if let matrix4 = matrix4 {
                            matrix4.withUnsafeBufferPointer { matrixPtr in
                                bridge.InitConical(
                                    focalPoint.dx, focalPoint.dy, focalRadius,
                                    center.dx, center.dy, radius,
                                    colorsPtr.baseAddress,
                                    Int32(colors.count),
                                    stopsPtr.baseAddress,
                                    Int32(stopsBuffer.count),
                                    Int32(tileMode.rawValue),
                                    matrixPtr.baseAddress
                                )
                            }
                        } else {
                            bridge.InitConical(
                                focalPoint.dx, focalPoint.dy, focalRadius,
                                center.dx, center.dy, radius,
                                colorsPtr.baseAddress,
                                Int32(colors.count),
                                stopsPtr.baseAddress,
                                Int32(stopsBuffer.count),
                                Int32(tileMode.rawValue),
                                nil
                            )
                        }
                    }
                } else {
                    if let matrix4 = matrix4 {
                        matrix4.withUnsafeBufferPointer { matrixPtr in
                            bridge.InitConical(
                                focalPoint.dx, focalPoint.dy, focalRadius,
                                center.dx, center.dy, radius,
                                colorsPtr.baseAddress,
                                Int32(colors.count),
                                nil, 0,
                                Int32(tileMode.rawValue),
                                matrixPtr.baseAddress
                            )
                        }
                    } else {
                        bridge.InitConical(
                            focalPoint.dx, focalPoint.dy, focalRadius,
                            center.dx, center.dy, radius,
                            colorsPtr.baseAddress,
                            Int32(colors.count),
                            nil, 0,
                            Int32(tileMode.rawValue),
                            nil
                        )
                    }
                }
            }
        }

        super.init()
    }

    // MARK: - Sweep Gradient

    /// Creates a sweep gradient centered at `center` that starts at `startAngle` and ends at `endAngle`.
    ///
    /// **Dart Source:** `painting.dart:5003-5031`
    /// **Original:** `Gradient.sweep(...)`
    ///
    /// `startAngle` and `endAngle` should be provided in radians, with zero
    /// radians being the horizontal line to the right of the `center` and with
    /// positive angles going clockwise around the `center`.
    ///
    /// If `colorStops` is provided, `colorStops[i]` is a number from 0.0 to 1.0
    /// that specifies where `colors[i]` begins in the gradient.
    ///
    /// - Parameters:
    ///   - center: The center of the gradient.
    ///   - colors: The colors the gradient should obtain at each of the stops.
    ///   - colorStops: A list of values from 0.0 to 1.0 that denote fractions along the gradient.
    ///   - tileMode: How this gradient should tile the plane beyond the angular sector.
    ///   - startAngle: The angle in radians at which stop 0.0 of the gradient is placed.
    ///   - endAngle: The angle in radians at which stop 1.0 of the gradient is placed.
    ///   - matrix4: Optional 4x4 transformation matrix.
    public init(
        sweep center: Offset,
        colors: [Color],
        colorStops: [Double]? = nil,
        tileMode: TileMode = .clamp,
        startAngle: Double = 0.0,
        endAngle: Double = .pi * 2,
        matrix4: [Double]? = nil
    ) {
        assert(!center.dx.isNaN && !center.dy.isNaN, "Offset argument contained a NaN value.")
        assert(startAngle < endAngle, "startAngle must be less than endAngle")
        assert(matrix4 == nil || (matrix4!.count == 16 && matrix4!.allSatisfy { $0.isFinite }),
               "Matrix4 must have 16 finite entries.")

        Self.validateColorStops(colors: colors, colorStops: colorStops)

        // Create the bridge first and capture in local variable to avoid capturing self
        let bridge = flutter.swift_bridge.GradientBridge()
        self.gradientBridge = bridge

        let colorsBuffer = Self.encodeWideColorList(colors)
        let stopsBuffer: [Float]? = colorStops?.map { Float($0) }

        colorsBuffer.withUnsafeBufferPointer { colorsPtr in
            if let stopsBuffer = stopsBuffer {
                stopsBuffer.withUnsafeBufferPointer { stopsPtr in
                    if let matrix4 = matrix4 {
                        matrix4.withUnsafeBufferPointer { matrixPtr in
                            bridge.InitSweep(
                                center.dx, center.dy,
                                colorsPtr.baseAddress,
                                Int32(colors.count),
                                stopsPtr.baseAddress,
                                Int32(stopsBuffer.count),
                                Int32(tileMode.rawValue),
                                startAngle, endAngle,
                                matrixPtr.baseAddress
                            )
                        }
                    } else {
                        bridge.InitSweep(
                            center.dx, center.dy,
                            colorsPtr.baseAddress,
                            Int32(colors.count),
                            stopsPtr.baseAddress,
                            Int32(stopsBuffer.count),
                            Int32(tileMode.rawValue),
                            startAngle, endAngle,
                            nil
                        )
                    }
                }
            } else {
                if let matrix4 = matrix4 {
                    matrix4.withUnsafeBufferPointer { matrixPtr in
                        bridge.InitSweep(
                            center.dx, center.dy,
                            colorsPtr.baseAddress,
                            Int32(colors.count),
                            nil, 0,
                            Int32(tileMode.rawValue),
                            startAngle, endAngle,
                            matrixPtr.baseAddress
                        )
                    }
                } else {
                    bridge.InitSweep(
                        center.dx, center.dy,
                        colorsPtr.baseAddress,
                        Int32(colors.count),
                        nil, 0,
                        Int32(tileMode.rawValue),
                        startAngle, endAngle,
                        nil
                    )
                }
            }
        }

        super.init()
    }

    // MARK: - Dispose

    /// Release the resources used by this gradient.
    ///
    /// **Dart Source:** `painting.dart:4631-4646`
    ///
    /// The object is no longer usable after this method is called.
    public override func dispose() {
        gradientBridge.Dispose()
        super.dispose()
    }

    /// Whether `dispose()` has been called.
    ///
    /// **Dart Source:** `painting.dart:4619-4629`
    public override var debugDisposed: Bool {
        return gradientBridge.DebugDisposed()
    }

    // MARK: - Private Helpers

    /// Validates that colors and colorStops have compatible lengths.
    ///
    /// **Dart Source:** `painting.dart:5102-5112`
    /// **Original:** `static void _validateColorStops(List<Color> colors, List<double>? colorStops)`
    private static func validateColorStops(colors: [Color], colorStops: [Double]?) {
        if colorStops == nil {
            if colors.count != 2 {
                fatalError("\"colors\" must have length 2 if \"colorStops\" is omitted.")
            }
        } else {
            if colors.count != colorStops!.count {
                fatalError("\"colors\" and \"colorStops\" arguments must have equal length.")
            }
        }
    }

    /// Encodes a list of colors as wide color floats (ARGB in extendedSRGB colorspace).
    ///
    /// **Dart Source:** `painting.dart:4761-4772`
    /// **Original:** `Float32List _encodeWideColorList(List<Color> colors)`
    ///
    /// Each color is converted to extendedSRGB color space and stored as 4 floats (A, R, G, B).
    private static func encodeWideColorList(_ colors: [Color]) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(colors.count * 4)
        for color in colors {
            let colorXr = color.withValues(colorSpace: .extendedSRGB)
            result.append(Float(colorXr.a))
            result.append(Float(colorXr.r))
            result.append(Float(colorXr.g))
            result.append(Float(colorXr.b))
        }
        return result
    }
}

// MARK: - FragmentProgram

/// An instance of `FragmentProgram` creates `Shader` objects (as used by
/// `Paint.shader`).
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:5187-5268`
/// **Original Name:** `FragmentProgram`
/// **Lines:** 5187-5268
///
/// For more information, see the website
/// [documentation](https://docs.flutter.dev/development/ui/advanced/shaders).
///
/// DIFFERENCE FROM DART: Uses SWIFT_SHARED_REFERENCE via FragmentProgramBridge
/// instead of NativeFieldWrapperClass1.
/// REASON: Swift has no equivalent to Dart's NativeFieldWrapperClass1; uses
/// C++ bridge with SWIFT_SHARED_REFERENCE for automatic memory management.
public class FragmentProgram {
  /// The C++ bridge object that handles native fragment program operations.
  ///
  /// Swift ARC manages lifetime via SWIFT_SHARED_REFERENCE.
  internal let bridge: flutter.swift_bridge.FragmentProgramBridge

  /// Debug name for error messages.
  ///
  /// **Dart Source:** `painting.dart:5206`
  /// **Original:** `String? _debugName;`
  private var _debugName: String?

  /// The number of float uniforms expected by the shader.
  ///
  /// **Dart Source:** `painting.dart:5254-5255`
  /// **Original:** `late int _uniformFloatCount;`
  public private(set) var uniformFloatCount: Int

  /// The number of sampler uniforms (image samplers) expected.
  ///
  /// **Dart Source:** `painting.dart:5257-5258`
  /// **Original:** `late int _samplerCount;`
  public private(set) var samplerCount: Int

  /// Runtime stage backend enum.
  ///
  /// DIFFERENCE FROM DART: Exposed as a Swift enum wrapping the C++ bridge Backend enum.
  /// REASON: The Dart version uses UIDartState to determine the backend at runtime.
  /// The Swift layer needs the caller to specify the backend since we don't have
  /// access to UIDartState (Dart VM infrastructure).
  public enum Backend: Int32 {
    case skSL = 0
    case metal = 1
    case openGLES = 2
    case vulkan = 3
    case openGLES3 = 4

    /// Converts to the C++ bridge Backend enum value.
    internal var cppBackend: flutter.swift_bridge.FragmentProgramBridge.Backend {
      return flutter.swift_bridge.FragmentProgramBridge.Backend(rawValue: self.rawValue)!
    }
  }

  // Cache of shaders that have been loaded by FragmentProgram.fromAsset.
  // Holds a strong reference to the FragmentPrograms.
  // The native engine will retain the resources associated with this shader
  // program (PSO variants) until shutdown, so maintaining a strong reference
  // here ensures we do not perform extra work if the object is continually
  // re-initialized.
  //
  // **Dart Source:** `painting.dart:5231-5237`
  // **Original:** `static final Map<String, FragmentProgram> _shaderRegistry`
  //
  // DIFFERENCE FROM DART: Uses nonisolated(unsafe) for Swift 6 concurrency.
  // REASON: Swift 6 strict concurrency requires explicit annotation for
  // mutable global state. Access is expected to be from the main thread.
  nonisolated(unsafe) private static var _shaderRegistry: [String: FragmentProgram] = [:]

  /// Creates a FragmentProgram by initializing from raw shader data.
  ///
  /// **Dart Source:** `painting.dart:5193-5204`
  /// **Original:** `FragmentProgram._fromAsset(String assetKey)`
  ///
  /// DIFFERENCE FROM DART: Takes raw data and backend instead of asset key.
  /// REASON: The Dart version uses UIDartState to load asset data and determine backend.
  /// The Swift bridge layer takes raw data to avoid depending on Dart VM infrastructure.
  /// The caller (Swift framework) is responsible for loading asset data.
  ///
  /// DIFFERENCE FROM DART: Constructor throws instead of using Dart exceptions.
  /// REASON: Swift uses throwing initializers for failable construction.
  public init(
    data: [UInt8],
    backend: Backend,
    debugName: String? = nil
  ) throws {
    let bridge = flutter.swift_bridge.FragmentProgramBridge()
    self.bridge = bridge

    let errorMsg: String? = data.withUnsafeBufferPointer { dataPtr in
      let result = bridge.InitFromData(
        dataPtr.baseAddress,
        dataPtr.count,
        backend.cppBackend
      )
      if let result = result {
        let msg = String(cString: result)
        free(UnsafeMutableRawPointer(mutating: result))
        return msg
      }
      return nil
    }

    if let errorMsg = errorMsg {
      self.uniformFloatCount = 0
      self.samplerCount = 0
      throw FlutterSwiftBridgeError.invalidArgument(errorMsg)
    }
    self.uniformFloatCount = Int(bridge.GetUniformFloatCount())
    self.samplerCount = Int(bridge.GetSamplerCount())
    assert({
      self._debugName = debugName
      return true
    }())
  }

  /// Creates a fragment program from the asset with key `assetKey`.
  ///
  /// **Dart Source:** `painting.dart:5208-5229`
  /// **Original:** `static Future<FragmentProgram> fromAsset(String assetKey)`
  ///
  /// The asset must be a file produced as the output of the shader
  /// compiler. The constructed object should then be reused via the
  /// `fragmentShader()` method to create `Shader` objects that can be used by
  /// `Paint.shader`.
  ///
  /// DIFFERENCE FROM DART: Takes additional `data` and `backend`
  /// parameters. Returns synchronously instead of Future<FragmentProgram>.
  /// REASON: The Dart version loads asset data via UIDartState::Current() which
  /// accesses the AssetManager. The Swift bridge doesn't have access to UIDartState,
  /// so the caller must provide the raw shader data and backend information.
  /// The Dart Future was wrapping synchronous work in a microtask; the Swift
  /// version is directly synchronous with caching.
  public static func fromAsset(
    _ assetKey: String,
    data: [UInt8],
    backend: Backend
  ) throws -> FragmentProgram {
    // The flutter tool converts all asset keys with spaces into URI
    // encoded paths (replacing ' ' with '%20', for example). We perform
    // the same encoding here so that users can load assets with the same
    // key they have written in the pubspec.
    //
    // **Dart Source:** `painting.dart:5219`
    let encodedKey = assetKey.addingPercentEncoding(
      withAllowedCharacters: .urlPathAllowed
    ) ?? assetKey

    if let program = _shaderRegistry[encodedKey] {
      return program
    }

    let program = try FragmentProgram(
      data: data,
      backend: backend,
      debugName: encodedKey
    )
    _shaderRegistry[encodedKey] = program
    return program
  }

  /// Reinitializes a shader that has already been loaded.
  ///
  /// **Dart Source:** `painting.dart:5239-5252`
  /// **Original:** `static void _reinitializeShader(String assetKey)`
  ///
  /// If a shader for the asset isn't already registered, then there's no
  /// need to reinitialize it. The new shader will be loaded and initialized
  /// the next time the program accesses it.
  ///
  /// DIFFERENCE FROM DART: Takes additional `data` and `backend`
  /// parameters instead of loading from asset manager.
  /// REASON: Same as fromAsset - no access to UIDartState asset manager.
  internal static func reinitializeShader(
    _ assetKey: String,
    data: [UInt8],
    backend: Backend
  ) throws {
    guard let program = _shaderRegistry[assetKey] else {
      return
    }

    let errorMsg: String? = data.withUnsafeBufferPointer { dataPtr in
      let result = program.bridge.InitFromData(
        dataPtr.baseAddress,
        dataPtr.count,
        backend.cppBackend
      )
      if let result = result {
        let msg = String(cString: result)
        free(UnsafeMutableRawPointer(mutating: result))
        return msg
      }
      return nil
    }

    if let errorMsg = errorMsg {
      throw FlutterSwiftBridgeError.invalidArgument(errorMsg)
    }
    program.uniformFloatCount = Int(program.bridge.GetUniformFloatCount())
    program.samplerCount = Int(program.bridge.GetSamplerCount())
  }

  /// Returns a fresh instance of `FragmentShader`.
  ///
  /// **Dart Source:** `painting.dart:5266-5267`
  /// **Original:** `FragmentShader fragmentShader() => FragmentShader._(this, debugName: _debugName);`
  public func fragmentShader() -> FragmentShader {
    return FragmentShader(self, debugName: _debugName)
  }
}

// MARK: - FragmentShader

/// A shader generated from a `FragmentProgram`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:5270-5388`
/// **Original Name:** `FragmentShader`
///
/// Instances of this class can be obtained from the
/// `FragmentProgram.fragmentShader()` method. The float uniforms list is
/// initialized to the size expected by the shader and is zero-filled. Uniforms
/// of float type can then be set by calling `setFloat`. Sampler uniforms are
/// set by calling `setImageSampler`.
///
/// A `FragmentShader` can be re-used, and this is an efficient way to avoid
/// allocating and re-initializing the uniform buffer and samplers. However,
/// if two `FragmentShader` objects with different float uniforms or samplers
/// are required to exist simultaneously, they must be obtained from two
/// different calls to `FragmentProgram.fragmentShader()`.
///
/// DIFFERENCE FROM DART: In Dart, the constructor returns a Float32List backed by
/// external typed data pointing into the C++ SkData buffer. In Swift, we use
/// SetFloat/GetFloat methods on the bridge instead, since Swift cannot create
/// an external typed data view into C++ memory in the same way. The float data
/// is still stored in the C++ bridge's uniform buffer.
/// REASON: Swift's C++ interop does not support external typed data views.
public class FragmentShader: Shader {
  /// The C++ bridge object that handles fragment shader operations.
  ///
  /// This bridge holds the uniform float data buffer and image samplers,
  /// mirroring the ReusableFragmentShader C++ class.
  internal let fragmentShaderBridge: flutter.swift_bridge.FragmentShaderBridge

  /// The fragment program that created this shader.
  ///
  /// **Dart Source:** `painting.dart:5278`
  /// **Original:** implicit reference via `_constructor(program, ...)`
  internal let program: FragmentProgram

  /// Debug name for error messages.
  ///
  /// **Dart Source:** `painting.dart:5290`
  /// **Original:** `final String? _debugName;`
  public private(set) var debugName: String?

  /// Creates a FragmentShader from a FragmentProgram.
  ///
  /// **Dart Source:** `painting.dart:5284-5288`
  /// **Original:** `FragmentShader._(FragmentProgram program, {String? debugName})`
  ///
  /// The constructor initializes the C++ bridge with the program's uniform
  /// float count and sampler count. The uniform data buffer is zero-filled.
  ///
  /// DIFFERENCE FROM DART: In Dart, the constructor calls `_constructor` which
  /// returns a Float32List backed by external typed data. In Swift, the bridge
  /// manages the float data internally, accessed via SetFloat/GetFloat.
  /// REASON: Swift cannot create external typed data views into C++ memory.
  internal init(_ program: FragmentProgram, debugName: String? = nil) {
    self.program = program
    self.debugName = debugName
    self.fragmentShaderBridge = flutter.swift_bridge.FragmentShaderBridge(
      program.bridge,
      Int32(program.uniformFloatCount),
      Int32(program.samplerCount)
    )
    super.init()
  }

  /// Sets the float uniform at `index` to `value`.
  ///
  /// **Dart Source:** `painting.dart:5295-5341`
  /// **Original:** `void setFloat(int index, double value)`
  ///
  /// All uniforms defined in a fragment shader that are not samplers must be
  /// set through this method. This includes floats and vec2, vec3, and vec4.
  /// The correct index for each uniform is determined by the order of the
  /// uniforms as defined in the fragment program, ignoring any samplers. For
  /// data types that are composed of multiple floats such as a vec4, more than
  /// one call to `setFloat` is required.
  ///
  /// For example, given the following uniforms in a fragment program:
  ///
  /// ```glsl
  /// uniform float uScale;
  /// uniform sampler2D uTexture;
  /// uniform vec2 uMagnitude;
  /// uniform vec4 uColor;
  /// ```
  ///
  /// Then the corresponding Swift code to correctly initialize these uniforms
  /// is:
  ///
  /// ```swift
  /// func updateShader(_ shader: FragmentShader, color: Color, image: Image) {
  ///   shader.setFloat(0, 23)   // uScale
  ///   shader.setFloat(1, 114)  // uMagnitude x
  ///   shader.setFloat(2, 83)   // uMagnitude y
  ///
  ///   // Convert color to premultiplied opacity.
  ///   shader.setFloat(3, Double(color.red) / 255.0 * color.opacity)   // uColor r
  ///   shader.setFloat(4, Double(color.green) / 255.0 * color.opacity) // uColor g
  ///   shader.setFloat(5, Double(color.blue) / 255.0 * color.opacity)  // uColor b
  ///   shader.setFloat(6, color.opacity)                                // uColor a
  ///
  ///   // initialize sampler uniform.
  ///   shader.setImageSampler(0, image)
  /// }
  /// ```
  ///
  /// Note how the indexes used does not count the `sampler2D` uniform. This
  /// uniform will be set separately with `setImageSampler`, with the index starting
  /// over at 0.
  ///
  /// Any float uniforms that are left uninitialized will default to `0`.
  public func setFloat(_ index: Int, _ value: Double) {
    assert(!debugDisposed, "Tried to access uniforms on a disposed Shader: \(self)")
    fragmentShaderBridge.SetFloat(Int32(index), Float(value))
  }

  /// Sets the sampler uniform at `index` to `image`.
  ///
  /// **Dart Source:** `painting.dart:5343-5354`
  /// **Original:** `void setImageSampler(int index, Image image)`
  ///
  /// The index provided to setImageSampler is the index of the sampler uniform
  /// defined in the fragment program, excluding all non-sampler uniforms.
  ///
  /// All the sampler uniforms that a shader expects must be provided or the
  /// results will be undefined.
  public func setImageSampler(_ index: Int, _ image: Image) {
    assert(!debugDisposed, "Tried to access uniforms on a disposed Shader: \(self)")
    assert(!image.debugDisposed, "Image has been disposed")
    let success = fragmentShaderBridge.SetImageSampler(
      Int32(index), image.bridge
    )
    assert(success, "Failed to set image sampler at index \(index)")
  }

  /// Releases the native resources held by the `FragmentShader`.
  ///
  /// **Dart Source:** `painting.dart:5356-5366`
  /// **Original:** `void dispose()`
  ///
  /// After this method is called, calling methods on the shader, or attaching
  /// it to a `Paint` object will fail with an exception. Calling `dispose`
  /// twice will also result in an exception being thrown.
  public override func dispose() {
    super.dispose()
    fragmentShaderBridge.Dispose()
  }

  /// Validates that all samplers have been set.
  ///
  /// **Dart Source:** `painting.dart:5380-5381`
  /// **Original:** `bool _validateSamplers()`
  ///
  /// Returns true if all sampler uniforms have been set to non-null images.
  public func validateSamplers() -> Bool {
    return fragmentShaderBridge.ValidateSamplers()
  }

  /// Validates this shader can be used as an image filter.
  ///
  /// **Dart Source:** `painting.dart:5383-5384`
  /// **Original:** `bool _validateImageFilter()`
  ///
  /// Image filters require at least one sampler. The first sampler does not
  /// need to be set (it binds the input texture), but all remaining samplers
  /// must be set.
  public func validateImageFilter() -> Bool {
    return fragmentShaderBridge.ValidateImageFilter()
  }
}

// MARK: - Paint

/// A description of the style to use when drawing on a `Canvas`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1267-1768`
/// **Original Name:** `Paint`
///
/// Most APIs on `Canvas` take a `Paint` object to describe the style
/// to use for that operation.
///
/// DIFFERENCE FROM DART: Paint uses a Data buffer instead of ByteData for
/// native interop, and stores objects in an array instead of a list.
/// REASON: Swift uses Data for binary data manipulation.
public final class Paint: CustomStringConvertible {
    // MARK: - Binary Data Layout

    // Paint objects are encoded in two buffers:
    //
    // * _data is binary data in four-byte fields, each of which is either a
    //   UInt32 or a Float32. The default value for each field is encoded as
    //   zero to make initialization trivial. Most values already have a default
    //   value of zero, but some, such as color, have a non-zero default value.
    //   To encode or decode these values, XOR the value with the default value.
    //
    // * _objects is a list of unencodable objects, typically wrappers for native
    //   objects. The objects are simply stored in the list without any additional
    //   encoding.
    //
    // The binary format must match the deserialization code in paint.cc.

    /// The binary data buffer for paint properties.
    ///
    /// **Dart Source:** `painting.dart:1307-1308`
    /// **Original:** `final ByteData _data = ByteData(_kDataByteCount);`
    private var data: Data

    // MARK: - Data Layout Constants

    // Must match //lib/ui/painting/paint.cc.
    private static let kIsAntiAliasIndex: Int = 0
    private static let kColorRedIndex: Int = 1
    private static let kColorGreenIndex: Int = 2
    private static let kColorBlueIndex: Int = 3
    private static let kColorAlphaIndex: Int = 4
    private static let kColorSpaceIndex: Int = 5
    private static let kBlendModeIndex: Int = 6
    private static let kStyleIndex: Int = 7
    private static let kStrokeWidthIndex: Int = 8
    private static let kStrokeCapIndex: Int = 9
    private static let kStrokeJoinIndex: Int = 10
    private static let kStrokeMiterLimitIndex: Int = 11
    private static let kFilterQualityIndex: Int = 12
    private static let kMaskFilterIndex: Int = 13
    private static let kMaskFilterBlurStyleIndex: Int = 14
    private static let kMaskFilterSigmaIndex: Int = 15
    private static let kInvertColorIndex: Int = 16

    private static let kIsAntiAliasOffset: Int = kIsAntiAliasIndex << 2
    private static let kColorRedOffset: Int = kColorRedIndex << 2
    private static let kColorGreenOffset: Int = kColorGreenIndex << 2
    private static let kColorBlueOffset: Int = kColorBlueIndex << 2
    private static let kColorAlphaOffset: Int = kColorAlphaIndex << 2
    private static let kColorSpaceOffset: Int = kColorSpaceIndex << 2
    private static let kBlendModeOffset: Int = kBlendModeIndex << 2
    private static let kStyleOffset: Int = kStyleIndex << 2
    private static let kStrokeWidthOffset: Int = kStrokeWidthIndex << 2
    private static let kStrokeCapOffset: Int = kStrokeCapIndex << 2
    private static let kStrokeJoinOffset: Int = kStrokeJoinIndex << 2
    private static let kStrokeMiterLimitOffset: Int = kStrokeMiterLimitIndex << 2
    private static let kFilterQualityOffset: Int = kFilterQualityIndex << 2
    private static let kMaskFilterOffset: Int = kMaskFilterIndex << 2
    private static let kMaskFilterBlurStyleOffset: Int = kMaskFilterBlurStyleIndex << 2
    private static let kMaskFilterSigmaOffset: Int = kMaskFilterSigmaIndex << 2
    private static let kInvertColorOffset: Int = kInvertColorIndex << 2

    // If you add more fields, remember to update kDataByteCount.
    /// **Dart Source:** `painting.dart:1348`
    /// **Original:** `static const int _kDataByteCount = 68;`
    private static let kDataByteCount: Int = 68  // 4 * (last index + 1)

    // MARK: - Objects Array

    /// Binary format must match the deserialization code in paint.cc.
    /// **Dart Source:** `painting.dart:1352-1353`
    /// **Original:** `List<Object?>? _objects;`
    private var objects: [AnyObject?]?

    private static let kShaderIndex: Int = 0
    private static let kColorFilterIndex: Int = 1
    private static let kImageFilterIndex: Int = 2
    private static let kObjectCount: Int = 3  // Must be one larger than the largest index

    /// Ensures the objects array is initialized.
    ///
    /// **Dart Source:** `painting.dart:1355-1357`
    /// **Original:** `List<Object?> _ensureObjectsInitialized()`
    private func ensureObjectsInitialized() -> [AnyObject?] {
        if objects == nil {
            objects = [AnyObject?](repeating: nil, count: Paint.kObjectCount)
        }
        return objects!
    }

    // MARK: - Default Values

    // Must be kept in sync with the default in paint.cc.
    /// **Dart Source:** `painting.dart:1380`
    /// **Original:** `static const int _kColorDefault = 0xFF000000;`
    private static let kColorDefault: Int = 0xFF000000

    // Must be kept in sync with the default in paint.cc.
    /// **Dart Source:** `painting.dart:1414`
    /// **Original:** `static final int _kBlendModeDefault = BlendMode.srcOver.index;`
    private static let kBlendModeDefault: Int = BlendMode.srcOver.rawValue

    // Must be kept in sync with the default in paint.cc.
    /// **Dart Source:** `painting.dart:1518`
    /// **Original:** `static const double _kStrokeMiterLimitDefault = 4.0;`
    private static let kStrokeMiterLimitDefault: Double = 4.0

    // MARK: - Initializers

    /// Constructs an empty Paint object with all fields initialized to their defaults.
    ///
    /// **Dart Source:** `painting.dart:1272-1274`
    /// **Original:** `Paint();`
    public init() {
        // Initialize data buffer with zeros (default values)
        self.data = Data(count: Paint.kDataByteCount)
    }

    /// Constructs a new Paint object with the same fields as another Paint.
    ///
    /// **Dart Source:** `painting.dart:1276-1290`
    /// **Original:** `Paint.from(Paint other)`
    ///
    /// Any changes made to the object returned will not affect `other`, and
    /// changes to `other` will not affect the object returned.
    public init(from other: Paint) {
        // Every field on Paint is deeply immutable, so to create a copy of a Paint
        // object, we copy the underlying data buffer and the list of objects (which
        // are also deeply immutable).
        self.data = Data(other.data)
        if let otherObjects = other.objects {
            self.objects = otherObjects.map { $0 }
        }
    }

    // MARK: - Data Access Helpers

    /// Gets a 32-bit signed integer from the data buffer at the given byte offset.
    private func getInt32(_ offset: Int) -> Int32 {
        return data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: Int32.self)
        }
    }

    /// Sets a 32-bit signed integer in the data buffer at the given byte offset.
    private func setInt32(_ offset: Int, _ value: Int32) {
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: value, toByteOffset: offset, as: Int32.self)
        }
    }

    /// Gets a 32-bit float from the data buffer at the given byte offset.
    private func getFloat32(_ offset: Int) -> Float {
        return data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: Float.self)
        }
    }

    /// Sets a 32-bit float in the data buffer at the given byte offset.
    private func setFloat32(_ offset: Int, _ value: Float) {
        data.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: value, toByteOffset: offset, as: Float.self)
        }
    }

    // MARK: - isAntiAlias

    /// Whether to apply anti-aliasing to lines and images drawn on the canvas.
    ///
    /// **Dart Source:** `painting.dart:1364-1377`
    /// **Original:** `bool get isAntiAlias` / `set isAntiAlias(bool value)`
    ///
    /// Defaults to true.
    public var isAntiAlias: Bool {
        get {
            return getInt32(Paint.kIsAntiAliasOffset) == 0
        }
        set {
            // We encode true as zero and false as one because the default value, which
            // we always encode as zero, is true.
            let encoded: Int32 = newValue ? 0 : 1
            setInt32(Paint.kIsAntiAliasOffset, encoded)
        }
    }

    // MARK: - color

    /// The color to use when stroking or filling a shape.
    ///
    /// **Dart Source:** `painting.dart:1382-1411`
    /// **Original:** `Color get color` / `set color(Color value)`
    ///
    /// Defaults to opaque black.
    ///
    /// See also:
    ///
    ///  * `style`, which controls whether to stroke or fill (or both).
    ///  * `colorFilter`, which overrides `color`.
    ///  * `shader`, which overrides `color` with more elaborate effects.
    ///
    /// This color is not used when compositing. To colorize a layer, use
    /// `colorFilter`.
    public var color: Color {
        get {
            let red = Double(getFloat32(Paint.kColorRedOffset))
            let green = Double(getFloat32(Paint.kColorGreenOffset))
            let blue = Double(getFloat32(Paint.kColorBlueOffset))
            let alpha = 1.0 - Double(getFloat32(Paint.kColorAlphaOffset))
            let colorSpace = indexToColorSpace(Int(getInt32(Paint.kColorSpaceOffset)))
            return Color(alpha: alpha, red: red, green: green, blue: blue, colorSpace: colorSpace)
        }
        set {
            setFloat32(Paint.kColorRedOffset, Float(newValue.r))
            setFloat32(Paint.kColorGreenOffset, Float(newValue.g))
            setFloat32(Paint.kColorBlueOffset, Float(newValue.b))
            setFloat32(Paint.kColorAlphaOffset, Float(1.0 - newValue.a))
            setInt32(Paint.kColorSpaceOffset, Int32(colorSpaceToIndex(newValue.colorSpace)))
        }
    }

    // MARK: - blendMode

    /// A blend mode to apply when a shape is drawn or a layer is composited.
    ///
    /// **Dart Source:** `painting.dart:1416-1442`
    /// **Original:** `BlendMode get blendMode` / `set blendMode(BlendMode value)`
    ///
    /// The source colors are from the shape being drawn (e.g. from
    /// `Canvas.drawPath`) or layer being composited (the graphics that were drawn
    /// between the `Canvas.saveLayer` and `Canvas.restore` calls), after applying
    /// the `colorFilter`, if any.
    ///
    /// The destination colors are from the background onto which the shape or
    /// layer is being composited.
    ///
    /// Defaults to `BlendMode.srcOver`.
    ///
    /// See also:
    ///
    ///  * `Canvas.saveLayer`, which uses its Paint's `blendMode` to composite
    ///    the layer when `Canvas.restore` is called.
    ///  * `BlendMode`, which discusses the user of `Canvas.saveLayer` with
    ///    `blendMode`.
    public var blendMode: BlendMode {
        get {
            let encoded = Int(getInt32(Paint.kBlendModeOffset))
            return BlendMode(rawValue: encoded ^ Paint.kBlendModeDefault) ?? .srcOver
        }
        set {
            let encoded = Int32(newValue.rawValue ^ Paint.kBlendModeDefault)
            setInt32(Paint.kBlendModeOffset, encoded)
        }
    }

    // MARK: - style

    /// Whether to paint inside shapes, the edges of shapes, or both.
    ///
    /// **Dart Source:** `painting.dart:1444-1454`
    /// **Original:** `PaintingStyle get style` / `set style(PaintingStyle value)`
    ///
    /// Defaults to `PaintingStyle.fill`.
    public var style: PaintingStyle {
        get {
            return PaintingStyle(rawValue: Int(getInt32(Paint.kStyleOffset))) ?? .fill
        }
        set {
            let encoded = Int32(newValue.rawValue)
            setInt32(Paint.kStyleOffset, encoded)
        }
    }

    // MARK: - strokeWidth

    /// How wide to make edges drawn when `style` is set to `PaintingStyle.stroke`.
    ///
    /// **Dart Source:** `painting.dart:1456-1468`
    /// **Original:** `double get strokeWidth` / `set strokeWidth(double value)`
    ///
    /// The width is given in logical pixels measured in the direction orthogonal
    /// to the direction of the path.
    ///
    /// Defaults to 0.0, which corresponds to a hairline width.
    public var strokeWidth: Double {
        get {
            return Double(getFloat32(Paint.kStrokeWidthOffset))
        }
        set {
            setFloat32(Paint.kStrokeWidthOffset, Float(newValue))
        }
    }

    // MARK: - strokeCap

    /// The kind of finish to place on the end of lines drawn when
    /// `style` is set to `PaintingStyle.stroke`.
    ///
    /// **Dart Source:** `painting.dart:1470-1481`
    /// **Original:** `StrokeCap get strokeCap` / `set strokeCap(StrokeCap value)`
    ///
    /// Defaults to `StrokeCap.butt`, i.e. no caps.
    public var strokeCap: StrokeCap {
        get {
            return StrokeCap(rawValue: Int(getInt32(Paint.kStrokeCapOffset))) ?? .butt
        }
        set {
            let encoded = Int32(newValue.rawValue)
            setInt32(Paint.kStrokeCapOffset, encoded)
        }
    }

    // MARK: - strokeJoin

    /// The kind of finish to place on the joins between segments.
    ///
    /// **Dart Source:** `painting.dart:1483-1515`
    /// **Original:** `StrokeJoin get strokeJoin` / `set strokeJoin(StrokeJoin value)`
    ///
    /// This applies to paths drawn when `style` is set to `PaintingStyle.stroke`,
    /// It does not apply to points drawn as lines with `Canvas.drawPoints`.
    ///
    /// Defaults to `StrokeJoin.miter`, i.e. sharp corners.
    ///
    /// See also:
    ///
    ///  * `strokeMiterLimit` to control when miters are replaced by bevels when
    ///    this is set to `StrokeJoin.miter`.
    ///  * `strokeCap` to control what is drawn at the ends of the stroke.
    ///  * `StrokeJoin` for the definitive list of stroke joins.
    public var strokeJoin: StrokeJoin {
        get {
            return StrokeJoin(rawValue: Int(getInt32(Paint.kStrokeJoinOffset))) ?? .miter
        }
        set {
            let encoded = Int32(newValue.rawValue)
            setInt32(Paint.kStrokeJoinOffset, encoded)
        }
    }

    // MARK: - strokeMiterLimit

    /// The limit for miters to be drawn on segments when the join is set to
    /// `StrokeJoin.miter` and the `style` is set to `PaintingStyle.stroke`.
    ///
    /// **Dart Source:** `painting.dart:1520-1553`
    /// **Original:** `double get strokeMiterLimit` / `set strokeMiterLimit(double value)`
    ///
    /// If this limit is exceeded, then a `StrokeJoin.bevel` join will be drawn
    /// instead. This may cause some 'popping' of the corners of a path if the
    /// angle between line segments is animated.
    ///
    /// This limit is expressed as a limit on the length of the miter.
    ///
    /// Defaults to 4.0. Using zero as a limit will cause a `StrokeJoin.bevel`
    /// join to be used all the time.
    ///
    /// See also:
    ///
    ///  * `strokeJoin` to control the kind of finish to place on the joins
    ///    between segments.
    ///  * `strokeCap` to control what is drawn at the ends of the stroke.
    public var strokeMiterLimit: Double {
        get {
            return Double(getFloat32(Paint.kStrokeMiterLimitOffset)) + Paint.kStrokeMiterLimitDefault
        }
        set {
            let encoded = Float(newValue - Paint.kStrokeMiterLimitDefault)
            setFloat32(Paint.kStrokeMiterLimitOffset, encoded)
        }
    }

    // MARK: - maskFilter

    /// A mask filter (for example, a blur) to apply to a shape after it has been
    /// drawn but before it has been composited into the image.
    ///
    /// **Dart Source:** `painting.dart:1555-1584`
    /// **Original:** `MaskFilter? get maskFilter` / `set maskFilter(MaskFilter? value)`
    ///
    /// See `MaskFilter` for details.
    public var maskFilter: MaskFilter? {
        get {
            switch Int(getInt32(Paint.kMaskFilterOffset)) {
            case MaskFilter.typeNone:
                return nil
            case MaskFilter.typeBlur:
                guard let blurStyle = BlurStyle(rawValue: Int(getInt32(Paint.kMaskFilterBlurStyleOffset))) else {
                    return nil
                }
                return MaskFilter(blur: blurStyle, Double(getFloat32(Paint.kMaskFilterSigmaOffset)))
            default:
                return nil
            }
        }
        set {
            if let value = newValue {
                // For now we only support one kind of MaskFilter, so we don't need to
                // check what the type is if it's not null.
                setInt32(Paint.kMaskFilterOffset, Int32(MaskFilter.typeBlur))
                setInt32(Paint.kMaskFilterBlurStyleOffset, Int32(value.blurStyle.rawValue))
                setFloat32(Paint.kMaskFilterSigmaOffset, Float(value.blurSigma))
            } else {
                setInt32(Paint.kMaskFilterOffset, Int32(MaskFilter.typeNone))
                setInt32(Paint.kMaskFilterBlurStyleOffset, 0)
                setFloat32(Paint.kMaskFilterSigmaOffset, 0.0)
            }
        }
    }

    // MARK: - filterQuality

    /// Controls the performance vs quality trade-off to use when sampling bitmaps.
    ///
    /// **Dart Source:** `painting.dart:1586-1599`
    /// **Original:** `FilterQuality get filterQuality` / `set filterQuality(FilterQuality value)`
    ///
    /// Controls quality when used with an `ImageShader`, or when drawing images
    /// with `Canvas.drawImage`, `Canvas.drawImageRect`, `Canvas.drawImageNine`
    /// or `Canvas.drawAtlas`.
    ///
    /// Defaults to `FilterQuality.none`.
    public var filterQuality: FilterQuality {
        get {
            return FilterQuality(rawValue: Int(getInt32(Paint.kFilterQualityOffset))) ?? .none
        }
        set {
            let encoded = Int32(newValue.rawValue)
            setInt32(Paint.kFilterQualityOffset, encoded)
        }
    }

    // MARK: - shader

    /// The shader to use when stroking or filling a shape.
    ///
    /// **Dart Source:** `painting.dart:1601-1629`
    /// **Original:** `Shader? get shader` / `set shader(Shader? value)`
    ///
    /// When this is nil, the `color` is used instead.
    ///
    /// See also:
    ///
    ///  * `Gradient`, a shader that paints a color gradient.
    ///  * `ImageShader`, a shader that tiles an Image.
    ///  * `colorFilter`, which overrides `shader`.
    ///  * `color`, which is used if `shader` and `colorFilter` are nil.
    public var shader: Shader? {
        get {
            return objects?[Paint.kShaderIndex] as? Shader
        }
        set {
            assert(newValue == nil || !newValue!.debugDisposed, "Attempted to set a disposed shader to \(self)")
            if let fragmentShader = newValue as? FragmentShader {
                assert(fragmentShader.validateSamplers(), "Invalid FragmentShader \(fragmentShader.debugName ?? ""): missing sampler")
            }
            _ = ensureObjectsInitialized()
            objects![Paint.kShaderIndex] = newValue
        }
    }

    // MARK: - colorFilter

    /// A color filter to apply when a shape is drawn or when a layer is composited.
    ///
    /// **Dart Source:** `painting.dart:1631-1651`
    /// **Original:** `ColorFilter? get colorFilter` / `set colorFilter(ColorFilter? value)`
    ///
    /// See `ColorFilter` for details.
    ///
    /// When a shape is being drawn, `colorFilter` overrides `color` and `shader`.
    ///
    /// Stored as the `_NativeColorFilter` wrapper, exactly as Dart stores
    /// `_ColorFilter` in `_objects`: the wrapper owns the C++ DlColorFilter
    /// that `colorFilterBridgePtr` hands to draw calls, so it must live as
    /// long as the Paint. Storing the bare struct and wrapping at draw time
    /// let ARC free the wrapper before the canvas bridge read the pointer —
    /// an EXC_BAD_ACCESS inside DecodePaint, not a Swift-side error.
    public var colorFilter: ColorFilter? {
        get {
            return (objects?[Paint.kColorFilterIndex] as? _NativeColorFilter)?.creator
        }
        set {
            _ = ensureObjectsInitialized()
            if let value = newValue {
                // Same dedupe as Dart: setting the value already stored must
                // not rebuild the native filter.
                let current = objects![Paint.kColorFilterIndex] as? _NativeColorFilter
                if current?.creator != value {
                    objects![Paint.kColorFilterIndex] = value.toNativeColorFilter()
                }
            } else {
                objects![Paint.kColorFilterIndex] = nil
            }
        }
    }

    // MARK: - imageFilter

    /// The ImageFilter to use when drawing raster images.
    ///
    /// **Dart Source:** `painting.dart:1653-1688`
    /// **Original:** `ImageFilter? get imageFilter` / `set imageFilter(ImageFilter? value)`
    ///
    /// For example, to blur an image using `Canvas.drawImage`, apply an
    /// `ImageFilter.blur`:
    ///
    /// ```swift
    /// func paint(canvas: Canvas, size: Size) {
    ///     var paint = Paint()
    ///     paint.imageFilter = ImageFilterFactory.blur(sigmaX: 0.5, sigmaY: 0.5)
    ///     canvas.drawImage(image, Offset.zero, paint)
    /// }
    /// ```
    ///
    /// See also:
    ///
    ///  * `MaskFilter`, which is used for drawing geometry.
    ///
    /// DIFFERENCE FROM DART: In Dart, ImageFilter is stored via a _ImageFilter native
    /// wrapper which has a creator property. In Swift, we store the ImageFilter directly.
    /// REASON: Swift doesn't need the native wrapper pattern since we don't use @Native.
    public var imageFilter: (any ImageFilter)? {
        get {
            return (objects?[Paint.kImageFilterIndex] as? NativeImageFilter)?
                .creator as? (any ImageFilter)
        }
        set {
            _ = ensureObjectsInitialized()
            // Stored as the native wrapper for the same lifetime reason as
            // `colorFilter` above. No dedupe: `creator` is `Any` here, so the
            // equality Dart uses is not expressible without narrowing it.
            objects![Paint.kImageFilterIndex] = newValue?.toNativeImageFilter()
        }
    }

    // MARK: - invertColors

    /// Whether the colors of the image are inverted when drawn.
    ///
    /// **Dart Source:** `painting.dart:1690-1701`
    /// **Original:** `bool get invertColors` / `set invertColors(bool value)`
    ///
    /// Inverting the colors of an image applies a new color filter that will
    /// be composed with any user provided color filters. This is primarily
    /// used for implementing smart invert on iOS.
    public var invertColors: Bool {
        get {
            return getInt32(Paint.kInvertColorOffset) == 1
        }
        set {
            setInt32(Paint.kInvertColorOffset, newValue ? 1 : 0)
        }
    }

    // MARK: - CustomStringConvertible

    /// Returns a string representation of this paint.
    ///
    /// **Dart Source:** `painting.dart:1703-1767`
    /// **Original:** `String toString()`
    public var description: String {
        var result = ""
        var semicolon = ""
        result.append("Paint(")
        if style == .stroke {
            result.append("\(style)")
            if strokeWidth != 0.0 {
                result.append(" \(String(format: "%.1f", strokeWidth))")
            } else {
                result.append(" hairline")
            }
            if strokeCap != .butt {
                result.append(" \(strokeCap)")
            }
            if strokeJoin == .miter {
                if strokeMiterLimit != Paint.kStrokeMiterLimitDefault {
                    result.append(" \(strokeJoin) up to \(String(format: "%.1f", strokeMiterLimit))")
                }
            } else {
                result.append(" \(strokeJoin)")
            }
            semicolon = "; "
        }
        if !isAntiAlias {
            result.append("\(semicolon)antialias off")
            semicolon = "; "
        }
        if color != Color(Paint.kColorDefault) {
            result.append("\(semicolon)\(color)")
            semicolon = "; "
        }
        if blendMode.rawValue != Paint.kBlendModeDefault {
            result.append("\(semicolon)\(blendMode)")
            semicolon = "; "
        }
        if colorFilter != nil {
            result.append("\(semicolon)colorFilter: \(colorFilter!)")
            semicolon = "; "
        }
        if maskFilter != nil {
            result.append("\(semicolon)maskFilter: \(maskFilter!)")
            semicolon = "; "
        }
        if filterQuality != .none {
            result.append("\(semicolon)filterQuality: \(filterQuality)")
            semicolon = "; "
        }
        if shader != nil {
            result.append("\(semicolon)shader: \(shader!)")
            semicolon = "; "
        }
        if imageFilter != nil {
            result.append("\(semicolon)imageFilter: \(imageFilter!)")
            semicolon = "; "
        }
        if invertColors {
            result.append("\(semicolon)invert: \(invertColors)")
        }
        result.append(")")
        return result
    }

    // MARK: - Internal Bridge Helpers (for NativeCanvas)

    /// Calls the closure with a pointer to the raw paint data buffer.
    /// The pointer is valid only for the duration of the closure.
    internal func withDataPointer<T>(_ body: (UnsafeRawPointer) -> T) -> T {
        return data.withUnsafeBytes { rawBuffer in
            body(rawBuffer.baseAddress!)
        }
    }

    /// Returns the shader bridge pointer for use with CanvasBridge draw methods.
    /// Returns nil if no shader is set.
    internal var shaderBridgePtr: UnsafeRawPointer? {
        guard let shader = objects?[Paint.kShaderIndex] as? Shader else {
            return nil
        }
        if let gradient = shader as? Gradient {
            return UnsafeRawPointer(gradient.gradientBridge.GetShaderPtr())
        } else if let imageShader = shader as? ImageShader {
            return UnsafeRawPointer(imageShader.imageShaderBridge.GetShaderPtr())
        } else if let fragmentShader = shader as? FragmentShader {
            return UnsafeRawPointer(fragmentShader.fragmentShaderBridge.GetShaderPtr())
        }
        return nil
    }

    /// Returns the color filter bridge pointer for use with CanvasBridge draw methods.
    /// Returns nil if no color filter is set.
    ///
    /// Reads the wrapper the setter stored — never a temporary. The returned
    /// pointer is into the wrapper's C++ object, so whoever holds it must keep
    /// the Paint alive across the bridge call, which every caller does.
    internal var colorFilterBridgePtr: UnsafeRawPointer? {
        guard let native = objects?[Paint.kColorFilterIndex] as? _NativeColorFilter else {
            return nil
        }
        return UnsafeRawPointer(native.bridge.GetFilterPtr())
    }

    /// Returns the image filter bridge pointer for use with CanvasBridge draw methods.
    /// Returns nil if no image filter is set. Same lifetime contract as
    /// `colorFilterBridgePtr`.
    internal var imageFilterBridgePtr: UnsafeRawPointer? {
        guard let native = objects?[Paint.kImageFilterIndex] as? NativeImageFilter else {
            return nil
        }
        return UnsafeRawPointer(native.bridge.GetFilterPtr(-1))
    }
}

// MARK: - Color Space Conversion Helpers for Paint

/// Converts a ColorSpace to its integer index.
///
/// **Dart Source:** `painting.dart:1805-1814`
/// **Original:** `int _colorSpaceToIndex(ColorSpace colorSpace)`
private func colorSpaceToIndex(_ colorSpace: ColorSpace) -> Int {
    switch colorSpace {
    case .sRGB:
        return 0
    case .extendedSRGB:
        return 1
    case .displayP3:
        return 2
    }
}

/// Converts an integer index to a ColorSpace.
///
/// **Dart Source:** `painting.dart:1816-1827`
/// **Original:** `ColorSpace _indexToColorSpace(int index)`
private func indexToColorSpace(_ index: Int) -> ColorSpace {
    switch index {
    case 0:
        return .sRGB
    case 1:
        return .extendedSRGB
    case 2:
        return .displayP3
    default:
        fatalError("Unknown color space: \(index)")
    }
}

// MARK: - ImageEventCallback

/// Callback signature for image creation/disposal events.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1914-1915`
/// **Original:** `typedef ImageEventCallback = void Function(Image image);`
public typealias ImageEventCallback = (Image) -> Void

// MARK: - Image

/// Opaque handle to raw decoded image data (pixels).
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:1917-2173`
/// **Original Name:** `Image`
///
/// To obtain an `Image` object, use the `ImageDescriptor` API.
///
/// To draw an `Image`, use one of the methods on the `Canvas` class, such as
/// `Canvas.drawImage`.
///
/// A class or method that receives an image object must call `dispose()` on the
/// handle when it is no longer needed. To create a shareable reference to the
/// underlying image, call `clone()`. The method or object that receives
/// the new instance will then be responsible for disposing it, and the
/// underlying image itself will be disposed when all outstanding handles are
/// disposed.
///
/// If `dart:ui` passes an `Image` object and the recipient wishes to share
/// that handle with other callers, `clone()` must be called _before_ `dispose()`.
/// A handle that has been disposed cannot create new handles anymore.
///
/// DIFFERENCE FROM DART: Uses a Swift class with explicit handle counting
/// rather than Dart's _Image/Image split. The ImageBridge C++ object
/// corresponds to Dart's _Image, and this Swift Image class corresponds
/// to Dart's Image.
/// REASON: Swift doesn't have NativeFieldWrapperClass1; we use
/// SWIFT_SHARED_REFERENCE via C++ bridge instead.
public class Image {
  /// The C++ bridge object that wraps the native DlImage.
  ///
  /// This corresponds to Dart's `_Image` internal class.
  /// Multiple Image handles can share the same bridge.
  internal let bridge: flutter.swift_bridge.ImageBridge

  /// The set of Image handles sharing this bridge.
  ///
  /// **Dart Source:** `painting.dart:2226`
  /// **Original:** `final Set<Image> _handles = <Image>{};`
  ///
  /// DIFFERENCE FROM DART: The handles set is stored on the Image class itself
  /// (on the "primary" handle) rather than on the _Image internal class.
  /// REASON: Swift bridge doesn't store Swift objects; we use a shared
  /// reference-counted container instead.
  private let handleTracker: ImageHandleTracker

  /// The number of image pixels along the image's horizontal axis.
  ///
  /// **Dart Source:** `painting.dart:1971-1972`
  /// **Original:** `final int width;`
  public let width: Int

  /// The number of image pixels along the image's vertical axis.
  ///
  /// **Dart Source:** `painting.dart:1974-1975`
  /// **Original:** `final int height;`
  public let height: Int

  /// Whether this handle has been disposed.
  ///
  /// **Dart Source:** `painting.dart:1977`
  /// **Original:** `bool _disposed = false;`
  private var _disposed: Bool = false

  /// Debug stack trace recorded at creation time.
  ///
  /// **Dart Source:** `painting.dart:1969`
  /// **Original:** `StackTrace? _debugStack;`
  ///
  /// DIFFERENCE FROM DART: Not implemented. Swift doesn't have a lightweight
  /// StackTrace equivalent for debug-only tracking.
  /// REASON: Swift Thread.callStackSymbols is expensive; omitted for now.

  // MARK: - Initializers

  /// Internal initializer (corresponds to Dart's `Image._`).
  ///
  /// **Dart Source:** `painting.dart:1942-1949`
  /// **Original:** `Image._(this._image, this.width, this.height)`
  private init(bridge: flutter.swift_bridge.ImageBridge, tracker: ImageHandleTracker) {
    self.bridge = bridge
    self.handleTracker = tracker
    self.width = Int(bridge.Width())
    self.height = Int(bridge.Height())
    tracker.addHandle(self)
    Image.onCreate?(self)
  }

  /// Creates a new Image wrapping a native bridge, setting up handle tracking internally.
  ///
  /// This replaces the former free function `wrapImage()` (Dart: `_wrapImage`).
  /// Callers outside the Image class should use this instead of the private init.
  internal static func wrap(_ bridge: flutter.swift_bridge.ImageBridge) -> Image {
    let tracker = ImageHandleTracker()
    return Image(bridge: bridge, tracker: tracker)
  }

  // MARK: - Static Fields

  /// A callback that is invoked to report an image creation.
  ///
  /// **Dart Source:** `painting.dart:1955-1960`
  /// **Original:** `static ImageEventCallback? onCreate;`
  ///
  /// It's preferred to use `MemoryAllocations` in flutter/foundation.dart
  /// than to use `onCreate` directly because `MemoryAllocations`
  /// allows multiple callbacks.
  nonisolated(unsafe) public static var onCreate: ImageEventCallback? = nil

  /// A callback that is invoked to report the image disposal.
  ///
  /// **Dart Source:** `painting.dart:1962-1967`
  /// **Original:** `static ImageEventCallback? onDispose;`
  ///
  /// It's preferred to use `MemoryAllocations` in flutter/foundation.dart
  /// than to use `onDispose` directly because `MemoryAllocations`
  /// allows multiple callbacks.
  nonisolated(unsafe) public static var onDispose: ImageEventCallback? = nil

  // MARK: - Methods

  /// Release this handle's claim on the underlying Image. This handle is no
  /// longer usable after this method is called.
  ///
  /// **Dart Source:** `painting.dart:1989-1999`
  /// **Original:** `void dispose()`
  ///
  /// Once all outstanding handles have been disposed, the underlying image will
  /// be disposed as well.
  public func dispose() {
    Image.onDispose?(self)
    assert(!_disposed && !bridge.IsDisposed())
    assert(handleTracker.contains(self))
    _disposed = true
    let removed = handleTracker.removeHandle(self)
    assert(removed)
    if handleTracker.isEmpty {
      bridge.Dispose()
    }
  }

  /// Converts the Image object into a byte array.
  ///
  /// **Dart Source:** `painting.dart:2015-2033, 2191-2205`
  /// **Original:** `Future<ByteData?> toByteData({ImageByteFormat format})`
  ///              `@Native String? _toByteData(int format, callback)`
  ///
  /// The `format` argument specifies the format in which the bytes will be
  /// returned.
  ///
  /// DIFFERENCE FROM DART: Synchronous instead of async. Dart version uses
  /// _futurizeWithError + task runners for async GPU readback before encoding.
  /// This version encodes synchronously for raster-backed (CPU) images.
  /// GPU-only images without Skia backing will throw.
  /// REASON: The async path requires UIDartState for task runner access,
  /// which is Dart VM specific. A future engine integration layer will
  /// provide the async path for GPU-backed images.
  public func toByteData(format: ImageByteFormat = .rawRgba) throws -> Data {
    assert(!_disposed && !bridge.IsDisposed())

    var outData: UnsafeRawPointer? = nil
    var outLength: Int64 = 0
    var outError: UnsafePointer<CChar>? = nil

    let success = bridge.ToByteData(
      Int32(format.rawValue),
      &outData,
      &outLength,
      &outError
    )

    guard success, let data = outData, outLength > 0 else {
      let errorMessage: String
      if let outError = outError {
        errorMessage = String(cString: outError)
      } else {
        errorMessage = "Unknown error encoding image"
      }
      throw PaintingError.operationFailed(errorMessage)
    }

    // Copy the data into a Swift Data and free the C++ allocated buffer.
    let result = Data(bytes: data, count: Int(outLength))
    flutter.swift_bridge.ImageBridge.FreeByteData(data)
    return result
  }

  /// Whether this reference to the underlying image is `dispose`d.
  ///
  /// **Dart Source:** `painting.dart:2005-2013`
  /// **Original:** `bool get debugDisposed`
  ///
  /// This only returns a valid value if asserts are enabled, and must not be
  /// used otherwise.
  public var debugDisposed: Bool {
    var disposed: Bool? = nil
    assert({
      disposed = _disposed
      return true
    }())
    if let disposed = disposed {
      return disposed
    }
    fatalError("Image.debugDisposed is only available when asserts are enabled.")
  }

  /// The color space that is used by the Image's colors.
  ///
  /// **Dart Source:** `painting.dart:2046-2056`
  /// **Original:** `ColorSpace get colorSpace`
  ///
  /// This value is a consequence of how the Image has been created. For
  /// example, loading a PNG that is in the Display P3 color space will result
  /// in a `ColorSpace.extendedSRGB` image.
  public var colorSpace: ColorSpace {
    let colorSpaceValue = Int(bridge.GetColorSpace())
    switch colorSpaceValue {
    case 0:
      return .sRGB
    case 1:
      return .extendedSRGB
    default:
      fatalError("Unrecognized color space: \(colorSpaceValue)")
    }
  }

  /// If asserts are enabled, returns the stack traces of each open handle from
  /// `clone()`, in creation order.
  ///
  /// **Dart Source:** `painting.dart:2062-2069`
  /// **Original:** `List<StackTrace>? debugGetOpenHandleStackTraces()`
  ///
  /// DIFFERENCE FROM DART: Always returns nil.
  /// REASON: Swift doesn't have a lightweight StackTrace for debug-only tracking.
  /// Thread.callStackSymbols is too expensive for routine use.
  public func debugGetOpenHandleStackTraces() -> [String]? {
    return nil
  }

  /// Creates a disposable handle to this image.
  ///
  /// **Dart Source:** `painting.dart:2147-2158`
  /// **Original:** `Image clone()`
  ///
  /// Holders of an Image must dispose of the image when they no longer need
  /// to access it or draw it. However, once the underlying image is disposed,
  /// it is no longer possible to use it. If a holder of an image needs to share
  /// access to that image with another object or method, `clone()` creates a
  /// duplicate handle.
  ///
  /// The returned object behaves identically to this image. Calling
  /// `dispose()` on it will only dispose the underlying native resources if it
  /// is the last remaining handle.
  public func clone() -> Image {
    if _disposed {
      fatalError(
        "Cannot clone a disposed image.\n"
        + "The clone() method of a previously-disposed Image was called. Once an "
        + "Image object has been disposed, it can no longer be used to create "
        + "handles, as the underlying data may have been released."
      )
    }
    assert(!bridge.IsDisposed())
    return Image(bridge: bridge, tracker: handleTracker)
  }

  /// Returns true if `other` is a clone of this and thus shares the same
  /// underlying image memory, even if this or `other` is disposed.
  ///
  /// **Dart Source:** `painting.dart:2169`
  /// **Original:** `bool isCloneOf(Image other) => other._image == _image;`
  ///
  /// This method may return false for two images that were decoded from the
  /// same underlying asset, if they are not sharing the same memory.
  public func isCloneOf(_ other: Image) -> Bool {
    // DIFFERENCE FROM DART: Uses handleTracker identity instead of _image identity.
    // REASON: C++ SWIFT_SHARED_REFERENCE types don't support Swift's === operator.
    // The handleTracker is a Swift class shared by all clones, providing the same
    // identity semantics as Dart's _image reference equality.
    return other.handleTracker === handleTracker
  }

  /// Returns a string representation of this image.
  ///
  /// **Dart Source:** `painting.dart:2171-2172`
  /// **Original:** `String toString() => _image.toString();`
  public var description: String {
    // Match Dart's _Image.toString(): '[$width×$height]'
    return "[\(width)\u{00D7}\(height)]"
  }
}

// MARK: - ImageHandleTracker

/// Tracks the set of Image handles sharing a single underlying ImageBridge.
///
/// This corresponds to the `_handles` Set on Dart's `_Image` class.
/// In Dart, `_Image._handles` is a `Set<Image>` stored directly on the
/// native wrapper. Since our C++ bridge can't store Swift objects, we use
/// this separate tracker class that is shared by all Image handles cloned
/// from the same source.
///
/// **Dart Source:** `painting.dart:2226`
/// **Original:** `final Set<Image> _handles = <Image>{};`
internal class ImageHandleTracker {
  /// Weak references to avoid retain cycles.
  /// Using ObjectIdentifier for identity-based tracking.
  private var handles: Set<ObjectIdentifier> = []

  /// The count of active handles.
  var count: Int { handles.count }

  /// Whether there are no active handles.
  var isEmpty: Bool { handles.isEmpty }

  /// Add a handle to the tracker.
  func addHandle(_ image: Image) {
    handles.insert(ObjectIdentifier(image))
  }

  /// Remove a handle from the tracker. Returns true if the handle was present.
  @discardableResult
  func removeHandle(_ image: Image) -> Bool {
    return handles.remove(ObjectIdentifier(image)) != nil
  }

  /// Check if a handle is tracked.
  func contains(_ image: Image) -> Bool {
    return handles.contains(ObjectIdentifier(image))
  }
}

// MARK: - ImageShader

/// A shader (as used by `Paint.shader`) that tiles an image.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:5115-5185`
/// **Original Name:** `ImageShader`
///
/// This shader takes an Image and tiles it according to the specified tile modes.
/// The transformation matrix can be used to scale, rotate, or translate the image.
///
/// DIFFERENCE FROM DART: Swift uses a separate ImageShaderBridge class instead of
/// extending the base ShaderBridge with native methods.
/// REASON: Swift's C++ interop requires explicit bridge classes with pimpl pattern.
public class ImageShader: Shader {
    /// The C++ bridge object that handles image shader operations.
    internal let imageShaderBridge: flutter.swift_bridge.ImageShaderBridge

    /// Creates an image-tiling shader.
    ///
    /// **Dart Source:** `painting.dart:5117-5159`
    /// **Original:** `ImageShader(...)`
    ///
    /// The first argument specifies the image to render. The
    /// `decodeImageFromList` function can be used to decode an image from bytes
    /// into the form expected here.
    ///
    /// The second and third arguments specify the `TileMode` for the x direction
    /// and y direction respectively. `TileMode.repeated` can be used for tiling
    /// images.
    ///
    /// The fourth argument gives the matrix to apply to the effect. The
    /// expression `Matrix4.identity().storage` creates a `[Double]`
    /// prepopulated with the identity matrix.
    ///
    /// All the arguments are required and must not be nil, except for
    /// `filterQuality`. If `filterQuality` is not specified at construction time
    /// it will be deduced from the environment where it is used, such as from
    /// `Paint.filterQuality`.
    ///
    /// - Parameters:
    ///   - image: The image to tile.
    ///   - tmx: The tile mode for the x direction.
    ///   - tmy: The tile mode for the y direction.
    ///   - matrix4: A 4x4 transformation matrix (16 values, column-major).
    ///   - filterQuality: The quality to use when sampling the image. If nil, uses environment setting.
    ///
    /// - Throws: `FlutterSwiftBridgeError.invalidArgument` if the matrix doesn't have 16 entries,
    ///           or `FlutterSwiftBridgeError.invalidState` if the image is disposed or invalid.
    public init(
        _ image: Image,
        _ tmx: TileMode,
        _ tmy: TileMode,
        _ matrix4: [Double],
        filterQuality: FilterQuality? = nil
    ) throws {
        // Validate matrix has 16 entries (Dart: painting.dart:5145-5147)
        guard matrix4.count == 16 else {
            throw FlutterSwiftBridgeError.invalidArgument("\"matrix4\" must have 16 entries.")
        }

        // Validate image is not disposed (Dart: painting.dart:5143)
        assert(!image.debugDisposed, "ImageShader created with disposed Image")

        // Create the image shader bridge
        let bridge = flutter.swift_bridge.ImageShaderBridge()
        self.imageShaderBridge = bridge

        // Initialize with the image (Dart: painting.dart:5148-5158)
        let filterQualityIndex: Int32 = filterQuality.map { Int32($0.rawValue) } ?? -1

        let success = matrix4.withUnsafeBufferPointer { matrixPtr in
            bridge.InitWithImage(
                image.bridge,
                Int32(tmx.rawValue),
                Int32(tmy.rawValue),
                filterQualityIndex,
                matrixPtr.baseAddress
            )
        }

        guard success else {
            throw FlutterSwiftBridgeError.invalidState("ImageShader constructor called with non-genuine Image.")
        }

        // Call parent initializer
        super.init()
    }

    /// Release the resources used by this image shader.
    ///
    /// **Dart Source:** `painting.dart:5161-5165`
    /// **Original:** `void dispose()`
    ///
    /// After calling this method, the shader is no longer usable.
    public override func dispose() {
        imageShaderBridge.Dispose()
        super.dispose()
    }

    /// Whether `dispose()` has been called on this shader.
    ///
    /// **Dart Source:** `painting.dart:4619-4629` (inherited from Shader)
    public override var debugDisposed: Bool {
        return imageShaderBridge.DebugDisposed()
    }
}

// MARK: - Path

/// A complex, one-dimensional subset of a plane.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2837-3494`
/// **Original Name:** `Path` (abstract class) / `_NativePath` (implementation)
///
/// A path consists of a number of sub-paths, and a _current point_.
/// Sub-paths consist of segments of various types, such as lines,
/// arcs, or beziers. Sub-paths can be open or closed, and can
/// self-intersect.
///
/// Closed sub-paths enclose a (possibly discontiguous) region of the
/// plane based on the current `fillType`.
///
/// The _current point_ is initially at the origin. After each operation
/// adding a segment to a sub-path, the current point is updated to the
/// end of that segment.
///
/// Paths can be drawn on canvases using `Canvas.drawPath`, and can
/// be used to create clip regions using `Canvas.clipPath`.
///
/// DIFFERENCE FROM DART: In Dart, `Path` is an abstract class with `_NativePath`
/// as its implementation extending `NativeFieldWrapperClass1`. In Swift, `Path`
/// is a concrete class wrapping the C++ `PathBridge` via SWIFT_SHARED_REFERENCE.
/// REASON: Swift doesn't use NativeFieldWrapperClass1; instead uses C++ bridge
/// with automatic memory management via Swift ARC.
public class Path {
  /// C++ bridge object - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
  internal let bridge: flutter.swift_bridge.PathBridge

  /// Creates a new empty Path.
  ///
  /// **Dart Source:** `painting.dart:2857`
  /// **Original:** `factory Path() = _NativePath;`
  public init() {
    self.bridge = flutter.swift_bridge.PathBridge()
  }

  /// Creates a Path wrapping an existing PathBridge.
  /// Used internally by static factory methods (shift, transform, clone, combine).
  fileprivate init(bridge: flutter.swift_bridge.PathBridge) {
    self.bridge = bridge
  }

  /// Creates a copy of another Path.
  ///
  /// **Dart Source:** `painting.dart:2859-2867`
  /// **Original:** `factory Path.from(Path source)`
  ///
  /// This copy is fast and does not require additional memory unless either
  /// the source path or the returned path are modified.
  public convenience init(from source: Path) {
    self.init(bridge: flutter.swift_bridge.PathBridge.Clone(source.bridge))
  }

  // MARK: - Fill Type

  /// Determines how the interior of this path is calculated.
  ///
  /// **Dart Source:** `painting.dart:2869-2872`
  /// **Original:** `PathFillType get fillType;`
  ///
  /// Defaults to the non-zero winding rule, `PathFillType.nonZero`.
  public var fillType: PathFillType {
    get {
      return PathFillType(rawValue: Int(bridge.GetFillType()))!
    }
    set {
      bridge.SetFillType(Int32(newValue.rawValue))
    }
  }

  // MARK: - Path Construction

  /// Starts a new sub-path at the given coordinate.
  ///
  /// **Dart Source:** `painting.dart:2875-2876`
  /// **Original:** `void moveTo(double x, double y);`
  public func moveTo(_ x: Double, _ y: Double) {
    bridge.MoveTo(x, y)
  }

  /// Starts a new sub-path at the given offset from the current point.
  ///
  /// **Dart Source:** `painting.dart:2878-2879`
  /// **Original:** `void relativeMoveTo(double dx, double dy);`
  public func relativeMoveTo(_ dx: Double, _ dy: Double) {
    bridge.RelativeMoveTo(dx, dy)
  }

  /// Adds a straight line segment from the current point to the given point.
  ///
  /// **Dart Source:** `painting.dart:2881-2883`
  /// **Original:** `void lineTo(double x, double y);`
  public func lineTo(_ x: Double, _ y: Double) {
    bridge.LineTo(x, y)
  }

  /// Adds a straight line segment from the current point to the point
  /// at the given offset from the current point.
  ///
  /// **Dart Source:** `painting.dart:2885-2887`
  /// **Original:** `void relativeLineTo(double dx, double dy);`
  public func relativeLineTo(_ dx: Double, _ dy: Double) {
    bridge.RelativeLineTo(dx, dy)
  }

  /// Adds a quadratic bezier segment that curves from the current
  /// point to the given point (x2,y2), using the control point (x1,y1).
  ///
  /// **Dart Source:** `painting.dart:2889-2895`
  /// **Original:** `void quadraticBezierTo(double x1, double y1, double x2, double y2);`
  public func quadraticBezierTo(_ x1: Double, _ y1: Double,
                                 _ x2: Double, _ y2: Double) {
    bridge.QuadraticBezierTo(x1, y1, x2, y2)
  }

  /// Adds a quadratic bezier segment that curves from the current
  /// point to the point at the offset (x2,y2) from the current point,
  /// using the control point at the offset (x1,y1) from the current point.
  ///
  /// **Dart Source:** `painting.dart:2897-2901`
  /// **Original:** `void relativeQuadraticBezierTo(double x1, double y1, double x2, double y2);`
  public func relativeQuadraticBezierTo(_ x1: Double, _ y1: Double,
                                         _ x2: Double, _ y2: Double) {
    bridge.RelativeQuadraticBezierTo(x1, y1, x2, y2)
  }

  /// Adds a cubic bezier segment that curves from the current point
  /// to the given point (x3,y3), using the control points (x1,y1) and (x2,y2).
  ///
  /// **Dart Source:** `painting.dart:2903-2909`
  /// **Original:** `void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3);`
  public func cubicTo(_ x1: Double, _ y1: Double,
                       _ x2: Double, _ y2: Double,
                       _ x3: Double, _ y3: Double) {
    bridge.CubicTo(x1, y1, x2, y2, x3, y3)
  }

  /// Adds a cubic bezier segment that curves from the current point
  /// to the point at the offset (x3,y3) from the current point, using
  /// the control points at the offsets (x1,y1) and (x2,y2) from the current point.
  ///
  /// **Dart Source:** `painting.dart:2911-2915`
  /// **Original:** `void relativeCubicTo(double x1, double y1, double x2, double y2, double x3, double y3);`
  public func relativeCubicTo(_ x1: Double, _ y1: Double,
                               _ x2: Double, _ y2: Double,
                               _ x3: Double, _ y3: Double) {
    bridge.RelativeCubicTo(x1, y1, x2, y2, x3, y3)
  }

  /// Adds a bezier segment that curves from the current point to the
  /// given point (x2,y2), using the control points (x1,y1) and the weight w.
  ///
  /// **Dart Source:** `painting.dart:2917-2925`
  /// **Original:** `void conicTo(double x1, double y1, double x2, double y2, double w);`
  ///
  /// If the weight is greater than 1, then the curve is a hyperbola;
  /// if the weight equals 1, it's a parabola; and if it is less than 1,
  /// it is an ellipse.
  public func conicTo(_ x1: Double, _ y1: Double,
                       _ x2: Double, _ y2: Double,
                       _ w: Double) {
    bridge.ConicTo(x1, y1, x2, y2, w)
  }

  /// Adds a bezier segment that curves from the current point to the
  /// point at the offset (x2,y2) from the current point, using the
  /// control point at the offset (x1,y1) from the current point and the weight w.
  ///
  /// **Dart Source:** `painting.dart:2927-2933`
  /// **Original:** `void relativeConicTo(double x1, double y1, double x2, double y2, double w);`
  public func relativeConicTo(_ x1: Double, _ y1: Double,
                               _ x2: Double, _ y2: Double,
                               _ w: Double) {
    bridge.RelativeConicTo(x1, y1, x2, y2, w)
  }

  /// If the `forceMoveTo` argument is false, adds a straight line
  /// segment and an arc segment.
  ///
  /// **Dart Source:** `painting.dart:2935-2951`
  /// **Original:** `void arcTo(Rect rect, double startAngle, double sweepAngle, bool forceMoveTo);`
  ///
  /// If the `forceMoveTo` argument is true, starts a new sub-path
  /// consisting of an arc segment.
  ///
  /// In either case, the arc segment consists of the arc that follows
  /// the edge of the oval bounded by the given rectangle, from
  /// startAngle radians around the oval up to startAngle + sweepAngle
  /// radians around the oval, with zero radians being the point on
  /// the right hand side of the oval that crosses the horizontal line
  /// that intersects the center of the rectangle and with positive
  /// angles going clockwise around the oval.
  public func arcTo(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double,
                     _ forceMoveTo: Bool) {
    assert(!rect.hasNaN, "Rect argument contained a NaN value.")
    bridge.ArcTo(rect.left, rect.top, rect.right, rect.bottom,
                  startAngle, sweepAngle, forceMoveTo)
  }

  /// Appends up to four conic curves weighted to describe an oval of `radius`
  /// and rotated by `rotation` (measured in degrees and clockwise).
  ///
  /// **Dart Source:** `painting.dart:2953-2971`
  /// **Original:** `void arcToPoint(Offset arcEnd, {Radius radius, double rotation, bool largeArc, bool clockwise});`
  ///
  /// The first curve begins from the last point in the path and the last ends
  /// at `arcEnd`. The curves follow a path in a direction determined by
  /// `clockwise` and `largeArc` in such a way that the sweep angle
  /// is always less than 360 degrees.
  public func arcToPoint(_ arcEnd: Offset,
                          radius: Radius = Radius.zero,
                          rotation: Double = 0.0,
                          largeArc: Bool = false,
                          clockwise: Bool = true) {
    assert(!arcEnd.dx.isNaN && !arcEnd.dy.isNaN,
           "Offset argument contained a NaN value.")
    bridge.ArcToPoint(arcEnd.dx, arcEnd.dy, radius.x, radius.y,
                       rotation, largeArc, clockwise)
  }

  /// Appends up to four conic curves weighted to describe an oval of `radius`
  /// and rotated by `rotation` (measured in degrees and clockwise).
  ///
  /// **Dart Source:** `painting.dart:2973-2993`
  /// **Original:** `void relativeArcToPoint(Offset arcEndDelta, {Radius radius, double rotation, bool largeArc, bool clockwise});`
  public func relativeArcToPoint(_ arcEndDelta: Offset,
                                  radius: Radius = Radius.zero,
                                  rotation: Double = 0.0,
                                  largeArc: Bool = false,
                                  clockwise: Bool = true) {
    assert(!arcEndDelta.dx.isNaN && !arcEndDelta.dy.isNaN,
           "Offset argument contained a NaN value.")
    bridge.RelativeArcToPoint(arcEndDelta.dx, arcEndDelta.dy,
                               radius.x, radius.y,
                               rotation, largeArc, clockwise)
  }

  // MARK: - Shape Addition

  /// Adds a new sub-path that consists of four lines that outline the
  /// given rectangle.
  ///
  /// **Dart Source:** `painting.dart:2995-2997`
  /// **Original:** `void addRect(Rect rect);`
  public func addRect(_ rect: Rect) {
    assert(!rect.hasNaN, "Rect argument contained a NaN value.")
    bridge.AddRect(rect.left, rect.top, rect.right, rect.bottom)
  }

  /// Adds a new sub-path that consists of a curve that forms the
  /// ellipse that fills the given rectangle.
  ///
  /// **Dart Source:** `painting.dart:2999-3004`
  /// **Original:** `void addOval(Rect oval);`
  ///
  /// To add a circle, pass an appropriate rectangle as `oval`. `Rect.fromCircle`
  /// can be used to easily describe the circle's center `Offset` and radius.
  public func addOval(_ oval: Rect) {
    assert(!oval.hasNaN, "Rect argument contained a NaN value.")
    bridge.AddOval(oval.left, oval.top, oval.right, oval.bottom)
  }

  /// Adds a new sub-path with one arc segment that consists of the arc
  /// that follows the edge of the oval bounded by the given rectangle.
  ///
  /// **Dart Source:** `painting.dart:3006-3020`
  /// **Original:** `void addArc(Rect oval, double startAngle, double sweepAngle);`
  public func addArc(_ oval: Rect, _ startAngle: Double, _ sweepAngle: Double) {
    assert(!oval.hasNaN, "Rect argument contained a NaN value.")
    bridge.AddArc(oval.left, oval.top, oval.right, oval.bottom,
                   startAngle, sweepAngle)
  }

  /// Adds a new sub-path with a sequence of line segments that connect the given
  /// points.
  ///
  /// **Dart Source:** `painting.dart:3022-3029`
  /// **Original:** `void addPolygon(List<Offset> points, bool close);`
  ///
  /// If `close` is true, a final line segment will be added that connects the
  /// last point to the first point.
  ///
  /// The `points` argument is interpreted as offsets from the origin.
  public func addPolygon(_ points: [Offset], _ close: Bool) {
    // Encode offsets as flat Float32 array [x0, y0, x1, y1, ...]
    // Same as Dart's _encodePointList (painting.dart:4783-4795)
    var encoded: [Float] = []
    encoded.reserveCapacity(points.count * 2)
    for point in points {
      assert(!point.dx.isNaN && !point.dy.isNaN,
             "Offset argument contained a NaN value.")
      encoded.append(Float(point.dx))
      encoded.append(Float(point.dy))
    }
    encoded.withUnsafeBufferPointer { buffer in
      bridge.AddPolygon(buffer.baseAddress, Int32(points.count), close)
    }
  }

  /// Adds a new sub-path that consists of the straight lines and
  /// curves needed to form the rounded rectangle described by the argument.
  ///
  /// **Dart Source:** `painting.dart:3031-3034`
  /// **Original:** `void addRRect(RRect rrect);`
  public func addRRect(_ rrect: RRect) {
    assert(!rrect.hasNaN, "RRect argument contained a NaN value.")
    // Encode RRect as 12 floats matching Dart's RRect._getValue32()
    let values: [Float] = [
      Float(rrect.left), Float(rrect.top), Float(rrect.right), Float(rrect.bottom),
      Float(rrect.tlRadiusX), Float(rrect.tlRadiusY),
      Float(rrect.trRadiusX), Float(rrect.trRadiusY),
      Float(rrect.brRadiusX), Float(rrect.brRadiusY),
      Float(rrect.blRadiusX), Float(rrect.blRadiusY),
    ]
    values.withUnsafeBufferPointer { buffer in
      bridge.AddRRect(buffer.baseAddress)
    }
  }

  /// Adds a new sub-path that consists of curves needed to form the rounded
  /// superellipse described by the argument.
  ///
  /// **Dart Source:** `painting.dart:3036-3038`
  /// **Original:** `void addRSuperellipse(RSuperellipse rsuperellipse);`
  public func addRSuperellipse(_ rsuperellipse: RSuperellipse) {
    bridge.AddRSuperellipse(
      rsuperellipse.left, rsuperellipse.top,
      rsuperellipse.right, rsuperellipse.bottom,
      rsuperellipse.tlRadiusX, rsuperellipse.tlRadiusY,
      rsuperellipse.trRadiusX, rsuperellipse.trRadiusY,
      rsuperellipse.brRadiusX, rsuperellipse.brRadiusY,
      rsuperellipse.blRadiusX, rsuperellipse.blRadiusY
    )
  }

  /// Adds the sub-paths of `path`, offset by `offset`, to this path.
  ///
  /// **Dart Source:** `painting.dart:3040-3045`
  /// **Original:** `void addPath(Path path, Offset offset, {Float64List? matrix4});`
  ///
  /// If `matrix4` is specified, the path will be transformed by this matrix
  /// after the matrix is translated by the given offset. The matrix is a 4x4
  /// matrix stored in column major order.
  public func addPath(_ path: Path, _ offset: Offset, matrix4: [Double]? = nil) {
    assert(!offset.dx.isNaN && !offset.dy.isNaN,
           "Offset argument contained a NaN value.")
    if let matrix4 = matrix4 {
      assert(matrix4.count == 16, "Matrix4 must have 16 entries.")
      assert(matrix4.allSatisfy { $0.isFinite }, "Matrix4 entries must be finite.")
      matrix4.withUnsafeBufferPointer { buffer in
        bridge.AddPathWithMatrix(path.bridge, offset.dx, offset.dy,
                                  buffer.baseAddress)
      }
    } else {
      bridge.AddPath(path.bridge, offset.dx, offset.dy)
    }
  }

  /// Adds the sub-paths of `path`, offset by `offset`, to this path.
  /// The current sub-path is extended with the first sub-path of `path`,
  /// connecting them with a lineTo if necessary.
  ///
  /// **Dart Source:** `painting.dart:3047-3054`
  /// **Original:** `void extendWithPath(Path path, Offset offset, {Float64List? matrix4});`
  ///
  /// If `matrix4` is specified, the path will be transformed by this matrix
  /// after the matrix is translated by the given `offset`. The matrix is a 4x4
  /// matrix stored in column major order.
  public func extendWithPath(_ path: Path, _ offset: Offset,
                              matrix4: [Double]? = nil) {
    assert(!offset.dx.isNaN && !offset.dy.isNaN,
           "Offset argument contained a NaN value.")
    if let matrix4 = matrix4 {
      assert(matrix4.count == 16, "Matrix4 must have 16 entries.")
      assert(matrix4.allSatisfy { $0.isFinite }, "Matrix4 entries must be finite.")
      matrix4.withUnsafeBufferPointer { buffer in
        bridge.ExtendWithPathAndMatrix(path.bridge, offset.dx, offset.dy,
                                        buffer.baseAddress)
      }
    } else {
      bridge.ExtendWithPath(path.bridge, offset.dx, offset.dy)
    }
  }

  // MARK: - Path Operations

  /// Closes the last sub-path, as if a straight line had been drawn
  /// from the current point to the first point of the sub-path.
  ///
  /// **Dart Source:** `painting.dart:3056-3058`
  /// **Original:** `void close();`
  public func close() {
    bridge.Close()
  }

  /// Clears the Path object of all sub-paths, returning it to the
  /// same state it had when it was created. The _current point_ is
  /// reset to the origin.
  ///
  /// **Dart Source:** `painting.dart:3060-3063`
  /// **Original:** `void reset();`
  public func reset() {
    bridge.Reset()
  }

  /// Tests to see if the given point is within the path. (That is, whether the
  /// point would be in the visible portion of the path if the path was used
  /// with `Canvas.clipPath`.)
  ///
  /// **Dart Source:** `painting.dart:3065-3072`
  /// **Original:** `bool contains(Offset point);`
  ///
  /// The `point` argument is interpreted as an offset from the origin.
  ///
  /// Returns true if the point is in the path, and false otherwise.
  public func contains(_ point: Offset) -> Bool {
    assert(!point.dx.isNaN && !point.dy.isNaN,
           "Offset argument contained a NaN value.")
    return bridge.Contains(point.dx, point.dy)
  }

  /// Returns a copy of the path with all the segments of every
  /// sub-path translated by the given offset.
  ///
  /// **Dart Source:** `painting.dart:3074-3076`
  /// **Original:** `Path shift(Offset offset);`
  public func shift(_ offset: Offset) -> Path {
    assert(!offset.dx.isNaN && !offset.dy.isNaN,
           "Offset argument contained a NaN value.")
    return Path(bridge: flutter.swift_bridge.PathBridge.Shift(
      bridge, offset.dx, offset.dy))
  }

  /// Returns a copy of the path with all the segments of every
  /// sub-path transformed by the given matrix.
  ///
  /// **Dart Source:** `painting.dart:3078-3080`
  /// **Original:** `Path transform(Float64List matrix4);`
  public func transform(_ matrix4: [Double]) -> Path {
    assert(matrix4.count == 16, "Matrix4 must have 16 entries.")
    assert(matrix4.allSatisfy { $0.isFinite }, "Matrix4 entries must be finite.")
    return matrix4.withUnsafeBufferPointer { buffer in
      Path(bridge: flutter.swift_bridge.PathBridge.Transform(
        bridge, buffer.baseAddress))
    }
  }

  /// Computes the bounding rectangle for this path.
  ///
  /// **Dart Source:** `painting.dart:3082-3097`
  /// **Original:** `Rect getBounds();`
  ///
  /// A path containing only axis-aligned points on the same straight line will
  /// have no area, and therefore `Rect.isEmpty` will return true for such a
  /// path. Consider checking `rect.width + rect.height > 0.0` instead, or
  /// using the `computeMetrics` API to check the path length.
  public func getBounds() -> Rect {
    var bounds: [Float] = [0, 0, 0, 0]
    bounds.withUnsafeMutableBufferPointer { buffer in
      bridge.GetBounds(buffer.baseAddress)
    }
    return Rect.fromLTRB(Double(bounds[0]), Double(bounds[1]),
                          Double(bounds[2]), Double(bounds[3]))
  }

  /// Combines the two paths according to the manner specified by the given
  /// `operation`.
  ///
  /// **Dart Source:** `painting.dart:3099-3113`
  /// **Original:** `static Path combine(PathOperation operation, Path path1, Path path2)`
  ///
  /// The resulting path will be constructed from non-overlapping contours. The
  /// curve order is reduced where possible so that cubics may be turned into
  /// quadratics, and quadratics may be turned into lines.
  public static func combine(_ operation: PathOperation, _ path1: Path,
                              _ path2: Path) -> Path {
    let result = Path()
    let success = result.bridge.Op(path1.bridge, path2.bridge,
                                    Int32(operation.rawValue))
    if !success {
      fatalError("Path.combine() failed. This may be due to an invalid path; in particular, check for NaN values.")
    }
    return result
  }

  /// Creates a PathMetrics object for this path, which can describe various
  /// properties about the contours of the path.
  ///
  /// **Dart Source:** `painting.dart:3115-3146`
  /// **Original:** `PathMetrics computeMetrics({bool forceClosed = false});`
  public func computeMetrics(forceClosed: Bool = false) -> PathMetrics {
    return PathMetrics(self, forceClosed: forceClosed)
  }

  /// String representation of this Path.
  ///
  /// **Dart Source:** `painting.dart:3492-3493`
  /// **Original:** `String toString() => 'Path';`
  public var description: String {
    return "Path"
  }
}

// MARK: - PathMetrics
/// An iterable collection of PathMetric objects describing a Path.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `PathMetrics`
/// **Lines:** 3542-3565
///
/// A PathMetrics object is created by using the Path.computeMetrics method,
/// and represents the path as it stood at the time of the call. Subsequent
/// modifications of the path do not affect the PathMetrics object.
///
/// Each path metric corresponds to a segment, or contour, of a path.
///
/// For example, a path consisting of a lineTo, a moveTo, and
/// another lineTo will contain two contours and thus be represented by
/// two PathMetric objects.
///
/// This type conforms to Sequence so it can be iterated with for-in loops.
/// It does not memoize. Callers who need to traverse the list multiple times,
/// or who need to randomly access elements of the list, should use
/// Array(pathMetrics) to convert to an array first.
///
/// DIFFERENCE FROM DART: Uses Swift Sequence protocol instead of IterableBase.
/// REASON: Swift idiomatic approach for iteration.
public class PathMetrics: Sequence {
  public typealias Element = PathMetric
  public typealias Iterator = PathMetricIterator

  /// Creates a PathMetrics from a Path and forceClosed flag.
  ///
  /// **Dart Source:** `painting.dart:3558-3559`
  /// **Original:** `PathMetrics._(Path path, bool forceClosed)`
  internal init(_ path: Path, forceClosed: Bool) {
    _iterator = PathMetricIterator(
      flutter.swift_bridge.PathMeasureBridge(path.bridge, forceClosed)
    )
  }

  private let _iterator: PathMetricIterator

  /// Returns the iterator for this sequence.
  ///
  /// **Dart Source:** `painting.dart:3563-3564`
  /// **Original:** `Iterator<PathMetric> get iterator => _iterator;`
  public func makeIterator() -> PathMetricIterator {
    return _iterator
  }
}

// MARK: - PathMetricIterator
/// Used by PathMetrics to track iteration from one segment of a path to the
/// next for measurement.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `PathMetricIterator`
/// **Lines:** 3567-3597
///
/// DIFFERENCE FROM DART: Implements Swift IteratorProtocol instead of
/// Dart's Iterator interface. The `current` property throwing behavior is
/// replaced by returning nil from `next()`, which is the Swift idiom.
/// REASON: Swift IteratorProtocol uses next() -> Element? pattern.
public class PathMetricIterator: IteratorProtocol {
  public typealias Element = PathMetric

  /// Creates a PathMetricIterator wrapping a C++ PathMeasureBridge.
  ///
  /// **Dart Source:** `painting.dart:3570`
  /// **Original:** `PathMetricIterator._(this._pathMeasure)`
  internal init(_ pathMeasure: flutter.swift_bridge.PathMeasureBridge) {
    _pathMeasure = pathMeasure
  }

  internal let _pathMeasure: flutter.swift_bridge.PathMeasureBridge

  /// The current contour index, matching Dart's _PathMeasure.currentContourIndex.
  ///
  /// **Dart Source:** `painting.dart:3762`
  /// Starts at -1, incremented by moveNext/next().
  private var _currentContourIndex: Int32 = -1

  /// Advances to the next PathMetric and returns it, or nil if exhausted.
  ///
  /// **Dart Source:** `painting.dart:3588-3596`
  /// **Original:** `bool moveNext()`
  ///
  /// DIFFERENCE FROM DART: Returns PathMetric? instead of bool+current pattern.
  /// REASON: Swift IteratorProtocol uses next() -> Element? idiom.
  public func next() -> PathMetric? {
    if _pathMeasure.NextContour() {
      _currentContourIndex += 1
      return PathMetric(_pathMeasure, contourIndex: _currentContourIndex)
    }
    return nil
  }
}

// MARK: - PathMetric
/// Utilities for measuring a Path and extracting sub-paths.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `PathMetric`
/// **Lines:** 3599-3674
///
/// Iterate over the object returned by Path.computeMetrics to obtain
/// PathMetric objects. Callers that want to randomly access elements or
/// iterate multiple times should use `Array(path.computeMetrics())`, since
/// PathMetrics does not memoize.
///
/// Once created, the metrics are only valid for the path as it was specified
/// when Path.computeMetrics was called. If additional contours are added or
/// any contours are updated, the metrics need to be recomputed.
public class PathMetric: CustomStringConvertible {

  /// Creates a PathMetric from a PathMeasureBridge and contour index.
  ///
  /// **Dart Source:** `painting.dart:3613-3616`
  /// **Original:** `PathMetric._(this._measure)`
  internal init(_ measure: flutter.swift_bridge.PathMeasureBridge,
                contourIndex: Int32) {
    _measure = measure
    self.contourIndex = Int64(contourIndex)
    self.length = measure.GetLength(contourIndex)
    self.isClosed = measure.IsClosed(contourIndex)
  }

  /// Return the total length of the current contour.
  ///
  /// **Dart Source:** `painting.dart:3618-3623`
  /// **Original:** `final double length;`
  ///
  /// The length may be calculated from an approximation of the geometry
  /// originally added. For this reason, it is not recommended to rely on
  /// this property for mathematically correct lengths of common shapes.
  public let length: Double

  /// Whether the contour is closed.
  ///
  /// **Dart Source:** `painting.dart:3625-3631`
  /// **Original:** `final bool isClosed;`
  ///
  /// Returns true if the contour ends with a call to Path.close (which may
  /// have been implied when using methods like Path.addRect) or if
  /// `forceClosed` was specified as true in the call to Path.computeMetrics.
  /// Returns false otherwise.
  public let isClosed: Bool

  /// The zero-based index of the contour.
  ///
  /// **Dart Source:** `painting.dart:3633-3645`
  /// **Original:** `final int contourIndex;`
  ///
  /// Path objects are made up of zero or more contours. The first contour is
  /// created once a drawing command (e.g. Path.lineTo) is issued. A
  /// Path.moveTo command after a drawing command may create a new contour,
  /// although it may not if optimizations are applied that determine the move
  /// command did not actually result in moving the pen.
  ///
  /// This property is only valid with reference to its original iterator and
  /// the contours of the path at the time the path's metrics were computed. If
  /// additional contours were added or existing contours updated, this metric
  /// will be invalid for the current state of the path.
  public let contourIndex: Int64

  /// The C++ PathMeasureBridge backing this metric.
  private let _measure: flutter.swift_bridge.PathMeasureBridge

  /// Computes the position of the current contour at the given offset, and the
  /// angle of the path at that point.
  ///
  /// **Dart Source:** `painting.dart:3649-3661`
  /// **Original:** `Tangent? getTangentForOffset(double distance)`
  ///
  /// For example, calling this method with a distance of 1.41 for a line from
  /// 0.0,0.0 to 2.0,2.0 would give a point 1.0,1.0 and the angle 45 degrees
  /// (but in radians).
  ///
  /// Returns nil if the contour has zero length.
  ///
  /// The distance is clamped to the length of the current contour.
  public func getTangentForOffset(_ distance: Double) -> Tangent? {
    var values: (Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0)
    withUnsafeMutablePointer(to: &values) { ptr in
      ptr.withMemoryRebound(to: Float.self, capacity: 5) { floatPtr in
        _measure.GetPosTan(Int32(contourIndex), distance, floatPtr)
      }
    }
    // First value is success flag: 0 = failure, 1 = success
    if values.0 == 0.0 {
      return nil
    }
    return Tangent(
      Offset(Double(values.1), Double(values.2)),
      Offset(Double(values.3), Double(values.4))
    )
  }

  /// Given a start and end distance, return the intervening segment(s).
  ///
  /// **Dart Source:** `painting.dart:3663-3669`
  /// **Original:** `Path extractPath(double start, double end, {bool startWithMoveTo = true})`
  ///
  /// `start` and `end` are clamped to legal values (0..length).
  /// Begin the segment with a moveTo if `startWithMoveTo` is true.
  public func extractPath(_ start: Double, _ end: Double,
                           startWithMoveTo: Bool = true) -> Path {
    let pathBridge = flutter.swift_bridge.PathMeasureBridge.ExtractPath(
      _measure, Int32(contourIndex), start, end, startWithMoveTo
    )
    return Path(bridge: pathBridge!)
  }

  /// String representation of this PathMetric.
  ///
  /// **Dart Source:** `painting.dart:3671-3673`
  /// **Original:** `'PathMetric(length: $length, isClosed: $isClosed, contourIndex: $contourIndex)'`
  public var description: String {
    return "PathMetric(length: \(length), isClosed: \(isClosed), contourIndex: \(contourIndex))"
  }
}

// MARK: - FrameInfo
/// Information for a single frame of an animation.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `FrameInfo`
/// **Lines:** 2243-2305
///
/// To obtain an instance of the FrameInfo class, see Codec.getNextFrame.
///
/// The recipient of an instance of this class is responsible for calling
/// Image.dispose() on the image. To share the image with other interested
/// parties, use Image.clone().
///
/// DIFFERENCE FROM DART: Uses TimeInterval (Double, seconds) instead of Duration.
/// REASON: Swift uses TimeInterval (seconds) as the standard time representation;
/// Dart's Duration stores microseconds. A zero duration indicates the frame should
/// be shown indefinitely.
public struct FrameInfo {

  /// Creates a FrameInfo with the given duration and image.
  ///
  /// **Dart Source:** `painting.dart:2292`
  /// **Original:** `FrameInfo._({required this.duration, required this.image})`
  ///
  /// This is internal because FrameInfo is created by the engine (Codec),
  /// not by user code.
  internal init(duration: TimeInterval, image: Image) {
    self.duration = duration
    self.image = image
  }

  /// The duration this frame should be shown.
  ///
  /// **Dart Source:** `painting.dart:2294-2297`
  /// **Original:** `final Duration duration;`
  ///
  /// A zero duration indicates that the frame should be shown indefinitely.
  ///
  /// DIFFERENCE FROM DART: Uses TimeInterval (Double, seconds) instead of Duration.
  /// REASON: Swift uses TimeInterval (seconds) as its standard time type.
  public let duration: TimeInterval

  /// The Image object for this frame.
  ///
  /// **Dart Source:** `painting.dart:2299-2304`
  /// **Original:** `final Image image;`
  ///
  /// This object must be disposed by the recipient of this frame info.
  /// To share this image with other interested parties, use Image.clone().
  public let image: Image
}

// MARK: - Codec

/// A handle to an image codec.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `Codec` (abstract class)
/// **Lines:** 2307-2340
///
/// This class is created by the engine, and should not be instantiated
/// or extended directly.
///
/// To obtain an instance of the Codec interface, see
/// `instantiateImageCodec`.
///
/// DIFFERENCE FROM DART: Using protocol instead of abstract class
/// REASON: Swift doesn't have abstract classes; protocol provides equivalent
///         interface definition for concrete implementations to conform to
public protocol Codec: AnyObject {
  /// Number of frames in this image.
  ///
  /// **Dart Source:** `painting.dart:2315-2316`
  /// **Original:** `int get frameCount`
  var frameCount: Int { get }

  /// Number of times to repeat the animation.
  ///
  /// * 0 when the animation should be played once.
  /// * -1 for infinity repetitions.
  ///
  /// **Dart Source:** `painting.dart:2318-2322`
  /// **Original:** `int get repetitionCount`
  var repetitionCount: Int { get }

  /// Fetches the next animation frame.
  ///
  /// Wraps back to the first frame after returning the last frame.
  ///
  /// The returned future can complete with an error if the decoding has failed.
  ///
  /// The caller of this method is responsible for disposing the
  /// `FrameInfo.image` on the returned object.
  ///
  /// **Dart Source:** `painting.dart:2324-2332`
  /// **Original:** `Future<FrameInfo> getNextFrame()`
  ///
  /// DIFFERENCE FROM DART: Uses Swift async/throws instead of Future
  /// REASON: Swift's native async/await is the idiomatic equivalent of Dart's Future
  func getNextFrame() async throws -> FrameInfo

  /// Release the resources used by this object. The object is no longer usable
  /// after this method is called.
  ///
  /// **Dart Source:** `painting.dart:2334-2339`
  /// **Original:** `void dispose()`
  func dispose()
}

// MARK: - NativeCodec

/// Concrete implementation of the `Codec` protocol backed by C++ CodecBridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2342-2405`
/// **Original Name:** `_NativeCodec`
/// **Lines:** 2342-2405
///
/// This is the Swift equivalent of Dart's `_NativeCodec` class, which is the
/// concrete native implementation of the abstract `Codec` class. It wraps
/// a C++ `CodecBridge` that directly accesses the image generator for
/// synchronous frame decoding.
///
/// DIFFERENCE FROM DART: In Dart, `_NativeCodec` extends `NativeFieldWrapperClass1`
/// for FFI and uses async callbacks via task runners for `getNextFrame()`.
/// In Swift, we use `CodecBridge` with `SWIFT_SHARED_REFERENCE` for memory
/// management and synchronous frame decoding.
/// REASON: Swift doesn't use Dart FFI; the async path requires UIDartState
/// for task runner access, which is Dart VM specific.
public class NativeCodec: Codec {
  /// The C++ bridge object that handles native codec operations.
  internal let bridge: flutter.swift_bridge.CodecBridge

  /// Cached frame count (matches Dart's `int? _cachedFrameCount`).
  ///
  /// **Dart Source:** `painting.dart:2351`
  private var _cachedFrameCount: Int?

  /// Cached repetition count (matches Dart's `int? _cachedRepetitionCount`).
  ///
  /// **Dart Source:** `painting.dart:2359`
  private var _cachedRepetitionCount: Int?

  /// Creates a NativeCodec wrapping a CodecBridge.
  ///
  /// **Dart Source:** `painting.dart:2349`
  /// **Original:** `_NativeCodec._()`
  ///
  /// DIFFERENCE FROM DART: Takes a CodecBridge parameter instead of being
  /// created empty and having native wrapper set by C++.
  /// REASON: Swift creates the bridge directly rather than using Dart's
  /// NativeFieldWrapperClass1 pattern.
  internal init(_ bridge: flutter.swift_bridge.CodecBridge) {
    self.bridge = bridge
  }

  /// Number of frames in this image.
  ///
  /// **Dart Source:** `painting.dart:2353-2357`
  /// **Original:** `int get frameCount => _cachedFrameCount ??= _frameCount;`
  ///              `@Native<Int32 Function(Pointer<Void>)>(symbol: 'Codec::frameCount', isLeaf: true)`
  ///              `external int get _frameCount;`
  public var frameCount: Int {
    if let cached = _cachedFrameCount {
      return cached
    }
    let count = Int(bridge.GetFrameCount())
    _cachedFrameCount = count
    return count
  }

  /// Number of times to repeat the animation.
  ///
  /// * 0 when the animation should be played once.
  /// * -1 for infinity repetitions.
  ///
  /// **Dart Source:** `painting.dart:2361-2365`
  /// **Original:** `int get repetitionCount => _cachedRepetitionCount ??= _repetitionCount;`
  ///              `@Native<Int32 Function(Pointer<Void>)>(symbol: 'Codec::repetitionCount', isLeaf: true)`
  ///              `external int get _repetitionCount;`
  public var repetitionCount: Int {
    if let cached = _cachedRepetitionCount {
      return cached
    }
    let count = Int(bridge.GetRepetitionCount())
    _cachedRepetitionCount = count
    return count
  }

  /// Fetches the next animation frame.
  ///
  /// Wraps back to the first frame after returning the last frame.
  ///
  /// The caller of this method is responsible for disposing the
  /// `FrameInfo.image` on the returned object.
  ///
  /// **Dart Source:** `painting.dart:2367-2393`
  /// **Original:** `Future<FrameInfo> getNextFrame() async { ... }`
  ///
  /// DIFFERENCE FROM DART: Synchronous decode wrapped in async interface.
  /// The Dart version uses task runner callbacks through `_getNextFrame(callback)`.
  /// This version decodes synchronously via CodecBridge and returns the result.
  /// REASON: The async path requires UIDartState for task runner access,
  /// which is Dart VM specific. A future engine integration layer will
  /// provide the async path with GPU upload support.
  public func getNextFrame() async throws -> FrameInfo {
    let success = bridge.DecodeNextFrame()

    if !success {
      var errorBuffer = [CChar](repeating: 0, count: 256)
      bridge.GetLastError(&errorBuffer, Int32(errorBuffer.count))
      let errorMessage = String(cString: errorBuffer)
      if errorMessage.isEmpty {
        throw PaintingError.operationFailed("Codec failed to produce an image, possibly due to invalid image data.")
      }
      throw PaintingError.operationFailed(errorMessage)
    }

    // GetLastFrameImage() returns a retained ImageBridge*.
    // Swift's SWIFT_SHARED_REFERENCE will manage the reference via ARC.
    guard let imageBridge = bridge.GetLastFrameImage() else {
      throw PaintingError.operationFailed("Codec failed to produce an image, possibly due to invalid image data.")
    }

    let durationMs = bridge.GetLastFrameDurationMs()
    // Convert milliseconds to TimeInterval (seconds)
    let durationSeconds: TimeInterval = Double(durationMs) / 1000.0

    // Create Image wrapping the ImageBridge
    // (matches Dart: Image._(_Image image, image.width, image.height))
    let image = Image.wrap(imageBridge)

    return FrameInfo(
      duration: durationSeconds,
      image: image
    )
  }

  /// Release the resources used by this object. The object is no longer usable
  /// after this method is called.
  ///
  /// **Dart Source:** `painting.dart:2399-2401`
  /// **Original:** `@Native<Void Function(Pointer<Void>)>(symbol: 'Codec::dispose')`
  ///              `external void dispose();`
  public func dispose() {
    bridge.Dispose()
  }

  /// Returns a string representation of this codec.
  ///
  /// **Dart Source:** `painting.dart:2403-2404`
  /// **Original:** `String toString() => 'Codec(${_cachedFrameCount == null ? "" : "$_cachedFrameCount frames"})'`
  public var description: String {
    if let cachedCount = _cachedFrameCount {
      return "Codec(\(cachedCount) frames)"
    }
    return "Codec()"
  }
}

// MARK: - Vertices

/// A set of vertex data used by `Canvas.drawVertices`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:5410-5657`
/// **Original Name:** `Vertices`
///
/// Vertex data consists of a series of points in the canvas coordinate space.
/// Based on the `VertexMode`, these points are interpreted either as
/// independent triangles (`VertexMode.triangles`), as a sliding window of
/// points forming a chain of triangles each sharing one side with the next
/// (`VertexMode.triangleStrip`), or as a fan of triangles with a single shared
/// point (`VertexMode.triangleFan`).
///
/// Each point can be associated with a color. Each triangle is painted as a
/// gradient that blends between the three colors at the three points of that
/// triangle. If no colors are specified, transparent black is assumed for all
/// the points.
///
/// DIFFERENCE FROM DART: In Dart, Vertices extends NativeFieldWrapperClass1 for FFI.
/// In Swift, we use a C++ bridge (VerticesBridge) with SWIFT_SHARED_REFERENCE for
/// automatic memory management via Swift ARC.
/// REASON: Swift doesn't use Dart FFI; instead uses direct C++ interop.
public class Vertices {
  /// The C++ bridge object that handles native vertex operations.
  internal let bridge: flutter.swift_bridge.VerticesBridge

  /// Creates a set of vertex data for use with `Canvas.drawVertices`.
  ///
  /// **Dart Source:** `painting.dart:5489-5533`
  /// **Original:** `Vertices(VertexMode mode, List<Offset> positions, {List<Color>? colors, List<Offset>? textureCoordinates, List<int>? indices})`
  ///
  /// The `mode` parameter describes how the points should be interpreted: as
  /// independent triangles (`VertexMode.triangles`), as a sliding window of
  /// points forming a chain of triangles each sharing one side with the next
  /// (`VertexMode.triangleStrip`), or as a fan of triangles with a single
  /// shared point (`VertexMode.triangleFan`).
  ///
  /// The `positions` parameter provides the points in the canvas space that
  /// will be use to draw the triangles.
  ///
  /// The `colors` parameter, if specified, provides the color for each point in
  /// `positions`. Each triangle is painted as a gradient that blends between
  /// the three colors at the three points of that triangle.
  ///
  /// The `textureCoordinates` parameter, if specified, provides the points in
  /// the `Paint` image to sample for the corresponding points in `positions`.
  ///
  /// If the `colors` or `textureCoordinates` parameters are specified, they must
  /// be the same length as `positions`.
  ///
  /// The `indices` parameter specifies the order in which the points should be
  /// painted. If it is omitted (or present but empty), the points are processed
  /// in the order they are given in `positions`.
  ///
  /// DIFFERENCE FROM DART: Throws FlutterError instead of ArgumentError.
  /// REASON: Swift uses its own error types.
  public init(
    _ mode: VertexMode,
    _ positions: [Offset],
    colors: [Color]? = nil,
    textureCoordinates: [Offset]? = nil,
    indices: [Int]? = nil
  ) throws {
    // Validate colors length matches positions
    if let colors = colors, colors.count != positions.count {
      throw FlutterSwiftBridgeError.invalidArgument(
        "\"positions\" and \"colors\" lengths must match."
      )
    }
    // Validate textureCoordinates length matches positions
    if let textureCoordinates = textureCoordinates,
       textureCoordinates.count != positions.count {
      throw FlutterSwiftBridgeError.invalidArgument(
        "\"positions\" and \"textureCoordinates\" lengths must match."
      )
    }
    // Debug-only: validate indices are in range
    assert({
      if let indices = indices {
        for (index, value) in indices.enumerated() {
          if value >= positions.count {
            assertionFailure(
              "\"indices\" values must be valid indices in the positions list "
              + "(i.e. numbers in the range 0..\(positions.count - 1)), "
              + "but indices[\(index)] is \(value), which is too big."
            )
          }
        }
      }
      return true
    }())

    // Encode positions as flat Float32 array [x0, y0, x1, y1, ...]
    // Same as Dart's _encodePointList (painting.dart:4783-4795)
    var encodedPositions: [Float] = []
    encodedPositions.reserveCapacity(positions.count * 2)
    for point in positions {
      encodedPositions.append(Float(point.dx))
      encodedPositions.append(Float(point.dy))
    }

    // Encode texture coordinates as flat Float32 array
    var encodedTextureCoordinates: [Float]? = nil
    if let textureCoordinates = textureCoordinates {
      var encoded: [Float] = []
      encoded.reserveCapacity(textureCoordinates.count * 2)
      for point in textureCoordinates {
        encoded.append(Float(point.dx))
        encoded.append(Float(point.dy))
      }
      encodedTextureCoordinates = encoded
    }

    // Encode colors as Int32 ARGB values
    // Same as Dart's _encodeColorList (painting.dart:4774-4781)
    var encodedColors: [Int32]? = nil
    if let colors = colors {
      var encoded: [Int32] = []
      encoded.reserveCapacity(colors.count)
      for color in colors {
        encoded.append(Int32(bitPattern: UInt32(color.toARGB32())))
      }
      encodedColors = encoded
    }

    // Encode indices as UInt16 array
    var encodedIndices: [UInt16]? = nil
    if let indices = indices {
      var encoded: [UInt16] = []
      encoded.reserveCapacity(indices.count)
      for idx in indices {
        encoded.append(UInt16(idx))
      }
      encodedIndices = encoded
    }

    // Call C++ bridge to create the vertices
    bridge = encodedPositions.withUnsafeBufferPointer { positionsPtr in
      return Vertices._createBridge(
        mode: mode,
        positions: positionsPtr.baseAddress!,
        positionCount: Int32(encodedPositions.count),
        textureCoordinates: encodedTextureCoordinates,
        colors: encodedColors,
        indices: encodedIndices
      )
    }

    if !bridge.IsValid() {
      throw FlutterSwiftBridgeError.invalidArgument("Invalid configuration for vertices.")
    }
  }

  /// Creates a set of vertex data for use with `Canvas.drawVertices`, using the
  /// encoding expected by the Flutter engine.
  ///
  /// **Dart Source:** `painting.dart:5579-5614`
  /// **Original:** `Vertices.raw(VertexMode mode, Float32List positions, {Int32List? colors, Float32List? textureCoordinates, Uint16List? indices})`
  ///
  /// The `mode` parameter describes how the points should be interpreted.
  ///
  /// The `positions` parameter provides the points in the canvas space. Each
  /// point is represented as two numbers in the list, the first giving the x
  /// coordinate and the second giving the y coordinate.
  ///
  /// The `colors` parameter, if specified, provides the color for each point in
  /// `positions` as ARGB with 8 bit color channels.
  ///
  /// The `textureCoordinates` parameter, if specified, provides the points in
  /// the `Paint` image to sample. Must be the same length as `positions`.
  ///
  /// DIFFERENCE FROM DART: Throws FlutterError instead of ArgumentError.
  /// REASON: Swift uses its own error types.
  public init(
    raw mode: VertexMode,
    positions: [Float],
    colors: [Int32]? = nil,
    textureCoordinates: [Float]? = nil,
    indices: [UInt16]? = nil
  ) throws {
    // Validate positions has even number of entries
    if positions.count % 2 != 0 {
      throw FlutterSwiftBridgeError.invalidArgument(
        "\"positions\" must have an even number of entries (each coordinate is an x,y pair)."
      )
    }
    // Validate colors length matches positions
    if let colors = colors, colors.count * 2 != positions.count {
      throw FlutterSwiftBridgeError.invalidArgument(
        "\"positions\" and \"colors\" lengths must match."
      )
    }
    // Validate textureCoordinates length matches positions
    if let textureCoordinates = textureCoordinates,
       textureCoordinates.count != positions.count {
      throw FlutterSwiftBridgeError.invalidArgument(
        "\"positions\" and \"textureCoordinates\" lengths must match."
      )
    }
    // Debug-only: validate indices are in range
    assert({
      if let indices = indices {
        for (index, value) in indices.enumerated() {
          if Int(value) * 2 >= positions.count {
            assertionFailure(
              "\"indices\" values must be valid indices in the positions list "
              + "(i.e. numbers in the range 0..\(positions.count / 2 - 1)), "
              + "but indices[\(index)] is \(value), which is too big."
            )
          }
        }
      }
      return true
    }())

    // Call C++ bridge with raw data
    bridge = positions.withUnsafeBufferPointer { positionsPtr in
      Vertices._createBridgeRaw(
        mode: mode,
        positions: positionsPtr.baseAddress!,
        positionCount: Int32(positions.count),
        textureCoordinates: textureCoordinates,
        colors: colors,
        indices: indices
      )
    }

    if !bridge.IsValid() {
      throw FlutterSwiftBridgeError.invalidArgument("Invalid configuration for vertices.")
    }
  }

  /// Release the resources used by this object. The object is no longer usable
  /// after this method is called.
  ///
  /// **Dart Source:** `painting.dart:5626-5635`
  /// **Original:** `void dispose()`
  public func dispose() {
    assert(!_disposed, "Vertices already disposed.")
    assert({
      _disposed = true
      return true
    }())
    bridge.Dispose()
  }

  /// Whether this reference to the underlying vertex data is `dispose`d.
  ///
  /// **Dart Source:** `painting.dart:5644-5656`
  /// **Original:** `bool get debugDisposed`
  ///
  /// This only returns a valid value if asserts are enabled, and must not be
  /// used otherwise.
  ///
  /// DIFFERENCE FROM DART: Throws FlutterError instead of StateError.
  /// REASON: Swift uses its own error types.
  public var debugDisposed: Bool {
    var disposed: Bool? = nil
    assert({
      disposed = _disposed
      return true
    }())
    guard let disposed = disposed else {
      fatalError("Vertices.debugDisposed is only available when asserts are enabled.")
    }
    return disposed
  }

  // MARK: - Private

  /// Tracks disposed state (only in debug/assert mode).
  ///
  /// **Dart Source:** `painting.dart:5642`
  /// **Original:** `bool _disposed = false;`
  private var _disposed: Bool = false

  /// Helper to create bridge with encoded Offset/Color arrays.
  private static func _createBridge(
    mode: VertexMode,
    positions: UnsafePointer<Float>,
    positionCount: Int32,
    textureCoordinates: [Float]?,
    colors: [Int32]?,
    indices: [UInt16]?
  ) -> flutter.swift_bridge.VerticesBridge {
    // Handle optional texture coordinates
    if let textureCoordinates = textureCoordinates {
      return textureCoordinates.withUnsafeBufferPointer { tcPtr in
        if let colors = colors {
          return colors.withUnsafeBufferPointer { colorsPtr in
            if let indices = indices {
              return indices.withUnsafeBufferPointer { indicesPtr in
                flutter.swift_bridge.VerticesBridge(
                  Int32(mode.rawValue),
                  positions, positionCount,
                  tcPtr.baseAddress, Int32(textureCoordinates.count),
                  colorsPtr.baseAddress, Int32(colors.count),
                  indicesPtr.baseAddress, Int32(indices.count)
                )
              }
            } else {
              return flutter.swift_bridge.VerticesBridge(
                Int32(mode.rawValue),
                positions, positionCount,
                tcPtr.baseAddress, Int32(textureCoordinates.count),
                colorsPtr.baseAddress, Int32(colors.count),
                nil, 0
              )
            }
          }
        } else {
          if let indices = indices {
            return indices.withUnsafeBufferPointer { indicesPtr in
              flutter.swift_bridge.VerticesBridge(
                Int32(mode.rawValue),
                positions, positionCount,
                tcPtr.baseAddress, Int32(textureCoordinates.count),
                nil, 0,
                indicesPtr.baseAddress, Int32(indices.count)
              )
            }
          } else {
            return flutter.swift_bridge.VerticesBridge(
              Int32(mode.rawValue),
              positions, positionCount,
              tcPtr.baseAddress, Int32(textureCoordinates.count),
              nil, 0,
              nil, 0
            )
          }
        }
      }
    } else {
      if let colors = colors {
        return colors.withUnsafeBufferPointer { colorsPtr in
          if let indices = indices {
            return indices.withUnsafeBufferPointer { indicesPtr in
              flutter.swift_bridge.VerticesBridge(
                Int32(mode.rawValue),
                positions, positionCount,
                nil, 0,
                colorsPtr.baseAddress, Int32(colors.count),
                indicesPtr.baseAddress, Int32(indices.count)
              )
            }
          } else {
            return flutter.swift_bridge.VerticesBridge(
              Int32(mode.rawValue),
              positions, positionCount,
              nil, 0,
              colorsPtr.baseAddress, Int32(colors.count),
              nil, 0
            )
          }
        }
      } else {
        if let indices = indices {
          return indices.withUnsafeBufferPointer { indicesPtr in
            flutter.swift_bridge.VerticesBridge(
              Int32(mode.rawValue),
              positions, positionCount,
              nil, 0,
              nil, 0,
              indicesPtr.baseAddress, Int32(indices.count)
            )
          }
        } else {
          return flutter.swift_bridge.VerticesBridge(
            Int32(mode.rawValue),
            positions, positionCount,
            nil, 0,
            nil, 0,
            nil, 0
          )
        }
      }
    }
  }

  /// Helper to create bridge with raw Float/Int32/UInt16 arrays.
  private static func _createBridgeRaw(
    mode: VertexMode,
    positions: UnsafePointer<Float>,
    positionCount: Int32,
    textureCoordinates: [Float]?,
    colors: [Int32]?,
    indices: [UInt16]?
  ) -> flutter.swift_bridge.VerticesBridge {
    // Reuse the same helper - raw data has same encoding
    return _createBridge(
      mode: mode,
      positions: positions,
      positionCount: positionCount,
      textureCoordinates: textureCoordinates,
      colors: colors,
      indices: indices
    )
  }
}

// MARK: - Picture

/// An object representing a sequence of recorded graphical operations.
///
// MARK: - PictureEventCallback

/// Callback signature for `Picture.onCreate` and `Picture.onDispose`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7284`
/// **Original:** `typedef PictureEventCallback = void Function(Picture picture);`
public typealias PictureEventCallback = (any Picture) -> Void

/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7286-7349`
/// **Original Name:** `Picture` (abstract class)
///
/// To create a `Picture`, use a `PictureRecorder`.
///
/// A `Picture` can be placed in a `Scene` using a `SceneBuilder`, via
/// the `SceneBuilder.addPicture` method. A `Picture` can also be
/// drawn into a `Canvas`, using the `Canvas.drawPicture` method.
///
/// DIFFERENCE FROM DART: Using protocol instead of abstract class
/// REASON: Swift doesn't have abstract classes; protocol provides equivalent
///         interface definition for concrete implementations to conform to
public protocol Picture: AnyObject {
  /// A callback that is invoked to report a picture creation.
  ///
  /// **Dart Source:** `painting.dart:7294-7299`
  /// **Original:** `static PictureEventCallback? onCreate;`
  ///
  /// It's preferred to use `MemoryAllocations` in flutter/foundation.dart
  /// than to use `onCreate` directly because `MemoryAllocations`
  /// allows multiple callbacks.
  static var onCreate: ((any Picture) -> Void)? { get set }

  /// A callback that is invoked to report the picture disposal.
  ///
  /// **Dart Source:** `painting.dart:7301-7306`
  /// **Original:** `static PictureEventCallback? onDispose;`
  ///
  /// It's preferred to use `MemoryAllocations` in flutter/foundation.dart
  /// than to use `onDispose` directly because `MemoryAllocations`
  /// allows multiple callbacks.
  static var onDispose: ((any Picture) -> Void)? { get set }

  /// Creates an image from this picture.
  ///
  /// **Dart Source:** `painting.dart:7308-7313`
  /// **Original:** `Future<Image> toImage(int width, int height);`
  ///
  /// The returned image will be `width` pixels wide and `height` pixels high.
  /// The picture is rasterized within the 0 (left), 0 (top), `width` (right),
  /// `height` (bottom) bounds. Content outside these bounds is clipped.
  ///
  /// DIFFERENCE FROM DART: Uses Swift async/throws instead of Dart Future.
  /// REASON: Swift concurrency model; throws replaces Future error propagation.
  func toImage(width: Int, height: Int) async throws -> Image

  /// Synchronously creates a handle to an image of this picture.
  ///
  /// **Dart Source:** `painting.dart:7315-7332`
  /// **Original:** `Image toImageSync(int width, int height);`
  ///
  /// The returned image will be `width` pixels wide and `height` pixels high.
  /// The picture is rasterized within the 0 (left), 0 (top), `width` (right),
  /// `height` (bottom) bounds. Content outside these bounds is clipped.
  ///
  /// The image object is created and returned synchronously, but is rasterized
  /// asynchronously. If the rasterization fails, an exception will be thrown
  /// when the image is drawn to a `Canvas`.
  ///
  /// If a GPU context is available, this image will be created as GPU resident
  /// and not copied back to the host. This means the image will be more
  /// efficient to draw.
  ///
  /// If no GPU context is available, the image will be rasterized on the CPU.
  func toImageSync(width: Int, height: Int) -> Image

  /// Release the resources used by this object. The object is no longer usable
  /// after this method is called.
  ///
  /// **Dart Source:** `painting.dart:7334-7336`
  /// **Original:** `void dispose();`
  func dispose()

  /// Whether this reference to the underlying picture is `dispose`d.
  ///
  /// **Dart Source:** `painting.dart:7338-7342`
  /// **Original:** `bool get debugDisposed;`
  ///
  /// This only returns a valid value if asserts are enabled, and must not be
  /// used otherwise.
  var debugDisposed: Bool { get }

  /// Returns the approximate number of bytes allocated for this object.
  ///
  /// **Dart Source:** `painting.dart:7344-7348`
  /// **Original:** `int get approximateBytesUsed;`
  ///
  /// The actual size of this picture may be larger, particularly if it contains
  /// references to image or other large objects.
  var approximateBytesUsed: Int { get }
}

// MARK: - NativePicture

/// Backing storage for Picture protocol static callbacks.
///
/// Swift protocols cannot have stored static properties, so we store
/// the onCreate/onDispose callbacks here and provide them via
/// NativePicture's static conformance.
nonisolated(unsafe) private var _pictureOnCreate: ((any Picture) -> Void)? = nil
nonisolated(unsafe) private var _pictureOnDispose: ((any Picture) -> Void)? = nil

/// Concrete Picture implementation that wraps a PictureBridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7351-7428`
/// **Original Name:** `_NativePicture`
///
/// This class wraps the C++ PictureBridge which holds an sk_sp<DisplayList>.
/// The DisplayList is built from a CanvasBridge's DisplayListBuilder when
/// recording ends (via NativePictureRecorder.endRecording).
///
/// DIFFERENCE FROM DART: In Dart, `_NativePicture` extends `NativeFieldWrapperClass1`
/// and uses `@Native` for FFI calls. In Swift, we wrap a C++ `PictureBridge` via
/// SWIFT_SHARED_REFERENCE for automatic memory management.
/// REASON: Swift doesn't use Dart FFI; instead uses direct C++ interop.
///
/// DIFFERENCE FROM DART: `toImage` is not yet implemented (requires rendering pipeline
/// integration with snapshot delegates and task runners that are Dart VM specific).
/// `toImageSync` IS implemented using CPU rasterization via PictureBridge.ToImage.
/// REASON: `toImage` relies on UIDartState for task runner access; `toImageSync` uses
/// direct CPU rasterization which does not require task runners.
public class NativePicture: Picture, NativePictureProvider {
  /// The C++ bridge object that holds the DisplayList.
  internal let bridge: flutter.swift_bridge.PictureBridge

  /// Whether this picture has been disposed.
  ///
  /// **Dart Source:** `painting.dart:7409`
  /// **Original:** `bool _disposed = false;`
  private var _disposed: Bool = false

  /// Creates a NativePicture from a CanvasBridge, building the PictureBridge internally.
  ///
  /// **Dart Source:** `painting.dart:7352-7356`
  /// **Original:** `_NativePicture._()`
  ///
  /// DIFFERENCE FROM DART: In Dart, the constructor is private and the engine
  /// creates the wrapper. In Swift, we create the PictureBridge from the
  /// CanvasBridge's DisplayListBuilder internally.
  internal init(canvasBridge: flutter.swift_bridge.CanvasBridge) {
    self.bridge = flutter.swift_bridge.PictureBridge(canvasBridge)
  }

  // MARK: - Static Callbacks

  /// A callback that is invoked to report a picture creation.
  ///
  /// **Dart Source:** `painting.dart:7294-7299`
  /// **Original:** `static PictureEventCallback? onCreate;`
  public static var onCreate: ((any Picture) -> Void)? {
    get { _pictureOnCreate }
    set { _pictureOnCreate = newValue }
  }

  /// A callback that is invoked to report the picture disposal.
  ///
  /// **Dart Source:** `painting.dart:7301-7306`
  /// **Original:** `static PictureEventCallback? onDispose;`
  public static var onDispose: ((any Picture) -> Void)? {
    get { _pictureOnDispose }
    set { _pictureOnDispose = newValue }
  }

  // MARK: - Methods

  /// Creates an image from this picture.
  ///
  /// **Dart Source:** `painting.dart:7358-7373`
  /// **Original:** `Future<Image> toImage(int width, int height)`
  ///
  /// DIFFERENCE FROM DART: Not yet implemented. The Dart version uses
  /// `_futurize` and `Picture::toImage` which requires UIDartState's
  /// snapshot delegate and task runners for GPU rasterization.
  /// REASON: Requires engine integration layer for async rendering pipeline.
  public func toImage(width: Int, height: Int) async throws -> Image {
    assert(!_disposed)
    guard width > 0 && height > 0 else {
      throw PaintingError.operationFailed("Invalid image dimensions.")
    }
    // TODO: Implement when engine integration layer provides async rendering.
    // The Dart version calls Picture::toImage which uses
    // UIDartState::CreateGPUObject and snapshot_delegate->MakeRasterSnapshot.
    fatalError("Picture.toImage requires engine integration (snapshot delegate + task runners)")
  }

  /// Synchronously creates a handle to an image of this picture.
  ///
  /// **Dart Source:** `painting.dart:7378-7388`
  /// **Original:** `Image toImageSync(int width, int height)`
  ///
  /// DIFFERENCE FROM DART: The Dart version uses `Picture::toImageSync` which creates
  /// a DeferredImage via the snapshot delegate for GPU-backed textures. Our implementation
  /// uses CPU rasterization via PictureBridge.ToImage instead.
  /// REASON: We bypass UIDartState/snapshot delegate and rasterize directly on the CPU.
  public func toImageSync(width: Int, height: Int) -> Image {
    assert(!_disposed)
    guard width > 0 && height > 0 else {
      fatalError("Invalid image dimensions.")
    }
    let imagePtr = bridge.ToImage(Int32(width), Int32(height))
    return Image.wrap(imagePtr!)
  }

  /// Release the resources used by this object.
  ///
  /// **Dart Source:** `painting.dart:7393-7402`
  /// **Original:** `void dispose()`
  public func dispose() {
    assert(!_disposed)
    _disposed = true
    NativePicture.onDispose?(self)
    bridge.Dispose()
  }

  /// Whether this picture has been disposed.
  ///
  /// **Dart Source:** `painting.dart:7411-7420`
  /// **Original:** `bool get debugDisposed`
  ///
  /// DIFFERENCE FROM DART: In Dart, this property only works when asserts
  /// are enabled and throws StateError otherwise. In Swift, we always return
  /// the value since Swift doesn't have the same assert-only semantics.
  /// REASON: Swift's assert stripping works differently than Dart's.
  public var debugDisposed: Bool {
    _disposed
  }

  /// Returns the approximate number of bytes allocated for this object.
  ///
  /// **Dart Source:** `painting.dart:7422-7424`
  /// **Original:** `@Native<Uint64 Function(Pointer<Void>)>(symbol: 'Picture::GetAllocationSize')`
  public var approximateBytesUsed: Int {
    Int(bridge.GetAllocationSize())
  }

  // MARK: - NativePictureProvider

  /// Returns an opaque pointer to the underlying DisplayList.
  ///
  /// Used by NativeCanvas.drawPicture to render this picture's recorded
  /// operations into a canvas.
  internal var displayListPtr: UnsafeRawPointer? {
    let ptr = bridge.GetDisplayListPtr()
    return ptr != nil ? UnsafeRawPointer(ptr) : nil
  }

  // MARK: - CustomStringConvertible

  /// Returns a string representation of this picture.
  ///
  /// **Dart Source:** `painting.dart:7426-7427`
  /// **Original:** `String toString() => 'Picture';`
  public var description: String {
    "Picture"
  }
}

// MARK: - PictureRecorder

/// Records a `Picture` containing a sequence of graphical operations.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7430-7468`
/// **Original Name:** `PictureRecorder` (abstract class)
/// **Lines:** 7430-7503
///
/// To begin recording, construct a `Canvas` to record the commands.
/// To end recording, use the `PictureRecorder.endRecording` method.
///
/// ## Use with the Flutter framework
///
/// The Flutter framework's `RendererBinding` provides a hook for creating
/// `PictureRecorder` objects (`RendererBinding.createPictureRecorder`) that
/// allows tests to hook into the scene creation logic. When creating a
/// `PictureRecorder` and `Canvas` that will be used with a `PictureLayer` as
/// part of the `Scene` in the context of the Flutter framework, consider
/// calling `RendererBinding.createPictureRecorder` instead of calling the
/// `PictureRecorder` constructor directly.
///
/// This does not apply when using a canvas to generate a bitmap for other
/// purposes, e.g. for generating a PNG image using `Picture.toImage`.
///
/// DIFFERENCE FROM DART: Declared as a protocol instead of abstract class.
/// REASON: Swift doesn't have abstract classes; protocol provides equivalent interface.
/// The factory constructor `PictureRecorder()` in Dart creates a `_NativePictureRecorder`;
/// in Swift, the concrete implementation will be provided by the C++ bridge layer.
public protocol PictureRecorder: AnyObject {
  /// Whether this object is currently recording commands.
  ///
  /// **Dart Source:** `painting.dart:7453-7460`
  /// **Original:** `bool get isRecording;`
  ///
  /// Specifically, this returns true if a `Canvas` object has been
  /// created to record commands and recording has not yet ended via a
  /// call to `endRecording`, and false if either this
  /// `PictureRecorder` has not yet been associated with a `Canvas`,
  /// or the `endRecording` method has already been called.
  var isRecording: Bool { get }

  /// Finishes recording graphical operations.
  ///
  /// **Dart Source:** `painting.dart:7462-7467`
  /// **Original:** `Picture endRecording();`
  ///
  /// Returns a picture containing the graphical operations that have been
  /// recorded thus far. After calling this function, both the picture recorder
  /// and the canvas objects are invalid and cannot be used further.
  func endRecording() -> any Picture
}

extension PictureRecorder {
  /// Returns a string representation of this PictureRecorder.
  ///
  /// **Dart Source:** `painting.dart:7502`
  /// **Original:** `String toString() => 'PictureRecorder(recording: $isRecording)';`
  ///
  /// Note: This is from `_NativePictureRecorder.toString()` in the Dart source.
  public var description: String {
    "PictureRecorder(recording: \(isRecording))"
  }
}

// MARK: - PictureRecorders Factory

/// Factory namespace for creating PictureRecorder instances.
///
/// **Dart Source:** `painting.dart:7444`
/// **Original:** `factory PictureRecorder() = _NativePictureRecorder;`
///
/// In Dart, `PictureRecorder` has a factory constructor that returns a
/// `_NativePictureRecorder`. In Swift, protocols cannot have factory
/// initializers, so this enum serves as the factory namespace.
public enum PictureRecorders {
  /// Creates a new `PictureRecorder`.
  ///
  /// Equivalent to Dart's `PictureRecorder()` factory constructor.
  public static func create() -> any PictureRecorder {
    return NativePictureRecorder()
  }
}

// MARK: - NativePictureRecorder

/// Concrete PictureRecorder implementation that manages a NativeCanvas.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7470-7503`
/// **Original Name:** `_NativePictureRecorder`
/// **Lines:** 7470-7503
///
/// In Dart, `_NativePictureRecorder` extends `NativeFieldWrapperClass1` and uses
/// `@Native` methods to create the recorder and end recording. In Swift, this class
/// directly manages a `NativeCanvas` and creates a `PictureBridge` from the canvas's
/// `CanvasBridge` when recording ends.
///
/// DIFFERENCE FROM DART: No separate C++ PictureRecorderBridge is needed.
/// The `PictureBridge` constructor already accepts a `CanvasBridge*` and builds
/// the DisplayList from it, which is equivalent to the Dart `_endRecording` native call.
/// REASON: The C++ PictureBridge encapsulates the endRecording logic directly.
///
/// Usage pattern (mirrors Dart):
/// ```swift
/// let recorder = NativePictureRecorder()
/// let canvas = NativeCanvas(recorder: recorder)
/// // ... draw on canvas ...
/// let picture = recorder.endRecording()
/// ```
public class NativePictureRecorder: PictureRecorder {
  /// The canvas currently recording to this recorder.
  ///
  /// **Dart Source:** `painting.dart:7499`
  /// **Original:** `_NativeCanvas? _canvas;`
  ///
  /// Non-nil while recording is in progress. Set by `NativeCanvas.init(recorder:)`
  /// and cleared by `endRecording()`.
  internal var _canvas: NativeCanvas?

  /// Creates a new idle NativePictureRecorder.
  ///
  /// **Dart Source:** `painting.dart:7471-7473`
  /// **Original:** `_NativePictureRecorder() { _constructor(); }`
  ///
  /// DIFFERENCE FROM DART: In Dart, the constructor calls a native `_constructor()`
  /// method (`PictureRecorder::Create`) which allocates the C++ PictureRecorder.
  /// In Swift, no C++ object is created until `endRecording()` is called, because
  /// the PictureBridge constructor handles building the DisplayList from the CanvasBridge.
  /// REASON: The C++ recorder object is not needed; PictureBridge does the work.
  public init() {}

  /// Whether this object is currently recording commands.
  ///
  /// **Dart Source:** `painting.dart:7478-7479`
  /// **Original:** `bool get isRecording => _canvas != null;`
  public var isRecording: Bool {
    _canvas != nil
  }

  /// Finishes recording graphical operations.
  ///
  /// **Dart Source:** `painting.dart:7481-7494`
  /// **Original:**
  /// ```dart
  /// Picture endRecording() {
  ///   if (_canvas == null) throw StateError('...');
  ///   final _NativePicture picture = _NativePicture._();
  ///   _endRecording(picture);
  ///   _canvas!._recorder = null;
  ///   _canvas = null;
  ///   Picture.onCreate?.call(picture);
  ///   return picture;
  /// }
  /// ```
  ///
  /// Returns a picture containing the graphical operations that have been
  /// recorded thus far. After calling this function, both the picture recorder
  /// and the canvas objects are invalid and cannot be used further.
  public func endRecording() -> any Picture {
    guard let canvas = _canvas else {
      fatalError("PictureRecorder did not start recording.")
    }

    // Create the NativePicture from the CanvasBridge — PictureBridge is built internally.
    // This is equivalent to Dart's `_endRecording(picture)` which calls
    // `PictureRecorder::endRecording` in C++.
    let picture = NativePicture(canvasBridge: canvas.bridge)

    // Invalidate the canvas (equivalent to Dart's `_canvas!._recorder = null`)
    canvas.bridge.Invalidate()
    _canvas = nil

    // Invoke the onCreate handler (equivalent to Dart's `Picture.onCreate?.call(picture)`)
    NativePicture.onCreate?(picture)

    return picture
  }
}

// MARK: - ImmutableBuffer

/// A handle to a read-only byte buffer that is managed by the engine.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7701-7801`
/// **Original Name:** `ImmutableBuffer`
/// **Lines:** 7701-7801
///
/// The creator of this object is responsible for calling `dispose` when it is
/// no longer needed.
///
/// DIFFERENCE FROM DART: The Dart version extends `NativeFieldWrapperClass1`
/// and uses async factory methods with `_futurize` pattern. The Swift version
/// wraps a C++ `ImmutableBufferBridge` via `SWIFT_SHARED_REFERENCE` and
/// provides synchronous factory methods.
/// REASON: Swift has no Dart VM or NativeFieldWrapperClass1.
public class ImmutableBuffer {
  // C++ bridge object - Swift ARC handles lifetime via SWIFT_SHARED_REFERENCE
  internal let bridge: flutter.swift_bridge.ImmutableBufferBridge

  /// Private initializer wrapping an existing bridge object.
  private init(bridge: flutter.swift_bridge.ImmutableBufferBridge) {
    self.bridge = bridge
    self._length = Int64(bridge.Length())
  }

  /// The tracked length of the buffer data.
  ///
  /// **Dart Source:** `painting.dart:7761-7763`
  /// **Original:** `int _length;`
  private var _length: Int64

  /// Creates an ImmutableBuffer by copying data from a `[UInt8]`.
  ///
  /// **Dart Source:** `painting.dart:7710-7715`
  /// **Original:** `static Future<ImmutableBuffer> fromUint8List(Uint8List list)`
  ///
  /// DIFFERENCE FROM DART: Synchronous initializer instead of `Future`-based
  /// static method. Also exposed as an init rather than a static factory.
  /// REASON: Swift idiom - initializers are preferred over static factory methods
  /// for straightforward construction. The Dart version uses `_futurize` with
  /// Dart VM callbacks which is not applicable in Swift.
  public init(fromUint8List list: [UInt8]) {
    let bridge = list.withUnsafeBufferPointer { bufferPtr -> flutter.swift_bridge.ImmutableBufferBridge in
      let baseAddress = bufferPtr.baseAddress
      return flutter.swift_bridge.ImmutableBufferBridge(baseAddress, list.count)
    }
    self.bridge = bridge
    self._length = Int64(bridge.Length())
  }

  /// Creates a copy of the data from a `[UInt8]` suitable for internal use
  /// in the engine.
  ///
  /// **Dart Source:** `painting.dart:7710-7715`
  /// **Original:** `static Future<ImmutableBuffer> fromUint8List(Uint8List list)`
  ///
  /// DIFFERENCE FROM DART: Synchronous instead of `Future`-based.
  /// REASON: The Dart version uses `_futurize` with Dart VM callbacks.
  public static func fromUint8List(_ list: [UInt8]) -> ImmutableBuffer {
    return ImmutableBuffer(fromUint8List: list)
  }

  /// Create a buffer from the asset with the given key.
  ///
  /// **Dart Source:** `painting.dart:7720-7735`
  /// **Original:** `static Future<ImmutableBuffer> fromAsset(String assetKey)`
  ///
  /// DIFFERENCE FROM DART: Synchronous and throws on failure instead of
  /// returning a Future that completes with an exception.
  /// REASON: Swift has no `_futurize` pattern.
  ///
  /// - Throws: An error if the asset cannot be found.
  public static func fromAsset(_ assetKey: String) throws -> ImmutableBuffer {
    let encodedKey = assetKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? assetKey
    let bridge = encodedKey.withCString { cStr -> flutter.swift_bridge.ImmutableBufferBridge in
      return flutter.swift_bridge.ImmutableBufferBridge.CreateFromAsset(cStr)
    }
    let buffer = ImmutableBuffer(bridge: bridge)
    if buffer.length == 0 {
      throw ImmutableBufferError.assetNotFound(assetKey)
    }
    return buffer
  }

  /// Create a buffer from the file at the given path.
  ///
  /// **Dart Source:** `painting.dart:7740-7750`
  /// **Original:** `static Future<ImmutableBuffer> fromFilePath(String path)`
  ///
  /// DIFFERENCE FROM DART: Synchronous and throws on failure.
  /// REASON: Swift has no `_futurize` pattern.
  ///
  /// - Throws: An error if the file cannot be found or read.
  public static func fromFilePath(_ path: String) throws -> ImmutableBuffer {
    let bridge = path.withCString { cStr -> flutter.swift_bridge.ImmutableBufferBridge in
      return flutter.swift_bridge.ImmutableBufferBridge.CreateFromFile(cStr)
    }
    let buffer = ImmutableBuffer(bridge: bridge)
    if buffer.length == 0 {
      throw ImmutableBufferError.fileNotFound(path)
    }
    return buffer
  }

  /// The length, in bytes, of the underlying data.
  ///
  /// **Dart Source:** `painting.dart:7761-7763`
  /// **Original:** `int get length => _length;`
  public var length: Int64 {
    return _length
  }

  /// Whether `dispose()` has been called.
  ///
  /// **Dart Source:** `painting.dart:7767-7777`
  /// **Original:** `bool get debugDisposed`
  ///
  /// DIFFERENCE FROM DART: Available in all builds (not debug-only).
  /// REASON: Swift doesn't have Dart's `late` + `assert(() { ... }())` pattern.
  private var _debugDisposed: Bool = false

  /// Whether `dispose()` has been called.
  ///
  /// **Dart Source:** `painting.dart:7770-7777`
  public var debugDisposed: Bool {
    return _debugDisposed
  }

  /// Release the resources used by this object. The object is no longer usable
  /// after this method is called.
  ///
  /// **Dart Source:** `painting.dart:7788-7795`
  /// **Original:** `void dispose()`
  public func dispose() {
    assert(!_debugDisposed, "ImmutableBuffer was already disposed.")
    _debugDisposed = true
    bridge.Dispose()
  }
}

/// Errors that can occur when creating an `ImmutableBuffer`.
///
/// DIFFERENCE FROM DART: Dart uses generic `Exception('...')`.
/// Swift uses a typed error enum for better error handling.
/// REASON: Swift idiom - typed errors are preferred over generic exceptions.
public enum ImmutableBufferError: Error, CustomStringConvertible {
  /// **Dart Source:** `painting.dart:7731-7732`
  case assetNotFound(String)

  /// **Dart Source:** `painting.dart:7745-7746`
  case fileNotFound(String)

  public var description: String {
    switch self {
    case .assetNotFound(let key):
      return "Asset not found: \(key)"
    case .fileNotFound(let path):
      return "Could not load file at \(path)."
    }
  }
}


// MARK: - Canvas

/// An interface for recording graphical operations.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:5702-6557`
/// **Original Name:** `Canvas` (abstract class)
///
/// `Canvas` objects are used in creating `Picture` objects, which can
/// themselves be used with a `SceneBuilder` to build a `Scene`. In
/// normal usage, however, this is all handled by the framework.
///
/// A canvas has a current transformation matrix which is applied to all
/// operations. Initially, the transformation matrix is the identity transform.
/// It can be modified using the `translate`, `scale`, `rotate`, `skew`,
/// and `transform` methods.
///
/// A canvas also has a current clip region which is applied to all operations.
/// Initially, the clip region is infinite. It can be modified using the
/// `clipRect`, `clipRRect`, and `clipPath` methods.
///
/// The current transform and clip can be saved and restored using the stack
/// managed by the `save`, `saveLayer`, and `restore` methods.
///
/// DIFFERENCE FROM DART: Canvas is a protocol in Swift instead of an abstract class.
/// REASON: Swift uses protocols for defining interfaces; the concrete implementation
/// (equivalent to Dart's `_NativeCanvas`) will conform to this protocol.
public protocol Canvas: AnyObject {

  // MARK: - Save/Restore Stack

  /// Saves a copy of the current transform and clip on the save stack.
  ///
  /// **Dart Source:** `painting.dart:5746-5754`
  /// **Original:** `void save();`
  ///
  /// Call `restore` to pop the save stack.
  ///
  /// See also:
  ///
  ///  * `saveLayer`, which does the same thing but additionally also groups the
  ///    commands done until the matching `restore`.
  func save()

  /// Saves a copy of the current transform and clip on the save stack, and then
  /// creates a new group which subsequent calls will become a part of.
  ///
  /// **Dart Source:** `painting.dart:5756-5865`
  /// **Original:** `void saveLayer(Rect? bounds, Paint paint);`
  ///
  /// When the save stack is later popped, the group will be flattened into a
  /// layer and have the given `paint`'s `Paint.colorFilter` and
  /// `Paint.blendMode` applied.
  ///
  /// This lets you create composite effects, for example making a group of
  /// drawing commands semi-transparent. Without using `saveLayer`, each part
  /// of the group would be painted individually, so where they overlap would
  /// be darker than where they do not. By using `saveLayer` to group them
  /// together, they can be drawn with an opaque color at first, and then the
  /// entire group can be made transparent using the `saveLayer`'s paint.
  ///
  /// Call `restore` to pop the save stack and apply the paint to the group.
  ///
  /// ## Performance considerations
  ///
  /// Generally speaking, `saveLayer` is relatively expensive.
  ///
  /// There are several different hardware architectures for GPUs, but most of
  /// them involve batching commands and reordering them for performance. When
  /// layers are used, they cause the rendering pipeline to have to switch render
  /// target (from one layer to another). Render target switches can flush the
  /// GPU's command buffer, which typically means that optimizations that one
  /// could get with larger batching are lost. Render target switches also
  /// generate a lot of memory churn because the GPU needs to copy out the
  /// current frame buffer contents from the part of memory that's optimized for
  /// writing, and then needs to copy it back in once the previous render target
  /// (layer) is restored.
  func saveLayer(_ bounds: Rect?, _ paint: Paint)

  /// Pops the current save stack, if there is anything to pop.
  /// Otherwise, does nothing.
  ///
  /// **Dart Source:** `painting.dart:5867-5874`
  /// **Original:** `void restore();`
  ///
  /// Use `save` and `saveLayer` to push state onto the stack.
  ///
  /// If the state was pushed with `saveLayer`, then this call will also
  /// cause the new layer to be composited into the previous layer.
  func restore()

  /// Restores the save stack to a previous level as might be obtained from
  /// `getSaveCount`.
  ///
  /// **Dart Source:** `painting.dart:5876-5885`
  /// **Original:** `void restoreToCount(int count);`
  ///
  /// If `count` is less than 1, the stack is restored to its initial state.
  /// If `count` is greater than the current `getSaveCount` then nothing happens.
  ///
  /// Use `save` and `saveLayer` to push state onto the stack.
  ///
  /// If any of the state stack levels restored by this call were pushed with
  /// `saveLayer`, then this call will also cause those layers to be composited
  /// into their previous layers.
  func restoreToCount(_ count: Int)

  /// Returns the number of items on the save stack, including the
  /// initial state.
  ///
  /// **Dart Source:** `painting.dart:5887-5893`
  /// **Original:** `int getSaveCount();`
  ///
  /// This means it returns 1 for a clean canvas, and that each call to
  /// `save` and `saveLayer` increments it, and that each matching call to
  /// `restore` decrements it.
  ///
  /// This number cannot go below 1.
  func getSaveCount() -> Int

  // MARK: - Transform

  /// Add a translation to the current transform, shifting the coordinate space
  /// horizontally by the first argument and vertically by the second argument.
  ///
  /// **Dart Source:** `painting.dart:5895-5897`
  /// **Original:** `void translate(double dx, double dy);`
  func translate(_ dx: Double, _ dy: Double)

  /// Add an axis-aligned scale to the current transform, scaling by the first
  /// argument in the horizontal direction and the second in the vertical
  /// direction.
  ///
  /// **Dart Source:** `painting.dart:5899-5905`
  /// **Original:** `void scale(double sx, [double? sy]);`
  ///
  /// If `sy` is nil, `sx` will be used for the scale in both directions.
  func scale(_ sx: Double, _ sy: Double?)

  /// Add a rotation to the current transform. The argument is in radians
  /// clockwise.
  ///
  /// **Dart Source:** `painting.dart:5907-5908`
  /// **Original:** `void rotate(double radians);`
  func rotate(_ radians: Double)

  /// Add an axis-aligned skew to the current transform, with the first argument
  /// being the horizontal skew in rise over run units clockwise around the
  /// origin, and the second argument being the vertical skew in rise over run
  /// units clockwise around the origin.
  ///
  /// **Dart Source:** `painting.dart:5910-5914`
  /// **Original:** `void skew(double sx, double sy);`
  func skew(_ sx: Double, _ sy: Double)

  /// Multiply the current transform by the specified 4x4 transformation matrix
  /// specified as a list of values in column-major order.
  ///
  /// **Dart Source:** `painting.dart:5916-5918`
  /// **Original:** `void transform(Float64List matrix4);`
  func transform(_ matrix4: [Double])

  /// Returns the current transform including the combined result of all
  /// transform methods executed since the creation of this `Canvas` object,
  /// and respecting the save/restore history.
  ///
  /// **Dart Source:** `painting.dart:5920-5928`
  /// **Original:** `Float64List getTransform();`
  ///
  /// Methods that can change the current transform include `translate`,
  /// `scale`, `rotate`, `skew`, and `transform`. The `restore` method
  /// can also modify the current transform by restoring it to the same
  /// value it had before its associated `save` or `saveLayer` call.
  func getTransform() -> [Double]

  // MARK: - Clip

  /// Reduces the clip region to the intersection of the current clip and the
  /// given rectangle.
  ///
  /// **Dart Source:** `painting.dart:5930-5943`
  /// **Original:** `void clipRect(Rect rect, {ClipOp clipOp = ClipOp.intersect, bool doAntiAlias = true});`
  ///
  /// If `doAntiAlias` is true, then the clip will be anti-aliased.
  ///
  /// If multiple draw commands intersect with the clip boundary, this can result
  /// in incorrect blending at the clip boundary. See `saveLayer` for a
  /// discussion of how to address that.
  ///
  /// Use `ClipOp.difference` to subtract the provided rectangle from the
  /// current clip.
  func clipRect(_ rect: Rect, clipOp: ClipOp, doAntiAlias: Bool)

  /// Reduces the clip region to the intersection of the current clip and the
  /// given rounded rectangle.
  ///
  /// **Dart Source:** `painting.dart:5945-5955`
  /// **Original:** `void clipRRect(RRect rrect, {bool doAntiAlias = true});`
  ///
  /// If `doAntiAlias` is true, then the clip will be anti-aliased.
  ///
  /// If multiple draw commands intersect with the clip boundary, this can result
  /// in incorrect blending at the clip boundary. See `saveLayer` for a
  /// discussion of how to address that and some examples of using `clipRRect`.
  func clipRRect(_ rrect: RRect, doAntiAlias: Bool)

  /// Reduces the clip region to the intersection of the current clip and the
  /// given rounded superellipse.
  ///
  /// **Dart Source:** `painting.dart:5957-5967`
  /// **Original:** `void clipRSuperellipse(RSuperellipse rsuperellipse, {bool doAntiAlias = true});`
  ///
  /// If `doAntiAlias` is true, then the clip will be anti-aliased.
  ///
  /// If multiple draw commands intersect with the clip boundary, this can result
  /// in incorrect blending at the clip boundary. See `saveLayer` for a
  /// discussion of how to address that and some examples of using
  /// `clipRSuperellipse`.
  func clipRSuperellipse(_ rsuperellipse: RSuperellipse, doAntiAlias: Bool)

  /// Reduces the clip region to the intersection of the current clip and the
  /// given `Path`.
  ///
  /// **Dart Source:** `painting.dart:5969-5979`
  /// **Original:** `void clipPath(Path path, {bool doAntiAlias = true});`
  ///
  /// If `doAntiAlias` is true, then the clip will be anti-aliased.
  ///
  /// If multiple draw commands intersect with the clip boundary, this can result
  /// in incorrect blending at the clip boundary. See `saveLayer` for a
  /// discussion of how to address that.
  func clipPath(_ path: Path, doAntiAlias: Bool)

  /// Returns the conservative bounds of the combined result of all clip methods
  /// executed within the current save stack of this `Canvas` object, as measured
  /// in the local coordinate space under which rendering operations are currently
  /// performed.
  ///
  /// **Dart Source:** `painting.dart:5981-6033`
  /// **Original:** `Rect getLocalClipBounds();`
  ///
  /// The combined clip results are rounded out to an integer pixel boundary
  /// before they are transformed back into the local coordinate space which
  /// accounts for the pixel roundoff in rendering operations, particularly
  /// when antialiasing. Because the `Picture` may eventually be rendered into
  /// a scene within the context of transforming widgets or layers, the result
  /// may thus be overly conservative due to premature rounding. Using the
  /// `getDestinationClipBounds` method combined with the external transforms
  /// and rounding in the true device coordinate system will produce more
  /// accurate results, but this value may provide a more convenient
  /// approximation to compare rendering operations to the established clip.
  func getLocalClipBounds() -> Rect

  /// Returns the conservative bounds of the combined result of all clip methods
  /// executed within the current save stack of this `Canvas` object, as measured
  /// in the destination coordinate space in which the `Picture` will be rendered.
  ///
  /// **Dart Source:** `painting.dart:6035-6049`
  /// **Original:** `Rect getDestinationClipBounds();`
  ///
  /// Unlike `getLocalClipBounds`, the bounds are not rounded out to an integer
  /// pixel boundary as the Destination coordinate space may not represent pixels
  /// if the `Picture` being constructed will be further transformed when it is
  /// rendered or added to a scene.
  func getDestinationClipBounds() -> Rect

  // MARK: - Drawing Methods

  /// Paints the given `Color` onto the canvas, applying the given
  /// `BlendMode`, with the given color being the source and the background
  /// being the destination.
  ///
  /// **Dart Source:** `painting.dart:6051-6054`
  /// **Original:** `void drawColor(Color color, BlendMode blendMode);`
  func drawColor(_ color: Color, _ blendMode: BlendMode)

  /// Draws a line between the given points using the given paint.
  ///
  /// **Dart Source:** `painting.dart:6056-6063`
  /// **Original:** `void drawLine(Offset p1, Offset p2, Paint paint);`
  ///
  /// The line is stroked, the value of the `Paint.style` is ignored for this
  /// call.
  ///
  /// The `p1` and `p2` arguments are interpreted as offsets from the origin.
  func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint)

  /// Fills the canvas with the given `Paint`.
  ///
  /// **Dart Source:** `painting.dart:6065-6069`
  /// **Original:** `void drawPaint(Paint paint);`
  ///
  /// To fill the canvas with a solid color and blend mode, consider
  /// `drawColor` instead.
  func drawPaint(_ paint: Paint)

  /// Draws a rectangle with the given `Paint`.
  ///
  /// **Dart Source:** `painting.dart:6071-6076`
  /// **Original:** `void drawRect(Rect rect, Paint paint);`
  ///
  /// Whether the rectangle is filled or stroked (or both) is controlled by
  /// `Paint.style`.
  func drawRect(_ rect: Rect, _ paint: Paint)

  /// Draws a rounded rectangle with the given `Paint`.
  ///
  /// **Dart Source:** `painting.dart:6078-6083`
  /// **Original:** `void drawRRect(RRect rrect, Paint paint);`
  ///
  /// Whether the rectangle is filled or stroked (or both) is controlled by
  /// `Paint.style`.
  func drawRRect(_ rrect: RRect, _ paint: Paint)

  /// Draws a shape consisting of the difference between two rounded rectangles
  /// with the given `Paint`.
  ///
  /// **Dart Source:** `painting.dart:6085-6090`
  /// **Original:** `void drawDRRect(RRect outer, RRect inner, Paint paint);`
  ///
  /// Whether this shape is filled or stroked (or both) is controlled by
  /// `Paint.style`.
  ///
  /// This shape is almost but not quite entirely unlike an annulus.
  func drawDRRect(_ outer: RRect, _ inner: RRect, _ paint: Paint)

  /// Draws a rounded superellipse with the given `Paint`.
  ///
  /// **Dart Source:** `painting.dart:6092-6097`
  /// **Original:** `void drawRSuperellipse(RSuperellipse rsuperellipse, Paint paint);`
  ///
  /// The shape is filled, and the value of the `Paint.style` is ignored for
  /// this call.
  func drawRSuperellipse(_ rsuperellipse: RSuperellipse, _ paint: Paint)

  /// Draws an axis-aligned oval that fills the given axis-aligned rectangle
  /// with the given `Paint`.
  ///
  /// **Dart Source:** `painting.dart:6099-6105`
  /// **Original:** `void drawOval(Rect rect, Paint paint);`
  ///
  /// Whether the oval is filled or stroked (or both) is controlled by
  /// `Paint.style`.
  func drawOval(_ rect: Rect, _ paint: Paint)

  /// Draws a circle centered at the point given by the first argument and
  /// that has the radius given by the second argument, with the `Paint` given
  /// in the third argument.
  ///
  /// **Dart Source:** `painting.dart:6107-6114`
  /// **Original:** `void drawCircle(Offset c, double radius, Paint paint);`
  ///
  /// Whether the circle is filled or stroked (or both) is controlled by
  /// `Paint.style`.
  func drawCircle(_ c: Offset, _ radius: Double, _ paint: Paint)

  /// Draw an arc scaled to fit inside the given rectangle.
  ///
  /// **Dart Source:** `painting.dart:6116-6130`
  /// **Original:** `void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter, Paint paint);`
  ///
  /// It starts from `startAngle` radians around the oval up to
  /// `startAngle` + `sweepAngle` radians around the oval, with zero radians
  /// being the point on the right hand side of the oval that crosses the
  /// horizontal line that intersects the center of the rectangle and with
  /// positive angles going clockwise around the oval. If `useCenter` is true,
  /// the arc is closed back to the center, forming a circle sector. Otherwise,
  /// the arc is not closed, forming a circle segment.
  ///
  /// This method is optimized for drawing arcs and should be faster than
  /// `Path.arcTo`.
  func drawArc(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint)

  /// Draws the given `Path` with the given `Paint`.
  ///
  /// **Dart Source:** `painting.dart:6132-6137`
  /// **Original:** `void drawPath(Path path, Paint paint);`
  ///
  /// Whether this shape is filled or stroked (or both) is controlled by
  /// `Paint.style`. If the path is filled, then sub-paths within it are
  /// implicitly closed (see `Path.close`).
  func drawPath(_ path: Path, _ paint: Paint)

  /// Draws the given `Image` into the canvas with its top-left corner at the
  /// given `Offset`.
  ///
  /// **Dart Source:** `painting.dart:6139-6141`
  /// **Original:** `void drawImage(Image image, Offset offset, Paint paint);`
  ///
  /// The image is composited into the canvas using the given `Paint`.
  func drawImage(_ image: Image, _ offset: Offset, _ paint: Paint)

  /// Draws the subset of the given image described by the `src` argument into
  /// the canvas in the axis-aligned rectangle given by the `dst` argument.
  ///
  /// **Dart Source:** `painting.dart:6143-6152`
  /// **Original:** `void drawImageRect(Image image, Rect src, Rect dst, Paint paint);`
  ///
  /// This might sample from outside the `src` rect by up to half the width of
  /// an applied filter.
  ///
  /// Multiple calls to this method with different arguments (from the same
  /// image) can be batched into a single call to `drawAtlas` to improve
  /// performance.
  func drawImageRect(_ image: Image, _ src: Rect, _ dst: Rect, _ paint: Paint)

  /// Draws the given `Image` into the canvas using the given `Paint`.
  ///
  /// **Dart Source:** `painting.dart:6154-6167`
  /// **Original:** `void drawImageNine(Image image, Rect center, Rect dst, Paint paint);`
  ///
  /// The image is drawn in nine portions described by splitting the image by
  /// drawing two horizontal lines and two vertical lines, where the `center`
  /// argument describes the rectangle formed by the four points where these
  /// four lines intersect each other. (This forms a 3-by-3 grid of regions,
  /// the center region being described by the `center` argument.)
  ///
  /// The four regions in the corners are drawn, without scaling, in the four
  /// corners of the destination rectangle described by `dst`. The remaining
  /// five regions are drawn by stretching them to fit such that they exactly
  /// cover the destination rectangle while maintaining their relative positions.
  func drawImageNine(_ image: Image, _ center: Rect, _ dst: Rect, _ paint: Paint)

  /// Draw the given picture onto the canvas.
  ///
  /// **Dart Source:** `painting.dart:6169-6171`
  /// **Original:** `void drawPicture(Picture picture);`
  ///
  /// To create a picture, see `PictureRecorder`.
  func drawPicture(_ picture: any Picture)

  /// Draws the text in the given `Paragraph` into this canvas at the given
  /// `Offset`.
  ///
  /// **Dart Source:** `painting.dart:6173-6193`
  /// **Original:** `void drawParagraph(Paragraph paragraph, Offset offset);`
  ///
  /// The `Paragraph` object must have had `Paragraph.layout` called on it first.
  ///
  /// To align the text, set the `textAlign` on the `ParagraphStyle` object
  /// passed to the `ParagraphBuilder` constructor. For more details see
  /// `TextAlign` and the discussion at `ParagraphStyle`.
  func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset)

  /// Draws a sequence of points according to the given `PointMode`.
  ///
  /// **Dart Source:** `painting.dart:6195-6206`
  /// **Original:** `void drawPoints(PointMode pointMode, List<Offset> points, Paint paint);`
  ///
  /// The `points` argument is interpreted as offsets from the origin.
  ///
  /// The `paint` is used for each point (`PointMode.points`) or line
  /// (`PointMode.lines` or `PointMode.polygon`), ignoring `Paint.style`.
  ///
  /// See also:
  ///
  ///  * `drawRawPoints`, which takes `points` as a `[Float]` rather than a
  ///    `[Offset]`.
  func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint)

  /// Draws a sequence of points according to the given `PointMode`.
  ///
  /// **Dart Source:** `painting.dart:6208-6220`
  /// **Original:** `void drawRawPoints(PointMode pointMode, Float32List points, Paint paint);`
  ///
  /// The `points` argument is interpreted as a list of pairs of floating point
  /// numbers, where each pair represents an x and y offset from the origin.
  ///
  /// The `paint` is used for each point (`PointMode.points`) or line
  /// (`PointMode.lines` or `PointMode.polygon`), ignoring `Paint.style`.
  ///
  /// See also:
  ///
  ///  * `drawPoints`, which takes `points` as a `[Offset]` rather than a
  ///    `[Float]`.
  func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint)

  /// Draws a set of `Vertices` onto the canvas as one or more triangles.
  ///
  /// **Dart Source:** `painting.dart:6222-6250`
  /// **Original:** `void drawVertices(Vertices vertices, BlendMode blendMode, Paint paint);`
  ///
  /// The `Paint.color` property specifies the default color to use for the
  /// triangles.
  ///
  /// The `Paint.shader` property, if set, overrides the color entirely,
  /// replacing it with the colors from the specified `ImageShader`, `Gradient`,
  /// or other shader.
  ///
  /// The `blendMode` parameter is used to control how the colors in the
  /// `vertices` are combined with the colors in the `paint`. If there are no
  /// colors specified in `vertices` then the `blendMode` has no effect. If
  /// there are colors in the `vertices`, then the color taken from the
  /// `Paint.shader` or `Paint.color` in the `paint` is blended with the colors
  /// specified in the `vertices` using the `blendMode` parameter.
  func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint)

  /// Draws many parts of an image - the `atlas` - onto the canvas.
  ///
  /// **Dart Source:** `painting.dart:6252-6391`
  /// **Original:** `void drawAtlas(Image atlas, List<RSTransform> transforms, List<Rect> rects, List<Color>? colors, BlendMode? blendMode, Rect? cullRect, Paint paint);`
  ///
  /// This method allows for optimization when you want to draw many parts of an
  /// image onto the canvas, such as when using sprites or zooming. It is more
  /// efficient than using multiple calls to `drawImageRect` and provides more
  /// functionality to individually transform each image part by a separate
  /// rotation or scale and blend or modulate those parts with a solid color.
  ///
  /// The method takes a list of `Rect` objects that each define a piece of the
  /// `atlas` image to be drawn independently. Each `Rect` is associated with an
  /// `RSTransform` entry in the `transforms` list which defines the location,
  /// rotation, and (uniform) scale with which to draw that portion of the image.
  ///
  /// The length of the `transforms` and `rects` lists must be equal and
  /// if the `colors` argument is not nil then it must either be empty or
  /// have the same length as the other two lists.
  func drawAtlas(
    _ atlas: Image,
    _ transforms: [RSTransform],
    _ rects: [Rect],
    _ colors: [Color]?,
    _ blendMode: BlendMode?,
    _ cullRect: Rect?,
    _ paint: Paint
  )

  /// Draws many parts of an image - the `atlas` - onto the canvas.
  ///
  /// **Dart Source:** `painting.dart:6393-6548`
  /// **Original:** `void drawRawAtlas(Image atlas, Float32List rstTransforms, Float32List rects, Int32List? colors, BlendMode? blendMode, Rect? cullRect, Paint paint);`
  ///
  /// This method allows for optimization when you want to draw many parts of an
  /// image onto the canvas. It is also more efficient than `drawAtlas` as the
  /// data in the arguments is already packed in a format that can be directly
  /// used by the rendering code.
  ///
  /// The `rstTransforms` argument is interpreted as a list of four-tuples, with
  /// each tuple being (`RSTransform.scos`, `RSTransform.ssin`,
  /// `RSTransform.tx`, `RSTransform.ty`).
  ///
  /// The `rects` argument is interpreted as a list of four-tuples, with each
  /// tuple being (`Rect.left`, `Rect.top`, `Rect.right`, `Rect.bottom`).
  ///
  /// The `colors` argument, which can be nil, is interpreted as a list of
  /// 32-bit colors, with the same packing as `Color.value`. If the `colors`
  /// argument is not nil then the `blendMode` argument must also not be nil.
  func drawRawAtlas(
    _ atlas: Image,
    _ rstTransforms: [Float],
    _ rects: [Float],
    _ colors: [Int32]?,
    _ blendMode: BlendMode?,
    _ cullRect: Rect?,
    _ paint: Paint
  )

  /// Draws a shadow for a `Path` representing the given material elevation.
  ///
  /// **Dart Source:** `painting.dart:6550-6556`
  /// **Original:** `void drawShadow(Path path, Color color, double elevation, bool transparentOccluder);`
  ///
  /// The `transparentOccluder` argument should be true if the occluding object
  /// is not opaque.
  func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool)
}

// MARK: - Canvas Protocol Default Parameters

/// Extension providing convenience methods with default parameter values for Canvas.
///
/// **Dart Source:** `painting.dart:5930-5979`
///
/// DIFFERENCE FROM DART: Swift protocols cannot have default parameter values.
/// REASON: Default parameter values in Dart named parameters are provided via
/// extension methods that call the full-parameter version.
public extension Canvas {

  /// Reduces the clip region to the intersection of the current clip and the
  /// given rectangle, using `ClipOp.intersect` and anti-aliasing by default.
  ///
  /// **Dart Source:** `painting.dart:5930-5943`
  func clipRect(_ rect: Rect) {
    clipRect(rect, clipOp: .intersect, doAntiAlias: true)
  }

  /// Reduces the clip region to the intersection of the current clip and the
  /// given rectangle, with the given `ClipOp` and anti-aliasing by default.
  ///
  /// **Dart Source:** `painting.dart:5930-5943`
  func clipRect(_ rect: Rect, clipOp: ClipOp) {
    clipRect(rect, clipOp: clipOp, doAntiAlias: true)
  }

  /// Reduces the clip region to the intersection of the current clip and the
  /// given rounded rectangle, with anti-aliasing by default.
  ///
  /// **Dart Source:** `painting.dart:5945-5955`
  func clipRRect(_ rrect: RRect) {
    clipRRect(rrect, doAntiAlias: true)
  }

  /// Reduces the clip region to the intersection of the current clip and the
  /// given rounded superellipse, with anti-aliasing by default.
  ///
  /// **Dart Source:** `painting.dart:5957-5967`
  func clipRSuperellipse(_ rsuperellipse: RSuperellipse) {
    clipRSuperellipse(rsuperellipse, doAntiAlias: true)
  }

  /// Reduces the clip region to the intersection of the current clip and the
  /// given `Path`, with anti-aliasing by default.
  ///
  /// **Dart Source:** `painting.dart:5969-5979`
  func clipPath(_ path: Path) {
    clipPath(path, doAntiAlias: true)
  }
}

// MARK: - NativeCanvas

/// Concrete Canvas implementation that wraps a CanvasBridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:6559-7281`
/// **Original Name:** `_NativeCanvas`
///
/// This class records graphical operations into a DisplayListBuilder via
/// the C++ CanvasBridge. The recorded operations are replayed when the
/// associated Picture is rendered.
///
/// DIFFERENCE FROM DART: In Dart, `_NativeCanvas` extends `NativeFieldWrapperClass1`
/// and uses `@Native` for FFI calls. In Swift, we wrap a C++ `CanvasBridge` via
/// SWIFT_SHARED_REFERENCE for automatic memory management.
/// REASON: Swift doesn't use Dart FFI; instead uses direct C++ interop.
public class NativeCanvas: Canvas {
  /// The C++ bridge object that holds the DisplayListBuilder.
  internal let bridge: flutter.swift_bridge.CanvasBridge

  /// Creates a NativeCanvas with the given cull rect bounds.
  ///
  /// **Dart Source:** `painting.dart:6560-6568`
  /// **Original:** `_NativeCanvas(PictureRecorder recorder, [Rect? cullRect])`
  ///
  /// DIFFERENCE FROM DART: In Dart, the Canvas constructor takes a PictureRecorder
  /// and optionally a cull rect. In Swift, the canvas creates its own
  /// DisplayListBuilder directly. The PictureRecorder retrieves the builder
  /// via `GetDisplayListBuilderPtr()`.
  /// REASON: Simplifies the bridge by not requiring PictureRecorder to be passed.
  public init(cullRect: Rect? = nil) {
    let rect = cullRect ?? Rect.fromLTRB(-1e9, -1e9, 1e9, 1e9)
    self.bridge = flutter.swift_bridge.CanvasBridge(
      rect.left, rect.top, rect.right, rect.bottom
    )
  }

  /// Creates a NativeCanvas associated with a PictureRecorder.
  ///
  /// **Dart Source:** `painting.dart:6560-6568`
  /// **Original:**
  /// ```dart
  /// _NativeCanvas(PictureRecorder recorder, [Rect? cullRect]) {
  ///   if (recorder.isRecording) throw ArgumentError(...);
  ///   _recorder = recorder as _NativePictureRecorder;
  ///   _recorder!._canvas = this;
  ///   ...
  /// }
  /// ```
  ///
  /// Links the canvas to the recorder so that `recorder.endRecording()`
  /// can build the Picture from this canvas's recorded operations.
  public convenience init(recorder: NativePictureRecorder, cullRect: Rect? = nil) {
    guard !recorder.isRecording else {
      fatalError("\"recorder\" must not already be associated with another Canvas.")
    }
    self.init(cullRect: cullRect)
    recorder._canvas = self
  }

  // MARK: - Save/Restore Stack

  public func save() {
    bridge.Save()
  }

  public func saveLayer(_ bounds: Rect?, _ paint: Paint) {
    let hasBounds = bounds != nil
    let left = bounds?.left ?? 0
    let top = bounds?.top ?? 0
    let right = bounds?.right ?? 0
    let bottom = bounds?.bottom ?? 0

    paint.withDataPointer { paintData in
      bridge.SaveLayer(
        hasBounds, left, top, right, bottom,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func restore() {
    bridge.Restore()
  }

  public func restoreToCount(_ count: Int) {
    bridge.RestoreToCount(Int32(count))
  }

  public func getSaveCount() -> Int {
    return Int(bridge.GetSaveCount())
  }

  // MARK: - Transform

  public func translate(_ dx: Double, _ dy: Double) {
    bridge.Translate(dx, dy)
  }

  public func scale(_ sx: Double, _ sy: Double?) {
    bridge.Scale(sx, sy ?? sx)
  }

  public func rotate(_ radians: Double) {
    bridge.Rotate(radians)
  }

  public func skew(_ sx: Double, _ sy: Double) {
    bridge.Skew(sx, sy)
  }

  public func transform(_ matrix4: [Double]) {
    precondition(matrix4.count == 16, "\"matrix4\" must have 16 entries.")
    matrix4.withUnsafeBufferPointer { buffer in
      bridge.Transform(buffer.baseAddress!)
    }
  }

  public func getTransform() -> [Double] {
    var result = [Double](repeating: 0, count: 16)
    result.withUnsafeMutableBufferPointer { buffer in
      bridge.GetTransform(buffer.baseAddress!)
    }
    return result
  }

  // MARK: - Clip

  public func clipRect(_ rect: Rect, clipOp: ClipOp, doAntiAlias: Bool) {
    bridge.ClipRect(
      rect.left, rect.top, rect.right, rect.bottom,
      Int32(clipOp.rawValue), doAntiAlias
    )
  }

  public func clipRRect(_ rrect: RRect, doAntiAlias: Bool) {
    let rrectData: [Float] = [
      Float(rrect.left), Float(rrect.top), Float(rrect.right), Float(rrect.bottom),
      Float(rrect.tlRadiusX), Float(rrect.tlRadiusY),
      Float(rrect.trRadiusX), Float(rrect.trRadiusY),
      Float(rrect.brRadiusX), Float(rrect.brRadiusY),
      Float(rrect.blRadiusX), Float(rrect.blRadiusY),
    ]
    rrectData.withUnsafeBufferPointer { buffer in
      bridge.ClipRRect(buffer.baseAddress!, doAntiAlias)
    }
  }

  public func clipRSuperellipse(_ rsuperellipse: RSuperellipse, doAntiAlias: Bool) {
    bridge.ClipRSuperellipse(
      rsuperellipse.left, rsuperellipse.top,
      rsuperellipse.right, rsuperellipse.bottom,
      rsuperellipse.tlRadiusX, rsuperellipse.tlRadiusY,
      rsuperellipse.trRadiusX, rsuperellipse.trRadiusY,
      rsuperellipse.brRadiusX, rsuperellipse.brRadiusY,
      rsuperellipse.blRadiusX, rsuperellipse.blRadiusY,
      doAntiAlias
    )
  }

  public func clipPath(_ path: Path, doAntiAlias: Bool) {
    bridge.ClipPath(path.bridge, doAntiAlias)
  }

  public func getLocalClipBounds() -> Rect {
    var bounds = [Double](repeating: 0, count: 4)
    bounds.withUnsafeMutableBufferPointer { buffer in
      bridge.GetLocalClipBounds(buffer.baseAddress!)
    }
    return Rect.fromLTRB(bounds[0], bounds[1], bounds[2], bounds[3])
  }

  public func getDestinationClipBounds() -> Rect {
    var bounds = [Double](repeating: 0, count: 4)
    bounds.withUnsafeMutableBufferPointer { buffer in
      bridge.GetDestinationClipBounds(buffer.baseAddress!)
    }
    return Rect.fromLTRB(bounds[0], bounds[1], bounds[2], bounds[3])
  }

  // MARK: - Drawing Methods

  public func drawColor(_ color: Color, _ blendMode: BlendMode) {
    bridge.DrawColor(Int32(color.toARGB32()), Int32(blendMode.rawValue))
  }

  public func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawLine(
        p1.dx, p1.dy, p2.dx, p2.dy,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawPaint(_ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawPaint(
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawRect(_ rect: Rect, _ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawRect(
        rect.left, rect.top, rect.right, rect.bottom,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawRRect(_ rrect: RRect, _ paint: Paint) {
    let rrectData: [Float] = [
      Float(rrect.left), Float(rrect.top), Float(rrect.right), Float(rrect.bottom),
      Float(rrect.tlRadiusX), Float(rrect.tlRadiusY),
      Float(rrect.trRadiusX), Float(rrect.trRadiusY),
      Float(rrect.brRadiusX), Float(rrect.brRadiusY),
      Float(rrect.blRadiusX), Float(rrect.blRadiusY),
    ]
    rrectData.withUnsafeBufferPointer { buffer in
      paint.withDataPointer { paintData in
        bridge.DrawRRect(
          buffer.baseAddress!,
          paintData,
          paint.shaderBridgePtr,
          paint.colorFilterBridgePtr,
          paint.imageFilterBridgePtr
        )
      }
    }
  }

  public func drawDRRect(_ outer: RRect, _ inner: RRect, _ paint: Paint) {
    let outerData: [Float] = [
      Float(outer.left), Float(outer.top), Float(outer.right), Float(outer.bottom),
      Float(outer.tlRadiusX), Float(outer.tlRadiusY),
      Float(outer.trRadiusX), Float(outer.trRadiusY),
      Float(outer.brRadiusX), Float(outer.brRadiusY),
      Float(outer.blRadiusX), Float(outer.blRadiusY),
    ]
    let innerData: [Float] = [
      Float(inner.left), Float(inner.top), Float(inner.right), Float(inner.bottom),
      Float(inner.tlRadiusX), Float(inner.tlRadiusY),
      Float(inner.trRadiusX), Float(inner.trRadiusY),
      Float(inner.brRadiusX), Float(inner.brRadiusY),
      Float(inner.blRadiusX), Float(inner.blRadiusY),
    ]
    outerData.withUnsafeBufferPointer { outerBuf in
      innerData.withUnsafeBufferPointer { innerBuf in
        paint.withDataPointer { paintData in
          bridge.DrawDRRect(
            outerBuf.baseAddress!, innerBuf.baseAddress!,
            paintData,
            paint.shaderBridgePtr,
            paint.colorFilterBridgePtr,
            paint.imageFilterBridgePtr
          )
        }
      }
    }
  }

  public func drawRSuperellipse(_ rsuperellipse: RSuperellipse, _ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawRSuperellipse(
        rsuperellipse.left, rsuperellipse.top,
        rsuperellipse.right, rsuperellipse.bottom,
        rsuperellipse.tlRadiusX, rsuperellipse.tlRadiusY,
        rsuperellipse.trRadiusX, rsuperellipse.trRadiusY,
        rsuperellipse.brRadiusX, rsuperellipse.brRadiusY,
        rsuperellipse.blRadiusX, rsuperellipse.blRadiusY,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawOval(_ rect: Rect, _ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawOval(
        rect.left, rect.top, rect.right, rect.bottom,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawCircle(_ c: Offset, _ radius: Double, _ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawCircle(
        c.dx, c.dy, radius,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawArc(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawArc(
        rect.left, rect.top, rect.right, rect.bottom,
        startAngle, sweepAngle, useCenter,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawPath(_ path: Path, _ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawPath(
        path.bridge,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawImage(_ image: Image, _ offset: Offset, _ paint: Paint) {
    paint.withDataPointer { paintData in
      let error = String(cString: bridge.DrawImage(
        image.bridge,
        offset.dx, offset.dy,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr,
        Int32(paint.filterQuality.rawValue)
      ))
      if !error.isEmpty {
        assertionFailure("drawImage failed: \(error)")
      }
    }
  }

  public func drawImageRect(_ image: Image, _ src: Rect, _ dst: Rect, _ paint: Paint) {
    paint.withDataPointer { paintData in
      let error = String(cString: bridge.DrawImageRect(
        image.bridge,
        src.left, src.top, src.right, src.bottom,
        dst.left, dst.top, dst.right, dst.bottom,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr,
        Int32(paint.filterQuality.rawValue)
      ))
      if !error.isEmpty {
        assertionFailure("drawImageRect failed: \(error)")
      }
    }
  }

  public func drawImageNine(_ image: Image, _ center: Rect, _ dst: Rect, _ paint: Paint) {
    paint.withDataPointer { paintData in
      let error = String(cString: bridge.DrawImageNine(
        image.bridge,
        center.left, center.top, center.right, center.bottom,
        dst.left, dst.top, dst.right, dst.bottom,
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr,
        Int32(paint.filterQuality.rawValue)
      ))
      if !error.isEmpty {
        assertionFailure("drawImageNine failed: \(error)")
      }
    }
  }

  public func drawPicture(_ picture: any Picture) {
    // The picture must provide a display list pointer.
    // NativePicture (task 40b) will implement this via PictureBridge.
    // For now, we use a protocol-based approach.
    if let bridgePicture = picture as? NativePictureProvider {
      let ptr = bridgePicture.displayListPtr
      if let ptr = ptr {
        bridge.DrawDisplayList(ptr)
      }
    }
  }

  public func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) {
    guard let nativeParagraph = paragraph as? NativeParagraph else { return }
    nativeParagraph.bridge.Paint(bridge, offset.dx, offset.dy)
  }

  public func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {
    // Convert [Offset] to [Float] (x,y pairs)
    var floatPoints = [Float](repeating: 0, count: points.count * 2)
    for i in 0..<points.count {
      floatPoints[i * 2] = Float(points[i].dx)
      floatPoints[i * 2 + 1] = Float(points[i].dy)
    }
    floatPoints.withUnsafeBufferPointer { buffer in
      paint.withDataPointer { paintData in
        bridge.DrawPoints(
          Int32(pointMode.rawValue),
          buffer.baseAddress!,
          Int32(floatPoints.count),
          paintData,
          paint.shaderBridgePtr,
          paint.colorFilterBridgePtr,
          paint.imageFilterBridgePtr
        )
      }
    }
  }

  public func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {
    points.withUnsafeBufferPointer { buffer in
      paint.withDataPointer { paintData in
        bridge.DrawPoints(
          Int32(pointMode.rawValue),
          buffer.baseAddress!,
          Int32(points.count),
          paintData,
          paint.shaderBridgePtr,
          paint.colorFilterBridgePtr,
          paint.imageFilterBridgePtr
        )
      }
    }
  }

  public func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {
    paint.withDataPointer { paintData in
      bridge.DrawVertices(
        vertices.bridge,
        Int32(blendMode.rawValue),
        paintData,
        paint.shaderBridgePtr,
        paint.colorFilterBridgePtr,
        paint.imageFilterBridgePtr
      )
    }
  }

  public func drawAtlas(
    _ atlas: Image,
    _ transforms: [RSTransform],
    _ rects: [Rect],
    _ colors: [Color]?,
    _ blendMode: BlendMode?,
    _ cullRect: Rect?,
    _ paint: Paint
  ) {
    // Convert RSTransforms to float array (scos, ssin, tx, ty per entry)
    var rstData = [Float](repeating: 0, count: transforms.count * 4)
    for i in 0..<transforms.count {
      rstData[i * 4] = Float(transforms[i].scos)
      rstData[i * 4 + 1] = Float(transforms[i].ssin)
      rstData[i * 4 + 2] = Float(transforms[i].tx)
      rstData[i * 4 + 3] = Float(transforms[i].ty)
    }

    // Convert rects to float array (left, top, right, bottom per entry)
    var rectsData = [Float](repeating: 0, count: rects.count * 4)
    for i in 0..<rects.count {
      rectsData[i * 4] = Float(rects[i].left)
      rectsData[i * 4 + 1] = Float(rects[i].top)
      rectsData[i * 4 + 2] = Float(rects[i].right)
      rectsData[i * 4 + 3] = Float(rects[i].bottom)
    }

    // Convert colors to int32 array
    let colorsData: [Int32]? = colors?.map { Int32(bitPattern: UInt32($0.toARGB32())) }

    // One implementation, not two: drawRawAtlas takes the same four buffers
    // and is the one that gets their lifetimes right (see the note there).
    drawRawAtlas(atlas, rstData, rectsData, colorsData, blendMode, cullRect, paint)
  }

  public func drawRawAtlas(
    _ atlas: Image,
    _ rstTransforms: [Float],
    _ rects: [Float],
    _ colors: [Int32]?,
    _ blendMode: BlendMode?,
    _ cullRect: Rect?,
    _ paint: Paint
  ) {
    let rectCount = rects.count / 4

    let cullData: [Float]? = cullRect.map {
      [Float($0.left), Float($0.top), Float($0.right), Float($0.bottom)]
    }

    // The `colors` and `cullRect` buffers are borrowed by NESTED closures, not
    // by `withUnsafeBufferPointer { $0.baseAddress }`. That spelling returns a
    // pointer whose buffer is only guaranteed alive for the duration of the
    // closure it escapes from, so the callee received a dangling pointer — it
    // happened to work while the array stayed alive by luck of the caller's
    // stack. The terminal's atlas painter passes a per-quad colour array on
    // every frame, which is exactly the case that would eventually bite.
    withExtendedLifetime(colors) {
      rstTransforms.withUnsafeBufferPointer { rstBuf in
        rects.withUnsafeBufferPointer { rectsBuf in
          paint.withDataPointer { paintData in
            func call(_ colorsPtr: UnsafePointer<Int32>?,
                      _ cullPtr: UnsafePointer<Float>?) {
              let error = String(cString: bridge.DrawAtlas(
                atlas.bridge,
                rstBuf.baseAddress!,
                rectsBuf.baseAddress!,
                Int32(rectCount),
                colorsPtr,
                Int32(colors?.count ?? 0),
                Int32(blendMode?.rawValue ?? BlendMode.srcOver.rawValue),
                cullPtr,
                paintData,
                paint.shaderBridgePtr,
                paint.colorFilterBridgePtr,
                paint.imageFilterBridgePtr,
                Int32(paint.filterQuality.rawValue)
              ))
              if !error.isEmpty {
                assertionFailure("drawRawAtlas failed: \(error)")
              }
            }
            func withCull(_ colorsPtr: UnsafePointer<Int32>?) {
              if let cullData = cullData {
                cullData.withUnsafeBufferPointer { call(colorsPtr, $0.baseAddress) }
              } else {
                call(colorsPtr, nil)
              }
            }
            if let colors = colors {
              colors.withUnsafeBufferPointer { withCull($0.baseAddress) }
            } else {
              withCull(nil)
            }
          }
        }
      }
    }
  }

  public func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {
    bridge.DrawShadow(path.bridge, Int32(color.toARGB32()), elevation, transparentOccluder)
  }

  /// Invalidates the canvas (called when recording ends).
  internal func invalidate() {
    bridge.Invalidate()
  }
}

// MARK: - NativePictureProvider

/// Internal protocol for objects that can provide a display list pointer.
///
/// This is used by NativeCanvas.drawPicture to get the DisplayList from
/// a Picture implementation without creating a circular dependency.
/// NativePicture (task 40b) will conform to this protocol.
internal protocol NativePictureProvider {
  var displayListPtr: UnsafeRawPointer? { get }
}

// MARK: - ImageDescriptor

/// A descriptor of data that can be turned into an `Image` via a `Codec`.
///
/// Use this class to determine the height, width, and byte size of image data
/// before decoding it.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7803-7866`
/// **Original Name:** `ImageDescriptor` (abstract class)
///
/// DIFFERENCE FROM DART: Uses Swift protocol instead of abstract class.
/// REASON: Swift does not have abstract classes; protocol provides equivalent interface.
public protocol ImageDescriptor: AnyObject {
  /// The width, in pixels, of the image.
  ///
  /// On the Web, this is only supported for raw images.
  ///
  /// **Dart Source:** `painting.dart:7834-7837`
  /// **Original:** `int get width`
  var width: Int { get }

  /// The height, in pixels, of the image.
  ///
  /// On the Web, this is only supported for raw images.
  ///
  /// **Dart Source:** `painting.dart:7839-7842`
  /// **Original:** `int get height`
  var height: Int { get }

  /// The number of bytes per pixel in the image.
  ///
  /// On web, this is only supported for raw images.
  ///
  /// **Dart Source:** `painting.dart:7844-7847`
  /// **Original:** `int get bytesPerPixel`
  var bytesPerPixel: Int { get }

  /// Release the resources used by this object. The object is no longer usable
  /// after this method is called.
  ///
  /// **Dart Source:** `painting.dart:7849-7854`
  /// **Original:** `void dispose()`
  func dispose()

  /// Creates a `Codec` object which is suitable for decoding the data in the
  /// buffer to an `Image`.
  ///
  /// If only one of `targetWidth` or `targetHeight` are specified, the other
  /// dimension will be scaled according to the aspect ratio of the supplied
  /// dimension.
  ///
  /// If either `targetWidth` or `targetHeight` is less than or equal to zero, it
  /// will be treated as if it is nil.
  ///
  /// **Dart Source:** `painting.dart:7856-7865`
  /// **Original:** `Future<Codec> instantiateCodec({int? targetWidth, int? targetHeight})`
  ///
  /// DIFFERENCE FROM DART: Uses Swift async/throws instead of Future.
  /// REASON: Swift's native async/await is the idiomatic equivalent of Dart's Future.
  func instantiateCodec(targetWidth: Int?, targetHeight: Int?) async throws -> any Codec
}

/// Static factory methods for `ImageDescriptor`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7803-7866`
///
/// DIFFERENCE FROM DART: Factory methods are in an enum namespace instead of static
/// methods on the class, since Swift protocols cannot have static factory methods
/// that return `Self` for protocol types.
/// REASON: Swift protocol limitation; enum namespace provides equivalent API surface.
public enum ImageDescriptorFactory {
  /// Creates an image descriptor from raw image pixels.
  ///
  /// The `pixels` parameter is the pixel data. They are packed in bytes in the
  /// order described by `pixelFormat`, then grouped in rows, from left to right,
  /// then top to bottom.
  ///
  /// The `rowBytes` parameter is the number of bytes consumed by each row of
  /// pixels in the data buffer. If unspecified, it defaults to `width` multiplied
  /// by the number of bytes per pixel in the provided `format`.
  ///
  /// **Dart Source:** `painting.dart:7808-7824`
  /// **Original:** `factory ImageDescriptor.raw(ImmutableBuffer buffer, {required int width, required int height, int? rowBytes, required PixelFormat pixelFormat})`
  public static func raw(
    _ buffer: ImmutableBuffer,
    width: Int,
    height: Int,
    rowBytes: Int? = nil,
    pixelFormat: PixelFormat
  ) -> any ImageDescriptor {
    return NativeImageDescriptor(
      raw: buffer,
      width: width,
      height: height,
      rowBytes: rowBytes,
      pixelFormat: pixelFormat
    )
  }

  /// Creates an image descriptor from encoded data in a supported format.
  ///
  /// **Dart Source:** `painting.dart:7826-7832`
  /// **Original:** `static Future<ImageDescriptor> encoded(ImmutableBuffer buffer)`
  ///
  /// DIFFERENCE FROM DART: Uses Swift async/throws instead of Future.
  /// REASON: Swift's native async/await is the idiomatic equivalent of Dart's Future.
  public static func encoded(_ buffer: ImmutableBuffer) async throws -> any ImageDescriptor {
    return try NativeImageDescriptor(encoded: buffer)
  }
}

// MARK: - NativeImageDescriptor

/// Concrete native implementation of `ImageDescriptor`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:7868-7971`
/// **Original Name:** `_NativeImageDescriptor`
/// **Lines:** 7868-7971
///
/// This class wraps the C++ `ImageDescriptorBridge` which in turn wraps
/// Skia's `SkImageInfo`, `sk_sp<SkData>`, and optionally an `ImageGenerator`.
///
/// DIFFERENCE FROM DART: Uses `ImageDescriptorBridge` instead of
/// `NativeFieldWrapperClass1`. Getters cache values like the Dart version.
/// REASON: Swift doesn't have `NativeFieldWrapperClass1`; uses
/// `SWIFT_SHARED_REFERENCE` C++ bridge for memory management.
public class NativeImageDescriptor: ImageDescriptor {
  /// The C++ bridge object that handles native image descriptor operations.
  internal let bridge: flutter.swift_bridge.ImageDescriptorBridge

  /// Cached width value.
  ///
  /// **Dart Source:** `painting.dart:7910`
  /// **Original:** `int? _width;`
  private var _width: Int?

  /// Cached height value.
  ///
  /// **Dart Source:** `painting.dart:7918`
  /// **Original:** `int? _height;`
  private var _height: Int?

  /// Cached bytes per pixel value.
  ///
  /// **Dart Source:** `painting.dart:7926`
  /// **Original:** `int? _bytesPerPixel;`
  private var _bytesPerPixel: Int?

  /// Private initializer wrapping an existing bridge object.
  ///
  /// **Dart Source:** `painting.dart:7869`
  /// **Original:** `_NativeImageDescriptor._()`
  ///
  /// DIFFERENCE FROM DART: Takes a bridge parameter.
  /// REASON: Swift creates the bridge directly rather than using
  /// NativeFieldWrapperClass1 pattern. Private because bridge objects are
  /// internal implementation details — use purpose-specific inits instead.
  private init(_ bridge: flutter.swift_bridge.ImageDescriptorBridge) {
    self.bridge = bridge
  }

  /// Creates an image descriptor from raw image pixels.
  ///
  /// **Dart Source:** `painting.dart:7871-7893`
  /// **Original:** `_NativeImageDescriptor.raw(ImmutableBuffer buffer, ...)`
  ///
  /// The `pixels` parameter is the pixel data packed in bytes in the order
  /// described by `pixelFormat`, grouped in rows from left to right, then
  /// top to bottom.
  ///
  /// The `rowBytes` parameter is the number of bytes consumed by each row
  /// of pixels. If `nil`, it defaults to `width * bytesPerPixel`.
  public convenience init(
    raw buffer: ImmutableBuffer,
    width: Int,
    height: Int,
    rowBytes: Int? = nil,
    pixelFormat: PixelFormat
  ) {
    let bridge = flutter.swift_bridge.ImageDescriptorBridge(
      buffer.bridge,
      Int32(width),
      Int32(height),
      Int32(rowBytes ?? -1),
      Int32(pixelFormat.rawValue)
    )
    self.init(bridge)
    // Match Dart behavior: cache width/height and set bytesPerPixel to 4
    // (Dart: _width = width; _height = height; _bytesPerPixel = 4;)
    self._width = width
    self._height = height
    self._bytesPerPixel = 4
  }

  /// Creates an image descriptor from encoded image data.
  ///
  /// **Dart Source:** `painting.dart:7895-7896`
  /// **Original:** `_initEncoded(ImmutableBuffer buffer, _Callback<void> callback)`
  ///
  /// DIFFERENCE FROM DART: Synchronous and throws on failure instead of
  /// using async callback.
  /// REASON: Swift doesn't use Dart VM callbacks; the bridge creates the
  /// generator synchronously.
  public convenience init(encoded buffer: ImmutableBuffer) throws {
    let bridge = flutter.swift_bridge.ImageDescriptorBridge(buffer.bridge)
    // DIFFERENCE FROM DART: Constructor + IsValid() check instead of async
    // callback. The Dart version returns an error string via Dart_Handle.
    guard bridge.IsValid() else {
      throw PaintingError.operationFailed("Invalid image data")
    }
    self.init(bridge)
  }

  /// The width of this image, in pixels.
  ///
  /// **Dart Source:** `painting.dart:7910-7916`
  /// **Original:** `int get width => _width ??= _getWidth();`
  public var width: Int {
    if let cached = _width {
      return cached
    }
    let w = Int(bridge.GetWidth())
    _width = w
    return w
  }

  /// The height of this image, in pixels.
  ///
  /// **Dart Source:** `painting.dart:7918-7924`
  /// **Original:** `int get height => _height ??= _getHeight();`
  public var height: Int {
    if let cached = _height {
      return cached
    }
    let h = Int(bridge.GetHeight())
    _height = h
    return h
  }

  /// The number of bytes per pixel in the image.
  ///
  /// **Dart Source:** `painting.dart:7926-7932`
  /// **Original:** `int get bytesPerPixel => _bytesPerPixel ??= _getBytesPerPixel();`
  public var bytesPerPixel: Int {
    if let cached = _bytesPerPixel {
      return cached
    }
    let bpp = Int(bridge.GetBytesPerPixel())
    _bytesPerPixel = bpp
    return bpp
  }

  /// Release the resources used by this object.
  ///
  /// **Dart Source:** `painting.dart:7934-7936`
  /// **Original:** `@Native<Void Function(Pointer<Void>)>(symbol: 'ImageDescriptor::dispose')`
  public func dispose() {
    bridge.Dispose()
  }

  /// Creates a `Codec` object suitable for decoding the data to an `Image`.
  ///
  /// If only one of `targetWidth` or `targetHeight` is specified, the other
  /// will be scaled according to the aspect ratio.
  ///
  /// If either `targetWidth` or `targetHeight` is less than or equal to zero,
  /// it will be treated as `nil`.
  ///
  /// **Dart Source:** `painting.dart:7938-7961`
  /// **Original:** `Future<Codec> instantiateCodec({int? targetWidth, int? targetHeight})`
  ///
  /// DIFFERENCE FROM DART: Synchronous bridge call wrapped in async.
  /// REASON: The Dart version uses @Native to call C++ synchronously then
  /// returns a Future. We do the same via the bridge.
  public func instantiateCodec(targetWidth: Int?, targetHeight: Int?) async throws -> any Codec {
    // Mirrors Dart logic at painting.dart:7939-7956
    var tw = targetWidth
    var th = targetHeight

    if let w = tw, w <= 0 {
      tw = nil
    }
    if let h = th, h <= 0 {
      th = nil
    }

    if tw == nil && th == nil {
      tw = width
      th = height
    } else if tw == nil, let targetH = th {
      tw = Int((Double(targetH) * (Double(width) / Double(height))).rounded())
    } else if th == nil, let targetW = tw {
      th = Int(Double(targetW) / (Double(width) / Double(height)))
    }

    assert(tw != nil)
    assert(th != nil)

    guard let codecBridge = bridge.InstantiateCodec(Int32(tw!), Int32(th!)) else {
      throw PaintingError.operationFailed(
        "Failed to instantiate codec for ImageDescriptor")
    }
    return NativeCodec(codecBridge)
  }

  /// Returns a string representation of this image descriptor.
  ///
  /// **Dart Source:** `painting.dart:7968-7970`
  /// **Original:** `String toString() => 'ImageDescriptor(width: ${_width ?? '?'}, ...)'`
  public var description: String {
    var buffer = [CChar](repeating: 0, count: 256)
    bridge.ToString(&buffer, 256)
    return String(cString: buffer)
  }
}

// MARK: - EngineLayer
/// A handle for the framework to hold and retain an engine layer across frames.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `EngineLayer`
/// **Lines:** 2807-2825
///
/// DIFFERENCE FROM DART: Using protocol instead of abstract class.
/// REASON: Swift doesn't have abstract classes; protocol provides equivalent functionality.
///
/// See also:
///  * Dart implementation at painting.dart:2807
public protocol EngineLayer: AnyObject {
  /// Release the resources used by this object. The object is no longer usable
  /// after this method is called.
  ///
  /// EngineLayers indirectly retain platform specific graphics resources. Some
  /// of these resources, such as images, may be memory intensive. It is
  /// important to dispose of EngineLayer objects that will no longer be used as
  /// soon as possible to avoid retaining these resources until the next
  /// garbage collection.
  ///
  /// Once this EngineLayer is disposed, it is no longer eligible for use as a
  /// retained layer, and must not be passed as an `oldLayer` to any of the
  /// `SceneBuilder` methods which accept that parameter.
  ///
  /// **Dart Source:** `painting.dart:2809-2824`
  /// **Original:** `void dispose();`
  func dispose()
}

// MARK: - NativeEngineLayer

/// Concrete EngineLayer implementation that wraps an EngineLayerBridge.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2827-2835`
/// **Original Name:** `_NativeEngineLayer`
///
/// In Dart, `_NativeEngineLayer` extends `NativeFieldWrapperClass1` and uses
/// `@Native` for FFI calls to `EngineLayer::dispose`. In Swift, we wrap a C++
/// `EngineLayerBridge` via SWIFT_SHARED_REFERENCE for automatic memory management.
///
/// DIFFERENCE FROM DART: In Dart, `_NativeEngineLayer` extends `NativeFieldWrapperClass1`
/// and the engine creates instances via `EngineLayer::MakeRetained`. In Swift, instances
/// are created by wrapping an `EngineLayerBridge` which holds the underlying ContainerLayer.
/// REASON: Swift doesn't use Dart FFI; instead uses direct C++ interop.
public class NativeEngineLayer: EngineLayer {
  /// The C++ bridge object that holds the ContainerLayer.
  internal let bridge: flutter.swift_bridge.EngineLayerBridge

  /// Creates a NativeEngineLayer by wrapping an EngineLayerBridge.
  ///
  /// **Dart Source:** `painting.dart:2828-2830`
  /// **Original:** `_NativeEngineLayer._()`
  ///
  /// DIFFERENCE FROM DART: In Dart, the constructor is private and the engine
  /// creates instances. In Swift, the SceneBuilder bridge will create
  /// EngineLayerBridge instances and wrap them in NativeEngineLayer.
  /// REASON: No Dart VM wrapper association needed; Swift ARC manages lifetime.
  internal init(bridge: flutter.swift_bridge.EngineLayerBridge) {
    self.bridge = bridge
  }

  /// Release the resources used by this object.
  ///
  /// **Dart Source:** `painting.dart:2832-2834`
  /// **Original:** `@Native<Void Function(Pointer<Void>)>(symbol: 'EngineLayer::dispose')`
  ///              `external void dispose();`
  ///
  /// Releases the underlying ContainerLayer shared_ptr. After calling this,
  /// the engine layer is no longer usable and must not be passed as an
  /// `oldLayer` to SceneBuilder methods.
  public func dispose() {
    bridge.Dispose()
  }
}

// MARK: - Top-Level Functions

/// Instantiates an image `Codec`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2407-2455`
/// **Original Name:** `instantiateImageCodec`
///
/// This method is a convenience wrapper around the `ImageDescriptor` API, and
/// using `ImageDescriptor` directly is preferred since it allows the caller to
/// make better determinations about how and whether to use the `targetWidth`
/// and `targetHeight` parameters.
///
/// The `list` parameter is the binary image data (e.g a PNG or GIF binary data).
/// The data can be for either static or animated images. The following image
/// formats are supported:
/// JPEG, PNG, GIF, Animated GIF, WebP, Animated WebP, BMP, and WBMP. Additional
/// formats may be supported by the underlying platform. Flutter will
/// attempt to call platform API to decode unrecognized formats, and if the
/// platform API supports decoding the image Flutter will be able to render it.
///
/// The `targetWidth` and `targetHeight` arguments specify the size of the
/// output image, in image pixels. If they are not equal to the intrinsic
/// dimensions of the image, then the image will be scaled after being decoded.
/// If the `allowUpscaling` parameter is not set to true, both dimensions will
/// be capped at the intrinsic dimensions of the image, even if only one of
/// them would have exceeded those intrinsic dimensions. If exactly one of these
/// two arguments is specified, then the aspect ratio will be maintained while
/// forcing the image to match the other given dimension. If neither is
/// specified, then the image maintains its intrinsic size.
///
/// Scaling the image to larger than its intrinsic size should usually be
/// avoided, since it causes the image to use more memory than necessary.
/// Instead, prefer scaling the `Canvas` transform. If the image must be scaled
/// up, the `allowUpscaling` parameter must be set to true.
///
/// The returned future can complete with an error if the image decoding has
/// failed.
///
/// DIFFERENCE FROM DART: Uses Swift async/throws instead of Future.
/// REASON: Swift's native async/await is the idiomatic equivalent of Dart's Future.
///
/// DIFFERENCE FROM DART: Takes `[UInt8]` instead of `Uint8List`.
/// REASON: Swift's `[UInt8]` is the equivalent of Dart's `Uint8List`.
public func instantiateImageCodec(
  _ list: [UInt8],
  targetWidth: Int64? = nil,
  targetHeight: Int64? = nil,
  allowUpscaling: Bool = true
) async throws -> any Codec {
  let buffer = ImmutableBuffer.fromUint8List(list)
  return try await instantiateImageCodecFromBuffer(
    buffer,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    allowUpscaling: allowUpscaling
  )
}

/// Signature for a callback that determines the size to which an image should
/// be decoded given its intrinsic size.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2576-2583`
/// **Original Name:** `TargetImageSizeCallback`
///
/// See also:
///  * `instantiateImageCodecWithSize`, which uses this signature for its
///    `getTargetSize` argument.
public typealias TargetImageSizeCallback = (Int, Int) -> TargetImageSize

/// Default target image size callback that returns the intrinsic size.
///
/// **Dart Source:** `painting.dart:2572-2574`
/// **Original Name:** `_getDefaultImageSize`
private func _getDefaultImageSize(_ intrinsicWidth: Int, _ intrinsicHeight: Int) -> TargetImageSize {
  return TargetImageSize()
}

/// Instantiates an image `Codec`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2457-2516`
/// **Original Name:** `instantiateImageCodecFromBuffer`
///
/// This method is a convenience wrapper around the `ImageDescriptor` API, and
/// using `ImageDescriptor` directly is preferred since it allows the caller to
/// make better determinations about how and whether to use the `targetWidth`
/// and `targetHeight` parameters.
///
/// The `buffer` parameter is the binary image data (e.g a PNG or GIF binary data).
/// The data can be for either static or animated images. The following image
/// formats are supported:
/// JPEG, PNG, GIF, Animated GIF, WebP, Animated WebP, BMP, and WBMP. Additional
/// formats may be supported by the underlying platform. Flutter will
/// attempt to call platform API to decode unrecognized formats, and if the
/// platform API supports decoding the image Flutter will be able to render it.
///
/// The `buffer` will be disposed by this method once the codec has been created,
/// so the caller must relinquish ownership of the `buffer` when they call this
/// method.
///
/// The `targetWidth` and `targetHeight` arguments specify the size of the
/// output image, in image pixels. If they are not equal to the intrinsic
/// dimensions of the image, then the image will be scaled after being decoded.
/// If the `allowUpscaling` parameter is not set to true, both dimensions will
/// be capped at the intrinsic dimensions of the image, even if only one of
/// them would have exceeded those intrinsic dimensions. If exactly one of these
/// two arguments is specified, then the aspect ratio will be maintained while
/// forcing the image to match the other given dimension. If neither is
/// specified, then the image maintains its intrinsic size.
///
/// Scaling the image to larger than its intrinsic size should usually be
/// avoided, since it causes the image to use more memory than necessary.
/// Instead, prefer scaling the `Canvas` transform. If the image must be scaled
/// up, the `allowUpscaling` parameter must be set to true.
///
/// The returned future can complete with an error if the image decoding has
/// failed.
///
/// DIFFERENCE FROM DART: Uses Swift async/throws instead of Future.
/// REASON: Swift's native async/await is the idiomatic equivalent of Dart's Future.
public func instantiateImageCodecFromBuffer(
  _ buffer: ImmutableBuffer,
  targetWidth: Int64? = nil,
  targetHeight: Int64? = nil,
  allowUpscaling: Bool = true
) async throws -> any Codec {
  return try await instantiateImageCodecWithSize(
    buffer,
    getTargetSize: { (intrinsicWidth: Int, intrinsicHeight: Int) -> TargetImageSize in
      var tw = targetWidth
      var th = targetHeight
      if !allowUpscaling {
        if let twVal = tw, twVal > Int64(intrinsicWidth) {
          tw = Int64(intrinsicWidth)
        }
        if let thVal = th, thVal > Int64(intrinsicHeight) {
          th = Int64(intrinsicHeight)
        }
      }
      return TargetImageSize(width: tw, height: th)
    }
  )
}

/// Instantiates an image `Codec`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2518-2570`
/// **Original Name:** `instantiateImageCodecWithSize`
///
/// This method is a convenience wrapper around the `ImageDescriptor` API.
///
/// The `buffer` parameter is the binary image data (e.g a PNG or GIF binary
/// data). The data can be for either static or animated images. The following
/// image formats are supported:
/// JPEG, PNG, GIF, Animated GIF, WebP, Animated WebP, BMP, and WBMP. Additional
/// formats may be supported by the underlying platform. Flutter will
/// attempt to call platform API to decode unrecognized formats, and if the
/// platform API supports decoding the image Flutter will be able to render it.
///
/// The `buffer` will be disposed by this method once the codec has been
/// created, so the caller must relinquish ownership of the `buffer` when they
/// call this method.
///
/// The `getTargetSize` parameter, when specified, will be invoked and passed
/// the image's intrinsic size to determine the size to decode the image to.
/// The width and the height of the size it returns must be positive values
/// greater than or equal to 1, or nil. It is valid to return a
/// `TargetImageSize` that specifies only one of `width` and `height` with the
/// other remaining nil, in which case the omitted dimension will be scaled to
/// maintain the aspect ratio of the original dimensions. When both are nil or
/// omitted, the image will be decoded at its native resolution (as will be the
/// case if the `getTargetSize` parameter is omitted).
///
/// Scaling the image to larger than its intrinsic size should usually be
/// avoided, since it causes the image to use more memory than necessary.
/// Instead, prefer scaling the `Canvas` transform.
///
/// The returned future can complete with an error if the image decoding has
/// failed.
///
/// DIFFERENCE FROM DART: Uses Swift async/throws instead of Future.
/// REASON: Swift's native async/await is the idiomatic equivalent of Dart's Future.
public func instantiateImageCodecWithSize(
  _ buffer: ImmutableBuffer,
  getTargetSize: TargetImageSizeCallback? = nil
) async throws -> any Codec {
  let targetSizeCallback = getTargetSize ?? _getDefaultImageSize
  let descriptor = try await ImageDescriptorFactory.encoded(buffer)
  defer {
    buffer.dispose()
  }
  let targetSize = targetSizeCallback(descriptor.width, descriptor.height)
  assert(targetSize.width == nil || targetSize.width! > 0)
  assert(targetSize.height == nil || targetSize.height! > 0)
  return try await descriptor.instantiateCodec(
    targetWidth: targetSize.width.map { Int($0) },
    targetHeight: targetSize.height.map { Int($0) }
  )
}

// MARK: - ImageDecoderCallback

/// Callback signature for `decodeImageFromList`.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2241`
/// **Original:** `typedef ImageDecoderCallback = void Function(Image result);`
public typealias ImageDecoderCallback = (Image) -> Void

// MARK: - decodeImageFromList

/// Loads a single image frame from a byte array into an `Image` object.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2627-2634`
/// **Original Name:** `decodeImageFromList`
///
/// This is a convenience wrapper around `instantiateImageCodec`. Prefer using
/// `instantiateImageCodec` which also supports multi frame images and offers
/// better error handling. This function swallows asynchronous errors.
///
/// DIFFERENCE FROM DART: In Dart, this function returns `void` and launches an
/// async operation that swallows errors. In Swift, we use `Task` to launch the
/// async work similarly, maintaining the fire-and-forget semantics.
/// REASON: Swift has no direct equivalent of Dart's unawaited Future; Task provides
/// similar fire-and-forget async behavior.
public func decodeImageFromList(_ list: sending [UInt8], _ callback: sending @escaping ImageDecoderCallback) {
  Task {
    let codec = try await instantiateImageCodec(list)
    let frameInfo: FrameInfo
    do {
      frameInfo = try await codec.getNextFrame()
    } catch {
      codec.dispose()
      throw error
    }
    codec.dispose()
    callback(frameInfo.image)
  }
}

// MARK: - decodeImageFromPixels

/// Convert an array of pixel values into an [Image] object.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart:2647-2721`
/// **Original Name:** `decodeImageFromPixels`
///
/// The `pixels` parameter is the pixel data. They are packed in bytes in the
/// order described by `format`, then grouped in rows, from left to right,
/// then top to bottom.
///
/// The `rowBytes` parameter is the number of bytes consumed by each row of
/// pixels in the data buffer. If unspecified, it defaults to `width` multiplied
/// by the number of bytes per pixel in the provided `format`.
///
/// The `targetWidth` and `targetHeight` arguments specify the size of the
/// output image, in image pixels. If they are not equal to the intrinsic
/// dimensions of the image, then the image will be scaled after being decoded.
/// If the `allowUpscaling` parameter is not set to true, both dimensions will
/// be capped at the intrinsic dimensions of the image, even if only one of
/// them would have exceeded those intrinsic dimensions. If exactly one of these
/// two arguments is specified, then the aspect ratio will be maintained while
/// forcing the image to match the other given dimension. If neither is
/// specified, then the image maintains its intrinsic size.
///
/// Scaling the image to larger than its intrinsic size should usually be
/// avoided, since it causes the image to use more memory than necessary.
/// Instead, prefer scaling the `Canvas` transform. If the image must be scaled
/// up, the `allowUpscaling` parameter must be set to true.
///
/// DIFFERENCE FROM DART: Uses Swift `Task` for fire-and-forget async instead of
/// Dart's chained `Future.then()` calls.
/// REASON: Swift has no direct equivalent of Dart's `Future.then()` chaining;
/// `Task` with `async`/`await` provides equivalent fire-and-forget async behavior.
public func decodeImageFromPixels(
  _ pixels: sending [UInt8],
  width: Int,
  height: Int,
  format: sending PixelFormat,
  callback: sending @escaping ImageDecoderCallback,
  rowBytes: Int? = nil,
  targetWidth: Int? = nil,
  targetHeight: Int? = nil,
  allowUpscaling: Bool = true
) {
  if let targetWidth = targetWidth {
    assert(allowUpscaling || targetWidth <= width)
  }
  if let targetHeight = targetHeight {
    assert(allowUpscaling || targetHeight <= height)
  }

  let capturedFormat = format
  let capturedRowBytes = rowBytes
  let capturedWidth = width
  let capturedHeight = height
  let capturedTargetWidth = targetWidth
  let capturedTargetHeight = targetHeight
  let capturedAllowUpscaling = allowUpscaling

  Task {
    let buffer = ImmutableBuffer.fromUint8List(pixels)
    let descriptor = ImageDescriptorFactory.raw(
      buffer,
      width: capturedWidth,
      height: capturedHeight,
      rowBytes: capturedRowBytes,
      pixelFormat: capturedFormat
    )

    var effectiveTargetWidth = capturedTargetWidth
    var effectiveTargetHeight = capturedTargetHeight

    if !capturedAllowUpscaling {
      if let tw = effectiveTargetWidth, tw > descriptor.width {
        effectiveTargetWidth = descriptor.width
      }
      if let th = effectiveTargetHeight, th > descriptor.height {
        effectiveTargetHeight = descriptor.height
      }
    }

    let codec = try await descriptor.instantiateCodec(
      targetWidth: effectiveTargetWidth,
      targetHeight: effectiveTargetHeight
    )
    let frameInfo: FrameInfo
    do {
      frameInfo = try await codec.getNextFrame()
    } catch {
      codec.dispose()
      throw error
    }
    codec.dispose()
    buffer.dispose()
    descriptor.dispose()

    callback(frameInfo.image)
  }
}

// MARK: - Private Validation Helper Functions

/// Validates that a Rect does not contain NaN values.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_rectIsValid`
/// **Lines:** 25-28
///
/// Returns true if validation passes (always true; asserts on NaN in debug).
private func rectIsValid(_ rect: Rect) -> Bool {
  assert(!rect.hasNaN, "Rect argument contained a NaN value.")
  return true
}

/// Validates that an RRect does not contain NaN values.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_rrectIsValid`
/// **Lines:** 30-33
///
/// Returns true if validation passes (always true; asserts on NaN in debug).
private func rrectIsValid(_ rrect: RRect) -> Bool {
  assert(!rrect.hasNaN, "RRect argument contained a NaN value.")
  return true
}

/// Validates that an RSuperellipse does not contain NaN values.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_rsuperellipseIsValid`
/// **Lines:** 35-38
///
/// Returns true if validation passes (always true; asserts on NaN in debug).
private func rsuperellipseIsValid(_ rsuperellipse: RSuperellipse) -> Bool {
  assert(!rsuperellipse.hasNaN, "RSuperellipse argument contained a NaN value.")
  return true
}

/// Validates that an Offset does not contain NaN values.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_offsetIsValid`
/// **Lines:** 40-43
///
/// Returns true if validation passes (always true; asserts on NaN in debug).
private func offsetIsValid(_ offset: Offset) -> Bool {
  assert(!offset.dx.isNaN && !offset.dy.isNaN, "Offset argument contained a NaN value.")
  return true
}

/// Validates that a 4x4 matrix (as [Double] with 16 entries) contains only finite values.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_matrix4IsValid`
/// **Lines:** 45-49
///
/// Returns true if validation passes (always true; asserts in debug).
private func matrix4IsValid(_ matrix4: [Double]) -> Bool {
  assert(matrix4.count == 16, "Matrix4 must have 16 entries.")
  assert(matrix4.allSatisfy { $0.isFinite }, "Matrix4 entries must be finite.")
  return true
}

/// Validates that a Radius does not contain NaN values.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_radiusIsValid`
/// **Lines:** 51-54
///
/// Returns true if validation passes (always true; asserts on NaN in debug).
private func radiusIsValid(_ radius: Radius) -> Bool {
  assert(!radius.x.isNaN && !radius.y.isNaN, "Radius argument contained a NaN value.")
  return true
}

// MARK: - Private Encoding Helper Functions

/// Encodes a list of Color objects as Int32 ARGB values.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_encodeColorList`
/// **Lines:** 4774-4781
///
/// Each color is converted to its ARGB32 integer representation.
private func encodeColorList(_ colors: [Color]) -> [Int32] {
  return colors.map { Int32(bitPattern: UInt32($0.value)) }
}

/// Encodes a list of Offset values as a flat Float32 array [x0, y0, x1, y1, ...].
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_encodePointList`
/// **Lines:** 4783-4795
///
/// Each offset contributes two consecutive floats (dx, dy).
private func encodePointList(_ points: [Offset]) -> [Float] {
  var result = [Float]()
  result.reserveCapacity(points.count * 2)
  for point in points {
    assert(offsetIsValid(point))
    result.append(Float(point.dx))
    result.append(Float(point.dy))
  }
  return result
}

/// Encodes two Offset values as a flat Float32 array [ax, ay, bx, by].
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_encodeTwoPoints`
/// **Lines:** 4797-4806
///
/// Used by Gradient.linear to encode the `from` and `to` points.
private func encodeTwoPoints(_ pointA: Offset, _ pointB: Offset) -> [Float] {
  assert(offsetIsValid(pointA))
  assert(offsetIsValid(pointB))
  return [
    Float(pointA.dx),
    Float(pointA.dy),
    Float(pointB.dx),
    Float(pointB.dy),
  ]
}

// MARK: - Private Async Helper Functions and Typedefs

/// Callback type for async native operations.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_Callback`
/// **Lines:** 7974
///
/// A function that receives a result of type T.
private typealias _Callback<T> = @Sendable (T) -> Void

/// Callback type for async native operations with error parameter.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_CallbackWithError`
/// **Lines:** 7977
///
/// A function that receives a result of type T and an optional error string.
private typealias _CallbackWithError<T> = @Sendable (T, String?) -> Void

/// A function that accepts a callback and invokes it asynchronously.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_Callbacker`
/// **Lines:** 7983
///
/// Returns an error string if the operation cannot be started, nil otherwise.
private typealias _Callbacker<T> = @Sendable (@escaping _Callback<T?>) -> String?

/// A function that accepts an error-aware callback and invokes it asynchronously.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_CallbackerWithError`
/// **Lines:** 7987
///
/// Returns an error string if the operation cannot be started, nil otherwise.
private typealias _CallbackerWithError<T> = @Sendable (@escaping _CallbackWithError<T?>) -> String?

/// Converts a callback-based async operation into a Swift async function.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_futurize`
/// **Lines:** 8016-8038
///
/// The callbacker is expected to invoke the callback exactly once with
/// either a non-nil result or nil (indicating failure).
///
/// DIFFERENCE FROM DART: Uses Swift async/await with CheckedContinuation
/// instead of Dart Completer. The sync/async error distinction from Dart
/// is not applicable in Swift's structured concurrency model.
/// REASON: Swift's concurrency model handles this pattern differently.
private func futurize<T: Sendable>(_ callbacker: @escaping _Callbacker<T>) async throws -> T {
  return try await withCheckedThrowingContinuation { continuation in
    let error = callbacker { result in
      if let result = result {
        continuation.resume(returning: result)
      } else {
        continuation.resume(throwing: PaintingError.operationFailed("operation failed"))
      }
    }
    if let error = error {
      continuation.resume(throwing: PaintingError.operationFailed(error))
    }
  }
}

/// A variant of `futurize` that can communicate specific errors.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_futurizeWithError`
/// **Lines:** 8040-8063
///
/// Similar to `futurize`, but the callback receives both a result and
/// an optional error string.
///
/// DIFFERENCE FROM DART: Uses Swift async/await with CheckedContinuation
/// instead of Dart Completer. The sync/async error distinction from Dart
/// is not applicable in Swift's structured concurrency model.
/// REASON: Swift's concurrency model handles this pattern differently.
private func futurizeWithError<T: Sendable>(_ callbacker: @escaping _CallbackerWithError<T>) async throws -> T {
  return try await withCheckedThrowingContinuation { continuation in
    let error = callbacker { result, errorMessage in
      if let result = result {
        continuation.resume(returning: result)
      } else {
        continuation.resume(
          throwing: PaintingError.operationFailed(errorMessage ?? "operation failed"))
      }
    }
    if let error = error {
      continuation.resume(throwing: PaintingError.operationFailed(error))
    }
  }
}

/// Error type for painting async operations.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Lines:** 8016-8063
///
/// DIFFERENCE FROM DART: Uses a dedicated error enum instead of generic Exception.
/// REASON: Swift encourages typed errors over string-based exceptions.
enum PaintingError: Error, CustomStringConvertible {
  case operationFailed(String)

  var description: String {
    switch self {
    case .operationFailed(let message):
      return "PaintingError: \(message)"
    }
  }
}

/// Decodes an image from a byte list asynchronously.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/painting.dart`
/// **Original Name:** `_decodeImageFromListAsync`
/// **Lines:** 2636-2645
///
/// Instantiates a codec from the byte list, gets the first frame,
/// and passes the resulting image to the callback.
func decodeImageFromListAsync(_ list: [UInt8], _ callback: @escaping ImageDecoderCallback) async throws {
  let codec = try await instantiateImageCodec(list)
  let frameInfo: FrameInfo
  do {
    frameInfo = try await codec.getNextFrame()
  } catch {
    codec.dispose()
    throw error
  }
  codec.dispose()
  callback(frameInfo.image)
}

// MARK: - ColorFilter as ImageFilter

/// In Dart, `ColorFilter implements ImageFilter`. The Swift port deferred the
/// protocol conformance (see ImageFilter type doc). Adding it here lets a
/// ColorFilter be used wherever an ImageFilter is expected — in particular as
/// the outer filter in `ImageFilterFactory.compose(outer:inner:)` so a
/// `BackdropFilter` can do blur AND a color matrix (e.g. saturation boost)
/// in a single pass.
extension ColorFilter: ImageFilter {
    // shortDescription is already public on ColorFilter (was internal,
    // promoted to public when this conformance was added).
    public func toNativeImageFilter() -> NativeImageFilter {
        return NativeImageFilter(colorFilter: self)
    }
}
