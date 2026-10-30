// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The rich-text document model: paragraphs of character runs.
//
// This is the value half of the editing stack (docs/plans/office.md). It has
// no engine dependency at all — offsets are UTF-16 code units because that is
// what `TextPainter` speaks, but nothing here lays anything out — so it is
// unit-tested in the fast tier without a GPU. `RichDocumentController` owns
// the mutations, `RichLayout` the geometry, `RichEditable` the widget.
//
// Offsets are UTF-16 throughout. A caller that wants grapheme-aware motion
// (the caret must not land inside an emoji) goes through
// `RichParagraph.graphemeBefore/After`, which convert at the edge.

import FlutterSwiftBridge
import Foundation

// MARK: - Styles

/// Vertical position of a run: normal, superscript or subscript.
public enum ScriptPosition: Int, Hashable, Sendable {
    case normal
    case superscript
    case `subscript`
}

/// Character-level formatting. Every field is optional in the sense that
/// `nil`/`false` means "the document default" — the layout resolves those
/// against its `RichTextTheme`.
/// A footnote or endnote reference mark: the run it sits on shows the
/// note's number, and a save writes the reference back into the document's
/// kept notes part (`RichDocument.keptParts`), where the note's text lives.
public struct NoteReference: Hashable, Sendable {
    public enum Kind: Int, Hashable, Sendable { case footnote, endnote }
    public var kind: Kind
    /// The note's id in the file's footnotes/endnotes part.
    public var id: Int
    public init(kind: Kind, id: Int) { self.kind = kind; self.id = id }
}

/// A tracked change on a run: text someone inserted or deleted, shown
/// as Word shows it (underlined or struck through, in the reviewer's
/// colour) and saved back as the change it was.
/// A tracked FORMAT change on a run (Word's `w:rPrChange`): who changed
/// it, when, and the run properties it had before, kept as written so the
/// "Formatted:" balloon comes back (delins has thirty).
public struct FormatChange: Hashable, Sendable {
    public var author: String
    public var date: String
    public var oldRPrXML: String
    public init(author: String, date: String, oldRPrXML: String) {
        self.author = author; self.date = date; self.oldRPrXML = oldRPrXML
    }
}

public struct RevisionMark: Hashable, Sendable {
    public enum Kind: Int, Hashable, Sendable { case inserted, deleted }
    public var kind: Kind
    public var author: String
    public var date: String
    /// Moved text (Word's `w:moveTo`, an insertion, and `w:moveFrom`, a
    /// deletion): shown so in a print with markup, written back as the
    /// insertion or deletion it is.
    public var moved = false
    /// Changed twice, with a move: a deletion made in moved text's new
    /// place (the place still printed "Moved (insertion)"), or moved-away
    /// text that was itself an insertion (gone from a print, unremarked).
    public var nested = false
    public init(kind: Kind, author: String = "", date: String = "", moved: Bool = false, nested: Bool = false) {
        self.kind = kind; self.author = author; self.date = date; self.moved = moved; self.nested = nested
    }
}

/// The boolean switches of a `CharStyle`, as a set.
public struct CharSwitches: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let bold = CharSwitches(rawValue: 1)
    public static let italic = CharSwitches(rawValue: 2)
    public static let underline = CharSwitches(rawValue: 4)
    public static let strikethrough = CharSwitches(rawValue: 8)
    public static let caps = CharSwitches(rawValue: 16)
    public static let smallCaps = CharSwitches(rawValue: 32)
    public static let hidden = CharSwitches(rawValue: 64)
}

/// A shadow cast by a run's letters (PowerPoint's `a:outerShdw` on a
/// run): its colour, where it falls in points, and how far it blurs.
public struct CharShadow: Hashable, Sendable {
    public var color: Color
    public var dx: Double
    public var dy: Double
    public var blur: Double
    /// A shape's shadow scaled alike both ways (`sx` = `sy`), about the
    /// point of the shape `anchor` names in fractions of its box (0, 0
    /// its top left; PowerPoint's `algn`). 1 for none; text ignores it.
    public var scale: Double = 1
    public var anchor = Offset(0.5, 0.5)
    public init(color: Color, dx: Double, dy: Double, blur: Double) {
        self.color = color; self.dx = dx; self.dy = dy; self.blur = blur
    }
}

public struct CharStyle: Hashable, Sendable {
    public var bold = false
    public var italic = false
    public var underline = false
    public var strikethrough = false
    public var fontFamily: String? = nil
    /// In points, the unit documents are written in (11pt, not 14.67px).
    public var fontSize: Double? = nil
    public var color: Color? = nil
    public var highlight: Color? = nil
    public var link: String? = nil
    public var script: ScriptPosition = .normal
    /// Set on the run that is a footnote/endnote reference mark.
    public var note: NoteReference? = nil
    /// Set on a one-character run (U+FFFC) that is a picture inline with
    /// the text: the id of an entry in the paragraph's `inlineImages`.
    public var inlineImage: String? = nil
    /// Set on a run that is a tracked insertion or deletion.
    public var revision: RevisionMark? = nil
    /// A tracked change to this run's formatting, with what it was.
    public var formatChange: FormatChange? = nil
    /// Switches this run turns OFF under a style that turns them on
    /// (Word's `w:b w:val="0"`): a false `bold` alone means "inherit".
    public var off: CharSwitches = []
    /// Word's All caps: the run's letters shown as capitals (the text
    /// itself keeps its case).
    public var caps = false
    /// Word's Small caps: lowercase letters shown as smaller capitals.
    public var smallCaps = false
    /// Word's hidden text (w:vanish): kept in the document, not shown or
    /// printed.
    public var hidden = false
    /// Extra space between characters in points (Word's w:spacing on a
    /// run); negative condenses.
    public var letterSpacing: Double? = nil
    /// Word's run-level right-to-left flag (w:rtl), which decides how
    /// neutral characters and digits sit in a right-to-left paragraph.
    public var rightToLeft = false
    /// Kerning from this size up, in points (Word's w:kern); nil for none.
    public var kerningFrom: Double? = nil
    /// Word's character scale (`w:w`): the letters set this much
    /// narrower or wider than drawn, their height as it was — a
    /// letterhead's name squeezed onto one line. 1 or nil for none.
    public var horizontalScale: Double? = nil
    /// Word's raised or lowered text (`w:position`): the baseline this
    /// many points up (negative: down), the line's height as it was.
    public var raised: Double? = nil
    /// The faces a file names for complex-script (Arabic, Hebrew) and
    /// East Asian characters when it names them (Word's w:cs and
    /// w:eastAsia font slots); nil means `fontFamily` serves them too.
    public var complexFontFamily: String? = nil
    public var eastAsiaFontFamily: String? = nil
    /// The face for the rest of the Latin range (`w:hAnsi`) when the file
    /// names another than `fontFamily` (its `w:ascii`), and `w:hint`:
    /// which face Word sets the characters both scripts claim — the
    /// curly quotes, dashes and ellipses of Chinese text — in.
    public var hAnsiFontFamily: String? = nil
    public var fontHint: String? = nil
    /// A shadow under the letters; nil for none.
    public var shadow: CharShadow? = nil
    /// Run properties the editor does not draw by, as the file wrote
    /// them (`w:w` character scale, `w:position`, `w:bdr`, `w:lang`,
    /// `w:em`, `w:fitText`, `w:snapToGrid`): written back with the run.
    public var keptXML: String? = nil
    /// Ids of the comments whose ranges cover this run (the comments
    /// themselves live in the kept `word/comments.xml`).
    public var comments: [String] = []
    /// The instruction of the field this text is the shown result of
    /// (`PAGEREF _Toc123 \h`): written back as the field, so Word can
    /// still bring a contents page's numbers up to date.
    public var field: String? = nil
    /// Ruby set over this run's text (Word's `w:ruby`: furigana over
    /// kanji); nil for none.
    public var ruby: RubyText? = nil
    /// Set on the first run of a field's result whose field code was
    /// reformatted under change tracking: Word's markup shows "Field Code
    /// Changed" there. Read, not written back.
    public var fieldCodeChanged = false
    /// Which field's shown result this run is, numbered through the
    /// document (0 for none): Word's markup ends a "Formatted:" stretch
    /// at a field's ends. Read, not written back.
    public var fieldResult = 0

    public init(bold: Bool = false, italic: Bool = false, underline: Bool = false,
                strikethrough: Bool = false, fontFamily: String? = nil,
                fontSize: Double? = nil, color: Color? = nil, highlight: Color? = nil,
                link: String? = nil, script: ScriptPosition = .normal, note: NoteReference? = nil,
                letterSpacing: Double? = nil, caps: Bool = false) {
        self.caps = caps
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.color = color
        self.highlight = highlight
        self.link = link
        self.script = script
        self.note = note
        self.letterSpacing = letterSpacing
    }

    public static let plain = CharStyle()
}

/// Ruby over a run of text (Word's `w:ruby`): the small text set above
/// the base — a reading over kanji — at `size` points, its baseline
/// `raise` points over the base's. `group` tells one ruby from the next
/// that says the same (runs of one ruby are one base); `xml` is the
/// file's `w:rubyPr` and `w:rt`, written back as they were.
public struct RubyText: Hashable, Sendable {
    public var text: String
    public var size: Double
    public var raise: Double
    /// Word's `w:rubyAlign` ("distributeSpace", "center", …); nil for its default.
    public var align: String?
    public var group: Int
    public var xml: String

    public init(text: String, size: Double, raise: Double, align: String? = nil, group: Int = 0, xml: String = "") {
        self.text = text
        self.size = size
        self.raise = raise
        self.align = align
        self.group = group
        self.xml = xml
    }
}

public enum ParagraphAlignment: Int, Hashable, Sendable {
    case left
    case center
    case right
    case justify
}

public enum ListKind: Int, Hashable, Sendable {
    case bullet
    case numbered
}

/// One edge of a paragraph border: a line of `width` points in `color`
/// (nil for the text colour), `space` points away from the text.
public struct BorderLine: Hashable, Sendable {
    public var width: Double
    public var color: Color?
    public var space: Double
    /// Word's line style when it is not a single line ("double",
    /// "thinThickSmallGap", …): drawn as a single line here, written back
    /// by name — the thick-and-thin red rule under an official letterhead.
    public var style: String? = nil
    public init(width: Double = 0.75, color: Color? = nil, space: Double = 1) {
        self.width = width
        self.color = color
        self.space = space
    }
}

/// A header or footer part kept as the file had it (see
/// `RichDocument.keptHeaderFooters`).
public struct KeptHeaderFooter: Hashable, Sendable {
    public enum Kind: Int, Hashable, Sendable { case header, footer }
    public var kind: Kind
    /// Word's type: "default", "first" or "even".
    public var type: String
    /// The package path of the part, a key of `keptParts`.
    public var part: String
    /// Its text as read, with the page fields as placeholders.
    public var text: String
    public init(kind: Kind, type: String, part: String, text: String) {
        self.kind = kind; self.type = type; self.part = part; self.text = text
    }
}

/// Where an anchored object floats (`ImageAttachment.float`): its
/// offsets in points from what Word measures them from ("column",
/// "margin", "page", "paragraph", "line"…), or an alignment in place of
/// an offset ("left", "center", "right"; "top", "bottom"), and whether
/// the text keeps clear above and below it (`wp:wrapTopAndBottom`).
public struct ImageFloat: Hashable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var horizontalFrom = "column"
    public var verticalFrom = "paragraph"
    public var horizontalAlign: String? = nil
    public var verticalAlign: String? = nil
    public var takesRoom = false
    /// A table nested in a cell and floating that is placed against the
    /// text (`w:vertAnchor="text"`), not the page: only that one is as
    /// tall in its row as it lays out (see the row's height).
    public var againstText = false
    /// Placed against the page or its margin with the text above and
    /// below it (`takesRoom` as the file has it): a band of its page the
    /// text keeps off, wherever on the page its anchor is — laid out and
    /// drawn as a free float, `takesRoom` false.
    public var bandsPage = false
    /// Text wraps round it (Word's square, tight and through wrapping):
    /// the lines beside it are shorter, or start under it.
    public var wraps = false
    /// … on which side (`wrapText` of `wp:wrapSquare`/`Tight`/`Through`,
    /// VML's `w10:wrap side`): "left" or "right" alone, or nil for both.
    public var wrapSide: String? = nil
    /// How far its drawn effects reach below its box (`wp:effectExtent`'s
    /// `b`, points): its outline's and shadow's share of the room Word
    /// gives it.
    public var effectBottom = 0.0
    /// How far text keeps from its top and its foot where it wraps round
    /// it (`wp:anchor`'s `distT`/`distB`, VML's `mso-wrap-distance-top`
    /// and `-bottom`), in points.
    public var distanceTop = 0.0
    public var distanceBottom = 0.0
    /// A height that is a share of the page's or its margins' height
    /// (`wp14:sizeRelV`'s `pctHeight`, as a fraction), measured from
    /// `heightFrom` ("page" or "margin"): the box and its effects take
    /// that share, in place of the file's fixed extent.
    public var heightShare: Double? = nil
    public var heightFrom = "margin"
    public init() {}
}

/// A text box's contents (`ImageAttachment.textBox`): its paragraphs,
/// and how far inside the box's edges they are set, in points.
public struct RichTextBox: Hashable, Sendable {
    public var paragraphs: [RichParagraph]
    public var insetLeft = 7.2
    public var insetTop = 3.6
    public var insetRight = 7.2
    public var insetBottom = 3.6
    /// The box takes its text's width (`wrap="none"` with `spAutoFit`,
    /// or VML's `mso-wrap-style:none` with `mso-fit-shape-to-text`):
    /// Word shrinks it to the text before it places it.
    public var fitsText = false
    /// The box takes its text's height (VML's `mso-fit-shape-to-text`
    /// without `mso-wrap-style:none`): in the line, it is as tall as its
    /// text and insets, whatever its own height says.
    public var fitsHeight = false
    /// … and is sized once, on the first page its header or footer is on
    /// (lab `ftD`, DrawingML; lab `vf`, VML alike).
    public var fitsOnce = false
    /// … and is DrawingML's (`wps:bodyPr`), not VML's: an em dash its
    /// text says is Latin (`w:hint` "default") is then set as Latin when
    /// the box is fitted, where a VML box's is not.
    public var fitsAsDrawing = false
    /// DrawingML's explicit `noAutofit`: the saved frame is fixed.
    /// Used to retain an overflowing first-line indent at its stated
    /// position and clip that corrected line to the frame.
    public var hasFixedFrame = false
    /// The tables among `paragraphs` (their cells' `CellRef.table`), with
    /// their looks and grids: a table nested in a cell is read as a box
    /// of its own, laid out as a document is.
    public var tableStyles: [String: TableStyle] = [:]
    public var tableColumns: [String: [Double]] = [:]
    /// The box is as tall as what is in it lays out (a nested table),
    /// not as `ImageAttachment.height` says.
    public var growsToFit = false
    /// The boxes after the first in a group of them (`wpg:wgp`): where
    /// each one's paragraphs start in `paragraphs`, and its place in the
    /// group in points — its top, its height, and whether its text
    /// stands at its foot (`anchor="b"`) or in its middle (`anchor="ctr"`).
    public struct Part: Hashable, Sendable {
        public var first: Int
        public var top: Double
        public var height: Double
        public var atFoot: Bool
        public var inMiddle = false
        public init(first: Int, top: Double, height: Double, atFoot: Bool, inMiddle: Bool = false) {
            self.first = first; self.top = top; self.height = height; self.atFoot = atFoot; self.inMiddle = inMiddle
        }
    }
    public var parts: [Part] = []
    /// Where the text of a box with a fixed frame stands in it, when not at
    /// its top (`wps:bodyPr anchor`): "ctr" in its middle, "b" at its foot.
    public var anchor: String? = nil
    /// Which way the box's text runs (`wps:bodyPr vert`): across, or
    /// turned a quarter — `vert270` reads up from the box's foot, its
    /// lines stacking rightwards from its left; `vert` reads down from
    /// its top, stacking leftwards from its right. Turned, its lines are
    /// as long as the box is tall.
    public var textDirection: CellRef.CellTextDirection = .horizontal
    /// East Asian vertical writing (`eaVert`): the text runs down as
    /// `vert` does, but an ideograph stands upright in it — as a cell's
    /// `uprightIdeographs`.
    public var uprightIdeographs = false
    public init(paragraphs: [RichParagraph]) { self.paragraphs = paragraphs }
}

/// Where a framed paragraph (`w:framePr`) is set: its offsets in points
/// from what it is anchored to ("text", "margin" or "page"), or an
/// alignment in place of one ("center", "right"; "top", "bottom"), and
/// its width where it states one.
public struct ParagraphFrame: Hashable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double? = nil
    public var horizontalAnchor = "text"
    public var verticalAnchor = "text"
    public var horizontalAlign: String? = nil
    public var verticalAlign: String? = nil
    public init() {}
}

/// A header or footer as the paragraphs the file wrote (with the
/// tables and pictures among them), for the layout to set on each page:
/// `kind` and `type` as `KeptHeaderFooter`'s. A run whose `field` is
/// PAGE or NUMPAGES shows that page's number, or the count. `section`
/// is the section whose pages it is for, counted as the layout counts
/// them (a paragraph that carries a `sectionPage` ends one) — what a
/// section does not name it has from the one before, type by type —
/// or nil for every page of the document.
public struct RichHeaderFooter: Hashable, Sendable {
    public var kind: KeptHeaderFooter.Kind
    public var type: String
    public var paragraphs: [RichParagraph]
    public var section: Int?
    public init(kind: KeptHeaderFooter.Kind, type: String, paragraphs: [RichParagraph], section: Int? = nil) {
        self.kind = kind; self.type = type; self.paragraphs = paragraphs; self.section = section
    }
}

/// A table nested in a cell, kept as the file wrote it (see
/// `RichDocument.keptTables`): the editor shows its text flattened into
/// the cell; the save writes this markup back while that text stands.
public struct KeptTable: Hashable, Sendable {
    public var xml: String
    public var rels: [KeptRel]
    /// The flattened paragraphs' texts as read, in order.
    public var texts: [String]
    public init(xml: String, rels: [KeptRel], texts: [String]) {
        self.xml = xml; self.rels = rels; self.texts = texts
    }
}

/// A tab stop: `position` points from the paragraph's left edge.
public struct TabStop: Hashable, Sendable {
    public enum Alignment: Int, Hashable, Sendable { case left, center, right, decimal }
    public var position: Double
    public var alignment: Alignment
    /// The fill before the tab ("dot" in a table of contents) and Word's
    /// own kind where `alignment` only stands in for it ("num", "bar"):
    /// not drawn here, written back.
    public var leader: String? = nil
    public var rawKind: String? = nil
    public init(position: Double, alignment: Alignment = .left) {
        self.position = position
        self.alignment = alignment
    }
}

/// A paragraph's borders, each edge its own line or none.
public struct ParagraphBorders: Hashable, Sendable {
    public var top: BorderLine? = nil
    public var bottom: BorderLine? = nil
    public var left: BorderLine? = nil
    public var right: BorderLine? = nil
    public init(top: BorderLine? = nil, bottom: BorderLine? = nil, left: BorderLine? = nil, right: BorderLine? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
    public var isEmpty: Bool { top == nil && bottom == nil && left == nil && right == nil }
}

/// Paragraph-level formatting. Lengths are in points.
public struct RichParagraphStyle: Hashable, Sendable {
    public var alignment: ParagraphAlignment = .left
    public var indentLeft: Double = 0
    public var indentRight: Double = 0
    /// Where a group's text boxes are set in one text (`RichTextBox.parts`),
    /// the right inset of the box this paragraph stands in, in points —
    /// its indents hold its box's place and both insets. nil elsewhere.
    public var boxInsetRight: Double? = nil
    public var firstLineIndent: Double = 0
    /// Points. What the paragraph says, and what the layout draws: 0 is
    /// no space, not "the default" — a file's Heading 1 that says 0 after
    /// gets 0 after. The defaults are Word's Normal (8pt after, 1.08
    /// lines); readers fill in what the file's own defaults say.
    public var spaceBefore: Double = 0
    public var spaceAfter: Double = 8
    /// Word's "auto" spacing (w:beforeAutospacing/w:afterAutospacing,
    /// HTML's paragraph gap): 14pt, none between items of one list; the
    /// stated `spaceBefore`/`spaceAfter` is then ignored.
    public var spaceBeforeAuto = false
    public var spaceAfterAuto = false
    /// Multiple of the font's natural line height (1.0 = single).
    public var lineSpacing: Double = 1.08
    /// Slides: no spacing is said for the paragraph anywhere (its
    /// single is the format's default, not a stated 100%), which a
    /// shrink-to-fit's reduction treats otherwise (`RichTextTheme
    /// .baselineShift`). False — Word's — for every paragraph.
    public var lineSpacingUnstated = false
    /// Exact line height in points ("exactly 20 pt"), which then wins over
    /// `lineSpacing`; nil for a multiple.
    public var lineHeightPoints: Double? = nil
    /// With `lineHeightPoints`: a minimum ("at least 20 pt") rather than
    /// an exact height — a taller font still gets its own line.
    public var lineHeightIsMinimum = false
    /// Word's line spacing of no lines (`w:line="0"`, a multiple): the
    /// paragraph takes its spacing before and after and no line, and
    /// what text it has is not shown — a footer's last empty paragraph,
    /// written so by converters to take no room.
    public var lineCollapsed = false
    /// The empty paragraph that ends a cell right under a table nested
    /// in it, which Word sets at half a point whatever its mark says
    /// (drawing.docx: five such marks of 8.5pt, five lines of 0.48pt in
    /// Word's print). Read from the file's shape, not written back.
    public var markUnderNestedTable = false
    /// Points: the room a page's frame — a one-cell table read as the
    /// body (Word's invisible wrapper) — keeps inside each page it goes on
    /// to, over the text and under it: its cell's top and bottom margin
    /// and twice its cell spacing. Set on each of its paragraphs.
    public var frameInsetTop = 0.0
    public var frameInsetBottom = 0.0
    public var list: ListKind? = nil
    public var listLevel: Int = 0
    /// The glyph this bulleted paragraph shows, when the file names one
    /// (PowerPoint's `buChar`); nil for the list's or the level's own.
    public var bulletText: String? = nil
    /// The marker's own colour and size as a share of the text's
    /// (PowerPoint's `buClr`, `buSzPct`); nil follows the text.
    public var bulletColor: Color? = nil
    public var bulletScale: Double? = nil
    /// The face the marker is set in (PowerPoint's `buFont`); nil is the
    /// text's. Arial's bullet is two thirds the width of Calibri's.
    public var bulletFontFamily: String? = nil
    /// How a bullet that stands in for a symbol face's is drawn — its
    /// face and how much larger than its size — where the stand-in's
    /// glyph is not the symbol's size: Wingdings' round bullet is 0.565
    /// of an em, the "●" drawn for it 0.46 in Carlito. Drawing only:
    /// `bulletFontFamily` and `bulletScale` stay the file's.
    public var bulletStandInFamily: String? = nil
    public var bulletStandInScale: Double? = nil
    /// A picture bullet (PowerPoint's `buBlip`): drawn by the slide in the
    /// bullet's place, the marker itself left empty.
    public var bulletPicture: ImageAttachment? = nil
    /// Which list this paragraph belongs to, for numbering: Word's numId.
    /// Items of one id number on across other paragraphs; nil items number
    /// as a run, restarting after an interruption.
    public var listId: String? = nil
    /// A list paragraph's OWN left indent, in points, when it states one:
    /// direct formatting that overrides its level's (`ListLevelFormat.
    /// indentLeft`). nil is the level's. bug65649's appendix says left 0
    /// under levels indented 6186 twips, and lost it, so every numbered
    /// clause started two-thirds of the way across the page.
    public var listIndentLeft: Double? = nil
    /// The paragraph mark is hidden text (w:vanish on w:pPr/w:rPr). With
    /// every run hidden too, Word shows nothing of the paragraph, borders
    /// included; without the mark's flag the line stays, empty, with its
    /// rules (bug59058's "Bottom of Form" paragraphs).
    public var markHidden = false
    /// The paragraph's own properties, not its style's, turn the
    /// document grid off (`w:snapToGrid` 0 on its `w:pPr`): Word then
    /// keeps its Latin text on the character grid all the same.
    public var ownGridOff = false
    /// The HTML block this paragraph came from (Word's `w:divId`, an
    /// entry of the kept web settings part): Word spaces the paragraph by
    /// that block's margins, so the reference goes back with the part.
    public var divId: String? = nil
    /// East Asian typography the editor does not lay out by, as the file
    /// (and the styles under the paragraph) stated it, by Word's name:
    /// the switches `w:snapToGrid`, `w:kinsoku`, `w:wordWrap`,
    /// `w:overflowPunct`, `w:topLinePunct`, `w:autoSpaceDE`,
    /// `w:autoSpaceDN`, `w:adjustRightInd` ("1"/"0"), `w:textAlignment`,
    /// and the measures in character and line units that override the
    /// point ones (`w:firstLineChars`, `w:leftChars`, `w:beforeLines`, …).
    /// A Chinese document is set on a line grid with these; written back
    /// on every paragraph so Word sets the copy the same way.
    public var eastAsian: [String: String] = [:]
    /// The paragraph mark's own run properties as the file had them
    /// (w:pPr/w:rPr), written back on every paragraph that had any: Word
    /// formats a list paragraph's NUMBER with them (bug65649's bold "1."
    /// came back small and plain), and sizes a last line by them.
    public var mark: CharStyle? = nil
    /// A list paragraph's own first-line indent, in points, when it states
    /// one (negative hangs): direct formatting above its level's hanging,
    /// zero included. nil is the level's.
    public var listFirstLine: Double? = nil
    /// 1...6 for a heading, nil for body text. The outline level is what
    /// `.docx`, RTF and Markdown all carry; the look comes from the
    /// document's style sheet ("Heading1"...) when it has that entry.
    public var heading: Int? = nil
    /// A named style other than a heading: "Title", "Quote", ... — an id in
    /// the document's `RichStyleSheet`. Applying one copies its paragraph
    /// props here and the layout takes its character defaults from the
    /// sheet, under any direct formatting.
    public var named: String? = nil
    public var pageBreakBefore = false
    /// The page break is a break character at the paragraph's start
    /// (Word's `w:br w:type="page"` in its first run), not the paragraph
    /// property: laid out the same here, written back as it was — Word
    /// places the text after one differently by the paragraph's spacing.
    public var pageBreakInline = false
    /// That break character is a COLUMN break (`w:br w:type="column"`):
    /// a new page here, where a page is one column, and written back as
    /// the column break it was.
    public var columnBreak = false
    /// The run properties that break character was written with, as the
    /// file had them: Word measures an indent counted in characters by
    /// the paragraph's first run, and the break is it.
    public var breakRunPropertiesXML: String? = nil
    /// The page break is a break character ENDING the paragraph before
    /// (a paragraph that is only the break, most often): written back
    /// there — Word drops the space before a paragraph that follows a
    /// break character, and keeps it under "page break before".
    public var breakEndsPrevious = false
    /// The paragraph is the rest of one a break character split (its
    /// `w:p` went on past a `w:br w:type="page"`): its first line is no
    /// first line, and takes no first-line indent.
    public var continuesParagraph = false
    /// The paragraph opens with its own page break right after a
    /// paragraph that ended with one: two breaks, and the page between
    /// them stands blank (its start before the break is all it holds).
    public var pageBreakTwice = false
    /// Word's pagination hints, kept through a save (the layout paginates
    /// its own way): keep with next, keep lines together, widow control.
    public var keepNext = false
    public var keepLines = false
    public var widowControl = true
    /// Lines around the paragraph (Word's paragraph borders); nil for none.
    public var borders: ParagraphBorders? = nil
    /// A fill behind the whole paragraph (Word's paragraph shading).
    public var fill: Color? = nil
    /// Word's frame (w:framePr: a paragraph positioned on the page), kept
    /// as written for the save; the layout flows it like any other.
    public var frameXML: String? = nil
    /// That frame's place, read off it: see `ParagraphFrame`.
    public var frame: ParagraphFrame? = nil
    /// Word's "don't add space between paragraphs of the same style"
    /// (w:contextualSpacing): the space before/after is dropped where the
    /// neighbour has the same named style.
    public var contextualSpacing = false
    /// The section this paragraph ends, as Word wrote it (a `w:sectPr`
    /// without its header/footer references): page size, margins,
    /// columns, numbering. The layout shows one page size for the whole
    /// document; the saved file keeps every section's.
    public var sectionXML: String? = nil
    /// That section's page — size, margins, gutter — where it states
    /// one: the pages its paragraphs are laid out on. (The document's
    /// last section's is the layout's own page setup.)
    public var sectionPage: PageSetup? = nil
    /// The header and footer parts that section names, kept with it: the
    /// sections after it that name none show the same ones.
    public var sectionRels: [KeptRel] = []
    /// Whether the section AFTER this one starts a page — which is the
    /// next section's `w:type` to say, not this one's.
    public var sectionBreaksPage: Bool? = nil
    /// Right-to-left paragraph direction (Word's w:bidi): the lines run
    /// from the right and "left" alignment means the start edge.
    public var rightToLeft = false
    /// Custom tab stops (Word's w:tabs), kept through a save; the layout
    /// still uses the default tab width.
    public var tabStops: [TabStop] = []
    /// Positional tabs (Word's w:ptab), by the paragraph's count of tabs
    /// before them: each goes to its place on the margins (left, centre,
    /// right), past whatever stops lie between.
    public var positionalTabs: [Int: TabStop.Alignment] = [:]
    /// A tracked change to the paragraph mark itself: deleted, the
    /// paragraph joins the next once accepted (and Word prints nothing
    /// for a paragraph whose text and mark are both deleted).
    public var markRevision: RevisionMark? = nil

    public init(alignment: ParagraphAlignment = .left, indentLeft: Double = 0,
                indentRight: Double = 0, firstLineIndent: Double = 0,
                spaceBefore: Double = 0, spaceAfter: Double = 8,
                lineSpacing: Double = 1.08, list: ListKind? = nil, listLevel: Int = 0,
                listId: String? = nil, heading: Int? = nil, named: String? = nil,
                pageBreakBefore: Bool = false) {
        self.alignment = alignment
        self.indentLeft = indentLeft
        self.indentRight = indentRight
        self.firstLineIndent = firstLineIndent
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.lineSpacing = lineSpacing
        self.list = list
        self.listLevel = listLevel
        self.listId = listId
        self.heading = heading
        self.named = named
        self.pageBreakBefore = pageBreakBefore
    }

    /// Word's Normal: 8pt after, 1.08 lines.
    public static let body = RichParagraphStyle()
    /// A table cell's, as Word's Table Grid sets it: no space after,
    /// single lines. Readers take a file's own table style over this.
    public static let cell = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
}

// MARK: - Named styles

/// One entry of a document's style sheet: Word's Title, Heading 1, Quote…
/// `paragraph` is copied onto a paragraph when the style is applied;
/// `char` supplies the defaults a run's own formatting does not set.
public struct RichNamedStyle: Hashable, Sendable {
    public var id: String
    public var name: String
    public var paragraph: RichParagraphStyle
    public var char: CharStyle
    /// The style Enter at the end of the paragraph moves to; nil keeps it.
    public var next: String?

    public init(id: String, name: String, paragraph: RichParagraphStyle = .body,
                char: CharStyle = CharStyle(), next: String? = nil) {
        self.id = id
        self.name = name
        self.paragraph = paragraph
        self.char = char
        self.next = next
    }

    public static let normalId = "Normal"
    public static func headingId(_ level: Int) -> String { "Heading\(level)" }
}

/// The style sheet, in gallery order. `word` is what a new document gets;
/// a `.docx` replaces entries with what its own styles.xml says.
public struct RichStyleSheet: Hashable, Sendable {
    public var styles: [RichNamedStyle]

    public init(styles: [RichNamedStyle]) { self.styles = styles }

    public subscript(id: String) -> RichNamedStyle? {
        get { styles.first { $0.id == id } }
        set {
            if let i = styles.firstIndex(where: { $0.id == id }) {
                if let newValue { styles[i] = newValue } else { styles.remove(at: i) }
            } else if let newValue {
                styles.append(newValue)
            }
        }
    }

    /// The entry a paragraph's style resolves to: its named style, else
    /// its heading's, else nil for body text.
    public func resolve(_ style: RichParagraphStyle) -> RichNamedStyle? {
        if let n = style.named { return self[n] }
        if let h = style.heading { return self[RichNamedStyle.headingId(h)] }
        return nil
    }

    public func id(of style: RichParagraphStyle) -> String {
        resolve(style)?.id ?? (style.heading.map(RichNamedStyle.headingId) ?? RichNamedStyle.normalId)
    }

    /// Give `style` the named style `id`: the sheet's paragraph props
    /// replace the direct ones (Word copies them the same way), the list
    /// and page-break flags survive, and the outline level follows the
    /// entry. Unknown ids are ignored.
    public func apply(_ id: String, to style: inout RichParagraphStyle) {
        let entry: RichNamedStyle
        if id == RichNamedStyle.normalId {
            entry = self[id] ?? RichNamedStyle(id: id, name: "Normal")
        } else {
            guard let e = self[id] else { return }
            entry = e
        }
        var s = entry.paragraph
        s.list = style.list
        s.listLevel = style.listLevel
        s.listId = style.listId
        s.pageBreakBefore = style.pageBreakBefore
        s.heading = entry.paragraph.heading
        s.named = id == RichNamedStyle.normalId || entry.paragraph.heading != nil ? nil : id
        style = s
    }

    /// Word's defaults, in points.
    public static let word: RichStyleSheet = {
        let blue = Color(0xFF2F5496)
        func heading(_ n: Int, _ size: Double, bold: Bool, italic: Bool = false,
                     before: Double, after: Double) -> RichNamedStyle {
            RichNamedStyle(id: RichNamedStyle.headingId(n), name: "Heading \(n)",
                           paragraph: RichParagraphStyle(spaceBefore: before, spaceAfter: after, heading: n),
                           char: CharStyle(bold: bold, italic: italic, fontSize: size, color: blue),
                           next: RichNamedStyle.normalId)
        }
        return RichStyleSheet(styles: [
            RichNamedStyle(id: RichNamedStyle.normalId, name: "Normal"),
            RichNamedStyle(id: "Title", name: "Title",
                           paragraph: RichParagraphStyle(spaceAfter: 4, lineSpacing: 1.0),
                           char: CharStyle(fontSize: 28, color: Color(0xFF1F3864)), next: RichNamedStyle.normalId),
            RichNamedStyle(id: "Subtitle", name: "Subtitle",
                           paragraph: RichParagraphStyle(spaceAfter: 8),
                           char: CharStyle(fontSize: 13, color: Color(0xFF5A5A5A)), next: RichNamedStyle.normalId),
            heading(1, 20, bold: true, before: 12, after: 4),
            heading(2, 16, bold: true, before: 8, after: 4),
            heading(3, 14, bold: true, before: 8, after: 4),
            heading(4, 12, bold: true, italic: true, before: 4, after: 2),
            heading(5, 11, bold: false, before: 4, after: 2),
            heading(6, 11, bold: false, italic: true, before: 4, after: 2),
            RichNamedStyle(id: "Quote", name: "Quote",
                           paragraph: RichParagraphStyle(alignment: .center, indentLeft: 36, indentRight: 36,
                                                         spaceBefore: 8, spaceAfter: 8),
                           char: CharStyle(italic: true, color: Color(0xFF404040))),
            RichNamedStyle(id: "Caption", name: "Caption",
                           paragraph: RichParagraphStyle(spaceAfter: 10),
                           char: CharStyle(italic: true, fontSize: 9, color: Color(0xFF44546A)),
                           next: RichNamedStyle.normalId),
            RichNamedStyle(id: "Code", name: "Code",
                           paragraph: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0),
                           char: CharStyle(fontSize: 10)),
        ])
    }()
}

// MARK: - Images

/// A picture that is a paragraph of its own: encoded bytes (PNG, JPEG,
/// GIF, WebP — whatever the engine decodes) and the size it is shown at, in
/// points. `id` identifies the bytes for decode caches without hashing them
/// on every paint.
/// A relationship an opaque object's markup names — its chart part, its
/// embedded workbook, a hyperlink — carried so a save can put it back
/// under a fresh id.
public struct KeptRel: Hashable, Sendable {
    public var id: String
    public var type: String
    public var target: String
    public var external: Bool
    public init(id: String, type: String, target: String, external: Bool) {
        self.id = id; self.type = type; self.target = target; self.external = external
    }
}

/// What of a drawn shape the layout draws itself: a straight line, or
/// a box's outline (and fill), in the line's colour and width (points).
/// The rule under a letterhead and the frame of a text box are these;
/// every other shape is kept for the file and not drawn.
public struct ShapeOutline: Hashable, Sendable {
    public enum Kind: Sendable { case line, box }
    public var kind: Kind
    public var color: Color?
    public var width: Double
    public var fill: Color? = nil
    /// A line that runs from the bottom left to the top right.
    public var flipped = false
    /// A box's effects (`a:effectLst`): its blur's radius (`a:blur`),
    /// in points, 0 for none; and its inner shadow (`a:innerShdw`) —
    /// what lies outside it, moved by `dx`/`dy` and blurred by `blur`,
    /// seen inside it.
    public var blur = 0.0
    public var innerShadow: (color: Color, dx: Double, dy: Double, blur: Double)? {
        get { _innerShadow.map { ($0.color, $0.dx, $0.dy, $0.blur) } }
        set { _innerShadow = newValue.map { InnerShadow(color: $0.color, dx: $0.dx, dy: $0.dy, blur: $0.blur) } }
    }
    private struct InnerShadow: Hashable, Sendable { var color: Color; var dx: Double; var dy: Double; var blur: Double }
    private var _innerShadow: InnerShadow? = nil
    public init(kind: Kind, color: Color?, width: Double) { self.kind = kind; self.color = color; self.width = width }
}

public struct ImageAttachment: Hashable, Sendable {
    public let id: String
    public var data: Data
    public var width: Double
    public var height: Double
    /// A file name for formats that store media as parts ("image1.png").
    public var name: String
    /// The pixel size as points at 96/in, when the inserter knew it: what
    /// "Original Size" restores. nil for a picture from a file format.
    public var naturalWidth: Double? = nil
    public var naturalHeight: Double? = nil
    /// For an object the editor cannot show (a chart, a shape, an embedded
    /// file): the file's own markup for it, kept verbatim and written back
    /// as it was, with `sourceRels` for the parts and links it names. Such
    /// an attachment has no decodable `data` and lays out as an empty box
    /// of its size.
    public var sourceXML: String? = nil
    public var sourceRels: [KeptRel] = []
    /// A kept shape's outline, where it is one the layout draws.
    public var outline: ShapeOutline? = nil
    /// The size the kept markup was read at, in points: an inline picture
    /// is written from `sourceXML` only while it still has this size, and
    /// regenerated once the editor resized it. (An anchored one is always
    /// kept.) issue_51265_3's four inline pictures lost their effectExtent
    /// when regenerated, and the row of them wrapped elsewhere.
    public var sourceWidth: Double? = nil
    public var sourceHeight: Double? = nil
    /// The properties of the run the picture sat in (`w:rPr`), as the
    /// file wrote them: a character border round a thumbnail, the size
    /// that sets the line it stands on. Written back with `sourceXML`.
    public var sourceRunPropertiesXML: String? = nil
    /// A character border round the picture in its line (`w:bdr` on the
    /// run it sits in): drawn `space` out from the picture's box, and
    /// its line taller by `space + width` above and below. bug59058's
    /// "tab1", 72.75pt in a 0.75pt grey frame, stands on a line of 75 in
    /// Word's print (with its effect extent below).
    public var frame: BorderLine? = nil
    /// How far an inline picture's effects reach past each edge of its
    /// box (`wp:effectExtent`, points): its line holds all four sides.
    public var effectLeft = 0.0
    public var effectRight = 0.0
    public var effectTop = 0.0
    /// Where the object's own baseline stands, in points from its top,
    /// where it has one (an equation's): set in a line, it stands there.
    public var baseline: Double? = nil
    public var effectBottom = 0.0
    /// For an object anchored to its paragraph rather than standing in
    /// the line (Word's `wp:anchor`): where it floats. The text makes no
    /// room for it in the line, and none above and below unless it
    /// `takesRoom`. nil for an object in the line.
    public var float: ImageFloat? = nil
    /// The picture's turn, in degrees clockwise (`a:xfrm rot` / 60000):
    /// its size is the unturned one, and it turns about its centre.
    /// Laid out and drawn for a floating picture only.
    public var rotation: Double = 0
    /// For a text box: the text inside it, which the layout sets in the
    /// box (a page number in a footer's text box, a letterhead's lines).
    /// The box itself — its outline, its fill — stays the kept markup's.
    public var textBox: RichTextBox? = nil

    public init(data: Data, width: Double, height: Double, name: String = "image.png",
                naturalWidth: Double? = nil, naturalHeight: Double? = nil) {
        self.id = UUID().uuidString
        self.data = data
        self.width = width
        self.height = height
        self.name = name
        self.naturalWidth = naturalWidth
        self.naturalHeight = naturalHeight
    }

    public static func == (a: ImageAttachment, b: ImageAttachment) -> Bool {
        a.id == b.id && a.width == b.width && a.height == b.height
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(width)
        hasher.combine(height)
    }

    public var isPNG: Bool { data.count > 8 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 }
    public var isJPEG: Bool { data.count > 2 && data[0] == 0xFF && data[1] == 0xD8 }

    /// A PNG's pixel size from its IHDR chunk, without decoding it — what a
    /// paste needs before the engine has looked at the bytes.
    public static func pngPixelSize(_ data: Data) -> (width: Int, height: Int)? {
        guard data.count >= 24, data[0] == 0x89, data[1] == 0x50, data[2] == 0x4E, data[3] == 0x47,
              data[12] == 0x49, data[13] == 0x48, data[14] == 0x44, data[15] == 0x52 else { return nil }
        func be32(_ at: Int) -> Int {
            (Int(data[at]) << 24) | (Int(data[at + 1]) << 16) | (Int(data[at + 2]) << 8) | Int(data[at + 3])
        }
        let w = be32(16), h = be32(20)
        return w > 0 && h > 0 ? (w, h) : nil
    }
    public var isGIF: Bool { data.count > 3 && data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 }
    public var fileExtension: String { isJPEG ? "jpeg" : isGIF ? "gif" : "png" }
}

// MARK: - Tables

/// Which table cell a paragraph belongs to. A table is a run of consecutive
/// paragraphs tagged with the same `table` id in row-major order; a cell
/// may hold several paragraphs. Keeping cells as ordinary paragraphs keeps
/// every edit, selection and format operation on the flat model.
public struct CellRef: Hashable, Sendable {
    public var table: String
    public var row: Int
    public var column: Int
    /// Grid columns this cell covers (Word's gridSpan): 1, or more for a
    /// cell merged across its neighbours to the right.
    public var span: Int
    /// Rows this cell covers (Word's vMerge): 1, or more for a cell merged
    /// downward; the rows below then have no cell in these columns.
    public var rowSpan: Int
    /// This cell's own shading (Word's `w:shd` on the cell), over the
    /// table style's row fills.
    public var fill: Color? = nil
    /// This cell's own borders, by side (Word's `w:tcBorders`), where
    /// they differ from the table's: a heading cell that says none on
    /// every side inside a ruled table (bug65649's estimates), a title
    /// cell with a bottom rule alone (Bug54771a), a form cell with no
    /// right edge (form_footnotes). A side left nil is the table's.
    public var edges: BorderEdges? = nil
    /// Where the cell's content sits when the row is taller than it:
    /// Word's `w:vAlign` ("center" or "bottom"; nil is the top).
    public var verticalAlign: String? = nil
    /// For a cell spanning rows: the sides each continuation row's cell
    /// stated (Word's w:tcBorders on the vMerge-continued cells), by row
    /// offset 1...rowSpan-1. Word draws a merged cell's bottom edge from
    /// its LAST continuation cell; writing the first cell's sides on
    /// every row left bug65649's merged headers open at the bottom and
    /// ruled inside.
    public var continuationEdges: [BorderEdges?] = []
    /// This cell's own border line width in points, where it differs from
    /// the table's: bug65649's header cells are ruled at 1.5pt over data
    /// rows at 0.75, and the extra width eats into the text area — Word
    /// wrapped "зарплаты" onto a second line and we did not, which made
    /// the header row a line shorter and every section a page longer.
    public var borderWidth: Double? = nil
    /// The cell's `w:tcBorders` as the file wrote it, and each continuation
    /// row's for a cell merged downward: every side's own line style,
    /// width and colour, which `edges` and `borderWidth` only summarise.
    /// Written back while the table's border switch is what the file had
    /// (`bordersKeptUnder`). form_footnotes rules one row's bottom
    /// double under single inside rules, 2pt taller — which decided a page.
    public var bordersXML: String? = nil
    /// The sides the cell's row gives it where the cell states none (a
    /// row's `w:tblPrEx` borders, as this cell's `w:tcBorders`): read
    /// for layout, never written — the row's exception is.
    public var rowBordersXML: String? = nil
    /// The cell's own margins (`w:tcMar`) as the file wrote them. The
    /// editor lays every cell out with the table's; a save restates the
    /// cell's so Word spaces it as it did.
    public var marginsXML: String? = nil
    /// The cell's preferred width (`w:tcW`) as the file wrote it — a
    /// percentage, a measure, or "auto" — written back while the columns
    /// it spans still add up to `widthKeptUnder` twips, as when read. The
    /// grid alone says none of it, and Word autofits by the cells' word.
    public var widthXML: String? = nil
    /// Cell properties kept as written (`w:noWrap`, `w:tcFitText`,
    /// `w:hideMark`): no-wrap decides how Word autofits the column.
    public var keptPropertiesXML: String? = nil
    public var widthKeptUnder: Int? = nil
    public var continuationBordersXML: [String?] = []
    /// What each continuation row's cell holds, as written, when it is
    /// only paragraphs: their marks' sizes and spacing are the height the
    /// merged cell asks of that row, which a bare empty paragraph is not.
    public var continuationContentXML: [String?] = []
    /// The same paragraphs read (empty where `continuationContentXML`
    /// is nil), by row offset: Word sizes a row in which no cell stands
    /// alone — every one merged on into the next row, or down from the
    /// one above — by what its cells hold, and a continued cell holds
    /// these.
    public var continuationParagraphs: [[RichParagraph]] = []
    /// The table's border switch when `bordersXML` was read: once the
    /// editor toggles the table's borders, the summary is written instead.
    public var bordersKeptUnder: Bool? = nil
    /// Which way the cell's text runs (PowerPoint's `vert`, Word's
    /// `w:textDirection`): across as usual, or turned a quarter so the
    /// lines run up or down the cell and stack across its width.
    public var textDirection: CellTextDirection = .horizontal
    /// Word's vertical writing (`tbRl`, `tbRlV`, `tbLrV`): the text runs
    /// down as `.down` does, but an ideograph stands upright in it, each
    /// a character's advance under the last — zh-2b955411's "评估目的"
    /// and "经济行为类型" in Word's print. (PowerPoint's `vert` turns
    /// every glyph; its upright kind is `eaVert`.)
    public var uprightIdeographs = false
    /// `w:textDirection` as the file wrote it, written back while the
    /// cell still runs the way it read as (`tbRlV` and `tbLrV` read as
    /// `.down`, which would be written `tbRl`).
    public var textDirectionValue: String? = nil
    /// The cell's own margins, in points (PowerPoint's `marL`…`marB`,
    /// Word's `w:tcMar`), over the table's (`TableStyle.cellMargin…`);
    /// nil: the table's.
    public var padding: EdgeInsets? = nil
    /// The cell's own edge lines where each has its own width and colour
    /// (PowerPoint's `lnL`…`lnB`), over `edges` and the table's rules;
    /// an edge left nil is theirs.
    public var borders = CellBorders()

    /// One edge's line: a width in points and a colour, or no line at all
    /// (`color` nil) where the style would have drawn one.
    public struct CellLine: Hashable, Sendable {
        public var width: Double
        public var color: Color?
        /// Dashed: its pieces, on and off by turns, in widths of the line
        /// (PowerPoint's `a:prstDash` on a cell's edge). nil is solid.
        public var dash: [Double]? = nil
        public init(width: Double, color: Color?, dash: [Double]? = nil) { self.width = width; self.color = color; self.dash = dash }
        /// No line on the edge (the name avoids `Optional.none`, which an
        /// unqualified `.none` resolves to on a `CellLine?`).
        public static let hidden = CellLine(width: 0, color: nil)
    }

    public struct CellBorders: Hashable, Sendable {
        public var left: CellLine? = nil
        public var right: CellLine? = nil
        public var top: CellLine? = nil
        public var bottom: CellLine? = nil
        public init() {}
        public var isEmpty: Bool { left == nil && right == nil && top == nil && bottom == nil }
    }

    public enum CellTextDirection: Hashable, Sendable {
        case horizontal
        /// Turned a quarter clockwise: the text reads top to bottom and the
        /// first line is at the cell's right (PowerPoint's `vert`, Word's
        /// `tbRl`).
        case down
        /// Turned a quarter anticlockwise: the text reads bottom to top and
        /// the first line is at the cell's left (`vert270`, `btLr`).
        case up
    }

    public init(table: String, row: Int, column: Int, span: Int = 1, rowSpan: Int = 1, fill: Color? = nil, edges: BorderEdges? = nil, verticalAlign: String? = nil) {
        self.table = table
        self.row = row
        self.column = column
        self.span = max(1, span)
        self.rowSpan = max(1, rowSpan)
        self.fill = fill
        self.edges = edges
        self.verticalAlign = verticalAlign
    }

    /// Whether this cell covers grid position (row, column).
    public func covers(row r: Int, column c: Int) -> Bool {
        r >= row && r < row + rowSpan && c >= column && c < column + span
    }

    /// Whether the cell's extent touches the grid rectangle.
    public func intersects(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> Bool {
        row <= rows.upperBound && row + rowSpan - 1 >= rows.lowerBound
            && column <= columns.upperBound && column + span - 1 >= columns.lowerBound
    }

    /// Same cell, ignoring the span.
    public func sameCell(as other: CellRef) -> Bool {
        table == other.table && row == other.row && column == other.column
    }
}

/// A table's look beyond its cells: Word's borders on or off, and a
/// header row that repeats at the top of every page the table runs on
/// (and is shaded so the reader sees it is one).
/// Border switches by side, each nil where nothing is said. A table's
/// six (Word's `w:tblBorders`, the inside ones between its cells) or a
/// cell's four (`w:tcBorders`) refine the one switch `TableStyle.borders`.
public struct BorderEdges: Hashable, Sendable {
    public var top: Bool? = nil
    public var left: Bool? = nil
    public var bottom: Bool? = nil
    public var right: Bool? = nil
    public var insideH: Bool? = nil
    public var insideV: Bool? = nil

    public init(top: Bool? = nil, left: Bool? = nil, bottom: Bool? = nil, right: Bool? = nil,
                insideH: Bool? = nil, insideV: Bool? = nil) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
        self.insideH = insideH; self.insideV = insideV
    }
    /// The four outer sides set alike.
    public init(all: Bool) { self.init(top: all, left: all, bottom: all, right: all) }
    public var isEmpty: Bool { top == nil && left == nil && bottom == nil && right == nil && insideH == nil && insideV == nil }
}

public struct TableStyle: Hashable, Sendable {
    public var borders = true
    /// A section's text columns set as a one-row table (the docx reader's
    /// emulation of `w:cols`), not a table of the file's.
    public var sectionColumns = false
    /// A floating table's position as the file wrote it (Word's
    /// w:tblpPr, and w:tblOverlap after it): the editor lays the table
    /// out in the text's flow, and a save puts it back where it floated.
    public var keptPosition: String? = nil
    /// How far below the text's place a floating table anchored to the
    /// text stands (its w:tblpY under w:vertAnchor="text"), in points:
    /// laid out in the flow, it starts that much lower.
    public var floatOffsetY: Double? = nil
    /// … and how far ABOVE it one stands whose w:tblpY is negative, in
    /// points: at a page's head it reaches up into the top margin.
    public var floatRaiseY: Double? = nil
    /// A floating table's left (`w:tblpX`, points) and what it is from
    /// (`w:horzAnchor`: "page", "margin" or "text").
    public var floatX: Double? = nil
    public var floatXAnchor: String? = nil
    /// A floating table placed against the page (`w:tblpPr w:vertAnchor="page"`):
    /// where it does not fit whole, Word sets its first row alone on its page
    /// and the rest on the next (zh-6cd1befe p51, zh-a4b0f6ea p20).
    public var pageAnchored = false
    /// Where such a table stands: its `w:tblpY` from the page's top edge,
    /// in points (nil where an alignment places it, `w:tblpYSpec`).
    public var pageOffsetY: Double? = nil
    /// The table floats anchored to the text (w:vertAnchor="text"): in a
    /// header or footer it takes no room, and stands over the paragraph
    /// after it (`RichLayout.floatsFrames`).
    public var floatsOverText = false
    /// The table's own `w:tblCellMar` when the editor's margins were
    /// taken from the cells instead (most of them stating a `w:tcMar`),
    /// with the margins that were current when it was read: written
    /// back while those still stand.
    public var keptCellMarginsXML: String? = nil
    public var keptCellMarginsUnder: [Double?] = []
    /// Per-side exceptions to `borders` (a form table ruled outside but
    /// not between its cells); nil sides follow `borders`.
    public var edges: BorderEdges? = nil
    public var headerRow = false
    /// How many leading rows repeat at the top of every page the table
    /// runs onto when `headerRow` is set (Word's w:tblHeader on each):
    /// bug59058's data tables repeat a caption row and a column-heading
    /// row, and came back repeating only the caption.
    public var headerRowCount = 1
    /// The table's preferred width as a share of the text width (Word's
    /// `w:tblW` in pct; 100 = full width), or in points (`width`); the
    /// grid's columns are scaled to it. Nil: the grid's own widths.
    public var widthPercent: Double? = nil
    public var width: Double? = nil
    /// Word's fixed layout (w:tblLayout fixed): the grid as given, no
    /// autofit to the cells' content.
    public var fixedLayout = false
    /// The cells state no preferred width (Word's `w:tcW` auto or absent):
    /// Word then autofits the columns to their content, and the grid is
    /// only a starting point. Writing the grid's widths as the cells'
    /// preferences froze bib-chernigovka's number column at its grid
    /// width and wrapped the text column a line early.
    public var autoCellWidths = false
    /// Nor does the table (`w:tblW` auto), nor any of its cells: Word
    /// then fits every column between its narrowest and its widest
    /// content, the saved grid set aside (`RichLayout._autofit`).
    public var contentFit = false
    /// … but for these columns, by grid index, which keep the width their
    /// cells state (points).
    public var contentFitFixed: [Int: Double] = [:]
    /// Columns whose cells state a share of the table's width (`w:tcW`
    /// in pct; 12 = 12%), and those whose cells do not wrap (`w:noWrap`):
    /// a spaced table of a stated share sizes them so (`_pctColumns`).
    public var columnPercents: [Int: Double] = [:]
    public var noWrapColumns: Set<Int> = []
    /// Space between cells in points (w:tblCellSpacing, HTML's
    /// cellspacing); nil when the file says nothing. Zero is kept apart
    /// from nil: Word draws a table that states it with separate borders.
    public var cellSpacing: Double? = nil
    /// Rows that say they have no cell spacing (`w:tblCellSpacing` of
    /// type nil, in their `w:tblPrEx` or `w:trPr`) in a table that has
    /// some: their borders collapse, as a table's of none do.
    public var rowsUnspaced: Set<Int> = []
    /// How far left of its place the table's edge stands so that its
    /// first column's text lines up with the paragraphs' (points): its
    /// left cell margin — the table's own, else its style's, else
    /// Word's 5.4 — in Word's layouts before 2013 (the layout decides:
    /// `RichLayout._tableLeft`). And the right one, by which a
    /// right-aligned table stands past the right margin.
    public var textOutdent: Double = 0
    public var textOutdentRight: Double = 0
    /// The header row's fill (nil: a faint tint of the text colour).
    public var headerFill: Color? = nil
    /// Banded rows: every other body row filled with this, the rest with
    /// `bandAltFill` (PowerPoint's default table look). nil: no bands.
    public var bandFill: Color? = nil
    public var bandAltFill: Color? = nil
    /// Border colour (nil: the text colour at 60%).
    public var borderColor: Color? = nil
    /// The border lines' width in points (Word's sz / 8); nil for 0.5pt.
    public var borderWidth: Double? = nil
    /// Word's line style when it is not a plain single line (`outset`,
    /// `inset`, `double`, `dashed`, ...), carried through unchanged: Word
    /// draws bib-chernigovka's outset rules as grey 3D lines, and single
    /// black ones in their place were most of what differed on 16 pages.
    public var borderStyle: String? = nil
    /// Per-side line styles and widths (points) where a side differs from
    /// `borderStyle`/`borderWidth`, keyed by Word's side names (top, left,
    /// bottom, right, insideH, insideV): form_footnotes' tables are double
    /// outside and single between their cells, and one style for all six
    /// sides drew the inside rules double and grew every row.
    public var edgeStyles: [String: String] = [:]
    public var edgeWidths: [String: Double] = [:]
    /// The file ruled this table through its CELLS (w:tcBorders on each)
    /// and said nothing at the table level. `borders` then only summarises
    /// them for the editor; the writer puts no w:tblBorders back and every
    /// cell keeps its own sides. Adding table-level inside rules on top of
    /// bug65649's cell rules grew its 370-row estimate a point a row.
    public var bordersFromCells = false
    /// Where a table narrower than the text column sits: Word's table
    /// alignment (`w:jc` on the table). Justify reads as left.
    public var alignment: ParagraphAlignment = .left
    /// A left-aligned table's offset from the text column's left edge, in
    /// points (Word's `w:tblInd`); negative hangs it into the margin.
    public var indent: Double = 0
    /// Minimum row heights in points by row index (Word's `w:trHeight`);
    /// a row without one is as tall as its content.
    /// Rows Word may not split across pages (w:cantSplit), by index.
    public var rowsCantSplit: Set<Int> = []
    /// A row's exceptions to the table's properties (Word's `w:tblPrEx`:
    /// its own borders or cell margins), by row index, kept as written.
    /// form_footnotes rules twenty of its form rows this way, and without
    /// the last one's 2.25pt box that row fitted a page Word breaks before.
    public var rowExceptions: [Int: String] = [:]
    /// Grid columns a row leaves empty before its first cell (Word's
    /// `w:gridBefore`), by row index: its cells start that far in.
    public var rowsGridBefore: [Int: Int] = [:]
    public var rowHeights: [Int: Double] = [:]
    /// Rows whose height is exact, not a minimum (Word's `w:hRule`
    /// "exact": the row clips what does not fit), by index.
    public var rowsExactHeight: Set<Int> = []
    /// Cell margins in points (Word's `w:tblCellMar`: 0 above and below,
    /// 5.4 at the sides by default); nil takes the layout's own padding.
    public var cellMarginTop: Double? = nil
    public var cellMarginLeft: Double? = nil
    public var cellMarginBottom: Double? = nil
    public var cellMarginRight: Double? = nil

    public init(borders: Bool = true, headerRow: Bool = false, headerFill: Color? = nil,
                bandFill: Color? = nil, bandAltFill: Color? = nil, borderColor: Color? = nil,
                alignment: ParagraphAlignment = .left, indent: Double = 0, rowHeights: [Int: Double] = [:],
                cellMarginTop: Double? = nil, cellMarginLeft: Double? = nil,
                cellMarginBottom: Double? = nil, cellMarginRight: Double? = nil) {
        self.cellMarginTop = cellMarginTop
        self.cellMarginLeft = cellMarginLeft
        self.cellMarginBottom = cellMarginBottom
        self.cellMarginRight = cellMarginRight
        self.borders = borders
        self.headerRow = headerRow
        self.headerFill = headerFill
        self.bandFill = bandFill
        self.bandAltFill = bandAltFill
        self.borderColor = borderColor
        self.alignment = alignment
        self.indent = indent
        self.rowHeights = rowHeights
    }
}

// MARK: - List numbering

public enum ListNumberFormat: Hashable, Sendable {
    case decimal, lowerLetter, upperLetter, lowerRoman, upperRoman
    /// A bullet: the level's `text` is the glyph itself, no counter.
    case bullet

    public func string(_ n: Int) -> String {
        switch self {
        case .decimal: return String(n)
        case .bullet: return ""
        case .lowerLetter, .upperLetter:
            guard n >= 1 else { return String(n) }
            let scalar = (self == .lowerLetter ? 97 : 65) + (n - 1) % 26
            return String(repeating: String(UnicodeScalar(UInt8(scalar))), count: (n - 1) / 26 + 1)
        case .lowerRoman, .upperRoman:
            guard n >= 1, n < 4000 else { return String(n) }
            var out = ""
            var v = n
            for (value, glyph) in [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                                   (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")] {
                while v >= value { out += glyph; v -= value }
            }
            return self == .upperRoman ? out.uppercased() : out
        }
    }
}

/// One level's label: `text` with `%1`…`%9` standing for the counters of
/// levels 1…9 ("%1.%2" gives "3.2"), each in that level's `format`.
public struct ListLevelFormat: Hashable, Sendable {
    public var text: String
    public var format: ListNumberFormat
    /// The level's own indents in points (Word's w:lvl/w:pPr/w:ind), kept
    /// through a save; nil for the editor's defaults.
    public var indentLeft: Double? = nil
    public var hanging: Double? = nil
    /// The level's own run properties for the NUMBER (Word's w:rPr on the
    /// w:lvl), kept as written: bug65649's sub-levels set their numbers
    /// at 14pt under 11pt text, and a 14pt number makes the line taller.
    public var numberRPrXML: String? = nil
    /// What follows the number (w:suff: "tab" is the default, "space",
    /// "nothing"), kept when the level says.
    public var suffix: String? = nil
    /// A bullet level's `w:lvlText` as the file wrote it — often a
    /// private-use code that means a glyph only in the level's symbol
    /// font — with the display glyph it was read as. Written back while
    /// `text` is still that glyph: form_footnotes' lists are Symbol
    /// U+F094 boxes, and came back as round bullets a little shorter.
    public var rawText: String? = nil
    public var rawTextGlyph: String? = nil
    /// Word's own name for the number format when `format` only stands
    /// in for it ("chineseCounting", "taiwaneseCountingThousand",
    /// "decimalEnclosedCircle", …: shown as 1, 2, 3 here, written back by
    /// name), and the level's first number and alignment when the file
    /// states other than 1 and left.
    public var rawFormat: String? = nil
    public var start: Int? = nil
    public var justification: String? = nil

    public init(text: String, format: ListNumberFormat = .decimal) {
        self.text = text
        self.format = format
    }

    public static func plain(_ level: Int) -> ListLevelFormat { ListLevelFormat(text: "%\(level + 1).") }

    /// The `n`th number of this level as it is written: by the file's
    /// own format where that is one of the East Asian ones `format`
    /// has no case for (`rawFormat`: 一二三, 壹貳參, 甲乙丙, ①②③…),
    /// else by `format`.
    public func number(_ n: Int) -> String {
        guard let raw = rawFormat, n >= 1 else { return format.string(n) }
        func counting(_ digits: [Character], ten: String, hundred: String, thousand: String, legal: Bool = false) -> String {
            guard n < 10000 else { return String(n) }
            var out = ""
            let parts = [(n / 1000, thousand), (n / 100 % 10, hundred), (n / 10 % 10, ten), (n % 10, "")]
            var pendingZero = false
            for (k, (d, unit)) in parts.enumerated() {
                if d == 0 {
                    if !out.isEmpty { pendingZero = true }
                    continue
                }
                if pendingZero { out.append(digits[0]); pendingZero = false }
                // (十, not 一十, for ten to nineteen — but 壹拾 in the
                // legal forms: zh-64044a1d's tenth chapter is "壹拾、" in
                // Word's print, ours "拾、".)
                if !(k == 2 && d == 1 && out.isEmpty && !legal) { out.append(digits[d]) }
                out += unit
            }
            return out
        }
        func cycle(_ glyphs: String) -> String {
            let g = Array(glyphs)
            return n <= g.count ? String(g[n - 1]) : String(n)
        }
        switch raw {
        case "taiwaneseCountingThousand", "taiwaneseCounting", "chineseCountingThousand", "chineseCounting",
             "japaneseCounting", "ideographDigital", "taiwaneseDigital", "japaneseDigitalTenThousand":
            return counting(Array("〇一二三四五六七八九"), ten: "十", hundred: "百", thousand: "千")
        case "ideographLegalTraditional", "japaneseLegal":
            return counting(Array("零壹貳參肆伍陸柒捌玖"), ten: "拾", hundred: "佰", thousand: "仟", legal: true)
        case "chineseLegalSimplified":
            return counting(Array("零壹贰叁肆伍陆柒捌玖"), ten: "拾", hundred: "佰", thousand: "仟", legal: true)
        case "ideographTraditional": return cycle("甲乙丙丁戊己庚辛壬癸")
        case "ideographZodiac": return cycle("子丑寅卯辰巳午未申酉戌亥")
        case "decimalEnclosedCircle", "decimalEnclosedCircleChinese": return cycle("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳")
        case "decimalEnclosedParen": return cycle("⑴⑵⑶⑷⑸⑹⑺⑻⑼⑽⑾⑿⒀⒁⒂⒃⒄⒅⒆⒇")
        case "decimalEnclosedFullstop": return cycle("⒈⒉⒊⒋⒌⒍⒎⒏⒐⒑⒒⒓⒔⒕⒖⒗⒘⒙⒚⒛")
        case "decimalFullWidth", "decimalFullWidth2":
            return String(String(n).unicodeScalars.map { Character(UnicodeScalar($0.value - 0x30 + 0xFF10)!) })
        case "decimalZero": return n < 10 ? "0\(n)" : String(n)
        // (A level that shows no number: zh-90e0cea8's chapters are
        // "%1%2　" over a level 0 of "none" — "6　", not "16　".)
        case "none": return ""
        case let r where r.hasPrefix("custom:"):
            return Self.customNumber(String(r.dropFirst(7)), n) ?? format.string(n)
        default: return format.string(n)
        }
    }

    /// A number in a Word 2010 custom format, given as samples of its
    /// first items ("α, β, γ, ...", "001, 002, 003, ..."): letters run on
    /// from the first (the Greek ones skipping the final sigma), digits
    /// are padded to the sample's width. nil for a sample not read.
    static func customNumber(_ spec: String, _ n: Int) -> String? {
        let items = spec.split(separator: ",").map { String($0.filter { $0 != " " }) }.filter { !$0.isEmpty && $0 != "..." }
        guard let first = items.first else { return nil }
        if first.allSatisfy({ $0.isASCII && $0.isNumber }) {
            let digits = String(n)
            return String(repeating: "0", count: max(0, first.count - digits.count)) + digits
        }
        guard first.unicodeScalars.count == 1, let start = first.unicodeScalars.first?.value else { return nil }
        var code = start
        var k = 1
        while k < n {
            code += 1
            if code == 0x3C2 || code == 0x3A2 { code += 1 }   // ς, and the unassigned capital
            k += 1
        }
        return Unicode.Scalar(code).map { String(Character($0)) }
    }

    /// The bullet a level shows when its list names none.
    public static func defaultBullet(_ level: Int) -> String { level % 2 == 0 ? "\u{2022}" : "\u{25E6}" }

    /// Word's numbering library, in its order.
    public static let numberingLibrary: [ListLevelFormat] = [
        ListLevelFormat(text: "%1.", format: .decimal),
        ListLevelFormat(text: "%1)", format: .decimal),
        ListLevelFormat(text: "%1.", format: .lowerLetter),
        ListLevelFormat(text: "%1)", format: .lowerLetter),
        ListLevelFormat(text: "%1.", format: .lowerRoman),
        ListLevelFormat(text: "%1.", format: .upperLetter),
        ListLevelFormat(text: "%1.", format: .upperRoman),
    ]

    /// Word's bullet library.
    public static let bulletLibrary: [ListLevelFormat] = [
        "\u{2022}", "\u{25E6}", "\u{25AA}", "\u{2013}", "\u{27A2}", "\u{2713}", "\u{2756}",
    ].map { ListLevelFormat(text: $0, format: .bullet) }

    /// A library entry is written for level 1 ("%1."); at a deeper level
    /// its counter is that level's ("%3." at level 2). The reverse gives
    /// the entry a stored format matches, for the library's check mark.
    public func forLevel(_ level: Int) -> ListLevelFormat {
        ListLevelFormat(text: text.replacingAll("%1", with: "%\(level + 1)"), format: format)
    }

    public func asLibraryEntry(atLevel level: Int) -> ListLevelFormat {
        guard level > 0, !text.containsSubstring("%1") else { return self }
        return ListLevelFormat(text: text.replacingAll("%\(level + 1)", with: "%1"), format: format)
    }

    /// What the level shows for item `n` at level `level`, as the ribbon
    /// previews it: "1.", "a)", "•".
    public func sample(_ n: Int = 1) -> String {
        if format == .bullet { return text }
        var out = ""
        var chars = text.makeIterator()
        while let ch = chars.next() {
            if ch == "%", let d = chars.next(), Int(String(d)) != nil { out += format.string(n) } else { out.append(ch) }
        }
        return out
    }
}

/// The label of every list paragraph, computed over the whole document:
/// Word's rules — a list id numbers on across other paragraphs, a deeper
/// level restarts when a shallower item appears, and anonymous items
/// (no id) form runs that restart after an interruption.
public enum RichListNumbering {
    public static func labels(_ document: RichDocument) -> [String?] {
        var out: [String?] = Array(repeating: nil, count: document.paragraphs.count)
        var counters: [String: [Int]] = [:]
        var restarted = Set<String>()
        let anonymous = ""
        for (i, p) in document.paragraphs.enumerated() {
            let s = p.style
            guard let kind = s.list else {
                counters[anonymous] = nil
                continue
            }
            // (An empty paragraph that ends a section is the break
            // alone: Word neither numbers nor counts it. zh-e6d54ae4's
            // section ends on an empty level-0 item before "計畫內容",
            // which Word's print numbers 肆, ours 伍.)
            if p.text.isEmpty, p.image == nil, s.sectionXML != nil { continue }
            let lvl = min(max(0, s.listLevel), 8)
            if kind == .bullet {
                let chosen = s.listId.flatMap { document.listFormats[$0]?[lvl] }
                out[i] = s.bulletText ?? (chosen?.format == .bullet ? chosen!.text : ListLevelFormat.defaultBullet(lvl))
                if s.listId == nil { counters[anonymous] = nil }
                continue
            }
            let key = s.listId.map { document.listCounterOf[$0] ?? $0 } ?? anonymous
            let formats = s.listId.flatMap { document.listFormats[$0] } ?? [:]
            let f = formats[lvl] ?? .plain(lvl)
            // (A level not yet counted, `Int.min`, begins at its own
            // start: zh-a7728bc9's fifth heading is a list of its own
            // whose level starts at 5 — "五、" in Word's print, "一、"
            // in ours.)
            var c = counters[key] ?? Array(repeating: Int.min, count: 9)
            if let id = s.listId, let start = document.listRestarts[id]?[lvl], !restarted.contains("\(id)|\(lvl)") {
                restarted.insert("\(id)|\(lvl)")
                c[lvl] = start - 1
            }
            if c[lvl] == Int.min { c[lvl] = (f.start ?? 1) - 1 }
            c[lvl] += 1
            for deeper in (lvl + 1) ..< 9 { c[deeper] = Int.min }
            // (And a shallower level not yet counted, where a deeper item
            // comes first, is counted at its start, not only shown so: the
            // next item there is the one after it. zh-505b9619's quality
            // list opens at level 2 ("1.1下列檢驗項目…"), and its first
            // two level-1 items are "2自主檢查與監造檢查（驗）" and
            // "3品質管制" in Word's print; ours numbered them 1 and 2,
            // and every "3.x" after read "2.x".)
            for shallower in 0 ..< lvl where c[shallower] == Int.min { c[shallower] = formats[shallower]?.start ?? 1 }
            counters[key] = c
            var label = ""
            var chars = f.text.makeIterator()
            while let ch = chars.next() {
                if ch == "%", let d = chars.next(), let k = Int(String(d)), k >= 1, k <= 9 {
                    let n = c[k - 1] == Int.min ? max(1, formats[k - 1]?.start ?? 1) : max(1, c[k - 1])
                    label += (formats[k - 1] ?? .plain(k - 1)).number(n)
                } else {
                    label.append(ch)
                }
            }
            out[i] = label
        }
        return out
    }
}

// MARK: - Runs and paragraphs

/// A stretch of `length` UTF-16 units sharing one `CharStyle`.
public struct Run: Hashable, Sendable {
    public var length: Int
    public var style: CharStyle

    public init(length: Int, style: CharStyle = .plain) {
        self.length = length
        self.style = style
    }
}

/// One paragraph: its text, the runs that cover it exactly, and its style.
///
/// Invariant (`isValid`): the run lengths sum to `text.utf16.count`, no run
/// has length 0 — except that an EMPTY paragraph keeps exactly one zero-length
/// run, so the style a new character will take survives deleting the last
/// one — and no two adjacent runs share a style (`normalize()` restores that).
public struct RichParagraph: Hashable, Sendable {
    public var text: String
    public var runs: [Run]
    public var style: RichParagraphStyle
    /// Set on a picture paragraph, whose text is empty.
    public var image: ImageAttachment? = nil
    /// Set on a paragraph that lives in a table cell.
    public var cell: CellRef? = nil
    /// Pictures inline with the text, by the id a run's
    /// `CharStyle.inlineImage` names; each stands where its U+FFFC is.
    public var inlineImages: [String: ImageAttachment] = [:]
    /// Set on the paragraphs flattened out of a nested table: the key of
    /// the entry in `RichDocument.keptTables`.
    public var keptTable: String? = nil
    /// Names of the bookmarks that start in this paragraph (what a
    /// contents page's page references point at).
    public var bookmarks: [String] = []

    public static let inlineImageCharacter = "\u{FFFC}"

    public init(text: String = "", runs: [Run]? = nil, style: RichParagraphStyle = .body) {
        self.text = text
        self.style = style
        self.runs = runs ?? [Run(length: text.utf16.count)]
        normalize()
    }

    public init(text: String, charStyle: CharStyle, style: RichParagraphStyle = .body) {
        self.init(text: text, runs: [Run(length: text.utf16.count, style: charStyle)],
                  style: style)
    }

    public init(image: ImageAttachment, style: RichParagraphStyle = .body) {
        self.init(text: "", runs: nil, style: style)
        self.image = image
    }

    public var isImage: Bool { image != nil }

    public var length: Int { text.utf16.count }
    public var isEmpty: Bool { text.isEmpty }

    public var isValid: Bool {
        let total = runs.reduce(0) { $0 + $1.length }
        if total != length { return false }
        if text.isEmpty { return runs.count == 1 && runs[0].length == 0 }
        if runs.contains(where: { $0.length <= 0 }) { return false }
        for i in 1 ..< max(1, runs.count) where runs[i - 1].style == runs[i].style {
            return false
        }
        return true
    }

    /// Merge equal neighbours and drop empty runs (keeping one for an empty
    /// paragraph). Every mutation ends here.
    public mutating func normalize() {
        if text.isEmpty {
            let style = runs.first?.style ?? .plain
            runs = [Run(length: 0, style: style)]
            return
        }
        var out: [Run] = []
        out.reserveCapacity(runs.count)
        for run in runs where run.length > 0 {
            if let last = out.last, last.style == run.style {
                out[out.count - 1].length += run.length
            } else {
                out.append(run)
            }
        }
        // Repair a total that drifted (a caller that edited `text` directly):
        // the last run absorbs the difference rather than the invariant
        // silently failing downstream.
        let total = out.reduce(0) { $0 + $1.length }
        if total != length {
            if out.isEmpty {
                out = [Run(length: length)]
            } else {
                out[out.count - 1].length += length - total
                if out[out.count - 1].length <= 0 { out.removeLast() }
            }
        }
        runs = out.isEmpty ? [Run(length: length)] : out
    }

    // MARK: Styles at offsets

    /// The style typing at `offset` would continue: the run holding the
    /// character BEFORE the offset (so typing after a bold word stays bold),
    /// or the first run at the paragraph start.
    public func style(at offset: Int) -> CharStyle {
        if runs.isEmpty { return .plain }
        if offset <= 0 { return runs[0].style }
        var pos = 0
        for run in runs {
            pos += run.length
            if offset <= pos { return run.style }
        }
        return runs[runs.count - 1].style
    }

    /// Index of the run containing the character AT `offset` (0-based unit),
    /// clamped to the last run.
    public func runIndex(containing offset: Int) -> Int {
        var pos = 0
        for (i, run) in runs.enumerated() {
            pos += run.length
            if offset < pos { return i }
        }
        return max(0, runs.count - 1)
    }

    /// The runs covering `range`, with lengths clipped to it.
    public func runs(in range: Range<Int>) -> [Run] {
        var out: [Run] = []
        var pos = 0
        for run in runs {
            let start = pos
            let end = pos + run.length
            pos = end
            let lo = max(start, range.lowerBound)
            let hi = min(end, range.upperBound)
            if hi > lo { out.append(Run(length: hi - lo, style: run.style)) }
        }
        return out
    }

    // MARK: Mutations

    /// Insert `string` at `offset`. `runs` gives its styling; nil means the
    /// style typing there would continue.
    public mutating func insert(_ string: String, at offset: Int, runs newRuns: [Run]? = nil) {
        let insertUnits = string.utf16.count
        guard insertUnits > 0 else { return }
        let offset = max(0, min(offset, length))
        let styled = newRuns ?? [Run(length: insertUnits, style: style(at: offset))]
        // Split the run at `offset` and splice the new runs between.
        var out: [Run] = []
        var pos = 0
        var spliced = false
        for run in runs {
            let start = pos
            let end = pos + run.length
            pos = end
            if !spliced && offset >= start && offset <= end {
                let before = offset - start
                let after = end - offset
                if before > 0 { out.append(Run(length: before, style: run.style)) }
                out.append(contentsOf: styled)
                if after > 0 { out.append(Run(length: after, style: run.style)) }
                spliced = true
            } else {
                out.append(run)
            }
        }
        if !spliced { out.append(contentsOf: styled) }
        runs = out
        let idx = String.Index(utf16Offset: offset, in: text)
        text.insert(contentsOf: string, at: idx)
        normalize()
    }

    /// Remove `range` (UTF-16). Returns the removed text and its runs, which
    /// is exactly what re-inserting on undo needs.
    @discardableResult
    public mutating func delete(_ range: Range<Int>) -> (text: String, runs: [Run]) {
        let lo = max(0, min(range.lowerBound, length))
        let hi = max(lo, min(range.upperBound, length))
        guard hi > lo else { return ("", []) }
        let removedRuns = runs(in: lo ..< hi)
        var out: [Run] = []
        var pos = 0
        for run in runs {
            let start = pos
            let end = pos + run.length
            pos = end
            let keepBefore = max(0, min(lo, end) - start)
            let keepAfter = max(0, end - max(hi, start))
            let kept = keepBefore + keepAfter
            if kept > 0 { out.append(Run(length: kept, style: run.style)) }
        }
        // Keep the style for an emptied paragraph.
        if out.isEmpty, let first = runs.first { out = [Run(length: 0, style: first.style)] }
        runs = out
        let a = String.Index(utf16Offset: lo, in: text)
        let b = String.Index(utf16Offset: hi, in: text)
        let removed = String(text[a ..< b])
        text.removeSubrange(a ..< b)
        normalize()
        return (removed, removedRuns)
    }

    /// Apply `transform` to the styles over `range`, splitting runs at its
    /// edges. A collapsed range is a no-op (the controller keeps a pending
    /// "typing style" for that case).
    public mutating func applyStyle(_ range: Range<Int>, _ transform: (inout CharStyle) -> Void) {
        let lo = max(0, min(range.lowerBound, length))
        let hi = max(lo, min(range.upperBound, length))
        if text.isEmpty {
            transform(&runs[0].style)
            return
        }
        guard hi > lo else { return }
        var out: [Run] = []
        var pos = 0
        for run in runs {
            let start = pos
            let end = pos + run.length
            pos = end
            let a = max(start, lo)
            let b = min(end, hi)
            if b <= a {
                out.append(run)
                continue
            }
            if a > start { out.append(Run(length: a - start, style: run.style)) }
            var styled = run.style
            transform(&styled)
            out.append(Run(length: b - a, style: styled))
            if end > b { out.append(Run(length: end - b, style: run.style)) }
        }
        runs = out
        normalize()
    }

    /// Split at `offset`: self keeps the head, the returned paragraph is the
    /// tail with the same paragraph style.
    public mutating func split(at offset: Int) -> RichParagraph {
        let offset = max(0, min(offset, length))
        let tailRuns = runs(in: offset ..< length)
        let idx = String.Index(utf16Offset: offset, in: text)
        let tailText = String(text[idx...])
        let headStyleAtEnd = style(at: offset)
        var tail = RichParagraph(text: tailText,
                                 runs: tailRuns.isEmpty ? [Run(length: 0, style: headStyleAtEnd)] : tailRuns,
                                 style: style)
        tail.normalize()
        if image != nil { tail.image = nil }
        tail.cell = cell
        text = String(text[..<idx])
        runs = runs(in: 0 ..< offset)
        if runs.isEmpty { runs = [Run(length: 0, style: headStyleAtEnd)] }
        normalize()
        return tail
    }

    /// Append `other`'s text and runs; the paragraph style stays self's.
    public mutating func append(_ other: RichParagraph) {
        if other.text.isEmpty { return }
        if text.isEmpty {
            text = other.text
            runs = other.runs
        } else {
            text += other.text
            runs.append(contentsOf: other.runs)
        }
        normalize()
    }

    // MARK: Grapheme-aware motion

    /// The UTF-16 offset one grapheme cluster before `offset` (0 at the start).
    public func graphemeBefore(_ offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        let clamped = min(offset, length)
        var idx = String.Index(utf16Offset: clamped, in: text)
        // If the offset fell inside a cluster, `index(before:)` from the
        // scalar-aligned index still lands on the cluster start.
        if idx > text.startIndex {
            idx = text.index(before: idx)
        }
        return idx.utf16Offset(in: text)
    }

    /// The UTF-16 offset one grapheme cluster after `offset` (length at the end).
    public func graphemeAfter(_ offset: Int) -> Int {
        guard offset < length else { return length }
        let idx = String.Index(utf16Offset: max(0, offset), in: text)
        let next = idx < text.endIndex ? text.index(after: idx) : text.endIndex
        return next.utf16Offset(in: text)
    }

    /// Snap an arbitrary offset to a grapheme boundary (rounding down).
    public func alignedOffset(_ offset: Int) -> Int {
        let clamped = max(0, min(offset, length))
        let idx = String.Index(utf16Offset: clamped, in: text)
        // `String.Index(utf16Offset:)` may produce an index inside a cluster;
        // round-tripping through the Character view rounds it down.
        let aligned = text.indices.last(where: { $0 <= idx }) ?? text.startIndex
        return clamped == length ? length : aligned.utf16Offset(in: text)
    }

    // MARK: Word motion

    enum UnitClass { case space, word, punct }

    static func classify(_ u: UInt16) -> UnitClass {
        guard let scalar = Unicode.Scalar(u) else { return .word }  // surrogate half: part of a word
        if scalar.properties.isWhitespace { return .space }
        if scalar.properties.isAlphabetic || scalar.properties.numericType != nil || u == 0x5F {
            return .word
        }
        return .punct
    }

    /// The sentence at `offset`: from after the previous terminator
    /// (. ! ? followed by space) or the paragraph's start, to the next
    /// terminator and the spaces after it, as ⌘-click selects in Word.
    public func sentenceRange(at offset: Int) -> Range<Int> {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return 0 ..< 0 }
        let at = max(0, min(offset, units.count - 1))
        func terminator(_ i: Int) -> Bool { [0x2E, 0x21, 0x3F].contains(units[i]) }
        func isSpace(_ i: Int) -> Bool { Self.classify(units[i]) == .space }
        func endsSentence(_ i: Int) -> Bool {
            guard terminator(i) else { return false }
            var j = i + 1
            while j < units.count, terminator(j) { j += 1 }
            return j >= units.count || isSpace(j)
        }
        var lo = at
        while lo > 0 {
            // Stop after a terminator run that is followed by space.
            if endsSentence(lo - 1) && !terminator(lo) { break }
            lo -= 1
        }
        while lo < units.count, isSpace(lo), lo < at { lo += 1 }
        var hi = at
        while hi < units.count, !endsSentence(hi) { hi += 1 }
        while hi < units.count, terminator(hi) { hi += 1 }
        while hi < units.count, isSpace(hi) { hi += 1 }
        return lo ..< max(hi, lo)
    }

    /// Start of the word before `offset` (Ctrl/Alt+Left): skip trailing
    /// spaces, then the run of like-classed units.
    public func wordStart(before offset: Int) -> Int {
        let units = Array(text.utf16)
        var i = max(0, min(offset, units.count))
        while i > 0 && Self.classify(units[i - 1]) == .space { i -= 1 }
        guard i > 0 else { return 0 }
        let cls = Self.classify(units[i - 1])
        while i > 0 && Self.classify(units[i - 1]) == cls { i -= 1 }
        return i
    }

    /// End of the word after `offset` (Ctrl/Alt+Right).
    public func wordEnd(after offset: Int) -> Int {
        let units = Array(text.utf16)
        var i = max(0, min(offset, units.count))
        while i < units.count && Self.classify(units[i]) == .space { i += 1 }
        guard i < units.count else { return units.count }
        let cls = Self.classify(units[i])
        while i < units.count && Self.classify(units[i]) == cls { i += 1 }
        return i
    }

    /// The word around `offset`, for double-click selection.
    public func wordRange(at offset: Int) -> Range<Int> {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return 0 ..< 0 }
        var i = max(0, min(offset, units.count))
        if i == units.count { i -= 1 }
        let cls = Self.classify(units[i])
        var lo = i
        var hi = i + 1
        while lo > 0 && Self.classify(units[lo - 1]) == cls { lo -= 1 }
        while hi < units.count && Self.classify(units[hi]) == cls { hi += 1 }
        return lo ..< hi
    }
}

// MARK: - Positions and selections

/// A caret position: paragraph index + UTF-16 offset within it.
public struct RichPosition: Hashable, Comparable, Sendable {
    public var paragraph: Int
    public var offset: Int

    public init(paragraph: Int, offset: Int) {
        self.paragraph = paragraph
        self.offset = offset
    }

    public static let start = RichPosition(paragraph: 0, offset: 0)

    public static func < (a: RichPosition, b: RichPosition) -> Bool {
        a.paragraph != b.paragraph ? a.paragraph < b.paragraph : a.offset < b.offset
    }
}

/// Anchor (where the selection started) and focus (where the caret is).
/// A rectangle of whole cells in one table (Word's cell selection): what
/// dragging or shift-selecting from one cell into another makes.
public struct CellBlock: Hashable, Sendable {
    public var table: String
    public var rows: ClosedRange<Int>
    public var columns: ClosedRange<Int>

    public init(table: String, rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        self.table = table
        self.rows = rows
        self.columns = columns
    }

    /// Whether a cell lies in the block. A block is closed over merged
    /// cells (see `RichDocument.cellBlock`), so touching it is being in it.
    public func contains(_ c: CellRef) -> Bool {
        c.table == table && c.intersects(rows: rows, columns: columns)
    }
}

public struct RichSelection: Hashable, Sendable {
    public var anchor: RichPosition
    public var focus: RichPosition
    /// Set when the selection is whole cells: anchor and focus are then in
    /// the corner cells, and every command works on the block's cells.
    public var block: CellBlock? = nil

    public init(anchor: RichPosition, focus: RichPosition, block: CellBlock? = nil) {
        self.anchor = anchor
        self.focus = focus
        self.block = block
    }

    public init(caret: RichPosition) {
        anchor = caret
        focus = caret
    }

    public var isCollapsed: Bool { anchor == focus }
    public var start: RichPosition { min(anchor, focus) }
    public var end: RichPosition { max(anchor, focus) }
    public var caret: RichPosition { focus }
}

// MARK: - Document

public struct RichDocument: Hashable, Sendable {
    public var paragraphs: [RichParagraph]
    /// Running header and footer, one line each; `{PAGE}` and `{NUMPAGES}`
    /// are replaced per page. Empty means none.
    public var header: String = ""
    public var footer: String = ""
    /// Column widths in points per table id; a table without an entry gets
    /// equal columns across the content width.
    public var tableColumns: [String: [Double]] = [:]
    /// Per table id, what the table looks like beyond its cells; a table
    /// without an entry has borders and no header row.
    public var tableStyles: [String: TableStyle] = [:]
    /// The named styles paragraphs refer to.
    public var styles: RichStyleSheet = .word
    /// Per list id, the label format of each level (Word's lvlText and
    /// numFmt); a level without one is "%n." in decimal.
    public var listFormats: [String: [Int: ListLevelFormat]] = [:]
    /// Per list id, the counter it numbers on when that is not its own:
    /// Word's lists that share one w:abstractNum share its numbers, so a
    /// heading style's list and the explicit lists over the same
    /// definition count as one (zh-64044a1d's 二、 after a restart in
    /// another list, not 五、). Absent for the editor's own lists.
    public var listCounterOf: [String: String] = [:]
    /// Per list id, the levels it restarts the first time it is used, at
    /// these numbers (Word's w:lvlOverride/w:startOverride).
    public var listRestarts: [String: [Int: Int]] = [:]
    /// Parts of the file the editor does not model but a save must keep —
    /// Word's footnotes and endnotes, with their rels and what those
    /// reach — by package path. The body refers into them (`NoteReference`);
    /// the format writer copies them back verbatim.
    public var keptParts: [String: Data] = [:]
    /// The file's character styles, as written, by id: the editor's runs
    /// carry their look themselves, but kept markup (a footnote's mark, a
    /// header's text box) names these and has nothing else to go by.
    public var keptCharacterStyles: [String: String] = [:]
    /// Those styles' ids by lower-cased name ("hyperlink", "footnote
    /// reference"): where the file has its own, the writer names that one
    /// instead of adding a second style of the same name.
    public var keptCharacterStyleIds: [String: String] = [:]
    /// Header and footer parts kept verbatim (in `keptParts`): those with
    /// pictures, tables or text boxes the editor cannot show, and the
    /// first-page and even-page ones. `text` is what the part read as, so
    /// the writer knows whether the editor's `header`/`footer` changed.
    public var keptHeaderFooters: [KeptHeaderFooter] = []
    /// Nested tables kept verbatim, by the id their flattened paragraphs
    /// carry in `keptTable`.
    public var keptTables: [String: KeptTable] = [:]
    /// The file's compatibility settings (Word's `w:compat` block, with
    /// its compatibility mode), written back so Word lays the saved copy
    /// out by the same rules it laid the original out by.
    public var keptCompat: String? = nil
    /// The distance between default tab stops in points when the file
    /// states one (Word's `w:defaultTabStop`; 36pt when nil). Written
    /// back as read; the editor's own tabs still step by 36.
    public var defaultTabStop: Double? = nil
    /// The section's page borders (`w:pgBorders`), kept as written: an
    /// art border is nothing the editor can draw, and bib-chernigovka's
    /// maple-muffins frame on all 16 pages was lost without it.
    public var pageBordersXML: String? = nil
    /// The last section's document grid (`w:docGrid`) as written: the
    /// line pitch a Chinese, Japanese or Korean document's lines snap to,
    /// and its character pitch. Without it Word sets every line of the
    /// copy at its natural height and the pages run short.
    public var docGridXML: String? = nil
    /// That grid's line pitch in points, when lines snap to it (the
    /// grid's type is `lines` or `linesAndChars`): each line of a
    /// paragraph that does not opt out (`w:snapToGrid` off) is then a
    /// whole number of pitches tall. nil lays lines out at their own
    /// height.
    public var lineGridPitch: Double? = nil
    /// What the grid adds to every character's width, in points, where
    /// it is a grid of characters too (type `linesAndChars`, its
    /// `w:charSpace` in 4096ths of a point — negative to fit more to a
    /// line). A run that says `w:snapToGrid` off keeps its own widths.
    public var characterGridSpace: Double? = nil
    /// More of the last section kept as written, in schema order: what
    /// stands before the columns (`w:lnNumType`, `w:pgNumType`) and
    /// after them (`w:vAlign`, `w:textDirection`, `w:bidi`,
    /// `w:rtlGutter` — the grid comes last, above).
    public var sectionLeadXML: String? = nil
    /// The last section's `w:type` (how it starts: "continuous" after
    /// the section before it, or on a new page).
    public var sectionTypeXML: String? = nil
    /// The last section's `w:cols` as written (unequal columns, their
    /// gaps, a line between), and the column count it was read with: it
    /// goes back while the page still has that many columns.
    public var columnsXML: String? = nil
    public var columnsKeptUnder: Int? = nil
    /// The last section's binding gutter in twips (`w:pgMar w:gutter`)
    /// and the settings' `w:mirrorMargins`/`w:gutterAtTop`: the page the
    /// editor shows has neither, the saved file keeps both.
    public var gutterTwips: Int? = nil
    public var marginSettingsXML: String? = nil
    /// More settings Word lays out by, kept as written, by name:
    /// hyphenation (`w:autoHyphenation`, `w:hyphenationZone`, …),
    /// `w:noPunctuationKerning`, the line-breaking character lists
    /// (`w:noLineBreaksAfter`/`Before`, `w:strictFirstAndLastChars`) and
    /// how page borders meet the header and footer.
    public var keptSettings: [String: String] = [:]
    public var sectionTailXML: String? = nil
    /// The document's languages: the defaults' `w:lang` and the
    /// settings' `w:themeFontLang`. Word chooses the East Asian face and
    /// its line-breaking rules by them.
    public var defaultLangXML: String? = nil
    /// Whether that language's East Asian one is mainland Chinese, whose
    /// marks sit in the left half of their em: a closing mark at a
    /// line's end in a table's cell then gives its empty half in every
    /// compatibility mode, where Taiwan's centred marks keep their em
    /// before Word 2013's layout.
    public var marksSitLeft: Bool { defaultLangXML?.containsSubstring("w:eastAsia=\"zh-CN\"") ?? false }
    /// Whether that language is Taiwan's, Hong Kong's or Macau's, whose
    /// "，。、；：！？" stand in the middle of their em: one has no blank
    /// half beside a closing bracket to give.
    public var marksCentred: Bool {
        ["zh-TW", "zh-HK", "zh-MO"].contains { defaultLangXML?.containsSubstring("w:eastAsia=\"\($0)\"") ?? false }
    }
    /// Whether Word's East Asian line-breaking rules hold — no closing
    /// mark to start a line nor opening one to end it, and a mark that
    /// may hang past the margin: only where that language is Chinese,
    /// Japanese or Korean. Lab `kc` (Word 16): with the defaults'
    /// `w:eastAsia` en-US, "…abcdefgh)" and "…測試測試測試" leave "，" and
    /// "）" to open the next line, where under zh-CN they stay; and
    /// zh-6600d539 (en-US) starts a line "，針對平臺…" in Word's print.
    /// (Text whose East Asian language nothing states is Word's own
    /// language's, and Word for Windows' — the reference's, en-US — has no
    /// such rules where the settings say `w:doNotUseEastAsianBreakRules`:
    /// zh-55087b5f's "…提高服务水平，促进…", no `w:lang` in its run, its
    /// styles or its defaults, fills its justified line to "平" in Word's
    /// print and opens the next with "，", where ours hung the mark. Its
    /// fellows bear it out: of the 198 files with the switch, those that
    /// state a language score 99.9 and those that do not 98.8.)
    public var eastAsianLineRules: Bool {
        guard let xml = defaultLangXML, let r = xml.rangeOfSubstring("w:eastAsia=\"") else {
            return !(RichTextTheme.wordWindowsPages && breakRulesOnlyForEastAsian)
        }
        return ["zh", "ja", "ko"].contains(String(xml[r.upperBound...].prefix(2)).lowercased())
    }
    public var themeFontLangXML: String? = nil
    /// The settings' `w:doNotUseEastAsianBreakRules`: Word's East Asian
    /// line rules hold only for text in an East Asian language (see
    /// `eastAsianLineRules`).
    public var breakRulesOnlyForEastAsian = false
    /// The settings' `w:characterSpacingControl` value when the file
    /// states one ("compressPunctuation" in Chinese documents: Word then
    /// squeezes adjacent full-width punctuation, and lines break later).
    public var characterSpacingControl: String? = nil
    /// Whether lines are set by Word's East Asian rules (the settings'
    /// `w:useFELayout`, which every Chinese, Japanese or Korean Word
    /// writes): a closing mark may hang past the margin rather than
    /// start a line, a line gives up to half an em off its punctuation
    /// where `characterSpacingControl` compresses it, and two marks that
    /// stand together close up where the text kerns.
    public var usesEastAsianLayout = false
    /// The settings' `w:doNotUseIndentAsNumberingTabStop`: a list
    /// label's tab goes to the next tab stop, not to the hanging indent.
    public var indentNotNumberingTabStop = false
    /// Widow control holds for no paragraph, whatever each says: Word for
    /// Mac lays out a body whose footer holds a framed paragraph raised
    /// over the footer's top (a page number in a `w:framePr` of negative
    /// `w:y`) so — labs wc2, wc3 (Word 16, mode 14): with it a three-line
    /// paragraph keeps one line at a page's foot, or two; with the footer
    /// gone, its frame gone, or the frame's y 0 or 1, they stay together.
    /// zh-9462c6d6's "（二）促進有線…" parts one and two over pages 1-2.
    public var widowControlSuspended = false
    /// Whether punctuation kerns (the settings lack
    /// `w:noPunctuationKerning`): two marks that stand together close up
    /// only where it does.
    public var kernsPunctuation = true
    /// Word's `w:balanceSingleByteDoubleByteWidth` (most documents from
    /// WPS say it): a space is half an em wide, whatever its face's own
    /// — unless it stands between two Latin words. The spaces that push
    /// a signature across the page are then twice as wide in most faces.
    public var balancesSpaceWidth = false
    /// Whether the defaults' run properties (`w:rPrDefault`) name a Latin
    /// face for East Asian text — Times New Roman in `w:rFonts w:eastAsia`.
    /// Word for Windows then compresses no punctuation, whatever the
    /// languages and `w:characterSpacingControl` say.
    public var eastAsianDefaultFaceIsLatin = false
    /// The embedded faces Word for Windows compresses no punctuation in:
    /// those whose "「" is a glyph of no advance — lab tfz (windows-1,
    /// zh-57f1de0d's 方正仿宋_GBK, which Word's subset embedding left with
    /// 「」『』 empty): mending that one advance to 256 alone set "》" and
    /// "：" at 13.33 and took a character more a line; any other table, or
    /// a smaller cmap without 「, compressed too.
    public var uncompressedFaces: Set<String> = []
    /// Word's `w:spaceForUL`: an exact line's text set by its middle
    /// (`w:textAlignment` "center") has its own line centred in the exact
    /// one. Without it the middle stands where the baseline would be.
    public var spacesForUnderline = true
    /// Word's `w:ulTrailSpace`: underlined spaces are underlined at a
    /// line's end too — text, not the blank a line may hang past its
    /// margin. A run of them wraps as characters do.
    public var underlinesTrailingSpaces = false
    /// Word's `w:adjustLineHeightInTable`: a table's text keeps to the
    /// section's line grid as body text does. Without it Word sets a
    /// cell's lines off the grid (zh-117cf7c6's 12pt rows on an 18.25pt
    /// grid are 26.65pt in Word's print, ours two pitches).
    public var adjustsLineHeightInTable = true
    /// The settings' `compatibilityMode` (15 for Word 2013 on; nil
    /// where they name none, which Word takes for an older one). Below
    /// 15 a line's punctuation hangs and gives in a paragraph set any
    /// way; from 15 on only in a justified one.
    public var compatibilityMode: Int? = nil
    /// Word for Windows, in the legacy mode (no `compatibilityMode`) and
    /// with the defaults' East Asian face a Latin theme one
    /// (`w:eastAsiaTheme` minorHAnsi): Han text after a space is one
    /// word to the next space, which goes to the next line whole and is
    /// broken by characters where it fills (Windows labs t167, t167b on
    /// zh-7773163d — its "⚫案例 2：公務人員…" items each break after
    /// "案例 "; with mode 15, or the face minorEastAsia, they fill the
    /// line).
    public var joinsHanAfterSpace = false
    /// Word's `w:useAltKinsokuLineBreakRules`: a closing mark hangs past
    /// the margin by half an em at most, not by all of itself.
    public var hangsHalf = false
    /// Whether `w:mirrorIndents` paragraphs are mirrored on odd pages
    /// (Word's older, flipped reading) — true unless the file's
    /// compatibility settings say `doNotFlipMirrorIndents`, when even
    /// pages are mirrored and odd ones set as written.
    public var flipsMirrorIndents = true
    /// Whether "automatic" paragraph spacing is the web's: 14 points,
    /// and between two paragraphs the larger of the one's space after
    /// and the other's before rather than both, with none before the
    /// document's first. Off (the settings' compatibility switch
    /// `w:doNotUseHTMLParagraphAutoSpacing`), a paragraph marked
    /// automatic has the spacing its own numbers say.
    public var htmlAutoSpacing = true
    /// The space above and below each HTML block a paragraph can name
    /// by `RichParagraphStyle.divId` (Word's web settings, `w:marTop` and
    /// `w:marBottom`), in points: a run of paragraphs of one block takes
    /// its top over the first and its bottom under the last.
    public var divMargins: [String: DivMargins] = [:]
    /// The document background (`w:background`, with its VML fill), kept
    /// as written with the parts it names. Word lays a document with one
    /// out differently — bib-chernigovka's title page sits 18pt lower and
    /// its tables a line further down on every page — so dropping it
    /// moved every page, not just its colour.
    public var backgroundXML: String? = nil
    public var backgroundRels: [KeptRel] = []
    /// The file's own ids for styles the sheet knows under ours (its "1"
    /// is our Heading1), for the markup kept verbatim that still names
    /// them: a nested table's heading, a header's paragraphs. The writer
    /// defines each as a style based on ours.
    public var styleAliases: [String: String] = [:]
    /// Font families the file itself named (in its styles or its runs),
    /// written back as named. The editor's own faces are Liberation
    /// Sans/Serif/Mono and export as Arial/Times/Courier — but a file that
    /// says Liberation Serif means it, and Times New Roman's line height
    /// is not the same (table-indent's rows grew a point each).
    public var fileFonts: Set<String> = []
    /// Set by a file reader. A list paragraph the editor made gets Word's
    /// List Paragraph style on save; one read from a file keeps whatever
    /// style the file gave it, none included — bug65649's numbered
    /// headings are plain paragraphs with contextual spacing, and giving
    /// them a style the next paragraph lacked put 10pt back between them.
    public var readFromFile = false
    /// The space after a paragraph and the space before the next are both
    /// there (Word's `w:doNotUseHTMLParagraphAutoSpacing`, in files from
    /// Word 2003 and before). Without it Word keeps the larger of the two
    /// alone, as HTML's margins collapse: 9pt after and 9pt before are 9.
    public var addsParagraphSpacing = false
    /// Word's w:titlePg: the first page uses the "first" header/footer.
    public var titlePage = false
    /// The kept headers and footers as paragraphs: what the layout draws
    /// on each page while the editor's one-line text for them
    /// (`header`, `footer`) is still the file's.
    public var headerFooters: [RichHeaderFooter] = []
    /// The file's footnotes, by the id the body's marks name
    /// (`NoteReference.id`), read like the body for the layout to set
    /// at the foot of the page each mark lands on; and the separator
    /// Word draws above them (its `w:separator` note's paragraphs). The
    /// file's part is still what a save writes back.
    public var footnotes: [Int: [RichParagraph]] = [:]
    public var footnoteSeparator: [RichParagraph] = []
    /// The file's endnotes, the same way, set after the body's last
    /// paragraph in the order their marks come, under their separator.
    public var endnotes: [Int: [RichParagraph]] = [:]
    public var endnoteSeparator: [RichParagraph] = []
    /// The number of the first page where the last section says one
    /// (`w:pgNumType w:start`), and how page numbers are written where it
    /// says that (`w:fmt`: "lowerRoman", "numberInDash"…).
    public var pageNumberStart: Int? = nil
    public var pageNumberFormat: String? = nil
    /// Word's w:evenAndOddHeaders: even pages use the "even" ones.
    public var evenAndOddHeaders = false
    /// Content types of `keptParts`, by package path, as the file declared
    /// them (a kept part the editor knows nothing about still needs one).
    public var keptPartTypes: [String: String] = [:]

    public static let pageField = "{PAGE}"
    public static let pageCountField = "{NUMPAGES}"

    /// `header`/`footer` with the fields filled in for page `page` (1-based).
    public static func fill(_ template: String, page: Int, pageCount: Int) -> String {
        template.replacingAll(pageField, with: String(page))
            .replacingAll(pageCountField, with: String(pageCount))
    }

    public init(paragraphs: [RichParagraph] = [RichParagraph()]) {
        self.paragraphs = paragraphs.isEmpty ? [RichParagraph()] : paragraphs
    }

    /// Plain text with paragraphs joined by `separator`.
    public init(plainText: String, style: RichParagraphStyle = .body) {
        let lines = plainText.split(separator: "\n", omittingEmptySubsequences: false)
        paragraphs = lines.map { RichParagraph(text: String($0), style: style) }
        if paragraphs.isEmpty { paragraphs = [RichParagraph()] }
    }

    public var isValid: Bool {
        !paragraphs.isEmpty && paragraphs.allSatisfy { $0.isValid }
    }

    public func plainText(separator: String = "\n") -> String {
        paragraphs.map(\.text).joined(separator: separator)
    }

    public var endPosition: RichPosition {
        RichPosition(paragraph: paragraphs.count - 1, offset: paragraphs[paragraphs.count - 1].length)
    }

    public func clamped(_ p: RichPosition) -> RichPosition {
        let para = max(0, min(p.paragraph, paragraphs.count - 1))
        let off = max(0, min(p.offset, paragraphs[para].length))
        return RichPosition(paragraph: para, offset: off)
    }

    /// The text between two positions, as paragraphs (a fragment). The first
    /// and last are partial; a copy-paste of the fragment reproduces the
    /// styles exactly.
    /// The paragraphs a selection covers: a block's cells whole, else the
    /// range from start to end.
    public func paragraphIndices(in selection: RichSelection) -> [Int] {
        if let block = selection.block {
            return paragraphs.indices.filter { paragraphs[$0].cell.map(block.contains) ?? false }
        }
        let a = clamped(selection.start), b = clamped(selection.end)
        return Array(a.paragraph ... b.paragraph)
    }

    /// The block two positions span when both are in cells of one table
    /// and not the same cell; nil otherwise.
    public func cellBlock(from a: RichPosition, to b: RichPosition) -> CellBlock? {
        guard a.paragraph < paragraphs.count, b.paragraph < paragraphs.count,
              let ca = paragraphs[a.paragraph].cell, let cb = paragraphs[b.paragraph].cell,
              ca.table == cb.table, !ca.sameCell(as: cb) else { return nil }
        var rows = min(ca.row, cb.row) ... max(ca.row + ca.rowSpan - 1, cb.row + cb.rowSpan - 1)
        var cols = min(ca.column, cb.column) ... max(ca.column + ca.span - 1, cb.column + cb.span - 1)
        // A merged cell straddling an edge pulls the rectangle out to cover
        // it whole, until nothing straddles: a block is always whole cells.
        let cells = paragraphs(inTable: ca.table).compactMap { paragraphs[$0].cell }
        var grew = true
        while grew {
            grew = false
            for c in cells where c.intersects(rows: rows, columns: cols) {
                let r = min(rows.lowerBound, c.row) ... max(rows.upperBound, c.row + c.rowSpan - 1)
                let k = min(cols.lowerBound, c.column) ... max(cols.upperBound, c.column + c.span - 1)
                if r != rows || k != cols { rows = r; cols = k; grew = true }
            }
        }
        return CellBlock(table: ca.table, rows: rows, columns: cols)
    }

    public func fragment(_ selection: RichSelection) -> [RichParagraph] {
        if selection.block != nil {
            return paragraphIndices(in: selection).map { paragraphs[$0] }
        }
        let a = clamped(selection.start)
        let b = clamped(selection.end)
        if a.paragraph == b.paragraph {
            var p = paragraphs[a.paragraph]
            p.delete(b.offset ..< p.length)
            p.delete(0 ..< a.offset)
            return [p]
        }
        var out: [RichParagraph] = []
        var first = paragraphs[a.paragraph]
        first.delete(0 ..< a.offset)
        out.append(first)
        if b.paragraph - a.paragraph > 1 {
            out.append(contentsOf: paragraphs[(a.paragraph + 1) ..< b.paragraph])
        }
        var last = paragraphs[b.paragraph]
        last.delete(b.offset ..< last.length)
        out.append(last)
        return out
    }

    public func text(in selection: RichSelection) -> String {
        fragment(selection).map(\.text).joined(separator: "\n")
    }

    // MARK: Tables

    /// Column count of `table`, from the cells present.
    public func columnCount(of table: String) -> Int {
        var cols = 0
        for p in paragraphs {
            if let c = p.cell, c.table == table { cols = max(cols, c.column + c.span) }
        }
        return max(1, cols)
    }

    /// Paragraph indices of every cell of `table`, in document order.
    public func paragraphs(inTable table: String) -> [Int] {
        paragraphs.indices.filter { paragraphs[$0].cell?.table == table }
    }

    // MARK: Whole-document counts

    /// Words as Word counts them: runs between spaces, and each East
    /// Asian character one of its own — a Chinese document of 27 pages
    /// is some fifteen thousand words, not the 71 its spaces make
    /// (seen in the status bar, 2026-10-13). The ideographic space is
    /// white space like any.
    public var wordCount: Int {
        var count = 0
        for p in paragraphs {
            var inWord = false
            for scalar in p.text.unicodeScalars {
                if scalar.properties.isWhitespace {
                    inWord = false
                } else if Self._countsAlone(scalar.value) {
                    inWord = false
                    count += 1
                } else if !inWord {
                    inWord = true
                    count += 1
                }
            }
        }
        return count
    }

    private static func _countsAlone(_ u: UInt32) -> Bool {
        switch u {
        case 0x1100 ... 0x11FF, 0x2E80 ... 0x9FFF, 0xAC00 ... 0xD7FF, 0xF900 ... 0xFAFF, 0xFE30 ... 0xFE4F,
             0xFF00 ... 0xFFEF, 0x20000 ... 0x3FFFF: return true
        default: return false
        }
    }

    public var characterCount: Int {
        paragraphs.reduce(0) { $0 + $1.text.count }
    }
}

/// An HTML block's margins above and below, in points (`RichDocument.divMargins`).
public struct DivMargins: Hashable, Sendable {
    public var top: Double
    public var bottom: Double
    public init(top: Double, bottom: Double) { self.top = top; self.bottom = bottom }
}
