// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// An immutable placeholder that is embedded inline within text.
///
/// **Dart Source:** `packages/flutter/lib/src/painting/placeholder_span.dart`

import FlutterSwiftBridge

// MARK: - PlaceholderSpan

/// An immutable placeholder that is embedded inline within text.
///
/// `PlaceholderSpan` represents a placeholder that acts as a stand-in for other
/// content. A `PlaceholderSpan` by itself does not contain useful information
/// to change a `TextSpan`. `WidgetSpan` from the widgets library extends
/// `PlaceholderSpan` and may be used instead to specify a widget as the contents
/// of the placeholder.
///
/// See also:
///
///  * `WidgetSpan`, a leaf node that represents an embedded inline widget.
///  * `TextSpan`, a node that represents text in a `TextSpan` tree.
///
/// **Dart Source:** `placeholder_span.dart:39-97`
open class PlaceholderSpan: InlineSpan {

    /// The unicode character to represent a placeholder.
    ///
    /// **Dart Source:** `placeholder_span.dart:51`
    public static let placeholderCodeUnit: Int = 0xFFFC

    /// How the placeholder aligns vertically with the text.
    ///
    /// See `PlaceholderAlignment` for details on each mode.
    ///
    /// **Dart Source:** `placeholder_span.dart:53-56`
    public let alignment: PlaceholderAlignment

    /// The `TextBaseline` to align against when using `PlaceholderAlignment.baseline`,
    /// `PlaceholderAlignment.aboveBaseline`, and `PlaceholderAlignment.belowBaseline`.
    ///
    /// This is ignored when using other alignment modes.
    ///
    /// **Dart Source:** `placeholder_span.dart:58-62`
    public let baseline: TextBaseline?

    /// Creates a `PlaceholderSpan` with the given values.
    ///
    /// A `TextStyle` may be provided with the `style` property, but only the
    /// decoration, foreground, background, and spacing options will be used.
    ///
    /// **Dart Source:** `placeholder_span.dart:40-48`
    public init(
        alignment: PlaceholderAlignment = .bottom,
        baseline: TextBaseline? = nil,
        style: TextStyle? = nil
    ) {
        self.alignment = alignment
        self.baseline = baseline
        super.init(style: style)
    }

    // MARK: - Override Methods

    /// A placeholder is a leaf: the walk visits it and goes on. (Without this the base class traps with "Subclasses must
    /// override visitChildren", so a `TextSpan` tree holding any placeholder could not be walked.)
    ///
    /// **Dart Source:** `widget_span.dart` (`visitChildren`)
    open override func visitChildren(_ visitor: InlineSpanVisitor) -> Bool { visitor(self) }

    /// A placeholder has no children.
    open override func visitDirectChildren(_ visitor: InlineSpanVisitor) -> Bool { true }

    /// `PlaceholderSpan`s are flattened to a `0xFFFC` object replacement character in the
    /// plain text representation when `includePlaceholders` is true.
    ///
    /// **Dart Source:** `placeholder_span.dart:66-75`
    open override func computeToPlainText(
        _ buffer: inout String,
        includeSemanticsLabels: Bool = true,
        includePlaceholders: Bool = true
    ) {
        if includePlaceholders {
            buffer.append(Character(UnicodeScalar(Self.placeholderCodeUnit)!))
        }
    }

    /// **Dart Source:** `placeholder_span.dart:77-80`
    open override func computeSemanticsInformation(
        _ collector: inout [InlineSpanSemanticsInformation]
    ) {
        collector.append(InlineSpanSemanticsInformation.placeholder)
    }

    /// **Dart Source:** `placeholder_span.dart:82-90`
    public override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        super.debugFillProperties(properties)

        properties.add(
            EnumProperty<PlaceholderAlignment>("alignment", alignment, defaultValue: nil)
        )
        properties.add(
            EnumProperty<TextBaseline>("baseline", baseline, defaultValue: nil)
        )
    }

    /// **Dart Source:** `placeholder_span.dart:92-96`
    open override func debugAssertIsValid() -> Bool {
        assert(false, "Consider implementing the WidgetSpan interface instead.")
        return super.debugAssertIsValid()
    }
}
