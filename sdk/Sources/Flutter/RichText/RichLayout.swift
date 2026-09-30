// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Geometry for a RichDocument: one TextPainter per paragraph, cached and
// invalidated by the controller's change log, so a keystroke lays out one
// paragraph and the rest keep their painters. Everything here is in
// "document space": (0, 0) is the top-left of the content column, `width`
// is the column width, y grows down through the paragraphs.
//
// Units: the model speaks points (11pt), the engine speaks logical pixels;
// `RichTextTheme.pixelsPerPoint` (96/72) times `scale` (zoom) converts.

import FlutterSwiftBridge
import Foundation

// MARK: - Theme

/// The document defaults a `CharStyle`/`RichParagraphStyle` resolve against.
public final class RichTextTheme {
    public var fontFamily: String?
    /// Points.
    public var fontSize: Double
    public var textColor: Color
    public var caretColor: Color
    public var selectionColor: Color
    public var linkColor: Color
    public var pixelsPerPoint: Double
    /// Heading font sizes in points, index 0 = Heading 1.
    public var headingSizes: [Double]
    public var headingColor: Color?
    /// Default spacing after a body paragraph, in points (Word: 8pt).
    public var spaceAfter: Double
    /// Default line spacing multiple (Word: 1.08; TextEdit: 1.0).
    public var lineSpacing: Double
    /// Hanging indent per list level, in points.
    public var listIndent: Double

    public init(fontFamily: String? = nil, fontSize: Double = 11,
                textColor: Color = Color(0xFF1B1B1B),
                caretColor: Color = Color(0xFF1B1B1B),
                selectionColor: Color = Color(0x5A3390FF),
                linkColor: Color = Color(0xFF0563C1),
                pixelsPerPoint: Double = 96.0 / 72.0,
                headingSizes: [Double] = [20, 16, 14, 12, 11, 11],
                headingColor: Color? = Color(0xFF2F5496),
                spaceAfter: Double = 8, lineSpacing: Double = 1.08,
                listIndent: Double = 36) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.textColor = textColor
        self.caretColor = caretColor
        self.selectionColor = selectionColor
        self.linkColor = linkColor
        self.pixelsPerPoint = pixelsPerPoint
        self.headingSizes = headingSizes
        self.headingColor = headingColor
        self.spaceAfter = spaceAfter
        self.lineSpacing = lineSpacing
        self.listIndent = listIndent
    }

    /// Resolve a run's style inside a paragraph to an engine TextStyle, at
    /// `scale` (zoom, 1.0 = 100%).
    public func textStyle(for style: CharStyle, in paragraph: RichParagraphStyle,
                          scale: Double) -> TextStyle {
        var size = style.fontSize ?? fontSize
        var bold = style.bold
        var color = style.color ?? textColor
        if let h = paragraph.heading, h >= 1 {
            let idx = min(h, headingSizes.count) - 1
            if style.fontSize == nil { size = headingSizes[idx] }
            if h <= 3 { bold = true }
            if style.color == nil, let hc = headingColor { color = hc }
        }
        if style.link != nil && style.color == nil { color = linkColor }
        var decorations: [TextDecoration] = []
        if style.underline || style.link != nil { decorations.append(.underline) }
        if style.strikethrough { decorations.append(.lineThrough) }
        let px = size * pixelsPerPoint * scale
        return TextStyle(
            color: color,
            backgroundColor: style.highlight,
            fontSize: style.script == .normal ? px : px * 0.65,
            fontWeight: bold ? .bold : .normal,
            fontStyle: style.italic ? .italic : .normal,
            height: paragraph.lineSpacing * lineSpacing,
            decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
            decorationColor: color,
            fontFamily: style.fontFamily ?? fontFamily
        )
    }
}

// MARK: - Layout

/// Laid-out geometry for one paragraph, in document space.
public struct ParagraphGeometry {
    public let painter: TextPainter
    /// Top of the block, including space-before.
    public let top: Double
    /// Height of the block, including space-before/after.
    public let height: Double
    /// Where the text itself starts.
    public let textTop: Double
    public let textLeft: Double
    public let textWidth: Double
    public var bottom: Double { top + height }
}

public final class RichLayout {
    public let theme: RichTextTheme

    /// Zoom. Invalidates every painter.
    public var scale: Double = 1.0 {
        didSet { if scale != oldValue { invalidateAll() } }
    }

    /// Content column width in logical pixels. Invalidates every painter.
    public var width: Double = 0 {
        didSet { if width != oldValue { invalidateAll() } }
    }

    private var _painters: [TextPainter?] = []
    private var _textLeft: [Double] = []
    private var _textWidth: [Double] = []
    private var _spaceBefore: [Double] = []
    private var _heights: [Double] = []
    private var _tops: [Double] = []
    private var _listNumbers: [Int] = []
    private var _topsValid = false
    private var _listValid = false

    public init(theme: RichTextTheme, paragraphCount: Int) {
        self.theme = theme
        _resize(paragraphCount)
    }

    public var count: Int { _painters.count }

    private func _resize(_ n: Int) {
        _painters = Array(repeating: nil, count: n)
        _textLeft = Array(repeating: 0, count: n)
        _textWidth = Array(repeating: 0, count: n)
        _spaceBefore = Array(repeating: 0, count: n)
        _heights = Array(repeating: 0, count: n)
        _tops = Array(repeating: 0, count: n)
        _listNumbers = Array(repeating: 0, count: n)
        _topsValid = false
        _listValid = false
    }

    public func invalidateAll() {
        for i in _painters.indices {
            _painters[i]?.dispose()
            _painters[i] = nil
        }
        _topsValid = false
        _listValid = false
    }

    /// Apply the controller's change log, keeping every untouched painter.
    public func apply(_ changes: [RichChange], paragraphCount: Int) {
        for change in changes {
            switch change {
            case .all:
                invalidateAll()
                _resize(paragraphCount)
            case .changed(let i):
                if i < _painters.count {
                    _painters[i]?.dispose()
                    _painters[i] = nil
                }
                _listValid = false
            case .inserted(let at, let n):
                let at = min(at, _painters.count)
                _painters.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _textLeft.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textWidth.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _spaceBefore.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _heights.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _tops.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _listNumbers.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _listValid = false
            case .removed(let at, let n):
                let at = min(at, _painters.count)
                let end = min(at + n, _painters.count)
                for i in at ..< end { _painters[i]?.dispose() }
                _painters.removeSubrange(at ..< end)
                _textLeft.removeSubrange(at ..< end)
                _textWidth.removeSubrange(at ..< end)
                _spaceBefore.removeSubrange(at ..< end)
                _heights.removeSubrange(at ..< end)
                _tops.removeSubrange(at ..< end)
                _listNumbers.removeSubrange(at ..< end)
                _listValid = false
            }
            _topsValid = false
        }
        if _painters.count != paragraphCount {
            // Defensive: the log and the document disagree — start over
            // rather than index past the end.
            invalidateAll()
            _resize(paragraphCount)
        }
    }

    // MARK: Laying out

    private func _px(_ points: Double) -> Double { points * theme.pixelsPerPoint * scale }

    /// Lay out every invalidated paragraph and recompute the tops.
    public func ensureLaidOut(_ document: RichDocument) {
        if _painters.count != document.paragraphs.count {
            invalidateAll()
            _resize(document.paragraphs.count)
        }
        if !_listValid { _renumberLists(document) }
        var changed = false
        for i in _painters.indices where _painters[i] == nil {
            _layoutParagraph(i, document.paragraphs[i])
            changed = true
        }
        if changed || !_topsValid {
            var y = 0.0
            for i in _heights.indices {
                _tops[i] = y
                y += _heights[i]
            }
            _topsValid = true
        }
    }

    private func _renumberLists(_ document: RichDocument) {
        var counters = [Int](repeating: 0, count: 10)
        for (i, p) in document.paragraphs.enumerated() {
            if p.style.list == .numbered {
                let lvl = min(p.style.listLevel, 9)
                counters[lvl] += 1
                for deeper in (lvl + 1) ..< 10 { counters[deeper] = 0 }
                _listNumbers[i] = counters[lvl]
            } else {
                _listNumbers[i] = 0
                if p.style.list == nil { for k in 0 ..< 10 { counters[k] = 0 } }
            }
        }
        _listValid = true
    }

    private func _layoutParagraph(_ i: Int, _ p: RichParagraph) {
        let style = p.style
        let left = _px(style.indentLeft)
            + (style.list != nil ? _px(theme.listIndent) * Double(style.listLevel + 1) : 0)
        let right = _px(style.indentRight)
        let textWidth = max(1, width - left - right)
        let painter = TextPainter(
            text: _span(for: p),
            textAlign: Self._textAlign(style.alignment),
            textDirection: .ltr
        )
        painter.layout(minWidth: textWidth, maxWidth: textWidth)
        let before = _px(style.spaceBefore)
        let after = _px(style.spaceAfter > 0 ? style.spaceAfter : theme.spaceAfter)
        _painters[i] = painter
        _textLeft[i] = left
        _textWidth[i] = textWidth
        _spaceBefore[i] = before
        _heights[i] = before + painter.height + after
        _topsValid = false
    }

    private static func _textAlign(_ a: ParagraphAlignment) -> TextAlign {
        switch a {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justify: return .justify
        }
    }

    /// The paragraph's runs as a span tree. An empty paragraph lays out a
    /// single space so it has a line height; offsets are clamped to 0 by
    /// every caller.
    private func _span(for p: RichParagraph) -> TextSpan {
        if p.text.isEmpty {
            return TextSpan(text: " ", style: theme.textStyle(for: p.runs[0].style, in: p.style, scale: scale))
        }
        if p.runs.count == 1 {
            return TextSpan(text: p.text, style: theme.textStyle(for: p.runs[0].style, in: p.style, scale: scale))
        }
        var children: [InlineSpan] = []
        children.reserveCapacity(p.runs.count)
        var pos = 0
        let utf16 = p.text.utf16
        for run in p.runs where run.length > 0 {
            let a = utf16.index(utf16.startIndex, offsetBy: pos)
            let b = utf16.index(a, offsetBy: run.length)
            children.append(TextSpan(text: String(utf16[a ..< b]) ?? "",
                                     style: theme.textStyle(for: run.style, in: p.style, scale: scale)))
            pos += run.length
        }
        return TextSpan(children: children)
    }

    // MARK: Geometry queries (call ensureLaidOut first)

    public var totalHeight: Double {
        guard let last = _tops.last, let h = _heights.last else { return 0 }
        return last + h
    }

    public func geometry(_ i: Int) -> ParagraphGeometry {
        ParagraphGeometry(painter: _painters[i]!, top: _tops[i], height: _heights[i],
                          textTop: _tops[i] + _spaceBefore[i], textLeft: _textLeft[i],
                          textWidth: _textWidth[i])
    }

    public func listLabel(_ i: Int, _ document: RichDocument) -> String? {
        let s = document.paragraphs[i].style
        switch s.list {
        case .none: return nil
        case .bullet: return s.listLevel % 2 == 0 ? "•" : "◦"
        case .numbered: return "\(_listNumbers[i])."
        }
    }

    /// Index of the paragraph containing document y (clamped to the ends).
    public func paragraphIndex(atY y: Double) -> Int {
        guard !_tops.isEmpty else { return 0 }
        if y < 0 { return 0 }
        var lo = 0
        var hi = _tops.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if _tops[mid] <= y { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Paragraphs whose blocks intersect the vertical range.
    public func paragraphs(intersecting top: Double, _ bottom: Double) -> Range<Int> {
        guard !_tops.isEmpty else { return 0 ..< 0 }
        let first = paragraphIndex(atY: top)
        var last = paragraphIndex(atY: bottom)
        if last < _tops.count - 1 { last += 1 }
        return first ..< min(_tops.count, last + 1)
    }

    /// Caret rectangle in document space.
    public func caretRect(_ pos: RichPosition, _ document: RichDocument) -> Rect {
        let i = max(0, min(pos.paragraph, count - 1))
        let g = geometry(i)
        let para = document.paragraphs[i]
        let offset = para.text.isEmpty ? 0 : max(0, min(pos.offset, para.length))
        let lineH = g.painter.preferredLineHeight
        let proto = Rect.fromLTWH(0, 0, 2, lineH)
        let o = g.painter.getOffsetForCaret(TextPosition(offset: offset), proto)
        let h = g.painter.getFullHeightForCaret(TextPosition(offset: offset), proto)
        return Rect.fromLTWH(g.textLeft + o.dx, g.textTop + o.dy, 2, h > 0 ? h : lineH)
    }

    /// Highlight rectangles for a selection, in document space.
    public func selectionRects(_ sel: RichSelection, _ document: RichDocument) -> [Rect] {
        guard !sel.isCollapsed else { return [] }
        let a = document.clamped(sel.start)
        let b = document.clamped(sel.end)
        var rects: [Rect] = []
        for i in a.paragraph ... b.paragraph {
            let g = geometry(i)
            let para = document.paragraphs[i]
            let lo = i == a.paragraph ? a.offset : 0
            let hi = i == b.paragraph ? b.offset : para.length
            if para.text.isEmpty || hi <= lo {
                // A selected empty paragraph (or the newline at a paragraph
                // end inside a multi-paragraph selection) shows as a sliver.
                if i != b.paragraph || para.text.isEmpty {
                    let c = caretRect(RichPosition(paragraph: i, offset: lo), document)
                    rects.append(Rect.fromLTWH(c.left, c.top, 6, c.height))
                }
                continue
            }
            for box in g.painter.getBoxesForSelection(
                TextSelection(baseOffset: lo, extentOffset: hi),
                boxHeightStyle: .max) {
                rects.append(Rect.fromLTRB(g.textLeft + box.left, g.textTop + box.top,
                                           g.textLeft + box.right, g.textTop + box.bottom))
            }
            if i != b.paragraph, let last = rects.last {
                // Extend past the line end to show the newline is included.
                rects[rects.count - 1] = Rect.fromLTRB(last.left, last.top, last.right + 6, last.bottom)
            }
        }
        return rects
    }

    /// The position nearest a point in document space.
    public func position(at point: Offset, _ document: RichDocument) -> RichPosition {
        guard count > 0 else { return .start }
        let i = paragraphIndex(atY: point.dy)
        let g = geometry(i)
        let para = document.paragraphs[i]
        if para.text.isEmpty { return RichPosition(paragraph: i, offset: 0) }
        let local = Offset(point.dx - g.textLeft, min(max(point.dy - g.textTop, 0), g.painter.height - 0.01))
        let tp = g.painter.getPositionForOffset(local)
        return RichPosition(paragraph: i, offset: para.alignedOffset(max(0, min(tp.offset, para.length))))
    }

    /// Start and end offsets of the visual line holding `pos`.
    public func lineBounds(_ pos: RichPosition, _ document: RichDocument) -> (start: Int, end: Int) {
        let i = max(0, min(pos.paragraph, count - 1))
        let para = document.paragraphs[i]
        if para.text.isEmpty { return (0, 0) }
        let g = geometry(i)
        let r = g.painter.getLineBoundary(TextPosition(offset: max(0, min(pos.offset, para.length))))
        var end = r.end
        // Exclude the soft-wrap space / hard newline at the end of the line
        // so End lands before it, as editors do.
        if end > r.start && end <= para.length && end > 0 {
            let idx = String.Index(utf16Offset: end - 1, in: para.text)
            if idx < para.text.endIndex, para.text[idx].isWhitespace, end < para.length { end -= 1 }
        }
        return (max(0, r.start), max(r.start, min(end, para.length)))
    }

    /// The position one line up or down from `pos`, keeping `x` (document
    /// space) — or nil at the document's top/bottom edge.
    public func verticalNeighbour(of pos: RichPosition, x: Double, down: Bool,
                                  _ document: RichDocument) -> RichPosition? {
        let c = caretRect(pos, document)
        let probeY = down ? c.bottom + 1 : c.top - 1
        if probeY < 0 || probeY >= totalHeight { return nil }
        return position(at: Offset(x, probeY), document)
    }

    // MARK: Painting

    /// Paint the paragraphs intersecting `visible` (document space) with the
    /// canvas already translated so that document (0, 0) is at the origin.
    public func paint(_ canvas: any Canvas, visible: Rect, document: RichDocument,
                      selection: RichSelection?, caret: Rect?) {
        let range = paragraphs(intersecting: visible.top, visible.bottom)
        if let selection, !selection.isCollapsed {
            let paint = Paint()
            paint.color = theme.selectionColor
            paint.style = .fill
            for r in selectionRects(selection, document) where r.bottom >= visible.top && r.top <= visible.bottom {
                canvas.drawRect(r, paint)
            }
        }
        for i in range {
            let g = geometry(i)
            if g.bottom < visible.top || g.top > visible.bottom { continue }
            if let label = listLabel(i, document) {
                let p = document.paragraphs[i]
                let markerStyle = theme.textStyle(for: p.runs[0].style, in: p.style, scale: scale)
                let marker = TextPainter(text: TextSpan(text: label, style: markerStyle),
                                         textAlign: .right, textDirection: .ltr)
                let slot = _px(theme.listIndent)
                marker.layout(minWidth: slot - 8, maxWidth: slot - 8)
                marker.paint(canvas, Offset(g.textLeft - slot, g.textTop))
                marker.dispose()
            }
            g.painter.paint(canvas, Offset(g.textLeft, g.textTop))
        }
        if let caret {
            let paint = Paint()
            paint.color = theme.caretColor
            paint.style = .fill
            canvas.drawRRect(RRect(fromRectAndRadius: caret, Radius(circular: 1)), paint)
        }
    }
}
