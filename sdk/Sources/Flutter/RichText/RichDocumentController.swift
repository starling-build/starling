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
    /// A list's level formats changed: every label is stale.
    case lists
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
    case setHeaderFooter(header: String, footer: String, oldHeader: String, oldFooter: String)
    /// A picture's shown size (its attachment replaced; the id survives).
    case setImage(Int, old: ImageAttachment, new: ImageAttachment)
    /// A table's column widths in points (nil: equal columns).
    case setTableColumns(String, old: [Double]?, new: [Double]?)
    /// One entry of the style sheet, replaced (every paragraph re-lays out).
    case setStyleEntry(old: RichNamedStyle, new: RichNamedStyle)
    /// A table's look (nil: the default).
    case setTableStyle(String, old: TableStyle?, new: TableStyle?)
    /// One level's format of one list (nil: the level's default).
    case setListFormat(String, level: Int, old: ListLevelFormat?, new: ListLevelFormat?)

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
        case .setHeaderFooter(let header, let footer, let oldHeader, let oldFooter):
            doc.header = header
            doc.footer = footer
            changes.append(.all)
            return .setHeaderFooter(header: oldHeader, footer: oldFooter, oldHeader: header, oldFooter: footer)
        case .setImage(let index, let old, let new):
            doc.paragraphs[index].image = new
            changes.append(.changed(index))
            return .setImage(index, old: new, new: old)
        case .setTableColumns(let table, let old, let new):
            doc.tableColumns[table] = new
            for i in doc.paragraphs.indices where doc.paragraphs[i].cell?.table == table { changes.append(.changed(i)) }
            return .setTableColumns(table, old: new, new: old)
        case .setStyleEntry(let old, let new):
            doc.styles[new.id] = new
            changes.append(.all)
            return .setStyleEntry(old: new, new: old)
        case .setTableStyle(let table, let old, let new):
            doc.tableStyles[table] = new
            for i in doc.paragraphs.indices where doc.paragraphs[i].cell?.table == table { changes.append(.changed(i)) }
            return .setTableStyle(table, old: new, new: old)
        case .setListFormat(let id, let level, let old, let new):
            var formats = doc.listFormats[id] ?? [:]
            formats[level] = new
            doc.listFormats[id] = formats.isEmpty ? nil : formats
            // The label's width is part of each item's layout.
            for i in doc.paragraphs.indices where doc.paragraphs[i].style.listId == id { changes.append(.changed(i)) }
            changes.append(.lists)
            return .setListFormat(id, level: level, old: new, new: old)
        }
    }
}

// MARK: - Undo entries

private enum UndoKind: Equatable {
    case typing        // coalescable character insertion
    case deleting      // coalescable backspace
    case styleEdit     // coalescable Modify Style controls (one dialog, one step)
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
            // Re-clamp, and keep a block only while both ends are still in
            // its table: an edit can have rewritten the cells under it.
            let a = document.clamped(selection.anchor), f = document.clamped(selection.focus)
            let block = selection.block.flatMap { b in
                document.cellBlock(from: a, to: f).map { _ in b }
            }
            selection = RichSelection(anchor: a, focus: f, block: block)
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
        case .styleEdit: undoKind = .styleEdit
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

    public enum UndoKindHint { case typing, deleting, styleEdit, other }

    /// End a run of coalesced edits: the next one starts a new undo step.
    /// A Modify Style strip calls this on Done, as typing does on a click.
    public func breakUndoCoalescing() { _breakCoalescing() }

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
        let hint: UndoKindHint = string.contains(Character("\n")) ? .other : .typing
        edit(kind: hint) {
            if hasSelection { _deleteSelectionOps() }
            if document.paragraphs[selection.focus.paragraph].isImage {
                // Typing on a picture starts a paragraph below it.
                let i = selection.focus.paragraph
                perform(.insertParagraphs(at: i + 1, [RichParagraph()]))
                _setCaret(RichPosition(paragraph: i + 1, offset: 0))
            }
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
            // Enter on an empty list item ends the list (Word, Pages, every
            // editor): the item becomes a plain paragraph instead of a
            // second empty bullet.
            let here = document.paragraphs[selection.focus.paragraph]
            if here.text.isEmpty, here.style.list != nil, !here.isImage {
                var style = here.style
                style.list = nil
                style.listLevel = 0
                perform(.setParagraphStyle(selection.focus.paragraph, old: here.style, new: style))
                return
            }
            _splitAtCaret()
        }
    }

    private func _splitAtCaret() {
        let pos = selection.focus
        if document.paragraphs[pos.paragraph].isImage {
            perform(.insertParagraphs(at: pos.paragraph + 1, [RichParagraph()]))
            _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
            return
        }
        var tailStyle = document.paragraphs[pos.paragraph].style
        if pos.offset == document.paragraphs[pos.paragraph].length {
            // Enter at the end of a heading or title starts a Normal
            // paragraph; a style without a `next` (Quote, Code) carries on.
            if let entry = document.styles.resolve(tailStyle) {
                if let next = entry.next, next != entry.id { document.styles.apply(next, to: &tailStyle) }
            } else if tailStyle.heading != nil {
                tailStyle.heading = nil
            }
        }
        tailStyle.pageBreakBefore = false
        perform(.splitParagraph(pos, tailStyle: tailStyle))
        _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
    }

    /// Insert a fragment (a rich paste) at the caret.
    /// Word's "smart cut and paste": a pasted or dropped word gets the
    /// space it needs on either side, and a cut leaves no double space
    /// and no space before a full stop. On by default.
    public var smartSpacing = true

    /// Insert `fragment` at the caret (replacing a selection). With
    /// `smart`, single-paragraph text is padded with a space where it
    /// would otherwise run into a word; the caret ends after the text and
    /// `lastInserted` records where the text itself went.
    @discardableResult
    public func insertFragment(_ fragment: [RichParagraph], smart: Bool = false) -> (before: Bool, after: Bool) {
        guard !fragment.isEmpty else { return (false, false) }
        var applied = (before: false, after: false)
        edit {
            if hasSelection { _deleteSelectionOps() }
            if document.paragraphs[selection.focus.paragraph].isImage {
                // Pasting or dropping on a picture goes below it, as typing does.
                let i = selection.focus.paragraph
                perform(.insertParagraphs(at: i + 1, [RichParagraph()]))
                _setCaret(RichPosition(paragraph: i + 1, offset: 0))
            }
            var fragment = fragment
            var pos = selection.focus
            if smart, fragment.count == 1, !fragment[0].isImage {
                let pad = _smartPad(fragment[0].text, at: pos)
                // The added spaces are the destination's, not the fragment's
                // (a pasted link must not grow by a linked space).
                let here = [Run(length: 1, style: document.paragraphs[pos.paragraph].style(at: pos.offset))]
                if pad.before { fragment[0].insert(" ", at: 0, runs: here) }
                if pad.after { fragment[0].insert(" ", at: fragment[0].length, runs: here) }
                applied = pad
            }
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
        return applied
    }

    /// Whether `text`, put at `pos`, needs a space before or after it so
    /// as not to run into the word there.
    private func _smartPad(_ text: String, at pos: RichPosition) -> (before: Bool, after: Bool) {
        guard smartSpacing, let f = text.utf16.first, let l = text.utf16.last,
              !document.paragraphs[pos.paragraph].isImage else { return (false, false) }
        let units = Array(document.paragraphs[pos.paragraph].text.utf16)
        let prevIsWord = pos.offset > 0 && RichParagraph.classify(units[pos.offset - 1]) == .word
        let nextIsWord = pos.offset < units.count && RichParagraph.classify(units[pos.offset]) == .word
        // Between words only: inside a word (letters on both sides) Word
        // pads nothing, and neither do we.
        if prevIsWord && nextIsWord { return (false, false) }
        let before = prevIsWord && RichParagraph.classify(f) == .word
        let after = nextIsWord && RichParagraph.classify(l) == .word
        return (before, after)
    }

    /// What a space never precedes: sentence and clause ends, closers.
    private static let _closingPunctuation: Set<UInt16> = Set(".,;:!?)]}\u{00BB}\u{201D}\u{2019}".utf16)

    /// After a cut or a move removed text at the caret: one space where
    /// two met, none before a full stop or at the paragraph's start.
    /// Returns where a unit was removed, so a caller can shift positions.
    @discardableResult
    private func _tidySpacesAtCaret() -> RichPosition? {
        guard smartSpacing else { return nil }
        let pos = selection.focus
        let para = document.paragraphs[pos.paragraph]
        guard !para.isImage else { return nil }
        let units = Array(para.text.utf16)
        let space: UInt16 = 0x20
        let before = pos.offset > 0 ? units[pos.offset - 1] : nil
        let after = pos.offset < units.count ? units[pos.offset] : nil
        var removeAt: Int? = nil
        if before == space, after == space { removeAt = pos.offset }
        else if before == space, let a = after, Self._closingPunctuation.contains(a) { removeAt = pos.offset - 1 }
        else if before == nil, after == space { removeAt = pos.offset }
        guard let at = removeAt else { return nil }
        _deleteRange(in: pos.paragraph, at ..< at + 1)
        _setCaret(RichPosition(paragraph: pos.paragraph, offset: at))
        return RichPosition(paragraph: pos.paragraph, offset: at)
    }

    /// Drag-and-drop: move the selected text to `drop` (or, with `copy`,
    /// put a copy there) and select it in its new place, as Word does. A
    /// drop inside the selection does nothing. Cell blocks do not drag.
    public func moveSelection(to drop: RichPosition, copy: Bool) {
        guard hasSelection, selection.block == nil else { return }
        let a = document.clamped(selection.start), b = document.clamped(selection.end)
        let drop = document.clamped(drop)
        guard drop < a || drop > b else { return }
        let fragment = document.fragment(selection)
        edit {
            var target = drop
            if !copy {
                _deleteSelectionOps()
                if drop > b {
                    // What followed the removed range moved up to its start.
                    target = drop.paragraph == b.paragraph
                        ? RichPosition(paragraph: a.paragraph, offset: a.offset + drop.offset - b.offset)
                        : RichPosition(paragraph: drop.paragraph - (b.paragraph - a.paragraph), offset: drop.offset)
                }
                if let removed = _tidySpacesAtCaret(), removed.paragraph == target.paragraph, removed.offset < target.offset {
                    target.offset -= 1
                }
            }
            _setCaret(target)
            let pad = insertFragment(fragment, smart: true)
            // Select the dropped text itself, not a space smart spacing added.
            let at = selection.focus   // after the fragment (and its pad)
            let text = fragment.map(\.text).joined(separator: "\n").utf16.count
            if fragment.count == 1 {
                let end = RichPosition(paragraph: at.paragraph, offset: at.offset - (pad.after ? 1 : 0))
                selection = RichSelection(anchor: RichPosition(paragraph: at.paragraph, offset: end.offset - text), focus: end)
            } else {
                selection = RichSelection(anchor: target, focus: at)
            }
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

    /// The picture the selection is on: a collapsed caret on an image
    /// paragraph, or a selection of exactly that paragraph.
    public var selectedImageIndex: Int? {
        let i = selection.focus.paragraph
        guard document.paragraphs[i].isImage else { return nil }
        if selection.isCollapsed { return i }
        return selection.anchor.paragraph == i ? i : nil
    }

    /// Put the caret on picture paragraph `index`, which selects it.
    public func selectImage(at index: Int) {
        guard index < document.paragraphs.count, document.paragraphs[index].isImage else { return }
        moveTo(RichPosition(paragraph: index, offset: 0), extend: false)
    }

    /// Show the picture at `index` at `width` × `height` points, one undo step.
    public func setImageSize(at index: Int, width: Double, height: Double) {
        guard index < document.paragraphs.count, let old = document.paragraphs[index].image else { return }
        let w = max(4, width), h = max(4, height)
        guard abs(w - old.width) > 0.01 || abs(h - old.height) > 0.01 else { return }
        var new = old
        new.width = w
        new.height = h
        edit { perform(.setImage(index, old: old, new: new)) }
    }

    /// Insert a picture as a paragraph of its own at the caret; the text
    /// after the caret continues below it.
    public func insertImage(_ image: ImageAttachment) {
        edit {
            if hasSelection { _deleteSelectionOps() }
            let pos = selection.focus
            let para = document.paragraphs[pos.paragraph]
            if para.isImage {
                perform(.insertParagraphs(at: pos.paragraph + 1, [RichParagraph(image: image)]))
                _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
                return
            }
            if para.text.isEmpty {
                // An empty paragraph becomes the picture; a fresh one follows.
                perform(.insertParagraphs(at: pos.paragraph, [RichParagraph(image: image, style: para.style)]))
                _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
                return
            }
            var tailStyle = para.style
            tailStyle.heading = nil
            if pos.offset < para.length {
                perform(.splitParagraph(pos, tailStyle: tailStyle))
            } else {
                perform(.insertParagraphs(at: pos.paragraph + 1, [RichParagraph(style: tailStyle)]))
            }
            perform(.insertParagraphs(at: pos.paragraph + 1, [RichParagraph(image: image)]))
            _setCaret(RichPosition(paragraph: pos.paragraph + 2, offset: 0))
        }
    }

    /// Backspace at a collapsed caret: one grapheme (or one word), or join
    /// with the previous paragraph at offset 0.
    private func _backspaceOps(word: Bool) {
        let pos = selection.focus
        let here = document.paragraphs[pos.paragraph]
        if here.isImage {
            // Backspace on a picture removes it.
            if document.paragraphs.count > 1 {
                perform(.removeParagraphs(at: pos.paragraph, [here]))
                let target = max(0, pos.paragraph - 1)
                _setCaret(RichPosition(paragraph: target,
                                       offset: pos.paragraph > 0 ? document.paragraphs[target].length : 0))
            }
            return
        }
        if pos.offset == 0, pos.paragraph > 0,
           document.paragraphs[pos.paragraph].cell != document.paragraphs[pos.paragraph - 1].cell {
            // Cell walls: backspace never joins across them.
            return
        }
        if pos.offset == 0, pos.paragraph > 0, document.paragraphs[pos.paragraph - 1].isImage {
            // Backspace right after a picture: select it (Word does this too),
            // so the next backspace removes it.
            _setCaret(RichPosition(paragraph: pos.paragraph - 1, offset: 0))
            return
        }
        if pos.offset == 0, !word, here.style.list != nil {
            // At the start of a list item the first Backspace takes the
            // bullet away; the next one joins, as usual.
            var style = here.style
            style.list = nil
            style.listLevel = 0
            perform(.setParagraphStyle(pos.paragraph, old: here.style, new: style))
            return
        }
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
        if para.isImage {
            if document.paragraphs.count > 1 {
                perform(.removeParagraphs(at: pos.paragraph, [para]))
                _setCaret(RichPosition(paragraph: min(pos.paragraph, document.paragraphs.count - 1), offset: 0))
            }
            return
        }
        if pos.offset >= para.length, pos.paragraph + 1 < document.paragraphs.count,
           para.cell != document.paragraphs[pos.paragraph + 1].cell {
            return
        }
        if pos.offset >= para.length, pos.paragraph + 1 < document.paragraphs.count,
           document.paragraphs[pos.paragraph + 1].isImage {
            _setCaret(RichPosition(paragraph: pos.paragraph + 1, offset: 0))
            return
        }
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
        if let block = selection.block {
            // Whole cells: their contents go, the cells stay. Extra
            // paragraphs of a cell are removed, the first emptied.
            let indices = document.paragraphIndices(in: selection)
            var firstOfCell: Set<Int> = []
            var seen: Set<String> = []
            for i in indices {
                let c = document.paragraphs[i].cell!
                let key = "\(c.row),\(c.column)"
                if !seen.contains(key) { seen.insert(key); firstOfCell.insert(i) }
            }
            for i in indices.reversed() {
                if firstOfCell.contains(i) {
                    let para = document.paragraphs[i]
                    if para.isImage {
                        var empty = RichParagraph(style: para.style)
                        empty.cell = para.cell
                        perform(.removeParagraphs(at: i, [para]))
                        perform(.insertParagraphs(at: i, [empty]))
                    } else if para.length > 0 {
                        _deleteRange(in: i, 0 ..< para.length)
                    }
                } else {
                    perform(.removeParagraphs(at: i, [document.paragraphs[i]]))
                }
            }
            let first = document.paragraphs.indices.first { document.paragraphs[$0].cell.map(block.contains) ?? false } ?? 0
            _setCaret(RichPosition(paragraph: first, offset: 0))
            return
        }
        let a = document.clamped(selection.start)
        let b = document.clamped(selection.end)
        guard a != b else { return }
        if a.paragraph == b.paragraph {
            _deleteRange(in: a.paragraph, a.offset ..< b.offset)
        } else if _crossesCellWall(a, b) {
            // A range that leaves a cell (or enters one) clears what it
            // covers and keeps every paragraph: cells never merge into
            // the text around them, and a cell never loses its last one.
            for i in a.paragraph ... b.paragraph {
                let len = document.paragraphs[i].length
                let lo = i == a.paragraph ? a.offset : 0
                let hi = i == b.paragraph ? b.offset : len
                _deleteRange(in: i, lo ..< hi)
            }
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

    /// Whether a range's ends are in different cells, or one in a table
    /// and the other out (or any paragraph between them is).
    private func _crossesCellWall(_ a: RichPosition, _ b: RichPosition) -> Bool {
        let first = document.paragraphs[a.paragraph].cell
        for i in a.paragraph ... b.paragraph {
            let c = document.paragraphs[i].cell
            switch (first, c) {
            case (nil, nil): continue
            case let (f?, c?) where f.sameCell(as: c): continue
            default: return true
            }
        }
        return false
    }

    /// The offsets of paragraph `i` the selection covers: whole for a
    /// block, else clipped at the ends.
    private func _selectedRange(in i: Int) -> Range<Int> {
        let len = document.paragraphs[i].length
        if selection.block != nil { return 0 ..< len }
        let a = document.clamped(selection.start), b = document.clamped(selection.end)
        return (i == a.paragraph ? a.offset : 0) ..< (i == b.paragraph ? b.offset : len)
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
            let block = selection.block != nil
            for i in document.paragraphIndices(in: selection) {
                let lo = !block && i == a.paragraph ? a.offset : 0
                let hi = !block && i == b.paragraph ? b.offset : document.paragraphs[i].length
                var para = document.paragraphs[i]
                let old = para.runs
                para.applyStyle(lo ..< hi, transform)
                if para.runs != old {
                    perform(.setRuns(i, old: old, new: para.runs))
                }
            }
        }
    }

    /// The link under the caret or at the selection's start, if any.
    public var currentLink: String? { currentCharStyle.link }

    /// Word's AutoCorrect for what a keyboard cannot type: straight quotes
    /// become curly, "--" between words an em dash, "..." an ellipsis,
    /// (c) (r) (tm) their symbols. Off for pasted text.
    public var autocorrect = true

    /// Typed text (one character at a time from the keyboard): autocorrect,
    /// then insert. Pasted or programmatic text uses `insertText`.
    public func insertTyped(_ text: String) {
        guard autocorrect, text.utf16.count == 1, !hasSelection else { insertText(text); return }
        let pos = selection.focus
        let para = document.paragraphs[pos.paragraph]
        guard !para.isImage else { insertText(text); return }
        let before = String(para.text.utf16.prefix(pos.offset)) ?? ""
        let prev = before.last
        let opens = prev == nil || prev!.isWhitespace || "([{\u{201C}\u{2018}\n".contains(prev!)
        switch text {
        case "\"": insertText(opens ? "\u{201C}" : "\u{201D}"); return
        case "'": insertText(opens ? "\u{2018}" : "\u{2019}"); return
        case ".":
            if before.hasSuffix("..") { _replaceBefore(2, with: "\u{2026}"); return }
        case ")":
            for (short, symbol) in [("(c", "\u{00A9}"), ("(r", "\u{00AE}"), ("(tm", "\u{2122}")]
            where before.lowercased().hasSuffix(short) {
                _replaceBefore(short.utf16.count, with: symbol); return
            }
        case " ":
            // "word--word " → "word—word ": the dash lands when the word after it ends.
            if let dash = before.range(of: "--", options: .backwards),
               !before[dash.upperBound...].isEmpty, before[dash.upperBound...].allSatisfy({ !$0.isWhitespace }),
               dash.lowerBound > before.startIndex, !before[before.index(before: dash.lowerBound)].isWhitespace {
                let tail = String(before[dash.upperBound...])
                _replaceBefore(tail.utf16.count + 2, with: "\u{2014}" + tail + " ")
                return
            }
        default: break
        }
        insertText(text)
    }

    /// Replace the `units` UTF-16 units before the caret with `replacement`,
    /// as one typing step.
    private func _replaceBefore(_ units: Int, with replacement: String) {
        let pos = selection.focus
        guard pos.offset >= units else { insertText(replacement); return }
        edit(kind: .typing) {
            let style = typingStyle ?? document.paragraphs[pos.paragraph].style(at: pos.offset)
            _deleteRange(in: pos.paragraph, (pos.offset - units) ..< pos.offset)
            perform(.insertText(RichPosition(paragraph: pos.paragraph, offset: pos.offset - units), replacement,
                                [Run(length: replacement.utf16.count, style: style)]))
            _setCaret(RichPosition(paragraph: pos.paragraph, offset: pos.offset - units + replacement.utf16.count))
        }
    }

    /// ⇧⏎: a line break inside the paragraph, not a new paragraph.
    public func insertLineBreak() {
        edit(kind: .typing) {
            if hasSelection { _deleteSelectionOps() }
            let pos = selection.focus
            let para = document.paragraphs[pos.paragraph]
            guard !para.isImage else { return }
            let style = typingStyle ?? para.style(at: pos.offset)
            perform(.insertText(pos, "\n", [Run(length: 1, style: style)]))
            _setCaret(RichPosition(paragraph: pos.paragraph, offset: pos.offset + 1))
        }
    }

    /// Re-lay out everything on the next frame: for a theme change the
    /// document itself does not record (dark mode, formatting marks).
    public func invalidateLayout() {
        _pendingChanges.append(.all)
        notifyListeners()
    }

    /// The text-input plugin's composing range (an IME's uncommitted
    /// text), underlined by the editable; nil when nothing is composing.
    public var composingRange: (paragraph: Int, range: Range<Int>)? = nil {
        didSet { if composingRange?.paragraph != oldValue?.paragraph || composingRange?.range != oldValue?.range { notifyListeners() } }
    }

    /// Replace `range` of paragraph `index` with `text` in the style at
    /// the range's start, as typing does — what an IME's editing-state
    /// update becomes after the diff against the paragraph.
    public func replaceText(in index: Int, _ range: Range<Int>, with text: String) {
        guard index < document.paragraphs.count else { return }
        let para = document.paragraphs[index]
        let lo = max(0, min(range.lowerBound, para.length)), hi = max(lo, min(range.upperBound, para.length))
        edit(kind: .typing) {
            let style = typingStyle ?? para.style(at: lo)
            if hi > lo { _deleteRange(in: index, lo ..< hi) }
            if !text.isEmpty {
                perform(.insertText(RichPosition(paragraph: index, offset: lo), text,
                                    [Run(length: text.utf16.count, style: style)]))
            }
            _setCaret(RichPosition(paragraph: index, offset: lo + text.utf16.count))
        }
    }

    public enum CaseChange { case sentence, lower, upper, capitalizeWords, toggle }

    /// Word's Change Case over the selection, or the word at the caret.
    /// Runs keep their formatting; their lengths follow the new text.
    public func changeCase(_ kind: CaseChange) {
        if selection.isCollapsed {
            let p = selection.focus
            let r = document.paragraphs[p.paragraph].wordRange(at: p.offset)
            guard r.upperBound > r.lowerBound else { return }
            selection = RichSelection(anchor: RichPosition(paragraph: p.paragraph, offset: r.lowerBound),
                                      focus: RichPosition(paragraph: p.paragraph, offset: r.upperBound))
        }
        let start = selection.start, end = selection.end
        let block = selection.block
        edit {
            var sentenceStart = true
            let indices = document.paragraphIndices(in: selection)
            for i in indices {
                let para = document.paragraphs[i]
                let r = _selectedRange(in: i)
                let lo = r.lowerBound, hi = r.upperBound
                guard hi > lo, !para.isImage else { continue }
                let a = String.Index(utf16Offset: lo, in: para.text)
                let b = String.Index(utf16Offset: hi, in: para.text)
                let old = String(para.text[a ..< b])
                var newRuns: [Run] = []
                var newText = ""
                var pos = a
                for run in para.runs(in: lo ..< hi) {
                    let q = para.text.utf16.index(pos, offsetBy: run.length)
                    let piece = String(para.text[pos ..< q])
                    let changed = Self._recase(piece, kind, sentenceStart: &sentenceStart)
                    newText += changed
                    newRuns.append(Run(length: changed.utf16.count, style: run.style))
                    pos = q
                }
                guard newText != old else { continue }
                _deleteRange(in: i, lo ..< hi)
                perform(.insertText(RichPosition(paragraph: i, offset: lo), newText, newRuns))
                if block == nil, i == end.paragraph {
                    selection = RichSelection(anchor: start, focus: RichPosition(paragraph: i, offset: lo + newText.utf16.count))
                } else if let block {
                    selection = RichSelection(anchor: start, focus: end, block: block)
                }
                sentenceStart = true
            }
        }
    }

    private static func _recase(_ s: String, _ kind: CaseChange, sentenceStart: inout Bool) -> String {
        switch kind {
        case .lower: return s.lowercased()
        case .upper: return s.uppercased()
        case .toggle:
            return String(s.map { ch -> String in
                let str = String(ch)
                return str == str.uppercased() ? str.lowercased() : str.uppercased()
            }.joined())
        case .capitalizeWords:
            var out = ""
            var atWordStart = true
            for ch in s {
                if ch.isLetter || ch.isNumber {
                    out += atWordStart ? String(ch).uppercased() : String(ch).lowercased()
                    atWordStart = false
                } else {
                    out.append(ch)
                    atWordStart = ch.isWhitespace || ch == "-" || ch == "/"
                }
            }
            return out
        case .sentence:
            var out = ""
            for ch in s {
                if ch.isLetter {
                    out += sentenceStart ? String(ch).uppercased() : String(ch).lowercased()
                    sentenceStart = false
                } else {
                    out.append(ch)
                    if ch == "." || ch == "!" || ch == "?" { sentenceStart = true }
                }
            }
            return out
        }
    }

    /// Replace one style sheet entry (Modify Style), one undo step.
    /// With `coalescing`, consecutive calls (a Modify Style strip's
    /// controls) join one undo step until the caret moves or
    /// `breakUndoCoalescing` is called, so one dialog is one step as in Word.
    public func setStyleEntry(_ entry: RichNamedStyle, coalescing: Bool = false) {
        guard let old = document.styles[entry.id], old != entry else { return }
        edit(kind: coalescing ? .styleEdit : .other) { perform(.setStyleEntry(old: old, new: entry)) }
    }

    /// Word's "Update <style> to Match Selection": the caret's character
    /// formatting and paragraph props become the sheet's entry, so every
    /// paragraph in that style changes. One undo step.
    public func updateStyleToMatchSelection(_ id: String) {
        guard var entry = document.styles[id] else { return }
        let old = entry
        var char = currentCharStyle
        char.link = nil
        char.highlight = nil
        entry.char = char
        var ps = currentParagraphStyle
        ps.list = nil
        ps.listLevel = 0
        ps.listId = nil
        ps.pageBreakBefore = false
        ps.named = old.paragraph.named
        ps.heading = old.paragraph.heading
        entry.paragraph = ps
        guard entry != old else { return }
        edit { perform(.setStyleEntry(old: old, new: entry)) }
    }

    /// Link the selection to `url`; with nothing selected, insert the URL
    /// as the link's text, as Word does. nil removes the link.
    public func setLink(_ url: String?) {
        if selection.isCollapsed {
            guard let url, !url.isEmpty else {
                // Remove the link from the run the caret is in.
                let pos = selection.focus
                let para = document.paragraphs[pos.paragraph]
                guard para.style(at: pos.offset).link != nil else { return }
                var start = pos.offset, end = pos.offset
                while start > 0, para.style(at: start).link != nil { start -= 1 }
                while end < para.length, para.style(at: end + 1).link != nil { end += 1 }
                edit {
                    let old = para.runs
                    var p = para
                    p.applyStyle(start ..< end) { $0.link = nil }
                    perform(.setRuns(pos.paragraph, old: old, new: p.runs))
                }
                return
            }
            edit {
                let pos = selection.focus
                insertText(url)
                selection = RichSelection(anchor: pos, focus: selection.focus)
                applyCharStyle { $0.link = url }
                selection = RichSelection(caret: selection.focus)
            }
            return
        }
        applyCharStyle { $0.link = (url?.isEmpty ?? true) ? nil : url }
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
            for i in document.paragraphIndices(in: selection) {
                let old = document.paragraphs[i]
                var para = old
                if selection.block == nil, selection.isCollapsed || (a.paragraph == b.paragraph) {
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

    // MARK: Tables

    public var isInCell: Bool { document.paragraphs[selection.focus.paragraph].cell != nil }

    /// Insert an empty rows×columns table at the caret, with a plain
    /// paragraph after it so the caret can leave it.
    public func insertTable(rows: Int, columns: Int) {
        let rows = max(1, rows), columns = max(1, columns)
        edit {
            if hasSelection { _deleteSelectionOps() }
            let pos = selection.focus
            let para = document.paragraphs[pos.paragraph]
            let id = UUID().uuidString
            var cells: [RichParagraph] = []
            for r in 0 ..< rows {
                for c in 0 ..< columns {
                    var p = RichParagraph(style: .cell)
                    p.cell = CellRef(table: id, row: r, column: c)
                    cells.append(p)
                }
            }
            var at = pos.paragraph + 1
            if para.text.isEmpty && !para.isImage && para.cell == nil {
                at = pos.paragraph
                perform(.insertParagraphs(at: at, cells))
            } else if para.cell != nil {
                // A table inside a table is a step too far: put it after.
                let after = _tableEnd(from: pos.paragraph) + 1
                perform(.insertParagraphs(at: after, cells + [RichParagraph()]))
                at = after
            } else {
                if pos.offset < para.length {
                    perform(.splitParagraph(pos, tailStyle: .body))
                } else {
                    perform(.insertParagraphs(at: at, [RichParagraph()]))
                }
                perform(.insertParagraphs(at: at, cells))
            }
            _setCaret(RichPosition(paragraph: at, offset: 0))
        }
    }

    private func _tableEnd(from index: Int) -> Int {
        guard let id = document.paragraphs[index].cell?.table else { return index }
        var i = index
        while i + 1 < document.paragraphs.count, document.paragraphs[i + 1].cell?.table == id { i += 1 }
        return i
    }

    /// Tab / Shift+Tab inside a table: the next or previous cell's first
    /// paragraph; past the last cell, the paragraph after the table.
    public func moveToAdjacentCell(forward: Bool) {
        let pos = selection.focus
        guard let here = document.paragraphs[pos.paragraph].cell else { return }
        let members = document.paragraphs(inTable: here.table)
        // First paragraph of each cell, in order.
        var firsts: [(CellRef, Int)] = []
        for i in members {
            let c = document.paragraphs[i].cell!
            if firsts.last?.0.row != c.row || firsts.last?.0.column != c.column { firsts.append((c, i)) }
        }
        guard let k = firsts.firstIndex(where: { $0.0.row == here.row && $0.0.column == here.column }) else { return }
        let target = forward ? k + 1 : k - 1
        if target < 0 { return }
        if target >= firsts.count {
            // Tab in the last cell adds a row, as Word does.
            insertRow(below: true)
            return
        }
        let i = firsts[target].1
        selection = RichSelection(anchor: RichPosition(paragraph: i, offset: 0),
                                  focus: RichPosition(paragraph: i, offset: document.paragraphs[i].length))
    }

    /// The paragraph range of the table the caret is in, or nil.
    public var currentTableRange: Range<Int>? {
        guard let id = document.paragraphs[selection.focus.paragraph].cell?.table else { return nil }
        let members = document.paragraphs(inTable: id)
        guard let first = members.first, let last = members.last else { return nil }
        return first ..< last + 1
    }

    /// Replace the whole table around the caret with `rewrite`'s result and
    /// put the caret at `caret` (an index into the new run). One undo step;
    /// the table stays one contiguous run of cell paragraphs.
    private func _rewriteTable(caret: (inout [RichParagraph]) -> Int?, rewrite: (inout [RichParagraph]) -> Void) {
        guard let range = currentTableRange else { return }
        edit {
            var paras = Array(document.paragraphs[range])
            let old = paras
            rewrite(&paras)
            let at = caret(&paras)
            perform(.removeParagraphs(at: range.lowerBound, old))
            if !paras.isEmpty { perform(.insertParagraphs(at: range.lowerBound, paras)) }
            if document.paragraphs.isEmpty { perform(.insertParagraphs(at: 0, [RichParagraph()])) }
            let index = min(document.paragraphs.count - 1, range.lowerBound + (at ?? 0))
            _setCaret(RichPosition(paragraph: index, offset: 0))
        }
    }

    /// The cell the caret is in, or nil.
    public var currentCell: CellRef? { document.paragraphs[selection.focus.paragraph].cell }

    /// Set a table's column widths (points), one undo step.
    /// The caret's table's look; nil outside a table.
    public var currentTableStyle: TableStyle? {
        guard let t = currentCell?.table else { return nil }
        return document.tableStyles[t] ?? TableStyle()
    }

    /// Change the caret's table's look (Borders, Header Row), one undo step.
    public func setTableStyle(_ transform: (inout TableStyle) -> Void) {
        guard let t = currentCell?.table else { return }
        let old = document.tableStyles[t]
        var new = old ?? TableStyle()
        transform(&new)
        guard new != (old ?? TableStyle()) else { return }
        edit { perform(.setTableStyle(t, old: old, new: new == TableStyle() ? nil : new)) }
    }

    public func setTableColumnWidths(_ table: String, _ widths: [Double]?) {
        let old = document.tableColumns[table]
        guard old != widths else { return }
        edit { perform(.setTableColumns(table, old: old, new: widths)) }
    }

    /// Equal columns across the content width.
    public func distributeColumns() {
        guard let here = currentCell else { return }
        setTableColumnWidths(here.table, nil)
    }

    /// The cells the selection touches in the caret's row: (column, span)
    /// of each, left to right. One entry when the selection is in one cell.
    public var selectedCellsInRow: [(column: Int, span: Int)] {
        guard let here = currentCell else { return [] }
        var out: [(Int, Int)] = []
        for i in selection.start.paragraph ... selection.end.paragraph {
            guard let c = document.paragraphs[i].cell, c.table == here.table, c.row == here.row else { continue }
            if out.last?.0 != c.column { out.append((c.column, c.span)) }
        }
        return out
    }

    /// The cells the selection touches in the caret's column, top to
    /// bottom: (row, rowSpan) of each.
    public var selectedCellsInColumn: [(row: Int, rowSpan: Int)] {
        guard let here = currentCell else { return [] }
        var out: [(Int, Int)] = []
        for i in selection.start.paragraph ... selection.end.paragraph {
            guard let c = document.paragraphs[i].cell, c.table == here.table, c.column == here.column else { continue }
            if out.last?.0 != c.row { out.append((c.row, c.rowSpan)) }
        }
        return out
    }

    /// Merge the selected cells: a block into its top-left cell, else
    /// across one row into the leftmost, or down one column into the
    /// topmost, keeping every paragraph in order.
    public func mergeCells() {
        guard let here = currentCell else { return }
        if let block = selection.block {
            let top = block.rows.lowerBound, left = block.columns.lowerBound
            var caretAt: Int? = nil
            _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
                var out: [RichParagraph] = []
                var merged: [RichParagraph] = []
                for var p in paras {
                    if var c = p.cell, block.contains(c) {
                        c.row = top; c.column = left
                        c.span = block.columns.count; c.rowSpan = block.rows.count
                        p.cell = c
                        merged.append(p)
                    } else {
                        out.append(p)
                    }
                }
                // The merged cell sits where the top-left cell was: before
                // the first remaining cell that follows it in reading order.
                let at = out.firstIndex { q in
                    guard let c = q.cell else { return false }
                    return c.row > top || (c.row == top && c.column > left)
                } ?? out.count
                caretAt = at
                out.insert(contentsOf: merged, at: at)
                paras = out
            })
            return
        }
        let cells = selectedCellsInRow
        if cells.count <= 1 {
            let column = selectedCellsInColumn
            guard column.count > 1 else { return }
            let first = column[0].row
            let rowSpan = column.map(\.rowSpan).reduce(0, +)
            var caretAt: Int? = nil
            _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
                // Lift the lower cells' paragraphs out, retagged to the top cell.
                var kept: [RichParagraph] = []
                var moved: [RichParagraph] = []
                for var p in paras {
                    if var c = p.cell, c.column == here.column, c.row > first, c.row < first + rowSpan {
                        c.row = first; c.rowSpan = rowSpan; p.cell = c
                        moved.append(p)
                    } else {
                        kept.append(p)
                    }
                }
                // Then put them after the top cell's last paragraph.
                var out: [RichParagraph] = []
                var topEnd: Int? = nil
                for var p in kept {
                    if var c = p.cell, c.row == first, c.column == here.column {
                        c.rowSpan = rowSpan; p.cell = c
                        if caretAt == nil { caretAt = out.count }
                        out.append(p)
                        topEnd = out.count
                    } else {
                        out.append(p)
                    }
                }
                out.insert(contentsOf: moved, at: topEnd ?? out.count)
                paras = out
            })
            return
        }
        let first = cells[0].column
        let span = cells.map(\.span).reduce(0, +)
        var caretAt: Int? = nil
        _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
            for k in paras.indices {
                guard var c = paras[k].cell, c.row == here.row, c.column >= first, c.column < first + span else { continue }
                if caretAt == nil { caretAt = k }
                c.column = first
                c.span = span
                paras[k].cell = c
            }
        })
    }

    /// Split the caret's merged cell back into its grid cells: the first
    /// keeps the content, the others are empty.
    public func splitCell() {
        guard let here = currentCell, here.span > 1 || here.rowSpan > 1 else { return }
        if here.rowSpan > 1 {
            var caretAt: Int? = nil
            _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
                var out: [RichParagraph] = []
                for var p in paras {
                    if var c = p.cell, c.sameCell(as: here) {
                        if caretAt == nil { caretAt = out.count }
                        c.rowSpan = 1
                        p.cell = c
                    }
                    out.append(p)
                }
                // An empty cell in each row the span covered, at the column's
                // place in that row.
                for r in (here.row + 1) ..< (here.row + here.rowSpan) {
                    var e = RichParagraph(style: .cell)
                    e.cell = CellRef(table: here.table, row: r, column: here.column, span: here.span)
                    let at = out.firstIndex { q in
                        guard let c = q.cell else { return false }
                        return c.row > r || (c.row == r && c.column > here.column)
                    } ?? out.count
                    out.insert(e, at: at)
                }
                paras = out
            })
            return
        }
        var caretAt: Int? = nil
        _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
            var out: [RichParagraph] = []
            for (k, var p) in paras.enumerated() {
                if var c = p.cell, c.sameCell(as: here) {
                    if caretAt == nil { caretAt = out.count }
                    c.span = 1
                    p.cell = c
                    out.append(p)
                    // After the merged cell's last paragraph: the empty
                    // cells it split into, whatever follows.
                    let isLast = k + 1 >= paras.count || !(paras[k + 1].cell?.sameCell(as: here) ?? false)
                    if isLast {
                        for s in 1 ..< here.span {
                            var e = RichParagraph(style: .cell)
                            e.cell = CellRef(table: here.table, row: here.row, column: here.column + s, rowSpan: here.rowSpan)
                            out.append(e)
                        }
                    }
                    continue
                }
                out.append(p)
            }
            paras = out
        })
    }

    /// Insert an empty column left or right of the caret's column. The new
    /// column takes half of the current one's width so the table keeps
    /// its width, as Word's "Insert Left/Right" does inside a fixed table.
    public func insertColumn(after: Bool) {
        guard let here = currentCell else { return }
        let at = after ? here.column + 1 : here.column
        let cols = document.columnCount(of: here.table)
        var widths = document.tableColumns[here.table]
        if widths?.count != cols { widths = nil }
        if var w = widths {
            let half = w[here.column] / 2
            w[here.column] = half
            w.insert(half, at: at)
            widths = w
        }
        var caretAt: Int? = nil
        let newWidths = widths
        // One undo step for the cells and the widths (edits nest).
        edit {
        _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
            var out: [RichParagraph] = []
            var lastRow = -1
            func addCell(_ row: Int) {
                var p = RichParagraph(style: .cell)
                p.cell = CellRef(table: here.table, row: row, column: at)
                if row == here.row { caretAt = out.count }
                out.append(p)
            }
            // A straddling cell that also spans rows widens for all of them:
            // the rows below its own get no new cell.
            var covered: Set<Int> = []
            for p in paras {
                if let c = p.cell, c.column < at, c.column + c.span > at, c.rowSpan > 1 {
                    for r in (c.row + 1) ..< (c.row + c.rowSpan) { covered.insert(r) }
                }
            }
            var rowInserted = false
            for var p in paras {
                guard var c = p.cell else { out.append(p); continue }
                if c.row != lastRow {
                    if lastRow >= 0, !rowInserted { addCell(lastRow) }
                    lastRow = c.row
                    rowInserted = covered.contains(c.row)
                }
                if c.column < at, c.column + c.span > at {
                    // A merged cell across the insertion point widens instead.
                    c.span += 1; p.cell = c; rowInserted = true
                    out.append(p)
                    continue
                }
                if !rowInserted, c.column >= at { addCell(c.row); rowInserted = true }
                if c.column >= at { c.column += 1; p.cell = c }
                out.append(p)
            }
            if lastRow >= 0, !rowInserted { addCell(lastRow) }
            paras = out
        })
        if let w = newWidths, w != document.tableColumns[here.table] {
            perform(.setTableColumns(here.table, old: document.tableColumns[here.table], new: w))
        }
        }
    }

    /// Remove the caret's column; the last column removes the table.
    public func deleteColumn() {
        guard let here = currentCell else { return }
        let cols = document.columnCount(of: here.table)
        if cols <= 1 { deleteTable(); return }
        var widths = document.tableColumns[here.table]
        if widths?.count == cols {
            // The neighbour takes the removed width, so the table keeps its width.
            let removed = widths![here.column]
            widths!.remove(at: here.column)
            let neighbour = min(here.column, widths!.count - 1)
            widths![neighbour] += removed
        } else {
            widths = nil
        }
        var caretAt: Int? = nil
        let newWidths = widths
        edit {
        _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
            var out: [RichParagraph] = []
            for var p in paras {
                guard var c = p.cell else { out.append(p); continue }
                if c.column <= here.column, c.column + c.span > here.column, c.span > 1 {
                    // A merged cell covering the column narrows by one.
                    c.span -= 1
                    if c.column > here.column { c.column -= 1 }
                    p.cell = c
                    if c.row == here.row, caretAt == nil { caretAt = out.count }
                    out.append(p)
                    continue
                }
                if c.column == here.column {
                    if c.row == here.row, caretAt == nil { caretAt = out.count }
                    continue
                }
                if c.column > here.column { c.column -= 1; p.cell = c }
                out.append(p)
            }
            caretAt = min(caretAt ?? 0, max(0, out.count - 1))
            paras = out
        })
        if newWidths != document.tableColumns[here.table] {
            perform(.setTableColumns(here.table, old: document.tableColumns[here.table], new: newWidths))
        }
        }
    }

    /// Remove the table the caret is in; the caret lands where it was.
    public func deleteTable() {
        _rewriteTable(caret: { _ in 0 }, rewrite: { $0.removeAll() })
    }

    /// Insert an empty row above or below the caret's row.
    public func insertRow(below: Bool) {
        guard let here = document.paragraphs[selection.focus.paragraph].cell else { return }
        let columns = document.columnCount(of: here.table)
        let newRow = below ? here.row + 1 : here.row
        var caretAt: Int? = nil
        _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
            var out: [RichParagraph] = []
            var inserted = false
            func addRow() {
                caretAt = out.count
                for c in 0 ..< columns {
                    var p = RichParagraph(style: .cell)
                    p.cell = CellRef(table: here.table, row: newRow, column: c)
                    out.append(p)
                }
                inserted = true
            }
            for var p in paras {
                guard var c = p.cell else { out.append(p); continue }
                if !inserted && c.row >= newRow { addRow() }
                if c.row >= newRow { c.row += 1; p.cell = c }
                else if c.row + c.rowSpan > newRow { c.rowSpan += 1; p.cell = c }   // a span across the new row grows
                out.append(p)
            }
            if !inserted { addRow() }
            // The new row needs no cell where a span from above covers it.
            let spans = out.compactMap(\.cell).filter { $0.row < newRow && $0.rowSpan > 1 }
            paras = out.filter { p in
                guard let c = p.cell, c.row == newRow, p.text.isEmpty else { return true }
                return !spans.contains { $0.covers(row: newRow, column: c.column) }
            }
        })
    }

    /// Remove the caret's row; the last row removes the table.
    public func deleteRow() {
        guard let here = document.paragraphs[selection.focus.paragraph].cell else { return }
        var caretAt: Int? = nil
        _rewriteTable(caret: { _ in caretAt }, rewrite: { paras in
            var out: [RichParagraph] = []
            for var p in paras {
                guard var c = p.cell else { out.append(p); continue }
                if c.row == here.row {
                    if c.rowSpan > 1 {
                        // A span starting here keeps its content, one row shorter.
                        c.rowSpan -= 1
                        p.cell = c
                        if caretAt == nil { caretAt = out.count }
                        out.append(p)
                    } else if caretAt == nil {
                        caretAt = out.count
                    }
                    continue
                }
                if c.row < here.row, c.row + c.rowSpan > here.row { c.rowSpan -= 1; p.cell = c }
                if c.row > here.row { c.row -= 1; p.cell = c }
                out.append(p)
            }
            // The row that moved up, or the last one when the caret's was last.
            caretAt = min(caretAt ?? 0, max(0, out.count - 1))
            paras = out
        })
    }

    // MARK: Header and footer

    public func setHeaderFooter(header: String? = nil, footer: String? = nil) {
        let newHeader = header ?? document.header
        let newFooter = footer ?? document.footer
        guard newHeader != document.header || newFooter != document.footer else { return }
        edit {
            perform(.setHeaderFooter(header: newHeader, footer: newFooter,
                                     oldHeader: document.header, oldFooter: document.footer))
        }
    }

    /// Word's Page Number: a centred "n" in the footer, or none.
    public func togglePageNumbers() {
        let field = "Page \(RichDocument.pageField) of \(RichDocument.pageCountField)"
        setHeaderFooter(footer: document.footer.containsSubstring(RichDocument.pageField) ? "" : field)
    }

    // MARK: Find

    /// The next occurrence of `query` after `from` (wrapping), or nil.
    public func find(_ query: String, from: RichPosition? = nil, backwards: Bool = false,
                     caseSensitive: Bool = false) -> RichSelection? {
        guard !query.isEmpty else { return nil }
        let start = document.clamped(from ?? (backwards ? selection.start : selection.end))
        let n = document.paragraphs.count
                func search(_ i: Int, lo: Int?, hi: Int?) -> RichSelection? {
            let text = document.paragraphs[i].text
            let a = lo.map { String.Index(utf16Offset: $0, in: text) } ?? text.startIndex
            let b = hi.map { String.Index(utf16Offset: $0, in: text) } ?? text.endIndex
            guard a <= b else { return nil }
            guard let r = text.findRange(of: query, caseSensitive: caseSensitive,
                                         backwards: backwards, in: a ..< b) else { return nil }
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
                // Backwards so earlier offsets stay valid.
                var searchEnd = text.endIndex
                while let r = text.findRange(of: query, caseSensitive: caseSensitive, backwards: true,
                                             in: text.startIndex ..< searchEnd) {
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
            for i in document.paragraphIndices(in: selection) {
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
        if let level, document.styles[RichNamedStyle.headingId(level)] == nil {
            applyParagraphStyle { $0.heading = level; $0.named = nil }
        } else {
            setNamedStyle(level.map(RichNamedStyle.headingId) ?? RichNamedStyle.normalId)
        }
    }

    /// Apply a style from the document's sheet to the selected paragraphs.
    public func setNamedStyle(_ id: String) {
        let sheet = document.styles
        applyParagraphStyle { sheet.apply(id, to: &$0) }
    }

    /// The sheet id of the caret paragraph's style ("Normal" for body text).
    public var currentNamedStyleId: String { document.styles.id(of: currentParagraphStyle) }

    public func toggleList(_ kind: ListKind) {
        let allOn = document.paragraphIndices(in: selection).allSatisfy { document.paragraphs[$0].style.list == kind }
        applyParagraphStyle { $0.list = allOn ? nil : kind }
    }

    /// The Numbering or Bullets library: make the selected paragraphs a
    /// list of the format's kind and give their level that format. Items
    /// with no list id first get one, together with the run of anonymous
    /// items they number with, so the whole list changes as in Word.
    public func setListFormat(_ format: ListLevelFormat) {
        let kind: ListKind = format.format == .bullet ? .bullet : .numbered
        edit {
            let indices = document.paragraphIndices(in: selection)
            // Items already of this kind take their anonymous run along
            // (that run is one list); items changing kind leave their old
            // list and become one new list of their own.
            for i in indices where document.paragraphs[i].style.list == kind && document.paragraphs[i].style.listId == nil {
                _assignListId(around: i)
            }
            let converted = indices.filter { document.paragraphs[$0].style.list != kind }
            let freshId = converted.isEmpty ? nil : _freshListId()
            for i in converted {
                let old = document.paragraphs[i].style
                var new = old
                new.list = kind
                new.listId = freshId
                perform(.setParagraphStyle(i, old: old, new: new))
            }
            var targets: [(String, Int)] = []
            for i in indices {
                let st = document.paragraphs[i].style
                let t = (st.listId!, st.listLevel)
                if !targets.contains(where: { $0 == t }) { targets.append(t) }
            }
            for (id, level) in targets {
                let old = document.listFormats[id]?[level]
                let new = format.forLevel(level)
                if old != new { perform(.setListFormat(id, level: level, old: old, new: new)) }
            }
        }
    }

    /// The format the caret's list level shows, for the ribbon's check
    /// marks: nil outside a list.
    public var currentListFormat: ListLevelFormat? {
        let st = document.paragraphs[selection.focus.paragraph].style
        guard let kind = st.list else { return nil }
        if let id = st.listId, let f = document.listFormats[id]?[st.listLevel], (f.format == .bullet) == (kind == .bullet) {
            return f
        }
        return kind == .bullet ? ListLevelFormat(text: ListLevelFormat.defaultBullet(st.listLevel), format: .bullet)
                               : .plain(st.listLevel)
    }

    /// Give paragraph `i`'s anonymous list run — the adjacent items of the
    /// same kind with no id — a fresh id.
    private func _freshListId() -> String {
        let used = Set(document.paragraphs.compactMap(\.style.listId)).union(document.listFormats.keys)
        var n = 1
        while used.contains("list\(n)") { n += 1 }
        return "list\(n)"
    }

    private func _assignListId(around i: Int) {
        guard let kind = document.paragraphs[i].style.list else { return }
        func anonymous(_ k: Int) -> Bool {
            let s = document.paragraphs[k].style
            return s.list == kind && s.listId == nil
        }
        var lo = i, hi = i
        while lo > 0, anonymous(lo - 1) { lo -= 1 }
        while hi + 1 < document.paragraphs.count, anonymous(hi + 1) { hi += 1 }
        let id = _freshListId()
        for k in lo ... hi {
            let old = document.paragraphs[k].style
            var new = old
            new.listId = id
            perform(.setParagraphStyle(k, old: old, new: new))
        }
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

    /// Where the editable scrolls the caret on the next change: into view
    /// (the default, and what every edit wants) or to the top of the
    /// viewport (a navigation pane jump). Consumed by the editable.
    public enum RevealPlacement { case visible, top }
    public var pendingReveal: RevealPlacement = .visible

    /// Move the caret and ask the editable to place it.
    public func moveTo(_ p: RichPosition, reveal: RevealPlacement) {
        pendingReveal = reveal
        moveTo(p, extend: false)
    }

    public func moveTo(_ p: RichPosition, extend: Bool) {
        let p = document.clamped(p)
        guard extend else { selection = RichSelection(caret: p); return }
        // Extending from one cell into another of the same table selects
        // whole cells, as in Word.
        selection = RichSelection(anchor: selection.anchor, focus: p,
                                  block: document.cellBlock(from: selection.anchor, to: p))
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

    /// ⌥↑ on the Mac: the paragraph's start, or the previous paragraph's
    /// when already there.
    public func moveToParagraphStart(extend: Bool) {
        let pos = selection.focus
        if pos.offset > 0 {
            moveTo(RichPosition(paragraph: pos.paragraph, offset: 0), extend: extend)
        } else if pos.paragraph > 0 {
            moveTo(RichPosition(paragraph: pos.paragraph - 1, offset: 0), extend: extend)
        }
    }

    /// ⌥↓: the paragraph's end, or the next paragraph's when already there.
    public func moveToParagraphEnd(extend: Bool) {
        let pos = selection.focus
        let len = document.paragraphs[pos.paragraph].length
        if pos.offset < len {
            moveTo(RichPosition(paragraph: pos.paragraph, offset: len), extend: extend)
        } else if pos.paragraph + 1 < document.paragraphs.count {
            let next = pos.paragraph + 1
            moveTo(RichPosition(paragraph: next, offset: document.paragraphs[next].length), extend: extend)
        }
    }

    /// ⌘⌫: delete from `offset` (a line start the layout found) to the
    /// caret, within the caret's paragraph.
    public func deleteBackward(toOffset offset: Int) {
        let pos = selection.focus
        guard !hasSelection, offset < pos.offset else { deleteBackward(); return }
        edit(kind: .deleting) {
            _deleteRange(in: pos.paragraph, offset ..< pos.offset)
            _setCaret(RichPosition(paragraph: pos.paragraph, offset: offset))
        }
    }

    public func moveToDocumentStart(extend: Bool) { moveTo(.start, extend: extend) }
    public func moveToDocumentEnd(extend: Bool) { moveTo(document.endPosition, extend: extend) }

    /// ⌘-click: the sentence at `p`.
    public func selectSentence(at p: RichPosition) {
        let p = document.clamped(p)
        let r = document.paragraphs[p.paragraph].sentenceRange(at: p.offset)
        selection = RichSelection(anchor: RichPosition(paragraph: p.paragraph, offset: r.lowerBound),
                                  focus: RichPosition(paragraph: p.paragraph, offset: r.upperBound))
    }

    public func selectWord(at p: RichPosition) {
        let p = document.clamped(p)
        let r = document.paragraphs[p.paragraph].wordRange(at: p.offset)
        selection = RichSelection(anchor: RichPosition(paragraph: p.paragraph, offset: r.lowerBound),
                                  focus: RichPosition(paragraph: p.paragraph, offset: r.upperBound))
    }

    /// The word or paragraph at `p`, as a selection (what a double or
    /// triple click takes).
    public func unitSpan(at p: RichPosition, paragraph whole: Bool) -> RichSelection {
        let p = document.clamped(p)
        let r = whole ? 0 ..< document.paragraphs[p.paragraph].length
                      : document.paragraphs[p.paragraph].wordRange(at: p.offset)
        return RichSelection(anchor: RichPosition(paragraph: p.paragraph, offset: r.lowerBound),
                             focus: RichPosition(paragraph: p.paragraph, offset: r.upperBound))
    }

    /// A drag that began with a double or triple click grows by whole
    /// words or paragraphs: the selection spans from the unit first
    /// clicked (`origin`) to the unit under the pointer, either way round.
    public func extendSelection(to p: RichPosition, byParagraph: Bool, from origin: RichSelection) {
        let unit = unitSpan(at: p, paragraph: byParagraph)
        var sel = unit.start < origin.start
            ? RichSelection(anchor: origin.end, focus: unit.start)
            : RichSelection(anchor: origin.start, focus: unit.end)
        sel.block = document.cellBlock(from: sel.anchor, to: sel.focus)
        selection = sel
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

    // MARK: Rich clipboard

    /// Installed by the app that knows the formats: turns a copied fragment
    /// into the flavours other apps read, and what other apps put on the
    /// clipboard back into paragraphs. Nil means plain text only.
    public var clipboardCodec: RichClipboardCodec? = nil

    /// The widest a pasted picture is shown, in points (the app sets the
    /// page's content width).
    public var maxPastedImageWidth: Double = 468

    /// The selection as clipboard data with every flavour the codec makes,
    /// plus the picture itself when the selection is exactly one.
    public func copySelectionData() -> ClipboardData? {
        guard hasSelection else { return nil }
        let fragment = document.fragment(selection)
        copiedFragment = fragment
        let text = fragment.map(\.text).joined(separator: "\n")
        var data = ClipboardData(text: text)
        if let codec = clipboardCodec {
            data = codec.encode(fragment, styles: document.styles, text: text)
        }
        if fragment.count == 1, let image = fragment[0].image, image.isPNG {
            data = ClipboardData(text: data.text, rtf: data.rtf, html: data.html, png: image.data)
        }
        return data
    }

    public func cutSelectionData() -> ClipboardData? {
        guard let data = copySelectionData() else { return nil }
        guard hasSelection else { return data }
        edit {
            _deleteSelectionOps()
            _tidySpacesAtCaret()
        }
        return data
    }

    /// Paste clipboard data: our own last copy as the fragment, else the
    /// richest flavour the codec reads, else a picture, else the text.
    public func paste(data: ClipboardData) {
        if let text = data.text, let fragment = copiedFragment,
           fragment.map(\.text).joined(separator: "\n") == text {
            insertFragment(fragment, smart: true)
            return
        }
        if let codec = clipboardCodec, let fragment = codec.decode(data), !fragment.isEmpty {
            insertFragment(fragment, smart: true)
            return
        }
        if let png = data.png, let px = ImageAttachment.pngPixelSize(png) {
            // Pixels at 96/in, capped to the content width, as Insert → Pictures does.
            let nw = Double(px.width) * 0.75, nh = Double(px.height) * 0.75
            var w = nw, h = nh
            if w > maxPastedImageWidth { h *= maxPastedImageWidth / w; w = maxPastedImageWidth }
            insertImage(ImageAttachment(data: png, width: w, height: h, name: "pasted.png",
                                        naturalWidth: nw, naturalHeight: nh))
            return
        }
        if let text = data.text, !text.isEmpty {
            // Plain text takes the style at the caret, padded like a fragment.
            edit {
                if hasSelection { _deleteSelectionOps() }
                var padded = text
                if !text.contains("\n") {
                    let pad = _smartPad(text, at: selection.focus)
                    padded = (pad.before ? " " : "") + text + (pad.after ? " " : "")
                }
                insertText(padded)
            }
        }
    }
}

/// See `RichDocumentController.clipboardCodec`.
public protocol RichClipboardCodec {
    /// Every flavour for `fragment`; `text` is its plain text, already made.
    func encode(_ fragment: [RichParagraph], styles: RichStyleSheet, text: String) -> ClipboardData
    /// Paragraphs from the richest flavour present, or nil for none.
    func decode(_ data: ClipboardData) -> [RichParagraph]?
}
