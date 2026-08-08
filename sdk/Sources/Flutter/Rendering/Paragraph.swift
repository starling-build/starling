// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Render object for displaying paragraphs of text.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/paragraph.dart`

import FlutterSwiftBridge
import Glibc

// MARK: - Constants

/// The ellipsis character used for text overflow.
private let kEllipsis = "\u{2026}"

// MARK: - Type Aliases

/// The start and end positions for a text boundary.
///
/// **Dart Source:** `paragraph.dart:36`
public typealias TextBoundaryRecord = (boundaryStart: TextPosition, boundaryEnd: TextPosition)

/// Signature for a function that determines the `TextBoundaryRecord` at the given
/// `TextPosition`.
///
/// **Dart Source:** `paragraph.dart:40`
public typealias TextBoundaryAtPosition = (_ position: TextPosition) -> TextBoundaryRecord

/// Signature for a function that determines the `TextBoundaryRecord` at the given
/// `TextPosition`, for the given `String`.
///
/// **Dart Source:** `paragraph.dart:44-45`
public typealias TextBoundaryAtPositionInText = (
    _ position: TextPosition, _ text: String
) -> TextBoundaryRecord

// MARK: - Text Boundary Stubs

/// A text boundary based on character boundaries.
///
/// Stub for `CharacterBoundary` from Dart's `services` library.
///
/// **Dart Source:** `services/text_boundary.dart`
public final class CharacterBoundary: TextBoundary {
    private let _text: String

    public init(_ text: String) {
        _text = text
    }

    public func getTextBoundaryAt(_ position: Int) -> TextRange {
        let start = max(0, position)
        let end = min(_text.count, position + 1)
        return TextRange(start: start, end: end)
    }

    public func getLeadingTextBoundaryAt(_ position: Int) -> Int? {
        if position < 0 { return nil }
        if position >= _text.count { return nil }
        return position
    }

    public func getTrailingTextBoundaryAt(_ position: Int) -> Int? {
        if position < 0 { return 0 }
        if position >= _text.count { return nil }
        return position + 1
    }
}

/// A text boundary based on paragraph (line separator) boundaries.
///
/// Stub for `ParagraphBoundary` from Dart's `services` library.
///
/// **Dart Source:** `services/text_boundary.dart`
public final class ParagraphBoundary: TextBoundary {
    private let _text: String

    public init(_ text: String) {
        _text = text
    }

    public func getTextBoundaryAt(_ position: Int) -> TextRange {
        let start = getLeadingTextBoundaryAt(position) ?? 0
        let end = getTrailingTextBoundaryAt(position) ?? _text.count
        return TextRange(start: start, end: end)
    }

    public func getLeadingTextBoundaryAt(_ position: Int) -> Int? {
        guard position >= 0 && position < _text.count else {
            return position < 0 ? nil : _text.count
        }
        // Find the start of the paragraph by searching backwards for a newline
        let scalars = Array(_text.unicodeScalars)
        var i = position
        while i > 0 {
            if scalars[i - 1] == "\n" {
                return i
            }
            i -= 1
        }
        return 0
    }

    public func getTrailingTextBoundaryAt(_ position: Int) -> Int? {
        guard position >= 0 else { return 0 }
        let scalars = Array(_text.unicodeScalars)
        guard position < scalars.count else { return nil }
        var i = position
        while i < scalars.count {
            if scalars[i] == "\n" {
                return i + 1
            }
            i += 1
        }
        return scalars.count
    }
}

/// A text boundary that treats the entire document as a single boundary.
///
/// Stub for `DocumentBoundary` from Dart's `services` library.
///
/// **Dart Source:** `services/text_boundary.dart`
public final class DocumentBoundary: TextBoundary {
    private let _text: String

    public init(_ text: String) {
        _text = text
    }

    public func getTextBoundaryAt(_ position: Int) -> TextRange {
        return TextRange(start: 0, end: _text.count)
    }

    public func getLeadingTextBoundaryAt(_ position: Int) -> Int? {
        return 0
    }

    public func getTrailingTextBoundaryAt(_ position: Int) -> Int? {
        return _text.count
    }
}

/// A text boundary based on line breaks as reported by `TextLayoutMetrics`.
///
/// Stub for `LineBoundary` from Dart's `services` library.
///
/// **Dart Source:** `services/text_boundary.dart`
public final class LineBoundary: TextBoundary {
    private let _metrics: any TextLayoutMetrics

    public init(_ metrics: any TextLayoutMetrics) {
        _metrics = metrics
    }

    public func getTextBoundaryAt(_ position: Int) -> TextRange {
        let line = _metrics.getLineAtOffset(TextPosition(offset: position))
        return TextRange(start: line.baseOffset, end: line.extentOffset)
    }

    public func getLeadingTextBoundaryAt(_ position: Int) -> Int? {
        let line = _metrics.getLineAtOffset(TextPosition(offset: position))
        return line.baseOffset
    }

    public func getTrailingTextBoundaryAt(_ position: Int) -> Int? {
        let line = _metrics.getLineAtOffset(TextPosition(offset: position))
        return line.extentOffset
    }
}

// MARK: - TextLayoutMetrics Protocol

/// Defines the interface for text layout measurements.
///
/// **Dart Source:** `services/text_layout_metrics.dart`
public protocol TextLayoutMetrics: AnyObject {
    /// Returns the `TextSelection` for the line at the given `TextPosition`.
    func getLineAtOffset(_ position: TextPosition) -> TextSelection

    /// Returns the `TextPosition` above the given position.
    func getTextPositionAbove(_ position: TextPosition) -> TextPosition

    /// Returns the `TextPosition` below the given position.
    func getTextPositionBelow(_ position: TextPosition) -> TextPosition

    /// Returns the `TextRange` for the word at the given `TextPosition`.
    func getWordBoundary(_ position: TextPosition) -> TextRange
}

// MARK: - SelectionPoint (private enum)

/// Identifies a selection edge (start or end).
///
/// **Dart Source:** `paragraph.dart` (private `_SelectionPoint` enum)
private enum SelectionPointType {
    case start
    case end
}

// MARK: - PlaceholderSpanIndexSemanticsTag

/// Used by the `RenderParagraph` to map its rendering children to their
/// corresponding semantics nodes.
///
/// The `RichText` uses this to tag the relation between its placeholder spans
/// and their semantics nodes.
///
/// In Dart, this extends `SemanticsTag`. Since `SemanticsTag` is final in Swift,
/// this uses composition instead of inheritance.
///
/// **Dart Source:** `paragraph.dart:55-73`
public struct PlaceholderSpanIndexSemanticsTag: Hashable, CustomStringConvertible {
    /// The index of this tag.
    ///
    /// **Dart Source:** `paragraph.dart:64`
    public let index: Int

    /// The underlying semantics tag.
    public let tag: SemanticsTag

    /// Creates a semantics tag with the input `index`.
    ///
    /// Different `PlaceholderSpanIndexSemanticsTag`s with the same `index` are
    /// considered the same.
    ///
    /// **Dart Source:** `paragraph.dart:60-61`
    public init(_ index: Int) {
        self.index = index
        self.tag = SemanticsTag("PlaceholderSpanIndexSemanticsTag(\(index))")
    }

    public static func == (
        lhs: PlaceholderSpanIndexSemanticsTag,
        rhs: PlaceholderSpanIndexSemanticsTag
    ) -> Bool {
        return lhs.index == rhs.index
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(index)
    }

    public var description: String {
        "PlaceholderSpanIndexSemanticsTag(\(index))"
    }
}

// MARK: - TextParentData

/// Parent data used by `RenderParagraph` and `RenderEditable` to annotate
/// inline contents (such as `WidgetSpan`s) with.
///
/// **Dart Source:** `paragraph.dart:77-101`
public class TextParentData: ContainerBoxParentData<RenderBox> {
    /// The offset at which to paint the child in the parent's coordinate system.
    ///
    /// A `nil` value indicates this inline widget is not laid out. For instance,
    /// when the inline widget has never been laid out, or the inline widget is
    /// ellipsized away.
    ///
    /// **Dart Source:** `paragraph.dart:83-84`
    public var textOffset: Offset? {
        get { _offset }
    }
    internal var _offset: Offset?

    /// The `PlaceholderSpan` associated with this render child.
    ///
    /// This field is usually set by a `ParentDataWidget`, and is typically not
    /// nil when `performLayout` is called.
    ///
    /// **Dart Source:** `paragraph.dart:90`
    public var span: PlaceholderSpan?

    /// **Dart Source:** `paragraph.dart:93-97`
    public override func detach() {
        span = nil
        _offset = nil
        super.detach()
    }

    /// **Dart Source:** `paragraph.dart:99-100`
    public override var description: String {
        "widget: \(span.map { "\($0)" } ?? "nil"), \(_offset == nil ? "not laid out" : "offset: \(_offset!)")"
    }
}

// MARK: - RenderInlineChildrenContainerDefaults

/// A mixin that provides useful default behaviors for text `RenderBox`es
/// (`RenderParagraph` and `RenderEditable` for example) with inline content
/// children managed by the `ContainerRenderObjectMixin` mixin.
///
/// This mixin assumes every child managed by the `ContainerRenderObjectMixin`
/// mixin corresponds to a `PlaceholderSpan`, and they are organized in logical
/// order of the text (the order each `PlaceholderSpan` is encountered when the
/// user reads the text).
///
/// In Swift, this is modeled as a protocol with default implementations that
/// RenderParagraph implements directly, since Swift does not support generic mixins.
///
/// **Dart Source:** `paragraph.dart:135-298`
public protocol RenderInlineChildrenContainerDefaults: AnyObject {
    var firstChild: RenderBox? { get }
    func childAfter(_ child: RenderBox) -> RenderBox?
    var childCount: Int { get }
    func setupParentData(_ child: RenderObject)
}

// MARK: - RenderParagraph

/// A render object that displays a paragraph of text.
///
/// **Dart Source:** `paragraph.dart:310-1434`
open class RenderParagraph: RenderBox {

    // MARK: - Static Properties

    /// The placeholder character used by inline widgets.
    ///
    /// **Dart Source:** `paragraph.dart:367-369`
    fileprivate static let _placeholderCharacter: String = String(
        Character(UnicodeScalar(PlaceholderSpan.placeholderCodeUnit)!)
    )

    // MARK: - Initialization

    /// Creates a paragraph render object.
    ///
    /// The `maxLines` property may be nil (and indeed defaults to nil), but if
    /// it is not nil, it must be greater than zero.
    ///
    /// **Dart Source:** `paragraph.dart:319-365`
    public init(
        text: InlineSpan,
        textAlign: TextAlign = .start,
        textDirection: TextDirection,
        softWrap: Bool = true,
        overflow: TextOverflow = .clip,
        textScaler: (any TextScaler)? = nil,
        maxLines: Int? = nil,
        locale: Locale? = nil,
        strutStyle: StrutStyle? = nil,
        textWidthBasis: TextWidthBasis = .parent,
        textHeightBehavior: TextHeightBehavior? = nil,
        children: [RenderBox]? = nil,
        selectionColor: Color? = nil,
        registrar: SelectionRegistrar? = nil
    ) {
        assert(text.debugAssertIsValid())
        assert(maxLines == nil || maxLines! > 0)
        _softWrap = softWrap
        _overflow = overflow
        _selectionColor = selectionColor
        if let e = getenv("STARLING_TEXT_DEBUG"), (e.pointee == 49 || e.pointee == 50) {
            let msg = "[RP-init]\n"
            _ = msg.withCString { write(2, $0, strlen($0)) }
        }
        _textPainter = TextPainter(
            text: text,
            textAlign: textAlign,
            textDirection: textDirection,
            textScaler: textScaler ?? TextScalers.noScaling,
            maxLines: maxLines,
            ellipsis: overflow == .ellipsis ? kEllipsis : nil,
            locale: locale,
            strutStyle: strutStyle,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior
        )
        super.init()
        if let children = children {
            addAll(children)
        }
        self.registrar = registrar
    }

    // MARK: - Private Properties

    /// The text painter responsible for layout and rendering.
    ///
    /// **Dart Source:** `paragraph.dart:371`
    fileprivate let _textPainter: TextPainter

    /// Cached intrinsics text painter to avoid destroying layout state.
    ///
    /// **Dart Source:** `paragraph.dart:379-392`
    private var _textIntrinsicsCache: TextPainter?
    private var _textIntrinsics: TextPainter {
        let cache = _textIntrinsicsCache ?? TextPainter()
        _textIntrinsicsCache = cache
        cache.text = _textPainter.text
        cache.textAlign = _textPainter.textAlign
        cache.textDirection = _textPainter.textDirection
        cache.textScaler = _textPainter.textScaler
        cache.maxLines = _textPainter.maxLines
        cache.ellipsis = _textPainter.ellipsis
        cache.locale = _textPainter.locale
        cache.strutStyle = _textPainter.strutStyle
        cache.textWidthBasis = _textPainter.textWidthBasis
        cache.textHeightBehavior = _textPainter.textHeightBehavior
        return cache
    }

    /// Cached attributed labels for semantics.
    ///
    /// **Dart Source:** `paragraph.dart:394`
    private var _cachedAttributedLabels: [AttributedString]?

    /// Cached combined semantics info.
    ///
    /// **Dart Source:** `paragraph.dart:396`
    private var _cachedCombinedSemanticsInfos: [InlineSpanSemanticsInformation]?

    // MARK: - Child Management (ContainerRenderObjectMixin pattern)

    /// The first child in the child list.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public private(set) var firstChild: RenderBox?

    /// The last child in the child list.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public private(set) var lastChild: RenderBox?

    /// The number of children.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public private(set) var childCount: Int = 0

    /// Returns the child after the given child, or nil.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public func childAfter(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as? TextParentData
        return parentData?.nextSibling
    }

    /// Returns the child before the given child, or nil.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public func childBefore(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as? TextParentData
        return parentData?.previousSibling
    }

    /// Sets up parent data for a child.
    ///
    /// **Dart Source:** `paragraph.dart:138-142`
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is TextParentData) {
            child.parentData = TextParentData()
        }
    }

    /// Inserts a child at the given position.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public func insert(_ child: RenderBox, after: RenderBox? = nil) {
        adoptChild(child)
        childCount += 1
        let childParentData = child.parentData as! TextParentData
        if let after = after {
            let afterParentData = after.parentData as! TextParentData
            childParentData.previousSibling = after
            childParentData.nextSibling = afterParentData.nextSibling
            if let next = afterParentData.nextSibling {
                let nextParentData = next.parentData as! TextParentData
                nextParentData.previousSibling = child
            }
            afterParentData.nextSibling = child
            if after === lastChild {
                lastChild = child
            }
        } else {
            // Insert at the beginning
            childParentData.nextSibling = firstChild
            if let first = firstChild {
                let firstParentData = first.parentData as! TextParentData
                firstParentData.previousSibling = child
            }
            firstChild = child
            lastChild = lastChild ?? child
        }
    }

    /// Adds all children from the list.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public func addAll(_ children: [RenderBox]) {
        for child in children {
            insert(child, after: lastChild)
        }
    }

    /// Removes a child from the child list.
    ///
    /// **Dart Source:** via `ContainerRenderObjectMixin`
    public func remove(_ child: RenderBox) {
        let childParentData = child.parentData as! TextParentData
        if childParentData.previousSibling != nil {
            let prev = childParentData.previousSibling!
            let prevParentData = prev.parentData as! TextParentData
            prevParentData.nextSibling = childParentData.nextSibling
        } else {
            firstChild = childParentData.nextSibling
        }
        if childParentData.nextSibling != nil {
            let next = childParentData.nextSibling!
            let nextParentData = next.parentData as! TextParentData
            nextParentData.previousSibling = childParentData.previousSibling
        } else {
            lastChild = childParentData.previousSibling
        }
        childParentData.previousSibling = nil
        childParentData.nextSibling = nil
        childCount -= 1
        dropChild(child)
    }

    // MARK: - Text Property

    /// The text to display.
    ///
    /// **Dart Source:** `paragraph.dart:399-424`
    public var text: InlineSpan {
        get { _textPainter.text! }
        set {
            let _cmp = _textPainter.text!.compareTo(newValue)
            if let e = getenv("STARLING_TEXT_DEBUG"), e.pointee == 50 {
                let old = (_textPainter.text as? TextSpan)?.text ?? "<span>"
                let new = (newValue as? TextSpan)?.text ?? "<span>"
                let msg = "[RenderParagraph] set cmp=\(_cmp) " +
                    "old='\(old.prefix(26))' new='\(new.prefix(26))'\n"
                _ = msg.withCString { write(2, $0, strlen($0)) }
            } else if let e = getenv("STARLING_TEXT_DEBUG"), (e.pointee == 49 || e.pointee == 50) {
                let msg = "[RenderParagraph] set cmp=\(_cmp)\n"
                _ = msg.withCString { write(2, $0, strlen($0)) }
            }
            switch _cmp {
            case .identical:
                return
            case .metadata:
                _textPainter.text = newValue
                _cachedCombinedSemanticsInfos = nil
                markNeedsSemanticsUpdate()
            case .paint:
                _textPainter.text = newValue
                _cachedAttributedLabels = nil
                _cachedCombinedSemanticsInfos = nil
                markNeedsPaint()
                markNeedsSemanticsUpdate()
            case .layout:
                _textPainter.text = newValue
                _overflowShader = nil
                _cachedAttributedLabels = nil
                _cachedCombinedSemanticsInfos = nil
                markNeedsLayout()
                _removeSelectionRegistrarSubscription()
                _disposeSelectableFragments()
                _updateSelectionRegistrarSubscription()
            }
        }
    }

    // MARK: - Selection Support

    /// The ongoing selections in this paragraph.
    ///
    /// The selection does not include selections in `PlaceholderSpan` if there
    /// are any.
    ///
    /// **Dart Source:** `paragraph.dart:431-447`
    public var selections: [TextSelection] {
        guard let fragments = _lastSelectableFragments else {
            return []
        }
        var results: [TextSelection] = []
        for fragment in fragments {
            if let start = fragment._textSelectionStart,
               let end = fragment._textSelectionEnd
            {
                results.append(
                    TextSelection(baseOffset: start.offset, extentOffset: end.offset)
                )
            }
        }
        return results
    }

    /// Fragments for selection handling.
    ///
    /// Should be nil if selection is not enabled, i.e. `_registrar == nil`. The
    /// paragraph splits on `PlaceholderSpan.placeholderCodeUnit`, and stores each
    /// fragment in this list.
    ///
    /// **Dart Source:** `paragraph.dart:452`
    fileprivate var _lastSelectableFragments: [SelectableFragment]?

    /// The `SelectionRegistrar` this paragraph will be, or is, registered to.
    ///
    /// **Dart Source:** `paragraph.dart:455-465`
    public var registrar: SelectionRegistrar? {
        get { _registrar }
        set {
            if newValue as AnyObject? === _registrar as AnyObject? {
                return
            }
            _removeSelectionRegistrarSubscription()
            _disposeSelectableFragments()
            _registrar = newValue
            _updateSelectionRegistrarSubscription()
        }
    }
    private var _registrar: SelectionRegistrar?

    /// **Dart Source:** `paragraph.dart:467-476`
    private func _updateSelectionRegistrarSubscription() {
        guard let registrar = _registrar else { return }
        if _lastSelectableFragments == nil {
            _lastSelectableFragments = _getSelectableFragments()
        }
        for fragment in _lastSelectableFragments! {
            registrar.add(fragment)
        }
        if !_lastSelectableFragments!.isEmpty {
            markNeedsCompositingBitsUpdate()
        }
    }

    /// **Dart Source:** `paragraph.dart:478-483`
    private func _removeSelectionRegistrarSubscription() {
        guard let registrar = _registrar, let fragments = _lastSelectableFragments else { return }
        for fragment in fragments {
            registrar.remove(fragment)
        }
    }

    /// **Dart Source:** `paragraph.dart:485-507`
    private func _getSelectableFragments() -> [SelectableFragment] {
        let plainText = text.toPlainText(includeSemanticsLabels: false)
        var result: [SelectableFragment] = []
        var start = 0
        let chars = Array(plainText)
        let placeholderChar = Character(UnicodeScalar(PlaceholderSpan.placeholderCodeUnit)!)
        while start < chars.count {
            var end = start
            while end < chars.count && chars[end] != placeholderChar {
                end += 1
            }
            if start != end {
                result.append(
                    SelectableFragment(
                        paragraph: self,
                        fullText: plainText,
                        range: TextRange(start: start, end: end)
                    )
                )
            }
            start = end + 1
        }
        return result
    }

    /// Determines whether the given `Selectable` was created by this
    /// `RenderParagraph`.
    ///
    /// **Dart Source:** `paragraph.dart:514-519`
    public func selectableBelongsToParagraph(_ selectable: any Selectable) -> Bool {
        guard let fragments = _lastSelectableFragments else { return false }
        for fragment in fragments {
            if fragment === selectable as AnyObject {
                return true
            }
        }
        return false
    }

    /// **Dart Source:** `paragraph.dart:521-529`
    private func _disposeSelectableFragments() {
        guard let fragments = _lastSelectableFragments else { return }
        for fragment in fragments {
            fragment.dispose()
        }
        _lastSelectableFragments = nil
    }

    /// Whether this render object always needs compositing.
    ///
    /// **Dart Source:** `paragraph.dart:532`
    open override var alwaysNeedsCompositing: Bool {
        _lastSelectableFragments?.isEmpty == false
    }

    /// **Dart Source:** `paragraph.dart:535-539`
    open override func markNeedsLayout() {
        _lastSelectableFragments?.forEach { $0.didChangeParagraphLayout() }
        super.markNeedsLayout()
    }

    /// **Dart Source:** `paragraph.dart:542-549`
    open override func dispose() {
        _removeSelectionRegistrarSubscription()
        _disposeSelectableFragments()
        _textPainter.dispose()
        _textIntrinsicsCache?.dispose()
        super.dispose()
    }

    // MARK: - Text Properties

    /// How the text should be aligned horizontally.
    ///
    /// **Dart Source:** `paragraph.dart:552-559`
    public var textAlign: TextAlign {
        get { _textPainter.textAlign }
        set {
            if _textPainter.textAlign == newValue { return }
            _textPainter.textAlign = newValue
            markNeedsPaint()
        }
    }

    /// The directionality of the text.
    ///
    /// **Dart Source:** `paragraph.dart:572-579`
    public var textDirection: TextDirection {
        get { _textPainter.textDirection! }
        set {
            if _textPainter.textDirection == newValue { return }
            _textPainter.textDirection = newValue
            markNeedsLayout()
        }
    }

    /// Whether the text should break at soft line breaks.
    ///
    /// **Dart Source:** `paragraph.dart:588-596`
    public var softWrap: Bool {
        get { _softWrap }
        set {
            if _softWrap == newValue { return }
            _softWrap = newValue
            markNeedsLayout()
        }
    }
    private var _softWrap: Bool

    /// How visual overflow should be handled.
    ///
    /// **Dart Source:** `paragraph.dart:599-608`
    public var overflow: TextOverflow {
        get { _overflow }
        set {
            if _overflow == newValue { return }
            _overflow = newValue
            _textPainter.ellipsis = newValue == .ellipsis ? kEllipsis : nil
            markNeedsLayout()
        }
    }
    private var _overflow: TextOverflow

    /// The text scaler used to scale the text.
    ///
    /// **Dart Source:** `paragraph.dart:633-641`
    public var textScaler: any TextScaler {
        get { _textPainter.textScaler }
        set {
            if _textPainter.textScaler == newValue { return }
            _textPainter.textScaler = newValue
            _overflowShader = nil
            markNeedsLayout()
        }
    }

    /// An optional maximum number of lines for the text to span, wrapping if
    /// necessary. If the text exceeds the given number of lines, it will be
    /// truncated according to `overflow` and `softWrap`.
    ///
    /// **Dart Source:** `paragraph.dart:646-658`
    public var maxLines: Int? {
        get { _textPainter.maxLines }
        set {
            assert(newValue == nil || newValue! > 0)
            if _textPainter.maxLines == newValue { return }
            _textPainter.maxLines = newValue
            _overflowShader = nil
            markNeedsLayout()
        }
    }

    /// Used by this paragraph's internal `TextPainter` to select a
    /// locale-specific font.
    ///
    /// **Dart Source:** `paragraph.dart:667-677`
    public var locale: Locale? {
        get { _textPainter.locale }
        set {
            if _textPainter.locale == newValue { return }
            _textPainter.locale = newValue
            _overflowShader = nil
            markNeedsLayout()
        }
    }

    /// The strut style to use.
    ///
    /// **Dart Source:** `paragraph.dart:680-690`
    public var strutStyle: StrutStyle? {
        get { _textPainter.strutStyle }
        set {
            if _textPainter.strutStyle == newValue { return }
            _textPainter.strutStyle = newValue
            _overflowShader = nil
            markNeedsLayout()
        }
    }

    /// The strategy for measuring the width of the text.
    ///
    /// **Dart Source:** `paragraph.dart:693-701`
    public var textWidthBasis: TextWidthBasis {
        get { _textPainter.textWidthBasis }
        set {
            if _textPainter.textWidthBasis == newValue { return }
            _textPainter.textWidthBasis = newValue
            _overflowShader = nil
            markNeedsLayout()
        }
    }

    /// Defines how the paragraph will apply `TextStyle.height` to the ascent of
    /// the first line and descent of the last line.
    ///
    /// **Dart Source:** `paragraph.dart:704-712`
    public var textHeightBehavior: TextHeightBehavior? {
        get { _textPainter.textHeightBehavior }
        set {
            if _textPainter.textHeightBehavior == newValue { return }
            _textPainter.textHeightBehavior = newValue
            _overflowShader = nil
            markNeedsLayout()
        }
    }

    /// The color to use when painting the selection.
    ///
    /// Ignored if the text is not selectable (e.g. if `registrar` is nil).
    ///
    /// **Dart Source:** `paragraph.dart:717-730`
    public var selectionColor: Color? {
        get { _selectionColor }
        set {
            if _selectionColor == newValue { return }
            _selectionColor = newValue
            if _lastSelectableFragments?.contains(where: { $0.value.hasSelection }) ?? false {
                markNeedsPaint()
            }
        }
    }
    private var _selectionColor: Color?

    // MARK: - Private Helpers

    /// **Dart Source:** `paragraph.dart:732-734`
    fileprivate func _getOffsetForPosition(_ position: TextPosition) -> Offset {
        return getOffsetForCaret(position, .zero)
            + Offset(0, getFullHeightForCaret(position))
    }

    // MARK: - Intrinsic Dimensions

    /// **Dart Source:** `paragraph.dart:737-748`
    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let placeholderDimensions = layoutInlineChildren(
            width: .infinity,
            layoutChild: { child, constraints in
                Size(child.getMinIntrinsicWidth(.infinity), 0.0)
            },
            getChildBaseline: ChildLayoutHelper.getDryBaseline
        )
        _textIntrinsics.setPlaceholderDimensions(placeholderDimensions)
        _textIntrinsics.layout()
        return _textIntrinsics.minIntrinsicWidth
    }

    /// **Dart Source:** `paragraph.dart:751-764`
    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let placeholderDimensions = layoutInlineChildren(
            width: .infinity,
            layoutChild: { child, constraints in
                Size(child.getMaxIntrinsicWidth(.infinity), 0.0)
            },
            getChildBaseline: ChildLayoutHelper.getDryBaseline
        )
        _textIntrinsics.setPlaceholderDimensions(placeholderDimensions)
        _textIntrinsics.layout()
        return _textIntrinsics.maxIntrinsicWidth
    }

    /// An estimate of the height of a line in the text.
    ///
    /// **Dart Source:** `paragraph.dart:770`
    public var preferredLineHeight: Double {
        _textPainter.preferredLineHeight
    }

    /// **Dart Source:** `paragraph.dart:772-783`
    private func _computeIntrinsicHeight(_ width: Double) -> Double {
        let dims = layoutInlineChildren(
            width: width,
            layoutChild: ChildLayoutHelper.dryLayoutChild,
            getChildBaseline: ChildLayoutHelper.getDryBaseline
        )
        _textIntrinsics.setPlaceholderDimensions(dims)
        _textIntrinsics.layout(minWidth: width, maxWidth: _adjustMaxWidth(width))
        return _textIntrinsics.height
    }

    /// **Dart Source:** `paragraph.dart:786-788`
    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        _computeIntrinsicHeight(width)
    }

    /// **Dart Source:** `paragraph.dart:791-793`
    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        _computeIntrinsicHeight(width)
    }

    // MARK: - Hit Testing

    /// **Dart Source:** `paragraph.dart:796`
    open override func hitTestSelf(_ position: Offset) -> Bool { true }

    /// **Dart Source:** `paragraph.dart:800-820`
    open override func hitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool {
        let glyph = _textPainter.getClosestGlyphForOffset(position)
        let spanHit: InlineSpan?
        if let glyph = glyph, glyph.graphemeClusterLayoutBounds.contains(position) {
            spanHit = _textPainter.text?.getSpanForPosition(
                TextPosition(offset: glyph.graphemeClusterCodeUnitRange.start)
            )
        } else {
            spanHit = nil
        }
        if let target = spanHit as? HitTestTarget {
            result.add(HitTestEntry(AnyHitTestTarget(target)))
            return true
        }
        return hitTestInlineChildren(result, position: position)
    }

    // MARK: - Overflow

    /// **Dart Source:** `paragraph.dart:822`
    private var _needsClipping = false

    /// **Dart Source:** `paragraph.dart:823`
    private var _overflowShader: Shader?

    /// Whether this paragraph currently has a `Shader` for its overflow effect.
    ///
    /// Used to test this object. Not for use in production.
    ///
    /// **Dart Source:** `paragraph.dart:830`
    public var debugHasOverflowShader: Bool { _overflowShader != nil }

    // MARK: - System Fonts

    /// **Dart Source:** `paragraph.dart:833-836`
    open func systemFontsDidChange() {
        _textPainter.markNeedsLayout()
    }

    // MARK: - Layout

    /// Placeholder dimensions representing the sizes of child inline widgets.
    ///
    /// **Dart Source:** `paragraph.dart:843`
    private var _placeholderDimensions: [PlaceholderDimensions]?

    /// **Dart Source:** `paragraph.dart:845-847`
    private func _adjustMaxWidth(_ maxWidth: Double) -> Double {
        softWrap || overflow == .ellipsis ? maxWidth : .infinity
    }

    /// **Dart Source:** `paragraph.dart:849-853`
    private func _layoutTextWithConstraints(_ constraints: BoxConstraints) {
        _textPainter.setPlaceholderDimensions(_placeholderDimensions)
        _textPainter.layout(
            minWidth: constraints.minWidth,
            maxWidth: _adjustMaxWidth(constraints.maxWidth)
        )
    }

    /// **Dart Source:** `paragraph.dart:857-873`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        let dims = layoutInlineChildren(
            width: constraints.maxWidth,
            layoutChild: ChildLayoutHelper.dryLayoutChild,
            getChildBaseline: ChildLayoutHelper.getDryBaseline
        )
        _textIntrinsics.setPlaceholderDimensions(dims)
        _textIntrinsics.layout(
            minWidth: constraints.minWidth,
            maxWidth: _adjustMaxWidth(constraints.maxWidth)
        )
        return constraints.constrain(_textIntrinsics.size)
    }

    /// **Dart Source:** `paragraph.dart:876-887`
    open override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        assert(!debugNeedsLayout)
        assert(boxConstraints.debugAssertIsValid())
        _layoutTextWithConstraints(boxConstraints)
        return _textPainter.computeDistanceToActualBaseline(.alphabetic)
    }

    /// **Dart Source:** `paragraph.dart:890-902`
    open override func computeDryBaseline(_ constraints: BoxConstraints, _ baseline: TextBaseline) -> Double? {
        assert(constraints.debugAssertIsValid())
        let dims = layoutInlineChildren(
            width: constraints.maxWidth,
            layoutChild: ChildLayoutHelper.dryLayoutChild,
            getChildBaseline: ChildLayoutHelper.getDryBaseline
        )
        _textIntrinsics.setPlaceholderDimensions(dims)
        _textIntrinsics.layout(
            minWidth: constraints.minWidth,
            maxWidth: _adjustMaxWidth(constraints.maxWidth)
        )
        return _textIntrinsics.computeDistanceToActualBaseline(.alphabetic)
    }

    /// **Dart Source:** `paragraph.dart:905-971`
    open override func performLayout() {
        _lastSelectableFragments?.forEach { $0.didChangeParagraphLayout() }
        let constraints = self.boxConstraints
        _placeholderDimensions = layoutInlineChildren(
            width: constraints.maxWidth,
            layoutChild: ChildLayoutHelper.layoutChild,
            getChildBaseline: ChildLayoutHelper.getBaseline
        )
        _layoutTextWithConstraints(constraints)
        if let boxes = _textPainter.inlinePlaceholderBoxes {
            positionInlineChildren(boxes)
        }

        let textSize = _textPainter.size
        size = constraints.constrain(textSize)

        let didOverflowHeight = size.height < textSize.height || _textPainter.didExceedMaxLines
        let didOverflowWidth = size.width < textSize.width
        let hasVisualOverflow = didOverflowWidth || didOverflowHeight
        if hasVisualOverflow {
            switch _overflow {
            case .visible:
                _needsClipping = false
                _overflowShader = nil
            case .clip, .ellipsis:
                _needsClipping = true
                _overflowShader = nil
            case .fade:
                _needsClipping = true
                let fadeSizePainter = TextPainter(
                    text: TextSpan(text: "\u{2026}", style: _textPainter.text?.style),
                    textDirection: textDirection,
                    textScaler: textScaler,
                    locale: locale
                )
                fadeSizePainter.layout()
                if didOverflowWidth {
                    let fadeStart: Double
                    let fadeEnd: Double
                    switch textDirection {
                    case .rtl:
                        fadeStart = fadeSizePainter.width
                        fadeEnd = 0.0
                    case .ltr:
                        fadeStart = size.width - fadeSizePainter.width
                        fadeEnd = size.width
                    }
                    _overflowShader = Gradient(
                        linear: Offset(fadeStart, 0.0),
                        to: Offset(fadeEnd, 0.0),
                        colors: [Color(0xFFFF_FFFF), Color(0x00FF_FFFF)]
                    )
                } else {
                    let fadeEnd = size.height
                    let fadeStart = fadeEnd - fadeSizePainter.height / 2.0
                    _overflowShader = Gradient(
                        linear: Offset(0.0, fadeStart),
                        to: Offset(0.0, fadeEnd),
                        colors: [Color(0xFFFF_FFFF), Color(0x00FF_FFFF)]
                    )
                }
                fadeSizePainter.dispose()
            }
        } else {
            _needsClipping = false
            _overflowShader = nil
        }
    }

    /// **Dart Source:** `paragraph.dart:974-976`
    open override func applyPaintTransform(_ child: RenderObject, _ transform: inout Matrix4) {
        defaultApplyPaintTransform(child as! RenderBox, &transform)
    }

    // MARK: - Painting

    /// **Dart Source:** `paragraph.dart:979-1029`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        _layoutTextWithConstraints(boxConstraints)

        if _needsClipping {
            let bounds = offset & size
            if _overflowShader != nil {
                context.canvas.saveLayer(bounds, Paint())
            } else {
                context.canvas.save()
            }
            context.canvas.clipRect(bounds)
        }

        if let fragments = _lastSelectableFragments {
            for fragment in fragments {
                fragment.paint(context, offset)
            }
        }

        _textPainter.paint(context.canvas, offset)
        paintInlineChildren(context, offset)

        if _needsClipping {
            if let shader = _overflowShader {
                context.canvas.translate(offset.dx, offset.dy)
                let paint = Paint()
                paint.blendMode = .modulate
                paint.shader = shader
                context.canvas.drawRect(Offset.zero & size, paint)
            }
            context.canvas.restore()
        }
    }

    // MARK: - Caret and Position Methods

    /// Returns the offset at which to paint the caret.
    ///
    /// Valid only after layout.
    ///
    /// **Dart Source:** `paragraph.dart:1034-1038`
    public func getOffsetForCaret(_ position: TextPosition, _ caretPrototype: Rect) -> Offset {
        assert(!debugNeedsLayout)
        _layoutTextWithConstraints(boxConstraints)
        return _textPainter.getOffsetForCaret(position, caretPrototype)
    }

    /// Returns the full height for the caret at the given position.
    ///
    /// Valid only after layout.
    ///
    /// **Dart Source:** `paragraph.dart:1043-1047`
    public func getFullHeightForCaret(_ position: TextPosition) -> Double {
        assert(!debugNeedsLayout)
        _layoutTextWithConstraints(boxConstraints)
        return _textPainter.getFullHeightForCaret(position, .zero)
    }

    /// Returns a list of rects that bound the given selection.
    ///
    /// **Dart Source:** `paragraph.dart:1065-1077`
    public func getBoxesForSelection(
        _ selection: TextSelection,
        boxHeightStyle: BoxHeightStyle = .tight,
        boxWidthStyle: BoxWidthStyle = .tight
    ) -> [TextBox] {
        assert(!debugNeedsLayout)
        _layoutTextWithConstraints(boxConstraints)
        return _textPainter.getBoxesForSelection(
            selection,
            boxHeightStyle: boxHeightStyle,
            boxWidthStyle: boxWidthStyle
        )
    }

    /// Returns the position within the text for the given pixel offset.
    ///
    /// Valid only after layout.
    ///
    /// **Dart Source:** `paragraph.dart:1082-1086`
    public func getPositionForOffset(_ offset: Offset) -> TextPosition {
        assert(!debugNeedsLayout)
        _layoutTextWithConstraints(boxConstraints)
        return _textPainter.getPositionForOffset(offset)
    }

    /// Returns the text range of the word at the given offset.
    ///
    /// **Dart Source:** `paragraph.dart:1097-1101`
    public func getWordBoundary(_ position: TextPosition) -> TextRange {
        assert(!debugNeedsLayout)
        _layoutTextWithConstraints(boxConstraints)
        return _textPainter.getWordBoundary(position)
    }

    /// **Dart Source:** `paragraph.dart:1103`
    fileprivate func _getLineAtOffset(_ position: TextPosition) -> TextRange {
        _textPainter.getLineBoundary(position)
    }

    /// **Dart Source:** `paragraph.dart:1105-1110`
    fileprivate func _getTextPositionAbove(_ position: TextPosition) -> TextPosition {
        let preferredLineHeight = _textPainter.preferredLineHeight
        let verticalOffset = -0.5 * preferredLineHeight
        return _getTextPositionVertical(position, verticalOffset)
    }

    /// **Dart Source:** `paragraph.dart:1112-1117`
    fileprivate func _getTextPositionBelow(_ position: TextPosition) -> TextPosition {
        let preferredLineHeight = _textPainter.preferredLineHeight
        let verticalOffset = 1.5 * preferredLineHeight
        return _getTextPositionVertical(position, verticalOffset)
    }

    /// **Dart Source:** `paragraph.dart:1119-1123`
    private func _getTextPositionVertical(
        _ position: TextPosition, _ verticalOffset: Double
    ) -> TextPosition {
        let caretOffset = _textPainter.getOffsetForCaret(position, .zero)
        let caretOffsetTranslated = caretOffset.translate(0.0, verticalOffset)
        return _textPainter.getPositionForOffset(caretOffsetTranslated)
    }

    /// Returns the size of the text as laid out.
    ///
    /// **Dart Source:** `paragraph.dart:1134-1137`
    public var textSize: Size {
        assert(!debugNeedsLayout)
        return _textPainter.size
    }

    /// Whether the text was truncated or ellipsized as laid out.
    ///
    /// **Dart Source:** `paragraph.dart:1144-1147`
    public var didExceedMaxLines: Bool {
        assert(!debugNeedsLayout)
        return _textPainter.didExceedMaxLines
    }

    // MARK: - Semantics

    /// Collected during `describeSemanticsConfiguration`, used by
    /// `assembleSemanticsNode`.
    ///
    /// **Dart Source:** `paragraph.dart:1151`
    private var _semanticsInfo: [InlineSpanSemanticsInformation]?

    /// Cached child semantics nodes for stable IDs.
    ///
    /// **Dart Source:** `paragraph.dart:1272`
    private var _cachedChildNodes: [AnyHashable: SemanticsNode]?

    /// **Dart Source:** `paragraph.dart:1154-1200`
    open override func describeSemanticsConfiguration(_ config: SemanticsConfiguration) {
        _semanticsInfo = text.getSemanticsInformation()
        var needsAssembleSemanticsNode = false
        var needsChildConfigurationsDelegate = false
        for info in _semanticsInfo! {
            if info.recognizer != nil || info.semanticsIdentifier != nil {
                needsAssembleSemanticsNode = true
                break
            }
            needsChildConfigurationsDelegate =
                needsChildConfigurationsDelegate || info.isPlaceholder
        }

        if needsAssembleSemanticsNode {
            config.explicitChildNodes = true
            config.isSemanticBoundary = true
        } else if needsChildConfigurationsDelegate {
            // Delegate child configurations
        } else {
            if _cachedAttributedLabels == nil {
                var buffer = ""
                var offset = 0
                var attributes: [StringAttribute] = []
                for info in _semanticsInfo! {
                    let label = info.semanticsLabel ?? info.text
                    for infoAttribute in info.stringAttributes {
                        let originalRange = infoAttribute.range
                        attributes.append(
                            infoAttribute.copy(
                                range: TextRange(
                                    start: offset + originalRange.start,
                                    end: offset + originalRange.end
                                )
                            )
                        )
                    }
                    buffer += label
                    offset += label.count
                }
                _cachedAttributedLabels = [
                    AttributedString(buffer, attributes: attributes)
                ]
            }
            config.attributedLabel = _cachedAttributedLabels![0]
            config.textDirection = textDirection
        }
    }

    /// **Dart Source:** `paragraph.dart:1275-1391`
    open func assembleSemanticsNode(
        _ node: SemanticsNode,
        _ config: SemanticsConfiguration,
        _ children: [SemanticsNode]
    ) {
        assert(_semanticsInfo != nil && !_semanticsInfo!.isEmpty)
        let newChildren: [SemanticsNode] = []
        _cachedCombinedSemanticsInfos =
            _cachedCombinedSemanticsInfos ?? combineSemanticsInfo(_semanticsInfo!)
        let newChildCache: [AnyHashable: SemanticsNode] = [:]
        _cachedChildNodes = newChildCache
        node.updateWith(config: config, childrenInInversePaintOrder: newChildren)
    }

    /// **Dart Source:** `paragraph.dart:1401-1404`
    open func clearSemantics() {
        _cachedChildNodes = nil
    }

    // MARK: - Inline Children Helpers

    /// Computes the layout for every inline child using the `maxWidth` constraint.
    ///
    /// **Dart Source:** `paragraph.dart:192-202`
    public func layoutInlineChildren(
        width: Double,
        layoutChild: @escaping ChildLayouter,
        getChildBaseline: @escaping ChildBaselineGetter
    ) -> [PlaceholderDimensions] {
        let constraints = BoxConstraints(maxWidth: width)
        var result: [PlaceholderDimensions] = []
        var child = firstChild
        while let c = child {
            result.append(
                Self._layoutChild(c, constraints, layoutChild, getChildBaseline)
            )
            child = childAfter(c)
        }
        return result
    }

    /// **Dart Source:** `paragraph.dart:144-172`
    private static func _layoutChild(
        _ child: RenderBox,
        _ childConstraints: BoxConstraints,
        _ layoutChild: ChildLayouter,
        _ getBaseline: ChildBaselineGetter
    ) -> PlaceholderDimensions {
        let parentData = child.parentData as? TextParentData
        guard let span = parentData?.span else {
            return .empty
        }
        let childSize = layoutChild(child, childConstraints)
        let baselineOffset: Double?
        switch span.alignment {
        case .aboveBaseline, .belowBaseline, .bottom, .middle, .top:
            baselineOffset = nil
        case .baseline:
            if let baseline = span.baseline {
                baselineOffset = getBaseline(child, childConstraints, baseline)
            } else {
                baselineOffset = nil
            }
        }
        return PlaceholderDimensions(
            size: childSize,
            alignment: span.alignment,
            baseline: span.baseline,
            baselineOffset: baselineOffset
        )
    }

    /// Positions each inline child according to the coordinates provided.
    ///
    /// **Dart Source:** `paragraph.dart:217-236`
    public func positionInlineChildren(_ boxes: [TextBox]) {
        var child = firstChild
        for box in boxes {
            guard let c = child else {
                assertionFailure(
                    "The length of boxes (\(boxes.count)) should be greater than childCount (\(childCount))"
                )
                return
            }
            let textParentData = c.parentData as! TextParentData
            textParentData._offset = Offset(box.left, box.top)
            child = childAfter(c)
        }
        while let c = child {
            let textParentData = c.parentData as! TextParentData
            textParentData._offset = nil
            child = childAfter(c)
        }
    }

    /// Applies the transform that would be applied when painting the given child.
    ///
    /// **Dart Source:** `paragraph.dart:244-252`
    public func defaultApplyPaintTransform(_ child: RenderBox, _ transform: inout Matrix4) {
        let childParentData = child.parentData as! TextParentData
        if let offset = childParentData.textOffset {
            transform.translate(offset.dx, offset.dy)
        } else {
            transform.setZero()
        }
    }

    /// Paints each inline child.
    ///
    /// **Dart Source:** `paragraph.dart:259-270`
    public func paintInlineChildren(_ context: PaintingContext, _ offset: Offset) {
        var child = firstChild
        while let c = child {
            let childParentData = c.parentData as! TextParentData
            guard let childOffset = childParentData.textOffset else { return }
            context.paintChild(c, childOffset + offset)
            child = childAfter(c)
        }
    }

    /// Performs a hit test on each inline child.
    ///
    /// **Dart Source:** `paragraph.dart:277-297`
    public func hitTestInlineChildren(
        _ result: BoxHitTestResult, position: Offset
    ) -> Bool {
        var child = firstChild
        while let c = child {
            let childParentData = c.parentData as! TextParentData
            guard let childOffset = childParentData.textOffset else { return false }
            let isHit = result.addWithPaintOffset(
                offset: childOffset,
                position: position,
                hitTest: { result, transformed in
                    c.hitTest(result, position: transformed)
                }
            )
            if isHit {
                return true
            }
            child = childAfter(c)
        }
        return false
    }

    // MARK: - Debug

    /// **Dart Source:** `paragraph.dart:1414-1433`
    open func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        properties.add(EnumProperty("textAlign", textAlign))
        properties.add(EnumProperty("textDirection", textDirection))
        properties.add(
            FlagProperty(
                "softWrap",
                value: softWrap,
                ifTrue: "wrapping at box width",
                ifFalse: "no wrapping except at line break characters"
            )
        )
        properties.add(StringProperty("overflow", "\(overflow)"))
        properties.add(IntProperty("maxLines", maxLines, ifNull: "unlimited"))
    }

    // MARK: - Compositing Bits (Stub)

    /// Marks compositing bits as needing update.
    ///
    /// **Dart Source:** via `RenderObject`
    open override func markNeedsCompositingBitsUpdate() {
        // Stub implementation
    }

    /// Marks semantics as needing update.
    ///
    /// **Dart Source:** via `RenderObject`
    open func markNeedsSemanticsUpdate() {
        // Stub implementation
    }
}

// MARK: - SelectableFragment

/// A continuous, selectable piece of paragraph.
///
/// Since the selections in `PlaceholderSpan` are handled independently in its
/// subtree, a selection in `RenderParagraph` can't continue across a
/// `PlaceholderSpan`. The `RenderParagraph` splits itself on `PlaceholderSpan`
/// to create multiple `SelectableFragment`s so that they can be selected
/// separately.
///
/// **Dart Source:** `paragraph.dart:1443-3602`
public final class SelectableFragment: ChangeNotifier, Selectable, TextLayoutMetrics {

    /// **Dart Source:** `paragraph.dart:1446-1452`
    public init(paragraph: RenderParagraph, fullText: String, range: TextRange) {
        assert(range.isValid && !range.isCollapsed && range.isNormalized)
        self.paragraph = paragraph
        self.fullText = fullText
        self.range = range
        super.init()
        _selectionGeometry = _getSelectionGeometry()
    }

    /// The text range this fragment covers.
    ///
    /// **Dart Source:** `paragraph.dart:1454`
    public let range: TextRange

    /// The parent `RenderParagraph`.
    ///
    /// **Dart Source:** `paragraph.dart:1455`
    public let paragraph: RenderParagraph

    /// The full plain text of the paragraph.
    ///
    /// **Dart Source:** `paragraph.dart:1456`
    public let fullText: String

    /// **Dart Source:** `paragraph.dart:1458-1459`
    fileprivate var _textSelectionStart: TextPosition?
    fileprivate var _textSelectionEnd: TextPosition?

    /// **Dart Source:** `paragraph.dart:1461`
    fileprivate var _selectableContainsOriginTextBoundary = false

    /// **Dart Source:** `paragraph.dart:1463-1464`
    private var _startHandleLayerLink: LayerLink?
    private var _endHandleLayerLink: LayerLink?

    // MARK: - SelectionGeometry (Selectable / SelectionHandler)

    /// The current selection geometry.
    ///
    /// **Dart Source:** `paragraph.dart:1467-1468`
    public var value: SelectionGeometry { _selectionGeometry }
    private var _selectionGeometry: SelectionGeometry!

    /// **Dart Source:** `paragraph.dart:1469-1477`
    private func _updateSelectionGeometry() {
        let newValue = _getSelectionGeometry()
        if _selectionGeometry == newValue { return }
        _selectionGeometry = newValue
        notifyListeners()
    }

    /// **Dart Source:** `paragraph.dart:1479-1527`
    private func _getSelectionGeometry() -> SelectionGeometry {
        guard let selStart = _textSelectionStart, let selEnd = _textSelectionEnd else {
            return SelectionGeometry(status: .none, hasContent: true)
        }
        let selectionStart = selStart.offset
        let selectionEnd = selEnd.offset
        let isReversed = selectionStart > selectionEnd
        let startOffset = paragraph._getOffsetForPosition(
            TextPosition(offset: selectionStart)
        )
        let endOffset =
            selectionStart == selectionEnd
            ? startOffset
            : paragraph._getOffsetForPosition(TextPosition(offset: selectionEnd))
        let flipHandles = isReversed != (TextDirection.rtl == paragraph.textDirection)
        let selection = TextSelection(
            baseOffset: selectionStart, extentOffset: selectionEnd
        )
        var selectionRects: [Rect] = []
        for textBox in paragraph.getBoxesForSelection(selection) {
            selectionRects.append(textBox.toRect())
        }
        let selectionCollapsed = selectionStart == selectionEnd

        let startHandleType: TextSelectionHandleType
        let endHandleType: TextSelectionHandleType
        if selectionCollapsed {
            startHandleType = .collapsed
            endHandleType = .collapsed
        } else if flipHandles {
            startHandleType = .right
            endHandleType = .left
        } else {
            startHandleType = .left
            endHandleType = .right
        }

        return SelectionGeometry(
            startSelectionPoint: SelectionPoint(
                localPosition: startOffset,
                lineHeight: paragraph._textPainter.preferredLineHeight,
                handleType: startHandleType
            ),
            endSelectionPoint: SelectionPoint(
                localPosition: endOffset,
                lineHeight: paragraph._textPainter.preferredLineHeight,
                handleType: endHandleType
            ),
            selectionRects: selectionRects,
            status: selectionCollapsed ? .collapsed : .uncollapsed,
            hasContent: true
        )
    }

    // MARK: - SelectionEvent Dispatch

    /// **Dart Source:** `paragraph.dart:1530-1603`
    public func dispatchSelectionEvent(_ event: SelectionEvent) -> SelectionResult {
        let result: SelectionResult
        let existingSelectionStart = _textSelectionStart
        let existingSelectionEnd = _textSelectionEnd

        switch event.type {
        case .startEdgeUpdate, .endEdgeUpdate:
            let edgeUpdate = event as! SelectionEdgeUpdateEvent
            let granularity = edgeUpdate.granularity
            switch granularity {
            case .character:
                result = _updateSelectionEdge(
                    edgeUpdate.globalPosition,
                    isEnd: edgeUpdate.type == .endEdgeUpdate
                )
            case .word:
                result = _updateSelectionEdgeByTextBoundary(
                    edgeUpdate.globalPosition,
                    isEnd: edgeUpdate.type == .endEdgeUpdate,
                    getTextBoundary: _getWordBoundaryAtPosition
                )
            case .paragraph:
                result = _updateSelectionEdgeByMultiSelectableTextBoundary(
                    edgeUpdate.globalPosition,
                    isEnd: edgeUpdate.type == .endEdgeUpdate,
                    getTextBoundary: _getParagraphBoundaryAtPosition,
                    getClampedTextBoundary: _getClampedParagraphBoundaryAtPosition
                )
            case .document, .line:
                assertionFailure(
                    "Moving the selection edge by line or document is not supported."
                )
                result = .end
            }
        case .clear:
            result = _handleClearSelection()
        case .selectAll:
            result = _handleSelectAll()
        case .selectWord:
            let selectWord = event as! SelectWordSelectionEvent
            result = _handleSelectWord(selectWord.globalPosition)
        case .selectParagraph:
            let selectParagraph = event as! SelectParagraphSelectionEvent
            if selectParagraph.absorb {
                _ = _handleSelectAll()
                result = .next
                _selectableContainsOriginTextBoundary = true
            } else {
                result = _handleSelectParagraph(selectParagraph.globalPosition)
            }
        case .granularlyExtendSelection:
            let granularlyExtend = event as! GranularlyExtendSelectionEvent
            result = _handleGranularlyExtendSelection(
                granularlyExtend.forward,
                granularlyExtend.isEnd,
                granularlyExtend.granularity
            )
        case .directionallyExtendSelection:
            let directionallyExtend = event as! DirectionallyExtendSelectionEvent
            result = _handleDirectionallyExtendSelection(
                directionallyExtend.dx,
                directionallyExtend.isEnd,
                directionallyExtend.direction
            )
        }

        if existingSelectionStart?.offset != _textSelectionStart?.offset
            || existingSelectionEnd?.offset != _textSelectionEnd?.offset
        {
            _didChangeSelection()
        }
        return result
    }

    // MARK: - SelectedContent

    /// **Dart Source:** `paragraph.dart:1606-1613`
    public func getSelectedContent() -> SelectedContent? {
        guard let start = _textSelectionStart, let end = _textSelectionEnd else {
            return nil
        }
        let s = min(start.offset, end.offset)
        let e = max(start.offset, end.offset)
        let startIdx = fullText.index(fullText.startIndex, offsetBy: s)
        let endIdx = fullText.index(fullText.startIndex, offsetBy: e)
        return SelectedContent(plainText: String(fullText[startIdx..<endIdx]))
    }

    /// **Dart Source:** `paragraph.dart:1616-1624`
    public func getSelection() -> SelectedContentRange? {
        guard let start = _textSelectionStart, let end = _textSelectionEnd else {
            return nil
        }
        return SelectedContentRange(startOffset: start.offset, endOffset: end.offset)
    }

    // MARK: - Selection Change Notification

    /// **Dart Source:** `paragraph.dart:1626-1629`
    private func _didChangeSelection() {
        paragraph.markNeedsPaint()
        _updateSelectionGeometry()
    }

    // MARK: - Edge Update Methods

    /// **Dart Source:** `paragraph.dart:1904-1933`
    private func _updateSelectionEdge(
        _ globalPosition: Offset, isEnd: Bool
    ) -> SelectionResult {
        _setSelectionPosition(nil, isEnd: isEnd)
        var transform = paragraph.getTransformTo(nil)
        transform.invert()
        let localPosition = MatrixUtils.transformPoint(transform, globalPosition)
        if _rect.isEmpty {
            return SelectionUtils.getResultBasedOnRect(_rect, localPosition)
        }
        let adjustedOffset = SelectionUtils.adjustDragOffset(
            _rect, localPosition, direction: paragraph.textDirection
        )
        let position = _clampTextPosition(
            paragraph.getPositionForOffset(adjustedOffset)
        )
        _setSelectionPosition(position, isEnd: isEnd)
        if position.offset == range.end {
            return .next
        }
        if position.offset == range.start {
            return .previous
        }
        return SelectionUtils.getResultBasedOnRect(_rect, localPosition)
    }

    /// **Dart Source:** `paragraph.dart:1828-1902`
    private func _updateSelectionEdgeByTextBoundary(
        _ globalPosition: Offset,
        isEnd: Bool,
        getTextBoundary: @escaping TextBoundaryAtPosition
    ) -> SelectionResult {
        let existingSelectionStart = _textSelectionStart
        let existingSelectionEnd = _textSelectionEnd
        _setSelectionPosition(nil, isEnd: isEnd)
        var transform = paragraph.getTransformTo(nil)
        transform.invert()
        let localPosition = MatrixUtils.transformPoint(transform, globalPosition)
        if _rect.isEmpty {
            return SelectionUtils.getResultBasedOnRect(_rect, localPosition)
        }
        let adjustedOffset = SelectionUtils.adjustDragOffset(
            _rect, localPosition, direction: paragraph.textDirection
        )
        let position = paragraph.getPositionForOffset(adjustedOffset)
        var textBoundary: TextBoundaryRecord? =
            _rect.contains(localPosition) ? getTextBoundary(position) : nil
        if let tb = textBoundary,
           (tb.boundaryStart.offset < range.start && tb.boundaryEnd.offset <= range.start)
            || (tb.boundaryStart.offset >= range.end && tb.boundaryEnd.offset > range.end)
        {
            textBoundary = nil
        }
        let targetPosition = _clampTextPosition(
            isEnd
                ? _updateSelectionEndEdgeByTextBoundary(
                    textBoundary, getTextBoundary, position,
                    existingSelectionStart, existingSelectionEnd)
                : _updateSelectionStartEdgeByTextBoundary(
                    textBoundary, getTextBoundary, position,
                    existingSelectionStart, existingSelectionEnd)
        )
        _setSelectionPosition(targetPosition, isEnd: isEnd)
        if targetPosition.offset == range.end {
            return .next
        }
        if targetPosition.offset == range.start {
            return .previous
        }
        return SelectionUtils.getResultBasedOnRect(_rect, localPosition)
    }

    /// **Dart Source:** `paragraph.dart:2800-2924`
    private func _updateSelectionEdgeByMultiSelectableTextBoundary(
        _ globalPosition: Offset,
        isEnd: Bool,
        getTextBoundary: @escaping TextBoundaryAtPositionInText,
        getClampedTextBoundary: @escaping TextBoundaryAtPosition
    ) -> SelectionResult {
        let existingSelectionStart = _textSelectionStart
        let existingSelectionEnd = _textSelectionEnd

        _setSelectionPosition(nil, isEnd: isEnd)
        var transform = paragraph.getTransformTo(nil)
        transform.invert()
        let localPosition = MatrixUtils.transformPoint(transform, globalPosition)
        if _rect.isEmpty {
            return SelectionUtils.getResultBasedOnRect(_rect, localPosition)
        }
        let adjustedOffset = SelectionUtils.adjustDragOffset(
            _rect, localPosition, direction: paragraph.textDirection
        )

        let position = paragraph.getPositionForOffset(adjustedOffset)

        // Try multi-selectable boundary update
        let result: SelectionResult? = isEnd
            ? _updateSelectionEndEdgeByMultiSelectableTextBoundary(
                getTextBoundary,
                paragraph.paintBounds.contains(localPosition),
                paragraph.getPositionForOffset(
                    SelectionUtils.adjustDragOffset(
                        paragraph.paintBounds, localPosition,
                        direction: paragraph.textDirection
                    )
                ),
                existingSelectionStart, existingSelectionEnd)
            : _updateSelectionStartEdgeByMultiSelectableTextBoundary(
                getTextBoundary,
                paragraph.paintBounds.contains(localPosition),
                paragraph.getPositionForOffset(
                    SelectionUtils.adjustDragOffset(
                        paragraph.paintBounds, localPosition,
                        direction: paragraph.textDirection
                    )
                ),
                existingSelectionStart, existingSelectionEnd)

        if let result = result {
            return result
        }

        // Fallback to local text boundary
        var textBoundary: TextBoundaryRecord? =
            _boundingBoxesContains(localPosition) ? getClampedTextBoundary(position) : nil
        if let tb = textBoundary,
           (tb.boundaryStart.offset < range.start && tb.boundaryEnd.offset <= range.start)
            || (tb.boundaryStart.offset >= range.end && tb.boundaryEnd.offset > range.end)
        {
            textBoundary = nil
        }
        let targetPosition = _clampTextPosition(
            isEnd
                ? _updateSelectionEndEdgeByTextBoundary(
                    textBoundary, getClampedTextBoundary, position,
                    existingSelectionStart, existingSelectionEnd)
                : _updateSelectionStartEdgeByTextBoundary(
                    textBoundary, getClampedTextBoundary, position,
                    existingSelectionStart, existingSelectionEnd)
        )
        _setSelectionPosition(targetPosition, isEnd: isEnd)
        if targetPosition.offset == range.end { return .next }
        if targetPosition.offset == range.start { return .previous }
        return SelectionUtils.getResultBasedOnRect(_rect, localPosition)
    }

    // MARK: - Start/End Edge Text Boundary Updates

    /// **Dart Source:** `paragraph.dart:1631-1728`
    private func _updateSelectionStartEdgeByTextBoundary(
        _ textBoundary: TextBoundaryRecord?,
        _ getTextBoundary: TextBoundaryAtPosition,
        _ position: TextPosition,
        _ existingSelectionStart: TextPosition?,
        _ existingSelectionEnd: TextPosition?
    ) -> TextPosition {
        var targetPosition: TextPosition?
        if let tb = textBoundary {
            if _selectableContainsOriginTextBoundary,
               let existingStart = existingSelectionStart,
               let existingEnd = existingSelectionEnd
            {
                let isSamePosition = position.offset == existingEnd.offset
                let isSelectionInverted = existingStart.offset > existingEnd.offset
                let shouldSwapEdges =
                    !isSamePosition
                    && (isSelectionInverted != (position.offset > existingEnd.offset))
                if shouldSwapEdges {
                    targetPosition =
                        position.offset < existingEnd.offset
                        ? tb.boundaryStart : tb.boundaryEnd
                    let localTextBoundary = getTextBoundary(existingEnd)
                    _setSelectionPosition(
                        existingEnd.offset == localTextBoundary.boundaryStart.offset
                            ? localTextBoundary.boundaryEnd : localTextBoundary.boundaryStart,
                        isEnd: true
                    )
                } else {
                    if position.offset < existingEnd.offset {
                        targetPosition = tb.boundaryStart
                    } else if position.offset > existingEnd.offset {
                        targetPosition = tb.boundaryEnd
                    } else {
                        targetPosition = existingStart
                    }
                }
            } else {
                if existingSelectionEnd != nil {
                    targetPosition =
                        position.offset < existingSelectionEnd!.offset
                        ? tb.boundaryStart : tb.boundaryEnd
                } else {
                    targetPosition = _closestTextBoundary(tb, position)
                }
            }
        } else {
            if _selectableContainsOriginTextBoundary,
               let existingStart = existingSelectionStart,
               let existingEnd = existingSelectionEnd
            {
                let isSamePosition = position.offset == existingEnd.offset
                let isSelectionInverted = existingStart.offset > existingEnd.offset
                let shouldSwapEdges =
                    !isSamePosition
                    && (isSelectionInverted != (position.offset > existingEnd.offset))
                if shouldSwapEdges {
                    let localTextBoundary = getTextBoundary(existingEnd)
                    _setSelectionPosition(
                        isSelectionInverted
                            ? localTextBoundary.boundaryEnd : localTextBoundary.boundaryStart,
                        isEnd: true
                    )
                }
            }
        }
        return targetPosition ?? position
    }

    /// **Dart Source:** `paragraph.dart:1730-1826`
    private func _updateSelectionEndEdgeByTextBoundary(
        _ textBoundary: TextBoundaryRecord?,
        _ getTextBoundary: TextBoundaryAtPosition,
        _ position: TextPosition,
        _ existingSelectionStart: TextPosition?,
        _ existingSelectionEnd: TextPosition?
    ) -> TextPosition {
        var targetPosition: TextPosition?
        if let tb = textBoundary {
            if _selectableContainsOriginTextBoundary,
               let existingStart = existingSelectionStart,
               let existingEnd = existingSelectionEnd
            {
                let isSamePosition = position.offset == existingStart.offset
                let isSelectionInverted = existingStart.offset > existingEnd.offset
                let shouldSwapEdges =
                    !isSamePosition
                    && (isSelectionInverted != (position.offset < existingStart.offset))
                if shouldSwapEdges {
                    targetPosition =
                        position.offset < existingStart.offset
                        ? tb.boundaryStart : tb.boundaryEnd
                    let localTextBoundary = getTextBoundary(existingStart)
                    _setSelectionPosition(
                        existingStart.offset == localTextBoundary.boundaryStart.offset
                            ? localTextBoundary.boundaryEnd : localTextBoundary.boundaryStart,
                        isEnd: false
                    )
                } else {
                    if position.offset < existingStart.offset {
                        targetPosition = tb.boundaryStart
                    } else if position.offset > existingStart.offset {
                        targetPosition = tb.boundaryEnd
                    } else {
                        targetPosition = existingEnd
                    }
                }
            } else {
                if existingSelectionStart != nil {
                    targetPosition =
                        position.offset < existingSelectionStart!.offset
                        ? tb.boundaryStart : tb.boundaryEnd
                } else {
                    targetPosition = _closestTextBoundary(tb, position)
                }
            }
        } else {
            if _selectableContainsOriginTextBoundary,
               let existingStart = existingSelectionStart,
               let existingEnd = existingSelectionEnd
            {
                let isSamePosition = position.offset == existingStart.offset
                let isSelectionInverted = existingStart.offset > existingEnd.offset
                let shouldSwapEdges =
                    isSelectionInverted != (position.offset < existingStart.offset)
                    || isSamePosition
                if shouldSwapEdges {
                    let localTextBoundary = getTextBoundary(existingStart)
                    _setSelectionPosition(
                        isSelectionInverted
                            ? localTextBoundary.boundaryStart : localTextBoundary.boundaryEnd,
                        isEnd: false
                    )
                }
            }
        }
        return targetPosition ?? position
    }

    // MARK: - Multi-selectable Text Boundary Updates

    /// **Dart Source:** `paragraph.dart:1946-2111`
    private func _updateSelectionStartEdgeByMultiSelectableTextBoundary(
        _ getTextBoundary: TextBoundaryAtPositionInText,
        _ paragraphContainsPosition: Bool,
        _ position: TextPosition,
        _ existingSelectionStart: TextPosition?,
        _ existingSelectionEnd: TextPosition?
    ) -> SelectionResult? {
        let isEnd = false

        if _selectableContainsOriginTextBoundary,
           let existingStart = existingSelectionStart,
           let existingEnd = existingSelectionEnd
        {
            let forwardSelection = existingEnd.offset >= existingStart.offset
            if paragraphContainsPosition {
                let boundaryAtPosition = getTextBoundary(position, fullText)
                let originTextBoundary = getTextBoundary(
                    forwardSelection
                        ? TextPosition(
                            offset: existingEnd.offset - 1,
                            affinity: existingEnd.affinity)
                        : existingEnd,
                    fullText
                )
                let targetPosition: TextPosition
                let pivotOffset =
                    forwardSelection
                    ? originTextBoundary.boundaryEnd.offset
                    : originTextBoundary.boundaryStart.offset
                let shouldSwapEdges =
                    !forwardSelection != (position.offset > pivotOffset)
                if position.offset < pivotOffset {
                    targetPosition = boundaryAtPosition.boundaryStart
                } else if position.offset > pivotOffset {
                    targetPosition = boundaryAtPosition.boundaryEnd
                } else {
                    targetPosition =
                        forwardSelection ? existingStart : existingEnd
                }
                if shouldSwapEdges {
                    _setSelectionPosition(
                        _clampTextPosition(
                            forwardSelection
                                ? originTextBoundary.boundaryStart
                                : originTextBoundary.boundaryEnd),
                        isEnd: true
                    )
                }
                _setSelectionPosition(_clampTextPosition(targetPosition), isEnd: isEnd)
                let finalSelectionIsForward =
                    _textSelectionEnd!.offset >= _textSelectionStart!.offset
                if boundaryAtPosition.boundaryStart.offset > range.end
                    && boundaryAtPosition.boundaryEnd.offset > range.end
                { return .next }
                if boundaryAtPosition.boundaryStart.offset < range.start
                    && boundaryAtPosition.boundaryEnd.offset < range.start
                { return .previous }
                if finalSelectionIsForward {
                    if boundaryAtPosition.boundaryStart.offset
                        >= originTextBoundary.boundaryStart.offset
                    { return .end }
                    if boundaryAtPosition.boundaryStart.offset
                        < originTextBoundary.boundaryStart.offset
                    { return .previous }
                } else {
                    if boundaryAtPosition.boundaryEnd.offset
                        <= originTextBoundary.boundaryEnd.offset
                    { return .end }
                    if boundaryAtPosition.boundaryEnd.offset
                        > originTextBoundary.boundaryEnd.offset
                    { return .next }
                }
            } else {
                let clampedPosition = _clampTextPosition(position)
                let originTextBoundary = getTextBoundary(
                    forwardSelection
                        ? TextPosition(
                            offset: existingEnd.offset - 1,
                            affinity: existingEnd.affinity)
                        : existingEnd,
                    fullText
                )
                if forwardSelection && clampedPosition.offset == range.start {
                    _setSelectionPosition(clampedPosition, isEnd: isEnd)
                    return .previous
                }
                if !forwardSelection && clampedPosition.offset == range.end {
                    _setSelectionPosition(clampedPosition, isEnd: isEnd)
                    return .next
                }
                if forwardSelection && clampedPosition.offset == range.end {
                    _setSelectionPosition(
                        _clampTextPosition(originTextBoundary.boundaryStart), isEnd: true
                    )
                    _setSelectionPosition(clampedPosition, isEnd: isEnd)
                    return .next
                }
                if !forwardSelection && clampedPosition.offset == range.start {
                    _setSelectionPosition(
                        _clampTextPosition(originTextBoundary.boundaryEnd), isEnd: true
                    )
                    _setSelectionPosition(clampedPosition, isEnd: isEnd)
                    return .previous
                }
            }
        } else {
            let placeholderCharacter = RenderParagraph._placeholderCharacter
            let positionOnPlaceholder: Bool
            let wordBound = paragraph.getWordBoundary(position)
            positionOnPlaceholder =
                wordBound.textInside(fullText) == placeholderCharacter

            if !paragraphContainsPosition || positionOnPlaceholder {
                return nil
            }
            if existingSelectionEnd != nil {
                let boundaryAtPosition = getTextBoundary(position, fullText)
                if boundaryAtPosition.boundaryStart.offset < range.start
                    && boundaryAtPosition.boundaryEnd.offset < range.start
                {
                    _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd)
                    return .previous
                }
                if boundaryAtPosition.boundaryStart.offset > range.end
                    && boundaryAtPosition.boundaryEnd.offset > range.end
                {
                    _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd)
                    return .next
                }
            }
        }
        return nil
    }

    /// **Dart Source:** `paragraph.dart:2124-2289`
    private func _updateSelectionEndEdgeByMultiSelectableTextBoundary(
        _ getTextBoundary: TextBoundaryAtPositionInText,
        _ paragraphContainsPosition: Bool,
        _ position: TextPosition,
        _ existingSelectionStart: TextPosition?,
        _ existingSelectionEnd: TextPosition?
    ) -> SelectionResult? {
        let isEnd = true

        if _selectableContainsOriginTextBoundary,
           let existingStart = existingSelectionStart,
           let existingEnd = existingSelectionEnd
        {
            let forwardSelection = existingEnd.offset >= existingStart.offset
            if paragraphContainsPosition {
                let boundaryAtPosition = getTextBoundary(position, fullText)
                let originTextBoundary = getTextBoundary(
                    forwardSelection
                        ? existingStart
                        : TextPosition(
                            offset: existingStart.offset - 1,
                            affinity: existingStart.affinity),
                    fullText
                )
                let targetPosition: TextPosition
                let pivotOffset =
                    forwardSelection
                    ? originTextBoundary.boundaryStart.offset
                    : originTextBoundary.boundaryEnd.offset
                let shouldSwapEdges =
                    !forwardSelection != (position.offset < pivotOffset)
                if position.offset < pivotOffset {
                    targetPosition = boundaryAtPosition.boundaryStart
                } else if position.offset > pivotOffset {
                    targetPosition = boundaryAtPosition.boundaryEnd
                } else {
                    targetPosition =
                        forwardSelection ? existingEnd : existingStart
                }
                if shouldSwapEdges {
                    _setSelectionPosition(
                        _clampTextPosition(
                            forwardSelection
                                ? originTextBoundary.boundaryEnd
                                : originTextBoundary.boundaryStart),
                        isEnd: false
                    )
                }
                _setSelectionPosition(_clampTextPosition(targetPosition), isEnd: isEnd)
                let finalSelectionIsForward =
                    _textSelectionEnd!.offset >= _textSelectionStart!.offset
                if boundaryAtPosition.boundaryStart.offset > range.end
                    && boundaryAtPosition.boundaryEnd.offset > range.end
                { return .next }
                if boundaryAtPosition.boundaryStart.offset < range.start
                    && boundaryAtPosition.boundaryEnd.offset < range.start
                { return .previous }
                if finalSelectionIsForward {
                    if boundaryAtPosition.boundaryEnd.offset
                        <= originTextBoundary.boundaryEnd.offset
                    { return .end }
                    if boundaryAtPosition.boundaryEnd.offset
                        > originTextBoundary.boundaryEnd.offset
                    { return .next }
                } else {
                    if boundaryAtPosition.boundaryStart.offset
                        >= originTextBoundary.boundaryStart.offset
                    { return .end }
                    if boundaryAtPosition.boundaryStart.offset
                        < originTextBoundary.boundaryStart.offset
                    { return .previous }
                }
            } else {
                let clampedPosition = _clampTextPosition(position)
                let originTextBoundary = getTextBoundary(
                    forwardSelection
                        ? existingStart
                        : TextPosition(
                            offset: existingStart.offset - 1,
                            affinity: existingStart.affinity),
                    fullText
                )
                if forwardSelection && clampedPosition.offset == range.start {
                    _setSelectionPosition(
                        _clampTextPosition(originTextBoundary.boundaryEnd), isEnd: false
                    )
                    _setSelectionPosition(clampedPosition, isEnd: isEnd)
                    return .previous
                }
                if !forwardSelection && clampedPosition.offset == range.end {
                    _setSelectionPosition(
                        _clampTextPosition(originTextBoundary.boundaryStart), isEnd: false
                    )
                    _setSelectionPosition(clampedPosition, isEnd: isEnd)
                    return .next
                }
                if forwardSelection && clampedPosition.offset == range.end {
                    _setSelectionPosition(clampedPosition, isEnd: isEnd)
                    return .next
                }
                if !forwardSelection && clampedPosition.offset == range.start {
                    _setSelectionPosition(clampedPosition, isEnd: isEnd)
                    return .previous
                }
            }
        } else {
            let placeholderCharacter = RenderParagraph._placeholderCharacter
            let positionOnPlaceholder: Bool
            let wordBound = paragraph.getWordBoundary(position)
            positionOnPlaceholder =
                wordBound.textInside(fullText) == placeholderCharacter

            if !paragraphContainsPosition || positionOnPlaceholder {
                return nil
            }
            if existingSelectionStart != nil {
                let boundaryAtPosition = getTextBoundary(position, fullText)
                if boundaryAtPosition.boundaryStart.offset < range.start
                    && boundaryAtPosition.boundaryEnd.offset < range.start
                {
                    _setSelectionPosition(TextPosition(offset: range.start), isEnd: isEnd)
                    return .previous
                }
                if boundaryAtPosition.boundaryStart.offset > range.end
                    && boundaryAtPosition.boundaryEnd.offset > range.end
                {
                    _setSelectionPosition(TextPosition(offset: range.end), isEnd: isEnd)
                    return .next
                }
            }
        }
        return nil
    }

    // MARK: - Helper Methods

    /// **Dart Source:** `paragraph.dart:2926-2930`
    private func _closestTextBoundary(
        _ textBoundary: TextBoundaryRecord, _ position: TextPosition
    ) -> TextPosition {
        let differenceA = abs(position.offset - textBoundary.boundaryStart.offset)
        let differenceB = abs(position.offset - textBoundary.boundaryEnd.offset)
        return differenceA < differenceB
            ? textBoundary.boundaryStart : textBoundary.boundaryEnd
    }

    /// **Dart Source:** `paragraph.dart:3002-3009`
    private func _boundingBoxesContains(_ position: Offset) -> Bool {
        for rect in boundingBoxes {
            if rect.contains(position) { return true }
        }
        return false
    }

    /// **Dart Source:** `paragraph.dart:3011-3021`
    private func _clampTextPosition(_ position: TextPosition) -> TextPosition {
        if position.offset > range.end
            || (position.offset == range.end && position.affinity == .downstream)
        {
            return TextPosition(offset: range.end, affinity: .upstream)
        }
        if position.offset < range.start {
            return TextPosition(offset: range.start)
        }
        return position
    }

    /// **Dart Source:** `paragraph.dart:3023-3029`
    private func _setSelectionPosition(_ position: TextPosition?, isEnd: Bool) {
        if isEnd {
            _textSelectionEnd = position
        } else {
            _textSelectionStart = position
        }
    }

    /// **Dart Source:** `paragraph.dart:3031-3036`
    private func _handleClearSelection() -> SelectionResult {
        _textSelectionStart = nil
        _textSelectionEnd = nil
        _selectableContainsOriginTextBoundary = false
        return .none
    }

    /// **Dart Source:** `paragraph.dart:3038-3042`
    private func _handleSelectAll() -> SelectionResult {
        _textSelectionStart = TextPosition(offset: range.start)
        _textSelectionEnd = TextPosition(offset: range.end, affinity: .upstream)
        return .none
    }

    /// **Dart Source:** `paragraph.dart:3044-3066`
    private func _handleSelectTextBoundary(
        _ textBoundary: TextBoundaryRecord
    ) -> SelectionResult {
        if textBoundary.boundaryStart.offset < range.start
            && textBoundary.boundaryEnd.offset <= range.start
        {
            return .previous
        } else if textBoundary.boundaryStart.offset >= range.end
                    && textBoundary.boundaryEnd.offset > range.end
        {
            return .next
        }
        _textSelectionStart = textBoundary.boundaryStart
        _textSelectionEnd = textBoundary.boundaryEnd
        _selectableContainsOriginTextBoundary = true
        return .end
    }

    /// **Dart Source:** `paragraph.dart:3068-3078`
    private func _intersect(_ a: TextRange, _ b: TextRange) -> TextRange? {
        let startMax = max(a.start, b.start)
        let endMin = min(a.end, b.end)
        if startMax <= endMin {
            return TextRange(start: startMax, end: endMin)
        }
        return nil
    }

    /// **Dart Source:** `paragraph.dart:3080-3107`
    private func _handleSelectMultiFragmentTextBoundary(
        _ textBoundary: TextBoundaryRecord
    ) -> SelectionResult {
        if textBoundary.boundaryStart.offset < range.start
            && textBoundary.boundaryEnd.offset <= range.start
        {
            return .previous
        } else if textBoundary.boundaryStart.offset >= range.end
                    && textBoundary.boundaryEnd.offset > range.end
        {
            return .next
        }
        let boundaryAsRange = TextRange(
            start: textBoundary.boundaryStart.offset,
            end: textBoundary.boundaryEnd.offset
        )
        if let intersectRange = _intersect(range, boundaryAsRange) {
            _textSelectionStart = TextPosition(offset: intersectRange.start)
            _textSelectionEnd = TextPosition(offset: intersectRange.end)
            _selectableContainsOriginTextBoundary = true
            if range.end < textBoundary.boundaryEnd.offset {
                return .next
            }
            return .end
        }
        return .none
    }

    /// **Dart Source:** `paragraph.dart:3109-3119`
    private func _adjustTextBoundaryAtPosition(
        _ textBoundary: TextRange, _ position: TextPosition
    ) -> TextBoundaryRecord {
        let start: TextPosition
        let end: TextPosition
        if position.offset > textBoundary.end {
            let pos = TextPosition(offset: position.offset)
            start = pos
            end = pos
        } else {
            start = TextPosition(offset: textBoundary.start)
            end = TextPosition(offset: textBoundary.end, affinity: .upstream)
        }
        return (boundaryStart: start, boundaryEnd: end)
    }

    /// **Dart Source:** `paragraph.dart:3121-3130`
    private func _handleSelectWord(_ globalPosition: Offset) -> SelectionResult {
        let position = paragraph.getPositionForOffset(
            paragraph.globalToLocal(globalPosition)
        )
        if _positionIsWithinCurrentSelection(position)
            && _textSelectionStart?.offset != _textSelectionEnd?.offset
        {
            return .end
        }
        let wordBoundary = _getWordBoundaryAtPosition(position)
        return _handleSelectTextBoundary(wordBoundary)
    }

    /// **Dart Source:** `paragraph.dart:3132-3136`
    private func _getWordBoundaryAtPosition(
        _ position: TextPosition
    ) -> TextBoundaryRecord {
        let word = paragraph.getWordBoundary(position)
        return _adjustTextBoundaryAtPosition(word, position)
    }

    /// **Dart Source:** `paragraph.dart:3138-3146`
    private func _handleSelectParagraph(_ globalPosition: Offset) -> SelectionResult {
        let localPosition = paragraph.globalToLocal(globalPosition)
        let position = paragraph.getPositionForOffset(localPosition)
        let paragraphBoundary = _getParagraphBoundaryAtPosition(position, fullText)
        return _handleSelectMultiFragmentTextBoundary(paragraphBoundary)
    }

    /// **Dart Source:** `paragraph.dart:3156-3172`
    private func _getParagraphBoundaryAtPosition(
        _ position: TextPosition, _ text: String
    ) -> TextBoundaryRecord {
        let paragraphBoundary = ParagraphBoundary(text)
        let effectiveOffset =
            position.offset == text.count || position.affinity == .upstream
            ? position.offset - 1 : position.offset
        let paragraphStart =
            paragraphBoundary.getLeadingTextBoundaryAt(effectiveOffset) ?? 0
        let paragraphEnd =
            paragraphBoundary.getTrailingTextBoundaryAt(position.offset) ?? text.count
        let paragraphRange = TextRange(start: paragraphStart, end: paragraphEnd)
        return _adjustTextBoundaryAtPosition(paragraphRange, position)
    }

    /// **Dart Source:** `paragraph.dart:3174-3199`
    private func _getClampedParagraphBoundaryAtPosition(
        _ position: TextPosition
    ) -> TextBoundaryRecord {
        let paragraphBoundary = ParagraphBoundary(fullText)
        let effectiveOffset =
            position.offset == fullText.count || position.affinity == .upstream
            ? position.offset - 1 : position.offset
        var paragraphStart =
            paragraphBoundary.getLeadingTextBoundaryAt(effectiveOffset) ?? 0
        var paragraphEnd =
            paragraphBoundary.getTrailingTextBoundaryAt(position.offset) ?? fullText.count

        paragraphStart =
            paragraphStart < range.start
            ? range.start
            : (paragraphStart > range.end ? range.end : paragraphStart)
        paragraphEnd =
            paragraphEnd > range.end
            ? range.end
            : (paragraphEnd < range.start ? range.start : paragraphEnd)

        let paragraphRange = TextRange(start: paragraphStart, end: paragraphEnd)
        return _adjustTextBoundaryAtPosition(paragraphRange, position)
    }

    // MARK: - Directional and Granular Extension

    /// **Dart Source:** `paragraph.dart:3202-3261`
    private func _handleDirectionallyExtendSelection(
        _ horizontalBaseline: Double,
        _ isExtent: Bool,
        _ movement: SelectionExtendDirection
    ) -> SelectionResult {
        var transform = paragraph.getTransformTo(nil)
        if transform.invert() == 0.0 {
            switch movement {
            case .previousLine, .backward: return .previous
            case .nextLine, .forward: return .next
            }
        }
        let baselineInParagraphCoordinates = MatrixUtils.transformPoint(
            transform, Offset(horizontalBaseline, 0)
        ).dx

        let newPosition: TextPosition
        let result: SelectionResult

        switch movement {
        case .previousLine, .nextLine:
            assert(_textSelectionEnd != nil && _textSelectionStart != nil)
            let targetedEdge = isExtent ? _textSelectionEnd! : _textSelectionStart!
            let moveResult = _handleVerticalMovement(
                targetedEdge,
                horizontalBaselineInParagraphCoordinates:
                    baselineInParagraphCoordinates,
                below: movement == .nextLine
            )
            newPosition = moveResult.position
            result = moveResult.result
        case .forward, .backward:
            _textSelectionEnd = _textSelectionEnd ?? (
                movement == .forward
                    ? TextPosition(offset: range.start)
                    : TextPosition(offset: range.end, affinity: .upstream)
            )
            _textSelectionStart = _textSelectionStart ?? _textSelectionEnd
            let targetedEdge = isExtent ? _textSelectionEnd! : _textSelectionStart!
            let edgeOffset = paragraph._getOffsetForPosition(targetedEdge)
            let baselineOffset = Offset(
                baselineInParagraphCoordinates,
                edgeOffset.dy - paragraph._textPainter.preferredLineHeight / 2
            )
            newPosition = paragraph.getPositionForOffset(baselineOffset)
            result = .end
        }
        if isExtent {
            _textSelectionEnd = newPosition
        } else {
            _textSelectionStart = newPosition
        }
        return result
    }

    /// **Dart Source:** `paragraph.dart:3263-3327`
    private func _handleGranularlyExtendSelection(
        _ forward: Bool,
        _ isExtent: Bool,
        _ granularity: TextGranularity
    ) -> SelectionResult {
        _textSelectionEnd = _textSelectionEnd ?? (
            forward
                ? TextPosition(offset: range.start)
                : TextPosition(offset: range.end, affinity: .upstream)
        )
        _textSelectionStart = _textSelectionStart ?? _textSelectionEnd
        let targetedEdge = isExtent ? _textSelectionEnd! : _textSelectionStart!
        if forward && targetedEdge.offset == range.end { return .next }
        if !forward && targetedEdge.offset == range.start { return .previous }

        let result: SelectionResult
        let newPosition: TextPosition
        switch granularity {
        case .character:
            let text = range.textInside(fullText)
            newPosition = _moveBeyondTextBoundaryAtDirection(
                targetedEdge, forward, CharacterBoundary(text)
            )
            result = .end
        case .word:
            let textBoundary = paragraph._textPainter.wordBoundaries.moveByWordBoundary
            newPosition = _moveBeyondTextBoundaryAtDirection(
                targetedEdge, forward, textBoundary
            )
            result = .end
        case .paragraph:
            let text = range.textInside(fullText)
            newPosition = _moveBeyondTextBoundaryAtDirection(
                targetedEdge, forward, ParagraphBoundary(text)
            )
            result = .end
        case .line:
            newPosition = _moveToTextBoundaryAtDirection(
                targetedEdge, forward, LineBoundary(self)
            )
            result = .end
        case .document:
            let text = range.textInside(fullText)
            newPosition = _moveBeyondTextBoundaryAtDirection(
                targetedEdge, forward, DocumentBoundary(text)
            )
            if forward && newPosition.offset == range.end {
                result = .next
            } else if !forward && newPosition.offset == range.start {
                result = .previous
            } else {
                result = .end
            }
        }

        if isExtent {
            _textSelectionEnd = newPosition
        } else {
            _textSelectionStart = newPosition
        }
        return result
    }

    /// **Dart Source:** `paragraph.dart:3333-3342`
    private func _moveBeyondTextBoundaryAtDirection(
        _ end: TextPosition, _ forward: Bool, _ textBoundary: TextBoundary
    ) -> TextPosition {
        let newOffset =
            forward
            ? textBoundary.getTrailingTextBoundaryAt(end.offset) ?? range.end
            : textBoundary.getLeadingTextBoundaryAt(end.offset - 1) ?? range.start
        return TextPosition(offset: newOffset)
    }

    /// **Dart Source:** `paragraph.dart:3347-3374`
    private func _moveToTextBoundaryAtDirection(
        _ end: TextPosition, _ forward: Bool, _ textBoundary: TextBoundary
    ) -> TextPosition {
        assert(end.offset >= 0)
        let caretOffset: Int
        switch end.affinity {
        case .upstream:
            if end.offset < 1 && !forward {
                assert(end.offset == 0)
                return TextPosition(offset: 0)
            }
            let characterBoundary = CharacterBoundary(fullText)
            caretOffset =
                max(
                    0,
                    characterBoundary.getLeadingTextBoundaryAt(range.start + end.offset)
                        ?? range.start
                ) - 1
        case .downstream:
            caretOffset = end.offset
        }
        let offset =
            forward
            ? textBoundary.getTrailingTextBoundaryAt(caretOffset) ?? range.end
            : textBoundary.getLeadingTextBoundaryAt(caretOffset) ?? range.start
        return TextPosition(offset: offset)
    }

    /// **Dart Source:** `paragraph.dart:3376-3414`
    private func _handleVerticalMovement(
        _ position: TextPosition,
        horizontalBaselineInParagraphCoordinates: Double,
        below: Bool
    ) -> (position: TextPosition, result: SelectionResult) {
        let lines = paragraph._textPainter.computeLineMetrics()
        let offset = paragraph.getOffsetForCaret(position, .zero)
        var currentLine = lines.count - 1
        for lineMetrics in lines {
            if lineMetrics.baseline > offset.dy {
                currentLine = lineMetrics.lineNumber
                break
            }
        }
        let newPosition: TextPosition
        if below && currentLine == lines.count - 1 {
            newPosition = TextPosition(offset: range.end, affinity: .upstream)
        } else if !below && currentLine == 0 {
            newPosition = TextPosition(offset: range.start)
        } else {
            let newLine = below ? currentLine + 1 : currentLine - 1
            newPosition = _clampTextPosition(
                paragraph.getPositionForOffset(
                    Offset(
                        horizontalBaselineInParagraphCoordinates,
                        lines[newLine].baseline
                    )
                )
            )
        }
        let result: SelectionResult
        if newPosition.offset == range.start {
            result = .previous
        } else if newPosition.offset == range.end {
            result = .next
        } else {
            result = .end
        }
        return (position: newPosition, result: result)
    }

    /// **Dart Source:** `paragraph.dart:3420-3436`
    private func _positionIsWithinCurrentSelection(
        _ position: TextPosition
    ) -> Bool {
        guard let selStart = _textSelectionStart, let selEnd = _textSelectionEnd else {
            return false
        }
        let currentStart: TextPosition
        let currentEnd: TextPosition
        if Self._compareTextPositions(selStart, selEnd) > 0 {
            currentStart = selStart
            currentEnd = selEnd
        } else {
            currentStart = selEnd
            currentEnd = selStart
        }
        return Self._compareTextPositions(currentStart, position) >= 0
            && Self._compareTextPositions(currentEnd, position) <= 0
    }

    /// Compares two text positions.
    ///
    /// Returns 1 if `position` < `otherPosition`, -1 if `position` > `otherPosition`,
    /// or 0 if they are equal.
    ///
    /// **Dart Source:** `paragraph.dart:3442-3452`
    private static func _compareTextPositions(
        _ position: TextPosition, _ otherPosition: TextPosition
    ) -> Int {
        if position.offset < otherPosition.offset {
            return 1
        } else if position.offset > otherPosition.offset {
            return -1
        } else if position.affinity == otherPosition.affinity {
            return 0
        } else {
            return position.affinity == .upstream ? 1 : -1
        }
    }

    // MARK: - Selectable Protocol

    /// **Dart Source:** `paragraph.dart:3455-3457`
    public func getTransformTo(_ ancestor: RenderObject?) -> Matrix4 {
        paragraph.getTransformTo(ancestor)
    }

    /// **Dart Source:** `paragraph.dart:3460-3473`
    public func pushHandleLayers(startHandle: LayerLink?, endHandle: LayerLink?) {
        if !paragraph.attached {
            assert(
                startHandle == nil && endHandle == nil,
                "Only clean up can be called."
            )
            return
        }
        if _startHandleLayerLink !== startHandle {
            _startHandleLayerLink = startHandle
            paragraph.markNeedsPaint()
        }
        if _endHandleLayerLink !== endHandle {
            _endHandleLayerLink = endHandle
            paragraph.markNeedsPaint()
        }
    }

    /// **Dart Source:** `paragraph.dart:3475-3498`
    private var _cachedBoundingBoxes: [Rect]?
    public var boundingBoxes: [Rect] {
        if _cachedBoundingBoxes == nil {
            let boxes = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: range.start, extentOffset: range.end),
                boxHeightStyle: .max
            )
            if !boxes.isEmpty {
                _cachedBoundingBoxes = boxes.map { $0.toRect() }
            } else {
                let offset = paragraph._getOffsetForPosition(
                    TextPosition(offset: range.start)
                )
                let rect = Rect.fromPoints(
                    offset,
                    offset.translate(0, -paragraph._textPainter.preferredLineHeight)
                )
                _cachedBoundingBoxes = [rect]
            }
        }
        return _cachedBoundingBoxes!
    }

    /// **Dart Source:** `paragraph.dart:3500-3521`
    private var _cachedRect: Rect?
    private var _rect: Rect {
        if _cachedRect == nil {
            let boxes = paragraph.getBoxesForSelection(
                TextSelection(baseOffset: range.start, extentOffset: range.end)
            )
            if !boxes.isEmpty {
                var result = boxes.first!.toRect()
                for index in 1..<boxes.count {
                    result = result.expandToInclude(boxes[index].toRect())
                }
                _cachedRect = result
            } else {
                let offset = paragraph._getOffsetForPosition(
                    TextPosition(offset: range.start)
                )
                _cachedRect = Rect.fromPoints(
                    offset,
                    offset.translate(0, -paragraph._textPainter.preferredLineHeight)
                )
            }
        }
        return _cachedRect!
    }

    /// **Dart Source:** `paragraph.dart:3523-3526`
    func didChangeParagraphLayout() {
        _cachedRect = nil
        _cachedBoundingBoxes = nil
    }

    /// **Dart Source:** `paragraph.dart:3529`
    public var contentLength: Int { range.end - range.start }

    /// **Dart Source:** `paragraph.dart:3532-3534`
    public var size: Size { _rect.size }

    // MARK: - Paint

    /// **Dart Source:** `paragraph.dart:3536-3571`
    func paint(_ context: PaintingContext, _ offset: Offset) {
        guard let start = _textSelectionStart, let end = _textSelectionEnd else {
            return
        }
        if let selectionColor = paragraph.selectionColor {
            let selection = TextSelection(
                baseOffset: start.offset, extentOffset: end.offset
            )
            let selectionPaint = Paint()
            selectionPaint.style = .fill
            selectionPaint.color = selectionColor
            for textBox in paragraph.getBoxesForSelection(selection) {
                context.canvas.drawRect(textBox.toRect().shift(offset), selectionPaint)
            }
        }
        if let link = _startHandleLayerLink,
           let startPoint = value.startSelectionPoint
        {
            context.pushLayer(
                LeaderLayer(link: link, offset: offset + startPoint.localPosition),
                { _, _ in },
                .zero
            )
        }
        if let link = _endHandleLayerLink,
           let endPoint = value.endSelectionPoint
        {
            context.pushLayer(
                LeaderLayer(link: link, offset: offset + endPoint.localPosition),
                { _, _ in },
                .zero
            )
        }
    }

    // MARK: - TextLayoutMetrics

    /// **Dart Source:** `paragraph.dart:3575-3580`
    public func getLineAtOffset(_ position: TextPosition) -> TextSelection {
        let line = paragraph._getLineAtOffset(position)
        let start = min(max(line.start, range.start), range.end)
        let end = min(max(line.end, range.start), range.end)
        return TextSelection(baseOffset: start, extentOffset: end)
    }

    /// **Dart Source:** `paragraph.dart:3583-3585`
    public func getTextPositionAbove(_ position: TextPosition) -> TextPosition {
        _clampTextPosition(paragraph._getTextPositionAbove(position))
    }

    /// **Dart Source:** `paragraph.dart:3588-3590`
    public func getTextPositionBelow(_ position: TextPosition) -> TextPosition {
        _clampTextPosition(paragraph._getTextPositionBelow(position))
    }

    /// **Dart Source:** `paragraph.dart:3593`
    public func getWordBoundary(_ position: TextPosition) -> TextRange {
        paragraph.getWordBoundary(position)
    }
}
