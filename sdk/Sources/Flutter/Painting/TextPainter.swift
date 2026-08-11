// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// An object that paints a `TextSpan` tree into a `Canvas`.
///
/// **Dart Source:** `packages/flutter/lib/src/painting/text_painter.dart`

import FlutterSwiftBridge

// MARK: - TextSelection Stub

/// A range of text that represents a selection.
///
/// TODO: Replace with full TextSelection type when services layer is migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/services/text_editing.dart`
public struct TextSelection: Equatable, Hashable {
    /// The offset at which the selection originates.
    public let baseOffset: Int

    /// The offset at which the selection terminates.
    public let extentOffset: Int

    /// The position at which the selection originates.
    public var base: TextPosition {
        TextPosition(offset: baseOffset, affinity: .downstream)
    }

    /// The position at which the selection terminates.
    public var extent: TextPosition {
        TextPosition(offset: extentOffset, affinity: .downstream)
    }

    /// Whether the selection range is empty (collapsed).
    public var isCollapsed: Bool {
        baseOffset == extentOffset
    }

    /// Whether the selection is valid.
    public var isValid: Bool {
        baseOffset >= 0 && extentOffset >= 0
    }

    /// The smaller of [baseOffset] and [extentOffset].
    public var start: Int {
        min(baseOffset, extentOffset)
    }

    /// The larger of [baseOffset] and [extentOffset].
    public var end: Int {
        max(baseOffset, extentOffset)
    }

    /// Creates a text selection with the given offsets.
    public init(baseOffset: Int, extentOffset: Int) {
        self.baseOffset = baseOffset
        self.extentOffset = extentOffset
    }

    /// Creates a collapsed selection at the given offset.
    public init(offset: Int) {
        self.baseOffset = offset
        self.extentOffset = offset
    }
}

// MARK: - TextBoundary Stub

/// A protocol that defines how to locate boundaries in text.
///
/// TODO: Replace with full TextBoundary protocol when services layer is migrated.
///
/// **Dart Source:** `packages/flutter/lib/src/services/text_boundary.dart`
public protocol TextBoundary: AnyObject {
    /// Returns the text boundary range at the given position.
    func getTextBoundaryAt(_ position: Int) -> TextRange

    /// Returns the leading text boundary at the given position.
    func getLeadingTextBoundaryAt(_ position: Int) -> Int?

    /// Returns the trailing text boundary at the given position.
    func getTrailingTextBoundaryAt(_ position: Int) -> Int?
}

/// Default implementations for TextBoundary.
extension TextBoundary {
    public func getLeadingTextBoundaryAt(_ position: Int) -> Int? {
        if position < 0 {
            return nil
        }
        return getTextBoundaryAt(position).start
    }

    public func getTrailingTextBoundaryAt(_ position: Int) -> Int? {
        let range = getTextBoundaryAt(max(position, 0))
        // If position is at the start, return the end of this range
        return range.end
    }
}

/// A predicate that determines whether a boundary should be skipped.
///
/// **Dart Source:** `text_painter.dart:271-293`
public typealias UntilPredicate = (Int, Bool) -> Bool

// MARK: - TextWidthBasis

/// The different ways of measuring the width of one or more lines of text.
///
/// See `Text.textWidthBasis`, for example.
///
/// **Dart Source:** `text_painter.dart:152-162`
public enum TextWidthBasis: Sendable, Hashable {
    /// Multiline text will take up the full width given by the parent. For single
    /// line text, only the minimum amount of width needed to contain the text
    /// will be used. A common use case for this is a standard series of
    /// paragraphs.
    case parent

    /// The width will be exactly enough to contain the longest line and no
    /// longer. A common use case for this is chat bubbles.
    case longestLine
}

// MARK: - LineCaretMetrics

/// The caret metrics for carets located in a non-empty paragraph. Such carets
/// are anchored to the trailing edge or the leading edge of a glyph, or a
/// ligature component.
///
/// **Dart Source:** `text_painter.dart:534-562`
internal struct LineCaretMetrics {
    /// The offset from the top left corner of the paragraph to the caret's top
    /// start location.
    let offset: Offset

    /// The writing direction of the glyph the `LineCaretMetrics` is associated with.
    /// The value determines whether the cursor is painted to the left or to the
    /// right of `offset`.
    let writingDirection: TextDirection

    /// The recommended height of the caret.
    let height: Double

    /// Returns a new `LineCaretMetrics` shifted by the given offset.
    func shift(_ offset: Offset) -> LineCaretMetrics {
        if offset == Offset.zero {
            return self
        }
        return LineCaretMetrics(
            offset: Offset(self.offset.dx + offset.dx, self.offset.dy + offset.dy),
            writingDirection: writingDirection,
            height: height
        )
    }
}

// MARK: - TextLayout

/// Internal class that wraps a `Paragraph` for text layout operations.
///
/// **Dart Source:** `text_painter.dart:295-420`
internal class TextLayout {
    let writingDirection: TextDirection

    // Computing plainText is a bit expensive and is currently not needed for
    // simple static text. Pass in the entire text painter so `TextPainter.plainText`
    // is only called when needed.
    //
    // `unowned`, and that is load bearing. This back-reference closes a strong
    // cycle the painter itself completes: TextPainter._layoutCache →
    // TextPainterLayoutCacheWithOffset.layout → TextLayout._painter →
    // TextPainter. Dart's GC collects cycles so upstream can hold this
    // strongly; under ARC it made every laid-out TextPainter immortal unless
    // something explicitly called dispose()/markNeedsLayout() to nil the
    // cache — which is exactly the ~20 MB/styled-dump terminal leak
    // (docs/perf/terminal-vs-ghostty-2026-08-04/): paragraphs made 150 /
    // freed 9, painters freed 0. Unowned rather than weak because a
    // TextLayout is only reachable through its painter's _layoutCache, so the
    // painter is always alive while any method here can run.
    private unowned let _painter: TextPainter

    // This field is not final because the owner TextPainter could create a new
    // Paragraph with the exact same text layout (for example, when only the
    // color of the text is changed).
    var _paragraph: any Paragraph

    init(_ paragraph: any Paragraph, _ writingDirection: TextDirection, _ painter: TextPainter) {
        self._paragraph = paragraph
        self.writingDirection = writingDirection
        self._painter = painter
    }

    /// Whether this layout has been invalidated and disposed.
    var debugDisposed: Bool { _paragraph.debugDisposed }

    /// The horizontal space required to paint this text.
    var width: Double { _paragraph.width }

    /// The vertical space required to paint this text.
    var height: Double { _paragraph.height }

    /// The width at which decreasing the width of the text would prevent it from
    /// painting itself completely within its bounds.
    var minIntrinsicLineExtent: Double { _paragraph.minIntrinsicWidth }

    /// The width at which increasing the width of the text no longer decreases the height.
    var maxIntrinsicLineExtent: Double { _paragraph.maxIntrinsicWidth }

    /// The distance from the left edge of the leftmost glyph to the right edge of
    /// the rightmost glyph in the paragraph.
    var longestLine: Double { _paragraph.longestLine }

    /// Returns the distance from the top of the text to the first baseline of the
    /// given type.
    func getDistanceToBaseline(_ baseline: TextBaseline) -> Double {
        switch baseline {
        case .alphabetic:
            return _paragraph.alphabeticBaseline
        case .ideographic:
            return _paragraph.ideographicBaseline
        @unknown default:
            return _paragraph.alphabeticBaseline
        }
    }

    /// The line caret metrics representing the end of text location.
    ///
    /// **Dart Source:** `text_painter.dart:364-412`
    lazy var _endOfTextCaretMetrics: LineCaretMetrics = _computeEndOfTextCaretAnchorOffset()

    private func _computeEndOfTextCaretAnchorOffset() -> LineCaretMetrics {
        let rawString = _painter.plainText
        let lastLineIndex = _paragraph.numberOfLines - 1
        assert(lastLineIndex >= 0)
        let lineMetrics = _paragraph.getLineMetricsAt(lastLineIndex)!

        // Check for trailing spaces
        let lastCharIndex = rawString.index(before: rawString.endIndex)
        let lastCodeUnit = rawString[lastCharIndex].utf16.first ?? 0
        let hasTrailingSpaces: Bool
        switch lastCodeUnit {
        case 0x0009: // horizontal tab
            hasTrailingSpaces = true
        case 0x00A0, 0x2007, 0x202F: // no-break space, figure space, narrow no-break space
            hasTrailingSpaces = false
        default:
            // Check if it's a space separator using Unicode category
            let scalar = Unicode.Scalar(lastCodeUnit)
            if let scalar = scalar {
                hasTrailingSpaces = scalar.properties.generalCategory == .spaceSeparator
            } else {
                hasTrailingSpaces = false
            }
        }

        let baseline = lineMetrics.baseline
        let dx: Double
        let caretHeight: Double

        // UTF-16 code unit count for rawString
        let utf16Length = rawString.utf16.count
        let lastGlyph = _paragraph.getGlyphInfoAt(utf16Length - 1)

        if hasTrailingSpaces, let lastGlyph = lastGlyph {
            let glyphBounds = lastGlyph.graphemeClusterLayoutBounds
            assert(!glyphBounds.isEmpty)
            switch writingDirection {
            case .ltr:
                dx = glyphBounds.right
            case .rtl:
                dx = glyphBounds.left
            @unknown default:
                dx = glyphBounds.right
            }
            caretHeight = glyphBounds.height
        } else {
            switch writingDirection {
            case .ltr:
                dx = lineMetrics.left + lineMetrics.width
            case .rtl:
                dx = lineMetrics.left
            @unknown default:
                dx = lineMetrics.left + lineMetrics.width
            }
            caretHeight = lineMetrics.height
        }

        return LineCaretMetrics(
            offset: Offset(dx, baseline),
            writingDirection: writingDirection,
            height: caretHeight
        )
    }

    func _contentWidthFor(_ minWidth: Double, _ maxWidth: Double, _ widthBasis: TextWidthBasis) -> Double {
        switch widthBasis {
        case .longestLine:
            return clampDouble(longestLine, minWidth, maxWidth)
        case .parent:
            return clampDouble(maxIntrinsicLineExtent, minWidth, maxWidth)
        }
    }
}

// MARK: - TextPainterLayoutCacheWithOffset

/// This class stores the current text layout and the corresponding
/// paintOffset/contentWidth, as well as some cached text metrics values that
/// depend on the current text layout, which will be invalidated as soon as the
/// text layout is invalidated.
///
/// **Dart Source:** `text_painter.dart:426-529`
internal class TextPainterLayoutCacheWithOffset {
    let layout: TextLayout
    let layoutMaxWidth: Double
    var contentWidth: Double
    let textAlignment: Double

    init(
        _ layout: TextLayout,
        _ textAlignment: Double,
        _ layoutMaxWidth: Double,
        _ contentWidth: Double
    ) {
        assert(textAlignment >= 0.0 && textAlignment <= 1.0)
        assert(!layoutMaxWidth.isNaN)
        assert(!contentWidth.isNaN)
        self.layout = layout
        self.textAlignment = textAlignment
        self.layoutMaxWidth = layoutMaxWidth
        self.contentWidth = contentWidth
    }

    /// The paintOffset of the `paragraph` in the TextPainter's canvas.
    var paintOffset: Offset {
        if textAlignment == 0 {
            return Offset.zero
        }
        if !paragraph.width.isFinite {
            return Offset(Double.infinity, 0.0)
        }
        let dx = textAlignment * (contentWidth - paragraph.width)
        assert(!dx.isNaN)
        return Offset(dx, 0)
    }

    var paragraph: any Paragraph { layout._paragraph }

    /// Try to resize the contentWidth to fit the new input constraints.
    ///
    /// Returns false if the new constraints require the text layout library to
    /// re-compute the line breaks.
    ///
    /// **Dart Source:** `text_painter.dart:471-516`
    func _resizeToFit(_ minWidth: Double, _ maxWidth: Double, _ widthBasis: TextWidthBasis) -> Bool {
        assert(layout.maxIntrinsicLineExtent.isFinite)
        assert(minWidth <= maxWidth)

        if maxWidth == contentWidth && minWidth == contentWidth {
            contentWidth = layout._contentWidthFor(minWidth, maxWidth, widthBasis)
            return true
        }

        // Special case:
        // When the paint offset and the paragraph width are both infinity, it's
        // likely that the text layout engine skipped layout because there weren't
        // anything to paint. Always try to re-compute the text layout.
        if !paintOffset.dx.isFinite && !paragraph.width.isFinite && minWidth.isFinite {
            assert(paintOffset.dx == Double.infinity)
            assert(paragraph.width == Double.infinity)
            return false
        }

        let maxIntrinsicWidth = paragraph.maxIntrinsicWidth
        // Skip line breaking if the input width remains the same, or there will be
        // no soft breaks.
        let skipLineBreaking =
            maxWidth == layoutMaxWidth
            || ((paragraph.width - maxIntrinsicWidth) > -precisionErrorTolerance
                && (maxWidth - maxIntrinsicWidth) > -precisionErrorTolerance)
        if skipLineBreaking {
            contentWidth = layout._contentWidthFor(minWidth, maxWidth, widthBasis)
            return true
        }
        return false
    }

    // ---- Cached Values ----

    var inlinePlaceholderBoxes: [TextBox] {
        if let cached = _cachedInlinePlaceholderBoxes {
            return cached
        }
        let boxes = paragraph.getBoxesForPlaceholders()
        _cachedInlinePlaceholderBoxes = boxes
        return boxes
    }
    private var _cachedInlinePlaceholderBoxes: [TextBox]?

    var lineMetrics: [LineMetrics] {
        if let cached = _cachedLineMetrics {
            return cached
        }
        let metrics = paragraph.computeLineMetrics()
        _cachedLineMetrics = metrics
        return metrics
    }
    private var _cachedLineMetrics: [LineMetrics]?

    /// Used to determine whether the caret metrics cache should be invalidated.
    var _previousCaretPositionKey: Int?
}

// MARK: - WordBoundary

/// A `TextBoundary` subclass for locating word breaks.
///
/// The underlying implementation uses UAX #29 defined default word boundaries.
///
/// **Dart Source:** `text_painter.dart:177-269`
public class WordBoundary: TextBoundary {
    private let _text: InlineSpan
    private let _paragraph: any Paragraph

    internal init(_ text: InlineSpan, _ paragraph: any Paragraph) {
        self._text = text
        self._paragraph = paragraph
    }

    public func getTextBoundaryAt(_ position: Int) -> TextRange {
        return _paragraph.getWordBoundary(TextPosition(offset: max(position, 0)))
    }

    // Combines two UTF-16 code units (high surrogate + low surrogate) into a
    // single code point that represents a supplementary character.
    static func _codePointFromSurrogates(_ highSurrogate: Int, _ lowSurrogate: Int) -> Int {
        assert(TextPainter.isHighSurrogate(highSurrogate))
        assert(TextPainter.isLowSurrogate(lowSurrogate))
        let base = 0x010000 - (0xD800 << 10) - 0xDC00
        return (highSurrogate << 10) + lowSurrogate + base
    }

    // The Runes class does not provide random access with a code unit offset.
    func _codePointAt(_ index: Int) -> Int? {
        guard let codeUnitAtIndex = _text.codeUnitAt(index) else {
            return nil
        }
        switch codeUnitAtIndex & 0xFC00 {
        case 0xD800:
            return WordBoundary._codePointFromSurrogates(codeUnitAtIndex, _text.codeUnitAt(index + 1)!)
        case 0xDC00:
            return WordBoundary._codePointFromSurrogates(_text.codeUnitAt(index - 1)!, codeUnitAtIndex)
        default:
            return codeUnitAtIndex
        }
    }

    /// Returns true if the given code point is a newline character.
    ///
    /// Carriage Return is not treated as a hard line break.
    public static func _isNewline(_ codePoint: Int) -> Bool {
        switch codePoint {
        case 0x000A, // Line Feed
             0x0085, // New Line
             0x000B, // Form Feed
             0x000C, // Vertical Feed
             0x2028, // Line Separator
             0x2029: // Paragraph Separator
            return true
        default:
            return false
        }
    }

    func _skipSpacesAndPunctuations(_ offset: Int, _ forward: Bool) -> Bool {
        // Use code point since some punctuations are supplementary characters.
        let innerCodePoint = _codePointAt(forward ? offset - 1 : offset)
        let outerCodeUnit = _text.codeUnitAt(forward ? offset : offset - 1)

        // Make sure the hard break rules in UAX#29 take precedence over the ones we
        // add below.
        let hardBreakRulesApply =
            innerCodePoint == nil
            || outerCodeUnit == nil
            || WordBoundary._isNewline(innerCodePoint!)
            || WordBoundary._isNewline(outerCodeUnit!)

        if hardBreakRulesApply {
            return true
        }

        // Check if the inner code point is a space separator or punctuation
        guard let codePoint = innerCodePoint, let scalar = Unicode.Scalar(codePoint) else {
            return true
        }
        let category = scalar.properties.generalCategory
        let isSpaceOrPunctuation =
            category == .spaceSeparator
            || category == .connectorPunctuation
            || category == .dashPunctuation
            || category == .closePunctuation
            || category == .finalPunctuation
            || category == .initialPunctuation
            || category == .otherPunctuation
            || category == .openPunctuation
        return !isSpaceOrPunctuation
    }

    /// Returns a `TextBoundary` suitable for handling keyboard navigation
    /// commands that change the current selection word by word.
    ///
    /// **Dart Source:** `text_painter.dart:268`
    public lazy var moveByWordBoundary: TextBoundary = {
        UntilTextBoundary(self, _skipSpacesAndPunctuations)
    }()
}

// MARK: - UntilTextBoundary

/// A text boundary that skips boundaries that don't match a predicate.
///
/// **Dart Source:** `text_painter.dart:271-293`
internal class UntilTextBoundary: TextBoundary {
    let _textBoundary: TextBoundary
    let _predicate: UntilPredicate

    init(_ textBoundary: TextBoundary, _ predicate: @escaping UntilPredicate) {
        self._textBoundary = textBoundary
        self._predicate = predicate
    }

    public func getTextBoundaryAt(_ position: Int) -> TextRange {
        return _textBoundary.getTextBoundaryAt(position)
    }

    public func getLeadingTextBoundaryAt(_ position: Int) -> Int? {
        if position < 0 {
            return nil
        }
        let offset = _textBoundary.getLeadingTextBoundaryAt(position)
        guard let offset = offset else { return nil }
        if _predicate(offset, false) {
            return offset
        }
        return getLeadingTextBoundaryAt(offset - 1)
    }

    public func getTrailingTextBoundaryAt(_ position: Int) -> Int? {
        let offset = _textBoundary.getTrailingTextBoundaryAt(max(position, 0))
        guard let offset = offset else { return nil }
        if _predicate(offset, true) {
            return offset
        }
        return getTrailingTextBoundaryAt(offset)
    }
}

// MARK: - TextPainter

/// An object that paints a `TextSpan` tree into a `Canvas`.
///
/// To use a `TextPainter`, follow these steps:
///
/// 1. Create a `TextSpan` tree and pass it to the `TextPainter`
///    constructor.
///
/// 2. Call `layout` to prepare the paragraph.
///
/// 3. Call `paint` as often as desired to paint the paragraph.
///
/// 4. Call `dispose` when the object will no longer be accessed to release
///    native resources.
///
/// **Dart Source:** `text_painter.dart:589-1831`
public final class TextPainter {

    // MARK: - Initialization

    /// Creates a text painter that paints the given text.
    ///
    /// The `text` and `textDirection` arguments are optional but `text` and
    /// `textDirection` must be non-nil before calling `layout`.
    ///
    /// The `maxLines` property, if non-nil, must be greater than zero.
    ///
    /// **Dart Source:** `text_painter.dart:596-632`
    public init(
        text: InlineSpan? = nil,
        textAlign: TextAlign = .start,
        textDirection: TextDirection? = nil,
        textScaler: any TextScaler = TextScalers.noScaling,
        maxLines: Int? = nil,
        ellipsis: String? = nil,
        locale: Locale? = nil,
        strutStyle: StrutStyle? = nil,
        textWidthBasis: TextWidthBasis = .parent,
        textHeightBehavior: TextHeightBehavior? = nil
    ) {
        assert(text == nil || text!.debugAssertIsValid())
        assert(maxLines == nil || maxLines! > 0)
        _text = text
        _textAlign = textAlign
        _textDirection = textDirection
        _textScaler = textScaler
        _maxLines = maxLines
        _ellipsis = ellipsis
        _locale = locale
        _strutStyle = strutStyle
        _textWidthBasis = textWidthBasis
        _textHeightBehavior = textHeightBehavior
    }

    // MARK: - Static Methods

    /// Computes the width of a configured `TextPainter`.
    ///
    /// This is a convenience method that creates a text painter with the supplied
    /// parameters, lays it out with the supplied `minWidth` and `maxWidth`, and
    /// returns its `TextPainter.width` making sure to dispose the underlying
    /// resources.
    ///
    /// **Dart Source:** `text_painter.dart:642-686`
    public static func computeWidth(
        text: InlineSpan,
        textDirection: TextDirection,
        textAlign: TextAlign = .start,
        textScaler: any TextScaler = TextScalers.noScaling,
        maxLines: Int? = nil,
        ellipsis: String? = nil,
        locale: Locale? = nil,
        strutStyle: StrutStyle? = nil,
        textWidthBasis: TextWidthBasis = .parent,
        textHeightBehavior: TextHeightBehavior? = nil,
        minWidth: Double = 0.0,
        maxWidth: Double = Double.infinity
    ) -> Double {
        let painter = TextPainter(
            text: text,
            textAlign: textAlign,
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: maxLines,
            ellipsis: ellipsis,
            locale: locale,
            strutStyle: strutStyle,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior
        )
        painter.layout(minWidth: minWidth, maxWidth: maxWidth)
        let width = painter.width
        painter.dispose()
        return width
    }

    /// Computes the max intrinsic width of a configured `TextPainter`.
    ///
    /// **Dart Source:** `text_painter.dart:696-740`
    public static func computeMaxIntrinsicWidth(
        text: InlineSpan,
        textDirection: TextDirection,
        textAlign: TextAlign = .start,
        textScaler: any TextScaler = TextScalers.noScaling,
        maxLines: Int? = nil,
        ellipsis: String? = nil,
        locale: Locale? = nil,
        strutStyle: StrutStyle? = nil,
        textWidthBasis: TextWidthBasis = .parent,
        textHeightBehavior: TextHeightBehavior? = nil,
        minWidth: Double = 0.0,
        maxWidth: Double = Double.infinity
    ) -> Double {
        let painter = TextPainter(
            text: text,
            textAlign: textAlign,
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: maxLines,
            ellipsis: ellipsis,
            locale: locale,
            strutStyle: strutStyle,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior
        )
        painter.layout(minWidth: minWidth, maxWidth: maxWidth)
        let maxIntrinsicW = painter.maxIntrinsicWidth
        painter.dispose()
        return maxIntrinsicW
    }

    // Returns true if value falls in the valid range of the UTF16 encoding.
    private static func _isUTF16(_ value: Int) -> Bool {
        return value >= 0x0 && value <= 0xFFFFF
    }

    /// Returns true if the given value is a valid UTF-16 high (first) surrogate.
    ///
    /// **Dart Source:** `text_painter.dart:1392-1395`
    public static func isHighSurrogate(_ value: Int) -> Bool {
        assert(_isUTF16(value))
        return value & 0xFC00 == 0xD800
    }

    /// Returns true if the given value is a valid UTF-16 low (second) surrogate.
    ///
    /// **Dart Source:** `text_painter.dart:1405-1408`
    public static func isLowSurrogate(_ value: Int) -> Bool {
        assert(_isUTF16(value))
        return value & 0xFC00 == 0xDC00
    }

    /// Computes the paint offset fraction for the given text alignment.
    ///
    /// **Dart Source:** `text_painter.dart:1432-1442`
    private static func _computePaintOffsetFraction(
        _ textAlign: TextAlign,
        _ textDirection: TextDirection
    ) -> Double {
        switch (textAlign, textDirection) {
        case (.left, _): return 0.0
        case (.right, _): return 1.0
        case (.center, _): return 0.5
        case (.start, .ltr), (.justify, .ltr): return 0.0
        case (.start, .rtl), (.justify, .rtl): return 1.0
        case (.end, .ltr): return 1.0
        case (.end, .rtl): return 0.0
        @unknown default: return 0.0
        }
    }

    // MARK: - Private State

    /// The result of the most recent `layout` call.
    private var _layoutCache: TextPainterLayoutCacheWithOffset?

    /// Whether _layoutCache contains outdated paint information and needs to be
    /// updated before painting.
    private var _rebuildParagraphForPaint = true

    // MARK: - Properties

    /// The (potentially styled) text to paint.
    ///
    /// After this is set, you must call `layout` before the next call to `paint`.
    /// This and `textDirection` must be non-nil before you call `layout`.
    ///
    /// **Dart Source:** `text_painter.dart:800-827`
    public var text: InlineSpan? {
        get { _text }
        set {
            assert(newValue == nil || newValue!.debugAssertIsValid())
            if _text === newValue {
                return
            }
            if _text?.style != newValue?.style {
                _layoutTemplate?.dispose()
                _layoutTemplate = nil
            }

            let comparison: RenderComparison
            if newValue == nil {
                comparison = .layout
            } else if let oldText = _text {
                comparison = oldText.compareTo(newValue!)
            } else {
                comparison = .layout
            }

            _text = newValue
            _cachedPlainText = nil

            if comparison.rawValue >= RenderComparison.layout.rawValue {
                markNeedsLayout()
            } else if comparison.rawValue >= RenderComparison.paint.rawValue {
                _rebuildParagraphForPaint = true
            }
        }
    }
    private var _text: InlineSpan?

    /// Returns a plain text version of the text to paint.
    ///
    /// **Dart Source:** `text_painter.dart:832-836`
    public var plainText: String {
        if _cachedPlainText == nil {
            _cachedPlainText = _text?.toPlainText(includeSemanticsLabels: false)
        }
        return _cachedPlainText ?? ""
    }
    private var _cachedPlainText: String?

    /// How the text should be aligned horizontally.
    ///
    /// **Dart Source:** `text_painter.dart:844-852`
    public var textAlign: TextAlign {
        get { _textAlign }
        set {
            if _textAlign == newValue { return }
            _textAlign = newValue
            markNeedsLayout()
        }
    }
    private var _textAlign: TextAlign

    /// The default directionality of the text.
    ///
    /// **Dart Source:** `text_painter.dart:869-879`
    public var textDirection: TextDirection? {
        get { _textDirection }
        set {
            if _textDirection == newValue { return }
            _textDirection = newValue
            markNeedsLayout()
            _layoutTemplate?.dispose()
            _layoutTemplate = nil
        }
    }
    private var _textDirection: TextDirection?

    /// The font scaling strategy to use when laying out and rendering the text.
    ///
    /// **Dart Source:** `text_painter.dart:916-926`
    public var textScaler: any TextScaler {
        get { _textScaler }
        set {
            if newValue == _textScaler { return }
            _textScaler = newValue
            markNeedsLayout()
            _layoutTemplate?.dispose()
            _layoutTemplate = nil
        }
    }
    private var _textScaler: any TextScaler

    /// The string used to ellipsize overflowing text.
    ///
    /// **Dart Source:** `text_painter.dart:944-953`
    public var ellipsis: String? {
        get { _ellipsis }
        set {
            assert(newValue == nil || !newValue!.isEmpty)
            if _ellipsis == newValue { return }
            _ellipsis = newValue
            markNeedsLayout()
        }
    }
    private var _ellipsis: String?

    /// The locale used to select region-specific glyphs.
    ///
    /// **Dart Source:** `text_painter.dart:956-964`
    public var locale: Locale? {
        get { _locale }
        set {
            if _locale == newValue { return }
            _locale = newValue
            markNeedsLayout()
        }
    }
    private var _locale: Locale?

    /// An optional maximum number of lines for the text to span, wrapping if
    /// necessary.
    ///
    /// **Dart Source:** `text_painter.dart:973-984`
    public var maxLines: Int? {
        get { _maxLines }
        set {
            assert(newValue == nil || newValue! > 0)
            if _maxLines == newValue { return }
            _maxLines = newValue
            markNeedsLayout()
        }
    }
    private var _maxLines: Int?

    /// The strut style to use.
    ///
    /// **Dart Source:** `text_painter.dart:998-1006`
    public var strutStyle: StrutStyle? {
        get { _strutStyle }
        set {
            if _strutStyle == newValue { return }
            _strutStyle = newValue
            markNeedsLayout()
        }
    }
    private var _strutStyle: StrutStyle?

    /// Defines how to measure the width of the rendered text.
    ///
    /// **Dart Source:** `text_painter.dart:1011-1021`
    public var textWidthBasis: TextWidthBasis {
        get { _textWidthBasis }
        set {
            if _textWidthBasis == newValue { return }
            _textWidthBasis = newValue
        }
    }
    private var _textWidthBasis: TextWidthBasis

    /// Text height behavior configuration.
    ///
    /// **Dart Source:** `text_painter.dart:1024-1032`
    public var textHeightBehavior: TextHeightBehavior? {
        get { _textHeightBehavior }
        set {
            if _textHeightBehavior == newValue { return }
            _textHeightBehavior = newValue
            markNeedsLayout()
        }
    }
    private var _textHeightBehavior: TextHeightBehavior?

    /// An ordered list of `TextBox`es that bound the positions of the placeholders
    /// in the paragraph.
    ///
    /// **Dart Source:** `text_painter.dart:1039-1053`
    public var inlinePlaceholderBoxes: [TextBox]? {
        guard let layoutCache = _layoutCache else {
            return nil
        }
        let offset = layoutCache.paintOffset
        if !offset.dx.isFinite || !offset.dy.isFinite {
            return []
        }
        let rawBoxes = layoutCache.inlinePlaceholderBoxes
        if offset == Offset.zero {
            return rawBoxes
        }
        return rawBoxes.map { TextPainter._shiftTextBox($0, offset) }
    }

    /// Sets the dimensions of each placeholder in `text`.
    ///
    /// **Dart Source:** `text_painter.dart:1064-1082`
    public func setPlaceholderDimensions(_ value: [PlaceholderDimensions]?) {
        guard let value = value, !value.isEmpty else { return }
        if value == _placeholderDimensions { return }
        _placeholderDimensions = value
        markNeedsLayout()
    }
    private var _placeholderDimensions: [PlaceholderDimensions]?

    // MARK: - Layout Template

    private var _layoutTemplate: (any Paragraph)?

    private func _createParagraphStyle(_ textAlignOverride: TextAlign? = nil) -> ParagraphStyle {
        assert(
            textDirection != nil,
            "TextPainter.textDirection must be set to a non-nil value before using the TextPainter."
        )
        let baseStyle = _text?.style ?? TextStyle()
        return baseStyle.getParagraphStyle(
            textAlign: textAlignOverride ?? textAlign,
            textDirection: textDirection,
            textScaler: textScaler,
            ellipsis: _ellipsis,
            maxLines: _maxLines,
            textHeightBehavior: _textHeightBehavior,
            locale: _locale,
            strutStyle: _strutStyle
        )
    }

    private func _createLayoutTemplate() -> any Paragraph {
        let builder = ParagraphBuilders.create(_createParagraphStyle(.left))
        let textStyle = text?.style?.getTextStyle(textScaler: textScaler)
        if let textStyle = textStyle {
            builder.pushStyle(textStyle)
        }
        builder.addText(" ")
        let paragraph = builder.build()
        paragraph.layout(ParagraphConstraints(width: Double.infinity))
        return paragraph
    }

    private func _getOrCreateLayoutTemplate() -> any Paragraph {
        if _layoutTemplate == nil {
            _layoutTemplate = _createLayoutTemplate()
        }
        return _layoutTemplate!
    }

    /// The height of a space in `text` in logical pixels.
    ///
    /// Not every line of text in `text` will have this height, but this height
    /// is "typical" for text in `text` and useful for sizing other objects
    /// relative a typical line of text.
    ///
    /// Obtaining this value does not require calling `layout`.
    ///
    /// **Dart Source:** `text_painter.dart:1129`
    public var preferredLineHeight: Double {
        return _getOrCreateLayoutTemplate().height
    }

    // MARK: - Layout Metrics (valid only after layout)

    /// The width at which decreasing the width of the text would prevent it from
    /// painting itself completely within its bounds.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1135-1138`
    public var minIntrinsicWidth: Double {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return _layoutCache!.layout.minIntrinsicLineExtent
    }

    /// The width at which increasing the width of the text no longer decreases the height.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1143-1146`
    public var maxIntrinsicWidth: Double {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return _layoutCache!.layout.maxIntrinsicLineExtent
    }

    /// The horizontal space required to paint this text.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1151-1155`
    public var width: Double {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return _layoutCache!.contentWidth
    }

    /// The vertical space required to paint this text.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1160-1163`
    public var height: Double {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return _layoutCache!.layout.height
    }

    /// The amount of space required to paint this text.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1168-1172`
    public var size: Size {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return Size(width, height)
    }

    /// Returns the distance from the top of the text to the first baseline of the
    /// given type.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1178-1181`
    public func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return _layoutCache!.layout.getDistanceToBaseline(baseline)
    }

    /// Whether any text was truncated or ellipsized.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1194-1197`
    public var didExceedMaxLines: Bool {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return _layoutCache!.paragraph.didExceedMaxLines
    }

    // MARK: - Layout

    /// Marks this text painter's layout information as dirty and removes cached
    /// information.
    ///
    /// **Dart Source:** `text_painter.dart:781-790`
    public func markNeedsLayout() {
        _layoutCache?.paragraph.dispose()
        _layoutCache = nil
    }

    /// Creates a `Paragraph` using the current configurations in this class.
    ///
    /// **Dart Source:** `text_painter.dart:1201-1210`
    private func _createParagraph(_ text: InlineSpan) -> any Paragraph {
        let builder = ParagraphBuilders.create(_createParagraphStyle())
        text.build(builder, textScaler: textScaler, dimensions: _placeholderDimensions)
        _rebuildParagraphForPaint = false
        return builder.build()
    }

    /// Computes the visual position of the glyphs for painting the text.
    ///
    /// The text will layout with a width that's as close to its max intrinsic
    /// width as possible while still being greater than or equal to `minWidth`
    /// and less than or equal to `maxWidth`.
    ///
    /// The `text` and `textDirection` properties must be non-nil before this is
    /// called.
    ///
    /// **Dart Source:** `text_painter.dart:1221-1292`
    public func layout(minWidth: Double = 0.0, maxWidth: Double = Double.infinity) {
        assert(!maxWidth.isNaN)
        assert(!minWidth.isNaN)

        let cachedLayout = _layoutCache
        if cachedLayout != nil && cachedLayout!._resizeToFit(minWidth, maxWidth, textWidthBasis) {
            return
        }

        guard let text = self.text else {
            preconditionFailure(
                "TextPainter.text must be set to a non-nil value before using the TextPainter."
            )
        }
        guard let textDirection = self.textDirection else {
            preconditionFailure(
                "TextPainter.textDirection must be set to a non-nil value before using the TextPainter."
            )
        }

        let paintOffsetAlignment = TextPainter._computePaintOffsetFraction(textAlign, textDirection)
        // Try to avoid laying out the paragraph with maxWidth=infinity
        // when the text is not left-aligned, so we don't have to deal with an
        // infinite paint offset.
        let adjustMaxWidth = !maxWidth.isFinite && paintOffsetAlignment != 0
        let adjustedMaxWidth: Double? = !adjustMaxWidth
            ? maxWidth
            : cachedLayout?.layout.maxIntrinsicLineExtent
        let layoutMaxWidth = adjustedMaxWidth ?? maxWidth

        // Only rebuild the paragraph when there're layout changes.
        let paragraph = cachedLayout?.paragraph ?? _createParagraph(text)
        paragraph.layout(ParagraphConstraints(width: layoutMaxWidth))
        let textLayout = TextLayout(paragraph, textDirection, self)
        let contentWidth = textLayout._contentWidthFor(minWidth, maxWidth, textWidthBasis)

        let newLayoutCache: TextPainterLayoutCacheWithOffset
        // Call layout again if newLayoutCache had an infinite paint offset.
        if adjustedMaxWidth == nil && minWidth.isFinite {
            assert(maxWidth.isInfinite)
            let newInputWidth = textLayout.maxIntrinsicLineExtent
            paragraph.layout(ParagraphConstraints(width: newInputWidth))
            newLayoutCache = TextPainterLayoutCacheWithOffset(
                textLayout,
                paintOffsetAlignment,
                newInputWidth,
                contentWidth
            )
        } else {
            newLayoutCache = TextPainterLayoutCacheWithOffset(
                textLayout,
                paintOffsetAlignment,
                layoutMaxWidth,
                contentWidth
            )
        }
        _layoutCache = newLayoutCache
    }

    // MARK: - Paint

    /// Causes the paragraph to paint the layout boxes of the text.
    ///
    /// The `paint` method reads this flag only in debug mode.
    ///
    /// **Dart Source:** `text_painter.dart:1308`
    public var debugPaintTextLayoutBoxes = false

    /// Paints the text onto the given canvas at the given offset.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1322-1358`
    public func paint(_ canvas: any Canvas, _ offset: Offset) {
        guard let layoutCache = _layoutCache else {
            preconditionFailure(
                "TextPainter.paint called when text geometry was not yet calculated.\n"
                + "Please call layout() before paint() to position the text before painting it."
            )
        }

        if !layoutCache.paintOffset.dx.isFinite || !layoutCache.paintOffset.dy.isFinite {
            return
        }

        if _rebuildParagraphForPaint {
            let paragraph = layoutCache.paragraph
            assert(!layoutCache.layoutMaxWidth.isNaN)
            let newParagraph = _createParagraph(text!)
            newParagraph.layout(ParagraphConstraints(width: layoutCache.layoutMaxWidth))
            layoutCache.layout._paragraph = newParagraph
            assert(paragraph.width == layoutCache.layout._paragraph.width)
            paragraph.dispose()
        }
        assert(!_rebuildParagraphForPaint)

        canvas.drawParagraph(
            layoutCache.paragraph,
            Offset(offset.dx + layoutCache.paintOffset.dx, offset.dy + layoutCache.paintOffset.dy)
        )
    }

    // MARK: - Caret Methods

    /// Returns the closest offset after `offset` at which the input cursor can be
    /// positioned.
    ///
    /// **Dart Source:** `text_painter.dart:1412-1419`
    public func getOffsetAfter(_ offset: Int) -> Int? {
        guard let nextCodeUnit = _text!.codeUnitAt(offset) else {
            return nil
        }
        return TextPainter.isHighSurrogate(nextCodeUnit) ? offset + 2 : offset + 1
    }

    /// Returns the closest offset before `offset` at which the input cursor can
    /// be positioned.
    ///
    /// **Dart Source:** `text_painter.dart:1423-1430`
    public func getOffsetBefore(_ offset: Int) -> Int? {
        guard let prevCodeUnit = _text!.codeUnitAt(offset - 1) else {
            return nil
        }
        return TextPainter.isLowSurrogate(prevCodeUnit) ? offset - 2 : offset - 1
    }

    /// Returns the offset at which to paint the caret.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1447-1480`
    public func getOffsetForCaret(_ position: TextPosition, _ caretPrototype: Rect) -> Offset {
        let layoutCache = _layoutCache!
        let caretMetrics = _computeCaretMetrics(position)

        if caretMetrics == nil {
            let paintOffsetAlignment = TextPainter._computePaintOffsetFraction(
                textAlign, textDirection!
            )
            let dx = paintOffsetAlignment == 0
                ? 0.0
                : paintOffsetAlignment * layoutCache.contentWidth
            return Offset(dx, 0.0)
        }

        let metrics = caretMetrics!
        let rawOffset: Offset
        switch metrics.writingDirection {
        case .ltr:
            rawOffset = metrics.offset
        case .rtl:
            rawOffset = Offset(metrics.offset.dx - caretPrototype.width, metrics.offset.dy)
        @unknown default:
            rawOffset = metrics.offset
        }

        let adjustedDx = clampDouble(
            rawOffset.dx + layoutCache.paintOffset.dx,
            0,
            layoutCache.contentWidth
        )
        return Offset(adjustedDx, rawOffset.dy + layoutCache.paintOffset.dy)
    }

    /// Whether strut is disabled.
    private var _strutDisabled: Bool {
        guard let strutStyle = strutStyle else { return true }
        if strutStyle == StrutStyle.disabled { return true }
        if let fontSize = strutStyle.fontSize, fontSize == 0.0 { return true }
        return false
    }

    /// Returns the strut bounded height of the glyph at the given `position`.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1496-1507`
    public func getFullHeightForCaret(_ position: TextPosition, _ caretPrototype: Rect) -> Double {
        if _strutDisabled {
            if let heightFromCaretMetrics = _computeCaretMetrics(position)?.height {
                return heightFromCaretMetrics
            }
        }
        let textBox = _getOrCreateLayoutTemplate()
            .getBoxesForRange(0, 1, boxHeightStyle: .strut)
            .first!
        return textBox.toRect().height
    }

    private func _isNewlineAtOffset(_ offset: Int) -> Bool {
        guard offset >= 0 else { return false }
        let text = plainText
        let utf16 = Array(text.utf16)
        guard offset < utf16.count else { return false }
        return WordBoundary._isNewline(Int(utf16[offset]))
    }

    // Cached caret metrics.
    private var _caretMetrics: LineCaretMetrics?

    /// This function returns the caret's offset and height for the given
    /// `position` in the text, or nil if the paragraph is empty.
    ///
    /// **Dart Source:** `text_painter.dart:1560-1638`
    private func _computeCaretMetrics(_ position: TextPosition) -> LineCaretMetrics? {
        let cachedLayout = _layoutCache!
        if cachedLayout.paragraph.numberOfLines < 1 {
            return nil
        }

        let offset: Int
        let anchorToLeadingEdge: Bool

        if position.offset == 0 {
            // As a special case, always anchor to the leading edge of the first
            // grapheme regardless of the affinity.
            offset = 0
            anchorToLeadingEdge = true
        } else if position.affinity == .downstream {
            offset = position.offset
            anchorToLeadingEdge = true
        } else {
            // upstream
            if _isNewlineAtOffset(position.offset - 1) {
                offset = position.offset
                anchorToLeadingEdge = true
            } else {
                offset = position.offset - 1
                anchorToLeadingEdge = false
            }
        }

        let caretPositionCacheKey = anchorToLeadingEdge ? offset : -offset - 1
        if caretPositionCacheKey == cachedLayout._previousCaretPositionKey {
            return _caretMetrics
        }

        let glyphInfo = cachedLayout.paragraph.getGlyphInfoAt(offset)

        if glyphInfo == nil {
            let template = _getOrCreateLayoutTemplate()
            assert(template.numberOfLines == 1)
            let baselineOffset = template.getLineMetricsAt(0)!.baseline
            return cachedLayout.layout._endOfTextCaretMetrics.shift(Offset(0.0, -baselineOffset))
        }

        let graphemeRange = glyphInfo!.graphemeClusterCodeUnitRange

        // Works around a SkParagraph bug: placeholders with a size of (0, 0)
        // always have a rect of Rect.zero and a range of (0, 0).
        if graphemeRange.isCollapsed {
            assert(graphemeRange.start == 0)
            return _computeCaretMetrics(TextPosition(offset: offset + 1))
        }
        if anchorToLeadingEdge && graphemeRange.start != offset {
            assert(graphemeRange.end > graphemeRange.start + 1)
            return _computeCaretMetrics(TextPosition(offset: graphemeRange.end))
        }

        let boxes = cachedLayout.paragraph.getBoxesForRange(
            graphemeRange.start,
            graphemeRange.end,
            boxHeightStyle: .strut
        )

        let anchorToLeft: Bool
        switch glyphInfo!.writingDirection {
        case .ltr:
            anchorToLeft = anchorToLeadingEdge
        case .rtl:
            anchorToLeft = !anchorToLeadingEdge
        @unknown default:
            anchorToLeft = anchorToLeadingEdge
        }

        let box = anchorToLeft ? boxes.first! : boxes.last!
        let metrics = LineCaretMetrics(
            offset: Offset(anchorToLeft ? box.left : box.right, box.top),
            writingDirection: box.direction,
            height: box.bottom - box.top
        )

        cachedLayout._previousCaretPositionKey = caretPositionCacheKey
        _caretMetrics = metrics
        return metrics
    }

    // MARK: - Selection and Position

    /// Returns a list of rects that bound the given selection.
    ///
    /// **Dart Source:** `text_painter.dart:1658-1680`
    public func getBoxesForSelection(
        _ selection: TextSelection,
        boxHeightStyle: BoxHeightStyle = .tight,
        boxWidthStyle: BoxWidthStyle = .tight
    ) -> [TextBox] {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        assert(selection.isValid)
        let cachedLayout = _layoutCache!
        let offset = cachedLayout.paintOffset
        if !offset.dx.isFinite || !offset.dy.isFinite {
            return []
        }
        let boxes = cachedLayout.paragraph.getBoxesForRange(
            selection.start,
            selection.end,
            boxHeightStyle: boxHeightStyle,
            boxWidthStyle: boxWidthStyle
        )
        if offset == Offset.zero {
            return boxes
        }
        return boxes.map { TextPainter._shiftTextBox($0, offset) }
    }

    /// Returns the `GlyphInfo` of the glyph closest to the given `offset` in the
    /// paragraph coordinate system, or nil if the text is empty, or is entirely
    /// clipped or ellipsized away.
    ///
    /// **Dart Source:** `text_painter.dart:1688-1703`
    public func getClosestGlyphForOffset(_ offset: Offset) -> GlyphInfo? {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        let cachedLayout = _layoutCache!
        let rawGlyphInfo = cachedLayout.paragraph.getClosestGlyphInfoForOffset(
            Offset(offset.dx - cachedLayout.paintOffset.dx, offset.dy - cachedLayout.paintOffset.dy)
        )
        guard let rawGlyphInfo = rawGlyphInfo else { return nil }
        if cachedLayout.paintOffset == Offset.zero {
            return rawGlyphInfo
        }
        return GlyphInfo(
            rawGlyphInfo.graphemeClusterLayoutBounds.shift(cachedLayout.paintOffset),
            rawGlyphInfo.graphemeClusterCodeUnitRange,
            rawGlyphInfo.writingDirection
        )
    }

    /// Returns the closest position within the text for the given pixel offset.
    ///
    /// **Dart Source:** `text_painter.dart:1706-1711`
    public func getPositionForOffset(_ offset: Offset) -> TextPosition {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        let cachedLayout = _layoutCache!
        return cachedLayout.paragraph.getPositionForOffset(
            Offset(offset.dx - cachedLayout.paintOffset.dx, offset.dy - cachedLayout.paintOffset.dy)
        )
    }

    // MARK: - Word and Line Boundaries

    /// Returns the text range of the word at the given offset.
    ///
    /// **Dart Source:** `text_painter.dart:1722-1725`
    public func getWordBoundary(_ position: TextPosition) -> TextRange {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return _layoutCache!.paragraph.getWordBoundary(position)
    }

    /// Returns a `TextBoundary` that can be used to perform word boundary analysis
    /// on the current `text`.
    ///
    /// Currently word boundary analysis can only be performed after `layout`
    /// has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1737`
    public var wordBoundaries: WordBoundary {
        return WordBoundary(text!, _layoutCache!.paragraph)
    }

    /// Returns the text range of the line at the given offset.
    ///
    /// The newline (if any) is not returned as part of the range.
    ///
    /// **Dart Source:** `text_painter.dart:1742-1745`
    public func getLineBoundary(_ position: TextPosition) -> TextRange {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        return _layoutCache!.paragraph.getLineBoundary(position)
    }

    // MARK: - Line Metrics

    private static func _shiftLineMetrics(_ metrics: LineMetrics, _ offset: Offset) -> LineMetrics {
        assert(offset.dx.isFinite)
        assert(offset.dy.isFinite)
        return LineMetrics(
            hardBreak: metrics.hardBreak,
            ascent: metrics.ascent,
            descent: metrics.descent,
            unscaledAscent: metrics.unscaledAscent,
            height: metrics.height,
            width: metrics.width,
            left: metrics.left + offset.dx,
            baseline: metrics.baseline + offset.dy,
            lineNumber: metrics.lineNumber
        )
    }

    private static func _shiftTextBox(_ box: TextBox, _ offset: Offset) -> TextBox {
        assert(offset.dx.isFinite)
        assert(offset.dy.isFinite)
        return TextBox(
            fromLTRBD: box.left + offset.dx,
            box.top + offset.dy,
            box.right + offset.dx,
            box.bottom + offset.dy,
            box.direction
        )
    }

    /// Returns the full list of `LineMetrics` that describe in detail the various
    /// metrics of each laid out line.
    ///
    /// Valid only after `layout` has been called.
    ///
    /// **Dart Source:** `text_painter.dart:1786-1800`
    public func computeLineMetrics() -> [LineMetrics] {
        assert(_layoutCache != nil, "Text layout not available. Call layout() first.")
        let layoutCache = _layoutCache!
        let offset = layoutCache.paintOffset
        if !offset.dx.isFinite || !offset.dy.isFinite {
            return []
        }
        let rawMetrics = layoutCache.lineMetrics
        if offset == Offset.zero {
            return rawMetrics
        }
        return rawMetrics.map { TextPainter._shiftLineMetrics($0, offset) }
    }

    // MARK: - Dispose

    private var _disposed = false

    /// Whether this object has been disposed or not.
    ///
    /// Only for use when asserts are enabled.
    ///
    /// **Dart Source:** `text_painter.dart:1807-1813`
    public var debugDisposed: Bool {
        return _disposed
    }

    /// Releases the resources associated with this painter.
    ///
    /// After disposal this painter is unusable.
    ///
    /// **Dart Source:** `text_painter.dart:1819-1831`
    public func dispose() {
        assert(!_disposed, "TextPainter.dispose called more than once.")
        _disposed = true
        _layoutTemplate?.dispose()
        _layoutTemplate = nil
        _layoutCache?.paragraph.dispose()
        _layoutCache = nil
        _text = nil
    }
}
