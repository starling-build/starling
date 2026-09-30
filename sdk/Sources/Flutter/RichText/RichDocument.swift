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

    public init(bold: Bool = false, italic: Bool = false, underline: Bool = false,
                strikethrough: Bool = false, fontFamily: String? = nil,
                fontSize: Double? = nil, color: Color? = nil, highlight: Color? = nil,
                link: String? = nil, script: ScriptPosition = .normal) {
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
    }

    public static let plain = CharStyle()
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

/// Paragraph-level formatting. Lengths are in points.
public struct RichParagraphStyle: Hashable, Sendable {
    public var alignment: ParagraphAlignment = .left
    public var indentLeft: Double = 0
    public var indentRight: Double = 0
    public var firstLineIndent: Double = 0
    public var spaceBefore: Double = 0
    public var spaceAfter: Double = 0
    /// Multiple of the font's natural line height (1.0 = single).
    public var lineSpacing: Double = 1.0
    public var list: ListKind? = nil
    public var listLevel: Int = 0
    /// Which list this paragraph belongs to, for numbering: Word's numId.
    /// Items of one id number on across other paragraphs; nil items number
    /// as a run, restarting after an interruption.
    public var listId: String? = nil
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

    public init(alignment: ParagraphAlignment = .left, indentLeft: Double = 0,
                indentRight: Double = 0, firstLineIndent: Double = 0,
                spaceBefore: Double = 0, spaceAfter: Double = 0,
                lineSpacing: Double = 1.0, list: ListKind? = nil, listLevel: Int = 0,
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

    public static let body = RichParagraphStyle()
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

    public init(table: String, row: Int, column: Int, span: Int = 1, rowSpan: Int = 1) {
        self.table = table
        self.row = row
        self.column = column
        self.span = max(1, span)
        self.rowSpan = max(1, rowSpan)
    }

    /// Whether this cell covers grid position (row, column).
    public func covers(row r: Int, column c: Int) -> Bool {
        r >= row && r < row + rowSpan && c >= column && c < column + span
    }

    /// Same cell, ignoring the span.
    public func sameCell(as other: CellRef) -> Bool {
        table == other.table && row == other.row && column == other.column
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

    public init(text: String, format: ListNumberFormat = .decimal) {
        self.text = text
        self.format = format
    }

    public static func plain(_ level: Int) -> ListLevelFormat { ListLevelFormat(text: "%\(level + 1).") }

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
        let anonymous = ""
        for (i, p) in document.paragraphs.enumerated() {
            let s = p.style
            guard let kind = s.list else {
                counters[anonymous] = nil
                continue
            }
            let lvl = min(max(0, s.listLevel), 8)
            if kind == .bullet {
                let chosen = s.listId.flatMap { document.listFormats[$0]?[lvl] }
                out[i] = chosen?.format == .bullet ? chosen!.text : ListLevelFormat.defaultBullet(lvl)
                if s.listId == nil { counters[anonymous] = nil }
                continue
            }
            let key = s.listId ?? anonymous
            var c = counters[key] ?? Array(repeating: 0, count: 9)
            c[lvl] += 1
            for deeper in (lvl + 1) ..< 9 { c[deeper] = 0 }
            counters[key] = c
            let formats = s.listId.flatMap { document.listFormats[$0] } ?? [:]
            let f = formats[lvl] ?? .plain(lvl)
            var label = ""
            var chars = f.text.makeIterator()
            while let ch = chars.next() {
                if ch == "%", let d = chars.next(), let k = Int(String(d)), k >= 1, k <= 9 {
                    let n = max(1, c[k - 1])
                    label += (formats[k - 1] ?? .plain(k - 1)).format.string(n)
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

    /// Whether a cell (by its origin) lies in the block.
    public func contains(_ c: CellRef) -> Bool {
        c.table == table && rows.contains(c.row) && columns.contains(c.column)
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
    /// The named styles paragraphs refer to.
    public var styles: RichStyleSheet = .word
    /// Per list id, the label format of each level (Word's lvlText and
    /// numFmt); a level without one is "%n." in decimal.
    public var listFormats: [String: [Int: ListLevelFormat]] = [:]

    public static let pageField = "{PAGE}"
    public static let pageCountField = "{NUMPAGES}"

    /// `header`/`footer` with the fields filled in for page `page` (1-based).
    public static func fill(_ template: String, page: Int, pageCount: Int) -> String {
        template.replacingOccurrences(of: pageField, with: String(page))
            .replacingOccurrences(of: pageCountField, with: String(pageCount))
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
        let rows = min(ca.row, cb.row) ... max(ca.row + ca.rowSpan - 1, cb.row + cb.rowSpan - 1)
        let cols = min(ca.column, cb.column) ... max(ca.column + ca.span - 1, cb.column + cb.span - 1)
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

    public var wordCount: Int {
        var count = 0
        for p in paragraphs {
            var inWord = false
            for scalar in p.text.unicodeScalars {
                if scalar.properties.isWhitespace {
                    inWord = false
                } else if !inWord {
                    inWord = true
                    count += 1
                }
            }
        }
        return count
    }

    public var characterCount: Int {
        paragraphs.reduce(0) { $0 + $1.text.count }
    }
}
