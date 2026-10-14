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
    /// Taken off every paragraph's line spacing: PowerPoint's shrink-to-fit
    /// reduces the spacing of a whole body (`lnSpcReduction`) without
    /// touching what the paragraphs say — 90% less 20% is 70%, not 72.
    public var lineSpacingReduction = 0.0
    /// Whether the first paragraph's space before is left out, as
    /// PowerPoint leaves it out at the top of a body; Word keeps it.
    public var omitsLeadingSpace = false
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

    /// "Single" spacing as a multiple of the size whatever the face, where
    /// nil takes each face's own. PowerPoint's is 1.2 for every face — its
    /// pages have Arial (1.15 by its metrics), Consolas (1.17) and Lucida
    /// Sans Unicode (1.47) all at 1.2; Word's is the face's.
    public var singleLineHeight: Double? = nil
    /// Whether letters are set one by one, the face's ligatures (Calibri's
    /// "tt", "ti") left out: PowerPoint sets "formatting" 0.6 pt wider
    /// than the engine does with them, and breaks its lines by that.
    public var disablesLigatures = false
    /// Whether a table's horizontal rules take room of their own: Word
    /// sets a row's height under its top rule and above its bottom one —
    /// three rows of 17.05pt ruled at half a point are 53pt, not 51 — and
    /// PowerPoint draws its lines over the rows as they are.
    public var tableRulesTakeRoom = true
    /// Whether the space after a paragraph and the space before the next
    /// share the room, the larger of the two alone standing between them:
    /// Word's way (unless the document says `addsParagraphSpacing`).
    /// PowerPoint sets both.
    public var collapsesParagraphSpacing = true

    /// The share of a face's line that lies below the baseline (Calibri's
    /// 0.22), measured once.
    private var _descentShares: [String: Double] = [:]

    public func descentShare(family: String?, bold: Bool, italic: Bool) -> Double {
        let key = "\(family ?? "")|\(bold)|\(italic)"
        if let d = _descentShares[key] { return d }
        let probe = TextPainter(text: TextSpan(text: "x", style: TextStyle(fontSize: 100, fontWeight: bold ? .bold : .normal,
                                                                            fontStyle: italic ? .italic : .normal, fontFamily: family)),
                                textDirection: .ltr)
        probe.layout(minWidth: 0, maxWidth: 1000)
        let d = probe.height > 0 ? 1 - probe.computeDistanceToActualBaseline(.alphabetic) / probe.height : 0.22
        probe.dispose()
        _descentShares[key] = d
        return d
    }

    /// How far the text of a paragraph set in `style` sits above (negative)
    /// or below where the engine puts it, in points per point of its
    /// size: PowerPoint takes a line spacing under single off the space
    /// ABOVE the line and adds one over single there, the letters keeping
    /// their depth below — where the engine shares the change out above
    /// and below. Zero for Word, and for a spacing given in points.
    public func baselineShift(for style: CharStyle, in paragraph: RichParagraphStyle) -> Double {
        guard let single = singleLineHeight, paragraph.lineHeightPoints == nil else { return 0 }
        let multiple = max(0.1, paragraph.lineSpacing - lineSpacingReduction)
        guard multiple != 1 else { return 0 }
        let family = (style.fontFamily ?? fontFamily).map { fontFamilyResolver?($0) ?? $0 }
        return (multiple - 1) * single * descentShare(family: family, bold: style.bold, italic: style.italic)
    }

    public func naturalLineHeight(family: String?, bold: Bool, italic: Bool) -> Double {
        if let singleLineHeight { return singleLineHeight }
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
        let multiple = max(0.1, paragraph.lineSpacing - lineSpacingReduction)
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
        let scaled = (style.horizontalScale ?? named?.char.horizontalScale ?? 1) != 1
        guard size > 0, let face = faceResolver?(familyName, eastAsian),
              let t = (scaled ? face.scaledBaseline : nil) ?? face.baseline else { return nil }
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        let natural = (scaled ? face.scaledHeight : nil) ?? face.naturalHeight
            ?? naturalLineHeight(family: face.family, bold: bold, italic: italic)
        return lineBox(size: size, natural: natural, baseline: t, in: paragraph, gridPitch: gridPitch).baseline
    }

    /// How far below the page's foot a line on a line grid may reach and
    /// still be set there, in points: Word centres the text's natural
    /// height in the pitches it takes, and the line fits where the room
    /// left reaches the foot of that natural height — the grid's extra
    /// below it may hang past the margin. Measured 2026-10-14 (lab
    /// `gf2`, YaHei bold, 1.72 em, on an 18pt grid): 16pt in 36 fits in
    /// 32 and not 31.75 (31.76 by this), 20pt in 36 in 36 and not 35
    /// (35.2), 28pt in 54 in 52 and not 50 (51.1), 12pt in 36 never in
    /// 18. 0 off the grid, or with a height the paragraph states.
    public func gridOverhang(for style: CharStyle, in paragraph: RichParagraphStyle, named: RichNamedStyle?,
                             eastAsian: Bool, gridPitch: Double?) -> Double {
        guard let pitch = gridPitch, pitch > 0, paragraph.lineHeightPoints == nil else { return 0 }
        let size = style.fontSize ?? named?.char.fontSize ?? fontSize
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        guard size > 0, let face = faceResolver?(familyName, eastAsian) else { return 0 }
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        let natural = face.naturalHeight ?? naturalLineHeight(family: face.family, bold: bold, italic: italic)
        let h = lineBox(size: size, natural: natural, baseline: nil, in: paragraph, gridPitch: pitch).height
        return max(0, (h - natural * size) / 2)
    }

    /// Resolve a run's style inside a paragraph to an engine TextStyle, at
    /// `scale` (zoom, 1.0 = 100%).
    ///
    /// `normal` is the sheet's Normal look — the size, face and colour of
    /// every run that states none and whose style states none either: a
    /// 12-point Aptos document's plain paragraphs are in 12-point Aptos,
    /// not the theme's Calibri 11.
    /// `eastAsian` is for a stretch of East Asian text: it takes the
    /// run's East Asian face when the file names one. `gridPitch` is the
    /// document's line grid (points), for a paragraph that snaps to it.
    /// `characterClass` picks one of the face's `classScales`.
    /// `characterGrid` is what the document's grid adds to each
    /// character's width, in points.
    public func textStyle(for style: CharStyle, in paragraph: RichParagraphStyle,
                          named: RichNamedStyle? = nil, normal: CharStyle? = nil,
                          scale: Double, fontScale: Double = 1,
                          eastAsian: Bool = false, gridPitch: Double? = nil, characterClass: Int? = nil,
                          characterGrid: Double? = nil, scriptHidden: Bool = false) -> TextStyle {
        var size = style.fontSize ?? named?.char.fontSize ?? normal?.fontSize ?? fontSize
        // A fitted size is a whole number of points: PowerPoint sets 32 pt
        // at 85% in 27, not 27.2.
        if fontScale != 1 { size = max(1, (size * fontScale).rounded()) }
        var bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        var color = style.color ?? named?.char.color ?? normal?.color ?? textColor
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? normal?.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let face = faceResolver?(familyName, eastAsian)
        let family = face?.family ?? familyName.map { fontFamilyResolver?($0) ?? $0 }
        // (A character scale is laid out as that much smaller or larger
        // a size — the engine sets no face narrower than it is, and the
        // widths are what break the lines — and drawn pulled back to
        // its height: `RichLayout._paintScaled`.)
        let classScale: Double = characterClass.flatMap { k in face?.classScales.flatMap { k < $0.count ? $0[k] : nil } } ?? 1
        let ownScale: Double = style.horizontalScale ?? named?.char.horizontalScale ?? 1
        let widen: Double = (face?.sizeScale ?? 1) * classScale * ownScale
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
        // A raised or lowered run holds its place in the line unseen: the
        // engine has no baseline to shift, so the layout draws it again
        // where it belongs (`_paintScripts`).
        if scriptHidden, style.script != .normal { color = color.withOpacity(0) }
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
                // (And a grid of characters adds its own to every one.)
                let spread = (bold ? (face?.boldSpread ?? 0) * size : 0) + (characterGrid ?? 0)
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
                let natural = (ownScale != 1 ? face?.scaledHeight : nil) ?? face?.naturalHeight
                    ?? naturalLineHeight(family: family, bold: bold, italic: italic)
                guard size > 0 else { return max(0.1, paragraph.lineSpacing - lineSpacingReduction) * natural / widen }
                return lineBox(size: size, natural: natural, baseline: nil, in: paragraph, gridPitch: gridPitch).height / (size * widen)
            }(),
            fontFeatures: disablesLigatures ? [FontFeature("liga", 0), FontFeature("clig", 0)] : nil,
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
    /// The widths, in ems, of the characters U+0020 to U+007E in the
    /// face this one stands in for, and in that face's bold: each is
    /// then set exactly as wide as the original's, whatever the
    /// stand-in draws it (nil: as wide as the scales make it). A line
    /// of Word's breaks by these, and a scale by kind is a per cent or
    /// six off for a single letter — YaHei's "C" is .669 of an em and
    /// a scaled sans's .711.
    public var advances: [Double]? = nil
    public var boldAdvances: [Double]? = nil
    /// The same for characters past those which the original face has
    /// and its stand-in has not, by code point: the stand-in's fallback
    /// draws them, and the line is set by the original's widths (Times
    /// New Roman's Roman numerals, Ⅳ wider than an em).
    public var otherAdvances: [UInt32: Double]? = nil
    public var boldOtherAdvances: [UInt32: Double]? = nil
    /// How far below the top of its single line the face's baseline
    /// sits, in ems, as Word sets it (a Latin face's line gap goes above
    /// the ascent; an East Asian face's extra three tenths go half
    /// above, half below). nil where that is not known: the text then
    /// sits where the engine puts it.
    public var baseline: Double?
    /// The line height and the baseline of the face's characters that
    /// have a scale of their own (`w:w`), where Word measures those
    /// another way: it takes such a stretch's height from the face's
    /// OS/2 metrics, and 华文中宋's are not its hhea ones.
    public var scaledHeight: Double? = nil
    public var scaledBaseline: Double? = nil
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
public struct PageSetup: Hashable, Sendable {
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
    /// The section's line grid (`w:docGrid` of lines: the pitch in
    /// points) and what its grid of characters adds to each one —
    /// nil where the section keeps to none. See
    /// `RichDocument.lineGridPitch`, which is the last section's.
    public var lineGridPitch: Double? = nil
    public var characterGridSpace: Double? = nil
    /// Whether the section's first page has a header and footer of its
    /// own (`w:titlePg`). The last section's is `RichDocument.titlePage`.
    public var titlePage = false

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

    /// Room kept clear for the binding, beside the left margin (Word's
    /// gutter): the text starts that much further in and is that much
    /// narrower.
    public var gutter: Double = 0

    public var contentWidth: Double { width - marginLeft - marginRight - gutter }
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
    /// What of the paragraph the piece shows. A table row that parts
    /// over two pages is cut cell by cell, each at a line of its own, so
    /// its members' pieces show their text alone (`text`) and the row's
    /// rules and shading are a piece apart (`rules`), on the row's first
    /// paragraph, that reaches the page's foot whatever the cells do.
    public var part: Part = .all
    public enum Part: Sendable { case all, rules, text }
    /// A stretch of a row's rules that does not end where the row was
    /// parted: the row is whole on its page, shown shorter or taller
    /// than the flow has it, and no line closes or opens the stretch.
    public var inner = false
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
    /// The fonts' own scale, over `scale`: PowerPoint's shrink-to-fit
    /// (`normAutofit fontScale`) makes the letters smaller and leaves the
    /// indents, the tab stops and the box where they were.
    public var fontScale: Double = 1.0 {
        didSet { if fontScale != oldValue { invalidateAll() } }
    }
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
    private var _floatImages: [ImageAttachment?] = []
    /// How far pagination moved a floating picture to the right, clear of
    /// one already on its page (by image id; `_paginate`).
    private var _floatShift: [String: Double] = [:]
    /// … and up, where its paragraph's line was moved down under the
    /// pictures and the picture stays where the paragraph first stood.
    private var _floatShiftY: [String: Double] = [:]

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
        /// How much of `pad`, top and bottom together, is the row's
        /// rules: a row is that much taller than the height the file
        /// gave it.
        var rules: Double = 0
        /// … and how much of that is the table's bottom rule, which a
        /// cell that reaches the last row carries.
        var ruleBelow: Double = 0
        /// Rows after this cell's that have no paragraph of their own
        /// (every cell of them merged down from above), whose height
        /// `ownRowHeight` takes in: the row's edges are drawn round both.
        var ghostRows = 0
        /// How much of `ownRowHeight` the row was given for the cells
        /// merged down into it, whose text was taller than their rows:
        /// what a page that takes up such a cell part-way can do without.
        var stretched: Double = 0
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
    private var _tableFlowWidth: [String: Double] = [:]   // px: the column each table is laid out in
    private var _tableRows: [String: Int] = [:]           // each table's last row
    public var cellPadding: Double = 4   // px, inside a cell

    private var _painters: [TextPainter?] = []
    private var _textLeft: [Double] = []
    private var _textWidth: [Double] = []
    private var _spaceBefore: [Double] = []
    /// What each paragraph's text is drawn lower by than the engine set
    /// it, so that its baselines are Word's (see `RichTextTheme.lineBox`).
    private var _inkShift: [Double] = []
    /// How far each paragraph's last line on a page may reach past the
    /// page's foot (px; `RichTheme.gridOverhang`).
    private var _overhang: [Double] = []
    /// How far a paragraph's text is set down to clear an object that
    /// floats over its head and leaves its first line no room beside it
    /// (px; part of `_spaceBefore`).
    private var _floatPush: [Double] = []
    /// The width (pixels, either sign) of the box that stands before
    /// each paragraph's text for its first line's indent or its list
    /// number; 0 for none.
    private var _leadWidth: [Double] = []
    /// The tabs of each paragraph that are filled with a leader (a
    /// contents page's dots): the tab's offset, and the character.
    private var _leaders: [[(offset: Int, fill: String)]] = []
    /// Where each paragraph's painter has a character the paragraph has
    /// not: the paragraph offsets a zero-width space stands before (see
    /// `_OffsetMap`).
    private var _inserts: [[Int]] = []
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
        let map = _map(i)
        let paint = Paint()
        paint.style = .stroke
        paint.strokeWidth = 1
        paint.color = theme.spellingColor
        for r in ranges {
            if let c = _paintCaret, c.paragraph == i, r.lowerBound <= c.offset, c.offset <= r.upperBound { continue }
            for box in g.painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(r.lowerBound), extentOffset: map.painter(r.upperBound)),
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
        _floatImages = Array(repeating: nil, count: n)
        _cells = Array(repeating: nil, count: n)
        _rowTops = Array(repeating: 0, count: n)
        _textLeft = Array(repeating: 0, count: n)
        _textWidth = Array(repeating: 0, count: n)
        _spaceBefore = Array(repeating: 0, count: n)
        _inkShift = Array(repeating: 0, count: n)
        _overhang = Array(repeating: 0, count: n)
        _floatPush = Array(repeating: 0, count: n)
        _leadWidth = Array(repeating: 0, count: n)
        _leaders = Array(repeating: [], count: n)
        _inserts = Array(repeating: [], count: n)
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
                _floatImages.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _cells.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _rowTops.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textLeft.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textWidth.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _spaceBefore.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _inkShift.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _overhang.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _floatPush.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _leadWidth.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _leaders.insert(contentsOf: Array(repeating: [], count: n), at: at)
                _inserts.insert(contentsOf: Array(repeating: [], count: n), at: at)
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
                _floatImages.removeSubrange(at ..< end)
                _cells.removeSubrange(at ..< end)
                _rowTops.removeSubrange(at ..< end)
                _textLeft.removeSubrange(at ..< end)
                _textWidth.removeSubrange(at ..< end)
                _spaceBefore.removeSubrange(at ..< end)
                _inkShift.removeSubrange(at ..< end)
                _overhang.removeSubrange(at ..< end)
                _floatPush.removeSubrange(at ..< end)
                _leadWidth.removeSubrange(at ..< end)
                _leaders.removeSubrange(at ..< end)
                _inserts.removeSubrange(at ..< end)
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
        if _resolveSections(document) {
            // A section's page changed, or which paragraphs are in it:
            // everything wraps and paginates again.
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
    /// One side of a cell's own borders as the file wrote them
    /// (`CellRef.bordersXML`): its line style and width in points, nil
    /// where the cell names no such side or says none.
    private static func _cellSide(_ xml: String?, _ side: String) -> (style: String, width: Double)? {
        // (`firstRange(of:)`, the standard library's: `range(of:)` is the
        // legacy Foundation layer, which the web build does not link.)
        guard let xml, let a = xml.firstRange(of: "<w:\(side) "), let b = xml[a.upperBound...].firstRange(of: ">") else { return nil }
        let element = xml[a.upperBound ..< b.lowerBound]
        func value(_ name: String) -> Substring? {
            guard let s = element.firstRange(of: name + "=\""), let e = element[s.upperBound...].firstRange(of: "\"") else { return nil }
            return element[s.upperBound ..< e.lowerBound]
        }
        guard let style = value("w:val"), style != "nil", style != "none" else { return nil }
        return (String(style), max(0.25, (value("w:sz").flatMap { Double($0) } ?? 4) / 8))
    }

    private func _cellInsets(_ table: String, _ document: RichDocument) -> (top: Double, left: Double, bottom: Double, right: Double) {
        let s = document.tableStyles[table]
        // A table that states no cell margins — one made in the editor —
        // has Word's where Word's rules are followed: none above or
        // below, 5.4pt at the sides. That is what its file will mean
        // when it is saved saying nothing, to Word and to this app on
        // reopening: with the editor's own padding its rows came back a
        // fifth shorter (seen on screen 2026-10-13).
        let side = theme.wordRules ? _px(5.4) : cellPadding, end = theme.wordRules ? 0 : cellPadding
        return (s?.cellMarginTop.map(_px) ?? end, s?.cellMarginLeft.map(_px) ?? side,
                s?.cellMarginBottom.map(_px) ?? end, s?.cellMarginRight.map(_px) ?? side)
    }

    private func _tableLeft(_ table: String, _ document: RichDocument) -> Double {
        let sum = (_columnWidths[table] ?? []).reduce(0, +)
        let width = _tableFlowWidth[table] ?? self.width
        // Set out by its cell margin, as Word sets it before its 2013
        // layout: a left-aligned table's edge stands its left cell margin
        // left of its indent, so that the first column's text lines up
        // with the paragraphs'; a right-aligned one its right margin past
        // the right margin; a centred one is centred as it is. From
        // compatibility mode 15 on the indent is the edge's place and
        // nothing is set out (labs `tc` and `tc15`, 2026-10-14: zh-4c3793e8's
        // centred table had been 5.4pt left of Word's).
        let old = theme.wordRules && (document.compatibilityMode ?? 0) < 15
        let style = document.tableStyles[table]
        let left = old ? _px(style?.textOutdent ?? 5.4) : 0
        let right = old ? _px(style?.textOutdentRight ?? 5.4) : 0
        switch style?.alignment ?? .left {
        case .center: return theme.wordRules ? (width - sum) / 2 : max(0, ((width - sum) / 2).rounded(.down))
        case .right: return theme.wordRules ? width - sum + right : max(0, (width - sum).rounded(.down))
        default: return theme.wordRules ? _px(style?.indent ?? 0) - left : _px(style?.indent ?? 0).rounded()
        }
    }

    /// Column widths per table (px); a table whose widths changed has every
    /// cell re-laid out.
    private func _updateTables(_ document: RichDocument) {
        var columns: [String: Int] = [:]
        _tableRows = [:]
        for p in document.paragraphs {
            if let c = p.cell {
                columns[c.table] = max(columns[c.table] ?? 1, c.column + c.span)
                _tableRows[c.table] = max(_tableRows[c.table] ?? 0, c.row + c.rowSpan - 1)
            }
        }
        var widths: [String: [Double]] = [:]
        _tableFlowWidth = [:]
        for (i, p) in document.paragraphs.enumerated() {
            guard let c = p.cell, widths[c.table] == nil else { continue }
            let cols = columns[c.table] ?? 1
            // (The table's section's column.)
            let width = _flowWidth(i)
            _tableFlowWidth[c.table] = width
            if let pts = _columnPreview[c.table] ?? document.tableColumns[c.table], pts.count == cols {
                // Wider than the column: scaled to fit, as Word autofits a
                // table whose grid outgrows the page; a preferred width
                // (a share of the column, or points) scales the grid to it.
                let sum = pts.reduce(0, +)
                var scale = sum > 0 && _px(sum) > width ? width / _px(sum) : 1
                if sum > 0, _columnPreview[c.table] == nil, let ts = document.tableStyles[c.table] {
                    // (A width the table states is its width, past the
                    // margin too where Word's rules are followed: a form
                    // 482pt wide in a 439pt column, set out to the left by
                    // its indent, keeps its columns.)
                    if let pct = ts.widthPercent { scale = (theme.wordRules ? width * pct / 100 : min(width, width * pct / 100)) / _px(sum) }
                    else if let w = ts.width { scale = (theme.wordRules ? _px(w) : min(width, _px(w))) / _px(sum) }
                    // (A fixed layout keeps its grid, past the margin too:
                    // zh-454e2e29's 482pt in a column of 468, whose second
                    // column then holds "個案事實" on one line, as Word's
                    // print has it.)
                    else if theme.wordRules, ts.fixedLayout { scale = 1 }
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
            guard let c = _cells[i] else {
                // The space before it lies over the space after the
                // paragraph above (`theme.collapsesParagraphSpacing`).
                let top = y - _sharedSpace(i, document)
                if i > settled, _rowTops[i] == top { return }
                _tops[i] = top
                _rowTops[i] = top
                y = top + _heights[i]
                i += 1
                continue
            }
            if i > settled, _rowTops[i] == y { return }
            // The table: every row of it, placed in turn; a cell spanning
            // rows takes its height from the rows it covers, and stretches
            // the last of them when its own content is taller.
            let table = c.table
            let ins = _cellInsets(table, document)
            var rows: [(first: Int, end: Int, top: Double, height: Double)] = []
            // The room a rule takes (`theme.tableRulesTakeRoom`): the
            // first row's top one, and every row's bottom one.
            let ts = document.tableStyles[table]
            func rule(_ side: String, _ on: Bool?) -> Double {
                // (Under Word's rules each cell carries its own row's
                // rules in its margins — its own sides, the row above's,
                // a double line's three widths: `_layoutParagraph`.)
                guard theme.tableRulesTakeRoom, !theme.wordRules, on ?? ts?.borders ?? true else { return 0 }
                return _px(ts?.edgeWidths[side] ?? ts?.borderWidth ?? 0.5)
            }
            var rules: [(above: Double, below: Double)] = []
            var k0 = i
            while k0 < n, let d = _cells[k0], d.table == table {
                // A row with no paragraph of its own — every cell of it
                // merged down from above — is a row all the same: as
                // tall as the file says, and counted by the cells that
                // span it. (Left out, a cell merged over three rows was
                // measured against the row after them, never stretched
                // its own, and ran into the text below.)
                while rows.count < d.row {
                    let h = _px(document.tableStyles[table]?.rowHeights[rows.count] ?? 0)
                    rows.append((k0, k0, y, h))
                    rules.append((0, 0))
                    y += h
                }
                var j = k0
                while j < n, let d2 = _cells[j], d2.table == table, d2.row == d.row { j += 1 }
                var stack: [Int: Double] = [:]
                var rowHeight = 0.0
                var ruled = 0.0
                let ruleAbove = rows.isEmpty ? rule("top", ts?.edges?.top) : 0
                let lastRow = !(j < n && _cells[j]?.table == table)
                let ruleBelow = lastRow ? rule("bottom", ts?.edges?.bottom) : rule("insideH", ts?.edges?.insideH)
                for k in k0 ..< j {
                    let cell = _cells[k]!
                    if cell.rowSpan == 1 { ruled = max(ruled, cell.rules) }
                    let offset = stack[cell.column] ?? 0
                    _tops[k] = y + ruleAbove + cell.pad.top + offset
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
                // (And its rules: the height is the room between them.)
                // An exact one is that tall with its rules, whatever is in it.
                if let least = document.tableStyles[table]?.rowHeights[d.row] {
                    let exact = theme.wordRules && (document.tableStyles[table]?.rowsExactHeight.contains(d.row) ?? false)
                    rowHeight = exact ? _px(least) : max(rowHeight, _px(least) + ruled)
                }
                rowHeight += ruleAbove + ruleBelow
                rules.append((ruleAbove, ruleBelow))
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
            // (… and so are such rows after the last that has one.)
            while theme.wordRules, !rows.isEmpty, rows.count <= _tableRows[table] ?? 0 {
                let h = _px(document.tableStyles[table]?.rowHeights[rows.count] ?? 0)
                rows.append((k0, k0, y, h))
                rules.append((0, 0))
                y += h
            }
            // A row in which no cell stands alone — each one merged on
            // into the row below, or down from the row above — Word
            // sizes by the cells themselves: one that starts there gives
            // its first line and the space after its first paragraph,
            // one that continues gives the (empty) paragraphs the file
            // wrote in it. Beside a cell of the row's own they give
            // nothing, and a merged cell's text counts where it ends.
            // (Measured off Word's rules, 2026-10-13: two rows merged
            // whole, a 14pt line with 8pt after in each cell, are 22 and
            // 22, not 22 over both; a thin cell beside them and they are
            // its height. A table of such rows ran a page short.)
            if theme.wordRules {
                var alone = rows.map { _ in false }
                var own = rows.map { _ in 0.0 }
                var measured: [RichParagraph: Double] = [:]
                for (r, row) in rows.enumerated() {
                    var seen: Set<Int> = []
                    for k in row.first ..< row.end {
                        let cell = _cells[k]!
                        guard seen.insert(cell.column).inserted else { continue }
                        if cell.rowSpan == 1 || cell.vertical { alone[r] = true; continue }
                        let pads = cell.pad.top + cell.pad.bottom - cell.ruleBelow
                        let firstLine = _painters[k].flatMap { Self._lineBottoms($0).first }
                        own[r] = max(own[r], (firstLine.map { $0 + _spacing(k, document).after } ?? _heights[k]) + pads)
                        let continued = document.paragraphs[k].cell?.continuationParagraphs ?? []
                        for offset in 1 ..< cell.rowSpan where r + offset < rows.count && offset - 1 < continued.count {
                            var h = 0.0
                            for p in continued[offset - 1] {
                                if measured[p] == nil { measured[p] = _detachedHeight(p, document) }
                                h += measured[p]!
                            }
                            own[r + offset] = max(own[r + offset], h + pads + (offset == cell.rowSpan - 1 ? cell.ruleBelow : 0))
                        }
                    }
                }
                var shift = 0.0
                for r in rows.indices {
                    rows[r].top += shift
                    guard !alone[r], !(ts?.rowsExactHeight.contains(r) ?? false) else { continue }
                    let want = (own[r] + rules[r].above + rules[r].below).rounded(.up)
                    if want > rows[r].height + 0.01 {
                        shift += want - rows[r].height
                        rows[r].height = want
                    }
                }
            }
            // Stretch for spanning cells, in the order of the rows they
            // end in; later rows shift. (By the rows they start in, a
            // cell over three rows was measured before the cell beside
            // it, over two, had stretched the second — and then stood
            // that much too tall.)
            var spanning: [(first: Int, last: Int, need: Double)] = []
            var stretched = rows.map { _ in 0.0 }
            for (r, row) in rows.enumerated() {
                var stackByColumn: [Int: Double] = [:]
                for k in row.first ..< row.end {
                    let cell = _cells[k]!
                    guard cell.rowSpan > 1, !cell.vertical else { continue }
                    stackByColumn[cell.column, default: 0] += _heights[k]
                    let need = stackByColumn[cell.column]! + cell.pad.top + cell.pad.bottom
                    spanning.append((r, min(rows.count - 1, r + cell.rowSpan - 1), need))
                }
            }
            for (_, cell) in spanning.enumerated().sorted(by: { ($0.element.last, $0.offset) < ($1.element.last, $1.offset) }) {
                let have = rows[cell.first ... cell.last].map(\.height).reduce(0, +)
                if cell.need > have + 0.01 {
                    let extra = cell.need - have
                    rows[cell.last].height += extra
                    stretched[cell.last] += extra
                    for (rr, later) in rows.enumerated() where rr > cell.last { rows[rr].top = later.top + extra }
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
                // The rows after it that hold no paragraph are drawn and
                // paged as part of this one: every cell of this row runs
                // on through them.
                var ghosts = 0.0, ghostCount = 0, given = stretched[r]
                while r + ghostCount + 1 < rows.count, rows[r + ghostCount + 1].first == rows[r + ghostCount + 1].end {
                    ghostCount += 1
                    ghosts += rows[r + ghostCount].height
                    given += stretched[r + ghostCount]
                }
                var stack: [Int: Double] = [:]
                for k in row.first ..< row.end {
                    let cell = _cells[k]!
                    let offset = stack[cell.column] ?? 0
                    let last = min(rows.count - 1, r + cell.rowSpan - 1)
                    let spanned = cell.rowSpan > 1 ? rows[r ... last].map(\.height).reduce(0, +) : row.height
                    let room = cell.vertical ? cell.colWidth - cell.pad.left - cell.pad.right
                        : spanned - cell.pad.top - cell.pad.bottom - rules[r].above - rules[last].below
                    let free = max(0, room - (content[cell.column] ?? 0))
                    let shift = cell.verticalAlign == "center" ? free / 2 : cell.verticalAlign == "bottom" ? free : 0
                    if cell.vertical {
                        _tops[k] = row.top
                        _cells[k]!.across = cell.acrossStart + offset + shift
                    } else {
                        _tops[k] = row.top + rules[r].above + cell.pad.top + offset + shift
                    }
                    _rowTops[k] = row.top
                    stack[cell.column] = offset + _heights[k]
                    _cells[k]!.rowTop = row.top
                    _cells[k]!.ownRowHeight = row.height + ghosts
                    _cells[k]!.ghostRows = ghostCount
                    _cells[k]!.stretched = given
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
    private func _pxColumnW(_ page: Int) -> Double { _px(pageSetup(forPage: page).columnWidth) }
    private func _pxColumnStride(_ page: Int) -> Double {
        let s = pageSetup(forPage: page)
        return _px(s.columnWidth + s.columnGap)
    }
    private func _pxPageW(_ page: Int) -> Double { _px(pageSetup(forPage: page).width) }
    private func _pxPageH(_ page: Int) -> Double { _px(pageSetup(forPage: page).height) }
    private var _pxGap: Double { _px(pageSetup!.gap) }
    private func _pxMarginTop(_ page: Int) -> Double {
        page >= 0 && page < _pageInsetTop.count ? _pageInsetTop[page] : _px(pageSetup(forPage: page).marginTop)
    }
    private func _pxMarginLeft(_ page: Int) -> Double {
        let s = pageSetup(forPage: page)
        // Mirrored margins (Word's `w:mirrorMargins`): the left margin
        // and the gutter are the INSIDE ones, on the left of an odd
        // page and the right of an even one, where the text starts at
        // the right margin's distance instead (zh-457a8d62, a gutter
        // of 11.35pt: its even pages begin at 70.9 and its odd ones at
        // 82.25).
        if _mirrorsMargins, page % 2 == 1 { return _px(s.marginRight) }
        return _px(s.marginLeft + s.gutter)
    }
    private var _mirrorsMargins = false

    // MARK: Sections
    //
    // A document's sections may each have their own page: a paragraph
    // that ends one carries its page setup (`sectionPage`), and the last
    // section's is `pageSetup`. A paragraph wraps at its section's
    // column width, and a page is its first paragraph's section's.
    // (Columns are the document's throughout.)

    /// Each section's page, in order; the last is `pageSetup`.
    private var _sectionSetups: [PageSetup] = []
    /// Each paragraph's section.
    private var _sectionOf: [Int] = []
    /// Each page's section, and each page's top on the canvas.
    private var _pageSection: [Int] = []
    private var _pageTops: [Double] = []
    /// Where each page's text starts below its top (pixels): the top
    /// margin, or under a taller header.
    private var _pageInsetTop: [Double] = []

    /// Page `p`'s setup: its section's.
    public func pageSetup(forPage p: Int) -> PageSetup {
        guard p >= 0, p < _pageSection.count, _pageSection[p] < _sectionSetups.count else { return pageSetup ?? .letter }
        return _sectionSetups[_pageSection[p]]
    }

    private func _setup(ofParagraph i: Int) -> PageSetup {
        guard i >= 0, i < _sectionOf.count, _sectionOf[i] < _sectionSetups.count else { return pageSetup ?? .letter }
        return _sectionSetups[_sectionOf[i]]
    }

    /// The width paragraph `i` wraps at: the layout's, in the measure of
    /// its section's column to the document's.
    private func _flowWidth(_ i: Int) -> Double {
        guard let base = pageSetup, _sectionSetups.count > 1, base.columnWidth > 0 else { return width }
        return width * _setup(ofParagraph: i).columnWidth / base.columnWidth
    }

    /// The grid paragraph `i` keeps to: its section's, which for the
    /// last section (and a document of one) is the document's.
    private func _grid(_ i: Int?, _ document: RichDocument) -> (pitch: Double?, chars: Double?) {
        guard let i, _sectionSetups.count > 1, i >= 0, i < _sectionOf.count, _sectionOf[i] < _sectionSetups.count - 1 else {
            return (document.lineGridPitch, document.characterGridSpace)
        }
        let setup = _sectionSetups[_sectionOf[i]]
        return (setup.lineGridPitch, setup.characterGridSpace)
    }

    /// The height of a paragraph that is not in the flow — one a
    /// vertically merged cell's continuation holds — with its spacing.
    private func _detachedHeight(_ p: RichParagraph, _ document: RichDocument) -> Double {
        let (span, _, _) = _span(for: p, at: nil, document, textWidth: _px(1000))
        let painter = TextPainter(text: span, textAlign: .left, textDirection: .ltr, strutStyle: _strut(span))
        painter.layout()
        defer { painter.dispose() }
        let body = p.style.lineCollapsed ? 0 : painter.height
        return (_px(p.style.spaceBefore) + body + _px(p.style.spaceAfter)).rounded(.up)
    }

    /// Where each of a painter's lines ends below its top. The engine's
    /// line heights are the lines' own — a first line that opens with
    /// the indent's box is reported an ascent taller than it is set —
    /// and under a forced strut do not add up to the painter's height
    /// (585, 560, 560 for three lines of 560): there every line ends
    /// as far below its baseline as the last does.
    static func _lineBottoms(_ painter: TextPainter) -> [Double] {
        let lines = painter.computeLineMetrics()
        var out: [Double] = []
        var sum = 0.0
        for line in lines { sum += line.height; out.append(sum) }
        guard let last = lines.last, abs(sum - painter.height) > 0.5, painter.strutStyle?.forceStrutHeight == true else { return out }
        let below = painter.height - last.baseline
        return lines.map { min(painter.height, $0.baseline + below) }
    }

    /// Reads the sections off the paragraphs; true when they changed.
    private func _resolveSections(_ document: RichDocument) -> Bool {
        guard let last = pageSetup, theme.wordRules else {
            let had = _sectionSetups.count > 1
            _sectionSetups = []
            _sectionOf = []
            _mirrorsMargins = false
            return had
        }
        _mirrorsMargins = document.marginSettingsXML.map { $0.containsSubstring("<w:mirrorMargins") && !$0.containsSubstring("<w:mirrorMargins w:val=\"0\"") } ?? false
        var setups: [PageSetup] = []
        var of = Array(repeating: 0, count: document.paragraphs.count)
        var start = 0
        for (i, p) in document.paragraphs.enumerated() where p.cell == nil {
            guard var setup = p.style.sectionPage, i < document.paragraphs.count - 1 else { continue }
            setup.columns = last.columns
            setup.columnGap = last.columnGap
            setup.gap = last.gap
            for k in start ... i { of[k] = setups.count }
            setups.append(setup)
            start = i + 1
        }
        if start < of.count { for k in start ..< of.count { of[k] = setups.count } }
        setups.append(last)
        let changed = setups != _sectionSetups || (setups.count > 1 && of != _sectionOf)
        _sectionSetups = setups
        _sectionOf = of
        return changed
    }

    /// Cut the flow into pages. A paragraph that straddles a page boundary
    /// is split between lines (its painter is painted twice, clipped), so
    /// the breakable positions inside a block are the bottoms of its lines.
    private func _paginate(_ document: RichDocument, from start: Int = 0, settled: Int = Int.max) {
        var contentH = 1.0
        var page = 0
        var y = 0.0
        var i = 0
        // A page is as tall as its section's content: the section of the
        // paragraph that opens it.
        var pageFresh = true   // no paragraph has been set on this page yet, not even an empty one
        func openPage() {
            pageFresh = true
            let para = min(i, max(0, count - 1))
            let physical = page / _columns
            if page % _columns == 0 {
                while _pageSection.count <= physical { _pageSection.append(0) }
                _pageSection[physical] = para < _sectionOf.count ? _sectionOf[para] : max(0, _sectionSetups.count - 1)
            }
            // (Between the header and the footer, where they reach past
            // the margins.)
            let insets = _bodyInsets(page: physical, document)
            while _pageInsetTop.count <= physical { _pageInsetTop.append(0) }
            _pageInsetTop[physical] = insets.top
            contentH = max(1, _px(pageSetup(forPage: physical).height) - insets.top - insets.bottom)
        }
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
           let first = _pages[p].first(where: { !$0.repeated }), first.part == .all {
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
        var prevContentH = contentH
        var prevY = 0.0   // how far down the page before was filled
        // The floating pictures on this page that text wraps round: page
        // y, and x from the column's edge.
        var bands: [(top: Double, bottom: Double, left: Double, right: Double)] = []
        // The paragraphs of nothing but floating pictures set on this
        // page since the last with text (`_anchorsOnly`).
        var anchorRun: [Int] = []
        func newPage() {
            bands.removeAll()
            anchorRun.removeAll()
            var fresh: [PagePiece] = []
            fresh.reserveCapacity(32)
            _pages.append(fresh)
            page += 1
            prevY = y
            y = 0
            prevContentH = contentH
            openPage()
        }
        if restarted {
            // (The page restarted on keeps its section.)
            let insets = _bodyInsets(page: page / _columns, document)
            contentH = max(1, _px(pageSetup(forPage: page / _columns).height) - insets.top - insets.bottom)
        } else {
            _pageSection.removeAll(keepingCapacity: true)
            openPage()
        }
        func add(_ piece: PagePiece) {
            _pages[page].append(piece)
            _allPieces.append(piece)
            pageFresh = false
        }
        // A table's header row, repeated at the top of each later page it
        // runs on: the row's pieces again, marked, in the page only.
        // How many of a table's first rows are its header, repeated on
        // each page it runs on: the rows the file marks — none where it
        // marks them all, which Word repeats nothing of (a form of
        // sixteen rows, each marked: every page began with the form's
        // head again and never got past it).
        func headerRows(_ table: String) -> Int {
            guard let ts = document.tableStyles[table], ts.headerRow else { return 0 }
            let n = theme.wordRules ? max(1, ts.headerRowCount) : 1
            return theme.wordRules && n > (_tableRows[table] ?? 0) ? 0 : n
        }
        func repeatHeader(of table: String, before i: Int) {
            var k0 = i
            while k0 > 0, let d = _cells[k0 - 1], d.table == table { k0 -= 1 }
            guard let h = _cells[k0], h.row == 0 else { return }
            // (Every row the file marks as a header, where Word's rules
            // are followed: a heading of two rows is repeated whole.)
            let rows = headerRows(table)
            var j = k0
            var height = 0.0
            var pieces: [PagePiece] = []
            while j < count, let d = _cells[j], d.table == table, d.row < rows {
                let bottom = d.rowSpan > 1 ? d.rowTop + d.rowHeight : d.rowTop + d.ownRowHeight
                var piece = PagePiece(paragraph: j, flowTop: d.rowTop, flowBottom: bottom, page: page, pageY: y + (d.rowTop - h.rowTop))
                piece.repeated = true
                pieces.append(piece)
                height = max(height, d.rowTop + d.ownRowHeight - h.rowTop)
                j += 1
            }
            // (Not a header that leaves the page no room under it.)
            guard height < contentH - y - 1 else { return }
            _pages[page].append(contentsOf: pieces)
            y += height
        }
        // A table row too tall for what is left of the page parts over
        // the page's foot, as Word parts it (prints of 2026-10-13): where
        // one line at least of one of its cells fits — no widow or orphan
        // is kept in a cell — each cell is cut under its own last line
        // that fits, and each goes on from the top of the next page.
        // Not a row Word may not split (`w:cantSplit`), a repeated
        // header row, or one with merged or turned cells.
        // Where a cell's paragraph may part at a page's foot: under any
        // of its lines, as Word parts it before its 2013 layout, which
        // keeps no widow or orphan in a table; from that layout on a
        // paragraph with widow control (Word's default) parts only with
        // two lines on each side — a row with room for one line of each
        // cell goes to the next page whole (prints of 2026-10-13, modes
        // 14 and 15).
        // The rule under a row is the next row's, and wants its room on
        // the row's page all the same: a row fits a page with the line
        // below it, and a row parted at the foot is closed there with
        // one. (Prints of 2026-10-13: a line with 0.45pt under it at
        // the foot goes over where the rules are half a point, with
        // 1.05 where they are a point and a half, and stays with 0.1
        // where there are none.) The table's last row has its own.
        func ruleUnder(_ c: _CellGeo, parted: Bool = false) -> Double {
            guard theme.wordRules else { return 0 }
            return c.ruleBelow > 0 && !parted ? 0 : max(0, c.rules - c.ruleBelow)
        }
        func cellCuts(_ k: Int) -> [Double] {
            let g = geometry(k)
            var lines = Self._lineBottoms(g.painter).map { g.textTop + $0 }
            if (document.compatibilityMode ?? 12) >= 15, document.paragraphs[k].style.widowControl {
                lines = lines.count >= 4 ? Array(lines[1 ..< lines.count - 2]) : []
            } else if !lines.isEmpty {
                lines.removeLast()
            }
            return lines + [_tops[k] + _heights[k]]
        }
        // A cell merged down from a row above (Word's `w:vMerge`) is
        // one cell over the rows it covers, and its text is cut at a
        // page's foot like any cell's: when the table goes on to a new
        // page under it, what of it did not fit on the page before goes
        // on from the top of this one.
        func continueSpans(into i: Int, _ c: _CellGeo) {
            guard theme.wordRules, page > 0 else { return }
            var spans: [[Int]] = []
            var open: (row: Int, column: Int)? = nil
            var k = i - 1
            while k >= 0, let d = _cells[k], d.table == c.table {
                if d.row < c.row, d.row + d.rowSpan > c.row, !d.vertical {
                    if let o = open, o.row == d.row, o.column == d.column {
                        spans[spans.count - 1].insert(k, at: 0)
                    } else {
                        spans.append([k])
                        open = (d.row, d.column)
                    }
                } else {
                    open = nil
                }
                k -= 1
            }
            for members in spans {
                // The cell's pieces on the page before, last first.
                var found: [Int] = []
                var n = _allPieces.count - 1
                while n >= 0, _allPieces[n].paragraph >= members[0] {
                    let piece = _allPieces[n]
                    if piece.page == page - 1, piece.part != .rules, !piece.repeated, members.contains(piece.paragraph) { found.append(n) }
                    n -= 1
                }
                guard let ref = found.first.map({ _allPieces[$0] }) else { continue }
                // That page's foot, in the flow as the cell was set on it.
                // (… or the foot of the table's last row there, where
                // the row after it went over whole: the cell's lines
                // below that go with it.)
                let limit = ref.flowTop + (min(prevContentH - ruleUnder(c, parted: true), prevY) - ref.pageY) + 0.01
                let last = members[members.count - 1]
                guard _tops[last] + _heights[last] > limit else { continue }
                var cut: Double? = nil
                for m in members {
                    for b in cellCuts(m) where b <= limit { cut = max(cut ?? b, b) }
                }
                let shownFrom = found.map { max(_allPieces[$0].flowTop, _tops[_allPieces[$0].paragraph]) }.min() ?? ref.flowTop
                let at = max(cut ?? shownFrom, shownFrom)
                for n in found {
                    let old = _allPieces[n]
                    let m = old.paragraph
                    let top = max(_tops[m], old.flowTop), bottom = _tops[m] + _heights[m]
                    guard bottom > at + 0.01, old.flowBottom > at + 0.01 else { continue }
                    var fresh = PagePiece(paragraph: m, flowTop: max(top, at), flowBottom: bottom, page: page, pageY: y + max(0, top - at))
                    fresh.part = .text
                    // What stays on the page before: the text above the
                    // cut, and the row's rules where this piece drew them.
                    var kept: [PagePiece] = []
                    if top < at - 0.01 {
                        var text = PagePiece(paragraph: m, flowTop: old.flowTop, flowBottom: at, page: old.page, pageY: old.pageY)
                        text.part = old.part == .all ? .text : old.part
                        kept.append(text)
                    }
                    if old.part == .all {
                        var rules = PagePiece(paragraph: m, flowTop: old.flowTop, flowBottom: min(old.flowBottom, limit), page: old.page, pageY: old.pageY)
                        rules.part = .rules
                        kept.append(rules)
                    }
                    _allPieces.replaceSubrange(n ... n, with: kept + [fresh])
                    if let at = _pages[old.page].lastIndex(of: old) { _pages[old.page].replaceSubrange(at ... at, with: kept) }
                    _pages[page].append(fresh)
                }
            }
        }
        var wentOver = false   // `splitRow` moved its row to a new page and left it to the caller
        func splitRow(_ i: Int, _ j: Int, _ c: _CellGeo, atTop: Bool) -> Bool {
            let ts = document.tableStyles[c.table]
            guard let ts, !ts.rowsCantSplit.contains(c.row), c.row >= headerRows(c.table) else { return false }
            for k in i ..< j { guard let d = _cells[k], !d.vertical else { return false } }
            var fresh = atTop
            let rowBottom = c.rowTop + c.ownRowHeight
            struct Column { var members: [Int]; var cuts: [Double]; var bottom: Double; var cut: Double }
            var columns: [Column] = []
            for k in i ..< j {
                let d = _cells[k]!
                if columns.isEmpty || _cells[columns[columns.count - 1].members[0]]!.column != d.column {
                    columns.append(Column(members: [], cuts: [], bottom: 0, cut: c.rowTop))
                }
                columns[columns.count - 1].members.append(k)
                columns[columns.count - 1].cuts.append(contentsOf: cellCuts(k))
                // (A cell merged down has the rows below for the rest.)
                columns[columns.count - 1].bottom = d.rowSpan > 1 ? min(rowBottom, _tops[k] + _heights[k] + d.pad.bottom)
                    : _tops[k] + _heights[k] + d.pad.bottom
            }
            let repeats = c.row > 0 && headerRows(c.table) > 0
            var pieces: [Int: [PagePiece]] = [:]
            var rules: [PagePiece] = []
            var first = true
            while true {
                let avail = contentH - y
                // (What goes over is a row again, and no shorter than
                // the file says a row is: the second half of a row of
                // 28.5pt at least is 28.75 at the head of Word's page.)
                // (With the line it opens with: 29.4 from the page's head.)
                let stated = ts.rowsExactHeight.contains(c.row) || ts.rowHeights[c.row] == nil ? 0
                    : min(c.ownRowHeight, _px(ts.rowHeights[c.row]!) + max(0, c.rules - c.ruleBelow))
                let rest = first ? c.ownRowHeight : max(stated, columns.map { max(0, $0.bottom - $0.cut) }.max() ?? 0)
                var fits = rest + ruleUnder(c) <= avail + 0.01
                // A row is not begun where the height the file states
                // for it has no room: it goes to the next page whole,
                // though a line of each cell would fit (prints of
                // 2026-10-13: a row of 49.65 at least with 36.5 left
                // goes over, one of 25 at least parts, as one with no
                // height does — whatever its cells' alignment, and a
                // cell merged down into it leaves its lines with it).
                if first, !fresh, y > 0.01, stated > 0, stated + ruleUnder(c) > avail + 0.01 {
                    newPage()
                    if repeats { repeatHeader(of: c.table, before: i) }
                    if c.row > 0 { continueSpans(into: i, c) }
                    wentOver = true
                    return false
                }
                var next = columns.map(\.cut)
                if !fits {
                    // (Every cell with something left must take some of
                    // it: where one cannot — a paragraph that may not
                    // part there — the row goes to the next page whole.
                    // On a page of its own it takes what it can.)
                    var moved = false, stuck = false
                    for (n, column) in columns.enumerated() {
                        let limit = column.cut + avail - ruleUnder(c, parted: true) + 0.01
                        if column.bottom <= limit {
                            // (All that is left of this cell is on this page.)
                            if column.bottom > column.cut + 0.01 { moved = true }
                            next[n] = max(column.cut, rowBottom)
                        } else if let cut = column.cuts.last(where: { $0 > column.cut + 0.01 && $0 <= limit }) {
                            next[n] = cut
                            moved = true
                        } else {
                            stuck = true
                        }
                    }
                    if stuck, !fresh { moved = false }
                    if !moved {
                        if !fresh, y > 0.01 {
                            // Not a line of it fits here: the row starts the next page.
                            newPage()
                            fresh = true
                            if repeats { repeatHeader(of: c.table, before: i) }
                            if c.row > 0 { continueSpans(into: i, c) }
                            continue
                        }
                        // (A line taller than a page: placed, and over the foot.)
                        fits = true
                    }
                }
                // The rules: from the row's top down to the page's foot,
                // then the row's last stretch with its bottom line.
                let shown = fits ? rest : avail
                let from = first ? c.rowTop : fits ? rowBottom - rest : max(c.rowTop + 1, min(rowBottom - rest, rowBottom - avail - 1))
                var rule = PagePiece(paragraph: i, flowTop: from, flowBottom: min(rowBottom, from + shown), page: page, pageY: y)
                rule.part = .rules
                rules.append(rule)
                _pages[page].append(rule)
                for (n, column) in columns.enumerated() {
                    for k in column.members {
                        let top = _tops[k], bottom = top + _heights[k]
                        let lo = max(top, column.cut), hi = fits ? bottom : min(bottom, next[n])
                        guard hi > lo + 0.01 || (pieces[k] == nil && hi >= lo && bottom <= lo + 0.01) else { continue }
                        var piece = PagePiece(paragraph: k, flowTop: lo, flowBottom: hi, page: page, pageY: y + (lo - column.cut))
                        piece.part = .text
                        pieces[k, default: []].append(piece)
                        _pages[page].append(piece)
                    }
                }
                y += shown
                if fits { break }
                for n in columns.indices { columns[n].cut = next[n] }
                first = false
                newPage()
                fresh = true
                if repeats { repeatHeader(of: c.table, before: i) }
                if c.row > 0 { continueSpans(into: i, c) }
            }
            // (In paragraph order, the rules after their paragraph's text.)
            for k in i ..< j {
                _allPieces.append(contentsOf: pieces[k] ?? [])
                if k == i { _allPieces.append(contentsOf: rules) }
            }
            return true
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
                // (At a page's top the table goes on: its header row
                // again, and the cells merged down from above.)
                func goOn() {
                    guard c.row > 0 else { return }
                    if headerRows(c.table) > 0 { repeatHeader(of: c.table, before: i) }
                    continueSpans(into: i, c)
                }
                let atTop = y < 0.01
                if atTop { goOn() }
                // A row made taller in the flow for a cell merged down
                // into it need not be so here, where that cell's text
                // was taken up again at the head of the page: it is as
                // tall as what is left of the cell asks, and no shorter
                // than itself. (Word lays the rows of each page out
                // with what the page holds: the room lost at the foot
                // of the page before is not owed again under the cell.)
                func pageHeight() -> Double {
                    guard theme.wordRules, c.stretched > 0.01 else { return c.ownRowHeight }
                    var need = 0.0, continued = false
                    for piece in _pages[page] where piece.part != .rules && piece.paragraph < i && !piece.repeated {
                        let m = piece.paragraph
                        guard let d = _cells[m], d.table == c.table, d.row < c.row, !d.vertical,
                              (c.row ... c.row + c.ghostRows).contains(d.row + d.rowSpan - 1) else { continue }
                        if piece.part == .text { continued = true }
                        need = max(need, piece.pageY + (min(piece.flowBottom, _tops[m] + _heights[m]) - piece.flowTop) + d.pad.bottom - y)
                    }
                    // (Taller than the flow made it, too: a cell that left
                    // one line with the row above and took four over the
                    // page asks this row for all four.)
                    return continued ? max(c.ownRowHeight - c.stretched, need) : c.ownRowHeight
                }
                var shown = pageHeight()
                wentOver = false
                if theme.wordRules, shown + ruleUnder(c) > contentH - y + 0.01, splitRow(i, j, c, atTop: atTop) {
                    if y > contentH - 0.01 { newPage() }
                    i = j
                    continue
                }
                if wentOver {
                    // (The row went to a new page whole: there it is laid
                    // out again, and parted if the page cannot hold it.)
                    shown = pageHeight()
                    if shown + ruleUnder(c) > contentH - y + 0.01, splitRow(i, j, c, atTop: true) {
                        if y > contentH - 0.01 { newPage() }
                        i = j
                        continue
                    }
                } else if !atTop, shown + ruleUnder(c) > contentH - y + 0.01, y > 0.01 {
                    newPage()
                    goOn()
                    shown = pageHeight()
                }
                if abs(shown - c.ownRowHeight) > 0.01 {
                    // Its cells' text from where each stands in a row of
                    // that height, and its rules: their last stretch with
                    // the line under it, under as much of their middle
                    // as a taller row needs.
                    let spare = c.ownRowHeight - shown
                    let edge = min(_px(2), c.ownRowHeight / 4)
                    for k in i ..< j {
                        let d = _cells[k]!
                        let down = d.rowSpan > 1 ? 0 : d.verticalAlign == "center" ? spare / 2 : d.verticalAlign == "bottom" ? spare : 0
                        var text = PagePiece(paragraph: k, flowTop: c.rowTop + down,
                                             flowBottom: d.rowSpan > 1 ? c.rowTop + d.rowHeight : c.rowTop + down + shown, page: page, pageY: y)
                        text.part = .text
                        add(text)
                        guard k == i else { continue }
                        var at = y, left = shown
                        while left > c.ownRowHeight + 0.01 {
                            let top = at == y ? c.rowTop : c.rowTop + edge
                            let take = min(rowBottom - edge - top, left - edge)
                            var middle = PagePiece(paragraph: i, flowTop: top, flowBottom: top + take, page: page, pageY: at)
                            middle.part = .rules
                            middle.inner = true
                            add(middle)
                            at += take
                            left -= take
                        }
                        var rules = PagePiece(paragraph: i, flowTop: rowBottom - left, flowBottom: rowBottom, page: page, pageY: at)
                        rules.part = .rules
                        rules.inner = true
                        add(rules)
                    }
                    y += shown
                    if y > contentH - 0.01 { newPage() }
                    i = j
                    continue
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
            // (One of no height takes its place on the page all the same.)
            if bottom - top < 0.01 { pageFresh = false }
            if _pageBreak[i] && (y > 0 || !_pages[page].isEmpty) && resumeCursor == nil {
                newPage()
            }
            // Kept with what follows (Word's `w:keepNext`, a heading's):
            // this paragraph, any kept run after it, and the start of
            // what follows them go to the next page together when this
            // page has no room for all of it.
            if theme.wordRules, resumeCursor == nil, y > 0.01, document.paragraphs[i].style.keepNext {
                var need = 0.0
                var k = i
                while k < count, _cells[k] == nil, document.paragraphs[k].style.keepNext, k - i < 8 {
                    need += _heights[k]
                    k += 1
                }
                if k < count {
                    if let c = _cells[k] {
                        need += c.ownRowHeight
                    } else {
                        // (As much of it as may stand alone at a page's foot.)
                        let st = document.paragraphs[k].style
                        let g = geometry(k)
                        let lines = g.painter.computeLineMetrics()
                        if st.keepLines || lines.count <= 1 || (st.widowControl && lines.count <= 3) {
                            need += _heights[k]
                        } else {
                            let bottoms = Self._lineBottoms(g.painter)
                            need += (g.textTop - g.top) + bottoms[min(bottoms.count - 1, st.widowControl ? 1 : 0)]
                        }
                    }
                }
                if need <= contentH + 0.01, need > contentH - y + 0.01 { newPage() }
            }
            // The space it shares with the paragraph above (`_sharedSpace`)
            // is on the page once, as it is in the flow.
            if i > 0, _cells[i - 1] == nil, y > 0.01, resumeCursor == nil {
                y -= min(y, max(0, _tops[i - 1] + _heights[i - 1] - top))
            }
            // Pictures that text wraps round (2026-10-14, zh-37b6536f's
            // photographs, from Word's print):
            // - a paragraph with less than an em beside the pictures over
            //   its top, either side, goes below them — empty ones too: a
            //   row of two photos across the column has the next anchor
            //   under it, where beside one narrower photo eleven empty
            //   paragraphs stand in the 43pt left over;
            // - a paragraph whose own picture would run past the page's
            //   foot goes to the next page with it;
            // - a picture that would lie over one already on the page
            //   stands to its right (the second of two photos of a row,
            //   anchored 10pt left of the column, is drawn beside the
            //   first).
            if theme.wordRules, resumeCursor == nil, _cells[i] == nil {
                let column = _flowWidth(i)
                let gap = _px(9)
                let em = _px(document.paragraphs[i].runs.first?.style.fontSize ?? theme.fontSize)
                // (Over any of the line, not only its top: an empty
                // anchor's line that a photo starts 16pt down went under
                // the photo in Word's print.)
                func noRoom(at at: Double, height: Double = 0, _ extra: [(top: Double, bottom: Double, left: Double, right: Double)]) -> Double? {
                    let over = (bands + extra).filter { $0.top < at + max(0.02, height) - 0.01 && $0.bottom > at + 0.01 }
                    guard !over.isEmpty else { return nil }
                    // The widest stretch of the column no picture covers.
                    var spans = over.map { (max(0, $0.left - gap), min(column, $0.right + gap)) }.sorted { $0.0 < $1.0 }
                    var widest = 0.0, edge = 0.0
                    for s in spans { widest = max(widest, s.0 - edge); edge = max(edge, s.1) }
                    widest = max(widest, column - edge)
                    spans.removeAll()
                    return widest < em ? over.map(\.bottom).min() : nil
                }
                var guardSteps = 0
                while let below = noRoom(at: y, []), guardSteps < 20 { y = below; guardSteps += 1 }
                if y > contentH - 0.01 { newPage() }
                var mine = _wrapBoxes(i)
                for box in mine { if let dy = _floatShiftY[box.id] { _floatShiftY[box.id] = nil; let r = box.rect; mine = mine.map { $0.id == box.id ? ($0.id, Rect.fromLTWH(r.left, r.top - dy, r.width, r.height)) : $0 } } }
                if !mine.isEmpty {
                    if y > 0.01, mine.contains(where: { y + $0.rect.bottom - top > contentH + 0.5 }) { newPage() }
                    var placed: [(top: Double, bottom: Double, left: Double, right: Double)] = []
                    for box in mine {
                        var r = (top: y + box.rect.top - top, bottom: y + box.rect.bottom - top, left: box.rect.left, right: box.rect.right)
                        let before = _floatShift[box.id] ?? 0
                        r.left -= before; r.right -= before
                        var shift = 0.0
                        for b in bands + placed where b.top < r.bottom - 0.5 && b.bottom > r.top + 0.5
                            && b.left < r.right + shift - 0.5 && b.right > r.left + shift + 0.5 && r.left + shift < b.right {
                            shift = max(shift, b.right - r.left)
                        }
                        _floatShift[box.id] = shift > 0.5 ? shift : nil
                        r.left += shift; r.right += shift
                        placed.append(r)
                    }
                    bands += placed
                }
                // Lines of picture-only paragraphs that the pictures now
                // leave no room — this one's and those just above it —
                // go under them, one after another; their pictures stay
                // where their paragraphs first stood. (Word's print of
                // zh-37b6536f: two photos anchored in two empty
                // paragraphs, the second moved clear of the first, and
                // both empty lines under the pair, the text after them.)
                if _anchorsOnly(i, document) {
                    anchorRun.append(i)
                    func lineTop(_ k: Int) -> Double? {
                        if k == i { return y + _spaceBefore[k] }
                        guard let piece = _pages[page].last(where: { $0.paragraph == k && $0.part == .all }) else { return nil }
                        return piece.pageY + (_tops[k] + _spaceBefore[k] - piece.flowTop)
                    }
                    func lineHeight(_ k: Int) -> Double { _heights[k] - _spaceBefore[k] }
                    if let first = anchorRun.firstIndex(where: { k in lineTop(k).map { noRoom(at: $0, height: lineHeight(k), []) != nil } ?? false }),
                       var at = lineTop(anchorRun[first]) {
                        var steps = 0
                        while let below = noRoom(at: at, height: lineHeight(anchorRun[first]), []), steps < 20 { at = below; steps += 1 }
                        for k in anchorRun[first...] {
                            guard let old = lineTop(k) else { continue }
                            let delta = at - old
                            at += lineHeight(k)
                            guard delta > 0.01 else { continue }
                            for image in document.paragraphs[k].inlineImages.values { _floatShiftY[image.id] = -delta }
                            if let image = document.paragraphs[k].image { _floatShiftY[image.id] = -delta }
                            if k == i {
                                y += delta
                            } else {
                                for n in _pages[page].indices where _pages[page][n].paragraph == k {
                                    let moved = _pages[page][n]
                                    _pages[page][n] = PagePiece(paragraph: moved.paragraph, flowTop: moved.flowTop, flowBottom: moved.flowBottom,
                                                                page: moved.page, pageY: moved.pageY + delta)
                                    if let m = _allPieces.lastIndex(of: moved) { _allPieces[m] = _pages[page][n] }
                                }
                            }
                        }
                    }
                } else if !document.paragraphs[i].text.isEmpty {
                    anchorRun.removeAll()
                }
            }
            var cursor = resumeCursor ?? top
            resumeCursor = nil
            var cuts: [Double]? = nil   // lazily computed line bottoms
            // A paragraph that heads a page leaves its space before
            // behind, as Word sets it (prints of 2026-10-13, modes 14 and
            // 15): where the page before filled up, and after a break
            // character — an empty paragraph's space as well, though its
            // line stays. The space counts toward whether the paragraph
            // fits the page it would not head: a line with room for
            // itself and not for its space goes over, and stands there
            // without it. Kept: the document's first paragraph's, a new
            // section's, that of a paragraph which itself begins with
            // the break character (one that ends the paragraph above
            // leaves it behind), and — before the 2013 layout only —
            // that of a paragraph with `w:pageBreakBefore`. And only
            // the page's first paragraph leaves it: one under
            // paragraphs of no height — hidden ones, after a section's
            // break — keeps its space (zh-90e0cea8's appendix heading).
            let lead = i < _floatPush.count ? max(0, _spaceBefore[i] - _floatPush[i]) : 0
            var leavesLead = false
            if theme.wordRules, lead > 0.01, cursor <= top + 0.01 {
                let st = document.paragraphs[i].style
                let newSection = i > 0 && document.paragraphs[i - 1].style.sectionXML != nil
                let ownBreak = _pageBreak[i] && !st.pageBreakInline && !st.breakEndsPrevious
                leavesLead = !newSection && !st.pageBreakInline && !(ownBreak && (document.compatibilityMode ?? 12) < 15)
            }
            while cursor < bottom - 0.01 {
                if leavesLead, pageFresh, y < 0.01, page > 0, cursor <= top + 0.01 { cursor = min(bottom, top + lead) }
                let available = contentH - y
                let rest = bottom - cursor
                // (The last line may reach past the foot by its grid's
                // overhang.)
                let overhang = theme.wordRules && i < _overhang.count ? _overhang[i] : 0
                if rest <= available + 0.01 + overhang {
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: bottom,
                                                  page: page, pageY: y))
                    y += rest
                    cursor = bottom
                    break
                }
                if cuts == nil {
                    let g = geometry(i)
                    cuts = Self._lineBottoms(g.painter).map { g.textTop + $0 }
                    if Self.debugPagination {
                        let m = g.painter.computeLineMetrics()
                        let desc = "para \(i) top \(g.top) textTop \(g.textTop) bottom \(g.bottom) painterH \(g.painter.height) lines \(m.count) heights \(m.map { $0.height }) baselines \(m.map { $0.baseline }) asc/desc \(m.first.map { "\($0.ascent)/\($0.descent)" } ?? "-") cursor \(cursor) y \(y) available \(available)\n"
                        FileHandle.standardError.write(Data(desc.utf8))
                    }
                }
                // The lowest cut that still fits.
                var cut: Double? = nil
                for c in cuts! where c > cursor + 0.01 && c - cursor <= available + 0.01 + overhang { cut = c }
                // Word's rules for where a paragraph may part: not at all
                // (`w:keepLines`), or — its widow and orphan control,
                // which is on unless the paragraph says otherwise — with
                // two lines at least on each side.
                if theme.wordRules, let chosen = cut, y > 0.01 || cursor > top + 0.01 {
                    let st = document.paragraphs[i].style
                    let all = cuts!
                    let first = all.firstIndex(where: { $0 > cursor + 0.01 }) ?? 0
                    let last = all.lastIndex(where: { $0 <= chosen + 0.01 }) ?? first
                    var keep = last - first + 1
                    if st.keepLines, bottom - top <= contentH + 0.01 {
                        keep = 0
                    } else if st.widowControl {
                        if all.count - 1 - last == 1 { keep -= 1 }
                        if cursor <= top + 0.01, keep < 2 { keep = 0 }
                    }
                    if keep <= 0 {
                        // (Only where a new page gives it more room.)
                        if y > 0.01 { cut = nil }
                    } else {
                        cut = all[first + keep - 1]
                    }
                }
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
        // Each page's top on the canvas, under the pages before it.
        let physicalPages = max(1, (_pages.count + _columns - 1) / _columns)
        while _pageSection.count < physicalPages { _pageSection.append(_pageSection.last ?? max(0, _sectionSetups.count - 1)) }
        if _pageSection.count > physicalPages { _pageSection.removeSubrange(physicalPages...) }
        while _pageInsetTop.count < physicalPages { _pageInsetTop.append(_px(pageSetup(forPage: _pageInsetTop.count).marginTop)) }
        if _pageInsetTop.count > physicalPages { _pageInsetTop.removeSubrange(physicalPages...) }
        _pageTops = []
        var pageTop = 0.0
        for k in 0 ..< physicalPages {
            _pageTops.append(pageTop)
            pageTop += _pxPageH(k) + _pxGap
        }
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
    /// `STARLING_RICHTEXT_FIT=<text>`: the East Asian line fitting of
    /// every paragraph that contains the text, stretch by stretch, on
    /// standard error (points) — where a line of ours and of Word's end
    /// a character apart, this says which rule let it on.
    static let debugFit = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_FIT"]

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
                let piece = pieces.first { $0.part != .rules && y < $0.flowBottom - 0.01 } ?? pieces.last
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
            let map = _map(i)
            let bottoms = Self._lineBottoms(g.painter)
            let first = y
            var k = 0
            for line in lines {
                let r = g.painter.getLineBoundary(TextPosition(offset: map.painter(start)))
                let end = max(start, min(map.paragraph(r.end), para.length))
                let a = utf16.index(utf16.startIndex, offsetBy: start)
                let b = utf16.index(utf16.startIndex, offsetBy: end)
                let text = (String(utf16[a ..< b]) ?? "").trimmingWhitespace()
                out += "p\(page(atFlow: y)) ¶\(i) \(_tenth(line.height)) |\(text)|\n"
                y = first + (k < bottoms.count ? bottoms[k] : 0)
                k += 1
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
        let top = p >= 0 && p < _pageTops.count ? _pageTops[p] : Double(p) * (_pxPageH(p) + _pxGap)
        return Rect.fromLTWH(0, top, _pxPageW(p), _pxPageH(p))
    }

    /// The canvas: the page column when paged, else the flow itself.
    public var canvasSize: Size {
        guard isPaged else { return Size(width, totalHeight) }
        let last = pageRect(pageCount - 1)
        return Size((0 ..< pageCount).reduce(0.0) { max($0, _pxPageW($1)) }, last.bottom)
    }

    /// Page index under canvas y (clamped).
    public func page(atCanvasY y: Double) -> Int {
        guard isPaged else { return 0 }
        var p = 0
        while p + 1 < pageCount, p + 1 < _pageTops.count, y >= _pageTops[p + 1] - _pxGap / 2 { p += 1 }
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
        for piece in pieces where piece.part != .rules {
            let lo = max(r.top, piece.flowTop)
            let hi = min(r.bottom, piece.flowBottom)
            let inside = r.height <= 0 ? (r.top >= piece.flowTop && r.top < piece.flowBottom + 0.01) : hi > lo
            if !inside { continue }
            let page = piece.page / _columns
            let dy = pageRect(page).top + _pxMarginTop(page) + piece.pageY - piece.flowTop
            let dx = _pxMarginLeft(page) + Double(piece.page % _columns) * _pxColumnStride(page)
            out.append(Rect.fromLTRB(r.left + dx, lo + dy, r.right + dx, max(hi, lo) + dy))
        }
        if out.isEmpty, let piece = pieces.last ?? _pages.last?.last {
            // Past the last cut (a caret in trailing space-after): pin to the
            // piece's page.
            let page = piece.page / _columns
            let dy = pageRect(page).top + _pxMarginTop(page) + piece.pageY - piece.flowTop
            let dx = _pxMarginLeft(page) + Double(piece.page % _columns) * _pxColumnStride(page)
            out.append(Rect.fromLTRB(r.left + dx, r.top + dy, r.right + dx, r.bottom + dy))
        }
        return out
    }

    /// Canvas point → flow point. Points in a page's margins or in the gap
    /// snap to the nearest content on that page.
    public func flowPoint(_ p: Offset) -> Offset {
        guard isPaged else { return p }
        let page = self.page(atCanvasY: p.dy)
        let localY = p.dy - pageRect(page).top - _pxMarginTop(page)
        // The column under x, then the point relative to it.
        let column = max(0, min(_columns - 1, Int(floor((p.dx - _pxMarginLeft(page)) / max(1, _pxColumnStride(page))))))
        let x = p.dx - _pxMarginLeft(page) - Double(column) * _pxColumnStride(page)
        let slot = page * _columns + column
        let pieces = _pages.indices.contains(slot) ? _pages[slot] : []
        guard let first = pieces.first, let last = pieces.last else {
            return Offset(x, totalHeight)
        }
        if localY <= first.pageY { return Offset(x, first.flowTop + max(0, localY - first.pageY)) }
        for piece in pieces where piece.part != .rules && localY < piece.pageY + piece.height {
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

    /// Paragraph `i`'s space before and after, in pixels, without its
    /// borders: none against a neighbour of the same style under
    /// contextual spacing, Word's 14pt where it is automatic.
    private func _spacing(_ i: Int, _ document: RichDocument) -> (before: Double, after: Double) {
        let p = document.paragraphs[i]
        let style = p.style
        // Word's auto spacing: 14pt, none between items of a list.
        let autoGap = style.list == nil ? 14.0 : 0.0
        // Contextual spacing: no space against a neighbour of the same style.
        func sameStyle(_ j: Int) -> Bool {
            guard j >= 0, j < document.paragraphs.count else { return false }
            let o = document.paragraphs[j].style
            return o.named == style.named && o.heading == style.heading && o.list == style.list
        }
        // A list made here, in a document that was not read from a file,
        // is saved in Word's List Paragraph — whose spacing is contextual.
        // It is laid out so from the start: it used to sit loose until
        // saved, and come back tight.
        let contextual = style.contextualSpacing
            || theme.wordRules && style.list != nil && style.named == nil && !document.readFromFile
        let skipBefore = contextual && sameStyle(i - 1) || theme.omitsLeadingSpace && i == 0
        let skipAfter = contextual && sameStyle(i + 1)
        // Automatic spacing is the web's, unless the document says its
        // own numbers stand: see `RichDocument.htmlAutoSpacing`.
        let web = !theme.wordRules || document.htmlAutoSpacing
        // Spacing counted in lines (`w:beforeLines`, `w:afterLines`:
        // hundredths of the grid's line pitch, or of 12 points where
        // lines keep to no grid) outranks the measure beside it.
        func inLines(_ s: RichParagraphStyle, _ key: String) -> Double? {
            guard theme.wordRules, let v = Double(s.eastAsian[key] ?? ""), v != 0 else { return nil }
            return v / 100 * (_grid(i, document).pitch ?? 12)
        }
        func spaceAfter(_ s: RichParagraphStyle) -> Double {
            web && s.spaceAfterAuto ? (s.list == nil ? 14.0 : 0.0) : inLines(s, "w:afterLines") ?? s.spaceAfter
        }
        var spaceBefore = web && style.spaceBeforeAuto ? autoGap : inLines(style, "w:beforeLines") ?? style.spaceBefore
        if theme.wordRules, web {
            if i == 0 {
                if style.spaceBeforeAuto { spaceBefore = 0 }
            } else if i - 1 < document.paragraphs.count {
                // (In a cell, where the layout shares no space between
                // two paragraphs: `_sharedSpace` is the body's.)
                let above = document.paragraphs[i - 1]
                if p.cell != nil, above.cell == p.cell, style.spaceBeforeAuto || above.style.spaceAfterAuto {
                    spaceBefore = max(0, spaceBefore - spaceAfter(above.style))
                }
            }
        }
        // The space two paragraphs share is the upper one's to give up:
        // where contextual spacing takes its space after away, what of
        // this one's space before lay over it goes with it (a title with
        // contextual spacing, then an empty paragraph with 14pt before:
        // nothing between them in Word's print, 2026-10-13).
        if theme.wordRules, theme.collapsesParagraphSpacing, !document.addsParagraphSpacing, i > 0, p.cell == nil,
           i - 1 < document.paragraphs.count, document.paragraphs[i - 1].cell == nil {
            let a = document.paragraphs[i - 1].style
            if a.contextualSpacing, a.named == style.named, a.heading == style.heading, a.list == style.list {
                spaceBefore = max(0, spaceBefore - spaceAfter(a))
            }
        }
        return (skipBefore ? 0 : _px(spaceBefore), skipAfter ? 0 : _px(spaceAfter(style)))
    }

    /// The sheet's Normal look, for `RichTextTheme.textStyle`.
    private func _normalChar(_ document: RichDocument) -> CharStyle? { document.styles[RichNamedStyle.normalId]?.char }

    /// How much of body paragraph `i`'s space before lies over the space
    /// after the body paragraph above it: the smaller of the two, so the
    /// larger alone separates them. None across a border, a page break
    /// or a table's edge.
    private func _sharedSpace(_ i: Int, _ document: RichDocument) -> Double {
        guard theme.collapsesParagraphSpacing, !document.addsParagraphSpacing,
              i > 0, i < document.paragraphs.count, _cells[i] == nil, _cells[i - 1] == nil else { return 0 }
        let above = document.paragraphs[i - 1].style, style = document.paragraphs[i].style
        guard above.borders?.bottom == nil, style.borders?.top == nil, !style.pageBreakBefore else { return 0 }
        return min(_spacing(i - 1, document).after, _spacing(i, document).before).rounded(.down)
    }

    /// Where a list paragraph's text and number stand, in points, when
    /// the file says: the text at the level's left indent (the
    /// paragraph's own above it) and the number that far back from it —
    /// 65099's "1.1.1" heading is a third level whose text is at 36pt,
    /// not at three levels' worth. nil for a list of the editor's own,
    /// which takes `theme.listIndent` a level.
    private func _listIndents(_ p: RichParagraph, _ document: RichDocument) -> (left: Double, hanging: Double)? {
        guard p.style.list != nil else { return nil }
        let level = p.style.listId.flatMap { document.listFormats[$0]?[p.style.listLevel] }
        guard let left = p.style.listIndentLeft ?? level?.indentLeft else { return nil }
        return (left, p.style.listFirstLine.map { -$0 } ?? level?.hanging ?? 0)
    }

    private func _layoutParagraph(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        let style = p.style
        let wordList = _wordList(p, document)
        let sides = _sideIndents(p, document)
        let ownLeft = wordList.map { _px($0.left) } ?? _px(sides.left)
        var left = wordList != nil ? ownLeft
            : ownLeft + (style.list != nil ? _px(_listIndents(p, document)?.left ?? theme.listIndent * Double(style.listLevel + 1)) : 0)
        let right = _px(sides.right)
        var width = _flowWidth(i)
        // A floating frame: as wide as it says, from where it says.
        var frameLeft: Double? = nil
        if floatsFrames, theme.wordRules, p.cell == nil, let frame = style.frame {
            let marginLeft = _px(frameMargins.left), marginRight = _px(frameMargins.right)
            // The band the frame is placed in, from the text's left edge.
            let band: (left: Double, width: Double) = frame.horizontalAnchor == "page"
                ? (-marginLeft, width + marginLeft + marginRight) : (0, width)
            let own = frame.width.map(_px) ?? band.width
            switch frame.horizontalAlign {
            case "center": frameLeft = band.left + (band.width - own) / 2
            case "right", "outside": frameLeft = band.left + band.width - own
            case "left", "inside": frameLeft = band.left
            default: frameLeft = band.left + _px(frame.x)
            }
            width = own
            left += frameLeft!
        }
        var textWidth = max(1, width - left - right + (frameLeft ?? 0))
        if let c = p.cell {
            let widths = _columnWidths[c.table] ?? []
            let colWidth = c.column < widths.count
                ? widths[c.column ..< min(widths.count, c.column + c.span)].reduce(0, +) : width
            let colLeft = _tableLeft(c.table, document) + widths.prefix(c.column).reduce(0, +)
            let ins = _cellInsets(c.table, document)
            var pad = c.padding.map { EdgeInsets(left: _px($0.left), top: _px($0.top), right: _px($0.right), bottom: _px($0.bottom)) }
                ?? EdgeInsets(left: ins.left, top: ins.top, right: ins.right, bottom: ins.bottom)
            // A ruled row is its rule taller, as Word sets it: the line
            // above each row takes its width from the row, and the last
            // row has the table's bottom line too.
            // (The cell's own side over the table's: a table ruled
            // around its rim alone whose cells each rule their four
            // sides has a line above every row. And a double line is
            // three of its width — two lines and the gap: rows 17.5pt
            // apart at half a point, 20.5 at one and a half, where a
            // single line's are 16.5 and 17.5.)
            // (The line between two rows is the upper row's bottom
            // one as much as the lower row's top one: a form whose
            // cells rule their bottoms and say none above is ruled
            // between every two rows, 31pt apart for rows 30 high.)
            var rules = 0.0
            var ruleBelow = 0.0
            // (A table with no style of its own — one made in the editor
            // — is ruled like one whose file says nothing more than
            // that it is ruled.)
            if theme.wordRules {
                let ts = document.tableStyles[c.table] ?? TableStyle()
                let rows = _tableRows[c.table] ?? 0
                func rule(_ d: CellRef, _ side: String) -> Double {
                    let said = Self._cellSide(d.bordersXML, side)
                    let end = d.row + d.rowSpan - 1
                    let tables = side == "top" ? (d.row == 0 ? ts.edges?.top : ts.edges?.insideH) : (end >= rows ? ts.edges?.bottom : ts.edges?.insideH)
                    guard (side == "top" ? d.edges?.top : d.edges?.bottom) ?? tables ?? ts.borders else { return 0 }
                    let tableSide = (side == "top" ? d.row > 0 : end < rows) ? "insideH" : side
                    let style = said?.style ?? ts.edgeStyles[tableSide] ?? ts.borderStyle
                    let width = said?.width ?? d.borderWidth ?? ts.edgeWidths[tableSide] ?? ts.borderWidth ?? 0.5
                    return _px(width * (style == "double" ? 3 : 1))
                }
                var below = 0.0
                var top = rule(c, "top")
                if c.row > 0 {
                    var k = i - 1
                    while k >= 0, let d = document.paragraphs[k].cell, d.table == c.table, d.row + d.rowSpan - 1 >= c.row - 1 {
                        if d.row + d.rowSpan - 1 == c.row - 1 { top = max(top, rule(d, "bottom")) }
                        k -= 1
                    }
                }
                if top > 0 { pad = EdgeInsets(left: pad.left, top: pad.top + top, right: pad.right, bottom: pad.bottom) }
                rules = top
                if c.row + c.rowSpan - 1 >= rows {
                    let bottom = rule(c, "bottom")
                    if bottom > 0 { pad = EdgeInsets(left: pad.left, top: pad.top, right: pad.right, bottom: pad.bottom + bottom) }
                    rules += bottom
                    below = bottom
                }
                ruleBelow = below
            }
            _cells[i] = _CellGeo(table: c.table, row: c.row, column: c.column,
                                 colLeft: colLeft, colWidth: colWidth, span: c.span, rowSpan: c.rowSpan, edges: c.edges,
                                 verticalAlign: c.verticalAlign, direction: c.textDirection, pad: pad, rules: rules, ruleBelow: ruleBelow, borders: c.borders)
            left = colLeft + pad.left + ownLeft
            textWidth = max(1, colWidth - pad.left - pad.right - ownLeft - right)
            if c.textDirection != .horizontal {
                // Turned text runs along the row's height, which the row's
                // other cells decide: laid out provisionally at the rows'
                // own heights, and again at the placed height in
                // `_placeBlocks`.
                let heights = document.tableStyles[c.table]?.rowHeights ?? [:]
                let own = (c.row ..< c.row + c.rowSpan).reduce(0.0) { $0 + (heights[$1] ?? 0) }
                textWidth = own > 0 ? max(1, _px(own) - pad.top - pad.bottom - ownLeft - right) : 100_000
            }
        } else {
            _cells[i] = nil
        }
        // The box before the text: the first line's indent, or — for a
        // list as Word sets it — from the number at the first line's
        // offset to where the text starts: at the number's end, a space
        // after it, or the next tab stop (the text's own left, when the
        // number fits in the hanging indent).
        var lead = _px(firstLineIndent(p, at: i, document))
        if let wl = wordList, !p.text.isEmpty, let label = listLabel(i, document) {
            let marker = _marker(i, p, document, label: label, strut: nil)
            var end = _px(wl.first) + marker.width
            switch wl.format?.suffix {
            case "nothing": break
            case "space":
                let spaced = _marker(i, p, document, label: label + "\u{A0}", strut: nil)
                end = _px(wl.first) + spaced.width
                spaced.dispose()
            default:
                if wl.first < 0, end <= 0.01 {
                    end = 0
                } else {
                    // (No default stops at all — `w:defaultTabStop` 0, as
                    // some files say — and the text follows the number.)
                    let tab = _px(document.defaultTabStop ?? 36)
                    let from = ownLeft + end
                    if tab > 0.01 { end = ((from / tab + 0.001).rounded(.down) + 1) * tab - ownLeft }
                }
            }
            marker.dispose()
            lead = end == 0 ? 0.01 : end
            // (Centred or set right, the number goes with its line —
            // "第一章 总则" is centred whole — so the box before the
            // text is all of the number and its gap.)
            if style.alignment == .center || style.alignment == .right { lead = max(0.01, end - _px(wl.first)) }
        }
        _leadWidth[i] = lead
        // Tabs, as Word sets them: each takes the text to the next stop —
        // the paragraph's own, the hanging indent, then the document's
        // default distance apart — and a centred, right or decimal stop
        // sets what follows about it. The engine gives a tab no width of
        // its own, so each is widened by what its stop needs.
        var tabs: [Int: Double] = [:]
        _leaders[i] = []
        if theme.wordRules, !style.rightToLeft, p.text.utf16.contains(0x09) {
            let (probeSpan, probeInline, probeInserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead)
            let probe = TextPainter(text: probeSpan, textAlign: .left, textDirection: .ltr)
            if !probeInline.isEmpty { probe.setPlaceholderDimensions(probeInline.map { $0.dimensions }) }
            probe.layout(minWidth: 0, maxWidth: 10_000_000)
            let probeMap = _OffsetMap(lead: lead != 0 ? 1 : 0, inserts: probeInserts)
            // (Each character's left edge, by its box: the caret after a
            // tab is not at the tab's far side.)
            func edge(_ offset: Int) -> Double {
                if offset >= units.count {
                    let last = probeMap.painter(units.count - 1)
                    return probe.getBoxesForSelection(TextSelection(baseOffset: last, extentOffset: last + 1)).last?.right ?? 0
                }
                let at = probeMap.painter(offset)
                return probe.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 1)).first?.left
                    ?? probe.getOffsetForCaret(TextPosition(offset: at), Rect.zero).dx
            }
            let units = Array(p.text.utf16)
            let stops = style.tabStops.sorted { $0.position < $1.position }
            let step = _px(document.defaultTabStop ?? 36)
            var shift = 0.0
            var lastTab = 0
            for (t, u) in units.enumerated() where u == 0x09 {
                // (A line break since the last tab: the line starts over.)
                if units[lastTab ..< t].contains(where: { $0 == 0x0A || $0 == 0x2028 }) { shift = 0 }
                lastTab = t
                let at = edge(t), after = edge(t + 1)
                let x = ownLeft + at + shift          // from the column's left
                let own = after - at
                var stop: (x: Double, alignment: TabStop.Alignment, leader: String?)? = nil
                if let s = stops.first(where: { _px($0.position) > x + 0.5 }) { stop = (_px(s.position), s.alignment, s.leader) }
                if lead < 0, ownLeft > x + 0.5, stop.map({ ownLeft < $0.x }) ?? true { stop = (ownLeft, .left, nil) }
                if stop == nil, step > 0 { stop = (((x + 0.5) / step).rounded(.down) * step + step, .left, nil) }
                guard let stop else { continue }
                // What follows, up to the next tab or the line's end.
                var end = t + 1
                while end < units.count, units[end] != 0x09, units[end] != 0x0A, units[end] != 0x2028 { end += 1 }
                let following = max(0, edge(end) - after)
                var extra = stop.x - x - own
                switch stop.alignment {
                case .left: break
                case .center: extra -= following / 2
                case .right: extra -= following
                case .decimal:
                    if let dot = (t + 1 ..< end).first(where: { units[$0] == 0x2E }) { extra -= edge(dot) - after } else { extra -= following }
                }
                extra = max(0, extra)
                tabs[t] = extra
                shift += extra
                if let fill = stop.leader, fill != "none" {
                    let ch = ["dot": ".", "hyphen": "-", "underscore": "_", "middleDot": "\u{B7}", "heavy": "_"][fill] ?? "."
                    _leaders[i].append((t, ch))
                }
            }
            probe.dispose()
        }
        let (span, inline, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: tabs)
        _inserts[i] = inserts
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
            // (A fiftieth of a point over: a line that is exactly the
            // column's width — ten ideographs in ten ems — must fit, and
            // the sum of its advances may come out a hair above.)
            let slack = theme.wordRules ? _px(0.005) : 0
            painter.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
            // One line of stretches of several heights is as tall as
            // its tallest and no more (a 14pt dash either side of a 9pt
            // page number): each face splits its height its own way,
            // and the engine would stack the deepest under the highest.
            if painter.strutStyle == nil, theme.wordRules, !inline.contains(where: { $0.image != nil }),
               painter.computeLineMetrics().count == 1, let strut = _strut(span, tallest: true) {
                let held = TextPainter(text: span, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr, strutStyle: strut)
                if !inline.isEmpty { held.setPlaceholderDimensions(inline.map { $0.dimensions }) }
                held.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                if held.computeLineMetrics().count == 1 { return held }
            }
            return painter
        }
        for item in inline { if let image = item.image { _ensureDecoded(image) } }
        _inline[i] = inline.compactMap(\.image)
        _floats[i] = p.image?.float
        _floatImages[i] = p.image?.float != nil ? p.image : nil
        var painter = laidOut(span)
        // East Asian line ends, as Word sets them: a closing mark that
        // would start a line hangs past the margin instead, and a line
        // half an em too long for its last character takes it anyway,
        // off one of its punctuation marks. The engine breaks lines by
        // width alone, so the marks are narrowed by what each line
        // needs and the paragraph laid out again.
        // (A line with a tab in it is fitted like any other, its tabs
        // as wide as they came out: a contents line typed with its own
        // dots takes its page number by what its commas give.)
        let fit = _fitEastAsianLines(p, at: i, document, textWidth: textWidth, first: painter, leadWidth: lead, tabs: tabs)
        if !fit.isEmpty {
            painter.dispose()
            painter = laidOut(_span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit).0)
        }
        // The engine's justifying sets every space of a line to the one
        // step it puts between ideographs, and the two spaces after
        // "第一条" are gone. In a justified paragraph the spaces beside
        // East Asian text are therefore set again as no-break spaces —
        // characters like any other, which keep their width — but only
        // those inside a line, and only if every line then breaks
        // where it did: a no-break space at a line's end would count
        // against the line, and a plain one takes no room there.
        if theme.wordRules, document.usesEastAsianLayout, style.alignment == .justify, p.text.utf16.contains(0x20) {
            let starts = _lineStarts(painter, _map(i), count: p.text.utf16.count)
            let hold = starts.count > 1 ? _spacesToHold(p, lineStarts: Set(starts)) : []
            if !hold.isEmpty {
                let (span, _, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit.isEmpty ? tabs : fit, held: hold)
                let again = laidOut(span)
                if _lineStarts(again, _OffsetMap(lead: _lead(i), inserts: inserts), count: p.text.utf16.count) == starts {
                    painter.dispose()
                    painter = again
                    _inserts[i] = inserts
                } else {
                    again.dispose()
                }
            }
        }
        // Whole pixels: a page break clips between two lines, and a
        // fractional line box leaves the previous line's descenders peeking
        // into the next page (and its ascenders shaved off the previous).
        // A border's line and its gap lie between the spacing and the text.
        let bTop = style.borders?.top.map { _px($0.space + $0.width) } ?? 0
        let bBottom = style.borders?.bottom.map { _px($0.space + $0.width) } ?? 0
        let spacing = _spacing(i, document)
        let before = (spacing.before + bTop).rounded()
        let after = spacing.after + bBottom
        // Where the engine put the baseline (a strut's even leading) is
        // not where Word has it: the text is drawn from as much lower.
        _inkShift[i] = 0
        if theme.wordRules, p.image == nil, !p.text.isEmpty, painter.strutStyle != nil,
           let line = painter.computeLineMetrics().first {
            let named = _named(p, document)
            let pitch = style.eastAsian["w:snapToGrid"] == "0" ? nil : _grid(i, document).pitch
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
        if i < _overhang.count {
            _overhang[i] = 0
            if theme.wordRules, p.image == nil, p.cell == nil, style.eastAsian["w:snapToGrid"] != "0", let pitch = _grid(i, document).pitch {
                let named = _named(p, document)
                // (An empty paragraph's line is its mark's.)
                let look = p.text.isEmpty ? (style.mark ?? p.runs.first?.style ?? CharStyle()) : p.runs[0].style
                let ea = p.text.isEmpty || p.text.contains { Self.isEastAsian($0, hinted: false) }
                _overhang[i] = _px(theme.gridOverhang(for: look, in: style, named: named, eastAsian: ea, gridPitch: pitch))
            }
        }
        _painters[i] = painter
        _textLeft[i] = left
        _textWidth[i] = textWidth
        // An object that floats over the paragraph's head with text
        // wrapping round it, and leaves the first line no room on either
        // side of it — the line's indent is taken off each — sets the
        // text down under it, as Word does: a box across the column
        // with the title of the page in it, anchored in the paragraph
        // of the line below. (Lines set beside a narrower one are not
        // built: the text then runs over it, as before.)
        var push = 0.0
        if theme.wordRules, p.cell == nil {
            let column = _flowWidth(i)
            let firstLine = max(0, lead) + (left - (frameLeft ?? 0))
            // (Together, too: two photos side by side that fill the
            // column between them set an empty anchor's line under both,
            // where either alone leaves room — zh-37b6536f's first row.)
            var spans: [(Double, Double, Double)] = []
            let em0 = _px(p.runs.first?.style.fontSize ?? theme.fontSize)
            for image in p.inlineImages.values {
                guard let float = image.float, float.wraps, float.verticalAlign == nil, ["paragraph", "line"].contains(float.verticalFrom),
                      float.horizontalFrom != "page", float.horizontalAlign == nil else { continue }
                let w = _px(image.width)
                spans.append((_px(float.x) - _px(9), _px(float.x) + w + _px(9), _px(float.y) + _px(image.height)))
            }
            if spans.count > 1 {
                let sorted = spans.sorted { $0.0 < $1.0 }
                var widest = 0.0, edge = firstLine
                for s in sorted { widest = max(widest, s.0 - edge); edge = max(edge, s.1) }
                widest = max(widest, column - max(0, lead) - right - edge)
                if widest < em0 { push = max(push, sorted.map(\.2).max() ?? 0) }
            }
            for image in p.inlineImages.values {
                guard let float = image.float, float.wraps, float.verticalAlign == nil, ["paragraph", "line"].contains(float.verticalFrom),
                      float.horizontalFrom != "page" else { continue }
                let w = min(_px(image.width), column)
                let x: Double
                switch float.horizontalAlign {
                case "center": x = (column - w) / 2
                case "right", "outside": x = column - w
                case "left", "inside": x = 0
                default: x = _px(float.x)
                }
                let gap = _px(9), em = _px(p.runs.first?.style.fontSize ?? theme.fontSize)
                let leftRoom = x - gap - firstLine, rightRoom = column - (x + w) - gap - max(0, lead) - right
                if leftRoom < em, rightRoom < em { push = max(push, _px(float.y) + _px(image.height)) }
            }
        }
        if i < _floatPush.count { _floatPush[i] = push }
        _spaceBefore[i] = before + push
        var bodyHeight = painter.height
        // A paragraph of nothing but floating objects stands as one of a
        // single floating picture does (25pt in zh-37b6536f, where the
        // two photos' 0-high places made a line of 0.8, and the next
        // photo stood 30pt above Word's).
        if theme.wordRules, p.image == nil, !p.inlineImages.isEmpty, !p.text.isEmpty,
           p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC }),
           p.inlineImages.values.allSatisfy({ $0.float.map { !$0.takesRoom } ?? false }) {
            // (As a paragraph of one floating picture is laid out — its
            // character in the objects' run, with no object in it: the
            // height Word gives such a line, 25pt where a line of text
            // is 29.)
            // (The paragraph mark's look: the objects' runs may carry none.)
            var mark = p.style.mark ?? p.runs.first?.style ?? CharStyle()
            mark.inlineImage = nil
            var empty = RichParagraph(text: "\u{FFFC}", runs: [Run(length: 1, style: mark)], style: p.style)
            empty.cell = p.cell
            let (span, held, _) = _span(for: empty, at: nil, document, textWidth: textWidth)
            let probe = TextPainter(text: span, textAlign: .left, textDirection: .ltr,
                                    strutStyle: held.contains(where: { $0.image != nil }) ? nil : _strut(span))
            if !held.isEmpty { probe.setPlaceholderDimensions(held.map { $0.dimensions }) }
            probe.layout(minWidth: 0, maxWidth: max(1, textWidth))
            bodyHeight = max(bodyHeight, probe.height)
            probe.dispose()
        }
        // A tab at the paragraph's end whose stop lies past the right
        // edge of the text goes to a line of its own, as Word sets it —
        // minutes typed with a tab after each full stop are a line
        // longer wherever the sentence filled its line. The engine
        // hangs a tab at a line's end like a space.
        if theme.wordRules, p.image == nil, p.text.utf16.count > 1, p.text.utf16.last == 0x09,
           let lastLine = painter.computeLineMetrics().last {
            let units = Array(p.text.utf16)
            var k = units.count - 1
            while k > 0, units[k] == 0x09 || units[k] == 0x20 { k -= 1 }
            let at = _map(i).painter(k)
            if let box = painter.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 1)).last {
                let x = ownLeft + box.right
                let step = _px(document.defaultTabStop ?? 36)
                let stop = style.tabStops.map { _px($0.position) }.sorted().first(where: { $0 > x + 0.5 })
                    ?? (step > 0 ? ((x + 0.5) / step).rounded(.down) * step + step : x)
                if stop > ownLeft + textWidth + 0.5 { bodyHeight += lastLine.height }
            }
        }
        // (No lines at all: `RichParagraphStyle.lineCollapsed`.)
        if theme.wordRules, style.lineCollapsed, p.image == nil { bodyHeight = 0 }
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
        _heights[i] = (before + push + bodyHeight + after).rounded(.up)
        // An empty paragraph that only ends a section stands for the
        // break and takes no room, as Word sets it.
        if theme.wordRules, p.text.isEmpty, p.image == nil, style.sectionXML != nil, p.cell == nil { _heights[i] = 0 }
        // A floating frame takes no room either: the text that follows
        // starts where it does.
        if frameLeft != nil {
            _heights[i] = 0
            // (And stands as far above or below the text it is anchored
            // to as the frame says: a page number 11.75pt up.)
            if let frame = style.frame, frame.verticalAnchor == "text", frame.verticalAlign == nil { _spaceBefore[i] = before + push + _px(frame.y) }
        }
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
    /// `autoSpaces` is told each character set wider by Word's automatic
    /// space after it (paragraph offset, pixels), for the line fitting.
    private func _span(for p: RichParagraph, at index: Int?, _ document: RichDocument, textWidth: Double, lead: Double = 0, adjust: [Int: Double] = [:],
                       held: Set<Int> = [], autoSpaces: ((Int, Double) -> Void)? = nil)
        -> (TextSpan, [(image: ImageAttachment?, dimensions: PlaceholderDimensions)], [Int]) {
        let named = _named(p, document)
        let pitch = p.style.eastAsian["w:snapToGrid"] == "0" ? nil : _grid(index, document).pitch
        if p.text.isEmpty {
            return (TextSpan(text: " ", style: theme.textStyle(for: p.runs[0].style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)), [], [])
        }
        // Where a zero-width space goes in, and what was before the
        // character at hand (across runs).
        var inserts: [Int] = []
        var before: Character? = nil
        let breaksAtQuotes = theme.wordRules && document.usesEastAsianLayout
        let fullQuotes = theme.wordRules && document.usesEastAsianLayout
        let loose = _looseWordOffsets(p, document, textWidth: textWidth, named: named, pitch: pitch)
        // The spaces Word sets half an em wide (UTF-16 offsets): every
        // run of them but one between two Latin characters — see
        // `RichDocument.balancesSpaceWidth`.
        var wideSpaces: Set<Int> = []
        // The spaces to set as no-break ones (`held`, by the layout: see
        // `_spacesToHold`), with a zero-width space after each run of
        // them for the break a space allows.
        let heldSpaces = held
        var afterHeld = false
        if theme.wordRules, document.balancesSpaceWidth || document.usesEastAsianLayout, p.text.utf16.contains(0x20) {
            var at = 0
            var run: [Int] = []
            var left: Character? = nil
            func close(_ right: Character?) {
                defer { run = [] }
                guard !run.isEmpty else { return }
                func latin(_ c: Character?) -> Bool { c.map { !Self.isEastAsian($0, hinted: false) } ?? false }
                if document.balancesSpaceWidth, !(latin(left) && latin(right)) { wideSpaces.formUnion(run) }
            }
            for ch in p.text {
                if ch == " " { run.append(at) } else { close(ch); left = ch }
                at += ch.utf16.count
            }
            close(nil)
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
        // The size that sets the lines' height, as Word has it: the
        // tallest character that is not a space — a run of 20pt spaces
        // in 18pt text adds nothing — and the paragraph mark's where
        // there are only spaces (prints of 2026-10-13: three 20pt spaces
        // under an 18pt mark are a line of 30.9pt, under a 14pt mark of
        // 23.9, and 18pt spaces under a 20pt mark of 34.2).
        let lineSize: (size: Double, blank: Bool)? = {
            guard theme.wordRules, p.text.utf16.contains(0x20) else { return nil }
            let normal = _normalChar(document)
            func size(_ c: CharStyle?) -> Double { c?.fontSize ?? named?.char.fontSize ?? normal?.fontSize ?? theme.fontSize }
            var best: Double? = nil
            var at = p.text.utf16.startIndex
            for run in p.runs {
                let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.utf16.endIndex) ?? p.text.utf16.endIndex
                if run.style.inlineImage != nil { return nil }
                if p.text.utf16[at ..< end].contains(where: { $0 != 0x20 }) { best = max(best ?? 0, size(run.style)) }
                at = end
            }
            if let best { return (best, false) }
            return (size(p.style.mark), true)
        }()
        func styled(_ text: Substring, _ run: CharStyle, at base: Int = 0, next: Character? = nil) -> [TextSpan] {
            let latinFace = theme.wordRules
                ? theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false) : nil
            let hinted = (run.fontHint ?? named?.char.fontHint) == "eastAsia" || (latinFace?.isEastAsian ?? false)
            let em = (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            let closes = _closesUpMarks(run, named, document)
            // A stretch is of one script, and — where the Latin face
            // stands in at a scale for each kind of character — of one
            // kind: -1 East Asian, else the kind (0 where there is one
            // scale for all).
            let classed = latinFace?.classScales != nil
            var styles: [Int: TextStyle] = [:]
            // (The grid's addition to each character, unless the run opts out.)
            let grid = theme.wordRules && !(run.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false)
                ? _grid(index, document).chars : nil
            // (Where single and double byte widths are balanced, a
            // full-width character takes the run's spacing twice: 16pt
            // text spaced -0.3 is set 15.4 apart.)
            let spacing = (run.letterSpacing ?? 0) * theme.pixelsPerPoint * scale
            let doubles = theme.wordRules && document.balancesSpaceWidth && spacing != 0
            func style(_ kind: Int) -> TextStyle {
                if let s = styles[kind] { return s }
                var s = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: kind < 0, gridPitch: pitch,
                                        characterClass: classed && kind >= 0 ? kind : nil, characterGrid: grid, scriptHidden: true)
                if doubles, kind < 0 { s = s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + spacing) }
                // (Set to the original's widths, the stand-in's own
                // kerning is no part of them: Arial's pair of ones.)
                if kind >= 0, latinFace?.advances != nil { s = s.copyWith(fontFeatures: [FontFeature("kern", 0)]) }
                // (A run of spaces alone takes the line's height, not its own.)
                if let lineSize, !text.isEmpty, text.allSatisfy({ $0 == " " }), let px = s.fontSize, px > 0.5, s.height != nil {
                    let own = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    if own > lineSize.size + 0.01 || (lineSize.blank && own < lineSize.size - 0.01) {
                        var sized = run
                        sized.fontSize = lineSize.size
                        let r = theme.textStyle(for: sized, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                                eastAsian: kind < 0, gridPitch: pitch, characterClass: classed && kind >= 0 ? kind : nil,
                                                characterGrid: grid, scriptHidden: true)
                        if let rs = r.fontSize, let rh = r.height { s = s.copyWith(height: rs * rh / px) }
                    }
                }
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
                // A stretch of Latin characters with no space in it is
                // one word to Word, which parts it only after a hyphen:
                // an address, a date with strokes, "100%200%", "(a)(b)"
                // go to the next line whole. The engine would break
                // after the stroke, the question mark, the percent
                // sign and the bracket; a word joiner holds them.
                // (One too long for any line Word parts wherever the
                // line ends, starting where it stands: a zero-width
                // space before each of its characters.)
                if loose.contains(offset) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: style(current ?? kind)))
                    inserts.append(offset)
                } else if theme.wordRules, let b = before, Self._joinsLatin(b, ch) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: style(current ?? kind)))
                    inserts.append(offset)
                }
                // In East Asian text a curly quote is a full-width mark,
                // an em with the blank half outside it, as 宋体 and
                // every face Word sets such text in draw it; the faces
                // that stand in here draw the Latin one. The closing
                // one's blank is spacing after it.
                let quote = ea && fullQuotes && (ch == "\u{201C}" || ch == "\u{2018}" || ch == "\u{201D}" || ch == "\u{2019}")
                let blank = quote ? max(0, em - _glyphWidth(style(kind), ch)) : 0
                var led = false
                // A zero-width space where Word may break the line and
                // the engine would not: after spaces set as no-break
                // ones (`heldSpaces`), and before an opening curly
                // quote or after a closing one, as at any bracket —
                // the engine breaks on neither side of a quote.
                if afterHeld, ch != " " {
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: style(current ?? kind)))
                    inserts.append(offset)
                    afterHeld = false
                } else if breaksAtQuotes, let b = before, Self._breaksBetween(b, ch) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: style(current ?? kind)))
                    inserts.append(offset)
                }
                // (The opening quote's blank: a word joiner as wide as
                // the blank, which no line parts from the quote — at a
                // line's start the blank leads the mark, as in Word,
                // and none is left at the end of the line before. What
                // the line fitting takes off the quote comes off it.)
                if quote, blank > 0, ch == "\u{201C}" || ch == "\u{2018}" {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: style(kind).copyWith(letterSpacing: max(0, blank + (adjust[offset] ?? 0)))))
                    inserts.append(offset)
                    led = true
                }
                before = ch
                if let c = current, c != kind { flush(i) }
                current = kind
                // What this character is set wider or narrower by: Word's
                // automatic space between an ideograph and the Latin
                // letter or digit beside it (`w:autoSpaceDE` and
                // `w:autoSpaceDN`, on unless the paragraph says
                // otherwise); the half em it takes off the first of two
                // punctuation marks that stand together; and what the
                // line fitting asked of this one.
                var extra = led ? 0 : adjust[offset] ?? 0
                if quote, !led { extra += blank }
                // (Balanced, a half-width character takes half of the
                // grid's addition, whatever follows it: on a grid of
                // 1.008pt Word sets a digit 0.504 wider than its face
                // does, before another and before an ideograph, and a
                // bracket and a letter the same. Lab `cg3`, 2026-10-13,
                // glyph by glyph. It was the full addition before an
                // ideograph here, which the automatic space hid — see
                // the gap below — and a paragraph with that space off
                // showed: zh-457a8d62 lost a character a line.)
                if !ea, document.balancesSpaceWidth, let g = grid, g != 0, ch != " ", let following, following != " " {
                    extra -= _px(g) / 2
                }
                if wideSpaces.contains(offset) {
                    // (Half an em and the run's own spacing once more,
                    // as Word measures it: 8.31pt at 16pt spaced 0.15.
                    // A face Word emboldens widens each character by its
                    // spread, and the space, a half-width character,
                    // by half of it — not by the whole, and not by the
                    // Latin stand-in's once more: 5.72pt at 12pt in
                    // 楷体_GB2312 bold spaced -0.2, where 6.02 wrapped a
                    // line of zh-232090e0 that Word keeps; lab `sp`,
                    // 2026-10-14.)
                    let s = style(kind)
                    let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    let eaFace = theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily
                                                     ?? run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, true)
                    let own = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    let spread = bold ? own * theme.pixelsPerPoint * scale : 0
                    // (The stand-in's spread is in the style's spacing,
                    // which the engine applies and the line above adds
                    // once more: off twice.)
                    extra += em / 2 - _spaceWidth(s) + (s.letterSpacing ?? 0)
                        - 2 * spread * (latinFace?.boldSpread ?? 0) + spread * (eaFace?.boldSpread ?? 0) / 2
                } else if !ea, let face = latinFace, face.advances != nil, ch.unicodeScalars.count == 1,
                          let u = ch.unicodeScalars.first?.value, u >= 0x20, u <= 0x7E {
                    // The width the original face gives this character
                    // (`RichResolvedFace.advances`), at the size the
                    // style sets it less the stand-in's scales.
                    let s = style(kind)
                    let k = Int(u) - 0x20
                    if let table = s.fontWeight == .bold ? face.boldAdvances : face.advances, k < table.count, let px = s.fontSize, px > 0.5 {
                        let classScale = classed ? face.classScales.flatMap { kind < $0.count ? $0[kind] : nil } ?? 1 : 1
                        extra += table[k] * px / (face.sizeScale * classScale) - _glyphWidth(s, ch)
                    }
                } else if !ea, let face = latinFace, face.otherAdvances != nil, ch.unicodeScalars.count == 1, let u = ch.unicodeScalars.first?.value {
                    // … and the width it gives one the stand-in lacks.
                    let s = style(kind)
                    if let w = (s.fontWeight == .bold ? face.boldOtherAdvances : face.otherAdvances)?[u], let px = s.fontSize, px > 0.5 {
                        let classScale = classed ? face.classScales.flatMap { kind < $0.count ? $0[kind] : nil } ?? 1 : 1
                        extra += w * px / (face.sizeScale * classScale) - _glyphWidth(s, ch)
                    }
                }
                if let following {
                    if theme.wordRules, document.usesEastAsianLayout, Self._autoSpaced(ch, following, p.style) {
                        let latin = run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily
                        // (Of the grid's character, where there is a grid
                        // of them, and of the run's spacing with it; a
                        // flat quarter of the two where the widths are
                        // balanced — measured 4.0pt at 16pt, and 3.6 in
                        // Times without.)
                        // (… and of the grid's: 4.25pt either side of a
                        // digit at 16pt on that grid of 1.008.)
                        let gap = document.balancesSpaceWidth
                            ? (em + _px(grid ?? 0) + 2 * spacing) / 4
                            : ((0.5 + (theme.averageCharWidth?(latin) ?? 0.5)) * (em + _px(grid ?? 0)) + spacing) / 4
                        extra += gap
                        autoSpaces?(offset, gap)
                    } else if ea, closes, Self.closesUp(ch, following) {
                        extra -= em / 2
                    }
                }
                if heldSpaces.contains(offset) {
                    flush(i)
                    let s = style(kind)
                    spans.append(TextSpan(text: "\u{00A0}", style: extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s))
                    start = after
                    afterHeld = true
                } else if extra != 0 {
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
        if lead == 0, p.runs.count == 1, p.runs[0].style.inlineImage == nil {
            let spans = styled(p.text[...], p.runs[0].style)
            if spans.count == 1 { return (spans[0], [], inserts) }
            return (TextSpan(children: spans), [], inserts)
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
            let style = theme.textStyle(for: p.runs[0].style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
            children.append(RichImageSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, style: style))
            inline.append((nil, PlaceholderDimensions(size: Size(lead, 0.01), alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, baselineOffset: 0.01)))
        }
        var pos = 0
        let utf16 = p.text.utf16
        for run in p.runs where run.length > 0 {
            let a = utf16.index(utf16.startIndex, offsetBy: pos)
            let b = utf16.index(a, offsetBy: run.length)
            pos += run.length
            if let id = run.style.inlineImage, let image = p.inlineImages[id] {
                let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                // A picture in the line, sitting on the baseline as Word
                // sets it; shrunk to the column when wider.
                var w = _px(image.width), h = _px(image.height)
                if w > textWidth { h *= textWidth / w; w = textWidth }
                // (A floating object takes no room in the line.)
                if theme.wordRules, let float = image.float, !float.takesRoom { w = 0; h = 0 }
                let size = Size(w.rounded(), h.rounded())
                // (Word's `w:textAlignment` "center" sets what is on a
                // line by its middle: a letterhead's words half way up
                // the emblem beside them, not on its foot.)
                let centred = theme.wordRules && p.style.eastAsian["w:textAlignment"] == "center" && image.float == nil
                let alignment = centred ? PlaceholderAlignment.middle : PlaceholderAlignment.baseline
                children.append(RichImageSpan(alignment: alignment, baseline: TextBaseline.alphabetic, style: style))
                inline.append((image, PlaceholderDimensions(size: size, alignment: alignment, baseline: TextBaseline.alphabetic, baselineOffset: size.height)))
                continue
            }
            children.append(contentsOf: styled(p.text[a ..< b], run.style, at: pos - run.length, next: b < utf16.endIndex ? p.text[b] : nil))
        }
        return (TextSpan(children: children), inline, inserts)
    }

    /// Where every stretch of a paragraph has one line height but not
    /// one face, each face splits that height about the baseline its own
    /// way and a line that mixes two comes out taller than either — and
    /// which lines those are depends on which face the platform falls
    /// back to for a character. A strut of that height holds every line
    /// to it. (Stretches of different heights are left to the tallest.)
    private func _strut(_ span: TextSpan, tallest: Bool = false) -> StrutStyle? {
        guard theme.wordRules else { return nil }
        var first: TextStyle? = nil
        var uniform = true
        var count = 0
        func visit(_ s: InlineSpan) {
            guard uniform, let t = s as? TextSpan else { return }
            if t.text != nil, let style = t.style, let size = style.fontSize, let h = style.height, size > 0.5 {
                count += 1
                if let f = first, let fs = f.fontSize, let fh = f.height {
                    if tallest {
                        if size * h > fs * fh + 0.01 { first = style }
                    } else if abs(fs * fh - size * h) > 0.01 { uniform = false }
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
    public func firstLineIndent(_ p: RichParagraph, at index: Int? = nil, _ document: RichDocument) -> Double {
        guard theme.wordRules, p.style.list == nil, !p.text.isEmpty, p.image == nil else { return 0 }
        let chars = Double(p.style.eastAsian["w:hangingChars"] ?? "").map { -$0 } ?? Double(p.style.eastAsian["w:firstLineChars"] ?? "")
        if let chars, chars != 0 {
            // (A character of the first run: its size, and its character
            // spacing with it.)
            let named = _named(p, document)
            let size: Double = p.runs.first?.style.fontSize ?? named?.char.fontSize ?? theme.fontSize
            var spacing: Double = p.runs.first?.style.letterSpacing ?? named?.char.letterSpacing ?? 0
            // (Twice where the document balances its widths: see `_span`.)
            if document.balancesSpaceWidth { spacing *= 2 }
            let grid: Double = _grid(index, document).chars ?? 0
            return chars / 100 * (size + spacing + grid)
        }
        return p.style.firstLineIndent
    }

    /// The sheet's entry for a paragraph: its style's, and for a plain
    /// paragraph Normal's — the face and size a document's body text is
    /// set in when its runs name none, and what its own style leaves
    /// unsaid. (A heading with no entry keeps the theme's look.)
    private func _named(_ p: RichParagraph, _ document: RichDocument) -> RichNamedStyle? {
        guard theme.wordRules else { return document.styles.resolve(p.style) }
        let normal = document.styles[RichNamedStyle.normalId]
        guard var entry = document.styles.resolve(p.style) else { return p.style.heading == nil ? normal : nil }
        // What a style leaves unsaid is Normal's: a sheet read from a
        // file states a style's face and size only where they differ.
        if entry.id != RichNamedStyle.normalId, let n = normal?.char {
            if entry.char.fontSize == nil { entry.char.fontSize = n.fontSize }
            if entry.char.fontFamily == nil { entry.char.fontFamily = n.fontFamily }
            if entry.char.eastAsiaFontFamily == nil { entry.char.eastAsiaFontFamily = n.eastAsiaFontFamily }
            if entry.char.hAnsiFontFamily == nil { entry.char.hAnsiFontFamily = n.hAnsiFontFamily }
            if entry.char.kerningFrom == nil { entry.char.kerningFrom = n.kerningFrom }
        }
        return entry
    }

    /// A paragraph's left and right indents in points: Word's
    /// `w:leftChars` and `w:rightChars` count characters of the
    /// document's own size (Normal's), and outrank the measure beside
    /// them.
    private func _sideIndents(_ p: RichParagraph, _ document: RichDocument) -> (left: Double, right: Double) {
        var left = p.style.indentLeft, right = p.style.indentRight
        guard theme.wordRules, !p.style.eastAsian.isEmpty else { return (left, right) }
        let unit = (document.styles[RichNamedStyle.normalId]?.char.fontSize ?? theme.fontSize) / 100
        if let c = Double(p.style.eastAsian["w:leftChars"] ?? p.style.eastAsian["w:startChars"] ?? ""), c != 0 { left = c * unit }
        if let c = Double(p.style.eastAsian["w:rightChars"] ?? p.style.eastAsian["w:endChars"] ?? ""), c != 0 { right = c * unit }
        return (left, right)
    }

    /// 1 when paragraph `i`'s painter has the indent's box before the
    /// text: what to add to a paragraph offset to get the painter's.
    private func _lead(_ i: Int) -> Int {
        i < _leadWidth.count && _leadWidth[i] != 0 ? 1 : 0
    }

    /// Between a paragraph's offsets and its painter's. The painter's
    /// text is the paragraph's with, at most, a box before it (the first
    /// line's indent: `lead`) and zero-width spaces in it — one before
    /// each of `inserts`, where Word breaks a line and the engine would
    /// not (beside a curly quotation mark).
    struct _OffsetMap {
        var lead = 0
        var inserts: [Int] = []
        func painter(_ offset: Int) -> Int {
            var n = 0
            for k in inserts { if k <= offset { n += 1 } else { break } }
            return offset + lead + n
        }
        func paragraph(_ painterOffset: Int) -> Int {
            var d = painterOffset - lead
            for (j, k) in inserts.enumerated() { if k + lead + j < painterOffset { d -= 1 } else { break } }
            return max(0, d)
        }
    }

    private func _map(_ i: Int) -> _OffsetMap {
        _OffsetMap(lead: _lead(i), inserts: i < _inserts.count ? _inserts[i] : [])
    }

    /// Where each of a painter's lines starts, in paragraph offsets.
    private func _lineStarts(_ painter: TextPainter, _ map: _OffsetMap, count: Int) -> [Int] {
        let total = count + map.lead + map.inserts.count
        var out: [Int] = []
        var at = 0
        while at < total {
            let r = painter.getLineBoundary(TextPosition(offset: at))
            out.append(min(count, map.paragraph(max(r.start, at))))
            guard r.end > at else { break }
            at = r.end
        }
        return out
    }

    /// The spaces of a paragraph (UTF-16 offsets) that stand beside East
    /// Asian text inside a line: every run of them with an ideograph,
    /// kana or full-width mark on either side, but one that ends the
    /// paragraph, a line break, or a line of the layout at hand.
    private func _spacesToHold(_ p: RichParagraph, lineStarts: Set<Int>) -> Set<Int> {
        var out: Set<Int> = []
        var at = 0
        var run: [Int] = []
        var left: Character? = nil
        func wide(_ c: Character?) -> Bool { c.map { Self.isEastAsian($0, hinted: false) } ?? false }
        for ch in p.text {
            if ch == " " {
                run.append(at)
            } else {
                if let end = run.last, ch != "\n", ch != "\u{2028}", wide(left) || wide(ch), !lineStarts.contains(end + 1) { out.formUnion(run) }
                run = []
                left = ch
            }
            at += ch.utf16.count
        }
        return out
    }

    /// How wide a face sets a space, in pixels, at a style's size.
    private func _spaceWidth(_ style: TextStyle) -> Double { _glyphWidth(style, " ") }

    /// How wide a face sets a character, in pixels, at a style's size.
    private func _glyphWidth(_ style: TextStyle, _ ch: Character) -> Double {
        let key = "\(ch)|\(style.fontFamily ?? "")|\(style.fontSize ?? 0)|\(style.fontWeight == .bold)|\(style.fontStyle == .italic)"
            + (style.fontFeatures?.isEmpty ?? true ? "" : "|f")
        if let w = _spaceWidths[key] { return w }
        func width(_ text: String) -> Double {
            let t = TextPainter(text: TextSpan(text: text, style: style.copyWith(letterSpacing: 0)), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            defer { t.dispose() }
            return t.width
        }
        let w = width("x\(ch)x") - width("xx")
        _spaceWidths[key] = w
        return w
    }
    private var _spaceWidths: [String: Double] = [:]

    /// Paints a paragraph that has characters of a scale of their own
    /// (`CharStyle.horizontalScale`, Word's `w:w`) and says so — false
    /// where it has none. The engine sets no face narrower than it is:
    /// such a stretch is laid out that much smaller or larger a size,
    /// which gives every character its width and every line its
    /// breaks. A paragraph all of one scale — a letterhead at 34%, a
    /// style at 95% — is drawn from a second painter instead: the same
    /// text at its full size in a column that much wider, under a
    /// canvas that much narrower, so that a 61pt letterhead is 61pt
    /// tall and a third as wide rather than 21pt text. One of several
    /// scales has each stretch pulled back to its height about its
    /// line's baseline.
    private func _paintScaled(_ i: Int, _ g: ParagraphGeometry, _ canvas: any Canvas, _ document: RichDocument) -> Bool {
        guard theme.wordRules, i < document.paragraphs.count else { return false }
        let p = document.paragraphs[i]
        let named = _named(p, document)
        let sheet = named?.char.horizontalScale
        guard p.image == nil, sheet != nil || p.runs.contains(where: { $0.style.horizontalScale != nil }) else { return false }
        func scale(of run: Run) -> Double { max(0.01, run.style.horizontalScale ?? sheet ?? 1) }
        let scales = Set(p.runs.filter { $0.length > 0 && $0.style.inlineImage == nil }.map { scale(of: $0) })
        guard scales.contains(where: { abs($0 - 1) > 0.001 }) else { return false }
        let lines = g.painter.computeLineMetrics()
        guard !lines.isEmpty else { return false }
        if scales.count == 1, let k = scales.first, let wide = _widePainter(g.painter, k) {
            let wideLines = wide.computeLineMetrics()
            if wideLines.count == lines.count,
               !zip(wideLines, lines).contains(where: { abs($0.width * k - $1.width) > max(2, $1.width * 0.01) }) {
                canvas.save()
                // (Its baseline where the paragraph's own is.)
                canvas.translate(g.textLeft, g.inkTop + lines[0].baseline - wideLines[0].baseline)
                canvas.scale(k, 1)
                wide.paint(canvas, Offset.zero)
                canvas.restore()
                return true
            }
        }
        // (Each stretch's boxes, joined where they follow on a line.)
        let map = _map(i)
        var pieces: [(rect: Rect, baseline: Double, k: Double)] = []
        var at = 0
        for run in p.runs {
            let from = at
            at += run.length
            let k = scale(of: run)
            guard run.length > 0, abs(k - 1) > 0.001, run.style.inlineImage == nil else { continue }
            let boxes = g.painter.getBoxesForSelection(
                TextSelection(baseOffset: map.painter(from), extentOffset: map.painter(at)), boxHeightStyle: .max)
            for box in boxes where box.right - box.left > 0.01 {
                let mid = (box.top + box.bottom) / 2
                var n = 0
                for (j, line) in lines.enumerated() where mid >= line.baseline - line.ascent - 0.5 { n = j }
                let line = lines[n]
                // (A line's whole band, and all the way out where the
                // stretch ends the line: an overhang is not cut.)
                let top = n == 0 ? -100_000 : lines[n - 1].baseline + lines[n - 1].descent
                let bottom = n == lines.count - 1 ? 100_000 : line.baseline + line.descent
                let left = box.left <= line.left + 0.5 ? -100_000 : box.left
                let right = box.right >= line.left + line.width - 0.5 ? 100_000 : box.right
                if let last = pieces.last, last.k == k, last.baseline == line.baseline, left - last.rect.right < (box.bottom - box.top) / 2 {
                    pieces[pieces.count - 1].rect = Rect.fromLTRB(last.rect.left, top, right, bottom)
                } else {
                    pieces.append((Rect.fromLTRB(left, top, right, bottom), line.baseline, k))
                }
            }
        }
        // (Every piece draws the paragraph again under its clip: a few
        // stretches, not a page of them.)
        guard !pieces.isEmpty, pieces.count <= 6 else { return false }
        let origin = Offset(g.textLeft, g.inkTop)
        canvas.save()
        for piece in pieces { canvas.clipRect(piece.rect.shift(origin), clipOp: .difference, doAntiAlias: false) }
        g.painter.paint(canvas, origin)
        canvas.restore()
        for piece in pieces {
            canvas.save()
            canvas.translate(0, origin.dy + piece.baseline)
            canvas.scale(1, 1 / piece.k)
            canvas.translate(0, -(origin.dy + piece.baseline))
            canvas.clipRect(piece.rect.shift(origin), clipOp: .intersect, doAntiAlias: false)
            g.painter.paint(canvas, origin)
            canvas.restore()
        }
        return true
    }

    /// `painter`'s text at 1/k its size in a column 1/k its width: what
    /// a canvas k as wide draws as characters of that scale. Kept while
    /// the painter is.
    private func _widePainter(_ painter: TextPainter, _ k: Double) -> TextPainter? {
        let id = ObjectIdentifier(painter)
        if let hit = _widePainters[id], hit.source === painter { return hit.wide }
        guard let root = painter.text else { return nil }
        if _widePainters.count > 256 {
            for entry in _widePainters.values { entry.wide.dispose() }
            _widePainters = [:]
        }
        func widened(_ style: TextStyle?) -> TextStyle? {
            guard let style, let size = style.fontSize else { return style }
            // (The same line: its height is a multiple of the size.)
            return style.copyWith(fontSize: size / k, letterSpacing: style.letterSpacing.map { $0 / k },
                                  height: style.height.map { $0 * k })
        }
        func copy(_ span: InlineSpan) -> InlineSpan {
            if let image = span as? RichImageSpan {
                return RichImageSpan(alignment: image.alignment, baseline: image.baseline, style: widened(image.style))
            }
            guard let t = span as? TextSpan else { return span }
            return TextSpan(text: t.text, children: t.children.map { $0.map(copy) }, style: widened(t.style))
        }
        let strut = painter.strutStyle.map { s in
            StrutStyle(fontFamily: s.fontFamily, fontFamilyFallback: s.fontFamilyFallback,
                       fontSize: s.fontSize.map { $0 / k }, height: s.height.map { $0 * k },
                       leadingDistribution: s.leadingDistribution, fontWeight: s.fontWeight,
                       forceStrutHeight: s.forceStrutHeight)
        }
        let wide = TextPainter(text: copy(root), textAlign: painter.textAlign, textDirection: painter.textDirection ?? .ltr,
                               strutStyle: strut)
        if let dims = painter.placeholderDimensions {
            wide.setPlaceholderDimensions(dims.map {
                PlaceholderDimensions(size: Size($0.size.width / k, $0.size.height), alignment: $0.alignment,
                                      baseline: $0.baseline, baselineOffset: $0.baselineOffset)
            })
        }
        wide.layout(minWidth: painter.width / k, maxWidth: painter.width / k)
        _widePainters[id] = (painter, wide)
        return wide
    }
    private var _widePainters: [ObjectIdentifier: (source: TextPainter, wide: TextPainter)] = [:]

    /// Word's geometry for a list paragraph, where the file gives it
    /// (points): the text's left, the first line's offset from it — the
    /// number stands there — and the level's format. nil for a list of
    /// the editor's own making, which keeps the theme's slot.
    private func _wordList(_ p: RichParagraph, _ document: RichDocument) -> (left: Double, first: Double, format: ListLevelFormat?)? {
        guard theme.wordRules, p.style.list != nil, p.image == nil else { return nil }
        let f = p.style.listId.flatMap { document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)] }
        guard let left = p.style.listIndentLeft ?? f?.indentLeft else { return nil }
        return (left, p.style.listFirstLine ?? -(f?.hanging ?? 0), f)
    }

    /// A list paragraph's marker, laid out at its own width.
    private func _marker(_ i: Int, _ p: RichParagraph, _ document: RichDocument, label: String, strut: StrutStyle?) -> TextPainter {
        var markerChar = p.runs[0].style
        if let c = p.style.bulletColor { markerChar.color = c }
        if let k = p.style.bulletScale {
            markerChar.fontSize = (markerChar.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize) * k
        }
        let pitch = p.style.eastAsian["w:snapToGrid"] == "0" ? nil : _grid(i, document).pitch
        let named = _named(p, document)
        // East Asian numbers in the run's East Asian face, as the text.
        let ea = theme.wordRules && label.contains(where: { Self.isEastAsian($0, hinted: true) })
        let markerStyle = theme.textStyle(for: markerChar, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: ea, gridPitch: pitch)
        // The number is on the document's character grid like the text
        // after it — each character wider by the grid's addition, a
        // half-width one by half of it where widths are balanced: Word
        // sets "（2）" 43.97pt wide at 16pt on a grid of 1.008, and the
        // text begins there (zh-457a8d62; it was 41.4 here, and the
        // line took a character more).
        var span = TextSpan(text: label, style: markerStyle)
        if theme.wordRules, let g = _grid(i, document).chars, g != 0, !(markerChar.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false) {
            let full = markerStyle.copyWith(letterSpacing: (markerStyle.letterSpacing ?? 0) + _px(g))
            let half = document.balancesSpaceWidth ? markerStyle.copyWith(letterSpacing: (markerStyle.letterSpacing ?? 0) + _px(g) / 2) : full
            span = TextSpan(children: label.map { TextSpan(text: String($0), style: Self.isEastAsian($0, hinted: true) ? full : half) })
        }
        let marker = TextPainter(text: span, textAlign: .left, textDirection: .ltr, strutStyle: strut)
        marker.layout(minWidth: 0, maxWidth: 100_000)
        return marker
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
    /// those. Measured from Word 16's prints, 2026-10-12, and only in a
    /// justified paragraph: a closing mark
    /// hangs unless the paragraph says `w:overflowPunct` off; a line
    /// gives up to half an em, off its punctuation, where the document's
    /// `w:characterSpacingControl` compresses punctuation.
    ///
    /// The automatic space between an ideograph and a letter or digit
    /// (see `_span`) is between two characters of a line: after a
    /// line's last character there is none, in any paragraph (a line of
    /// 25 ideographs and "C" is taken at 414.7pt, the letter's own
    /// 10.7 and the 4 before it, not the 4 after). And where punctuation
    /// is compressed, before Word 2013's layout, each such space on the
    /// line gives up to half of itself like a mark does: one "C" among
    /// twenty ideographs takes the next one 4pt over, two take it 8 —
    /// the half em that is the most a line takes — and the space before
    /// a last "C" 2 (measured 2026-10-12; with `doNotCompress` none
    /// gives). From 2013's layout on they give in a justified paragraph
    /// only and by another rule, not found: one space gave 4pt, two
    /// under 4, four under 5.
    ///
    /// In a table's cell no mark hangs; the marks inside a line give
    /// there as anywhere.
    private func _fitEastAsianLines(_ p: RichParagraph, at i: Int, _ document: RichDocument, textWidth width: Double,
                                    first: TextPainter, leadWidth: Double, tabs: [Int: Double] = [:]) -> [Int: Double] {
        // (From Word 2013's layout on, only a justified paragraph's
        // lines are fitted — set left or centred, a mark neither hangs
        // nor gives. Before it, and that is most documents written
        // elsewhere, every paragraph's are.)
        guard theme.wordRules, document.usesEastAsianLayout, !p.style.rightToLeft, p.text.utf16.count > 2 else { return [:] }
        let legacy = (document.compatibilityMode ?? 12) < 15
        let fitted = p.style.alignment == .justify || legacy
        // (The probe is the text alone: the box before it — the first
        // line's indent — is where the first line starts from instead.)
        let lead = 0
        // (Nothing hangs out of a table's cell: a line of 24
        // ideographs and a full stop is taken at 25 ems there, where
        // the same paragraph outside a table takes it at 24 — in every
        // mode, alignment and setting of the compatibility switches
        // that sound like it, `w:doNotWrapTextWithPunct` among them.)
        let inCell = p.cell != nil
        let hangs = fitted && !inCell && p.style.eastAsian["w:overflowPunct"] != "0"
        let squeezes = fitted && (document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false)
        let units = Array(p.text.utf16)
        // (Marks to hang or squeeze, or a letter or digit an automatic
        // space may stand beside.)
        let marked = (hangs || squeezes) && units.contains(where: { Self._hangingUnits.contains($0) || Self._openingUnits.contains($0) })
        guard marked || units.contains(where: { $0 < 0x250 && ($0 >= 0x41 || ($0 >= 0x30 && $0 <= 0x39)) }),
              first.computeLineMetrics().count > 1 else { return [:] }
        // What each character's automatic space after it is.
        var gaps: [Int: Double] = [:]
        let (span, inline, inserts) = _span(for: p, at: i, document, textWidth: width, lead: 0, adjust: tabs, autoSpaces: { gaps[$0] = $1 })
        guard marked || !gaps.isEmpty else { return [:] }
        let map = _OffsetMap(lead: 0, inserts: inserts)
        // Where a zero-width space lets the line break (a word joiner,
        // the other thing `_span` puts in, does the opposite).
        let breakBefore = Set(inserts.filter { o in
            guard o > 0, o < units.count, let a = Unicode.Scalar(units[o - 1]), let b = Unicode.Scalar(units[o]) else { return false }
            return Self._breaksBetween(Character(a), Character(b))
        }).union(_looseWordOffsets(p, document, textWidth: width, named: _named(p, document),
                                   pitch: p.style.eastAsian["w:snapToGrid"] == "0" ? nil : _grid(i, document).pitch))
        let probe = TextPainter(text: span, textAlign: .left, textDirection: .ltr)
        if !inline.isEmpty { probe.setPlaceholderDimensions(inline.map { $0.dimensions }) }
        probe.layout(minWidth: 0, maxWidth: 1)
        defer { probe.dispose() }
        // The size (pixels) of the run at each offset: a mark's em.
        var ems: [Double] = []
        ems.reserveCapacity(units.count)
        let named = _named(p, document)
        var closing: [Bool] = []
        // Whether a curly quote at each offset is the full-width one
        // (East Asian text's, see `_span`): a mark like a bracket.
        var wideQuotes: [Bool] = []
        for run in p.runs {
            let em = (run.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            ems.append(contentsOf: repeatElement(em, count: run.length))
            closing.append(contentsOf: repeatElement(_closesUpMarks(run.style, named, document), count: run.length))
            let face = theme.faceResolver?(run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, false)
            let hinted = (run.style.fontHint ?? named?.char.fontHint) == "eastAsia" || (face?.isEastAsian ?? false)
            wideQuotes.append(contentsOf: repeatElement(hinted, count: run.length))
        }
        guard ems.count == units.count else { return [:] }
        func wideQuote(_ k: Int) -> Bool { wideQuotes[k] && (units[k] == 0x201C || units[k] == 0x201D || units[k] == 0x2018 || units[k] == 0x2019) }
        // (A no-break space of the text's own is a character like any
        // other: it is not what a line may end with for nothing.)
        func isSpace(_ u: UInt16) -> Bool { u == 0x20 || u == 0x3000 || u == 0x09 }
        func closesUp(_ k: Int) -> Bool {
            guard closing[k], k + 1 < units.count, let a = Unicode.Scalar(units[k]), let b = Unicode.Scalar(units[k + 1]) else { return false }
            return Self.closesUp(Character(a), Character(b))
        }
        // The probe's lines are the engine's clusters (at no width it
        // breaks even inside a word): each with its width, and its
        // trailing spaces' apart, which the engine leaves out of a line's
        // width and of its fit.
        struct Piece { var a: Int; var b: Int; var last: Int; var w: Double; var trail: Double; var hard: Bool }
        var pieces: [Piece] = []
        var start = 0           // painter offset
        let total = units.count + inserts.count
        // (Walked by the lines' boundaries, and measured by the boxes
        // of what is between them: the engine's count of lines is not
        // the count of those where a space is set wider than it is.)
        func boxes(_ from: Int, _ to: Int) -> Double {
            guard to > from else { return 0 }
            var w = 0.0
            for box in probe.getBoxesForSelection(TextSelection(baseOffset: map.painter(from), extentOffset: map.painter(to - 1) + 1)) {
                w += box.right - box.left
            }
            return w
        }
        // (What `_span` put in before a character and the engine set
        // on a line of its own: a word joiner as wide as an opening
        // quote's blank. Its width goes with what follows it.)
        var pending = 0.0
        while start < total {
            let r = probe.getLineBoundary(TextPosition(offset: start))
            let end = min(total, max(start + 1, r.end))
            let a = min(units.count, map.paragraph(start)), b = min(units.count, max(a, map.paragraph(end)))   // paragraph offsets
            let from = start
            start = end
            guard b > a else {
                for box in probe.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: end)) { pending += box.right - box.left }
                continue
            }
            var last = b
            while last > a, isSpace(units[last - 1]) { last -= 1 }
            let trail = boxes(last, b)
            // (From the line's own start: one may sit on this line too.)
            var lineWidth = pending
            if last > a {
                for box in probe.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: map.painter(last - 1) + 1)) {
                    lineWidth += box.right - box.left
                }
            }
            pending = 0
            let hard = units[b - 1] == 0x0A || units[b - 1] == 0x2028 || units[b - 1] == 0x0B || end >= total
            // Clusters the engine will not part are one stretch: a space
            // stays with what it follows, and so does whatever may not
            // start a line or follows what may not end one — unless a
            // zero-width space stands between them.
            if var g = pieces.last, !g.hard, g.b == a, g.b > g.a, !breakBefore.contains(a),
               last == a || (g.last == g.b && Self._glued(units[g.b - 1], units[a])) {
                g.w += lineWidth
                g.b = b
                if last > a { g.last = last }
                g.trail += trail
                g.hard = hard
                pieces[pieces.count - 1] = g
            } else {
                pieces.append(Piece(a: a, b: b, last: last, w: lineWidth, trail: trail, hard: hard))
            }
        }
        var adjust: [Int: Double] = [:]
        var x = leadWidth
        var marks: [Int] = []   // this line's marks that still have their whole em
        var spaces: [Int] = []  // this line's characters with an automatic space after them
        var opening = true      // nothing on the line yet
        var lineWide = 0        // this line's characters, and whether it has spaces among them
        var lineOther = false
        var lineSpaced = false  // … or ends, so far, with one
        for piece in pieces {
            let a = piece.a, last = piece.last, w = piece.w
            if lineSpaced, last > a { lineOther = true }
            // (The automatic space after this stretch, which is no part
            // of a line that ends with it.)
            let after = last > a ? gaps[last - 1] ?? 0 : 0
            let ownSpaces = last > a ? (a ..< last - 1).filter { gaps[$0] != nil } : []
            let own = (a ..< last).filter {
                (Self._closingUnits.contains(units[$0]) || Self._openingUnits.contains(units[$0]) || wideQuote($0)) && !closesUp($0)
            }
            let em = a < ems.count ? ems[a] : 0
            let hair = min(em * 0.01, _px(0.005))   // (a stand-in's half em is a hair over half)
            // (The half em a line takes at most is Word's to a twentieth
            // of a point: 7.12pt over at 14pt is not taken. The widths
            // are the faces' own now, and the hair would take it.)
            // (Under a twentieth, which is one of Word's units: 16pt
            // text spaced -0.5 takes a character 7.5 over and leaves one
            // 7.55 over — zh-6cd1befe, in a column of 445.25. But as
            // near to it as may be: with Latin digits on the line the
            // sum here is not Word's to the hundredth, and zh-a4b0f6ea
            // has a "《威" taken that comes out a few hundredths over.)
            let edge = min(em * 0.01, _px(0.045))
            var fits = x + w - after <= width + hair
            let traced = Self.debugFit.map { p.text.firstRange(of: $0) != nil } ?? false
            if traced {
                let pt = theme.pixelsPerPoint * scale
                let text = String(decoding: units[a ..< piece.b], as: UTF16.self)
                FileHandle.standardError.write(Data("fit [\(text)] w \(w / pt) x \(x / pt) of \(width / pt) fits \(fits) marks \(marks.count)+\(own.count)\n".utf8))
            }
            // (Fitting by that hair is fitting: the engine allows none,
            // so the last character gives it up.)
            if fits, x + w > width, last > a { adjust[last - 1, default: 0] -= x + w - width + 0.02 }
            if !fits, !opening, last > a {
                let over = x + w - width
                let tail = last - 1
                // A closing mark at the end of what comes next may hang
                // past the margin, by as much as it is wide; what is
                // still over, the line's other marks may give.
                // (No more than the mark is wide — a curly quote in a
                // Latin face is under half an em — and half an em at
                // most under the alternative kinsoku rules.)
                // (And not at all under those rules where the document
                // compresses no punctuation: the half that hangs is the
                // mark's own, given up.)
                let hang = hangs && Self._hangingUnits.contains(units[tail]) && (squeezes || !document.hangsHalf)
                    ? min(ems[tail] * (closesUp(tail) || document.hangsHalf ? 0.5 : 1), boxes(tail, tail + 1)) : 0
                if hang > 0, over <= hang + hair {
                    // (All of it, the hair too: the engine has none.)
                    adjust[tail, default: 0] -= over + 0.02
                    fits = true
                } else if squeezes {
                    // Word takes the next character where it is half an
                    // em or less too wide for the line, and then all of
                    // what cannot be parted from it (an opening mark's
                    // word), as long as the line's marks can give that
                    // much: half an em each, shared evenly.
                    // (The mark at the end is not one of them where it
                    // hangs — nor, before Word 2013's layout, in a cell,
                    // where it would have hung: there the line's other
                    // marks give and the last keeps its em; from 2013's
                    // on it gives its half like the rest.)
                    // (That was a document in Taiwan's Chinese. In the
                    // mainland's — the language Normal names for East
                    // Asian text — the last gives its half before 2013's
                    // layout too: twenty ideographs and a comma are
                    // taken at 20.5 ems, with a comma among them at 21,
                    // and under `zh-TW` at 21 and 21.5. Measured
                    // 2026-10-13, left and justified, with and without
                    // kerning, cell margins and nine compatibility
                    // switches, none of which moved it.)
                    let kept = hang > 0 || (legacy && inCell && !document.marksSitLeft && Self._hangingUnits.contains(units[tail]))
                    let all = (marks + own).filter { !kept || $0 != tail }
                    let given = legacy ? spaces + ownSpaces : []
                    // (A curly quote in a Latin face is as wide as it is.)
                    // (… as it is set: spaced wider, an ideograph 16.6
                    // apart is 8.4 over where its em would be 7.8 over,
                    // and Word leaves it — lab `sq2`.)
                    let lead = Self._closingUnits.contains(units[a]) || Self._openingUnits.contains(units[a]) || units[a] >= 0x2E80 || wideQuote(a)
                        ? (closesUp(a) ? em * 0.5 : wideQuote(a) ? em : max(em, boxes(a, a + 1) - (gaps[a] ?? 0))) : Self._quotes.contains(units[a]) ? boxes(a, a + 1) : w - after
                    // (Half of a mark as it is set — on a character
                    // grid half of its em and of the grid's addition:
                    // two marks on a grid of 1.008 gave 8.5pt each, a
                    // line 16.9 over at 16pt, zh-457a8d62. A full-width
                    // quote is its glyph and a blank: half its em.)
                    func half(_ k: Int) -> Double { wideQuote(k) ? ems[k] / 2 : (boxes(k, k + 1) - (gaps[k] ?? 0)) / 2 }
                    let markRoom = all.reduce(0.0) { $0 + half($1) }
                    let room = given.reduce(markRoom) { $0 + (gaps[$1] ?? 0) / 2 }
                    let need = over - hang - after
                    // From Word 2013's layout on the test is another:
                    // what each mark must give is no more than the
                    // line would have to stretch by without the
                    // stretch — one mark takes a character half an em
                    // over, two take one two thirds over, three one
                    // three quarters over (measured 2026-10-12).
                    // Measured again 2026-10-13, to a tenth of a point
                    // (labs `mm`, `mm2`, `mm3`): the line is squeezed
                    // where that asks less of it than stretching would
                    // — what the marks must give, as a share of the half
                    // each can give, is no more than what the line
                    // would otherwise stretch by as a share of what it
                    // can stretch: a sixty-fourth of an em at each of
                    // its gaps. So it turns on how many characters the
                    // line holds: with 26 of 16pt, two commas take a
                    // character 11.5 over and not 11.6, seven 14.3 and
                    // not 14.4; with 16 on the line two take 12.9, with
                    // 10, 14.0; at 14pt, 10.0. One mark never gives
                    // more than its half, and every kind of mark gives
                    // alike. Measured on lines of full-width characters
                    // alone; digits and brackets among them are counted
                    // as characters like any (zh-457a8d62 takes a 同
                    // 11.4 over with two marks and 23 characters, which
                    // this allows and a gap fewer would not), and a
                    // line with spaces in it, which stretches at those
                    // first, keeps the older test. So does a character
                    // with a mark after it that hangs: there the marks
                    // may each give no more than the line would stretch
                    // by — one takes it 8.0 over, two 10.4 and not
                    // 10.8, three 11.6 and not 12.0 (lab `mh`), which
                    // is what was first measured.
                    let modern = (document.compatibilityMode ?? 12) >= 15
                    // (Half an em of the character as it is set, its
                    // run's spacing with it: 16pt text spaced -0.4 sets
                    // an ideograph 15.2 apart and takes one 7.55 over,
                    // not 7.65; spaced -1, 6.9 and not 7.1; unspaced,
                    // 7.9 and not 8.1. Lab `sq`, 2026-10-13.)
                    let wide = Self._closingUnits.contains(units[a]) || Self._openingUnits.contains(units[a]) || units[a] >= 0x2E80 || wideQuote(a)
                    // (Without the automatic space after it, which is
                    // no part of the character.)
                    let set = wide && !closesUp(a) ? boxes(a, a + 1) - (gaps[a] ?? 0) : em
                    // (Before 2013's layout a Latin word at the line's end
                    // is taken in a cell whenever the marks and the
                    // automatic spaces can give what it needs — "110.01.01"
                    // 10.5 over, with a full-width colon and two such
                    // spaces on the line, and not 11; an ideograph is taken
                    // half its em over there as in the body. Lab `ovc`,
                    // from zh-4c3793e8's timetable, 2026-10-14. In the body
                    // the word keeps the half-em test: zh-e27cd8bf's "20"
                    // and "2021" are taken by Word, and the body lab `ov`
                    // could not say more — its natural widths were not
                    // known to the point.)
                    let taken = modern
                        ? (!lineOther && lineWide > 1 && room > 0 && hang == 0
                            ? need * Double(lineWide - 1) * em / 64 <= room * (width - x + hair)
                            // (To the limit with one mark — 8.0 over is
                            // taken — and short of it with more: three
                            // leave a character 12.0 over.)
                            : need / Double(max(1, all.count)) <= width - x + (all.count > 1 ? -_px(0.02) : hair))
                        : (!wide && inCell) || x + min(lead, w) - width <= set / 2 + edge
                    if traced {
                        let pt = theme.pixelsPerPoint * scale
                        FileHandle.standardError.write(Data("    over \(over / pt) hang \(hang / pt) need \(need / pt) room \(room / pt) of \(all.count) marks, lead \(lead / pt) set \(set / pt) taken \(taken)\n".utf8))
                    }
                    if room > 0, taken, need <= room + hair {
                        let share = min(1, (need + 0.02) / room)
                        // (The marks give first, and the automatic spaces
                        // what is still needed: the colon of lab `ovc` is
                        // set at its half, 7.0, and the two spaces at 2.63
                        // of their 3.5, not all three at a share.)
                        let markShare = given.isEmpty || markRoom <= 0 ? share : min(1, (need + 0.02) / markRoom)
                        let spaceShare = given.isEmpty || markRoom <= 0 ? share
                            : min(1, max(0, need + 0.02 - markRoom) / max(0.001, room - markRoom))
                        for mark in all { adjust[mark, default: 0] -= half(mark) * markShare }
                        for k in given { adjust[k, default: 0] -= (gaps[k] ?? 0) / 2 * spaceShare }
                        // (What the marks cannot give of that fiftieth —
                        // where they give all they have — the last
                        // character does: the engine allows the line
                        // nothing over.)
                        let short = need + 0.02 - room * share
                        if short > 0.001 { adjust[last - 1, default: 0] -= short }
                        if hang > 0 { adjust[tail, default: 0] -= hang }
                        if after > 0 { adjust[tail, default: 0] -= after }
                        fits = true
                    }
                }
                if fits {
                    // The line is full: whatever comes next starts another.
                    x = width
                    marks = []
                    spaces = []
                    if piece.hard { x = 0; opening = true; lineWide = 0; lineOther = false; lineSpaced = false }
                    continue
                }
            }
            if !fits {
                x = 0
                marks = []
                spaces = []
                lineWide = 0
                lineOther = false
                lineSpaced = false
            }
            // (Spaces a line opens with are no characters of it, and
            // those it ends with stretch nothing.)
            for k in a ..< last {
                if isSpace(units[k]) { if lineWide > 0 { lineOther = true } } else { lineWide += 1 }
            }
            if last < piece.b, lineWide > 0 { lineSpaced = true }
            x += w + piece.trail
            opening = false
            marks.append(contentsOf: own)
            spaces.append(contentsOf: ownSpaces)
            if after > 0 { spaces.append(last - 1) }
            if piece.hard {
                x = 0
                marks = []
                spaces = []
                opening = true
                lineWide = 0
                lineOther = false
                lineSpaced = false
            }
        }
        // (With the tabs' widths, which the paragraph is laid out by.)
        guard !adjust.isEmpty else { return [:] }
        for (k, v) in tabs { adjust[k, default: 0] += v }
        return adjust
    }

    /// Whether the engine keeps `a` and `b` on one line (a reading of the
    /// Unicode line breaking rules it follows, for the cases Chinese text
    /// meets): nothing parts a mark that may not start a line from what
    /// is before it, or one that may not end a line from what follows; a
    /// quotation mark from either side; the letters and digits of a word.
    private static func _glued(_ a: UInt16, _ b: UInt16) -> Bool {
        if _noStart.contains(b) || _noEnd.contains(a) || _quotes.contains(a) || _quotes.contains(b) { return true }
        if a == 0xA0 || b == 0xA0 { return true }
        func word(_ u: UInt16) -> Bool {
            (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || (u >= 0xC0 && u <= 0x24F)
        }
        func digit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
        if word(a) && word(b) { return true }
        // (A Latin word is whole but after its hyphens: see `_joinsLatin`.)
        if a > 0x20, a < 0x7F, b > 0x20, b < 0x7F, a != 0x2D { return true }
        // (1.5, 1,000, 10:30, 2024-10, -5)
        if digit(b), a == 0x2E || a == 0x2C || a == 0x3A || a == 0x2D || a == 0x2F { return true }
        return false
    }

    private static let _noStart = _hangingUnits.subtracting("”’".utf16)
        .union(",.:;!?%)]}-/‰℃°…～·・ー々〃ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ".utf16)
    private static let _noEnd = _openingUnits.union("([{$#￥＄£".utf16)
    private static let _quotes = Set("\"'“”‘’".utf16)

    private static let _closingUnits = Set(_closingMarks.flatMap { String($0).utf16 })
    private static let _openingUnits = Set(_openingMarks.flatMap { String($0).utf16 })
    /// The marks that may hang past the margin at a line's end.
    private static let _hangingUnits = _closingUnits.union("？”’％".utf16)

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

    /// The offsets at which a Latin word may be parted: inside one too
    /// long for a line of `textWidth` (every character of it but its
    /// first — Word parts those wherever a line ends), and inside every
    /// one where the paragraph says so. A word here is a stretch of
    /// ASCII with no space in it; only one of twenty characters or more
    /// is measured.
    private func _looseWordOffsets(_ p: RichParagraph, _ document: RichDocument, textWidth: Double,
                                   named: RichNamedStyle?, pitch: Double?) -> Set<Int> {
        guard theme.wordRules else { return [] }
        let units = Array(p.text.utf16)
        var out: Set<Int> = []
        // (`w:wordWrap` off, as many Chinese documents say: every Latin
        // word parts at any character — but not so as to begin a line
        // with what may not begin one, or end it with what may not end.)
        if p.style.eastAsian["w:wordWrap"] == "0" {
            for k in units.indices.dropFirst() where units[k] > 0x20 && units[k] < 0x7F && units[k - 1] > 0x20 && units[k - 1] < 0x7F {
                if !Self._noStart.contains(units[k]), !Self._noEnd.contains(units[k - 1]) { out.insert(k) }
            }
            return out
        }
        guard textWidth > 1, textWidth < 50_000, units.count >= 20 else { return [] }
        var k = 0
        while k < units.count {
            guard units[k] > 0x20, units[k] < 0x7F else { k += 1; continue }
            var end = k
            while end < units.count, units[end] > 0x20, units[end] < 0x7F { end += 1 }
            if end - k >= 20 {
                var at = 0
                var run = p.runs[0].style
                for r in p.runs { if k < at + r.length { run = r.style; break }; at += r.length }
                let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let word = String(decoding: units[k ..< end], as: UTF16.self)
                let painter = TextPainter(text: TextSpan(text: word, style: style), textDirection: .ltr)
                painter.layout(minWidth: 0, maxWidth: 1_000_000)
                if painter.width > textWidth { out.formUnion((k + 1) ..< end) }
                painter.dispose()
            }
            k = end
        }
        return out
    }

    /// Whether a word joiner goes between `a` and `b`: two characters
    /// of one Latin word (see `_span`) after the first of which the
    /// engine may break — a stroke, a question or exclamation mark, a
    /// bar, a closing bracket.
    private static func _joinsLatin(_ a: Character, _ b: Character) -> Bool {
        guard let x = a.asciiValue, let y = b.asciiValue, y > 0x20, y < 0x7F else { return false }
        return x == 0x2F || x == 0x3F || x == 0x21 || x == 0x7C || x == 0x29 || x == 0x5D || x == 0x7D
    }

    /// Whether a line may break between `a` and `b` for a curly quote's
    /// sake: before an opening one that follows East Asian text or a
    /// closing mark, after a closing one that East Asian text or an
    /// opening mark follows.
    private static func _breaksBetween(_ a: Character, _ b: Character) -> Bool {
        func wide(_ c: Character) -> Bool { (c.unicodeScalars.first?.value ?? 0) >= 0x2E80 }
        if b == "\u{201C}" || b == "\u{2018}" {
            return wide(a) && !_openingMarks.contains(a) || a == "\u{201D}" || a == "\u{2019}"
        }
        if a == "\u{201D}" || a == "\u{2019}" {
            return wide(b) && !_closingMarks.contains(b) && !"？！％…".contains(b)
        }
        return false
    }

    /// Whether Word's automatic spacing falls between `a` and `b`: one
    /// an ideograph, kana or hangul, the other a Latin letter (unless
    /// the paragraph turns `w:autoSpaceDE` off) or a digit
    /// (`w:autoSpaceDN`). Punctuation of either script takes none —
    /// and nor does anything in a document not set by the East Asian
    /// rules, which the caller checks.
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

    /// A kept shape's line or box (`ImageAttachment.outline`), in `rect`.
    private func _paintOutline(_ image: ImageAttachment, _ rect: Rect, _ canvas: any Canvas) {
        guard theme.wordRules, let outline = image.outline else { return }
        if outline.kind == .box, let fill = outline.fill {
            let paint = Paint()
            paint.style = .fill
            paint.color = fill
            canvas.drawRect(rect, paint)
        }
        guard let color = outline.color else { return }
        let stroke = Paint()
        stroke.style = .stroke
        stroke.strokeWidth = max(1, _px(outline.width))
        stroke.color = color
        switch outline.kind {
        case .box: canvas.drawRect(rect, stroke)
        case .line:
            canvas.drawLine(outline.flipped ? rect.bottomLeft : rect.topLeft, outline.flipped ? rect.topRight : rect.bottomRight, stroke)
        }
    }

    /// Whether a picture of the document — the body's, a header's or
    /// footer's, a text box's — is still being decoded: what is painted
    /// before that is a grey box in its place. An export waits on this.
    public var hasPendingImages: Bool {
        !_decoding.isEmpty || _headerFooterCache.values.contains { $0.layout.hasPendingImages }
            || _textBoxCache.values.contains { $0.layout.hasPendingImages }
    }

    private func _ensureDecoded(_ image: ImageAttachment) {
        // (An attachment with no picture in it — a drawn shape kept for
        // the file — is nothing to decode.)
        if _decoded[image.id] != nil || _decoding.contains(image.id) || image.data.isEmpty { return }
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
                if ProcessInfo.processInfo.environment["STARLING_RICHTEXT_PERF"] != nil {
                    FileHandle.standardError.write(Data("image \(id): not decoded: \(error) (\(bytes.count) bytes, \(bytes.prefix(8)))\n".utf8))
                }
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
        if theme.wordRules, i < _floats.count, let float = _floats[i], !float.takesRoom, i < _floatImages.count, let image = _floatImages[i] {
            return _floatRect(float, image, g, i)
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
        let map = _map(i)
        let o = g.painter.getOffsetForCaret(TextPosition(offset: map.painter(offset)), proto)
        let h = g.painter.getFullHeightForCaret(TextPosition(offset: map.painter(offset)), proto)
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
            let map = _map(i)
            for box in g.painter.getBoxesForSelection(
                TextSelection(baseOffset: map.painter(lo), extentOffset: map.painter(hi)),
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
        return RichPosition(paragraph: i, offset: para.alignedOffset(max(0, min(_map(i).paragraph(tp.offset), para.length))))
    }

    /// Start and end offsets of the visual line holding `pos`.
    public func lineBounds(_ pos: RichPosition, _ document: RichDocument) -> (start: Int, end: Int) {
        let i = max(0, min(pos.paragraph, count - 1))
        let para = document.paragraphs[i]
        if para.text.isEmpty { return (0, 0) }
        let g = geometry(i)
        let map = _map(i)
        let bound = g.painter.getLineBoundary(TextPosition(offset: map.painter(max(0, min(pos.offset, para.length)))))
        let r = (start: map.paragraph(bound.start), end: map.paragraph(bound.end))
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
    private func _paintShading(_ i: Int, _ canvas: any Canvas, _ document: RichDocument, part: PagePiece.Part = .all) {
        if part != .rules, let fill = document.paragraphs[i].style.fill, i < count {
            // The paragraph's own shading, text area wide.
            let g = geometry(i)
            let paint = Paint()
            paint.style = .fill
            paint.color = fill
            canvas.drawRect(Rect.fromLTWH(g.textLeft.rounded(), g.textTop.rounded(), g.textWidth.rounded(), g.painter.height.rounded()), paint)
        }
        if part != .text, let c = _cells[i], c.firstInRow, let ts = document.tableStyles[c.table] {
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
        // (For a row that parts over two pages, all its cells' with the
        // rules; its members' own pieces are their text alone.)
        var members = part == .text ? i ..< i : i ..< i + 1
        if part == .rules, let c = _cells[i] {
            var j = i
            while j < count, j < document.paragraphs.count, let d = _cells[j], d.table == c.table, d.row == c.row { j += 1 }
            members = i ..< j
        }
        for k in members {
            guard let c = _cells[k], let color = document.paragraphs[k].cell?.fill else { continue }
            let fill = Paint()
            fill.style = .fill
            fill.color = color
            let height = c.rowSpan > 1 ? c.rowHeight : c.ownRowHeight
            canvas.drawRect(Rect.fromLTWH(c.colLeft.rounded(), c.rowTop.rounded(), c.colWidth.rounded(), height.rounded()), fill)
        }
    }

    /// `theme.baselineShift` for paragraph `i`, in pixels of its first
    /// run's size.
    private func _baselineShift(_ i: Int, _ document: RichDocument) -> Double {
        guard theme.singleLineHeight != nil else { return 0 }
        let p = document.paragraphs[i]
        guard let run = p.runs.first else { return 0 }
        let k = theme.baselineShift(for: run.style, in: p.style)
        guard k != 0 else { return 0 }
        var size = run.style.fontSize ?? document.styles.resolve(p.style)?.char.fontSize
            ?? document.styles[RichNamedStyle.normalId]?.char.fontSize ?? theme.fontSize
        if fontScale != 1 { size = max(1, (size * fontScale).rounded()) }
        return k * _px(size)
    }

    /// The lines of paragraph `piece.paragraph` that `piece` holds, as a
    /// painter of their own, where they stand below the paragraph's first
    /// line, and whether they begin it — or nil when the piece is the
    /// whole paragraph (or the paragraph is one this does not take
    /// apart: a table cell's, one with a picture in it).
    ///
    /// For PowerPoint's columns. A piece is otherwise the whole paragraph
    /// seen through a window, which is exact while lines keep to their
    /// boxes; at a spacing under single they do not — the next line's
    /// ascenders stand in the last line's box, and showed as a row of
    /// specks under the foot of a column.
    private func _linesPainter(_ piece: PagePiece, _ document: RichDocument)
        -> (painter: TextPainter, top: Double, first: Bool, paragraph: RichParagraph)? {
        let i = piece.paragraph
        guard theme.singleLineHeight != nil, _cells[i] == nil, i >= _inline.count || _inline[i].isEmpty else { return nil }
        let g = geometry(i)
        let p = document.paragraphs[i]
        let from = piece.flowTop - g.textTop, to = piece.flowBottom - g.textTop
        let whole = g.painter.height
        guard from > 0.5 || to < whole - 0.5, !p.text.isEmpty else { return nil }
        let start = from <= 0.5 ? 0 : g.painter.getLineBoundary(g.painter.getPositionForOffset(Offset(1, from + 1))).start
        let end = to >= whole - 0.5 ? p.length : g.painter.getLineBoundary(g.painter.getPositionForOffset(Offset(1, to - 1))).end
        guard end > start else { return nil }
        var head = p
        _ = head.split(at: min(end, p.length))
        let lines = start > 0 ? head.split(at: start) : head
        let (span, inline, inserts) = _span(for: lines, at: nil, document, textWidth: g.textWidth)
        // (Only where the painter's text is the paragraph's own, offset
        // for offset: nothing put in for Word's line rules.)
        guard inline.isEmpty, inserts.isEmpty else { return nil }
        var align = Self._textAlign(p.style.alignment)
        if p.style.rightToLeft {
            switch p.style.alignment {
            case .left: align = .right
            case .right: align = .left
            default: break
            }
        }
        let painter = TextPainter(text: span, textAlign: align, textDirection: p.style.rightToLeft ? .rtl : .ltr)
        painter.layout(minWidth: g.textWidth, maxWidth: g.textWidth)
        let top = start == 0 ? 0 : g.painter.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dy
        return (painter, top, start == 0, lines)
    }

    /// The raised and lowered runs of `p`, drawn where they belong: each
    /// stretch of one on a line again in its own style, up by three
    /// tenths of the size it was shrunk from, or down by a fifth —
    /// PowerPoint's and Word's superscript and subscript. `painter` is
    /// the paragraph's (or its lines'), painted at `origin`, in which the
    /// runs hold their place unseen.
    private func _paintScripts(_ p: RichParagraph, _ painter: TextPainter, at origin: Offset,
                               _ canvas: any Canvas, _ document: RichDocument, map: _OffsetMap? = nil) {
        guard p.runs.contains(where: { $0.style.script != .normal }) else { return }
        let named = document.styles.resolve(p.style)
        let units = Array(p.text.utf16)
        var pos = 0
        for run in p.runs {
            let from = pos, to = min(units.count, pos + run.length)
            pos += run.length
            guard run.style.script != .normal, to > from else { continue }
            let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: document.styles[RichNamedStyle.normalId]?.char, scale: scale, fontScale: fontScale)
            // The size it was shrunk from (the style's is 65% of it).
            let full = (style.fontSize ?? 0) / 0.65
            // (Measured on PowerPoint's page: 7.0 pt up and 5.0 down at 24 pt.)
            let dy = run.style.script == .superscript ? -0.3 * full : 0.2 * full
            var a = from
            while a < to {
                // To the end of the run or of its line, whichever is first.
                // (The painter's offsets are the paragraph's but for what
                // the layout put in: `map`.)
                let line = painter.getLineBoundary(TextPosition(offset: map?.painter(a) ?? a))
                let b = max(a + 1, min(to, map?.paragraph(line.end) ?? line.end))
                let boxes = painter.getBoxesForSelection(TextSelection(baseOffset: map?.painter(a) ?? a,
                                                                       extentOffset: (map?.painter(b - 1) ?? b - 1) + 1))
                if let box = boxes.first {
                    let text = String(decoding: units[a ..< b], as: UTF16.self)
                    // At the face's own height, as the box it stood in unseen
                    // is: the two then share a baseline.
                    let plain = TextStyle(color: style.color, fontSize: style.fontSize, fontWeight: style.fontWeight,
                                          fontStyle: style.fontStyle, letterSpacing: style.letterSpacing,
                                          fontFeatures: style.fontFeatures, decoration: style.decoration,
                                          decorationColor: style.decorationColor, fontFamily: style.fontFamily,
                                          fontFamilyFallback: style.fontFamilyFallback)
                    let tp = TextPainter(text: TextSpan(text: text, style: plain), textDirection: p.style.rightToLeft ? .rtl : .ltr)
                    tp.layout(minWidth: 0, maxWidth: Double.infinity)
                    tp.paint(canvas, Offset(origin.dx + box.toRect().left, origin.dy + box.toRect().top + dy))
                    tp.dispose()
                }
                a = b
            }
        }
    }

    private func _paintParagraph(_ i: Int, _ canvas: any Canvas, _ document: RichDocument, part: PagePiece.Part = .all,
                                 lines: (painter: TextPainter, top: Double, first: Bool, paragraph: RichParagraph)? = nil) {
        let g = geometry(i)
        if let lines, !lines.first {
            // Lines from inside the paragraph: no marker, no rules — the text alone.
            let at = Offset(g.textLeft, g.textTop + lines.top + _baselineShift(i, document))
            lines.painter.paint(canvas, at)
            _paintScripts(lines.paragraph, lines.painter, at: at, canvas, document)
            return
        }
        if part != .text, let c = _cells[i], c.firstInRow {
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
                    paintEdges(d, bottomHere: d.rowSpan - 1 <= d.ghostRows, ownTop: true)
                    lastColumn = d.column
                }
                j += 1
            }
            var k = i - 1
            var seen: Set<Int> = []
            while k >= 0, let d = _cells[k], d.table == c.table {
                if d.rowSpan > 1, d.row < c.row, d.row + d.rowSpan > c.row, !seen.contains(d.column) {
                    seen.insert(d.column)
                    paintEdges(d, bottomHere: d.row + d.rowSpan - 1 <= c.row + c.ghostRows, ownTop: false)
                }
                k -= 1
            }
        }
        if part == .rules { return }
        if theme.wordRules, i < document.paragraphs.count, document.paragraphs[i].style.lineCollapsed, document.paragraphs[i].image == nil { return }
        if let image = document.paragraphs[i].image, let box = imageRect(i) {
            if _decoded[image.id] == nil { _paintOutline(image, box, canvas) }
            if let decoded = _decoded[image.id] {
                _drawPicture(decoded, image, box, canvas)
            } else if let inside = _textBox(image, document), let text = image.textBox {
                // A text box: its text, set inside it.
                canvas.save()
                canvas.translate(box.left + _px(text.insetLeft), box.top + _px(text.insetTop))
                inside.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: inside.document,
                                    selection: nil, caret: nil)
                canvas.restore()
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
            if let wl = _wordList(p, document) {
                // As Word sets it: from the first line's offset, or up to
                // it where the level's numbers are set to the right.
                let marker = _marker(i, p, document, label: label, strut: g.painter.strutStyle)
                var at = g.textLeft + _px(wl.first)
                // (Centred or set right, the number goes with its line:
                // "第一章 总则" is centred whole. The box it stands in
                // is the first thing on that line.)
                if p.style.alignment == .center || p.style.alignment == .right, _lead(i) > 0,
                   let first = g.painter.computeLineMetrics().first {
                    at = g.textLeft + first.left
                }
                marker.paint(canvas, Offset(wl.format?.justification == "right" ? at - marker.width : at, g.inkTop))
                marker.dispose()
            } else {
            var markerChar = p.runs[0].style
            if let c = p.style.bulletColor { markerChar.color = c }
            if let f = p.style.bulletFontFamily { markerChar.fontFamily = f }
            if let k = p.style.bulletScale {
                markerChar.fontSize = (markerChar.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize) * k
            }
            let markerStyle = theme.textStyle(for: markerChar, in: p.style, named: _named(p, document), normal: _normalChar(document), scale: scale, fontScale: fontScale)
            // (On the paragraph's strut, so that the marker's baseline
            // is the text's.)
            let marker = TextPainter(text: TextSpan(text: label, style: markerStyle),
                                     textAlign: .right, textDirection: .ltr, strutStyle: g.painter.strutStyle)
            let slot = _px(theme.listIndent)
            // On the first line's baseline: a marker of another size (a
            // bullet at 80%) has its own, higher or lower than the text's.
            func top() -> Double {
                g.textTop + _baselineShift(i, document) + g.painter.computeDistanceToActualBaseline(.alphabetic)
                    - marker.computeDistanceToActualBaseline(.alphabetic)
            }
            if !theme.markersAtHang, let own = _listIndents(p, document), own.hanging > 0 {
                // Where the file hangs it: the number starts that far
                // back from the text, as Word sets it.
                marker.textAlign = .left
                marker.layout(minWidth: 0, maxWidth: max(1, slot * 8))
                let hang = g.textLeft - _px(own.hanging)
                marker.paint(canvas, Offset(min(hang, g.textLeft - marker.width), top()))
            } else if theme.markersAtHang {
                // At the hang, and never over the text: a bullet whose hang
                // is at the text (indent 0) sits just before it instead.
                marker.layout(minWidth: 0, maxWidth: max(1, slot * 4))
                let hang = g.textLeft - slot + _px(p.style.firstLineIndent)
                marker.paint(canvas, Offset(min(hang, g.textLeft - marker.width - 4), g.inkTop))
            } else if theme.wordRules, !document.readFromFile {
                // No level of its own yet: where the file it is saved to
                // will hang it, half the indent back from the text.
                marker.textAlign = .left
                marker.layout(minWidth: 0, maxWidth: max(1, slot * 8))
                marker.paint(canvas, Offset(min(g.textLeft - slot / 2, g.textLeft - marker.width), top()))
            } else {
                marker.layout(minWidth: slot - 8, maxWidth: slot - 8)
                marker.paint(canvas, Offset(g.textLeft - slot, g.inkTop))
            }
            marker.dispose()
            }
        }
        let textAt = Offset(g.textLeft, g.inkTop + _baselineShift(i, document))
        if let lines {
            lines.painter.paint(canvas, textAt)
        } else if !_paintScaled(i, g, canvas, document) {
            g.painter.paint(canvas, textAt)
        }
        _paintScripts(lines?.paragraph ?? document.paragraphs[i], lines?.painter ?? g.painter, at: textAt, canvas, document,
                      map: lines == nil ? _map(i) : nil)
        if i < _leaders.count, !_leaders[i].isEmpty {
            // A leader fills its tab: the character over and over, up to
            // the text the tab leads to.
            let p = document.paragraphs[i]
            let named = _named(p, document)
            let map = _map(i)
            for leader in _leaders[i] {
                guard let box = g.painter.getBoxesForSelection(
                    TextSelection(baseOffset: map.painter(leader.offset), extentOffset: map.painter(leader.offset) + 1), boxHeightStyle: .max).first,
                      box.right - box.left > 1 else { continue }
                var at = 0
                var run = p.runs[0].style
                for r in p.runs { if leader.offset < at + r.length { run = r.style; break }; at += r.length }
                let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            gridPitch: p.style.eastAsian["w:snapToGrid"] == "0" ? nil : _grid(i, document).pitch)
                let one = TextPainter(text: TextSpan(text: leader.fill, style: style), textDirection: .ltr)
                one.layout(minWidth: 0, maxWidth: 10_000)
                let n = Int(((box.right - box.left) / max(0.5, one.width)).rounded(.down))
                one.dispose()
                guard n > 0 else { continue }
                let fill = TextPainter(text: TextSpan(text: String(repeating: leader.fill, count: n), style: style),
                                       textDirection: .ltr, strutStyle: g.painter.strutStyle)
                fill.layout(minWidth: 0, maxWidth: 10_000_000)
                fill.paint(canvas, Offset(g.textLeft + box.right - fill.width, g.inkTop + box.top))
                fill.dispose()
            }
        }
        if i < _inline.count, !_inline[i].isEmpty, let all = g.painter.inlinePlaceholderBoxes {
            let boxes = all.dropFirst(_lead(i))
            for (k, box) in boxes.enumerated() where k < _inline[i].count {
                let image = _inline[i][k]
                var rect = box.toRect().shift(Offset(g.textLeft, g.inkTop))
                if theme.wordRules, let float = image.float, !float.takesRoom {
                    // A floating object, from its paragraph by its place:
                    // a picture, or a text box's text; one that cannot
                    // be drawn is left out.
                    rect = _floatRect(float, image, g, i)
                    if _decoded[image.id] == nil {
                        _paintOutline(image, rect, canvas)
                        if let inside = _textBox(image, document), let text = image.textBox {
                            canvas.save()
                            canvas.translate(rect.left + _px(text.insetLeft), rect.top + _px(text.insetTop))
                            inside.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000),
                                                document: inside.document, selection: nil, caret: nil)
                            canvas.restore()
                        }
                        continue
                    }
                }
                let paint = Paint()
                if let decoded = _decoded[image.id] {
                    _drawPicture(decoded, image, rect, canvas)
                } else if let inside = _textBox(image, document), let text = image.textBox {
                    canvas.save()
                    canvas.translate(rect.left + _px(text.insetLeft), rect.top + _px(text.insetTop))
                    inside.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000),
                                        document: inside.document, selection: nil, caret: nil)
                    canvas.restore()
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

    // MARK: Headers and footers
    //
    // A file's header or footer is paragraphs like the body's
    // (`RichDocument.headerFooters`), laid out by a layout of its own at
    // the page's text width, with the page fields filled in for the page.
    // Its height matters to the body: Word starts the text under a
    // header taller than the top margin, and ends it above a footer
    // taller than the bottom one.

    private struct _HeaderFooter {
        let layout: RichLayout
        let document: RichDocument
        var height: Double { layout.totalHeight }
    }

    /// Set on a header's or footer's own layout: its framed paragraphs
    /// (a page number in a frame, as Word's "Insert Page Number" makes
    /// them) float — they take no room, and stand where the frame says,
    /// measured from the text's left, the margins `frameMargins` wide
    /// (points) on either side of it.
    public var floatsFrames = false
    public var frameMargins: (left: Double, right: Double) = (0, 0)

    private var _headerFooterCache: [String: _HeaderFooter] = [:]
    /// Text boxes' own layouts, by attachment.
    private var _textBoxCache: [String: _HeaderFooter] = [:]

    /// A text box's text, laid out at the box's width inside its insets.
    private func _textBox(_ image: ImageAttachment, _ document: RichDocument) -> _HeaderFooter? {
        guard theme.wordRules, let box = image.textBox else { return nil }
        let key = "\(image.id)|\(image.width)|\(scale)|\(box.hashValue)"
        if let hit = _textBoxCache[key] { return hit }
        var sub = RichDocument(paragraphs: box.paragraphs)
        sub.styles = document.styles
        sub.listFormats = document.listFormats
        sub.usesEastAsianLayout = document.usesEastAsianLayout
        sub.characterSpacingControl = document.characterSpacingControl
        sub.kernsPunctuation = document.kernsPunctuation
        sub.balancesSpaceWidth = document.balancesSpaceWidth
        sub.compatibilityMode = document.compatibilityMode
        sub.hangsHalf = document.hangsHalf
        sub.defaultLangXML = document.defaultLangXML
        sub.htmlAutoSpacing = document.htmlAutoSpacing
        sub.defaultTabStop = document.defaultTabStop
        let layout = RichLayout(theme: theme, paragraphCount: sub.paragraphs.count)
        layout.scale = scale
        layout.width = max(1, _px(image.width - box.insetLeft - box.insetRight))
        layout.ensureLaidOut(sub)
        let made = _HeaderFooter(layout: layout, document: sub)
        if _textBoxCache.count > 256 { _textBoxCache.removeAll() }
        _textBoxCache[key] = made
        return made
    }

    /// Where a floating object stands, in the layout's own space, given
    /// the paragraph it is anchored to: by its offsets from the column
    /// or the paragraph, or set left, centre or right in the column (or
    /// the page, where `frameMargins` says how far that reaches).
    private func _floatRect(_ float: ImageFloat, _ image: ImageAttachment, _ g: ParagraphGeometry, _ i: Int) -> Rect {
        let w = _px(image.width), h = _px(image.height)
        // The band it is placed in, from the paragraph's column edge.
        let column = _flowWidth(i)
        var bandLeft = g.textLeft - _textLeftInColumn(i), bandWidth = column
        if float.horizontalFrom == "page" {
            let setup = _setup(ofParagraph: i)
            let margins = floatsFrames ? frameMargins : (setup.marginLeft + setup.gutter, setup.marginRight)
            bandLeft -= _px(margins.0)
            bandWidth += _px(margins.0 + margins.1)
        }
        var x: Double
        switch float.horizontalAlign {
        case "center": x = bandLeft + (bandWidth - w) / 2
        case "right", "outside": x = bandLeft + bandWidth - w
        case "left", "inside": x = bandLeft
        default: x = bandLeft + _px(float.x)
        }
        if float.horizontalAlign == nil, float.horizontalFrom == "character" { x = g.textLeft + _px(float.x) }
        let pushed = i < _floatPush.count ? _floatPush[i] : 0
        let y = g.textTop - pushed + (float.verticalAlign == nil && ["paragraph", "line"].contains(float.verticalFrom) ? _px(float.y) : 0)
        let box = Rect.fromLTWH(x + (_floatShift[image.id] ?? 0), y + (_floatShiftY[image.id] ?? 0), w, h)
        // (Turned a quarter, about its centre: as tall as it is wide.
        // Word's print of zh-37b6536f puts a photo of 236.8 by 222.4
        // turned 90° in a box of 222.4 by 236.8 with the same centre.)
        guard Self._quarterTurned(image) else { return box }
        let c = box.center
        return Rect.fromLTWH(c.dx - h / 2, c.dy - w / 2, h, w)
    }

    /// Whether a floating picture is turned by an odd number of quarters.
    static func _quarterTurned(_ image: ImageAttachment) -> Bool {
        let r = (image.rotation.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
        return abs(r - 90) < 1 && image.float != nil
    }

    /// A decoded picture into its box, turned as the file turns it: the
    /// box is the turned one, and the picture is drawn unturned about
    /// the same centre and then turned.
    private func _drawPicture(_ decoded: Image, _ image: ImageAttachment, _ box: Rect, _ canvas: any Canvas) {
        let src = Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height))
        guard image.float != nil, abs(image.rotation) > 0.01 else {
            canvas.drawImageRect(decoded, src, box, Paint())
            return
        }
        let c = box.center
        let (w, h) = Self._quarterTurned(image) ? (box.height, box.width) : (box.width, box.height)
        canvas.save()
        canvas.translate(c.dx, c.dy)
        canvas.rotate(image.rotation * Double.pi / 180)
        canvas.drawImageRect(decoded, src, Rect.fromLTWH(-w / 2, -h / 2, w, h), Paint())
        canvas.restore()
    }

    /// Whether paragraph `i` holds nothing but floating objects: its
    /// line is empty, and its objects stand where its anchor puts them.
    private func _anchorsOnly(_ i: Int, _ document: RichDocument) -> Bool {
        guard i < document.paragraphs.count, _cells[i] == nil else { return false }
        let p = document.paragraphs[i]
        if let image = p.image { return image.float.map { !$0.takesRoom } ?? false }
        return !p.inlineImages.isEmpty && !p.text.isEmpty && p.text.unicodeScalars.allSatisfy { $0.value == 0xFFFC }
            && p.inlineImages.values.allSatisfy { $0.float.map { !$0.takesRoom } ?? false }
    }

    /// The pictures paragraph `i` anchors that text wraps round (Word's
    /// square, tight and through wrapping, placed from the paragraph):
    /// each one's id and box in the flow, x from the column's edge.
    private func _wrapBoxes(_ i: Int) -> [(id: String, rect: Rect)] {
        guard theme.wordRules, i < count, _cells[i] == nil, _painters[i] != nil else { return [] }
        var images: [ImageAttachment] = []
        if i < _floatImages.count, let image = _floatImages[i] { images.append(image) }
        if i < _inline.count { images += _inline[i] }
        let g = geometry(i)
        var out: [(id: String, rect: Rect)] = []
        for image in images {
            guard let float = image.float, float.wraps, !float.takesRoom, float.verticalAlign == nil,
                  ["paragraph", "line"].contains(float.verticalFrom), float.horizontalFrom != "page", !image.data.isEmpty else { continue }
            out.append((image.id, _floatRect(float, image, g, i)))
        }
        return out
    }

    /// How far paragraph `i`'s text starts from its column's left edge
    /// (its indents; a cell's place is left out of it).
    private func _textLeftInColumn(_ i: Int) -> Double {
        guard i < _cells.count, _cells[i] == nil else { return 0 }
        return _textLeft[i]
    }
    private var _headerFooterSource: [RichHeaderFooter] = []

    /// A page number as the document writes them.
    private func _pageNumber(_ n: Int, _ document: RichDocument) -> String {
        switch document.pageNumberFormat {
        case "lowerRoman": return ListNumberFormat.lowerRoman.string(n)
        case "upperRoman": return ListNumberFormat.upperRoman.string(n)
        case "lowerLetter": return ListNumberFormat.lowerLetter.string(n)
        case "upperLetter": return ListNumberFormat.upperLetter.string(n)
        case "numberInDash": return "- \(n) -"
        default: return String(n)
        }
    }

    /// The section page `p` is of, as `RichHeaderFooter.section` counts
    /// them, and whether that is the last (the document's own).
    private func _headerFooterSection(_ p: Int) -> (index: Int, last: Bool) {
        let last = max(0, _sectionSetups.count - 1)
        guard _sectionSetups.count > 1, p >= 0, p < _pageSection.count else { return (last, true) }
        return (_pageSection[p], _pageSection[p] >= last)
    }

    /// Whether page `p` is the first of a section that gives its first
    /// page a header and footer of its own.
    private func _titlePage(_ p: Int, _ document: RichDocument) -> Bool {
        let section = _headerFooterSection(p)
        guard p == 0 || _headerFooterSection(p - 1).index != section.index else { return false }
        return section.last ? document.titlePage : pageSetup(forPage: p).titlePage
    }

    /// The file's header or footer for page `p`, laid out — or nil where
    /// the page has none, or the editor's own one-line text stands (it
    /// was edited, or holds tabs, whose stops only that form sets).
    private func _headerFooter(_ kind: KeptHeaderFooter.Kind, page p: Int, _ document: RichDocument,
                               pageCount: Int? = nil) -> _HeaderFooter? {
        guard theme.wordRules, !document.headerFooters.isEmpty else { return nil }
        if document.headerFooters != _headerFooterSource {
            for hf in _headerFooterCache.values { hf.layout.invalidateAll() }
            _headerFooterCache = [:]
            _headerFooterSource = document.headerFooters
        }
        let number = p + (document.pageNumberStart ?? 1)
        let type = _titlePage(p, document) ? "first" : document.evenAndOddHeaders && number % 2 == 0 ? "even" : "default"
        let section = _headerFooterSection(p)
        guard let source = document.headerFooters.first(where: {
            $0.kind == kind && $0.type == type && ($0.section == nil || $0.section == section.index)
        }) else { return nil }
        if type == "default", section.last {
            // (One an earlier section named has no line of the editor's.)
            let own = kind == .header ? document.header : document.footer
            if let kept = document.keptHeaderFooters.first(where: { $0.kind == kind && $0.type == type })?.text {
                if kept != own || own.contains("\t" as Character) { return nil }
            }
        }
        let setup = pageSetup(forPage: p)
        let shown = _pageNumber(number, document)
        let count = String(pageCount ?? self.pageCount)
        let key = "\(kind.rawValue)|\(type)|\(section.index)|\(shown)|\(count)|\(setup.contentWidth)|\(setup.lineGridPitch ?? 0)|\(scale)"
        if let hit = _headerFooterCache[key] { return hit }
        // The paragraphs with this page's number and the count in their
        // fields — and those of the text boxes among them, where a page
        // number often is.
        func filled(_ source: [RichParagraph]) -> [RichParagraph] {
            var paragraphs = source
            for k in paragraphs.indices {
                let old = paragraphs[k]
                var fresh = old
                if old.runs.contains(where: { $0.style.field != nil }) {
                    var text = ""
                    var runs: [Run] = []
                    var at = old.text.utf16.startIndex
                    var lastField: String? = nil
                    for run in old.runs {
                        let end = old.text.utf16.index(at, offsetBy: run.length)
                        var piece = String(old.text[at ..< end])
                        at = end
                        if let field = run.style.field {
                            // (One number per field, however many runs its old result was in.)
                            let word = field.trimmingWhitespace().uppercased().split(separator: " ").first.map(String.init) ?? ""
                            piece = lastField == field ? "" : (word == "PAGE" ? shown : count)
                        }
                        lastField = run.style.field
                        guard !piece.isEmpty else { continue }
                        text += piece
                        runs.append(Run(length: piece.utf16.count, style: run.style))
                    }
                    fresh = RichParagraph(text: text, runs: runs.isEmpty ? nil : runs, style: old.style)
                    fresh.cell = old.cell
                    fresh.inlineImages = old.inlineImages
                }
                if var image = fresh.image, let box = image.textBox {
                    image.textBox?.paragraphs = filled(box.paragraphs)
                    fresh.image = image
                }
                for (id, var image) in fresh.inlineImages {
                    guard let box = image.textBox else { continue }
                    image.textBox?.paragraphs = filled(box.paragraphs)
                    fresh.inlineImages[id] = image
                }
                paragraphs[k] = fresh
            }
            return paragraphs
        }
        let paragraphs = filled(source.paragraphs)
        var sub = RichDocument(paragraphs: paragraphs)
        sub.styles = document.styles
        sub.listFormats = document.listFormats
        sub.tableColumns = document.tableColumns
        sub.tableStyles = document.tableStyles
        sub.lineGridPitch = section.last ? document.lineGridPitch : setup.lineGridPitch
        sub.characterGridSpace = section.last ? document.characterGridSpace : setup.characterGridSpace
        sub.usesEastAsianLayout = document.usesEastAsianLayout
        sub.characterSpacingControl = document.characterSpacingControl
        sub.kernsPunctuation = document.kernsPunctuation
        sub.balancesSpaceWidth = document.balancesSpaceWidth
        sub.compatibilityMode = document.compatibilityMode
        sub.hangsHalf = document.hangsHalf
        sub.defaultLangXML = document.defaultLangXML
        sub.htmlAutoSpacing = document.htmlAutoSpacing
        sub.defaultTabStop = document.defaultTabStop
        let layout = RichLayout(theme: theme, paragraphCount: sub.paragraphs.count)
        layout.scale = scale
        layout.floatsFrames = true
        layout.frameMargins = (setup.marginLeft + setup.gutter, setup.marginRight)
        layout.width = _px(setup.contentWidth)
        layout.ensureLaidOut(sub)
        let made = _HeaderFooter(layout: layout, document: sub)
        _headerFooterCache[key] = made
        return made
    }

    /// How far below the paper's top page `p`'s text starts, and how far
    /// above its bottom it ends (pixels): the margins, or the header's
    /// and the footer's extent where that is more.
    private func _bodyInsets(page p: Int, _ document: RichDocument) -> (top: Double, bottom: Double) {
        let setup = pageSetup(forPage: p)
        var top = _px(setup.marginTop), bottom = _px(setup.marginBottom)
        if let header = _headerFooter(.header, page: p, document, pageCount: 1) {
            top = max(top, _px(setup.headerDistance) + header.height)
        }
        if let footer = _headerFooter(.footer, page: p, document, pageCount: 1) {
            bottom = max(bottom, _px(setup.footerDistance) + footer.height)
        }
        return (top, bottom)
    }

    /// Running header (left) and footer (centred), fields filled per
    /// page, in Normal's face: the header's top and the footer's bottom
    /// at the page setup's distances from the paper's edges, as Word
    /// places them. The file's own, where it has them, as it wrote them.
    private func _paintHeaderFooter(_ p: Int, _ canvas: any Canvas, _ document: RichDocument) {
        guard pageSetup != nil else { return }
        let setup = pageSetup(forPage: p)
        let rect = pageRect(p)
        let n = pageCount
        var drawn: Set<KeptHeaderFooter.Kind> = []
        for kind in [KeptHeaderFooter.Kind.header, .footer] {
            guard let hf = _headerFooter(kind, page: p, document) else {
                // (A first or even page that names none shows none.)
                if theme.wordRules, document.headerFooters.contains(where: { $0.kind == kind }),
                   _titlePage(p, document) { drawn.insert(kind) }
                continue
            }
            let top = kind == .header ? rect.top + _px(setup.headerDistance) : rect.bottom - _px(setup.footerDistance) - hf.height
            canvas.save()
            canvas.translate(rect.left + _pxMarginLeft(p), top)
            hf.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: hf.document,
                            selection: nil, caret: nil)
            canvas.restore()
            drawn.insert(kind)
        }
        let style = theme.textStyle(for: CharStyle(color: theme.textColor.withOpacity(0.7)),
                                    in: .body, named: document.styles[RichNamedStyle.normalId], scale: scale)
        let left = _pxMarginLeft(p)
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
        if !document.header.isEmpty, !drawn.contains(.header) {
            line(document.header, align: .left, top: rect.top + _px(setup.headerDistance))
        }
        if !document.footer.isEmpty, !drawn.contains(.footer) {
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

    /// The lines a table row parted over a page's foot is closed with
    /// there and opened with on the next page, as Word draws them: the
    /// table's inside line, across the table, wherever a piece of the
    /// row's rules stops short of the row's own top or bottom.
    private func _paintPartedRules(_ piece: PagePiece, _ canvas: any Canvas, _ document: RichDocument) {
        guard theme.wordRules, !piece.repeated, piece.part != .text, let c = _cells[piece.paragraph], c.firstInRow else { return }
        let ts = document.tableStyles[c.table]
        guard ts?.edges?.insideH ?? ts?.borders ?? true else { return }
        // (And over a row that starts a page under cells merged down
        // from the page before, which have no top of their own there.)
        let parted = piece.part == .rules && !piece.inner
        let opens = (parted && piece.flowTop > c.rowTop + 0.5) || (piece.pageY < 0.01 && c.row > 0 && piece.flowTop < c.rowTop + 0.5)
        let closes = parted && piece.flowBottom < c.rowTop + c.ownRowHeight - 0.5
        guard opens || closes else { return }
        let widths = _columnWidths[c.table] ?? []
        let left = (c.colLeft - widths.prefix(c.column).reduce(0, +)).rounded()
        let right = (left + widths.reduce(0, +)).rounded()
        let stroke = Paint()
        stroke.style = .stroke
        stroke.strokeWidth = max(1, _px(ts?.edgeWidths["insideH"] ?? ts?.borderWidth ?? 0.5).rounded())
        stroke.color = ts?.borderColor ?? theme.textColor.withOpacity(0.6)
        let half = stroke.strokeWidth / 2
        if opens { canvas.drawLine(Offset(left, piece.flowTop + half), Offset(right, piece.flowTop + half), stroke) }
        if closes { canvas.drawLine(Offset(left, piece.flowBottom - half), Offset(right, piece.flowBottom - half), stroke) }
    }

    /// Every visible paragraph, page by page and column by column: its
    /// table row's shading only (`shading`), or everything else.
    private func _paintFlow(_ canvas: any Canvas, visible: Rect, document: RichDocument, shading: Bool) {
        if isPaged {
            let firstPage = page(atCanvasY: visible.top)
            let lastPage = page(atCanvasY: visible.bottom)
            for p in firstPage ... lastPage {
                let pageTop = pageRect(p).top + _pxMarginTop(p)
                for column in 0 ..< _columns {
                    let slot = p * _columns + column
                    guard _pages.indices.contains(slot) else { continue }
                    let left = _pxMarginLeft(p) + Double(column) * _pxColumnStride(p)
                    // One column clips to its own width; a lone column keeps
                    // the page, so a table wider than the text can still show.
                    let clipL = _columns > 1 ? left - 1 : 0
                    let clipR = _columns > 1 ? left + _pxColumnW(p) + 1 : _pxPageW(p)
                    for piece in _pages[slot] {
                        let top = pageTop + piece.pageY
                        let bottom = top + piece.height
                        if bottom < visible.top || top > visible.bottom { continue }
                        canvas.save()
                        let lines = shading ? nil : _linesPainter(piece, document)
                        // A paragraph shown whole that carries a floating
                        // object is not cut to its own lines: the object
                        // stands where its anchor puts it, below or above
                        // them — four photos anchored to empty paragraphs
                        // were each a strip one line tall (zh-37b6536f).
                        let i = piece.paragraph
                        let whole = piece.flowTop <= _tops[i] + 0.5 && piece.flowBottom >= _tops[i] + _heights[i] - 0.5
                        let floats = theme.wordRules && !shading && whole && piece.part == .all
                            && ((i < _floatImages.count && _floatImages[i] != nil)
                                || (i < _inline.count && _inline[i].contains { $0.float.map { !$0.takesRoom } ?? false }))
                        if lines != nil || floats {
                            // Its own lines and no others: nothing to cut off above or below.
                            canvas.clipRect(Rect.fromLTRB(clipL, top - 10_000, clipR, bottom + 10_000))
                        } else {
                            // The window moves with the text: a paragraph drawn
                            // above its line box (`baselineShift`) would
                            // otherwise show the tops of its next line here.
                            let dy = shading ? 0 : _baselineShift(piece.paragraph, document)
                            canvas.clipRect(Rect.fromLTRB(clipL, top + dy, clipR, bottom + dy))
                        }
                        canvas.translate(left, top - piece.flowTop)
                        if shading { _paintShading(piece.paragraph, canvas, document, part: piece.part) } else {
                            _paintParagraph(piece.paragraph, canvas, document, part: piece.part, lines: lines)
                            _paintPartedRules(piece, canvas, document)
                        }
                        lines?.painter.dispose()
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
