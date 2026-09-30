// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Attributed string types and label builder for semantics.
///
/// **Dart Source:** `packages/flutter/lib/src/semantics/semantics.dart`

import FlutterSwiftBridge

// MARK: - Unicode Constants

/// Constants for useful Unicode characters related to bidirectional text.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/unicode.dart`
/// **Original Name:** `Unicode`
/// **Lines:** 13-97
///
/// DIFFERENCE FROM DART: Using an enum namespace instead of `abstract final class`.
/// REASON: Swift uses caseless enums as namespaces for grouping static constants,
/// which is the idiomatic equivalent of Dart's `abstract final class`.
public enum UnicodeConstants {
  /// `U+202A LEFT-TO-RIGHT EMBEDDING`
  ///
  /// Treat the following text as embedded left-to-right.
  ///
  /// Use `PDF` to end the embedding.
  ///
  /// **Dart Source:** `unicode.dart:19`
  public static let LRE: String = "\u{202A}"

  /// `U+202B RIGHT-TO-LEFT EMBEDDING`
  ///
  /// Treat the following text as embedded right-to-left.
  ///
  /// Use `PDF` to end the embedding.
  ///
  /// **Dart Source:** `unicode.dart:26`
  public static let RLE: String = "\u{202B}"

  /// `U+202C POP DIRECTIONAL FORMATTING`
  ///
  /// End the scope of the last `LRE`, `RLE`, `RLO`, or `LRO`.
  ///
  /// **Dart Source:** `unicode.dart:31`
  public static let PDF: String = "\u{202C}"

  /// `U+202D LEFT-TO-RIGHT OVERRIDE`
  ///
  /// Force following characters to be treated as strong left-to-right characters.
  ///
  /// Use `PDF` to end the override.
  ///
  /// **Dart Source:** `unicode.dart:40`
  public static let LRO: String = "\u{202D}"

  /// `U+202E RIGHT-TO-LEFT OVERRIDE`
  ///
  /// Force following characters to be treated as strong right-to-left characters.
  ///
  /// Use `PDF` to end the override.
  ///
  /// **Dart Source:** `unicode.dart:49`
  public static let RLO: String = "\u{202E}"

  /// `U+2066 LEFT-TO-RIGHT ISOLATE`
  ///
  /// Treat the following text as isolated and left-to-right.
  ///
  /// Use `PDI` to end the isolated scope.
  ///
  /// **Dart Source:** `unicode.dart:56`
  public static let LRI: String = "\u{2066}"

  /// `U+2067 RIGHT-TO-LEFT ISOLATE`
  ///
  /// Treat the following text as isolated and right-to-left.
  ///
  /// Use `PDI` to end the isolated scope.
  ///
  /// **Dart Source:** `unicode.dart:63`
  public static let RLI: String = "\u{2067}"

  /// `U+2068 FIRST STRONG ISOLATE`
  ///
  /// Treat the following text as isolated and in the direction of its first
  /// strong directional character that is not inside a nested isolate.
  ///
  /// Use `PDI` to end the isolated scope.
  ///
  /// **Dart Source:** `unicode.dart:76`
  public static let FSI: String = "\u{2068}"

  /// `U+2069 POP DIRECTIONAL ISOLATE`
  ///
  /// End the scope of the last `LRI`, `RLI`, or `FSI`.
  ///
  /// **Dart Source:** `unicode.dart:81`
  public static let PDI: String = "\u{2069}"

  /// `U+200E LEFT-TO-RIGHT MARK`
  ///
  /// Left-to-right zero-width character.
  ///
  /// **Dart Source:** `unicode.dart:86`
  public static let LRM: String = "\u{200E}"

  /// `U+200F RIGHT-TO-LEFT MARK`
  ///
  /// Right-to-left zero-width non-Arabic character.
  ///
  /// **Dart Source:** `unicode.dart:91`
  public static let RLM: String = "\u{200F}"

  /// `U+061C ARABIC LETTER MARK`
  ///
  /// Right-to-left zero-width Arabic character.
  ///
  /// **Dart Source:** `unicode.dart:96`
  public static let ALM: String = "\u{061C}"
}

// MARK: - AttributedString

/// A string that carries a list of `StringAttribute`s.
///
/// **Dart Source:** `packages/flutter/lib/src/semantics/semantics.dart`
/// **Original Name:** `AttributedString`
/// **Lines:** 722-795
///
/// DIFFERENCE FROM DART: Using a Swift struct instead of `@immutable` class.
/// REASON: `AttributedString` is an immutable value type in Dart; Swift structs
/// with value semantics are the idiomatic equivalent.
public struct AttributedString: CustomStringConvertible {
  /// Creates an attributed string.
  ///
  /// The `TextRange` in the `attributes` must be inside the length of the
  /// `string`.
  ///
  /// The `attributes` must not be changed after the attributed string is
  /// created.
  ///
  /// **Dart Source:** `semantics.dart:730-740`
  /// **Original:** `AttributedString(this.string, {this.attributes = const <StringAttribute>[]})`
  public init(_ string: String, attributes: [any StringAttribute] = []) {
    assert(
      !string.isEmpty || attributes.isEmpty,
      "An empty string cannot have attributes"
    )
    assert({
      for attribute in attributes {
        assert(
          string.count >= attribute.range.start && string.count >= attribute.range.end,
          "The range in \(attribute) is outside of the string \(string)"
        )
      }
      return true
    }())
    self.string = string
    self.attributes = attributes
  }

  /// The plain string stored in the attributed string.
  ///
  /// **Dart Source:** `semantics.dart:743`
  public let string: String

  /// The attributes this string carries.
  ///
  /// The list must not be modified after this string is created.
  ///
  /// **Dart Source:** `semantics.dart:748`
  public let attributes: [any StringAttribute]

  /// Returns a new `AttributedString` by concatenating the operands.
  ///
  /// The string attribute list of the returned `AttributedString` will contain
  /// the string attributes from both operands with updated text ranges.
  ///
  /// **Dart Source:** `semantics.dart:754-777`
  /// **Original:** `AttributedString operator +(AttributedString other)`
  public static func + (lhs: AttributedString, rhs: AttributedString) -> AttributedString {
    if lhs.string.isEmpty {
      return rhs
    }
    if rhs.string.isEmpty {
      return lhs
    }

    // None of the strings is empty.
    let newString = lhs.string + rhs.string
    var newAttributes: [any StringAttribute] = Array(lhs.attributes)
    if !rhs.attributes.isEmpty {
      let offset = lhs.string.count
      for attribute in rhs.attributes {
        let newRange = TextRange(
          start: attribute.range.start + offset,
          end: attribute.range.end + offset
        )
        let adjustedAttribute = attribute.copy(range: newRange)
        newAttributes.append(adjustedAttribute)
      }
    }
    return AttributedString(newString, attributes: newAttributes)
  }

  // MARK: - Equatable

  /// Two `AttributedString`s are equal if their string and attributes are.
  ///
  /// **Dart Source:** `semantics.dart:781-786`
  ///
  /// DIFFERENCE FROM DART: Cannot conform to `Equatable` because `StringAttribute`
  /// is a protocol type (`any StringAttribute`) which is not `Equatable`.
  /// Instead, we compare attributes by count and their range properties.
  /// REASON: Swift protocols with associated types or class-only constraints
  /// cannot easily conform to `Equatable`. We use a pragmatic comparison.
  public static func == (lhs: AttributedString, rhs: AttributedString) -> Bool {
    guard lhs.string == rhs.string else { return false }
    guard lhs.attributes.count == rhs.attributes.count else { return false }
    for i in 0..<lhs.attributes.count {
      let lhsAttr = lhs.attributes[i]
      let rhsAttr = rhs.attributes[i]
      // Compare by range and type
      if lhsAttr.range != rhsAttr.range {
        return false
      }
      // Compare by concrete type identity
      if type(of: lhsAttr) != type(of: rhsAttr) {
        return false
      }
      // For LocaleStringAttribute, also compare locale
      if let lhsLocale = lhsAttr as? LocaleStringAttribute,
         let rhsLocale = rhsAttr as? LocaleStringAttribute {
        if lhsLocale.locale != rhsLocale.locale {
          return false
        }
      }
    }
    return true
  }

  public static func != (lhs: AttributedString, rhs: AttributedString) -> Bool {
    return !(lhs == rhs)
  }

  // MARK: - Hashable

  /// **Dart Source:** `semantics.dart:788-789`
  /// **Original:** `int get hashCode => Object.hash(string, attributes);`
  ///
  /// DIFFERENCE FROM DART: Cannot conform to `Hashable` protocol because
  /// `[any StringAttribute]` is not `Hashable`. Provides a `hashValue` computed
  /// property instead.
  /// REASON: Swift's `Hashable` requires all stored properties to also be `Hashable`.
  /// Protocol existential types (`any StringAttribute`) cannot conform to `Hashable`.
  public var hashValue: Int {
    var hasher = Hasher()
    hasher.combine(string)
    hasher.combine(attributes.count)
    for attribute in attributes {
      hasher.combine(attribute.range.start)
      hasher.combine(attribute.range.end)
    }
    return hasher.finalize()
  }

  // MARK: - CustomStringConvertible

  /// **Dart Source:** `semantics.dart:792-794`
  /// **Original:** `String toString() => "${objectRuntimeType(this, 'AttributedString')}('$string', attributes: $attributes)";`
  public var description: String {
    "AttributedString('\(string)', attributes: \(attributes))"
  }
}

// MARK: - AttributedStringProperty

/// A `DiagnosticsProperty` for `AttributedString`s, which shows a string
/// when there are no attributes, and more details otherwise.
///
/// **Dart Source:** `packages/flutter/lib/src/semantics/semantics.dart`
/// **Original Name:** `AttributedStringProperty`
/// **Lines:** 799-838
public class AttributedStringProperty: DiagnosticsProperty<AttributedString> {
  /// Create a diagnostics property for an `AttributedString` object.
  ///
  /// Such properties are used with `SemanticsData` objects.
  ///
  /// **Dart Source:** `semantics.dart:803-811`
  public init(
    _ name: String,
    _ value: AttributedString?,
    showName: Bool = true,
    showWhenEmpty: Bool = false,
    defaultValue: Any? = nil,
    level: DiagnosticLevel = .info,
    description: String? = nil
  ) {
    self._showWhenEmpty = showWhenEmpty
    super.init(
      name,
      value,
      description: description,
      showName: showName,
      defaultValue: defaultValue ?? kNoDefaultValue,
      level: level
    )
  }

  /// Whether to show the property when the `value` is an `AttributedString`
  /// whose `AttributedString.string` is the empty string.
  ///
  /// This overrides `defaultValue`.
  ///
  /// **Dart Source:** `semantics.dart:818`
  private let _showWhenEmpty: Bool

  /// **Dart Source:** `semantics.dart:820-821`
  /// **Original:** `bool get isInteresting => super.isInteresting && (showWhenEmpty || (value != null && value!.string.isNotEmpty));`
  public override var isInteresting: Bool {
    super.isInteresting && (_showWhenEmpty || (typedValue != nil && !typedValue!.string.isEmpty))
  }

  /// **Dart Source:** `semantics.dart:823-837`
  /// **Original:** `String valueToString({TextTreeConfiguration? parentConfiguration})`
  public override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
    guard let value = typedValue else {
      return "nil"
    }
    var text = value.string
    if let parentConfig = parentConfiguration, !parentConfig.lineBreakProperties {
      // This follows a similar pattern to StringProperty.
      text = text.replacingAll("\n", with: "\\n")
    }
    if value.attributes.isEmpty {
      return "\"\(text)\""
    }
    return "\"\(text)\" \(value.attributes)"
  }
}

// MARK: - SemanticsLabelBuilder

/// Builder for creating semantically correct concatenated labels with proper
/// text direction handling and spacing.
///
/// This builder helps address the complexity of concatenating multiple text
/// parts while handling language-specific nuances like RTL vs LTR text direction
/// and proper spacing.
///
/// Example usage:
/// ```swift
/// let builder = SemanticsLabelBuilder()
/// builder.addPart("Hello")
/// builder.addPart("world")
/// let label = builder.build() // "Hello world"
/// ```
///
/// For multilingual text with proper RTL support:
/// ```swift
/// let builder = SemanticsLabelBuilder(textDirection: .rtl)
/// builder.addPart("Welcome", textDirection: .ltr)
/// builder.addPart("\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}", textDirection: .rtl) // Arabic
/// let label = builder.build()
/// ```
///
/// **Dart Source:** `packages/flutter/lib/src/semantics/semantics.dart`
/// **Original Name:** `SemanticsLabelBuilder`
/// **Lines:** 864-940
///
/// DIFFERENCE FROM DART: Using a Swift `final class` with the same mutable semantics.
/// REASON: Direct equivalent of Dart's `final class`.
public final class SemanticsLabelBuilder {
  /// Creates a new `SemanticsLabelBuilder`.
  ///
  /// The `separator` is used between text parts (defaults to space).
  /// The `textDirection` specifies the overall text direction for the concatenated label.
  ///
  /// **Dart Source:** `semantics.dart:869`
  /// **Original:** `SemanticsLabelBuilder({this.separator = ' ', this.textDirection});`
  public init(separator: String = " ", textDirection: TextDirection? = nil) {
    self.separator = separator
    self.textDirection = textDirection
  }

  /// The separator used between text parts.
  ///
  /// **Dart Source:** `semantics.dart:872`
  public let separator: String

  /// The overall text direction for the concatenated label.
  ///
  /// **Dart Source:** `semantics.dart:875`
  public let textDirection: TextDirection?

  /// Internal storage for label parts.
  ///
  /// **Dart Source:** `semantics.dart:877`
  /// **Original:** `final List<_LabelPart> _parts = <_LabelPart>[];`
  private var _parts: [(text: String, textDirection: TextDirection?)] = []

  /// Adds a text part.
  ///
  /// If `textDirection` is specified, it will be used for this specific part.
  /// Empty parts are ignored.
  ///
  /// **Dart Source:** `semantics.dart:883-887`
  /// **Original:** `void addPart(String label, {TextDirection? textDirection})`
  public func addPart(_ label: String, textDirection: TextDirection? = nil) {
    if !label.isEmpty {
      _parts.append((text: label, textDirection: textDirection))
    }
  }

  /// Returns true if no parts have been added to this builder.
  ///
  /// **Dart Source:** `semantics.dart:890`
  public var isEmpty: Bool { _parts.isEmpty }

  /// Returns the number of parts added to this builder.
  ///
  /// **Dart Source:** `semantics.dart:893`
  public var length: Int { _parts.count }

  /// Builds and returns the concatenated label from the added parts.
  ///
  /// This method concatenates all parts with proper text direction handling
  /// and spacing.
  ///
  /// **Dart Source:** `semantics.dart:899-933`
  /// **Original:** `String build()`
  public func build() -> String {
    if _parts.isEmpty {
      return ""
    }

    if _parts.count == 1 {
      return _parts[0].text
    }

    // Concatenate multiple parts with proper text direction handling
    var buffer = ""
    buffer.append(_parts[0].text)

    for part in _parts.dropFirst() {
      let partDirection = part.textDirection ?? textDirection

      if !separator.isEmpty {
        buffer.append(separator)
      }

      var processedText = part.text
      if textDirection != nil && partDirection != nil && textDirection != partDirection {
        let directionalEmbedding: String
        switch partDirection! {
        case .rtl:
          directionalEmbedding = UnicodeConstants.RLE
        case .ltr:
          directionalEmbedding = UnicodeConstants.LRE
        }
        processedText = directionalEmbedding + part.text + UnicodeConstants.PDF
      }

      buffer.append(processedText)
    }

    return buffer
  }

  /// Clears all parts from this builder, allowing it to be reused.
  ///
  /// **Dart Source:** `semantics.dart:937-939`
  /// **Original:** `void clear()`
  public func clear() {
    _parts.removeAll()
  }
}
