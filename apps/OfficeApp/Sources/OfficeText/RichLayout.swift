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

import Flutter
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
    /// A right-to-left run uses its complex-script face (`w:cs`), which
    /// may need different fallbacks from a Latin metric clone. nil keeps
    /// that face's name and metrics instead of applying the Latin resolver.
    public var complexFaceResolver: ((String?) -> RichResolvedFace?)? = nil
    /// A complex-script face Word draws its digits in (an installed Arabic or Hebrew face), not the run's Latin one.
    public var complexFaceKeepsDigits: ((String) -> Bool)? = nil
    /// A Latin family's average character width in ems, by the name
    /// the document uses (nil: half an em). Word's automatic space
    /// between an ideograph and a Latin letter or digit is a quarter of
    /// this and the ideograph face's half em together — 0.225 em beside
    /// Times New Roman, 0.275 beside Courier New.
    public var averageCharWidth: ((String?) -> Double)? = nil
    /// A symbol face's characters as the Unicode glyphs they show, for
    /// drawing: a run in Wingdings 2 says "£" (`w:sym w:char="00A3"`) for
    /// a box. Character for character, so offsets hold; the document keeps
    /// what it said. Nil leaves the text as it is.
    public var symbolGlyphs: ((String?, String) -> String)? = nil
    /// … and such a glyph's advance in the symbol face, in ems, where
    /// the stand-in's differs.
    public var symbolAdvance: ((String?, Character) -> Double?)? = nil
    /// Families tried, in order, for a character the run's own family
    /// lacks. Process-wide rather than per theme: it answers "which faces did
    /// this app load for coverage", which is one fact, and an app builds a
    /// theme in many places. Empty leaves the platform's own fallback — all
    /// there is on macOS and in the browser, and nothing at all on Linux,
    /// where a ⌘ in a Liberation run otherwise draws as a missing glyph and
    /// lays its line out a pixel shorter than everywhere else.
    public nonisolated(unsafe) static var glyphFallback: [String] = []
    /// Whether Thai text breaks only where it has spaces, as Word for Mac
    /// sets it (see `_span`); the engine otherwise breaks it by word.
    public nonisolated(unsafe) static var thaiBreaksAtSpaces = false
    /// The shapes Word's fallback sets in Segoe UI Symbol where the run's
    /// Latin face has none — Times New Roman, Arial, Calibri — and whose
    /// ascent stands their line taller. Word for Mac's (lab `picln`):
    /// ◇ ◆ ◎ ★ ☆. Word for Windows sets "◎" in Cambria Math, which lifts
    /// nothing (lab e6p, zh-e68a2f57's package): an app printing as
    /// Windows takes it out.
    public nonisolated(unsafe) static var segoeSymbolShapes: Set<UInt32> = [0x25C7, 0x25C6, 0x25CE, 0x2605, 0x2606, 0x274F]
    /// Shapes Word for Windows sets in Cambria Math where the run's Latin face has none
    /// (see `_holdsSegoeGlyph`'s caller): they stand the line at Cambria Math's height.
    public nonisolated(unsafe) static var cambriaMathShapes: Set<UInt32> = [0x25B8]
    /// Pages break as Word for Windows breaks them where it differs from
    /// Word for Mac (OFFICE_WORD_FONTS=windows): an "at least" line that
    /// stands at its minimum ties on the foot as an exact line does.
    public nonisolated(unsafe) static var wordWindowsPages = false
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
    /// Latin text parted at spaces and after hyphens alone, as Office
    /// parts it — not after a slash or a closing bracket, where the
    /// engine, by Unicode's rules, may: PowerPoint keeps
    /// "PROGRAMMES/R200" and ".../articles/#articles-by-..." whole on
    /// their lines. Implied by `wordRules`; on alone for slides.
    public var officeLatinBreaks = false
    /// Each Latin character's advance snapped to this grid, in points:
    /// PowerPoint's print sets glyphs on an eighth of a point (Arial's
    /// "d" at 32pt is 17.797 wide and set 17.75, its "S" 21.344 and set
    /// 21.375), and a line that fits there by a hair can be a hair too
    /// long at the faces' own widths. nil for the faces' own.
    public var advanceGrid: Double? = nil

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

    /// Word raises a superscript by the face's own OS/2 offset when that is
    /// small (lab sup1: Cambria 0.246, Georgia 0.265, Palatino 0.273 ...), and
    /// by 0.355 em otherwise (Times, Calibri, Arial, Verdana, Tahoma, Malgun).
    @inline(never)
    static func superscriptRaise(_ family: String?) -> Double {
        switch family?.lowercased() ?? "" {
        case "cambria": return 0.246
        case "book antiqua": return 0.242
        case "georgia": return 0.265
        case "sylfaen": return 0.283
        case "palatino linotype": return 0.273
        default: return 0.355
        }
    }

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
    public func baselineShift(for style: CharStyle, in paragraph: RichParagraphStyle, depth forced: Double? = nil) -> Double {
        guard let single = singleLineHeight, paragraph.lineHeightPoints == nil else { return 0 }
        let multiple = max(0.1, paragraph.lineSpacing - lineSpacingReduction)
        // (Over single, PowerPoint shares the extra out above and below
        // as the engine does — 0.70 of it above the first line at 150% in
        // tdf137367's 40 pt Calibri, 0.72 in bug68703's 11 pt cells, the
        // engine's own share 0.75; all of it above had them 7.3 and 1.9
        // pt low.)
        let name = style.fontFamily ?? fontFamily
        let own = forced ?? name.flatMap { ownDescentShare?($0) }
        if exactLinesAsPowerPoint, multiple != 1 {
            // PowerPoint for Windows, labs p3lp and p3lu (Arial, Calibri, Courier
            // New, Times New Roman, Cambria, Segoe UI, MS Gothic at 18 and 32 pt,
            // 80% to 200%, in a box, a shape and under a shrink's reduction): a
            // line's foot (its baseline to its bottom) is a quarter of the line
            // and K, K being 0.013 less 0.07 of the face's depth, or its single
            // line's foot less 0.3 where that is more (Courier New's). Over
            // single that is the foot; under single, no more than single's own
            // (the face's depth of its 1.2 size) — Arial's has no lift, Calibri's
            // is under 90%, Courier New's at every spacing.
            let family = name.map { fontFamilyResolver?($0) ?? $0 }
            let drawn = forced ?? descentShare(family: family, bold: style.bold, italic: style.italic)
            let depth = own ?? drawn
            let line = multiple * single
            let natural = single * depth
            var foot = 0.25 * line + max(0.013 - 0.07 * depth, natural - 0.25 * single)
            if multiple < 1 { foot = min(foot, natural) }
            let shift = line * drawn - foot
            // (Unsaid spacing under a reduction keeps its floor: three fifths of
            // a single line down.)
            if multiple < 1, paragraph.lineSpacingUnstated, lineSpacingReduction > 0 {
                return max(shift, single * (0.6 - multiple * (1 - drawn)))
            }
            return shift
        }
        if multiple > 1, own == nil, let share = extraAboveShare {
            // That share of the extra above the first baseline, the rest
            // below, against the engine's share by the drawn face's ascent
            // and descent. (Not a face with a depth of its own: Courier
            // New's and Poppins' lines kept to it, TextFittingStored's
            // 150% and master-slides' 110% went +0.40 and +0.27.)
            let family = name.map { fontFamilyResolver?($0) ?? $0 }
            let drawn = forced ?? descentShare(family: family, bold: style.bold, italic: style.italic)
            return single * (multiple - 1) * (share - (1 - drawn))
        }
        guard multiple < 1 || own != nil else { return 0 }
        let family = name.map { fontFamilyResolver?($0) ?? $0 }
        let drawn = forced ?? descentShare(family: family, bold: style.bold, italic: style.italic)
        // (The face the text asks for, where its stand-in is not its
        // clone, keeps its own depth below the baseline: `ownDescentShare`.)
        let below = own ?? drawn
        // Under a spacing of its own below single, a shrink-to-fit's
        // reduction (`lineSpacingReduction`) scales the whole line,
        // baseline and all: lo-3columns' 90% less 20% stands its first
        // baseline 9.5 pt down at 15 pt, where taking it all off above
        // gave 8.7 and set its later lines a point high. From single, it
        // comes off above as the paragraph's own does (font-scale's 100%
        // less 20%, its lines where PowerPoint's are so and a point low
        // scaled).
        let spacing = paragraph.lineSpacing
        if spacing < 1, multiple < spacing {
            return single * (spacing - below) * multiple / spacing - multiple * single * (1 - drawn)
        }
        // (A shrink-to-fit's reduction of a spacing said nowhere comes off
        // above no further than three fifths of a single line down: 20%
        // off stands the first baseline 0.72 of the size under the text's
        // top in PowerPoint's print, eight boxes of 18 to 36 pt bounding
        // it to 0.717–0.721 (bug62513's lists, ecodesign's, customGeo's),
        // where all of it off above put it at 0.696, a point high in five;
        // 10% off, 0.816, is above the floor. A stated 100% takes it all
        // off above, lo-font-scale's lines where PowerPoint's are so, and
        // so does a spacing under single with no reduction, tdf157740's.)
        if multiple < 1, paragraph.lineSpacingUnstated, lineSpacingReduction > 0 {
            return max(single * (multiple * drawn - below), single * (0.6 - multiple * (1 - drawn)))
        }
        if multiple < 1 { return single * (multiple * drawn - below) }
        return multiple * single * (drawn - below)
    }

    /// The share of a face's single line below its baseline, by the
    /// name the text asks for, where the face that draws it is not cut
    /// to its metrics — nil for the drawn face's own. PowerPoint sets a
    /// line's baseline by the face it names: Verdana's at 0.83 of the
    /// line, where DejaVu Sans, drawing it, has 0.80.
    public var ownDescentShare: ((String) -> Double?)? = nil
    /// Slides: the share of a spacing over single's extra that stands
    /// above a paragraph's lines (`baselineShift`), whatever the face:
    /// PowerPoint's 0.70 at 150% in tdf137367's 40 pt Calibri, where the
    /// engine shares it by the drawn face, Carlito's 0.78. nil — Word —
    /// leaves it to the engine.
    public var extraAboveShare: Double? = nil
    /// Slides: the share of a line of so many points (`lineHeightPoints`,
    /// not a minimum) below its baseline, whatever its face. PowerPoint
    /// sets pptx2svg's 30 pt Verdana line where it sets Calibri's, the
    /// share Carlito's metrics give; the engine, by DejaVu Sans drawing
    /// it, set it 0.5 pt lower. nil — Word — leaves it to the face.
    public var exactLineDescentShare: Double? = nil
    /// Slides: the least below such a line's baseline, as a share of its
    /// text's size: a line hardly taller than its text keeps the text's
    /// depth under it (customGeo's 32 pt text in 33 pt lines, its 40 pt
    /// title in 35, both 0.25 of the size under their baselines in
    /// PowerPoint's print). The size is the first run's: pptx2svg's line
    /// of 28 pt text with a 47 pt word in 30 pt keeps 0.22 of the line.
    /// nil leaves `exactLineDescentShare` alone.
    public var exactLineDescentOfSize: Double? = nil
    /// Slides: a line of so many points keeps its natural depth under single
    /// and takes 0.255 of the extra over it (see `_baselineShift`).
    public var exactLinesAsPowerPoint = false
    /// Device units to a layout pixel while a document is drawn into a
    /// PDF (1/20 for Slides' export, drawn twenty pixels a point): with
    /// it, a run's blurred shadow is blurred (see `textStyle`); nil, as on
    /// screen and in Word, draws it sharp and fainter. Set only around
    /// such a drawing.
    nonisolated(unsafe) public static var shadowBlurDeviceScale: Double? = nil
    /// Whether a run's characters are set at the widths its resolved
    /// face gives (`RichResolvedFace.advances`) outside Word's rules too:
    /// PowerPoint's Lucida Sans Unicode, drawn here in a narrower face.
    public var setsFaceAdvances = false
    /// A raised or lowered run's size is 65% of its own rounded UP to a
    /// whole point, as PowerPoint sets it (20 → 13, 24 → 16, 28 → 19,
    /// 32 → 21, 34 → 23, 11 → 8 in its prints), where 65% exactly is
    /// Word's.
    public var scriptSizeWholeUp = false
    /// A run in capitals is measured — spaced, kerned, put on the grid —
    /// by the capitals it shows rather than the letters it holds, as
    /// PowerPoint fits a title in caps. Off for Word.
    public var measuresShownCaps = false
    /// A run that names a `kerningFrom` is kerned only from that size up
    /// (0: not at all), where the engine kerns every pair; one that
    /// names none is kerned as the engine kerns it. PowerPoint kerns by a
    /// run's `kern` where it says one, and every pair where it says none.
    /// Off for Word, whose `wordRules` kern only where a run says so.
    public var kernsByRun = false
    /// Slides: how far a table cell's line is moved from where it is set,
    /// in points, by its baseline's depth below the top of its cell's
    /// text, in points (PowerPoint sets each on a whole point from
    /// there). nil — Word — leaves every line where it is set.
    public var cellLineShift: ((Double) -> Double)? = nil
    /// Slides: a cell's own line runs half its width past each end of its
    /// edge, and its dashes count from there, as PowerPoint draws them
    /// (lo-tableBorderLineStyle's "Dash" rule starts at 203.5 for a
    /// corner at 204). Off for Word.
    public var cellLinesPastCorners = false

    /// Each face's own single line, even with `singleLineHeight` set: a
    /// PowerPoint diagram's text steps at its face's height (Calibri
    /// 1.22, Courier New 1.13), the rest of its text at 1.2. `faceLineHeight`
    /// gives it for a drawn face standing in for one of another height;
    /// otherwise it is measured. Off by default.
    public var naturalLinesPerFace = false
    public var faceLineHeight: ((String) -> Double?)? = nil

    public func naturalLineHeight(family: String?, bold: Bool, italic: Bool) -> Double {
        if let singleLineHeight, !naturalLinesPerFace { return singleLineHeight }
        if naturalLinesPerFace, let family, let h = faceLineHeight?(family) { return h }
        let key = "\(family ?? "")|\(bold)|\(italic)"
        if let h = _naturalHeights[key] { return h }
        // (Measured at a size where the engine's whole-pixel line height is
        // exact to a few parts in a hundred thousand: at 100 it rounded
        // Calibri's 1.2207 to 1.22, every line of every Calibri paragraph
        // 0.06% short — 13.419 for 11pt where Word's is 13.428, and
        // lo-db739416's 11th line fitted by 0.05pt where Word's does not.)
        let probe = TextPainter(text: TextSpan(text: "x", style: TextStyle(fontSize: 10000, fontWeight: bold ? .bold : .normal,
                                                                            fontStyle: italic ? .italic : .normal, fontFamily: family)),
                                textDirection: .ltr)
        probe.layout(minWidth: 0, maxWidth: 100_000)
        let h = probe.height > 0 ? probe.height / 10000 : 1.2
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
    /// - an exact height stands whatever the face, its baseline 4/5 of
    ///   the way down (lab `exline`, Word for Windows: SimSun 10.5 to 16
    ///   and Times New Roman 12 in 12 to 30pt lines, 0.8 of the line
    ///   and the print's 0.05 offset each — not 13/16, 0.1 to 0.3 more);
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
            return (points, points * 4 / 5)
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
        // (Under single, Word takes the cut off above and below the
        // baseline as the face's line shares itself — the baseline that
        // multiple of its own depth: labs `ml_*`, 宋体 12pt at 0.75 sets
        // the line 12.48 under the one before and the next 14.64 under
        // it, where ours, all of it off below, had 15.6 and 11.7; over
        // single all of the extra goes below, as ours already had.)
        guard let points = paragraph.lineHeightPoints else { return (multiple * n, t0.map { multiple < 1 ? $0 * multiple : $0 }) }
        let h = max(points, multiple * n)
        return (h, t0.map { $0 + max(0, h - n) })
    }

    /// The baseline of a paragraph's lines below their tops, in points,
    /// by its East Asian stretch when it has one (the taller face, which
    /// sets the line) and its first run otherwise — or nil where the
    /// face's own is not known.
    public func baseline(for style: CharStyle, in paragraph: RichParagraphStyle, named: RichNamedStyle?,
                         eastAsian: Bool, gridPitch: Double?, centresInLine: Bool = true) -> Double? {
        var size = style.fontSize ?? named?.char.fontSize ?? fontSize
        // (A right-to-left run is set at the size the file gives complex script, as
        // `textStyle` does: lo-7ec36a70's Persian, 12pt in a style of sz 10, stood 1pt high.)
        if wordRules, style.rightToLeft, !eastAsian, style.fontSize == nil, let z = named?.char.complexFontSize { size = z }
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let scaled = (style.horizontalScale ?? named?.char.horizontalScale ?? 1) != 1
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        // (An exact height needs nothing of the face: the 9pt PMingLiU
        // notes under zh-04f73697's tables, 16pt exact lines, stood 2pt
        // high of Word's for want of a baseline the face has none of.)
        if size > 0, let points = paragraph.lineHeightPoints, !paragraph.lineHeightIsMinimum, faceResolver != nil {
            // (Set by its middle — `w:textAlignment` "center" — the text's
            // own line stands in the middle of the exact one: zh-1563bd74's
            // articles, 16pt in 30pt exact lines, have their baselines
            // 21.7pt down in Word's print, not 24.4.)
            // (Only under `w:spaceForUL`: without it the middle stands
            // where the baseline would — lab `ctr` (Word for Mac): zh-ee9d81b3's
            // 16pt YaHei in 35pt exact lines, which lacks it, is set 34.53
            // down (28.05 by the baseline and 6.45 more), at 30pt 30.45;
            // its paragraphs with the switch added, 23.97, and zh-1563bd74's
            // with it taken out, 30.54 for 21.66.)
            // ("top" sets it the same: zh-df505e38's 16pt 仿宋 title in a 30pt exact
            // line stands 313.9 in Word's print; ours 317.9 by the baseline,
            // 310.0 at the ascent, 314.6 centred.)
            if ["center", "top"].contains(paragraph.eastAsian["w:textAlignment"] ?? ""),
               let middle = lineMiddle(for: style, named: named, eastAsian: eastAsian) {
                return (centresInLine ? points / 2 : lineBox(size: size, natural: 1, baseline: 0, in: paragraph, gridPitch: gridPitch).baseline ?? points / 2) + middle
            }
            // (Set by its foot — "bottom" — the text's own line ends at the
            // exact one's: zh-d3d3f266's 22pt YaHei titles in 28pt exact
            // lines have their baselines 18.06pt down in Word's print,
            // 28 less YaHei's 0.455 em under the baseline; ours, 22.8.)
            if paragraph.eastAsian["w:textAlignment"] == "bottom",
               let under = lineUnder(for: style, named: named, eastAsian: eastAsian) {
                return points - under
            }
            return lineBox(size: size, natural: 1, baseline: 0, in: paragraph, gridPitch: gridPitch).baseline
        }
        guard size > 0, let face = faceResolver?(familyName, eastAsian),
              let t = (scaled ? face.scaledBaseline : nil) ?? (bold ? face.boldBaseline : nil) ?? face.baseline else { return nil }
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        let natural = (scaled ? face.scaledHeight : nil) ?? (bold ? face.boldHeight : nil) ?? face.naturalHeight
            ?? naturalLineHeight(family: face.family, bold: bold, italic: italic)
        return lineBox(size: size, natural: natural, baseline: t, in: paragraph, gridPitch: gridPitch).baseline
    }

    /// How far the middle of a single line of `style`'s text stands above
    /// its baseline, in points — or nil where the face's own line is not
    /// known. What Word's `w:textAlignment` "center" lines a picture up
    /// with.
    public func lineMiddle(for style: CharStyle, named: RichNamedStyle?, eastAsian: Bool) -> Double? {
        let size = style.fontSize ?? named?.char.fontSize ?? fontSize
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        // (A Latin face that keeps no line of its own is measured by its
        // stand-in's natural line, as `baseline(for:)` measures it: zh-27a874b7's
        // Times 14pt in 27pt exact lines set by their middle stands 18.7pt
        // down each line in Word's print; with no middle ours fell to the
        // exact line's baseline, 21.9, and every English line was 3.4pt low.)
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        guard size > 0, let face = faceResolver?(familyName, eastAsian),
              let t = (bold ? face.boldBaseline : nil) ?? face.baseline,
              let natural = (bold ? face.boldHeight : nil) ?? face.naturalHeight
                ?? (eastAsian ? nil : naturalLineHeight(family: face.family, bold: bold, italic: italic)) else { return nil }
        return (t - natural / 2) * size
    }

    /// How tall a single line of `style`'s text is, in points — or nil
    /// where the face is not known.
    public func naturalLine(for style: CharStyle, named: RichNamedStyle?, eastAsian: Bool) -> Double? {
        let size = style.fontSize ?? named?.char.fontSize ?? fontSize
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        guard size > 0, let face = faceResolver?(familyName, eastAsian) else { return nil }
        return ((bold ? face.boldHeight : nil) ?? face.naturalHeight ?? naturalLineHeight(family: face.family, bold: bold, italic: italic)) * size
    }

    /// How far a single line of `style`'s text reaches under its baseline,
    /// in points — or nil where the face's own line is not known: what
    /// Word's `w:textAlignment` "bottom" sets on an exact line's foot.
    public func lineUnder(for style: CharStyle, named: RichNamedStyle?, eastAsian: Bool) -> Double? {
        let size = style.fontSize ?? named?.char.fontSize ?? fontSize
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        guard size > 0, let face = faceResolver?(familyName, eastAsian),
              let t = (bold ? face.boldBaseline : nil) ?? face.baseline,
              let natural = (bold ? face.boldHeight : nil) ?? face.naturalHeight else { return nil }
        return (natural - t) * size
    }

    /// The height of a line whose text carries ruby, as a multiple of the
    /// text's size: its own line made as much taller over its baseline as
    /// the ruby stands above the text's ascent — on a line grid, as many
    /// pitches as that takes. (61470's 11pt "東京" under 5.5pt
    /// "とうきょう" raised 10pt is a line of two 18pt pitches in Word's
    /// print, where the text alone takes one.) Nil where the face's own
    /// metrics are not known.
    public func rubyLineHeight(for style: CharStyle, in paragraph: RichParagraphStyle, named: RichNamedStyle?,
                               eastAsian: Bool, gridPitch: Double?) -> Double? {
        rubyLine(for: style, in: paragraph, named: named, eastAsian: eastAsian, gridPitch: gridPitch)?.height
    }

    /// The ruby line's height as a multiple of the text's size, and on a
    /// line grid how far the text stands above where the engine puts it
    /// (negative: below). The engine keeps the baseline where the line of
    /// the text alone has it; Word centres the text and its ruby together
    /// in the pitches they take, the text under the ruby's room: 61470's
    /// 11pt MS Mincho line is 36pt with its baseline 24.3 down, the text
    /// alone's 12.9 by the engine.
    public func rubyLine(for style: CharStyle, in paragraph: RichParagraphStyle, named: RichNamedStyle?,
                         eastAsian: Bool, gridPitch: Double?) -> (height: Double, raise: Double)? {
        guard let ruby = style.ruby else { return nil }
        let size = style.fontSize ?? named?.char.fontSize ?? fontSize
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        guard size > 0, let face = faceResolver?(familyName, eastAsian) else { return nil }
        let natural = (bold ? face.boldHeight : nil) ?? face.naturalHeight ?? naturalLineHeight(family: face.family, bold: bold, italic: italic)
        let ascent = (bold ? face.boldBaseline : nil) ?? face.baseline ?? 0.8
        let rubySize = ruby.size > 0 ? ruby.size : size / 2
        let raise = ruby.raise > 0 ? ruby.raise : size / 2
        let above = max(0, raise + ascent * rubySize - ascent * size)
        let line = lineBox(size: size, natural: natural + above / size, baseline: nil, in: paragraph, gridPitch: gridPitch).height
        guard gridPitch != nil, paragraph.lineHeightPoints == nil else { return (line / size, 0) }
        let n = natural * size
        let one = lineBox(size: size, natural: natural, baseline: nil, in: paragraph, gridPitch: gridPitch).height
        return (line / size, ((one - n) - (line - n - above)) / 2 - above)
    }

    /// The height of an auto line whose text is all raised by its
    /// `w:position`, as a multiple of the text's size, and how far above
    /// the engine's baseline the text then stands, in points (below,
    /// negative). Word grows
    /// the line rather than move the text up in it: lab t198 (Word for
    /// Windows, zh-f2835e26's head row, 11.5pt SimSun, 14.88 a line) has
    /// it max(14.88, 11.58 + r) tall for a raise r — unchanged to r ≈ 3.3,
    /// then growing with it — the text standing under its top where an
    /// unraised line's does, 11.78 to 11.90; on a 15.6pt grid it takes as
    /// many pitches as that height does, centred in them (pos 15: two,
    /// 31.2, the text 17.90 down). Word for Mac's is the same: zh-10e3a42be's
    /// opening line, 15.5pt raised 7.5 at 1.13 lines, has the text where
    /// unraised and the next line 3.1 lower in Mac Word's print (by this,
    /// 2.9); taller by the whole raise, the page ran 5pt low. Nil where
    /// the face's metrics are not known.
    public func raisedLineHeight(for style: CharStyle, in paragraph: RichParagraphStyle, named: RichNamedStyle?,
                                 eastAsian: Bool, gridPitch: Double?) -> (height: Double, raise: Double)? {
        let r = style.raised ?? named?.char.raised ?? 0
        guard wordRules, NativeParagraphBuilder.supportsBaselineShift, paragraph.lineHeightPoints == nil, r > 0 else { return nil }
        let size = style.fontSize ?? named?.char.fontSize ?? fontSize
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        guard size > 0, let face = faceResolver?(familyName, eastAsian) else { return nil }
        let natural = (bold ? face.boldHeight : nil) ?? face.naturalHeight ?? naturalLineHeight(family: face.family, bold: bold, italic: italic)
        let n = natural * size
        // (The raised text's em stands on the line's foot: 11.5 + r
        // against the lab's 11.58 + r.)
        let grown = max(n, size + r)
        // (The engine keeps the text's baseline where the unraised line
        // has it, the extra below; Word centres the grown height in the
        // line it takes as it centres the unraised one in its own. The
        // text moves by the difference — down, on a grid; not at all off
        // one, the line grown under it.)
        let one = lineBox(size: size, natural: natural, baseline: nil, in: paragraph, gridPitch: gridPitch).height
        let line = lineBox(size: size, natural: grown / size, baseline: nil, in: paragraph, gridPitch: gridPitch).height
        return (line / size, ((one - n) - (line - grown)) / 2)
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
        // (An "at least" height on the grid as well: what it adds over the
        // grid's lines goes above the text, and under it stands the
        // grid's own half — zh-8186c98d's 16pt 仿宋, at least 30pt on a
        // 15.6pt grid, keeps a second line at page 2's foot in Word's print
        // whose box reaches 1.1pt past it; ours sent it over.)
        guard let pitch = gridPitch, pitch > 0, paragraph.lineHeightPoints == nil || paragraph.lineHeightIsMinimum else { return 0 }
        let size = style.fontSize ?? named?.char.fontSize ?? fontSize
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? fontFamily
        let familyName = eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        guard size > 0, let face = faceResolver?(familyName, eastAsian) else { return 0 }
        let bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        let natural = (bold ? face.boldHeight : nil) ?? face.naturalHeight ?? naturalLineHeight(family: face.family, bold: bold, italic: italic)
        if let points = paragraph.lineHeightPoints {
            // ("At least 0" keeps to no grid: no overhang.)
            guard points > 0 else { return 0 }
            let snapped = (natural * size / pitch - 0.002).rounded(.up) * pitch
            return max(0, (snapped - natural * size) / 2)
        }
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
                          characterGrid: Double? = nil, scriptHidden: Bool = false) -> Flutter.TextStyle {
        var size = style.fontSize ?? named?.char.fontSize ?? normal?.fontSize ?? fontSize
        // (Complex-script text is set at the size the file gives it, `w:szCs`:
        // lo tdf163575's Persian is 12pt in a style whose `w:sz` is 10.)
        if wordRules, style.rightToLeft, !eastAsian, style.fontSize == nil, let z = named?.char.complexFontSize ?? normal?.complexFontSize { size = z }
        // (A run that gives `w:sz` and no `w:szCs` is set at the szCs its style or the defaults give: xd 72ea457a's Hebrew, sz 14 over Normal's szCs 12, prints at 12 in David.)
        else if wordRules, style.rightToLeft, !eastAsian, style.sizeFromStyleSzCs, style.complexFontSize == nil, let z = named?.char.complexFontSize ?? normal?.complexFontSize { size = z }
        // (A style that sets `w:sz` and no `w:szCs` anywhere in the chain leaves complex-script text at Word's 10 pt default, not at `w:sz`:
        // ara-z4399437's keyword lines step 11.5 in Word's print, not 10.4.)
        else if wordRules, style.rightToLeft, !eastAsian, style.fontSize == nil, named?.char.fontSize != nil, named?.char.complexFontSize == nil, normal?.complexFontSize == nil { size = 10 }
        // A fitted size is a whole number of points: PowerPoint sets 32 pt
        // at 85% in 27, not 27.2.
        if fontScale != 1 { size = max(1, (size * fontScale).rounded()) }
        var bold = style.bold || ((named?.char.bold ?? false) && !style.off.contains(.bold))
        let italic = style.italic || ((named?.char.italic ?? false) && !style.off.contains(.italic))
        var color = style.color ?? (wordRules && style.off.contains(.autoColor) ? textColor : named?.char.color ?? normal?.color ?? textColor)
        // Word prints automatic text colour white over a black shaded paragraph
        // (ell-z20423699-8d41bb's title bar, fill 000000: ours drew it dark grey).
        if wordRules, style.color == nil, let fill = paragraph.fill, fill.alpha == 255,
           style.off.contains(.autoColor) || (named?.char.color == nil && normal?.color == nil),
           0.299 * Double(fill.red) + 0.587 * Double(fill.green) + 0.114 * Double(fill.blue) < 0.2 * 255 {
            color = Color(0xFFFFFFFF)
        }
        let latinName = style.fontFamily ?? named?.char.fontFamily ?? normal?.fontFamily ?? fontFamily
        let complex = style.rightToLeft && !eastAsian
        var complexName = style.complexFontFamily ?? named?.char.complexFontFamily ?? normal?.complexFontFamily ?? latinName
        // (A right-to-left run that names no complex-script face but Arial Narrow for Latin: Word's prints of the Urdu
        // forms 8963bef7, f98daa05 and 0de57755 draw it in plain Arial, not at Arial Narrow's widths.)
        if complex, wordRules, complexName?.trimmingWhitespace().lowercased() == "arial narrow" { complexName = "Arial" }
        let familyName = complex ? complexName
            : eastAsian ? (style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName) : latinName
        let face = complex ? complexFaceResolver?(familyName) : faceResolver?(familyName, eastAsian)
        let family = face?.family ?? familyName.map { complex ? $0 : (fontFamilyResolver?($0) ?? $0) }
        // (A character scale is laid out as that much smaller or larger
        // a size — the engine sets no face narrower than it is, and the
        // widths are what break the lines — and drawn pulled back to
        // its height: `RichLayout._paintScaled`.)
        let classScale: Double = characterClass.flatMap { k in face?.classScales.flatMap { k < $0.count ? $0[k] : nil } } ?? 1
        let ownScale: Double = RichTextTheme.wordWidthScale(style.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: wordRules,
            eastAsiaFamily: style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latinName)
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
        // (Where the bridge can shift a run's baseline, under Word's rules,
        // the run is drawn in its line instead, shifted: a PDF then holds a
        // note mark where it stands — "Blahdeblah¹ 1", not "Blahdeblah 1"
        // and a "1" after the line, as copying and readers gave it.)
        let shifted = scriptHidden && style.script != .normal && wordRules && NativeParagraphBuilder.supportsBaselineShift
        if scriptHidden, style.script != .normal, !shifted { color = color.withOpacity(0) }
        var px = size * widen * pixelsPerPoint * scale
        // (A raised or lowered run's size, of its own: Word for Windows takes
        // the face's (OS/2 ySuperscriptYSize) — half the size in an East
        // Asian face, as SimSun, SimHei, KaiTi and MingLiU all say, and 65%
        // in Times or Calibri. zh-e51c31a7's "*註1", superscript in 13pt
        // 標楷體, is 6.5pt in its print and raised 6.5, where ours set 8.45
        // and 4.6: see `baselineShift`.)
        // (Meiryo's superscript is 65% rounded up to the half point: 10.5pt gives 6.825, and 7.0 in 934bd3e5's print.)
        let meiryoScript = wordRules && RichTextTheme.wordWindowsPages && style.script != .normal
            && (familyName.map { $0.lowercased().containsSubstring("meiryo") || $0.containsSubstring("メイリオ") } ?? false)
        let scriptRatio = wordRules && RichTextTheme.wordWindowsPages && style.script != .normal
            && (eastAsian || face?.isEastAsian == true)
            // (Meiryo says 65% like a Latin face: 934bd3e5's "３" in 10.5pt Meiryo Bold is 7.0pt in its print.)
            && !meiryoScript ? 0.5 : 0.65
        if style.unseen { color = color.withOpacity(1.0 / 255) }
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
            fontSize: style.script == .normal ? px
                : scriptSizeWholeUp ? (size * 0.65 - 1e-6).rounded(.up) * widen * pixelsPerPoint * scale
                : meiryoScript ? (size * 0.65 * 2 - 1e-6).rounded(.up) / 2 * widen * pixelsPerPoint * scale : px * scriptRatio,
            fontWeight: bold ? .bold : .normal,
            fontStyle: italic ? .italic : .normal,
            letterSpacing: {
                // (A face with no bold of its own is emboldened by Word,
                // and each character set that much wider.)
                // (And a grid of characters adds its own to every one.)
                let spread = (bold ? (face?.boldSpread ?? 0) * size : 0) + (characterGrid ?? 0)
                // (The run's spacing, else its style's, as its size is:
                // zh-5dc5ce34's Normal says -0.3pt and its runs nothing,
                // and Word sets its 16pt text 15.4 apart, ours 16.)
                let own = style.letterSpacing ?? (wordRules ? named?.char.letterSpacing ?? normal?.letterSpacing : nil)
                guard own != nil || spread != 0 else { return nil }
                return ((own ?? 0) + spread) * pixelsPerPoint * scale
            }(),
            // (Up by 0.355 of the size it was shrunk from, or down by a
            // fifth: `_paintScripts`' measures.)
            // (And raised or lowered by its own position, Word's
            // `w:position`: zh-10e3a42be sets its numbered clauses 10.5pt
            // up in 30pt exact lines, and Word's print has them there, the
            // lines' pitch unchanged.)
            baselineShift: {
                // (Up by what the face's size leaves of the em: 0.355 at 65%,
                // half at half.)
                // (Of the run's own size: not a stand-in's drawn one.)
                let script = !shifted ? 0
                    : scriptRatio < 0.6 && style.script == .superscript ? -(1 - scriptRatio) * size * pixelsPerPoint * scale
                    : (style.script == .superscript ? -Self.superscriptRaise(familyName) : 0.2) * px
                let raised = wordRules && NativeParagraphBuilder.supportsBaselineShift ? (style.raised ?? named?.char.raised ?? 0) : 0
                let shift = script - raised * pixelsPerPoint * scale
                return shift != 0 ? shift : nil
            }(),
            // An exact line height is the same multiple of every run's own
            // size: points over size ("at least" that, or the multiple when
            // it is more). A multiple is of the face's natural line height
            // (the engine's `height` is of the size).
            // (A run shifted in its line takes no line of its own: the
            // engine would count its raised ascent, and a line with a note
            // mark stood taller than Word's. At a hair of a height only the
            // shift itself reaches past the baseline, and that stays
            // inside the line the text makes.)
            height: shifted ? 0.01 : {
                // (The engine's `height` is of the drawn size, and a
                // stand-in drawn larger or smaller keeps the line of the
                // size the document names.)
                let natural = (ownScale != 1 ? face?.scaledHeight : nil) ?? (bold ? face?.boldHeight : nil) ?? face?.naturalHeight
                    ?? naturalLineHeight(family: family, bold: bold, italic: italic)
                guard size > 0 else { return max(0.1, paragraph.lineSpacing - lineSpacingReduction) * natural / widen }
                return lineBox(size: size, natural: natural, baseline: nil, in: paragraph, gridPitch: gridPitch).height / (size * widen)
            }(),
            // (In points, as the file gives it, at the layout's scale.) A
            // blurred shadow is drawn sharp at under half its strength
            // unless `shadowBlurDeviceScale` says what the engine's blur is
            // measured in: it takes its sigma in device units, whatever the
            // canvas's scale, so drawn twenty pixels a point into a PDF
            // (whose units are points) it spread twenty times too wide and
            // faded to nothing. With the scale, the blur is the engine's at
            // 0.4 of the file's radius and 55% strength: the PDF's mask is
            // 72 dpi and softens it again, where PowerPoint's is 300 dpi
            // and black at its core (45541's 3 pt blur; 0.5 and full
            // strength spread it wider and darker than PowerPoint's).
            // (None on a raised or lowered run held unseen in its line:
            // its shadow goes with the run where `_paintScripts` draws it,
            // where it stood at the baseline under 5864's raised "st".)
            shadows: scriptHidden && style.script != .normal && !shifted ? [] : px <= 0.01 ? nil : { () -> [Shadow]? in
                guard let line = style.outline, line.width > 0 else { return nil }
                // (An outline as the letters' copies a half line out all round, in its colour, under the
                // letters: PowerPoint's is centred on the edge.)
                let k = pixelsPerPoint * scale, r = line.width * 0.35 * k
                let d = r * 0.7071
                return [Offset(r, 0), Offset(d, d), Offset(0, r), Offset(-d, d), Offset(-r, 0), Offset(-d, -d), Offset(0, -r), Offset(d, -d)]
                    .map { Shadow(color: line.color, offset: $0, blurRadius: 0) }
            }().map { ring in (style.shadow.map { sh in
                if sh.ground != nil { return [] }
                let k = pixelsPerPoint * scale
                let device = sh.blur > 0 ? Self.shadowBlurDeviceScale : nil
                if sh.glow {
                    // (A glow: the letters' colour all round them, strongest at the edge and gone by about
                    // a quarter of its radius, PowerPoint's print of lo-shape-text-glow-effect's 20 pt glow
                    // on 18 pt text: a green band 4 to 5 pt wide. Ten blurred copies stand in for it.)
                    if device == nil {
                        // (Where nothing blurs, as on screen and in Word's PDF: two rings of sharp copies a
                        // half and the whole band out, eight ways round.)
                        let band = sh.blur * 0.3 * k, a = Double(sh.color.alpha) / 255 * 0.36
                        return [0.35, 0.7, 1.0].flatMap { f in (0 ..< 12).map { i -> Shadow in
                            let t = Double(i) * Double.pi / 6
                            return Shadow(color: Color(rgbo: sh.color.red, sh.color.green, sh.color.blue, a),
                                          offset: Offset(cos(t) * band * f, sin(t) * band * f), blurRadius: 0)
                        } }
                    }
                    let r = device.map { max(0, (sh.blur * 0.2 * k * $0 - 0.5) / 0.57735) } ?? 0
                    let a = Double(sh.color.alpha) / 255 * 0.85
                    return (0 ..< 10).map { _ in Shadow(color: Color(rgbo: sh.color.red, sh.color.green, sh.color.blue, a), offset: .zero, blurRadius: r) }
                }
                let a = Double(sh.color.alpha) / 255 * (sh.blur > 0 ? device == nil ? 0.45 : 0.55 : 1)
                let radius = device.map { max(0, (sh.blur * 0.4 * k * $0 - 0.5) / 0.57735) } ?? 0
                return [Shadow(color: Color(rgbo: sh.color.red, sh.color.green, sh.color.blue, a),
                               offset: Offset(sh.dx * k, sh.dy * k), blurRadius: radius)]
            } ?? []) + ring } ?? style.shadow.map { sh in
                if sh.ground != nil { return [] }
                let k = pixelsPerPoint * scale
                let device = sh.blur > 0 ? Self.shadowBlurDeviceScale : nil
                if sh.glow {
                    // (A glow: the letters' colour all round them, strongest at the edge and gone by about
                    // a quarter of its radius, PowerPoint's print of lo-shape-text-glow-effect's 20 pt glow
                    // on 18 pt text: a green band 4 to 5 pt wide. Ten blurred copies stand in for it.)
                    if device == nil {
                        // (Where nothing blurs, as on screen and in Word's PDF: two rings of sharp copies a
                        // half and the whole band out, eight ways round.)
                        let band = sh.blur * 0.3 * k, a = Double(sh.color.alpha) / 255 * 0.36
                        return [0.35, 0.7, 1.0].flatMap { f in (0 ..< 12).map { i -> Shadow in
                            let t = Double(i) * Double.pi / 6
                            return Shadow(color: Color(rgbo: sh.color.red, sh.color.green, sh.color.blue, a),
                                          offset: Offset(cos(t) * band * f, sin(t) * band * f), blurRadius: 0)
                        } }
                    }
                    let r = device.map { max(0, (sh.blur * 0.2 * k * $0 - 0.5) / 0.57735) } ?? 0
                    let a = Double(sh.color.alpha) / 255 * 0.85
                    return (0 ..< 10).map { _ in Shadow(color: Color(rgbo: sh.color.red, sh.color.green, sh.color.blue, a), offset: .zero, blurRadius: r) }
                }
                let a = Double(sh.color.alpha) / 255 * (sh.blur > 0 ? device == nil ? 0.45 : 0.55 : 1)
                // (The engine's blur radius, from its sigma: r · 0.57735 + 0.5.)
                let radius = device.map { max(0, (sh.blur * 0.4 * k * $0 - 0.5) / 0.57735) } ?? 0
                return [Shadow(color: Color(rgbo: sh.color.red, sh.color.green, sh.color.blue, a),
                               offset: Offset(sh.dx * k, sh.dy * k), blurRadius: radius)]
            },
            fontFeatures: {
                var features = disablesLigatures ? [FontFeature("liga", 0), FontFeature("clig", 0)] : []
                // (Nor contextual alternates, which Word sets only where a run
                // asks for them (`w14:cntxtAlts`): StarlingFangSong's calt
                // takes a lone "—" to emdash.unjoined, a glyph no character
                // maps to, and the PDF's text of zh-8d6f702e's "— 3 —"
                // footers read "∴ 3 ∴" — its glyph number taken for a code
                // point, one line a page lost to the reader.)
                if wordRules { features.append(FontFeature("calt", 0)) }
                // Word kerns a run only from the size its `w:kern` names
                // up; the engine kerns every pair. Bug59058's caption in
                // Times New Roman bold, kerned, fitted "State," on a line
                // Word's unkerned "Women by" filled ("Wo" alone 0.67pt).
                // (MS Mincho, Gothic and their P faces carry no kern pairs: the Noto stand-in's kana pairs
                // (ア before イ, 0.81 pt at 9 pt) shortened cab6d785's cell line, which then held a character
                // more than Word's.)
                let msJapanese = wordRules && RichTextTheme.wordWindowsPages && (familyName.map { n in
                    let l = n.lowercased()
                    return ["ms mincho", "ms pmincho", "ms gothic", "ms pgothic", "ｍｓ 明朝", "ｍｓ ｐ明朝", "ｍｓ ゴシック", "ｍｓ ｐゴシック"].contains { l.containsSubstring($0) }
                } ?? false)
                if wordRules, msJapanese || !((style.kerningFrom ?? named?.char.kerningFrom ?? normal?.kerningFrom).map { $0 > 0 && size >= $0 } ?? false) {
                    features.append(FontFeature("kern", 0))
                } else if kernsByRun, let from = style.kerningFrom ?? named?.char.kerningFrom ?? normal?.kerningFrom,
                          !(from > 0 && size >= from) {
                    features.append(FontFeature("kern", 0))
                }
                return features.isEmpty ? nil : features
            }(),
            decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
            decorationColor: color,
            debugLabel: familyName,
            fontFamily: family,
            fontFamilyFallback: {
                let list = (face?.fallback ?? []) + Self.glyphFallback
                return list.isEmpty ? nil : list
            }()
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
    /// The face's Latin is fixed at half an em a character (SimSun, FangSong, KaiTi, MS Mincho and Gothic, the -Che faces), not proportional.
    public var fixedHalfLatin = false
    /// Its italic's and bold italic's, where the face has them and they
    /// differ from the regular's and bold's (nil: those are used).
    public var italicAdvances: [Double]? = nil
    public var boldItalicAdvances: [Double]? = nil
    /// The widths to set a run of this weight and slant by.
    func advanceTable(bold: Bool, italic: Bool) -> [Double]? {
        if italic {
            if bold, let t = boldItalicAdvances ?? italicAdvances { return t }
            if !bold, let t = italicAdvances { return t }
        }
        return bold ? boldAdvances : advances
    }
    /// The original face's kern pairs among those characters, in ems,
    /// keyed first << 8 | second, and its bold's: set where the run
    /// kerns at its size (`kerningFrom`), as Word kerns them — the
    /// stand-in's own kerning is off, its pairs not the original's.
    public var kerns: [UInt32: Double]? = nil
    public var boldKerns: [UInt32: Double]? = nil
    /// The same for characters past those which the original face has
    /// and its stand-in has not, by code point: the stand-in's fallback
    /// draws them, and the line is set by the original's widths (Times
    /// New Roman's Roman numerals, Ⅳ wider than an em).
    public var otherAdvances: [UInt32: Double]? = nil
    /// A missing Korean face Word draws in Batang: its quotes, circles and circled digits come from Malgun Gothic, and a line holding one is Malgun's height.
    public var malgunSymbols = false
    public var boldOtherAdvances: [UInt32: Double]? = nil
    /// The original's Arabic advances by code point, presentation forms
    /// among them (`ArabicForms.width`): each word of it is set to the
    /// width its joining forms have there, where the stand-in's shaping
    /// gives another.
    public var joinedAdvances: [UInt32: Double]? = nil
    public var boldJoinedAdvances: [UInt32: Double]? = nil
    /// Letter groups the face sets as one glyph, `"letters|1or0 joins before|1or0 joins after"` to ems.
    public var joinedClusters: [String: Double]? = nil
    public var boldJoinedClusters: [String: Double]? = nil
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
    /// The line height and the baseline of the face's bold, where its
    /// bold is a face of its own with other metrics (nil: the regular's).
    public var boldHeight: Double? = nil
    public var boldBaseline: Double? = nil
    /// Whether the face has none of the CJK compatibility ideographs
    /// Word's fallback sets in Noto Sans SC (`_notoCompatibility`) —
    /// YaHei, the face Word on a Mac sets most Chinese names in.
    public var lacksCompatibilityIdeographs = false
    /// The characters the face holds, where it is a subset a document
    /// embeds (nil: any), and the face Word sets the others in —
    /// whose line they then give theirs (see `_span`).
    public var covers: Set<UInt32>? = nil
    public var uncoveredFamily: String? = nil
    /// Word for Mac draws this face from the subset the document embeds,
    /// having none of its own by the name (see `covers`).
    public var drawnFromSubset = false
    /// Where Word takes what the subset lacks from more than one face: in
    /// order, each face and what it holds (nil: anything). A character
    /// goes to the face the one before it went to while that face has
    /// it, else to the first that has it; one the subset holds starts
    /// over (see `_span`). `uncoveredFamily` is then the last.
    public var uncoveredChain: [(family: String, covers: Set<UInt32>?)]? = nil
    /// Whether the name is an East Asian face's: the quotes, dashes and
    /// dots both scripts claim are then its full-width ones, whatever
    /// the run's hint.
    public var isEastAsian: Bool
    /// East Asian symbols (■□●○◆, arrows, box drawing) are an em wide
    /// in this face, as in the square faces Word has (SimSun, SimHei,
    /// KaiTi, FangSong, MingLiU); a proportional one (YaHei) sets its own
    /// widths — ○ at 0.6 em.
    public var fullWidthSymbols = false
    /// The advance, in ems, of the face's missing-glyph box: what Word
    /// sets a private-use character in where no face has it (drawn
    /// blank in its print). nil: the fallback's glyph.
    public var missingGlyphAdvance: Double? = nil
    /// Faces to draw what `family` has no glyph for, before the theme's
    /// `glyphFallback`: a Song face's ideographs in a serif, its letters
    /// and digits still the Latin stand-in's.
    public var fallback: [String] = []
    /// Where Word sets the triangles and stars (▲ △ ▼ ▽ ★ ☆) of a run in this
    /// face in another, and measures their line by it: a name Word on a
    /// Mac lacks, set in Microsoft YaHei, draws them from SimSun.
    public var symbolFamily: String? = nil
    /// Whether a bold run's are `symbolFamily`'s too: not in Word for
    /// Windows, which sets them in the stand-in's bold.
    public var symbolsInBold = true
    /// A math face (Cambria Math): its characters past ASCII come from
    /// the platform's math face, set inside the run's line.
    public var setsMath = false

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
        // (Thai — a cluster of its letter and marks — a class of its own:
        // a face with four scales leaves it at its size.)
        if let u = ch.unicodeScalars.first?.value, u >= 0x0E01, u <= 0x0E5B { return 4 }
        if ch.isNumber { return 0 }
        if ch.isUppercase { return 1 }
        if ch.isLowercase { return 2 }
        return 3
    }
}

// MARK: - Pages

/// A section's line numbers (`w:lnNumType`): Word counts the lines of the
/// body's paragraphs (not those of tables, frames, notes, headers or
/// footers, nor of a paragraph that says `suppressLineNumbers`) and sets the
/// count in the margin, `distance` points left of the text, at every
/// `countBy`th line.
public struct LineNumbering: Hashable, Sendable {
    public enum Restart: Sendable { case newPage, newSection, continuous }
    public var countBy = 1
    /// The first line's number.
    public var start = 1
    /// From the text's left edge, in points; nil is Word's "auto".
    public var distance: Double? = nil
    /// `w:restart`'s default is a new count on every page.
    public var restart = Restart.newPage
    public init() {}
}

/// Paper size and margins, in points. `nil` on the layout means a continuous
/// column (a note, a text field); set, the flow is cut into pages at line
/// boundaries and every geometry query has a canvas-space twin.
public struct ColumnSpan: Hashable, Sendable {
    public var width: Double
    public var gap: Double
    public init(width: Double, gap: Double) { self.width = width; self.gap = gap }
}

public struct PageSetup: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public var marginTop: Double
    public var marginBottom: Double
    /// A margin the file wrote negative: Word reads it as exact, the text kept
    /// to it whatever the header or footer needs (`w:pgMar`).
    public var marginTopExact = false
    public var marginBottomExact = false
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
    /// Where the section numbers its pages from (`w:pgNumType w:start`;
    /// nil: on from the section before) and how (`w:fmt`). The last
    /// section's are `RichDocument.pageNumberStart`/`pageNumberFormat`.
    public var pageNumberStart: Int? = nil
    public var pageNumberFormat: String? = nil
    /// The section's chapter numbers on its page numbers
    /// (`RichDocument.chapterStyle`/`chapterSeparator` are the last section's).
    public var chapterStyle: Int? = nil
    public var chapterSeparator: String? = nil
    /// The section's line numbers (`w:lnNumType`), nil where it has none.
    public var lineNumbers: LineNumbering? = nil
    /// The section's vertical alignment of a page's text (`w:vAlign`):
    /// "center", "bottom" or "both" (spread between the paragraphs); nil is
    /// the top.
    public var verticalAlign: String? = nil
    /// An explicit odd/even section start (`w:type`). Its page numbers,
    /// rather than physical sheet indices, determine the requested side.
    public enum PageParity: Int, Hashable, Sendable { case even = 0, odd = 1 }
    public var sectionStartParity: PageParity? = nil
    /// How far in from the left margin the body's lines start because a header's picture that
    /// wraps the text stands the page's height there (`Docx._headerWrapLeft`), in points; 0 for
    /// none. Only the layout reads it: the file's own margins are what is saved.
    public var headerWrapLeft: Double = 0

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
    /// A right-to-left section (`w:bidi`): its first column is the rightmost.
    public var rtlColumns = false
    /// Unequal columns (`w:equalWidth` 0): each one's width and the gap
    /// after it, as the file states them. Nil for equal columns.
    public var columnSpec: [ColumnSpan]?

    /// The left edge of column `k` from the text's left edge.
    public func columnOffset(_ k: Int) -> Double {
        guard let spec = columnSpec, spec.count == columns, k > 0 else { return Double(k) * (columnWidth + columnGap) }
        return spec[..<min(k, spec.count)].reduce(0) { $0 + $1.width + $1.gap }
    }

    /// The width text wraps at: the content width shared by the columns.
    /// Where they are unequal it is the widest; a narrower column's lines
    /// are held in by the layout's per-column pass (`_specInsetBoxes`).
    public var columnWidth: Double {
        if let spec = columnSpec, spec.count == columns, let m = spec.map(\.width).max(), m > 0 { return m }
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

    /// The section writes its text top to bottom, columns from the right
    /// (`w:textDirection` tbRl/tbRlV). Everything in this setup is then the
    /// TRANSPOSED page the layout works in (a line runs along the physical
    /// height, the lines stack across the physical width); `transposed()`
    /// gives the paper back.
    public var vertical = false

    /// The page turned a quarter: width and height swap, and the margins go
    /// round with it (physical top becomes the line's start, physical right
    /// the first column's edge). Its own inverse.
    public func transposed() -> PageSetup {
        var p = self
        p.width = height
        p.height = width
        p.marginLeft = marginTop
        p.marginRight = marginBottom
        p.marginTop = marginRight
        p.marginBottom = marginLeft
        return p
    }

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
    /// The space before and after paragraphs shrinks with `fontScale` too:
    /// a SmartArt shape's spacing is a share of its line, and PowerPoint
    /// sets it smaller with the text it fits (an office diagram's list).
    public var spacingFollowsFont = false {
        didSet { if spacingFollowsFont != oldValue { invalidateAll() } }
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

    var _pages: [[PagePiece]] = []
    /// Every page piece in generation order (paragraph order), and where
    /// each paragraph's pieces start in it — one flat array, not one array
    /// per paragraph, which cost a keystroke a thousand allocations.
    var _allPieces: [PagePiece] = []
    var _pieceStart: [Int] = []
    /// Cached from the style at layout time so pagination never copies a
    /// paragraph value just to read one flag.
    var _pageBreak: [Bool] = []
    /// Paragraphs re-laid out since the last pass; nil means scan them all
    /// (after an insert, a removal, or invalidateAll).
    var _dirty: [Int]? = []
    /// The lowest paragraph index changed since the last placement: the
    /// tops and pages before it are still right, so placement and
    /// pagination restart there. nil means from the top.
    var _firstDirty: Int? = nil
    /// The highest changed index: past it, a paragraph whose top comes out
    /// where it was means nothing below moved, and both passes stop.
    var _lastDirty: Int = 0
    var _pagesValid = false

    /// Called when a picture finished decoding and the view should repaint.
    public var onNeedsRepaint: (() -> Void)?
    var _decoded: [String: Image] = [:]
    var _tileSource: (ImageAttachment, Double, Double)? = nil
    var _decoding: Set<String> = []
    var _imageSize: [Size?] = []
    /// How far a picture paragraph's picture stands in from its text's
    /// left, as the paragraph aligns it (pixels).
    var _imageShift: [Double] = []
    /// How far down its line a picture paragraph's picture stands: its
    /// character border's and effect extent's room above it (pixels).
    var _imageDrop: [Double] = []
    /// Per paragraph, its inline pictures in placeholder order.
    var _inline: [[ImageAttachment]] = []
    /// Paragraphs laid out on `_mixedFaceSpan`'s line, which sets their baseline itself.
    var _mixedFace: [Int: (depth: Double, size: Double)] = [:]
    var _inlineBoxes: [[Int]] = []
    /// An inline object's own height where its box is a page tall (`_span`), by id.
    var _pageFill: [String: Double] = [:]
    /// Room above a picture centred in the grid pitches of its line (several pictures in a paragraph), by image id.
    var _lineCentre: [String: Double] = [:]
    /// A picture paragraph's float, when its picture is anchored.
    var _floats: [ImageFloat?] = []
    var _floatImages: [ImageAttachment?] = []
    /// How far pagination moved a floating picture to the right, clear of
    /// one already on its page (by image id; `_paginate`).
    var _floatShift: [String: Double] = [:]
    /// A text box's width where it takes its text's (`RichTextBox.fitsText`).
    var _fitWidths: [String: Double] = [:]
    /// Whether the page this layout is drawn for is a left-hand (even)
    /// one: a header's or footer's, where an object aligned "outside"
    /// stands at the left.
    public var leftHandPage = false
    /// The same for a floating shape aligned inside or outside: see where
    /// a header or footer sets it.
    public var leftHandFloat = false
    /// The widths (pixels, by image id) a header's or footer's fit-to-text
    /// boxes keep from the first page that header or footer is on: Word
    /// sizes such a box once and wraps later pages' text inside it (a
    /// DrawingML box: `RichTextBox.fitsOnce`).
    var inheritedFitWidths: [String: Double] = [:]
    /// … and up, where its paragraph's line was moved down under the
    /// pictures and the picture stays where the paragraph first stood.
    var _floatShiftY: [String: Double] = [:]
    /// A box wrapped on one side only: its own left and right, before the open side is run out to the column's edge.
    var _wrapOwnSpan: [String: (left: Double, right: Double)] = [:]
    /// Floats set before the content above their anchor on their page
    /// (see `_paginate`): the page, their band there (page y, x from the
    /// column's edge, wrap distances in) and where their anchor stood.
    /// Paragraphs that open a column of their own (a forced break before each): the last paragraph of a
    /// column whose next column then sent its anchor paragraph on, after Word's prints of
    /// LibreOffice's fdo43573-2-min (see `_paginate`, "an anchor paragraph whose own small band").
    var _columnPushed: Set<Int> = []
    var _pinnedFloats: [String: (page: Int, top: Double, bottom: Double, left: Double, right: Double, anchorY: Double)] = [:]

    /// Table cells: per paragraph, the row's top and height (for borders and
    /// hit-testing) and the column geometry; nil for ordinary paragraphs.
    struct _CellGeo {
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
        /// The bottom margin the file states for the cell, without the
        /// rule room `pad` takes in with it.
        var margin: Double = 0
        /// How much of `pad`, top and bottom together, is the row's
        /// rules: a row is that much taller than the height the file
        /// gave it.
        var rules: Double = 0
        /// The width of the cell's own top rule (px) — its tcBorders, row or
        /// table — without the row above's bottom line it shares: what a
        /// part carried to a new page draws above itself.
        var ownTopRule: Double = 0
        /// … and how much of that is the table's bottom rule, which a
        /// cell that reaches the last row carries.
        var ruleBelow: Double = 0
        /// The line drawn under the row where it ends a page: the next
        /// row's top one, or this row's own bottom one.
        var ruleNext: Double = 0
        /// Rows after this cell's that have no paragraph of their own
        /// (every cell of them merged down from above), whose height
        /// `ownRowHeight` takes in: the row's edges are drawn round both.
        var ghostRows = 0
        /// Where each of those rows begins, under the row's top (px): the
        /// row parts over a page only there (see where rows part).
        var ghostBounds: [Double] = []
        /// How much of `ownRowHeight` the row was given for the cells
        /// merged down into it, whose text was taller than their rows:
        /// what a page that takes up such a cell part-way can do without.
        var stretched: Double = 0
        /// A turned cell merged over rows that go on past its page's
        /// foot: how much of it is on the page (px), where its text is
        /// set; nil where the merge is whole on its page.
        var turnedPart: Double? = nil
        /// Its text was wrapped to that part: not shared out over the rest.
        var wrapsPart = false
        /// The cell's own edge lines (`CellRef.borders`).
        var borders = CellRef.CellBorders()
        var vertical: Bool { direction != .horizontal }
        /// Where a turned cell's text starts along its reading direction:
        /// at the bottom margin reading up, the top margin reading down.
        var alongStart: Double { direction == .up ? pad.bottom : pad.top }
        var acrossStart: Double { direction == .up ? pad.left : pad.right }
    }
    var _cells: [_CellGeo?] = []
    /// Tables holding a drawing anchored with `layoutInCell="0"`.
    var _shapesLeaveCell: Set<String> = []
    /// Row top for every paragraph (its own top when not in a table): the
    /// monotonic sequence the binary search runs on.
    var _rowTops: [Double] = []
    /// How far a table floating in the cell reaches from its top (px): the content a centred cell has.
    var _floatReach: [Double] = []
    var _flowHeight = 0.0
    var _columnWidths: [String: [Double]] = [:]   // px, per table
    var _nestedInFixedTable = false
    /// A table nested in a cell, set as a block: Word's nested table is not set out by its cell margin, as a body's is.
    var _nestedBlock = false
    /// Bands, from this nested block's top, that floating tables of its cell stand in: a row of the
    /// block that its natural height would put in one steps down to the band's foot (Word, lab
    /// `frcell` on lo-5c5eb1f7 row 25: a table row is not wrapped round a floating table, it
    /// steps below it, once for each).
    var _avoidBands: [(top: Double, bottom: Double)] = []
    /// How far the bands pushed the block's rows down in all: a float anchored to what follows the block keeps the place it had.
    var _avoidPush = 0.0
    /// Floating tables anchored to what follows the block, against the text: their places are from the block's natural foot.
    var _followBands: [(dy: Double, height: Double)] = []
    /// Per paragraph holding such a block: how far it stepped down (`_avoidPush`), for the floats anchored after it.
    var _blockPush: [Int: Double] = [:]
    /// The room a nested table has where its autofitting parent already
    /// spans its page's text: past it the child keeps its saved grid and
    /// its content overflows (pixels; nil elsewhere).
    var _nestedCap: Double? = nil
    /// A turned text box's layout (`RichTextBox.textDirection` not across):
    /// its lines run along the box's height.
    var _turnedBox = false
    /// Whether this layout is a text box's text (`_textBox`).
    var _inTextBox = false
    /// Laid out as a text box's own text (also the layouts remade for a box whose text is
    /// centred or at the foot, which keep nothing else of the first).
    var _boxText = false
    // Frame edges in the nested layout's line coordinates, for restoring
    // an overflowing first-line indent. Other lines keep their own policy.
    var _fixedTextFrame: (left: Double, right: Double)?
    /// A nested table whose autofitting parent fitted its column narrower
    /// than the child's saved width: a share of it is a share of that
    /// column, under the saved grid too (lab dr2/h).
    var _nestedNarrowed = false
    var _tableFlowWidth: [String: Double] = [:]   // px: the column each table is laid out in
    /// Points: how far a table of cell spacing is set out before Word 2013's
    /// layout — its first cell's whole text inset (`_tableLeft`).
    var _tableSpacedOutdent: [String: Double] = [:]
    var _tableRows: [String: Int] = [:]           // each table's last row
    var _tableMerged: [String: [Int]] = [:]       // each table's paragraphs in cells merged down
    public var cellPadding: Double = 4   // px, inside a cell

    var _painters: [TextPainter?] = []
    var _textLeft: [Double] = []
    var _textWidth: [Double] = []
    /// A turned merged cell's length before it was wrapped to a page's part.
    var _turnedFull: [Int: Double] = [:]
    var _spaceBefore: [Double] = []
    /// What each paragraph's text is drawn lower by than the engine set
    /// it, so that its baselines are Word's (see `RichTextTheme.lineBox`).
    var _inkShift: [Double] = []
    /// The part of `_inkShift` that a bullet larger than its text adds to the first line's height (it stands over the cut points of a table cell).
    var _numberLiftShift: [Double] = []
    /// Per line, how far a paragraph's lines are drawn from where the engine set them (px, down).
    var _lineLift: [[Double]] = []
    /// How far each paragraph's last line on a page may reach past the
    /// page's foot (px; `RichTheme.gridOverhang`).
    var _overhang: [Double] = []
    /// How much taller each paragraph's first line is than its painter's
    /// for a shape set in Segoe UI Symbol (px; `RichTextTheme.segoeSymbolShapes`): its
    /// lines' cuts stand as much lower.
    var _firstLineLift: [Double] = []
    /// … line by line, where its faces differ from line to line (px; empty
    /// where only the paragraph's `_overhang` is known).
    var _lineOverhang: [[Double]] = []
    /// The paragraphs set with their indents mirrored (`w:mirrorIndents`
    /// on a page Word mirrors), by index; recomputed after paging.
    var _mirrored: Set<Int> = []
    var _mirrorPassing = false
    var _besidePassing = false
    /// The first paragraph of a page whose header holds a box the body may not run under
    /// (`_headerBoxFloor`): how far its line goes down to clear it (pixels), by paragraph.
    var _headPushUse: [Int: Double] = [:]
    var _headPassing = false
    /// The strips beside a frame the page fixes (`_stripFrame`): for each paragraph a line of
    /// it stands level with, the room it is held in and the band, from the paragraph's top.
    var _stripUse: [Int: (indent: Double, band: (top: Double, bottom: Double), right: Bool)] = [:]
    /// A shape that wraps the text, set by its offset from a paragraph in a column of a
    /// section of columns, reaches the other columns too (lo-ff3b52d1's oval, anchored in the
    /// first and standing over the second and third): every piece of the paragraph on the
    /// page gets the rooms beside it as per-line indents, from the band (from the
    /// paragraph's top) it covers there. Set by the pass after pagination.
    var _colWrap: [Int: [ColWrapBox]] = [:]
    var _colWrapPassing = false
    struct ColWrapBox: Equatable { var top: Double; var bottom: Double; var left: Double; var right: Double; var byStart = false }
    var _stripPassing = false
    /// A table floating by the text whose room above it (`w:topFromText`) reaches the text
    /// before it: the place in the flow it is held at, by table, once that text wraps beside it.
    var _floatPin: [String: (page: Int, y: Double)] = [:]
    /// The stretch of a float that a paragraph set beside it really shares,
    /// from the paragraph's own top, as the page it fell on made it
    /// (`_besideBand` takes it over the whole float's).
    var _besideBandUse: [Int: (top: Double, bottom: Double)] = [:]
    /// A paragraph's beside-float band ends where its first page's piece does: the lines
    /// that go on to the next page are set across it (`_capPassing`).
    var _bandCap: [Int: Double] = [:]
    var _capPassing = false
    /// A box the text keeps above and below, set from the top of the part of
    /// its paragraph its anchor's line is in, in the paragraph's own pixels
    /// (`_clearPassing`): in several columns that is known only once the
    /// paragraph is cut into them.
    var _clearBand: [Int: (top: Double, bottom: Double)] = [:]
    var _clearPassing = false
    /// Paragraphs whose band is the union of two floats' (the page-fit pass leaves them alone).
    var _besideUnion: Set<Int> = []
    /// … and the stretches the paragraph shares with the rest of that float on the pages
    /// after the first it stands on (from the paragraph's own top, so the
    /// page break falls inside them): a float whose rows run over two pages.
    var _besideMoreBands: [Int: [(top: Double, bottom: Double)]] = [:]
    /// The boxes with room at both sides that a paragraph is set round, when
    /// there are two or more (the text then stands in the room between and
    /// outside them): top, bottom, left edge and right edge, from the text's start.
    var _besideBoxes: [Int: [(top: Double, bottom: Double, left: Double, right: Double)]] = [:]
    /// A box standing at the line start of a paragraph whose other box is at its right: how far its lines start in, and its band.
    var _besideStartLeft: [Int: (indent: Double, band: (top: Double, bottom: Double))] = [:]
    /// How far a paragraph's text is set down to clear an object that
    /// floats over its head and leaves its first line no room beside it
    /// (px; part of `_spaceBefore`).
    var _floatPush: [Double] = []
    /// Paragraph i has a float wrapped tight or through (lab anch): the one thing that carries a box with its pushed line.
    var _floatTight: [Bool] = []
    /// The width (pixels, either sign) of the box that stands before
    /// each paragraph's text for its first line's indent or its list
    /// number; 0 for none.
    var _leadWidth: [Double] = []
    /// How far a paragraph's first line is held in beside a floating table
    /// it follows (`_besideIndent`), in layout pixels; 0 for none.
    var _besideLead: [Double] = []
    /// Whether that hold is on the paragraph's RIGHT: the table stands at the right, and the lines end short of it.
    var _besideRightSide: [Bool] = []
    /// Paragraphs laid out before the rows of the table they sit beside were
    /// measured: laid out again once those are.
    var _besidePending: Set<Int> = []
    /// A fixed box still puts the first glyph at its stated indent when
    /// it overflows. Its painter reserves room for that glyph on line one;
    /// painting restores the difference before clipping to the frame.
    var _boxFirstLineShift: [Double] = []
    /// The tabs of each paragraph that are filled with a leader (a
    /// contents page's dots): the tab's offset, and the character.
    var _leaders: [[(offset: Int, fill: String)]] = []
    var _unseenShift: [Int: Double] = [:]
    /// Where each paragraph's painter has a character the paragraph has
    /// not: the paragraph offsets a zero-width space stands before (see
    /// `_OffsetMap`).
    var _inserts: [[Int]] = []
    /// Soft hyphens (U+00AD) a paragraph's lines end at, drawn as a visible
    /// hyphen (U+2010) so the line breaking measures it: Word shows the
    /// hyphen only where the line breaks there.
    var _hyphenShown: [Int: Set<Int>] = [:]
    /// Offsets `_span` joins inside a long Han/kana piece Word starts on a fresh line (`_hanPieceMoves`).
    var _hanChunks: [Int: Set<Int>] = [:]
    /// Paragraph -> the offset from which its closing run of ideographic spaces is set with no width (Word lets that run hang past the line, so it never starts a line of its own: 8b283c4d's "政治家" paragraph).
    var _trailCut: [Int: Int] = [:]
    /// Where each paragraph may be parted by automatic hyphenation
    /// (`w:autoHyphenation`): the text offsets the next line may begin at.
    var _hyphenPoints: [Int: Set<Int>] = [:]
    var _heights: [Double] = []
    var _tops: [Double] = []
    var _listLabels: [String?] = []
    /// How far a list item's first line, beside a box at the left, sets its number and text past where the box ends.
    var _besideLabelShift: [Int: Double] = [:]
    /// What each paragraph's list membership and cell were at its last
    /// layout: a change in either is what invalidates the numbering pass
    /// and the table pass, not a change in the paragraph's text.
    var _listSig: [ListSig] = []
    var _wasCell: [Bool] = []
    var _tablesDirty = true
    /// Each cell paragraph's narrowest and widest settings (px), for
    /// `_autofit`.
    var _cellMins: [Int: (min: Double, max: Double)] = [:]
    struct ListSig: Equatable {
        var kind: ListKind?
        var level: Int
        var id: String?
    }
    var _topsValid = false
    var _listValid = false

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
    var _spellCache: [String: [Range<Int>]] = [:]
    var _spellVersion = 0
    public internal(set) var pendingSpellChecks: [Int] = []
    /// The caret during a paint: its word is not underlined while typed.
    var _paintCaret: RichPosition? = nil

    var _tableFirstParagraph: [String: Int] = [:]
    /// The widest line a table's first-column cells state on their own
    /// left (points), by table: see `_edgeShift`.
    var _tableOwnLeft: [String: (style: String, width: Double)] = [:]
    /// The widest right line a last-column cell states of its own, per table.
    var _tableOwnRight: [String: (style: String, width: Double)] = [:]

    /// Column widths (points) shown instead of the document's while a
    /// border is being dragged; the edit lands on release.
    var _columnPreview: [String: [Double]] = [:]
    /// Each section keeps its own columns (see `_resolveSections`): the
    /// slots of a page are the largest count's, a section of fewer fills
    /// the first of them, and the next column after its last is the next
    /// page's.
    var _perSection = false
    var _maxSectionColumns = 1
    var _sectionColumnCounts: [Int] = []
    /// The columns of a body of sections that all have them, closed by a
    /// section of one with nothing in it (see `_resolveSections`); nil
    /// elsewhere.
    var _bodyColumns: Int? = nil
    /// The document's sections disagree on their columns: the layout has
    /// one count for the whole document (slots are `page * columns`), so
    /// one column — zh-8f9b19f4's thirteen sections are one column but
    /// for three of its last four, and the last's three columns set all
    /// fourteen of Word's pages in seven.
    var _oneColumn = false
    /// Paragraphs of a cover's one-column section in a file of more
    /// columns (see where `_oneColumn` is decided): set across the page,
    /// from the first column's edge.
    var _fullWidthCover: Set<Int> = []
    var _mirrorsMargins = false

    // MARK: Sections
    //
    // A document's sections may each have their own page: a paragraph
    // that ends one carries its page setup (`sectionPage`), and the last
    // section's is `pageSetup`. A paragraph wraps at its section's
    // column width, and a page is its first paragraph's section's.
    // (Columns are the document's throughout.)

    /// Each section's page, in order; the last is `pageSetup`.
    var _sectionSetups: [PageSetup] = []
    /// Each paragraph's section.
    var _sectionOf: [Int] = []
    /// Paragraph `i` stands in a vertical (tbRl) section.
    @inline(never) func _verticalBody(_ i: Int) -> Bool {
        let s = i < _sectionOf.count ? _sectionOf[i] : _sectionSetups.count
        return (s < _sectionSetups.count ? _sectionSetups[s] : pageSetup)?.vertical ?? false
    }
    /// Each page's section, and each page's top on the canvas.
    var _pageSection: [Int] = []
    /// Pages whose header and footer come from a later section than the one that sets the page up.
    var _pageHeaderSection: [Int: Int] = [:]
    /// Pages left blank so that a section opens on its number's side
    /// (`_paginate`): they have no number, header or footer.
    var _blankPages: Set<Int> = []
    /// Explicit odd/even section breaks count their blank page when
    /// numbering continues. Restart-alignment blanks do not.
    var _numberedBlankPages: Set<Int> = []
    var _pageTops: [Double] = []
    /// Where each page's text starts below its top (pixels): the top
    /// margin, or under a taller header.
    var _pageInsetTop: [Double] = []

    /// Paragraphs set on both sides of a box: per painter, how far each line
    /// is moved up (a right piece stands level with the left piece before
    /// it, and the lines after the pair stand as if it took no room) and the
    /// height all the right pieces give back.
    struct _PairedLines { weak var painter: TextPainter?; var shifts: [Double]; var saving: Double }

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
    var _spaceWidths: [String: Double] = [:]
    var _glyphCounts: [String: Int] = [:]
    var _wordWidths: [String: Double] = [:]
    var _clearedPainters: [ObjectIdentifier: [Int: (source: TextPainter, cleared: TextPainter)]] = [:]
    var _widePainters: [ObjectIdentifier: (source: TextPainter, wide: TextPainter)] = [:]

    // MARK: Painting

    /// A table row's shading — the header's, or a band's — under every cell
    /// of the row; drawn by its first cell's paragraph, before the selection.
    /// The pictures of paragraph `i` that float behind the text (`behindDoc`),
    /// drawn first, under the shading of every paragraph: lo-4dc8da49's red
    /// 260pt strip, anchored in its first paragraph, lies under the blue
    /// shading of all the paragraphs and under their text in Word's print;
    /// ours drew it after the shading, over them.
    var _behindDrawn: Set<String> = []
    var _shadingFloats = false

    // MARK: Headers and footers
    //
    // A file's header or footer is paragraphs like the body's
    // (`RichDocument.headerFooters`), laid out by a layout of its own at
    // the page's text width, with the page fields filled in for the page.
    // Its height matters to the body: Word starts the text under a
    // header taller than the top margin, and ends it above a footer
    // taller than the bottom one.

    struct _HeaderFooter {
        let layout: RichLayout
        let document: RichDocument
        /// A text box group's later boxes that stand beside another rather
        /// than under it: each laid out alone, painted `dy` below the box's
        /// top (pixels).
        var beside: [(layout: RichLayout, document: RichDocument, dy: Double, turn: (degrees: Double, x: Double, y: Double)?)] = []
        var height: Double { layout.totalHeight }
        /// Where a table placed against the PAGE opens the header stands below the paper's
        /// top (points), if it does: Word sets it there, not at the header distance
        /// (LibreOffice's tdf108272, tblpY 400 twips against a header of 720).
        var pageAnchoredTop: Double? {
            guard let first = document.paragraphs.first, let cell = first.cell,
                  let ts = document.tableStyles[cell.table], ts.pageAnchored, let off = ts.pageOffsetY else { return nil }
            return off
        }
        /// How far its floating frames stand above its first line
        /// (pixels, 0 where none does): they take no room in its flow.
        var frameRise: Double {
            guard layout.floatsFrames else { return 0 }
            var rise = 0.0
            for (i, p) in document.paragraphs.enumerated() where p.style.frame != nil && p.cell == nil && i < layout._tops.count {
                rise = max(rise, -(layout._tops[i] + layout._spaceBefore[i]))
            }
            return rise
        }
    }

    /// Set on a header's or footer's own layout: its framed paragraphs
    /// (a page number in a frame, as Word's "Insert Page Number" makes
    /// them) float — they take no room, and stand where the frame says,
    /// measured from the text's left, the margins `frameMargins` wide
    /// (points) on either side of it.
    public var floatsFrames = false
    /// Where a header's or footer's own top stands below the paper's top
    /// (pixels), set as it is painted: what its objects placed from the
    /// page or its margins measure from (`_floatRect`).
    public var regionTopOnPage: Double? = nil
    /// … and the page's top margin there (pixels).
    public var regionMarginTop: Double = 0
    /// … its bottom margin, and the page's height (pixels).
    public var regionMarginBottom: Double = 0
    public var regionPageHeight: Double = 0
    public var frameMargins: (left: Double, right: Double) = (0, 0)

    var _headerFooterCache: [String: _HeaderFooter] = [:]

    var _textBoxCache: [String: _HeaderFooter] = [:]
    var _imageParagraphs: [String: Int]? = nil
    /// The boxes Word's two lines in one are set in (`_span`), by their
    /// text and look: one attachment each, so its laid-out box is kept.
    var _combineBoxes: [String: ImageAttachment] = [:]

    /// Footnotes' own layouts, by note and width; and the footnotes set
    /// at the foot of each page, by physical page.
    var _noteCache: [String: _HeaderFooter] = [:]
    var _pageNotes: [Int: [Int]] = [:]
    /// A page of columns (all its sections the same number of them) sets
    /// its footnotes under the columns, in each one's own width: the room
    /// they take off the foot of every column of the page, per page. Found
    /// by laying out again until it settles (Word's lab fn-cols-long).
    var _columnNoteReserve: [Int: Double] = [:]
    var _columnNoteRaw: [Int: Double] = [:]
    var _slotNotes = false
    /// The column of the page each footnote's mark stands in (page of columns).
    var _noteColumn: [Int: Int] = [:]
    var _columnNoteRounds = 0
    var _columnNoteGeometry: [Int: (columns: Int, width: Double, stride: Double, left: Double, perColumn: Bool)] = [:]
    /// A note parted over two pages: the last at a page's foot shown to
    /// `keep` of its height (pixels), and its rest the first at the next
    /// page's — see where a body paragraph's notes are placed.
    var _noteCutOut: [Int: (id: Int, keep: Double)] = [:]
    var _noteCarryIn: [Int: (id: Int, from: Double)] = [:]

    /// How far paragraph `i`'s text starts from its column's left edge
    /// (its indents; a cell's place is left out of it).
    /// How far the column being painted stands right of the page's first
    /// column (pixels): a box placed from the page is placed from the page
    /// whatever column its anchor is in, and the paint moves by the column.
    var _floatColumnShift = 0.0
    /// 1 while the page's body is painted without its drop caps, 2 while only they are.
    var _dropCapPass = 0
    var _headerFooterSource: [RichHeaderFooter] = []
}
