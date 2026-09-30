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
    /// The spelling underline.
    public var spellingColor: Color = Color(0xFFD03A2E)
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
    /// Word's Show/Hide ¶: a pilcrow at every paragraph's end (¤ in a
    /// table cell, as Word draws it).
    public var showMarks = false
    /// Maps a family name in the document to the family the engine draws
    /// with. The document keeps its own names — "Times New Roman" stays
    /// so, and is written back — while the app decides which shipped face
    /// stands in for it (Office: a metric-compatible clone). nil draws the
    /// name as given.
    public var fontFamilyResolver: ((String) -> String)? = nil

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
                          named: RichNamedStyle? = nil, scale: Double) -> TextStyle {
        var size = style.fontSize ?? named?.char.fontSize ?? fontSize
        var bold = style.bold || (named?.char.bold ?? false)
        let italic = style.italic || (named?.char.italic ?? false)
        var color = style.color ?? named?.char.color ?? textColor
        let family = (style.fontFamily ?? named?.char.fontFamily ?? fontFamily)
            .map { fontFamilyResolver?($0) ?? $0 }
        if named == nil, let h = paragraph.heading, h >= 1 {
            // A heading the sheet has no entry for: the theme's look.
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
            fontStyle: italic ? .italic : .normal,
            height: paragraph.lineSpacing * lineSpacing,
            decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
            decorationColor: color,
            fontFamily: family
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

    /// Text columns per page (Word's Layout → Columns) and the gap between
    /// them, in points. The flow fills a page's columns left to right.
    public var columns: Int = 1
    public var columnGap: Double = 36

    /// The width text wraps at: the content width shared by the columns.
    public var columnWidth: Double {
        let n = Double(max(1, columns))
        return (contentWidth - columnGap * (n - 1)) / n
    }

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
    /// A header row shown again at the top of a later page: painted and
    /// hit-tested there, but not where the paragraph lives.
    public var repeated = false
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
    /// Every page piece in generation order (paragraph order), and where
    /// each paragraph's pieces start in it — one flat array, not one array
    /// per paragraph, which cost a keystroke a thousand allocations.
    private var _allPieces: [PagePiece] = []
    private var _pieceStart: [Int] = []
    /// Cached from the style at layout time so pagination never copies a
    /// paragraph value just to read one flag.
    private var _pageBreak: [Bool] = []
    /// Paragraphs re-laid out since the last pass; nil means scan them all
    /// (after an insert, a removal, or invalidateAll).
    private var _dirty: [Int]? = []
    /// The lowest paragraph index changed since the last placement: the
    /// tops and pages before it are still right, so placement and
    /// pagination restart there. nil means from the top.
    private var _firstDirty: Int? = nil
    /// The highest changed index: past it, a paragraph whose top comes out
    /// where it was means nothing below moved, and both passes stop.
    private var _lastDirty: Int = 0
    private var _pagesValid = false

    /// Called when a picture finished decoding and the view should repaint.
    public var onNeedsRepaint: (() -> Void)?
    private var _decoded: [String: Image] = [:]
    private var _decoding: Set<String> = []
    private var _imageSize: [Size?] = []

    /// Table cells: per paragraph, the row's top and height (for borders and
    /// hit-testing) and the column geometry; nil for ordinary paragraphs.
    private struct _CellGeo {
        var table: String
        var row: Int
        var column: Int
        var rowTop: Double = 0
        var rowHeight: Double = 0
        var colLeft: Double = 0
        var colWidth: Double = 0
        var firstInRow = false
        var span = 1
        var rowSpan = 1
        /// The row's own height when the cell spans rows (rowHeight then
        /// covers every row it spans).
        var ownRowHeight: Double = 0
    }
    private var _cells: [_CellGeo?] = []
    /// Row top for every paragraph (its own top when not in a table): the
    /// monotonic sequence the binary search runs on.
    private var _rowTops: [Double] = []
    private var _flowHeight = 0.0
    private var _columnWidths: [String: [Double]] = [:]   // px, per table
    public var cellPadding: Double = 4   // px, inside a cell

    private var _painters: [TextPainter?] = []
    private var _textLeft: [Double] = []
    private var _textWidth: [Double] = []
    private var _spaceBefore: [Double] = []
    private var _heights: [Double] = []
    private var _tops: [Double] = []
    private var _listLabels: [String?] = []
    /// What each paragraph's list membership and cell were at its last
    /// layout: a change in either is what invalidates the numbering pass
    /// and the table pass, not a change in the paragraph's text.
    private var _listSig: [ListSig] = []
    private var _wasCell: [Bool] = []
    private var _tablesDirty = true
    private struct ListSig: Equatable {
        var kind: ListKind?
        var level: Int
        var id: String?
    }
    private var _topsValid = false
    private var _listValid = false

    public init(theme: RichTextTheme, paragraphCount: Int) {
        self.theme = theme
        _resize(paragraphCount)
    }

    // MARK: Spelling

    /// The checker, if any. Results are cached by paragraph text, so a
    /// paragraph is checked once per distinct text; paint records the
    /// paragraphs it could not answer for in `pendingSpellChecks`, and the
    /// editable runs `runSpellChecks` after a short idle.
    public var spellChecker: RichSpellChecker? {
        didSet {
            if spellChecker !== oldValue { _spellCache = [:]; _spellVersion = spellChecker?.version ?? 0 }
            onNeedsRepaint?()
        }
    }
    private var _spellCache: [String: [Range<Int>]] = [:]
    private var _spellVersion = 0
    public private(set) var pendingSpellChecks: [Int] = []
    /// The caret during a paint: its word is not underlined while typed.
    private var _paintCaret: RichPosition? = nil

    /// Check the paragraphs paint queued, newest first, within `budget`
    /// milliseconds; true when anything was checked (a repaint is due).
    @discardableResult
    public func runSpellChecks(_ document: RichDocument, budget: Double = 8) -> Bool {
        guard let checker = spellChecker else { pendingSpellChecks = []; return false }
        if checker.version != _spellVersion { _spellCache = [:]; _spellVersion = checker.version }
        if _spellCache.count > 4096 { _spellCache = [:] }
        let start = Date()
        var checked = false
        var queue = pendingSpellChecks
        pendingSpellChecks = []
        while !queue.isEmpty {
            let i = queue.removeFirst()
            guard i < document.paragraphs.count else { continue }
            let text = document.paragraphs[i].text
            if _spellCache[text] != nil { continue }
            _spellCache[text] = checker.misspelledRanges(in: text)
            checked = true
            if Date().timeIntervalSince(start) * 1000 > budget { break }
        }
        pendingSpellChecks = queue
        return checked
    }

    /// The misspelled range at `pos`, if that paragraph has been checked.
    public func misspelling(at pos: RichPosition, _ document: RichDocument) -> Range<Int>? {
        guard pos.paragraph < document.paragraphs.count,
              let ranges = _spellCache[document.paragraphs[pos.paragraph].text] else { return nil }
        return ranges.first { $0.lowerBound <= pos.offset && pos.offset <= $0.upperBound }
    }

    private func _paintSpelling(_ i: Int, _ g: ParagraphGeometry, _ canvas: any Canvas, _ document: RichDocument) {
        guard let checker = spellChecker else { return }
        if checker.version != _spellVersion { _spellCache = [:]; _spellVersion = checker.version }
        let para = document.paragraphs[i]
        guard !para.isImage, !para.text.isEmpty else { return }
        guard let ranges = _spellCache[para.text] else {
            if !pendingSpellChecks.contains(i) { pendingSpellChecks.append(i) }
            return
        }
        guard !ranges.isEmpty else { return }
        let paint = Paint()
        paint.style = .stroke
        paint.strokeWidth = 1
        paint.color = theme.spellingColor
        for r in ranges {
            if let c = _paintCaret, c.paragraph == i, r.lowerBound <= c.offset, c.offset <= r.upperBound { continue }
            for box in g.painter.getBoxesForSelection(TextSelection(baseOffset: r.lowerBound, extentOffset: r.upperBound),
                                                      boxHeightStyle: .max) {
                let y = (g.textTop + box.bottom - 1.5).rounded() + 0.5
                let x0 = g.textLeft + box.left, x1 = g.textLeft + box.right
                let path = Path()
                path.moveTo(x0, y)
                var x = x0
                var up = true
                while x < x1 {
                    x = min(x + 2, x1)
                    path.lineTo(x, up ? y - 1.5 : y)
                    up.toggle()
                }
                canvas.drawPath(path, paint)
            }
        }
    }

    public var count: Int { _painters.count }

    private func _resize(_ n: Int) {
        _painters = Array(repeating: nil, count: n)
        _imageSize = Array(repeating: nil, count: n)
        _cells = Array(repeating: nil, count: n)
        _rowTops = Array(repeating: 0, count: n)
        _textLeft = Array(repeating: 0, count: n)
        _textWidth = Array(repeating: 0, count: n)
        _spaceBefore = Array(repeating: 0, count: n)
        _heights = Array(repeating: 0, count: n)
        _tops = Array(repeating: 0, count: n)
        _listLabels = Array(repeating: nil, count: n)
        _listSig = Array(repeating: ListSig(kind: nil, level: 0, id: nil), count: n)
        _wasCell = Array(repeating: false, count: n)
        _pageBreak = Array(repeating: false, count: n)
        _tablesDirty = true
        _dirty = nil
        _firstDirty = 0
        _lastDirty = Int.max
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
        _dirty = nil
        _firstDirty = 0
        _lastDirty = Int.max
    }

    /// Apply the controller's change log, keeping every untouched painter.
    public func apply(_ changes: [RichChange], paragraphCount: Int) {
        for change in changes {
            switch change {
            case .all:
                invalidateAll()
                _resize(paragraphCount)
            case .lists:
                _listValid = false
            case .changed(let i):
                if i < _painters.count {
                    _painters[i]?.dispose()
                    _painters[i] = nil
                    _dirty?.append(i)
                    _firstDirty = min(_firstDirty ?? i, i)
                    _lastDirty = max(_lastDirty, i)
                    // A cell's text can change a row's height; its table's
                    // widths do not depend on it, but re-check cheaply.
                    if _wasCell[i] { _tablesDirty = true }
                }
            case .inserted(let at, let n):
                let at = min(at, _painters.count)
                _painters.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _imageSize.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _cells.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _rowTops.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textLeft.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textWidth.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _spaceBefore.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _heights.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _tops.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _listLabels.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _listSig.insert(contentsOf: Array(repeating: ListSig(kind: nil, level: 0, id: nil), count: n), at: at)
                _wasCell.insert(contentsOf: Array(repeating: false, count: n), at: at)
                _pageBreak.insert(contentsOf: Array(repeating: false, count: n), at: at)
                _tablesDirty = true
                _listValid = false
                _dirty = nil
                _firstDirty = min(_firstDirty ?? at, at)
                _lastDirty = Int.max
            case .removed(let at, let n):
                let at = min(at, _painters.count)
                let end = min(at + n, _painters.count)
                for i in at ..< end { _painters[i]?.dispose() }
                _painters.removeSubrange(at ..< end)
                _imageSize.removeSubrange(at ..< end)
                _cells.removeSubrange(at ..< end)
                _rowTops.removeSubrange(at ..< end)
                _textLeft.removeSubrange(at ..< end)
                _textWidth.removeSubrange(at ..< end)
                _spaceBefore.removeSubrange(at ..< end)
                _heights.removeSubrange(at ..< end)
                _tops.removeSubrange(at ..< end)
                _listLabels.removeSubrange(at ..< end)
                _listSig.removeSubrange(at ..< end)
                _wasCell.removeSubrange(at ..< end)
                _pageBreak.removeSubrange(at ..< end)
                _tablesDirty = true
                _dirty = nil
                _firstDirty = min(_firstDirty ?? at, at)
                _lastDirty = Int.max
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
    private static let _perf = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_PERF"] != nil

    public func ensureLaidOut(_ document: RichDocument) {
        let t0 = Self._perf ? DispatchTime.now().uptimeNanoseconds : 0
        var marks: [(String, UInt64)] = []
        func mark(_ name: String) { if Self._perf { marks.append((name, DispatchTime.now().uptimeNanoseconds)) } }
        defer {
            if Self._perf, marks.count > 1 {
                var prev = t0
                var line = "richlayout:"
                for (name, t) in marks { line += " \(name)=\((t - prev) / 1000)us"; prev = t }
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
        }
        if _painters.count != document.paragraphs.count {
            invalidateAll()
            _resize(document.paragraphs.count)
        }
        // The paragraphs to lay out: the ones changed since the last pass,
        // or every one without a painter after a structural change.
        let toLayout: [Int]
        if let dirty = _dirty {
            toLayout = dirty.count > 1 ? Array(Set(dirty)).sorted() : dirty
        } else {
            toLayout = _painters.indices.filter { _painters[$0] == nil }
        }
        _dirty = []
        // A paragraph whose list membership or cell changed since its last
        // layout invalidates the passes that depend on the whole document.
        for i in toLayout {
            let st = document.paragraphs[i].style
            let sig = ListSig(kind: st.list, level: st.listLevel, id: st.listId)
            if sig != _listSig[i] { _listValid = false; _listSig[i] = sig }
            let isCell = document.paragraphs[i].cell != nil
            if isCell != _wasCell[i] { _tablesDirty = true; _wasCell[i] = isCell }
            _pageBreak[i] = st.pageBreakBefore
        }
        mark("sigs")
        if !_listValid { _renumberLists(document) }
        var toLayoutNow = toLayout
        if _tablesDirty {
            _updateTables(document)
            _tablesDirty = false
            toLayoutNow = _painters.indices.filter { _painters[$0] == nil }
        }
        mark("lists+tables")
        var changed = false
        for i in toLayoutNow where _painters[i] == nil {
            _layoutParagraph(i, document.paragraphs[i], document)
            changed = true
        }
        mark("paragraphs")
        // Placement and pagination restart at the first changed paragraph
        // (its row's first member); everything above is as it was.
        // (_topsValid only says the tops need recomputing; the ones above
        // the first change are still right, which is what makes the
        // restart possible.)
        var from = min(_firstDirty ?? 0, max(0, _heights.count - 1))
        // Inside a table, restart at the table's first paragraph: a cell
        // spanning rows above the change decides heights below it.
        while from > 0, let c = _cells[from], let d = _cells[from - 1], c.table == d.table { from -= 1 }
        let settled = _lastDirty   // paragraphs above this may have moved
        if changed || !_topsValid {
            _placeBlocks(document, from: from, settled: settled)
            _topsValid = true
            _pagesValid = false
        }
        mark("place")
        if pageSetup != nil && !_pagesValid { _paginate(document, from: from, settled: settled) }
        _firstDirty = nil
        _lastDirty = 0
        mark("paginate")
    }

    /// Column widths per table (px); a table whose widths changed has every
    /// cell re-laid out.
    private func _updateTables(_ document: RichDocument) {
        var columns: [String: Int] = [:]
        for p in document.paragraphs {
            if let c = p.cell { columns[c.table] = max(columns[c.table] ?? 1, c.column + c.span) }
        }
        var widths: [String: [Double]] = [:]
        for p in document.paragraphs {
            guard let c = p.cell, widths[c.table] == nil else { continue }
            let cols = columns[c.table] ?? 1
            if let pts = _columnPreview[c.table] ?? document.tableColumns[c.table], pts.count == cols {
                widths[c.table] = pts.map { _px($0) }
            } else {
                widths[c.table] = Array(repeating: (width / Double(cols)).rounded(.down), count: cols)
            }
        }
        for (table, w) in widths where _columnWidths[table] != w {
            for i in document.paragraphs.indices where document.paragraphs[i].cell?.table == table {
                _painters[i]?.dispose()
                _painters[i] = nil
                _firstDirty = min(_firstDirty ?? i, i)
                _lastDirty = max(_lastDirty, i)
            }
        }
        _columnWidths = widths
    }

    /// Column widths (points) shown instead of the document's while a
    /// border is being dragged; the edit lands on release.
    private var _columnPreview: [String: [Double]] = [:]

    public func previewColumns(_ table: String, _ widths: [Double]?, _ document: RichDocument) {
        if widths == nil { _columnPreview[table] = nil } else { _columnPreview[table] = widths }
        _tablesDirty = true
        for i in document.paragraphs.indices where document.paragraphs[i].cell?.table == table {
            _painters[i]?.dispose()
            _painters[i] = nil
        }
        _topsValid = false
    }

    /// The column border under a document-space point, within `reach` px:
    /// the table and the index of the column whose right edge it is.
    public func columnBorder(at point: Offset, reach: Double = 4) -> (table: String, column: Int)? {
        guard !_rowTops.isEmpty else { return nil }
        let i = paragraphIndex(atY: point.dy)
        guard let c = _cells[i], point.dy >= c.rowTop, point.dy <= c.rowTop + c.rowHeight,
              let widths = _columnWidths[c.table] else { return nil }
        var x = 0.0
        for (k, w) in widths.enumerated() {
            x += w
            if abs(point.dx - x) <= reach { return (c.table, k) }
        }
        return nil
    }

    /// A table's column widths as laid out, in points.
    public func columnWidths(of table: String) -> [Double]? {
        _columnWidths[table].map { $0.map { $0 / (theme.pixelsPerPoint * scale) } }
    }

    /// Stack the blocks: ordinary paragraphs one under another, a table row's
    /// cells side by side with each column's paragraphs stacked inside it.
    private func _placeBlocks(_ document: RichDocument, from start: Int = 0, settled: Int = Int.max) {
        let n = _heights.count
        var i = min(start, n)
        // Continue below the block before the restart, which is as it was;
        // the restart index's own top may belong to a paragraph that moved.
        var y = 0.0
        if i > 0 {
            if let c = _cells[i - 1] { y = c.rowTop + c.ownRowHeight } else { y = _tops[i - 1] + _heights[i - 1] }
        }
        while i < n {
            // Past the last change, a block whose top is unchanged means
            // every block below is too (heights above it are the same).
            if i > settled, _rowTops[i] == y { return }
            guard let c = _cells[i] else {
                _tops[i] = y
                _rowTops[i] = y
                y += _heights[i]
                i += 1
                continue
            }
            // The table: every row of it, placed in turn; a cell spanning
            // rows takes its height from the rows it covers, and stretches
            // the last of them when its own content is taller.
            let table = c.table
            var rows: [(first: Int, end: Int, top: Double, height: Double)] = []
            var k0 = i
            while k0 < n, let d = _cells[k0], d.table == table {
                var j = k0
                while j < n, let d2 = _cells[j], d2.table == table, d2.row == d.row { j += 1 }
                var stack: [Int: Double] = [:]
                var rowHeight = 0.0
                for k in k0 ..< j {
                    let cell = _cells[k]!
                    let offset = stack[cell.column] ?? 0
                    _tops[k] = y + cellPadding + offset
                    _rowTops[k] = y
                    stack[cell.column] = offset + _heights[k]
                    // A spanning cell's content counts against the rows it spans, below.
                    if cell.rowSpan == 1 { rowHeight = max(rowHeight, offset + _heights[k]) }
                }
                rowHeight += cellPadding * 2
                for k in k0 ..< j {
                    _cells[k]!.rowTop = y
                    _cells[k]!.rowHeight = rowHeight
                    _cells[k]!.ownRowHeight = rowHeight
                    _cells[k]!.firstInRow = k == k0
                }
                rows.append((k0, j, y, rowHeight))
                y += rowHeight
                k0 = j
            }
            // Stretch for spanning cells, in row order; later rows shift.
            for (r, row) in rows.enumerated() {
                var stackByColumn: [Int: Double] = [:]
                for k in row.first ..< row.end {
                    let cell = _cells[k]!
                    guard cell.rowSpan > 1 else { continue }
                    stackByColumn[cell.column, default: 0] += _heights[k]
                    let need = stackByColumn[cell.column]! + cellPadding * 2
                    let last = min(rows.count - 1, r + cell.rowSpan - 1)
                    let have = rows[r ... last].map(\.height).reduce(0, +)
                    if need > have + 0.01 {
                        let extra = need - have
                        rows[last].height += extra
                        for (rr, later) in rows.enumerated() where rr > last { rows[rr].top = later.top + extra }
                    }
                }
            }
            // Second pass: final tops and heights, spanned heights for spanning cells.
            for (r, row) in rows.enumerated() {
                var stack: [Int: Double] = [:]
                for k in row.first ..< row.end {
                    let cell = _cells[k]!
                    let offset = stack[cell.column] ?? 0
                    _tops[k] = row.top + cellPadding + offset
                    _rowTops[k] = row.top
                    stack[cell.column] = offset + _heights[k]
                    _cells[k]!.rowTop = row.top
                    _cells[k]!.ownRowHeight = row.height
                    if cell.rowSpan > 1 {
                        let last = min(rows.count - 1, r + cell.rowSpan - 1)
                        _cells[k]!.rowHeight = rows[r ... last].map(\.height).reduce(0, +)
                    } else {
                        _cells[k]!.rowHeight = row.height
                    }
                }
            }
            if let last = rows.last { y = last.top + last.height }
            i = k0
        }
        _flowHeight = y
    }

    // MARK: Pagination

    private var _columns: Int { max(1, pageSetup?.columns ?? 1) }
    private var _pxColumnW: Double { _px(pageSetup!.columnWidth) }
    private var _pxColumnStride: Double { _px(pageSetup!.columnWidth + pageSetup!.columnGap) }
    private var _pxPageW: Double { _px(pageSetup!.width) }
    private var _pxPageH: Double { _px(pageSetup!.height) }
    private var _pxGap: Double { _px(pageSetup!.gap) }
    private var _pxMarginTop: Double { _px(pageSetup!.marginTop) }
    private var _pxMarginLeft: Double { _px(pageSetup!.marginLeft) }
    private var _pxContentH: Double { _px(pageSetup!.contentHeight) }

    /// Cut the flow into pages. A paragraph that straddles a page boundary
    /// is split between lines (its painter is painted twice, clipped), so
    /// the breakable positions inside a block are the bottoms of its lines.
    private func _paginate(_ document: RichDocument, from start: Int = 0, settled: Int = Int.max) {
        let contentH = max(1, _pxContentH)
        var page = 0
        var y = 0.0
        var i = 0
        var resumeCursor: Double? = nil
        // The previous result, to splice back in once the flow past the
        // change lands where it did before.
        let oldPieces = _allPieces
        let oldPages = _pages
        let oldStart = _pieceStart
        var restarted = false
        // Restart on the page where the first changed paragraph begins,
        // from that page's first piece; the pages before it are kept.
        if start > 0, start < count, _pieceStart.count == count + 1, _pieceStart[start] < _allPieces.count,
           case let p = _allPieces[_pieceStart[start]].page, p > 0, p < _pages.count,
           let first = _pages[p].first(where: { !$0.repeated }) {
            page = p
            i = first.paragraph
            resumeCursor = first.flowTop
            restarted = true
            _pages.removeSubrange(p...)
            _pages.append([])
            _pages[p].reserveCapacity(32)
            if let k = _allPieces.firstIndex(where: { $0.paragraph == i && $0.flowTop >= first.flowTop - 0.01 }) {
                _allPieces.removeSubrange(k...)
            } else {
                _allPieces.removeAll(keepingCapacity: true)
            }
        } else {
            _pages = [[]]
            _pages[0].reserveCapacity(32)
            _allPieces.removeAll(keepingCapacity: true)
        }
        func newPage() {
            var fresh: [PagePiece] = []
            fresh.reserveCapacity(32)
            _pages.append(fresh)
            page += 1
            y = 0
        }
        func add(_ piece: PagePiece) {
            _pages[page].append(piece)
            _allPieces.append(piece)
        }
        // A table's header row, repeated at the top of each later page it
        // runs on: the row's pieces again, marked, in the page only.
        func repeatHeader(of table: String, before i: Int) {
            var k0 = i
            while k0 > 0, let d = _cells[k0 - 1], d.table == table { k0 -= 1 }
            guard let h = _cells[k0], h.row == 0 else { return }
            var j = k0
            while j < count, let d = _cells[j], d.table == table, d.row == 0 { j += 1 }
            for k in k0 ..< j {
                let bottom = _cells[k]!.rowSpan > 1 ? h.rowTop + _cells[k]!.rowHeight : h.rowTop + h.ownRowHeight
                var piece = PagePiece(paragraph: k, flowTop: h.rowTop, flowBottom: bottom, page: page, pageY: y)
                piece.repeated = true
                _pages[page].append(piece)
            }
            y += h.ownRowHeight
        }
        while i < count {
            // Converged: this paragraph starts on the same page at the same
            // y as before and nothing below has changed, so the old pieces
            // and pages from here on are still right.
            if restarted, i > settled, resumeCursor == nil, oldStart.count == count + 1,
               oldStart[i] < oldPieces.count, case let old = oldPieces[oldStart[i]],
               old.page == page, abs(old.pageY - y) < 0.01, abs(old.flowTop - _tops[i]) < 0.01,
               page < oldPages.count {
                _allPieces.append(contentsOf: oldPieces[oldStart[i]...])
                _pages[page].append(contentsOf: oldPages[page].filter { $0.paragraph >= i })
                if page + 1 < oldPages.count { _pages.append(contentsOf: oldPages[(page + 1)...]) }
                break
            }
            if let c = _cells[i] {
                // A table row is one unbreakable block; every member gets the
                // row's piece so its text paints on the row's page.
                var j = i
                while j < count, let d = _cells[j], d.table == c.table, d.row == c.row { j += 1 }
                let rowBottom = c.rowTop + c.ownRowHeight
                resumeCursor = nil   // a row restarts whole
                if c.ownRowHeight > contentH - y + 0.01 && y > 0.01 { newPage() }
                if y < 0.01, c.row > 0, document.tableStyles[c.table]?.headerRow == true {
                    repeatHeader(of: c.table, before: i)
                }
                for k in i ..< j {
                    // A cell spanning rows paints through every row it covers.
                    let bottom = _cells[k]!.rowSpan > 1 ? c.rowTop + _cells[k]!.rowHeight : rowBottom
                    add(PagePiece(paragraph: k, flowTop: c.rowTop, flowBottom: bottom,
                                  page: page, pageY: y))
                }
                y += c.ownRowHeight
                if y > contentH - 0.01 { newPage() }
                i = j
                continue
            }
            defer { i += 1 }
            let top = _tops[i]
            let bottom = top + _heights[i]
            if _pageBreak[i] && (y > 0 || !_pages[page].isEmpty) && resumeCursor == nil {
                newPage()
            }
            var cursor = resumeCursor ?? top
            resumeCursor = nil
            var cuts: [Double]? = nil   // lazily computed line bottoms
            while cursor < bottom - 0.01 {
                let available = contentH - y
                let rest = bottom - cursor
                if rest <= available + 0.01 {
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: bottom,
                                                  page: page, pageY: y))
                    y += rest
                    cursor = bottom
                    break
                }
                if cuts == nil {
                    let g = geometry(i)
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
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: cut,
                                                  page: page, pageY: y))
                    cursor = cut
                    newPage()
                } else if y > 0.01 {
                    // Nothing fits in what is left of this page: start a new one.
                    newPage()
                } else {
                    // A single line taller than a page: place it and overflow.
                    let next = cuts!.first(where: { $0 > cursor + 0.01 }) ?? bottom
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: next,
                                                  page: page, pageY: y))
                    cursor = next
                    newPage()
                }
            }
        }
        if _pages.count > 1 && _pages[_pages.count - 1].isEmpty { _pages.removeLast() }
        // Pieces came out in paragraph order (a row's members are contiguous
        // and a paragraph's cuts consecutive), so one flat array indexed by
        // start replaces an array per paragraph.
        if _pieceStart.count != count + 1 { _pieceStart = Array(repeating: 0, count: count + 1) }
        var k = 0
        for para in 0 ... count {
            while k < _allPieces.count, _allPieces[k].paragraph < para { k += 1 }
            _pieceStart[para] = k
        }
        _pagesValid = true
    }

    /// `STARLING_RICHTEXT_PERF=1` also prints page-break decisions.
    public static let debugPagination = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_PERF"] != nil

    public var isPaged: Bool { pageSetup != nil }
    /// `_pages` holds one entry per column slot; a page has `columns` of them.
    public var pageCount: Int { isPaged ? max(1, (_pages.count + _columns - 1) / _columns) : 1 }
    /// Per column slot (page × columns + column), in flow order.
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
        let pieces = i + 1 < _pieceStart.count ? Array(_allPieces[_pieceStart[i] ..< _pieceStart[i + 1]]) : []
        for piece in pieces {
            let lo = max(r.top, piece.flowTop)
            let hi = min(r.bottom, piece.flowBottom)
            let inside = r.height <= 0 ? (r.top >= piece.flowTop && r.top < piece.flowBottom + 0.01) : hi > lo
            if !inside { continue }
            let dy = pageRect(piece.page / _columns).top + _pxMarginTop + piece.pageY - piece.flowTop
            let dx = _pxMarginLeft + Double(piece.page % _columns) * _pxColumnStride
            out.append(Rect.fromLTRB(r.left + dx, lo + dy, r.right + dx, max(hi, lo) + dy))
        }
        if out.isEmpty, let piece = pieces.last ?? _pages.last?.last {
            // Past the last cut (a caret in trailing space-after): pin to the
            // piece's page.
            let dy = pageRect(piece.page / _columns).top + _pxMarginTop + piece.pageY - piece.flowTop
            let dx = _pxMarginLeft + Double(piece.page % _columns) * _pxColumnStride
            out.append(Rect.fromLTRB(r.left + dx, r.top + dy, r.right + dx, r.bottom + dy))
        }
        return out
    }

    /// Canvas point → flow point. Points in a page's margins or in the gap
    /// snap to the nearest content on that page.
    public func flowPoint(_ p: Offset) -> Offset {
        guard isPaged else { return p }
        let page = self.page(atCanvasY: p.dy)
        let localY = p.dy - pageRect(page).top - _pxMarginTop
        // The column under x, then the point relative to it.
        let column = max(0, min(_columns - 1, Int(floor((p.dx - _pxMarginLeft) / max(1, _pxColumnStride)))))
        let x = p.dx - _pxMarginLeft - Double(column) * _pxColumnStride
        let slot = page * _columns + column
        let pieces = _pages.indices.contains(slot) ? _pages[slot] : []
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
        _listLabels = RichListNumbering.labels(document)
        _listValid = true
    }

    private func _layoutParagraph(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        let style = p.style
        var left = _px(style.indentLeft)
            + (style.list != nil ? _px(theme.listIndent) * Double(style.listLevel + 1) : 0)
        let right = _px(style.indentRight)
        var textWidth = max(1, width - left - right)
        if let c = p.cell {
            let widths = _columnWidths[c.table] ?? []
            let colWidth = c.column < widths.count
                ? widths[c.column ..< min(widths.count, c.column + c.span)].reduce(0, +) : width
            let colLeft = widths.prefix(c.column).reduce(0, +)
            _cells[i] = _CellGeo(table: c.table, row: c.row, column: c.column,
                                 colLeft: colLeft, colWidth: colWidth, span: c.span, rowSpan: c.rowSpan)
            left = colLeft + cellPadding + _px(style.indentLeft)
            textWidth = max(1, colWidth - cellPadding * 2 - _px(style.indentLeft) - right)
        } else {
            _cells[i] = nil
        }
        let painter = TextPainter(
            text: _span(for: p, document),
            textAlign: Self._textAlign(style.alignment),
            textDirection: .ltr
        )
        painter.layout(minWidth: textWidth, maxWidth: textWidth)
        // Whole pixels: a page break clips between two lines, and a
        // fractional line box leaves the previous line's descenders peeking
        // into the next page (and its ascenders shaved off the previous).
        let before = _px(style.spaceBefore).rounded()
        let after = p.cell != nil
            ? _px(style.spaceAfter)
            : _px(style.spaceAfter > 0 ? style.spaceAfter : theme.spaceAfter)
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
    private func _span(for p: RichParagraph, _ document: RichDocument) -> TextSpan {
        let named = document.styles.resolve(p.style)
        if p.text.isEmpty {
            return TextSpan(text: " ", style: theme.textStyle(for: p.runs[0].style, in: p.style, named: named, scale: scale))
        }
        if p.runs.count == 1 {
            return TextSpan(text: p.text, style: theme.textStyle(for: p.runs[0].style, in: p.style, named: named, scale: scale))
        }
        var children: [InlineSpan] = []
        children.reserveCapacity(p.runs.count)
        var pos = 0
        let utf16 = p.text.utf16
        for run in p.runs where run.length > 0 {
            let a = utf16.index(utf16.startIndex, offsetBy: pos)
            let b = utf16.index(a, offsetBy: run.length)
            children.append(TextSpan(text: String(utf16[a ..< b]) ?? "",
                                     style: theme.textStyle(for: run.style, in: p.style, named: named, scale: scale)))
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

    public var totalHeight: Double { _flowHeight }

    public func geometry(_ i: Int) -> ParagraphGeometry {
        ParagraphGeometry(painter: _painters[i]!, top: _tops[i], height: _heights[i],
                          textTop: _tops[i] + _spaceBefore[i], textLeft: _textLeft[i],
                          textWidth: _textWidth[i])
    }

    public func listLabel(_ i: Int, _ document: RichDocument) -> String? {
        if !_listValid || _listLabels.count != document.paragraphs.count { _renumberLists(document) }
        return _listLabels[i]
    }

    /// Index of the paragraph containing document y (clamped to the ends).
    /// Inside a table row this is some member of the row; `paragraphIndex(at:)`
    /// picks the cell by x.
    public func paragraphIndex(atY y: Double) -> Int {
        guard !_rowTops.isEmpty else { return 0 }
        if y < 0 { return 0 }
        var lo = 0
        var hi = _rowTops.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if _rowTops[mid] <= y { lo = mid } else { hi = mid - 1 }
        }
        // The search lands on the last row member with that top; step back
        // to the row's first member so callers see the whole row.
        while lo > 0, let c = _cells[lo], let d = _cells[lo - 1], c.table == d.table, c.row == d.row { lo -= 1 }
        return lo
    }

    /// The paragraph under a document-space point: the row by y, then the
    /// cell by x, then the paragraph within the cell's stack by y.
    public func paragraphIndex(at point: Offset) -> Int {
        let i = paragraphIndex(atY: point.dy)
        guard let c = _cells[i] else { return i }
        var best = i
        var j = i
        var hit = false
        while j < _cells.count, let d = _cells[j], d.table == c.table, d.row == c.row {
            if point.dx >= d.colLeft && point.dx < d.colLeft + d.colWidth {
                // In this column: the paragraph whose block spans y, else the last.
                best = j
                hit = true
                if point.dy < _tops[j] + _heights[j] { return j }
            }
            j += 1
        }
        if !hit {
            // No cell of this row under x: a cell from a row above spans here.
            var k = i - 1
            while k >= 0, let d = _cells[k], d.table == c.table {
                if d.rowSpan > 1, d.row + d.rowSpan > c.row, point.dx >= d.colLeft, point.dx < d.colLeft + d.colWidth {
                    var m = k
                    while m > 0, let e = _cells[m - 1], e.table == d.table, e.row == d.row, e.column == d.column { m -= 1 }
                    var last = m
                    while last + 1 < _cells.count, let e = _cells[last + 1], e.table == d.table, e.row == d.row, e.column == d.column { last += 1 }
                    for q in m ... last where point.dy < _tops[q] + _heights[q] { return q }
                    return last
                }
                k -= 1
            }
        }
        return best
    }

    /// The row's box in document space for a cell paragraph, else nil.
    public func rowRect(_ i: Int) -> Rect? {
        guard i < _cells.count, let c = _cells[i] else { return nil }
        let widths = _columnWidths[c.table] ?? []
        return Rect.fromLTWH(0, c.rowTop, widths.reduce(0, +), c.ownRowHeight)
    }

    /// Paragraphs whose blocks intersect the vertical range.
    public func paragraphs(intersecting top: Double, _ bottom: Double) -> Range<Int> {
        guard !_tops.isEmpty else { return 0 ..< 0 }
        let first = paragraphIndex(atY: top)
        var last = paragraphIndex(atY: bottom)
        while last < _tops.count - 1, let c = _cells[last], let d = _cells[last + 1], c.table == d.table, c.row == d.row { last += 1 }
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
        if let block = sel.block {
            // Whole cells: each selected cell's box, once per cell.
            var rects: [Rect] = []
            var seen: Set<String> = []
            // One rect per row a cell covers: a rect starting in a row maps
            // through that row's page piece, which ends at the row's bottom.
            var rowGeo: [Int: (top: Double, height: Double)] = [:]
            for i in document.paragraphs.indices {
                if let c = _cells[i], c.table == block.table, c.firstInRow { rowGeo[c.row] = (c.rowTop, c.ownRowHeight) }
            }
            for i in document.paragraphs.indices {
                guard let c = _cells[i], let ref = document.paragraphs[i].cell, block.contains(ref) else { continue }
                let key = "\(c.row),\(c.column)"
                if seen.contains(key) { continue }
                seen.insert(key)
                for r in c.row ..< c.row + c.rowSpan {
                    guard let g = rowGeo[r] else { continue }
                    rects.append(Rect.fromLTWH(c.colLeft, g.top, c.colWidth, g.height))
                }
            }
            return rects
        }
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
        let i = paragraphIndex(at: point)
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
        if let c = _cells[i], c.firstInRow, c.row == 0, document.tableStyles[c.table]?.headerRow == true {
            // The header row's shading, under every cell of the row.
            let fill = Paint()
            fill.style = .fill
            fill.color = theme.textColor.withOpacity(0.06)
            let width = (_columnWidths[c.table] ?? []).reduce(0, +)
            canvas.drawRect(Rect.fromLTWH(0, c.rowTop.rounded(), width.rounded(), c.ownRowHeight.rounded()), fill)
        }
        if let c = _cells[i], c.firstInRow, document.tableStyles[c.table]?.borders ?? true {
            let stroke = Paint()
            stroke.style = .stroke
            stroke.strokeWidth = 1
            stroke.color = theme.textColor.withOpacity(0.6)
            // Every line lies inside the row (the paint is clipped to the
            // row's page piece, so a stroke centred on the row's bottom
            // edge lost its outer half and the table's last row had no
            // bottom border). Rows share edges: a row draws its bottom and
            // only the first row its top; columns draw their left and only
            // the last its right.
            let widths = _columnWidths[c.table] ?? []
            let rowTop = c.rowTop.rounded()
            let rowBottom = (c.rowTop + c.ownRowHeight).rounded()
            let right = widths.reduce(0, +).rounded()
            if c.row == 0 {
                canvas.drawLine(Offset(0, rowTop + 0.5), Offset(right, rowTop + 0.5), stroke)
            }
            // Each cell of the row draws its left edge and, unless it spans
            // further down, its bottom; a cell from above that spans into
            // this row draws its left edge here too, and its bottom on its
            // last row.
            var j = i
            var lastColumn = -1
            while j < _cells.count, let d = _cells[j], d.table == c.table, d.row == c.row {
                if d.column != lastColumn {
                    canvas.drawLine(Offset(d.colLeft + 0.5, rowTop), Offset(d.colLeft + 0.5, rowBottom), stroke)
                    if d.rowSpan == 1 {
                        canvas.drawLine(Offset(d.colLeft, rowBottom - 0.5), Offset((d.colLeft + d.colWidth).rounded(), rowBottom - 0.5), stroke)
                    }
                    lastColumn = d.column
                }
                j += 1
            }
            var k = i - 1
            var seen: Set<Int> = []
            while k >= 0, let d = _cells[k], d.table == c.table {
                if d.rowSpan > 1, d.row < c.row, d.row + d.rowSpan > c.row, !seen.contains(d.column) {
                    seen.insert(d.column)
                    canvas.drawLine(Offset(d.colLeft + 0.5, rowTop), Offset(d.colLeft + 0.5, rowBottom), stroke)
                    if d.row + d.rowSpan - 1 == c.row {
                        canvas.drawLine(Offset(d.colLeft, rowBottom - 0.5), Offset((d.colLeft + d.colWidth).rounded(), rowBottom - 0.5), stroke)
                    }
                }
                k -= 1
            }
            canvas.drawLine(Offset(right - 0.5, rowTop), Offset(right - 0.5, rowBottom), stroke)
        }
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
        _paintSpelling(i, g, canvas, document)
        if theme.showMarks, !document.paragraphs[i].isImage {
            let end = caretRect(RichPosition(paragraph: i, offset: document.paragraphs[i].length), document)
            let style = theme.textStyle(for: CharStyle(color: theme.textColor.withOpacity(0.45)),
                                        in: document.paragraphs[i].style, scale: scale)
            let mark = TextPainter(text: TextSpan(text: document.paragraphs[i].cell == nil ? "\u{00B6}" : "\u{00A4}", style: style),
                                   textAlign: .left, textDirection: .ltr)
            mark.layout(minWidth: 0, maxWidth: 40)
            mark.paint(canvas, Offset(end.left + 1, end.top + (end.height - mark.height) / 2))
            mark.dispose()
        }
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
        _paintCaret = selection.flatMap { $0.isCollapsed ? $0.focus : nil }
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
            for p in firstPage ... lastPage {
                let pageTop = pageRect(p).top + _pxMarginTop
                for column in 0 ..< _columns {
                    let slot = p * _columns + column
                    guard _pages.indices.contains(slot) else { continue }
                    let left = _pxMarginLeft + Double(column) * _pxColumnStride
                    // One column clips to its own width; a lone column keeps
                    // the page, so a table wider than the text can still show.
                    let clipL = _columns > 1 ? left - 1 : 0
                    let clipR = _columns > 1 ? left + _pxColumnW + 1 : _pxPageW
                    for piece in _pages[slot] {
                        let top = pageTop + piece.pageY
                        let bottom = top + piece.height
                        if bottom < visible.top || top > visible.bottom { continue }
                        canvas.save()
                        canvas.clipRect(Rect.fromLTRB(clipL, top, clipR, bottom))
                        canvas.translate(left, top - piece.flowTop)
                        _paintParagraph(piece.paragraph, canvas, document)
                        canvas.restore()
                    }
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
