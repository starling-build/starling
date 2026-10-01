// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Render object for editable text fields.
///
/// This is the renderer for an editable text field. It does not directly
/// provide affordances for editing the text, but it does handle text selection
/// and manipulation of the text cursor.
///
/// **Dart Source:** `packages/flutter/lib/src/rendering/editable.dart`

import FlutterSwiftBridge

// MARK: - Constants

/// Gap between the caret and the text in pixels.
///
/// **Dart Source:** `editable.dart:25`
private let _kCaretGap: Double = 1.0

/// Height offset for the caret in pixels.
///
/// **Dart Source:** `editable.dart:26`
private let _kCaretHeightOffset: Double = 2.0

/// Additional size on the x and y axis with which to expand the prototype
/// cursor to render the floating cursor in pixels.
///
/// **Dart Source:** `editable.dart:30-33`
private let _kFloatingCursorSizeIncrease = EdgeInsets(
    horizontal: 0.5,
    vertical: 1.0
)

/// The corner radius of the floating cursor in pixels.
///
/// **Dart Source:** `editable.dart:36`
private let _kFloatingCursorRadius = Radius(circular: 1.0)

/// The shortest squared distance required between the floating cursor
/// and the regular cursor when both are present in the text field.
///
/// **Dart Source:** `editable.dart:43`
private let _kShortestDistanceSquaredWithFloatingAndRegularCursors: Double = 15.0 * 15.0

// MARK: - Stub Types

/// A notifier that holds a single value and notifies listeners when the value changes.
///
/// This is a stub for Dart's `ValueNotifier<T>`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/change_notifier.dart`
public class ValueNotifier<T: Equatable>: ChangeNotifier, ValueListenable {
    /// Creates a change notifier that wraps a given value.
    public init(_ value: T) {
        _value = value
        super.init()
    }

    /// The current value.
    public var value: T {
        get { _value }
        set {
            if _value == newValue { return }
            _value = newValue
            notifyListeners()
        }
    }
    private var _value: T
}

/// The reason that the text selection changed.
///
/// **Dart Source:** `packages/flutter/lib/src/services/text_input.dart`
public enum SelectionChangedCause: Sendable {
    /// The user tapped.
    case tap
    /// The user double-tapped.
    case doubleTap
    /// The user long-pressed.
    case longPress
    /// The user used the keyboard.
    case keyboard
    /// The user dragged.
    case drag
    /// Selection was forced programmatically.
    case forcePress
    /// The user tapped on a toolbar action.
    case toolbar
    /// Scroll position change.
    case scribble
}

/// The state of a floating cursor drag.
///
/// **Dart Source:** `packages/flutter/lib/src/services/text_input.dart`
public enum FloatingCursorDragState: Sendable {
    /// The floating cursor is being dragged.
    case Start
    /// The floating cursor is being updated.
    case Update
    /// The floating cursor drag has ended.
    case End
}

/// The current text, selection, and composing state for editing.
///
/// **Dart Source:** `packages/flutter/lib/src/services/text_editing.dart`
public struct TextEditingValue: Equatable {
    /// The current text being edited.
    public let text: String

    /// The current selection range.
    public let selection: TextSelection

    /// The range of text that is still being composed.
    public let composing: TextRange

    /// Creates an editing value.
    public init(
        text: String = "",
        selection: TextSelection = TextSelection(offset: -1),
        composing: TextRange = TextRange.empty
    ) {
        self.text = text
        self.selection = selection
        self.composing = composing
    }

    /// Creates a copy of this value with the given fields replaced.
    public func copyWith(
        text: String? = nil,
        selection: TextSelection? = nil,
        composing: TextRange? = nil
    ) -> TextEditingValue {
        TextEditingValue(
            text: text ?? self.text,
            selection: selection ?? self.selection,
            composing: composing ?? self.composing
        )
    }
}

/// A delegate that provides text editing services.
///
/// **Dart Source:** `packages/flutter/lib/src/services/text_input.dart`
public protocol TextSelectionDelegate: AnyObject {
    /// The current `TextEditingValue`.
    var textEditingValue: TextEditingValue { get set }

    /// Called when the user changes the text editing value.
    func userUpdateTextEditingValue(_ value: TextEditingValue, _ cause: SelectionChangedCause)
}

// MARK: - TextSelectionPoint

/// Represents the coordinates of the point in a selection, and the text
/// direction at that point, relative to top left of the `RenderEditable` that
/// holds the selection.
///
/// **Dart Source:** `editable.dart:49-82`
public struct TextSelectionPoint: Equatable, Hashable, CustomStringConvertible {
    /// Creates a description of a point in a text selection.
    ///
    /// **Dart Source:** `editable.dart:51`
    public init(_ point: Offset, _ direction: TextDirection?) {
        self.point = point
        self.direction = direction
    }

    /// Coordinates of the lower left or lower right corner of the selection,
    /// relative to the top left of the `RenderEditable` object.
    ///
    /// **Dart Source:** `editable.dart:55`
    public let point: Offset

    /// Direction of the text at this edge of the selection.
    ///
    /// **Dart Source:** `editable.dart:58`
    public let direction: TextDirection?

    public static func == (lhs: TextSelectionPoint, rhs: TextSelectionPoint) -> Bool {
        lhs.point == rhs.point && lhs.direction == rhs.direction
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(point.dx)
        hasher.combine(point.dy)
        hasher.combine(direction)
    }

    public var description: String {
        if let dir = direction {
            return "\(point)-\(dir == .ltr ? "ltr" : "rtl")"
        }
        return "\(point)"
    }
}

// MARK: - VerticalCaretMovementRun

/// The consecutive sequence of `TextPosition`s that the caret should move to
/// when the user navigates the paragraph using the upward/downward arrow key.
///
/// **Dart Source:** `editable.dart:134-251`
public class VerticalCaretMovementRun {
    internal init(
        _ editable: RenderEditable,
        _ lineMetrics: [LineMetrics],
        _ currentTextPosition: TextPosition,
        _ currentLine: Int,
        _ currentOffset: Offset
    ) {
        _editable = editable
        _lineMetrics = lineMetrics
        _currentTextPosition = currentTextPosition
        _currentLine = currentLine
        _currentOffset = currentOffset
    }

    private var _currentOffset: Offset
    private var _currentLine: Int
    private var _currentTextPosition: TextPosition

    private let _lineMetrics: [LineMetrics]
    private let _editable: RenderEditable

    private var _isValid = true

    /// Whether this run can still continue.
    ///
    /// **Dart Source:** `editable.dart:159-170`
    public var isValid: Bool {
        if !_isValid {
            return false
        }
        let newLineMetrics = _editable._textPainter.computeLineMetrics()
        if newLineMetrics.count != _lineMetrics.count {
            _isValid = false
        }
        return _isValid
    }

    private var _positionCache: [Int: (Offset, TextPosition)] = [:]

    private func _getTextPositionForLine(_ lineNumber: Int) -> (Offset, TextPosition) {
        assert(isValid)
        assert(lineNumber >= 0)
        if let cached = _positionCache[lineNumber] {
            return cached
        }
        assert(lineNumber != _currentLine)

        let newOffset = Offset(_currentOffset.dx, _lineMetrics[lineNumber].baseline)
        let closestPosition = _editable._textPainter.getPositionForOffset(newOffset)
        let position = (newOffset, closestPosition)
        _positionCache[lineNumber] = position
        return position
    }

    /// The current text position.
    ///
    /// **Dart Source:** `editable.dart:195-198`
    public var current: TextPosition {
        assert(isValid)
        return _currentTextPosition
    }

    /// Move to the next line. Returns true if successful.
    ///
    /// **Dart Source:** `editable.dart:201-211`
    public func moveNext() -> Bool {
        assert(isValid)
        if _currentLine + 1 >= _lineMetrics.count {
            return false
        }
        let position = _getTextPositionForLine(_currentLine + 1)
        _currentLine += 1
        _currentOffset = position.0
        _currentTextPosition = position.1
        return true
    }

    /// Move to the previous line. Returns true if successful.
    ///
    /// **Dart Source:** `editable.dart:216-226`
    public func movePrevious() -> Bool {
        assert(isValid)
        if _currentLine <= 0 {
            return false
        }
        let position = _getTextPositionForLine(_currentLine - 1)
        _currentLine -= 1
        _currentOffset = position.0
        _currentTextPosition = position.1
        return true
    }

    /// Move forward or backward by a number of elements determined by pixel offset.
    ///
    /// **Dart Source:** `editable.dart:234-250`
    public func moveByOffset(_ offset: Double) -> Bool {
        let initialOffset = _currentOffset
        if offset >= 0.0 {
            while _currentOffset.dy < initialOffset.dy + offset {
                if !moveNext() { break }
            }
        } else {
            while _currentOffset.dy > initialOffset.dy + offset {
                if !movePrevious() { break }
            }
        }
        return initialOffset != _currentOffset
    }
}

// MARK: - RenderEditablePainter

/// An interface that paints within a `RenderEditable`'s bounds, above or
/// beneath its text content.
///
/// **Dart Source:** `editable.dart:2835-2860`
open class RenderEditablePainter: ChangeNotifier {
    /// Determines whether repaint is needed when a new `RenderEditablePainter`
    /// is provided to a `RenderEditable`.
    ///
    /// **Dart Source:** `editable.dart:2848`
    open func shouldRepaint(_ oldDelegate: RenderEditablePainter?) -> Bool {
        return true
    }

    /// Paints within the bounds of a `RenderEditable`.
    ///
    /// **Dart Source:** `editable.dart:2859`
    open func paint(_ canvas: any Canvas, _ size: Size, _ renderEditable: RenderEditable) {
        // Subclasses should override
    }
}

// MARK: - _TextHighlightPainter

/// A painter that highlights a range of text.
///
/// **Dart Source:** `editable.dart:2862-2958`
internal class _TextHighlightPainter: RenderEditablePainter {
    init(highlightedRange: TextRange? = nil, highlightColor: Color? = nil) {
        _highlightedRange = highlightedRange
        _highlightColor = highlightColor
        super.init()
    }

    let highlightPaint = Paint()

    var highlightColor: Color? {
        get { _highlightColor }
        set {
            if newValue == _highlightColor { return }
            _highlightColor = newValue
            notifyListeners()
        }
    }
    private var _highlightColor: Color?

    var highlightedRange: TextRange? {
        get { _highlightedRange }
        set {
            if newValue == _highlightedRange { return }
            _highlightedRange = newValue
            notifyListeners()
        }
    }
    private var _highlightedRange: TextRange?

    var selectionHeightStyle: BoxHeightStyle = .tight {
        didSet {
            if oldValue != selectionHeightStyle {
                notifyListeners()
            }
        }
    }

    var selectionWidthStyle: BoxWidthStyle = .tight {
        didSet {
            if oldValue != selectionWidthStyle {
                notifyListeners()
            }
        }
    }

    override func paint(_ canvas: any Canvas, _ size: Size, _ renderEditable: RenderEditable) {
        let range = highlightedRange
        let color = highlightColor
        guard let range = range, let color = color, !range.isCollapsed else {
            return
        }
        highlightPaint.color = color
        let textPainter = renderEditable._textPainter
        let boxes = textPainter.getBoxesForSelection(
            TextSelection(baseOffset: range.start, extentOffset: range.end),
            boxHeightStyle: selectionHeightStyle,
            boxWidthStyle: selectionWidthStyle
        )
        for box in boxes {
            let rect = box.toRect()
                .shift(renderEditable._paintOffset)
                .intersect(Rect.fromLTWH(0, 0, textPainter.width, textPainter.height))
            canvas.drawRect(rect, highlightPaint)
        }
    }

    override func shouldRepaint(_ oldDelegate: RenderEditablePainter?) -> Bool {
        if oldDelegate === self { return false }
        guard let oldDelegate = oldDelegate else {
            return highlightColor != nil && highlightedRange != nil
        }
        guard let old = oldDelegate as? _TextHighlightPainter else { return true }
        return old.highlightColor != highlightColor
            || old.highlightedRange != highlightedRange
            || old.selectionHeightStyle != selectionHeightStyle
            || old.selectionWidthStyle != selectionWidthStyle
    }
}

// MARK: - _CaretPainter

/// A painter that renders the caret and floating cursor.
///
/// **Dart Source:** `editable.dart:2960-3118`
internal class _CaretPainter: RenderEditablePainter {
    var shouldPaint: Bool {
        get { _shouldPaint }
        set {
            if _shouldPaint == newValue { return }
            _shouldPaint = newValue
            notifyListeners()
        }
    }
    private var _shouldPaint: Bool = true

    var showRegularCaret: Bool = false

    let caretPaint = Paint()
    lazy var floatingCursorPaint = Paint()

    var caretColor: Color? {
        get { _caretColor }
        set {
            if _caretColor == newValue { return }
            _caretColor = newValue
            notifyListeners()
        }
    }
    private var _caretColor: Color?

    var cursorRadius: Radius? {
        get { _cursorRadius }
        set {
            if _cursorRadius == newValue { return }
            _cursorRadius = newValue
            notifyListeners()
        }
    }
    private var _cursorRadius: Radius?

    var cursorOffset: Offset {
        get { _cursorOffset }
        set {
            if _cursorOffset == newValue { return }
            _cursorOffset = newValue
            notifyListeners()
        }
    }
    private var _cursorOffset: Offset = Offset.zero

    var backgroundCursorColor: Color? {
        get { _backgroundCursorColor }
        set {
            if _backgroundCursorColor == newValue { return }
            _backgroundCursorColor = newValue
            if showRegularCaret {
                notifyListeners()
            }
        }
    }
    private var _backgroundCursorColor: Color?

    var floatingCursorRect: Rect? {
        get { _floatingCursorRect }
        set {
            if _floatingCursorRect == newValue { return }
            _floatingCursorRect = newValue
            notifyListeners()
        }
    }
    private var _floatingCursorRect: Rect?

    func paintRegularCursor(
        _ canvas: any Canvas,
        _ renderEditable: RenderEditable,
        _ caretColor: Color,
        _ textPosition: TextPosition
    ) {
        let integralRect = renderEditable.getLocalRectForCaret(textPosition)
        if shouldPaint {
            if let floatingRect = floatingCursorRect {
                let distanceSquared = (floatingRect.center - integralRect.center).distanceSquared
                if distanceSquared < _kShortestDistanceSquaredWithFloatingAndRegularCursors {
                    return
                }
            }
            let radius = cursorRadius
            caretPaint.color = caretColor
            if let radius = radius {
                let caretRRect = RRect(fromRectAndRadius:integralRect, radius)
                canvas.drawRRect(caretRRect, caretPaint)
            } else {
                canvas.drawRect(integralRect, caretPaint)
            }
        }
    }

    override func paint(_ canvas: any Canvas, _ size: Size, _ renderEditable: RenderEditable) {
        let selection = renderEditable.selection
        guard let selection = selection, selection.isCollapsed, selection.isValid else {
            return
        }

        let floatingRect = floatingCursorRect
        let resolvedCaretColor: Color?
        if floatingRect == nil {
            resolvedCaretColor = caretColor
        } else if showRegularCaret {
            resolvedCaretColor = backgroundCursorColor
        } else {
            resolvedCaretColor = nil
        }

        let caretTextPosition: TextPosition
        if floatingRect == nil {
            caretTextPosition = selection.extent
        } else {
            caretTextPosition = renderEditable._floatingCursorTextPosition
        }

        if let color = resolvedCaretColor {
            paintRegularCursor(canvas, renderEditable, color, caretTextPosition)
        }

        guard let floatingRect = floatingRect,
              let floatingColor = caretColor?.withOpacity(0.75),
              shouldPaint else {
            return
        }

        canvas.drawRRect(
            RRect(fromRectAndRadius:floatingRect, _kFloatingCursorRadius),
            { floatingCursorPaint.color = floatingColor; return floatingCursorPaint }()
        )
    }

    override func shouldRepaint(_ oldDelegate: RenderEditablePainter?) -> Bool {
        if oldDelegate === self { return false }
        guard let old = oldDelegate as? _CaretPainter else { return shouldPaint }
        return old.shouldPaint != shouldPaint
            || old.showRegularCaret != showRegularCaret
            || old.caretColor != caretColor
            || old.cursorRadius != cursorRadius
            || old.cursorOffset != cursorOffset
            || old.backgroundCursorColor != backgroundCursorColor
            || old.floatingCursorRect != floatingCursorRect
    }
}

// MARK: - _CompositeRenderEditablePainter

/// A composite painter that delegates to a list of painters.
///
/// **Dart Source:** `editable.dart:3120-3166`
internal class _CompositeRenderEditablePainter: RenderEditablePainter {
    init(painters: [RenderEditablePainter]) {
        self.painters = painters
        super.init()
    }

    let painters: [RenderEditablePainter]

    override func addListener(_ listener: @escaping VoidCallback) {
        for painter in painters {
            painter.addListener(listener)
        }
    }

    override func removeListener(_ listener: @escaping VoidCallback) {
        for painter in painters {
            painter.removeListener(listener)
        }
    }

    override func addListener(_ listener: @escaping VoidCallback, owner: AnyObject) {
        for painter in painters {
            painter.addListener(listener, owner: owner)
        }
    }

    override func removeListeners(owner: AnyObject) {
        for painter in painters {
            painter.removeListeners(owner: owner)
        }
    }

    override func paint(_ canvas: any Canvas, _ size: Size, _ renderEditable: RenderEditable) {
        for painter in painters {
            painter.paint(canvas, size, renderEditable)
        }
    }

    override func shouldRepaint(_ oldDelegate: RenderEditablePainter?) -> Bool {
        if oldDelegate === self { return false }
        guard let old = oldDelegate as? _CompositeRenderEditablePainter,
              old.painters.count == painters.count else {
            return true
        }
        for i in 0..<painters.count {
            if painters[i].shouldRepaint(old.painters[i]) {
                return true
            }
        }
        return false
    }
}

// MARK: - _RenderEditableCustomPaint

/// A custom paint render box that paints a `RenderEditablePainter`.
///
/// **Dart Source:** `editable.dart:2752-2810`
internal class _RenderEditableCustomPaint: RenderBox {
    init(painter: RenderEditablePainter? = nil) {
        _painter = painter
        super.init()
    }

    override var isRepaintBoundary: Bool { true }

    override var sizedByParent: Bool { true }

    var painter: RenderEditablePainter? {
        get { _painter }
        set {
            if newValue === _painter { return }
            let oldPainter = _painter
            _painter = newValue
            if newValue?.shouldRepaint(oldPainter) ?? true {
                markNeedsPaint()
            }
            if attached {
                oldPainter?.removeListeners(owner: self)
                newValue?.addListener(markNeedsPaint, owner: self)
            }
        }
    }
    private var _painter: RenderEditablePainter?

    override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _painter?.addListener(markNeedsPaint, owner: self)
    }

    override func detach() {
        _painter?.removeListeners(owner: self)
        super.detach()
    }

    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        return constraints.biggest
    }
}

// MARK: - RenderEditable

/// Displays some text in a scrollable container with a potentially blinking
/// cursor and with gesture recognizers.
///
/// This is the renderer for an editable text field. It does not directly
/// provide affordances for editing the text, but it does handle text selection
/// and manipulation of the text cursor.
///
/// **Dart Source:** `editable.dart:270-2750`
open class RenderEditable: RenderBox, RenderInlineChildrenContainerDefaults, TextLayoutMetrics {

    // MARK: - Initialization

    /// Creates a render object that implements the visual aspects of a text field.
    ///
    /// **Dart Source:** `editable.dart:288-405`
    public init(
        text: InlineSpan? = nil,
        textDirection: TextDirection,
        textAlign: TextAlign = .start,
        cursorColor: Color? = nil,
        backgroundCursorColor: Color? = nil,
        showCursor: ValueNotifier<Bool>? = nil,
        hasFocus: Bool? = nil,
        startHandleLayerLink: LayerLink = LayerLink(),
        endHandleLayerLink: LayerLink = LayerLink(),
        maxLines: Int? = 1,
        minLines: Int? = nil,
        expands: Bool = false,
        strutStyle: StrutStyle? = nil,
        selectionColor: Color? = nil,
        textScaler: (any TextScaler)? = nil,
        selection: TextSelection? = nil,
        offset: ViewportOffset,
        ignorePointer: Bool = false,
        readOnly: Bool = false,
        forceLine: Bool = true,
        textHeightBehavior: TextHeightBehavior? = nil,
        textWidthBasis: TextWidthBasis = .parent,
        obscuringCharacter: String = "\u{2022}",
        obscureText: Bool = false,
        locale: Locale? = nil,
        cursorWidth: Double = 1.0,
        cursorHeight: Double? = nil,
        cursorRadius: Radius? = nil,
        paintCursorAboveText: Bool = false,
        cursorOffset: Offset = .zero,
        devicePixelRatio: Double = 1.0,
        selectionHeightStyle: BoxHeightStyle = .max,
        selectionWidthStyle: BoxWidthStyle = .max,
        enableInteractiveSelection: Bool? = nil,
        floatingCursorAddedMargin: EdgeInsets = EdgeInsets.fromLTRB(4, 4, 4, 5),
        promptRectRange: TextRange? = nil,
        promptRectColor: Color? = nil,
        clipBehavior: Clip = .hardEdge,
        textSelectionDelegate: (any TextSelectionDelegate)?,
        painter: RenderEditablePainter? = nil,
        foregroundPainter: RenderEditablePainter? = nil,
        children: [RenderBox]? = nil
    ) {
        assert(maxLines == nil || maxLines! > 0)
        assert(minLines == nil || minLines! > 0)
        assert(
            (maxLines == nil) || (minLines == nil) || (maxLines! >= minLines!),
            "minLines can't be greater than maxLines"
        )
        assert(
            !expands || (maxLines == nil && minLines == nil),
            "minLines and maxLines must be null when expands is true."
        )
        assert(cursorWidth >= 0.0)
        assert(cursorHeight == nil || cursorHeight! >= 0.0)

        _textPainter = TextPainter(
            text: text,
            textAlign: textAlign,
            textDirection: textDirection,
            textScaler: textScaler ?? TextScalers.noScaling,
            maxLines: maxLines == 1 ? 1 : nil,
            locale: locale,
            strutStyle: strutStyle,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior
        )
        _showCursor = showCursor ?? ValueNotifier<Bool>(false)
        _maxLines = maxLines
        _minLines = minLines
        _expands = expands
        _selection = selection
        _offset = offset
        _cursorWidth = cursorWidth
        _cursorHeight = cursorHeight
        _paintCursorOnTop = paintCursorAboveText
        _enableInteractiveSelection = enableInteractiveSelection
        _devicePixelRatio = devicePixelRatio
        _startHandleLayerLink = startHandleLayerLink
        _endHandleLayerLink = endHandleLayerLink
        _obscuringCharacter = obscuringCharacter
        _obscureText = obscureText
        _readOnly = readOnly
        _forceLine = forceLine
        _clipBehavior = clipBehavior
        _hasFocus = hasFocus ?? false
        _disposeShowCursor = showCursor == nil
        self.ignorePointer = ignorePointer
        self.floatingCursorAddedMargin = floatingCursorAddedMargin
        self.textSelectionDelegate = textSelectionDelegate

        super.init()

        _selectionPainter.highlightColor = selectionColor
        if let selection = selection {
            _selectionPainter.highlightedRange = TextRange(start: selection.start, end: selection.end)
        }
        _selectionPainter.selectionHeightStyle = selectionHeightStyle
        _selectionPainter.selectionWidthStyle = selectionWidthStyle

        _autocorrectHighlightPainter.highlightColor = promptRectColor
        _autocorrectHighlightPainter.highlightedRange = promptRectRange

        _caretPainter.caretColor = cursorColor
        _caretPainter.cursorRadius = cursorRadius
        _caretPainter.cursorOffset = cursorOffset
        _caretPainter.backgroundCursorColor = backgroundCursorColor

        _updateForegroundPainter(foregroundPainter)
        _updatePainter(painter)
        if let children = children {
            addAll(children)
        }
    }

    // MARK: - Child Management (ContainerRenderObjectMixin pattern)

    /// The first child in the child list.
    public private(set) var firstChild: RenderBox?

    /// The last child in the child list.
    public private(set) var lastChild: RenderBox?

    /// The number of children.
    public private(set) var childCount: Int = 0

    /// Returns the child after the given child.
    public func childAfter(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as? TextParentData
        return parentData?.nextSibling
    }

    /// Returns the child before the given child.
    public func childBefore(_ child: RenderBox) -> RenderBox? {
        let parentData = child.parentData as? TextParentData
        return parentData?.previousSibling
    }

    /// Sets up parent data for a child.
    open override func setupParentData(_ child: RenderObject) {
        if !(child.parentData is TextParentData) {
            child.parentData = TextParentData()
        }
    }

    /// Inserts a child at the given position.
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
    public func addAll(_ children: [RenderBox]) {
        for child in children {
            insert(child, after: lastChild)
        }
    }

    /// Removes a child from the child list.
    public func remove(_ child: RenderBox) {
        let childParentData = child.parentData as! TextParentData
        if let prev = childParentData.previousSibling {
            let prevParentData = prev.parentData as! TextParentData
            prevParentData.nextSibling = childParentData.nextSibling
        } else {
            firstChild = childParentData.nextSibling
        }
        if let next = childParentData.nextSibling {
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

    // MARK: - RenderInlineChildrenContainerDefaults (Stub Methods)

    /// Layout inline children and return placeholder dimensions.
    ///
    /// This is a simplified stub. The full implementation would measure each
    /// inline widget child.
    ///
    /// **Dart Source:** `paragraph.dart:135-219`
    internal func layoutInlineChildren(
        _ maxWidth: Double,
        _ layoutChild: (RenderBox, BoxConstraints) -> Size,
        _ getBaseline: (RenderBox, BoxConstraints, TextBaseline) -> Double?
    ) -> [PlaceholderDimensions] {
        // TODO: Full implementation
        return []
    }

    /// Position inline children based on their placeholder boxes.
    ///
    /// **Dart Source:** `paragraph.dart:221-244`
    internal func positionInlineChildren(_ boxes: [TextBox]) {
        // TODO: Full implementation
    }

    /// Hit test inline children.
    ///
    /// **Dart Source:** `paragraph.dart:257-297`
    internal func hitTestInlineChildren(_ result: BoxHitTestResult, _ position: Offset) -> Bool {
        // TODO: Full implementation
        return false
    }

    /// Paint inline children.
    ///
    /// **Dart Source:** `paragraph.dart:246-255`
    internal func paintInlineChildren(_ context: PaintingContext, _ offset: Offset) {
        // TODO: Full implementation
    }

    // MARK: - Internal Painter Infrastructure

    /// Child render objects for custom paint overlays.
    ///
    /// **Dart Source:** `editable.dart:408-409`
    private var _foregroundRenderObject: _RenderEditableCustomPaint?
    private var _backgroundRenderObject: _RenderEditableCustomPaint?

    /// Caret painter.
    ///
    /// **Dart Source:** `editable.dart:505`
    internal lazy var _caretPainter = _CaretPainter()

    /// Text highlight painters.
    ///
    /// **Dart Source:** `editable.dart:508-509`
    internal let _selectionPainter = _TextHighlightPainter()
    internal let _autocorrectHighlightPainter = _TextHighlightPainter()

    /// Built-in foreground painters cache.
    ///
    /// **Dart Source:** `editable.dart:511-518`
    private var _cachedBuiltInForegroundPainters: _CompositeRenderEditablePainter?
    private var _builtInForegroundPainters: _CompositeRenderEditablePainter {
        if let cached = _cachedBuiltInForegroundPainters { return cached }
        let painters = _createBuiltInForegroundPainters()
        _cachedBuiltInForegroundPainters = painters
        return painters
    }
    private func _createBuiltInForegroundPainters() -> _CompositeRenderEditablePainter {
        var list: [RenderEditablePainter] = []
        if paintCursorAboveText { list.append(_caretPainter) }
        return _CompositeRenderEditablePainter(painters: list)
    }

    /// Built-in background painters cache.
    ///
    /// **Dart Source:** `editable.dart:520-531`
    private var _cachedBuiltInPainters: _CompositeRenderEditablePainter?
    private var _builtInPainters: _CompositeRenderEditablePainter {
        if let cached = _cachedBuiltInPainters { return cached }
        let painters = _createBuiltInPainters()
        _cachedBuiltInPainters = painters
        return painters
    }
    private func _createBuiltInPainters() -> _CompositeRenderEditablePainter {
        var list: [RenderEditablePainter] = [_autocorrectHighlightPainter, _selectionPainter]
        if !paintCursorAboveText { list.append(_caretPainter) }
        return _CompositeRenderEditablePainter(painters: list)
    }

    /// Update foreground painter.
    ///
    /// **Dart Source:** `editable.dart:435-452`
    private func _updateForegroundPainter(_ newPainter: RenderEditablePainter?) {
        let effectivePainter: _CompositeRenderEditablePainter
        if let newPainter = newPainter {
            effectivePainter = _CompositeRenderEditablePainter(
                painters: [_builtInForegroundPainters, newPainter]
            )
        } else {
            effectivePainter = _builtInForegroundPainters
        }

        if _foregroundRenderObject == nil {
            let obj = _RenderEditableCustomPaint(painter: effectivePainter)
            // adoptChild(obj)  // TODO: Full implementation
            _foregroundRenderObject = obj
        } else {
            _foregroundRenderObject?.painter = effectivePainter
        }
        _foregroundPainter = newPainter
    }

    /// Update background painter.
    ///
    /// **Dart Source:** `editable.dart:469-486`
    private func _updatePainter(_ newPainter: RenderEditablePainter?) {
        let effectivePainter: _CompositeRenderEditablePainter
        if let newPainter = newPainter {
            effectivePainter = _CompositeRenderEditablePainter(
                painters: [_builtInPainters, newPainter]
            )
        } else {
            effectivePainter = _builtInPainters
        }

        if _backgroundRenderObject == nil {
            let obj = _RenderEditableCustomPaint(painter: effectivePainter)
            // adoptChild(obj)  // TODO: Full implementation
            _backgroundRenderObject = obj
        } else {
            _backgroundRenderObject?.painter = effectivePainter
        }
        _painter = newPainter
    }

    // MARK: - Properties

    /// Whether the `handleEvent` will propagate pointer events to selection handlers.
    ///
    /// **Dart Source:** `editable.dart:544`
    public var ignorePointer: Bool

    /// The foreground painter.
    ///
    /// **Dart Source:** `editable.dart:460-467`
    public var foregroundPainter: RenderEditablePainter? {
        get { _foregroundPainter }
        set {
            if newValue === _foregroundPainter { return }
            _updateForegroundPainter(newValue)
        }
    }
    private var _foregroundPainter: RenderEditablePainter?

    /// The background painter.
    ///
    /// **Dart Source:** `editable.dart:494-501`
    public var painter: RenderEditablePainter? {
        get { _painter }
        set {
            if newValue === _painter { return }
            _updatePainter(newValue)
        }
    }
    private var _painter: RenderEditablePainter?

    /// Text height behavior.
    ///
    /// **Dart Source:** `editable.dart:547-554`
    public var textHeightBehavior: TextHeightBehavior? {
        get { _textPainter.textHeightBehavior }
        set {
            if _textPainter.textHeightBehavior == newValue { return }
            _textPainter.textHeightBehavior = newValue
            markNeedsLayout()
        }
    }

    /// Text width basis.
    ///
    /// **Dart Source:** `editable.dart:557-564`
    public var textWidthBasis: TextWidthBasis {
        get { _textPainter.textWidthBasis }
        set {
            if _textPainter.textWidthBasis == newValue { return }
            _textPainter.textWidthBasis = newValue
            markNeedsLayout()
        }
    }

    /// The pixel ratio of the current device.
    ///
    /// **Dart Source:** `editable.dart:569-577`
    public var devicePixelRatio: Double {
        get { _devicePixelRatio }
        set {
            if _devicePixelRatio == newValue { return }
            _devicePixelRatio = newValue
            markNeedsLayout()
        }
    }
    private var _devicePixelRatio: Double

    /// Character used for obscuring text if `obscureText` is true.
    ///
    /// **Dart Source:** `editable.dart:582-591`
    public var obscuringCharacter: String {
        get { _obscuringCharacter }
        set {
            if _obscuringCharacter == newValue { return }
            _obscuringCharacter = newValue
            markNeedsLayout()
        }
    }
    private var _obscuringCharacter: String

    /// Whether to hide the text being edited (e.g., for passwords).
    ///
    /// **Dart Source:** `editable.dart:594-603`
    public var obscureText: Bool {
        get { _obscureText }
        set {
            if _obscureText == newValue { return }
            _obscureText = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _obscureText: Bool

    /// Controls how tall the selection highlight boxes are computed to be.
    ///
    /// **Dart Source:** `editable.dart:608-611`
    public var selectionHeightStyle: BoxHeightStyle {
        get { _selectionPainter.selectionHeightStyle }
        set { _selectionPainter.selectionHeightStyle = newValue }
    }

    /// Controls how wide the selection highlight boxes are computed to be.
    ///
    /// **Dart Source:** `editable.dart:616-619`
    public var selectionWidthStyle: BoxWidthStyle {
        get { _selectionPainter.selectionWidthStyle }
        set { _selectionPainter.selectionWidthStyle = newValue }
    }

    /// The object that controls the text selection.
    ///
    /// **Dart Source:** `editable.dart:626`
    public weak var textSelectionDelegate: (any TextSelectionDelegate)?

    /// Track whether position of the start of the selected text is within the viewport.
    ///
    /// **Dart Source:** `editable.dart:638-639`
    public var selectionStartInViewport: ValueNotifier<Bool> { _selectionStartInViewport }
    private let _selectionStartInViewport = ValueNotifier<Bool>(true)

    /// Track whether position of the end of the selected text is within the viewport.
    ///
    /// **Dart Source:** `editable.dart:651-652`
    public var selectionEndInViewport: ValueNotifier<Bool> { _selectionEndInViewport }
    private let _selectionEndInViewport = ValueNotifier<Bool>(true)

    /// Returns a plain text version of the text in `TextPainter`.
    ///
    /// **Dart Source:** `editable.dart:782`
    public var plainText: String { _textPainter.plainText }

    /// The text to paint in the form of a tree of `InlineSpan`s.
    ///
    /// **Dart Source:** `editable.dart:787-801`
    public var text: InlineSpan? {
        get { _textPainter.text }
        set {
            if _textPainter.text === newValue { return }
            _cachedLineBreakCount = nil
            _textPainter.text = newValue
            markNeedsLayout()
            markNeedsSemanticsUpdate()
        }
    }

    /// The text painter.
    ///
    /// **Dart Source:** `editable.dart:788`
    internal let _textPainter: TextPainter

    /// Cache for intrinsics text painter.
    ///
    /// **Dart Source:** `editable.dart:803-816`
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

    /// How the text should be aligned horizontally.
    ///
    /// **Dart Source:** `editable.dart:819-826`
    public var textAlign: TextAlign {
        get { _textPainter.textAlign }
        set {
            if _textPainter.textAlign == newValue { return }
            _textPainter.textAlign = newValue
            markNeedsLayout()
        }
    }

    /// The directionality of the text.
    ///
    /// **Dart Source:** `editable.dart:842-850`
    public var textDirection: TextDirection {
        get { _textPainter.textDirection! }
        set {
            if _textPainter.textDirection == newValue { return }
            _textPainter.textDirection = newValue
            markNeedsLayout()
            markNeedsSemanticsUpdate()
        }
    }

    /// Used by this renderer's internal `TextPainter` to select a locale-specific font.
    ///
    /// **Dart Source:** `editable.dart:862-869`
    public var locale: Locale? {
        get { _textPainter.locale }
        set {
            if _textPainter.locale == newValue { return }
            _textPainter.locale = newValue
            markNeedsLayout()
        }
    }

    /// The `StrutStyle` used by the renderer's internal `TextPainter`.
    ///
    /// **Dart Source:** `editable.dart:872-880`
    public var strutStyle: StrutStyle? {
        get { _textPainter.strutStyle }
        set {
            if _textPainter.strutStyle == newValue { return }
            _textPainter.strutStyle = newValue
            markNeedsLayout()
        }
    }

    /// The color to use when painting the cursor.
    ///
    /// **Dart Source:** `editable.dart:883-886`
    public var cursorColor: Color? {
        get { _caretPainter.caretColor }
        set { _caretPainter.caretColor = newValue }
    }

    /// The color to use when painting the cursor aligned to the text while
    /// rendering the floating cursor.
    ///
    /// **Dart Source:** `editable.dart:899-902`
    public var backgroundCursorColor: Color? {
        get { _caretPainter.backgroundCursorColor }
        set { _caretPainter.backgroundCursorColor = newValue }
    }

    private var _disposeShowCursor: Bool

    /// Whether to paint the cursor.
    ///
    /// **Dart Source:** `editable.dart:907-925`
    public var showCursor: ValueNotifier<Bool> {
        get { _showCursor }
        set {
            if _showCursor === newValue { return }
            if attached {
                _showCursor.removeListeners(owner: self)
            }
            if _disposeShowCursor {
                _showCursor.dispose()
                _disposeShowCursor = false
            }
            _showCursor = newValue
            if attached {
                _showHideCursor()
                _showCursor.addListener(_showHideCursor, owner: self)
            }
        }
    }
    private var _showCursor: ValueNotifier<Bool>

    private func _showHideCursor() {
        _caretPainter.shouldPaint = showCursor.value
    }

    /// Whether the editable is currently focused.
    ///
    /// **Dart Source:** `editable.dart:932-940`
    public var hasFocus: Bool {
        get { _hasFocus }
        set {
            if _hasFocus == newValue { return }
            _hasFocus = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _hasFocus: Bool = false

    /// Whether this rendering object will take a full line regardless the text width.
    ///
    /// **Dart Source:** `editable.dart:943-951`
    public var forceLine: Bool {
        get { _forceLine }
        set {
            if _forceLine == newValue { return }
            _forceLine = newValue
            markNeedsLayout()
        }
    }
    private var _forceLine: Bool = false

    /// Whether this rendering object is read only.
    ///
    /// **Dart Source:** `editable.dart:954-962`
    public var readOnly: Bool {
        get { _readOnly }
        set {
            if _readOnly == newValue { return }
            _readOnly = newValue
            markNeedsSemanticsUpdate()
        }
    }
    private var _readOnly: Bool = false

    /// The maximum number of lines for the text to span, wrapping if necessary.
    ///
    /// **Dart Source:** `editable.dart:974-990`
    public var maxLines: Int? {
        get { _maxLines }
        set {
            assert(newValue == nil || newValue! > 0)
            if _maxLines == newValue { return }
            _maxLines = newValue
            _textPainter.maxLines = newValue == 1 ? 1 : nil
            markNeedsLayout()
        }
    }
    private var _maxLines: Int?

    /// The minimum number of lines to occupy.
    ///
    /// **Dart Source:** `editable.dart:993-1004`
    public var minLines: Int? {
        get { _minLines }
        set {
            assert(newValue == nil || newValue! > 0)
            if _minLines == newValue { return }
            _minLines = newValue
            markNeedsLayout()
        }
    }
    private var _minLines: Int?

    /// Whether this widget's height will be sized to fill its parent.
    ///
    /// **Dart Source:** `editable.dart:1007-1015`
    public var expands: Bool {
        get { _expands }
        set {
            if _expands == newValue { return }
            _expands = newValue
            markNeedsLayout()
        }
    }
    private var _expands: Bool

    /// The color to use when painting the selection.
    ///
    /// **Dart Source:** `editable.dart:1018-1021`
    public var selectionColor: Color? {
        get { _selectionPainter.highlightColor }
        set { _selectionPainter.highlightColor = newValue }
    }

    /// The text scaler.
    ///
    /// **Dart Source:** `editable.dart:1046-1053`
    public var textScaler: any TextScaler {
        get { _textPainter.textScaler }
        set {
            // TextScaler comparison through existential; just always set
            // (the TextPainter will skip redundant updates internally)
            _textPainter.textScaler = newValue
            markNeedsLayout()
        }
    }

    /// The region of text that is selected, if any.
    ///
    /// **Dart Source:** `editable.dart:1061-1071`
    public var selection: TextSelection? {
        get { _selection }
        set {
            if _selection == newValue { return }
            _selection = newValue
            if let sel = newValue {
                _selectionPainter.highlightedRange = TextRange(start: sel.start, end: sel.end)
            } else {
                _selectionPainter.highlightedRange = nil
            }
            markNeedsPaint()
            markNeedsSemanticsUpdate()
        }
    }
    private var _selection: TextSelection?

    /// The offset at which the text should be painted.
    ///
    /// **Dart Source:** `editable.dart:1078-1092`
    public var offset: ViewportOffset {
        get { _offset }
        set {
            if _offset === newValue { return }
            if attached {
                _offset.removeListeners(owner: self)
            }
            _offset = newValue
            if attached {
                _offset.addListener(markNeedsPaint, owner: self)
            }
            markNeedsLayout()
        }
    }
    private var _offset: ViewportOffset

    /// How thick the cursor will be.
    ///
    /// **Dart Source:** `editable.dart:1095-1103`
    public var cursorWidth: Double {
        get { _cursorWidth }
        set {
            if _cursorWidth == newValue { return }
            _cursorWidth = newValue
            markNeedsLayout()
        }
    }
    private var _cursorWidth: Double = 1.0

    /// How tall the cursor will be.
    ///
    /// **Dart Source:** `editable.dart:1112-1120`
    public var cursorHeight: Double {
        get { _cursorHeight ?? preferredLineHeight }
    }
    private var _cursorHeight: Double?

    /// Set the cursor height.
    public func setCursorHeight(_ value: Double?) {
        if _cursorHeight == value { return }
        _cursorHeight = value
        markNeedsLayout()
    }

    /// If the cursor should be painted on top of the text or underneath it.
    ///
    /// **Dart Source:** `editable.dart:1128-1141`
    public var paintCursorAboveText: Bool {
        get { _paintCursorOnTop }
        set {
            if _paintCursorOnTop == newValue { return }
            _paintCursorOnTop = newValue
            _cachedBuiltInForegroundPainters = nil
            _cachedBuiltInPainters = nil
            _updateForegroundPainter(_foregroundPainter)
            _updatePainter(_painter)
        }
    }
    private var _paintCursorOnTop: Bool

    /// The offset that is used, in pixels, when painting the cursor on screen.
    ///
    /// **Dart Source:** `editable.dart:1151-1154`
    public var cursorOffset: Offset {
        get { _caretPainter.cursorOffset }
        set { _caretPainter.cursorOffset = newValue }
    }

    /// How rounded the corners of the cursor should be.
    ///
    /// **Dart Source:** `editable.dart:1159-1162`
    public var cursorRadius: Radius? {
        get { _caretPainter.cursorRadius }
        set { _caretPainter.cursorRadius = newValue }
    }

    /// The `LayerLink` of start selection handle.
    ///
    /// **Dart Source:** `editable.dart:1168-1176`
    public var startHandleLayerLink: LayerLink {
        get { _startHandleLayerLink }
        set {
            if _startHandleLayerLink === newValue { return }
            _startHandleLayerLink = newValue
            markNeedsPaint()
        }
    }
    private var _startHandleLayerLink: LayerLink

    /// The `LayerLink` of end selection handle.
    ///
    /// **Dart Source:** `editable.dart:1182-1190`
    public var endHandleLayerLink: LayerLink {
        get { _endHandleLayerLink }
        set {
            if _endHandleLayerLink === newValue { return }
            _endHandleLayerLink = newValue
            markNeedsPaint()
        }
    }
    private var _endHandleLayerLink: LayerLink

    /// The padding applied to text field. Used to determine the bounds when
    /// moving the floating cursor.
    ///
    /// **Dart Source:** `editable.dart:1201`
    public var floatingCursorAddedMargin: EdgeInsets

    /// Returns true if the floating cursor is visible.
    ///
    /// **Dart Source:** `editable.dart:1204-1205`
    public var floatingCursorOn: Bool { _floatingCursorOn }
    internal var _floatingCursorOn: Bool = false
    internal var _floatingCursorTextPosition: TextPosition = TextPosition(offset: 0)

    /// Whether to allow the user to change the selection.
    ///
    /// **Dart Source:** `editable.dart:1221-1230`
    public var enableInteractiveSelection: Bool? {
        get { _enableInteractiveSelection }
        set {
            if _enableInteractiveSelection == newValue { return }
            _enableInteractiveSelection = newValue
            markNeedsLayout()
            markNeedsSemanticsUpdate()
        }
    }
    private var _enableInteractiveSelection: Bool?

    /// Whether interactive selection are enabled based on the values of
    /// `enableInteractiveSelection` and `obscureText`.
    ///
    /// **Dart Source:** `editable.dart:1252-1254`
    public var selectionEnabled: Bool {
        enableInteractiveSelection ?? !obscureText
    }

    /// The color used to paint the prompt rectangle.
    ///
    /// **Dart Source:** `editable.dart:1262-1265`
    public var promptRectColor: Color? {
        get { _autocorrectHighlightPainter.highlightColor }
        set { _autocorrectHighlightPainter.highlightColor = newValue }
    }

    /// Dismisses the currently displayed prompt rectangle and displays a new one.
    ///
    /// **Dart Source:** `editable.dart:1274-1276`
    public func setPromptRectRange(_ newRange: TextRange?) {
        _autocorrectHighlightPainter.highlightedRange = newRange
    }

    /// The maximum amount the text is allowed to scroll.
    ///
    /// **Dart Source:** `editable.dart:1283-1284`
    public var maxScrollExtent: Double { _maxScrollExtent }
    private var _maxScrollExtent: Double = 0

    private var _caretMargin: Double { _kCaretGap + cursorWidth }

    /// Clip behavior.
    ///
    /// **Dart Source:** `editable.dart:1291-1299`
    public var clipBehavior: Clip {
        get { _clipBehavior }
        set {
            if newValue != _clipBehavior {
                _clipBehavior = newValue
                markNeedsPaint()
                markNeedsSemanticsUpdate()
            }
        }
    }
    private var _clipBehavior: Clip = .hardEdge

    // MARK: - Semantics Update Stub

    /// Mark that semantics need updating.
    ///
    /// **Dart Source:** `object.dart:3487-3533`
    public func markNeedsSemanticsUpdate() {
        // TODO: Full implementation with PipelineOwner
    }

    // MARK: - TextLayoutMetrics Implementation

    /// An estimate of the height of a line in the text.
    ///
    /// **Dart Source:** `editable.dart:1910`
    public var preferredLineHeight: Double { _textPainter.preferredLineHeight }

    /// Returns the `TextPosition` above or below the given offset.
    ///
    /// **Dart Source:** `editable.dart:655-659`
    private func _getTextPositionVertical(_ position: TextPosition, _ verticalOffset: Double) -> TextPosition {
        let caretOffset = _textPainter.getOffsetForCaret(position, _caretPrototype)
        let caretOffsetTranslated = Offset(caretOffset.dx, caretOffset.dy + verticalOffset)
        return _textPainter.getPositionForOffset(caretOffsetTranslated)
    }

    /// Returns the `TextSelection` for the line at the given offset.
    ///
    /// **Dart Source:** `editable.dart:665-672`
    public func getLineAtOffset(_ position: TextPosition) -> TextSelection {
        let line = _textPainter.getLineBoundary(position)
        if obscureText {
            return TextSelection(baseOffset: 0, extentOffset: plainText.count)
        }
        return TextSelection(baseOffset: line.start, extentOffset: line.end)
    }

    /// Returns the word boundary at the given position.
    ///
    /// **Dart Source:** `editable.dart:676-678`
    public func getWordBoundary(_ position: TextPosition) -> TextRange {
        return _textPainter.getWordBoundary(position)
    }

    /// Returns the `TextPosition` above the given position.
    ///
    /// **Dart Source:** `editable.dart:682-689`
    public func getTextPositionAbove(_ position: TextPosition) -> TextPosition {
        let preferredLineHeight = _textPainter.preferredLineHeight
        let verticalOffset = -0.5 * preferredLineHeight
        return _getTextPositionVertical(position, verticalOffset)
    }

    /// Returns the `TextPosition` below the given position.
    ///
    /// **Dart Source:** `editable.dart:693-700`
    public func getTextPositionBelow(_ position: TextPosition) -> TextPosition {
        let preferredLineHeight = _textPainter.preferredLineHeight
        let verticalOffset = 1.5 * preferredLineHeight
        return _getTextPositionVertical(position, verticalOffset)
    }

    // MARK: - Selection Helpers

    /// Updates whether selection extents are visible.
    ///
    /// **Dart Source:** `editable.dart:704-735`
    private func _updateSelectionExtentsVisibility(_ effectiveOffset: Offset) {
        guard let selection = selection, selection.isValid else {
            _selectionStartInViewport.value = false
            _selectionEndInViewport.value = false
            return
        }
        let visibleRegion = Rect.fromLTWH(0, 0, size.width, size.height)
        let visibleRegionSlop: Double = 0.5

        let startOffset = _textPainter.getOffsetForCaret(
            TextPosition(offset: selection.start),
            _caretPrototype
        )
        _selectionStartInViewport.value = visibleRegion
            .inflate(visibleRegionSlop)
            .contains(startOffset + effectiveOffset)

        let endOffset = _textPainter.getOffsetForCaret(
            TextPosition(offset: selection.end),
            _caretPrototype
        )
        _selectionEndInViewport.value = visibleRegion
            .inflate(visibleRegionSlop)
            .contains(endOffset + effectiveOffset)
    }

    private func _setTextEditingValue(_ newValue: TextEditingValue, _ cause: SelectionChangedCause) {
        textSelectionDelegate?.userUpdateTextEditingValue(newValue, cause)
    }

    private func _setSelection(_ nextSelection: TextSelection, _ cause: SelectionChangedCause) {
        var sel = nextSelection
        if sel.isValid {
            let textLength = textSelectionDelegate?.textEditingValue.text.count ?? 0
            sel = TextSelection(
                baseOffset: min(sel.baseOffset, textLength),
                extentOffset: min(sel.extentOffset, textLength)
            )
        }
        if let delegate = textSelectionDelegate {
            _setTextEditingValue(
                delegate.textEditingValue.copyWith(selection: sel),
                cause
            )
        }
    }

    // MARK: - Layout Helpers

    private var _isMultiline: Bool { maxLines != 1 }

    private var _viewportAxis: Axis { _isMultiline ? .vertical : .horizontal }

    internal var _paintOffset: Offset {
        switch _viewportAxis {
        case .horizontal: return Offset(-offset.pixels, 0.0)
        case .vertical: return Offset(0.0, -offset.pixels)
        }
    }

    private var _viewportExtent: Double {
        assert(hasSize)
        switch _viewportAxis {
        case .horizontal: return size.width
        case .vertical: return size.height
        }
    }

    private func _getMaxScrollExtent(_ contentSize: Size) -> Double {
        assert(hasSize)
        switch _viewportAxis {
        case .horizontal: return max(0.0, contentSize.width - size.width)
        case .vertical: return max(0.0, contentSize.height - size.height)
        }
    }

    private var _hasVisualOverflow: Bool {
        _maxScrollExtent > 0 || _paintOffset != Offset.zero
    }

    // MARK: - Intrinsic Dimensions

    private func _adjustConstraints(
        minWidth: Double = 0.0,
        maxWidth: Double = .infinity
    ) -> (Double, Double) {
        let availableMaxWidth = max(0.0, maxWidth - _caretMargin)
        let availableMinWidth = min(minWidth, availableMaxWidth)
        return (
            _forceLine ? availableMaxWidth : availableMinWidth,
            _isMultiline ? availableMaxWidth : Double.infinity
        )
    }

    open override func computeMinIntrinsicWidth(_ height: Double) -> Double {
        let placeholderDimensions = layoutInlineChildren(
            .infinity,
            { (child: RenderBox, constraints: BoxConstraints) -> Size in
                Size(child.getMinIntrinsicWidth(.infinity), 0.0)
            },
            { (_: RenderBox, _: BoxConstraints, _: TextBaseline) -> Double? in nil }
        )
        let (minW, maxW) = _adjustConstraints()
        _textIntrinsics.setPlaceholderDimensions(placeholderDimensions)
        _textIntrinsics.layout(minWidth: minW, maxWidth: maxW)
        return _textIntrinsics.minIntrinsicWidth
    }

    open override func computeMaxIntrinsicWidth(_ height: Double) -> Double {
        let placeholderDimensions = layoutInlineChildren(
            .infinity,
            { (child: RenderBox, constraints: BoxConstraints) -> Size in
                Size(child.getMaxIntrinsicWidth(.infinity), 0.0)
            },
            { (_: RenderBox, _: BoxConstraints, _: TextBaseline) -> Double? in nil }
        )
        let (minW, maxW) = _adjustConstraints()
        _textIntrinsics.setPlaceholderDimensions(placeholderDimensions)
        _textIntrinsics.layout(minWidth: minW, maxWidth: maxW)
        return _textIntrinsics.maxIntrinsicWidth + _caretMargin
    }

    private var _cachedLineBreakCount: Int?

    private func _countHardLineBreaks(_ text: String) -> Int {
        if let cached = _cachedLineBreakCount {
            return cached
        }
        var count = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x000A, 0x0085, 0x000B, 0x000C, 0x2028, 0x2029:
                count += 1
            default:
                break
            }
        }
        _cachedLineBreakCount = count
        return count
    }

    private func _preferredHeight(_ width: Double) -> Double {
        let maxLines = self.maxLines
        let minLines = self.minLines ?? maxLines
        let minHeight = preferredLineHeight * Double(minLines ?? 0)

        if maxLines == nil {
            let estimatedHeight: Double
            if width == .infinity {
                estimatedHeight = preferredLineHeight * Double(_countHardLineBreaks(plainText) + 1)
            } else {
                let (minW, maxW) = _adjustConstraints(maxWidth: width)
                _textIntrinsics.layout(minWidth: minW, maxWidth: maxW)
                estimatedHeight = _textIntrinsics.height
            }
            return max(estimatedHeight, minHeight)
        }

        if maxLines == 1 {
            let (minW, maxW) = _adjustConstraints(maxWidth: width)
            _textIntrinsics.layout(minWidth: minW, maxWidth: maxW)
            return _textIntrinsics.height
        }

        if minLines == maxLines {
            return minHeight
        }

        let maxHeight = preferredLineHeight * Double(maxLines!)
        let (minW, maxW) = _adjustConstraints(maxWidth: width)
        _textIntrinsics.layout(minWidth: minW, maxWidth: maxW)
        return clampDouble(_textIntrinsics.height, minHeight, maxHeight)
    }

    open override func computeMinIntrinsicHeight(_ width: Double) -> Double {
        return getMaxIntrinsicHeight(width)
    }

    open override func computeMaxIntrinsicHeight(_ width: Double) -> Double {
        _textIntrinsics.setPlaceholderDimensions(
            layoutInlineChildren(
                width,
                { (child: RenderBox, constraints: BoxConstraints) -> Size in
                    child.computeDryLayout(constraints)
                },
                { (_: RenderBox, _: BoxConstraints, _: TextBaseline) -> Double? in nil }
            )
        )
        return _preferredHeight(width)
    }

    /// Computes the distance to the actual baseline.
    ///
    /// **Dart Source:** `editable.dart:1988-1991`
    public override func computeDistanceToActualBaseline(_ baseline: TextBaseline) -> Double? {
        _computeTextMetricsIfNeeded()
        return _textPainter.computeDistanceToActualBaseline(baseline)
    }

    // MARK: - Hit Testing

    open override func hitTestSelf(_ position: Offset) -> Bool { true }

    open override func hitTestChildren(_ result: BoxHitTestResult, position: Offset) -> Bool {
        // TODO: Full implementation
        return false
    }

    // MARK: - Gesture Handling

    private var _lastTapDownPosition: Offset?
    private var _lastSecondaryTapDownPosition: Offset?

    /// The position of the most recent secondary tap down event.
    ///
    /// **Dart Source:** `editable.dart:2045`
    public var lastSecondaryTapDownPosition: Offset? { _lastSecondaryTapDownPosition }

    /// Tracks the position of a secondary tap event.
    ///
    /// **Dart Source:** `editable.dart:2051-2054`
    public func handleSecondaryTapDown(_ details: TapDownDetails) {
        _lastTapDownPosition = details.globalPosition
        _lastSecondaryTapDownPosition = details.globalPosition
    }

    /// If `ignorePointer` is false then this method is called by the internal
    /// gesture recognizer's `onTapDown` callback.
    ///
    /// **Dart Source:** `editable.dart:2062-2064`
    public func handleTapDown(_ details: TapDownDetails) {
        _lastTapDownPosition = details.globalPosition
    }

    /// If `ignorePointer` is false then this method is called by the internal
    /// gesture recognizer's `onTap` callback.
    ///
    /// **Dart Source:** `editable.dart:2077-2079`
    public func handleTap() {
        selectPosition(cause: .tap)
    }

    /// If `ignorePointer` is false then this method is called by the internal
    /// gesture recognizer's `onDoubleTap` callback.
    ///
    /// **Dart Source:** `editable.dart:2092-2094`
    public func handleDoubleTap() {
        selectWord(cause: .doubleTap)
    }

    /// If `ignorePointer` is false then this method is called by the internal
    /// gesture recognizer's `onLongPress` callback.
    ///
    /// **Dart Source:** `editable.dart:2102-2104`
    public func handleLongPress() {
        selectWord(cause: .longPress)
    }

    // MARK: - Selection Methods

    /// Move selection to the location of the last tap down.
    ///
    /// **Dart Source:** `editable.dart:2121-2123`
    public func selectPosition(cause: SelectionChangedCause) {
        selectPositionAt(from: _lastTapDownPosition!, cause: cause)
    }

    /// Select text between the global positions `from` and `to`.
    ///
    /// **Dart Source:** `editable.dart:2129-2148`
    public func selectPositionAt(
        from: Offset,
        to: Offset? = nil,
        cause: SelectionChangedCause
    ) {
        _computeTextMetricsIfNeeded()
        let fromPosition = _textPainter.getPositionForOffset(
            globalToLocal(from) - _paintOffset
        )
        let toPosition: TextPosition?
        if let to = to {
            toPosition = _textPainter.getPositionForOffset(
                globalToLocal(to) - _paintOffset
            )
        } else {
            toPosition = nil
        }

        let baseOffset = fromPosition.offset
        let extentOffset = toPosition?.offset ?? fromPosition.offset

        let newSelection = TextSelection(
            baseOffset: baseOffset,
            extentOffset: extentOffset
        )

        _setSelection(newSelection, cause)
    }

    /// Word boundaries access.
    ///
    /// **Dart Source:** `editable.dart:2151`
    public var wordBoundaries: WordBoundary { _textPainter.wordBoundaries }

    /// Select a word around the location of the last tap down.
    ///
    /// **Dart Source:** `editable.dart:2156-2158`
    public func selectWord(cause: SelectionChangedCause) {
        selectWordsInRange(from: _lastTapDownPosition!, cause: cause)
    }

    /// Selects the set of words that intersect a given range of global positions.
    ///
    /// **Dart Source:** `editable.dart:2168-2194`
    public func selectWordsInRange(
        from: Offset,
        to: Offset? = nil,
        cause: SelectionChangedCause
    ) {
        _computeTextMetricsIfNeeded()
        let fromPosition = _textPainter.getPositionForOffset(
            globalToLocal(from) - _paintOffset
        )
        let fromWord = getWordAtOffset(fromPosition)
        let toPosition: TextPosition
        if let to = to {
            toPosition = _textPainter.getPositionForOffset(
                globalToLocal(to) - _paintOffset
            )
        } else {
            toPosition = fromPosition
        }
        let toWord = toPosition == fromPosition
            ? fromWord
            : getWordAtOffset(toPosition)
        let isFromWordBeforeToWord = fromWord.start < toWord.end

        _setSelection(
            TextSelection(
                baseOffset: isFromWordBeforeToWord ? fromWord.base.offset : fromWord.extent.offset,
                extentOffset: isFromWordBeforeToWord ? toWord.extent.offset : toWord.base.offset
            ),
            cause
        )
    }

    /// Select to the beginning or end of a word.
    ///
    /// **Dart Source:** `editable.dart:2199-2213`
    public func selectWordEdge(cause: SelectionChangedCause) {
        _computeTextMetricsIfNeeded()
        assert(_lastTapDownPosition != nil)
        let position = _textPainter.getPositionForOffset(
            globalToLocal(_lastTapDownPosition!) - _paintOffset
        )
        let word = _textPainter.getWordBoundary(position)
        let newSelection: TextSelection
        if position.offset <= word.start {
            newSelection = TextSelection(offset: word.start)
        } else {
            newSelection = TextSelection(offset: word.end)
        }
        _setSelection(newSelection, cause)
    }

    /// Returns a `TextSelection` that encompasses the word at the given `TextPosition`.
    ///
    /// **Dart Source:** `editable.dart:2218-2276`
    public func getWordAtOffset(_ position: TextPosition) -> TextSelection {
        if position.offset >= plainText.count {
            return TextSelection(offset: plainText.count)
        }
        if obscureText {
            return TextSelection(baseOffset: 0, extentOffset: plainText.count)
        }
        let word = _textPainter.getWordBoundary(position)
        return TextSelection(baseOffset: word.start, extentOffset: word.end)
    }

    // MARK: - Text Metrics

    /// Placeholder dimensions for inline widgets.
    private var _placeholderDimensions: [PlaceholderDimensions]?

    /// Computes the text metrics if needed.
    ///
    /// **Dart Source:** `editable.dart:2316-2322`
    internal func _computeTextMetricsIfNeeded() {
        let (minW, maxW) = _adjustConstraints(
            minWidth: boxConstraints.minWidth,
            maxWidth: boxConstraints.maxWidth
        )
        _textPainter.layout(minWidth: minW, maxWidth: maxW)
    }

    /// The caret prototype rect.
    internal var _caretPrototype: Rect = Rect.zero

    /// Computes the caret prototype based on the platform.
    ///
    /// **Dart Source:** `editable.dart:2331-2347`
    private func _computeCaretPrototype() {
        // Use a simple default for all platforms in this stub
        _caretPrototype = Rect.fromLTWH(0.0, 0.0, cursorWidth, cursorHeight)
    }

    /// Computes the offset to apply to snap to physical pixels.
    ///
    /// **Dart Source:** `editable.dart:2351-2362`
    private func _snapToPhysicalPixel(_ sourceOffset: Offset) -> Offset {
        let globalOffset = localToGlobal(sourceOffset)
        let pixelMultiple = 1.0 / _devicePixelRatio
        return Offset(
            globalOffset.dx.isFinite
                ? (globalOffset.dx / pixelMultiple).rounded() * pixelMultiple - globalOffset.dx
                : 0,
            globalOffset.dy.isFinite
                ? (globalOffset.dy / pixelMultiple).rounded() * pixelMultiple - globalOffset.dy
                : 0
        )
    }

    // MARK: - Layout

    /// Compute dry layout.
    ///
    /// **Dart Source:** `editable.dart:2366-2384`
    open override func computeDryLayout(_ constraints: BoxConstraints) -> Size {
        let (minW, maxW) = _adjustConstraints(
            minWidth: constraints.minWidth,
            maxWidth: constraints.maxWidth
        )
        _textIntrinsics.setPlaceholderDimensions(
            layoutInlineChildren(
                constraints.maxWidth,
                { (child: RenderBox, constraints: BoxConstraints) -> Size in
                    child.computeDryLayout(constraints)
                },
                { (_: RenderBox, _: BoxConstraints, _: TextBaseline) -> Double? in nil }
            )
        )
        _textIntrinsics.layout(minWidth: minW, maxWidth: maxW)
        let width = _forceLine
            ? constraints.maxWidth
            : constraints.constrainWidth(_textIntrinsics.size.width + _caretMargin)
        return Size(width, constraints.constrainHeight(_preferredHeight(constraints.maxWidth)))
    }

    /// Do the work of computing the layout for this render object.
    ///
    /// **Dart Source:** `editable.dart:2405-2447`
    open override func performLayout() {
        let constraints = boxConstraints
        _placeholderDimensions = layoutInlineChildren(
            constraints.maxWidth,
            { (child: RenderBox, constraints: BoxConstraints) -> Size in
                child.computeDryLayout(constraints)
            },
            { (_: RenderBox, _: BoxConstraints, _: TextBaseline) -> Double? in nil }
        )
        let (minW, maxW) = _adjustConstraints(
            minWidth: constraints.minWidth,
            maxWidth: constraints.maxWidth
        )
        _textPainter.setPlaceholderDimensions(_placeholderDimensions)
        _textPainter.layout(minWidth: minW, maxWidth: maxW)
        if let boxes = _textPainter.inlinePlaceholderBoxes {
            positionInlineChildren(boxes)
        }
        _computeCaretPrototype()

        let width = _forceLine
            ? constraints.maxWidth
            : constraints.constrainWidth(_textPainter.width + _caretMargin)

        let preferredHeight: Double
        if maxLines == nil {
            preferredHeight = max(_textPainter.height, self.preferredLineHeight * Double(minLines ?? 0))
        } else if maxLines == 1 {
            preferredHeight = _textPainter.height
        } else {
            preferredHeight = clampDouble(
                _textPainter.height,
                self.preferredLineHeight * Double(minLines ?? maxLines!),
                self.preferredLineHeight * Double(maxLines!)
            )
        }

        size = Size(width, constraints.constrainHeight(preferredHeight))
        let contentSize = Size(_textPainter.width + _caretMargin, _textPainter.height)

        let painterConstraints = BoxConstraints.tight(contentSize)
        _foregroundRenderObject?.layout(painterConstraints)
        _backgroundRenderObject?.layout(painterConstraints)

        _maxScrollExtent = _getMaxScrollExtent(contentSize)
        let _ = offset.applyViewportDimension(_viewportExtent)
        let _ = offset.applyContentDimensions(0.0, _maxScrollExtent)
    }

    // MARK: - Floating Cursor

    private var _relativeOrigin = Offset.zero
    private var _previousOffset: Offset?
    private var _shouldResetOrigin = true
    private var _resetOriginOnLeft = false
    private var _resetOriginOnRight = false
    private var _resetOriginOnTop = false
    private var _resetOriginOnBottom = false
    private var _resetFloatingCursorAnimationValue: Double?

    private static func _calculateAdjustedCursorOffset(_ offset: Offset, _ boundingRects: Rect) -> Offset {
        let adjustedX = clampDouble(offset.dx, boundingRects.left, boundingRects.right)
        let adjustedY = clampDouble(offset.dy, boundingRects.top, boundingRects.bottom)
        return Offset(adjustedX, adjustedY)
    }

    /// Returns the position within the text field closest to the raw cursor offset.
    ///
    /// **Dart Source:** `editable.dart:2473-2535`
    public func calculateBoundedFloatingCursorOffset(
        _ rawCursorOffset: Offset,
        shouldResetOrigin: Bool? = nil
    ) -> Offset {
        let topBound = -floatingCursorAddedMargin.top
        let bottomBound = min(size.height, _textPainter.height)
            - preferredLineHeight
            + floatingCursorAddedMargin.bottom
        let leftBound = -floatingCursorAddedMargin.left
        let rightBound = min(size.width, _textPainter.width) + floatingCursorAddedMargin.right
        let boundingRects = Rect.fromLTRB(leftBound, topBound, rightBound, bottomBound)

        if let reset = shouldResetOrigin {
            _shouldResetOrigin = reset
        }

        if !_shouldResetOrigin {
            return Self._calculateAdjustedCursorOffset(rawCursorOffset, boundingRects)
        }

        var deltaPosition = Offset.zero
        if let prev = _previousOffset {
            deltaPosition = rawCursorOffset - prev
        }

        if _resetOriginOnLeft && deltaPosition.dx > 0 {
            _relativeOrigin = Offset(rawCursorOffset.dx - boundingRects.left, _relativeOrigin.dy)
            _resetOriginOnLeft = false
        } else if _resetOriginOnRight && deltaPosition.dx < 0 {
            _relativeOrigin = Offset(rawCursorOffset.dx - boundingRects.right, _relativeOrigin.dy)
            _resetOriginOnRight = false
        }
        if _resetOriginOnTop && deltaPosition.dy > 0 {
            _relativeOrigin = Offset(_relativeOrigin.dx, rawCursorOffset.dy - boundingRects.top)
            _resetOriginOnTop = false
        } else if _resetOriginOnBottom && deltaPosition.dy < 0 {
            _relativeOrigin = Offset(_relativeOrigin.dx, rawCursorOffset.dy - boundingRects.bottom)
            _resetOriginOnBottom = false
        }

        let currentX = rawCursorOffset.dx - _relativeOrigin.dx
        let currentY = rawCursorOffset.dy - _relativeOrigin.dy
        let adjustedOffset = Self._calculateAdjustedCursorOffset(
            Offset(currentX, currentY), boundingRects
        )

        if currentX < boundingRects.left && deltaPosition.dx < 0 {
            _resetOriginOnLeft = true
        } else if currentX > boundingRects.right && deltaPosition.dx > 0 {
            _resetOriginOnRight = true
        }
        if currentY < boundingRects.top && deltaPosition.dy < 0 {
            _resetOriginOnTop = true
        } else if currentY > boundingRects.bottom && deltaPosition.dy > 0 {
            _resetOriginOnBottom = true
        }

        _previousOffset = rawCursorOffset
        return adjustedOffset
    }

    /// Sets the screen position of the floating cursor and the text position
    /// closest to the cursor.
    ///
    /// **Dart Source:** `editable.dart:2544-2574`
    public func setFloatingCursor(
        _ state: FloatingCursorDragState,
        _ boundedOffset: Offset,
        _ lastTextPosition: TextPosition,
        resetLerpValue: Double? = nil
    ) {
        if state == .End {
            _relativeOrigin = Offset.zero
            _previousOffset = nil
            _shouldResetOrigin = true
            _resetOriginOnBottom = false
            _resetOriginOnTop = false
            _resetOriginOnRight = false
            _resetOriginOnLeft = false
        }
        _floatingCursorOn = state != .End
        _resetFloatingCursorAnimationValue = resetLerpValue
        if _floatingCursorOn {
            _floatingCursorTextPosition = lastTextPosition
            let animationValue = _resetFloatingCursorAnimationValue
            let sizeAdjustment: EdgeInsets
            if let animVal = animationValue {
                sizeAdjustment = EdgeInsets.lerp(
                    _kFloatingCursorSizeIncrease,
                    EdgeInsets.zero,
                    animVal
                ) ?? EdgeInsets.zero
            } else {
                sizeAdjustment = _kFloatingCursorSizeIncrease
            }
            _caretPainter.floatingCursorRect = sizeAdjustment
                .inflateRect(_caretPrototype)
                .shift(boundedOffset)
        } else {
            _caretPainter.floatingCursorRect = nil
        }
        _caretPainter.showRegularCaret = _resetFloatingCursorAnimationValue == nil
    }

    // MARK: - Vertical Caret Movement

    /// Starts a `VerticalCaretMovementRun` at the given location.
    ///
    /// **Dart Source:** `editable.dart:2609-2619`
    public func startVerticalCaretMovement(_ startPosition: TextPosition) -> VerticalCaretMovementRun {
        let metrics = _textPainter.computeLineMetrics()
        let currentLine = _lineNumberFor(startPosition, metrics)
        return VerticalCaretMovementRun(
            self,
            metrics,
            startPosition,
            currentLine.0,
            currentLine.1
        )
    }

    private func _lineNumberFor(_ startPosition: TextPosition, _ metrics: [LineMetrics]) -> (Int, Offset) {
        let offset = _textPainter.getOffsetForCaret(startPosition, Rect.zero)
        for lineMetrics in metrics {
            if lineMetrics.baseline > offset.dy {
                return (lineMetrics.lineNumber, Offset(offset.dx, lineMetrics.baseline))
            }
        }
        assert(startPosition.offset == 0, "unable to find the line for \(startPosition)")
        return (
            max(0, metrics.count - 1),
            Offset(
                offset.dx,
                metrics.isEmpty ? 0.0 : metrics.last!.baseline + metrics.last!.descent
            )
        )
    }

    // MARK: - Endpoints for Selection

    /// Returns the local coordinates of the endpoints of the given selection.
    ///
    /// **Dart Source:** `editable.dart:1743-1772`
    public func getEndpointsForSelection(_ selection: TextSelection) -> [TextSelectionPoint] {
        _computeTextMetricsIfNeeded()

        let paintOffset = _paintOffset

        let boxes: [TextBox]
        if selection.isCollapsed {
            boxes = []
        } else {
            boxes = _textPainter.getBoxesForSelection(
                selection,
                boxHeightStyle: selectionHeightStyle,
                boxWidthStyle: selectionWidthStyle
            )
        }

        if boxes.isEmpty {
            let caretOffset = _textPainter.getOffsetForCaret(selection.extent, _caretPrototype)
            let start = Offset(0.0, preferredLineHeight) + caretOffset + paintOffset
            return [TextSelectionPoint(start, nil)]
        } else {
            let start = Offset(
                clampDouble(boxes.first!.start, 0, _textPainter.size.width),
                boxes.first!.bottom
            ) + paintOffset
            let end = Offset(
                clampDouble(boxes.last!.end, 0, _textPainter.size.width),
                boxes.last!.bottom
            ) + paintOffset
            return [
                TextSelectionPoint(start, boxes.first!.direction),
                TextSelectionPoint(end, boxes.last!.direction),
            ]
        }
    }

    /// Returns the smallest `Rect` that covers the text within the `TextRange`.
    ///
    /// **Dart Source:** `editable.dart:1782-1801`
    public func getRectForComposingRange(_ range: TextRange) -> Rect? {
        if !range.isValid || range.isCollapsed { return nil }
        _computeTextMetricsIfNeeded()
        let boxes = _textPainter.getBoxesForSelection(
            TextSelection(baseOffset: range.start, extentOffset: range.end),
            boxHeightStyle: selectionHeightStyle,
            boxWidthStyle: selectionWidthStyle
        )
        var result: Rect?
        for box in boxes {
            let rect = box.toRect()
            if let r = result {
                result = r.expandToInclude(rect)
            } else {
                result = rect
            }
        }
        return result?.shift(_paintOffset)
    }

    /// Returns the position in the text for the given global coordinate.
    ///
    /// **Dart Source:** `editable.dart:1811-1814`
    public func getPositionForPoint(_ globalPosition: Offset) -> TextPosition {
        _computeTextMetricsIfNeeded()
        return _textPainter.getPositionForOffset(globalToLocal(globalPosition) - _paintOffset)
    }

    /// Returns the `Rect` in local coordinates for the caret at the given text position.
    ///
    /// **Dart Source:** `editable.dart:1827-1873`
    public func getLocalRectForCaret(_ caretPosition: TextPosition) -> Rect {
        _computeTextMetricsIfNeeded()
        let caretPrototype = _caretPrototype
        let caretOffset = _textPainter.getOffsetForCaret(caretPosition, caretPrototype)
        var caretRect = caretPrototype.shift(caretOffset + cursorOffset)
        let scrollableWidth = max(_textPainter.width + _caretMargin, size.width)

        let caretX = clampDouble(
            caretRect.left,
            0,
            max(scrollableWidth - _caretMargin, 0)
        )
        caretRect = Rect.fromLTWH(caretX, caretRect.top, caretRect.width, caretRect.height)

        let fullHeight = _textPainter.getFullHeightForCaret(caretPosition, caretPrototype)
        // Simple height adjustment (platform-neutral stub)
        let heightDiff = fullHeight - caretRect.height
        caretRect = Rect.fromLTWH(
            caretRect.left,
            caretRect.top + heightDiff / 2,
            caretRect.width,
            caretRect.height
        )

        caretRect = caretRect.shift(_paintOffset)
        return caretRect.shift(_snapToPhysicalPixel(caretRect.topLeft))
    }

    /// Returns the boxes that bound the given selection, adjusted for paint offset.
    ///
    /// **Dart Source:** `editable.dart:1316-1334`
    public func getBoxesForSelection(_ selection: TextSelection) -> [TextBox] {
        _computeTextMetricsIfNeeded()
        return _textPainter.getBoxesForSelection(
            selection,
            boxHeightStyle: selectionHeightStyle,
            boxWidthStyle: selectionWidthStyle
        ).map { textBox in
            TextBox(fromLTRBD:
                textBox.left + _paintOffset.dx,
                textBox.top + _paintOffset.dy,
                textBox.right + _paintOffset.dx,
                textBox.bottom + _paintOffset.dy,
                textBox.direction
            )
        }
    }

    // MARK: - Paint

    private func _paintContents(_ context: PaintingContext, _ offset: Offset) {
        let effectiveOffset = offset + _paintOffset

        if selection != nil && !_floatingCursorOn {
            _updateSelectionExtentsVisibility(effectiveOffset)
        }

        let foregroundChild = _foregroundRenderObject
        let backgroundChild = _backgroundRenderObject

        if let backgroundChild = backgroundChild {
            context.paintChild(backgroundChild, offset)
        }

        _textPainter.paint(context.canvas, effectiveOffset)
        paintInlineChildren(context, effectiveOffset)

        if let foregroundChild = foregroundChild {
            context.paintChild(foregroundChild, offset)
        }
    }

    private let _leaderLayerHandler = LayerHandle<LeaderLayer>()

    private func _paintHandleLayers(
        _ context: PaintingContext,
        _ endpoints: [TextSelectionPoint],
        _ offset: Offset
    ) {
        var startPoint = endpoints[0].point
        startPoint = Offset(
            clampDouble(startPoint.dx, 0.0, size.width),
            clampDouble(startPoint.dy, 0.0, size.height)
        )
        _leaderLayerHandler.layer = LeaderLayer(
            link: startHandleLayerLink,
            offset: startPoint + offset
        )
        if let layer = _leaderLayerHandler.layer {
            context.pushLayer(
                layer,
                { (ctx: PaintingContext, off: Offset) in },
                Offset.zero
            )
        }
        if endpoints.count == 2 {
            var endPoint = endpoints[1].point
            endPoint = Offset(
                clampDouble(endPoint.dx, 0.0, size.width),
                clampDouble(endPoint.dy, 0.0, size.height)
            )
            context.pushLayer(
                LeaderLayer(link: endHandleLayerLink, offset: endPoint + offset),
                { (ctx: PaintingContext, off: Offset) in },
                Offset.zero
            )
        }
    }

    private let _clipRectLayer = LayerHandle<ClipRectLayer>()

    /// Paint the editable.
    ///
    /// **Dart Source:** `editable.dart:2691-2710`
    open override func paint(_ context: PaintingContext, _ offset: Offset) {
        _computeTextMetricsIfNeeded()
        if _hasVisualOverflow && clipBehavior != .none {
            _clipRectLayer.layer = context.pushClipRect(
                needsCompositing,
                offset,
                Rect.fromLTWH(0, 0, size.width, size.height),
                _paintContents,
                clipBehavior: clipBehavior,
                oldLayer: _clipRectLayer.layer
            )
        } else {
            _clipRectLayer.layer = nil
            _paintContents(context, offset)
        }
        if let selection = self.selection, selection.isValid {
            _paintHandleLayers(context, getEndpointsForSelection(selection), offset)
        }
    }

    /// Returns a rect describing the approximate paint clip.
    ///
    /// **Dart Source:** `editable.dart:2715-2724`
    open func describeApproximatePaintClip(_ child: RenderObject) -> Rect? {
        switch clipBehavior {
        case .none:
            return nil
        case .hardEdge, .antiAlias, .antiAliasWithSaveLayer:
            return _hasVisualOverflow ? Rect.fromLTWH(0, 0, size.width, size.height) : nil
        @unknown default:
            return nil
        }
    }

    // MARK: - Attach / Detach

    open override func attach(_ owner: PipelineOwner) {
        super.attach(owner)
        _foregroundRenderObject?.attach(owner)
        _backgroundRenderObject?.attach(owner)
        _offset.addListener(markNeedsPaint, owner: self)
        _showHideCursor()
        _showCursor.addListener(_showHideCursor, owner: self)
    }

    open override func detach() {
        _offset.removeListeners(owner: self)
        _showCursor.removeListeners(owner: self)
        super.detach()
        _foregroundRenderObject?.detach()
        _backgroundRenderObject?.detach()
    }

    // MARK: - Dispose

    open override func dispose() {
        _leaderLayerHandler.layer = nil
        _foregroundRenderObject?.dispose()
        _foregroundRenderObject = nil
        _backgroundRenderObject?.dispose()
        _backgroundRenderObject = nil
        _clipRectLayer.layer = nil
        _cachedBuiltInForegroundPainters?.dispose()
        _cachedBuiltInPainters?.dispose()
        _selectionStartInViewport.dispose()
        _selectionEndInViewport.dispose()
        _autocorrectHighlightPainter.dispose()
        _selectionPainter.dispose()
        _caretPainter.dispose()
        _textPainter.dispose()
        _textIntrinsicsCache?.dispose()
        if _disposeShowCursor {
            _showCursor.dispose()
            _disposeShowCursor = false
        }
        super.dispose()
    }

    // MARK: - Mark Needs Paint Override

    open override func markNeedsPaint() {
        super.markNeedsPaint()
        _foregroundRenderObject?.markNeedsPaint()
        _backgroundRenderObject?.markNeedsPaint()
    }

    // MARK: - Paint Bounds

    open override var paintBounds: Rect {
        Rect.fromLTWH(0, 0, hasSize ? size.width : 0, hasSize ? size.height : 0)
    }
}
