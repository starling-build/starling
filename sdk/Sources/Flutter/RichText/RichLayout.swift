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
    /// The face a family name is drawn with, by the name the document
    /// uses and by whether the text is East Asian (ideographs, kana,
    /// full-width forms) — or nil for `fontFamilyResolver`'s answer at
    /// the face's own measure. An app that knows how Word sets a name it
    /// has no face for answers here: a stand-in, the scale that gives
    /// the stand-in the original's widths, and the original's line
    /// height.
    public var faceResolver: ((String?, Bool) -> RichResolvedFace?)? = nil
    /// A Latin family's average character width in ems, by the name
    /// the document uses (nil: half an em). Word's automatic space
    /// between an ideograph and a Latin letter or digit is a quarter of
    /// this and the ideograph face's half em together — 0.225 em beside
    /// Times New Roman, 0.275 beside Courier New.
    public var averageCharWidth: ((String?) -> Double)? = nil
    /// Families tried, in order, for a character the run's own family
    /// lacks. Process-wide rather than per theme: it answers "which faces did
    /// this app load for coverage", which is one fact, and an app builds a
    /// theme in many places. Empty leaves the platform's own fallback — all
    /// there is on macOS and in the browser, and nothing at all on Linux,
    /// where a ⌘ in a Liberation run otherwise draws as a missing glyph and
    /// lays its line out a pixel shorter than everywhere else.
    public nonisolated(unsafe) static var glyphFallback: [String] = []
    /// Every paragraph's line spacing multiplied by this: PowerPoint's
    /// shrink-to-fit reduces the spacing of a whole body (`lnSpcReduction`)
    /// without touching what the paragraphs say.
    public var lineSpacingScale = 1.0
    /// Whether an empty list paragraph shows its marker: Word does,
    /// PowerPoint does not.
    public var marksEmptyListItems = true
    /// Where a list marker sits: right before the text (the editor's
    /// own look), or at the paragraph's hanging position — the list
    /// indent before the text, plus the first-line indent — as
    /// PowerPoint places a bullet at `marL + indent`.
    public var markersAtHang = false
    /// Whether text is set by Word's rules, for a word processor's
    /// pages: a first line set in by its first-line indent or out by a
    /// hanging one; a plain paragraph in Normal's face; East Asian
    /// stretches in the run's East Asian face, with Word's automatic
    /// space beside Latin text and its line-end rules for punctuation;
    /// lines of one height where faces mix. Off, a paragraph is laid
    /// out as the engine sets it (and PowerPoint's indent places the
    /// bullet, which `markersAtHang` handles).
    public var wordRules = false

    /// Each face's natural line height as a multiple of its size (ascent,
    /// descent and line gap — Calibri's 1.22, Arial's 1.15), measured once:
    /// what Word's and PowerPoint's "single" spacing is a multiple of.
    private var _naturalHeights: [String: Double] = [:]

    public func naturalLineHeight(family: String?, bold: Bool, italic: Bool) -> Double {
        let key = "\(family ?? "")|\(bold)|\(italic)"
        if let h = _naturalHeights[key] { return h }
        let probe = TextPainter(text: TextSpan(text: "x", style: TextStyle(fontSize: 100, fontWeight: bold ? .bold : .normal,
                                                                            fontStyle: italic ? .italic : .normal, fontFamily: family)),
                                textDirection: .ltr)
        probe.layout(minWidth: 0, maxWidth: 1000)
        let h = probe.height > 0 ? probe.height / 100 : 1.2
        probe.dispose()
        _naturalHeights[key] = h
        return h
    }

    public init(fontFamily: String? = nil, fontSize: Double = 11,
                textColor: Color = Color(0xFF1B1B1B),
                caretColor: Color = Color(0xFF1B1B1B),
                selectionColor: Color = Color(0x5A3390FF),
                linkColor: Color = Color(0xFF0563C1),
                pixelsPerPoint: Double = 96.0 / 72.0,
                headingSizes: [Double] = [20, 16, 14, 12, 11, 11],
                headingColor: Color? = Color(0xFF2F5496),
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
        self.listIndent = listIndent
        // A face that arrives later (the browser fetches fonts on demand)
        // has its own height: measure again.
        SystemFontsNotifier.shared.addListener({ [weak self] in self?._naturalHeights.removeAll() }, owner: self)
    }

    deinit { SystemFontsNotifier.shared.removeListeners(owner: self) }

    /// A line's height in points, and where its baseline sits below its
    /// top, for text of `size` in a face whose single line is `natural`
    /// ems tall with its baseline `baseline` ems down. Word's rules,
    /// measured from its prints (2026-10-12):
    ///
    /// - a multiple is of the natural height, and what it adds goes
    ///   below the text;
    /// - "at least" is that or the natural height, and what it adds
    ///   goes above;
    /// - an exact height stands whatever the face, its baseline 13/16
    ///   of the way down;
    /// - on a line grid (`gridPitch`) the line is as many whole pitches
    ///   as the text needs, and a multiple counts pitches rather than
    ///   text heights (14pt Song on a 15.6pt grid is 31.2 at single and
    ///   still 31.2 at 1.5 lines), with the text centred in it; "at
    ///   least" more than that adds the rest above. An exact height
    ///   ignores the grid, and so does "at least 0".
    public func lineBox(size: Double, natural: Double, baseline: Double?, in paragraph: RichParagraphStyle,
                        gridPitch: Double?) -> (height: Double, baseline: Double?) {
        let n = natural * size
        let t0 = baseline.map { $0 * size }
        let multiple = paragraph.lineSpacing * lineSpacingScale
        if let points = paragraph.lineHeightPoints, !paragraph.lineHeightIsMinimum {
            return (points, points * 13 / 16)
        }
        if let pitch = gridPitch, pitch > 0 {
            let snapped = (n / pitch - 0.002).rounded(.up) * pitch
            guard let points = paragraph.lineHeightPoints else {
                let h = max(snapped, multiple * pitch)
                return (h, t0.map { $0 + (h - n) / 2 })
            }
            if points > 0 {
                return (max(snapped, points), t0.map { $0 + (snapped - n) / 2 + max(0, points - snapped) })
            }
        }
        guard let points = paragraph.lineHeightPoints else { return (multiple * n, t0) }
        let h = max(points, multiple * n)
        return (h, t0.map { $0 + max(0, h - n) })
    }

    /// The baseline of a paragraph's lines below their tops, in points,
    /// by its East Asian stretch when it has one (the taller face, which
    /// sets the line) and its first run otherwise — or nil where the
    /// face's own is not known.
    public func baseline(for style: CharStyle, in paragraph: RichParagraphStyle, named: RichNamedStyle?,
                         eastAsian: Bool, gridPitch: Double?) -> Double? {
        let size = style.fontSize ?? named?.char.fontSize ?? fontSize
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        guard size > 0, let face = faceResolver?(familyName, eastAsian), let t = face.baseline else { return nil }
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        let natural = face.naturalHeight ?? naturalLineHeight(family: face.family, bold: bold, italic: italic)
        return lineBox(size: size, natural: natural, baseline: t, in: paragraph, gridPitch: gridPitch).baseline
    }

    /// Resolve a run's style inside a paragraph to an engine TextStyle, at
    /// `scale` (zoom, 1.0 = 100%).
    ///
    /// `eastAsian` is for a stretch of East Asian text: it takes the
    /// run's East Asian face when the file names one. `gridPitch` is the
    /// document's line grid (points), for a paragraph that snaps to it.
    /// `characterClass` picks one of the face's `classScales`.
    public func textStyle(for style: CharStyle, in paragraph: RichParagraphStyle,
                          named: RichNamedStyle? = nil, scale: Double,
                          eastAsian: Bool = false, gridPitch: Double? = nil, characterClass: Int? = nil) -> TextStyle {
        var size = style.fontSize ?? named?.char.fontSize ?? fontSize
        var bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        var color = style.color ?? named?.char.color ?? textColor
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let face = faceResolver?(familyName, eastAsian)
        let family = face?.family ?? familyName.map { fontFamilyResolver?($0) ?? $0 }
        let widen = (face?.sizeScale ?? 1)
            * (characterClass.flatMap { k in face?.classScales.flatMap { k < $0.count ? $0[k] : nil } } ?? 1)
        if named == nil, let h = paragraph.heading, h >= 1 {
            // A heading the sheet has no entry for: the theme's look.
            let idx = min(h, headingSizes.count) - 1
            if style.fontSize == nil { size = headingSizes[idx] }
            if h <= 3 { bold = true }
            if style.color == nil, let hc = headingColor { color = hc }
        }
        if style.link != nil && style.color == nil { color = linkColor }
        var decorations: [TextDecoration] = []
        if style.underline || ((style.link != nil || (named?.char.underline ?? false)) && !style.off.contains(.underline)) { decorations.append(.underline) }
        if style.strikethrough || ((named?.char.strikethrough ?? false) && !style.off.contains(.strikethrough)) { decorations.append(.lineThrough) }
        if let revision = style.revision {
            // Tracked changes as Word marks them: insertions underlined,
            // deletions struck through, both in the reviewer's colour.
            decorations.append(revision.kind == .deleted ? .lineThrough : .underline)
            if style.color == nil { color = Color(0xFFC00000) }
        }
        var px = size * widen * pixelsPerPoint * scale
        if style.hidden || ((named?.char.hidden ?? false) && !style.hidden) {
            // Hidden text takes no room and shows nothing, as Word prints it;
            // a hair of a size keeps the span (and the caret) in the line.
            px = 0.01
            color = color.withOpacity(0)
        }
        return TextStyle(
            color: color,
            // Commented text carries Word's balloon tint.
            backgroundColor: style.highlight ?? (style.comments.isEmpty ? nil : Color(0x40FFD966)),
            fontSize: style.script == .normal ? px : px * 0.65,
            fontWeight: bold ? .bold : .normal,
            fontStyle: italic ? .italic : .normal,
            letterSpacing: {
                // (A face with no bold of its own is emboldened by Word,
                // and each character set that much wider.)
                let spread = bold ? (face?.boldSpread ?? 0) * size : 0
                guard style.letterSpacing != nil || spread != 0 else { return nil }
                return ((style.letterSpacing ?? 0) + spread) * pixelsPerPoint * scale
            }(),
            // An exact line height is the same multiple of every run's own
            // size: points over size ("at least" that, or the multiple when
            // it is more). A multiple is of the face's natural line height
            // (the engine's `height` is of the size).
            height: {
                // (The engine's `height` is of the drawn size, and a
                // stand-in drawn larger or smaller keeps the line of the
                // size the document names.)
                let natural = face?.naturalHeight ?? naturalLineHeight(family: family, bold: bold, italic: italic)
                guard size > 0 else { return paragraph.lineSpacing * lineSpacingScale * natural / widen }
                return lineBox(size: size, natural: natural, baseline: nil, in: paragraph, gridPitch: gridPitch).height / (size * widen)
            }(),
            decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
            decorationColor: color,
            fontFamily: family,
            fontFamilyFallback: Self.glyphFallback.isEmpty ? nil : Self.glyphFallback
        )
    }
}

/// What `RichTextTheme.faceResolver` answers: the family to draw with,
/// the scale of the size that gives it the widths of the face it stands
/// in for, that face's line height as a multiple of the (unscaled) size
/// — nil for the drawn face's own — and how much wider, in ems, each
/// character is set in bold.
public struct RichResolvedFace: Sendable {
    public var family: String
    public var sizeScale: Double
    public var naturalHeight: Double?
    public var boldSpread: Double
    /// Further scales by kind of character — digits, capitals, small
    /// letters, the rest — where the stand-in's proportions are not the
    /// original's (nil: one scale for all).
    public var classScales: [Double]?
    /// How far below the top of its single line the face's baseline
    /// sits, in ems, as Word sets it (a Latin face's line gap goes above
    /// the ascent; an East Asian face's extra three tenths go half
    /// above, half below). nil where that is not known: the text then
    /// sits where the engine puts it.
    public var baseline: Double?
    /// Whether the name is an East Asian face's: the quotes, dashes and
    /// dots both scripts claim are then its full-width ones, whatever
    /// the run's hint.
    public var isEastAsian: Bool

    public init(family: String, sizeScale: Double = 1, naturalHeight: Double? = nil, boldSpread: Double = 0,
                classScales: [Double]? = nil, baseline: Double? = nil, isEastAsian: Bool = false) {
        self.baseline = baseline
        self.isEastAsian = isEastAsian
        self.family = family
        self.sizeScale = sizeScale
        self.naturalHeight = naturalHeight
        self.boldSpread = boldSpread
        self.classScales = classScales
    }

    /// The index into `classScales` for a character.
    public static func characterClass(_ ch: Character) -> Int {
        if ch.isNumber { return 0 }
        if ch.isUppercase { return 1 }
        if ch.isLowercase { return 2 }
        return 3
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
    /// Where the header's top and the footer's bottom sit from the page
    /// edges, in points (Word's pgMar header/footer; 0.49in by default).
    public var headerDistance: Double = 35.4
    public var footerDistance: Double = 35.4
    /// Whether a landscape page says so (Word's `w:orient`). A file that
    /// gives landscape dimensions without the attribute prints, in Word,
    /// onto portrait paper with the sides clipped — 60329 does — and the
    /// writer must not add what the file did not say, or the saved copy
    /// prints differently from the original. True for the editor's own.
    public var orientStated = true

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
        p.orientStated = true
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
    /// Where the painter is drawn from: `textTop`, moved by what puts
    /// the lines' baselines where Word has them.
    public var inkTop: Double { textTop + inkShift }
    public let inkShift: Double
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
    /// Per paragraph, its inline pictures in placeholder order.
    private var _inline: [[ImageAttachment]] = []
    /// A picture paragraph's float, when its picture is anchored.
    private var _floats: [ImageFloat?] = []

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
        /// The cell's own border sides, over the table's (`CellRef.edges`).
        var edges: BorderEdges? = nil
        /// Where the content sits in a taller row (`CellRef.verticalAlign`).
        var verticalAlign: String? = nil
        var direction: CellRef.CellTextDirection = .horizontal
        /// A turned cell: where this paragraph's block starts across the
        /// cell's width (from the left edge for text reading up, from the
        /// right edge for text reading down), padding included.
        var across: Double = 0
        /// The cell's margins, px: its own, or the table's.
        var pad = EdgeInsets.zero
        /// The cell's own edge lines (`CellRef.borders`).
        var borders = CellRef.CellBorders()
        var vertical: Bool { direction != .horizontal }
        /// Where a turned cell's text starts along its reading direction:
        /// at the bottom margin reading up, the top margin reading down.
        var alongStart: Double { direction == .up ? pad.bottom : pad.top }
        var acrossStart: Double { direction == .up ? pad.left : pad.right }
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
    /// What each paragraph's text is drawn lower by than the engine set
    /// it, so that its baselines are Word's (see `RichTextTheme.lineBox`).
    private var _inkShift: [Double] = []
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
        let lead = _lead(para, document)
        let paint = Paint()
        paint.style = .stroke
        paint.strokeWidth = 1
        paint.color = theme.spellingColor
        for r in ranges {
            if let c = _paintCaret, c.paragraph == i, r.lowerBound <= c.offset, c.offset <= r.upperBound { continue }
            for box in g.painter.getBoxesForSelection(TextSelection(baseOffset: r.lowerBound + lead, extentOffset: r.upperBound + lead),
                                                      boxHeightStyle: .max) {
                let y = (g.inkTop + box.bottom - 1.5).rounded() + 0.5
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
        _inline = Array(repeating: [], count: n)
        _floats = Array(repeating: nil, count: n)
        _cells = Array(repeating: nil, count: n)
        _rowTops = Array(repeating: 0, count: n)
        _textLeft = Array(repeating: 0, count: n)
        _textWidth = Array(repeating: 0, count: n)
        _spaceBefore = Array(repeating: 0, count: n)
        _inkShift = Array(repeating: 0, count: n)
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
                _inline.insert(contentsOf: Array(repeating: [], count: n), at: at)
                _floats.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _cells.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _rowTops.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textLeft.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textWidth.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _spaceBefore.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _inkShift.insert(contentsOf: Array(repeating: 0, count: n), at: at)
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
                _inline.removeSubrange(at ..< end)
                _floats.removeSubrange(at ..< end)
                _cells.removeSubrange(at ..< end)
                _rowTops.removeSubrange(at ..< end)
                _textLeft.removeSubrange(at ..< end)
                _textWidth.removeSubrange(at ..< end)
                _spaceBefore.removeSubrange(at ..< end)
                _inkShift.removeSubrange(at ..< end)
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

    /// Where a table's first column starts: the text column's left edge,
    /// or further in for a table narrower than the column that the document
    /// centres or right-aligns (Word's table alignment).
    /// A table's cell insets (px): its own margins where it has them, the
    /// layout's padding where not.
    private func _cellInsets(_ table: String, _ document: RichDocument) -> (top: Double, left: Double, bottom: Double, right: Double) {
        let s = document.tableStyles[table]
        return (s?.cellMarginTop.map(_px) ?? cellPadding, s?.cellMarginLeft.map(_px) ?? cellPadding,
                s?.cellMarginBottom.map(_px) ?? cellPadding, s?.cellMarginRight.map(_px) ?? cellPadding)
    }

    private func _tableLeft(_ table: String, _ document: RichDocument) -> Double {
        let sum = (_columnWidths[table] ?? []).reduce(0, +)
        switch document.tableStyles[table]?.alignment ?? .left {
        case .center: return max(0, ((width - sum) / 2).rounded(.down))
        case .right: return max(0, (width - sum).rounded(.down))
        default: return _px(document.tableStyles[table]?.indent ?? 0).rounded()
        }
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
                // Wider than the column: scaled to fit, as Word autofits a
                // table whose grid outgrows the page; a preferred width
                // (a share of the column, or points) scales the grid to it.
                let sum = pts.reduce(0, +)
                var scale = sum > 0 && _px(sum) > width ? width / _px(sum) : 1
                if sum > 0, _columnPreview[c.table] == nil, let ts = document.tableStyles[c.table] {
                    if let pct = ts.widthPercent { scale = min(width, width * pct / 100) / _px(sum) }
                    else if let w = ts.width { scale = min(width, _px(w)) / _px(sum) }
                }
                widths[c.table] = pts.map { (_px($0) * scale).rounded(.down) }
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
        var x = c.colLeft - widths.prefix(c.column).reduce(0, +)
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
            let ins = _cellInsets(table, document)
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
                    _tops[k] = y + cell.pad.top + offset
                    _rowTops[k] = y
                    stack[cell.column] = offset + _heights[k]
                    // A spanning cell's content counts against the rows it
                    // spans, below; a turned cell's against the placed height.
                    if cell.rowSpan == 1, !cell.vertical {
                        rowHeight = max(rowHeight, offset + _heights[k] + cell.pad.top + cell.pad.bottom)
                    }
                }
                // (A row of spanning or turned cells alone is still its
                // margins tall.)
                rowHeight = max(rowHeight, ins.top + ins.bottom)
                // A row the file gave a height: at least that tall.
                if let least = document.tableStyles[table]?.rowHeights[d.row] { rowHeight = max(rowHeight, _px(least)) }
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
                    guard cell.rowSpan > 1, !cell.vertical else { continue }
                    stackByColumn[cell.column, default: 0] += _heights[k]
                    let need = stackByColumn[cell.column]! + cell.pad.top + cell.pad.bottom
                    let last = min(rows.count - 1, r + cell.rowSpan - 1)
                    let have = rows[r ... last].map(\.height).reduce(0, +)
                    if need > have + 0.01 {
                        let extra = need - have
                        rows[last].height += extra
                        for (rr, later) in rows.enumerated() where rr > last { rows[rr].top = later.top + extra }
                    }
                }
            }
            // Turned cells: wrapped at the height the rows now have (as
            // PowerPoint wraps them), their lines stacking across the
            // column; a word longer than that height stretches the last
            // row the cell covers, as a spanning cell's content does.
            for (r, row) in rows.enumerated() {
                var k = row.first
                while k < row.end {
                    let cell = _cells[k]!
                    guard cell.vertical else { k += 1; continue }
                    var members = [k]
                    while members.last! + 1 < row.end, _cells[members.last! + 1]!.column == cell.column { members.append(members.last! + 1) }
                    k = members.last! + 1
                    let last = min(rows.count - 1, r + cell.rowSpan - 1)
                    let spanned = rows[r ... last].map(\.height).reduce(0, +)
                    var need = 0.0
                    for m in members {
                        let style = document.paragraphs[m].style
                        let inset = cell.pad.top + cell.pad.bottom + _px(style.indentLeft) + _px(style.indentRight)
                        guard let painter = _painters[m] else { continue }
                        var length = max(1, spanned - inset)
                        painter.layout(minWidth: length, maxWidth: length)
                        // No shorter than its longest word: the paragraph
                        // engine breaks the word instead, where PowerPoint
                        // makes the row taller. (The engine knows the word
                        // only once it has wrapped: after an unconstrained
                        // layout it reports nothing.)
                        let word = painter.minIntrinsicWidth.rounded(.up)
                        if word > length + 0.01 {
                            length = word
                            painter.layout(minWidth: length, maxWidth: length)
                        }
                        _textWidth[m] = length
                        _heights[m] = (_spaceBefore[m] + painter.height + _px(style.spaceAfter)).rounded(.up)
                        need = max(need, painter.longestLine + inset)
                    }
                    if need > spanned + 0.01 {
                        let extra = need - spanned
                        rows[last].height += extra
                        for (rr, later) in rows.enumerated() where rr > last { rows[rr].top = later.top + extra }
                    }
                }
            }
            // Second pass: final tops and heights, spanned heights for spanning cells.
            for (r, row) in rows.enumerated() {
                // Each cell's content height, for anchoring it in a taller
                // row (a turned cell's content width, across the column).
                var content: [Int: Double] = [:]
                for k in row.first ..< row.end { content[_cells[k]!.column, default: 0] += _heights[k] }
                var stack: [Int: Double] = [:]
                for k in row.first ..< row.end {
                    let cell = _cells[k]!
                    let offset = stack[cell.column] ?? 0
                    let last = min(rows.count - 1, r + cell.rowSpan - 1)
                    let spanned = cell.rowSpan > 1 ? rows[r ... last].map(\.height).reduce(0, +) : row.height
                    let room = cell.vertical ? cell.colWidth - cell.pad.left - cell.pad.right : spanned - cell.pad.top - cell.pad.bottom
                    let free = max(0, room - (content[cell.column] ?? 0))
                    let shift = cell.verticalAlign == "center" ? free / 2 : cell.verticalAlign == "bottom" ? free : 0
                    if cell.vertical {
                        _tops[k] = row.top
                        _cells[k]!.across = cell.acrossStart + offset + shift
                    } else {
                        _tops[k] = row.top + cell.pad.top + offset + shift
                    }
                    _rowTops[k] = row.top
                    stack[cell.column] = offset + _heights[k]
                    _cells[k]!.rowTop = row.top
                    _cells[k]!.ownRowHeight = row.height
                    if cell.rowSpan > 1 {
                        _cells[k]!.rowHeight = spanned
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
                        FileHandle.standardError.write(Data(desc.utf8))
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

    /// The laid-out document, one text line per line: `p<page> ¶<paragraph>
    /// <height> |<text>|`, after a first line with the page count. Two
    /// layouts that agree — native and browser, before and after a save —
    /// produce identical text, and where they differ, `diff` says which
    /// line broke elsewhere. Heights are logical pixels to a tenth.
    public func lineDump(_ document: RichDocument) -> String {
        ensureLaidOut(document)
        var out = "pages \(pageCount)\n"
        for i in 0 ..< count {
            let para = document.paragraphs[i]
            let g = geometry(i)
            let pieces = _pieceStart.count == count + 1 ? _allPieces[_pieceStart[i] ..< _pieceStart[i + 1]] : []
            func page(atFlow y: Double) -> Int {
                let piece = pieces.first { y < $0.flowBottom - 0.01 } ?? pieces.last
                return piece.map { $0.page / _columns + 1 } ?? 0
            }
            // The block: its height with the spacing around the text, and
            // where the text starts inside it — what pagination sums.
            out += "¶\(i) block \(_tenth(g.height)) text@\(_tenth(g.textTop - g.top))\n"
            if para.isImage {
                out += "p\(page(atFlow: g.textTop)) ¶\(i) \(_tenth(g.height)) |<image>|\n"
                continue
            }
            let utf16 = para.text.utf16
            var y = g.textTop
            var start = 0
            let lines = g.painter.computeLineMetrics()
            let lead = _lead(para, document)
            for line in lines {
                let r = g.painter.getLineBoundary(TextPosition(offset: start + lead))
                let end = max(start, min(r.end - lead, para.length))
                let a = utf16.index(utf16.startIndex, offsetBy: start)
                let b = utf16.index(utf16.startIndex, offsetBy: end)
                let text = (String(utf16[a ..< b]) ?? "").trimmingWhitespace()
                out += "p\(page(atFlow: y)) ¶\(i) \(_tenth(line.height)) |\(text)|\n"
                y += line.height
                start = end
                if start >= para.length { break }
            }
            if lines.isEmpty { out += "p\(page(atFlow: y)) ¶\(i) \(_tenth(g.painter.height)) ||\n" }
        }
        return out
    }

    private func _tenth(_ v: Double) -> String {
        let t = Int((v * 10).rounded())
        return "\(t / 10).\(t % 10)"
    }

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
        // By the rect's middle, not its top edge: a rect is never taller
        // than its paragraph, and a sub-pixel overshoot at either edge must
        // not hand it to a neighbour whose pieces then clip it to a sliver.
        let i = paragraphIndex(atY: r.height > 0 ? (r.top + r.bottom) / 2 : r.top)
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
            let colLeft = _tableLeft(c.table, document) + widths.prefix(c.column).reduce(0, +)
            let ins = _cellInsets(c.table, document)
            let pad = c.padding.map { EdgeInsets(left: _px($0.left), top: _px($0.top), right: _px($0.right), bottom: _px($0.bottom)) }
                ?? EdgeInsets(left: ins.left, top: ins.top, right: ins.right, bottom: ins.bottom)
            _cells[i] = _CellGeo(table: c.table, row: c.row, column: c.column,
                                 colLeft: colLeft, colWidth: colWidth, span: c.span, rowSpan: c.rowSpan, edges: c.edges,
                                 verticalAlign: c.verticalAlign, direction: c.textDirection, pad: pad, borders: c.borders)
            left = colLeft + pad.left + _px(style.indentLeft)
            textWidth = max(1, colWidth - pad.left - pad.right - _px(style.indentLeft) - right)
            if c.textDirection != .horizontal {
                // Turned text runs along the row's height, which the row's
                // other cells decide: laid out provisionally at the rows'
                // own heights, and again at the placed height in
                // `_placeBlocks`.
                let heights = document.tableStyles[c.table]?.rowHeights ?? [:]
                let own = (c.row ..< c.row + c.rowSpan).reduce(0.0) { $0 + (heights[$1] ?? 0) }
                textWidth = own > 0 ? max(1, _px(own) - pad.top - pad.bottom - _px(style.indentLeft) - right) : 100_000
            }
        } else {
            _cells[i] = nil
        }
        let (span, inline) = _span(for: p, document, textWidth: textWidth)
        // A right-to-left paragraph runs from the right, and its "left"
        // (Word's start) is the right edge.
        var align = Self._textAlign(style.alignment)
        if style.rightToLeft {
            switch style.alignment {
            case .left: align = .right
            case .right: align = .left
            default: break
            }
        }
        func laidOut(_ span: TextSpan) -> TextPainter {
            let painter = TextPainter(
                text: span,
                textAlign: align,
                textDirection: style.rightToLeft ? .rtl : .ltr,
                // (A picture in the line makes its own line taller.)
                strutStyle: inline.contains(where: { $0.image != nil }) ? nil : _strut(span)
            )
            if !inline.isEmpty { painter.setPlaceholderDimensions(inline.map { $0.dimensions }) }
            painter.layout(minWidth: textWidth, maxWidth: textWidth)
            return painter
        }
        for item in inline { if let image = item.image { _ensureDecoded(image) } }
        _inline[i] = inline.compactMap(\.image)
        _floats[i] = p.image?.float
        var painter = laidOut(span)
        // East Asian line ends, as Word sets them: a closing mark that
        // would start a line hangs past the margin instead, and a line
        // half an em too long for its last character takes it anyway,
        // off one of its punctuation marks. The engine breaks lines by
        // width alone, so the marks are narrowed by what each line
        // needs and the paragraph laid out again.
        let fit = _fitEastAsianLines(p, document, span: span, dimensions: inline.map { $0.dimensions }, width: textWidth, first: painter)
        if !fit.isEmpty {
            painter.dispose()
            painter = laidOut(_span(for: p, document, textWidth: textWidth, adjust: fit).0)
        }
        // Whole pixels: a page break clips between two lines, and a
        // fractional line box leaves the previous line's descenders peeking
        // into the next page (and its ascenders shaved off the previous).
        // A border's line and its gap lie between the spacing and the text.
        let bTop = style.borders?.top.map { _px($0.space + $0.width) } ?? 0
        let bBottom = style.borders?.bottom.map { _px($0.space + $0.width) } ?? 0
        // Word's auto spacing: 14pt, none between items of a list.
        let autoGap = style.list == nil ? 14.0 : 0.0
        // Contextual spacing: no space against a neighbour of the same style.
        func sameStyle(_ j: Int) -> Bool {
            guard j >= 0, j < document.paragraphs.count else { return false }
            let o = document.paragraphs[j].style
            return o.named == style.named && o.heading == style.heading && o.list == style.list
        }
        let skipBefore = style.contextualSpacing && sameStyle(i - 1)
        let skipAfter = style.contextualSpacing && sameStyle(i + 1)
        // Automatic spacing is the web's, unless the document says its
        // own numbers stand: see `RichDocument.htmlAutoSpacing`.
        let web = !theme.wordRules || document.htmlAutoSpacing
        func spaceAfter(_ s: RichParagraphStyle) -> Double {
            web && s.spaceAfterAuto ? (s.list == nil ? 14.0 : 0.0) : s.spaceAfter
        }
        var spaceBefore = web && style.spaceBeforeAuto ? autoGap : style.spaceBefore
        if theme.wordRules, web {
            if i == 0 {
                if style.spaceBeforeAuto { spaceBefore = 0 }
            } else if i - 1 < document.paragraphs.count {
                let above = document.paragraphs[i - 1]
                if above.cell == p.cell, style.spaceBeforeAuto || above.style.spaceAfterAuto {
                    spaceBefore = max(0, spaceBefore - spaceAfter(above.style))
                }
            }
        }
        let before = ((skipBefore ? 0 : _px(spaceBefore)) + bTop).rounded()
        let after = (skipAfter ? 0 : _px(spaceAfter(style))) + bBottom
        // Where the engine put the baseline (a strut's even leading) is
        // not where Word has it: the text is drawn from as much lower.
        _inkShift[i] = 0
        if theme.wordRules, p.image == nil, !p.text.isEmpty, painter.strutStyle != nil,
           let line = painter.computeLineMetrics().first {
            let named = _named(p, document)
            let pitch = style.eastAsian["w:snapToGrid"] == "0" ? nil : document.lineGridPitch
            var at = 0
            var lead: (CharStyle, Bool) = (p.runs[0].style, false)
            search: for run in p.runs {
                let hinted = (run.style.fontHint ?? named?.char.fontHint) == "eastAsia"
                let a = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: at)
                let b = p.text.utf16.index(a, offsetBy: run.length)
                at += run.length
                for ch in p.text[a ..< b] where Self.isEastAsian(ch, hinted: hinted) {
                    lead = (run.style, true)
                    break search
                }
            }
            if let target = theme.baseline(for: lead.0, in: style, named: named, eastAsian: lead.1, gridPitch: pitch) {
                _inkShift[i] = _px(target) - line.baseline
            }
        }
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
            // A floating object stands clear of the flow: its paragraph
            // is the height of its (empty) line, as Word sets it.
            if theme.wordRules, let float = image.float, !float.takesRoom {} else { bodyHeight = h.rounded() }
            _ensureDecoded(image)
        } else {
            _imageSize[i] = nil
        }
        _heights[i] = (before + bodyHeight + after).rounded(.up)
        // An empty paragraph that only ends a section stands for the
        // break and takes no room, as Word sets it.
        if theme.wordRules, p.text.isEmpty, p.image == nil, style.sectionXML != nil, p.cell == nil { _heights[i] = 0 }
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
    private func _span(for p: RichParagraph, _ document: RichDocument, textWidth: Double, adjust: [Int: Double] = [:])
        -> (TextSpan, [(image: ImageAttachment?, dimensions: PlaceholderDimensions)]) {
        let named = _named(p, document)
        let pitch = p.style.eastAsian["w:snapToGrid"] == "0" ? nil : document.lineGridPitch
        if p.text.isEmpty {
            return (TextSpan(text: " ", style: theme.textStyle(for: p.runs[0].style, in: p.style, named: named, scale: scale, gridPitch: pitch)), [])
        }
        /// A run's text as shown: capitals for Word's All caps and Small
        /// caps (the latter with the lowercase letters' capitals at 80%),
        /// the same number of UTF-16 units as the text, so that offsets
        /// into the painted text are offsets into the paragraph.
        func capped(_ text: Substring, _ run: CharStyle, _ style: TextStyle) -> [TextSpan] {
            let caps = run.caps || ((named?.char.caps ?? false) && !run.off.contains(.caps))
            let small = !caps && (run.smallCaps || ((named?.char.smallCaps ?? false) && !run.off.contains(.smallCaps)))
            if !caps && !small { return [TextSpan(text: String(text), style: style)] }
            var spans: [TextSpan] = []
            var piece = ""
            var pieceSmall = false
            let smallStyle = small ? style.copyWith(fontSize: (style.fontSize ?? 12) * 0.8) : style
            for ch in text {
                let s = String(ch)
                let up = s.uppercased()
                let lower = up != s && up.utf16.count == s.utf16.count
                let isSmall = small && lower
                if isSmall != pieceSmall, !piece.isEmpty {
                    spans.append(TextSpan(text: piece, style: pieceSmall ? smallStyle : style))
                    piece = ""
                }
                pieceSmall = isSmall
                piece += lower ? up : s
            }
            if !piece.isEmpty { spans.append(TextSpan(text: piece, style: pieceSmall ? smallStyle : style)) }
            return spans
        }
        /// A run's text as spans, East Asian stretches apart from the
        /// rest: each is set in its own face of the run (Word's
        /// `w:eastAsia` and `w:ascii`) at that face's line height.
        func styled(_ text: Substring, _ run: CharStyle, at base: Int = 0, next: Character? = nil) -> [TextSpan] {
            let latinFace = theme.wordRules ? theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, false) : nil
            let hinted = (run.fontHint ?? named?.char.fontHint) == "eastAsia" || (latinFace?.isEastAsian ?? false)
            let em = (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            let closes = _closesUpMarks(run, named, document)
            // A stretch is of one script, and — where the Latin face
            // stands in at a scale for each kind of character — of one
            // kind: -1 East Asian, else the kind (0 where there is one
            // scale for all).
            let classed = latinFace?.classScales != nil
            var styles: [Int: TextStyle] = [:]
            func style(_ kind: Int) -> TextStyle {
                if let s = styles[kind] { return s }
                let s = theme.textStyle(for: run, in: p.style, named: named, scale: scale, eastAsian: kind < 0, gridPitch: pitch,
                                        characterClass: classed && kind >= 0 ? kind : nil)
                styles[kind] = s
                return s
            }
            var spans: [TextSpan] = []
            var start = text.startIndex
            var current: Int? = nil
            func flush(_ end: Substring.Index) {
                guard let kind = current, start < end else { return }
                spans.append(contentsOf: capped(text[start ..< end], run, style(kind)))
                start = end
            }
            var offset = base
            var i = text.startIndex
            while i < text.endIndex {
                let ch = text[i]
                let after = text.index(after: i)
                let following = after < text.endIndex ? text[after] : next
                let ea = theme.wordRules && RichLayout.isEastAsian(ch, hinted: hinted)
                let kind = ea ? -1 : (classed ? RichResolvedFace.characterClass(ch) : 0)
                if let c = current, c != kind { flush(i) }
                current = kind
                // What this character is set wider or narrower by: Word's
                // automatic space between an ideograph and the Latin
                // letter or digit beside it (`w:autoSpaceDE` and
                // `w:autoSpaceDN`, on unless the paragraph says
                // otherwise); the half em it takes off the first of two
                // punctuation marks that stand together; and what the
                // line fitting asked of this one.
                var extra = adjust[offset] ?? 0
                if let following {
                    if theme.wordRules, Self._autoSpaced(ch, following, p.style) {
                        let latin = run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily
                        extra += (0.5 + (theme.averageCharWidth?(latin) ?? 0.5)) / 4 * em
                    } else if ea, closes, Self.closesUp(ch, following) {
                        extra -= em / 2
                    }
                }
                if extra != 0 {
                    flush(i)
                    let s = style(kind)
                    spans.append(contentsOf: capped(text[i ..< after], run, s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra)))
                    start = after
                }
                offset += ch.utf16.count
                i = after
            }
            flush(text.endIndex)
            return spans
        }
        let lead = firstLineIndent(p, document)
        if lead == 0, p.runs.count == 1, p.runs[0].style.inlineImage == nil {
            let spans = styled(p.text[...], p.runs[0].style)
            if spans.count == 1 { return (spans[0], []) }
            return (TextSpan(children: spans), [])
        }
        var children: [InlineSpan] = []
        var inline: [(image: ImageAttachment?, dimensions: PlaceholderDimensions)] = []
        children.reserveCapacity(p.runs.count + 1)
        if lead != 0 {
            // The first line's indent is a box of that width before the
            // text — of less than no width for a hanging one, which sets
            // the line out to the left and leaves it that much longer.
            // It is one more character in the painter's text than in the
            // paragraph's: `_lead` says so to every offset that crosses.
            let style = theme.textStyle(for: p.runs[0].style, in: p.style, named: named, scale: scale, gridPitch: pitch)
            children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
            inline.append((nil, PlaceholderDimensions(size: Size(_px(lead), 0.01), alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: 0.01)))
        }
        var pos = 0
        let utf16 = p.text.utf16
        for run in p.runs where run.length > 0 {
            let a = utf16.index(utf16.startIndex, offsetBy: pos)
            let b = utf16.index(a, offsetBy: run.length)
            pos += run.length
            if let id = run.style.inlineImage, let image = p.inlineImages[id] {
                let style = theme.textStyle(for: run.style, in: p.style, named: named, scale: scale, gridPitch: pitch)
                // A picture in the line, sitting on the baseline as Word
                // sets it; shrunk to the column when wider.
                var w = _px(image.width), h = _px(image.height)
                if w > textWidth { h *= textWidth / w; w = textWidth }
                // (A floating object takes no room in the line.)
                if theme.wordRules, let float = image.float, !float.takesRoom { w = 0; h = 0 }
                let size = Size(w.rounded(), h.rounded())
                children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
                inline.append((image, PlaceholderDimensions(size: size, alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: size.height)))
                continue
            }
            children.append(contentsOf: styled(p.text[a ..< b], run.style, at: pos - run.length, next: b < utf16.endIndex ? p.text[b] : nil))
        }
        return (TextSpan(children: children), inline)
    }

    /// Where every stretch of a paragraph has one line height but not
    /// one face, each face splits that height about the baseline its own
    /// way and a line that mixes two comes out taller than either — and
    /// which lines those are depends on which face the platform falls
    /// back to for a character. A strut of that height holds every line
    /// to it. (Stretches of different heights are left to the tallest.)
    private func _strut(_ span: TextSpan) -> StrutStyle? {
        guard theme.wordRules else { return nil }
        var first: TextStyle? = nil
        var uniform = true
        var count = 0
        func visit(_ s: InlineSpan) {
            guard uniform, let t = s as? TextSpan else { return }
            if t.text != nil, let style = t.style, let size = style.fontSize, let h = style.height, size > 0.5 {
                count += 1
                if let f = first, let fs = f.fontSize, let fh = f.height {
                    if abs(fs * fh - size * h) > 0.01 { uniform = false }
                } else {
                    first = style
                }
            }
            for c in t.children ?? [] { visit(c) }
        }
        visit(span)
        guard uniform, count > 0, let base = first, let size = base.fontSize, let h = base.height else { return nil }
        // (Even leading: the engine's proportional strut scales the
        // face's ascent and descent by a height that counts its line gap
        // too, and comes out that much short — 15.15 for 15.6 in
        // Liberation Sans.)
        return StrutStyle(fontFamily: base.fontFamily, fontFamilyFallback: base.fontFamilyFallback,
                          fontSize: size, height: h, leadingDistribution: .even, fontWeight: base.fontWeight,
                          forceStrutHeight: true)
    }

    /// The first line's indent in points, where the theme sets first
    /// lines in: positive in, negative out (hanging). Word's
    /// `w:firstLineChars` and `w:hangingChars` count characters of the
    /// paragraph's first run and outrank the measure beside them. A
    /// list's marker has its own slot, and an empty paragraph no line
    /// to indent.
    public func firstLineIndent(_ p: RichParagraph, _ document: RichDocument) -> Double {
        guard theme.wordRules, p.style.list == nil, !p.text.isEmpty, p.image == nil else { return 0 }
        let chars = Double(p.style.eastAsian["w:hangingChars"] ?? "").map { -$0 } ?? Double(p.style.eastAsian["w:firstLineChars"] ?? "")
        if let chars, chars != 0 {
            let size = p.runs.first?.style.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize
            return chars / 100 * size
        }
        return p.style.firstLineIndent
    }

    /// The sheet's entry for a paragraph: its style's, and for a plain
    /// paragraph Normal's — the face and size a document's body text is
    /// set in when its runs name none. (A heading with no entry keeps the
    /// theme's look.)
    private func _named(_ p: RichParagraph, _ document: RichDocument) -> RichNamedStyle? {
        document.styles.resolve(p.style)
            ?? (theme.wordRules && p.style.heading == nil ? document.styles[RichNamedStyle.normalId] : nil)
    }

    /// 1 when paragraph `i`'s painter has the indent's box before the
    /// text: what to add to a paragraph offset to get the painter's.
    private func _lead(_ p: RichParagraph, _ document: RichDocument) -> Int {
        firstLineIndent(p, document) != 0 ? 1 : 0
    }

    /// Whether two punctuation marks that stand together close up in
    /// this run: by the East Asian rules, where the text kerns
    /// (`w:kern`, from that size up) and the document's punctuation may.
    private func _closesUpMarks(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool {
        guard theme.wordRules, document.usesEastAsianLayout, document.kernsPunctuation,
              let from = run.kerningFrom ?? named?.char.kerningFrom, from > 0 else { return false }
        return (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) >= from
    }

    /// What to take off which characters (paragraph offset → pixels,
    /// negative) so that the engine breaks this paragraph's lines where
    /// Word does: see `_layoutParagraph`. The paragraph is laid out once
    /// more at no width, which makes a line of every stretch the engine
    /// will not break — the break opportunities and the widths between
    /// them, by the engine's own measure — and Word's rules are run over
    /// those. Measured from Word 16's prints, 2026-10-12: a closing mark
    /// hangs unless the paragraph says `w:overflowPunct` off; a line
    /// gives up to half an em, off its punctuation, where the document's
    /// `w:characterSpacingControl` compresses punctuation.
    private func _fitEastAsianLines(_ p: RichParagraph, _ document: RichDocument, span: TextSpan,
                                    dimensions: [PlaceholderDimensions], width: Double, first: TextPainter) -> [Int: Double] {
        guard theme.wordRules, document.usesEastAsianLayout, !p.style.rightToLeft, p.text.utf16.count > 2 else { return [:] }
        let hangs = p.style.eastAsian["w:overflowPunct"] != "0"
        let squeezes = document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false
        guard hangs || squeezes else { return [:] }
        let units = Array(p.text.utf16)
        guard units.contains(where: { Self._closingUnits.contains($0) || Self._openingUnits.contains($0) }),
              first.computeLineMetrics().count > 1 else { return [:] }
        let lead = _lead(p, document)
        let probe = TextPainter(text: span, textAlign: .left, textDirection: .ltr)
        if !dimensions.isEmpty { probe.setPlaceholderDimensions(dimensions) }
        probe.layout(minWidth: 0, maxWidth: 1)
        defer { probe.dispose() }
        // The size (pixels) of the run at each offset: a mark's em.
        var ems: [Double] = []
        ems.reserveCapacity(units.count)
        let named = _named(p, document)
        var closing: [Bool] = []
        for run in p.runs {
            let em = (run.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            ems.append(contentsOf: repeatElement(em, count: run.length))
            closing.append(contentsOf: repeatElement(_closesUpMarks(run.style, named, document), count: run.length))
        }
        guard ems.count == units.count else { return [:] }
        func isSpace(_ u: UInt16) -> Bool { u == 0x20 || u == 0x3000 || u == 0x09 || u == 0xA0 }
        func closesUp(_ k: Int) -> Bool {
            guard closing[k], k + 1 < units.count, let a = Unicode.Scalar(units[k]), let b = Unicode.Scalar(units[k + 1]) else { return false }
            return Self.closesUp(Character(a), Character(b))
        }
        var adjust: [Int: Double] = [:]
        var x = 0.0
        var marks: [Int] = []   // this line's marks that still have their whole em
        var start = 0           // painter offset
        let total = units.count + lead
        for line in probe.computeLineMetrics() {
            guard start < total else { break }
            let r = probe.getLineBoundary(TextPosition(offset: start))
            let end = min(total, max(start + 1, r.end))
            let a = max(0, start - lead), b = max(a, end - lead)   // paragraph offsets
            start = end
            // The stretch's width, and its trailing spaces' (which the
            // engine leaves out of a line's width, and of its fit).
            var last = b
            while last > a, isSpace(units[last - 1]) { last -= 1 }
            var trail = 0.0
            if last < b {
                for box in probe.getBoxesForSelection(TextSelection(baseOffset: last + lead, extentOffset: b + lead)) {
                    trail += box.right - box.left
                }
            }
            let w = line.width
            let own = (a ..< last).filter { (Self._closingUnits.contains(units[$0]) || Self._openingUnits.contains(units[$0])) && !closesUp($0) }
            var fits = x + w <= width + 0.01
            if !fits, x > 0, last > a {
                let over = x + w - width
                let tail = last - 1
                if hangs, Self._hangingUnits.contains(units[tail]), over <= ems[tail] * (closesUp(tail) ? 0.5 : 1) + 0.01 {
                    adjust[tail, default: 0] -= over + 0.02
                    fits = true
                } else if squeezes {
                    // Word takes the next character where it is half an
                    // em or less too wide for the line, and then all of
                    // what cannot be parted from it (an opening mark's
                    // word), as long as the line's marks can give that
                    // much: half an em each, shared evenly.
                    let all = marks + own
                    let lead = Self._closingUnits.contains(units[a]) || Self._openingUnits.contains(units[a]) || units[a] >= 0x2E80
                        ? ems[a] * (closesUp(a) ? 0.5 : 1) : w
                    let room = all.reduce(0.0) { $0 + ems[$1] / 2 }
                    if !all.isEmpty, x + min(lead, w) - width <= ems[a] / 2 + 0.01, over <= room + 0.01 {
                        let share = (over + 0.02) / room
                        for mark in all { adjust[mark, default: 0] -= ems[mark] / 2 * share }
                        fits = true
                    }
                }
                if fits {
                    // The line is full: whatever comes next starts another.
                    x = width
                    marks = []
                    if line.hardBreak { x = 0 }
                    continue
                }
            }
            if !fits {
                x = 0
                marks = []
            }
            x += w + trail
            marks.append(contentsOf: own)
            if line.hardBreak {
                x = 0
                marks = []
            }
        }
        return adjust
    }

    private static let _closingUnits = Set(_closingMarks.flatMap { String($0).utf16 })
    private static let _openingUnits = Set(_openingMarks.flatMap { String($0).utf16 })
    /// The marks that may hang past the margin at a line's end.
    private static let _hangingUnits = _closingUnits.union("？”’".utf16)

    /// Punctuation whose ink keeps to the left half of its em, and to
    /// the right half: Word takes half an em off the first of two that
    /// stand together — a closing mark before any of either kind, an
    /// opening mark before another opening one (measured from Word 16's
    /// prints; the question mark and the curly quotes take no part).
    private static let _closingMarks: Set<Character> = ["，", "。", "、", "；", "：", "！", "）", "》", "」", "』", "】", "〕", "〉", "｝", "］", "．"]
    private static let _openingMarks: Set<Character> = ["（", "《", "「", "『", "【", "〔", "〈", "｛", "［"]

    static func closesUp(_ a: Character, _ b: Character) -> Bool {
        if _closingMarks.contains(a) { return _closingMarks.contains(b) || _openingMarks.contains(b) }
        return _openingMarks.contains(a) && _openingMarks.contains(b)
    }

    /// Whether Word's automatic spacing falls between `a` and `b`: one
    /// an ideograph, kana or hangul, the other a Latin letter (unless
    /// the paragraph turns `w:autoSpaceDE` off) or a digit
    /// (`w:autoSpaceDN`). Punctuation of either script takes none.
    private static func _autoSpaced(_ a: Character, _ b: Character, _ style: RichParagraphStyle) -> Bool {
        func ideograph(_ c: Character) -> Bool {
            guard let u = c.unicodeScalars.first?.value else { return false }
            switch u {
            case 0x1100 ... 0x11FF, 0x3040 ... 0x30FF, 0x3400 ... 0x9FFF, 0xAC00 ... 0xD7FF, 0xF900 ... 0xFAFF, 0x20000 ... 0x3FFFF: return true
            default: return false
            }
        }
        func latin(_ c: Character) -> Bool {
            if c.isASCII { return c.isNumber ? style.eastAsian["w:autoSpaceDN"] != "0" : c.isLetter && style.eastAsian["w:autoSpaceDE"] != "0" }
            guard let u = c.unicodeScalars.first?.value, u < 0x530 else { return false }
            return c.isLetter && style.eastAsian["w:autoSpaceDE"] != "0"
        }
        return (ideograph(a) && latin(b)) || (latin(a) && ideograph(b))
    }

    /// Whether Word sets `ch` in a run's East Asian face: ideographs,
    /// kana, hangul, their punctuation and the full-width forms — and,
    /// in a run hinted East Asian, the quotes, dashes and dots both
    /// scripts claim.
    static func isEastAsian(_ ch: Character, hinted: Bool) -> Bool {
        guard let u = ch.unicodeScalars.first?.value, u >= 0xA0 else { return false }
        switch u {
        case 0x1100 ... 0x11FF, 0x2E80 ... 0x9FFF, 0xA960 ... 0xA97F, 0xAC00 ... 0xD7FF, 0xF900 ... 0xFAFF,
             0xFE30 ... 0xFE6F, 0xFF00 ... 0xFFEF, 0x20000 ... 0x3FFFF:
            return true
        case 0xA1 ... 0x24F, 0x2010 ... 0x203B, 0x2103, 0x2109, 0x2116, 0x2121, 0x2160 ... 0x217F, 0x2190 ... 0x2199,
             0x2200 ... 0x22FF, 0x2460 ... 0x257F, 0x25A0 ... 0x266F:
            return hinted
        default:
            return false
        }
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
        if theme.wordRules, i < _floats.count, let float = _floats[i], !float.takesRoom {
            // From its paragraph, by its offsets where they are measured
            // from the column and the paragraph (the common anchor).
            let dx = float.horizontalAlign == nil && ["column", "margin", "character"].contains(float.horizontalFrom) ? _px(float.x) : 0
            let dy = float.verticalAlign == nil && ["paragraph", "line"].contains(float.verticalFrom) ? _px(float.y) : 0
            return Rect.fromLTWH(g.textLeft + dx, g.textTop + dy, size.width, size.height)
        }
        return Rect.fromLTWH(g.textLeft, g.textTop, size.width, size.height)
    }

    // MARK: Geometry queries (call ensureLaidOut first)

    public var totalHeight: Double { _flowHeight }

    public func geometry(_ i: Int) -> ParagraphGeometry {
        ParagraphGeometry(painter: _painters[i]!, top: _tops[i], height: _heights[i],
                          textTop: _tops[i] + _spaceBefore[i], inkShift: i < _inkShift.count ? _inkShift[i] : 0,
                          textLeft: _textLeft[i], textWidth: _textWidth[i])
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
        let lead = _lead(para, document)
        let o = g.painter.getOffsetForCaret(TextPosition(offset: offset + lead), proto)
        let h = g.painter.getFullHeightForCaret(TextPosition(offset: offset + lead), proto)
        return Rect.fromLTWH(g.textLeft + o.dx, g.inkTop + o.dy, 2, h > 0 ? h : lineH)
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
            // Clamp each box to the paragraph's body. The builder's `.max`
            // boxes overshoot the line grid by the fraction the line height
            // was rounded away (a 28pt line at spacing 1.0 is 37.33px laid
            // out as 37, so the first box starts at -0.33). A rect that
            // starts above its paragraph belongs, by y, to the paragraph
            // before it — canvasRects then clipped it to that paragraph's
            // bottom and the first line of a selection drew as a hairline.
            let bodyHeight = g.painter.height
            let lead = _lead(para, document)
            for box in g.painter.getBoxesForSelection(
                TextSelection(baseOffset: lo + lead, extentOffset: hi + lead),
                boxHeightStyle: .max) {
                let top = max(0, box.top)
                let bottom = min(bodyHeight, box.bottom)
                guard bottom > top else { continue }
                rects.append(Rect.fromLTRB(g.textLeft + box.left, g.inkTop + top,
                                           g.textLeft + box.right, g.inkTop + bottom))
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
        let local = Offset(point.dx - g.textLeft, min(max(point.dy - g.inkTop, 0), g.painter.height - 0.01))
        let tp = g.painter.getPositionForOffset(local)
        return RichPosition(paragraph: i, offset: para.alignedOffset(max(0, min(tp.offset - _lead(para, document), para.length))))
    }

    /// Start and end offsets of the visual line holding `pos`.
    public func lineBounds(_ pos: RichPosition, _ document: RichDocument) -> (start: Int, end: Int) {
        let i = max(0, min(pos.paragraph, count - 1))
        let para = document.paragraphs[i]
        if para.text.isEmpty { return (0, 0) }
        let g = geometry(i)
        let lead = _lead(para, document)
        let bound = g.painter.getLineBoundary(TextPosition(offset: max(0, min(pos.offset, para.length)) + lead))
        let r = (start: max(0, bound.start - lead), end: max(0, bound.end - lead))
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

    /// A table row's shading — the header's, or a band's — under every cell
    /// of the row; drawn by its first cell's paragraph, before the selection.
    private func _paintShading(_ i: Int, _ canvas: any Canvas, _ document: RichDocument) {
        if let fill = document.paragraphs[i].style.fill, i < count {
            // The paragraph's own shading, text area wide.
            let g = geometry(i)
            let paint = Paint()
            paint.style = .fill
            paint.color = fill
            canvas.drawRect(Rect.fromLTWH(g.textLeft.rounded(), g.textTop.rounded(), g.textWidth.rounded(), g.painter.height.rounded()), paint)
        }
        if let c = _cells[i], c.firstInRow, let ts = document.tableStyles[c.table] {
            // The row's shading, under every cell of the row: the header's,
            // or a band's.
            let header = c.row == 0 && ts.headerRow
            let bodyRow = c.row - (ts.headerRow ? 1 : 0)
            let color: Color? = header ? (ts.headerFill ?? theme.textColor.withOpacity(0.06))
                : (bodyRow % 2 == 0 ? ts.bandFill : ts.bandAltFill)
            if let color {
                let fill = Paint()
                fill.style = .fill
                fill.color = color
                let width = (_columnWidths[c.table] ?? []).reduce(0, +)
                let left = c.colLeft - (_columnWidths[c.table] ?? []).prefix(c.column).reduce(0, +)
                // A cell whose own fill is fully transparent says "no fill"
                // (PowerPoint's `a:noFill` on a cell of a banded table): the
                // row's shading stops at its edges rather than showing through.
                var holes: [(Double, Double)] = []
                var j = i
                while j < count, j < document.paragraphs.count, let cj = _cells[j], cj.table == c.table, cj.row == c.row {
                    if let own = document.paragraphs[j].cell?.fill, own.alpha == 0 {
                        holes.append((cj.colLeft, cj.colLeft + cj.colWidth))
                    }
                    j += 1
                }
                if holes.isEmpty {
                    canvas.drawRect(Rect.fromLTWH(left.rounded(), c.rowTop.rounded(), width.rounded(), c.ownRowHeight.rounded()), fill)
                }
                var from = left
                for (l, r) in holes.isEmpty ? [] : holes + [(left + width, left + width)] {
                    if l > from {
                        canvas.drawRect(Rect.fromLTRB(from.rounded(), c.rowTop.rounded(), l.rounded(),
                                                      (c.rowTop + c.ownRowHeight).rounded()), fill)
                    }
                    from = max(from, r)
                }
            }
        }
        // The cell's own shading, over the row's; every paragraph of the
        // cell paints it (the same rectangle, so no seam).
        if let c = _cells[i], let color = document.paragraphs[i].cell?.fill {
            let fill = Paint()
            fill.style = .fill
            fill.color = color
            let height = c.rowSpan > 1 ? c.rowHeight : c.ownRowHeight
            canvas.drawRect(Rect.fromLTWH(c.colLeft.rounded(), c.rowTop.rounded(), c.colWidth.rounded(), height.rounded()), fill)
        }
    }

    private func _paintParagraph(_ i: Int, _ canvas: any Canvas, _ document: RichDocument) {
        let g = geometry(i)
        if let c = _cells[i], c.firstInRow {
            // The table's switch, refined by its own sides and by each
            // cell's: a side a cell states wins, then the table's side
            // for that position (outer or inside), then the switch.
            let ts = document.tableStyles[c.table]
            let tableOn = ts?.borders ?? true
            let te = ts?.edges
            func on(_ cell: Bool?, _ table: Bool?) -> Bool { cell ?? table ?? tableOn }
            let stroke = Paint()
            stroke.style = .stroke
            stroke.strokeWidth = max(1, _px(ts?.borderWidth ?? 0.5).rounded())
            stroke.color = ts?.borderColor ?? theme.textColor.withOpacity(0.6)
            // Every line lies inside the row (the paint is clipped to the
            // row's page piece, so a stroke centred on the row's bottom
            // edge lost its outer half and the table's last row had no
            // bottom border). Rows share edges: a row draws its bottom and
            // only the first row its top; columns draw their left and only
            // the last its right. A cell's own edge lines (the file's
            // lnL…lnB) replace the style's rule on that edge: drawn at
            // their width and colour, or not at all.
            let widths = _columnWidths[c.table] ?? []
            let rowTop = c.rowTop.rounded()
            let rowBottom = (c.rowTop + c.ownRowHeight).rounded()
            let tableLeft = (c.colLeft - widths.prefix(c.column).reduce(0, +)).rounded()
            let right = (tableLeft + widths.reduce(0, +)).rounded()
            // Is this the table's last row? (Its bottom is then the outer
            // bottom side, not an inside one.)
            var probe = i
            while probe < _cells.count, let d = _cells[probe], d.table == c.table, d.row == c.row { probe += 1 }
            let lastRow = !(probe < _cells.count && _cells[probe]?.table == c.table)
            // A cell's own line on an edge (the file's lnL…lnB, with its
            // own width and colour) replaces the rule there: drawn centred
            // on the edge, or not at all for a hidden one.
            func line(_ own: CellRef.CellLine?, _ ruled: Bool, _ from: Offset, _ to: Offset, inward: Offset) {
                if let own {
                    guard let color = own.color, own.width > 0 else { return }
                    let p = Paint()
                    p.style = .stroke
                    p.strokeWidth = max(1, _px(own.width))
                    p.color = color
                    canvas.save()
                    canvas.clipRect(Rect.fromLTRB(-1e6, rowTop, 1e6, rowBottom))
                    canvas.drawLine(from, to, p)
                    canvas.restore()
                } else if ruled {
                    canvas.drawLine(from + inward * 0.5, to + inward * 0.5, stroke)
                }
            }
            func paintEdges(_ d: _CellGeo, bottomHere: Bool, ownTop: Bool) {
                let cellRight = (d.colLeft + d.colWidth).rounded()
                line(d.borders.left, on(d.edges?.left, d.column == 0 ? te?.left : te?.insideV),
                     Offset(d.colLeft, rowTop), Offset(d.colLeft, rowBottom), inward: Offset(1, 0))
                // The row above drew this cell's top, unless the cell has
                // its own line there (on the first row it covers).
                if (c.row == 0 && d.row == 0) || (ownTop && d.borders.top != nil) {
                    line(d.borders.top, c.row == 0 && d.row == 0 && on(d.edges?.top, te?.top),
                         Offset(d.colLeft, rowTop), Offset(cellRight, rowTop), inward: Offset(0, 1))
                }
                if bottomHere {
                    line(d.borders.bottom, on(d.edges?.bottom, lastRow ? te?.bottom : te?.insideH),
                         Offset(d.colLeft, rowBottom), Offset(cellRight, rowBottom), inward: Offset(0, -1))
                }
                if cellRight >= right - 0.5 {
                    line(d.borders.right, on(d.edges?.right, te?.right),
                         Offset(right, rowTop), Offset(right, rowBottom), inward: Offset(-1, 0))
                } else if d.borders.right != nil {
                    line(d.borders.right, false, Offset(cellRight, rowTop), Offset(cellRight, rowBottom), inward: Offset(-1, 0))
                }
            }
            // Each cell of the row draws its edges; a cell from above that
            // spans into this row draws its left edge here too, and its
            // bottom on its last row.
            var j = i
            var lastColumn = -1
            while j < _cells.count, let d = _cells[j], d.table == c.table, d.row == c.row {
                if d.column != lastColumn {
                    paintEdges(d, bottomHere: d.rowSpan == 1, ownTop: true)
                    lastColumn = d.column
                }
                j += 1
            }
            var k = i - 1
            var seen: Set<Int> = []
            while k >= 0, let d = _cells[k], d.table == c.table {
                if d.rowSpan > 1, d.row < c.row, d.row + d.rowSpan > c.row, !seen.contains(d.column) {
                    seen.insert(d.column)
                    paintEdges(d, bottomHere: d.row + d.rowSpan - 1 == c.row, ownTop: false)
                }
                k -= 1
            }
        }
        if let image = document.paragraphs[i].image, let box = imageRect(i) {
            if let decoded = _decoded[image.id] {
                let paint = Paint()
                canvas.drawImageRect(decoded,
                                     Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height)),
                                     box, paint)
            } else if !(theme.wordRules && image.float.map({ !$0.takesRoom }) == true) {
                // (No stand-in for a floating object the editor cannot
                // draw: it would lie over the text it floats beside.)
                let paint = Paint()
                paint.style = .fill
                paint.color = Color(0x22808080)
                canvas.drawRect(box, paint)
            }
            return
        }
        if let c = _cells[i], c.vertical {
            // The block painted in its own horizontal space, turned a
            // quarter about the cell's corner it reads from: text reading
            // up starts at the bottom-left corner with its lines stacking
            // rightwards, text reading down at the top-right corner with
            // its lines stacking leftwards.
            let height = c.rowSpan > 1 ? c.rowHeight : c.ownRowHeight
            canvas.save()
            if c.direction == .up {
                canvas.translate(c.colLeft, c.rowTop + height)
                canvas.rotate(-Double.pi / 2)
            } else {
                canvas.translate(c.colLeft + c.colWidth, c.rowTop)
                canvas.rotate(Double.pi / 2)
            }
            let along = c.alongStart + _px(document.paragraphs[i].style.indentLeft)
            g.painter.paint(canvas, Offset(along, c.across + _spaceBefore[i]))
            canvas.restore()
            return
        }
        if let b = document.paragraphs[i].style.borders {
            // Word's paragraph borders: each edge a line its `space` away
            // from the text, the horizontal ones spanning the text width
            // (plus the side edges' own gaps).
            let textBottom = g.textTop + g.painter.height
            let leftExt = b.left.map { _px($0.space + $0.width) } ?? 0
            let rightExt = b.right.map { _px($0.space + $0.width) } ?? 0
            let x0 = (g.textLeft - leftExt).rounded(), x1 = (g.textLeft + g.textWidth + rightExt).rounded()
            func stroke(_ l: BorderLine) -> Paint {
                let p = Paint()
                p.style = .stroke
                p.strokeWidth = max(1, _px(l.width).rounded())
                p.color = l.color ?? theme.textColor
                return p
            }
            if let l = b.top, l.style != "none" {
                let y = (g.textTop - _px(l.space) - _px(l.width) / 2).rounded() + 0.5
                canvas.drawLine(Offset(x0, y), Offset(x1, y), stroke(l))
            }
            if let l = b.bottom, l.style != "none" {
                let y = (textBottom + _px(l.space) + _px(l.width) / 2).rounded() - 0.5
                canvas.drawLine(Offset(x0, y), Offset(x1, y), stroke(l))
            }
            let y0 = b.top.map { g.textTop - _px($0.space + $0.width) } ?? g.textTop
            let y1 = b.bottom.map { textBottom + _px($0.space + $0.width) } ?? textBottom
            if let l = b.left, l.style != "none" {
                let x = (g.textLeft - _px(l.space) - _px(l.width) / 2).rounded() + 0.5
                canvas.drawLine(Offset(x, y0), Offset(x, y1), stroke(l))
            }
            if let l = b.right, l.style != "none" {
                let x = (g.textLeft + g.textWidth + _px(l.space) + _px(l.width) / 2).rounded() - 0.5
                canvas.drawLine(Offset(x, y0), Offset(x, y1), stroke(l))
            }
        }
        if let label = listLabel(i, document), theme.marksEmptyListItems || !document.paragraphs[i].text.isEmpty {
            let p = document.paragraphs[i]
            var markerChar = p.runs[0].style
            if let c = p.style.bulletColor { markerChar.color = c }
            if let k = p.style.bulletScale {
                markerChar.fontSize = (markerChar.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize) * k
            }
            let markerStyle = theme.textStyle(for: markerChar, in: p.style, named: _named(p, document), scale: scale)
            // (On the paragraph's strut, so that the marker's baseline
            // is the text's.)
            let marker = TextPainter(text: TextSpan(text: label, style: markerStyle),
                                     textAlign: .right, textDirection: .ltr, strutStyle: g.painter.strutStyle)
            let slot = _px(theme.listIndent)
            if theme.markersAtHang {
                // At the hang, and never over the text: a bullet whose hang
                // is at the text (indent 0) sits just before it instead.
                marker.layout(minWidth: 0, maxWidth: max(1, slot * 4))
                let hang = g.textLeft - slot + _px(p.style.firstLineIndent)
                marker.paint(canvas, Offset(min(hang, g.textLeft - marker.width - 4), g.inkTop))
            } else {
                marker.layout(minWidth: slot - 8, maxWidth: slot - 8)
                marker.paint(canvas, Offset(g.textLeft - slot, g.inkTop))
            }
            marker.dispose()
        }
        g.painter.paint(canvas, Offset(g.textLeft, g.inkTop))
        if i < _inline.count, !_inline[i].isEmpty, let all = g.painter.inlinePlaceholderBoxes {
            let boxes = all.dropFirst(_lead(document.paragraphs[i], document))
            for (k, box) in boxes.enumerated() where k < _inline[i].count {
                let image = _inline[i][k]
                var rect = box.toRect().shift(Offset(g.textLeft, g.inkTop))
                if theme.wordRules, let float = image.float, !float.takesRoom {
                    // A floating picture, from its paragraph by its
                    // offsets; an object that cannot be drawn is left out.
                    guard _decoded[image.id] != nil else { continue }
                    let dx = float.horizontalAlign == nil && ["column", "margin", "character"].contains(float.horizontalFrom) ? _px(float.x) : 0
                    let dy = float.verticalAlign == nil && ["paragraph", "line"].contains(float.verticalFrom) ? _px(float.y) : 0
                    rect = Rect.fromLTWH(g.textLeft + dx, g.textTop + dy, _px(image.width), _px(image.height))
                }
                let paint = Paint()
                if let decoded = _decoded[image.id] {
                    canvas.drawImageRect(decoded, Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height)), rect, paint)
                } else {
                    paint.style = .fill
                    paint.color = Color(0x22808080)
                    canvas.drawRect(rect, paint)
                }
            }
        }
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

    /// Running header (left) and footer (centred), fields filled per
    /// page, in Normal's face: the header's top and the footer's bottom
    /// at the page setup's distances from the paper's edges, as Word
    /// places them.
    private func _paintHeaderFooter(_ p: Int, _ canvas: any Canvas, _ document: RichDocument) {
        guard let setup = pageSetup else { return }
        let rect = pageRect(p)
        let n = pageCount
        let style = theme.textStyle(for: CharStyle(color: theme.textColor.withOpacity(0.7)),
                                    in: .body, named: document.styles[RichNamedStyle.normalId], scale: scale)
        let left = _px(setup.marginLeft)
        let width = _px(setup.contentWidth)
        /// One line at `centerY`: as a whole in `align`, or — with tabs —
        /// Word's header/footer thirds: left, centre and right parts.
        func line(_ template: String, align: TextAlign, top: Double? = nil, bottom: Double? = nil) {
            let text = RichDocument.fill(template, page: p + 1, pageCount: n)
            var parts: [(String, TextAlign)]
            if text.contains("\t" as Character) {
                let pieces = text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                parts = [(pieces[0], .left)]
                if pieces.count > 1 { parts.append((pieces[1], .center)) }
                if pieces.count > 2 { parts.append((pieces[2...].joined(), .right)) }
            } else {
                parts = [(text, align)]
            }
            for (piece, a) in parts where !piece.isEmpty {
                let tp = TextPainter(text: TextSpan(text: piece, style: style), textAlign: a, textDirection: .ltr)
                tp.layout(minWidth: width, maxWidth: width)
                tp.paint(canvas, Offset(rect.left + left, top ?? ((bottom ?? 0) - tp.height)))
                tp.dispose()
            }
        }
        if !document.header.isEmpty {
            line(document.header, align: .left, top: rect.top + _px(setup.headerDistance))
        }
        if !document.footer.isEmpty {
            line(document.footer, align: .center, bottom: rect.bottom - _px(setup.footerDistance))
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
        // Three layers: table shading, the selection over it, then the text
        // and rules. (Shading painted with its paragraph covered a selected
        // cell's highlight.)
        _paintFlow(canvas, visible: visible, document: document, shading: true)
        if let selection, !selection.isCollapsed {
            let paint = Paint()
            paint.color = theme.selectionColor
            paint.style = .fill
            for r in canvasSelectionRects(selection, document)
            where r.bottom >= visible.top && r.top <= visible.bottom {
                canvas.drawRect(r, paint)
            }
        }
        _paintFlow(canvas, visible: visible, document: document, shading: false)
        if let caret {
            let paint = Paint()
            paint.color = theme.caretColor
            paint.style = .fill
            canvas.drawRRect(RRect(fromRectAndRadius: caret, Radius(circular: 1)), paint)
        }
    }

    /// Every visible paragraph, page by page and column by column: its
    /// table row's shading only (`shading`), or everything else.
    private func _paintFlow(_ canvas: any Canvas, visible: Rect, document: RichDocument, shading: Bool) {
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
                        if shading { _paintShading(piece.paragraph, canvas, document) } else {
                            _paintParagraph(piece.paragraph, canvas, document)
                        }
                        canvas.restore()
                    }
                }
            }
        } else {
            for i in paragraphs(intersecting: visible.top, visible.bottom) {
                let g = geometry(i)
                if g.bottom < visible.top || g.top > visible.bottom { continue }
                if shading { _paintShading(i, canvas, document) } else { _paintParagraph(i, canvas, document) }
            }
        }
    }
}
