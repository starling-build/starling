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

// MARK: - Pages

/// Paper size and margins, in points. `nil` on the layout means a continuous
/// column (a note, a text field); set, the flow is cut into pages at line
/// boundaries and every geometry query has a canvas-space twin.
public struct PageSetup: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var marginTop: Double
    public var marginBottom: Double
    public var marginLeft: Double
    public var marginRight: Double
    /// Space between pages on the canvas, in points.
    public var gap: Double

    public init(width: Double, height: Double, marginTop: Double = 72,
                marginBottom: Double = 72, marginLeft: Double = 72,
                marginRight: Double = 72, gap: Double = 18) {
        self.width = width
        self.height = height
        self.marginTop = marginTop
        self.marginBottom = marginBottom
        self.marginLeft = marginLeft
        self.marginRight = marginRight
        self.gap = gap
    }

    public static let letter = PageSetup(width: 612, height: 792)
    public static let a4 = PageSetup(width: 595.3, height: 841.9)

    public var contentWidth: Double { width - marginLeft - marginRight }
    public var contentHeight: Double { height - marginTop - marginBottom }
    public var isLandscape: Bool { width > height }

    public func rotated() -> PageSetup {
        var p = self
        swap(&p.width, &p.height)
        return p
    }
}

/// A run of one paragraph's flow placed on one page. `pageY` is measured
/// from the top of the page's content area; the piece covers flow
/// `flowTop ..< flowBottom`.
public struct PagePiece: Equatable, Sendable {
    public let paragraph: Int
    public let flowTop: Double
    public let flowBottom: Double
    public let page: Int
    public let pageY: Double
    public var height: Double { flowBottom - flowTop }
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

    /// Paginate when set. Geometry in FLOW space (the continuous column) is
    /// unchanged; the `canvas*` methods map it onto pages.
    public var pageSetup: PageSetup? {
        didSet { if pageSetup != oldValue { _pagesValid = false } }
    }

    private var _pages: [[PagePiece]] = []
    private var _piecesByParagraph: [[PagePiece]] = []
    private var _pagesValid = false

    /// Called when a picture finished decoding and the view should repaint.
    public var onNeedsRepaint: (() -> Void)?
    private var _decoded: [String: Image] = [:]
    private var _decoding: Set<String> = []
    private var _imageSize: [Size?] = []

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
        _imageSize = Array(repeating: nil, count: n)
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
        _pagesValid = false
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
                _imageSize.insert(contentsOf: Array(repeating: nil, count: n), at: at)
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
                _imageSize.removeSubrange(at ..< end)
                _textLeft.removeSubrange(at ..< end)
                _textWidth.removeSubrange(at ..< end)
                _spaceBefore.removeSubrange(at ..< end)
                _heights.removeSubrange(at ..< end)
                _tops.removeSubrange(at ..< end)
                _listNumbers.removeSubrange(at ..< end)
                _listValid = false
            }
            _topsValid = false
            _pagesValid = false
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
            _pagesValid = false
        }
        if pageSetup != nil && !_pagesValid { _paginate(document) }
    }

    // MARK: Pagination

    private var _pxPageW: Double { _px(pageSetup!.width) }
    private var _pxPageH: Double { _px(pageSetup!.height) }
    private var _pxGap: Double { _px(pageSetup!.gap) }
    private var _pxMarginTop: Double { _px(pageSetup!.marginTop) }
    private var _pxMarginLeft: Double { _px(pageSetup!.marginLeft) }
    private var _pxContentH: Double { _px(pageSetup!.contentHeight) }

    /// Cut the flow into pages. A paragraph that straddles a page boundary
    /// is split between lines (its painter is painted twice, clipped), so
    /// the breakable positions inside a block are the bottoms of its lines.
    private func _paginate(_ document: RichDocument) {
        _pages = [[]]
        let contentH = max(1, _pxContentH)
        var page = 0
        var y = 0.0
        func newPage() {
            _pages.append([])
            page += 1
            y = 0
        }
        for i in 0 ..< count {
            let g = geometry(i)
            if document.paragraphs[i].style.pageBreakBefore && (y > 0 || !_pages[page].isEmpty) {
                newPage()
            }
            var cursor = g.top
            var cuts: [Double]? = nil   // lazily computed line bottoms
            while cursor < g.bottom - 0.01 {
                let available = contentH - y
                let rest = g.bottom - cursor
                if rest <= available + 0.01 {
                    _pages[page].append(PagePiece(paragraph: i, flowTop: cursor, flowBottom: g.bottom,
                                                  page: page, pageY: y))
                    y += rest
                    cursor = g.bottom
                    break
                }
                if cuts == nil {
                    var list: [Double] = []
                    var ly = g.textTop
                    for line in g.painter.computeLineMetrics() {
                        ly += line.height
                        list.append(ly)
                    }
                    cuts = list
                    if Self.debugPagination {
                        let m = g.painter.computeLineMetrics()
                        let desc = "para \(i) top \(g.top) textTop \(g.textTop) bottom \(g.bottom) painterH \(g.painter.height) lines \(m.count) heights \(m.map { $0.height }) asc/desc \(m.first.map { "\($0.ascent)/\($0.descent)" } ?? "-") cursor \(cursor) y \(y) available \(available)\n"
                        _ = desc.withCString { write(2, $0, strlen($0)) }
                    }
                }
                // The lowest cut that still fits.
                var cut: Double? = nil
                for c in cuts! where c > cursor + 0.01 && c - cursor <= available + 0.01 { cut = c }
                if let cut {
                    _pages[page].append(PagePiece(paragraph: i, flowTop: cursor, flowBottom: cut,
                                                  page: page, pageY: y))
                    cursor = cut
                    newPage()
                } else if y > 0.01 {
                    // Nothing fits in what is left of this page: start a new one.
                    newPage()
                } else {
                    // A single line taller than a page: place it and overflow.
                    let next = cuts!.first(where: { $0 > cursor + 0.01 }) ?? g.bottom
                    _pages[page].append(PagePiece(paragraph: i, flowTop: cursor, flowBottom: next,
                                                  page: page, pageY: y))
                    cursor = next
                    newPage()
                }
            }
        }
        if _pages.count > 1 && _pages[_pages.count - 1].isEmpty { _pages.removeLast() }
        _piecesByParagraph = Array(repeating: [], count: count)
        for page in _pages {
            for piece in page { _piecesByParagraph[piece.paragraph].append(piece) }
        }
        _pagesValid = true
    }

    /// `STARLING_RICHTEXT_PERF=1` also prints page-break decisions.
    public static let debugPagination = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_PERF"] != nil

    public var isPaged: Bool { pageSetup != nil }
    public var pageCount: Int { isPaged ? max(1, _pages.count) : 1 }
    public var pieces: [[PagePiece]] { _pages }

    /// Page `p`'s rectangle on the canvas.
    public func pageRect(_ p: Int) -> Rect {
        Rect.fromLTWH(0, Double(p) * (_pxPageH + _pxGap), _pxPageW, _pxPageH)
    }

    /// The canvas: the page column when paged, else the flow itself.
    public var canvasSize: Size {
        guard isPaged else { return Size(width, totalHeight) }
        let n = Double(pageCount)
        return Size(_pxPageW, n * _pxPageH + (n - 1) * _pxGap)
    }

    /// Page index under canvas y (clamped).
    public func page(atCanvasY y: Double) -> Int {
        guard isPaged else { return 0 }
        let p = Int(floor(y / (_pxPageH + _pxGap)))
        return max(0, min(pageCount - 1, p))
    }

    /// Flow rectangle → canvas rectangles (one, unless it straddles pieces).
    public func canvasRects(_ r: Rect) -> [Rect] {
        guard isPaged else { return [r] }
        let i = paragraphIndex(atY: r.top)
        var out: [Rect] = []
        let pieces = _piecesByParagraph.indices.contains(i) ? _piecesByParagraph[i] : []
        for piece in pieces {
            let lo = max(r.top, piece.flowTop)
            let hi = min(r.bottom, piece.flowBottom)
            let inside = r.height <= 0 ? (r.top >= piece.flowTop && r.top < piece.flowBottom + 0.01) : hi > lo
            if !inside { continue }
            let dy = pageRect(piece.page).top + _pxMarginTop + piece.pageY - piece.flowTop
            out.append(Rect.fromLTRB(r.left + _pxMarginLeft, lo + dy,
                                     r.right + _pxMarginLeft, max(hi, lo) + dy))
        }
        if out.isEmpty, let piece = pieces.last ?? _pages.last?.last {
            // Past the last cut (a caret in trailing space-after): pin to the
            // piece's page.
            let dy = pageRect(piece.page).top + _pxMarginTop + piece.pageY - piece.flowTop
            out.append(Rect.fromLTRB(r.left + _pxMarginLeft, r.top + dy, r.right + _pxMarginLeft, r.bottom + dy))
        }
        return out
    }

    /// Canvas point → flow point. Points in a page's margins or in the gap
    /// snap to the nearest content on that page.
    public func flowPoint(_ p: Offset) -> Offset {
        guard isPaged else { return p }
        let page = self.page(atCanvasY: p.dy)
        let localY = p.dy - pageRect(page).top - _pxMarginTop
        let x = p.dx - _pxMarginLeft
        let pieces = _pages.indices.contains(page) ? _pages[page] : []
        guard let first = pieces.first, let last = pieces.last else {
            return Offset(x, totalHeight)
        }
        if localY <= first.pageY { return Offset(x, first.flowTop + max(0, localY - first.pageY)) }
        for piece in pieces where localY < piece.pageY + piece.height {
            return Offset(x, piece.flowTop + (localY - piece.pageY))
        }
        return Offset(x, last.flowBottom - 0.01)
    }

    public func canvasCaretRect(_ pos: RichPosition, _ document: RichDocument) -> Rect {
        canvasRects(caretRect(pos, document)).first!
    }

    public func canvasSelectionRects(_ sel: RichSelection, _ document: RichDocument) -> [Rect] {
        selectionRects(sel, document).flatMap { canvasRects($0) }
    }

    public func canvasPosition(at p: Offset, _ document: RichDocument) -> RichPosition {
        position(at: flowPoint(p), document)
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
        // Whole pixels: a page break clips between two lines, and a
        // fractional line box leaves the previous line's descenders peeking
        // into the next page (and its ascenders shaved off the previous).
        let before = _px(style.spaceBefore).rounded()
        let after = _px(style.spaceAfter > 0 ? style.spaceAfter : theme.spaceAfter)
        _painters[i] = painter
        _textLeft[i] = left
        _textWidth[i] = textWidth
        _spaceBefore[i] = before
        var bodyHeight = painter.height
        if let image = p.image {
            // Shown at its own size, shrunk to the column when wider.
            var w = _px(image.width)
            var h = _px(image.height)
            if w > textWidth { h *= textWidth / w; w = textWidth }
            _imageSize[i] = Size(w.rounded(), h.rounded())
            bodyHeight = h.rounded()
            _ensureDecoded(image)
        } else {
            _imageSize[i] = nil
        }
        _heights[i] = (before + bodyHeight + after).rounded(.up)
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

    // MARK: Pictures

    private func _ensureDecoded(_ image: ImageAttachment) {
        if _decoded[image.id] != nil || _decoding.contains(image.id) { return }
        _decoding.insert(image.id)
        let bytes = [UInt8](image.data)
        let id = image.id
        Task { @MainActor [weak self] in
            var decoded: Image? = nil
            do {
                let codec = try await instantiateImageCodec(bytes)
                let frame = try await codec.getNextFrame()
                codec.dispose()
                decoded = frame.image
            } catch {
                decoded = nil
            }
            guard let self else { decoded?.dispose(); return }
            self._decoding.remove(id)
            if let decoded {
                self._decoded[id] = decoded
                self.onNeedsRepaint?()
            }
        }
    }

    /// The picture's box for paragraph `i` in document space, or nil.
    public func imageRect(_ i: Int) -> Rect? {
        guard i < count, let size = _imageSize[i] else { return nil }
        let g = geometry(i)
        return Rect.fromLTWH(g.textLeft, g.textTop, size.width, size.height)
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
        if let box = imageRect(i) {
            return Rect.fromLTWH(box.left - 2, box.top, 2, box.height)
        }
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
            if let box = imageRect(i) {
                rects.append(box)
                continue
            }
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

    private func _paintParagraph(_ i: Int, _ canvas: any Canvas, _ document: RichDocument) {
        let g = geometry(i)
        if let image = document.paragraphs[i].image, let box = imageRect(i) {
            if let decoded = _decoded[image.id] {
                let paint = Paint()
                canvas.drawImageRect(decoded,
                                     Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height)),
                                     box, paint)
            } else {
                let paint = Paint()
                paint.style = .fill
                paint.color = Color(0x22808080)
                canvas.drawRect(box, paint)
            }
            return
        }
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

    /// Running header (left, halfway into the top margin) and footer
    /// (centred, halfway into the bottom margin), fields filled per page.
    private func _paintHeaderFooter(_ p: Int, _ canvas: any Canvas, _ document: RichDocument) {
        guard let setup = pageSetup else { return }
        let rect = pageRect(p)
        let n = pageCount
        let style = theme.textStyle(for: CharStyle(color: theme.textColor.withOpacity(0.7)),
                                    in: .body, scale: scale)
        let left = _px(setup.marginLeft)
        let width = _px(setup.contentWidth)
        if !document.header.isEmpty {
            let text = RichDocument.fill(document.header, page: p + 1, pageCount: n)
            let tp = TextPainter(text: TextSpan(text: text, style: style), textAlign: .left, textDirection: .ltr)
            tp.layout(minWidth: width, maxWidth: width)
            tp.paint(canvas, Offset(rect.left + left, rect.top + _px(setup.marginTop) / 2 - tp.height / 2))
            tp.dispose()
        }
        if !document.footer.isEmpty {
            let text = RichDocument.fill(document.footer, page: p + 1, pageCount: n)
            let tp = TextPainter(text: TextSpan(text: text, style: style), textAlign: .center, textDirection: .ltr)
            tp.layout(minWidth: width, maxWidth: width)
            tp.paint(canvas, Offset(rect.left + left, rect.bottom - _px(setup.marginBottom) / 2 - tp.height / 2))
            tp.dispose()
        }
    }

    /// Paint everything intersecting `visible` (CANVAS space), the canvas
    /// already translated so canvas (0, 0) is at the origin. `caret` is in
    /// canvas space too. `pageBackground` paints each visible page's paper
    /// before its text.
    public func paint(_ canvas: any Canvas, visible: Rect, document: RichDocument,
                      selection: RichSelection?, caret: Rect?,
                      pageBackground: ((Int, Rect) -> Void)? = nil) {
        if isPaged {
            let firstPage = page(atCanvasY: visible.top)
            let lastPage = page(atCanvasY: visible.bottom)
            for p in firstPage ... lastPage {
                pageBackground?(p, pageRect(p))
                _paintHeaderFooter(p, canvas, document)
            }
        }
        if let selection, !selection.isCollapsed {
            let paint = Paint()
            paint.color = theme.selectionColor
            paint.style = .fill
            for r in canvasSelectionRects(selection, document)
            where r.bottom >= visible.top && r.top <= visible.bottom {
                canvas.drawRect(r, paint)
            }
        }
        if isPaged {
            let firstPage = page(atCanvasY: visible.top)
            let lastPage = page(atCanvasY: visible.bottom)
            for p in firstPage ... lastPage where _pages.indices.contains(p) {
                let pageTop = pageRect(p).top + _pxMarginTop
                for piece in _pages[p] {
                    let top = pageTop + piece.pageY
                    let bottom = top + piece.height
                    if bottom < visible.top || top > visible.bottom { continue }
                    canvas.save()
                    canvas.clipRect(Rect.fromLTRB(0, top, _pxPageW, bottom))
                    canvas.translate(_pxMarginLeft, top - piece.flowTop)
                    _paintParagraph(piece.paragraph, canvas, document)
                    canvas.restore()
                }
            }
        } else {
            for i in paragraphs(intersecting: visible.top, visible.bottom) {
                let g = geometry(i)
                if g.bottom < visible.top || g.top > visible.bottom { continue }
                _paintParagraph(i, canvas, document)
            }
        }
        if let caret {
            let paint = Paint()
            paint.color = theme.caretColor
            paint.style = .fill
            canvas.drawRRect(RRect(fromRectAndRadius: caret, Radius(circular: 1)), paint)
        }
    }
}
