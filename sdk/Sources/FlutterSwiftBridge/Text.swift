// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
// Windows: the C library module is ucrt. Without this branch the file gets no
// platform C declarations at all, which is how M_E went missing here.
import ucrt
#endif
import FlutterSwiftBridgeCxx
import Foundation

// MARK: - kTextHeightNone

/// A [TextStyle.height] value that indicates the text span should take
/// the height defined by the font, which may not be exactly the height of
/// [TextStyle.fontSize].
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `kTextHeightNone`
/// **Lines:** 6-10
///
/// **Original:** `const double kTextHeightNone = 0.0;`
public let kTextHeightNone: Double = 0.0

// MARK: - FontStyle

/// Whether to use the italic type variation of glyphs in the font.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `FontStyle`
/// **Lines:** 12-26
///
/// Some modern fonts allow this to be selected in a more fine-grained manner.
/// See `FontVariation.italic` for details.
///
/// Italic type is distinct from slanted glyphs. To control the slant of a
/// glyph, consider the `FontVariation.slant` font feature.
public enum FontStyle: Int, Sendable {
  /// Use the upright ("Roman") glyphs.
  ///
  /// **Dart Source:** `text.dart:21`
  case normal = 0

  /// Use glyphs that have a more pronounced angle and typically a cursive style
  /// ("italic type").
  ///
  /// **Dart Source:** `text.dart:25`
  case italic = 1
}

// MARK: - TextAlign

/// Whether and how to align text horizontally.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextAlign`
/// **Lines:** 1273-1304
///
/// DIFFERENCE FROM DART: Using `Int` raw value for C++ bridge encoding.
/// REASON: Dart enums have implicit indices; Swift raw values serve the same purpose.
public enum TextAlign: Int, Sendable {
  /// Align the text on the left edge of the container.
  ///
  /// **Dart Source:** `text.dart:1277`
  case left = 0

  /// Align the text on the right edge of the container.
  ///
  /// **Dart Source:** `text.dart:1280`
  case right = 1

  /// Align the text in the center of the container.
  ///
  /// **Dart Source:** `text.dart:1283`
  case center = 2

  /// Stretch lines of text that end with a soft line break to fill the width of
  /// the container.
  ///
  /// Lines that end with hard line breaks are aligned towards the `start` edge.
  ///
  /// **Dart Source:** `text.dart:1289`
  case justify = 3

  /// Align the text on the leading edge of the container.
  ///
  /// For left-to-right text (`TextDirection.ltr`), this is the left edge.
  ///
  /// For right-to-left text (`TextDirection.rtl`), this is the right edge.
  ///
  /// **Dart Source:** `text.dart:1296`
  case start = 4

  /// Align the text on the trailing edge of the container.
  ///
  /// For left-to-right text (`TextDirection.ltr`), this is the right edge.
  ///
  /// For right-to-left text (`TextDirection.rtl`), this is the left edge.
  ///
  /// **Dart Source:** `text.dart:1303`
  case end = 5
}

// MARK: - TextBaseline

/// A horizontal line used for aligning text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextBaseline`
/// **Lines:** 1306-1313
///
/// DIFFERENCE FROM DART: Using `Int` raw value for C++ bridge encoding.
/// REASON: Dart enums have implicit indices; Swift raw values serve the same purpose.
public enum TextBaseline: Int, Sendable {
  /// The horizontal line used to align the bottom of glyphs for alphabetic
  /// characters.
  ///
  /// **Dart Source:** `text.dart:1309`
  case alphabetic = 0

  /// The horizontal line used to align ideographic characters.
  ///
  /// **Dart Source:** `text.dart:1312`
  case ideographic = 1
}

// MARK: - TextRange

/// A range of characters in a string of text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextRange`
/// **Lines:** 2581-2654
///
/// DIFFERENCE FROM DART: Using struct instead of class.
/// REASON: TextRange is an immutable value type; Swift structs with value
/// semantics are the idiomatic equivalent.
public struct TextRange: Equatable, Hashable, Sendable, CustomStringConvertible {
  /// The index of the first character in the range.
  ///
  /// If [start] and [end] are both -1, the text range is empty.
  ///
  /// **Dart Source:** `text.dart:2607`
  public let start: Int

  /// The next index after the characters in this range.
  ///
  /// If [start] and [end] are both -1, the text range is empty.
  ///
  /// **Dart Source:** `text.dart:2612`
  public let end: Int

  /// Creates a text range.
  ///
  /// The [start] and [end] must either be greater than or equal to zero or
  /// both exactly -1.
  ///
  /// **Dart Source:** `text.dart:2592-2594`
  /// **Original:** `const TextRange({required this.start, required this.end})`
  public init(start: Int, end: Int) {
    assert(start >= -1, "TextRange.start must be >= -1")
    assert(end >= -1, "TextRange.end must be >= -1")
    self.start = start
    self.end = end
  }

  /// A text range that starts and ends at offset.
  ///
  /// **Dart Source:** `text.dart:2599`
  /// **Original:** `const TextRange.collapsed(int offset)`
  public init(collapsed offset: Int) {
    assert(offset >= -1, "TextRange.collapsed offset must be >= -1")
    self.start = offset
    self.end = offset
  }

  /// A text range that contains nothing and is not in the text.
  ///
  /// **Dart Source:** `text.dart:2602`
  /// **Original:** `static const TextRange empty = TextRange(start: -1, end: -1);`
  public static let empty = TextRange(start: -1, end: -1)

  /// Whether this range represents a valid position in the text.
  ///
  /// **Dart Source:** `text.dart:2615`
  /// **Original:** `bool get isValid => start >= 0 && end >= 0;`
  public var isValid: Bool {
    start >= 0 && end >= 0
  }

  /// Whether this range is empty (but still potentially placed inside the text).
  ///
  /// **Dart Source:** `text.dart:2618`
  /// **Original:** `bool get isCollapsed => start == end;`
  public var isCollapsed: Bool {
    start == end
  }

  /// Whether the start of this range precedes the end.
  ///
  /// **Dart Source:** `text.dart:2621`
  /// **Original:** `bool get isNormalized => end >= start;`
  public var isNormalized: Bool {
    end >= start
  }

  /// The text before this range.
  ///
  /// **Dart Source:** `text.dart:2624-2627`
  /// **Original:** `String textBefore(String text) { ... }`
  public func textBefore(_ text: String) -> String {
    assert(isNormalized)
    let index = text.index(text.startIndex, offsetBy: start)
    return String(text[text.startIndex..<index])
  }

  /// The text after this range.
  ///
  /// **Dart Source:** `text.dart:2630-2633`
  /// **Original:** `String textAfter(String text) { ... }`
  public func textAfter(_ text: String) -> String {
    assert(isNormalized)
    let index = text.index(text.startIndex, offsetBy: end)
    return String(text[index..<text.endIndex])
  }

  /// The text inside this range.
  ///
  /// **Dart Source:** `text.dart:2636-2639`
  /// **Original:** `String textInside(String text) { ... }`
  public func textInside(_ text: String) -> String {
    assert(isNormalized)
    let startIdx = text.index(text.startIndex, offsetBy: start)
    let endIdx = text.index(text.startIndex, offsetBy: end)
    return String(text[startIdx..<endIdx])
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:2653`
  /// **Original:** `String toString() => 'TextRange(start: $start, end: $end)';`
  public var description: String {
    "TextRange(start: \(start), end: \(end))"
  }
}

// MARK: - TextDirection

/// A direction in which text flows.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextDirection`
/// **Lines:** 2313-2404
///
/// Some languages are written from the left to the right (for example, English,
/// Tamil, or Chinese), while others are written from the right to the left (for
/// example Aramaic, Hebrew, or Urdu). Some are also written in a mixture, for
/// example Arabic is mostly written right-to-left, with numerals written
/// left-to-right.
///
/// The text direction must be provided to APIs that render text or lay out
/// boxes horizontally, so that they can determine which direction to start in:
/// either right-to-left, ``TextDirection/rtl``; or left-to-right,
/// ``TextDirection/ltr``.
///
/// DIFFERENCE FROM DART: Using `Int` raw value for C++ bridge encoding.
/// REASON: Dart enums have implicit indices; Swift raw values serve the same purpose.
public enum TextDirection: Int, Sendable {
  /// The text flows from right to left (e.g. Arabic, Hebrew).
  ///
  /// **Dart Source:** `text.dart:2399-2400`
  case rtl = 0

  /// The text flows from left to right (e.g., English, French).
  ///
  /// **Dart Source:** `text.dart:2402-2403`
  case ltr = 1
}

// MARK: - TextDecorationStyle

/// The style in which to draw a text decoration.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextDecorationStyle`
/// **Lines:** 1377-1393
///
/// DIFFERENCE FROM DART: Using `Int` raw value for C++ bridge encoding.
/// REASON: Dart enums have implicit indices; Swift raw values serve the same purpose.
public enum TextDecorationStyle: Int, Sendable {
  /// Draw a solid line.
  ///
  /// **Dart Source:** `text.dart:1380`
  case solid = 0

  /// Draw two lines.
  ///
  /// **Dart Source:** `text.dart:1383`
  case double = 1

  /// Draw a dotted line.
  ///
  /// **Dart Source:** `text.dart:1386`
  case dotted = 2

  /// Draw a dashed line.
  ///
  /// **Dart Source:** `text.dart:1389`
  case dashed = 3

  /// Draw a sinusoidal line.
  ///
  /// **Dart Source:** `text.dart:1392`
  case wavy = 4
}

// MARK: - TextLeadingDistribution

/// How the "leading" is distributed over and under the text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextLeadingDistribution`
/// **Lines:** 1396-1421
///
/// DIFFERENCE FROM DART: Using `Int` raw value for C++ bridge encoding.
/// REASON: Dart enums have implicit indices; Swift raw values serve the same purpose.
public enum TextLeadingDistribution: Int, Sendable {
  /// Distributes the leading of the text proportionally above and below the
  /// text, to the font's ascent/descent ratio.
  ///
  /// The leading of a text run is defined as
  /// `TextStyle.height * TextStyle.fontSize - TextStyle.fontSize`. When
  /// `TextStyle.height` is not set, the text run uses the leading specified by
  /// the font instead.
  ///
  /// **Dart Source:** `text.dart:1407`
  case proportional = 0

  /// Distributes the "leading" of the text evenly above and below the text
  /// (i.e. evenly above the font's ascender and below the descender).
  ///
  /// The leading can become negative when `TextStyle.height` is smaller than
  /// 1.0.
  ///
  /// This is the default strategy used by CSS, known as "half-leading".
  ///
  /// **Dart Source:** `text.dart:1420`
  case even = 1
}

// MARK: - TextAffinity

/// A way to disambiguate a [TextPosition] when its offset could match two
/// different locations in the rendered string.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextAffinity`
/// **Lines:** 2477-2523
///
/// For example, at an offset where the rendered text wraps, there are two
/// visual positions that the offset could represent: one prior to the line
/// break (at the end of the first line) and one after the line break (at the
/// start of the second line). A text affinity disambiguates between these two
/// cases.
///
/// This affects only line breaks caused by wrapping, not explicit newline
/// characters. For newline characters, the position is fully specified by the
/// offset alone, and there is no ambiguity.
///
/// [TextAffinity] also affects bidirectional text at the interface between LTR
/// and RTL text. Consider the following string, where the lowercase letters
/// will be displayed as LTR and the uppercase letters RTL: "helloHELLO".  When
/// rendered, the string would appear visually as "helloOLLEH".  An offset of 5
/// would be ambiguous without a corresponding [TextAffinity].  Looking at the
/// string in code, the offset represents the position just after the "o" and
/// just before the "H".  When rendered, this offset could be either in the
/// middle of the string to the right of the "o" or at the end of the string to
/// the right of the "H".
///
/// DIFFERENCE FROM DART: Using `Int` raw value for C++ bridge encoding.
/// REASON: Dart enums have implicit indices; Swift raw values serve the same purpose.
public enum TextAffinity: Int, Sendable {
  /// The position has affinity for the upstream side of the text position, i.e.
  /// in the direction of the beginning of the string.
  ///
  /// In the example of an offset at the place where text is wrapping, upstream
  /// indicates the end of the first line.
  ///
  /// In the bidirectional text example "helloHELLO", an offset of 5 with
  /// [TextAffinity] upstream would appear in the middle of the rendered text,
  /// just to the right of the "o". See the definition of [TextAffinity] for the
  /// full example.
  ///
  /// **Dart Source:** `text.dart:2510`
  case upstream = 0

  /// The position has affinity for the downstream side of the text position,
  /// i.e. in the direction of the end of the string.
  ///
  /// In the example of an offset at the place where text is wrapping,
  /// downstream indicates the beginning of the second line.
  ///
  /// In the bidirectional text example "helloHELLO", an offset of 5 with
  /// [TextAffinity] downstream would appear at the end of the rendered text,
  /// just to the right of the "H". See the definition of [TextAffinity] for the
  /// full example.
  ///
  /// **Dart Source:** `text.dart:2522`
  case downstream = 1
}

// MARK: - BoxHeightStyle

/// Defines various ways to vertically bound the boxes returned by
/// [Paragraph.getBoxesForRange].
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `BoxHeightStyle`
/// **Lines:** 2702-2757
///
/// See [BoxWidthStyle] for a similar property to control width.
public enum BoxHeightStyle: Int, Sendable {
  /// Provide tight bounding boxes that fit heights per run. This style may result
  /// in uneven bounding boxes that do not nicely connect with adjacent boxes.
  ///
  /// **Dart Source:** `text.dart:2709`
  case tight = 0

  /// The height of the boxes will be the maximum height of all runs in the
  /// line. All boxes in the same line will be the same height.
  ///
  /// This does not guarantee that the boxes will cover the entire vertical height of the line
  /// when there is additional line spacing.
  ///
  /// See [BoxHeightStyle.includeLineSpacingTop], [BoxHeightStyle.includeLineSpacingMiddle],
  /// and [BoxHeightStyle.includeLineSpacingBottom] for styles that will cover
  /// the entire line.
  ///
  /// **Dart Source:** `text.dart:2720`
  case max = 1

  /// Extends the top and bottom edge of the bounds to fully cover any line
  /// spacing.
  ///
  /// The top and bottom of each box will cover half of the
  /// space above and half of the space below the line.
  ///
  /// The top edge of each line should be the same as the bottom edge
  /// of the line above. There should be no gaps in vertical coverage given any
  /// amount of line spacing. Line spacing is not included above the first line
  /// and below the last line due to no additional space present there.
  ///
  /// **Dart Source:** `text.dart:2734`
  case includeLineSpacingMiddle = 2

  /// Extends the top edge of the bounds to fully cover any line spacing.
  ///
  /// The line spacing will be added to the top of the box.
  ///
  /// The top edge of each line should be the same as the bottom edge
  /// of the line above. There should be no gaps in vertical coverage given any
  /// amount of line spacing. Line spacing is not included above the first line
  /// and below the last line due to no additional space present there.
  ///
  /// **Dart Source:** `text.dart:2741`
  case includeLineSpacingTop = 3

  /// Extends the bottom edge of the bounds to fully cover any line spacing.
  ///
  /// The line spacing will be added to the bottom of the box.
  ///
  /// The top edge of each line should be the same as the bottom edge
  /// of the line above. There should be no gaps in vertical coverage given any
  /// amount of line spacing. Line spacing is not included above the first line
  /// and below the last line due to no additional space present there.
  ///
  /// **Dart Source:** `text.dart:2748`
  case includeLineSpacingBottom = 4

  /// Calculate box heights based on the metrics of this paragraph's [StrutStyle].
  ///
  /// Boxes based on the strut will have consistent heights throughout the
  /// entire paragraph. The top edge of each line will align with the bottom
  /// edge of the previous line. It is possible for glyphs to extend outside
  /// these boxes.
  ///
  /// **Dart Source:** `text.dart:2756`
  case strut = 5
}

// MARK: - BoxWidthStyle

/// Defines various ways to horizontally bound the boxes returned by
/// [Paragraph.getBoxesForRange].
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `BoxWidthStyle`
/// **Lines:** 2759-2776
///
/// See [BoxHeightStyle] for a similar property to control height.
///
/// DIFFERENCE FROM DART: Using `Int` raw value for C++ bridge encoding.
/// REASON: Dart enums have implicit indices; Swift raw values serve the same purpose.
public enum BoxWidthStyle: Int, Sendable {
  /// Provide tight bounding boxes that fit widths to the runs of each line
  /// independently.
  ///
  /// **Dart Source:** `text.dart:2766`
  case tight = 0

  /// Adds up to two additional boxes as needed at the beginning and/or end
  /// of each line so that the widths of the boxes in line are the same width
  /// as the widest line in the paragraph.
  ///
  /// The additional boxes on each line are only added when the relevant box
  /// at the relevant edge of that line does not span the maximum width of
  /// the paragraph.
  ///
  /// **Dart Source:** `text.dart:2775`
  case max = 1
}

// MARK: - PlaceholderAlignment

/// Where to vertically align the placeholder relative to the surrounding text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `PlaceholderAlignment`
/// **Lines:** 2778-2819
///
/// Used by `ParagraphBuilder.addPlaceholder`.
///
/// DIFFERENCE FROM DART: Using `Int` raw value for C++ bridge encoding.
/// REASON: Dart enums have implicit indices; Swift raw values serve the same purpose.
public enum PlaceholderAlignment: Int, Sendable {
  /// Match the baseline of the placeholder with the baseline.
  ///
  /// The `TextBaseline` to use must be specified and non-null when using this
  /// alignment mode.
  ///
  /// **Dart Source:** `text.dart:2786`
  case baseline = 0

  /// Align the bottom edge of the placeholder with the baseline such that the
  /// placeholder sits on top of the baseline.
  ///
  /// The `TextBaseline` to use must be specified and non-null when using this
  /// alignment mode.
  ///
  /// **Dart Source:** `text.dart:2793`
  case aboveBaseline = 1

  /// Align the top edge of the placeholder with the baseline specified
  /// such that the placeholder hangs below the baseline.
  ///
  /// The `TextBaseline` to use must be specified and non-null when using this
  /// alignment mode.
  ///
  /// **Dart Source:** `text.dart:2800`
  case belowBaseline = 2

  /// Align the top edge of the placeholder with the top edge of the text.
  ///
  /// When the placeholder is very tall, the extra space will hang from
  /// the top and extend through the bottom of the line.
  ///
  /// **Dart Source:** `text.dart:2806`
  case top = 3

  /// Align the bottom edge of the placeholder with the bottom edge of the text.
  ///
  /// When the placeholder is very tall, the extra space will rise from the
  /// bottom and extend through the top of the line.
  ///
  /// **Dart Source:** `text.dart:2812`
  case bottom = 4

  /// Align the middle of the placeholder with the middle of the text.
  ///
  /// When the placeholder is very tall, the extra space will grow equally
  /// from the top and bottom of the line.
  ///
  /// **Dart Source:** `text.dart:2818`
  case middle = 5
}

// MARK: - FontWeight

/// The thickness of the glyphs used to draw the text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `FontWeight`
/// **Lines:** 28-157
///
/// Fonts are typically weighted on a 9-point scale, which, for historical
/// reasons, uses the names 100 to 900. In Flutter, these are named `w100` to
/// `w900` and have the following conventional meanings:
///
///  * `w100`: Thin, the thinnest font weight.
///  * `w200`: Extra light.
///  * `w300`: Light.
///  * `w400`: Normal. The constant `FontWeight.normal` is an alias for this value.
///  * `w500`: Medium.
///  * `w600`: Semi-bold.
///  * `w700`: Bold. The constant `FontWeight.bold` is an alias for this value.
///  * `w800`: Extra-bold.
///  * `w900`: Black, the thickest font weight.
///
/// For example, the font named "Roboto Medium" is typically exposed as a font
/// with the name "Roboto" and the weight `FontWeight.w500`.
///
/// Some modern fonts allow the weight to be adjusted in arbitrary increments.
/// See `FontVariation.weight` for details.
///
/// DIFFERENCE FROM DART: Using struct instead of class.
/// REASON: FontWeight is an immutable value type; Swift structs with value
/// semantics are the idiomatic equivalent.
public struct FontWeight: Equatable, Hashable, Sendable, CustomStringConvertible {
  /// The encoded integer value of this font weight.
  ///
  /// **Dart Source:** `text.dart:61`
  /// **Original:** `final int index;`
  public let index: Int

  /// The thickness value of this font weight.
  ///
  /// **Dart Source:** `text.dart:64`
  /// **Original:** `final int value;`
  public let value: Int

  /// Creates a FontWeight with the given index and value.
  ///
  /// **Dart Source:** `text.dart:58`
  /// **Original:** `const FontWeight._(this.index, this.value);`
  ///
  /// DIFFERENCE FROM DART: Internal initializer instead of private named constructor.
  /// REASON: Swift uses access control keywords instead of Dart's underscore convention.
  internal init(_ index: Int, _ value: Int) {
    self.index = index
    self.value = value
  }

  /// Thin, the least thick.
  ///
  /// **Dart Source:** `text.dart:67`
  public static let w100 = FontWeight(0, 100)

  /// Extra-light.
  ///
  /// **Dart Source:** `text.dart:70`
  public static let w200 = FontWeight(1, 200)

  /// Light.
  ///
  /// **Dart Source:** `text.dart:73`
  public static let w300 = FontWeight(2, 300)

  /// Normal / regular / plain.
  ///
  /// **Dart Source:** `text.dart:76`
  public static let w400 = FontWeight(3, 400)

  /// Medium.
  ///
  /// **Dart Source:** `text.dart:79`
  public static let w500 = FontWeight(4, 500)

  /// Semi-bold.
  ///
  /// **Dart Source:** `text.dart:82`
  public static let w600 = FontWeight(5, 600)

  /// Bold.
  ///
  /// **Dart Source:** `text.dart:85`
  public static let w700 = FontWeight(6, 700)

  /// Extra-bold.
  ///
  /// **Dart Source:** `text.dart:88`
  public static let w800 = FontWeight(7, 800)

  /// Black, the most thick.
  ///
  /// **Dart Source:** `text.dart:91`
  public static let w900 = FontWeight(8, 900)

  /// The default font weight.
  ///
  /// **Dart Source:** `text.dart:94`
  /// **Original:** `static const FontWeight normal = w400;`
  public static let normal = w400

  /// A commonly used font weight that is heavier than normal.
  ///
  /// **Dart Source:** `text.dart:97`
  /// **Original:** `static const FontWeight bold = w700;`
  public static let bold = w700

  /// A list of all the font weights.
  ///
  /// **Dart Source:** `text.dart:100-110`
  /// **Original:** `static const List<FontWeight> values = <FontWeight>[w100, ..., w900];`
  public static let values: [FontWeight] = [
    w100, w200, w300, w400, w500, w600, w700, w800, w900,
  ]

  /// Linearly interpolates between two font weights.
  ///
  /// **Dart Source:** `text.dart:136-141`
  /// **Original:** `static FontWeight? lerp(FontWeight? a, FontWeight? b, double t)`
  ///
  /// Rather than using fractional weights, the interpolation rounds to the
  /// nearest weight.
  ///
  /// If both `a` and `b` are nil, then this method will return nil. Otherwise,
  /// any nil values for `a` or `b` are interpreted as equivalent to `normal`
  /// (also known as `w400`).
  ///
  /// The `t` argument represents position on the timeline, with 0.0 meaning
  /// that the interpolation has not started, returning `a` (or something
  /// equivalent to `a`), 1.0 meaning that the interpolation has finished,
  /// returning `b` (or something equivalent to `b`), and values in between
  /// meaning that the interpolation is at the relevant point on the timeline
  /// between `a` and `b`. The interpolation can be extrapolated beyond 0.0 and
  /// 1.0, so negative values and values greater than 1.0 are valid. The result
  /// is clamped to the range `w100`–`w900`.
  public static func lerp(_ a: FontWeight?, _ b: FontWeight?, _ t: Double) -> FontWeight? {
    if a == nil && b == nil {
      return nil
    }
    let index = min(max(
      Int(
        _lerpInt(
          Int64((a ?? normal).index),
          Int64((b ?? normal).index),
          t
        ).rounded()
      ), 0), 8)
    return values[index]
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:143-156`
  /// **Original:** `String toString() { ... }`
  public var description: String {
    switch index {
    case 0: return "FontWeight.w100"
    case 1: return "FontWeight.w200"
    case 2: return "FontWeight.w300"
    case 3: return "FontWeight.w400"
    case 4: return "FontWeight.w500"
    case 5: return "FontWeight.w600"
    case 6: return "FontWeight.w700"
    case 7: return "FontWeight.w800"
    case 8: return "FontWeight.w900"
    default: return "FontWeight.w\(value)"
    }
  }
}

// MARK: - FontFeature

/// A feature tag and value that affect the selection of glyphs in a font.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `FontFeature`
/// **Lines:** 159-985
///
/// Different fonts support different features. Consider using a tool
/// such as https://wakamaifondue.com/ to examine your fonts to
/// determine what features are available.
///
/// Some fonts also support continuous font variations; see the `FontVariation`
/// class.
///
/// DIFFERENCE FROM DART: Using struct instead of class.
/// REASON: FontFeature is an immutable value type; Swift structs with value
/// semantics are the idiomatic equivalent.
///
/// DIFFERENCE FROM DART: Factory constructors moved to `FontFeatures` enum namespace.
/// REASON: Swift structs cannot have factory constructors that return different instances
/// in the same way Dart does. The factory namespace pattern (like SceneBuilders) provides
/// equivalent ergonomics.
public struct FontFeature: Equatable, Hashable, Sendable, CustomStringConvertible {
  /// The tag that identifies the effect of this feature. Must consist of 4
  /// ASCII characters (typically lowercase letters).
  ///
  /// **Dart Source:** `text.dart:946`
  /// **Original:** `final String feature;`
  public let feature: String

  /// The value assigned to this feature.
  ///
  /// Must be a positive integer. Many features are Boolean values that accept
  /// values of either 0 (feature is disabled) or 1 (feature is enabled).
  ///
  /// **Dart Source:** `text.dart:960`
  /// **Original:** `final int value;`
  public let value: Int

  /// Creates a `FontFeature` object, which can be added to a `TextStyle` to
  /// change how the engine selects glyphs when rendering text.
  ///
  /// `feature` is the four-character tag that identifies the feature.
  /// `value` is the value that the feature will be set to (default 1).
  ///
  /// **Dart Source:** `text.dart:195-197`
  /// **Original:** `const FontFeature(this.feature, [this.value = 1])`
  public init(_ feature: String, _ value: Int = 1) {
    assert(feature.count == 4, "Feature tag must be exactly four characters long.")
    assert(value >= 0, "Feature value must be zero or a positive integer.")
    self.feature = feature
    self.value = value
  }

  /// The encoded size in bytes for C++ bridge encoding.
  ///
  /// **Dart Source:** `text.dart:962`
  /// **Original:** `static const int _kEncodedSize = 8;`
  internal static let encodedSize = 8

  /// Encodes this font feature into binary data for the C++ bridge.
  ///
  /// Writes 4 bytes for the feature tag (ASCII) followed by 4 bytes for
  /// the value (little-endian Int32).
  ///
  /// **Dart Source:** `text.dart:964-970`
  /// **Original:** `void _encode(ByteData byteData)`
  internal func encode(into data: inout Data) {
    assert(feature.utf8.allSatisfy { $0 >= 0x20 && $0 <= 0x7F })
    // Write 4 ASCII bytes for the feature tag
    let utf8 = Array(feature.utf8)
    for i in 0..<4 {
      data.append(utf8[i])
    }
    // Write value as little-endian Int32
    var val = Int32(value).littleEndian
    withUnsafeBytes(of: &val) { bytes in
      data.append(contentsOf: bytes)
    }
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:984`
  /// **Original:** `String toString() => "FontFeature('$feature', $value)";`
  public var description: String {
    "FontFeature('\(feature)', \(value))"
  }
}

// MARK: - FontFeatures Factory

/// Factory namespace for creating `FontFeature` instances with named constructors.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Lines:** 199-937
///
/// In Dart, `FontFeature` has many named constructors (e.g. `FontFeature.enable()`,
/// `FontFeature.fractions()`). In Swift, these are organized into this factory
/// namespace enum following the SceneBuilders/PictureRecorders pattern.
///
/// DIFFERENCE FROM DART: Uses an enum factory namespace instead of named constructors.
/// REASON: Swift factory namespace pattern provides clean API separation between
/// the data type and its factory methods: `FontFeatures.fractions()` instead of
/// `FontFeature.fractions()`.
public enum FontFeatures {
  /// Create a `FontFeature` object that enables the feature with the given tag.
  ///
  /// **Dart Source:** `text.dart:200`
  /// **Original:** `const FontFeature.enable(String feature) : this(feature, 1);`
  public static func enable(_ feature: String) -> FontFeature {
    FontFeature(feature, 1)
  }

  /// Create a `FontFeature` object that disables the feature with the given tag.
  ///
  /// **Dart Source:** `text.dart:203`
  /// **Original:** `const FontFeature.disable(String feature) : this(feature, 0);`
  public static func disable(_ feature: String) -> FontFeature {
    FontFeature(feature, 0)
  }

  /// Access alternative glyphs. (`aalt`)
  ///
  /// This feature selects the given glyph variant for glyphs in the span.
  ///
  /// **Dart Source:** `text.dart:243`
  /// **Original:** `const FontFeature.alternative(this.value) : feature = 'aalt';`
  public static func alternative(_ value: Int) -> FontFeature {
    FontFeature("aalt", value)
  }

  /// Use alternative ligatures to represent fractions. (`afrc`)
  ///
  /// **Dart Source:** `text.dart:269`
  /// **Original:** `const FontFeature.alternativeFractions() : feature = 'afrc', value = 1;`
  public static func alternativeFractions() -> FontFeature {
    FontFeature("afrc")
  }

  /// Enable contextual alternates. (`calt`)
  ///
  /// With this feature enabled, specific glyphs may be replaced by
  /// alternatives based on nearby text.
  ///
  /// **Dart Source:** `text.dart:293`
  /// **Original:** `const FontFeature.contextualAlternates() : feature = 'calt', value = 1;`
  public static func contextualAlternates() -> FontFeature {
    FontFeature("calt")
  }

  /// Enable case-sensitive forms. (`case`)
  ///
  /// Some glyphs are adjusted so as to form a more aesthetically pleasing
  /// combination with capital letters.
  ///
  /// **Dart Source:** `text.dart:326`
  /// **Original:** `const FontFeature.caseSensitiveForms() : feature = 'case', value = 1;`
  public static func caseSensitiveForms() -> FontFeature {
    FontFeature("case")
  }

  /// Select a character variant. (`cv01` through `cv99`)
  ///
  /// Fonts may have up to 99 character variant sets, numbered 1 through 99,
  /// each of which can be independently enabled or disabled.
  ///
  /// **Dart Source:** `text.dart:363-367`
  /// **Original:** `factory FontFeature.characterVariant(int value)`
  public static func characterVariant(_ value: Int) -> FontFeature {
    assert(value >= 1, "Character variant value must be >= 1")
    assert(value <= 99, "Character variant value must be <= 99")
    return FontFeature("cv\(String(format: "%02d", value))")
  }

  /// Display digits as denominators. (`dnom`)
  ///
  /// **Dart Source:** `text.dart:387`
  /// **Original:** `const FontFeature.denominator() : feature = 'dnom', value = 1;`
  public static func denominator() -> FontFeature {
    FontFeature("dnom")
  }

  /// Use ligatures to represent fractions. (`frac`)
  ///
  /// **Dart Source:** `text.dart:414`
  /// **Original:** `const FontFeature.fractions() : feature = 'frac', value = 1;`
  public static func fractions() -> FontFeature {
    FontFeature("frac")
  }

  /// Use historical forms. (`hist`)
  ///
  /// Some fonts have alternatives for letters whose forms have changed
  /// through the ages.
  ///
  /// **Dart Source:** `text.dart:441`
  /// **Original:** `const FontFeature.historicalForms() : feature = 'hist', value = 1;`
  public static func historicalForms() -> FontFeature {
    FontFeature("hist")
  }

  /// Use historical ligatures. (`hlig`)
  ///
  /// Some fonts support ligatures that have fallen out of favor today,
  /// but were historically in common use.
  ///
  /// **Dart Source:** `text.dart:487`
  /// **Original:** `const FontFeature.historicalLigatures() : feature = 'hlig', value = 1;`
  public static func historicalLigatures() -> FontFeature {
    FontFeature("hlig")
  }

  /// Use lining figures. (`lnum`)
  ///
  /// Lining figures have a uniform height, and align with the baseline and the
  /// height of capital letters.
  ///
  /// **Dart Source:** `text.dart:513`
  /// **Original:** `const FontFeature.liningFigures() : feature = 'lnum', value = 1;`
  public static func liningFigures() -> FontFeature {
    FontFeature("lnum")
  }

  /// Use locale-specific glyphs. (`locl`)
  ///
  /// When enabled, the locale is used to determine which glyphs to use when
  /// locale-specific alternatives exist. This feature is enabled by default.
  ///
  /// **Dart Source:** `text.dart:556`
  /// **Original:** `const FontFeature.localeAware({bool enable = true}) : feature = 'locl', value = enable ? 1 : 0;`
  public static func localeAware(enable: Bool = true) -> FontFeature {
    FontFeature("locl", enable ? 1 : 0)
  }

  /// Display alternative glyphs for numerals (alternate annotation forms). (`nalt`)
  ///
  /// Fonts sometimes support multiple alternatives, and the argument
  /// selects the set to use (a positive integer, or 0 to disable).
  ///
  /// **Dart Source:** `text.dart:587`
  /// **Original:** `const FontFeature.notationalForms([this.value = 1]) : feature = 'nalt', assert(value >= 0);`
  public static func notationalForms(_ value: Int = 1) -> FontFeature {
    assert(value >= 0, "Notational forms value must be >= 0")
    return FontFeature("nalt", value)
  }

  /// Display digits as numerators. (`numr`)
  ///
  /// **Dart Source:** `text.dart:607`
  /// **Original:** `const FontFeature.numerators() : feature = 'numr', value = 1;`
  public static func numerators() -> FontFeature {
    FontFeature("numr")
  }

  /// Use old style figures. (`onum`)
  ///
  /// Some fonts have variants of the figures that render with descenders
  /// under the baseline.
  ///
  /// **Dart Source:** `text.dart:634`
  /// **Original:** `const FontFeature.oldstyleFigures() : feature = 'onum', value = 1;`
  public static func oldstyleFigures() -> FontFeature {
    FontFeature("onum")
  }

  /// Use ordinal forms for alphabetic glyphs. (`ordn`)
  ///
  /// **Dart Source:** `text.dart:656`
  /// **Original:** `const FontFeature.ordinalForms() : feature = 'ordn', value = 1;`
  public static func ordinalForms() -> FontFeature {
    FontFeature("ordn")
  }

  /// Use proportional (varying width) figures. (`pnum`)
  ///
  /// This is mutually exclusive with `tabularFigures`.
  ///
  /// **Dart Source:** `text.dart:683`
  /// **Original:** `const FontFeature.proportionalFigures() : feature = 'pnum', value = 1;`
  public static func proportionalFigures() -> FontFeature {
    FontFeature("pnum")
  }

  /// Randomize the alternate forms used in text. (`rand`)
  ///
  /// **Dart Source:** `text.dart:699`
  /// **Original:** `const FontFeature.randomize() : feature = 'rand', value = 1;`
  public static func randomize() -> FontFeature {
    FontFeature("rand")
  }

  /// Enable stylistic alternates. (`salt`)
  ///
  /// Some fonts have alternative forms that are purely stylistic alternatives.
  ///
  /// **Dart Source:** `text.dart:728`
  /// **Original:** `const FontFeature.stylisticAlternates() : feature = 'salt', value = 1;`
  public static func stylisticAlternates() -> FontFeature {
    FontFeature("salt")
  }

  /// Use scientific inferiors. (`sinf`)
  ///
  /// Renders digits in a manner more appropriate for subscripted digits
  /// used in scientific contexts.
  ///
  /// **Dart Source:** `text.dart:751`
  /// **Original:** `const FontFeature.scientificInferiors() : feature = 'sinf', value = 1;`
  public static func scientificInferiors() -> FontFeature {
    FontFeature("sinf")
  }

  /// Select a stylistic set. (`ss01` through `ss20`)
  ///
  /// Fonts may have up to 20 stylistic sets, numbered 1 through 20,
  /// each of which can be independently enabled or disabled.
  ///
  /// **Dart Source:** `text.dart:797-801`
  /// **Original:** `factory FontFeature.stylisticSet(int value)`
  public static func stylisticSet(_ value: Int) -> FontFeature {
    assert(value >= 1, "Stylistic set value must be >= 1")
    assert(value <= 20, "Stylistic set value must be <= 20")
    return FontFeature("ss\(String(format: "%02d", value))")
  }

  /// Enable subscripts. (`subs`)
  ///
  /// **Dart Source:** `text.dart:827`
  /// **Original:** `const FontFeature.subscripts() : feature = 'subs', value = 1;`
  public static func `subscripts`() -> FontFeature {
    FontFeature("subs")
  }

  /// Enable superscripts. (`sups`)
  ///
  /// **Dart Source:** `text.dart:856`
  /// **Original:** `const FontFeature.superscripts() : feature = 'sups', value = 1;`
  public static func superscripts() -> FontFeature {
    FontFeature("sups")
  }

  /// Enable swash glyphs. (`swsh`)
  ///
  /// Some fonts have beautiful flourishes on some characters. The argument
  /// selects which swash to use (0 disables them altogether).
  ///
  /// **Dart Source:** `text.dart:887`
  /// **Original:** `const FontFeature.swash([this.value = 1]) : feature = 'swsh', assert(value >= 0);`
  public static func swash(_ value: Int = 1) -> FontFeature {
    assert(value >= 0, "Swash value must be >= 0")
    return FontFeature("swsh", value)
  }

  /// Use tabular (monospace) figures. (`tnum`)
  ///
  /// This is mutually exclusive with `proportionalFigures`.
  ///
  /// **Dart Source:** `text.dart:914`
  /// **Original:** `const FontFeature.tabularFigures() : feature = 'tnum', value = 1;`
  public static func tabularFigures() -> FontFeature {
    FontFeature("tnum")
  }

  /// Use the slashed zero. (`zero`)
  ///
  /// Some fonts contain both a circular zero and a zero with a slash.
  ///
  /// **Dart Source:** `text.dart:936`
  /// **Original:** `const FontFeature.slashedZero() : feature = 'zero', value = 1;`
  public static func slashedZero() -> FontFeature {
    FontFeature("zero")
  }
}

// MARK: - FontVariation

/// An axis tag and value that can be used to customize variable fonts.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `FontVariation`
/// **Lines:** 987-1207
///
/// Some fonts are variable fonts that can generate a range of different
/// font faces by altering the values of the font's design axes.
///
/// For example:
///
/// ```swift
/// TextStyle(fontVariations: [FontVariation("wght", 800.0)])
/// ```
///
/// Font variations are distinct from font features, as exposed by the
/// `FontFeature` class. Where features can be enabled or disabled in a discrete
/// manner, font variations provide a continuous axis of control.
///
/// DIFFERENCE FROM DART: Using struct instead of class.
/// REASON: FontVariation is an immutable value type; Swift structs with value
/// semantics are the idiomatic equivalent.
public struct FontVariation: Equatable, Hashable, Sendable, CustomStringConvertible {
  /// The tag that identifies the design axis.
  ///
  /// An axis tag must consist of 4 ASCII characters.
  ///
  /// **Dart Source:** `text.dart:1131`
  /// **Original:** `final String axis;`
  public let axis: String

  /// The value assigned to this design axis.
  ///
  /// The range of usable values depends on the specification of the axis.
  ///
  /// While this property is represented as a `Double` in this API
  /// (binary64), fonts use the fixed-point 16.16 format to represent the value
  /// of font variations. This means that the actual range is -32768.0 to
  /// approximately 32767.999985 and in principle the smallest increment between
  /// two values is approximately 0.000015 (1/65536).
  ///
  /// **Dart Source:** `text.dart:1151`
  /// **Original:** `final double value;`
  public let value: Double

  /// Creates a `FontVariation` object, which can be added to a `TextStyle` to
  /// change the variable attributes of a font.
  ///
  /// `axis` is the four-character tag that identifies the design axis.
  /// `value` is the value that the axis will be set to.
  ///
  /// **Dart Source:** `text.dart:1019-1024`
  /// **Original:** `const FontVariation(this.axis, this.value)`
  public init(_ axis: String, _ value: Double) {
    assert(axis.count == 4, "Axis tag must be exactly four characters long.")
    assert(
      value >= -32768.0 && value < 32768.0,
      "Value must be representable as a signed 16.16 fixed-point number, "
        + "i.e. it must be in this range: -32768.0 ≤ value < 32768.0"
    )
    self.axis = axis
    self.value = value
  }

  /// Variable font style. (`ital`)
  ///
  /// Varies the style of glyphs in the font between normal and italic.
  ///
  /// Values must in the range 0.0 (meaning normal) to 1.0 (meaning fully italic).
  ///
  /// **Dart Source:** `text.dart:1046-1049`
  /// **Original:** `const FontVariation.italic(this.value) : axis = 'ital';`
  public init(italic value: Double) {
    assert(value >= 0.0)
    assert(value <= 1.0)
    self.axis = "ital"
    self.value = value
  }

  /// Optical size optimization. (`opsz`)
  ///
  /// Changes the rendering of the font to be optimized for the given text size.
  /// Values must be greater than zero, and are interpreted as points.
  ///
  /// **Dart Source:** `text.dart:1075`
  /// **Original:** `const FontVariation.opticalSize(this.value) : axis = 'opsz';`
  public init(opticalSize value: Double) {
    assert(value > 0.0)
    self.axis = "opsz"
    self.value = value
  }

  /// Variable font slant. (`slnt`)
  ///
  /// Varies the slant of glyphs in the font.
  /// Values must be greater than -90.0 and less than +90.0, representing the
  /// angle in counter-clockwise degrees relative to "normal" at 0.0.
  ///
  /// **Dart Source:** `text.dart:1093-1096`
  /// **Original:** `const FontVariation.slant(this.value) : axis = 'slnt';`
  public init(slant value: Double) {
    assert(value > -90.0)
    assert(value < 90.0)
    self.axis = "slnt"
    self.value = value
  }

  /// Variable font width. (`wdth`)
  ///
  /// Varies the width of glyphs in the font.
  /// Values must be greater than zero. 100.0 represents the "normal" width.
  /// Smaller values are "condensed", greater values are "extended".
  ///
  /// **Dart Source:** `text.dart:1109`
  /// **Original:** `const FontVariation.width(this.value) : axis = 'wdth';`
  public init(width value: Double) {
    assert(value >= 0.0)
    self.axis = "wdth"
    self.value = value
  }

  /// Variable font weight. (`wght`)
  ///
  /// Varies the stroke thickness of the font, similar to `FontWeight` but on a
  /// continuous axis.
  /// Values must be in the range 1..1000.
  ///
  /// **Dart Source:** `text.dart:1123`
  /// **Original:** `const FontVariation.weight(this.value) : axis = 'wght';`
  public init(weight value: Double) {
    assert(value >= 1)
    assert(value <= 1000)
    self.axis = "wght"
    self.value = value
  }

  /// The encoded size in bytes for C++ bridge encoding.
  ///
  /// **Dart Source:** `text.dart:1153`
  /// **Original:** `static const int _kEncodedSize = 8;`
  internal static let encodedSize = 8

  /// Encodes this font variation into binary data for the C++ bridge.
  ///
  /// Writes 4 bytes for the axis tag (ASCII) followed by 4 bytes for
  /// the value (little-endian Float32).
  ///
  /// **Dart Source:** `text.dart:1155-1161`
  /// **Original:** `void _encode(ByteData byteData)`
  internal func encode(into data: inout Data) {
    assert(axis.utf8.allSatisfy { $0 >= 0x20 && $0 <= 0x7F })
    // Write 4 ASCII bytes for the axis tag
    let utf8 = Array(axis.utf8)
    for i in 0..<4 {
      data.append(utf8[i])
    }
    // Write value as little-endian Float32
    var val = Float32(value).bitPattern.littleEndian
    withUnsafeBytes(of: &val) { bytes in
      data.append(contentsOf: bytes)
    }
  }

  /// Linearly interpolates between two font variations.
  ///
  /// If the two variations have different axis tags, the interpolation switches
  /// abruptly from one to the other at t=0.5. Otherwise, the value is
  /// interpolated (see `lerpDouble`).
  ///
  /// The value is not clamped to the valid values of the axis tag, but it is
  /// clamped to the valid range of font variation values in general (the range
  /// of signed 16.16 fixed point numbers).
  ///
  /// **Dart Source:** `text.dart:1195-1203`
  /// **Original:** `static FontVariation? lerp(FontVariation? a, FontVariation? b, double t)`
  public static func lerp(_ a: FontVariation?, _ b: FontVariation?, _ t: Double) -> FontVariation? {
    if a?.axis != b?.axis || (a == nil && b == nil) {
      return t < 0.5 ? a : b
    }
    return FontVariation(
      a!.axis,
      clampDouble(lerpDouble(a!.value, b!.value, t)!, -32768.0, 32768.0 - 1.0 / 65536.0)
    )
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:1206`
  /// **Original:** `String toString() => "FontVariation('$axis', $value)";`
  public var description: String {
    "FontVariation('\(axis)', \(value))"
  }
}

// MARK: - TextDecoration

/// A linear decoration to draw near the text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextDecoration`
/// **Lines:** 1315-1375
///
/// DIFFERENCE FROM DART: Using struct instead of class.
/// REASON: TextDecoration is an immutable value type; Swift structs with value
/// semantics are the idiomatic equivalent.
///
/// DIFFERENCE FROM DART: Not using Swift OptionSet protocol.
/// REASON: To maintain exact parity with Dart's bitmask approach and API surface.
/// The Dart API uses `contains()` method and `combine()` factory, which we replicate directly.
public struct TextDecoration: Equatable, Hashable, Sendable, CustomStringConvertible {
  /// The bitmask representing the active decorations.
  ///
  /// **Dart Source:** `text.dart:1328`
  /// **Original:** `final int _mask;`
  internal let _mask: Int

  /// Public accessor for the decoration mask value.
  ///
  /// **Dart Source:** `text.dart:1328`
  /// **Original:** `final int _mask;`
  ///
  /// Used by NativeParagraphBuilder to encode TextStyle decorations.
  public var mask: Int { _mask }

  /// Creates a TextDecoration with the given bitmask.
  ///
  /// **Dart Source:** `text.dart:1317`
  /// **Original:** `const TextDecoration._(this._mask);`
  internal init(_ mask: Int) {
    self._mask = mask
  }

  /// Creates a decoration that paints the union of all the given decorations.
  ///
  /// **Dart Source:** `text.dart:1320-1326`
  /// **Original:** `factory TextDecoration.combine(List<TextDecoration> decorations)`
  ///
  /// DIFFERENCE FROM DART: Static method instead of factory constructor.
  /// REASON: Swift structs cannot have factory constructors; static method
  /// provides equivalent functionality.
  public static func combine(_ decorations: [TextDecoration]) -> TextDecoration {
    var mask = 0
    for decoration in decorations {
      mask |= decoration._mask
    }
    return TextDecoration(mask)
  }

  /// Whether this decoration will paint at least as much decoration as the
  /// given decoration.
  ///
  /// **Dart Source:** `text.dart:1331-1333`
  /// **Original:** `bool contains(TextDecoration other) { return (_mask | other._mask) == _mask; }`
  public func contains(_ other: TextDecoration) -> Bool {
    (_mask | other._mask) == _mask
  }

  /// Do not draw a decoration.
  ///
  /// **Dart Source:** `text.dart:1336`
  /// **Original:** `static const TextDecoration none = TextDecoration._(0x0);`
  public static let none = TextDecoration(0x0)

  /// Draw a line underneath each line of text.
  ///
  /// **Dart Source:** `text.dart:1339`
  /// **Original:** `static const TextDecoration underline = TextDecoration._(0x1);`
  public static let underline = TextDecoration(0x1)

  /// Draw a line above each line of text.
  ///
  /// **Dart Source:** `text.dart:1342`
  /// **Original:** `static const TextDecoration overline = TextDecoration._(0x2);`
  public static let overline = TextDecoration(0x2)

  /// Draw a line through each line of text.
  ///
  /// **Dart Source:** `text.dart:1345`
  /// **Original:** `static const TextDecoration lineThrough = TextDecoration._(0x4);`
  public static let lineThrough = TextDecoration(0x4)

  // MARK: - Equatable & Hashable

  /// **Dart Source:** `text.dart:1348-1349`
  /// **Original:** `bool operator ==(Object other) { return other is TextDecoration && other._mask == _mask; }`
  public static func == (lhs: TextDecoration, rhs: TextDecoration) -> Bool {
    lhs._mask == rhs._mask
  }

  /// **Dart Source:** `text.dart:1352-1353`
  /// **Original:** `int get hashCode => _mask.hashCode;`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(_mask)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:1356-1374`
  /// **Original:** `String toString() { ... }`
  public var description: String {
    if _mask == 0 {
      return "TextDecoration.none"
    }
    var values: [String] = []
    if _mask & TextDecoration.underline._mask != 0 {
      values.append("underline")
    }
    if _mask & TextDecoration.overline._mask != 0 {
      values.append("overline")
    }
    if _mask & TextDecoration.lineThrough._mask != 0 {
      values.append("lineThrough")
    }
    if values.count == 1 {
      return "TextDecoration.\(values[0])"
    }
    return "TextDecoration.combine([\(values.joined(separator: ", "))])"
  }
}

// MARK: - TextHeightBehavior

/// Defines how to apply `TextStyle.height` over and under text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextHeightBehavior`
/// **Lines:** 1423-1534
///
/// `applyHeightToFirstAscent` and `applyHeightToLastDescent` represent whether
/// the `TextStyle.height` modifier will be applied to the corresponding metric.
/// By default both properties are true, and `TextStyle.height` is applied as
/// normal. When set to false, the font's default ascent will be used.
///
/// `leadingDistribution` determines how the leading is distributed over and
/// under text. This property applies before `applyHeightToFirstAscent` and
/// `applyHeightToLastDescent`.
///
/// DIFFERENCE FROM DART: Using struct instead of class.
/// REASON: TextHeightBehavior is an immutable value type; Swift structs with
/// value semantics are the idiomatic equivalent.
public struct TextHeightBehavior: Equatable, Hashable, Sendable, CustomStringConvertible {
  /// Whether to apply the `TextStyle.height` modifier to the ascent of the
  /// first line in the paragraph.
  ///
  /// When true, the `TextStyle.height` modifier will be applied to the ascent
  /// of the first line. When false, the font's default ascent will be used and
  /// the `TextStyle.height` will have no effect on the ascent of the first line.
  ///
  /// This property only has effect if a non-null `TextStyle.height` is specified.
  ///
  /// Defaults to true (height modifications applied as normal).
  ///
  /// **Dart Source:** `text.dart:1474`
  /// **Original:** `final bool applyHeightToFirstAscent;`
  public let applyHeightToFirstAscent: Bool

  /// Whether to apply the `TextStyle.height` modifier to the descent of the
  /// last line in the paragraph.
  ///
  /// When true, the `TextStyle.height` modifier will be applied to the descent
  /// of the last line. When false, the font's default descent will be used and
  /// the `TextStyle.height` will have no effect on the descent of the last line.
  ///
  /// This property only has effect if a non-null `TextStyle.height` is specified.
  ///
  /// Defaults to true (height modifications applied as normal).
  ///
  /// **Dart Source:** `text.dart:1486`
  /// **Original:** `final bool applyHeightToLastDescent;`
  public let applyHeightToLastDescent: Bool

  /// How the "leading" is distributed over and under the text.
  ///
  /// Does not affect layout when `TextStyle.height` is not specified. The
  /// leading can become negative, for example, when `TextLeadingDistribution.even`
  /// is used with a `TextStyle.height` much smaller than 1.0.
  ///
  /// Defaults to `TextLeadingDistribution.proportional`.
  ///
  /// **Dart Source:** `text.dart:1498`
  /// **Original:** `final TextLeadingDistribution leadingDistribution;`
  public let leadingDistribution: TextLeadingDistribution

  /// Creates a new TextHeightBehavior object.
  ///
  /// - Parameters:
  ///   - applyHeightToFirstAscent: When true, the `TextStyle.height` modifier
  ///     will be applied to the ascent of the first line. Defaults to true.
  ///   - applyHeightToLastDescent: When true, the `TextStyle.height` modifier
  ///     will be applied to the descent of the last line. Defaults to true.
  ///   - leadingDistribution: How the leading is distributed over and under
  ///     text. Defaults to `.proportional`.
  ///
  /// **Dart Source:** `text.dart:1451-1455`
  /// **Original:** `const TextHeightBehavior({...})`
  public init(
    applyHeightToFirstAscent: Bool = true,
    applyHeightToLastDescent: Bool = true,
    leadingDistribution: TextLeadingDistribution = .proportional
  ) {
    self.applyHeightToFirstAscent = applyHeightToFirstAscent
    self.applyHeightToLastDescent = applyHeightToLastDescent
    self.leadingDistribution = leadingDistribution
  }

  /// Creates a new TextHeightBehavior object from an encoded form.
  ///
  /// See `encode()` for the creation of the encoded form.
  ///
  /// **Dart Source:** `text.dart:1460-1462`
  /// **Original:** `const TextHeightBehavior._fromEncoded(int encoded, this.leadingDistribution)`
  internal init(fromEncoded encoded: Int, leadingDistribution: TextLeadingDistribution) {
    self.applyHeightToFirstAscent = (encoded & 0x1) == 0
    self.applyHeightToLastDescent = (encoded & 0x2) == 0
    self.leadingDistribution = leadingDistribution
  }

  /// Returns an encoded int representation of this object (excluding
  /// `leadingDistribution`).
  ///
  /// **Dart Source:** `text.dart:1502-1504`
  /// **Original:** `int _encode() { ... }`
  internal func encode() -> Int {
    (applyHeightToFirstAscent ? 0 : 1 << 0) | (applyHeightToLastDescent ? 0 : 1 << 1)
  }

  // MARK: - Equatable & Hashable

  /// **Dart Source:** `text.dart:1507-1514`
  /// **Original:** `bool operator ==(Object other) { ... }`
  public static func == (lhs: TextHeightBehavior, rhs: TextHeightBehavior) -> Bool {
    lhs.applyHeightToFirstAscent == rhs.applyHeightToFirstAscent
      && lhs.applyHeightToLastDescent == rhs.applyHeightToLastDescent
      && lhs.leadingDistribution == rhs.leadingDistribution
  }

  /// **Dart Source:** `text.dart:1518-1523`
  /// **Original:** `int get hashCode { return Object.hash(...); }`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(applyHeightToFirstAscent)
    hasher.combine(applyHeightToLastDescent)
    hasher.combine(leadingDistribution)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:1527-1533`
  /// **Original:** `String toString() { ... }`
  public var description: String {
    "TextHeightBehavior("
      + "applyHeightToFirstAscent: \(applyHeightToFirstAscent), "
      + "applyHeightToLastDescent: \(applyHeightToLastDescent), "
      + "leadingDistribution: \(leadingDistribution)"
      + ")"
  }
}

// MARK: - TextBox

/// A rectangle enclosing a run of text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextBox`
/// **Lines:** 2406-2475
///
/// This is similar to `Rect` but includes an inherent `TextDirection`.
///
/// DIFFERENCE FROM DART: Using `struct` instead of `class`.
/// REASON: TextBox is an immutable value type; Swift `struct` provides value semantics.
public struct TextBox: Hashable, Equatable, CustomStringConvertible, Sendable {

  /// Creates an object that describes a box containing text.
  ///
  /// **Dart Source:** `text.dart:2411`
  /// **Original:** `const TextBox.fromLTRBD(this.left, this.top, this.right, this.bottom, this.direction);`
  public init(fromLTRBD left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ direction: TextDirection) {
    self.left = left
    self.top = top
    self.right = right
    self.bottom = bottom
    self.direction = direction
  }

  /// The left edge of the text box, irrespective of direction.
  ///
  /// To get the leading edge (which may depend on the [direction]), consider [start].
  ///
  /// **Dart Source:** `text.dart:2416`
  public let left: Double

  /// The top edge of the text box.
  ///
  /// **Dart Source:** `text.dart:2419`
  public let top: Double

  /// The right edge of the text box, irrespective of direction.
  ///
  /// To get the trailing edge (which may depend on the [direction]), consider [end].
  ///
  /// **Dart Source:** `text.dart:2423`
  public let right: Double

  /// The bottom edge of the text box.
  ///
  /// **Dart Source:** `text.dart:2426`
  public let bottom: Double

  /// The direction in which text inside this box flows.
  ///
  /// **Dart Source:** `text.dart:2430`
  public let direction: TextDirection

  /// Returns a rect of the same size as this box.
  ///
  /// **Dart Source:** `text.dart:2433`
  /// **Original:** `Rect toRect() => Rect.fromLTRB(left, top, right, bottom);`
  public func toRect() -> Rect {
    Rect.fromLTRB(left, top, right, bottom)
  }

  /// The `left` edge of the box for left-to-right text; the `right` edge of the box for right-to-left text.
  ///
  /// **Dart Source:** `text.dart:2440-2442`
  /// **Original:** `double get start { return (direction == TextDirection.ltr) ? left : right; }`
  ///
  /// See also:
  ///  * `direction`, which specifies the text direction.
  public var start: Double {
    (direction == .ltr) ? left : right
  }

  /// The `right` edge of the box for left-to-right text; the `left` edge of the box for right-to-left text.
  ///
  /// **Dart Source:** `text.dart:2449-2451`
  /// **Original:** `double get end { return (direction == TextDirection.ltr) ? right : left; }`
  ///
  /// See also:
  ///  * `direction`, which specifies the text direction.
  public var end: Double {
    (direction == .ltr) ? right : left
  }

  // MARK: - Equatable

  /// **Dart Source:** `text.dart:2454-2467`
  /// **Original:** `bool operator ==(Object other) { ... }`
  public static func == (lhs: TextBox, rhs: TextBox) -> Bool {
    lhs.left == rhs.left
      && lhs.top == rhs.top
      && lhs.right == rhs.right
      && lhs.bottom == rhs.bottom
      && lhs.direction == rhs.direction
  }

  // MARK: - Hashable

  /// **Dart Source:** `text.dart:2470`
  /// **Original:** `int get hashCode => Object.hash(left, top, right, bottom, direction);`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(left)
    hasher.combine(top)
    hasher.combine(right)
    hasher.combine(bottom)
    hasher.combine(direction)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:2473-2474`
  /// **Original:** `String toString() => 'TextBox.fromLTRBD(${left.toStringAsFixed(1)}, ...)'`
  public var description: String {
    "TextBox.fromLTRBD(\(String(format: "%.1f", left)), \(String(format: "%.1f", top)), \(String(format: "%.1f", right)), \(String(format: "%.1f", bottom)), \(direction))"
  }
}

// MARK: - TextPosition

/// A position in a string of text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextPosition`
/// **Lines:** 2525-2578
///
/// A TextPosition can be used to describe a caret position in between
/// characters. The `offset` points to the position between `offset - 1` and
/// `offset` characters of the string, and the `affinity` is used to describe
/// which character this position affiliates with.
///
/// One use case is when rendered text is forced to wrap. In this case, the offset
/// where the wrap occurs could visually appear either at the end of the first
/// line or the beginning of the second line. The second way is with
/// bidirectional text. An offset at the interface between two different text
/// directions could have one of two locations in the rendered text.
///
/// See the documentation for `TextAffinity` for more information on how
/// TextAffinity disambiguates situations like these.
public struct TextPosition: Hashable, CustomStringConvertible {
  /// The index of the character that immediately follows the position in the
  /// string representation of the text.
  ///
  /// **Dart Source:** `text.dart:2552`
  /// **Original:** `final int offset;`
  ///
  /// For example, given the string `'Hello'`, offset 0 represents the cursor
  /// being before the `H`, while offset 5 represents the cursor being just
  /// after the `o`.
  public let offset: Int

  /// Disambiguates cases where the position in the string given by `offset`
  /// could represent two different visual positions in the rendered text.
  ///
  /// **Dart Source:** `text.dart:2561`
  /// **Original:** `final TextAffinity affinity;`
  ///
  /// For example, this can happen when text is forced to wrap, or when one
  /// string of text is rendered with multiple text directions.
  ///
  /// See the documentation for `TextAffinity` for more information on how
  /// TextAffinity disambiguates situations like these.
  public let affinity: TextAffinity

  /// Creates an object representing a particular position in a string.
  ///
  /// **Dart Source:** `text.dart:2544`
  /// **Original:** `const TextPosition({required this.offset, this.affinity = TextAffinity.downstream});`
  public init(offset: Int, affinity: TextAffinity = .downstream) {
    self.offset = offset
    self.affinity = affinity
  }

  // MARK: - Equatable

  /// **Dart Source:** `text.dart:2564-2569`
  /// **Original:** `bool operator ==(Object other) { ... }`
  public static func == (lhs: TextPosition, rhs: TextPosition) -> Bool {
    lhs.offset == rhs.offset && lhs.affinity == rhs.affinity
  }

  // MARK: - Hashable

  /// **Dart Source:** `text.dart:2572`
  /// **Original:** `int get hashCode => Object.hash(offset, affinity);`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(offset)
    hasher.combine(affinity)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:2575-2577`
  /// **Original:** `String toString() => 'TextPosition(offset: $offset, affinity: $affinity)';`
  public var description: String {
    "TextPosition(offset: \(offset), affinity: \(affinity))"
  }
}

// MARK: - GlyphInfo

/// The measurements of a character (or a sequence of visually connected
/// characters) within a paragraph.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `GlyphInfo`
/// **Lines:** 1209-1271
///
/// See also:
///
///  * `Paragraph.getGlyphInfoAt`, which finds the `GlyphInfo` associated with
///    a code unit in the text.
///  * `Paragraph.getClosestGlyphInfoForOffset`, which finds the `GlyphInfo` of
///    the glyph(s) onscreen that's closest to the given `Offset`.
///
/// DIFFERENCE FROM DART: Using struct instead of final class.
/// REASON: GlyphInfo is an immutable value type; Swift structs with value
/// semantics are the idiomatic equivalent.
public struct GlyphInfo: Equatable, Hashable, Sendable, CustomStringConvertible {
  /// The layout bounding rect of the associated character, in the paragraph's
  /// coordinates.
  ///
  /// This is **not** a tight bounding box that encloses the character's outline.
  /// The vertical extent reported is derived from the font metrics (instead of
  /// glyph metrics), and the horizontal extent is the horizontal advance of the
  /// character.
  ///
  /// **Dart Source:** `text.dart:1245`
  public let graphemeClusterLayoutBounds: Rect

  /// The UTF-16 range of the associated character in the text.
  ///
  /// **Dart Source:** `text.dart:1248`
  public let graphemeClusterCodeUnitRange: TextRange

  /// The writing direction within the `GlyphInfo`.
  ///
  /// **Dart Source:** `text.dart:1251`
  public let writingDirection: TextDirection

  /// Creates a `GlyphInfo` with the specified values.
  ///
  /// **Dart Source:** `text.dart:1220-1224`
  /// **Original:** `GlyphInfo(this.graphemeClusterLayoutBounds, this.graphemeClusterCodeUnitRange, this.writingDirection)`
  public init(
    _ graphemeClusterLayoutBounds: Rect,
    _ graphemeClusterCodeUnitRange: TextRange,
    _ writingDirection: TextDirection
  ) {
    self.graphemeClusterLayoutBounds = graphemeClusterLayoutBounds
    self.graphemeClusterCodeUnitRange = graphemeClusterCodeUnitRange
    self.writingDirection = writingDirection
  }

  /// Internal constructor for C++ bridge.
  ///
  /// **Dart Source:** `text.dart:1226-1236`
  /// **Original:** `GlyphInfo._(double left, double top, double right, double bottom, int graphemeStart, int graphemeEnd, bool isLTR)`
  internal init(
    left: Double,
    top: Double,
    right: Double,
    bottom: Double,
    graphemeStart: Int,
    graphemeEnd: Int,
    isLTR: Bool
  ) {
    self.graphemeClusterLayoutBounds = Rect.fromLTRB(left, top, right, bottom)
    self.graphemeClusterCodeUnitRange = TextRange(start: graphemeStart, end: graphemeEnd)
    self.writingDirection = isLTR ? .ltr : .rtl
  }

  // MARK: - Hashable

  /// **Dart Source:** `text.dart:1265-1266`
  /// **Original:** `int get hashCode => Object.hash(graphemeClusterLayoutBounds, graphemeClusterCodeUnitRange, writingDirection);`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(graphemeClusterLayoutBounds)
    hasher.combine(graphemeClusterCodeUnitRange)
    hasher.combine(writingDirection)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:1269-1270`
  /// **Original:** `String toString() => 'Glyph($graphemeClusterLayoutBounds, textRange: $graphemeClusterCodeUnitRange, direction: $writingDirection)';`
  public var description: String {
    "Glyph(\(graphemeClusterLayoutBounds), textRange: \(graphemeClusterCodeUnitRange), direction: \(writingDirection))"
  }
}

// MARK: - ParagraphConstraints

/// Layout constraints for `Paragraph` objects.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `ParagraphConstraints`
/// **Lines:** 2656-2700
///
/// Instances of this class are typically used with `Paragraph.layout`.
///
/// The only constraint that can be specified is the `width`. See the discussion
/// at `width` for more details.
///
/// DIFFERENCE FROM DART: Using Swift `struct` instead of Dart `class`.
/// REASON: ParagraphConstraints is an immutable value type; Swift struct provides
/// value semantics which is more appropriate.
public struct ParagraphConstraints: Hashable, CustomStringConvertible, Sendable {

  /// Creates constraints for laying out a paragraph.
  ///
  /// **Dart Source:** `text.dart:2666`
  /// **Original:** `const ParagraphConstraints({required this.width})`
  public init(width: Double) {
    self.width = width
  }

  /// The width the paragraph should use when computing the positions of glyphs.
  ///
  /// **Dart Source:** `text.dart:2685`
  /// **Original:** `final double width;`
  ///
  /// If possible, the paragraph will select a soft line break prior to reaching
  /// this width. If no soft line break is available, the paragraph will select
  /// a hard line break prior to reaching this width. If that would force a line
  /// break without any characters having been placed (i.e. if the next
  /// character to be laid out does not fit within the given width constraint)
  /// then the next character is allowed to overflow the width constraint and a
  /// forced line break is placed after it (even if an explicit line break
  /// follows).
  ///
  /// The width influences how ellipses are applied. See the discussion at
  /// `ParagraphStyle` for more details.
  ///
  /// This width is also used to position glyphs according to the `TextAlign`
  /// alignment described in the `ParagraphStyle` used when building the
  /// `Paragraph` with a `ParagraphBuilder`.
  public let width: Double

  // MARK: - Hashable

  /// **Dart Source:** `text.dart:2696`
  /// **Original:** `int get hashCode => width.hashCode;`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(width)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:2699`
  /// **Original:** `String toString() => 'ParagraphConstraints(width: $width)';`
  public var description: String {
    "ParagraphConstraints(width: \(width))"
  }
}

// MARK: - LineMetrics

/// Stores the measurements and statistics of a single line in the paragraph.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `LineMetrics`
/// **Lines:** 2821-2964
///
/// The measurements here are for the line as a whole, and represent the maximum
/// extent of the line instead of per-run or per-glyph metrics. For more detailed
/// metrics, see `TextBox` and `Paragraph.getBoxesForRange`.
///
/// `LineMetrics` should be obtained directly from the `Paragraph.computeLineMetrics`
/// method.
///
/// DIFFERENCE FROM DART: Uses Swift `struct` instead of Dart `class`.
/// REASON: LineMetrics is an immutable value type with no identity semantics.
public struct LineMetrics: Hashable, CustomStringConvertible {

  /// Creates a `LineMetrics` object with only the specified values.
  ///
  /// **Dart Source:** `text.dart:2832-2842`
  /// **Original:** `LineMetrics({required this.hardBreak, ...})`
  public init(
    hardBreak: Bool,
    ascent: Double,
    descent: Double,
    unscaledAscent: Double,
    height: Double,
    width: Double,
    left: Double,
    baseline: Double,
    lineNumber: Int
  ) {
    self.hardBreak = hardBreak
    self.ascent = ascent
    self.descent = descent
    self.unscaledAscent = unscaledAscent
    self.height = height
    self.width = width
    self.left = left
    self.baseline = baseline
    self.lineNumber = lineNumber
  }

  /// Internal initializer for C++ bridge.
  ///
  /// **Dart Source:** `text.dart:2844-2854`
  /// **Original:** `LineMetrics._(this.hardBreak, this.ascent, ...)`
  internal init(
    _ hardBreak: Bool,
    _ ascent: Double,
    _ descent: Double,
    _ unscaledAscent: Double,
    _ height: Double,
    _ width: Double,
    _ left: Double,
    _ baseline: Double,
    _ lineNumber: Int
  ) {
    self.hardBreak = hardBreak
    self.ascent = ascent
    self.descent = descent
    self.unscaledAscent = unscaledAscent
    self.height = height
    self.width = width
    self.left = left
    self.baseline = baseline
    self.lineNumber = lineNumber
  }

  /// True if this line ends with an explicit line break (e.g. '\n') or is the end
  /// of the paragraph. False otherwise.
  ///
  /// **Dart Source:** `text.dart:2858`
  public let hardBreak: Bool

  /// The rise from the `baseline` as calculated from the font and style for this line.
  ///
  /// **Dart Source:** `text.dart:2869`
  ///
  /// This is the final computed ascent and can be impacted by the strut, height, scaling,
  /// as well as outlying runs that are very tall.
  ///
  /// The `ascent` is provided as a positive value, even though it is typically defined
  /// in fonts as negative. This is to ensure the signage of operations with these
  /// metrics directly reflects the intended signage of the value. For example,
  /// the y coordinate of the top edge of the line is `baseline - ascent`.
  public let ascent: Double

  /// The drop from the `baseline` as calculated from the font and style for this line.
  ///
  /// **Dart Source:** `text.dart:2877`
  ///
  /// This is the final computed descent and can be impacted by the strut, height, scaling,
  /// as well as outlying runs that are very tall.
  ///
  /// The y coordinate of the bottom edge of the line is `baseline + descent`.
  public let descent: Double

  /// The rise from the `baseline` as calculated from the font and style for this line
  /// ignoring the `TextStyle.height`.
  ///
  /// **Dart Source:** `text.dart:2885`
  ///
  /// The `unscaledAscent` is provided as a positive value, even though it is typically
  /// defined in fonts as negative. This is to ensure the signage of operations with
  /// these metrics directly reflects the intended signage of the value.
  public let unscaledAscent: Double

  /// Total height of the line from the top edge to the bottom edge.
  ///
  /// **Dart Source:** `text.dart:2892`
  ///
  /// This is equivalent to `round(ascent + descent)`. This value is provided
  /// separately due to rounding causing sub-pixel differences from the unrounded
  /// values.
  public let height: Double

  /// Width of the line from the left edge of the leftmost glyph to the right
  /// edge of the rightmost glyph.
  ///
  /// **Dart Source:** `text.dart:2903`
  ///
  /// This is not the same as the width of the paragraph.
  ///
  /// See also:
  ///  * `Paragraph.width`, the max width passed in during layout.
  ///  * `Paragraph.longestLine`, the width of the longest line in the paragraph.
  public let width: Double

  /// The x coordinate of left edge of the line.
  ///
  /// **Dart Source:** `text.dart:2908`
  ///
  /// The right edge can be obtained with `left + width`.
  public let left: Double

  /// The y coordinate of the baseline for this line from the top of the paragraph.
  ///
  /// **Dart Source:** `text.dart:2914`
  ///
  /// The bottom edge of the paragraph up to and including this line may be obtained
  /// through `baseline + descent`.
  public let baseline: Double

  /// The number of this line in the overall paragraph, with the first line being
  /// index zero.
  ///
  /// **Dart Source:** `text.dart:2920`
  ///
  /// For example, the first line is line 0, second line is line 1.
  public let lineNumber: Int

  // MARK: - Hashable

  /// **Dart Source:** `text.dart:2940-2950`
  /// **Original:** `int get hashCode => Object.hash(hardBreak, ascent, ...)`
  public func hash(into hasher: inout Hasher) {
    hasher.combine(hardBreak)
    hasher.combine(ascent)
    hasher.combine(descent)
    hasher.combine(unscaledAscent)
    hasher.combine(height)
    hasher.combine(width)
    hasher.combine(left)
    hasher.combine(baseline)
    hasher.combine(lineNumber)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:2953-2963`
  /// **Original:** `String toString() => 'LineMetrics(hardBreak: $hardBreak, ...)'`
  public var description: String {
    "LineMetrics(hardBreak: \(hardBreak), "
      + "ascent: \(ascent), "
      + "descent: \(descent), "
      + "unscaledAscent: \(unscaledAscent), "
      + "height: \(height), "
      + "width: \(width), "
      + "left: \(left), "
      + "baseline: \(baseline), "
      + "lineNumber: \(lineNumber))"
  }
}

// MARK: - listEquals Helper

/// Determines if arrays `a` and `b` are deep equivalent.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `_listEquals`
/// **Lines:** 1536-1554
///
/// Returns true if the arrays are both nil, or if they are both non-nil, have
/// the same length, and contain the same elements in the same order. Returns
/// false otherwise.
///
/// DIFFERENCE FROM DART: In Swift, `[T] == [T]` works for Equatable elements,
/// but this helper handles the optional wrapping case (`[T]? == [T]?`).
/// REASON: Used by TextStyle, ParagraphStyle, StrutStyle equality checks
/// where the arrays are optional.
internal func listEquals<T: Equatable>(_ a: [T]?, _ b: [T]?) -> Bool {
  if a == nil {
    return b == nil
  }
  if b == nil || a!.count != b!.count {
    return false
  }
  for index in 0..<a!.count {
    if a![index] != b![index] {
      return false
    }
  }
  return true
}

// MARK: - TextStyle

/// An opaque object that determines the size, position, and rendering of text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `TextStyle`
/// **Lines:** 1686-1882
///
/// DIFFERENCE FROM DART: This is a pure Swift struct with no `_encoded` array.
/// REASON: Encoding logic is moved to the C++ bridge layer
/// (ParagraphBuilderBridge.PushStyle). Swift passes structured data to C++,
/// which handles encoding internally. This results in a cleaner Swift API.
///
/// See also:
///  * [TextStyle](https://api.flutter.dev/flutter/painting/TextStyle-class.html),
///    the class in the [painting] library.
public struct TextStyle: Hashable, CustomStringConvertible {

  /// Creates a new TextStyle object.
  ///
  /// **Dart Source:** `text.dart:1724-1786`
  /// **Original:** `TextStyle({Color? color, ...})`
  ///
  /// - Parameters:
  ///   - color: The color to use when painting the text. If this is specified,
  ///     `foreground` must be nil.
  ///   - decoration: The decorations to paint near the text (e.g., an underline).
  ///   - decorationColor: The color in which to paint the text decorations.
  ///   - decorationStyle: The style in which to paint the text decorations (e.g., dashed).
  ///   - decorationThickness: The thickness of the decoration as a multiplier
  ///     on the thickness specified by the font.
  ///   - fontWeight: The typeface thickness to use when painting the text (e.g., bold).
  ///   - fontStyle: The typeface variant to use when drawing the letters (e.g., italics).
  ///   - textBaseline: The common baseline that should be aligned between this
  ///     text span and its parent text span, or, for the root text spans, with the line box.
  ///   - fontFamily: The name of the font to use when painting the text (e.g., Roboto).
  ///   - fontFamilyFallback: An ordered list of the names of the fonts to fallback on
  ///     when a glyph cannot be found in a higher priority font.
  ///   - fontSize: The size of glyphs (in logical pixels) to use when painting the text.
  ///   - letterSpacing: The amount of space (in logical pixels) to add between each letter.
  ///   - wordSpacing: The amount of space (in logical pixels) to add at each sequence of white-space.
  ///   - height: The height of this text span, as a multiplier of the font size.
  ///   - leadingDistribution: When `height` is set, how the extra vertical space
  ///     should be distributed over and under the text.
  ///   - locale: The locale used to select region-specific glyphs.
  ///   - background: The paint drawn as a background for the text.
  ///   - foreground: The paint used to draw the text. If this is specified, `color` must be nil.
  ///   - shadows: The shadows to paint behind the text.
  ///   - fontFeatures: The font features that should be applied to the text.
  ///   - fontVariations: The font variations that should be applied to the text.
  public init(
    color: Color? = nil,
    decoration: TextDecoration? = nil,
    decorationColor: Color? = nil,
    decorationStyle: TextDecorationStyle? = nil,
    decorationThickness: Double? = nil,
    fontWeight: FontWeight? = nil,
    fontStyle: FontStyle? = nil,
    textBaseline: TextBaseline? = nil,
    fontFamily: String? = nil,
    fontFamilyFallback: [String]? = nil,
    fontSize: Double? = nil,
    letterSpacing: Double? = nil,
    wordSpacing: Double? = nil,
    height: Double? = nil,
    leadingDistribution: TextLeadingDistribution? = nil,
    locale: Locale? = nil,
    background: Paint? = nil,
    foreground: Paint? = nil,
    shadows: [Shadow]? = nil,
    fontFeatures: [FontFeature]? = nil,
    fontVariations: [FontVariation]? = nil
  ) {
    assert(
      color == nil || foreground == nil,
      "Cannot provide both a color and a foreground\n"
        + "The color argument is just a shorthand for \"foreground: Paint()..color = color\"."
    )
    self.color = color
    self.decoration = decoration
    self.decorationColor = decorationColor
    self.decorationStyle = decorationStyle
    self.decorationThickness = decorationThickness
    self.fontWeight = fontWeight
    self.fontStyle = fontStyle
    self.textBaseline = textBaseline
    self.fontFamily = fontFamily
    self.fontFamilyFallback = fontFamilyFallback
    self.fontSize = fontSize
    self.letterSpacing = letterSpacing
    self.wordSpacing = wordSpacing
    self.height = height
    self.leadingDistribution = leadingDistribution
    self.locale = locale
    self.background = background
    self.foreground = foreground
    self.shadows = shadows
    self.fontFeatures = fontFeatures
    self.fontVariations = fontVariations
  }

  /// The color to use when painting the text.
  ///
  /// **Dart Source:** `text.dart:1725`
  public let color: Color?

  /// The decorations to paint near the text (e.g., an underline).
  ///
  /// **Dart Source:** `text.dart:1726`
  public let decoration: TextDecoration?

  /// The color in which to paint the text decorations.
  ///
  /// **Dart Source:** `text.dart:1727`
  public let decorationColor: Color?

  /// The style in which to paint the text decorations (e.g., dashed).
  ///
  /// **Dart Source:** `text.dart:1728`
  public let decorationStyle: TextDecorationStyle?

  /// The thickness of the decoration as a multiplier on the thickness
  /// specified by the font.
  ///
  /// **Dart Source:** `text.dart:1729`
  public let decorationThickness: Double?

  /// The typeface thickness to use when painting the text (e.g., bold).
  ///
  /// **Dart Source:** `text.dart:1730`
  public let fontWeight: FontWeight?

  /// The typeface variant to use when drawing the letters (e.g., italics).
  ///
  /// **Dart Source:** `text.dart:1731`
  public let fontStyle: FontStyle?

  /// The common baseline that should be aligned between this text span and
  /// its parent text span, or, for the root text spans, with the line box.
  ///
  /// **Dart Source:** `text.dart:1732`
  public let textBaseline: TextBaseline?

  /// The name of the font to use when painting the text (e.g., Roboto).
  ///
  /// **Dart Source:** `text.dart:1733`
  public let fontFamily: String?

  /// An ordered list of the names of the fonts to fallback on when a glyph
  /// cannot be found in a higher priority font.
  ///
  /// **Dart Source:** `text.dart:1734`
  public let fontFamilyFallback: [String]?

  /// The size of glyphs (in logical pixels) to use when painting the text.
  ///
  /// **Dart Source:** `text.dart:1735`
  public let fontSize: Double?

  /// The amount of space (in logical pixels) to add between each letter.
  ///
  /// **Dart Source:** `text.dart:1736`
  public let letterSpacing: Double?

  /// The amount of space (in logical pixels) to add at each sequence of
  /// white-space (i.e. between each word).
  ///
  /// **Dart Source:** `text.dart:1737`
  public let wordSpacing: Double?

  /// The height of this text span, as a multiplier of the font size.
  ///
  /// **Dart Source:** `text.dart:1738`
  /// Setting `height` to `kTextHeightNone` will allow the line height to take
  /// the height as defined by the font, which may not be exactly the height
  /// of the fontSize.
  public let height: Double?

  /// When `height` is set to a non-nil value that is not `kTextHeightNone`,
  /// how the extra vertical space should be distributed over and under the text.
  ///
  /// **Dart Source:** `text.dart:1739`
  public let leadingDistribution: TextLeadingDistribution?

  /// The locale used to select region-specific glyphs.
  ///
  /// **Dart Source:** `text.dart:1740`
  public let locale: Locale?

  /// The paint drawn as a background for the text.
  ///
  /// **Dart Source:** `text.dart:1741`
  ///
  /// DIFFERENCE FROM DART: Paint is a reference type (class) in both Dart and Swift.
  /// Equality comparison uses reference identity, matching Dart's `identical()` behavior.
  public let background: Paint?

  /// The paint used to draw the text. If this is specified, `color` must be nil.
  ///
  /// **Dart Source:** `text.dart:1742`
  ///
  /// DIFFERENCE FROM DART: Paint is a reference type (class) in both Dart and Swift.
  /// Equality comparison uses reference identity, matching Dart's `identical()` behavior.
  public let foreground: Paint?

  /// The shadows to paint behind the text.
  ///
  /// **Dart Source:** `text.dart:1743`
  public let shadows: [Shadow]?

  /// The font features that should be applied to the text.
  ///
  /// **Dart Source:** `text.dart:1744`
  public let fontFeatures: [FontFeature]?

  /// The font variations that should be applied to the text.
  ///
  /// **Dart Source:** `text.dart:1745`
  public let fontVariations: [FontVariation]?

  // MARK: - Equatable

  /// **Dart Source:** `text.dart:1804-1825`
  /// **Original:** `bool operator ==(Object other)`
  ///
  /// DIFFERENCE FROM DART: Dart's `==` compared `_encoded` (the Int32List bitmask array)
  /// instead of comparing individual fields like color, decoration, decorationColor, etc.
  /// REASON: Since encoding is moved to C++ bridge, we compare all fields directly.
  /// This is semantically equivalent because the encoded array was derived from these
  /// same fields. The fields not in `_encoded` (fontFamily, fontSize, letterSpacing,
  /// wordSpacing, height, decorationThickness, locale, background, foreground,
  /// shadows, fontFeatures, fontVariations, leadingDistribution, fontFamilyFallback)
  /// were compared separately in Dart too.
  public static func == (lhs: TextStyle, rhs: TextStyle) -> Bool {
    return lhs.color == rhs.color
      && lhs.decoration == rhs.decoration
      && lhs.decorationColor == rhs.decorationColor
      && lhs.decorationStyle == rhs.decorationStyle
      && lhs.decorationThickness == rhs.decorationThickness
      && lhs.fontWeight == rhs.fontWeight
      && lhs.fontStyle == rhs.fontStyle
      && lhs.textBaseline == rhs.textBaseline
      && lhs.fontFamily == rhs.fontFamily
      && lhs.fontSize == rhs.fontSize
      && lhs.letterSpacing == rhs.letterSpacing
      && lhs.wordSpacing == rhs.wordSpacing
      && lhs.height == rhs.height
      && lhs.leadingDistribution == rhs.leadingDistribution
      && lhs.locale == rhs.locale
      && lhs.background === rhs.background
      && lhs.foreground === rhs.foreground
      && listEquals(lhs.fontFamilyFallback, rhs.fontFamilyFallback)
      && listEquals(lhs.shadows, rhs.shadows)
      && listEquals(lhs.fontFeatures, rhs.fontFeatures)
      && listEquals(lhs.fontVariations, rhs.fontVariations)
  }

  // MARK: - Hashable

  /// **Dart Source:** `text.dart:1828-1849`
  /// **Original:** `int get hashCode`
  ///
  /// DIFFERENCE FROM DART: Dart hashed `Object.hashAll(_encoded)` (the Int32List).
  /// REASON: Since encoding is moved to C++ bridge, we hash the individual fields
  /// that were encoded into that array (color, decoration, decorationColor,
  /// decorationStyle, fontWeight, fontStyle, textBaseline), plus all the fields
  /// that Dart hashed separately.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(color)
    hasher.combine(decoration)
    hasher.combine(decorationColor)
    hasher.combine(decorationStyle)
    hasher.combine(fontWeight)
    hasher.combine(fontStyle)
    hasher.combine(textBaseline)
    hasher.combine(leadingDistribution)
    hasher.combine(fontFamily)
    hasher.combine(fontFamilyFallback)
    hasher.combine(fontSize)
    hasher.combine(letterSpacing)
    hasher.combine(wordSpacing)
    hasher.combine(height)
    hasher.combine(decorationThickness)
    hasher.combine(locale)
    if let background = background {
      hasher.combine(ObjectIdentifier(background))
    }
    if let foreground = foreground {
      hasher.combine(ObjectIdentifier(foreground))
    }
    if let shadows = shadows {
      for shadow in shadows {
        hasher.combine(shadow)
      }
    }
    if let fontFeatures = fontFeatures {
      for feature in fontFeatures {
        hasher.combine(feature)
      }
    }
    if let fontVariations = fontVariations {
      for variation in fontVariations {
        hasher.combine(variation)
      }
    }
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:1852-1881`
  /// **Original:** `String toString()`
  ///
  /// DIFFERENCE FROM DART: Dart's toString() checked bits in `_encoded[0]` to
  /// determine which fields were "specified". Since we don't have the encoded
  /// array, we check if the field is non-nil instead, which is semantically
  /// equivalent.
  public var description: String {
    let heightText: String
    if let h = height {
      heightText = h == kTextHeightNone ? "kTextHeightNone" : "\(h)x"
    } else {
      heightText = "unspecified"
    }

    func desc<T>(_ value: T?) -> String {
      if let v = value { return "\(v)" }
      return "unspecified"
    }

    let fontFamilyDesc: String
    if let family = fontFamily, !family.isEmpty {
      fontFamilyDesc = family
    } else {
      fontFamilyDesc = "unspecified"
    }

    let fontFamilyFallbackDesc: String
    if let fallback = fontFamilyFallback, !fallback.isEmpty {
      fontFamilyFallbackDesc = "\(fallback)"
    } else {
      fontFamilyFallbackDesc = "unspecified"
    }

    let letterSpacingDesc = letterSpacing != nil ? "\(letterSpacing!)x" : "unspecified"
    let wordSpacingDesc = wordSpacing != nil ? "\(wordSpacing!)x" : "unspecified"

    return "TextStyle("
      + "color: \(desc(color)), "
      + "decoration: \(desc(decoration)), "
      + "decorationColor: \(desc(decorationColor)), "
      + "decorationStyle: \(desc(decorationStyle)), "
      + "decorationThickness: \(desc(decorationThickness)), "
      + "fontWeight: \(desc(fontWeight)), "
      + "fontStyle: \(desc(fontStyle)), "
      + "textBaseline: \(desc(textBaseline)), "
      + "fontFamily: \(fontFamilyDesc), "
      + "fontFamilyFallback: \(fontFamilyFallbackDesc), "
      + "fontSize: \(desc(fontSize)), "
      + "letterSpacing: \(letterSpacingDesc), "
      + "wordSpacing: \(wordSpacingDesc), "
      + "height: \(heightText), "
      + "leadingDistribution: \(desc(leadingDistribution)), "
      + "locale: \(desc(locale)), "
      + "background: \(desc(background)), "
      + "foreground: \(desc(foreground)), "
      + "shadows: \(desc(shadows)), "
      + "fontFeatures: \(desc(fontFeatures)), "
      + "fontVariations: \(desc(fontVariations))"
      + ")"
  }
}

// MARK: - StrutStyle

/// Defines the strut, which sets the minimum height a line can be
/// relative to the baseline.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `StrutStyle`
/// **Lines:** 2210-2311
///
/// DIFFERENCE FROM DART: This is a pure Swift struct with no `_encoded` ByteData.
/// REASON: Encoding logic is moved to the C++ bridge layer
/// (ParagraphBuilderBridge constructor). Swift passes structured data to C++,
/// which handles encoding internally. This results in a cleaner Swift API.
///
/// See also:
///  * [StrutStyle](https://api.flutter.dev/flutter/painting/StrutStyle-class.html),
///    the class in the [painting] library.
public struct StrutStyle: Hashable, CustomStringConvertible {

  /// Creates a new StrutStyle object.
  ///
  /// **Dart Source:** `text.dart:2261-2284`
  /// **Original:** `StrutStyle({String? fontFamily, ...})`
  ///
  /// - Parameters:
  ///   - fontFamily: The name of the font to use when painting the text (e.g., Roboto).
  ///   - fontFamilyFallback: An ordered list of font family names that will be
  ///     searched for when the font in `fontFamily` cannot be found.
  ///   - fontSize: The size of glyphs (in logical pixels) to use when painting the text.
  ///   - height: The minimum height of the line boxes, as a multiplier of the font size.
  ///     Omitting `height` (or setting it to `kTextHeightNone`) will allow the minimum
  ///     line height to take the height as defined by the font.
  ///   - leadingDistribution: How the extra vertical space added by the `height` multiplier
  ///     should be distributed over and under the text, independent of `leading`.
  ///   - leading: The minimum amount of leading between lines as a multiple of the font size.
  ///   - fontWeight: The typeface thickness to use when painting the text (e.g., bold).
  ///   - fontStyle: The typeface variant to use when drawing the letters (e.g., italics).
  ///   - forceStrutHeight: When true, the paragraph will force all lines to be exactly
  ///     `(height + leading) * fontSize` tall from baseline to baseline.
  public init(
    fontFamily: String? = nil,
    fontFamilyFallback: [String]? = nil,
    fontSize: Double? = nil,
    height: Double? = nil,
    leadingDistribution: TextLeadingDistribution? = nil,
    leading: Double? = nil,
    fontWeight: FontWeight? = nil,
    fontStyle: FontStyle? = nil,
    forceStrutHeight: Bool? = nil
  ) {
    self.fontFamily = fontFamily
    self.fontFamilyFallback = fontFamilyFallback
    self.fontSize = fontSize
    self.height = height
    self.leadingDistribution = leadingDistribution
    self.leading = leading
    self.fontWeight = fontWeight
    self.fontStyle = fontStyle
    self.forceStrutHeight = forceStrutHeight
  }

  /// The name of the font to use when painting the text (e.g., Roboto).
  ///
  /// **Dart Source:** `text.dart:2283`
  public let fontFamily: String?

  /// An ordered list of font family names that will be searched for when
  /// the font in `fontFamily` cannot be found.
  ///
  /// **Dart Source:** `text.dart:2284`
  public let fontFamilyFallback: [String]?

  /// The size of glyphs (in logical pixels) to use when painting the text.
  ///
  /// **Dart Source:** `text.dart:2264`
  public let fontSize: Double?

  /// The minimum height of the line boxes, as a multiplier of the font size.
  ///
  /// **Dart Source:** `text.dart:2265`
  /// Omitting `height` (or setting it to `kTextHeightNone`) will allow the
  /// minimum line height to take the height as defined by the font.
  public let height: Double?

  /// How the extra vertical space added by the `height` multiplier should be
  /// distributed over and under the text.
  ///
  /// **Dart Source:** `text.dart:2266`
  public let leadingDistribution: TextLeadingDistribution?

  /// The minimum amount of leading between lines as a multiple of the font size.
  ///
  /// **Dart Source:** `text.dart:2267`
  public let leading: Double?

  /// The typeface thickness to use when painting the text (e.g., bold).
  ///
  /// **Dart Source:** `text.dart:2269`
  public let fontWeight: FontWeight?

  /// The typeface variant to use when drawing the letters (e.g., italics).
  ///
  /// **Dart Source:** `text.dart:2270`
  public let fontStyle: FontStyle?

  /// When true, the paragraph will force all lines to be exactly
  /// `(height + leading) * fontSize` tall from baseline to baseline.
  ///
  /// **Dart Source:** `text.dart:2271`
  public let forceStrutHeight: Bool?

  /// Whether this StrutStyle has any properties set.
  ///
  /// **Dart Source:** `text.dart:2291`
  /// **Original:** `bool get _enabled => _encoded.lengthInBytes > 0;`
  ///
  /// DIFFERENCE FROM DART: Dart checked if the encoded ByteData was non-empty.
  /// REASON: Since encoding is moved to C++ bridge, we check if any fields are set.
  /// This is semantically equivalent because the encoded data was non-empty if and
  /// only if at least one field was set (see _encodeStrut at text.dart:2153-2160).
  internal var enabled: Bool {
    // Strut styles are unique in a paragraph, there is no inheriting so
    // height == nil and height == kTextHeightNone are semantically equivalent.
    let hasHeightOverride = height != nil && height != kTextHeightNone
    return fontFamily != nil
      || fontSize != nil
      || hasHeightOverride
      || leadingDistribution != nil
      || leading != nil
      || fontWeight != nil
      || fontStyle != nil
      || forceStrutHeight != nil
  }

  // MARK: - Equatable

  /// **Dart Source:** `text.dart:2293-2306`
  /// **Original:** `bool operator ==(Object other)`
  ///
  /// DIFFERENCE FROM DART: Dart compared `_encoded.buffer.asInt8List()` and
  /// `_fontFamily`, `_leadingDistribution`, `_fontFamilyFallback`.
  /// REASON: Since encoding is moved to C++ bridge, we compare all fields directly.
  /// This is semantically equivalent because the encoded ByteData contained
  /// fontWeight, fontStyle, fontSize, height, leading, and forceStrutHeight.
  public static func == (lhs: StrutStyle, rhs: StrutStyle) -> Bool {
    return lhs.fontFamily == rhs.fontFamily
      && lhs.leadingDistribution == rhs.leadingDistribution
      && lhs.fontWeight == rhs.fontWeight
      && lhs.fontStyle == rhs.fontStyle
      && lhs.fontSize == rhs.fontSize
      && lhs.height == rhs.height
      && lhs.leading == rhs.leading
      && lhs.forceStrutHeight == rhs.forceStrutHeight
      && listEquals(lhs.fontFamilyFallback, rhs.fontFamilyFallback)
  }

  // MARK: - Hashable

  /// **Dart Source:** `text.dart:2308-2310`
  /// **Original:** `int get hashCode => Object.hash(Object.hashAll(_encoded.buffer.asInt8List()), _fontFamily, _leadingDistribution);`
  ///
  /// DIFFERENCE FROM DART: Dart hashed the encoded ByteData bytes.
  /// REASON: Since encoding is moved to C++ bridge, we hash the individual fields
  /// that were encoded into that ByteData.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(fontFamily)
    hasher.combine(leadingDistribution)
    hasher.combine(fontWeight)
    hasher.combine(fontStyle)
    hasher.combine(fontSize)
    hasher.combine(height)
    hasher.combine(leading)
    hasher.combine(forceStrutHeight)
    if let fontFamilyFallback = fontFamilyFallback {
      for family in fontFamilyFallback {
        hasher.combine(family)
      }
    }
  }

  // MARK: - Encoding

  /// Encodes this StrutStyle to binary data for the C++ bridge.
  ///
  /// **Dart Source:** `text.dart:2139-2208` (_encodeStrut function)
  /// **Original:**
  /// ```dart
  /// ByteData _encodeStrut(
  ///   String? fontFamily, List<String>? fontFamilyFallback, double? fontSize,
  ///   double? height, TextLeadingDistribution? leadingDistribution,
  ///   double? leading, FontWeight? fontWeight, FontStyle? fontStyle,
  ///   bool? forceStrutHeight,
  /// )
  /// ```
  ///
  /// The encoding format is:
  /// - Byte 0: Bitmask (8 bits)
  ///   - Bit 0: fontWeight present
  ///   - Bit 1: fontStyle present
  ///   - Bit 2: fontFamily present (passed separately)
  ///   - Bit 3: leadingDistribution (set by caller)
  ///   - Bit 4: fontSize present
  ///   - Bit 5: height present
  ///   - Bit 6: leading present
  ///   - Bit 7: forceStrutHeight true
  /// - Following bytes are the values in order, if present
  internal func encode() -> Data {
    guard enabled else {
      return Data()
    }

    var data = Data(count: 16)  // Max size is 16 bytes
    var bitmask: UInt8 = 0
    var byteCount = 1

    if let fontWeight = fontWeight {
      bitmask |= (1 << 0)
      data[byteCount] = UInt8(fontWeight.index)
      byteCount += 1
    }

    if let fontStyle = fontStyle {
      bitmask |= (1 << 1)
      data[byteCount] = UInt8(fontStyle.rawValue)
      byteCount += 1
    }

    if fontFamily != nil
      || (fontFamilyFallback != nil && !(fontFamilyFallback?.isEmpty ?? true))
    {
      bitmask |= (1 << 2)
      // Font family is passed separately to native
    }

    // Bit 3 is reserved for leadingDistribution (set by caller)

    if let fontSize = fontSize {
      bitmask |= (1 << 4)
      var value = Float32(fontSize).bitPattern.littleEndian
      withUnsafeBytes(of: &value) { bytes in
        for byte in bytes {
          data[byteCount] = byte
          byteCount += 1
        }
      }
    }

    let hasHeightOverride = height != nil && height != kTextHeightNone
    if hasHeightOverride, let height = height {
      bitmask |= (1 << 5)
      var value = Float32(height).bitPattern.littleEndian
      withUnsafeBytes(of: &value) { bytes in
        for byte in bytes {
          data[byteCount] = byte
          byteCount += 1
        }
      }
    }

    if let leading = leading {
      bitmask |= (1 << 6)
      var value = Float32(leading).bitPattern.littleEndian
      withUnsafeBytes(of: &value) { bytes in
        for byte in bytes {
          data[byteCount] = byte
          byteCount += 1
        }
      }
    }

    if forceStrutHeight ?? false {
      bitmask |= (1 << 7)
    }

    data[0] = bitmask
    assert(byteCount <= 16, "StrutStyle encoding exceeded max size")

    return data.prefix(byteCount)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:2210-2311` (StrutStyle class, no explicit toString in Dart)
  ///
  /// DIFFERENCE FROM DART: Dart's StrutStyle did not override toString().
  /// REASON: Added for debugging convenience, following the pattern of other
  /// text types in this file.
  public var description: String {
    func desc<T>(_ value: T?) -> String {
      if let v = value { return "\(v)" }
      return "unspecified"
    }

    let heightText: String
    if let h = height {
      heightText = h == kTextHeightNone ? "kTextHeightNone" : "\(h)x"
    } else {
      heightText = "unspecified"
    }

    return "StrutStyle("
      + "fontFamily: \(desc(fontFamily)), "
      + "fontFamilyFallback: \(desc(fontFamilyFallback)), "
      + "fontSize: \(desc(fontSize)), "
      + "height: \(heightText), "
      + "leadingDistribution: \(desc(leadingDistribution)), "
      + "leading: \(desc(leading)), "
      + "fontWeight: \(desc(fontWeight)), "
      + "fontStyle: \(desc(fontStyle)), "
      + "forceStrutHeight: \(desc(forceStrutHeight))"
      + ")"
  }
}

// MARK: - ParagraphStyle

/// An opaque object that determines the configuration used by
/// [ParagraphBuilder] to position lines within a [Paragraph] of text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `ParagraphStyle`
/// **Lines:** 1973-2128
///
/// DIFFERENCE FROM DART: Using struct instead of class.
/// REASON: ParagraphStyle is an immutable value type; Swift structs with value
/// semantics are the idiomatic equivalent.
///
/// DIFFERENCE FROM DART: No `_encoded` Int32List field.
/// REASON: Encoding is moved to C++ bridge. The C++ bridge will extract
/// all fields and encode them internally when NativeParagraphBuilder is
/// initialized.
public struct ParagraphStyle: Hashable, CustomStringConvertible {

  /// Creates a new ParagraphStyle object.
  ///
  /// **Dart Source:** `text.dart:2036-2070`
  /// **Original:** `ParagraphStyle({TextAlign? textAlign, ...})`
  ///
  /// - Parameters:
  ///   - textAlign: The alignment of the text within the lines of the paragraph.
  ///     If the last line is ellipsized (see `ellipsis` below), the alignment is
  ///     applied to that line after it has been truncated but before the ellipsis
  ///     has been added.
  ///   - textDirection: The directionality of the text, left-to-right (e.g. Norwegian)
  ///     or right-to-left (e.g. Hebrew). This controls the overall directionality of
  ///     the paragraph, as well as the meaning of `TextAlign.start` and `TextAlign.end`
  ///     in the `textAlign` field.
  ///   - maxLines: The maximum number of lines painted. Lines beyond this number are
  ///     silently dropped. For example, if `maxLines` is 1, then only one line is
  ///     rendered. If `maxLines` is nil, but `ellipsis` is not nil, then lines after
  ///     the first one that overflows the width constraints are dropped.
  ///   - fontFamily: The name of the font family to apply when painting the text,
  ///     in the absence of a `textStyle` being attached to the span.
  ///   - fontSize: The fallback size of glyphs (in logical pixels) to use when
  ///     painting the text. This is used when there is no `TextStyle`.
  ///   - height: The fallback height of the spans as a multiplier of the font size.
  ///     The fallback height is used when no height is provided through `TextStyle.height`.
  ///     Omitting `height` here (or setting it to `kTextHeightNone`) and in `TextStyle`
  ///     will allow the line height to take the height as defined by the font.
  ///   - textHeightBehavior: Specifies how the `height` multiplier is applied to ascent
  ///     of the first line and the descent of the last line.
  ///   - fontWeight: The typeface thickness to use when painting the text (e.g., bold).
  ///   - fontStyle: The typeface variant to use when drawing the letters (e.g., italics).
  ///   - strutStyle: The properties of the strut. Strut defines a set of minimum vertical
  ///     line height related metrics and can be used to obtain more advanced line spacing
  ///     behavior.
  ///   - ellipsis: String used to ellipsize overflowing text. If `maxLines` is not nil,
  ///     then the `ellipsis`, if any, is applied to the last rendered line, if that line
  ///     overflows the width constraints. If `maxLines` is nil, then the `ellipsis` is
  ///     applied to the first line that overflows the width constraints.
  ///   - locale: The locale used to select region-specific glyphs.
  public init(
    textAlign: TextAlign? = nil,
    textDirection: TextDirection? = nil,
    maxLines: Int? = nil,
    fontFamily: String? = nil,
    fontSize: Double? = nil,
    height: Double? = nil,
    textHeightBehavior: TextHeightBehavior? = nil,
    fontWeight: FontWeight? = nil,
    fontStyle: FontStyle? = nil,
    strutStyle: StrutStyle? = nil,
    ellipsis: String? = nil,
    locale: Locale? = nil
  ) {
    self.textAlign = textAlign
    self.textDirection = textDirection
    self.maxLines = maxLines
    self.fontFamily = fontFamily
    self.fontSize = fontSize
    self.height = height
    self.textHeightBehavior = textHeightBehavior
    self.fontWeight = fontWeight
    self.fontStyle = fontStyle
    self.strutStyle = strutStyle
    self.ellipsis = ellipsis
    self.locale = locale
    // Compute the leading distribution that will be used as the default
    // for TextStyles that don't specify one.
    self._leadingDistribution = textHeightBehavior?.leadingDistribution ?? .proportional
  }

  /// The alignment of the text within the lines of the paragraph.
  ///
  /// **Dart Source:** `text.dart:2037`
  public let textAlign: TextAlign?

  /// The directionality of the text.
  ///
  /// **Dart Source:** `text.dart:2038`
  public let textDirection: TextDirection?

  /// The maximum number of lines painted.
  ///
  /// **Dart Source:** `text.dart:2039`
  public let maxLines: Int?

  /// The name of the font family to apply when painting the text.
  ///
  /// **Dart Source:** `text.dart:2073`
  public let fontFamily: String?

  /// The fallback size of glyphs (in logical pixels).
  ///
  /// **Dart Source:** `text.dart:2074`
  public let fontSize: Double?

  /// The fallback height of the spans as a multiplier of the font size.
  ///
  /// **Dart Source:** `text.dart:2075`
  public let height: Double?

  /// Specifies how the `height` multiplier is applied.
  ///
  /// **Dart Source:** `text.dart:2043`
  public let textHeightBehavior: TextHeightBehavior?

  /// The typeface thickness to use when painting the text (e.g., bold).
  ///
  /// **Dart Source:** `text.dart:2044`
  public let fontWeight: FontWeight?

  /// The typeface variant to use when drawing the letters (e.g., italics).
  ///
  /// **Dart Source:** `text.dart:2045`
  public let fontStyle: FontStyle?

  /// The properties of the strut.
  ///
  /// **Dart Source:** `text.dart:2076`
  public let strutStyle: StrutStyle?

  /// String used to ellipsize overflowing text.
  ///
  /// **Dart Source:** `text.dart:2077`
  public let ellipsis: String?

  /// The locale used to select region-specific glyphs.
  ///
  /// **Dart Source:** `text.dart:2078`
  public let locale: Locale?

  /// The leading distribution that will be used as the default for TextStyles
  /// that don't specify one.
  ///
  /// **Dart Source:** `text.dart:2079`
  /// **Original:** `final TextLeadingDistribution _leadingDistribution;`
  ///
  /// This is derived from `textHeightBehavior?.leadingDistribution ?? .proportional`.
  internal let _leadingDistribution: TextLeadingDistribution

  // MARK: - Equatable

  /// **Dart Source:** `text.dart:2081-2098`
  /// **Original:** `bool operator ==(Object other)`
  ///
  /// DIFFERENCE FROM DART: Dart compared `_encoded` Int32List along with other fields.
  /// REASON: Since encoding is moved to C++ bridge, we compare all fields directly.
  /// The `_encoded` array contained: textAlign, textDirection, fontWeight, fontStyle,
  /// maxLines, textHeightBehavior (encoded), and flags for which fields are set.
  /// Comparing all fields directly is semantically equivalent.
  public static func == (lhs: ParagraphStyle, rhs: ParagraphStyle) -> Bool {
    return lhs.textAlign == rhs.textAlign
      && lhs.textDirection == rhs.textDirection
      && lhs.maxLines == rhs.maxLines
      && lhs.fontFamily == rhs.fontFamily
      && lhs.fontSize == rhs.fontSize
      && lhs.height == rhs.height
      && lhs.textHeightBehavior == rhs.textHeightBehavior
      && lhs.fontWeight == rhs.fontWeight
      && lhs.fontStyle == rhs.fontStyle
      && lhs.strutStyle == rhs.strutStyle
      && lhs.ellipsis == rhs.ellipsis
      && lhs.locale == rhs.locale
      && lhs._leadingDistribution == rhs._leadingDistribution
  }

  // MARK: - Hashable

  /// **Dart Source:** `text.dart:2100-2109`
  /// **Original:** `int get hashCode => Object.hash(Object.hashAll(_encoded), _fontFamily, ...);`
  ///
  /// DIFFERENCE FROM DART: Dart hashed `Object.hashAll(_encoded)` which included
  /// the encoded int array. Since encoding is moved to C++ bridge, we hash
  /// all the individual fields that would have been encoded.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(textAlign)
    hasher.combine(textDirection)
    hasher.combine(maxLines)
    hasher.combine(fontFamily)
    hasher.combine(fontSize)
    hasher.combine(height)
    hasher.combine(textHeightBehavior)
    hasher.combine(fontWeight)
    hasher.combine(fontStyle)
    hasher.combine(strutStyle)
    hasher.combine(ellipsis)
    hasher.combine(locale)
    hasher.combine(_leadingDistribution)
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `text.dart:2111-2127`
  /// **Original:** `String toString()`
  ///
  /// DIFFERENCE FROM DART: Dart used bitmask checks on `_encoded[0]` to determine
  /// which fields were specified. Since we don't use encoding, we check for nil directly.
  /// This is semantically equivalent since the bitmask was set based on whether
  /// each optional field was provided.
  public var description: String {
    func desc<T>(_ value: T?) -> String {
      if let v = value { return "\(v)" }
      return "unspecified"
    }

    let heightText: String
    if let h = height {
      heightText = "\(h)x"
    } else {
      heightText = "unspecified"
    }

    return "ParagraphStyle("
      + "textAlign: \(desc(textAlign)), "
      + "textDirection: \(desc(textDirection)), "
      + "fontWeight: \(desc(fontWeight)), "
      + "fontStyle: \(desc(fontStyle)), "
      + "maxLines: \(desc(maxLines)), "
      + "textHeightBehavior: \(desc(textHeightBehavior)), "
      + "fontFamily: \(desc(fontFamily)), "
      + "fontSize: \(desc(fontSize)), "
      + "height: \(heightText), "
      + "strutStyle: \(desc(strutStyle)), "
      + "ellipsis: \(ellipsis.map { "\"\($0)\"" } ?? "unspecified"), "
      + "locale: \(desc(locale))"
      + ")"
  }
}

// MARK: - Paragraph Protocol

/// A paragraph of text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `Paragraph`
/// **Lines:** 2966-3149
///
/// A paragraph retains the size and position of each glyph in the text and can
/// be efficiently resized and painted.
///
/// To create a `Paragraph` object, use a `ParagraphBuilder`.
///
/// Paragraphs can be displayed on a `Canvas` using the `Canvas.drawParagraph`
/// method.
///
/// DIFFERENCE FROM DART: Using `protocol` instead of `abstract class`.
/// REASON: Swift doesn't have abstract classes. A protocol with required
/// members provides equivalent functionality.
public protocol Paragraph: AnyObject {
  // MARK: - Properties (read-only)

  /// The amount of horizontal space this paragraph occupies.
  ///
  /// Valid only after `layout` has been called.
  ///
  /// **Dart Source:** `text.dart:2979`
  /// **Original:** `double get width;`
  var width: Double { get }

  /// The amount of vertical space this paragraph occupies.
  ///
  /// Valid only after `layout` has been called.
  ///
  /// **Dart Source:** `text.dart:2984`
  /// **Original:** `double get height;`
  var height: Double { get }

  /// The distance from the left edge of the leftmost glyph to the right edge of
  /// the rightmost glyph in the paragraph.
  ///
  /// Valid only after `layout` has been called.
  ///
  /// **Dart Source:** `text.dart:2990`
  /// **Original:** `double get longestLine;`
  var longestLine: Double { get }

  /// The minimum width that this paragraph could be without failing to paint
  /// its contents within itself.
  ///
  /// Valid only after `layout` has been called.
  ///
  /// **Dart Source:** `text.dart:2996`
  /// **Original:** `double get minIntrinsicWidth;`
  var minIntrinsicWidth: Double { get }

  /// Returns the smallest width beyond which increasing the width never
  /// decreases the height.
  ///
  /// Valid only after `layout` has been called.
  ///
  /// **Dart Source:** `text.dart:3002`
  /// **Original:** `double get maxIntrinsicWidth;`
  var maxIntrinsicWidth: Double { get }

  /// The distance from the top of the paragraph to the alphabetic
  /// baseline of the first line, in logical pixels.
  ///
  /// **Dart Source:** `text.dart:3006`
  /// **Original:** `double get alphabeticBaseline;`
  var alphabeticBaseline: Double { get }

  /// The distance from the top of the paragraph to the ideographic
  /// baseline of the first line, in logical pixels.
  ///
  /// **Dart Source:** `text.dart:3010`
  /// **Original:** `double get ideographicBaseline;`
  var ideographicBaseline: Double { get }

  /// True if there is more vertical content, but the text was truncated, either
  /// because we reached `maxLines` lines of text or because the `maxLines` was
  /// null, `ellipsis` was not null, and one of the lines exceeded the width
  /// constraint.
  ///
  /// See the discussion of the `maxLines` and `ellipsis` arguments at
  /// `ParagraphStyle.init`.
  ///
  /// **Dart Source:** `text.dart:3019`
  /// **Original:** `bool get didExceedMaxLines;`
  var didExceedMaxLines: Bool { get }

  /// The total number of visible lines in the paragraph.
  ///
  /// Returns a non-negative number. If `maxLines` is non-null, the value of
  /// `numberOfLines` never exceeds `maxLines`.
  ///
  /// **Dart Source:** `text.dart:3122`
  /// **Original:** `int get numberOfLines;`
  var numberOfLines: Int { get }

  /// Whether this reference to the underlying picture is `dispose`d.
  ///
  /// This only returns a valid value if asserts are enabled, and must not be
  /// used otherwise.
  ///
  /// **Dart Source:** `text.dart:3148`
  /// **Original:** `bool get debugDisposed;`
  var debugDisposed: Bool { get }

  // MARK: - Methods

  /// Computes the size and position of each glyph in the paragraph.
  ///
  /// The `ParagraphConstraints` control how wide the text is allowed to be.
  ///
  /// **Dart Source:** `text.dart:3024`
  /// **Original:** `void layout(ParagraphConstraints constraints);`
  func layout(_ constraints: ParagraphConstraints)

  /// Returns a list of text boxes that enclose the given text range.
  ///
  /// The `boxHeightStyle` and `boxWidthStyle` parameters allow customization
  /// of how the boxes are bound vertically and horizontally. Both style
  /// parameters default to the tight option, which will provide close-fitting
  /// boxes and will not account for any line spacing.
  ///
  /// Coordinates of the TextBox are relative to the upper-left corner of the paragraph,
  /// where positive y values indicate down.
  ///
  /// The `boxHeightStyle` and `boxWidthStyle` parameters must not be null.
  ///
  /// See `BoxHeightStyle` and `BoxWidthStyle` for full descriptions of each option.
  ///
  /// **Dart Source:** `text.dart:3039-3044`
  /// **Original:** `List<TextBox> getBoxesForRange(int start, int end, {BoxHeightStyle boxHeightStyle = BoxHeightStyle.tight, BoxWidthStyle boxWidthStyle = BoxWidthStyle.tight});`
  func getBoxesForRange(
    _ start: Int,
    _ end: Int,
    boxHeightStyle: BoxHeightStyle,
    boxWidthStyle: BoxWidthStyle
  ) -> [TextBox]

  /// Returns a list of text boxes that enclose all placeholders in the paragraph.
  ///
  /// The order of the boxes are in the same order as passed in through
  /// `ParagraphBuilder.addPlaceholder`.
  ///
  /// Coordinates of the `TextBox` are relative to the upper-left corner of the paragraph,
  /// where positive y values indicate down.
  ///
  /// **Dart Source:** `text.dart:3053`
  /// **Original:** `List<TextBox> getBoxesForPlaceholders();`
  func getBoxesForPlaceholders() -> [TextBox]

  /// Returns the text position closest to the given offset.
  ///
  /// This method always returns a `TextPosition` for any given `offset`, even
  /// when the `offset` is not close to any text, or when the paragraph is empty.
  /// This is useful for determining the text to select when the user drags the
  /// text selection handle.
  ///
  /// See also:
  ///
  ///  * `getClosestGlyphInfoForOffset`, which returns more information about
  ///    the closest character to an `Offset`.
  ///
  /// **Dart Source:** `text.dart:3066`
  /// **Original:** `TextPosition getPositionForOffset(Offset offset);`
  func getPositionForOffset(_ offset: Offset) -> TextPosition

  /// Returns the `GlyphInfo` of the glyph closest to the given `offset` in the
  /// paragraph coordinate system, or nil if if the text is empty, or is
  /// entirely clipped or ellipsized away.
  ///
  /// This method first finds the line closest to `offset.dy`, and then returns
  /// the `GlyphInfo` of the closest glyph(s) within that line.
  ///
  /// **Dart Source:** `text.dart:3074`
  /// **Original:** `GlyphInfo? getClosestGlyphInfoForOffset(Offset offset);`
  func getClosestGlyphInfoForOffset(_ offset: Offset) -> GlyphInfo?

  /// Returns the `GlyphInfo` located at the given UTF-16 `codeUnitOffset` in
  /// the paragraph, or nil if the given `codeUnitOffset` is out of the visible
  /// lines or is ellipsized.
  ///
  /// **Dart Source:** `text.dart:3079`
  /// **Original:** `GlyphInfo? getGlyphInfoAt(int codeUnitOffset);`
  func getGlyphInfoAt(_ codeUnitOffset: Int) -> GlyphInfo?

  /// Returns the `TextRange` of the word at the given `TextPosition`.
  ///
  /// Characters not part of a word, such as spaces, symbols, and punctuation,
  /// have word breaks on both sides. In such cases, this method will return
  /// (offset, offset+1). Word boundaries are defined more precisely in Unicode
  /// Standard Annex #29 http://www.unicode.org/reports/tr29/#Word_Boundaries
  ///
  /// The `TextPosition` is treated as caret position, its `TextPosition.affinity`
  /// is used to determine which character this position points to. For example,
  /// the word boundary at `TextPosition(offset: 5, affinity: TextAffinity.upstream)`
  /// of the `string = 'Hello word'` will return range (0, 5) because the position
  /// points to the character 'o' instead of the space.
  ///
  /// **Dart Source:** `text.dart:3093`
  /// **Original:** `TextRange getWordBoundary(TextPosition position);`
  func getWordBoundary(_ position: TextPosition) -> TextRange

  /// Returns the `TextRange` of the line at the given `TextPosition`.
  ///
  /// The newline (if any) is returned as part of the range.
  ///
  /// Not valid until after layout.
  ///
  /// This can potentially be expensive, since it needs to compute the line
  /// metrics, so use it sparingly.
  ///
  /// **Dart Source:** `text.dart:3103`
  /// **Original:** `TextRange getLineBoundary(TextPosition position);`
  func getLineBoundary(_ position: TextPosition) -> TextRange

  /// Returns the full list of `LineMetrics` that describe in detail the various
  /// metrics of each laid out line.
  ///
  /// Not valid until after layout.
  ///
  /// This can potentially return a large amount of data, so it is not recommended
  /// to repeatedly call this. Instead, cache the results.
  ///
  /// **Dart Source:** `text.dart:3112`
  /// **Original:** `List<LineMetrics> computeLineMetrics();`
  func computeLineMetrics() -> [LineMetrics]

  /// Returns the `LineMetrics` for the line at `lineNumber`, or nil if the
  /// given `lineNumber` is greater than or equal to `numberOfLines`.
  ///
  /// **Dart Source:** `text.dart:3116`
  /// **Original:** `LineMetrics? getLineMetricsAt(int lineNumber);`
  func getLineMetricsAt(_ lineNumber: Int) -> LineMetrics?

  /// Returns the line number of the line that contains the code unit that
  /// `codeUnitOffset` points to.
  ///
  /// This method returns nil if the given `codeUnitOffset` is out of bounds, or
  /// is logically after the last visible codepoint. This includes the case where
  /// its codepoint belongs to a visible line, but the text layout library
  /// replaced it with an ellipsis.
  ///
  /// If the target code unit points to a control character that introduces
  /// mandatory line breaks (most notably the line feed character `LF`, typically
  /// represented in strings as the escape sequence "\n"), to conform to
  /// [the unicode rules](https://unicode.org/reports/tr14/#LB4), the control
  /// character itself is always considered to be at the end of "current" line
  /// rather than the beginning of the new line.
  ///
  /// **Dart Source:** `text.dart:3138`
  /// **Original:** `int? getLineNumberAt(int codeUnitOffset);`
  func getLineNumberAt(_ codeUnitOffset: Int) -> Int?

  /// Release the resources used by this object. The object is no longer usable
  /// after this method is called.
  ///
  /// **Dart Source:** `text.dart:3142`
  /// **Original:** `void dispose();`
  func dispose()
}

// MARK: - Paragraph Protocol Extension (Default Implementations)

/// Default implementations for optional parameters in `Paragraph` methods.
///
/// **Dart Source:** `text.dart:3039-3044`
/// **Original:** The Dart abstract class has default parameter values. Since Swift
/// protocols cannot have default parameter values, we provide them via extension.
public extension Paragraph {
  /// Returns a list of text boxes that enclose the given text range.
  ///
  /// This is a convenience overload with default style parameters.
  ///
  /// **Dart Source:** `text.dart:3039-3044`
  /// **Original:** `List<TextBox> getBoxesForRange(int start, int end, {BoxHeightStyle boxHeightStyle = BoxHeightStyle.tight, BoxWidthStyle boxWidthStyle = BoxWidthStyle.tight});`
  func getBoxesForRange(
    _ start: Int,
    _ end: Int,
    boxHeightStyle: BoxHeightStyle = .tight,
    boxWidthStyle: BoxWidthStyle = .tight
  ) -> [TextBox] {
    getBoxesForRange(start, end, boxHeightStyle: boxHeightStyle, boxWidthStyle: boxWidthStyle)
  }
}

// MARK: - NativeParagraph

/// Native implementation of the `Paragraph` protocol that wraps a C++ paragraph.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart:3151-3412`
/// **Original Name:** `_NativeParagraph`
///
/// This class wraps a `ParagraphBridge` which holds a `std::unique_ptr<txt::Paragraph>`.
/// It is created by `ParagraphBuilder.build()` and represents laid out text.
///
/// DIFFERENCE FROM DART: Class is named `NativeParagraph` (no underscore prefix).
/// REASON: Swift uses `public`/`internal` access control instead of underscore-prefix
/// naming convention for internal types.
///
/// DIFFERENCE FROM DART: Uses `ParagraphBridge` with `SWIFT_SHARED_REFERENCE` instead
/// of `NativeFieldWrapperClass1` / Dart VM wrapper.
/// REASON: Swift layer calls C++ directly; no Dart VM involvement.
public class NativeParagraph: Paragraph {
  /// The C++ bridge object that holds the paragraph.
  ///
  /// **Dart Source:** `text.dart:3151`
  /// **Original:** `_NativeParagraph extends NativeFieldWrapperClass1`
  ///
  /// DIFFERENCE FROM DART: Uses ParagraphBridge with SWIFT_SHARED_REFERENCE
  /// instead of NativeFieldWrapperClass1 / Dart VM wrapper.
  /// REASON: Swift layer calls C++ directly; no Dart VM involvement.
  internal let bridge: flutter.swift_bridge.ParagraphBridge

  /// Tracks whether layout() has been called.
  ///
  /// **Dart Source:** `text.dart:3158`
  /// **Original:** `bool _needsLayout = true;`
  ///
  /// Used in debug assertions to ensure layout is called before rendering.
  #if DEBUG
    private var _needsLayout: Bool = true
  #endif

  /// Whether this paragraph has been disposed.
  ///
  /// **Dart Source:** `text.dart:3377`
  /// **Original:** `bool _disposed = false;`
  ///
  /// Only valid in debug mode.
  #if DEBUG
    private var _disposed: Bool = false
  #endif

  /// Creates a NativeParagraph wrapping a ParagraphBridge.
  ///
  /// **Dart Source:** `text.dart:3152-3156`
  /// **Original:** `_NativeParagraph._()`
  ///
  /// DIFFERENCE FROM DART: Takes a ParagraphBridge parameter instead of being
  /// engine-created via NativeFieldWrapperClass1.
  /// REASON: Swift creates the wrapper directly around the C++ bridge object.
  internal init(_ bridge: flutter.swift_bridge.ParagraphBridge) {
    self.bridge = bridge
  }

  // MARK: - Properties

  /// The amount of horizontal space this paragraph occupies.
  ///
  /// **Dart Source:** `text.dart:3161-3162`
  /// **Original:** `@Native<Double Function(Pointer<Void>)>(symbol: 'Paragraph::width')`
  public var width: Double {
    bridge.GetWidth()
  }

  /// The amount of vertical space this paragraph occupies.
  ///
  /// **Dart Source:** `text.dart:3165-3166`
  /// **Original:** `@Native<Double Function(Pointer<Void>)>(symbol: 'Paragraph::height')`
  public var height: Double {
    bridge.GetHeight()
  }

  /// The distance from the left edge of the leftmost glyph to the right edge of
  /// the rightmost glyph in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3168-3170`
  /// **Original:** `@Native<Double Function(Pointer<Void>)>(symbol: 'Paragraph::longestLine')`
  public var longestLine: Double {
    bridge.GetLongestLine()
  }

  /// The minimum width that this paragraph could be without failing to paint
  /// its contents within itself.
  ///
  /// **Dart Source:** `text.dart:3173-3174`
  /// **Original:** `@Native<Double Function(Pointer<Void>)>(symbol: 'Paragraph::minIntrinsicWidth')`
  public var minIntrinsicWidth: Double {
    bridge.GetMinIntrinsicWidth()
  }

  /// Returns the smallest width beyond which increasing the width never
  /// decreases the height.
  ///
  /// **Dart Source:** `text.dart:3177-3178`
  /// **Original:** `@Native<Double Function(Pointer<Void>)>(symbol: 'Paragraph::maxIntrinsicWidth')`
  public var maxIntrinsicWidth: Double {
    bridge.GetMaxIntrinsicWidth()
  }

  /// The distance from the top of the paragraph to the alphabetic
  /// baseline of the first line, in logical pixels.
  ///
  /// **Dart Source:** `text.dart:3181-3182`
  /// **Original:** `@Native<Double Function(Pointer<Void>)>(symbol: 'Paragraph::alphabeticBaseline')`
  public var alphabeticBaseline: Double {
    bridge.GetAlphabeticBaseline()
  }

  /// The distance from the top of the paragraph to the ideographic
  /// baseline of the first line, in logical pixels.
  ///
  /// **Dart Source:** `text.dart:3185-3186`
  /// **Original:** `@Native<Double Function(Pointer<Void>)>(symbol: 'Paragraph::ideographicBaseline')`
  public var ideographicBaseline: Double {
    bridge.GetIdeographicBaseline()
  }

  /// True if there is more vertical content, but the text was truncated.
  ///
  /// **Dart Source:** `text.dart:3189-3190`
  /// **Original:** `@Native<Bool Function(Pointer<Void>)>(symbol: 'Paragraph::didExceedMaxLines')`
  public var didExceedMaxLines: Bool {
    bridge.DidExceedMaxLines()
  }

  /// The total number of visible lines in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3350-3351`
  /// **Original:** `@Native<Uint32 Function(Pointer<Void>)>(symbol: 'Paragraph::getNumberOfLines')`
  public var numberOfLines: Int {
    Int(bridge.GetNumberOfLines())
  }

  /// Whether this reference to the underlying picture is disposed.
  ///
  /// **Dart Source:** `text.dart:3380-3390`
  /// **Original:**
  /// ```dart
  /// bool get debugDisposed {
  ///   bool? disposed;
  ///   assert(() {
  ///     disposed = _disposed;
  ///     return true;
  ///   }());
  ///   return disposed ?? (throw StateError(...));
  /// }
  /// ```
  ///
  /// DIFFERENCE FROM DART: Always returns actual disposed state in debug builds,
  /// returns bridge.IsDisposed() in release builds.
  /// REASON: Swift doesn't have the exact same assert pattern, but the debug
  /// flag tracking is equivalent.
  public var debugDisposed: Bool {
    #if DEBUG
      return _disposed
    #else
      return bridge.IsDisposed()
    #endif
  }

  // MARK: - Methods

  /// Computes the size and position of each glyph in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3193-3199`
  /// **Original:**
  /// ```dart
  /// void layout(ParagraphConstraints constraints) {
  ///   _layout(constraints.width);
  ///   assert(() {
  ///     _needsLayout = false;
  ///     return true;
  ///   }());
  /// }
  /// ```
  public func layout(_ constraints: ParagraphConstraints) {
    bridge.Layout(constraints.width)
    #if DEBUG
      _needsLayout = false
    #endif
  }

  /// Decodes text boxes from a flat Float32 array.
  ///
  /// **Dart Source:** `text.dart:3204-3220`
  /// **Original:**
  /// ```dart
  /// List<TextBox> _decodeTextBoxes(Float32List encoded) {
  ///   final int count = encoded.length ~/ 5;
  ///   final List<TextBox> boxes = <TextBox>[];
  ///   int position = 0;
  ///   for (int index = 0; index < count; index += 1) {
  ///     boxes.add(TextBox.fromLTRBD(
  ///       encoded[position++],
  ///       encoded[position++],
  ///       encoded[position++],
  ///       encoded[position++],
  ///       TextDirection.values[encoded[position++].toInt()],
  ///     ));
  ///   }
  ///   return boxes;
  /// }
  /// ```
  private func decodeTextBoxes(_ data: [Float], count: Int) -> [TextBox] {
    var boxes: [TextBox] = []
    boxes.reserveCapacity(count)
    var position = 0
    for _ in 0..<count {
      let left = Double(data[position])
      let top = Double(data[position + 1])
      let right = Double(data[position + 2])
      let bottom = Double(data[position + 3])
      let directionRaw = Int(data[position + 4])
      position += 5
      // TextDirection: 0 = rtl, 1 = ltr
      let direction = TextDirection(rawValue: directionRaw) ?? .ltr
      boxes.append(TextBox(fromLTRBD: left, top, right, bottom, direction))
    }
    return boxes
  }

  /// Returns a list of text boxes that enclose the given text range.
  ///
  /// **Dart Source:** `text.dart:3222-3232`
  /// **Original:**
  /// ```dart
  /// List<TextBox> getBoxesForRange(
  ///   int start,
  ///   int end, {
  ///   BoxHeightStyle boxHeightStyle = BoxHeightStyle.tight,
  ///   BoxWidthStyle boxWidthStyle = BoxWidthStyle.tight,
  /// }) {
  ///   return _decodeTextBoxes(
  ///     _getBoxesForRange(start, end, boxHeightStyle.index, boxWidthStyle.index),
  ///   );
  /// }
  /// ```
  public func getBoxesForRange(
    _ start: Int,
    _ end: Int,
    boxHeightStyle: BoxHeightStyle,
    boxWidthStyle: BoxWidthStyle
  ) -> [TextBox] {
    // First get the count to allocate buffer
    let boxCount = bridge.GetBoxesForRangeCount(
      UInt32(start),
      UInt32(end),
      UInt32(boxHeightStyle.rawValue),
      UInt32(boxWidthStyle.rawValue)
    )
    guard boxCount > 0 else { return [] }

    // Each box is 5 floats: left, top, right, bottom, direction
    var data = [Float](repeating: 0, count: Int(boxCount) * 5)
    var outCount: Int = 0
    data.withUnsafeMutableBufferPointer { buffer in
      bridge.GetBoxesForRange(
        UInt32(start),
        UInt32(end),
        UInt32(boxHeightStyle.rawValue),
        UInt32(boxWidthStyle.rawValue),
        buffer.baseAddress,
        &outCount,
        boxCount
      )
    }
    return decodeTextBoxes(data, count: outCount)
  }

  /// Returns a list of text boxes that enclose all placeholders in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3240-3243`
  /// **Original:**
  /// ```dart
  /// List<TextBox> getBoxesForPlaceholders() {
  ///   return _decodeTextBoxes(_getBoxesForPlaceholders());
  /// }
  /// ```
  public func getBoxesForPlaceholders() -> [TextBox] {
    let boxCount = bridge.GetBoxesForPlaceholdersCount()
    guard boxCount > 0 else { return [] }

    var data = [Float](repeating: 0, count: Int(boxCount) * 5)
    var outCount: Int = 0
    data.withUnsafeMutableBufferPointer { buffer in
      bridge.GetBoxesForPlaceholders(buffer.baseAddress, &outCount, boxCount)
    }
    return decodeTextBoxes(data, count: outCount)
  }

  /// Returns the text position closest to the given offset.
  ///
  /// **Dart Source:** `text.dart:3248-3252`
  /// **Original:**
  /// ```dart
  /// TextPosition getPositionForOffset(Offset offset) {
  ///   final List<int> encoded = _getPositionForOffset(offset.dx, offset.dy);
  ///   return TextPosition(offset: encoded[0], affinity: TextAffinity.values[encoded[1]]);
  /// }
  /// ```
  public func getPositionForOffset(_ offset: Offset) -> TextPosition {
    var outOffset: Int = 0
    var outAffinity: Int32 = 0
    bridge.GetPositionForOffset(offset.dx, offset.dy, &outOffset, &outAffinity)
    // TextAffinity: 0 = upstream, 1 = downstream
    let affinity = TextAffinity(rawValue: Int(outAffinity)) ?? .downstream
    return TextPosition(offset: outOffset, affinity: affinity)
  }

  /// Returns the `GlyphInfo` located at the given UTF-16 `codeUnitOffset`.
  ///
  /// **Dart Source:** `text.dart:3257-3259`
  /// **Original:**
  /// ```dart
  /// GlyphInfo? getGlyphInfoAt(int codeUnitOffset) => _getGlyphInfoAt(codeUnitOffset, GlyphInfo._);
  /// ```
  public func getGlyphInfoAt(_ codeUnitOffset: Int) -> GlyphInfo? {
    var boundsLeft: Double = 0
    var boundsTop: Double = 0
    var boundsRight: Double = 0
    var boundsBottom: Double = 0
    var rangeStart: Int = 0
    var rangeEnd: Int = 0
    var isLtr: Bool = true

    let found = bridge.GetGlyphInfoAt(
      UInt32(codeUnitOffset),
      &boundsLeft,
      &boundsTop,
      &boundsRight,
      &boundsBottom,
      &rangeStart,
      &rangeEnd,
      &isLtr
    )

    guard found else { return nil }

    let bounds = Rect.fromLTRB(boundsLeft, boundsTop, boundsRight, boundsBottom)
    let range = TextRange(start: rangeStart, end: rangeEnd)
    let direction: TextDirection = isLtr ? .ltr : .rtl

    return GlyphInfo(bounds, range, direction)
  }

  /// Returns the `GlyphInfo` closest to the given offset.
  ///
  /// **Dart Source:** `text.dart:3262-3264`
  /// **Original:**
  /// ```dart
  /// GlyphInfo? getClosestGlyphInfoForOffset(Offset offset) =>
  ///     _getClosestGlyphInfoForOffset(offset.dx, offset.dy, GlyphInfo._);
  /// ```
  public func getClosestGlyphInfoForOffset(_ offset: Offset) -> GlyphInfo? {
    var boundsLeft: Double = 0
    var boundsTop: Double = 0
    var boundsRight: Double = 0
    var boundsBottom: Double = 0
    var rangeStart: Int = 0
    var rangeEnd: Int = 0
    var isLtr: Bool = true

    let found = bridge.GetClosestGlyphInfoForOffset(
      offset.dx,
      offset.dy,
      &boundsLeft,
      &boundsTop,
      &boundsRight,
      &boundsBottom,
      &rangeStart,
      &rangeEnd,
      &isLtr
    )

    guard found else { return nil }

    let bounds = Rect.fromLTRB(boundsLeft, boundsTop, boundsRight, boundsBottom)
    let range = TextRange(start: rangeStart, end: rangeEnd)
    let direction: TextDirection = isLtr ? .ltr : .rtl

    return GlyphInfo(bounds, range, direction)
  }

  /// Returns the `TextRange` of the word at the given `TextPosition`.
  ///
  /// **Dart Source:** `text.dart:3270-3281`
  /// **Original:**
  /// ```dart
  /// TextRange getWordBoundary(TextPosition position) {
  ///   final int characterPosition;
  ///   switch (position.affinity) {
  ///     case TextAffinity.upstream:
  ///       characterPosition = position.offset - 1;
  ///     case TextAffinity.downstream:
  ///       characterPosition = position.offset;
  ///   }
  ///   final List<int> boundary = _getWordBoundary(characterPosition);
  ///   return TextRange(start: boundary[0], end: boundary[1]);
  /// }
  /// ```
  public func getWordBoundary(_ position: TextPosition) -> TextRange {
    let characterPosition: Int
    switch position.affinity {
    case .upstream:
      characterPosition = position.offset - 1
    case .downstream:
      characterPosition = position.offset
    }

    var outStart: Int = 0
    var outEnd: Int = 0
    bridge.GetWordBoundary(UInt32(max(0, characterPosition)), &outStart, &outEnd)
    return TextRange(start: outStart, end: outEnd)
  }

  /// Returns the `TextRange` of the line at the given `TextPosition`.
  ///
  /// **Dart Source:** `text.dart:3286-3308`
  /// **Original:**
  /// ```dart
  /// TextRange getLineBoundary(TextPosition position) {
  ///   final List<int> boundary = _getLineBoundary(position.offset);
  ///   final TextRange line = TextRange(start: boundary[0], end: boundary[1]);
  ///
  ///   final List<int> nextBoundary = _getLineBoundary(position.offset + 1);
  ///   final TextRange nextLine = TextRange(start: nextBoundary[0], end: nextBoundary[1]);
  ///   // If there is no next line, because we're at the end of the field, return line.
  ///   if (!nextLine.isValid) {
  ///     return line;
  ///   }
  ///
  ///   // _getLineBoundary only considers the offset and assumes that the
  ///   // TextAffinity is upstream. In the case that TextPosition is just after a
  ///   // word wrap (downstream), we need to return the line for the next offset.
  ///   if (position.affinity == TextAffinity.downstream &&
  ///       line != nextLine &&
  ///       position.offset == line.end &&
  ///       line.end == nextLine.start) {
  ///     return TextRange(start: nextBoundary[0], end: nextBoundary[1]);
  ///   }
  ///   return line;
  /// }
  /// ```
  public func getLineBoundary(_ position: TextPosition) -> TextRange {
    var lineStart: Int32 = 0
    var lineEnd: Int32 = 0
    bridge.GetLineBoundary(UInt32(position.offset), &lineStart, &lineEnd)
    let line = TextRange(start: Int(lineStart), end: Int(lineEnd))

    var nextLineStart: Int32 = 0
    var nextLineEnd: Int32 = 0
    bridge.GetLineBoundary(UInt32(position.offset + 1), &nextLineStart, &nextLineEnd)
    let nextLine = TextRange(start: Int(nextLineStart), end: Int(nextLineEnd))

    // If there is no next line, because we're at the end of the field, return line.
    if !nextLine.isValid {
      return line
    }

    // _getLineBoundary only considers the offset and assumes that the
    // TextAffinity is upstream. In the case that TextPosition is just after a
    // word wrap (downstream), we need to return the line for the next offset.
    if position.affinity == .downstream
      && line != nextLine
      && position.offset == line.end
      && line.end == nextLine.start
    {
      return TextRange(start: Int(nextLineStart), end: Int(nextLineEnd))
    }
    return line
  }

  /// Returns the full list of `LineMetrics` that describe in detail the various
  /// metrics of each laid out line.
  ///
  /// **Dart Source:** `text.dart:3320-3338`
  /// **Original:**
  /// ```dart
  /// List<LineMetrics> computeLineMetrics() {
  ///   final Float64List encoded = _computeLineMetrics();
  ///   final int count = encoded.length ~/ 9;
  ///   int position = 0;
  ///   final List<LineMetrics> metrics = <LineMetrics>[
  ///     for (int index = 0; index < count; index += 1)
  ///       LineMetrics(
  ///         hardBreak: encoded[position++] != 0,
  ///         ascent: encoded[position++],
  ///         descent: encoded[position++],
  ///         unscaledAscent: encoded[position++],
  ///         height: encoded[position++],
  ///         width: encoded[position++],
  ///         left: encoded[position++],
  ///         baseline: encoded[position++],
  ///         lineNumber: encoded[position++].toInt(),
  ///       ),
  ///   ];
  ///   return metrics;
  /// }
  /// ```
  public func computeLineMetrics() -> [LineMetrics] {
    let lineCount = bridge.ComputeLineMetricsCount()
    guard lineCount > 0 else { return [] }

    // Each line is 9 doubles: hardBreak, ascent, descent, unscaledAscent,
    // height, width, left, baseline, lineNumber
    var data = [Double](repeating: 0, count: Int(lineCount) * 9)
    var outCount: Int = 0
    data.withUnsafeMutableBufferPointer { buffer in
      bridge.ComputeLineMetrics(buffer.baseAddress, &outCount, lineCount)
    }

    var metrics: [LineMetrics] = []
    metrics.reserveCapacity(outCount)
    var position = 0
    for _ in 0..<outCount {
      let hardBreak = data[position] != 0
      let ascent = data[position + 1]
      let descent = data[position + 2]
      let unscaledAscent = data[position + 3]
      let height = data[position + 4]
      let width = data[position + 5]
      let left = data[position + 6]
      let baseline = data[position + 7]
      let lineNumber = Int(data[position + 8])
      position += 9

      metrics.append(
        LineMetrics(
          hardBreak: hardBreak,
          ascent: ascent,
          descent: descent,
          unscaledAscent: unscaledAscent,
          height: height,
          width: width,
          left: left,
          baseline: baseline,
          lineNumber: lineNumber
        ))
    }
    return metrics
  }

  /// Returns the `LineMetrics` for the line at `lineNumber`.
  ///
  /// **Dart Source:** `text.dart:3344-3345`
  /// **Original:**
  /// ```dart
  /// LineMetrics? getLineMetricsAt(int lineNumber) => _getLineMetricsAt(lineNumber, LineMetrics._);
  /// ```
  public func getLineMetricsAt(_ lineNumber: Int) -> LineMetrics? {
    var hardBreak: Bool = false
    var ascent: Double = 0
    var descent: Double = 0
    var unscaledAscent: Double = 0
    var height: Double = 0
    var width: Double = 0
    var left: Double = 0
    var baseline: Double = 0
    var outLineNumber: Int32 = 0

    let found = bridge.GetLineMetricsAt(
      Int32(lineNumber),
      &hardBreak,
      &ascent,
      &descent,
      &unscaledAscent,
      &height,
      &width,
      &left,
      &baseline,
      &outLineNumber
    )

    guard found else { return nil }

    return LineMetrics(
      hardBreak: hardBreak,
      ascent: ascent,
      descent: descent,
      unscaledAscent: unscaledAscent,
      height: height,
      width: width,
      left: left,
      baseline: baseline,
      lineNumber: Int(outLineNumber)
    )
  }

  /// Returns the line number of the line that contains the code unit that
  /// `codeUnitOffset` points to.
  ///
  /// **Dart Source:** `text.dart:3354-3357`
  /// **Original:**
  /// ```dart
  /// int? getLineNumberAt(int codeUnitOffset) {
  ///   final int lineNumber = _getLineNumber(codeUnitOffset);
  ///   return lineNumber < 0 ? null : lineNumber;
  /// }
  /// ```
  public func getLineNumberAt(_ codeUnitOffset: Int) -> Int? {
    let lineNumber = bridge.GetLineNumberAt(codeUnitOffset)
    return lineNumber < 0 ? nil : Int(lineNumber)
  }

  /// Release the resources used by this object.
  ///
  /// **Dart Source:** `text.dart:3362-3370`
  /// **Original:**
  /// ```dart
  /// void dispose() {
  ///   assert(!_disposed);
  ///   assert(() {
  ///     _disposed = true;
  ///     return true;
  ///   }());
  ///   _dispose();
  /// }
  /// ```
  public func dispose() {
    #if DEBUG
      assert(!_disposed, "Paragraph has already been disposed")
      _disposed = true
    #endif
    bridge.Dispose()
  }

  // MARK: - CustomStringConvertible (toString)

  /// Returns a string representation of this paragraph.
  ///
  /// **Dart Source:** `text.dart:3392-3411`
  /// **Original:**
  /// ```dart
  /// String toString() {
  ///   String? result;
  ///   assert(() {
  ///     if (_disposed && _needsLayout) {
  ///       result = 'Paragraph(DISPOSED while dirty)';
  ///     }
  ///     if (_disposed && !_needsLayout) {
  ///       result = 'Paragraph(DISPOSED)';
  ///     }
  ///     return true;
  ///   }());
  ///   if (result != null) {
  ///     return result!;
  ///   }
  ///   if (_needsLayout) {
  ///     return 'Paragraph(dirty)';
  ///   }
  ///   return 'Paragraph()';
  /// }
  /// ```
  public var description: String {
    #if DEBUG
      if _disposed && _needsLayout {
        return "Paragraph(DISPOSED while dirty)"
      }
      if _disposed {
        return "Paragraph(DISPOSED)"
      }
      if _needsLayout {
        return "Paragraph(dirty)"
      }
    #endif
    return "Paragraph()"
  }
}

// MARK: - ParagraphBuilder Protocol

/// Builds a [Paragraph] containing text with the given styling information.
///
/// **Dart Source:** `text.dart:3414-3519`
/// **Original Name:** `ParagraphBuilder` (abstract class)
///
/// To set the paragraph's alignment, truncation, and ellipsizing behavior, pass
/// an appropriately-configured [ParagraphStyle] object to the
/// [ParagraphBuilders.create] factory method.
///
/// Then, call combinations of [pushStyle], [addText], and [pop] to add styled
/// text to the object.
///
/// Finally, call [build] to obtain the constructed [Paragraph] object. After
/// this point, the builder is no longer usable.
///
/// After constructing a [Paragraph], call [Paragraph.layout] on it and then
/// paint it with [Canvas.drawParagraph].
///
/// DIFFERENCE FROM DART: Uses a protocol instead of abstract class.
/// REASON: Swift doesn't have abstract classes; protocol provides equivalent interface.
/// The factory constructor `factory ParagraphBuilder(ParagraphStyle style) = _NativeParagraphBuilder;`
/// is handled by the `ParagraphBuilders` factory namespace (Task 5.4).
public protocol ParagraphBuilder: AnyObject {
  // MARK: - Properties

  /// The number of placeholders currently in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3433-3434`
  /// **Original:**
  /// ```dart
  /// int get placeholderCount;
  /// ```
  var placeholderCount: Int { get }

  /// The scales of the placeholders in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3436-3437`
  /// **Original:**
  /// ```dart
  /// List<double> get placeholderScales;
  /// ```
  var placeholderScales: [Double] { get }

  // MARK: - Methods

  /// Applies the given style to the added text until [pop] is called.
  ///
  /// **Dart Source:** `text.dart:3439-3442`
  /// **Original:**
  /// ```dart
  /// void pushStyle(TextStyle style);
  /// ```
  ///
  /// See [pop] for details.
  func pushStyle(_ style: TextStyle)

  /// Ends the effect of the most recent call to [pushStyle].
  ///
  /// **Dart Source:** `text.dart:3444-3450`
  /// **Original:**
  /// ```dart
  /// void pop();
  /// ```
  ///
  /// Internally, the paragraph builder maintains a stack of text styles. Text
  /// added to the paragraph is affected by all the styles in the stack. Calling
  /// [pop] removes the topmost style in the stack, leaving the remaining styles
  /// in effect.
  func pop()

  /// Adds the given text to the paragraph.
  ///
  /// **Dart Source:** `text.dart:3452-3455`
  /// **Original:**
  /// ```dart
  /// void addText(String text);
  /// ```
  ///
  /// The text will be styled according to the current stack of text styles.
  func addText(_ text: String)

  /// Adds an inline placeholder space to the paragraph.
  ///
  /// **Dart Source:** `text.dart:3457-3511`
  /// **Original:**
  /// ```dart
  /// void addPlaceholder(
  ///   double width,
  ///   double height,
  ///   PlaceholderAlignment alignment, {
  ///   double scale = 1.0,
  ///   double? baselineOffset,
  ///   TextBaseline? baseline,
  /// });
  /// ```
  ///
  /// The paragraph will contain a rectangular space with no text of the dimensions
  /// specified.
  ///
  /// The `width` and `height` parameters specify the size of the placeholder rectangle.
  ///
  /// The `alignment` parameter specifies how the placeholder rectangle will be vertically
  /// aligned with the surrounding text. When [PlaceholderAlignment.baseline],
  /// [PlaceholderAlignment.aboveBaseline], and [PlaceholderAlignment.belowBaseline]
  /// alignment modes are used, the baseline needs to be set with the `baseline`.
  /// When using [PlaceholderAlignment.baseline], `baselineOffset` indicates the distance
  /// of the baseline down from the top of the rectangle. The default `baselineOffset`
  /// is the `height`.
  ///
  /// Examples:
  ///
  /// * For a 30x50 placeholder with the bottom edge aligned with the bottom of the text, use:
  /// `addPlaceholder(30, 50, .bottom)`
  /// * For a 30x50 placeholder that is vertically centered around the text, use:
  /// `addPlaceholder(30, 50, .middle)`.
  /// * For a 30x50 placeholder that sits completely on top of the alphabetic baseline, use:
  /// `addPlaceholder(30, 50, .aboveBaseline, baseline: .alphabetic)`.
  /// * For a 30x50 placeholder with 40 pixels above and 10 pixels below the alphabetic baseline, use:
  /// `addPlaceholder(30, 50, .baseline, baselineOffset: 40, baseline: .alphabetic)`.
  ///
  /// Lines are permitted to break around each placeholder.
  ///
  /// Decorations will be drawn based on the font defined in the most recently
  /// pushed [TextStyle]. The decorations are drawn as if unicode text were present
  /// in the placeholder space, and will draw the same regardless of the height and
  /// alignment of the placeholder. To hide or manually adjust decorations to fit,
  /// a text style with the desired decoration behavior should be pushed before
  /// adding a placeholder.
  ///
  /// Any decorations drawn through a placeholder will exist on the same canvas/layer
  /// as the text. This means any content drawn on top of the space reserved by
  /// the placeholder will be drawn over the decoration, possibly obscuring the
  /// decoration.
  ///
  /// Placeholders are represented by a unicode 0xFFFC "object replacement character"
  /// in the text buffer. For each placeholder, one object replacement character is
  /// added on to the text buffer.
  ///
  /// The `scale` parameter will scale the `width` and `height` by the specified amount,
  /// and keep track of the scale. The scales of placeholders added can be accessed
  /// through [placeholderScales]. This is primarily used for accessibility scaling.
  func addPlaceholder(
    _ width: Double,
    _ height: Double,
    _ alignment: PlaceholderAlignment,
    scale: Double,
    baselineOffset: Double?,
    baseline: TextBaseline?
  )

  /// Applies the given paragraph style and returns a [Paragraph] containing the
  /// added text and associated styling.
  ///
  /// **Dart Source:** `text.dart:3513-3518`
  /// **Original:**
  /// ```dart
  /// Paragraph build();
  /// ```
  ///
  /// After calling this function, the paragraph builder object is invalid and
  /// cannot be used further.
  func build() -> any Paragraph
}

// MARK: - ParagraphBuilder Protocol Extension (Default Implementations)

/// Default implementations for ParagraphBuilder protocol methods with optional parameters.
///
/// **Dart Source:** `text.dart:3504-3511`
///
/// DIFFERENCE FROM DART: Uses protocol extension for default parameter values.
/// REASON: Swift protocols cannot have default parameter values directly;
/// protocol extensions provide equivalent functionality.
extension ParagraphBuilder {
  /// Adds an inline placeholder space to the paragraph with default scale of 1.0.
  ///
  /// **Dart Source:** `text.dart:3504-3511`
  /// **Original:**
  /// ```dart
  /// void addPlaceholder(
  ///   double width,
  ///   double height,
  ///   PlaceholderAlignment alignment, {
  ///   double scale = 1.0,
  ///   double? baselineOffset,
  ///   TextBaseline? baseline,
  /// });
  /// ```
  ///
  /// This convenience method provides Dart-like default parameter behavior.
  public func addPlaceholder(
    _ width: Double,
    _ height: Double,
    _ alignment: PlaceholderAlignment,
    scale: Double = 1.0,
    baselineOffset: Double? = nil,
    baseline: TextBaseline? = nil
  ) {
    addPlaceholder(width, height, alignment, scale: scale, baselineOffset: baselineOffset, baseline: baseline)
  }
}

// MARK: - NativeParagraphBuilder

/// The native implementation of `ParagraphBuilder` that wraps `ParagraphBuilderBridge`.
///
/// **Dart Source:** `text.dart:3521-3749`
/// **Original Name:** `_NativeParagraphBuilder`
///
/// This class implements the `ParagraphBuilder` protocol by wrapping the C++
/// `ParagraphBuilderBridge`. It handles encoding of styles and passing structured
/// data to the C++ bridge layer.
///
/// DIFFERENCE FROM DART: Uses ParagraphBuilderBridge with SWIFT_SHARED_REFERENCE
/// instead of NativeFieldWrapperClass1 / Dart VM wrapper.
/// REASON: Swift layer calls C++ directly; no Dart VM involvement.
///
/// DIFFERENCE FROM DART: No `_encodeTextStyle()` or `_encodeParagraphStyle()` calls.
/// REASON: Encoding logic is moved to C++ bridge layer. Swift passes structured
/// data to C++, which handles encoding internally.
public class NativeParagraphBuilder: ParagraphBuilder {
  /// The C++ bridge object that wraps txt::ParagraphBuilder.
  ///
  /// **Dart Source:** `text.dart:3521`
  /// **Original:** `_NativeParagraphBuilder extends NativeFieldWrapperClass1`
  ///
  /// DIFFERENCE FROM DART: Uses ParagraphBuilderBridge with SWIFT_SHARED_REFERENCE
  /// instead of NativeFieldWrapperClass1.
  private let bridge: flutter.swift_bridge.ParagraphBuilderBridge

  /// The number of placeholders currently in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3568-3569`
  /// **Original:** `int _placeholderCount = 0;`
  private var _placeholderCount: Int = 0

  /// The scales of the placeholders in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3572-3573`
  /// **Original:** `final List<double> _placeholderScales = <double>[];`
  private var _placeholderScales: [Double] = []

  /// The default leading distribution from the ParagraphStyle.
  ///
  /// **Dart Source:** `text.dart:3575`
  /// **Original:** `final TextLeadingDistribution _defaultLeadingDistribution;`
  ///
  /// This is used when a TextStyle doesn't specify its own leadingDistribution.
  private let _defaultLeadingDistribution: TextLeadingDistribution

  /// Creates a new NativeParagraphBuilder with the given ParagraphStyle.
  ///
  /// **Dart Source:** `text.dart:3522-3551`
  /// **Original:**
  /// ```dart
  /// _NativeParagraphBuilder(ParagraphStyle style)
  ///     : _defaultLeadingDistribution = style._leadingDistribution {
  ///   // ... encodes style and calls _constructor
  /// }
  /// ```
  ///
  /// DIFFERENCE FROM DART: Instead of calling `_encodeParagraphStyle()` and
  /// building Int32List/ByteData arrays, this extracts fields and passes them
  /// to the C++ bridge constructor which handles encoding.
  public init(_ style: ParagraphStyle) {
    // Store the default leading distribution for TextStyles that don't specify one
    self._defaultLeadingDistribution = style._leadingDistribution

    // Create the bridge using the helper method
    self.bridge = NativeParagraphBuilder.createBridge(for: style)
  }

  /// Creates the C++ ParagraphBuilderBridge for the given style.
  ///
  /// This is a separate static method to work around Swift's requirement that
  /// `self.bridge` must be assigned before exiting the initializer, which
  /// conflicts with closure-based memory management patterns.
  private static func createBridge(for style: ParagraphStyle)
    -> flutter.swift_bridge.ParagraphBuilderBridge
  {
    // Build the encoded style array matching _encodeParagraphStyle format:
    // [0]: Bitmask indicating which fields are set
    // [1]: textAlign index (if mask & (1<<1))
    // [2]: textDirection index (if mask & (1<<2))
    // [3]: fontWeight index (if mask & (1<<3))
    // [4]: fontStyle index (if mask & (1<<4))
    // [5]: maxLines (if mask & (1<<5))
    // [6]: textHeightBehavior encoded (if mask & (1<<6))
    var encodedStyle: [Int32] = [Int32](repeating: 0, count: 7)
    var mask: Int32 = 0

    if let textAlign = style.textAlign {
      mask |= (1 << 1)
      encodedStyle[1] = Int32(textAlign.rawValue)
    }

    if let textDirection = style.textDirection {
      mask |= (1 << 2)
      encodedStyle[2] = Int32(textDirection.rawValue)
    }

    if let fontWeight = style.fontWeight {
      mask |= (1 << 3)
      encodedStyle[3] = Int32(fontWeight.index)
    }

    if let fontStyle = style.fontStyle {
      mask |= (1 << 4)
      encodedStyle[4] = Int32(fontStyle.rawValue)
    }

    if let maxLines = style.maxLines {
      mask |= (1 << 5)
      encodedStyle[5] = Int32(maxLines)
    }

    if let textHeightBehavior = style.textHeightBehavior {
      mask |= (1 << 6)
      encodedStyle[6] = Int32(textHeightBehavior.encode())
    }

    encodedStyle[0] = mask

    // Handle StrutStyle encoding if present and enabled
    var strutData: Data = Data()
    var strutFontFamilies: [String] = []

    if let strutStyle = style.strutStyle, strutStyle.enabled {
      // Build strut font families array: [fontFamily, ...fontFamilyFallback]
      if let fontFamily = strutStyle.fontFamily {
        strutFontFamilies.append(fontFamily)
      }
      if let fallback = strutStyle.fontFamilyFallback {
        strutFontFamilies.append(contentsOf: fallback)
      }

      // Encode strut style to ByteData
      // The leading distribution from strut style or paragraph style
      let leadingDistribution =
        strutStyle.leadingDistribution ?? style._leadingDistribution

      // Build encoded strut data
      strutData = strutStyle.encode()

      // Update bitmask with leading distribution (bit 3)
      // TextLeadingDistribution has exactly 2 values (proportional=0, even=1)
      if !strutData.isEmpty {
        var bitmask = strutData[0]
        bitmask |= UInt8(leadingDistribution.rawValue << 3)
        strutData[0] = bitmask
      }
    }

    // Create the C++ bridge with extracted parameters
    let fontFamily = style.fontFamily ?? ""
    let fontSize = style.fontSize ?? 0.0
    let height = style.height ?? 0.0
    let ellipsis = style.ellipsis ?? ""
    let locale = encodeLocale(style.locale)

    // Create the bridge
    return strutFontFamilies.withCStringArray { strutFamilyPtrs in
      strutData.withUnsafeBytes { strutBytes in
        encodedStyle.withUnsafeBufferPointer { encodedPtr in
          flutter.swift_bridge.ParagraphBuilderBridge(
            encodedPtr.baseAddress,
            encodedPtr.count,
            fontFamily,
            fontSize,
            height,
            ellipsis,
            locale,
            strutData.isEmpty ? nil : strutBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
            strutData.count,
            strutFamilyPtrs,
            strutFontFamilies.count
          )
        }
      }
    }
  }

  // MARK: - Properties

  /// The number of placeholders currently in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3567-3569`
  /// **Original:**
  /// ```dart
  /// @override
  /// int get placeholderCount => _placeholderCount;
  /// ```
  public var placeholderCount: Int {
    _placeholderCount
  }

  /// The scales of the placeholders in the paragraph.
  ///
  /// **Dart Source:** `text.dart:3571-3573`
  /// **Original:**
  /// ```dart
  /// @override
  /// List<double> get placeholderScales => _placeholderScales;
  /// ```
  public var placeholderScales: [Double] {
    _placeholderScales
  }

  // MARK: - Methods

  /// Applies the given style to the added text until [pop] is called.
  ///
  /// **Dart Source:** `text.dart:3577-3638`
  /// **Original:**
  /// ```dart
  /// @override
  /// void pushStyle(TextStyle style) {
  ///   // ... encodes style and calls _pushStyle
  /// }
  /// ```
  ///
  /// DIFFERENCE FROM DART: Instead of calling `_encodeTextStyle()` and
  /// building Int32List/ByteData arrays, this extracts fields and passes them
  /// to the C++ bridge which handles encoding.
  public func pushStyle(_ style: TextStyle) {
    // Build font families array: [fontFamily, ...fontFamilyFallback]
    var fontFamilies: [String] = []
    if let fontFamily = style.fontFamily {
      fontFamilies.append(fontFamily)
    }
    if let fallback = style.fontFamilyFallback {
      fontFamilies.append(contentsOf: fallback)
    }

    // Build encoded style array matching _encodeTextStyle format:
    // [0]: Bitmask + leadingDistribution in bit 0
    // [1]: color value (if mask & (1<<1))
    // [2]: decoration mask (if mask & (1<<2))
    // [3]: decorationColor value (if mask & (1<<3))
    // [4]: decorationStyle index (if mask & (1<<4))
    // [5]: fontWeight index (if mask & (1<<5))
    // [6]: fontStyle index (if mask & (1<<6))
    // [7]: textBaseline index (if mask & (1<<7))
    // [8]: (unused)
    var encodedStyle: [Int32] = [Int32](repeating: 0, count: 9)
    var mask: Int32 = 0

    // Use the leading distribution from style, or default from paragraph style
    let finalLeadingDistribution = style.leadingDistribution ?? _defaultLeadingDistribution
    // TextLeadingDistribution has exactly 2 values (proportional=0, even=1)
    // Leading distribution goes in bit 0 of mask
    encodedStyle[0] = Int32(finalLeadingDistribution.rawValue)

    if let color = style.color {
      mask |= (1 << 1)
      encodedStyle[1] = Int32(bitPattern: UInt32(truncatingIfNeeded: color.toARGB32()))
    }

    if let decoration = style.decoration {
      mask |= (1 << 2)
      encodedStyle[2] = Int32(decoration.mask)
    }

    if let decorationColor = style.decorationColor {
      mask |= (1 << 3)
      encodedStyle[3] = Int32(bitPattern: UInt32(truncatingIfNeeded: decorationColor.toARGB32()))
    }

    if let decorationStyle = style.decorationStyle {
      mask |= (1 << 4)
      encodedStyle[4] = Int32(decorationStyle.rawValue)
    }

    if let fontWeight = style.fontWeight {
      mask |= (1 << 5)
      encodedStyle[5] = Int32(fontWeight.index)
    }

    if let fontStyle = style.fontStyle {
      mask |= (1 << 6)
      encodedStyle[6] = Int32(fontStyle.rawValue)
    }

    if let textBaseline = style.textBaseline {
      mask |= (1 << 7)
      encodedStyle[7] = Int32(textBaseline.rawValue)
    }

    // Set mask bits for float/string properties (bits 8-19)
    if style.decorationThickness != nil {
      mask |= (1 << 8)   // kTSTextDecorationThicknessIndex
    }
    if !fontFamilies.isEmpty {
      mask |= (1 << 9)   // kTSFontFamilyIndex
    }
    if style.fontSize != nil {
      mask |= (1 << 10)  // kTSFontSizeIndex
    }
    if style.letterSpacing != nil {
      mask |= (1 << 11)  // kTSLetterSpacingIndex
    }
    if style.wordSpacing != nil {
      mask |= (1 << 12)  // kTSWordSpacingIndex
    }
    if style.height != nil {
      mask |= (1 << 13)  // kTSHeightIndex
    }
    if style.locale != nil {
      mask |= (1 << 14)  // kTSLocaleIndex
    }
    if style.background != nil {
      mask |= (1 << 15)  // kTSBackgroundIndex
    }
    if style.foreground != nil {
      mask |= (1 << 16)  // kTSForegroundIndex
    }

    // Encode shadows if present
    var shadowsData: Data = Data()
    if let shadows = style.shadows, !shadows.isEmpty {
      mask |= (1 << 17)  // kTSTextShadowsIndex
      shadowsData = NativeParagraphBuilder.encodeShadows(shadows)
    }

    // Encode font features if present
    var fontFeaturesData: Data = Data()
    if let fontFeatures = style.fontFeatures, !fontFeatures.isEmpty {
      mask |= (1 << 18)  // kTSFontFeaturesIndex
      fontFeaturesData.reserveCapacity(fontFeatures.count * FontFeature.encodedSize)
      for feature in fontFeatures {
        feature.encode(into: &fontFeaturesData)
      }
    }

    // Encode font variations if present
    var fontVariationsData: Data = Data()
    if let fontVariations = style.fontVariations, !fontVariations.isEmpty {
      mask |= (1 << 19)  // kTSFontVariationsIndex
      fontVariationsData.reserveCapacity(fontVariations.count * FontVariation.encodedSize)
      for variation in fontVariations {
        variation.encode(into: &fontVariationsData)
      }
    }

    // Update the mask in encodedStyle after all bits are set
    encodedStyle[0] = Int32(finalLeadingDistribution.rawValue) | mask

    // Handle background and foreground paint
    // Note: For now we only handle color-based backgrounds/foregrounds
    // Full Paint support would require more complex bridge handling
    let hasBackground = style.background != nil
    let hasForeground = style.foreground != nil
    let backgroundColor: UInt32 =
      style.background != nil ? UInt32(truncatingIfNeeded: style.background!.color.toARGB32()) : 0
    let foregroundColor: UInt32
    if let fg = style.foreground {
      foregroundColor = UInt32(truncatingIfNeeded: fg.color.toARGB32())
    } else if let c = style.color {
      foregroundColor = UInt32(truncatingIfNeeded: c.toARGB32())
    } else {
      foregroundColor = 0
    }

    let fontSize = style.fontSize ?? 0.0
    let letterSpacing = style.letterSpacing ?? 0.0
    let wordSpacing = style.wordSpacing ?? 0.0
    let height = style.height ?? 0.0
    let decorationThickness = style.decorationThickness ?? 0.0
    let locale = NativeParagraphBuilder.encodeLocale(style.locale)

    // Call C++ bridge with encoded parameters
    fontFamilies.withCStringArray { familyPtrs in
      encodedStyle.withUnsafeBufferPointer { encodedPtr in
        shadowsData.withUnsafeBytes { shadowsBytes in
          fontFeaturesData.withUnsafeBytes { featuresBytes in
            fontVariationsData.withUnsafeBytes { variationsBytes in
              bridge.PushStyle(
                encodedPtr.baseAddress,
                encodedPtr.count,
                familyPtrs,
                fontFamilies.count,
                fontSize,
                letterSpacing,
                wordSpacing,
                height,
                decorationThickness,
                locale,
                shadowsData.isEmpty ? nil : shadowsBytes.baseAddress?.assumingMemoryBound(
                  to: UInt8.self),
                shadowsData.count,
                fontFeaturesData.isEmpty
                  ? nil : featuresBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                fontFeaturesData.count,
                fontVariationsData.isEmpty
                  ? nil : variationsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                fontVariationsData.count,
                hasBackground,
                hasForeground,
                backgroundColor,
                foregroundColor
              )
            }
          }
        }
      }
    }
  }

  /// Ends the effect of the most recent call to [pushStyle].
  ///
  /// **Dart Source:** `text.dart:3681-3683`
  /// **Original:**
  /// ```dart
  /// @override
  /// @Native<Void Function(Pointer<Void>)>(symbol: 'ParagraphBuilder::pop', isLeaf: true)
  /// external void pop();
  /// ```
  public func pop() {
    bridge.Pop()
  }

  /// Adds the given text to the paragraph.
  ///
  /// **Dart Source:** `text.dart:3685-3691`
  /// **Original:**
  /// ```dart
  /// @override
  /// void addText(String text) {
  ///   final String? error = _addText(text);
  ///   if (error != null) {
  ///     throw ArgumentError(error);
  ///   }
  /// }
  /// ```
  ///
  /// DIFFERENCE FROM DART: Uses AddTextSafe which returns a bool instead of
  /// an error string pointer.
  /// REASON: Swift C++ interop cannot handle methods that return interior pointers.
  public func addText(_ text: String) {
    // Note: We use AddTextSafe which returns true on success, false on error
    // The original Dart threw ArgumentError on malformed text
    let success = bridge.AddTextSafe(text)
    if !success {
      preconditionFailure("Invalid text provided to addText")
    }
  }

  /// Adds an inline placeholder space to the paragraph.
  ///
  /// **Dart Source:** `text.dart:3696-3724`
  /// **Original:**
  /// ```dart
  /// @override
  /// void addPlaceholder(
  ///   double width,
  ///   double height,
  ///   PlaceholderAlignment alignment, {
  ///   double scale = 1.0,
  ///   double? baselineOffset,
  ///   TextBaseline? baseline,
  /// }) {
  ///   assert(!(alignment == PlaceholderAlignment.aboveBaseline ||
  ///            alignment == PlaceholderAlignment.belowBaseline ||
  ///            alignment == PlaceholderAlignment.baseline) || baseline != null);
  ///   baselineOffset = baselineOffset ?? height;
  ///   _addPlaceholder(width * scale, height * scale, alignment.index,
  ///                   baselineOffset * scale, (baseline ?? TextBaseline.alphabetic).index);
  ///   _placeholderCount++;
  ///   _placeholderScales.add(scale);
  /// }
  /// ```
  public func addPlaceholder(
    _ width: Double,
    _ height: Double,
    _ alignment: PlaceholderAlignment,
    scale: Double,
    baselineOffset: Double?,
    baseline: TextBaseline?
  ) {
    // Require a baseline to be specified if using a baseline-based alignment
    assert(
      !(alignment == .aboveBaseline || alignment == .belowBaseline || alignment == .baseline)
        || baseline != nil,
      "Baseline-based alignment requires a baseline to be specified"
    )

    // Default the baselineOffset to height if nil
    let effectiveBaselineOffset = baselineOffset ?? height

    bridge.AddPlaceholder(
      width * scale,
      height * scale,
      Int32(alignment.rawValue),
      effectiveBaselineOffset * scale,
      Int32((baseline ?? .alphabetic).rawValue)
    )

    _placeholderCount += 1
    _placeholderScales.append(scale)
  }

  /// Applies the given paragraph style and returns a [Paragraph] containing the
  /// added text and associated styling.
  ///
  /// **Dart Source:** `text.dart:3737-3742`
  /// **Original:**
  /// ```dart
  /// @override
  /// Paragraph build() {
  ///   final _NativeParagraph paragraph = _NativeParagraph._();
  ///   _build(paragraph);
  ///   return paragraph;
  /// }
  /// ```
  ///
  /// After calling this function, the paragraph builder object is invalid and
  /// cannot be used further.
  public func build() -> any Paragraph {
    guard let paragraphBridge = bridge.Build() else {
      preconditionFailure("Failed to build paragraph")
    }
    return NativeParagraph(paragraphBridge)
  }

  /// Returns a string representation of this builder.
  ///
  /// **Dart Source:** `text.dart:3747-3748`
  /// **Original:** `String toString() => 'ParagraphBuilder';`
  public var description: String {
    "ParagraphBuilder"
  }

  // MARK: - Private Helper Methods

  /// Encodes a Locale to its string representation.
  ///
  /// **Dart Source:** `text.dart:3679`
  /// **Original:** `static String _encodeLocale(Locale? locale) => locale?.toString() ?? '';`
  private static func encodeLocale(_ locale: Locale?) -> String {
    locale?.description ?? ""
  }

  /// Encodes shadows to binary data for the C++ bridge.
  ///
  /// **Dart Source:** `painting.dart:7667-7695` (Shadow._encodeShadows)
  /// **Original:**
  /// ```dart
  /// static ByteData _encodeShadows(List<Shadow>? shadows) {
  ///   if (shadows == null) return ByteData(0);
  ///   // ... encodes each shadow as 16 bytes
  /// }
  /// ```
  ///
  /// Each shadow is encoded as 16 bytes:
  /// - 4 bytes: color XOR'd with default color (0xFF000000)
  /// - 4 bytes: x offset (Float32)
  /// - 4 bytes: y offset (Float32)
  /// - 4 bytes: blur sigma (Float32)
  private static func encodeShadows(_ shadows: [Shadow]) -> Data {
    let bytesPerShadow = Shadow.kBytesPerShadow
    var data = Data(count: shadows.count * bytesPerShadow)

    for (index, shadow) in shadows.enumerated() {
      let offset = index * bytesPerShadow

      // Color XOR'd with default color (0xFF000000)
      let colorARGB = UInt32(truncatingIfNeeded: shadow.color.toARGB32())
      let colorValue = Int32(bitPattern: colorARGB ^ 0xFF00_0000)
      withUnsafeBytes(of: colorValue.littleEndian) { bytes in
        data.replaceSubrange(offset..<(offset + 4), with: bytes)
      }

      // X offset as Float32
      let x = Float32(shadow.offset.dx)
      withUnsafeBytes(of: x.bitPattern.littleEndian) { bytes in
        data.replaceSubrange((offset + 4)..<(offset + 8), with: bytes)
      }

      // Y offset as Float32
      let y = Float32(shadow.offset.dy)
      withUnsafeBytes(of: y.bitPattern.littleEndian) { bytes in
        data.replaceSubrange((offset + 8)..<(offset + 12), with: bytes)
      }

      // Blur sigma as Float32 (converted from blur radius)
      let blurSigma = Float32(Shadow.convertRadiusToSigma(shadow.blurRadius))
      withUnsafeBytes(of: blurSigma.bitPattern.littleEndian) { bytes in
        data.replaceSubrange((offset + 12)..<(offset + 16), with: bytes)
      }
    }

    return data
  }
}

// MARK: - Helper Extension for C String Arrays

/// Extension to convert an array of strings to C string pointers for C++ interop.
extension Array where Element == String {
  /// Calls the provided closure with an array of C string pointers.
  ///
  /// This is needed to pass string arrays to C++ bridge functions that expect
  /// `const char* const*` parameters.
  func withCStringArray<R>(_ body: (UnsafePointer<UnsafePointer<CChar>?>?) throws -> R) rethrows
    -> R
  {
    if isEmpty {
      return try body(nil)
    }

    // Create an array to hold the C strings, keeping them alive for the duration
    let cStrings: [UnsafePointer<CChar>] = map { $0.withCString { UnsafePointer(strdup($0)!) } }
    defer {
      for ptr in cStrings {
        free(UnsafeMutablePointer(mutating: ptr))
      }
    }

    var optionalPointers: [UnsafePointer<CChar>?] = cStrings.map { Optional($0) }
    return try optionalPointers.withUnsafeMutableBufferPointer { buffer in
      try body(UnsafePointer(buffer.baseAddress))
    }
  }
}

// MARK: - ParagraphBuilders Factory

/// Factory namespace for creating ParagraphBuilder instances.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original:** `factory ParagraphBuilder(ParagraphStyle style) = _NativeParagraphBuilder;`
/// **Lines:** 3429-3431
///
/// In Dart, `ParagraphBuilder` has a factory constructor that returns a
/// `_NativeParagraphBuilder`. In Swift, protocols cannot have factory
/// initializers, so this enum serves as the factory namespace.
///
/// DIFFERENCE FROM DART: Uses an enum factory namespace instead of factory constructor.
/// REASON: Swift protocols cannot have factory constructors. This pattern provides
/// equivalent ergonomics while maintaining type safety.
public enum ParagraphBuilders {
  /// Creates a new `ParagraphBuilder`.
  ///
  /// **Dart Source:** `text.dart:3429-3431`
  /// **Original:** `factory ParagraphBuilder(ParagraphStyle style) = _NativeParagraphBuilder;`
  ///
  /// Equivalent to Dart's `ParagraphBuilder(style)` factory constructor.
  ///
  /// ## Usage
  ///
  /// ```swift
  /// // Dart: let builder = ParagraphBuilder(style);
  /// // Swift: let builder = ParagraphBuilders.create(style)
  /// let style = ParagraphStyle(textAlign: .center)
  /// let builder = ParagraphBuilders.create(style)
  /// builder.addText("Hello, world!")
  /// let paragraph = builder.build()
  /// ```
  public static func create(_ style: ParagraphStyle) -> any ParagraphBuilder {
    return NativeParagraphBuilder(style)
  }
}

// MARK: - Font Loading Support

/// The system channel name for platform messages.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `kSystemChannelName` (local constant in _sendFontChangeMessage)
/// **Lines:** 3769
private let kSystemChannelName = "flutter/system"

/// The message data sent to notify the framework that fonts have changed.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `_fontChangeMessage`
/// **Lines:** 3763-3766
///
/// This is a JSON-encoded message: `{"type": "fontsChange"}`
///
/// **Original:**
/// ```dart
/// final ByteData _fontChangeMessage = utf8
///     .encode(json.encode(<String, Object?>{'type': 'fontsChange'}))
///     .buffer
///     .asByteData();
/// ```
///
/// DIFFERENCE FROM DART: the JSON is written out, not encoded.
/// REASON: it is a constant, and JSONEncoder is 3 MB of the web build
/// (it brings date formatting, which brings Calendar and the regex engine).
internal let fontChangeMessage = Data(#"{"type":"fontsChange"}"#.utf8)

/// Sends a platform message to notify the framework that fonts have changed.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `_sendFontChangeMessage`
/// **Lines:** 3768-3781
///
/// This function is called after a font is successfully loaded to notify
/// the Flutter framework that the font collection has changed.
///
/// **Original:**
/// ```dart
/// FutureOr<void> _sendFontChangeMessage() async {
///   const String kSystemChannelName = 'flutter/system';
///   if (PlatformDispatcher.instance.onPlatformMessage != null) {
///     _invoke3<String, ByteData?, PlatformMessageResponseCallback>(
///       PlatformDispatcher.instance.onPlatformMessage,
///       PlatformDispatcher.instance._onPlatformMessageZone,
///       kSystemChannelName,
///       _fontChangeMessage,
///       (ByteData? responseData) {},
///     );
///   } else {
///     channelBuffers.push(kSystemChannelName, _fontChangeMessage, (ByteData? responseData) {});
///   }
/// }
/// ```
///
/// DIFFERENCE FROM DART: Simplified to not use zones (Dart-specific concurrency concept).
/// REASON: Swift doesn't have Dart's Zone mechanism. The callback is invoked directly.
///
/// DIFFERENCE FROM DART: Uses @MainActor for thread safety.
/// REASON: Swift 6 strict concurrency requires explicit actor isolation.
@MainActor
internal func sendFontChangeMessage() {
  if let onPlatformMessage = PlatformDispatcher.instance.onPlatformMessage {
    // Call the platform message handler directly
    // The _invoke3 pattern in Dart handles zone management which isn't needed in Swift
    onPlatformMessage(kSystemChannelName, fontChangeMessage, { _ in })
  } else {
    // Push to channel buffers if no handler is registered yet
    channelBuffers.push(kSystemChannelName, fontChangeMessage, { _ in })
  }
}

// MARK: - Font Loading

/// Error type for font loading operations.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Lines:** 3756-3761
///
/// DIFFERENCE FROM DART: Uses a dedicated error enum instead of generic Exception.
/// REASON: Swift encourages typed errors over string-based exceptions.
public enum FontLoadingError: Error, CustomStringConvertible {
  case loadFailed(String)

  public var description: String {
    switch self {
    case .loadFailed(let message):
      return "Font loading failed: \(message)"
    }
  }
}

/// Loads a font from a buffer and makes it available for rendering text.
///
/// **Dart Source:** `engine/src/flutter/lib/ui/text.dart`
/// **Original Name:** `loadFontFromList`
/// **Lines:** 3751-3761
///
/// - Parameters:
///   - list: A byte array containing the font file data.
///   - fontFamily: The family name used to identify the font in text styles.
///     If this is not provided (nil), then the family name will be extracted
///     from the font file.
///
/// **Original:**
/// ```dart
/// Future<void> loadFontFromList(Uint8List list, {String? fontFamily}) {
///   return _futurize((_Callback<void> callback) {
///     _loadFontFromList(list, callback, fontFamily ?? '');
///     return null;
///   }).then((_) => _sendFontChangeMessage());
/// }
/// ```
///
/// DIFFERENCE FROM DART: Uses Swift async/await instead of Dart Future.
/// REASON: Swift's native concurrency model is more idiomatic.
///
/// DIFFERENCE FROM DART: Uses a global font collection instead of per-engine.
/// REASON: No Dart VM state to track engine instances. The Swift bridge
/// maintains its own font manager that is used by ParagraphBuilder.
///
/// DIFFERENCE FROM DART: Synchronous font loading wrapped in async.
/// REASON: The actual font loading (creating SkTypeface from data) is
/// synchronous. The Dart version used async due to the futurize pattern,
/// but the underlying operation doesn't require async behavior.
@MainActor
public func loadFontFromList(_ list: Data, fontFamily: String? = nil) async throws {
  // Call the synchronous C++ bridge function
  let success = list.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
    guard let baseAddress = buffer.baseAddress else {
      return false
    }
    let dataPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
    return flutter.swift_bridge.LoadFontFromList(dataPtr, list.count, fontFamily)
  }

  if !success {
    throw FontLoadingError.loadFailed(
      "Failed to load font" + (fontFamily.map { " '\($0)'" } ?? "")
    )
  }

  // Notify the framework that fonts have changed
  sendFontChangeMessage()
}
