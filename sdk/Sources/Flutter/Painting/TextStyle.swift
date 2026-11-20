// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// An immutable style describing how to format and paint text.
///
/// **Dart Source:** `packages/flutter/lib/src/painting/text_style.dart`

import FlutterSwiftBridge

// MARK: - Paint Equality Helper

/// Compares two optional Paint values by identity (reference equality).
///
/// Paint is a reference type (class) that does not conform to Equatable,
/// so we compare by object identity using `===`.
private func _paintEquals(_ a: Paint?, _ b: Paint?) -> Bool {
    if a == nil && b == nil { return true }
    guard let a = a, let b = b else { return false }
    return a === b
}

// MARK: - Constants

/// The default debug label for TextStyle instances.
///
/// **Dart Source:** `text_style.dart:21`
private let _kDefaultDebugLabel = "unknown"

/// Warning message for color/foreground conflict.
///
/// **Dart Source:** `text_style.dart:23-25`
private let _kColorForegroundWarning =
    "Cannot provide both a color and a foreground\n"
    + "The color argument is just a shorthand for \"foreground: Paint()..color = color\"."

/// Warning message for backgroundColor/background conflict.
///
/// **Dart Source:** `text_style.dart:27-29`
private let _kColorBackgroundWarning =
    "Cannot provide both a backgroundColor and a background\n"
    + "The backgroundColor argument is just a shorthand for \"background: Paint()..color = color\"."

/// The default font size used by `getParagraphStyle` when `fontSize` is null.
///
/// **Dart Source:** `packages/flutter/lib/src/painting/text_painter.dart`
/// (referenced as `kDefaultFontSize`)
public let kDefaultFontSize: Double = 14.0

// MARK: - TextOverflow

/// How overflowing text should be handled.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/paragraph.dart`
/// This is normally in the rendering layer, but is needed here for TextStyle.
public enum TextOverflow: Sendable, Hashable {
    /// Clip the overflowing text to fix its container.
    case clip

    /// Fade the overflowing text to transparent.
    case fade

    /// Use an ellipsis to indicate that the text has overflowed.
    case ellipsis

    /// Render overflowing text outside of its container.
    case visible
}

// MARK: - TextStyle

/// An immutable style describing how to format and paint text.
///
/// **Dart Source:** `packages/flutter/lib/src/painting/text_style.dart`
/// **Original Name:** `TextStyle`
/// **Lines:** 466-1682
public struct TextStyle: Hashable, CustomStringConvertible {

    // MARK: - Properties

    /// Whether null values in this `TextStyle` can be replaced with their value
    /// in another `TextStyle` using `merge`.
    ///
    /// **Dart Source:** `text_style.dart:534`
    public let inherit: Bool

    /// The color to use when painting the text.
    ///
    /// If `foreground` is specified, this value must be nil.
    ///
    /// **Dart Source:** `text_style.dart:544`
    public let color: Color?

    /// The color to use as the background for the text.
    ///
    /// If `background` is specified, this value must be nil.
    ///
    /// **Dart Source:** `text_style.dart:555`
    public let backgroundColor: Color?

    /// The name of the font to use when painting the text (e.g., Roboto).
    ///
    /// If the font is defined in a package, this will be prefixed with
    /// 'packages/package_name/'.
    ///
    /// **Dart Source:** `text_style.dart:578`
    public let fontFamily: String?

    /// The backing store for `fontFamilyFallback`.
    ///
    /// **Dart Source:** `text_style.dart:604`
    private let _fontFamilyFallback: [String]?

    /// The package name used to prefix font families.
    ///
    /// **Dart Source:** `text_style.dart:608`
    private let _package: String?

    /// The size of fonts (in logical pixels) to use when painting the text.
    ///
    /// **Dart Source:** `text_style.dart:623`
    public let fontSize: Double?

    /// The typeface thickness to use when painting the text (e.g., bold).
    ///
    /// **Dart Source:** `text_style.dart:626`
    public let fontWeight: FontWeight?

    /// The typeface variant to use when drawing the letters (e.g., italics).
    ///
    /// **Dart Source:** `text_style.dart:629`
    public let fontStyle: FontStyle?

    /// The amount of space (in logical pixels) to add between each letter.
    ///
    /// **Dart Source:** `text_style.dart:633`
    public let letterSpacing: Double?

    /// The amount of space (in logical pixels) to add at each sequence of
    /// white-space (i.e. between each word).
    ///
    /// **Dart Source:** `text_style.dart:638`
    public let wordSpacing: Double?

    /// How far the text's baseline is moved down from the line's, in
    /// logical pixels (negative: up) — skparagraph's baseline shift. The
    /// text keeps its place in the line and in its order: a raised note
    /// mark drawn this way is read where it stands, not after its line.
    /// (Starling, no Dart counterpart.)
    public let baselineShift: Double?
    /// Starling: the glyphs drawn and advanced this much narrower (under 1)
    /// or wider — SkFont::setScaleX, through the engine's
    /// patches/skia-scale-x.patch; nil or 1 for none. (No Dart counterpart.)
    public let scaleX: Double?
    /// Starling: this run's ascent and descent, positive logical-pixel distances
    /// from its baseline, in place of its face's (both or neither) —
    /// `ui.TextStyle.ascentOverride`, through the engine's
    /// patches/skia-style-line-indents-metrics.patch. (No Dart counterpart.)
    public let ascentOverride: Double?
    public let descentOverride: Double?

    /// The common baseline that should be aligned between this text span and its
    /// parent text span, or, for the root text spans, with the line box.
    ///
    /// **Dart Source:** `text_style.dart:642`
    public let textBaseline: TextBaseline?

    /// The height of this text span, as a multiple of the font size.
    ///
    /// **Dart Source:** `text_style.dart:666`
    public let height: Double?

    /// How the vertical space added by the `height` multiplier should be
    /// distributed over and under the text.
    ///
    /// **Dart Source:** `text_style.dart:682`
    public let leadingDistribution: TextLeadingDistribution?

    /// The locale used to select region-specific glyphs.
    ///
    /// **Dart Source:** `text_style.dart:692`
    public let locale: Locale?

    /// The paint drawn as a foreground for the text.
    ///
    /// If `color` is specified, this value must be nil.
    ///
    /// **Dart Source:** `text_style.dart:707`
    public let foreground: Paint?

    /// The paint drawn as a background for the text.
    ///
    /// If `backgroundColor` is specified, this value must be nil.
    ///
    /// **Dart Source:** `text_style.dart:724`
    public let background: Paint?

    /// The decorations to paint near the text (e.g., an underline).
    ///
    /// **Dart Source:** `text_style.dart:729`
    public let decoration: TextDecoration?

    /// The color in which to paint the text decorations.
    ///
    /// **Dart Source:** `text_style.dart:732`
    public let decorationColor: Color?

    /// The style in which to paint the text decorations (e.g., dashed).
    ///
    /// **Dart Source:** `text_style.dart:735`
    public let decorationStyle: TextDecorationStyle?

    /// The thickness of the decoration stroke as a multiplier of the thickness
    /// defined by the font.
    ///
    /// **Dart Source:** `text_style.dart:780`
    public let decorationThickness: Double?

    /// A human-readable description of this text style.
    ///
    /// This property is not considered when comparing text styles using `==` or
    /// `compareTo`, and it does not affect `hashCode`.
    ///
    /// **Dart Source:** `text_style.dart:793`
    public let debugLabel: String?

    /// A list of `Shadow`s that will be painted underneath the text.
    ///
    /// **Dart Source:** `text_style.dart:802`
    public let shadows: [Shadow]?

    /// A list of `FontFeature`s that affect how the font selects glyphs.
    ///
    /// **Dart Source:** `text_style.dart:817`
    public let fontFeatures: [FontFeature]?

    /// A list of `FontVariation`s that affect how a variable font is rendered.
    ///
    /// **Dart Source:** `text_style.dart:842`
    public let fontVariations: [FontVariation]?

    /// How visual text overflow should be handled.
    ///
    /// **Dart Source:** `text_style.dart:845`
    public let overflow: TextOverflow?

    // MARK: - Computed Properties

    /// The ordered list of font families to fall back on when a glyph cannot be
    /// found in a higher priority font family.
    ///
    /// If the font is defined in a package, each font family in the list will be
    /// prefixed with 'packages/package_name/'.
    ///
    /// **Dart Source:** `text_style.dart:601-603`
    public var fontFamilyFallback: [String]? {
        if let package = _package, let fallback = _fontFamilyFallback {
            return fallback.map { "packages/\(package)/\($0)" }
        }
        return _fontFamilyFallback
    }

    /// Return the original value of fontFamily, without the additional
    /// "packages/$_package/" prefix.
    ///
    /// **Dart Source:** `text_style.dart:849-856`
    private var _fontFamily: String? {
        if let package = _package {
            let prefix = "packages/\(package)/"
            assert(fontFamily?.hasPrefix(prefix) ?? true)
            if let family = fontFamily, family.hasPrefix(prefix) {
                return String(family.dropFirst(prefix.count))
            }
        }
        return fontFamily
    }

    // MARK: - Initializer

    /// Creates a text style.
    ///
    /// The `package` argument must be non-nil if the font family is defined in a
    /// package. It is combined with the `fontFamily` argument to set the
    /// `fontFamily` property.
    ///
    /// **Dart Source:** `text_style.dart:480-511`
    public init(
        inherit: Bool = true,
        color: Color? = nil,
        backgroundColor: Color? = nil,
        fontSize: Double? = nil,
        fontWeight: FontWeight? = nil,
        fontStyle: FontStyle? = nil,
        letterSpacing: Double? = nil,
        wordSpacing: Double? = nil,
        baselineShift: Double? = nil,
        scaleX: Double? = nil,
        ascentOverride: Double? = nil,
        descentOverride: Double? = nil,
        textBaseline: TextBaseline? = nil,
        height: Double? = nil,
        leadingDistribution: TextLeadingDistribution? = nil,
        locale: Locale? = nil,
        foreground: Paint? = nil,
        background: Paint? = nil,
        shadows: [Shadow]? = nil,
        fontFeatures: [FontFeature]? = nil,
        fontVariations: [FontVariation]? = nil,
        decoration: TextDecoration? = nil,
        decorationColor: Color? = nil,
        decorationStyle: TextDecorationStyle? = nil,
        decorationThickness: Double? = nil,
        debugLabel: String? = nil,
        fontFamily: String? = nil,
        fontFamilyFallback: [String]? = nil,
        package: String? = nil,
        overflow: TextOverflow? = nil
    ) {
        assert(color == nil || foreground == nil, _kColorForegroundWarning)
        assert(backgroundColor == nil || background == nil, _kColorBackgroundWarning)

        self.inherit = inherit
        self.color = color
        self.backgroundColor = backgroundColor
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.letterSpacing = letterSpacing
        self.wordSpacing = wordSpacing
        self.baselineShift = baselineShift
        self.scaleX = scaleX
        self.ascentOverride = ascentOverride
        self.descentOverride = descentOverride
        self.textBaseline = textBaseline
        self.height = height
        self.leadingDistribution = leadingDistribution
        self.locale = locale
        self.foreground = foreground
        self.background = background
        self.shadows = shadows
        self.fontFeatures = fontFeatures
        self.fontVariations = fontVariations
        self.decoration = decoration
        self.decorationColor = decorationColor
        self.decorationStyle = decorationStyle
        self.decorationThickness = decorationThickness
        self.debugLabel = debugLabel
        self.overflow = overflow

        // Prefix fontFamily with package if provided
        if let package = package, let family = fontFamily {
            self.fontFamily = "packages/\(package)/\(family)"
        } else {
            self.fontFamily = fontFamily
        }

        self._fontFamilyFallback = fontFamilyFallback
        self._package = package
    }

    // MARK: - copyWith

    /// Creates a copy of this text style but with the given fields replaced with
    /// the new values.
    ///
    /// One of `color` or `foreground` must be nil, and if this has `foreground`
    /// specified it will be given preference over any color parameter.
    ///
    /// One of `backgroundColor` or `background` must be nil, and if this has
    /// `background` specified it will be given preference over any
    /// backgroundColor parameter.
    ///
    /// **Dart Source:** `text_style.dart:867-937`
    public func copyWith(
        inherit: Bool? = nil,
        color: Color? = nil,
        backgroundColor: Color? = nil,
        fontSize: Double? = nil,
        fontWeight: FontWeight? = nil,
        fontStyle: FontStyle? = nil,
        letterSpacing: Double? = nil,
        wordSpacing: Double? = nil,
        baselineShift: Double? = nil,
        scaleX: Double? = nil,
        ascentOverride: Double? = nil,
        descentOverride: Double? = nil,
        textBaseline: TextBaseline? = nil,
        height: Double? = nil,
        leadingDistribution: TextLeadingDistribution? = nil,
        locale: Locale? = nil,
        foreground: Paint? = nil,
        background: Paint? = nil,
        shadows: [Shadow]? = nil,
        fontFeatures: [FontFeature]? = nil,
        fontVariations: [FontVariation]? = nil,
        decoration: TextDecoration? = nil,
        decorationColor: Color? = nil,
        decorationStyle: TextDecorationStyle? = nil,
        decorationThickness: Double? = nil,
        debugLabel: String? = nil,
        fontFamily: String? = nil,
        fontFamilyFallback: [String]? = nil,
        package: String? = nil,
        overflow: TextOverflow? = nil
    ) -> TextStyle {
        assert(color == nil || foreground == nil, _kColorForegroundWarning)
        assert(backgroundColor == nil || background == nil, _kColorBackgroundWarning)

        var newDebugLabel: String? = nil
        if let label = debugLabel {
            newDebugLabel = label
        } else if let existingLabel = self.debugLabel {
            newDebugLabel = "(\(existingLabel)).copyWith"
        }

        return TextStyle(
            inherit: inherit ?? self.inherit,
            color: self.foreground == nil && foreground == nil ? color ?? self.color : nil,
            backgroundColor: self.background == nil && background == nil
                ? backgroundColor ?? self.backgroundColor
                : nil,
            fontSize: fontSize ?? self.fontSize,
            fontWeight: fontWeight ?? self.fontWeight,
            fontStyle: fontStyle ?? self.fontStyle,
            letterSpacing: letterSpacing ?? self.letterSpacing,
            wordSpacing: wordSpacing ?? self.wordSpacing,
            baselineShift: baselineShift ?? self.baselineShift,
            scaleX: scaleX ?? self.scaleX,
            ascentOverride: ascentOverride ?? self.ascentOverride,
            descentOverride: descentOverride ?? self.descentOverride,
            textBaseline: textBaseline ?? self.textBaseline,
            height: height ?? self.height,
            leadingDistribution: leadingDistribution ?? self.leadingDistribution,
            locale: locale ?? self.locale,
            foreground: foreground ?? self.foreground,
            background: background ?? self.background,
            shadows: shadows ?? self.shadows,
            fontFeatures: fontFeatures ?? self.fontFeatures,
            fontVariations: fontVariations ?? self.fontVariations,
            decoration: decoration ?? self.decoration,
            decorationColor: decorationColor ?? self.decorationColor,
            decorationStyle: decorationStyle ?? self.decorationStyle,
            decorationThickness: decorationThickness ?? self.decorationThickness,
            debugLabel: newDebugLabel,
            fontFamily: fontFamily ?? self._fontFamily,
            fontFamilyFallback: fontFamilyFallback ?? self._fontFamilyFallback,
            package: package ?? self._package,
            overflow: overflow ?? self.overflow
        )
    }

    // MARK: - apply

    /// Creates a copy of this text style replacing or altering the specified
    /// properties.
    ///
    /// The non-numeric properties `color`, `fontFamily`, `decoration`,
    /// `decorationColor` and `decorationStyle` are replaced with the new values.
    ///
    /// The numeric properties are multiplied by the given factors and then
    /// incremented by the given deltas.
    ///
    /// **Dart Source:** `text_style.dart:967-1052`
    public func apply(
        color: Color? = nil,
        backgroundColor: Color? = nil,
        decoration: TextDecoration? = nil,
        decorationColor: Color? = nil,
        decorationStyle: TextDecorationStyle? = nil,
        decorationThicknessFactor: Double = 1.0,
        decorationThicknessDelta: Double = 0.0,
        fontFamily: String? = nil,
        fontFamilyFallback: [String]? = nil,
        fontSizeFactor: Double = 1.0,
        fontSizeDelta: Double = 0.0,
        fontWeightDelta: Int = 0,
        fontStyle: FontStyle? = nil,
        letterSpacingFactor: Double = 1.0,
        letterSpacingDelta: Double = 0.0,
        wordSpacingFactor: Double = 1.0,
        wordSpacingDelta: Double = 0.0,
        heightFactor: Double = 1.0,
        heightDelta: Double = 0.0,
        textBaseline: TextBaseline? = nil,
        leadingDistribution: TextLeadingDistribution? = nil,
        locale: Locale? = nil,
        shadows: [Shadow]? = nil,
        fontFeatures: [FontFeature]? = nil,
        fontVariations: [FontVariation]? = nil,
        package: String? = nil,
        overflow: TextOverflow? = nil
    ) -> TextStyle {
        assert(self.fontSize != nil || (fontSizeFactor == 1.0 && fontSizeDelta == 0.0))
        assert(self.fontWeight != nil || fontWeightDelta == 0)
        assert(self.letterSpacing != nil || (letterSpacingFactor == 1.0 && letterSpacingDelta == 0.0))
        assert(self.wordSpacing != nil || (wordSpacingFactor == 1.0 && wordSpacingDelta == 0.0))
        assert(
            self.decorationThickness != nil
                || (decorationThicknessFactor == 1.0 && decorationThicknessDelta == 0.0)
        )

        var modifiedDebugLabel: String? = nil
        if let label = self.debugLabel {
            modifiedDebugLabel = "(\(label)).apply"
        }

        let newFontWeight: FontWeight?
        if let weight = self.fontWeight {
            let newIndex = min(max(weight.index + fontWeightDelta, 0), FontWeight.values.count - 1)
            newFontWeight = FontWeight.values[newIndex]
        } else {
            newFontWeight = nil
        }

        let newHeight: Double?
        if self.height == nil || self.height == kTextHeightNone {
            newHeight = self.height
        } else {
            newHeight = self.height! * heightFactor + heightDelta
        }

        return TextStyle(
            inherit: self.inherit,
            color: self.foreground == nil ? color ?? self.color : nil,
            backgroundColor: self.background == nil ? backgroundColor ?? self.backgroundColor : nil,
            fontSize: self.fontSize == nil ? nil : self.fontSize! * fontSizeFactor + fontSizeDelta,
            fontWeight: newFontWeight,
            fontStyle: fontStyle ?? self.fontStyle,
            letterSpacing: self.letterSpacing == nil
                ? nil
                : self.letterSpacing! * letterSpacingFactor + letterSpacingDelta,
            wordSpacing: self.wordSpacing == nil
                ? nil
                : self.wordSpacing! * wordSpacingFactor + wordSpacingDelta,
            baselineShift: self.baselineShift,
            scaleX: self.scaleX,
            ascentOverride: self.ascentOverride,
            descentOverride: self.descentOverride,
            textBaseline: textBaseline ?? self.textBaseline,
            height: newHeight,
            leadingDistribution: leadingDistribution ?? self.leadingDistribution,
            locale: locale ?? self.locale,
            foreground: self.foreground,
            background: self.background,
            shadows: shadows ?? self.shadows,
            fontFeatures: fontFeatures ?? self.fontFeatures,
            fontVariations: fontVariations ?? self.fontVariations,
            decoration: decoration ?? self.decoration,
            decorationColor: decorationColor ?? self.decorationColor,
            decorationStyle: decorationStyle ?? self.decorationStyle,
            decorationThickness: self.decorationThickness == nil
                ? nil
                : self.decorationThickness! * decorationThicknessFactor + decorationThicknessDelta,
            debugLabel: modifiedDebugLabel,
            fontFamily: fontFamily ?? self._fontFamily,
            fontFamilyFallback: fontFamilyFallback ?? self._fontFamilyFallback,
            package: package ?? self._package,
            overflow: overflow ?? self.overflow
        )
    }

    // MARK: - merge

    /// Returns a new text style that is a combination of this style and the given
    /// `other` style.
    ///
    /// If the given `other` text style has its `inherit` set to true,
    /// its nil properties are replaced with the non-nil properties of this text
    /// style. The `other` style _inherits_ the properties of this style.
    ///
    /// If the given `other` text style has its `inherit` set to false,
    /// returns the given `other` style unchanged.
    ///
    /// If the given text style is nil, returns this text style.
    ///
    /// **Dart Source:** `text_style.dart:1075-1119`
    public func merge(_ other: TextStyle?) -> TextStyle {
        guard let other = other else {
            return self
        }
        if !other.inherit {
            return other
        }

        var mergedDebugLabel: String? = nil
        if other.debugLabel != nil || self.debugLabel != nil {
            mergedDebugLabel =
                "(\(self.debugLabel ?? _kDefaultDebugLabel)).merge(\(other.debugLabel ?? _kDefaultDebugLabel))"
        }

        return copyWith(
            color: other.color,
            backgroundColor: other.backgroundColor,
            fontSize: other.fontSize,
            fontWeight: other.fontWeight,
            fontStyle: other.fontStyle,
            letterSpacing: other.letterSpacing,
            wordSpacing: other.wordSpacing,
            baselineShift: other.baselineShift,
            scaleX: other.scaleX,
            ascentOverride: other.ascentOverride,
            descentOverride: other.descentOverride,
            textBaseline: other.textBaseline,
            height: other.height,
            leadingDistribution: other.leadingDistribution,
            locale: other.locale,
            foreground: other.foreground,
            background: other.background,
            shadows: other.shadows,
            fontFeatures: other.fontFeatures,
            fontVariations: other.fontVariations,
            decoration: other.decoration,
            decorationColor: other.decorationColor,
            decorationStyle: other.decorationStyle,
            decorationThickness: other.decorationThickness,
            debugLabel: mergedDebugLabel,
            fontFamily: other._fontFamily,
            fontFamilyFallback: other._fontFamilyFallback,
            package: other._package,
            overflow: other.overflow
        )
    }

    // MARK: - lerp

    /// Interpolate between two text styles for animated transitions.
    ///
    /// If both `a` and `b` are nil, returns nil.
    ///
    /// **Dart Source:** `text_style.dart:1144-1330`
    public static func lerp(_ a: TextStyle?, _ b: TextStyle?, _ t: Double) -> TextStyle? {
        if a == nil && b == nil {
            return nil
        }
        // For structs we can't use `identical`, but we can check equality
        if let a = a, let b = b, a == b {
            return a
        }

        var lerpDebugLabel: String? = nil
        if a?.debugLabel != nil || b?.debugLabel != nil {
            lerpDebugLabel =
                "lerp(\(a?.debugLabel ?? _kDefaultDebugLabel) \u{23AF}\(String(format: "%.1f", t))\u{2192} \(b?.debugLabel ?? _kDefaultDebugLabel))"
        }

        if a == nil {
            return TextStyle(
                inherit: b!.inherit,
                color: Color.lerp(nil, b!.color, t),
                backgroundColor: Color.lerp(nil, b!.backgroundColor, t),
                fontSize: t < 0.5 ? nil : b!.fontSize,
                fontWeight: FontWeight.lerp(nil, b!.fontWeight, t),
                fontStyle: t < 0.5 ? nil : b!.fontStyle,
                letterSpacing: t < 0.5 ? nil : b!.letterSpacing,
                wordSpacing: t < 0.5 ? nil : b!.wordSpacing,
                baselineShift: t < 0.5 ? nil : b!.baselineShift,
                scaleX: t < 0.5 ? nil : b!.scaleX,
                ascentOverride: t < 0.5 ? nil : b!.ascentOverride,
                descentOverride: t < 0.5 ? nil : b!.descentOverride,
                textBaseline: t < 0.5 ? nil : b!.textBaseline,
                height: t < 0.5 ? nil : b!.height,
                leadingDistribution: t < 0.5 ? nil : b!.leadingDistribution,
                locale: t < 0.5 ? nil : b!.locale,
                foreground: t < 0.5 ? nil : b!.foreground,
                background: t < 0.5 ? nil : b!.background,
                shadows: t < 0.5 ? nil : b!.shadows,
                fontFeatures: t < 0.5 ? nil : b!.fontFeatures,
                fontVariations: lerpFontVariations(nil, b!.fontVariations, t),
                decoration: t < 0.5 ? nil : b!.decoration,
                decorationColor: Color.lerp(nil, b!.decorationColor, t),
                decorationStyle: t < 0.5 ? nil : b!.decorationStyle,
                decorationThickness: t < 0.5 ? nil : b!.decorationThickness,
                debugLabel: lerpDebugLabel,
                fontFamily: t < 0.5 ? nil : b!._fontFamily,
                fontFamilyFallback: t < 0.5 ? nil : b!._fontFamilyFallback,
                package: t < 0.5 ? nil : b!._package,
                overflow: t < 0.5 ? nil : b!.overflow
            )
        }

        if b == nil {
            return TextStyle(
                inherit: a!.inherit,
                color: Color.lerp(a!.color, nil, t),
                backgroundColor: Color.lerp(nil, a!.backgroundColor, t),
                fontSize: t < 0.5 ? a!.fontSize : nil,
                fontWeight: FontWeight.lerp(a!.fontWeight, nil, t),
                fontStyle: t < 0.5 ? a!.fontStyle : nil,
                letterSpacing: t < 0.5 ? a!.letterSpacing : nil,
                wordSpacing: t < 0.5 ? a!.wordSpacing : nil,
                baselineShift: t < 0.5 ? a!.baselineShift : nil,
                scaleX: t < 0.5 ? a!.scaleX : nil,
                ascentOverride: t < 0.5 ? a!.ascentOverride : nil,
                descentOverride: t < 0.5 ? a!.descentOverride : nil,
                textBaseline: t < 0.5 ? a!.textBaseline : nil,
                height: t < 0.5 ? a!.height : nil,
                leadingDistribution: t < 0.5 ? a!.leadingDistribution : nil,
                locale: t < 0.5 ? a!.locale : nil,
                foreground: t < 0.5 ? a!.foreground : nil,
                background: t < 0.5 ? a!.background : nil,
                shadows: t < 0.5 ? a!.shadows : nil,
                fontFeatures: t < 0.5 ? a!.fontFeatures : nil,
                fontVariations: lerpFontVariations(a!.fontVariations, nil, t),
                decoration: t < 0.5 ? a!.decoration : nil,
                decorationColor: Color.lerp(a!.decorationColor, nil, t),
                decorationStyle: t < 0.5 ? a!.decorationStyle : nil,
                decorationThickness: t < 0.5 ? a!.decorationThickness : nil,
                debugLabel: lerpDebugLabel,
                fontFamily: t < 0.5 ? a!._fontFamily : nil,
                fontFamilyFallback: t < 0.5 ? a!._fontFamilyFallback : nil,
                package: t < 0.5 ? a!._package : nil,
                overflow: t < 0.5 ? a!.overflow : nil
            )
        }

        let a = a!
        let b = b!

        // Foreground handling: if either side has foreground, construct Paint from color
        let lerpForeground: Paint?
        if a.foreground != nil || b.foreground != nil {
            if t < 0.5 {
                lerpForeground = a.foreground ?? {
                    let p = Paint()
                    p.color = a.color!
                    return p
                }()
            } else {
                lerpForeground = b.foreground ?? {
                    let p = Paint()
                    p.color = b.color!
                    return p
                }()
            }
        } else {
            lerpForeground = nil
        }

        // Background handling: if either side has background, construct Paint from backgroundColor
        let lerpBackground: Paint?
        if a.background != nil || b.background != nil {
            if t < 0.5 {
                lerpBackground = a.background ?? {
                    let p = Paint()
                    p.color = a.backgroundColor!
                    return p
                }()
            } else {
                lerpBackground = b.background ?? {
                    let p = Paint()
                    p.color = b.backgroundColor!
                    return p
                }()
            }
        } else {
            lerpBackground = nil
        }

        return TextStyle(
            inherit: t < 0.5 ? a.inherit : b.inherit,
            color: a.foreground == nil && b.foreground == nil
                ? Color.lerp(a.color, b.color, t) : nil,
            backgroundColor: a.background == nil && b.background == nil
                ? Color.lerp(a.backgroundColor, b.backgroundColor, t) : nil,
            fontSize: lerpDouble(a.fontSize ?? b.fontSize, b.fontSize ?? a.fontSize, t),
            fontWeight: FontWeight.lerp(a.fontWeight, b.fontWeight, t),
            fontStyle: t < 0.5 ? a.fontStyle : b.fontStyle,
            letterSpacing: lerpDouble(
                a.letterSpacing ?? b.letterSpacing,
                b.letterSpacing ?? a.letterSpacing,
                t
            ),
            wordSpacing: lerpDouble(
                a.wordSpacing ?? b.wordSpacing,
                b.wordSpacing ?? a.wordSpacing,
                t
            ),
            baselineShift: t < 0.5 ? a.baselineShift : b.baselineShift,
            scaleX: t < 0.5 ? a.scaleX : b.scaleX,
            ascentOverride: t < 0.5 ? a.ascentOverride : b.ascentOverride,
            descentOverride: t < 0.5 ? a.descentOverride : b.descentOverride,
            textBaseline: t < 0.5 ? a.textBaseline : b.textBaseline,
            height: lerpDouble(a.height ?? b.height, b.height ?? a.height, t),
            leadingDistribution: t < 0.5 ? a.leadingDistribution : b.leadingDistribution,
            locale: t < 0.5 ? a.locale : b.locale,
            foreground: lerpForeground,
            background: lerpBackground,
            shadows: Shadow.lerpList(a.shadows, b.shadows, t),
            fontFeatures: t < 0.5 ? a.fontFeatures : b.fontFeatures,
            fontVariations: lerpFontVariations(a.fontVariations, b.fontVariations, t),
            decoration: t < 0.5 ? a.decoration : b.decoration,
            decorationColor: Color.lerp(a.decorationColor, b.decorationColor, t),
            decorationStyle: t < 0.5 ? a.decorationStyle : b.decorationStyle,
            decorationThickness: lerpDouble(
                a.decorationThickness ?? b.decorationThickness,
                b.decorationThickness ?? a.decorationThickness,
                t
            ),
            debugLabel: lerpDebugLabel,
            fontFamily: t < 0.5 ? a._fontFamily : b._fontFamily,
            fontFamilyFallback: t < 0.5 ? a._fontFamilyFallback : b._fontFamilyFallback,
            package: t < 0.5 ? a._package : b._package,
            overflow: t < 0.5 ? a.overflow : b.overflow
        )
    }

    // MARK: - getTextStyle

    /// The style information for text runs, encoded for use by `dart:ui`.
    ///
    /// **Dart Source:** `text_style.dart:1333-1378`
    public func getTextStyle(
        textScaler: any TextScaler = TextScalers.noScaling
    ) -> FlutterSwiftBridge.TextStyle {
        let scaledFontSize: Double?
        if let size = self.fontSize {
            if textScaler == TextScalers.noScaling {
                scaledFontSize = size
            } else {
                scaledFontSize = textScaler.scale(size)
            }
        } else {
            scaledFontSize = nil
        }

        let effectiveBackground: Paint?
        if let bg = background {
            effectiveBackground = bg
        } else if let bgColor = backgroundColor {
            let p = Paint()
            p.color = bgColor
            effectiveBackground = p
        } else {
            effectiveBackground = nil
        }

        return FlutterSwiftBridge.TextStyle(
            color: color,
            decoration: decoration,
            decorationColor: decorationColor,
            decorationStyle: decorationStyle,
            decorationThickness: decorationThickness,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            textBaseline: textBaseline,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
            fontSize: scaledFontSize,
            letterSpacing: letterSpacing,
            wordSpacing: wordSpacing,
            baselineShift: baselineShift,
            scaleX: scaleX,
            ascentOverride: ascentOverride,
            descentOverride: descentOverride,
            height: height,
            leadingDistribution: leadingDistribution,
            locale: locale,
            background: effectiveBackground,
            foreground: foreground,
            shadows: shadows,
            fontFeatures: fontFeatures,
            fontVariations: fontVariations
        )
    }

    // MARK: - getParagraphStyle

    /// The style information for paragraphs, encoded for use by `dart:ui`.
    ///
    /// If the font size on this style isn't set, it will default to 14 logical
    /// pixels.
    ///
    /// **Dart Source:** `text_style.dart:1388-1442`
    public func getParagraphStyle(
        textAlign: TextAlign? = nil,
        textDirection: TextDirection? = nil,
        textScaler: any TextScaler = TextScalers.noScaling,
        ellipsis: String? = nil,
        maxLines: Int? = nil,
        textHeightBehavior: TextHeightBehavior? = nil,
        locale: Locale? = nil,
        fontFamily: String? = nil,
        fontSize: Double? = nil,
        fontWeight: FontWeight? = nil,
        fontStyle: FontStyle? = nil,
        height: Double? = nil,
        strutStyle: Flutter.StrutStyle? = nil
    ) -> FlutterSwiftBridge.ParagraphStyle {
        assert(maxLines == nil || maxLines! > 0)

        let ld = self.leadingDistribution
        let effectiveTextHeightBehavior: TextHeightBehavior?
        if let thb = textHeightBehavior {
            effectiveTextHeightBehavior = thb
        } else if let ld = ld {
            effectiveTextHeightBehavior = TextHeightBehavior(leadingDistribution: ld)
        } else {
            effectiveTextHeightBehavior = nil
        }

        let uiStrutStyle: FlutterSwiftBridge.StrutStyle?
        if let ss = strutStyle {
            let scaledStrutFontSize: Double?
            if let ssSize = ss.fontSize {
                scaledStrutFontSize = textScaler.scale(ssSize)
            } else {
                scaledStrutFontSize = nil
            }
            uiStrutStyle = FlutterSwiftBridge.StrutStyle(
                fontFamily: ss.fontFamily,
                fontFamilyFallback: ss.fontFamilyFallback,
                fontSize: scaledStrutFontSize,
                height: ss.height,
                leadingDistribution: ss.leadingDistribution,
                leading: ss.leading,
                fontWeight: ss.fontWeight,
                fontStyle: ss.fontStyle,
                forceStrutHeight: ss.forceStrutHeight
            )
        } else {
            uiStrutStyle = nil
        }

        return FlutterSwiftBridge.ParagraphStyle(
            textAlign: textAlign,
            textDirection: textDirection,
            maxLines: maxLines,
            fontFamily: fontFamily ?? self.fontFamily,
            fontSize: textScaler.scale(fontSize ?? self.fontSize ?? kDefaultFontSize),
            height: height ?? self.height,
            textHeightBehavior: effectiveTextHeightBehavior,
            fontWeight: fontWeight ?? self.fontWeight,
            fontStyle: fontStyle ?? self.fontStyle,
            strutStyle: uiStrutStyle,
            ellipsis: ellipsis,
            locale: locale
        )
    }

    // MARK: - compareTo

    /// Describe the difference between this style and another, in terms of how
    /// much damage it will make to the rendering.
    ///
    /// **Dart Source:** `text_style.dart:1450-1483`
    public func compareTo(_ other: TextStyle) -> RenderComparison {
        if self == other {
            return .identical
        }
        if inherit != other.inherit ||
            fontFamily != other.fontFamily ||
            fontSize != other.fontSize ||
            fontWeight != other.fontWeight ||
            fontStyle != other.fontStyle ||
            letterSpacing != other.letterSpacing ||
            wordSpacing != other.wordSpacing ||
            baselineShift != other.baselineShift ||
            scaleX != other.scaleX ||
            ascentOverride != other.ascentOverride ||
            descentOverride != other.descentOverride ||
            textBaseline != other.textBaseline ||
            height != other.height ||
            leadingDistribution != other.leadingDistribution ||
            locale != other.locale ||
            !_paintEquals(foreground, other.foreground) ||
            !_paintEquals(background, other.background) ||
            shadows != other.shadows ||
            fontFeatures != other.fontFeatures ||
            fontVariations != other.fontVariations ||
            fontFamilyFallback != other.fontFamilyFallback ||
            overflow != other.overflow
        {
            return .layout
        }
        if color != other.color ||
            backgroundColor != other.backgroundColor ||
            decoration != other.decoration ||
            decorationColor != other.decorationColor ||
            decorationStyle != other.decorationStyle ||
            decorationThickness != other.decorationThickness
        {
            return .paint
        }
        return .identical
    }

    // MARK: - Equatable

    /// Compares two text styles for equality.
    ///
    /// The `debugLabel` is not considered when comparing text styles.
    ///
    /// **Dart Source:** `text_style.dart:1486-1519`
    public static func == (lhs: TextStyle, rhs: TextStyle) -> Bool {
        return lhs.inherit == rhs.inherit &&
            lhs.color == rhs.color &&
            lhs.backgroundColor == rhs.backgroundColor &&
            lhs.fontSize == rhs.fontSize &&
            lhs.fontWeight == rhs.fontWeight &&
            lhs.fontStyle == rhs.fontStyle &&
            lhs.letterSpacing == rhs.letterSpacing &&
            lhs.wordSpacing == rhs.wordSpacing &&
            lhs.baselineShift == rhs.baselineShift &&
            lhs.scaleX == rhs.scaleX &&
            lhs.ascentOverride == rhs.ascentOverride &&
            lhs.descentOverride == rhs.descentOverride &&
            lhs.textBaseline == rhs.textBaseline &&
            lhs.height == rhs.height &&
            lhs.leadingDistribution == rhs.leadingDistribution &&
            lhs.locale == rhs.locale &&
            _paintEquals(lhs.foreground, rhs.foreground) &&
            _paintEquals(lhs.background, rhs.background) &&
            lhs.shadows == rhs.shadows &&
            lhs.fontFeatures == rhs.fontFeatures &&
            lhs.fontVariations == rhs.fontVariations &&
            lhs.decoration == rhs.decoration &&
            lhs.decorationColor == rhs.decorationColor &&
            lhs.decorationStyle == rhs.decorationStyle &&
            lhs.decorationThickness == rhs.decorationThickness &&
            lhs.fontFamily == rhs.fontFamily &&
            lhs.fontFamilyFallback == rhs.fontFamilyFallback &&
            lhs._package == rhs._package &&
            lhs.overflow == rhs.overflow
    }

    // MARK: - Hashable

    /// The hash code for this text style.
    ///
    /// **Dart Source:** `text_style.dart:1522-1558`
    public func hash(into hasher: inout Hasher) {
        hasher.combine(inherit)
        hasher.combine(color)
        hasher.combine(backgroundColor)
        hasher.combine(fontSize)
        hasher.combine(fontWeight)
        hasher.combine(fontStyle)
        hasher.combine(letterSpacing)
        hasher.combine(wordSpacing)
        hasher.combine(baselineShift)
        hasher.combine(scaleX)
        hasher.combine(ascentOverride)
        hasher.combine(descentOverride)
        hasher.combine(textBaseline)
        hasher.combine(height)
        hasher.combine(leadingDistribution)
        hasher.combine(locale)
        // Use ObjectIdentifier for Paint (reference type) since it's not Hashable
        if let fg = foreground {
            hasher.combine(ObjectIdentifier(fg))
        } else {
            hasher.combine(0 as Int)
        }
        if let bg = background {
            hasher.combine(ObjectIdentifier(bg))
        } else {
            hasher.combine(0 as Int)
        }
        hasher.combine(shadows)
        hasher.combine(fontFeatures)
        hasher.combine(fontVariations)
        hasher.combine(decoration)
        hasher.combine(decorationColor)
        hasher.combine(decorationStyle)
        hasher.combine(decorationThickness)
        hasher.combine(fontFamily)
        hasher.combine(fontFamilyFallback)
        hasher.combine(_package)
        hasher.combine(overflow)
    }

    // MARK: - CustomStringConvertible

    /// A string representation of this text style, matching the Dart diagnostics
    /// output format.
    ///
    /// **Dart Source:** `text_style.dart:1561` (`toStringShort`) and
    /// `text_style.dart:1565-1681` (`debugFillProperties`)
    public var description: String {
        var parts: [String] = []

        // debugLabel
        if let label = debugLabel {
            parts.append("debugLabel: \(label)")
        }

        // Collect style properties
        var styles: [String] = []

        // color
        if let c = color {
            styles.append("color: \(c)")
        }

        // backgroundColor
        if let bg = backgroundColor {
            styles.append("backgroundColor: \(bg)")
        }

        // family
        if let family = fontFamily {
            styles.append("family: \(family)")
        }

        // familyFallback
        if let fallback = fontFamilyFallback, !fallback.isEmpty {
            styles.append("familyFallback: [\(fallback.joined(separator: ", "))]")
        }

        // size
        if let size = fontSize {
            styles.append("size: \(debugFormatDouble(size))")
        }

        // weight
        if let weight = fontWeight {
            styles.append("weight: \(weight.index + 1)00")
        }

        // style
        if let style = fontStyle {
            let styleName: String
            switch style {
            case .normal: styleName = "normal"
            case .italic: styleName = "italic"
            @unknown default: styleName = "unknown"
            }
            styles.append("style: \(styleName)")
        }

        // letterSpacing
        if let ls = letterSpacing {
            styles.append("letterSpacing: \(debugFormatDouble(ls))")
        }

        // wordSpacing
        if let ws = wordSpacing {
            styles.append("wordSpacing: \(debugFormatDouble(ws))")
        }

        // baseline
        if let bl = textBaseline {
            let baseName: String
            switch bl {
            case .alphabetic: baseName = "alphabetic"
            case .ideographic: baseName = "ideographic"
            @unknown default: baseName = "unknown"
            }
            styles.append("baseline: \(baseName)")
        }

        // height
        if let h = height {
            styles.append("height: \(debugFormatDouble(h))x")
        }

        // leadingDistribution
        if let ld = leadingDistribution {
            let distName: String
            switch ld {
            case .proportional: distName = "proportional"
            case .even: distName = "even"
            @unknown default: distName = "unknown"
            }
            styles.append("leadingDistribution: \(distName)")
        }

        // locale
        if let loc = locale {
            styles.append("locale: \(loc)")
        }

        // foreground
        if let fg = foreground {
            styles.append("foreground: \(fg)")
        }

        // background
        if let bg = background {
            styles.append("background: \(bg)")
        }

        // decoration (collapsed summary like Dart)
        if decoration != nil || decorationColor != nil || decorationStyle != nil || decorationThickness != nil {
            var decorationParts: [String] = []
            if let ds = decorationStyle {
                decorationParts.append("\(ds)")
            }
            if let dc = decorationColor {
                decorationParts.append("\(dc)")
            }
            if let d = decoration {
                decorationParts.append("\(d)")
            }
            if !decorationParts.isEmpty {
                styles.append("decoration: \(decorationParts.joined(separator: " "))")
            }
            if let dt = decorationThickness {
                styles.append("decorationThickness: \(debugFormatDouble(dt))x")
            }
        }

        let styleSpecified = !styles.isEmpty

        // inherit
        parts.append("inherit: \(inherit)")

        // Add all style parts
        parts.append(contentsOf: styles)

        // overflow
        if let of = overflow {
            let overflowName: String
            switch of {
            case .clip: overflowName = "clip"
            case .fade: overflowName = "fade"
            case .ellipsis: overflowName = "ellipsis"
            case .visible: overflowName = "visible"
            }
            parts.append("overflow: \(overflowName)")
        }

        if !styleSpecified && inherit {
            return "TextStyle(<all styles inherited>)"
        }
        if !styleSpecified && !inherit {
            return "TextStyle(inherit: false, <no style specified>)"
        }

        return "TextStyle(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - lerpFontVariations

/// Interpolate between two lists of `FontVariation` objects.
///
/// Variations are paired by axis, and interpolated using `FontVariation.lerp`.
///
/// Entries that are only present in one list are animated using a step-function
/// at t=0.5 that enables or disables the variation.
///
/// **Dart Source:** `text_style.dart:1725-1774`
public func lerpFontVariations(
    _ a: [FontVariation]?,
    _ b: [FontVariation]?,
    _ t: Double
) -> [FontVariation]? {
    if t == 0.0 {
        return a
    }
    if t == 1.0 {
        return b
    }
    if a == nil || a!.isEmpty || b == nil || b!.isEmpty {
        return t < 0.5 ? a : b
    }
    let a = a!
    let b = b!
    assert(!a.isEmpty && !b.isEmpty)

    var result: [FontVariation] = []

    // First, try the efficient O(N) solution in the event that
    // the lists are compatible.
    var index = 0
    let minLength = min(a.count, b.count)
    while index < minLength {
        if a[index].axis != b[index].axis {
            break
        }
        if let v = FontVariation.lerp(a[index], b[index], t) {
            result.append(v)
        }
        index += 1
    }

    let maxLength = max(a.count, b.count)
    if index < maxLength {
        // If we get here, we have found some case where we cannot
        // use the efficient approach.
        var axes = Set<String>()
        var aVariations: [String: FontVariation] = [:]
        for indexA in index..<a.count {
            aVariations[a[indexA].axis] = a[indexA]
            axes.insert(a[indexA].axis)
        }
        var bVariations: [String: FontVariation] = [:]
        for indexB in index..<b.count {
            bVariations[b[indexB].axis] = b[indexB]
            axes.insert(b[indexB].axis)
        }
        for axis in axes {
            if let variation = FontVariation.lerp(aVariations[axis], bVariations[axis], t) {
                result.append(variation)
            }
        }
    }

    return result
}
