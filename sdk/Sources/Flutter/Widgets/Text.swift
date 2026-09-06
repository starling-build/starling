// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Text widgets — Text, DefaultTextStyle, DefaultTextHeightBehavior.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/text.dart`

import FlutterSwiftBridge

// MARK: - DefaultTextStyle

/// An inherited widget that defines the default text style for descendant
/// `Text` widgets without explicit styles.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/text.dart:49`
public class DefaultTextStyle: InheritedWidget {
    public let style: TextStyle
    public let textAlign: TextAlign?
    public let softWrap: Bool
    public let overflow: TextOverflow
    public let maxLines: Int?
    public let textWidthBasis: TextWidthBasis
    public let textHeightBehavior: TextHeightBehavior?

    public init(
        key: (any Key)? = nil,
        style: TextStyle,
        textAlign: TextAlign? = nil,
        softWrap: Bool = true,
        overflow: TextOverflow = .clip,
        maxLines: Int? = nil,
        textWidthBasis: TextWidthBasis = .parent,
        textHeightBehavior: TextHeightBehavior? = nil,
        child: Widget
    ) {
        self.style = style
        self.textAlign = textAlign
        self.softWrap = softWrap
        self.overflow = overflow
        self.maxLines = maxLines
        self.textWidthBasis = textWidthBasis
        self.textHeightBehavior = textHeightBehavior
        super.init(key: key, child: child)
    }

    /// Default fallback instance (used when no DefaultTextStyle ancestor exists).
    ///
    /// **Dart Source:** `text.dart:106`
    nonisolated(unsafe) public static let fallback = DefaultTextStyle(
        style: TextStyle(),
        child: _DefaultTextStyleNullWidget()
    )

    /// Retrieves the nearest DefaultTextStyle ancestor.
    ///
    /// **Dart Source:** `text.dart:114`
    public static func of(_ context: any BuildContext) -> DefaultTextStyle {
        return context.dependOnInheritedWidgetOfExactType(DefaultTextStyle.self) ?? fallback
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        let old = oldWidget as! DefaultTextStyle
        return style != old.style
            || textAlign != old.textAlign
            || softWrap != old.softWrap
            || overflow != old.overflow
            || maxLines != old.maxLines
            || textWidthBasis != old.textWidthBasis
    }
}

// MARK: - DefaultTextHeightBehavior

/// An inherited widget that defines the default `TextHeightBehavior` for
/// descendant `Text` and `RichText` widgets.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/text.dart:160`
public class DefaultTextHeightBehavior: InheritedWidget {
    public let textHeightBehavior: TextHeightBehavior

    public init(
        key: (any Key)? = nil,
        textHeightBehavior: TextHeightBehavior,
        child: Widget
    ) {
        self.textHeightBehavior = textHeightBehavior
        super.init(key: key, child: child)
    }

    /// Returns the nearest `DefaultTextHeightBehavior` ancestor's value, or nil.
    ///
    /// **Dart Source:** `text.dart:181`
    public static func maybeOf(_ context: any BuildContext) -> TextHeightBehavior? {
        return context.dependOnInheritedWidgetOfExactType(DefaultTextHeightBehavior.self)?
            .textHeightBehavior
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        let old = oldWidget as! DefaultTextHeightBehavior
        return textHeightBehavior != old.textHeightBehavior
    }
}

// MARK: - Text

/// A run of text with a single style.
///
/// The `Text` widget displays a string of text with a single style. The string
/// might break across multiple lines or might all be displayed on the same line
/// depending on the layout constraints.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/text.dart:491`
public class Text: StatelessWidget {
    public let data: String?
    public let textSpan: InlineSpan?
    public let style: TextStyle?
    public let textAlign: TextAlign?
    public let textDirection: TextDirection?
    public let softWrap: Bool?
    public let overflow: TextOverflow?
    public let maxLines: Int?
    public let textWidthBasis: TextWidthBasis?
    public let textHeightBehavior: TextHeightBehavior?

    /// Creates a Text widget from a string.
    ///
    /// **Dart Source:** `text.dart:525`
    public init(
        _ data: String,
        key: (any Key)? = nil,
        style: TextStyle? = nil,
        textAlign: TextAlign? = nil,
        textDirection: TextDirection? = nil,
        softWrap: Bool? = nil,
        overflow: TextOverflow? = nil,
        maxLines: Int? = nil,
        textWidthBasis: TextWidthBasis? = nil,
        textHeightBehavior: TextHeightBehavior? = nil
    ) {
        self.data = data
        self.textSpan = nil
        self.style = style
        self.textAlign = textAlign
        self.textDirection = textDirection
        self.softWrap = softWrap
        self.overflow = overflow
        self.maxLines = maxLines
        self.textWidthBasis = textWidthBasis
        self.textHeightBehavior = textHeightBehavior
        super.init(key: key)
    }

    /// Creates a Text widget from an InlineSpan (Text.rich equivalent).
    ///
    /// **Dart Source:** `text.dart:575`
    public init(
        rich textSpan: InlineSpan,
        key: (any Key)? = nil,
        style: TextStyle? = nil,
        textAlign: TextAlign? = nil,
        textDirection: TextDirection? = nil,
        softWrap: Bool? = nil,
        overflow: TextOverflow? = nil,
        maxLines: Int? = nil,
        textWidthBasis: TextWidthBasis? = nil,
        textHeightBehavior: TextHeightBehavior? = nil
    ) {
        self.data = nil
        self.textSpan = textSpan
        self.style = style
        self.textAlign = textAlign
        self.textDirection = textDirection
        self.softWrap = softWrap
        self.overflow = overflow
        self.maxLines = maxLines
        self.textWidthBasis = textWidthBasis
        self.textHeightBehavior = textHeightBehavior
        super.init(key: key)
    }

    /// **Dart Source:** `text.dart:628`
    public override func build(_ context: any BuildContext) -> Widget {
        let defaultTextStyle = DefaultTextStyle.of(context)
        var effectiveTextStyle = style
        if let s = style {
            effectiveTextStyle = defaultTextStyle.style.merge(s)
        } else {
            effectiveTextStyle = defaultTextStyle.style
        }

        let effectiveSoftWrap = softWrap ?? defaultTextStyle.softWrap
        let effectiveOverflow = overflow ?? defaultTextStyle.overflow
        let effectiveMaxLines = maxLines ?? defaultTextStyle.maxLines
        let effectiveTextWidthBasis = textWidthBasis ?? defaultTextStyle.textWidthBasis
        let effectiveTextHeightBehavior = textHeightBehavior
            ?? defaultTextStyle.textHeightBehavior
            ?? DefaultTextHeightBehavior.maybeOf(context)

        // A rich span hangs under the effective style, as Dart's does, so
        // `style:` and the ambient DefaultTextStyle still apply to it. It
        // used to be handed over bare, which painted a tooltip's caption
        // in the paragraph default — white on a light surface.
        let span: InlineSpan
        if let textSpan = textSpan {
            span = TextSpan(children: [textSpan], style: effectiveTextStyle)
        } else {
            span = TextSpan(text: data ?? "", style: effectiveTextStyle)
        }

        return RichText(
            text: span,
            textAlign: textAlign ?? defaultTextStyle.textAlign ?? .start,
            textDirection: textDirection,
            softWrap: effectiveSoftWrap,
            overflow: effectiveOverflow,
            maxLines: effectiveMaxLines,
            textWidthBasis: effectiveTextWidthBasis,
            textHeightBehavior: effectiveTextHeightBehavior
        )
    }
}

// MARK: - _DefaultTextStyleNullWidget

/// Private widget used as a placeholder child for `DefaultTextStyle.fallback`.
///
/// **Dart Source:** `text.dart` (private `_NullWidget`)
private class _DefaultTextStyleNullWidget: StatelessWidget {
    init() {
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        fatalError(
            "A DefaultTextStyle constructed with DefaultTextStyle.fallback "
            + "cannot be incorporated into the widget tree, it is meant only to provide "
            + "a fallback value returned by DefaultTextStyle.of() when no enclosing "
            + "default text style is present in a BuildContext."
        )
    }
}
