// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The editing half of the rich-text stack: every mutation of a RichDocument
// goes through here as an `EditOp` with an inverse, which is what makes
// undo/redo a stack of op lists rather than document snapshots. Typing
// coalesces into one undo step until the caret jumps or a non-typing edit
// lands, the way every desktop editor does it.
//
// Listeners (the RichEditable widget, a toolbar) get `notifyListeners()` after
// each user-level action; `drainChanges()` hands the layout the paragraph-level
// invalidation it needs so a keystroke re-lays out one paragraph, not the
// document.

import FlutterSwiftBridge
import Foundation

// MARK: - Change log

/// Paragraph-level invalidation, consumed by `RichLayout`.
public enum RichChange: Equatable, Sendable {
    /// Paragraph `index`'s text, runs or style changed in place.
    case changed(Int)
    /// `count` paragraphs were inserted before `index`.
    case inserted(at: Int, count: Int)
    /// `count` paragraphs starting at `index` were removed.
    case removed(at: Int, count: Int)
    /// Everything: a new document was loaded.
    case all
}

// MARK: - Edit operations

/// One reversible edit. `apply` mutates the document and returns the op that
/// undoes it; the controller records that inverse.
public enum EditOp: Equatable, Sendable {
    case insertText(RichPosition, String, [Run])
    case deleteText(RichPosition, String, [Run])
    /// Split the paragraph at the position; the tail takes `tailStyle`.
    case splitParagraph(RichPosition, tailStyle: RichParagraphStyle)
    /// Join paragraph `index + 1` onto `index`; `removedStyle` is the tail's
    /// style, kept so the inverse split restores it.
    case mergeParagraph(Int, removedStyle: RichParagraphStyle)
    case setRuns(Int, old: [Run], new: [Run])
    case setParagraphStyle(Int, old: RichParagraphStyle, new: RichParagraphStyle)
    case insertParagraphs(at: Int, [RichParagraph])
    case removeParagraphs(at: Int, [RichParagraph])

    /// Apply to `doc`, appending the invalidation to `changes`, and return
    /// the inverse.
    @discardableResult
    func apply(to doc: inout RichDocument, changes: inout [RichChange]) -> EditOp {
        switch self {
        case .insertText(let pos, let text, let runs):
            doc.paragraphs[pos.paragraph].insert(text, at: pos.offset, runs: runs)
            changes.append(.changed(pos.paragraph))
            return .deleteText(pos, text, runs)
        case .deleteText(let pos, let text, let runs):
            let units = text.utf16.count
            let removed = doc.paragraphs[pos.paragraph].delete(pos.offset ..< pos.offset + units)
            changes.append(.changed(pos.paragraph))
            // Prefer what was actually removed (defensive: identical unless a
            // caller composed ops by hand).
            return .insertText(pos, removed.text.isEmpty ? text : removed.text,
                               removed.runs.isEmpty ? runs : removed.runs)
        case .splitParagraph(let pos, let tailStyle):
            var tail = doc.paragraphs[pos.paragraph].split(at: pos.offset)
            let removedStyle = tail.style
            tail.style = tailStyle
            doc.paragraphs.insert(tail, at: pos.paragraph + 1)
            changes.append(.changed(pos.paragraph))
            changes.append(.inserted(at: pos.paragraph + 1, count: 1))
            _ = removedStyle
            return .mergeParagraph(pos.paragraph, removedStyle: tailStyle)
        case .mergeParagraph(let index, let removedStyle):
            let headLength = doc.paragraphs[index].length
            let tail = doc.paragraphs.remove(at: index + 1)
            doc.paragraphs[index].append(tail)
            changes.append(.changed(index))
            changes.append(.removed(at: index + 1, count: 1))
            _ = removedStyle
            return .splitParagraph(RichPosition(paragraph: index, offset: headLength),
                                   tailStyle: tail.style)
        case .setRuns(let index, let old, let new):
            doc.paragraphs[index].runs = new
            doc.paragraphs[index].normalize()
            changes.append(.changed(index))
            return .setRuns(index, old: new, new: old)
        case .setParagraphStyle(let index, let old, let new):
            doc.paragraphs[index].style = new
            changes.append(.changed(index))
            return .setParagraphStyle(index, old: new, new: old)
        case .insertParagraphs(let at, let paras):
            doc.paragraphs.insert(contentsOf: paras, at: at)
            changes.append(.inserted(at: at, count: paras.count))
            return .removeParagraphs(at: at, paras)
        case .removeParagraphs(let at, let paras):
            let removed = Array(doc.paragraphs[at ..< at + paras.count])
            doc.paragraphs.removeSubrange(at ..< at + paras.count)
            if doc.paragraphs.isEmpty { doc.paragraphs = [RichParagraph()] }
            changes.append(.removed(at: at, count: paras.count))
            return .insertParagraphs(at: at, removed)
        }
    }
}

// MARK: - Undo entries

private enum UndoKind: Equatable {
    case typing        // coalescable character insertion
    case deleting      // coalescable backspace
    case other
}

private struct UndoEntry {
    var inverses: [EditOp]           // in application order; undo applies reversed
    var selectionBefore: RichSelection
    var selectionAfter: RichSelection
    var kind: UndoKind
    /// Where the next coalescable keystroke must land to join this entry.
    var continuation: RichPosition?
}

// MARK: - Controller

/// Owns a `RichDocument`, its selection, and the undo history.
public final class RichDocumentController: ChangeNotifier {
    public private(set) var document: RichDocument

    /// Set directly to move the caret without an edit (clicks, arrows).
    public var selection: RichSelection {
        didSet {
            selection = RichSelection(anchor: document.clamped(selection.anchor),
                                      focus: document.clamped(selection.focus))
            if selection != oldValue {
                // A caret move breaks the typing run and drops the pending
                // style: Word does exactly this.
                if !_inEdit {
                    _breakCoalescing()
                    typingStyle = nil
                }
                notifyListeners()
            }
        }
    }

    /// The style the next typed character takes at a collapsed caret after
    /// a toggle (Ctrl+B with nothing selected). Cleared by any caret move.
    public var typingStyle: CharStyle?

    /// The last rich fragment copied from THIS controller, so an in-app paste
    /// keeps its formatting while the system clipboard only carries text.
    public private(set) var copiedFragment: [RichParagraph]?

    /// Editing is refused when set (a viewer, a locked document).
    public var readOnly = false

    private var _undo: [UndoEntry] = []
    private var _redo: [UndoEntry] = []
    private var _pendingChanges: [RichChange] = []
    private var _inEdit = false
    /// Paragraphs the current top-level action has touched: drained by the
    /// layout with `drainChanges()`.
    public var hasPendingChanges: Bool { !_pendingChanges.isEmpty }

    public var maxUndoDepth = 500

    /// Bumped by every edit, undo and redo — compare against the value at
    /// the last save to know whether the document is dirty.
    public private(set) var revision = 0

    public init(document: RichDocument = RichDocument()) {
        self.document = document
        self.selection = RichSelection(caret: .start)
        super.init()
    }

    public convenience init(plainText: String) {
        self.init(document: RichDocument(plainText: plainText))
    }

    // MARK: Loading

    /// Replace the document wholesale (open a file). Clears history.
    public func load(_ doc: RichDocument) {
        document = doc
        _undo.removeAll()
        _redo.removeAll()
        typingStyle = nil
        revision += 1
        _pendingChanges = [.all]
        selection = RichSelection(caret: .start)
        notifyListeners()
    }

    /// Hand the accumulated paragraph invalidation to whoever lays out.
    public func drainChanges() -> [RichChange] {
        let out = _pendingChanges
        _pendingChanges.removeAll()
        return out
    }

    // MARK: Queries

    public var caret: RichPosition { selection.focus }
    public var hasSelection: Bool { !selection.isCollapsed }
    public var canUndo: Bool { !_undo.isEmpty }
    public var canRedo: Bool { !_redo.isEmpty }

    public var selectedText: String {
        selection.isCollapsed ? "" : document.text(in: selection)
    }

    /// The character style a toolbar should show: the pending typing style,
    /// else the style at the caret, else — over a selection — the style of
    /// its first run.
    public var currentCharStyle: CharStyle {
        if let typingStyle { return typingStyle }
        let p = document.clamped(selection.start)
        return document.paragraphs[p.paragraph].style(at: selection.isCollapsed ? p.offset : p.offset + 1)
    }

    /// True when EVERY run in the selection satisfies `predicate` (so a
    /// mixed selection shows bold as off, and toggling turns it on for all).
    public func selectionAll(_ predicate: (CharStyle) -> Bool) -> Bool {
        if selection.isCollapsed { return predicate(currentCharStyle) }
        for run in document.fragment(selection).flatMap(\.runs) where run.length > 0 {
            if !predicate(run.style) { return false }
        }
        return true
    }

    public var currentParagraphStyle: RichParagraphStyle {
        document.paragraphs[document.clamped(selection.focus).paragraph].style
    }

    /// Paragraph indices the selection touches.
    public var selectedParagraphRange: ClosedRange<Int> {
        let a = document.clamped(selection.start).paragraph
        let b = document.clamped(selection.end).paragraph
        return a ... b
    }

    // MARK: Editing primitives

    /// Run `body` as one undoable action. Nested calls join the outer one.
    public func edit(kind: UndoKindHint = .other, _ body: () -> Void) {
        guard !readOnly else { return }
        let outer = _inEdit
        let undoKind: UndoKind
        switch kind {
        case .typing: undoKind = .typing
        case .deleting: undoKind = .deleting
        case .other: undoKind = .other
        }
        if !outer {
            _inEdit = true
            _redo.removeAll()
            let coalesce: Bool = {
                guard undoKind != .other, let last = _undo.last, last.kind == undoKind,
                      let cont = last.continuation, cont == selection.focus,
                      selection.isCollapsed else { return false }
                return true
            }()
            if !coalesce {
                _undo.append(UndoEntry(inverses: [], selectionBefore: selection,
                                       selectionAfter: selection, kind: undoKind,
                                       continuation: nil))
                if _undo.count > maxUndoDepth { _undo.removeFirst(_undo.count - maxUndoDepth) }
            }
        }
        body()
        if !outer {
            _inEdit = false
            _undo[_undo.count - 1].selectionAfter = selection
            _undo[_undo.count - 1].continuation = undoKind == .other ? nil : selection.focus
            if _undo[_undo.count - 1].inverses.isEmpty {
                _undo.removeLast()
            } else {
                revision += 1
            }
            notifyListeners()
        }
    }

    public enum UndoKindHint { case typing, deleting, other }

    /// Apply one op inside an `edit` block.
    public func perform(_ op: EditOp) {
        precondition(_inEdit, "perform(_:) must run inside edit { }")
        let inverse = op.apply(to: &document, changes: &_pendingChanges)
        _undo[_undo.count - 1].inverses.append(inverse)
    }

    private func _breakCoalescing() {
        if !_undo.isEmpty { _undo[_undo.count - 1].continuation = nil }
    }

    // MARK: Undo / redo

    public func undo() {
        guard !readOnly, let entry = _undo.popLast() else { return }
        var redoInverses: [EditOp] = []
        for op in entry.inverses.reversed() {
            redoInverses.append(op.apply(to: &document, changes: &_pendingChanges))
        }
        _redo.append(UndoEntry(inverses: redoInverses.reversed(),
                               selectionBefore: entry.selectionBefore,
                               selectionAfter: entry.selectionAfter,
                               kind: .other, continuation: nil))
        typingStyle = nil
        revision += 1
        _inEdit = true
        selection = entry.selectionBefore
        _inEdit = false
        notifyListeners()
    }

    public func redo() {
        guard !readOnly, let entry = _redo.popLast() else { return }
        // entry.inverses undo the undo, i.e. they re-apply the original edit.
        var undoInverses: [EditOp] = []
        for op in entry.inverses {
            undoInverses.append(op.apply(to: &document, changes: &_pendingChanges))
        }
        _undo.append(UndoEntry(inverses: undoInverses,
                               selectionBefore: entry.selectionBefore,
                               selectionAfter: entry.selectionAfter,
                               kind: .other, continuation: nil))
        typingStyle = nil
        revision += 1
        _inEdit = true
        selection = entry.selectionAfter
        _inEdit = false
        notifyListeners()
    }

    // MARK: Text entry

    /// Type `string` at the caret, replacing any selection. Newlines split
    /// paragraphs.
    public func insertText(_ string: String) {
        guard !string.isEmpty else { return }
        let hint: UndoKindHint = string.contains("\n") ? .other : .typing
        edit(kind: hint) {
            if hasSelection { _deleteSelectionOps() }
            let style = typingStyle
            let pieces = string.split(separator: "\n", omittingEmptySubsequences: false)
            for (i, piece) in pieces.enumerated() {
                if i > 0 { _splitAtCaret() }
                let text = String(piece)
                if !text.isEmpty {
                    let pos = selection.focus
                    let runs = style.map { [Run(length: text.utf16.count, style: $0)] }
                    perform(.insertText(pos, text, runs ?? [Run(length: text.utf16.count,
                                                                  style: document.paragraphs[pos.paragraph].style(at: pos.offset))]))
                    _setCaret(RichPosition(paragraph: pos.paragraph, offset: pos.offset + text.utf16.count))
                }
            }
            typingStyle = style  // a typed run keeps the pending style alive
        }
    }

    /// Enter: split the paragraph at the caret. A heading's continuation is
    /// body text, as in every word processor.
    public func insertParagraphBreak() {
        edit {
            if hasSelection { _deleteSelectionOps() }
            _splitAtCaret()
        }
    }

    private func _splitAtCaret() {
        let pos = selection.focus
        var tailStyle = document.paragraphs[pos.paragraph].style
        if tailStyle.heading != nil && pos.offset == document.paragraphs[pos.paragraph].length {
            tailStyle.heading = nil
        }
        tailStyle.pageBreakBefore = false
        perform(.splitParagraph(pos, tailStyle: tailStyle))
        _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
    }

    /// Insert a fragment (a rich paste) at the caret.
    public func insertFragment(_ fragment: [RichParagraph]) {
        guard !fragment.isEmpty else { return }
        edit {
            if hasSelection { _deleteSelectionOps() }
            var pos = selection.focus
            for (i, para) in fragment.enumerated() {
                if i > 0 {
                    perform(.splitParagraph(pos, tailStyle: para.style))
                    pos = RichPosition(paragraph: pos.paragraph + 1, offset: 0)
                    // A fragment's inner paragraphs carry their own style.
                    let old = document.paragraphs[pos.paragraph].style
                    if old != para.style {
                        perform(.setParagraphStyle(pos.paragraph, old: old, new: para.style))
                    }
                }
                if !para.text.isEmpty {
                    perform(.insertText(pos, para.text, para.runs))
                    pos.offset += para.length
                }
            }
            _setCaret(pos)
        }
    }

    // MARK: Deletion

    public func deleteBackward() {
        edit(kind: hasSelection ? .other : .deleting) {
            if hasSelection {
                _deleteSelectionOps()
                return
            }
            _backspaceOps(word: false)
        }
    }

    public func deleteForward() {
        edit {
            if hasSelection {
                _deleteSelectionOps()
                return
            }
            _deleteForwardOps(word: false)
        }
    }

    public func deleteWordBackward() {
        edit {
            if hasSelection {
                _deleteSelectionOps()
                return
            }
            _backspaceOps(word: true)
        }
    }

    public func deleteWordForward() {
        edit {
            if hasSelection {
                _deleteSelectionOps()
                return
            }
            _deleteForwardOps(word: true)
        }
    }

    /// Backspace at a collapsed caret: one grapheme (or one word), or join
    /// with the previous paragraph at offset 0.
    private func _backspaceOps(word: Bool) {
        let pos = selection.focus
        if pos.offset > 0 {
            let para = document.paragraphs[pos.paragraph]
            let from = word ? para.wordStart(before: pos.offset) : para.graphemeBefore(pos.offset)
            _deleteRange(in: pos.paragraph, from ..< pos.offset)
            _setCaret(RichPosition(paragraph: pos.paragraph, offset: from))
        } else if pos.paragraph > 0 {
            let prevLen = document.paragraphs[pos.paragraph - 1].length
            perform(.mergeParagraph(pos.paragraph - 1,
                                    removedStyle: document.paragraphs[pos.paragraph].style))
            _setCaret(RichPosition(paragraph: pos.paragraph - 1, offset: prevLen))
        }
    }

    private func _deleteForwardOps(word: Bool) {
        let pos = selection.focus
        let para = document.paragraphs[pos.paragraph]
        if pos.offset < para.length {
            let to = word ? para.wordEnd(after: pos.offset) : para.graphemeAfter(pos.offset)
            _deleteRange(in: pos.paragraph, pos.offset ..< to)
        } else if pos.paragraph + 1 < document.paragraphs.count {
            perform(.mergeParagraph(pos.paragraph,
                                    removedStyle: document.paragraphs[pos.paragraph + 1].style))
        }
        _setCaret(pos)
    }

    public func deleteSelection() {
        guard hasSelection else { return }
        edit { _deleteSelectionOps() }
    }

    private func _deleteRange(in paragraph: Int, _ range: Range<Int>) {
        guard range.upperBound > range.lowerBound else { return }
        let para = document.paragraphs[paragraph]
        let a = String.Index(utf16Offset: range.lowerBound, in: para.text)
        let b = String.Index(utf16Offset: range.upperBound, in: para.text)
        let text = String(para.text[a ..< b])
        perform(.deleteText(RichPosition(paragraph: paragraph, offset: range.lowerBound),
                            text, para.runs(in: range)))
    }

    /// Remove the selection's contents; caret lands at its start.
    private func _deleteSelectionOps() {
        let a = document.clamped(selection.start)
        let b = document.clamped(selection.end)
        guard a != b else { return }
        if a.paragraph == b.paragraph {
            _deleteRange(in: a.paragraph, a.offset ..< b.offset)
        } else {
            // Tail of the first, head of the last, the middle ones whole,
            // then join first and last.
            let firstLen = document.paragraphs[a.paragraph].length
            _deleteRange(in: a.paragraph, a.offset ..< firstLen)
            _deleteRange(in: b.paragraph, 0 ..< b.offset)
            let middle = b.paragraph - a.paragraph - 1
            if middle > 0 {
                let paras = Array(document.paragraphs[(a.paragraph + 1) ..< b.paragraph])
                perform(.removeParagraphs(at: a.paragraph + 1, paras))
            }
            perform(.mergeParagraph(a.paragraph,
                                    removedStyle: document.paragraphs[a.paragraph + 1].style))
        }
        _setCaret(a)
    }

    private func _setCaret(_ p: RichPosition) {
        selection = RichSelection(caret: p)
    }

    // MARK: Character formatting

    /// Apply `transform` to the selection's runs, or to the typing style at
    /// a collapsed caret.
    public func applyCharStyle(_ transform: @escaping (inout CharStyle) -> Void) {
        if selection.isCollapsed {
            var style = currentCharStyle
            transform(&style)
            typingStyle = style
            notifyListeners()
            return
        }
        edit {
            let a = document.clamped(selection.start)
            let b = document.clamped(selection.end)
            for i in a.paragraph ... b.paragraph {
                let lo = i == a.paragraph ? a.offset : 0
                let hi = i == b.paragraph ? b.offset : document.paragraphs[i].length
                var para = document.paragraphs[i]
                let old = para.runs
                para.applyStyle(lo ..< hi, transform)
                if para.runs != old {
                    perform(.setRuns(i, old: old, new: para.runs))
                }
            }
        }
    }

    public func toggleBold() {
        let on = !selectionAll { $0.bold }
        applyCharStyle { $0.bold = on }
    }

    public func toggleItalic() {
        let on = !selectionAll { $0.italic }
        applyCharStyle { $0.italic = on }
    }

    public func toggleUnderline() {
        let on = !selectionAll { $0.underline }
        applyCharStyle { $0.underline = on }
    }

    public func toggleStrikethrough() {
        let on = !selectionAll { $0.strikethrough }
        applyCharStyle { $0.strikethrough = on }
    }

    public func setFontFamily(_ family: String?) {
        applyCharStyle { $0.fontFamily = family }
    }

    public func setFontSize(_ points: Double?) {
        applyCharStyle { $0.fontSize = points }
    }

    /// Step the font size the way Word's Grow/Shrink Font do, relative to
    /// `base` (the document default) where a run has no size of its own.
    public func stepFontSize(_ direction: Int, base: Double) {
        let steps: [Double] = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72]
        applyCharStyle { style in
            let current = style.fontSize ?? base
            if direction > 0 {
                style.fontSize = steps.first(where: { $0 > current + 0.01 }) ?? min(200, current + 12)
            } else {
                style.fontSize = steps.last(where: { $0 < current - 0.01 }) ?? max(1, current - 1)
            }
        }
    }

    public func setTextColor(_ color: Color?) {
        applyCharStyle { $0.color = color }
    }

    public func setHighlight(_ color: Color?) {
        applyCharStyle { $0.highlight = color }
    }

    public func setScript(_ script: ScriptPosition) {
        let on = !selectionAll { $0.script == script }
        applyCharStyle { $0.script = on ? script : .normal }
    }

    /// Word's Clear All Formatting: plain runs and a body paragraph.
    public func clearFormatting() {
        edit {
            let a = document.clamped(selection.start)
            let b = document.clamped(selection.end)
            for i in a.paragraph ... b.paragraph {
                let old = document.paragraphs[i]
                var para = old
                if selection.isCollapsed || (a.paragraph == b.paragraph) {
                    let lo = a.paragraph == b.paragraph ? a.offset : 0
                    let hi = a.paragraph == b.paragraph ? b.offset : para.length
                    para.applyStyle(lo ..< hi) { $0 = .plain }
                } else {
                    para.applyStyle(0 ..< para.length) { $0 = .plain }
                }
                if para.runs != old.runs { perform(.setRuns(i, old: old.runs, new: para.runs)) }
                if old.style != .body { perform(.setParagraphStyle(i, old: old.style, new: .body)) }
            }
            typingStyle = nil
        }
    }

    // MARK: Paragraph formatting

    public func setLineSpacing(_ multiple: Double) {
        applyParagraphStyle { $0.lineSpacing = multiple }
    }

    public func setParagraphSpacing(before: Double? = nil, after: Double? = nil) {
        applyParagraphStyle { style in
            if let before { style.spaceBefore = max(0, before) }
            if let after { style.spaceAfter = max(0, after) }
        }
    }

    public func setIndents(left: Double? = nil, right: Double? = nil, firstLine: Double? = nil) {
        applyParagraphStyle { style in
            if let left { style.indentLeft = max(0, left) }
            if let right { style.indentRight = max(0, right) }
            if let firstLine { style.firstLineIndent = firstLine }
        }
    }

    /// Start a new page at the caret: the text after it becomes a paragraph
    /// with `pageBreakBefore`.
    public func insertPageBreak() {
        edit {
            if hasSelection { _deleteSelectionOps() }
            let pos = selection.focus
            var tailStyle = document.paragraphs[pos.paragraph].style
            tailStyle.pageBreakBefore = true
            perform(.splitParagraph(pos, tailStyle: tailStyle))
            _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
        }
    }

    // MARK: Find

    /// The next occurrence of `query` after `from` (wrapping), or nil.
    public func find(_ query: String, from: RichPosition? = nil, backwards: Bool = false,
                     caseSensitive: Bool = false) -> RichSelection? {
        guard !query.isEmpty else { return nil }
        let start = document.clamped(from ?? (backwards ? selection.start : selection.end))
        let n = document.paragraphs.count
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        func search(_ i: Int, lo: Int?, hi: Int?) -> RichSelection? {
            let text = document.paragraphs[i].text
            let a = lo.map { String.Index(utf16Offset: $0, in: text) } ?? text.startIndex
            let b = hi.map { String.Index(utf16Offset: $0, in: text) } ?? text.endIndex
            guard a <= b else { return nil }
            var opts = options
            if backwards { opts.insert(.backwards) }
            guard let r = text.range(of: query, options: opts, range: a ..< b) else { return nil }
            return RichSelection(
                anchor: RichPosition(paragraph: i, offset: r.lowerBound.utf16Offset(in: text)),
                focus: RichPosition(paragraph: i, offset: r.upperBound.utf16Offset(in: text)))
        }
        if !backwards {
            if let s = search(start.paragraph, lo: start.offset, hi: nil) { return s }
            for k in 1 ... n {
                let i = (start.paragraph + k) % n
                if let s = search(i, lo: nil, hi: i == start.paragraph ? start.offset + query.utf16.count : nil) { return s }
            }
        } else {
            if let s = search(start.paragraph, lo: nil, hi: start.offset) { return s }
            for k in 1 ... n {
                let i = (start.paragraph - k + n * 2) % n
                if let s = search(i, lo: i == start.paragraph ? start.offset : nil, hi: nil) { return s }
            }
        }
        return nil
    }

    /// Replace every occurrence; returns the count.
    @discardableResult
    public func replaceAll(_ query: String, with replacement: String, caseSensitive: Bool = false) -> Int {
        guard !query.isEmpty else { return 0 }
        var count = 0
        edit {
            for i in document.paragraphs.indices {
                var text = document.paragraphs[i].text
                let opts: String.CompareOptions = caseSensitive ? [.backwards] : [.caseInsensitive, .backwards]
                // Backwards so earlier offsets stay valid.
                var searchEnd = text.endIndex
                while let r = text.range(of: query, options: opts, range: text.startIndex ..< searchEnd) {
                    let lo = r.lowerBound.utf16Offset(in: text)
                    let hi = r.upperBound.utf16Offset(in: text)
                    let para = document.paragraphs[i]
                    let style = para.style(at: lo + 1)
                    _deleteRange(in: i, lo ..< hi)
                    if !replacement.isEmpty {
                        perform(.insertText(RichPosition(paragraph: i, offset: lo), replacement,
                                            [Run(length: replacement.utf16.count, style: style)]))
                    }
                    count += 1
                    text = document.paragraphs[i].text
                    searchEnd = String.Index(utf16Offset: lo, in: text)
                }
            }
            _setCaret(document.clamped(selection.focus))
        }
        return count
    }

    /// Apply `transform` to every paragraph the selection touches.
    public func applyParagraphStyle(_ transform: (inout RichParagraphStyle) -> Void) {
        edit {
            for i in selectedParagraphRange {
                let old = document.paragraphs[i].style
                var new = old
                transform(&new)
                if new != old { perform(.setParagraphStyle(i, old: old, new: new)) }
            }
        }
    }

    public func setAlignment(_ alignment: ParagraphAlignment) {
        applyParagraphStyle { $0.alignment = alignment }
    }

    public func setHeading(_ level: Int?) {
        applyParagraphStyle { $0.heading = level }
    }

    public func toggleList(_ kind: ListKind) {
        let allOn = selectedParagraphRange.allSatisfy { document.paragraphs[$0].style.list == kind }
        applyParagraphStyle { $0.list = allOn ? nil : kind }
    }

    public func indent(_ delta: Int) {
        applyParagraphStyle { style in
            if style.list != nil {
                style.listLevel = max(0, min(8, style.listLevel + delta))
            } else {
                style.indentLeft = max(0, style.indentLeft + Double(delta) * 36)
            }
        }
    }

    // MARK: Selection motion (model-level; visual motion lives in the layout)

    public func selectAll() {
        selection = RichSelection(anchor: .start, focus: document.endPosition)
    }

    public func moveTo(_ p: RichPosition, extend: Bool) {
        let p = document.clamped(p)
        selection = extend ? RichSelection(anchor: selection.anchor, focus: p)
                           : RichSelection(caret: p)
    }

    public func moveLeft(extend: Bool) {
        if !extend && hasSelection {
            moveTo(selection.start, extend: false)
            return
        }
        let pos = selection.focus
        if pos.offset > 0 {
            moveTo(RichPosition(paragraph: pos.paragraph,
                                offset: document.paragraphs[pos.paragraph].graphemeBefore(pos.offset)),
                   extend: extend)
        } else if pos.paragraph > 0 {
            moveTo(RichPosition(paragraph: pos.paragraph - 1,
                                offset: document.paragraphs[pos.paragraph - 1].length),
                   extend: extend)
        }
    }

    public func moveRight(extend: Bool) {
        if !extend && hasSelection {
            moveTo(selection.end, extend: false)
            return
        }
        let pos = selection.focus
        let para = document.paragraphs[pos.paragraph]
        if pos.offset < para.length {
            moveTo(RichPosition(paragraph: pos.paragraph, offset: para.graphemeAfter(pos.offset)),
                   extend: extend)
        } else if pos.paragraph + 1 < document.paragraphs.count {
            moveTo(RichPosition(paragraph: pos.paragraph + 1, offset: 0), extend: extend)
        }
    }

    public func moveWordLeft(extend: Bool) {
        let pos = selection.focus
        if pos.offset == 0 {
            moveLeft(extend: extend)
            return
        }
        moveTo(RichPosition(paragraph: pos.paragraph,
                            offset: document.paragraphs[pos.paragraph].wordStart(before: pos.offset)),
               extend: extend)
    }

    public func moveWordRight(extend: Bool) {
        let pos = selection.focus
        let para = document.paragraphs[pos.paragraph]
        if pos.offset >= para.length {
            moveRight(extend: extend)
            return
        }
        moveTo(RichPosition(paragraph: pos.paragraph, offset: para.wordEnd(after: pos.offset)),
               extend: extend)
    }

    public func moveToDocumentStart(extend: Bool) { moveTo(.start, extend: extend) }
    public func moveToDocumentEnd(extend: Bool) { moveTo(document.endPosition, extend: extend) }

    public func selectWord(at p: RichPosition) {
        let p = document.clamped(p)
        let r = document.paragraphs[p.paragraph].wordRange(at: p.offset)
        selection = RichSelection(anchor: RichPosition(paragraph: p.paragraph, offset: r.lowerBound),
                                  focus: RichPosition(paragraph: p.paragraph, offset: r.upperBound))
    }

    public func selectParagraph(at p: RichPosition) {
        let p = document.clamped(p)
        selection = RichSelection(anchor: RichPosition(paragraph: p.paragraph, offset: 0),
                                  focus: RichPosition(paragraph: p.paragraph,
                                                      offset: document.paragraphs[p.paragraph].length))
    }

    // MARK: Clipboard helpers

    /// Remember the selection as a rich fragment and return its plain text
    /// for the system clipboard.
    public func copySelection() -> String? {
        guard hasSelection else { return nil }
        let fragment = document.fragment(selection)
        copiedFragment = fragment
        return fragment.map(\.text).joined(separator: "\n")
    }

    public func cutSelection() -> String? {
        guard let text = copySelection() else { return nil }
        deleteSelection()
        return text
    }

    /// Paste: if the system text is exactly what we last copied, paste the
    /// rich fragment; otherwise plain text.
    public func paste(text: String) {
        if let fragment = copiedFragment,
           fragment.map(\.text).joined(separator: "\n") == text {
            insertFragment(fragment)
        } else {
            insertText(text)
        }
    }
}
