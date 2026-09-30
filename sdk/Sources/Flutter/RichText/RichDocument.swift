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
    /// 1...6 for a heading, nil for body text. Named styles (Phase 2) build
    /// on this; the number is what `.docx` and Markdown both carry.
    public var heading: Int? = nil
    public var pageBreakBefore = false

    public init(alignment: ParagraphAlignment = .left, indentLeft: Double = 0,
                indentRight: Double = 0, firstLineIndent: Double = 0,
                spaceBefore: Double = 0, spaceAfter: Double = 0,
                lineSpacing: Double = 1.0, list: ListKind? = nil, listLevel: Int = 0,
                heading: Int? = nil, pageBreakBefore: Bool = false) {
        self.alignment = alignment
        self.indentLeft = indentLeft
        self.indentRight = indentRight
        self.firstLineIndent = firstLineIndent
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
        self.lineSpacing = lineSpacing
        self.list = list
        self.listLevel = listLevel
        self.heading = heading
        self.pageBreakBefore = pageBreakBefore
    }

    public static let body = RichParagraphStyle()
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

    public init(data: Data, width: Double, height: Double, name: String = "image.png") {
        self.id = UUID().uuidString
        self.data = data
        self.width = width
        self.height = height
        self.name = name
    }

    public static func == (a: ImageAttachment, b: ImageAttachment) -> Bool {
        a.id == b.id && a.width == b.width && a.height == b.height
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(width)
        hasher.combine(height)
    }

    public var isJPEG: Bool { data.count > 2 && data[0] == 0xFF && data[1] == 0xD8 }
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

    public init(table: String, row: Int, column: Int) {
        self.table = table
        self.row = row
        self.column = column
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

    private enum UnitClass { case space, word, punct }

    private static func classify(_ u: UInt16) -> UnitClass {
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
public struct RichSelection: Hashable, Sendable {
    public var anchor: RichPosition
    public var focus: RichPosition

    public init(anchor: RichPosition, focus: RichPosition) {
        self.anchor = anchor
        self.focus = focus
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
    public func fragment(_ selection: RichSelection) -> [RichParagraph] {
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
            if let c = p.cell, c.table == table { cols = max(cols, c.column + 1) }
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
